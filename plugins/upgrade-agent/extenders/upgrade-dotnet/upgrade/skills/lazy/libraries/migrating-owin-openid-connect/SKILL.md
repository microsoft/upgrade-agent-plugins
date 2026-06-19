---
name: migrating-owin-openid-connect
description: >
  Migrates legacy OWIN OpenID Connect authentication
  (Microsoft.Owin.Security.OpenIdConnect) to ASP.NET Core OpenID
  Connect (Microsoft.AspNetCore.Authentication.OpenIdConnect).
  Use ONLY when Microsoft.Owin.Security.OpenIdConnect has been
  flagged as obsolete or deprecated and must be replaced — not
  for version-bump scenarios where
  Microsoft.Owin.Security.OpenIdConnect is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# OWIN OpenID Connect Authentication Migration

## Overview

Migrate OWIN-based OpenID Connect authentication to ASP.NET Core. The main change is replacing OWIN middleware registration and notification callbacks with the ASP.NET Core `AddOpenIdConnect()` builder pattern and strongly-typed events. Cookie authentication must be explicitly paired because ASP.NET Core does not implicitly manage session cookies for OpenID Connect.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="Microsoft.Owin.Security.OpenIdConnect" Version="{old-version}" />
<PackageReference Include="Microsoft.Owin.Security.Cookies" Version="{old-version}" />
<PackageReference Include="Microsoft.Owin" Version="{old-version}" />
```

### New References (Add)

```xml
<PackageReference Include="Microsoft.AspNetCore.Authentication.OpenIdConnect" Version="{version}" />
```

The cookie authentication middleware is included in the ASP.NET Core shared framework and does not require a separate package reference.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect OWIN OpenID Connect usage
- [ ] Step 2: Update project file references
- [ ] Step 3: Replace middleware registration
- [ ] Step 4: Migrate options and notification callbacks
- [ ] Step 5: Build and verify
```

### Step 1: Detect OWIN OpenID Connect Usage

Scan the project for:
- `using Microsoft.Owin.Security.OpenIdConnect;` statements
- `app.UseOpenIdConnectAuthentication(...)` calls
- `OpenIdConnectAuthenticationOptions` configuration
- `Notifications` property assignments (`SecurityTokenValidated`, `AuthorizationCodeReceived`, etc.)

### Step 2: Update Project File References

Remove old OWIN packages and add the ASP.NET Core package (see "Package Reference Changes" above).

### Step 3: Replace Middleware Registration

Replace the OWIN middleware setup with ASP.NET Core service registration:

```csharp
// Old: OWIN Startup.Auth.cs
app.UseOpenIdConnectAuthentication(new OpenIdConnectAuthenticationOptions { ... });

// New: ASP.NET Core Program.cs / Startup.cs
builder.Services.AddAuthentication(options =>
{
    options.DefaultScheme = CookieAuthenticationDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = OpenIdConnectDefaults.AuthenticationScheme;
})
.AddCookie()
.AddOpenIdConnect(options => { /* see Step 4 */ });
```

Pair `AddOpenIdConnect()` with `AddCookie()` — ASP.NET Core requires explicit cookie auth for session management after the OpenID Connect handshake.

### Step 4: Migrate Options and Notification Callbacks

| OWIN (Old) | ASP.NET Core (New) |
|------------|-------------------|
| `OpenIdConnectAuthenticationOptions` | `OpenIdConnectOptions` |
| `options.ClientId` | `options.ClientId` (same) |
| `options.Authority` | `options.Authority` (same) |
| `options.RedirectUri` | `options.CallbackPath` (relative path, not absolute URI) |
| `options.PostLogoutRedirectUri` | `options.SignedOutCallbackPath` |
| `options.Notifications` | `options.Events` |
| `Notifications.SecurityTokenValidated` | `Events.OnTokenValidated` |
| `Notifications.AuthorizationCodeReceived` | `Events.OnAuthorizationCodeReceived` |
| `Notifications.RedirectToIdentityProvider` | `Events.OnRedirectToIdentityProvider` |
| `Notifications.AuthenticationFailed` | `Events.OnAuthenticationFailed` |

Callback context types also change — update parameter types in event handlers:

```csharp
// Old
Notifications = new OpenIdConnectAuthenticationNotifications
{
    SecurityTokenValidated = context => { /* SecurityTokenValidatedNotification */ }
};

// New
Events = new OpenIdConnectEvents
{
    OnTokenValidated = context => { /* TokenValidatedContext */ }
};
```

### Step 5: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Verify the authentication flow end-to-end: sign-in redirect, callback handling, token validation, and sign-out
3. Confirm cookie-based session persistence works after the OpenID Connect handshake

## Troubleshooting

### Redirect URI Mismatch

ASP.NET Core uses `CallbackPath` (a relative path like `/signin-oidc`) rather than a full redirect URI. Update the identity provider's registered redirect URI to match the application's base URL plus the callback path.

### Missing Cookie Authentication

If users are redirected in a loop after authentication, `AddCookie()` is likely missing. ASP.NET Core requires explicit cookie auth to persist the session after the OpenID Connect handshake.

### Notification Context Type Errors

The event context types changed between OWIN and ASP.NET Core. Replace OWIN notification parameter types with the corresponding ASP.NET Core context types (e.g., `TokenValidatedContext` instead of `SecurityTokenValidatedNotification`).
