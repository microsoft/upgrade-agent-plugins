---
name: migrating-mvc-routing
description: >
  Converts ASP.NET MVC RouteCollection-based routing to ASP.NET Core endpoint routing with
  MapControllerRoute in Program.cs. Use when migrating RouteConfig.cs, RouteTable.Routes,
  routes.MapRoute, routes.MapMvcAttributeRoutes, or RouteCollection to ASP.NET Core. Also triggers
  for MVC routing upgrade, endpoint routing migration, and conventional route conversion.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC Routing Migration

Migrate ASP.NET MVC routing from `RouteCollection`/`RouteConfig.cs` to ASP.NET Core endpoint routing in Program.cs.

## Workflow

```
Migration Progress:
- [ ] Step 1: Locate route registration
- [ ] Step 2: Convert to ASP.NET Core routing
- [ ] Step 3: Handle MVC + API controllers
- [ ] Step 4: Preserve existing customizations
- [ ] Step 5: Remove RouteConfig
```

### Step 1: Locate Route Registration

Find all route registration code. Typically lives in `RouteConfig.cs`:

```csharp
public class RouteConfig
{
    public static void RegisterRoutes(RouteCollection routes)
    {
        routes.MapMvcAttributeRoutes();
        routes.IgnoreRoute("{resource}.axd/{*pathInfo}");
        routes.MapRoute(
            name: "Default",
            url: "{controller}/{action}/{id}",
            defaults: new { controller = "Catalog", action = "Index", id = UrlParameter.Optional }
        );
    }
}
```

### Step 2: Convert to ASP.NET Core Routing

**Default routes (no customization):** Replace with:

```csharp
app.MapDefaultControllerRoute();
```

**Custom routes:** Add `MapControllerRoute` calls in Program.cs. Inline defaults and optional parameters into the pattern string because ASP.NET Core uses pattern tokens instead of a separate defaults object:

```csharp
// Old: url: "{controller}/{action}/{id}", defaults: new { controller = "Catalog", action = "Index", id = UrlParameter.Optional }
// New:
app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Catalog}/{action=Index}/{id?}");
```

#### Route Pattern Conversion Reference

| Old (RouteCollection) | New (ASP.NET Core) |
|-----------------------|--------------------|
| `url: "{controller}/{action}/{id}"` | `pattern: "{controller}/{action}/{id?}"` |
| `defaults: new { controller = "Home" }` | `pattern: "{controller=Home}"` |
| `defaults: new { action = "Index" }` | `pattern: "{action=Index}"` |
| `id = UrlParameter.Optional` | `{id?}` |
| `routes.MapMvcAttributeRoutes()` | `app.MapControllers()` |

### Step 3: Handle MVC + API Controllers

If the project has both MVC and API controllers, register both attribute and conventional routing. Call `app.MapControllers()` before `app.MapControllerRoute()` so attribute-routed API controllers take precedence over conventional routes — otherwise conventional routes could intercept API requests:

```csharp
app.MapControllers(); // Attribute routing for API controllers
app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");
```

### Step 4: Preserve Existing Customizations

Keep any existing routing middleware on the application object and add new routes alongside it. Carry over method-chained customizations like `.RequireSystemWebAdapterSession()`:

```csharp
app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}")
    .RequireSystemWebAdapterSession();
```

### Step 5: Remove RouteConfig

1. Delete `RouteConfig.cs` (or equivalent file containing `RegisterRoutes`). Only delete if it contains no non-routing logic.
2. Remove all references to `RouteTable.Routes` across the codebase.
3. Clean up orphaned `using` statements and class references.

## Success Criteria

- All routes migrated to Program.cs with correct pattern syntax
- Both attribute and conventional routing configured when needed
- RouteConfig.cs removed and no `RouteTable.Routes` references remain
- Project builds without errors
