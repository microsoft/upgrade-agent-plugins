---
name: managing-blazor-server-authentication
description: >
  Manages authentication in Blazor Server applications with ASP.NET Core Identity. Solves critical
  Blazor Server auth issues: HttpContext NULL errors during WebSocket circuits, cookie auth
  operations failing silently in component handlers, login/logout not working in interactive mode,
  SignInManager returning null, cascading auth state parameter errors. Configures cascading
  authentication state and minimal API endpoints for login/logout/register (required for
  Interactive Server Mode). Covers Blazor auth UI (AuthorizeView, HTML form login,
  LoginName via @context.User.Identity?.Name). Also covers OWIN to ASP.NET Core middleware
  migration. Use when setting up authentication in Blazor Server, troubleshooting auth issues,
  encountering build errors for System.Web.Security types, or fixing runtime authentication
  failures in Blazor Server circuits.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore

---

# Managing Authentication in Blazor Server

Manages authentication in Blazor Server applications with ASP.NET Core Identity. Covers critical Blazor Server auth patterns required for Interactive Server Mode (cookie auth via HTTP endpoints, cascading state) and Blazor auth UI patterns for WebForms migration.

## Related Skills

**Reference guide for complementary patterns.** The workflow steps below contain explicit instructions on when to invoke each skill.

| Skill | Use For |
|-------|---------|
| **migrating-webforms-to-blazor-server** | Initial WebForms to Blazor migration (project setup, Routes, markup conversion) → Prerequisites |
| **migrating-aspnet-identity** | Core Identity migration (IdentityDbContext, middleware, OWIN cleanup) → Step 1 |
| **migrating-owin-cookie-auth** | OWIN cookie authentication without Identity (alternative path) → See OWIN reference section |
| **managing-blazor-server-data-access** | Data access and state management patterns in Blazor Server → Related |
| **migrating-mvc-configuration** | Web.config to appsettings.json migration → Related |

---

## Workflow

Configure Blazor Server authentication in order:

```
Configuration Progress:
- [ ] Step 1: Configure core Identity infrastructure
- [ ] Step 2: Implement cookie auth pattern for Interactive Server Mode
- [ ] Step 3  Implement Blazor auth UI
- [ ] Step 4: Set up authorization patterns
```

---

## Step 1: Migrate Core Identity Infrastructure

**Execute the `migrating-aspnet-identity` skill** to migrate core ASP.NET Identity infrastructure. Complete all steps in that skill, then return here for Blazor Server-specific authentication patterns. That skill handles:
- Installing required Identity packages (`Microsoft.AspNetCore.Identity.EntityFrameworkCore`, etc.)
- Converting `IdentityDbContext` (constructor changes, namespace updates)
- Registering DbContext and Identity services in `Program.cs`
- Adding authentication/authorization middleware (`UseAuthentication()`, `UseAuthorization()`)
- Updating `UserManager` and `SignInManager` usage
- Cleaning up OWIN code

The process is identical whether migrating from ASP.NET MVC or Web Forms Identity.

**After completing the Identity migration skill, add this Blazor Server-specific configuration:**
```csharp
builder.Services.AddCascadingAuthenticationState();
```

---

## Step 2: Implement Cookie Auth Pattern for Blazor Server Interactive Mode

> **CRITICAL:** When using `<Routes @rendermode="InteractiveServer" />`, `HttpContext` is **NULL** during WebSocket circuits. Cookie-based authentication operations (login, register, logout) **cannot** be performed via Blazor component event handlers. They will silently fail.

**Required pattern:** Use standard HTML `<form method="post">` elements that submit to **minimal API endpoints** via full HTTP POST requests. The endpoint performs the auth operation over a real HTTP connection and redirects back to a Blazor page.

**For complete explanation of why this is necessary, troubleshooting common issues, and alternative approaches**, read **[references/cookie-auth-pattern.md](references/cookie-auth-pattern.md)**.

**For ready-to-use endpoint code (login, register, logout, password reset, external providers)**, read **[references/endpoint-templates.md](references/endpoint-templates.md)**.

**Quick example:**

```razor
@* Login.razor *@
<form method="post" action="/Account/LoginHandler">
    <input type="email" name="email" required />
    <input type="password" name="password" required />
    <button type="submit">Log in</button>
</form>
```

```csharp
// Program.cs
app.MapPost("/Account/LoginHandler", async (HttpContext context, SignInManager<IdentityUser> signInManager) =>
{
    var form = await context.Request.ReadFormAsync();
    var result = await signInManager.PasswordSignInAsync(form["email"].ToString(), form["password"].ToString(), false, false);
    return result.Succeeded ? Results.Redirect("/") : Results.Redirect("/Account/Login?error=Invalid+login+attempt");
}).DisableAntiforgery();
```

---

## Step 3: Implement Blazor Auth UI

Use this step when migrating Web Forms auth controls (`asp:Login`, `asp:LoginView`, `asp:LoginStatus`, `asp:LoginName`) to Blazor UI.

If the application already has working auth UI, or uses scaffolded Identity Razor Pages under `/Areas/Identity/`, skip this step.

The cookie auth pattern from Step 2 handles the actual auth operations; this step covers the display layer.

### AuthorizeView for Conditional Content

```razor
@* Show different content for authenticated vs anonymous users *@
<AuthorizeView>
    <NotAuthorized>
        <a href="/Account/Login">Log in</a>
        <a href="/Account/Register">Register</a>
    </NotAuthorized>
    <Authorized>
        Welcome, @context.User.Identity?.Name!
        <form method="post" action="/Account/Logout" class="d-inline">
            <button type="submit" class="btn btn-link">Log out</button>
        </form>
    </Authorized>
</AuthorizeView>
```

### Login Form

Use a standard HTML `<form method="post">` that submits to a minimal API endpoint (see Step 2):

```razor
@page "/Account/Login"

<h2>Log in</h2>

@if (!string.IsNullOrEmpty(errorMessage))
{
    <div class="alert alert-danger">@errorMessage</div>
}

<form method="post" action="/Account/LoginHandler">
    <div class="mb-3">
        <label for="email">Email</label>
        <input type="email" id="email" name="email" required class="form-control" />
    </div>
    <div class="mb-3">
        <label for="password">Password</label>
        <input type="password" id="password" name="password" required class="form-control" />
    </div>
    <button type="submit" class="btn btn-primary">Log in</button>
    <a href="/Account/Register">Register as new user</a>
</form>

@code {
    [SupplyParameterFromQuery] public string? Error { get; set; }
    private string? errorMessage;

    protected override void OnInitialized() => errorMessage = Error;
}
```

### Registration Form

```razor
@page "/Account/Register"

<h2>Create a new account</h2>

@if (!string.IsNullOrEmpty(errorMessage))
{
    <div class="alert alert-danger">@errorMessage</div>
}

<form method="post" action="/Account/RegisterHandler">
    <div class="mb-3">
        <label for="email">Email</label>
        <input type="email" id="email" name="email" required class="form-control" />
    </div>
    <div class="mb-3">
        <label for="password">Password</label>
        <input type="password" id="password" name="password" required class="form-control" />
    </div>
    <div class="mb-3">
        <label for="confirmPassword">Confirm Password</label>
        <input type="password" id="confirmPassword" name="confirmPassword" required class="form-control" />
    </div>
    <button type="submit" class="btn btn-primary">Register</button>
</form>

@code {
    [SupplyParameterFromQuery] public string? Error { get; set; }
    private string? errorMessage;

    protected override void OnInitialized() => errorMessage = Error;
}
```

### Change Password Form

```razor
@page "/Account/ChangePassword"
@attribute [Authorize]

<h2>Change Password</h2>

@if (!string.IsNullOrEmpty(errorMessage))
{
    <div class="alert alert-danger">@errorMessage</div>
}
@if (!string.IsNullOrEmpty(successMessage))
{
    <div class="alert alert-success">@successMessage</div>
}

<form method="post" action="/Account/ChangePasswordHandler">
    <div class="mb-3">
        <label for="currentPassword">Current Password</label>
        <input type="password" id="currentPassword" name="currentPassword" required class="form-control" />
    </div>
    <div class="mb-3">
        <label for="newPassword">New Password</label>
        <input type="password" id="newPassword" name="newPassword" required class="form-control" />
    </div>
    <div class="mb-3">
        <label for="confirmPassword">Confirm New Password</label>
        <input type="password" id="confirmPassword" name="confirmPassword" required class="form-control" />
    </div>
    <button type="submit" class="btn btn-primary">Change Password</button>
</form>

@code {
    [SupplyParameterFromQuery] public string? Error { get; set; }
    [SupplyParameterFromQuery] public string? Success { get; set; }

    private string? errorMessage;
    private string? successMessage;

    protected override void OnInitialized()
    {
        errorMessage = Error;
        successMessage = Success;
    }
}
```

### Web Forms Control → Blazor Mapping

| Web Forms | Blazor |
|-----------|---------------|
| `<asp:Login>` | `<form method="post">` with email/password inputs → minimal API endpoint |
| `<asp:LoginView>` | `<AuthorizeView>` with `<NotAuthorized>` / `<Authorized>` templates |
| `<asp:LoginName>` | `@context.User.Identity?.Name` inside `<AuthorizeView>` |
| `<asp:LoginStatus>` | Links inside `<AuthorizeView>` (login link for anonymous, logout form for authenticated) |
| `<asp:CreateUserWizard>` | Custom registration form with `<form method="post">` → minimal API endpoint |
| `<asp:ChangePassword>` | Custom form with `<form method="post">` → minimal API endpoint |

---

## Step 4: Migrate Authorization Patterns

### Web.config Authorization → Blazor Authorization

```xml
<!-- Web Forms — Web.config -->
<location path="Admin">
    <system.web>
        <authorization>
            <allow roles="Administrator" />
            <deny users="*" />
        </authorization>
    </system.web>
</location>
```

```razor
@* Blazor — Admin pages use [Authorize] attribute *@
@page "/Admin"
@attribute [Authorize(Roles = "Administrator")]

<h1>Admin Panel</h1>
```

### LoginView Conditional Content

```html
<!-- Web Forms -->
<asp:LoginView runat="server">
    <AnonymousTemplate>
        <a href="~/Account/Login">Log in</a>
    </AnonymousTemplate>
    <LoggedInTemplate>
        Welcome, <asp:LoginName runat="server" />!
        <asp:LoginStatus runat="server" LogoutAction="Redirect" LogoutPageUrl="~/" />
    </LoggedInTemplate>
</asp:LoginView>
```

```razor
@* Blazor — Native AuthorizeView *@
<AuthorizeView>
    <NotAuthorized>
        <a href="/Account/Login">Log in</a>
    </NotAuthorized>
    <Authorized>
        Welcome, @context.User.Identity?.Name!
        <form method="post" action="/Account/Logout" class="d-inline">
            <button type="submit" class="btn btn-link">Log out</button>
        </form>
    </Authorized>
</AuthorizeView>
```

### Role-Based Content

```html
<!-- Web Forms -->
<asp:LoginView runat="server">
    <RoleGroups>
        <asp:RoleGroup Roles="Administrator">
            <ContentTemplate><a href="~/Admin">Admin Panel</a></ContentTemplate>
        </asp:RoleGroup>
    </RoleGroups>
</asp:LoginView>
```

```razor
@* Blazor *@
<AuthorizeView Roles="Administrator">
    <a href="/Admin">Admin Panel</a>
</AuthorizeView>
```

---

## Step 5: Update Authentication State Access

### Code-Behind Auth Patterns

```csharp
// Web Forms — code-behind
if (HttpContext.Current.User.Identity.IsAuthenticated)
{
    var userName = HttpContext.Current.User.Identity.Name;
    var isAdmin = HttpContext.Current.User.IsInRole("Administrator");
}

// Web Forms — OWIN
var manager = Context.GetOwinContext().GetUserManager<ApplicationUserManager>();
var user = manager.FindById(User.Identity.GetUserId());
```

```csharp
// Blazor — inject auth state
@inject AuthenticationStateProvider AuthStateProvider

@code {
    private string? userName;
    private bool isAdmin;

    protected override async Task OnInitializedAsync()
    {
        var authState = await AuthStateProvider.GetAuthenticationStateAsync();
        var user = authState.User;
        userName = user.Identity?.Name;
        isAdmin = user.IsInRole("Administrator");
    }
}
```

### Cascading Auth Parameter (Simpler)

```csharp
// Blazor — cascading parameter (requires AddCascadingAuthenticationState)
[CascadingParameter]
private Task<AuthenticationState>? AuthState { get; set; }

protected override async Task OnInitializedAsync()
{
    if (AuthState != null)
    {
        var state = await AuthState;
        var user = state.User;
    }
}
```

---

## OWIN to ASP.NET Core Identity Reference

Quick reference for OWIN Identity patterns already handled by the `migrating-aspnet-identity` skill:

| Web Forms (OWIN Startup.cs) | Blazor (Program.cs) |
|------------------------------|---------------------|
| `app.UseCookieAuthentication(...)` | `builder.Services.AddAuthentication().AddCookie(...)` |
| `app.UseExternalSignInCookie(...)` | `builder.Services.AddAuthentication().AddGoogle/Facebook(...)` |
| `ConfigureAuth(app)` in `Startup.Auth.cs` | Configuration in `Program.cs` services section |
| `app.CreatePerOwinContext<ApplicationUserManager>(...)` | `builder.Services.AddIdentity<ApplicationUser, IdentityRole>()` |
| `SecurityStampValidator.OnValidateIdentity(...)` | Built into ASP.NET Core Identity automatically |

> **Note:** For projects using OWIN **cookie authentication without ASP.NET Identity**, use the `migrating-owin-cookie-auth` skill instead.

---

## Reference Documents

For detailed implementation patterns and code examples:

- **[references/cookie-auth-pattern.md](references/cookie-auth-pattern.md)** — Complete explanation of why HttpContext NULL errors in WebSocket circuits, the form → minimal API pattern, DisableAntiforgery requirement, troubleshooting, and alternative approaches
- **[references/endpoint-templates.md](references/endpoint-templates.md)** — Ready-to-use minimal API endpoint code for login, register, logout, password reset, external providers (Google/Microsoft), and testing examples

---

## Common Identity Gotchas

### No HttpContext.Current
Blazor Server has no `HttpContext.Current`. Use dependency injection:
```csharp
// WRONG: HttpContext.Current.User
// RIGHT: Inject AuthenticationStateProvider or use [CascadingParameter]
```

### Cookie Auth Requires HTTP Endpoints
Blazor Server login/logout MUST use HTTP endpoints (not component-based), because cookies are set on HTTP responses — see [references/cookie-auth-pattern.md](references/cookie-auth-pattern.md).

### SignalR Circuit vs HTTP Request
Authentication state is captured when the circuit starts. If the user's session expires mid-circuit, they remain "authenticated" until the page refreshes. Use `RevalidatingServerAuthenticationStateProvider` for periodic revalidation.

### Blazor Identity UI Scaffolding
For a complete Identity UI (login, register, manage profile), scaffold it:
```bash
dotnet aspnet-codegenerator identity -dc ApplicationDbContext --files "Account.Login;Account.Register;Account.Logout"
```
This generates Razor Pages (not components) under `/Areas/Identity/`. They coexist with Blazor.