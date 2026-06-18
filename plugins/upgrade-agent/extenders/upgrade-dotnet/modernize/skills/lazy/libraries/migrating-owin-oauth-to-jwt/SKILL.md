---
name: migrating-owin-oauth-to-jwt
description: >
  Migrates legacy OWIN OAuth bearer authentication
  (Microsoft.Owin.Security.OAuth) to ASP.NET Core JWT Bearer
  authentication (Microsoft.AspNetCore.Authentication.JwtBearer).
  Use ONLY when Microsoft.Owin.Security.OAuth has been flagged as
  obsolete or deprecated and must be replaced — not for version-bump
  scenarios where the OWIN package is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# OWIN OAuth to JWT Bearer Migration

## Overview

Migrate OAuth bearer token authentication from OWIN (`Microsoft.Owin.Security.OAuth`) to ASP.NET Core JWT Bearer (`Microsoft.AspNetCore.Authentication.JwtBearer`). ASP.NET Core has no built-in equivalent to OWIN's `OAuthAuthorizationServerProvider` for issuing tokens — token issuance must move to an external identity provider such as Duende IdentityServer or Azure AD / Microsoft Entra ID. Token validation is handled by `AddJwtBearer()` with `TokenValidationParameters`.

> **Related skills:** For OWIN cookie authentication migration, see `migrating-owin-cookie-auth`. For general OWIN middleware migration, see `migrating-owin-to-aspnet-core`. For Azure AD authentication library migration, see `migrating-adal-to-msal`.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="Microsoft.Owin.Security.OAuth" Version="4.x.x" />
<PackageReference Include="Microsoft.Owin.Security" Version="4.x.x" />
<PackageReference Include="Microsoft.Owin" Version="4.x.x" />
```

### New Reference (Add)

```xml
<PackageReference Include="Microsoft.AspNetCore.Authentication.JwtBearer" Version="{version}" />
```

Use tools or [NuGet](https://www.nuget.org/packages/Microsoft.AspNetCore.Authentication.JwtBearer) to find the latest stable version matching the target framework.

## Workflow

```
Migration Progress:
- [ ] Step 1: Audit OWIN OAuth usage
- [ ] Step 2: Determine token issuance strategy
- [ ] Step 3: Update package references
- [ ] Step 4: Replace bearer token validation
- [ ] Step 5: Migrate token issuance (if applicable)
- [ ] Step 6: Update authorization attributes
- [ ] Step 7: Build and verify
```

### Step 1: Audit OWIN OAuth Usage

Scan the project for:
- `using Microsoft.Owin.Security.OAuth;` statements
- `app.UseOAuthBearerAuthentication(...)` calls (token validation)
- `app.UseOAuthAuthorizationServer(...)` calls (token issuance)
- `OAuthAuthorizationServerProvider` subclasses (custom token generation)
- `OAuthAuthorizationServerOptions` configuration (token endpoint, expiry, etc.)

Categorize findings into two buckets:
1. **Token validation only** — the API validates tokens issued elsewhere
2. **Token issuance + validation** — the API both issues and validates tokens

### Step 2: Determine Token Issuance Strategy

If the project issues tokens via `OAuthAuthorizationServerProvider`, choose a replacement:

| Strategy | When to Use |
|----------|-------------|
| Azure AD / Entra ID | Already using Azure; want managed identity provider |
| Duende IdentityServer | Need self-hosted OAuth 2.0 / OpenID Connect server |
| Custom JWT generation | Simple scenarios; use `System.IdentityModel.Tokens.Jwt` to create tokens manually |

If the project only validates tokens, skip to Step 4.

### Step 3: Update Package References

Remove OWIN OAuth packages and add the JWT Bearer package (see "Package Reference Changes" above). Update `using` directives:

```csharp
// Old
using Microsoft.Owin.Security.OAuth;

// New
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
```

### Step 4: Replace Bearer Token Validation

The OWIN bearer middleware becomes ASP.NET Core service configuration:

```csharp
// OWIN
app.UseOAuthBearerAuthentication(new OAuthBearerAuthenticationOptions
{
    AccessTokenFormat = new TicketDataFormat(new MachineKeyDataProtector("OAuth"))
});

// ASP.NET Core
services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = "https://login.microsoftonline.com/{tenant}/v2.0";
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidAudience = "{client-id}",
            ValidIssuer = "https://login.microsoftonline.com/{tenant}/v2.0"
        };
    });

// In the middleware pipeline
app.UseAuthentication();
app.UseAuthorization();
```

### Key Options Mapping

| OWIN Option | ASP.NET Core Equivalent | Notes |
|-------------|------------------------|-------|
| `OAuthBearerAuthenticationOptions` | `JwtBearerOptions` | Configured via `AddJwtBearer()` |
| `AccessTokenFormat` | `options.TokenValidationParameters` | JWT validation replaces data protection format |
| `Provider.OnValidateIdentity` | `options.Events.OnTokenValidated` | Event-based model |
| `Provider.OnRequestToken` | `options.Events.OnMessageReceived` | Customize token extraction |
| `AllowedAudiences` | `options.TokenValidationParameters.ValidAudiences` | Array of accepted audiences |

### Step 5: Migrate Token Issuance (If Applicable)

If the OWIN app used `OAuthAuthorizationServerProvider` to issue tokens, that logic must be extracted into a separate identity provider or a custom token endpoint.

**Option A: Custom JWT token endpoint** (for simple scenarios):

```csharp
app.MapPost("/token", async (LoginRequest request, IConfiguration config) =>
{
    // Validate credentials (replace with actual validation)
    if (!await ValidateCredentialsAsync(request.Username, request.Password))
        return Results.Unauthorized();

    var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config["Jwt:Key"]));
    var token = new JwtSecurityToken(
        issuer: config["Jwt:Issuer"],
        audience: config["Jwt:Audience"],
        claims: new[] { new Claim(ClaimTypes.Name, request.Username) },
        expires: DateTime.UtcNow.AddHours(1),
        signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));

    return Results.Ok(new { access_token = new JwtSecurityTokenHandler().WriteToken(token) });
});
```

**Option B: External identity provider** — migrate the token issuance logic to Duende IdentityServer or Azure AD / Entra ID and configure the API to validate tokens from that provider.

### Step 6: Update Authorization Attributes

OWIN OAuth typically used `[Authorize]` attributes that work with the OWIN authentication type. In ASP.NET Core, ensure the authorization scheme matches:

```csharp
// If using a single scheme (default), [Authorize] works as-is
[Authorize]
public class SecureController : ControllerBase { }

// If using multiple schemes, specify explicitly
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
public class ApiController : ControllerBase { }
```

### Step 7: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Test token validation with a valid JWT from the configured authority
3. Verify that expired or invalid tokens are rejected with 401
4. If token issuance was migrated, test the full flow: request token → call API with token → receive response
5. Confirm claims are correctly mapped from the JWT to `HttpContext.User`

## Troubleshooting

### "Bearer error=invalid_token"

Check that `Authority`, `ValidAudience`, and `ValidIssuer` match the token issuer's configuration. Use [jwt.ms](https://jwt.ms) to decode the token and inspect the `iss` and `aud` claims.

### No Built-In Token Endpoint

ASP.NET Core intentionally removed the built-in OAuth authorization server. For production scenarios, use Duende IdentityServer or Azure AD / Entra ID rather than hand-rolling a token endpoint. A custom endpoint (Step 5, Option A) is suitable only for simple internal scenarios.

### OWIN DataProtection Tokens Not Compatible

OWIN's default token format used machine key data protection, which is incompatible with JWT. Existing tokens issued by the OWIN server will not validate against `AddJwtBearer()`. Plan a token rollover: deploy the new JWT-based system, then expire or revoke old tokens.

### Claims Mapping Differences

ASP.NET Core maps JWT claims differently than OWIN by default. If claims like `sub` or `name` are missing, configure `TokenValidationParameters.NameClaimType` and `RoleClaimType`, or disable automatic mapping:

```csharp
JwtSecurityTokenHandler.DefaultInboundClaimTypeMap.Clear();
```
