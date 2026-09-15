# A Worked Example

One production implementation of the exchange shape, end to end. It is **an** implementation,
not the target architecture: the type names, the folder layout, and the credential format
below belong to this application, and a different application will name every one of them
differently. What transfers is the *arrangement* — which control sits where, and which seam
crosses which boundary.

Read `SKILL.md` first. Everything here is an instance of a rule stated there.

The example is the trusted-publishing feature of the NuGet Gallery, whose source is public.
A CI job holds no API key; it presents the OIDC token its platform minted for the job to a
token endpoint, and receives a short-lived API key scoped to the package it is allowed to
publish.

## The starting state

### The compile island

The exchange lives in `NuGetGallery.Services`, a project that is **already SDK-style** and
already multi-targets:

```xml
<PropertyGroup>
  <TargetFrameworks>net472;netstandard2.1</TargetFrameworks>
</PropertyGroup>

<ItemGroup Condition="'$(TargetFramework)' == 'netstandard2.1'">
  <Compile Remove="AccountManagement\*.cs" />
  <Compile Remove="Authentication\**\*.cs" />
  <Compile Remove="Configuration\**\*.cs" />
  <!-- ...and a dozen more folders... -->
</ItemGroup>

<ItemGroup>
  <PackageReference Include="Microsoft.Identity.Web" />
  <PackageReference Include="System.Text.Json" />
</ItemGroup>
```

This is the recognition signal from step 2 of `SKILL.md`, and it is exactly the trap
described there. Three observations, in the order that matters:

1. The exchange is under `Authentication\Federated\`, so the folder-wide glob excludes it
   from the portable target. It **looks** like Framework-only code.
2. But the glob is folder-wide. It also catches the genuinely OWIN-bound neighbors in the
   same folder tree — the API-key authentication handler, the local user authenticator —
   which is a sufficient reason for the exclusion to exist without the exchange being
   Framework-bound at all.
3. `Microsoft.Identity.Web` — the package the Entra validator needs — is referenced
   **unconditionally**, for both targets. The security core was already portable when the
   exclusion was written.

The verdict for most of the exchange is therefore *portable*, and the migration is mostly a
question of which neighbors have to come with it.

### What actually blocks it

`FederatedCredentialService` depends on `IGalleryConfigurationService` from `Configuration\`,
which the **same item group** excludes. And `FederatedCredentialConfiguration` binds through
a `TypeConverter` from `NuGet.Services.Configuration`, whose `ProjectReference` is itself
inside the `net472`-only item group.

`IAuditingService` is the instructive contrast, and the reason to check the closure rather
than infer it. It is *not* excluded: it lives in a different project
(`NuGetGallery.Core\Auditing\`, which `NuGetGallery.Services` references unconditionally),
and that project curates its portable surface **per file** rather than per folder — it
removes `AuditingService.cs`, `CloudAuditingService.cs`, and `FileSystemAuditingService.cs`
while keeping `IAuditingService.cs`. The abstraction is already available on the portable
target and only the concrete implementations need attention. Reading the closure off the
folder globs would have recorded a blocker that does not exist.

So removing `<Compile Remove="Authentication\**\*.cs" />` does not produce a working build.
It produces the next layer of the closure. This is the "portable, blocked" row of the
classification table, and it is the honest cost of the migration — not the exchange logic,
which needs no rewriting, but its dependency closure, which needs its own passes.

## The seams

### Hosting

`TokenApiController` derives from the application's `AppController`, which is
`System.Web.Mvc`. It returns `ActionResult`. That is the ordinary controller port — except
for one method:

```csharp
public class TokenApiController : AppController
{
    private const string BearerScheme = "Bearer";

    [HttpPost]
    [ActionName(RouteName.CreateToken)]
    [AllowAnonymous] // authentication is handled inside the action
    public async Task<ActionResult> CreateToken(CreateTokenRequest request)
    {
        // ... bearer token extracted from the Authorization header ...

        if (User.Identity.IsAuthenticated)
        {
            return UnauthorizedJson("Only Bearer authentication is accepted.");
        }

        // ... content-type, user-agent and body validation, then the exchange ...
    }

    private JsonResult UnauthorizedJson(string errorMessage)
    {
        // Add the "Federated" challenge so the other authentication providers
        // (such as the default sign-in) are not triggered.
        OwinContext.Authentication.Challenge(AuthenticationTypes.Federated);

        Response.Headers["WWW-Authenticate"] = BearerScheme;

        return ErrorJson(HttpStatusCode.Unauthorized, errorMessage);
    }
}
```

Two controls live in this one controller, and a mechanical port drops both.

The `Challenge` call issues no challenge anyone acts on. It exists to *claim* the challenge
for a scheme that does nothing, so the cookie sign-in scheme does not redirect an API client
to a login page. It has no ASP.NET Core equivalent and needs none — on the new host, write
the 401, the `WWW-Authenticate` header, and the JSON body directly. Drop the line and change
nothing else, and the endpoint starts answering unauthorized API requests with a 302.

`[AllowAnonymous]` and the `User.Identity.IsAuthenticated` rejection are the second control,
and they are a pair. The endpoint authenticates the request *itself*, from the presented
token, and refuses one that arrived carrying an ambient session instead.

**Do not port the challenge by naming a scheme in the endpoint's authorization metadata.**
It is the obvious-looking translation and it breaks the pair.
`[Authorize(AuthenticationSchemes = "Federated")]` with a challenge-only scheme fails
authorization, so the action never runs and no exchange is possible. With a validating
scheme it populates `User`, so a valid exchange is rejected as an ambient session. Keeping
`[AllowAnonymous]` beside the metadata is not a safe middle either: ASP.NET Core
authenticates the named schemes *before* it honours `[AllowAnonymous]`, and when none of
them succeeds it assigns an empty principal. `User.Identity.IsAuthenticated` then reads
`false` even for a caller who presented a valid session cookie, and the rejection above
silently stops firing.

### The header collection

`NameValueCollection` appears in the interface, not just at the boundary:

```csharp
public interface IFederatedCredentialService
{
    Task<GenerateApiKeyResult> GenerateApiKeyAsync(
        string username,
        string bearerToken,
        NameValueCollection requestHeaders);
}
```

It reaches all the way to `FederatedCredentialPolicyEvaluator.GetMatchingPolicyAsync`, where
supplementary validators read from it. `NameValueCollection` exists on modern .NET, so
**this compiles unchanged and produces no diagnostic** — which is why it is still there.
It is an adapter decision, not a compile break, and adapter decisions that produce no error
are the ones a migration skips.

## The arrangement

### Ordering: validate, then match

```csharp
public class FederatedCredentialPolicyEvaluator
{
    public async Task<OidcTokenEvaluationResult> GetMatchingPolicyAsync(
        IReadOnlyCollection<FederatedCredentialPolicy> policies,
        string bearerToken,
        NameValueCollection requestHeaders)
    {
        // perform basic validations not specific to any federated credential policy
        var context = await ValidateJwtByIssuerAsync(bearerToken);

        // Whether or not we have detected a problem already, pass the information to all
        // additional validators. This allows custom logic to execute but will not override
        // any initial failed validation result.
        await ExecuteAdditionalValidatorsAsync(requestHeaders, context);

        var externalCredentialAudit = context.CreateAuditRecord();
        await AuditExternalCredentialAsync(externalCredentialAudit);

        if (context.Error is not null)
        {
            return OidcTokenEvaluationResult.BadToken(context.Error);
        }

        // Ordered by creation date, so older policy results are preferred.
        StringBuilder disclosableErrors = new();

        foreach (var policy in policies.OrderBy(x => x.Created))
        {
            var result = await EvaluatePolicyAsync(policy, context);
            var success = result.Type == FederatedCredentialPolicyResultType.Success;

            // Every comparison is audited, matched or not, using the record created above.
            await AuditPolicyComparisonAsync(externalCredentialAudit, policy, success);

            if (success)
            {
                // ... build the credential and return NewMatchedPolicy
            }
            else if (result.IsErrorDisclosable && result.Error != null)
            {
                // Combine all disclosable errors to provide more context to the user.
                // ... the original also normalises separators between accumulated errors
                disclosableErrors.Append(result.Error);
            }
        }

        // The loop returns only on success. A non-match and a rejection both continue, and
        // what the caller finally sees is the accumulated disclosable text — never the
        // non-disclosable errors, and never a count of how many policies were tried.
        string? userError = disclosableErrors.Length > 0 ? disclosableErrors.ToString() : null;
        return OidcTokenEvaluationResult.NoMatchingPolicy(userError);
    }

    private async Task<FederatedCredentialPolicyResult> EvaluatePolicyAsync(
        FederatedCredentialPolicy policy, TokenContext context)
    {
        // We do not want to fail the entire evaluation if a single policy fails
        FederatedCredentialPolicyResult result;
        try
        {
            result = await context.TokenValidator!.EvaluatePolicyAsync(policy, context.Jwt!);
        }
        catch (Exception ex)
        {
            result = FederatedCredentialPolicyResult.Unauthorized($"{ex.GetType().FullName}: {ex.Message}");
        }

        // Every verdict is logged except NotApplicable, which is the only operational
        // difference between it and a non-disclosable Unauthorized.
        if (result.Type != FederatedCredentialPolicyResultType.NotApplicable)
        {
            _logger.LogInformation(
                "Evaluated policy key {PolicyKey} of type {PolicyType}. Result type: {ResultType}. Reason: {Reason}. Disclosable {Disclosable}",
                policy.Key,
                policy.Type,
                result.Type,
                result.Error,
                result.IsErrorDisclosable);
        }

        return result;
    }
}
```

Three rules from `SKILL.md` are visible in that method:

- **Claim matching is gated on validation.** The `foreach` is unreachable while
  `context.Error` is set.
- **Supplementary validators run regardless, and cannot clear a failure.** They execute
  before the error check, deliberately, so their own findings are recorded — but the check
  that follows reads the *accumulated* error, so a supplementary success cannot resurrect a
  failed token.
- **Policies are evaluated oldest first**, so the match is deterministic when a user owns
  more than one policy that could match.

### The store is read before validation, and that is fine

```csharp
public class FederatedCredentialService
{
    public async Task<GenerateApiKeyResult> GenerateApiKeyAsync(
        string username,
        string bearerToken,
        NameValueCollection requestHeaders)
    {
        var currentUser = _userService.FindByUsername(username, includeDeleted: false);
        if (currentUser is null)
        {
            return NoMatchingPolicy(username);
        }

        var policies = _repository.GetPoliciesCreatedByUser(currentUser.Key);
        var policyEvaluation = await _evaluator.GetMatchingPolicyAsync(
            policies, bearerToken, requestHeaders);

        // ...

        // perform validations after the policy evaluation to avoid leaking
        // information about the related users
        var currentUserError = ValidateCurrentUser(currentUser);
        if (currentUserError != null)
        {
            return currentUserError;
        }

        var packageOwner = _userService.FindByKey(
            policyEvaluation.MatchedPolicy.PackageOwnerUserKey);
        policyEvaluation.MatchedPolicy.PackageOwner = packageOwner;
        var packageOwnerError = ValidatePackageOwner(packageOwner);
        if (packageOwnerError != null)
        {
            return packageOwnerError;
        }

        var apiKeyCredential = _credentialBuilder.CreateShortLivedApiKey(
            _configuration.ShortLivedApiKeyDuration,
            policyEvaluation.MatchedPolicy,
            _galleryConfigurationService.Current.Environment,
            out var plaintextApiKey);

        if (!_credentialBuilder.VerifyScopes(currentUser, apiKeyCredential.Scopes))
        {
            return GenerateApiKeyResult.BadRequest(
                $"The scopes on the generated API key are not valid. " +
                $"Confirm that you still have permissions to operate on behalf of package owner '{packageOwner.Username}'.");
        }

        return await SaveAndRejectReplayAsync(currentUser, policyEvaluation, apiKeyCredential)
            ?? GenerateApiKeyResult.Created(plaintextApiKey, apiKeyCredential.Expires!.Value);
    }
}
```

Note the order carefully, because it is counter-intuitive and a plausible "fix" breaks it:

- `GetPoliciesCreatedByUser` runs **before** any signature validation. The lookup key is the
  `username` from the request body, not from the token, so no untrusted token claim reaches
  the store. Reordering this to "validate first" is a refactor that changes nothing and
  risks the ordering that does matter.
- `ValidateCurrentUser` runs **after** matching, with the reason stated in the comment.
  Moving it earlier — which looks like a cheap early-out — turns the endpoint into an
  account-state oracle.
- **Two accounts are validated, not one.** `currentUser` is the caller who owns the policy.
  `PackageOwner` is the account the credential will act *for*, it is a different row, and it
  is frequently an organization rather than the caller. It is re-read by key and state-checked
  on its own. `VerifyScopes` below does not cover this: it checks the permission
  *relationship* between the two accounts, so an administrator in good standing still passes
  it for an organization that is deleted, locked, or unconfirmed. Drop the
  `ValidatePackageOwner` block and the endpoint issues credentials on behalf of accounts the
  original refuses.
- The same two lines are also load-bearing for what follows. Assigning
  `MatchedPolicy.PackageOwner` populates the navigation property `CreateShortLivedApiKey`
  reads, and the scope-failure message names `packageOwner.Username`.
- The credential's lifetime comes from `ShortLivedApiKeyDuration`, and its scopes are
  re-verified against the caller's *current* permissions after the policy matched.

### Replay: persistence, not inspection

```csharp
public class FederatedCredentialService
{
    private async Task<GenerateApiKeyResult?> SaveAndRejectReplayAsync(
        User currentUser,
        OidcTokenEvaluationResult evaluation,
        Credential apiKeyCredential)
    {
        evaluation.MatchedPolicy.LastMatched = _dateTimeProvider.UtcNow;

        await _repository.SaveFederatedCredentialAsync(evaluation.FederatedCredential, saveChanges: false);

        try
        {
            await _authenticationService.AddCredential(currentUser, apiKeyCredential);
        }
        catch (DataException ex) when (ex.IsSqlUniqueConstraintViolation())
        {
            await _auditingService.SaveAuditRecordAsync(FederatedCredentialPolicyAuditRecord.RejectReplay(
                evaluation.MatchedPolicy,
                evaluation.FederatedCredential));

            return GenerateApiKeyResult.Unauthorized(
                "This bearer token has already been used. A new bearer token must be used for each request.");
        }

        await _auditingService.SaveAuditRecordAsync(FederatedCredentialPolicyAuditRecord.ExchangeForApiKey(
            evaluation.MatchedPolicy,
            evaluation.FederatedCredential,
            apiKeyCredential));

        return null;
    }
}
```

The token identifier — `jti` for the CI issuers, `uti` for Entra — is stored on the
federated credential row, and reuse is caught by a **database uniqueness constraint**, not
by a code path that inspects the claim. An agent that "simplifies" this into a check that
the identifier claim is present removes replay prevention entirely while leaving something
that looks like it.

### The lifetime ceiling

The issued credential has a lifetime of its own, independent of the token that bought it —
which is the point, and also why it is the last remaining bound on the exchange. Do not
assume it is the *longer* of the two: a CI job's token may be minutes old, while an Entra
access token commonly lasts an hour or more and can easily outlive the key it buys. What
matters is that the two are unrelated, so the inbound token's expiry constrains nothing
about the outbound credential. It is enforced twice: a configured duration, and a literal
the configuration cannot exceed.

```csharp
public class CredentialBuilder
{
    public Credential CreateShortLivedApiKey(
        TimeSpan expiration,
        FederatedCredentialPolicy policy,
        string galleryEnvironment,
        out string plaintextApiKey)
    {
        if (policy.PackageOwner is null)
        {
            throw new ArgumentException($"The {nameof(policy.PackageOwner)} property on the policy must not be null.");
        }

        // The ceiling is a literal in code, not a configuration value. A config setting is a
        // knob someone can turn; this is the bound they cannot turn past. Note that the
        // lower bound is guarded too — a non-positive expiration is rejected rather than
        // normalized, because "expires immediately" and "never expires" are one typo apart.
        if (expiration <= TimeSpan.Zero || expiration > TimeSpan.FromHours(1))
        {
            throw new ArgumentOutOfRangeException(nameof(expiration));
        }

        var apiKey = ApiKeyV5.Create(
            allocationTime,
            ApiKeyV5.GetEnvironment(galleryEnvironment),
            policy.PackageOwnerUserKey,
            ApiKeyV5.KnownApiKeyTypes.ShortLived,
            expiration);

        // ... hash, attach the policy, and copy the policy's scopes onto the credential
    }
}
```

This is the easiest control in the whole exchange to lose, because losing it changes
nothing observable. A rewrite that reads the configured duration and passes it straight to
the credential builder works, passes every test, and issues whatever the configuration says
— including a value someone raises later for a legitimate-sounding reason, with no
remaining bound. Two properties are worth stating separately, because a port tends to keep
the first and drop the second:

- The **configured** duration is what the exchange asks for.
- The **ceiling** is what the credential type will accept, and it lives here rather than
  alongside the configuration precisely so that changing configuration cannot move it.

Moving the bound into `appsettings`, or into a constant that the configuration overrides,
looks like a tidying refactor and removes the guarantee entirely.

### Entra: assertion claims and a tenant allow-list

The class is `EntraIdTokenPolicyValidator`, in a file named `EntraIdTokenValidator.cs` — the
names differ, which matters if you are searching by file name.

```csharp
public class EntraIdTokenPolicyValidator : TokenPolicyValidator
{
    public const string Authority = "login.microsoftonline.com";
    public const string Issuer = $"https://{Authority}/common/v2.0";

    public EntraIdTokenPolicyValidator(
        ConfigurationManager<OpenIdConnectConfiguration> oidcConfigManager,
        IFederatedCredentialConfiguration configuration,
        IFeatureFlagService featureFlagService,
        JsonWebTokenHandler jsonWebTokenHandler)
        : base(oidcConfigManager, configuration, jsonWebTokenHandler, "uti")
    {
        _featureFlagService = featureFlagService ?? throw new ArgumentNullException(nameof(featureFlagService));
    }

    public override async Task<TokenValidationResult> ValidateTokenAsync(JsonWebToken jwt)
    {
        var tokenValidationParameters = new TokenValidationParameters
        {
            IssuerValidator = AadIssuerValidator.GetAadIssuerValidator(Issuer).Validate,
            ValidAudience = _configuration.EntraIdAudience,
            ConfigurationManager = _oidcConfigManager,
        };

        tokenValidationParameters.EnableAadSigningKeyIssuerValidation();

        return await _jsonWebTokenHandler.ValidateTokenAsync(jwt, tokenValidationParameters);
    }

    public override Task<FederatedCredentialPolicyResult> EvaluatePolicyAsync(
        FederatedCredentialPolicy policy,
        JsonWebToken jwt)
    {
        // The same applicability guard as the GitHub validator, with a different type and a
        // different return shape — this method is synchronous and wraps its result.
        if (policy.Type != FederatedCredentialType.EntraIdServicePrincipal)
        {
            return Task.FromResult(FederatedCredentialPolicyResult.NotApplicable);
        }

        if (EvaluateEntraIdServicePrincipal(policy, jwt) is string error)
        {
            return Task.FromResult(FederatedCredentialPolicyResult.Unauthorized(error));
        }

        return Task.FromResult(FederatedCredentialPolicyResult.Success);
    }

    private string? EvaluateEntraIdServicePrincipal(FederatedCredentialPolicy policy, JsonWebToken jwt)
    {
        const string ClientCredentialTypeClaim = "azpacr";
        const string ClientCertificateType = "2";
        const string IdentityTypeClaim = "idtyp";
        const string AppIdentityType = "app";
        const string VersionClaim = "ver";
        const string Version2 = "2.0";

        // An application-owned gate on issuance, checked before any claim is read, so a
        // disabled owner never reaches the claim rules at all. This is the only validator
        // that consults the flag — the GitHub one injects it and never calls it.
        if (!_featureFlagService.CanUseFederatedCredentials(policy.PackageOwner))
        {
            return $"The package owner '{policy.PackageOwner.Username}' is not enabled to use federated credentials.";
        }

        string? error = TryGetRequiredClaim(jwt, ClaimConstants.Tid, out var tid);
        if (error != null)
        {
            return error;
        }

        error = TryGetRequiredClaim(jwt, ClaimConstants.Oid, out var oid);
        if (error != null)
        {
            return error;
        }

        error = TryGetRequiredClaim(jwt, ClientCredentialTypeClaim, out var azpacr);
        if (error != null)
        {
            return error;
        }

        if (azpacr != ClientCertificateType)
        {
            return $"The JSON web token must have an {ClientCredentialTypeClaim} claim with a value of {ClientCertificateType}.";
        }

        error = TryGetRequiredClaim(jwt, IdentityTypeClaim, out var idtyp);
        if (error != null)
        {
            return error;
        }

        if (idtyp != AppIdentityType)
        {
            return $"The JSON web token must have an {IdentityTypeClaim} claim with a value of {AppIdentityType}.";
        }

        error = TryGetRequiredClaim(jwt, VersionClaim, out var ver);
        if (error != null)
        {
            return error;
        }

        // The claim vocabulary asserted above is the v2.0 vocabulary. A v1.0 token carries
        // different claims, so accepting one would mean asserting nothing.
        if (ver != Version2)
        {
            return $"The JSON web token must have a {VersionClaim} claim with a value of {Version2}.";
        }

        // For an application token the subject IS the service principal object ID. If they
        // disagree, the token is not what the rest of this method assumes it is.
        if (jwt.Subject != oid)
        {
            return $"The JSON web token {ClaimConstants.Sub} claim must match the {ClaimConstants.Oid} claim.";
        }

        var criteria = JsonSerializer.Deserialize<EntraIdServicePrincipalCriteria>(policy.Criteria);

        if (string.IsNullOrWhiteSpace(tid) || !Guid.TryParse(tid, out var parsedTid) || parsedTid != criteria!.TenantId)
        {
            return $"The JSON web token must have a {ClaimConstants.Tid} claim that matches the policy.";
        }

        if (!IsTenantAllowed(parsedTid))
        {
            return "The tenant ID in the JSON web token is not in allow list.";
        }

        // The identity match. Without this the method authorizes a TENANT, not a service
        // principal: every certificate-backed application in an allowed tenant would satisfy
        // every policy scoped to that tenant.
        if (string.IsNullOrWhiteSpace(oid) || !Guid.TryParse(oid, out var parsedOid) || parsedOid != criteria.ObjectId)
        {
            return $"The JSON web token must have a {ClaimConstants.Oid} claim that matches the policy.";
        }

        return null;
    }
}
```

Everything here that could be mistaken for boilerplate is a control:

- **The `policy.Type` guard is the per-issuer separation itself.** The evaluator selects one
  validator from the token's issuer authority, then offers that validator every policy the
  caller owns, oldest first, returning only on success. `NotApplicable` is therefore
  load-bearing rather than defensive — it is how a GitHub policy fails to be judged by
  Entra's claim rules. It is also the control most at risk from the obvious tidy-up: merging
  three validators into one parameterized class, or "simplifying" a guard that appears to
  reject nothing, produces code that still authenticates every legitimate caller while
  reading the wrong policy's criteria. `NotApplicable` is a third verdict, distinct from both
  success and rejection — but be precise about what collapsing it into a rejection costs,
  because the obvious guess is wrong and *matching is not what changes*. The loop continues
  past a rejection exactly as it continues past `NotApplicable`; `Unauthorized` is
  non-disclosable unless the caller asks otherwise; and a policy belonging to another issuer
  was never going to match this token anyway, so a later policy that does match still
  succeeds. What the substitution actually costs is the diagnostic record:
  `EvaluatePolicyAsync` logs every verdict *except* `NotApplicable`, so each routine "not
  mine to judge" comparison becomes a logged authorization failure and an operator reading
  those logs sees rejections that never happened. Removing the guard outright is the louder
  fault — the wrong policy's criteria get read, and this issuer's disclosable required-claim
  errors then describe a policy that was never its to judge.
- `"uti"` in the base call — Entra's token identifier, replacing the default `jti`. Replay
  prevention for this issuer depends on that one argument.
- **The feature-flag gate runs before any claim is read.** It is an application-owned kill
  switch on issuance for a given owner, and exactly the kind of parameter a port carries over
  into the constructor and then never calls — the dependency still resolves, the code still
  compiles, and the switch silently stops working. That failure is not hypothetical here:
  this is the only validator that consults the flag, and the GitHub validator injects the
  same service, null-checks it, and never reads it. Verify the call site, not the constructor
  parameter.
- `AadIssuerValidator` plus `EnableAadSigningKeyIssuerValidation()` — the configured issuer
  is the multi-tenant `common` endpoint, so a plain string comparison would be wrong in both
  directions. See [providers.md](providers.md).
- `azpacr` and `idtyp` are **asserted**, not matched against the policy. They restrict the
  credential type to a certificate-backed or managed-identity application token. Nothing in
  the trust policy mentions them, so a migration that ports "the claims the policy uses"
  drops them and quietly begins accepting weaker credentials.
- `ver` and the `sub == oid` check are asserted for the same reason: they establish that the
  token really is a v2.0 application token, which is what makes the rest of the assertions
  mean anything.
- **`tid` and `oid` are both matched against the policy.** A tenant is not an identity.
  Dropping the `oid` match is the single most damaging edit available here, because the
  method still returns success on every legitimate token, and an application that uses one
  service principal per tenant passes all of its own tests.
- `IsTenantAllowed` is a second, application-owned gate on top of the tenant match — the
  policy says which tenant, the allow-list says which tenants are permitted at all.

### GitHub Actions: the disclosure matrix and first-use binding

```csharp
public class GitHubTokenPolicyValidator : TokenPolicyValidator
{
    public override async Task<FederatedCredentialPolicyResult> EvaluatePolicyAsync(
        FederatedCredentialPolicy policy,
        JsonWebToken jwt)
    {
        // Applicability, before anything is read from the token. This validator was already
        // selected from the token's issuer; what varies here is the policy. NotApplicable is
        // not a rejection — it means "not this policy", and the evaluator tries the next one.
        if (policy.Type != FederatedCredentialType.GitHubActions)
        {
            return FederatedCredentialPolicyResult.NotApplicable;
        }

        // Check for required claims — disclosable: the token is malformed for its own issuer.
        string? error = TryGetRequiredClaim(jwt, RepositoryClaim, out _);
        if (error != null)
        {
            return FederatedCredentialPolicyResult.Unauthorized(error, isErrorDisclosable: true);
        }

        error = TryGetRequiredClaim(jwt, RepositoryOwnerClaim, out _);
        if (error != null)
        {
            return FederatedCredentialPolicyResult.Unauthorized(error, isErrorDisclosable: true);
        }

        error = TryGetRequiredClaim(jwt, RepositoryOwnerIdClaim, out string repositoryOwnerId);
        if (error != null)
        {
            return FederatedCredentialPolicyResult.Unauthorized(error, isErrorDisclosable: true);
        }

        error = TryGetRequiredClaim(jwt, RepositoryIdClaim, out string repositoryId);
        if (error != null)
        {
            return FederatedCredentialPolicyResult.Unauthorized(error, isErrorDisclosable: true);
        }

        error = TryGetRequiredClaim(jwt, EventNameClaim, out string eventName);
        if (error != null)
        {
            return FederatedCredentialPolicyResult.Unauthorized(error, isErrorDisclosable: true);
        }

        var criteria = GitHubCriteria.FromDatabaseJson(policy.Criteria);

        // Ownership — NOT disclosable: this is the enumeration surface.
        error = ValidateClaimExactMatch(jwt, RepositoryOwnerClaim, criteria.RepositoryOwner, StringComparison.OrdinalIgnoreCase);
        if (error != null)
        {
            return FederatedCredentialPolicyResult.Unauthorized(error);
        }

        // The repository claim is "{owner}/{repo}", so it must be matched against the pair.
        // Matching only the owner would authorize every repository the owner has.
        error = ValidateClaimExactMatch(jwt, RepositoryClaim, $"{criteria.RepositoryOwner}/{criteria.Repository}", StringComparison.OrdinalIgnoreCase);
        if (error != null)
        {
            return FederatedCredentialPolicyResult.Unauthorized(error);
        }

        if (!criteria.IsPermanentlyEnabled)
        {
            // The first-use window is bounded, and an absent date is treated as expired
            // rather than as unbounded. Note the polarity: this fails closed.
            if (!criteria.ValidateByDate.HasValue || DateTimeOffset.UtcNow > criteria.ValidateByDate.Value)
            {
                return FederatedCredentialPolicyResult.Unauthorized(
                    $"The policy '{policy.PolicyName}' has expired. Sign in and renew the trust policy on the Trusted Publishing page.",
                    isErrorDisclosable: true);
            }

            // First use: bind the immutable IDs to the policy authored against mutable names.
            criteria.RepositoryOwnerId = repositoryOwnerId;
            criteria.RepositoryId = repositoryId;
            criteria.ValidateByDate = null;
            policy.Criteria = criteria.ToDatabaseJson();

            try
            {
                await _federatedCredentialRepository.SavePoliciesAsync();
                await _auditingService.SaveAuditRecordAsync(
                    FederatedCredentialPolicyAuditRecord.FirstUseUpdate(policy));
            }
            catch (DbUpdateConcurrencyException)
            {
                // Two runs of the same workflow can call concurrently on first use.
                var updatedPolicy = _federatedCredentialRepository.GetPolicyByKey(policy.Key);
                if (updatedPolicy == null)
                {
                    return FederatedCredentialPolicyResult.Unauthorized(
                        "The policy was not found after concurrent first use.");
                }

                var updatedCriteria = GitHubCriteria.FromDatabaseJson(updatedPolicy.Criteria);
                if (!string.Equals(updatedCriteria.RepositoryOwnerId, criteria.RepositoryOwnerId, StringComparison.Ordinal)
                    || !string.Equals(updatedCriteria.RepositoryId, criteria.RepositoryId, StringComparison.Ordinal))
                {
                    return FederatedCredentialPolicyResult.Unauthorized(
                        "The policy was updated with different repository owner/repo IDs during concurrent first use.");
                }
            }
        }
        else
        {
            // Note that ID comparisons are case-sensitive.
            error = ValidateClaimExactMatch(jwt, RepositoryOwnerIdClaim, criteria.RepositoryOwnerId!, StringComparison.Ordinal);
            if (error != null)
            {
                return FederatedCredentialPolicyResult.Unauthorized(error);
            }

            error = ValidateClaimExactMatch(jwt, RepositoryIdClaim, criteria.RepositoryId!, StringComparison.Ordinal);
            if (error != null)
            {
                return FederatedCredentialPolicyResult.Unauthorized(error);
            }
        }

        // IMPORTANT. By now we validated repo owner and repo. Including IDs.
        // From now on we can report errors as disclosable.

        if (_configuration.BannedGitHubActionsEvents is not null
            && _configuration.BannedGitHubActionsEvents.Contains(eventName, StringComparer.OrdinalIgnoreCase))
        {
            return FederatedCredentialPolicyResult.Unauthorized(
                $"The GitHub Actions event '{eventName}' is not allowed.",
                isErrorDisclosable: true);
        }

        // The claim is "{owner}/{repo}/.github/workflows/release.yml@refs/heads/main", so it
        // is parsed, not compared. An exact-match port of this would never succeed.
        error = TryGetRequiredClaim(jwt, JobWorkflowRefClaim, out string workflowRef);
        if (error != null)
        {
            return FederatedCredentialPolicyResult.Unauthorized(error, isErrorDisclosable: true);
        }

        string expectedPrefix = $"{criteria.RepositoryOwner}/{criteria.Repository}/.github/workflows/";
        int suffixIndex = expectedPrefix.Length < workflowRef.Length ? workflowRef.IndexOf('@', expectedPrefix.Length) : -1;
        if (suffixIndex < 0 || !workflowRef.StartsWith(expectedPrefix, StringComparison.OrdinalIgnoreCase))
        {
            return FederatedCredentialPolicyResult.Unauthorized(
                $"Claim '{JobWorkflowRefClaim}' has value '{workflowRef}' which does not start with {expectedPrefix}.",
                isErrorDisclosable: true);
        }

        string workflowFile = workflowRef[expectedPrefix.Length..suffixIndex];
        if (!string.Equals(workflowFile, criteria.WorkflowFile, StringComparison.OrdinalIgnoreCase))
        {
            return FederatedCredentialPolicyResult.Unauthorized(
                $"Workflow mismatch for policy '{policy.PolicyName}': expected '{criteria.WorkflowFile}', actual '{workflowFile}'",
                isErrorDisclosable: true);
        }

        // Environment is matched only when the policy asks for it — but an absent claim
        // becomes the empty string and then MISMATCHES, rather than skipping the check.
        if (!string.IsNullOrWhiteSpace(criteria.Environment))
        {
            if (TryGetRequiredClaim(jwt, EnvironmentClaim, out string environment) != null)
            {
                environment = string.Empty;
            }

            if (!string.Equals(environment, criteria.Environment, StringComparison.OrdinalIgnoreCase))
            {
                return FederatedCredentialPolicyResult.Unauthorized(
                    $"Environment mismatch for policy '{policy.PolicyName}': expected '{criteria.Environment}', actual '{environment}'",
                    isErrorDisclosable: true);
            }
        }

        return FederatedCredentialPolicyResult.Success;
    }
}
```

This one method carries five of the checklist rows, and it is the reason disclosure is a
matrix rather than a rule:

- **Required-claim failures are disclosable, and they happen first** — before ownership is
  established. The tempting summary "nothing is disclosable until ownership is proven" is
  wrong, and a test asserting it would fail correct code.
- **Ownership mismatches are the only non-disclosable category.** They are what an attacker
  would use to enumerate which owners have trust policies.
- **Owner and repository are both matched, and both IDs are bound.** The `repository` claim
  is `{owner}/{repo}`, so matching the owner alone authorizes every repository that owner
  has. Binding only the owner ID leaves the repository half of the policy resting on a name
  that can be transferred or renamed — which is the entire reason the binding exists.
- After the marked comment, everything is disclosable again — the caller has proven it knows
  the owner and repository. The comment is only true because both matches ran above it.
- **The deny-list is checked after a full ownership match.** A banned trigger rejects a
  token whose every other claim matched the policy exactly. It is the last thing a rewrite
  would think to keep and the thing most worth keeping.
- **Comparison semantics are mixed on purpose.** Names compare with
  `OrdinalIgnoreCase`; the immutable numeric identifiers compare with `Ordinal`, and the
  source says so in a comment because it looks like an inconsistency. Normalizing the two is
  an authorization change.
- **The first-use window fails closed.** `!HasValue ||` past the date, both rejected. A port
  that writes the intuitive `criteria.ValidateByDate < DateTimeOffset.UtcNow` inverts the
  null case — in C# that comparison is `false` when the value is null — and turns "never
  bound" into "always allowed" while every ordinary policy keeps working.
- **`job_workflow_ref` is parsed, not compared.** The claim carries an `@ref` suffix, so a
  port that reaches for the exact-match helper used everywhere else in this method produces
  a check that can never pass. That failure at least announces itself. The quieter one is
  dropping the `StartsWith` prefix guard and keeping only the file-name comparison, which
  would accept a workflow of the same name from another repository.
- **An absent `environment` claim mismatches rather than skipping.** A policy scoped to
  `production` is not satisfied by a job that declares no environment at all. The natural
  rewrite — "if the claim is missing, there is nothing to compare, so continue" — makes the
  environment restriction opt-out by the caller.
- The concurrency catch is a **trust check**, not error handling: it re-reads the policy and
  confirms the concurrent writer bound the same identifiers — both of them.

### GitLab: the same shape, a different vocabulary

`GitLabTokenPolicyValidator` follows `GitHubTokenPolicyValidator` structurally — required
claims, ownership match, first-use identifier binding, then the narrower checks — over an
entirely different claim set:

```csharp
public class GitLabTokenPolicyValidator : TokenPolicyValidator
{
    public const string Authority = "gitlab.com";
    public const string Issuer = $"https://{Authority}";

    private const string NamespacePathClaim = "namespace_path";
    private const string NamespaceIdClaim = "namespace_id";
    private const string ProjectPathClaim = "project_path";
    private const string ProjectIdClaim = "project_id";
    private const string RefClaim = "ref";
    private const string RefTypeClaim = "ref_type";
    private const string EnvironmentClaim = "environment";

    public GitLabTokenPolicyValidator(
        ConfigurationManager<OpenIdConnectConfiguration> oidcConfigManager,
        IFederatedCredentialConfiguration configuration,
        JsonWebTokenHandler jsonWebTokenHandler)
        : base(oidcConfigManager, configuration, jsonWebTokenHandler)
    {
    }

    public override string IssuerAuthority => Authority;
}
```

Only the constructor and the claim vocabulary are shown; the `EvaluatePolicyAsync` body
follows the GitHub validator's structure over these claim names. **Do not read the omission
as "GitLab needs less."** It needs the same controls against a different vocabulary.

**"Structurally the same" is a statement about shape, not about comparison semantics.** The
two validators deliberately differ on one: GitHub matches the `environment` claim with
`StringComparison.OrdinalIgnoreCase`, while GitLab routes the same claim through a
case-sensitive helper (`StringComparison.Ordinal`). The helper exists to make that choice
explicit, so it is a decision rather than an oversight. A port that harmonizes the two —
the natural instinct once they are described as parallel — loosens the GitLab match to
accept case variants the original rejects, and no test notices, because every environment
name in use is already lowercase. Copy each comparison's casing rule from the validator you
are porting, not from its sibling.

**The deny-list has no counterpart here, and that is a fact about this implementation rather
than about GitLab.** There is no `event_name` in this claim list, so a port that maps
claim-for-claim finds no home for the banned-trigger check. The right conclusion is that
there is nothing to preserve — not that the dimension does not exist. GitLab's token does
carry a trigger claim, `pipeline_source`, which this validator simply does not consume; see
[providers.md](providers.md). Two mistakes follow from getting this backwards. Inventing a
deny-list during a migration adds an authorization rule nobody signed off on. Mapping
`event_name` onto `ref_type` instead — the intuitive move, since both read as "what kind of
thing triggered this" — is worse, because it leaves a control that looks present while
`ref_type` only distinguishes a branch from a tag.

Note also the base constructor: three arguments, so the token identifier claim defaults to
`jti`. The Entra validator's fourth argument is the exception, not the pattern.

## Applying the classification

| File | Marker | Verdict |
|---|---|---|
| `EntraIdTokenValidator.cs`, `GitHubTokenPolicyValidator.cs`, `GitLabTokenPolicyValidator.cs` | `Microsoft.IdentityModel.*`, `Microsoft.Identity.Web`, `System.Text.Json` — plus `System.Data.Entity.Infrastructure` in the two CI validators | Mostly portable; **the ORM concurrency catch is the one coupled line** |
| `FederatedCredentialPolicyEvaluator.cs` | `NameValueCollection` only | Portable; adapter decision at the boundary |
| `FederatedCredentialService.cs` | No framework types, but depends on `IGalleryConfigurationService` from an excluded folder | **Portable, blocked** |
| `FederatedCredentialConfiguration.cs` | `TypeConverter` from a `net472`-only project reference | Coupled — via its dependency, not its own code |
| `TokenApiController.cs` | `System.Web.Mvc`, `OwinContext` | **Coupled** — and carries the challenge suppression |
| `DefaultDependenciesModule` registration | Autofac, `System.Web` | **Coupled** — and carries the singleton/scoped split |

The summary a migration should produce is therefore *not* "port the federated
authentication subsystem." It is:

- The validators and the evaluator move as-is, minus one exception type each.
- The endpoint and the DI registration are genuine ports.
- The real work is the dependency closure — configuration, auditing, and the entity types —
  none of which is exchange logic, and all of which has to move first.
