---
name: migrating-owin-oauth-to-jwt
description: >
  Migrates OWIN OAuth bearer authentication and OWIN-hosted custom Entra ID
  (Azure AD) token validation to ASP.NET Core AddJwtBearer. Covers
  Microsoft.Owin.Security.OAuth, JsonWebTokenHandler, TokenValidationParameters,
  ConfigurationManager and OpenIdConnectConfiguration for JWKS caching,
  AadIssuerValidator, custom IssuerValidator and IssuerSigningKeyValidator,
  EnableAadSigningKeyIssuerValidation, tid/azp allow-lists, and exact #if
  test-bypass guard preservation. Use when replacing an OWIN bearer path,
  including custom Katana handlers. Not for a version bump that keeps OWIN,
  or apps already on ASP.NET Core configuring JWT bearer authentication.
  Not for an endpoint that trades a caller-supplied external OIDC token
  for a short-lived application credential after matching its claims
  against a stored trust policy; that is
  `migrating-federated-oidc-token-exchange`.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# OWIN OAuth to JWT Bearer Migration

## Overview

Migrate OAuth bearer token authentication from OWIN (`Microsoft.Owin.Security.OAuth`) to ASP.NET Core JWT Bearer (`Microsoft.AspNetCore.Authentication.JwtBearer`). ASP.NET Core has no built-in equivalent to OWIN's `OAuthAuthorizationServerProvider` for issuing tokens — token issuance must move to an external identity provider such as Duende IdentityServer or Azure AD / Microsoft Entra ID. Token validation is handled by `AddJwtBearer()` with `TokenValidationParameters`.

> **Related skills:** For OWIN cookie authentication migration, see `migrating-owin-cookie-auth`. For general OWIN middleware migration, see `migrating-owin-to-aspnet-core`. For Azure AD authentication library migration, see `migrating-adal-to-msal`. For interactive sign-in rather than API token validation, see `migrating-owin-openid-connect`. For an endpoint that trades a caller-supplied external OIDC token for a short-lived application credential, see `migrating-federated-oidc-token-exchange`.
>
> **Arriving from a custom Katana handler.** `migrating-owin-authentication-handler-to-core` ports the *shape* of a scheme the application wrote itself — the class, its options, and its registration — and defers the token validation inside it to this skill. Port the shape there and the validation here; Step 5 below is written for exactly that hand-off. Going the other way, a scheme that only configured stock `UseOAuthBearerAuthentication` needs no handler port and stays here.

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
- [ ] Step 5: Port Entra ID custom validation (if present)
- [ ] Step 6: Preserve compile-time guards around bypass code
- [ ] Step 7: Migrate token issuance (if applicable)
- [ ] Step 8: Update authorization attributes
- [ ] Step 9: Build and verify
```

### Step 1: Audit OWIN OAuth Usage

Scan the project for:
- `using Microsoft.Owin.Security.OAuth;` statements
- `app.UseOAuthBearerAuthentication(...)` calls (token validation)
- `app.UseOAuthAuthorizationServer(...)` calls (token issuance)
- `OAuthAuthorizationServerProvider` subclasses (custom token generation)
- `OAuthBearerAuthenticationOptions` configuration (audiences, token format, provider)
- `OAuthAuthorizationServerOptions` configuration (token endpoint, expiry, etc.)
- Validation the application performed itself: `JsonWebTokenHandler`, `JwtSecurityTokenHandler`, `TokenValidationParameters`, `ConfigurationManager<OpenIdConnectConfiguration>`, `AadIssuerValidator`
- **`#if` directives anywhere in the authentication path.** Record the exact symbol names now, before any code moves, and record every branch each directive has. A guard around authentication code is a security control: its `#if` branch typically disables validation for test builds while its `#else` branch holds the real validation, so the branches move together or not at all. Step 6 has the full rule; capture the inventory here so the decision is never made implicitly.

Categorize findings into two buckets:
1. **Token validation only** — the API validates tokens issued elsewhere
2. **Token issuance + validation** — the API both issues and validates tokens

### Step 2: Determine Token Issuance Strategy

**Stop first — is this an exchange?** If the endpoint accepts a token minted by an
external identity provider for a caller (a CI job or a workload identity), validates it
against that provider, matches its claims against a stored trust policy, and returns a
short-lived application credential, then none of the strategies below apply. That is a
token-exchange endpoint rather than an authorization server: see
`migrating-federated-oidc-token-exchange` and do not continue here.

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

For a standalone application replacing stock OWIN bearer middleware with its only
authentication scheme, use the baseline below. It registers and explicitly selects
the default scheme named `Bearer`. For custom validation or a host with other
schemes, use Step 5 instead of copying this registration first; its named scheme
and policy replace this baseline, rather than adding a second bearer registration.

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

### Step 5: Port Entra ID Custom Validation (If Present)

Skip this step only if Step 1 found none of the signals below.

**Signals that this step applies:**

- `ConfigurationManager<OpenIdConnectConfiguration>` constructed anywhere in the authentication path.
- `AadIssuerValidator`, `EnableAadSigningKeyIssuerValidation`, or `EnableEntraIdSigningKeyCloudInstanceValidation`.
- `JsonWebTokenHandler.ValidateTokenAsync` or `JwtSecurityTokenHandler.ValidateToken` called by application code rather than by middleware.
- Claims read off the token after validation to decide whether the caller is permitted — `tid`, `azp`, `appid`, `oid`.

**Stop before writing any configuration if Step 1 recorded an `#if` symbol in the authentication path.** Port the guarded branches under Step 6 first. The guarded branches are the part of this port that fails silently and dangerously, and they are decided by the code you are about to write.

Add the validator package alongside the JWT bearer package:

```xml
<PackageReference Include="Microsoft.IdentityModel.Validators" Version="{version}" />
```

Read [`ref/entra-validation.md`](ref/entra-validation.md) before porting. It carries the full option and event map, a complete worked example, and the list of things in the legacy code that must deliberately *not* be preserved. Five rules from it are restated here, because each one produces a working build that is wrong at runtime.

**The framework owns the metadata cache.** `AddJwtBearer` builds one `ConfigurationManager<OpenIdConnectConfiguration>` per scheme when options are post-configured, and keeps it for the process lifetime, so JWKS is fetched once and refreshed on a schedule. Set `options.Authority` and let it. Two consequences:

- Legacy code that constructed a manager *per request* re-downloaded the discovery document and the signing keys on every call. That is the one behavior in this step worth deliberately not preserving. Do not reproduce it to stay faithful to the original.
- Assigning `options.TokenValidationParameters.ConfigurationManager` is discarded whenever the scheme has a `BaseConfigurationManager` of its own. The handler clones the validation parameters on every request and, if `options.ConfigurationManager` is a `BaseConfigurationManager`, overwrites the clone's property with it — and setting `Authority` or `MetadataAddress` creates exactly that at post-configure time. A custom manager therefore goes on `options.ConfigurationManager`. The assignment survives only when the scheme has no such manager: no `Authority`, no `MetadataAddress`, and nothing on `options.ConfigurationManager` that derives from `BaseConfigurationManager`. Do not rely on that; it is a configuration you would not choose deliberately.

**`AadIssuerValidator` is required when the authority's advertised issuer is templated.** For `common` and `organizations`, the discovery document advertises an issuer containing the literal `{tenantid}`, and the default issuer check is an exact string comparison, so it can never match a real token's tenant-specific `iss`. `AadIssuerValidator` substitutes the token's `tid` into the template before comparing. A single-tenant authority — and `consumers` — advertises a concrete issuer, so template substitution is not what makes the validator necessary there; keep it anyway if the legacy code had it, because it also handles v1/v2 issuer skew and cloud-instance differences that a literal `ValidIssuer` does not. Resolve it once at configuration time, not per request:

```csharp
options.TokenValidationParameters.IssuerValidator =
    AadIssuerValidator.GetAadIssuerValidator(authority).Validate;
options.TokenValidationParameters.EnableAadSigningKeyIssuerValidation();
```

`GetAadIssuerValidator` caches instances by authority unless a **non-null**
`configurationManagerProvider` is supplied. The three-argument call with a null
provider still uses that cache. Resolve a provider-backed validator once, not per request.

**A validator the application wrote itself is ported, not replaced.** `AadIssuerValidator` is the right target only when the legacy code used it or hand-rolled the same tenant-substitution logic. Preserve custom acceptance logic, but adapt token-specific reads: modern `AddJwtBearer` uses `JsonWebTokenHandler` and supplies `JsonWebToken`, whereas a legacy `JwtSecurityTokenHandler` callback may cast its `SecurityToken` argument to `JwtSecurityToken`. Copying that cast causes an `InvalidCastException` and rejects otherwise-valid tokens. Prefer shared `SecurityToken` properties where sufficient; otherwise adapt to `JsonWebToken` and use nonthrowing claim reads. The delegate signatures alone do not guarantee behavioral compatibility:

| Legacy delegate | Signature | Notes |
|---|---|---|
| `TokenValidationParameters.IssuerValidator` | `string (string issuer, SecurityToken, TokenValidationParameters)` | Return the issuer to accept it; throw `SecurityTokenInvalidIssuerException` to reject. Returning `null` is not a rejection. |
| `TokenValidationParameters.IssuerSigningKeyValidator` | `bool (SecurityKey, SecurityToken, TokenValidationParameters)` | Returns false to reject. Configuration-aware validators take precedence over this slot; see the ordering rule below. |

Set a plain signing-key validator **before all** Entra signing-key wrappers, including
`EnableEntraIdSigningKeyCloudInstanceValidation` and `EnableAadSigningKeyIssuerValidation`.
Each wrapper captures both slots but invokes `IssuerSigningKeyValidatorUsingConfiguration`
in preference to the plain delegate; it does not run both. Assigning the plain delegate
between wrappers can silently skip it. If both slots have independent custom checks,
compose those checks explicitly into the configuration-aware delegate before wrapping,
and verify each rejection path.

Do not delete a custom validator on the assumption that `Authority` now covers it. `Authority` supplies the metadata, and with it the default issuer value the framework compares against — but it cannot reproduce an application-specific acceptance rule, which is what a hand-written validator encodes.

**Inbound claim mapping renames `tid` and leaves `azp` alone.** This is the failure most likely to survive review. Application code calling `JsonWebTokenHandler` directly got no claim mapping, because `JsonWebTokenHandler.DefaultMapInboundClaims` is `false`, and read `tid` straight off the token. `JwtBearerOptions.MapInboundClaims` defaults to `true`, so by the time a principal exists, `tid` has become `http://schemas.microsoft.com/identity/claims/tenantid` while `azp`, which is not in the default map, is unchanged. A port that reads `User.FindFirst("tid")` gets `null` — and an allow-list keyed on tenant then rejects every caller, or, if someone "fixes" it by dropping the tenant half of the check, accepts callers from any tenant. Choose one:

- Prefer `options.MapInboundClaims = false` for this bearer scheme after checking existing consumers. Then the policy can read `context.User.FindFirst("tid")` and `FindFirst("azp")`, as the worked example does.
- If other consumers require mapped names, keep mapping enabled and make the policy read the mapped tenant type `http://schemas.microsoft.com/identity/claims/tenantid` and unchanged `azp`. In `OnTokenValidated` (`TokenValidatedContext`), `JsonWebToken.TryGetClaim` can read raw values for additional token checks, but those local values do not flow into `context.User`. If projecting them into principal claims instead, use application-owned types, replace any token-supplied values of those types after validation, and make the policy read those same types. Never assume reading a raw token unmapped the principal.

`GetClaim` throws when a claim is absent; `?.Value` does not prevent that exception.

**401 and 403 are different outcomes, and the obvious port collapses them.** A token that fails validation is a 401. A valid token from a caller that is not on the allow-list is a 403 — the caller proved who they are and is not permitted. Putting the allow-list in `Events.OnTokenValidated` and calling `context.Fail(...)` makes authentication itself fail, so every rejection becomes a 401 and the distinction is gone from both the response and the logs. Keep token checks in the handler and express the allow-list as an authorization policy, which is registered on the service collection and **not** inside the `AddJwtBearer` options lambda:

```csharp
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("BearerApiCallers", policy =>
        policy.AddAuthenticationSchemes(bearerScheme)
            .RequireAuthenticatedUser()
            .RequireAssertion(context => IsAllowedCaller(context.User)));
```

Use the source's scheme name for `bearerScheme` and attach this policy only to the migrated admin controller or endpoints. Register the bearer scheme with parameterless `AddAuthentication()` to preserve existing **explicit** defaults. First check for a host relying on single-scheme inference: `AddAuthentication().AddCookie()` has an implicit cookie default only while it is the sole scheme. Adding bearer removes that default, and a browser challenge can throw instead of redirecting. Make the original inferred scheme explicit at its existing registration before adding bearer; do not overwrite explicit authenticate/challenge/sign-in defaults. Do not put the admin policy on every controller. Leave unmigrated routes on the Framework host, as the handler-port skill requires.

Preserve the identity the legacy handler returned, not just token validation. Application-created claims are not necessarily in the JWT: reproduce them on `context.Principal` in `OnTokenValidated` and update their consumers together. Set `TokenValidationParameters.AuthenticationType` to the source value when consumers depend on it; a named scheme does not automatically set the identity's authentication type. Publish an authorization-success marker only in the migrated filter or endpoint after the caller policy succeeds, not in `OnTokenValidated`.

If validation succeeds but `tid` or `azp` is missing or blank, preserve the source's authorization result. For a source that returns 403, reject the pair in the policy, not with `context.Fail` in `OnTokenValidated`. Do not substitute `appid` for `azp` unless the source already accepted it. The worked example keeps the validated principal's raw claim names with per-scheme `MapInboundClaims = false` and uses non-throwing `FindFirst` reads in the policy.

`migrating-owin-authentication-handler-to-core` describes the same split one layer down, where a Katana handler's single `ApplyResponseChallengeAsync` override becomes `HandleChallengeAsync` and `HandleForbiddenAsync`.

If token *issuance* also has to move — an endpoint that exchanges a caller-supplied external token for an application credential after matching it against a stored trust policy — **stop, and do not port its validation half here.** This is the Step 2 check arriving late: a hand-off from `migrating-owin-authentication-handler-to-core` enters at this step directly, so the exchange test has to be repeated here rather than assumed to have run. Validation, policy matching and issuance are one trust decision, and splitting them is the specific mistake that drops the controls: the validation half becomes a stock bearer scheme with a fixed authority, and the trust-policy match, the disclosure staging, the replay record and the bounded credential lifetime have nowhere left to live. Route the whole flow to `migrating-federated-oidc-token-exchange`. Everything above in this step applies to a handler that only *validates* an inbound Entra ID token, which is the common case.

### Step 6: Preserve Compile-Time Guards Around Bypass Code

Authentication code that ships a test-mode bypass normally guards it with a conditional-compilation symbol, so the bypass cannot exist in a build that did not opt in. **The guard is the security control**, not a build convenience. Porting the code it wraps while dropping or rewriting the guard removes that control, and nothing about the result looks wrong: it compiles, the tests pass, and the API starts accepting tokens it should reject.

Apply every rule below only to an existing source bypass. **Never add a test bypass
that the source did not have.** For such a source, use only the examples' normal
validation, without introducing a bypass symbol or branch.

- **Preserve the exact symbol name found in source.** Do not rename it, shorten it, substitute `DEBUG`, or replace it with a configuration setting. The name is the string that build pipelines, signing exclusions, and release gates search for; a renamed symbol passes all of them by not being found.
- **Port every branch of the directive as one unit** — `#if`, each `#elif`, `#else`, and `#endif` together. The `#else` branch is usually where the *real* validation lives. A port that keeps only the `#if` body therefore ships the bypass as the sole code path, which is the highest-severity outcome available in this migration and the hardest to catch in review, because what remains is short and reads like ordinary configuration.
- **Do not *replace* the compile-time guard with a runtime check.** `if (env.IsDevelopment())` is not an equivalent substitute: a compile-time guard cannot be re-enabled in a deployed binary, while a runtime check is one environment variable away from being active in production. Adding a runtime assertion *inside* the guard is the opposite case and is encouraged — see the next rule.
- **Watch for a change in when the guard is evaluated.** Legacy code usually decided per request, inside the handler. `AddJwtBearer` configuration runs once, when the scheme's options are first resolved. Moving the guarded code into the options lambda therefore widens a per-request bypass into a process-wide one. Keep the compile guard *and* add an inner runtime assertion that throws when the symbol is defined but the test-mode opt-in is off, so a binary built with the symbol by mistake fails on the first request that touches the scheme rather than serving traffic. Mirror whatever opt-in the source already has — a configuration flag, an environment check, whatever it used — and introduce a new setting only if it had none, since a key the application does not define reads as `false` and turns the assertion into an unconditional startup failure. Options are materialized lazily, so this fires on first use, not at startup; force scheme resolution during startup if you want it to fail earlier.
- **Keep process-global side effects inside the guard.** Diagnostic switches a bypass turns on — `IdentityModelEventSource.ShowPII`, `IdentityModelEventSource.LogCompleteSecurityArtifact` — are static and process-wide. Hoisting them out leaks token contents into the logs of every build.
- **Check `DefineConstants` everywhere it can be set, not only in the project file.** The symbol must be absent from every shipping configuration. A project-file check alone is necessary and not sufficient: `Directory.Build.props`, a CI variable, and a `-p:DefineConstants=...` command line can all define it with no trace in the `.csproj`. When the migration also rewrites the project file, confirm no configuration-specific symbol was hoisted into an unconditional `DefineConstants` while consolidating property groups.
- **If the guarded code cannot be ported faithfully, stop and report it.** Leaving the OWIN implementation in place is recoverable. Shipping the bypass ungated is not.

The symbol below is illustrative — use whatever name the source actually defines.

```csharp
#if UNSAFE_AUTH_BYPASS_FOR_TESTING
    // Kept verbatim: the symbol name, the disabled validations, and the
    // process-global diagnostic switches all stay inside the guard.
    // The inner runtime assertion is not a substitute for the guard — it is a
    // backstop for a binary built with the symbol by mistake, and it matters
    // more here than in the original, because this runs once when the scheme's
    // options are resolved rather than once per request. Mirror the source's
    // own test-mode opt-in; do not invent a key the application does not define.
    if (!builder.Configuration.GetValue<bool>("BearerAuth:TestModeEnabled"))
    {
        throw new InvalidOperationException(
            "Built with UNSAFE_AUTH_BYPASS_FOR_TESTING but test mode is off.");
    }

    parameters.ValidateIssuer = false;
    parameters.ValidateAudience = false;
    parameters.ValidateLifetime = false;
    parameters.ValidateIssuerSigningKey = false;
    parameters.SignatureValidator = (token, _) => new JsonWebToken(token);
    IdentityModelEventSource.ShowPII = true;
#else
    // Moves with the block above. Dropping this branch is the failure mode.
    parameters.IssuerValidator =
        AadIssuerValidator.GetAadIssuerValidator(authority).Validate;
    parameters.ValidAudience = audience;
    parameters.EnableAadSigningKeyIssuerValidation();
#endif
```

Other skills instruct removal of conditional compilation once a migration completes — `migrating-aspnet-framework-to-core` for `#if NETFRAMEWORK`, and the `dotnet-version-upgrade` consolidation phase for multi-targeting symbols. Neither applies to a guard like this one. Framework and multi-targeting symbols become dead when the old target goes away; a bypass guard stays live for as long as the bypass exists.

### Step 7: Migrate Token Issuance (If Applicable)

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

### Step 8: Update Authorization Attributes

Use the registration actually chosen in Step 4 or Step 5. A bare `[Authorize]`
is appropriate only when its default policy selects the intended scheme or the
host has effective authenticate/challenge defaults. A sole scheme may be inferred
as the default, but adding another removes that inference; do not rely on it in
a multi-scheme host.

For Step 5's caller allow-list, name the policy on the migrated admin controller.
The policy selects `bearerScheme` and evaluates the allow-list; naming only a
scheme would skip that authorization check:

```csharp
[Authorize(Policy = "BearerApiCallers")]
public class ManagementController : ControllerBase { }
```

For a bearer endpoint with no additional caller policy, an explicit
`AuthenticationSchemes` value must match the registered scheme name exactly.
Use `Bearer` only for Step 4's stock registration, not for a source-named scheme
such as `ManagementBearer`. Keep other controllers' existing policies unchanged.

### Step 9: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Test token validation with a valid JWT from the configured authority
3. Verify that expired or invalid tokens are rejected with 401
4. If token issuance was migrated, test the full flow: request token → call API with token → receive response
5. Confirm claims are correctly mapped from the JWT to `HttpContext.User`
6. If Step 5 applied, confirm a valid token from a caller outside the allow-list is rejected with **403**, not 401 — a 401 here means the allow-list was implemented as an authentication failure
7. If Step 6 applied, confirm the guard symbol is absent from `DefineConstants` in every shipping configuration, and that a default build rejects a token the bypass would have accepted
8. For custom validation, check missing and blank allow-list claims against the source's response contract; a validated token must not become a 500 or an unintended 401
9. Verify with the host's full scheme set: public routes remain public, browser cookies still authenticate browser endpoints, and a cookie alone does not satisfy the admin-bearer policy

## Troubleshooting

### "Bearer error=invalid_token"

Check that `Authority`, `ValidAudience`, and `ValidIssuer` match the token issuer's configuration. Use [jwt.ms](https://jwt.ms) to decode the token and inspect the `iss` and `aud` claims.

### No Built-In Token Endpoint

ASP.NET Core intentionally removed the built-in OAuth authorization server. For production scenarios, use Duende IdentityServer or Azure AD / Entra ID rather than hand-rolling a token endpoint. A custom endpoint (Step 7, Option A) is suitable only for simple internal scenarios.

### OWIN DataProtection Tokens Not Compatible

OWIN's default token format used machine key data protection, which is incompatible with JWT. Existing tokens issued by the OWIN server will not validate against `AddJwtBearer()`. Plan a token rollover: deploy the new JWT-based system, then expire or revoke old tokens.

### Claims Mapping Differences

ASP.NET Core maps JWT claims differently than OWIN by default. If claims like `sub` or `name` are missing, configure `TokenValidationParameters.NameClaimType` and `RoleClaimType`, or turn mapping off for the scheme:

```csharp
options.MapInboundClaims = false;
```

Prefer that over `JwtSecurityTokenHandler.DefaultInboundClaimTypeMap.Clear()`. The static map is process-global, so clearing it changes every component in the process — and it governs `JwtSecurityTokenHandler`, which is not the handler `AddJwtBearer` uses by default, so it can perturb everything else while leaving the behavior you were trying to change untouched.

### A Claim the Old Code Read Is Suddenly `null`

Most often `tid`. `JwtBearerOptions.MapInboundClaims` defaults to `true`, so `tid` arrives on the principal as `http://schemas.microsoft.com/identity/claims/tenantid`. Code that called `JsonWebTokenHandler` directly saw no mapping at all — `JsonWebTokenHandler.DefaultMapInboundClaims` is `false` — so a claim name copied straight out of the old code can resolve to nothing.

The mapping is selective: `tid` and `oid` are renamed, `azp` and `appid` are not. Set `options.MapInboundClaims = false` and use `Principal.FindFirst`, or keep mapping and make the policy read the mapped claim types. Raw `TryGetClaim` reads in `OnTokenValidated` do not change the principal consumed by the policy. A missing claim is not a mapping problem by default: `GetClaim` throws for absent claims, and a null-conditional operator cannot catch it. Preserve the source's missing-claim authorization result instead of letting the event throw.

### Metadata Is Fetched on Every Request

The scheme has its own `ConfigurationManager` being constructed per request, or one assigned to `options.TokenValidationParameters.ConfigurationManager`, which the handler overwrites from `options.ConfigurationManager` on every request. Set `options.Authority` and let the framework build and hold one, or assign `options.ConfigurationManager` directly. See Step 5.
