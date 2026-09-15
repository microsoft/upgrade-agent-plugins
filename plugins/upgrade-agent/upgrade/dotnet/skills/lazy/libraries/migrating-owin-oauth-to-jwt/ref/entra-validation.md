# Entra ID token validation: OWIN to ASP.NET Core

Reference for Step 5 of `migrating-owin-oauth-to-jwt`. Read this before porting
authentication code that validates Microsoft Entra ID (Azure AD) tokens itself
rather than delegating to stock middleware.

## Contents

- [The shape being ported](#the-shape-being-ported)
- [Option and event map](#option-and-event-map)
- [Do not preserve these](#do-not-preserve-these)
- [Worked example](#worked-example)
- [Compile-guard checklist](#compile-guard-checklist)

## The shape being ported

The legacy code builds `TokenValidationParameters` by hand, calls a token handler
directly, and then reads claims off the result to authorize the caller:

```csharp
// Framework: inside AuthenticateCoreAsync, or inside a message handler.
var handler = new JsonWebTokenHandler();
var configManager = new ConfigurationManager<OpenIdConnectConfiguration>(
    metadataAddress,
    new OpenIdConnectConfigurationRetriever());

var parameters = new TokenValidationParameters
{
    ConfigurationManager = configManager,
    IssuerValidator = AadIssuerValidator.GetAadIssuerValidator(issuer).Validate,
    ValidAudience = audience,
};
parameters.EnableAadSigningKeyIssuerValidation();

var result = await handler.ValidateTokenAsync(token, parameters);
if (!result.IsValid) { /* 401 */ }

var jwt = (JsonWebToken)result.SecurityToken;
jwt.TryGetClaim("tid", out var tenantClaim);
jwt.TryGetClaim("azp", out var clientClaim);
var tenant = tenantClaim?.Value;
var client = clientClaim?.Value;
if (!IsAllowed(tenant, client)) { /* 403 */ }
```

Several parts of this flow need more than a line-by-line translation. The map
below separates middleware-owned work from application validation and authorization.

## Option and event map

| Legacy | ASP.NET Core | Notes |
|---|---|---|
| `new ConfigurationManager<OpenIdConnectConfiguration>(address, retriever)` | `options.Authority`, or `options.MetadataAddress` | The handler builds and holds one per scheme. Do not construct your own unless you need non-default behavior, and then assign `options.ConfigurationManager`. |
| `parameters.ConfigurationManager = ...` | `options.ConfigurationManager` | Assigning the `TokenValidationParameters` property is discarded whenever the scheme has a manager of its own: the handler clones the parameters per request and, when `options.ConfigurationManager` is a `BaseConfigurationManager`, overwrites the clone from it. Setting `Authority` or `MetadataAddress` creates exactly that. |
| `AadIssuerValidator.GetAadIssuerValidator(authority).Validate` | `options.TokenValidationParameters.IssuerValidator` | Same type, same delegate. Required when the authority's advertised issuer is a `{tenantid}` template — `common` and `organizations`. A single-tenant authority and `consumers` advertise concrete issuers. |
| A hand-written issuer check | `options.TokenValidationParameters.IssuerValidator` | Signature `string (string issuer, SecurityToken, TokenValidationParameters)`. Return the issuer to accept; **throw** `SecurityTokenInvalidIssuerException` to reject. A null return can leave `TokenValidationResult.IsValid` true but no `ClaimsIdentity`; the current `AddJwtBearer` pipeline then rejects authentication with 401. Do not use that downstream failure as an issuer-rejection mechanism. |
| A hand-written signing-key check | `options.TokenValidationParameters.IssuerSigningKeyValidator` | Signature `bool (SecurityKey, SecurityToken, TokenValidationParameters)`. |
| Callback casts to `JwtSecurityToken` | Shared `SecurityToken` properties, or adapted `JsonWebToken` reads | The default modern handler supplies `JsonWebToken`; the same delegate signature does not make a legacy concrete-type cast compatible. Preserve acceptance logic, not the old cast. |
| `parameters.EnableAadSigningKeyIssuerValidation()` | Same extension method, on `options.TokenValidationParameters` | Binds the signing key's issuer to the token's tenant, then invokes the captured configuration-aware validator if present; otherwise it invokes the captured plain validator. Register a plain `IssuerSigningKeyValidator` before all Entra wrappers, not between cloud-instance and issuer-validation wrappers. If both slots carry independent checks, explicitly compose them first; assigning both does not make both execute. |
| `parameters.ValidAudience = audience` | `options.Audience`, or `options.TokenValidationParameters.ValidAudience` | `options.Audience` is copied into the parameters at post-configure time, and only when `ValidAudience` is still empty. Setting both is redundant, not additive. |
| `handler.ValidateTokenAsync(token, parameters)` | The handler does this | Do not call a token handler yourself from inside a Core authentication handler. |
| Reading claims off `result.SecurityToken` | Per-scheme `MapInboundClaims = false` and `Principal.FindFirst`, or mapped-type policy reads | With mapping enabled, the policy reads the tenant URI and unchanged `azp`. Raw `TryGetClaim` reads in `OnTokenValidated` (`TokenValidatedContext`) do not change the principal. `GetClaim` throws on absence; `?.Value` cannot prevent it. |
| Claims added to the returned ticket and its identity authentication type | `OnTokenValidated` principal enrichment and `TokenValidationParameters.AuthenticationType` | Preserve downstream claim consumers and the source authentication type where relied on. A claim used as proof of authorization must be created only after the caller policy succeeds, not merely after JWT validation. |
| An allow-list decision after validation | An authorization policy | Preserves the 401 / 403 distinction. See below. |
| Writing a `WWW-Authenticate` header on 401 | `options.Challenge`, or `options.Events.OnChallenge` | The handler writes `options.Challenge` (default `Bearer`). It appends `error` and `error_description` automatically only when `IncludeErrorDetails` is on *and* authentication actually failed — a request with no token at all gets the bare challenge. `OnChallenge` can set them regardless. Set `options.Challenge` to keep a custom realm, or write the header in `OnChallenge` to reproduce it exactly. |
| Recovering from a signing-key rotation | `options.RefreshOnIssuerKeyNotFound` (default `true`) | The handler requests a metadata refresh when a key is not found, which is the behavior a per-request `ConfigurationManager` was accidentally buying at the cost of a fetch per request. |

## Do not preserve these

Faithfulness is the default in a migration. These four are the exceptions, and
each needs a line in the change summary rather than a silent fix.

**A `ConfigurationManager` constructed per request.** It re-downloads the
discovery document and the JWKS on every call, so it defeats the cache it appears
to be. One per scheme, held for the process lifetime, is both the framework
default and the correct behavior.

**`GetAadIssuerValidator(authority, httpClient, configurationManagerProvider)`
called per request with a non-null provider.** All overloads use the authority cache
unless `configurationManagerProvider` is non-null; passing null to the three-argument
overload still uses the cache. With a provider, each call creates a new validator.
Metadata-manager lifetime is then whatever the provider
returns, so the cost varies — but resolve the validator once at configuration
time either way.

**Claim reads that assume no inbound mapping.** The legacy code got raw claim
names because it called `JsonWebTokenHandler` directly, where
`DefaultMapInboundClaims` is `false`. `AddJwtBearer` sets `MapInboundClaims` to
`true`. Copying `FindFirst("tid")` across produces `null`. The mapping is
selective — `tid` and `oid` are renamed, `azp` and `appid` are not — so a check
over several claims half-works, which is harder to notice than failing outright.

**Diagnostic switches left outside a guard.** `IdentityModelEventSource.ShowPII`
and `LogCompleteSecurityArtifact` are static and process-wide. If the legacy code
set them inside a conditional-compilation guard, they stay inside it.

## Worked example

A generic API with an administrative surface. Entra-issued tokens, JWKS caching,
tenant and client allow-list, preserved 401 / 403 split, and a compile-guarded
test bypass. No part of this is specific to any one application; substitute your
own configuration keys and your own symbol name.

Keep the source's authentication scheme name; `ManagementBearer` below is illustrative.
The policy selects only that scheme and is attached only to the administrative
controller. Preserve existing explicit browser authentication defaults. If the host
previously used `AddAuthentication().AddCookie()`, the sole cookie scheme was an
**inferred** default which disappears when a second scheme is added. Change that
original registration to `AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme).AddCookie()`
(or the original custom cookie name) before adding bearer. Do not override defaults
the application explicitly configured. Keep admin routes on the Framework host until their explicit migration;
do not add this policy to the YARP fallback or to all Core controllers.

Note the change in *when* the guard is evaluated. The legacy code decided per
request; this runs once, when the scheme's options are first resolved, so a binary
built with the symbol defined would bypass validation for its whole lifetime. The
runtime assertion inside the guard is the backstop for that, and it does not
replace the guard. Options are materialized lazily, so it throws on the first
request that touches the scheme rather than at startup.

**Preserve an existing bypass only. Never add a test bypass that the source did not
have.** If there was no compile-guarded bypass, omit the example's `#if` branch and
directives and use only the normal validation from `#else`.

```csharp
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Logging;
using Microsoft.IdentityModel.Tokens;
using Microsoft.IdentityModel.Validators;

var builder = WebApplication.CreateBuilder(args);
const string bearerScheme = "ManagementBearer";

var authority = builder.Configuration["BearerAuth:Authority"]!;
var audience = builder.Configuration["BearerAuth:Audience"]!;

// Application-supplied, not a framework type: the allow-list the legacy code
// parsed out of its own configuration.
var allowedCallers = builder.Configuration
    .GetSection("BearerAuth:AllowedCallers")
    .Get<AllowedCaller[]>() ?? [];

builder.Services.AddControllers();

builder.Services
    .AddAuthentication()
    .AddJwtBearer(bearerScheme, options =>
    {
        // One ConfigurationManager per scheme, built here and held for the
        // process lifetime. This is the JWKS cache; nothing else is needed.
        options.Authority = authority;
        options.Audience = audience;
        // This policy consumes raw tid/azp names, without changing other schemes.
        options.MapInboundClaims = false;

        // Keeps the realm the Framework host advertised.
        options.Challenge =
            $"{JwtBearerDefaults.AuthenticationScheme} realm=\"admin-api\"";

#if UNSAFE_AUTH_BYPASS_FOR_TESTING
        // Compiled only into builds that opted in. The symbol name is the
        // control: it must match the source it came from, and must not appear
        // in DefineConstants for any shipping configuration.
        //
        // This throw is a backstop, not a substitute for the guard. Mirror the
        // source's own test-mode opt-in rather than inventing a key.
        if (!builder.Configuration.GetValue<bool>("BearerAuth:TestModeEnabled"))
        {
            throw new InvalidOperationException(
                "Built with UNSAFE_AUTH_BYPASS_FOR_TESTING but test mode is off.");
        }

        options.TokenValidationParameters.ValidateIssuer = false;
        options.TokenValidationParameters.ValidateAudience = false;
        options.TokenValidationParameters.ValidateLifetime = false;
        options.TokenValidationParameters.ValidateIssuerSigningKey = false;
        options.TokenValidationParameters.SignatureValidator =
            (token, _) => new JsonWebToken(token);

        // Process-global, so it stays inside the guard.
        IdentityModelEventSource.ShowPII = true;
#else
        // The real validation. This branch moves with the one above; keeping
        // only the #if body would ship the bypass as the only code path.
        options.TokenValidationParameters.IssuerValidator =
            AadIssuerValidator.GetAadIssuerValidator(authority).Validate;
        options.TokenValidationParameters.EnableAadSigningKeyIssuerValidation();
#endif
    });

builder.Services.AddAuthorizationBuilder()
    .AddPolicy("BearerApiCallers", policy =>
    {
        policy.AddAuthenticationSchemes(bearerScheme);
        policy.RequireAuthenticatedUser();
        policy.RequireAssertion(context =>
        {
            var tenant = context.User.FindFirst("tid")?.Value;
            var client = context.User.FindFirst("azp")?.Value;
            return !string.IsNullOrWhiteSpace(tenant)
                && !string.IsNullOrWhiteSpace(client)
                && allowedCallers.Any(caller =>
                    string.Equals(caller.TenantId, tenant, StringComparison.OrdinalIgnoreCase)
                    && string.Equals(caller.ClientId, client, StringComparison.OrdinalIgnoreCase));
        });
    });

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();

internal sealed record AllowedCaller(string TenantId, string ClientId);

[ApiController]
[Route("api/admin")]
[Authorize(Policy = "BearerApiCallers")]
public sealed class ManagementController : ControllerBase
{
    [HttpGet("status")]
    public IActionResult Status() => Ok();
}
```

Why the allow-list is a policy and not a `context.Fail` in `OnTokenValidated`:
`Fail` makes authentication itself fail, so the challenge path runs and the caller
gets a 401. A caller holding a valid token from an unlisted tenant proved its
identity and is not permitted, which is a 403. The split also matters to logs and
alerting — merged into 401, a targeted probe from an unlisted tenant looks
identical to an expired token.

This example preserves a source contract where a validated token with a missing
or blank allow-list claim also gets 403. `FindFirst` returns null for an absent
claim, and the policy rejects it without throwing or failing authentication.
Invalid signatures, expired tokens, and invalid audiences still fail
authentication with 401. A missing `tid` can itself fail Entra issuer validation;
the policy only runs after token validation succeeds.

Preserve any additional application token checks in `OnTokenValidated`; they
remain authentication failures when the source treats them that way. Do not move
the allow-list rejection there or change claim names used by other consumers.

## Compile-guard checklist

Run through this whenever the authentication path contains conditional
compilation.

- [ ] Every `#if`, `#elif`, `#else`, and `#endif` in the auth path is accounted for before any code moves.
- [ ] The symbol name in the ported code is character-for-character the one in the source.
- [ ] Every branch moved. In particular, the `#else` branch was not dropped as "dead code".
- [ ] The guard is still a compile-time guard. A runtime check was added inside it, not substituted for it.
- [ ] If the guard moved into cached options, a runtime assertion inside it fails closed on first scheme use (or at startup if options are explicitly resolved there).
- [ ] Process-global diagnostic switches are inside the guard, not hoisted out of it.
- [ ] The symbol is absent from `DefineConstants` in every shipping configuration — checked in the project file, `Directory.Build.props`, and CI, since any of them can define it.
- [ ] The default build was tested against a token the bypass would have accepted, and rejected it.
