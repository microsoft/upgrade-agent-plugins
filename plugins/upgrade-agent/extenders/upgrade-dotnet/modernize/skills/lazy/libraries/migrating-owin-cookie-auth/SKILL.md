---
name: migrating-owin-cookie-auth
description: >
  Migrates legacy OWIN cookie authentication
  (Microsoft.Owin.Security.Cookies) to ASP.NET Core cookie
  authentication (Microsoft.AspNetCore.Authentication.Cookies).
  Use ONLY when Microsoft.Owin.Security.Cookies has been flagged as
  obsolete or deprecated and must be replaced — not for version-bump
  scenarios where the OWIN package is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# OWIN Cookie Authentication Migration

## Overview

Migrate cookie-based authentication from OWIN (`Microsoft.Owin.Security.Cookies`) to ASP.NET Core's built-in cookie authentication. The core change is replacing the OWIN middleware pipeline (`IAppBuilder.UseCookieAuthentication()`) with ASP.NET Core's service-based model (`AddAuthentication().AddCookie()`). Most cookie options map directly, but the provider/callback model is replaced by an events pattern.

> **Related skills:** For general OWIN middleware migration, see `migrating-owin-to-aspnet-core`. For OAuth bearer token migration, see `migrating-owin-oauth-to-jwt`.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="Microsoft.Owin.Security.Cookies" Version="4.x.x" />
<PackageReference Include="Microsoft.Owin.Security" Version="4.x.x" />
<PackageReference Include="Microsoft.Owin" Version="4.x.x" />
```

### New Reference (Add)

```xml
<!-- Included in Microsoft.AspNetCore.App shared framework; explicit reference usually not needed -->
<PackageReference Include="Microsoft.AspNetCore.Authentication.Cookies" Version="{version}" />
```

For projects targeting the `Microsoft.AspNetCore.App` shared framework, the cookie authentication package is included automatically — no explicit package reference is required.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect OWIN cookie auth usage
- [ ] Step 2: Update package references
- [ ] Step 3: Replace middleware registration
- [ ] Step 4: Migrate cookie options
- [ ] Step 5: Convert provider callbacks to events
- [ ] Step 6: Update sign-in/sign-out calls
- [ ] Step 7: Build and verify
```

### Step 1: Detect OWIN Cookie Auth Usage

Scan the project for:
- `using Microsoft.Owin.Security.Cookies;` statements
- `app.UseCookieAuthentication(new CookieAuthenticationOptions { ... })` calls
- `ICookieAuthenticationProvider` or `CookieAuthenticationProvider` implementations
- References to `IOwinContext` for authentication operations

If the project already uses `Microsoft.AspNetCore.Authentication.Cookies`, no migration is needed.

### Step 2: Update Package References

Remove OWIN cookie packages and add the ASP.NET Core equivalent if not already available via the shared framework (see "Package Reference Changes" above). Update the `using` directives:

```csharp
// Old
using Microsoft.Owin.Security.Cookies;

// New
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
```

### Step 3: Replace Middleware Registration

The OWIN middleware pipeline becomes ASP.NET Core service configuration and middleware:

```csharp
// OWIN (Startup.Configuration)
app.UseCookieAuthentication(new CookieAuthenticationOptions
{
    AuthenticationType = "ApplicationCookie",
    LoginPath = new PathString("/Account/Login")
});

// ASP.NET Core (Startup.ConfigureServices + Configure)
services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.LoginPath = "/Account/Login";
    });

// In the middleware pipeline
app.UseAuthentication();
app.UseAuthorization();
```

### Step 4: Migrate Cookie Options

| OWIN Option | ASP.NET Core Equivalent | Notes |
|-------------|------------------------|-------|
| `AuthenticationType` | `CookieAuthenticationDefaults.AuthenticationScheme` | Set via `AddAuthentication(scheme)` |
| `LoginPath` | `options.LoginPath` | Same purpose, same format |
| `LogoutPath` | `options.LogoutPath` | Same purpose, same format |
| `ReturnUrlParameter` | `options.ReturnUrlParameter` | Same purpose |
| `CookieName` | `options.Cookie.Name` | Moved under `options.Cookie` |
| `CookieDomain` | `options.Cookie.Domain` | Moved under `options.Cookie` |
| `CookieHttpOnly` | `options.Cookie.HttpOnly` | Moved under `options.Cookie` |
| `CookieSecure` | `options.Cookie.SecurePolicy` | Enum: `Always`, `SameAsRequest`, `None` |
| `ExpireTimeSpan` | `options.ExpireTimeSpan` | Same purpose |
| `SlidingExpiration` | `options.SlidingExpiration` | Same purpose |

### Step 5: Convert Provider Callbacks to Events

OWIN uses a `CookieAuthenticationProvider` class with overridable methods. ASP.NET Core uses a `CookieAuthenticationEvents` class with delegate properties:

| OWIN Provider Method | ASP.NET Core Event |
|---------------------|-------------------|
| `OnValidateIdentity` | `events.OnValidateIdentity` → use `options.Events.OnValidatePrincipal` |
| `OnResponseSignIn` | `options.Events.OnSigningIn` |
| `OnResponseSignedIn` | `options.Events.OnSignedIn` |
| `OnResponseSignOut` | `options.Events.OnSigningOut` |
| `OnApplyRedirect` | `options.Events.OnRedirectToLogin` / `OnRedirectToLogout` / `OnRedirectToAccessDenied` |
| `OnException` | Handle via middleware exception handling |

```csharp
// OWIN
Provider = new CookieAuthenticationProvider
{
    OnValidateIdentity = context => { /* ... */ }
};

// ASP.NET Core
options.Events = new CookieAuthenticationEvents
{
    OnValidatePrincipal = context => { /* ... */ }
};
```

### Step 6: Update Sign-In/Sign-Out Calls

Replace OWIN context-based calls with ASP.NET Core `HttpContext` extension methods:

```csharp
// OWIN
HttpContext.GetOwinContext().Authentication.SignIn(identity);
HttpContext.GetOwinContext().Authentication.SignOut("ApplicationCookie");

// ASP.NET Core
await HttpContext.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme, principal);
await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
```

Note: ASP.NET Core sign-in/sign-out methods are async and require `await`.

### Step 7: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Test the login flow end-to-end (login page → authenticate → redirect)
3. Confirm cookie is set in the browser with expected name and properties
4. Verify sign-out clears the authentication cookie
5. Test sliding expiration behavior if configured

## Troubleshooting

### "No authentication handler is registered for the scheme"

Ensure `AddAuthentication(scheme)` is called with the correct scheme name, and that `AddCookie()` is chained. If using multiple schemes, set the default scheme explicitly.

### Cookie Not Being Set

Check that `app.UseAuthentication()` is called before `app.UseAuthorization()` and before endpoint routing. In ASP.NET Core, middleware order matters — authentication must run before authorization.

### OnValidateIdentity Not Firing

The OWIN `OnValidateIdentity` callback maps to `OnValidatePrincipal` in ASP.NET Core (not `OnValidateIdentity`). Ensure the event name is updated.

### Redirect Loops on Login

Verify that `LoginPath` points to a page that does not itself require authentication. Add `[AllowAnonymous]` to the login endpoint if using authorization policies.
