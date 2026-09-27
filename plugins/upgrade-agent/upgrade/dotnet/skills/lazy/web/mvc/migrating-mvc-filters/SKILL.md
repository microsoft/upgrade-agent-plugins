---
name: migrating-mvc-filters
description: >
  Migrates ASP.NET MVC global filters and custom AuthorizeAttribute subclasses to ASP.NET Core
  middleware, authorization policies, and filters. Use for GlobalFilterCollection, FilterConfig,
  HandleErrorAttribute, IActionFilter/IExceptionFilter conversion, or overrides of AuthorizeCore,
  OnAuthorization, and HandleUnauthorizedRequest. Covers inherited controller authorization,
  role/claim equivalence, TempData redirects, response headers, and explicit challenge schemes.
  Also triggers for MVC-to-Core filter conversion, custom authorization filter migration,
  global error handling, and UseExceptionHandler setup.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC Filters and Authorization Migration

## Overview

Migrate `GlobalFilterCollection`-based filters from ASP.NET MVC to ASP.NET Core middleware and filter pipeline. ASP.NET Core replaces `HandleErrorAttribute` with `UseExceptionHandler` middleware because middleware runs earlier in the pipeline and catches errors from all middleware, not just controller actions.

For custom `System.Web.Mvc.AuthorizeAttribute` subclasses, start at **Custom
Authorization** below. An authorization-only task does not require error middleware,
error actions/views, or removal of unrelated filter registrations.

> **Related skills:** `migrating-mvc-authentication` owns authentication configuration
> and ordinary authorization metadata. `sharing-authentication-cookies-katana-interop`
> owns shared-cookie identity and the claims contract consumed here.
> `migrating-owin-authentication-handler-to-core` owns custom authentication schemes
> and the final challenge response, not the authorization gates that request it.

## Workflow

For global error-filter work only, track these steps. For authorization-only work,
use the separate **Custom Authorization** checklist instead:

```
Migration Progress:
- [ ] Step 1: Identify main controller from routing
- [ ] Step 2: Add exception handler middleware
- [ ] Step 3: Add error action methods
- [ ] Step 4: Create error views
- [ ] Step 5: Convert custom filters
- [ ] Step 6: Remove FilterConfig and GlobalFilters references
```

### Step 1: Identify Main Controller

Determine the main controller name from routing configuration. Check `Program.cs` for route registration first, then fall back to `RouteConfig.cs` if the project hasn't been fully migrated. The default route typically maps to `HomeController`. This controller will host the error-handling action methods.

### Step 2: Add Exception Handler Middleware

If `HandleErrorAttribute` was registered as a global filter, add exception handling middleware in `Program.cs`:

```csharp
app.UseExceptionHandler("/<MainControllerName>/Error");
app.UseStatusCodePagesWithReExecute("/<MainControllerName>/StatusErrorCode", "?code={0}");
```

Replace `<MainControllerName>` with the controller name from Step 1. Skip if these lines already exist.

`UseExceptionHandler` replaces `HandleErrorAttribute` globally, while `UseStatusCodePagesWithReExecute` provides user-friendly pages for HTTP status codes like 404 and 403.

### Step 3: Add Error Action Methods

Open the main controller file and add an `Error` action method if missing:

```csharp
public IActionResult Error()
{
    return View();
}
```

Add a `StatusErrorCode` action method to the same controller:

```csharp
public IActionResult StatusErrorCode(int code)
{
    return View("StatusErrorCode", code);
}
```

If other methods in the controller use attribute routing, add `[Route]` attributes to these methods as well to stay consistent.

### Step 4: Create Error Views

Create `Views/Shared/Error.cshtml` if it does not exist:

```cshtml
@{
    ViewData["Title"] = "Error";
}

<h1 class="text-danger">Oops! Something went wrong.</h1>
<p class="text-muted">An unexpected error occurred. Please try again later.</p>
```

Create `Views/Shared/StatusErrorCode.cshtml` if it does not exist:

```cshtml
@{
    ViewData["Title"] = "Status Error Code";
    var code = Context.Request.Query["code"];
}

<h1 class="text-danger">Oops! Something went wrong.</h1>

@if (code == "404")
{
    <p class="text-muted">The page you are looking for could not be found.</p>
}
else if (code == "403")
{
    <p class="text-muted">You do not have permission to access this resource.</p>
}
else if (code == "500")
{
    <p class="text-muted">An internal server error occurred. Please try again later.</p>
}
else
{
    <p class="text-muted">An unexpected error occurred (Status code: @code).</p>
}
```

Place views under `Views/Shared/` for app-wide access, or under `Views/<ControllerName>/` if only that controller handles errors.

### Step 5: Convert Custom Filters

Convert action/exception filters to ASP.NET Core filter interfaces (`IActionFilter`,
`IAsyncActionFilter`, `IExceptionFilter`, etc.). Route authorization subclasses through
**Custom Authorization** instead of treating them as action filters. Register only
filters that were global in `Program.cs`; retain controller/action scope for the rest:

```csharp
builder.Services.AddControllersWithViews(options =>
{
    options.Filters.Add<MyCustomFilter>();
});
```

ASP.NET Core filters use dependency injection natively, so constructor-injected services work without extra setup.

### Step 6: Remove FilterConfig

Remove `FilterConfig.cs` (or equivalent class that called `GlobalFilters.Filters.Add()`). Search for and remove all references to `GlobalFilters.Filters` across the codebase. If the class contained only filter registration code, delete the entire file; otherwise, remove only the filter-related code.

## Custom Authorization

- [ ] Inventory overrides and observable behavior
- [ ] Preserve claims and inheritance
- [ ] Preserve filter-scoped effects and denial ordering
- [ ] Validate the migrated contract

### 1. Inventory Overrides and Observable Behavior

Record the source namespace first: MVC's `System.Web.Mvc.AuthorizeAttribute` and
Web API's `System.Web.Http.AuthorizeAttribute` have different contexts and base
behavior. The reference here targets the MVC shape; inspect Web API base semantics
separately rather than copying MVC assumptions.

For each subclass, record `Users`, `Roles`, constructor flags, global/controller/action
registrations, inherited uses, `Order`, anonymous exemptions, and every override's
calls to its base implementation. Trace identity creation and the scheme's challenge
handler as well as the filter. Record status, headers, redirect route (including
area), TempData producers/readers, and side-effect order on success and failure.

Trace from each Katana startup registration (`UseCookieAuthentication`, custom
`Use...`/`IAppBuilder` extension) through its `AuthenticationMode`,
`AuthenticateCoreAsync`, identity construction and sign-in calls. On Core, inspect
`AddAuthentication` defaults, registered schemes, forwarding selectors and the
policy's `AuthenticationSchemes`. Test browser-only, API-only and both credentials
and record `User.Identities` order and the primary identity; registration alone
does not prove a handler populated the request.

| Legacy override | Core destination | Preservation rule |
|---|---|---|
| `AuthorizeCore` | `IAuthorizationRequirement` + `AuthorizationHandler<TRequirement>` | Keep the predicate, authentication prerequisite, claim types/values and comparison rules. No redirects or response writes in a handler. |
| `OnAuthorization` | Policy metadata for a pure gate; `IAsyncAuthorizationFilter` for MVC-scoped effects/order | Translate code before and after `base.OnAuthorization`; an action filter runs too late to reproduce authorization behavior. |
| `HandleUnauthorizedRequest` | Standard challenge/forbid, or explicit filter result; `IAuthorizationMiddlewareResultHandler` for endpoint-wide customization | Preserve the requested scheme and final wire response. Do not replace every denial with the default 401/403 split without checking the old override. |

Do not subclass Core `AuthorizeAttribute` expecting these overrides: it is
`IAuthorizeData` metadata, not executable authorization logic. Do not turn warning
headers, UI nudges, or an authentication-type check used only to select those effects
into new access requirements.

### 2. Preserve Claims and Inheritance

Read the **Step 1: Inventory the Contract** checklist in
`sharing-authentication-cookies-katana-interop` before defining policies. Record
subject/name, tenant, role and MFA claim URIs, values, issuers where checked,
`NameClaimType`, `RoleClaimType`, authentication type, and primary versus secondary
identity selection. Do not invent a new role or MFA claim to make a policy pass.
`ClaimsIssuer` does not configure `RoleClaimType`. Preserve each identity's
name/role mapping when constructing or transforming it, without mutating issued
shared tickets just to fit new defaults.

Use the claim-backed `ExistingRoleRequirement` / `ExistingRoleHandler` in
[`ref/core.cs`](ref/core.cs) as a synthetic policy example. Register its handler and
the application policy:

```csharp
builder.Services.AddSingleton<IAuthorizationHandler, ExistingRoleHandler>();
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("OperatorAccess", policy =>
    {
        policy.RequireAuthenticatedUser();
        policy.AddRequirements(new ExistingRoleRequirement("Operators"));
    });
});
```

`OperatorAccess` and `Operators` are illustrative policy/role values, not new claims
to issue. Bind them to the source contract. The handler uses `IsInRole`, which reads
the identity's `RoleClaimType`, and retains MVC's primary-identity authentication
check. Add the actual `AuthorizeCore` predicate, including user allowlists if present.
For a signed-in-only legacy gate, use
`policy.RequireAssertion(ExistingIdentity.IsAuthenticated)` from the reference;
`RequireAuthenticatedUser()` alone accepts an authenticated secondary identity
even when MVC's primary-identity check would deny.
One comma-separated `Roles` list means OR; multiple authorization attributes combine
as AND. Retain case/duplicate-claim semantics rather than replacing every lookup
with `HasClaim`.

ASP.NET Core **does inherit** `[Authorize]` and inheritable filter attributes from
base controllers. A pure role gate can stay on the base:

```csharp
[Authorize(Policy = "OperatorAccess")]
public abstract class OperationsControllerBase : Controller
{
}
```

Keep derived actions protected without copying attributes onto every controller.
Inspect action overrides, multiple base attributes, and `[AllowAnonymous]` exceptions.
A policy alone is insufficient when the old base attribute also redirects or writes
headers; retain those effects using the next path.

### 3. Preserve Filter-Scoped Effects and Denial Ordering

Read [`ref/core.cs`](ref/core.cs) for two filter-shaped examples and
[`ref/worked-example.md`](ref/worked-example.md) for application bindings.
The C# reference requires only the ASP.NET Core shared framework in a web project;
translate it for a Visual Basic application. It is an adaptation example, not a
replacement authentication architecture.

For side-effecting subclasses, use inheritable `TypeFilterAttribute` metadata and
constructor-injected filters. Register `AddControllersWithViews()`, the policy
handler above, the application's `UiFlowContract`, and a scoped implementation of
`ICredentialWarningWriter`. That writer must port the existing credential lookup,
expiry branches, formatting, and response-header operation, not return a placeholder
success. Bind the attribute's policy and challenge-scheme arguments at its existing
controller/action scope. Do not add it globally unless the old filter was global.

The sample `UiAccessAttribute` and `ApiAccessAttribute` deliberately do **not**
implement `IAuthorizeData`: their filters resolve the named policy through
`IAuthorizationPolicyProvider` and invoke `IPolicyEvaluator` themselves.
Do not also add `[Authorize]`/`RequireAuthorization` for the same gate. Endpoint
authorization runs before MVC and would short-circuit the filter's TempData/header
work. Inventory fallback policies, global `AuthorizeFilter`s and other authorization
metadata too: they can preempt it. Preserve their restrictions without silently
disabling them; if the combined ordering cannot be represented by this filter
path, move the required effects into an appropriately scoped middleware/result
handler and validate the whole pipeline.

Authenticate the policy's named schemes **before** inspecting identity-dependent
effects, even on anonymous exemptions; then run effects, check the exemption and
evaluate the policy. `IAuthorizationService.AuthorizeAsync` alone only checks
requirements; it ignores `AuthenticationSchemes`. A nondefault credential would
never be read, and a default browser identity could pass a scheme-restricted gate.
The reference's `IPolicyEvaluator.AuthenticateAsync` establishes the principal and
`AuthorizeAsync` checks it without moving the effects into a policy handler.

Inventory Katana `AuthenticationMode.Active` handlers that established the legacy
principal. Core does not automatically run every registered scheme. Where both
browser and API credentials were accepted, list all those schemes in the applicable
policy (or preserve an existing equivalent forwarding setup), not just the challenge
scheme. Keep browser defaults unchanged. Verify primary-identity precedence when
several credentials are present; scheme merging can change which identity is first.
Core combines the policy's `AuthenticationSchemes` in list order with each later
successful scheme's identities first; it is not service-registration order.
If the legacy API identity was primary, put that scheme last in this policy list.
If browser identity was primary, preserve that instead. When source precedence
is unknown, capture it from the legacy dual-credential request before choosing;
do not turn an accidental order into a new authorization rule.
Policies without explicit schemes use the already established request principal.

The reference preserves a particular legacy contract: UI denial challenges even an
authenticated user, overwriting any pending redirect; API denial challenges an explicit
scheme. For an ordinary pure policy, Core instead challenges anonymous users and
forbids authenticated users. Choose from source evidence, not from the reference's
default. A `ChallengeResult` executes the scheme handler; a bare
`StatusCodeResult(401)` does not. Keep browser defaults unchanged, and do not infer
API-key-only authentication from an API-key warning condition.

If the source does not name a challenge scheme, preserve the observed default
challenge behavior rather than choosing the last authenticated scheme. The UI
reference's bare `ChallengeResult()` deliberately delegates to that default.
Verify the effective `DefaultChallengeScheme`/`DefaultScheme` (including forwarding)
and its redirect/status behavior after registering all schemes. If no default
exists or the source default is unknown, report the missing configuration instead
of guessing a cookie or API scheme.

Preserve anonymous semantics deliberately. Legacy custom code *before*
`base.OnAuthorization` can still run on `[AllowAnonymous]`. The sample checks
anonymous endpoint/filter metadata only **after** those effects, skipping the gate
and challenge but retaining any redirect/header. Do not copy an early anonymous
return into a subclass whose base call occurred last.

Use `ITempDataDictionaryFactory` during authorization: controller instantiation has
not happened yet, so `AuthorizationFilterContext` has no controller instance.
`ContainsKey`/`Peek` retain the marker; an indexer read can consume it. Preserve the
producer's writes and the destination view's reads, not merely the redirect URL.
Save loaded TempData on **any** authorization short-circuit, not just a result set
by the UI filter itself. Checking even an absent marker loads the whole dictionary;
the session provider removes its backing entry, including unrelated flash messages.
The reference's always-run result filter registers `Response.OnStarting` so the
snapshot includes result-time reads and writes before headers are sent, including
when a later authorization filter denies. A post-result fallback saves no-body
results before session teardown; it must not save inline before `next()` or wait
until headers are already sent. Suppress the callback on an unhandled result
exception. Request-shared state avoids duplicate saves across UI attributes.
TempData mutations must finish before the first response write/flush.
The saved `AuthorizationFilterContext.Result`
detects a denial by any authorization filter, without mistaking a resource/action
short-circuit for one; MVC's normal saver retains those paths. It honors `IKeepTempDataResult` on
redirects so a preceding read survives. Retain these hooks when adapting the sample;
an unconditional early save can duplicate normal saves or miss later modifications.
During side-by-side migration, shared authentication cookies do **not** share
TempData. Co-locate the marker producer, protected action, and redirect consumer on
one host, or require a separately designed transfer contract before moving the route.

### 4. Validate the Migrated Contract

Exercise the real MVC pipeline, not only the predicate. Compare legacy and Core for:

For each case assert action execution plus the final status, redirect `Location`,
challenge and warning headers, cache directives and persisted TempData contents.
An intermediate result type or a save count alone does not establish parity.

| Request | Required observation |
|---|---|
| Anonymous / authenticated allowed / authenticated denied | Same gate outcome, challenge scheme, final 401/403 or redirect, and action execution |
| Missing, wrong-value, duplicate or differently mapped claims | No broadened access; original comparison and identity-selection semantics |
| Inherited base gate, multiple attributes, anonymous exception | Same effective restrictions and pre-base effects |
| UI marker present (including false), absent, consumed; legacy-login exemption | Same redirect target/area, marker lifetime and exemption boundaries |
| Passing UI gate followed by authorization denial/redirect, resource short-circuit, or normal action | Unread session/cookie TempData survives; result-time reads/writes persist correctly for body and no-body results; no duplicate saves or save after unhandled result exceptions |
| Expired, near-expiry, non-expiring and excluded credential versions | Same header value and timing, including on denied requests |
| Browser-only, nondefault API-only and both credentials | Correct accepted schemes and primary identity; effects see the authenticated principal; denial invokes the intended challenge handler |
| Side-by-side host transition | No lost TempData nudge or change of authentication authority |

Retain cache protection: MVC's base authorization included cache validation that
Core does not reproduce. `AuthorizationResponseCache` in the reference sets
`Cache-Control: private, no-store, no-cache`, `Pragma: no-cache` and an expired
`Expires`, then reapplies them at response start so action/result cache directives
cannot replace them. This intentionally conservative example disables storage on
all routes carrying these filters, including anonymous exemptions and denials.
For pure-policy routes, configure equivalent response/output-cache protection
separately. Remove or partition any upstream/output-cache entries that can be served
before MVC runs; response headers cannot repair an already cached protected response.
Do not serve output-cached protected content across users.
Build, run these cases, fix mismatches, and repeat before removing the legacy filters.

## Success Criteria

- For global error-filter work:
  - `UseExceptionHandler` and `UseStatusCodePagesWithReExecute` configured in `Program.cs`
  - `Error` and `StatusErrorCode` action methods exist in the main controller
  - Error views created under `Views/Shared/` or the appropriate controller folder
- Custom filters converted to ASP.NET Core interfaces and registered
- For authorization work: claims, inheritance, anonymous exceptions, side effects and final challenge responses remain equivalent
- No migrated `FilterConfig.cs` or `GlobalFilters.Filters` references remain
- Project builds without errors
