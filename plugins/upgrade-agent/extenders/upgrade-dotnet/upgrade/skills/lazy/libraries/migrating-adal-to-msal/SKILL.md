---
name: migrating-adal-to-msal
description: >
  Migrates deprecated ADAL
  (Microsoft.IdentityModel.Clients.ActiveDirectory) to MSAL
  (Microsoft.Identity.Client) for Azure AD authentication.
  Use ONLY when
  Microsoft.IdentityModel.Clients.ActiveDirectory has been
  flagged as obsolete or deprecated and must be replaced —
  not for version-bump scenarios where ADAL is still
  supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# ADAL to MSAL Migration

## Overview

Migrate Azure AD authentication from ADAL (Active Directory Authentication Library) to MSAL (Microsoft Authentication Library). ADAL reached end of support in June 2023, and MSAL is the recommended replacement for all Azure AD / Microsoft Entra ID authentication scenarios. The core change is replacing `AuthenticationContext` with MSAL's fluent application builders and converting resource-based token requests to scope-based requests.

> **Related skills:** For OWIN-based cookie or OAuth authentication migration, see `migrating-owin-cookie-auth` and `migrating-owin-oauth-to-jwt`.

## Package Reference Changes

### Old Reference (Remove)

```xml
<PackageReference Include="Microsoft.IdentityModel.Clients.ActiveDirectory" Version="5.x.x" />
```

### New Reference (Add)

```xml
<PackageReference Include="Microsoft.Identity.Client" Version="{latest-stable}" />
```

Use tools or [NuGet](https://www.nuget.org/packages/Microsoft.Identity.Client) to find the latest stable version.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect ADAL usage patterns
- [ ] Step 2: Update package references
- [ ] Step 3: Replace AuthenticationContext with application builders
- [ ] Step 4: Convert resource strings to scopes
- [ ] Step 5: Update token cache serialization
- [ ] Step 6: Migrate credential flows
- [ ] Step 7: Build and verify
```

### Step 1: Detect ADAL Usage Patterns

Scan the project for:
- `using Microsoft.IdentityModel.Clients.ActiveDirectory;` statements
- `AuthenticationContext` instantiation
- `AcquireTokenAsync` calls with resource parameters
- `UserCredential` or `UserPasswordCredential` usage
- `ClientCredential` or `ClientAssertionCertificate` usage
- Custom `TokenCache` implementations

If the project already uses `Microsoft.Identity.Client`, no migration is needed.

### Step 2: Update Package References

Remove the ADAL package and add MSAL (see "Package Reference Changes" above). Update the `using` directive:

```csharp
// Old
using Microsoft.IdentityModel.Clients.ActiveDirectory;

// New
using Microsoft.Identity.Client;
```

### Step 3: Replace AuthenticationContext with Application Builders

MSAL distinguishes between public client apps (desktop/mobile) and confidential client apps (web/daemon). Choose the appropriate builder based on the application type.

| ADAL Pattern | MSAL Replacement |
|-------------|-----------------|
| `new AuthenticationContext(authority)` (public app) | `PublicClientApplicationBuilder.Create(clientId).WithAuthority(authority).Build()` |
| `new AuthenticationContext(authority)` (confidential app) | `ConfidentialClientApplicationBuilder.Create(clientId).WithClientSecret(secret).WithAuthority(authority).Build()` |
| `new ClientCredential(clientId, secret)` | `.WithClientSecret(secret)` on the builder |
| `new ClientAssertionCertificate(clientId, cert)` | `.WithCertificate(cert)` on the builder |

### Step 4: Convert Resource Strings to Scopes

ADAL uses a single resource string; MSAL uses a scopes array. For v1-to-v2 parity, append `/.default` to the resource URI:

```csharp
// ADAL
var result = await context.AcquireTokenAsync("https://graph.microsoft.com", credential);

// MSAL
var result = await app.AcquireTokenForClient(new[] { "https://graph.microsoft.com/.default" }).ExecuteAsync();
```

The `/.default` scope requests all statically configured permissions, matching ADAL's resource-based behavior.

### Step 5: Update Token Cache Serialization

ADAL's `TokenCache` and its `BeforeAccess`/`AfterAccess` events are replaced by MSAL's token cache serialization API. MSAL does not persist the cache by default — add serialization explicitly for web apps and daemon services:

```csharp
// MSAL cache serialization (example using Microsoft.Identity.Web)
app.AddInMemoryTokenCache();
// or
app.AddDistributedTokenCache(services => { /* configure */ });
```

For desktop apps, MSAL provides built-in file-based cache helpers via `Microsoft.Identity.Client.Extensions.Msal`.

### Step 6: Migrate Credential Flows

| ADAL Flow | MSAL Equivalent |
|-----------|----------------|
| `AcquireTokenAsync(resource, credential)` | `AcquireTokenForClient(scopes).ExecuteAsync()` |
| `AcquireTokenAsync(resource, clientId, redirectUri)` | `AcquireTokenInteractive(scopes).ExecuteAsync()` |
| `AcquireTokenSilentAsync(resource, clientId)` | `AcquireTokenSilent(scopes, account).ExecuteAsync()` |
| `new UserPasswordCredential(user, pass)` | `AcquireTokenByUsernamePassword(scopes, user, pass).ExecuteAsync()` |
| `AcquireTokenByAuthorizationCodeAsync(...)` | `AcquireTokenByAuthorizationCode(scopes, code).ExecuteAsync()` |

Note: `AuthenticationResult.AccessToken` works the same way in both libraries.

### Step 7: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Verify token acquisition succeeds against your Azure AD / Entra ID tenant
3. Confirm that `AuthenticationResult.AccessToken` is returned and API calls function correctly
4. Check that token caching works as expected (cache hit on second request)

## Troubleshooting

### "AADSTS50011: The reply URL does not match"

MSAL constructs redirect URIs differently than ADAL. For public client apps, use `http://localhost` or the platform-specific default. Update the app registration in the Azure portal to match.

### Authority URL Changes

ADAL uses `https://login.microsoftonline.com/{tenant}` by default. MSAL supports the same format but also accepts `https://login.microsoftonline.com/{tenant}/v2.0`. Use the v2.0 endpoint for new integrations; omit it for strict v1 parity.

### Token Cache Not Persisting

MSAL's default cache is in-memory only. For web apps, add `Microsoft.Identity.Web` and call `AddInMemoryTokenCache()` or `AddDistributedTokenCache()`. For desktop apps, add `Microsoft.Identity.Client.Extensions.Msal` and use `MsalCacheHelper`.

### Multi-Tenant Apps

If the ADAL code used `https://login.microsoftonline.com/common`, set `.WithAuthority(AadAuthorityAudience.AzureAdAndPersonalMicrosoftAccount)` or `.WithAuthority("https://login.microsoftonline.com/common")` on the MSAL builder.
