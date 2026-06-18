---
name: migrating-mvc-filters
description: >
  Migrates ASP.NET MVC global filters (GlobalFilterCollection, HandleErrorAttribute, FilterConfig)
  to ASP.NET Core exception handling middleware and filter pipeline. Use when upgrading MVC apps
  that register filters via GlobalFilters.Filters.Add(), have a FilterConfig.cs, use
  HandleErrorAttribute, or need to convert custom IActionFilter/IExceptionFilter implementations
  to ASP.NET Core equivalents. Also triggers for global error handling migration, MVC-to-Core
  filter conversion, and UseExceptionHandler setup.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC Global Filters Migration

## Overview

Migrate `GlobalFilterCollection`-based filters from ASP.NET MVC to ASP.NET Core middleware and filter pipeline. ASP.NET Core replaces `HandleErrorAttribute` with `UseExceptionHandler` middleware because middleware runs earlier in the pipeline and catches errors from all middleware, not just controller actions.

## Workflow

Track progress across these steps:

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

Convert any custom filters registered in `GlobalFilterCollection` to ASP.NET Core filter interfaces (`IActionFilter`, `IAsyncActionFilter`, `IExceptionFilter`, etc.). Register them in `Program.cs`:

```csharp
builder.Services.AddControllersWithViews(options =>
{
    options.Filters.Add<MyCustomFilter>();
});
```

ASP.NET Core filters use dependency injection natively, so constructor-injected services work without extra setup.

### Step 6: Remove FilterConfig

Remove `FilterConfig.cs` (or equivalent class that called `GlobalFilters.Filters.Add()`). Search for and remove all references to `GlobalFilters.Filters` across the codebase. If the class contained only filter registration code, delete the entire file; otherwise, remove only the filter-related code.

## Success Criteria

- `UseExceptionHandler` and `UseStatusCodePagesWithReExecute` configured in `Program.cs`
- Error and StatusErrorCode action methods exist in the main controller
- Error views created under `Views/Shared/` or appropriate controller folder
- Custom filters converted to ASP.NET Core interfaces and registered
- No `FilterConfig.cs` or `GlobalFilters.Filters` references remain
- Project builds without errors
