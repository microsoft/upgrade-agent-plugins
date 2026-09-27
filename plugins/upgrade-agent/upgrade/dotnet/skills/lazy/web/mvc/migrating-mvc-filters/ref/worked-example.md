# Worked Example: NuGet Gallery Authorization Subclasses

This is an application binding, not a generic policy schema. Names, claim URIs,
routes, headers and credential versions below belong only to this example. Inspect
the target repository's revision before applying it.

## Contents

- [Source contract](#source-contract)
- [UI and inherited admin access](#ui-and-inherited-admin-access)
- [API warnings and challenge](#api-warnings-and-challenge)
- [Migration probes](#migration-probes)

## Source Contract

Baseline: `NuGet/NuGetGallery` commit
`bc5a59e3cf5d4d357e40615639b78615f97b2cc0`.

- [UiAuthorizeAttribute.cs](https://github.com/NuGet/NuGetGallery/blob/bc5a59e3cf5d4d357e40615639b78615f97b2cc0/src/NuGetGallery/Filters/UiAuthorizeAttribute.cs)
- [ApiAuthorizeAttribute.cs](https://github.com/NuGet/NuGetGallery/blob/bc5a59e3cf5d4d357e40615639b78615f97b2cc0/src/NuGetGallery/Filters/ApiAuthorizeAttribute.cs)
- [AdminControllerBase.cs](https://github.com/NuGet/NuGetGallery/blob/bc5a59e3cf5d4d357e40615639b78615f97b2cc0/src/NuGetGallery/Areas/Admin/Controllers/AdminControllerBase.cs)
- [ClaimsExtensions.cs](https://github.com/NuGet/NuGetGallery/blob/bc5a59e3cf5d4d357e40615639b78615f97b2cc0/src/NuGetGallery.Services/Extensions/ClaimsExtensions.cs)
- [AuthenticationService.cs](https://github.com/NuGet/NuGetGallery/blob/bc5a59e3cf5d4d357e40615639b78615f97b2cc0/src/NuGetGallery.Services/Authentication/AuthenticationService.cs)
- [AuthenticationController.cs](https://github.com/NuGet/NuGetGallery/blob/bc5a59e3cf5d4d357e40615639b78615f97b2cc0/src/NuGetGallery/Controllers/AuthenticationController.cs)
- [Home.cshtml](https://github.com/NuGet/NuGetGallery/blob/bc5a59e3cf5d4d357e40615639b78615f97b2cc0/src/NuGetGallery/Views/Pages/Home.cshtml)
- [ApiKeyAuthenticationHandler.cs](https://github.com/NuGet/NuGetGallery/blob/bc5a59e3cf5d4d357e40615639b78615f97b2cc0/src/NuGetGallery.Services/Authentication/Providers/ApiKey/ApiKeyAuthenticationHandler.cs)
- [UserExtensions.cs](https://github.com/NuGet/NuGetGallery/blob/bc5a59e3cf5d4d357e40615639b78615f97b2cc0/src/NuGetGallery.Services/Extensions/UserExtensions.cs)

The filename uses `Ui`, but the declared class is `UIAuthorizeAttribute`.
Both subclasses derive from **MVC**, not Web API. Both run custom work **before**
`base.OnAuthorization`; neither overrides `AuthorizeCore`. Keep base authentication,
`Users`/`Roles`, anonymous exemptions and cache protections as well as the custom work.

| Contract from identity creation | Policy/filter consumer |
|---|---|
| `ClaimTypes.Name` and `ClaimTypes.NameIdentifier` both contain username | Preserve name-based gates; do not substitute a numeric user ID |
| `ClaimTypes.Role`, configured as the identity's role claim type | `IsInRole("Admins")` for inherited admin access |
| `https://claims.nuget.org/discontinuedlogin` | Primary authenticated `ClaimsIdentity`, first matching claim, value `"true"` ignoring case |
| `enabledmultifactorauthentication` / `wasmultifactorauthenticated` under `https://claims.nuget.org/` | Account MFA and session MFA are distinct; neither replaces the TempData nudge |
| Authentication types `"LocalUser"`, `"ApiKey"`, `"External"`, `"Federated"` | Preserve exact scheme names and existing defaults; the API warning selects `"ApiKey"` only |

These are the authorization inputs to the shared-cookie claims-equivalence
inventory, not instructions to reissue claims or configure another cookie.

## UI and Inherited Admin Access

Bind the generic reference to the existing flow:

```csharp
builder.Services.AddSingleton(new UiFlowContract(
    "https://claims.nuget.org/discontinuedlogin",
    "AskUserToEnable2FA",
    "Home",
    "Pages",
    ""));
builder.Services.AddSingleton<IAuthorizationHandler, ExistingRoleHandler>();
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("Admins", policy =>
    {
        policy.RequireAuthenticatedUser();
        policy.AddRequirements(new ExistingRoleRequirement("Admins"));
    });
    options.AddPolicy("SignedIn", policy =>
        policy.RequireAssertion(ExistingIdentity.IsAuthenticated));
});
builder.Services.AddControllersWithViews();
```

`Admins` is the new policy's name bound to the **existing role value** `Admins`,
not a new `isAdmin` claim. Retain any additional predicates found in the target
revision. `SignedIn` uses the reference's primary-identity check: Core's
`RequireAuthenticatedUser()` alone also accepts an authenticated secondary
identity, unlike MVC's base gate. The old `[UIAuthorize(Roles = "Admins")]` stays
at base-controller scope:

```csharp
[UiAccess("Admins")]
public abstract class AdminControllerBase : Controller
{
}
```

Retain the migrated `AppController` inheritance and members in the real application;
the empty class above only shows attribute placement. Derived admin controllers
inherit the gate and UI flow. Do not replace it with only `[Authorize(Policy =
"Admins")]`, which retains access control but loses the redirect. Do not stack both
attributes: endpoint authorization can reject before the MVC filter runs.

| Legacy branch | Core binding and effect |
|---|---|
| Discontinued login and `AllowDiscontinuedLogins == false` | `UiAccessFilter` selects `Pages/Home`, `area = ""`; preserves first-claim, case-insensitive `"true"` evaluation |
| `AllowDiscontinuedLogins == true` | Pass `allowRetiredLogin: true` on the equivalent use; only this check is exempted |
| TempData contains `AskUserToEnable2FA` | Same redirect regardless of the stored value, including `false`; `ContainsKey` does not consume it |
| Both checks false | Continue into the base-equivalent policy, no redirect |
| Base authorization fails | Challenge overwrites the pending redirect, even for an authenticated non-admin |
| `[AllowAnonymous]` | Skip the base gate but retain a redirect already selected by the custom work |

Preserve the **producer**, not just the filter. The successful Microsoft-account
external-login path updates session/account MFA state, then writes
`TempData["AskUserToEnable2FA"] = true` if the account still lacks MFA, then safely
redirects to the return URL. This is a nudge, not an MFA authorization requirement.
Keep the existing safe-return-URL validation.

At `Pages/Home`, preserve the view's Boolean read and feature-flag check. The
organization transform/link modal (`Model.ShowTransformModal`, `_TransformOrLink`)
has precedence over the 2FA modal. The TempData indexer read consumes
the TempData value; the intervening authorization filter must not consume it first.
Shared cookies do not transfer TempData: while external login remains on Framework,
hold the nudge-dependent flow there unless an explicit cross-host transfer design
exists. Moving only the protected controller to Core silently loses the marker.

## API Warnings and Challenge

Keep each existing `ApiAuthorize` registration at its current scope. First preserve
the active handlers that populated its principal. For a host accepting both the
existing `"LocalUser"` cookie and `"ApiKey"` credential, configure a separate policy:

```csharp
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("ApiSignedIn", policy =>
    {
        policy.AddAuthenticationSchemes("LocalUser", "ApiKey");
        policy.RequireAssertion(ExistingIdentity.IsAuthenticated);
    });
});
```

Both names must already be registered with their migrated handlers. Verify this
list against the source's active handlers: include other schemes that actually
authenticated these requests, but do not activate temporary external-login schemes
merely because their names exist. Preserve credential precedence when both are
present; Core's policy evaluator merges successful identities with the later
scheme's identities first. Do not change the browser's default scheme to API key.
Bind the authenticated-user gate to this policy:

```csharp
[ApiAccess("ApiSignedIn", "ApiKey")]
public sealed class PackageApiController : Controller
{
}
```

This illustrates attribute placement, not replacement of the application's
controller or its actions. Preserve existing `Roles`/`Users` restrictions using a
matching policy where a use supplies them. Retain separate `ApiScopeRequired`
filters and their ordering. **Do not restrict authentication to `"ApiKey"` alone
just because the warning branch checks that identity type.** The old base gate
accepts any authenticated identity meeting its access restrictions. Conversely, a
challenge scheme alone does not authenticate API requests: use the policy's scheme
list so the nondefault API-key handler runs before warning or access evaluation.

Implement and register `ICredentialWarningWriter` as a scoped adapter to the
existing services; the reference filter authenticates the policy's schemes, then
awaits the writer before evaluating authorization requirements:

1. Only process a primary authenticated `ClaimsIdentity` whose authentication type
   equals `"ApiKey"` (case-sensitive), at a use whose legacy controller was an
   `AppController`. Record that applicability when porting the registration; a Core
   authorization filter cannot obtain an instantiated controller.
2. Port `GetCurrentUser()` and credential lookup, including disabled/deleted-user
   failure behavior. Read `https://claims.nuget.org/apikey` and select the first
   credential with equal stored `Value`. The claim may contain a hash: do not log it,
   replace it with `credentialkey`, or compare it to the incoming plaintext header.
3. With no credential or no expiry, emit nothing. Otherwise generate the existing
   absolute `ManageMyApiKeys(false)` URL and calculate remaining UTC lifetime.
4. If expired, append `X-NuGet-Warning` using the existing expired-message resource,
   including for V5 credentials. Otherwise warn when remaining `TotalDays` is at
   most `WarnAboutExpirationInDaysForApiKeyV1` and the credential is **not V5**
   (`apikey.v5`, ignoring case). Despite the setting's name, do not narrow this to V1.
5. Preserve the existing resource strings, `Math.Round(totalDays, 0)`, singular
   `"day"` only for rounded `1`, and header-add semantics. The warning is not an
   authorization failure and must also survive a later policy denial.

No authentication rewrite is needed for those steps. In particular, leave any
federated/trusted-publisher token-exchange validation and issuance untouched:
that produces credentials; this filter consumes the established principal.

`HandleUnauthorizedRequest` requests the `"ApiKey"` challenge, sets OWIN status
401 and returns MVC `HttpUnauthorizedResult`. The Core filter must request
`ChallengeResult("ApiKey")`, not `Unauthorized()` or a browser-cookie challenge.
The **final** status belongs to the migrated authentication handler:

| Request at challenge time | Existing API-key handler response |
|---|---|
| No nonempty `X-NuGet-ApiKey` header | 401 plus `WWW-Authenticate: ApiKey realm="<request host>"` |
| Nonempty `X-NuGet-ApiKey` header | 403 with the existing not-authorized message |

Preserve that handler response using `migrating-owin-authentication-handler-to-core`.
Do not assume the requested 401 is the final wire status, or change an authenticated
denial to `ForbidResult` when the old override always challenged. Expired keys are
normally rejected upstream; still preserve the filter's expired-warning branch
and test it using an already-authenticated fixture.

## Migration Probes

Run source-equivalence probes for allowed/denied roles with and without the UI
redirect, discontinued-login exemption plus a nudge, a false-valued marker,
`[AllowAnonymous]` with a pending effect, duplicate discontinued-login claims,
and inherited admin actions. Verify the producer-to-Home marker survives and is
consumed only at Home.

For the API, cover missing/non-expiring credentials, the exact expiry boundary,
warning threshold, rounded day counts, V5 near-expiry suppression and V5 expired
warning, a browser identity, and both challenge header branches. Confirm warning
headers remain on denial and scope filters still restrict actions. Exercise browser
credentials alone, API keys alone and both together, with the browser still the
default authenticate scheme; assert the selected primary identity in each case.

The generic reference is exercised with synthetic identities in repository tests;
these Gallery adapters require the target application's services and integration
tests. Neither reference compilation nor text guards prove that an agent performs
the migration correctly.
