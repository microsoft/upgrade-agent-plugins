---
name: migrating-mvc-model-binding
description: >
  Migrates ASP.NET Framework model binding to ASP.NET Core, including binding source attributes,
  custom model binders, value providers, and over-posting protection. Use when upgrading MVC or
  Web API projects that use [FromUri], [FromBody], [ModelBinder], [Bind], TryUpdateModel, custom
  IModelBinder implementations, or ValueProviderFactories. Also triggers for binding source
  inference with [ApiController], IModelBinderProvider registration, and BindNever attribute
  migration.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET Model Binding Migration

## Overview

Migrate model binding infrastructure from ASP.NET Framework (MVC 5 / Web API 2) to ASP.NET Core. The core challenge is that binding source inference changed significantly — `[ApiController]` auto-infers binding sources, `[FromUri]` was split into `[FromQuery]` and `[FromRoute]`, and custom model binder registration moved from static collections to `IModelBinderProvider`.

## Workflow

Track progress across these steps:

```
Migration Progress:
- [ ] Step 1: Inventory binding usage
- [ ] Step 2: Migrate binding source attributes
- [ ] Step 3: Migrate custom model binders
- [ ] Step 4: Migrate value providers
- [ ] Step 5: Migrate over-posting protection
- [ ] Step 6: Verify build and runtime behavior
```

### Step 1: Inventory Binding Usage

Search the codebase for these patterns to determine which sections apply:

| Pattern | Indicates |
|---------|-----------|
| `[FromUri]` | Binding source attribute migration needed |
| `[FromBody]` | Review for strict single-body enforcement |
| `[ModelBinder(typeof(...))]` | Custom model binder attribute usage |
| `ModelBinders.Binders.Add` or `ModelBinders.Binders[typeof(...)]` | Global binder registration (MVC) |
| `config.BindParameter` or `BinderConfig` | Web API binder registration |
| `IModelBinder` (in project source) | Custom binder implementation to convert |
| `ValueProviderFactories.Factories.Add` | Value provider registration |
| `IValueProvider` (in project source) | Custom value provider to convert |
| `[Bind(Include = "...")]` or `[Bind(Exclude = "...")]` | Over-posting protection |
| `TryUpdateModel` or `TryUpdateModelAsync` | Manual model update calls |

### Step 2: Migrate Binding Source Attributes

#### `[FromUri]` → `[FromQuery]` / `[FromRoute]`

ASP.NET Core has no `[FromUri]`. Determine the correct replacement by checking whether the parameter is part of a route template or a query string:

**Before (Web API):**
```csharp
[Route("api/orders/{id}")]
public IHttpActionResult Get([FromUri] int id, [FromUri] string status)
{
    // id comes from route, status from query string
}
```

**After (ASP.NET Core):**
```csharp
[Route("api/orders/{id}")]
public IActionResult Get([FromRoute] int id, [FromQuery] string status)
{
    // Split based on whether parameter appears in route template
}
```

**Decision rule:** If the parameter name appears in the route template (`{id}`), use `[FromRoute]`. Otherwise, use `[FromQuery]`.

#### `[FromBody]` Behavior Change

`[FromBody]` exists in both frameworks, but ASP.NET Core enforces one `[FromBody]` parameter per action more strictly. If an action binds multiple complex types from the body, refactor to a single wrapper model.

#### `[ApiController]` Binding Source Inference

Controllers decorated with `[ApiController]` auto-infer binding sources, making many explicit attributes unnecessary:

| Parameter type | Inferred source |
|---------------|----------------|
| Complex types | `[FromBody]` |
| `IFormFile` / `IFormFileCollection` | `[FromForm]` |
| `CancellationToken` | `[FromServices]` (via DI) |
| Route template parameters | `[FromRoute]` |
| Everything else | `[FromQuery]` |

After migrating attributes, remove redundant ones that match inference rules. Keep explicit attributes when the inferred source would be wrong (e.g., a complex type that should come from query string).

### Step 3: Migrate Custom Model Binders

The `IModelBinder` interface exists in both frameworks but the method signature and context type differ entirely.

**Before (MVC 5):**
```csharp
public class DateRangeModelBinder : IModelBinder
{
    public object BindModel(ControllerContext controllerContext,
                            ModelBindingContext bindingContext)
    {
        var from = bindingContext.ValueProvider.GetValue("from");
        var to = bindingContext.ValueProvider.GetValue("to");
        return new DateRange(
            DateTime.Parse(from.AttemptedValue),
            DateTime.Parse(to.AttemptedValue));
    }
}

// Registration in Global.asax or App_Start
ModelBinders.Binders.Add(typeof(DateRange), new DateRangeModelBinder());
```

**After (ASP.NET Core):**
```csharp
public class DateRangeModelBinder : IModelBinder
{
    public Task BindModelAsync(ModelBindingContext bindingContext)
    {
        var fromValue = bindingContext.ValueProvider.GetValue("from").FirstValue;
        var toValue = bindingContext.ValueProvider.GetValue("to").FirstValue;

        if (DateTime.TryParse(fromValue, out var from) &&
            DateTime.TryParse(toValue, out var to))
        {
            bindingContext.Result = ModelBindingResult.Success(new DateRange(from, to));
        }
        else
        {
            bindingContext.ModelState.AddModelError(
                bindingContext.ModelName, "Invalid date range.");
        }

        return Task.CompletedTask;
    }
}
```

Key differences in the binder implementation:
- Method is async: `BindModel` → `BindModelAsync` returning `Task`
- No `ControllerContext` parameter — all context is on `ModelBindingContext`
- `ValueProviderResult.AttemptedValue` → `ValueProviderResult.FirstValue`
- Set `bindingContext.Result` instead of returning an object
- Report errors via `bindingContext.ModelState` instead of throwing

#### Registration via IModelBinderProvider

Replace static binder registration with an `IModelBinderProvider`:

```csharp
public class DateRangeModelBinderProvider : IModelBinderProvider
{
    public IModelBinder? GetBinder(ModelBinderProviderContext context)
    {
        if (context.Metadata.ModelType == typeof(DateRange))
        {
            return new DateRangeModelBinder();
        }
        return null;
    }
}

// Registration in Program.cs
builder.Services.AddControllersWithViews(options =>
{
    options.ModelBinderProviders.Insert(0, new DateRangeModelBinderProvider());
});
```

Insert at position 0 so custom binders take precedence over built-in ones. Alternatively, use `[ModelBinder(typeof(DateRangeModelBinder))]` on the parameter or type for targeted binding without global registration.

### Step 4: Migrate Value Providers

Custom `IValueProvider` implementations are structurally similar across frameworks. The main change is registration location.

**Before (Global.asax or App_Start):**
```csharp
ValueProviderFactories.Factories.Add(new CookieValueProviderFactory());
```

**After (Program.cs):**
```csharp
builder.Services.AddControllersWithViews(options =>
{
    options.ValueProviderFactories.Add(new CookieValueProviderFactory());
});
```

The `IValueProviderFactory` interface changed from a synchronous `GetValueProvider` method to an async `CreateValueProviderAsync` on `ValueProviderFactoryContext`:

**Before:**
```csharp
public class CookieValueProviderFactory : ValueProviderFactory
{
    public override IValueProvider GetValueProvider(ControllerContext context)
    {
        return new CookieValueProvider(context.HttpContext.Request.Cookies);
    }
}
```

**After:**
```csharp
public class CookieValueProviderFactory : IValueProviderFactory
{
    public Task CreateValueProviderAsync(ValueProviderFactoryContext context)
    {
        context.ValueProviders.Add(
            new CookieValueProvider(context.ActionContext.HttpContext.Request.Cookies));
        return Task.CompletedTask;
    }
}
```

### Step 5: Migrate Over-Posting Protection

#### `[Bind]` Attribute

`[Bind(Include = "Name,Email")]` still works in ASP.NET Core but `Bind(Exclude = "...")` is removed. Replace excluded properties with `[BindNever]` on the model:

**Before:**
```csharp
public ActionResult Create([Bind(Exclude = "IsAdmin")] User user) { }
```

**After — option A (`[BindNever]`):**
```csharp
public class User
{
    public string Name { get; set; }
    public string Email { get; set; }

    [BindNever]
    public bool IsAdmin { get; set; }
}
```

**After — option B (dedicated ViewModel, preferred):**
```csharp
public class CreateUserViewModel
{
    public string Name { get; set; }
    public string Email { get; set; }
    // IsAdmin intentionally omitted
}
```

Prefer dedicated ViewModels over `[Bind]` when the action only needs a subset of properties — it makes the binding contract explicit and avoids accidental exposure if new properties are added to the entity.

#### `TryUpdateModel` → `TryUpdateModelAsync`

`TryUpdateModel` is replaced by `TryUpdateModelAsync` in ASP.NET Core. The method is now async and the overload signatures differ:

**Before:**
```csharp
var user = db.Users.Find(id);
TryUpdateModel(user, new[] { "Name", "Email" });
```

**After:**
```csharp
var user = await db.Users.FindAsync(id);
await TryUpdateModelAsync(user, "", u => u.Name, u => u.Email);
```

The second parameter is the value prefix (empty string for top-level). Property selection uses lambda expressions instead of string arrays.

### Step 6: Verify Build and Runtime Behavior

1. Build the project and resolve any compilation errors from changed APIs.
2. Test model binding by exercising endpoints that accept complex parameters.
3. Verify that `[ApiController]` inference produces correct binding — watch for complex types unexpectedly bound from body when they should come from query.
4. Confirm custom model binders produce the same parsed values as the original implementation.
5. Verify over-posting protection by confirming excluded properties cannot be set via requests.

## Success Criteria

- No references to `[FromUri]` remain — replaced with `[FromQuery]` or `[FromRoute]`
- Custom `IModelBinder` implementations use the async signature and `ModelBindingResult`
- Custom binders registered via `IModelBinderProvider` in `Program.cs`, not `ModelBinders.Binders.Add`
- `ValueProviderFactories.Factories.Add` replaced with `MvcOptions.ValueProviderFactories`
- `[Bind(Exclude = "...")]` replaced with `[BindNever]` or dedicated ViewModels
- `TryUpdateModel` calls replaced with `await TryUpdateModelAsync`
- Project builds without binding-related errors
