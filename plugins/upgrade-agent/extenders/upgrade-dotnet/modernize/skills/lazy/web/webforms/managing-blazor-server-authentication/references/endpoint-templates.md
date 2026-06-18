# Ready-to-Use Authentication Endpoint Templates

These minimal API endpoints handle authentication operations that must run over HTTP (not WebSocket). Add them to `Program.cs` after building the app but before `app.Run()`.

## Contents
- Login Endpoint
- Register Endpoint
- Logout Endpoint
- Change Password Endpoint
- External Provider Callback Endpoint
- Password Reset Flow
- Testing Endpoints
- Summary

> **Important:** Every endpoint below calls `.DisableAntiforgery()` because Blazor-rendered `<form>` elements do not include antiforgery tokens.

---

## Login Endpoint

Authenticates user credentials and sets the authentication cookie.

### Endpoint

```csharp
// Program.cs — authenticates user and sets auth cookie via HTTP response
app.MapPost("/Account/LoginHandler", async (HttpContext context, SignInManager<IdentityUser> signInManager) =>
{
    var form = await context.Request.ReadFormAsync();
    var email = form["email"].ToString();
    var password = form["password"].ToString();

    var result = await signInManager.PasswordSignInAsync(email, password, isPersistent: false, lockoutOnFailure: false);

    if (result.Succeeded)
        return Results.Redirect("/");

    if (result.RequiresTwoFactor)
        return Results.Redirect("/Account/LoginWith2fa");

    if (result.IsLockedOut)
        return Results.Redirect("/Account/Lockout");

    return Results.Redirect("/Account/Login?error=Invalid+login+attempt");
}).DisableAntiforgery();
```

### Blazor Form Component

```razor
@page "/Account/Login"

<h2>Log in</h2>

@if (!string.IsNullOrEmpty(errorMessage))
{
    <div class="alert alert-danger">@errorMessage</div>
}

<form method="post" action="/Account/LoginHandler">
    <div class="mb-3">
        <label for="email" class="form-label">Email</label>
        <input type="email" class="form-control" id="email" name="email" required />
    </div>
    <div class="mb-3">
        <label for="password" class="form-label">Password</label>
        <input type="password" class="form-control" id="password" name="password" required />
    </div>
    <button type="submit" class="btn btn-primary">Log in</button>
    <a href="/Account/Register" class="btn btn-link">Register as a new user</a>
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

**Key features:**
- Error handling via query string (`?error=...`)
- Redirects to different pages for 2FA and lockout
- Form field names match endpoint parameter reads

---

## Register Endpoint

Creates a new user account and signs them in automatically.

### Endpoint

```csharp
// Program.cs — creates user, signs in, and redirects
app.MapPost("/Account/RegisterHandler", async (HttpContext context,
    UserManager<IdentityUser> userManager, SignInManager<IdentityUser> signInManager) =>
{
    var form = await context.Request.ReadFormAsync();
    var email = form["email"].ToString();
    var password = form["password"].ToString();
    var confirmPassword = form["confirmPassword"].ToString();

    if (password != confirmPassword)
        return Results.Redirect("/Account/Register?error=Passwords+do+not+match");

    var user = new IdentityUser { UserName = email, Email = email };
    var result = await userManager.CreateAsync(user, password);

    if (result.Succeeded)
    {
        await signInManager.SignInAsync(user, isPersistent: false);
        return Results.Redirect("/");
    }

    var errors = string.Join("; ", result.Errors.Select(e => e.Description));
    return Results.Redirect($"/Account/Register?error={Uri.EscapeDataString(errors)}");
}).DisableAntiforgery();
```

### Blazor Form Component

```razor
@page "/Account/Register"

<h2>Create a new account</h2>

@if (!string.IsNullOrEmpty(errorMessage))
{
    <div class="alert alert-danger">@errorMessage</div>
}

<form method="post" action="/Account/RegisterHandler">
    <div class="mb-3">
        <label for="email" class="form-label">Email</label>
        <input type="email" class="form-control" id="email" name="email" required />
    </div>
    <div class="mb-3">
        <label for="password" class="form-label">Password</label>
        <input type="password" class="form-control" id="password" name="password" required />
    </div>
    <div class="mb-3">
        <label for="confirmPassword" class="form-label">Confirm Password</label>
        <input type="password" class="form-control" id="confirmPassword" name="confirmPassword" required />
    </div>
    <button type="submit" class="btn btn-primary">Register</button>
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

**Key features:**
- Password confirmation validation
- Identity error messages passed via query string
- Auto-login after successful registration

---

## Logout Endpoint

Signs out the current user and clears the authentication cookie.

### Endpoint

```csharp
// Program.cs — signs out and redirects to home page
app.MapPost("/Account/Logout", async (SignInManager<IdentityUser> signInManager) =>
{
    await signInManager.SignOutAsync();
    return Results.Redirect("/");
}).DisableAntiforgery();
```

### Blazor Form Component (Inline)

```razor
<form method="post" action="/Account/Logout" class="d-inline">
    <button type="submit" class="nav-link btn btn-link">Log out</button>
</form>
```

Or in a navigation menu:

```razor
<AuthorizeView>
    <Authorized>
        <span class="navbar-text">Hello, @context.User.Identity?.Name!</span>
        <form method="post" action="/Account/Logout" class="d-inline">
            <button type="submit" class="btn btn-link">Log out</button>
        </form>
    </Authorized>
    <NotAuthorized>
        <a href="/Account/Login" class="btn btn-link">Log in</a>
    </NotAuthorized>
</AuthorizeView>
```

> **Important:** Do NOT use `<a href="/Account/Logout">` — Blazor's enhanced navigation will intercept the click and attempt client-side navigation instead of a real HTTP POST. Use a `<form method="post">` with a submit button, or add `data-enhance-nav="false"` to the link.

---

## Change Password Endpoint

Allows authenticated users to change their password.

### Endpoint

```csharp
// Program.cs — changes password for authenticated user
app.MapPost("/Account/ChangePasswordHandler", async (HttpContext context,
    UserManager<IdentityUser> userManager) =>
{
    var form = await context.Request.ReadFormAsync();
    var currentPassword = form["currentPassword"].ToString();
    var newPassword = form["newPassword"].ToString();
    var confirmPassword = form["confirmPassword"].ToString();

    if (newPassword != confirmPassword)
        return Results.Redirect("/Account/ChangePassword?error=Passwords+do+not+match");

    var user = await userManager.GetUserAsync(context.User);
    if (user == null)
        return Results.Redirect("/Account/Login");

    var result = await userManager.ChangePasswordAsync(user, currentPassword, newPassword);

    if (result.Succeeded)
        return Results.Redirect("/Account/ChangePassword?success=Password+changed+successfully");

    var errors = string.Join("; ", result.Errors.Select(e => e.Description));
    return Results.Redirect($"/Account/ChangePassword?error={Uri.EscapeDataString(errors)}");
}).DisableAntiforgery();
```

### Blazor Form Component

```razor
@page "/Account/ChangePassword"
@attribute [Authorize]

<h2>Change Password</h2>

@if (!string.IsNullOrEmpty(successMessage))
{
    <div class="alert alert-success">@successMessage</div>
}

@if (!string.IsNullOrEmpty(errorMessage))
{
    <div class="alert alert-danger">@errorMessage</div>
}

<form method="post" action="/Account/ChangePasswordHandler">
    <div class="mb-3">
        <label for="currentPassword" class="form-label">Current Password</label>
        <input type="password" class="form-control" id="currentPassword" name="currentPassword" required />
    </div>
    <div class="mb-3">
        <label for="newPassword" class="form-label">New Password</label>
        <input type="password" class="form-control" id="newPassword" name="newPassword" required />
    </div>
    <div class="mb-3">
        <label for="confirmPassword" class="form-label">Confirm New Password</label>
        <input type="password" class="form-control" id="confirmPassword" name="confirmPassword" required />
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

**Key features:**
- Requires authentication (`[Authorize]`)
- Validates current password before allowing change
- Success message via query string

---

## External Provider Callback Endpoint

Handles OAuth callbacks from external providers (Google, Microsoft, Facebook, etc.).

### Prerequisites

```csharp
// Program.cs — configure external providers
builder.Services.AddAuthentication()
    .AddGoogle(options =>
    {
        options.ClientId = builder.Configuration["Authentication:Google:ClientId"]!;
        options.ClientSecret = builder.Configuration["Authentication:Google:ClientSecret"]!;
    })
    .AddMicrosoftAccount(options =>
    {
        options.ClientId = builder.Configuration["Authentication:Microsoft:ClientId"]!;
        options.ClientSecret = builder.Configuration["Authentication:Microsoft:ClientSecret"]!;
    });
```

### Endpoint

```csharp
// Program.cs — initiates external auth challenge
app.MapGet("/Account/ExternalLogin", (string provider, string returnUrl, IAuthenticationSchemeProvider schemes) =>
{
    return Results.Challenge(
        new AuthenticationProperties { RedirectUri = $"/Account/ExternalLoginCallback?returnUrl={returnUrl}" },
        new[] { provider });
}).DisableAntiforgery();

// Program.cs — handles external auth callback
app.MapGet("/Account/ExternalLoginCallback", async (HttpContext context,
    SignInManager<IdentityUser> signInManager, UserManager<IdentityUser> userManager, string? returnUrl = null) =>
{
    var info = await signInManager.GetExternalLoginInfoAsync();
    if (info == null)
        return Results.Redirect("/Account/Login?error=External+login+error");

    var result = await signInManager.ExternalLoginSignInAsync(info.LoginProvider, info.ProviderKey, isPersistent: false);

    if (result.Succeeded)
        return Results.Redirect(returnUrl ?? "/");

    // User doesn't exist, create account
    var email = info.Principal.FindFirstValue(ClaimTypes.Email);
    if (email == null)
        return Results.Redirect("/Account/Login?error=Email+not+provided");

    var user = new IdentityUser { UserName = email, Email = email };
    var createResult = await userManager.CreateAsync(user);

    if (!createResult.Succeeded)
        return Results.Redirect("/Account/Login?error=Failed+to+create+account");

    await userManager.AddLoginAsync(user, info);
    await signInManager.SignInAsync(user, isPersistent: false);

    return Results.Redirect(returnUrl ?? "/");
}).DisableAntiforgery();
```

### Blazor Form Component

```razor
@page "/Account/Login"

<h2>Log in</h2>

<!-- Local login form here -->

<hr />

<h4>Use another service to log in</h4>
<form method="post" action="/Account/ExternalLogin?provider=Google&returnUrl=/">
    <button type="submit" class="btn btn-outline-primary">
        <i class="fab fa-google"></i> Log in with Google
    </button>
</form>

<form method="post" action="/Account/ExternalLogin?provider=Microsoft&returnUrl=/">
    <button type="submit" class="btn btn-outline-primary">
        <i class="fab fa-microsoft"></i> Log in with Microsoft
    </button>
</form>
```

**Key features:**
- Auto-creates user account if external login succeeds but user doesn't exist
- Preserves return URL through the OAuth flow
- Email is required from external provider

---

## Password Reset Flow

Two-step process: request reset link, then complete reset.

### Request Reset Endpoint

```csharp
// Program.cs — sends password reset email
app.MapPost("/Account/ForgotPasswordHandler", async (HttpContext context,
    UserManager<IdentityUser> userManager, IEmailSender emailSender) =>
{
    var form = await context.Request.ReadFormAsync();
    var email = form["email"].ToString();

    var user = await userManager.FindByEmailAsync(email);
    if (user == null || !await userManager.IsEmailConfirmedAsync(user))
    {
        // Don't reveal that user doesn't exist
        return Results.Redirect("/Account/ForgotPasswordConfirmation");
    }

    var code = await userManager.GeneratePasswordResetTokenAsync(user);
    var callbackUrl = $"https://yourdomain.com/Account/ResetPassword?code={Uri.EscapeDataString(code)}&email={Uri.EscapeDataString(email)}";

    await emailSender.SendEmailAsync(email, "Reset Password",
        $"Please reset your password by clicking here: <a href='{callbackUrl}'>link</a>");

    return Results.Redirect("/Account/ForgotPasswordConfirmation");
}).DisableAntiforgery();
```

### Complete Reset Endpoint

```csharp
// Program.cs — completes password reset
app.MapPost("/Account/ResetPasswordHandler", async (HttpContext context,
    UserManager<IdentityUser> userManager, SignInManager<IdentityUser> signInManager) =>
{
    var form = await context.Request.ReadFormAsync();
    var email = form["email"].ToString();
    var code = form["code"].ToString();
    var password = form["password"].ToString();

    var user = await userManager.FindByEmailAsync(email);
    if (user == null)
        return Results.Redirect("/Account/Login");

    var result = await userManager.ResetPasswordAsync(user, code, password);

    if (result.Succeeded)
    {
        // Optionally sign in the user
        await signInManager.SignInAsync(user, isPersistent: false);
        return Results.Redirect("/");
    }

    var errors = string.Join("; ", result.Errors.Select(e => e.Description));
    return Results.Redirect($"/Account/ResetPassword?error={Uri.EscapeDataString(errors)}");
}).DisableAntiforgery();
```

---

## Testing Endpoints

### Integration Test Example

```csharp
[TestClass]
public class AuthenticationEndpointTests
{
    [TestMethod]
    public async Task Login_ValidCredentials_RedirectsToHome()
    {
        // Arrange
        var factory = new WebApplicationFactory<Program>();
        var client = factory.CreateClient();
        var formData = new Dictionary<string, string>
        {
            ["email"] = "test@example.com",
            ["password"] = "Test123!"
        };

        // Act
        var response = await client.PostAsync("/Account/LoginHandler", new FormUrlEncodedContent(formData));

        // Assert
        Assert.AreEqual(HttpStatusCode.Redirect, response.StatusCode);
        Assert.AreEqual("/", response.Headers.Location?.PathAndQuery);
    }
}
```

---

## Summary

All endpoints follow the same pattern:
1. Read form data with `await context.Request.ReadFormAsync()`
2. Perform authentication operation (credentials validation, user creation, etc.)
3. Return `Results.Redirect()` to appropriate Blazor page
4. Use query strings for error/success messages
5. **Always** call `.DisableAntiforgery()`

**Copy these templates directly into your `Program.cs` and adjust user types, redirect URLs, and error handling as needed.**
