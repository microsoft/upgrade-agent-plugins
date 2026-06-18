---
name: migrating-mvc-http-pipeline
description: >
  Migrates ASP.NET Framework HttpModules, HttpHandlers, and Global.asax events to ASP.NET Core
  middleware and endpoints. Use when projects contain IHttpModule, IHttpHandler, IHttpAsyncHandler,
  .ashx generic handlers, Global.asax Application_Start/Application_Error/Application_BeginRequest,
  or web.config httpModules/httpHandlers sections. Also triggers for "convert HttpModule to
  middleware", "migrate Global.asax", "replace HttpHandler", "pipeline ordering", or when
  assessment signals include UsesHttpModules, UsesHttpHandlers, UsesGlobalAsax, UsesCustomHandlers,
  or UsesManagedModules.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET HTTP Pipeline Migration — Modules, Handlers, and Global.asax

## Overview

Migrate the ASP.NET Framework HTTP pipeline (HttpModules, HttpHandlers, Global.asax) to ASP.NET Core middleware and endpoints. Pipeline ordering is the critical concern — module execution order directly affects authentication, logging, and error handling behavior, and must be reconstructed exactly in the Core middleware pipeline.

> **Adapter precedence**: If the `aspnet-system-web-adapters` skill is loaded, its guidance takes precedence over HttpModule and HttpHandler sections during scaffold and migrate task phases. Global.asax migration is NOT covered by adapters — always migrate directly using this skill.

## Workflow

Track progress across these steps:

```
Migration Progress:
- [ ] Step 1: Inventory pipeline components
- [ ] Step 2: Map pipeline ordering
- [ ] Step 3: Migrate Global.asax events
- [ ] Step 4: Convert HttpModules to middleware
- [ ] Step 5: Convert HttpHandlers to endpoints
- [ ] Step 6: Register middleware in correct order
- [ ] Step 7: Remove legacy pipeline references
```

### Step 1: Inventory Pipeline Components

Scan the project for all HTTP pipeline components:

- `web.config` — `<httpModules>`, `<httpHandlers>`, and `<system.webServer><modules>` / `<handlers>` sections
- Classes implementing `IHttpModule` or `IHttpHandler` / `IHttpAsyncHandler`
- `Global.asax` / `Global.asax.cs` — all `Application_*` and `Session_*` event methods
- `.ashx` files (generic handlers)

Record each component's purpose and the pipeline event it hooks into. This inventory drives all subsequent steps.

### Step 2: Map Pipeline Ordering

Reconstruct the pipeline execution order from `web.config` registration order and `Global.asax` event sequence. Modules execute in registration order for each event, and the order directly affects behavior.

ASP.NET Framework pipeline event order:

1. `BeginRequest`
2. `AuthenticateRequest` / `PostAuthenticateRequest`
3. `AuthorizeRequest` / `PostAuthorizeRequest`
4. `ResolveRequestCache`
5. `MapRequestHandler`
6. `AcquireRequestState`
7. `PreRequestHandlerExecute`
8. **Handler executes**
9. `PostRequestHandlerExecute`
10. `ReleaseRequestState`
11. `UpdateRequestCache`
12. `EndRequest`

Map each module's events to this sequence. Record the intended middleware order — this becomes the `app.Use*()` registration order in `Program.cs`.

### Step 3: Migrate Global.asax Events

Convert each `Global.asax` event method to its ASP.NET Core equivalent:

| Global.asax Event | ASP.NET Core Equivalent |
|---|---|
| `Application_Start` | `Program.cs` — code before `app.Run()` |
| `Application_End` | `IHostApplicationLifetime.ApplicationStopping` |
| `Application_Error` | `app.UseExceptionHandler()` middleware |
| `Application_BeginRequest` | Custom middleware (before `next()`) |
| `Application_EndRequest` | Custom middleware (after `next()`) |
| `Application_AuthenticateRequest` | Authentication middleware |
| `Session_Start` / `Session_End` | Removed — no equivalent in Core |

**Application_Start** — move initialization logic to `Program.cs`:

Before (`Global.asax.cs`):
```csharp
protected void Application_Start()
{
    AreaRegistration.RegisterAllAreas();
    FilterConfig.RegisterGlobalFilters(GlobalFilters.Filters);
    RouteConfig.RegisterRoutes(RouteTable.Routes);
    BundleConfig.RegisterBundles(BundleTable.Bundles);
    Database.SetInitializer(new MigrateDatabaseToLatestVersion<AppDbContext, Configuration>());
}
```

After (`Program.cs`):
```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllersWithViews();
// DB initializer moves to EF Core migration or service configuration
var app = builder.Build();
```

**Application_End** — register a shutdown callback:

```csharp
var lifetime = app.Services.GetRequiredService<IHostApplicationLifetime>();
lifetime.ApplicationStopping.Register(() =>
{
    // Cleanup logic from Application_End
});
```

**Session_Start / Session_End** — these events have no ASP.NET Core equivalent. Session state in Core is a simple key-value store without lifecycle events. Remove these methods and relocate any initialization logic to middleware that checks session state on each request.

### Step 4: Convert HttpModules to Middleware

Each `IHttpModule` becomes a middleware class. The module's `Init` method subscribed to pipeline events; the middleware's `InvokeAsync` replaces those subscriptions with code that runs before and/or after calling `next()`.

Before (`LoggingModule.cs`):
```csharp
public class LoggingModule : IHttpModule
{
    public void Init(HttpApplication context)
    {
        context.BeginRequest += OnBeginRequest;
        context.EndRequest += OnEndRequest;
    }

    private void OnBeginRequest(object sender, EventArgs e)
    {
        var app = (HttpApplication)sender;
        app.Context.Items["RequestStart"] = DateTime.UtcNow;
    }

    private void OnEndRequest(object sender, EventArgs e)
    {
        var app = (HttpApplication)sender;
        var start = (DateTime)app.Context.Items["RequestStart"];
        var elapsed = DateTime.UtcNow - start;
        Debug.WriteLine($"Request took {elapsed.TotalMilliseconds}ms");
    }

    public void Dispose() { }
}
```

After (`LoggingMiddleware.cs`):
```csharp
public class LoggingMiddleware
{
    private readonly RequestDelegate _next;

    public LoggingMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // BeginRequest equivalent — runs before the rest of the pipeline
        context.Items["RequestStart"] = DateTime.UtcNow;

        await _next(context);

        // EndRequest equivalent — runs after the rest of the pipeline
        var start = (DateTime)context.Items["RequestStart"]!;
        var elapsed = DateTime.UtcNow - start;
        Debug.WriteLine($"Request took {elapsed.TotalMilliseconds}ms");
    }
}
```

Key conversion rules:

- **BeginRequest** → code before `await _next(context)`
- **EndRequest** → code after `await _next(context)`
- **AuthenticateRequest / AuthorizeRequest** → authentication/authorization middleware; position relative to `UseAuthentication()` / `UseAuthorization()` is critical
- **PostAuthorizeRequest** → middleware registered immediately after `UseAuthorization()`
- **Error** → `app.UseExceptionHandler()` or a custom exception middleware wrapping `next()` in try/catch
- **Module state via `HttpContext.Items`** → `HttpContext.Items` exists in Core and works identically
- Inject services via constructor — Core middleware supports DI natively

### Step 5: Convert HttpHandlers to Endpoints

Each `IHttpHandler` maps to either a minimal API endpoint or a terminal middleware, depending on complexity.

**Simple handler → minimal API endpoint:**

Before (`StatusHandler.cs`):
```csharp
public class StatusHandler : IHttpHandler
{
    public bool IsReusable => true;

    public void ProcessRequest(HttpContext context)
    {
        context.Response.ContentType = "application/json";
        context.Response.Write("{\"status\":\"ok\"}");
    }
}
```

After (`Program.cs`):
```csharp
app.MapGet("/status", () => Results.Json(new { status = "ok" }));
```

**Async handler → async minimal API or middleware:**

Before (`ReportHandler.cs`):
```csharp
public class ReportHandler : IHttpAsyncHandler
{
    public IAsyncResult BeginProcessRequest(HttpContext context, AsyncCallback cb, object state)
    {
        // Async report generation
    }
    public void EndProcessRequest(IAsyncResult result) { }
    public void ProcessRequest(HttpContext context) { }
    public bool IsReusable => false;
}
```

After (`Program.cs`):
```csharp
app.MapGet("/report", async (ReportService reportService) =>
{
    var report = await reportService.GenerateAsync();
    return Results.File(report, "application/pdf");
});
```

**Generic handlers (.ashx)** — convert to a controller action or minimal API endpoint. There is no `.ashx` equivalent in Core. Move the `ProcessRequest` logic to the new endpoint method.

**Handler factory pattern** — if a custom `IHttpHandlerFactory` dispatches to different handlers based on the request, replace with route-based dispatch using `app.MapGet` / `app.MapPost` with distinct route patterns.

### Step 6: Register Middleware in Correct Order

Register all converted middleware in `Program.cs` in the exact order determined in Step 2. Middleware order in Core is the registration order — there is no event-based system.

Standard pipeline order for a typical migration:

```csharp
var app = builder.Build();

app.UseExceptionHandler("/Home/Error");  // Application_Error
app.UseHsts();
app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();

// Custom middleware from modules (BeginRequest-phase modules)
app.UseMiddleware<LoggingMiddleware>();

app.UseAuthentication();                 // AuthenticateRequest
app.UseAuthorization();                  // AuthorizeRequest

// Custom middleware from PostAuthorizeRequest modules
app.UseMiddleware<PostAuthMiddleware>();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

// Minimal API endpoints from converted handlers
app.MapGet("/status", () => Results.Json(new { status = "ok" }));
```

Pipeline ordering is the most common source of migration bugs. Verify that:
- Exception middleware is registered first (catches errors from all subsequent middleware)
- Authentication runs before authorization
- Custom modules that depend on auth state are registered after `UseAuthorization()`
- Logging/telemetry middleware wraps as much of the pipeline as the original module did

### Step 7: Remove Legacy Pipeline References

Remove all legacy pipeline artifacts:

- Delete `Global.asax` and `Global.asax.cs`
- Delete original `IHttpModule` implementation files
- Delete original `IHttpHandler` / `IHttpAsyncHandler` files
- Delete `.ashx` and `.ashx.cs` files
- Remove `<httpModules>`, `<httpHandlers>`, `<modules>`, and `<handlers>` sections from `web.config` (if `web.config` is still present)
- Remove `using System.Web` statements that are no longer needed
- Search for remaining references to `HttpApplication`, `IHttpModule`, `IHttpHandler`, and `HttpContext.Current` — these indicate incomplete migration

## Success Criteria

- All `IHttpModule` implementations converted to middleware classes
- All `IHttpHandler` / `IHttpAsyncHandler` implementations converted to endpoints or terminal middleware
- All `Global.asax` events migrated to `Program.cs`, lifetime hooks, or middleware
- `Session_Start` / `Session_End` removed with logic relocated or dropped
- Middleware registration order in `Program.cs` matches the original module execution order
- No references remain to `Global.asax`, `IHttpModule`, `IHttpHandler`, or `HttpContext.Current`
- No `.ashx` files remain in the project
- Project builds without errors
