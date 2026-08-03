# Cookie Authentication Pattern for Blazor Server

The cookie authentication pattern is required for all authentication operations (login, register, logout) in Blazor Server when using Interactive Server Mode.

## Contents
- The Problem
- The Pattern
- Why This Works
- DisableAntiforgery Requirement
- Pattern Applies to All Cookie Operations
- Alternative: Per-Page Render Modes
- Common Mistakes
- Troubleshooting
- Summary

## The Problem

> **CRITICAL:** When using `<Routes @rendermode="InteractiveServer" />` (global interactive server mode), `HttpContext` is **NULL** during WebSocket circuits. This means cookie-based authentication operations — login, register, logout — **cannot** be performed via Blazor component event handlers (e.g., `@onclick`). They will silently fail: no exception is thrown, but no cookie is set.

### Why This Happens

After the initial HTTP request, Blazor Server communicates over a WebSocket (SignalR circuit). There is no HTTP response to attach a `Set-Cookie` header to. `SignInAsync()` called inside a component event handler has no `HttpContext.Response` to write the cookie.

### The Solution

Use standard HTML `<form method="post">` elements that submit to **minimal API endpoints** via full HTTP POST requests. The endpoint performs the auth operation over a real HTTP connection and redirects back to a Blazor page.

---

## The Pattern

### 1. Blazor Component: HTML Form (Not Blazor Event)

```razor
@page "/Account/Login"

<h2>Log in</h2>
@if (!string.IsNullOrEmpty(errorMessage))
{
    <div class="text-danger">@errorMessage</div>
}

<form method="post" action="/Account/LoginHandler">
    <div>
        <label>Email</label>
        <input type="email" name="email" required />
    </div>
    <div>
        <label>Password</label>
        <input type="password" name="password" required />
    </div>
    <button type="submit">Log in</button>
</form>

@code {
    [SupplyParameterFromQuery] public string? Error { get; set; }
    private string? errorMessage;

    protected override void OnInitialized()
    {
        errorMessage = Error;
    }
}
```

**Key points:**
- `<form method="post">` — standard HTML form, NOT `<EditForm>` or `@onclick`
- `action="/Account/LoginHandler"` — posts to a minimal API endpoint
- Named `<input>` elements — form data is read by name in the endpoint
- Error handling via query string redirect

---

### 2. Program.cs: Minimal API Endpoint

```csharp
// Program.cs — add after app.Build() but before app.Run()

app.MapPost("/Account/LoginHandler", async (HttpContext context, SignInManager<IdentityUser> signInManager) =>
{
    var form = await context.Request.ReadFormAsync();
    var email = form["email"].ToString();
    var password = form["password"].ToString();

    var result = await signInManager.PasswordSignInAsync(email, password, isPersistent: false, lockoutOnFailure: false);

    if (result.Succeeded)
        return Results.Redirect("/");

    return Results.Redirect("/Account/Login?error=Invalid+login+attempt");
}).DisableAntiforgery();
```

**Key points:**
- Real `HttpContext` with real HTTP request/response
- `SignInAsync()` can write cookie to `HttpContext.Response`
- Redirects back to Blazor pages (success → home, failure → login with error)
- `.DisableAntiforgery()` is **required** (explained below)

---

## Why This Works

| Blazor Event Handler | Minimal API Endpoint |
|---------------------|----------------------|
| Runs over WebSocket | Runs over HTTP POST |
| No `HttpContext.Response` | Real `HttpContext.Response` |
| Cannot write cookies | Can write `Set-Cookie` header |
| Stays on same circuit | Creates new HTTP transaction |

**The form submission creates a full HTTP POST request**, not a WebSocket message. This gives the endpoint a real HTTP response object where it can set the authentication cookie.

---

## DisableAntiforgery Requirement

> **Important:** Every endpoint that receives form submissions from Blazor-rendered pages **MUST** call `.DisableAntiforgery()` because Blazor's HTML rendering does not include antiforgery tokens.

```csharp
// ✅ CORRECT — DisableAntiforgery() required for Blazor form submissions
app.MapPost("/Account/LoginHandler", handler).DisableAntiforgery();

// ❌ WRONG — will reject POST from Blazor-rendered forms with 400 Bad Request
app.MapPost("/Account/LoginHandler", handler);
```

**Why:** ASP.NET Core minimal APIs require antiforgery tokens by default for POST requests. Blazor's Razor component rendering does not generate these tokens automatically (unlike Razor Pages). Without `.DisableAntiforgery()`, the endpoint rejects all form submissions.

**If you need antiforgery protection**, you must manually include the token:

```razor
@inject Microsoft.AspNetCore.Antiforgery.IAntiforgery Antiforgery

<form method="post" action="/Account/LoginHandler">
    @{
        var tokens = Antiforgery.GetAndStoreTokens(HttpContext);
    }
    <input type="hidden" name="@tokens.FormFieldName" value="@tokens.RequestToken" />
    <!-- rest of form -->
</form>
```

For most migration scenarios, `.DisableAntiforgery()` is the pragmatic choice.

---

## Pattern Applies to All Cookie Operations

This pattern is **NOT optional** and applies to **ALL** cookie-writing authentication operations:

| Operation | Web Forms Pattern | Blazor Server Pattern |
|-----------|------------------|----------------------|
| **Login** | Code-behind `FormsAuthentication.SetAuthCookie()` | `<form>` → minimal API endpoint |
| **Register** | Code-behind `SignInManager.SignInAsync()` | `<form>` → minimal API endpoint |
| **Logout** | Code-behind `FormsAuthentication.SignOut()` | `<form>` → minimal API endpoint |
| **External auth callback** | OWIN middleware callback | Minimal API endpoint |
| **Password reset with auto-login** | Code-behind | `<form>` → minimal API endpoint |

**Any operation that calls:**
- `SignInManager.SignInAsync()`
- `SignInManager.PasswordSignInAsync()`
- `SignInManager.SignOutAsync()`
- `HttpContext.SignInAsync()`
- `HttpContext.SignOutAsync()`

**Must use this pattern in Blazor Server Interactive Mode.**

---

## Alternative: Per-Page Render Modes

If you want to avoid this pattern, you can use **per-page render modes** and set authentication pages to static SSR (no interactivity):

```razor
@page "/Account/Login"
@rendermode @(new InteractiveServerRenderMode(prerender: false))
@* OR: Remove @rendermode entirely to use static SSR *@
```

With static SSR, the page has a real HTTP request/response cycle, and `@onclick` handlers can call `SignInAsync()` directly. However, this means:
- The page is not interactive (no real-time updates, no WebSocket)
- You lose Blazor component model benefits on that page

For most migrations, the `<form>` → minimal API pattern is preferred because it preserves full Blazor interactivity everywhere except the actual auth operation.

---

## Common Mistakes

### ❌ Using @onclick with SignInManager

```razor
@* WRONG — this will silently fail in Interactive Server Mode *@
<button @onclick="Login">Log in</button>

@code {
    [Inject] private SignInManager<IdentityUser> SignInManager { get; set; }

    private async Task Login()
    {
        // THIS WILL NOT WORK — no HttpContext.Response during WebSocket
        await SignInManager.PasswordSignInAsync(email, password, false, false);
    }
}
```

**Why it fails:** `SignInManager.PasswordSignInAsync()` tries to write a cookie to `HttpContext.Response`, but during a WebSocket circuit, `HttpContext` is NULL or the response is already sent.

### ❌ Using EditForm with SignInManager

```razor
@* WRONG — EditForm is a Blazor component that uses @onclick internally *@
<EditForm Model="model" OnValidSubmit="HandleLogin">
    <InputText @bind-Value="model.Email" />
    <InputText @bind-Value="model.Password" type="password" />
    <button type="submit">Log in</button>
</EditForm>

@code {
    private async Task HandleLogin()
    {
        // Same problem — OnValidSubmit runs over WebSocket
        await SignInManager.PasswordSignInAsync(...);
    }
}
```

### ✅ Correct: HTML Form with minimal API endpoint

```razor
@* CORRECT — standard HTML form posts over HTTP *@
<form method="post" action="/Account/LoginHandler">
    <input type="email" name="email" required />
    <input type="password" name="password" required />
    <button type="submit">Log in</button>
</form>
```

---

## Troubleshooting

### "Cookie is not being set"

**Symptom:** Login appears to succeed (no error) but user is not authenticated after redirect.

**Cause:** The auth operation is running over WebSocket, not HTTP.

**Solution:** Verify you're using `<form method="post">` (not `<EditForm>` or `@onclick`) and the endpoint calls `.DisableAntiforgery()`.

### "400 Bad Request" on form submission

**Symptom:** Form submission immediately returns 400 error.

**Cause:** Endpoint is missing `.DisableAntiforgery()`.

**Solution:** Add `.DisableAntiforgery()` to the endpoint:
```csharp
app.MapPost("/Account/LoginHandler", handler).DisableAntiforgery();
```

### "User is authenticated but circuit doesn't reflect it"

**Symptom:** After login redirect, `AuthenticationStateProvider` still shows unauthenticated until page refresh.

**Cause:** The redirect creates a new HTTP request, which establishes a new circuit with the updated auth cookie.

**Solution:** This is normal behavior. The redirect already forces a new circuit with updated auth state. If you need to stay on the same circuit, use a different pattern (e.g., JavaScript-based token auth instead of cookies).

---

## Summary

**The cookie auth pattern is mandatory for Blazor Server Interactive Mode:**
1. Use `<form method="post" action="/endpoint">` (not Blazor events)
2. Create minimal API endpoints that have real `HttpContext`
3. Endpoints perform auth operations and redirect back to Blazor pages
4. Always call `.DisableAntiforgery()` on endpoints

**This pattern preserves Blazor interactivity everywhere while ensuring authentication operations work correctly.**
