---
name: migrating-mvc-logging
description: >
  Migrates ASP.NET Framework logging and diagnostics to ASP.NET Core built-in logging abstractions,
  error handling middleware, and health checks. Use when projects use System.Diagnostics.Trace,
  log4net, NLog, ELMAH, Serilog static loggers, customErrors in web.config, custom error pages,
  Application_Error, or need health check endpoints. Also triggers for "migrate logging", "replace
  ELMAH", "convert Trace to ILogger", "add health checks", "migrate error pages", and assessment
  signals UsesLog4Net, UsesNLog, UsesElmah, UsesSerilog, UsesTraceSource, UsesCustomErrorPages,
  UsesHealthChecks.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC Logging and Diagnostics Migration

## Overview

Migrate logging, error handling, and diagnostics from ASP.NET Framework patterns to ASP.NET Core equivalents. Framework apps typically used `System.Diagnostics.Trace`, third-party libraries (log4net, NLog, ELMAH, Serilog) with static access, `customErrors` in web.config, and `Application_Error` in Global.asax. Core provides a built-in `ILogger<T>` abstraction with dependency injection, exception handling middleware, and a health check framework.

> **Related skills:** `migrating-mvc-filters` covers `HandleErrorAttribute` → `UseExceptionHandler` conversion. `migrating-mvc-http-pipeline` covers `Application_Error` and logging module pipeline migration. This skill focuses on logging framework migration, error page configuration, and health checks.

## Workflow

Track progress across these steps:

```
Migration Progress:
- [ ] Step 1: Inventory logging and diagnostics usage
- [ ] Step 2: Configure built-in logging providers
- [ ] Step 3: Migrate logging framework calls
- [ ] Step 4: Migrate error pages and exception handling
- [ ] Step 5: Add health checks
- [ ] Step 6: Remove legacy logging references
```

### Step 1: Inventory Logging and Diagnostics Usage

Scan the project for all logging and diagnostics patterns:

- `System.Diagnostics.Trace` / `TraceSource` calls
- log4net references (`ILog`, `LogManager.GetLogger`, `log4net.config`)
- NLog references (`Logger`, `LogManager.GetCurrentClassLogger`, `NLog.config`)
- ELMAH references (`ErrorSignal`, `ErrorLog`, ELMAH HTTP modules in web.config)
- Serilog references (`Log.Information`, `Log.Error`, static `Log` class usage)
- `customErrors` section in web.config
- Custom error pages (`.aspx` or `.html` error pages)
- `Application_Error` in `Global.asax.cs`
- `HttpContext.Current` used for logging context

Record each pattern found. This inventory drives which sections below apply.

### Step 2: Configure Built-in Logging Providers

ASP.NET Core includes logging providers out of the box. Register them in `Program.cs`:

```csharp
var builder = WebApplication.CreateBuilder(args);

// Built-in providers are added by default (Console, Debug, EventSource, EventLog on Windows).
// To customize:
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.AddDebug();
```

Configure log levels in `appsettings.json`:

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning",
      "MyApp.DataAccess": "Debug"
    }
  }
}
```

This replaces `<system.diagnostics>` trace listener configuration in web.config and XML-based logging configuration files.

### Step 3: Migrate Logging Framework Calls

Apply the appropriate migration pattern based on the framework found in Step 1.

#### System.Diagnostics.Trace → ILogger\<T>

Replace static `Trace` calls with constructor-injected `ILogger<T>`. The `Trace` API has no log levels or structured logging — `ILogger<T>` provides both.

Before:
```csharp
using System.Diagnostics;

public class OrderService
{
    public void ProcessOrder(int orderId)
    {
        Trace.TraceInformation("Processing order {0}", orderId);
        try
        {
            // processing logic
        }
        catch (Exception ex)
        {
            Trace.TraceError("Order {0} failed: {1}", orderId, ex.Message);
            throw;
        }
    }
}
```

After:
```csharp
public class OrderService
{
    private readonly ILogger<OrderService> _logger;

    public OrderService(ILogger<OrderService> logger)
    {
        _logger = logger;
    }

    public void ProcessOrder(int orderId)
    {
        _logger.LogInformation("Processing order {OrderId}", orderId);
        try
        {
            // processing logic
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Order {OrderId} failed", orderId);
            throw;
        }
    }
}
```

Map `Trace` methods to `ILogger` methods:

| System.Diagnostics.Trace | ILogger\<T> |
|---|---|
| `Trace.TraceInformation(...)` | `_logger.LogInformation(...)` |
| `Trace.TraceWarning(...)` | `_logger.LogWarning(...)` |
| `Trace.TraceError(...)` | `_logger.LogError(...)` |
| `Trace.WriteLine(...)` | `_logger.LogDebug(...)` |
| `Debug.WriteLine(...)` | `_logger.LogDebug(...)` |

Use structured logging placeholders (`{OrderId}`) instead of format strings (`{0}`) because structured placeholders are captured as named properties by logging providers.

#### log4net → ILoggerProvider Adapter

log4net works in ASP.NET Core through the `Microsoft.Extensions.Logging.Log4Net.AspNetCore` adapter package. This preserves existing log4net configuration while routing through `ILogger<T>`.

Add the NuGet package and register in `Program.cs`:

```csharp
builder.Logging.AddLog4Net("log4net.config");
```

Then replace static `LogManager.GetLogger` calls with `ILogger<T>` injection:

Before:
```csharp
private static readonly ILog _log = LogManager.GetLogger(typeof(OrderService));

public void ProcessOrder(int orderId)
{
    _log.Info($"Processing order {orderId}");
}
```

After:
```csharp
private readonly ILogger<OrderService> _logger;

public OrderService(ILogger<OrderService> logger)
{
    _logger = logger;
}

public void ProcessOrder(int orderId)
{
    _logger.LogInformation("Processing order {OrderId}", orderId);
}
```

Move `log4net.config` to the project root and set it to copy to output directory. Existing appender configuration (file appenders, rolling file appenders) continues to work through the adapter.

#### NLog → NLog.Extensions.Logging

NLog integrates with ASP.NET Core through `NLog.Web.AspNetCore`. This is the recommended approach because it preserves NLog targets and rules.

Add the NuGet package and register in `Program.cs`:

```csharp
builder.Logging.ClearProviders();
builder.Host.UseNLog();
```

Most NLog layout renderers (`${aspnet-request}`, `${aspnet-session}`, `${aspnet-user-identity}`) work identically in Core through the `NLog.Web.AspNetCore` package. Replace static logger access with constructor injection:

Before:
```csharp
private static readonly Logger _logger = LogManager.GetCurrentClassLogger();
```

After:
```csharp
private readonly ILogger<OrderService> _logger;

public OrderService(ILogger<OrderService> logger)
{
    _logger = logger;
}
```

NLog targets (file, database, email) continue to work. The integration package bridges `ILogger<T>` calls to NLog's pipeline.

#### ELMAH → Serilog + Exception Middleware

ELMAH has no ASP.NET Core port. Replace it with a combination of structured logging (Serilog recommended) and exception handling middleware.

Add NuGet packages: `Serilog.AspNetCore`, and optionally `Serilog.Sinks.Seq` or `Serilog.Sinks.ApplicationInsights` for centralized error viewing.

Configure in `Program.cs`:

```csharp
builder.Host.UseSerilog((context, config) => config
    .ReadFrom.Configuration(context.Configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .WriteTo.File("logs/app-.log", rollingInterval: RollingInterval.Day));
```

Replace ELMAH error signaling with `ILogger`:

Before:
```csharp
catch (Exception ex)
{
    Elmah.ErrorSignal.FromCurrentContext().Raise(ex);
}
```

After:
```csharp
catch (Exception ex)
{
    _logger.LogError(ex, "Operation failed in {Method}", nameof(ProcessOrder));
}
```

Remove ELMAH NuGet packages (`Elmah`, `Elmah.Mvc`), HTTP modules from web.config, and the `elmah` configuration section. The ELMAH dashboard (`/elmah.axd`) is replaced by the Serilog sink dashboard (Seq UI, Application Insights, or log file inspection).

#### Static Logger Access → Constructor Injection

Any pattern that accesses a logger through a static field or service locator must change to constructor injection. ASP.NET Core's DI container provides `ILogger<T>` automatically — no registration needed.

Before (service locator pattern):
```csharp
public class OrderService
{
    private readonly ILog _logger = ServiceLocator.Current.GetInstance<ILog>();
}
```

After:
```csharp
public class OrderService
{
    private readonly ILogger<OrderService> _logger;

    public OrderService(ILogger<OrderService> logger)
    {
        _logger = logger;
    }
}
```

For classes not created by DI (e.g., utility or static helper classes), use `ILoggerFactory` obtained from DI and passed explicitly, or restructure the class to be DI-friendly.

### Step 4: Migrate Error Pages and Exception Handling

#### customErrors → Exception Handling Middleware

Replace `customErrors` in web.config with middleware in `Program.cs`:

Before (`web.config`):
```xml
<system.web>
  <customErrors mode="On" defaultRedirect="~/Error">
    <error statusCode="404" redirect="~/Error/NotFound" />
    <error statusCode="403" redirect="~/Error/Forbidden" />
    <error statusCode="500" redirect="~/Error/ServerError" />
  </customErrors>
</system.web>
```

After (`Program.cs`):
```csharp
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
}

app.UseStatusCodePagesWithReExecute("/Error/{0}");
```

The `UseExceptionHandler` middleware catches unhandled exceptions and re-executes the pipeline to the error path. `UseStatusCodePagesWithReExecute` handles non-exception status codes (404, 403) by re-executing to a status-specific route.

Create an `ErrorController` (or add to an existing controller):

```csharp
public class ErrorController : Controller
{
    [Route("Error")]
    public IActionResult Index()
    {
        return View();
    }

    [Route("Error/{statusCode}")]
    public IActionResult StatusCode(int statusCode)
    {
        return statusCode switch
        {
            404 => View("NotFound"),
            403 => View("Forbidden"),
            _ => View("GenericError", statusCode)
        };
    }
}
```

#### Application_Error → Exception Middleware or IExceptionHandler

If `Application_Error` in `Global.asax.cs` performed custom logging or error processing beyond displaying an error page, convert it to an `IExceptionHandler` implementation (.NET 8+):

Before (`Global.asax.cs`):
```csharp
protected void Application_Error()
{
    var exception = Server.GetLastError();
    Logger.Error("Unhandled exception", exception);
    Server.ClearError();
    Response.Redirect("~/Error");
}
```

After (`GlobalExceptionHandler.cs`):
```csharp
public class GlobalExceptionHandler : IExceptionHandler
{
    private readonly ILogger<GlobalExceptionHandler> _logger;

    public GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger)
    {
        _logger = logger;
    }

    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        _logger.LogError(exception, "Unhandled exception occurred");
        return false; // Let UseExceptionHandler handle the response
    }
}
```

Register in `Program.cs`:

```csharp
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
app.UseExceptionHandler("/Error");
```

#### Developer Exception Page

In development, ASP.NET Core shows a detailed exception page (replacing the Framework "yellow screen of death"). This is enabled by default when `ASPNETCORE_ENVIRONMENT` is `Development`. Verify it is not exposed in production:

```csharp
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/Error");
}
```

### Step 5: Add Health Checks

ASP.NET Framework has no built-in health check mechanism. ASP.NET Core provides `Microsoft.Extensions.Diagnostics.HealthChecks` for readiness and liveness probes.

Register health checks in `Program.cs`:

```csharp
builder.Services.AddHealthChecks()
    .AddSqlServer(
        builder.Configuration.GetConnectionString("DefaultConnection")!,
        name: "database",
        tags: new[] { "ready" })
    .AddCheck("self", () => HealthCheckResult.Healthy(), tags: new[] { "live" });
```

Map health check endpoints:

```csharp
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});

app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("live")
});
```

Add the `AspNetCore.HealthChecks.SqlServer` NuGet package for SQL Server checks. Other common packages:

| Dependency | Package |
|---|---|
| SQL Server | `AspNetCore.HealthChecks.SqlServer` |
| Redis | `AspNetCore.HealthChecks.Redis` |
| RabbitMQ | `AspNetCore.HealthChecks.Rabbitmq` |
| External URL | `AspNetCore.HealthChecks.Uris` |

Health checks are optional — add them only when the project deploys to an environment that supports health probes (Kubernetes, Azure App Service, load balancers). Skip this step if the deployment target does not use them.

### Step 6: Remove Legacy Logging References

Remove all legacy logging and error handling artifacts:

- Delete `customErrors` section from web.config
- Remove ELMAH NuGet packages and configuration sections from web.config
- Remove `Application_Error` from `Global.asax.cs` (if Global.asax is still present)
- Remove `using System.Diagnostics` where only used for `Trace` calls
- Remove static logger fields (`private static readonly ILog`, `private static readonly Logger`)
- Remove `HttpContext.Current` references used for logging context
- Search for remaining `Trace.`, `Debug.WriteLine`, `LogManager.Get`, `ErrorSignal.From` calls

## Common Patterns

### Logging in Middleware

When converting `IHttpModule` logging to middleware, inject `ILogger<T>` through the constructor:

```csharp
public class RequestTimingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestTimingMiddleware> _logger;

    public RequestTimingMiddleware(RequestDelegate next, ILogger<RequestTimingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var sw = Stopwatch.StartNew();
        await _next(context);
        sw.Stop();
        _logger.LogInformation("Request {Method} {Path} completed in {ElapsedMs}ms",
            context.Request.Method, context.Request.Path, sw.ElapsedMilliseconds);
    }
}
```

### Scoped Logging with Correlation IDs

Framework apps that used `HttpContext.Current.Items` to store correlation IDs should switch to `ILogger` scopes:

```csharp
using (_logger.BeginScope(new Dictionary<string, object>
{
    ["CorrelationId"] = context.Request.Headers["X-Correlation-Id"].FirstOrDefault()
        ?? Guid.NewGuid().ToString()
}))
{
    await _next(context);
}
```

## Troubleshooting

- **log4net configuration not loading**: Ensure `log4net.config` is set to "Copy to Output Directory" in the project file and the path in `AddLog4Net()` matches.
- **NLog layout renderers missing**: Install `NLog.Web.AspNetCore` (not just `NLog.Extensions.Logging`) for ASP.NET-specific layout renderers.
- **Health check endpoint returns 404**: Verify `MapHealthChecks` is called after `UseRouting()` in the middleware pipeline.
- **IExceptionHandler not invoked**: Requires .NET 8+. For earlier versions, use `UseExceptionHandler` with a lambda or a custom exception middleware.

## Success Criteria

- All `System.Diagnostics.Trace` / `TraceSource` calls replaced with `ILogger<T>`
- Third-party logging frameworks (log4net, NLog, Serilog) integrated via `ILoggerProvider` adapters or replaced
- ELMAH references removed and replaced with structured logging and exception middleware
- Static logger access patterns converted to constructor injection
- `customErrors` removed from web.config and replaced with `UseExceptionHandler` / `UseStatusCodePagesWithReExecute`
- `Application_Error` logic migrated to `IExceptionHandler` or exception middleware
- Health check endpoints configured (when applicable to deployment target)
- No references remain to `Elmah`, `Trace.TraceInformation`, `Trace.TraceError`, or `HttpContext.Current` for logging
- Project builds without errors
