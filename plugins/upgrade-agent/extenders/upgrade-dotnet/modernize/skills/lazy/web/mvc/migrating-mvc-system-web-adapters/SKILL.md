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

For true side-by-side migration where the Framework app and Core app run simultaneously, configure remote app connection for shared session and authentication state:

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

On the Framework side, install `Microsoft.AspNetCore.SystemWebAdapters.FrameworkServices` package and register the remote app server in `Global.asax.cs` or OWIN startup.

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

For side-by-side deployments, use `AddSessionClient()` / `AddSessionServer()` instead of `AddWrappedAspNetCoreSession()` to share session between Framework and Core apps.

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
- Remote app configured if side-by-side deployment is used
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
