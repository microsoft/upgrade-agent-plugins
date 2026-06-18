---
name: migrating-mvc-authentication
description: >
  Migrates ASP.NET MVC and Web API authentication and authorization to ASP.NET Core, covering
  Forms Authentication, Membership providers, Windows Authentication, token-based auth, authorization
  rules, and anti-forgery tokens. Use when upgrading projects that use FormsAuthentication,
  SqlMembershipProvider, SimpleMembership, Windows auth, OWIN OAuth, custom IPrincipal, role
  providers, ClaimsPrincipal.Current, machineKey, or web.config authorization rules. Also triggers
  for auth migration, login migration, cookie ticket conversion, password rehash strategy, and
  Authorize attribute differences.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC Authentication and Authorization Migration

## Overview

Migrate authentication and authorization from ASP.NET MVC/Web API to ASP.NET Core. This is the highest-risk area of any ASP.NET migration because wrong decisions produce security vulnerabilities, not compiler errors. Multiple migration paths exist depending on the authentication mechanism used — assess first, then apply the correct path.

> **Related skills:** For ASP.NET Identity (UserManager, SignInManager, IdentityDbContext), see `migrating-aspnet-identity`. For OWIN cookie auth, see `migrating-owin-cookie-auth`. For OWIN OAuth/JWT, see `migrating-owin-oauth-to-jwt`. For OWIN OpenID Connect, see `migrating-owin-openid-connect`. For ADAL to MSAL, see `migrating-adal-to-msal`.

## Workflow

```
Migration Progress:
- [ ] Step 1: Assess authentication mechanisms
- [ ] Step 2: Migrate authentication configuration
- [ ] Step 3: Migrate sign-in and sign-out calls
- [ ] Step 4: Migrate membership and user stores
- [ ] Step 5: Migrate authorization rules
- [ ] Step 6: Migrate anti-forgery tokens
- [ ] Step 7: Remove legacy references
- [ ] Step 8: Build and verify
```

### Step 1: Assess Authentication Mechanisms

Scan the project to determine which authentication mechanisms are in use. Check these locations:

- `web.config`: `<authentication mode="...">`, `<membership>`, `<roleManager>`, `<machineKey>`, `<authorization>`
- `Global.asax` / `Startup.cs` / `Startup.Auth.cs`: OWIN middleware registration
- Controllers and views: `FormsAuthentication.*`, `Membership.*`, `Roles.*`, `User.Identity.*`
- Custom classes: `IPrincipal`, `IIdentity`, `MembershipProvider`, `RoleProvider` implementations

Categorize findings into one or more paths:

| Signal | Migration Path |
|--------|---------------|
| `<authentication mode="Forms">`, `FormsAuthentication.*` | → Cookie Authentication (Step 2A) |
| `SqlMembershipProvider`, `SimpleMembership`, custom `MembershipProvider` | → ASP.NET Core Identity (Step 4) |
| `<authentication mode="Windows">` | → Negotiate Authentication (Step 2B) |
| OWIN OAuth/JWT middleware | → See `migrating-owin-oauth-to-jwt` |
| OWIN cookie middleware | → See `migrating-owin-cookie-auth` |
| OWIN OpenID Connect | → See `migrating-owin-openid-connect` |
| ASP.NET Identity (IdentityDbContext, UserManager) | → See `migrating-aspnet-identity` |

Projects often combine multiple mechanisms (e.g., Forms Auth + Membership + Role Provider). Apply each relevant path.

### Step 2: Migrate Authentication Configuration

#### Step 2A: Forms Authentication → Cookie Authentication

Replace Forms Authentication with ASP.NET Core cookie authentication. Register the service in `Program.cs`:

```csharp
// Old: web.config
// <authentication mode="Forms">
//   <forms loginUrl="~/Account/Login" timeout="30" slidingExpiration="true" />
// </authentication>

// New: Program.cs
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.LoginPath = "/Account/Login";
        options.LogoutPath = "/Account/Logout";
        options.AccessDeniedPath = "/Account/AccessDenied";
        options.ExpireTimeSpan = TimeSpan.FromMinutes(30);
        options.SlidingExpiration = true;
    });
```

Add authentication middleware in the correct order:

```csharp
app.UseAuthentication();
app.UseAuthorization();
```

**⚠️ Security note:** Old Forms Authentication cookie tickets are not compatible with ASP.NET Core cookies. Users will be logged out after migration. Plan a session reset.

**⚠️ machineKey migration:** `<machineKey>` in web.config is replaced by the Data Protection API. Key management is completely different. If the old app shared machine keys across servers for cookie decryption, configure Data Protection with a shared key ring:

```csharp
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo(@"\\server\share\keys"))
    .SetApplicationName("SharedAppName");
```

#### Step 2B: Windows Authentication → Negotiate Authentication

Replace web.config Windows auth with the Negotiate authentication handler:

```csharp
// Old: web.config
// <authentication mode="Windows" />

// New: Program.cs
builder.Services.AddAuthentication(NegotiateDefaults.AuthenticationScheme)
    .AddNegotiate();

builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = options.DefaultPolicy;
});
```

Add the NuGet package `Microsoft.AspNetCore.Authentication.Negotiate`.

**Hosting differences:** Windows Authentication setup varies by host:
- **IIS (in-process):** Enable Windows Authentication in IIS site settings; no code changes beyond the service registration.
- **Kestrel:** Requires Negotiate handler configuration and may need SPN registration for domain environments.

`WindowsIdentity` is still accessible via `HttpContext.User.Identity as WindowsIdentity`, but access paths through `Thread.CurrentPrincipal` or `ClaimsPrincipal.Current` no longer work.

### Step 3: Migrate Sign-In and Sign-Out Calls

Replace `FormsAuthentication` static method calls with `HttpContext` extension methods. All ASP.NET Core equivalents are async.

```csharp
// OLD: FormsAuthentication.SetAuthCookie(username, isPersistent);
// NEW:
var claims = new List<Claim>
{
    new Claim(ClaimTypes.Name, username)
};
var identity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
var principal = new ClaimsPrincipal(identity);
await HttpContext.SignInAsync(
    CookieAuthenticationDefaults.AuthenticationScheme,
    principal,
    new AuthenticationProperties { IsPersistent = isPersistent });
```

```csharp
// OLD: FormsAuthentication.SignOut();
// NEW:
await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
```

```csharp
// OLD: FormsAuthentication.RedirectToLoginPage();
// NEW (in a controller):
return Challenge();
// Or explicit redirect:
return Redirect("/Account/Login");
```

**⚠️ Async requirement:** All sign-in/sign-out calls are async in ASP.NET Core. Update controller action signatures to return `Task<IActionResult>`.

Replace `FormsAuthenticationTicket` custom data with additional claims on the `ClaimsIdentity`. Do not attempt to replicate the ticket format.

### Step 4: Migrate Membership and User Stores

#### SqlMembershipProvider / SimpleMembership → ASP.NET Core Identity

If the project uses `SqlMembershipProvider` or `SimpleMembership`, migrate to ASP.NET Core Identity. For detailed Identity migration (DbContext, UserManager, SignInManager), see `migrating-aspnet-identity`.

**Password hashing change:** ASP.NET Membership uses SHA-1 or SHA-256 hashed passwords. ASP.NET Core Identity uses PBKDF2 with HMAC-SHA256. Existing password hashes are incompatible. Implement a compatibility hasher that verifies old hashes and re-hashes on successful login:

```csharp
public class MembershipPasswordHasher : IPasswordHasher<ApplicationUser>
{
    private readonly PasswordHasher<ApplicationUser> _coreHasher = new();

    public string HashPassword(ApplicationUser user, string password)
    {
        return _coreHasher.HashPassword(user, password);
    }

    public PasswordVerificationResult VerifyHashedPassword(
        ApplicationUser user, string hashedPassword, string providedPassword)
    {
        // Try ASP.NET Core format first
        var result = _coreHasher.VerifyHashedPassword(user, hashedPassword, providedPassword);
        if (result != PasswordVerificationResult.Failed)
            return result;

        // Fall back to legacy Membership hash verification
        if (VerifyLegacyHash(hashedPassword, providedPassword))
            return PasswordVerificationResult.SuccessRehashNeeded;

        return PasswordVerificationResult.Failed;
    }

    private bool VerifyLegacyHash(string hashedPassword, string providedPassword)
    {
        // Implement legacy hash verification matching the old provider's algorithm
        // (SHA-1, SHA-256, or custom — check the old <membership> config for hashAlgorithmType)
        throw new NotImplementedException("Match the old provider's hash algorithm");
    }
}
```

Register the custom hasher:

```csharp
builder.Services.AddScoped<IPasswordHasher<ApplicationUser>, MembershipPasswordHasher>();
```

**⚠️ Security note:** The `VerifyLegacyHash` implementation must match the exact algorithm from the old `<membership>` configuration, including salt handling. Get this wrong and either all logins fail or password verification is insecure.

#### Custom MembershipProvider → Custom UserStore

If the project uses a custom `MembershipProvider`, implement `IUserStore<TUser>` and optionally `IUserPasswordStore<TUser>`:

```csharp
public class LegacyUserStore : IUserStore<ApplicationUser>, IUserPasswordStore<ApplicationUser>
{
    // Map old MembershipProvider methods to UserStore interface
    // GetUser → FindByIdAsync / FindByNameAsync
    // ValidateUser → handled by IPasswordHasher
    // CreateUser → CreateAsync
}
```

Replace `Roles.IsUserInRole(username, role)` with:

```csharp
// In a controller (synchronous check via ClaimsPrincipal):
User.IsInRole("Admin")

// Via UserManager (async):
await userManager.IsInRoleAsync(user, "Admin")
```

### Step 5: Migrate Authorization Rules

#### Web.config Authorization → Policy-Based Authorization

Replace `<authorization>` rules in web.config with ASP.NET Core authorization policies:

```xml
<!-- Old: web.config -->
<authorization>
  <allow roles="Admin,Manager" />
  <deny users="*" />
</authorization>
```

```csharp
// New: Program.cs
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
});
```

#### Authorize Attribute Changes

`[Authorize(Roles = "Admin")]` works in both frameworks but resolves roles from different sources. Verify the role claim type matches:

```csharp
// If roles come from a custom claim type, configure it:
builder.Services.AddAuthentication()
    .AddCookie(options =>
    {
        options.ClaimsIssuer = "LegacyApp";
    });

// Or map during claims transformation:
builder.Services.AddTransient<IClaimsTransformation, LegacyRoleClaimsTransformation>();
```

**`[Authorize(Users = "...")]` is removed** in ASP.NET Core. Replace with a policy:

```csharp
// Old: [Authorize(Users = "admin,john")]
// New:
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("SpecificUsers", policy =>
        policy.RequireAssertion(context =>
            new[] { "admin", "john" }.Contains(
                context.User.Identity?.Name,
                StringComparer.OrdinalIgnoreCase)));
});

// On the controller or action:
[Authorize(Policy = "SpecificUsers")]
```

#### ClaimsPrincipal.Current Removal

`ClaimsPrincipal.Current` and `Thread.CurrentPrincipal` do not work in ASP.NET Core. Replace all usages:

```csharp
// Old (anywhere in code):
var user = ClaimsPrincipal.Current;

// New (in controllers):
var user = HttpContext.User;
// Or User property directly:
var user = User;

// New (in services — inject IHttpContextAccessor):
public class MyService
{
    private readonly IHttpContextAccessor _httpContextAccessor;
    public MyService(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }
    public ClaimsPrincipal GetCurrentUser() =>
        _httpContextAccessor.HttpContext?.User;
}
```

Register the accessor:

```csharp
builder.Services.AddHttpContextAccessor();
```

**⚠️ Security note:** `IHttpContextAccessor` returns null outside an HTTP request context (e.g., background tasks). Guard against null to avoid security bypass.

### Step 6: Migrate Anti-Forgery Tokens

ASP.NET Core uses a different anti-forgery token format. Old tokens are invalid after migration.

**Razor views:**

```cshtml
@* Old (still works but tag helpers are preferred): *@
@Html.AntiForgeryToken()

@* New (automatic with form tag helper): *@
<form asp-action="Submit" asp-controller="Home" method="post">
    @* Anti-forgery token is auto-generated *@
</form>
```

**Validation attribute:** `[ValidateAntiForgeryToken]` works in both frameworks but the underlying token mechanism differs. No code change needed for the attribute, but existing tokens in user browsers will be rejected after deployment.

**Global anti-forgery (AutoValidateAntiforgeryToken):**

```csharp
// Apply to all POST actions globally:
builder.Services.AddControllersWithViews(options =>
{
    options.Filters.Add(new AutoValidateAntiforgeryTokenAttribute());
});
```

**SPA / AJAX scenarios:** Inject `IAntiforgery` to generate tokens for non-form requests:

```csharp
app.MapGet("/antiforgery/token", (IAntiforgery antiforgery, HttpContext context) =>
{
    var tokens = antiforgery.GetAndStoreTokens(context);
    return Results.Ok(new { token = tokens.RequestToken });
});
```

**Cookie name change:** Configure a custom cookie name if client code depends on it:

```csharp
builder.Services.AddAntiforgery(options =>
{
    options.Cookie.Name = "X-CSRF-TOKEN";
    options.HeaderName = "X-CSRF-TOKEN";
});
```

### Step 7: Remove Legacy References

Remove all legacy authentication references:

- Delete `<authentication>`, `<membership>`, `<roleManager>`, `<machineKey>`, and `<authorization>` sections from web.config (if web.config is retained for IIS configuration, keep only IIS-relevant sections)
- Remove `FormsAuthentication` namespace usages (`System.Web.Security`)
- Remove `Membership` and `Roles` static class usages
- Remove OWIN authentication startup code (`Startup.Auth.cs`) if fully migrated
- Remove NuGet packages: `Microsoft.AspNet.Membership.OpenAuth`, `Microsoft.AspNet.Identity.Owin`, `Microsoft.Owin.Security`

### Step 8: Build and Verify

1. Build the project and resolve all compilation errors
2. **Security-critical verifications:**
   - Unauthenticated requests to protected endpoints return 401/redirect to login
   - Authentication succeeds with valid credentials
   - Old session cookies are rejected (not silently accepted)
   - Role-based and policy-based authorization enforces correctly
   - Anti-forgery validation rejects cross-site requests
   - `[AllowAnonymous]` endpoints remain accessible
3. If using Membership password rehashing, verify that a user with a legacy password hash can log in and that the hash is upgraded on success

## Troubleshooting

### "No authenticationScheme was specified"

Ensure `AddAuthentication(scheme)` is called with a default scheme. If multiple schemes are registered, set `DefaultAuthenticateScheme` and `DefaultChallengeScheme` explicitly.

### Users Logged Out After Deployment

Expected behavior. ASP.NET Core cookie tickets are incompatible with Forms Authentication tickets. Communicate the session reset to users before deployment.

### Legacy Passwords All Fail

The custom `IPasswordHasher` must match the exact hash algorithm, salt format, and encoding from the old Membership configuration. Check `<membership><providers><add passwordFormat="..." hashAlgorithmType="..." />` in the old web.config.

### Authorization Rules Not Applied

Web.config `<authorization>` rules are ignored by ASP.NET Core. All authorization must be configured through `AddAuthorization()` policies, `[Authorize]` attributes, or `RequireAuthorization()` on endpoints.

## Success Criteria

- Authentication middleware registered in `Program.cs` with correct scheme and options
- All `FormsAuthentication.*` calls replaced with `HttpContext.SignInAsync/SignOutAsync`
- Membership provider replaced with ASP.NET Core Identity or custom `IUserStore` with password rehash support
- Authorization rules migrated from web.config to policy-based authorization
- `ClaimsPrincipal.Current` replaced with `HttpContext.User` or `IHttpContextAccessor`
- Anti-forgery tokens configured for the new middleware
- No legacy authentication namespaces (`System.Web.Security`) remain
- Project builds without errors
- Protected endpoints reject unauthenticated requests
