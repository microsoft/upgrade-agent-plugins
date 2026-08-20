---
name: migrating-mvc-system-web-adapters
description: >
  Provides System.Web Adapters overlay guidance for incremental ASP.NET Framework to ASP.NET Core
  migration. Installs Microsoft.AspNetCore.SystemWebAdapters compatibility shims so System.Web API
  patterns (HttpContext.Current, HttpModules, HttpHandlers, Session, ClaimsPrincipal.Current)
  continue working in ASP.NET Core during the migrate phase, then guides ordered decommission of
  each shim. Use when assessment signals include UsesSystemWeb, UsesHttpContextCurrent,
  UsesHttpModules, UsesHttpHandlers, UsesMvc, UsesWebApi, or UsesHttpSessionState and the
  System.Web Adapters option is confirmed. Also triggers for "system web adapters", "incremental
  migration shim", "side-by-side Framework and Core", or "adapter cleanup".
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# System.Web Adapters — Cross-Cutting Overlay

## Overview

This skill is a **transitional overlay**, not a migration target. The `Microsoft.AspNetCore.SystemWebAdapters` package provides compatibility shims that let `System.Web` API patterns coexist with ASP.NET Core during incremental migration. Without this guidance, the agent either breaks the build by replacing patterns too early or leaves shims in permanently.

> **Related skills:** `migrating-mvc-session-state` (full session migration), `migrating-mvc-http-pipeline` (full module/handler rewrite), `migrating-mvc-controllers` (HttpContext usage patterns). Those skills define the final migration targets; this skill defers their application during the migrate phase.

## Skill Precedence Rules

This skill is loaded as standing context for all tasks in the migrate phase when System.Web Adapters are confirmed. Where guidance conflicts with a feature skill, apply this table:

| Task Phase | Precedence | Effect |
|---|---|---|
| **Scaffold** | Adapter skill wins | Install adapters, defer replacements |
| **Migrate** | Adapter skill wins | Use shims, add TODO comments |
| **Decommission** | Feature skill wins | Replace shims with native Core patterns |

**Core rule:** Always defer, never improvise — if a shim exists for a pattern, use the shim during scaffold and migrate phases. Only migrate directly when no shim is available (see "No Shim Available" column in the surface tables below).

## Workflow — Migrate Phase

Track progress when setting up adapters:

```
Adapter Setup Progress:
- [ ] Step 1: Install NuGet package
- [ ] Step 2: Register services and middleware
- [ ] Step 3: Configure remote app (if side-by-side)
- [ ] Step 4: Apply HttpContext.Current shim
- [ ] Step 5: Apply HttpModule/HttpHandler shims
- [ ] Step 6: Apply session state shim
- [ ] Step 7: Apply request/response surface shims
- [ ] Step 8: Apply ClaimsPrincipal.Current shim
```

### Step 1: Install NuGet Package

Add the adapter package to the ASP.NET Core project:

```xml
<PackageReference Include="Microsoft.AspNetCore.SystemWebAdapters" Version="1.*" />
```

### Step 2: Register Services and Middleware

In `Program.cs`, register adapter services and middleware. Middleware order matters — place after routing, before endpoints:

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSystemWebAdapters();

var app = builder.Build();
app.UseRouting();
app.UseSystemWebAdapters(); // After routing, before endpoints
app.MapControllers();
```

### Step 3: Configure Remote App (Side-by-Side)

For true side-by-side migration where the Framework app and Core app run simultaneously, configure remote app connection for shared session and authentication state.

Which client registrations to write depends on the confirmed **Cross-App Cookie Authentication**
value. Write one of the two blocks below, not both.

Before either, check the floor: the Framework-side package below requires .NET Framework 4.7.2
or later. If the Framework host is below that and can be retargeted, retargeting it is a
prerequisite of this step — except under confirmed **Shared Cookie (Data Protection interop)**,
where identity does not depend on this step at all. There, retarget only if the migration
actually needs cross-host session, and otherwise leave the host where it is rather than moving
it for a package it will never use.

Whenever the host ends this check still below the floor — pinned there by a dependency that
cannot move, or deliberately left there under Shared Cookie — the remote app connection is
unavailable in **both** forms, remote authentication and remote session alike. Do not emit
wiring the host cannot restore, and do not write either block below. What that costs depends on
which mechanism is in play, so do not treat it as one outcome:

- **Confirmed Shared Cookie (Data Protection interop)** — authentication is unaffected. That
  mechanism carries no dependency on this package and supports far older Framework targets, so
  the Core host still gets identity from `sharing-authentication-cookies-katana-interop`. Only
  shared *session* is lost. Do not block on this: continue without the remote app connection,
  treat cross-host session state as unavailable, migrate the routes that do not depend on it,
  and report the ones that do.
- **Otherwise** — remote authentication was the only thing that was going to give the Core host
  identity, and the side-by-side gate in `migrating-mvc-authentication` also forbids giving that
  host its own cookie scheme. Continuing silently would leave authenticated Core routes with no
  authentication at all, so this is a blocking condition. Stop and report the conflict, naming
  the dependency that pins the host, so the operator can lift the pin, move to shared cookies if
  that host qualifies, or state that a session reset is acceptable. That last answer is the one
  resolution that needs an explicit statement to take effect — see the release described in the
  side-by-side gate in `migrating-mvc-authentication`; do not apply it on your own.

Absence of that option is **not** a decision, and it does not mean one thing. It is what you get
when the trigger never fired, when the option dropped out because no mechanism was available,
and when a session reset was accepted — and no execution-time evidence can tell those apart,
because a `Plan impact: No` option is never reopened. That ambiguity is not resolvable here, so
do not try to resolve it:

- **Confirmed Remote Authentication** → first block.
- **Confirmed Shared Cookie (Data Protection interop)** → second block.
- **No confirmed value** → first block, whatever the reason for the absence. Remote
  authentication with shared session is what a side-by-side migration got before this option
  existed, so it is the behavior absence maps to. Do not infer a session reset from silence,
  and do not read one out of the task's risk narrative either — prose written for a human
  reader is not a decision record. Wiring an authentication client nobody needed is recoverable;
  omitting one that was needed signs every user out at the host boundary with nobody having
  chosen that. If a Framework host does authenticate browser requests with a cookie, say
  plainly that no cross-app mechanism was confirmed and that this wiring is the default rather
  than a chosen one, so the omission is visible instead of silent.

  One exception, and it turns on positive evidence rather than on silence: if the Core host
  already carries shared-cookie interop wiring — a Data Protection key ring shared with the
  Framework host plus a matching cookie name, scheme, and application name, or the
  `README.SHAREDCOOKIE.md` handoff note the scaffold copies in — then a shared-cookie path was
  already chosen at scaffold time. Read that off the code the way Step 6 does, not from
  recollection. Write the first block without `AddAuthenticationClient()` in that case. Adding
  it on top of shared-cookie wiring authenticates every request twice, which is exactly the
  pairing the option's **Interactions** rules exist to prevent.

For **Remote Authentication** — remote authentication and shared session:

```csharp
builder.Services.AddSystemWebAdapters()
    .AddRemoteAppClient(options =>
    {
        options.RemoteAppUrl = new Uri("https://localhost:44300");
        options.ApiKey = builder.Configuration["RemoteAppApiKey"]!;
    })
    .AddAuthenticationClient()
    .AddSessionClient();
```

Omit the authentication client only when **Shared Cookie (Data Protection interop)** is confirmed. That mechanism already authenticates each request, so a remote authentication client would authenticate every request a second time and can produce a redirect loop behind the reverse proxy. Shared session is a separate concern and stays:

```csharp
builder.Services.AddSystemWebAdapters()
    .AddRemoteAppClient(options =>
    {
        options.RemoteAppUrl = new Uri("https://localhost:44300");
        options.ApiKey = builder.Configuration["RemoteAppApiKey"]!;
    })
    .AddSessionClient();
```

If the Core project was scaffolded with remote authentication already wired, omitting the call here is not enough — `AddAuthenticationClient(...)` is already present in `Program.cs`, so the double authentication persists. Remove that existing call too, leaving `AddRemoteAppClient` and `AddSessionClient` in place.

On the Framework side, install `Microsoft.AspNetCore.SystemWebAdapters.FrameworkServices` package and register the remote app server in `Global.asax.cs` or OWIN startup. That registration is where the matching `AddAuthenticationServer()` call goes — omit it too whenever the authentication client was omitted. The package requires the Framework host to target .NET Framework 4.7.2 or later. If the host is below that, apply the floor rule at the top of this step rather than deciding here. Shared cookies do not depend on this package, so a host that stays below the floor can still share the cookie if it otherwise qualifies.

Skip this step if the migration is a full cutover (not side-by-side).

### Step 4: HttpContext.Current Shim

The adapter exposes `HttpContext.Current` so that code accessing it continues to compile and function in ASP.NET Core.

**Feature skill says:** Replace with `IHttpContextAccessor` injection.
**Adapter override (migrate phase):** Defer replacement. The shim handles it.

Mark each usage site with a TODO comment for later cleanup:

```csharp
// TODO: adapter-cleanup — replace HttpContext.Current with IHttpContextAccessor
var user = System.Web.HttpContext.Current?.User;
```

The shim routes through `IHttpContextAccessor` internally, so there is no runtime penalty — this is purely about deferring the code change.

### Step 5: HttpModule and HttpHandler Shims

The adapter allows existing `IHttpModule` implementations to register without rewriting as middleware.

**Feature skill says:** Rewrite each module as ASP.NET Core middleware.
**Adapter override (migrate phase):** Register existing modules via adapter infrastructure.

```csharp
builder.Services.AddSystemWebAdapters()
    .AddHttpModule<MyLoggingModule>(); // TODO: adapter-cleanup — rewrite as middleware
```

For `IHttpHandler`, the adapter does not provide a direct shim. Handlers that serve specific routes should be converted to minimal API endpoints or controller actions immediately — no deferral is possible.

| Component | Shim Available | Migrate Phase Action |
|---|---|---|
| `IHttpModule` | Yes | Register via adapter, add TODO |
| `IHttpHandler` | No | Migrate directly to endpoint |
| `IHttpAsyncHandler` | No | Migrate directly to endpoint |
| `.ashx` generic handler | No | Migrate directly to endpoint |

### Step 6: Session State Shim

The adapter wraps ASP.NET Core's `ISession` to expose the `HttpSessionState` API surface.

**Feature skill says:** Replace `HttpSessionState` with `ISession` and typed accessors.
**Adapter override (migrate phase):** Enable wrapped session so `Session["key"]` syntax continues to work.

```csharp
builder.Services.AddSystemWebAdapters()
    .AddWrappedAspNetCoreSession(); // TODO: adapter-cleanup — replace with ISession
builder.Services.AddSession();
```

Existing `Session["key"]` access continues to function through the shim. Complex objects still require serialization — the shim does not add automatic serialization.

For side-by-side deployments, use `AddSessionClient()` / `AddSessionServer()` instead of `AddWrappedAspNetCoreSession()` to share session between Framework and Core apps — but only where Step 3 actually wired the remote app connection. Decide that from the code Step 3 left behind, not from recollection: register these only when the Core host has an `AddRemoteAppClient(...)` **and** the Framework host has the matching remote app server registration. If either is missing, do not register them — the wiring would have no working remote app behind it. That is the case whenever Step 3 ended with the Framework host below .NET Framework 4.7.2, whether it was pinned there or deliberately left there under confirmed **Shared Cookie (Data Protection interop)**. Keep the routes that depend on cross-host session on the Framework host and report them, exactly as Step 3 directs.

### Step 7: Request and Response Surface Shims

Some `HttpRequest` and `HttpResponse` members are shimmed; others must be migrated directly.

| API | Shim Available | Migrate Phase Action |
|---|---|---|
| `HttpRequest.QueryString` | Yes | Defer, add TODO |
| `HttpRequest.Form` | Yes | Defer, add TODO |
| `HttpRequest.Headers` | Yes | Defer, add TODO |
| `HttpRequest.Cookies` | Yes | Defer, add TODO |
| `HttpResponse.Write()` | Yes | Defer, add TODO |
| `HttpResponse.StatusCode` | Yes | Defer, add TODO |
| `HttpRequest.InputStream` | No | Replace with `Request.Body` |
| `HttpRequest.Files` | No | Replace with `IFormFile` |
| `HttpResponse.End()` | No | Remove — use `return` from action |
| `HttpResponse.AddHeader()` | No | Replace with `Response.Headers.Append()` |
| `HttpResponse.BinaryWrite()` | No | Replace with `Response.Body.WriteAsync()` |

For APIs without shims, migrate directly even during the migrate phase — there is no deferral option.

### Step 8: ClaimsPrincipal.Current Shim

The adapter makes `ClaimsPrincipal.Current` available without additional configuration. It works automatically once `AddSystemWebAdapters()` is registered.

```csharp
// TODO: adapter-cleanup — replace with HttpContext.User or injected ClaimsPrincipal
var identity = System.Security.Claims.ClaimsPrincipal.Current?.Identity;
```

Defer replacement, add TODO comment.

## Workflow — Decommission Phase

Once the Core project is fully functional and the Framework project can be shut down, remove adapters in dependency order. Removing shims in wrong order breaks the build.

```
Decommission Progress:
- [ ] Step 1: Catalogue all TODO adapter-cleanup comments
- [ ] Step 2: Replace HttpContext.Current with IHttpContextAccessor
- [ ] Step 3: Replace Session shims with ISession
- [ ] Step 4: Replace request/response shims with Core APIs
- [ ] Step 5: Replace ClaimsPrincipal.Current with HttpContext.User
- [ ] Step 6: Rewrite HttpModules as middleware
- [ ] Step 7: Remove adapter package and registrations
- [ ] Step 8: Verify build and run tests
```

### Decommission Gate Checklist

Do not begin decommission until all gates pass:

- [ ] All `TODO: adapter-cleanup` comments are catalogued and tracked
- [ ] New Core project is fully functional (all endpoints tested)
- [ ] Old Framework project is confirmed ready for shutdown
- [ ] No new code is being written against adapter shims

### Decommission Order

Remove shims in this order to avoid cascading build failures:

1. **HttpContext.Current** → Replace with `IHttpContextAccessor` per `migrating-mvc-controllers`
2. **Session shims** → Replace with `ISession` per `migrating-mvc-session-state`
3. **Request/Response shims** → Replace with ASP.NET Core `HttpRequest`/`HttpResponse` APIs
4. **ClaimsPrincipal.Current** → Replace with `HttpContext.User` or injected `ClaimsPrincipal`
5. **HttpModule registrations** → Rewrite as middleware per `migrating-mvc-http-pipeline`
6. **Remove adapter package** — Remove `Microsoft.AspNetCore.SystemWebAdapters` from project file, delete `AddSystemWebAdapters()` and `UseSystemWebAdapters()` from `Program.cs`

After each step, build the project and fix compilation errors before proceeding to the next step. Batch decommission across multiple shims is error-prone — work through the list sequentially.

## TODO Comment Convention

All adapter-deferred code must use this exact comment format for searchability:

```csharp
// TODO: adapter-cleanup — <description of what to replace and how>
```

Examples:

```csharp
// TODO: adapter-cleanup — replace HttpContext.Current with IHttpContextAccessor
// TODO: adapter-cleanup — replace Session["key"] with ISession.GetString("key")
// TODO: adapter-cleanup — rewrite MyLoggingModule as LoggingMiddleware
// TODO: adapter-cleanup — replace ClaimsPrincipal.Current with HttpContext.User
```

Search for all deferred work: `grep -r "adapter-cleanup" --include="*.cs"`

## Success Criteria

### Migrate Phase Complete

- `Microsoft.AspNetCore.SystemWebAdapters` package installed
- `AddSystemWebAdapters()` and `UseSystemWebAdapters()` registered in `Program.cs`
- Remote app configured if side-by-side deployment is used — or, when the Framework host ends Step 3 still below .NET Framework 4.7.2 (pinned there, or deliberately left there under confirmed **Shared Cookie (Data Protection interop)**), its unavailability recorded and cross-host session treated as lost under **Shared Cookie (Data Protection interop)**, and reported as a blocking conflict under any other mechanism
- All shim-eligible patterns deferred with `TODO: adapter-cleanup` comments
- All non-shimmed patterns (InputStream, End, AddHeader, IHttpHandler) migrated directly
- Project builds and runs against ASP.NET Core

### Decommission Phase Complete

- Zero `TODO: adapter-cleanup` comments remain in codebase
- All shims replaced with native ASP.NET Core patterns
- `Microsoft.AspNetCore.SystemWebAdapters` package removed from project file
- No `AddSystemWebAdapters()` or `UseSystemWebAdapters()` calls remain
- No `System.Web` namespace references remain
- Project builds without errors
