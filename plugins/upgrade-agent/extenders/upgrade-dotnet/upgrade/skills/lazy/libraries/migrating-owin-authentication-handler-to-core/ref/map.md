# Katana to ASP.NET Core Handler Member Map

Reference for step 4 of `migrating-owin-authentication-handler-to-core`. Load when porting
members. Katana types are in `Microsoft.Owin.Security` and
`Microsoft.Owin.Security.Infrastructure`; ASP.NET Core types are in
`Microsoft.AspNetCore.Authentication`.

## Contents

- [Handler members](#handler-members)
- [Result contract](#result-contract)
- [Options](#options)
- [Registration](#registration)
- [Members with no direct equivalent](#members-with-no-direct-equivalent)

## Handler members

| Katana member | ASP.NET Core member | Notes |
|---|---|---|
| `AuthenticateCoreAsync()` returning `AuthenticationTicket` | `HandleAuthenticateAsync()` returning `AuthenticateResult` | A `null` return became two outcomes. See "Result contract" below. |
| `ApplyResponseChallengeAsync()` | `HandleChallengeAsync(AuthenticationProperties)` **and** `HandleForbiddenAsync(AuthenticationProperties)` | One Katana override covered both 401 and 403. Split it; a handler that only overrides the challenge silently loses its forbid behavior. |
| Reading `Response.StatusCode == 401` at the top of `ApplyResponseChallengeAsync` | Not needed | ASP.NET Core calls the challenge and forbid paths explicitly. Do not port the status-code check. |
| `ApplyResponseGrantAsync()` — sign-in half | `HandleSignInAsync(ClaimsPrincipal, AuthenticationProperties)` | Only exists on `SignInAuthenticationHandler`. Not a member of `AuthenticationHandler`. |
| `ApplyResponseGrantAsync()` — sign-out half | `HandleSignOutAsync(AuthenticationProperties)` | Only exists on `SignOutAuthenticationHandler`. |
| `InvokeAsync()` returning `bool` | `IAuthenticationRequestHandler.HandleRequestAsync()` returning `Task<bool>` | Implement the interface explicitly; it is not a virtual on the base handler. `true` still means "the response is complete, stop the pipeline". |
| `InitializeCoreAsync()` | `InitializeHandlerAsync()` | Runs after `Scheme` and `Options` are set. |
| `Options.AuthenticationType` | `Scheme.Name` | Supplied to `AddScheme` rather than stored on options, so one handler type can back several named schemes. |
| `Options.Description` | `Scheme.DisplayName` | Second argument to `AddScheme`. |
| `Options.AuthenticationMode` | No member | Translated to scheme selection. See step 7 of the skill. |
| `Request` / `Response` (`IOwinRequest`, `IOwinResponse`) | `Request` / `Response` (`HttpRequest`, `HttpResponse`) | Same property names on the base handler, different types. |
| `Context` (`IOwinContext`) | `Context` (`HttpContext`) | |
| `Helper.LookupChallenge(authenticationType, authenticationMode)` | The `AuthenticationProperties` argument passed to `HandleChallengeAsync` | The framework resolves which scheme was challenged before calling the handler. |
| `Options.Provider` / notification classes | `Options.Events`, `Options.EventsType`, `CreateEventsAsync()` | Katana notification objects exposed the handler's internals; Core events receive a context object. |
| `new AuthenticationTicket(identity, properties)` | `new AuthenticationTicket(principal, properties, scheme)` | Core takes a `ClaimsPrincipal` and requires the scheme name. There is no `(principal, properties)` overload, so dropping the scheme is a compile error, not a silent bug. The silent failures are the ones that still compile: passing a scheme name that is not `Scheme.Name`, or building the `ClaimsIdentity` with a null or empty authentication type, which leaves `IsAuthenticated` false on an otherwise successful result. |

## Result contract

Katana had one success value and one failure value. ASP.NET Core has three outcomes:

| Situation | Return |
|---|---|
| The request carries no credential this handler owns | `AuthenticateResult.NoResult()` |
| A credential is present and invalid, expired, or malformed | `AuthenticateResult.Fail(reason)` |
| A credential is present and valid | `AuthenticateResult.Success(ticket)` |

Both `NoResult` and `Fail` leave the request unauthenticated, so a mechanical port that
returns `Fail` for a missing credential still appears to work. The cost shows up in
diagnostics and in event handlers, which cannot distinguish "not my request" from "rejected
this request", and in logs where every anonymous request records an authentication failure.

## Options

| Katana | ASP.NET Core |
|---|---|
| `AuthenticationOptions` base class | `AuthenticationSchemeOptions` base class |
| Constructor taking the authentication type | Parameterless; the scheme name arrives via `AddScheme` |
| Ad-hoc argument checks in the middleware constructor | `override void Validate()`, called by the framework during handler initialization |
| Options instance captured by the middleware at startup | `IOptionsMonitor<TOptions>.Get(Scheme.Name)`, read per request by the base handler |

## Registration

| Katana | ASP.NET Core |
|---|---|
| `AuthenticationMiddleware<TOptions>` subclass | Nothing. The scheme is not middleware. |
| `IAppBuilder.UseXxx(options)` extension | `AuthenticationBuilder.AddXxx(...)` extension calling `AddScheme<TOptions, THandler>` |
| `app.UseXxx(...)` in `Startup.Configuration` | `builder.Services.AddAuthentication().AddXxx(...)` |
| `app.UseStageMarker(PipelineStage.Authenticate)` | `app.UseAuthentication()`, before `app.UseAuthorization()` |
| Dependencies resolved from the application container at startup and captured | Constructor parameters on the handler, resolved per request |

## Members with no direct equivalent

- **`TeardownCoreAsync()`** — there is no teardown hook. The handler is a transient service
  resolved from the request container, so per-request cleanup belongs in `IDisposable` or
  `IAsyncDisposable` on a collaborator, or in the request pipeline.
- **`ApplyResponseCoreAsync()`** — no equivalent. Katana used it to fan out to the challenge
  and grant paths, and it ran on every response at header-send time via `OnSendingHeaders`.
  "No equivalent" is not "drop it". Reproduce it with middleware registered **before**
  `UseAuthentication()`, doing its work in a `Response.OnStarting` callback. `ref/core.cs`
  carries that shape as `UseSampleResponseMarker`; copy it.

  Two details in that shape are load-bearing, and both look like arbitrary style until they
  bite:
  - **Before `UseAuthentication()`, not after.** A handler implementing
    `IAuthenticationRequestHandler` short-circuits from inside the authentication middleware,
    which returns without calling the rest of the pipeline. Middleware registered after it
    never runs on those responses.
  - **Inside `OnStarting`, not before `await next`.** The callback runs when the Katana override
    ran, so it observes the final status code and the authenticated user and survives a
    downstream `Response.Clear()`. Straight-line code before `next` sees a status code of 200
    no matter what the pipeline later produces, so status-conditional logic ported from the
    Katana body silently stops working.

  Do **not** register that callback from `HandleAuthenticateAsync`, and do not move the logic
  into the challenge and forbid overrides. Every override fires on exactly one outcome, so each
  choice silently drops the behavior from some other set of responses; splitting it across
  `HandleChallengeAsync` and `HandleForbiddenAsync` drops it from every 200. `Response.OnStarting`
  itself is not the problem — registering it somewhere that only runs on some requests is.

  Move logic into an override only when it was guarded by *that specific outcome* inside the
  Katana body. A header being authentication-related does not make it outcome-specific.
- **`BaseContext`, `BaseValidatingContext`, and the `*Notification` types** — replaced by the
  `Events` object model. There is no one-to-one type mapping; port the intent.
- **`IOwinContext.Get<T>(key)` / `Set<T>(key, value)`** — the OWIN environment dictionary
  becomes `HttpContext.Items` for per-request values, or a feature on `HttpContext.Features`
  for values other components discover by contract. Inventory every key the handler wrote:
  downstream code that read one of them keeps compiling and starts reading nothing.
- **`Response.Headers.Set` after the response started** — ASP.NET Core throws instead of
  silently discarding. Guard with `Response.HasStarted` where the Katana handler wrote
  headers late.
- **`ISystemClock` / clock injection** — Katana's base `AuthenticationOptions` had no clock, but
  the stock middleware options did, and Core's first-generation equivalent (`ISystemClock`, plus
  the four-argument handler constructor that took one) is obsolete.
  `AuthenticationSchemeOptions.TimeProvider` replaces both.
