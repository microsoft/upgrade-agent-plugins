---
name: migrating-global-asax
description: >
  Migrates Global.asax application lifecycle events to ASP.NET Core middleware, startup
  configuration, and Program.cs. Use when upgrading ASP.NET Framework apps containing Global.asax
  or Global.asax.cs files. Triggers for "migrate Global.asax", "convert application events",
  "move Application_Start to Program.cs", "replace Global.asax with middleware", and
  ASP.NET-to-Core migration involving request lifecycle, error handling, or session management.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Global.asax to ASP.NET Core Migration

## Overview

Converts `Global.asax.cs` application lifecycle event handlers into ASP.NET Core equivalents: service registration in `Program.cs`, custom middleware, and built-in middleware configuration.

## Workflow

```
Migration Progress:
- [ ] Step 1: Verify Global.asax exists
- [ ] Step 2: Audit event handlers
- [ ] Step 3: Triage each event
- [ ] Step 4: Convert events using mapping
- [ ] Step 5: Add required using statements
- [ ] Step 6: Remove Global.asax files
- [ ] Step 7: Verify build and behavior
```

### Step 1: Verify Global.asax Exists

Check if the project still has `Global.asax.cs`. If not, inform the user there is nothing to migrate and stop.

### Step 2: Audit Event Handlers

Inventory all application events in `Global.asax.cs`:

- `Application_Start`
- `Application_End`
- `Application_Error`
- `Application_BeginRequest` / `Application_EndRequest`
- `Session_Start` / `Session_End`
- Any custom event handlers

### Step 3: Triage Each Event

Determine whether each event is still needed. ASP.NET Core handles some concerns (like routing registration) through its built-in pipeline, so not every handler needs a direct replacement.

### Step 4: Convert Events Using the Mapping Below

Apply the [Event Conversion Mapping](#event-conversion-mapping) to migrate each needed handler to its ASP.NET Core equivalent.

### Step 5: Add Required Using Statements

Add any using statements needed by the new middleware or services in `Program.cs`.

### Step 6: Remove Global.asax Files

Delete both `Global.asax.cs` and `Global.asax` from the project. ASP.NET Core does not use them — keeping them causes confusion and they are never loaded by the runtime.

### Step 7: Verify

Build the project and confirm no compilation errors. Verify that the application behavior is preserved.

## Event Conversion Mapping

| Global.asax Event | ASP.NET Core Pattern | Why |
|---|---|---|
| `Application_Start` | Service registration in `Program.cs` | The DI container and pipeline replace manual initialization |
| `Application_End` | `IHostApplicationLifetime.ApplicationStopping` | Host lifetime events replace the application-level shutdown hook |
| `Application_Error` | `app.UseExceptionHandler()` | Built-in middleware provides structured error handling with logging |
| `Application_BeginRequest` | Custom middleware before `await next()` | The middleware pipeline replaces per-request event hooks |
| `Application_EndRequest` | Custom middleware after `await next()` | Code after `next()` runs on the response path |
| `Session_Start` / `Session_End` | `builder.Services.AddSession()` + `app.UseSession()` | ASP.NET Core manages sessions through explicit middleware opt-in |

## Conversion Examples

### Application_Start → Program.cs

```csharp
// Before: Global.asax.cs
protected void Application_Start()
{
    AreaRegistration.RegisterAllAreas();
    RouteConfig.RegisterRoutes(RouteTable.Routes);
}

// After: Program.cs
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllersWithViews();
var app = builder.Build();
app.MapControllers();
```

### Application_End → Shutdown Hook

```csharp
var lifetime = app.Services.GetRequiredService<IHostApplicationLifetime>();
lifetime.ApplicationStopping.Register(() =>
{
    // Cleanup logic from Application_End
});
```

### Application_Error → Exception Middleware

```csharp
app.UseExceptionHandler("/Home/Error");
```

### BeginRequest/EndRequest → Custom Middleware

```csharp
app.Use(async (context, next) =>
{
    // Logic from Application_BeginRequest
    await next();
    // Logic from Application_EndRequest
});
```

### Session Events → Session Middleware

```csharp
builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromMinutes(30);
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
});
app.UseSession();
```

## Troubleshooting

- **Custom events not in the mapping**: Implement as custom middleware or `IHostedService` depending on whether they are request-scoped or application-scoped.
- **Session state differences**: ASP.NET Core sessions are opt-in and require explicit middleware registration. If the app relied on implicit session behavior, add `UseSession()` and verify cookie settings.

## Success Criteria

- All needed Global.asax events converted to ASP.NET Core patterns
- `Global.asax.cs` and `Global.asax` files removed from project
- Project builds without errors
- Application functionality preserved
