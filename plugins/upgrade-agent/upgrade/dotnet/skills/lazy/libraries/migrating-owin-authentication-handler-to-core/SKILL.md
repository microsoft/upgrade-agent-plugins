---
name: migrating-owin-authentication-handler-to-core
description: >
  Migrates a custom Katana/OWIN authentication handler to an ASP.NET Core authentication
  scheme. Use when an application defines its own scheme by deriving from the OWIN
  AuthenticationHandler base class in Microsoft.Owin.Security.Infrastructure — usually with
  its own AuthenticationMiddleware subclass and IAppBuilder extension, but however it is
  registered — and the equivalent ASP.NET Core handler must be registered with AddScheme.
  Covers AuthenticateCoreAsync, ApplyResponseChallengeAsync, ApplyResponseGrantAsync,
  InvokeAsync, custom AuthenticationType values, AuthenticationMode Active versus Passive,
  and per-scheme options binding. Triggers for "custom OWIN authentication handler",
  "custom authentication middleware", "custom authentication scheme", "port
  AuthenticateCoreAsync", or "AuthenticationMiddleware subclass". Not for stock OWIN cookie,
  OAuth bearer, or OpenID Connect middleware, which have their own migration paths.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Migrate a Custom Katana Authentication Handler to ASP.NET Core

## Overview

Port an application-defined authentication scheme from Katana to ASP.NET Core. The Katana shape is a handler deriving from `Microsoft.Owin.Security.Infrastructure.AuthenticationHandler<TOptions>`, an `AuthenticationMiddleware<TOptions>` subclass that constructs it, and an `IAppBuilder.UseXxx` extension that registers the middleware.

ASP.NET Core has a type with the same name and a different shape: `Microsoft.AspNetCore.Authentication.AuthenticationHandler<TOptions>`. It is not middleware, it is not registered on the pipeline, and its members do not line up one-to-one with the Katana ones. Type names matching across the two frameworks is the single most misleading thing about this migration.

Three failure modes here are silent at runtime rather than loud at build time. Each step below exists to prevent one of them.

- **The handler is converted to middleware.** `AuthenticationMiddleware<TOptions>` is an `OwinMiddleware`, so a generic OWIN pass wraps it as `app.UseMiddleware<T>()`. It compiles, it runs, and the authentication system never learns the scheme exists, so `[Authorize]` cannot name it.
- **The ported handler never runs.** Katana's `AuthenticationOptions.AuthenticationMode` defaults to `Active`, meaning the handler authenticated every request. `AddScheme` is passive: `UseAuthentication()` runs only the default authenticate scheme. A correct, correctly registered port can still authenticate nothing.
- **The response contract collapses.** The Katana handler returned `null` for both a missing and an invalid credential, and decided between 401 and 403 inside one override. A mechanical port loses both distinctions and typically starts redirecting API clients to a login page.

Every snippet here is C#. A Visual Basic application must translate them; the scheme contract is language-independent.

> **Related skills:** Use `migrating-owin-to-aspnet-core` for the rest of the Katana pipeline, startup, and SignalR — but route custom authentication handlers here rather than through its middleware conversion step. Use `migrating-owin-cookie-auth`, `migrating-owin-oauth-to-jwt`, or `migrating-owin-openid-connect` when the scheme is stock middleware that was only configured, not subclassed. Use `sharing-authentication-cookies-katana-interop` when both hosts must accept one cookie during an incremental migration. Use `migrating-mvc-filters` for `AuthorizeAttribute` subclasses and authorization filters; porting a handler does not migrate the gates that consume it.
>
> **Out of scope — credential issuance.** This skill ports a handler that *validates* an inbound credential. A handler that also **mints** one — exchanging a caller-supplied external OIDC token for an application credential after matching it against a stored trust policy — is a token-exchange endpoint that happens to be written as a handler. Port the validation half here, and keep the exchange and issuance logic behind an explicit interface rather than inlining it into `HandleAuthenticateAsync`; the credential store, policy matching, and lifetime rules are application logic, not scheme logic. No skill covers the issuance half today.

## Workflow

```text
Migration progress:
- [ ] Step 1: Decide which host owns the scheme
- [ ] Step 2: Inventory the scheme contract
- [ ] Step 3: Choose the ASP.NET Core base class
- [ ] Step 4: Port the handler members
- [ ] Step 5: Convert options and register the scheme
- [ ] Step 6: Place configuration and dependencies
- [ ] Step 7: Make the scheme actually run
- [ ] Step 8: Wire, validate, and retire the OWIN registration
```

### Step 1: Decide Which Host Owns the Scheme

Port the scheme into the host that will serve the endpoints it protects. Determine that first, because it decides whether the Katana registration is removed in this change or left alone.

- **The Framework host is being retired in this change.** Port the scheme and remove the Katana registration together.
- **The Framework host still serves some of the protected endpoints.** Port the scheme into the Core host for the endpoints that have moved, and leave the Katana handler, its middleware, its `IAppBuilder` registration, and its `app.UseStageMarker(PipelineStage.Authenticate)` placement exactly as they are. Both hosts run the scheme until the last endpoint moves.

Removing the OWIN registration is gated on the endpoints having moved, not on the port compiling. Removing it early does not fail a build or throw at startup: the Framework host simply stops authenticating, and requests that used to be rejected arrive anonymous.

**If the gate cannot be settled, treat it as unsatisfied.** Leave the Katana registration in place and say so in the summary. Leaving it registered while the Core host also runs the scheme costs a redundant authentication pass; removing it while the Framework host still serves a protected endpoint silently opens that endpoint.

If the Framework host must keep issuing or reading a shared credential during the transition, that is a separate concern from this port — see the related skills above.

### Step 2: Inventory the Scheme Contract

Record every item before writing code. Each collaborator gets an explicit decision: port it, share it, call back into the Framework host, or defer it with the endpoints that have not moved.

| Contract item | Katana source | Why it matters |
|---|---|---|
| Scheme name | `Options.AuthenticationType` | Becomes the `AddScheme` name and the identity's authentication type. Every consumer that names the scheme must use the same string. |
| Active or passive | `Options.AuthenticationMode` | Drives step 7. Unset means `Active`. |
| Options type | The `TOptions` argument and its base class | Real Katana options derive from `Microsoft.Owin.Security.AuthenticationOptions`; that base is replaced, not ported. |
| Overridden members | The handler and middleware classes | Drives step 3. `ApplyResponseGrantAsync` and `InvokeAsync` in particular change the base class. |
| Collaborators | Constructor parameters and service locator calls in the handler, middleware, and `IAppBuilder` extension | Drives step 6. A user store or validation service is expected here; it does not disqualify the migration. |
| Consumers | `[Authorize]` usages, `AuthorizeAttribute` subclasses, and explicit `owinContext.Authentication.Challenge(authenticationType)` calls | Anything naming the scheme must keep naming it, with the same string. |
| Environment entries | `IOwinContext.Get` and `Set` calls in the handler | Downstream code reading these keeps compiling and starts reading nothing. |
| Response shape | Status codes, headers, and bodies written on challenge and on forbid | Clients depend on these. Preserve them rather than accepting framework defaults. |

Do not stop the migration because the handler calls into application services or because the options type derives from a Katana base class. Both are true of essentially every real custom handler.

### Step 3: Choose the ASP.NET Core Base Class

The base class follows from what the Katana handler overrode.

| The Katana handler overrode | Derive from | Because |
|---|---|---|
| `AuthenticateCoreAsync` and `ApplyResponseChallengeAsync` only | `AuthenticationHandler<TOptions>` | Authenticate-only scheme. |
| `ApplyResponseGrantAsync` to sign a user in | `SignInAuthenticationHandler<TOptions>` | `HandleSignInAsync` is declared there, not on `AuthenticationHandler<TOptions>`. |
| `ApplyResponseGrantAsync` to sign a user out only | `SignOutAuthenticationHandler<TOptions>` | Same reason, for `HandleSignOutAsync`. |
| `InvokeAsync` to own a callback path and short-circuit | The base class above, plus `IAuthenticationRequestHandler` | `HandleRequestAsync` runs before the authenticate pass and can complete the response. |
| A remote provider round trip with a redirect and a callback endpoint | `RemoteAuthenticationHandler<TOptions>` | It already implements the callback, correlation, and state handling. |

Getting this wrong is a compile error, not a silent failure, provided the choice is made before the members are ported. Making it afterwards means discovering that `HandleSignInAsync` does not exist on the chosen base class after the whole handler has been written.

For a remote provider round trip, port the shape here and defer the token validation itself to the OAuth or OpenID Connect skill.

### Step 4: Port the Handler Members

Read [`ref/map.md`](ref/map.md) before porting any member. It carries the full member map, the options map, and the list of members with no ASP.NET Core equivalent. [`ref/core.cs`](ref/core.cs) is a complete, compiling authenticate-only handler that uses only the ASP.NET Core shared framework; read it as the target shape rather than reconstructing one.

One rule from that map is restated here because it is where mechanical ports go wrong. `HandleAuthenticateAsync` has three outcomes where Katana had two:

- `AuthenticateResult.NoResult()` when the request carries no credential this handler owns.
- `AuthenticateResult.Fail(reason)` when a credential is present and invalid.
- `AuthenticateResult.Success(ticket)` otherwise.

Katana's single `null` return must be split in two, because Core has three outcomes where Katana had two. Return `NoResult()` when no credential is present and `Fail(reason)` when one is present and invalid — the choice is about the *inbound* credential and nothing else.

Katana's single `ApplyResponseChallengeAsync` override splits in two as well, and independently: `HandleChallengeAsync` writes the 401 and `HandleForbiddenAsync` writes the 403 that the Katana override emitted from the same method. These are *outbound* response paths. Neither result value selects a response path, and neither response path depends on which result value was returned.

Returning `Fail` for a missing credential is not a functional break — the request is unauthenticated either way, and a policy naming several schemes still evaluates each one and merges the successes. It is a diagnostics break: events and logs can no longer separate "not my request" from "rejected this request", and every anonymous request records an authentication failure.

A handler that overrode `ApplyResponseCoreAsync` needs one more decision, because that method ran on *every* response — at header-send time, through Katana's `OnSendingHeaders` — and no ASP.NET Core handler override does. Every override fires on exactly one outcome, so no combination of them reproduces "always", and which override an agent picks only decides *which* responses silently lose the behavior. Reproduce it with middleware registered **before** `UseAuthentication()`, doing its work in a `Response.OnStarting` callback:

```csharp
// Before UseAuthentication(): a handler implementing IAuthenticationRequestHandler can
// short-circuit from inside it, and later middleware never runs on those responses.
app.Use(async (context, next) =>
{
    context.Response.OnStarting(() =>
    {
        // Everything ApplyResponseCoreAsync did goes here.
        context.Response.Headers["X-Example-Scheme"] = "MyScheme";
        return Task.CompletedTask;
    });

    await next(context);
});

app.UseAuthentication();
app.UseAuthorization();
```

The callback runs just before headers are sent, which is when the Katana override ran. That timing is the point: it observes the final status code and the authenticated user, and it survives a downstream `Response.Clear()` — so status-conditional logic ported straight from the Katana body still works. Writing the header before `await next(context)` instead looks equivalent and is not; it cannot see the final status, and an exception handler that clears the response discards it.

`Response.OnStarting` is only a trap when it is registered from `HandleAuthenticateAsync`, because then it is only registered on the requests that reach that override. Registered from middleware, it is the faithful shape. Move logic into `HandleChallengeAsync` or `HandleForbiddenAsync` only when it was guarded by *that specific outcome* inside the Katana override.

### Step 5: Convert Options and Register the Scheme

1. Change the options base class to `AuthenticationSchemeOptions`. Delete the authentication type and authentication mode members; neither has a Core counterpart on the options object.
2. Move constructor argument checks into an `override void Validate()`. The framework calls it during handler initialization, so a misconfigured scheme fails at first use with a clear message instead of misbehaving.
3. Use the three-argument handler base constructor: `IOptionsMonitor<TOptions>`, `ILoggerFactory`, `UrlEncoder`. The four-argument overload taking `ISystemClock` is obsolete; a handler that needs the current time reads `TimeProvider` from `AuthenticationSchemeOptions`. Using the obsolete overload produces a warning rather than an error, so it survives a build that is not warning-clean.
4. Delete the `AuthenticationMiddleware<TOptions>` subclass. It has no counterpart.
5. Replace the `IAppBuilder.UseXxx` extension with an `AuthenticationBuilder.AddXxx` extension that calls `AddScheme<TOptions, THandler>(scheme, displayName, configureOptions)`.

```csharp
services.AddAuthentication(SampleDefaults.AuthenticationScheme)
    .AddSample(SampleDefaults.AuthenticationScheme, displayName: null, options =>
    {
        options.HeaderName = "X-Sample-Credential";
    });
```

### Step 6: Place Configuration and Dependencies

Katana resolved everything at startup and captured it on the options object. ASP.NET Core separates two concerns that must not be merged.

**Late-bound configuration values** — anything read from configuration, key vault, or a hosting environment — belong in an `IConfigureNamedOptions<TOptions>` or `IPostConfigureOptions<TOptions>` registration.

```csharp
builder.Services.TryAddEnumerable(
    ServiceDescriptor.Singleton<IConfigureOptions<SampleAuthenticationOptions>, ConfigureSampleAuthenticationOptions>());
```

The registered service type is `IConfigureOptions<TOptions>`, but the implementation must implement `IConfigureNamedOptions<TOptions>`. `AddScheme` stores options under the scheme name and the base handler reads them with `IOptionsMonitor<TOptions>.Get(Scheme.Name)`. An implementation that only implements the unnamed interface is registered, resolved, and then skipped for every named scheme, because the options factory calls unnamed configurators only for the default name. Nothing throws, nothing logs, and the options object arrives with its property initializers intact.

**Runtime collaborators** — a user store, a credential validator, a `DbContext`, an HTTP client — belong in the handler's constructor.

```csharp
public SampleAuthenticationHandler(
    IOptionsMonitor<SampleAuthenticationOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    ISampleCredentialValidator validator)
    : base(options, logger, encoder)
```

`AddScheme` registers the handler as transient and the framework activates it from `HttpContext.RequestServices`, so scoped collaborators are resolved once per request and are safe here. Assigning a resolved service to a property on the options object instead is a captive dependency: options and their configurators are singletons, so a scoped service captured there outlives its scope, and a `DbContext` captured that way is shared across concurrent requests.

### Step 7: Make the Scheme Actually Run

This step has no Katana counterpart to port, which is exactly why it is skipped. `UseAuthentication()` runs the request handlers of every scheme that implements `IAuthenticationRequestHandler`, and then authenticates only the default authenticate scheme. A scheme added with `AddScheme` and named by nobody never executes.

**`AuthenticationMode` defaults to `Active` in Katana**, so a scheme whose options never assign it was Active and needs a translation — absence of the assignment is not evidence of Passive. Choose one translation:

| Situation | Translation |
|---|---|
| The ported scheme was the only Active scheme, and the host serves one credential kind | Make it the default: `AddAuthentication(SampleDefaults.AuthenticationScheme)`. |
| Other schemes exist, or the host also serves browser sign-in | Name it at every consumer: `[Authorize(AuthenticationSchemes = SampleDefaults.AuthenticationScheme)]`, or a policy with `AddAuthenticationSchemes`. |
| One host serves both browser cookies and API credentials on different paths | Add a policy scheme as the default and select per request with `ForwardDefaultSelector`. |

The signature symptom of skipping this step is an API client receiving a 302 to a login page instead of a 401 with a `WWW-Authenticate` header, because the cookie scheme remained the default and handled the challenge.

**Do not verify this step against an application that registers only the ported scheme.** When exactly one scheme is registered, ASP.NET Core promotes it to the default automatically, so a port that skipped this step entirely authenticates correctly and looks finished. The auto-selection stops the moment a second scheme is registered — which is what every real host does, and the reason this defect reaches production from a green spike. Verify against the host's full scheme set: registering a second scheme is what turns the auto-selection off.

A Katana handler whose `AuthenticationMode` was already `Passive` needs no translation; it was named explicitly then and is named explicitly now.

### Step 8: Wire, Validate, and Retire the OWIN Registration

1. Call `app.UseAuthentication()` before `app.UseAuthorization()`.
2. Confirm every consumer recorded in step 2 names the scheme with the same string.
3. Update the downstream readers of every environment entry recorded in step 2. Porting the handler's `IOwinContext.Set` calls to `HttpContext.Items` or a request feature is only half the change: the code that read those keys must be moved to the same store in the same pass. It keeps compiling either way and starts reading nothing.
4. Re-check the step 1 gate before deleting anything from the Framework host. Remove the Katana handler, middleware, `IAppBuilder` extension, and stage marker only once no endpoint the scheme protected is still served there.

Write these into the pull request description as the validation checklist:

- A request with a valid credential authenticates, and the resulting identity carries the same claim types the Katana handler produced.
- A request with no credential is anonymous and produces no authentication failure in the logs.
- A request with an invalid credential fails with a diagnosable reason.
- An unauthenticated request to a protected endpoint receives the same status code, headers, and body the Katana handler produced — a 401 with `WWW-Authenticate` for an API scheme, not a redirect.
- An authenticated but unauthorized request receives the forbid response, not the challenge response.
- Any other scheme on the same host still authenticates independently.
- Every value the Katana handler published through `IOwinContext.Set` reaches its consumer through `HttpContext.Items` or a feature.
- Anything the Katana handler wrote from `ApplyResponseCoreAsync` is present on a successful response *and* on a challenge response. Check both: placing it in the handler instead of middleware yields one or the other, never both.
- If the Framework host still serves protected endpoints, it still authenticates them.

## Success Criteria

Verifiable when this skill completes:

- No type in the migrated code derives from `Microsoft.Owin.Security.Infrastructure.AuthenticationHandler<TOptions>` or `AuthenticationMiddleware<TOptions>` in the Core host, and no such type was converted to `app.UseMiddleware<T>()`.
- The options type derives from `AuthenticationSchemeOptions` and validates its own configuration in an `override void Validate()`.
- The handler uses the non-obsolete three-argument base constructor.
- `HandleAuthenticateAsync` returns `NoResult` for a missing credential and `Fail` only for an invalid one.
- The 401 and 403 paths are implemented separately in `HandleChallengeAsync` and `HandleForbiddenAsync`.
- The scheme is registered with `AddScheme` behind an `AuthenticationBuilder` extension, and no `IAppBuilder` extension remains in the Core host.
- Any configuration binding is registered as `IConfigureNamedOptions<TOptions>` or `IPostConfigureOptions<TOptions>`; no service instance is stored on the options object.
- The scheme is reachable: it is either the default authenticate scheme, named by every consumer, or selected by a policy scheme.
- `UseAuthentication()` precedes `UseAuthorization()`.
- Every reader of an environment entry the Katana handler published has been moved to the same store the ported handler writes to.
- Either the Katana registration is still in place, or the step 1 gate was settled and the summary says on what evidence.

Confirmed by the operator after deployment, not by the agent:

- Valid, missing, and invalid credentials produce the same outcomes they produced under Katana.
- Challenge and forbid responses match the previous status codes, headers, and bodies.
- Existing clients that name the scheme continue to authenticate.
- Every endpoint the scheme protected is still authenticated by whichever host now serves it.
