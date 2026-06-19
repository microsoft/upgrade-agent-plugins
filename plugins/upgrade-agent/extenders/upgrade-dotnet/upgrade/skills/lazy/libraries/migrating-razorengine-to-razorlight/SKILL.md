---
name: migrating-razorengine-to-razorlight
description: >
  Migrates the deprecated RazorEngine to RazorLight for Razor
  template rendering outside of MVC. Use ONLY when RazorEngine
  has been flagged as deprecated or unmaintained and must be
  replaced — not for version-bump scenarios where RazorEngine
  is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# RazorEngine to RazorLight Migration

## Overview

Migrate Razor-based template rendering from `RazorEngine` to `RazorLight`. RazorEngine relies on a global static `Engine.Razor` singleton and synchronous compilation, which is incompatible with modern .NET. RazorLight provides an async-first API, built-in dependency injection support, and runs on .NET 6+. The core change is replacing `Engine.Razor.RunCompile()` with `RazorLightEngine.CompileRenderAsync()`.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="RazorEngine" Version="*" />
<!-- Also remove if present -->
<PackageReference Include="RazorEngine.NetCore" Version="*" />
```

### New Reference (Add)

```xml
<PackageReference Include="RazorLight" Version="{latest-stable}" />
```

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect RazorEngine usage
- [ ] Step 2: Update package references
- [ ] Step 3: Replace engine initialization
- [ ] Step 4: Migrate template rendering calls
- [ ] Step 5: Migrate custom template sources
- [ ] Step 6: Update caching logic
- [ ] Step 7: Build and verify
```

### Step 1: Detect RazorEngine Usage

Scan the project for:
- `using RazorEngine;` and `using RazorEngine.Templating;` statements
- Calls to `Engine.Razor.RunCompile()`, `Engine.Razor.Compile()`, `Engine.Razor.Run()`
- Custom `ITemplateSource` or `ITemplateResolver` implementations
- `TemplateServiceConfiguration` setup code

### Step 2: Update Package References

Remove `RazorEngine` (or `RazorEngine.NetCore`) and add `RazorLight` in the project file.

### Step 3: Replace Engine Initialization

| Old (RazorEngine) | New (RazorLight) |
|-------------------|------------------|
| `Engine.Razor` (global static, no setup) | `new RazorLightEngineBuilder().UseMemoryCachingProvider().Build()` |
| `var config = new TemplateServiceConfiguration(); var service = RazorEngineService.Create(config);` | `new RazorLightEngineBuilder().UseEmbeddedResourcesProject(typeof(MyClass)).Build()` |

Register the engine in DI as a singleton because `RazorLightEngine` is thread-safe and caches compiled templates:

```csharp
services.AddSingleton<IRazorLightEngine>(sp =>
    new RazorLightEngineBuilder()
        .UseMemoryCachingProvider()
        .Build());
```

### Step 4: Migrate Template Rendering Calls

All RazorLight rendering methods are async. Update call sites to use `await`.

| Old (RazorEngine) | New (RazorLight) |
|-------------------|------------------|
| `Engine.Razor.RunCompile(templateSource, "key", typeof(T), model)` | `await engine.CompileRenderStringAsync("key", templateSource, model)` |
| `Engine.Razor.Compile(templateSource, "key")` then `Engine.Razor.Run("key", typeof(T), model)` | `await engine.CompileRenderStringAsync("key", templateSource, model)` |
| `Engine.Razor.IsTemplateCached("key", typeof(T))` | Check via `engine.Options.CachingProvider.RetrieveTemplate("key")` |

The `typeof(T)` model-type parameter is not needed in RazorLight — the engine infers the model type automatically.

### Step 5: Migrate Custom Template Sources

If the project uses custom template resolution (loading templates from a database, embedded resources, or custom paths), implement RazorLight's `RazorLightProject`:

| Old (RazorEngine) | New (RazorLight) |
|-------------------|------------------|
| `ITemplateResolver` | Inherit from `RazorLightProject` |
| `ITemplateSource` | Return `RazorLightProjectItem` from your project |

Configure the engine to use the custom project:

```csharp
var engine = new RazorLightEngineBuilder()
    .UseProject(new MyCustomProject())
    .UseMemoryCachingProvider()
    .Build();
```

For file-based templates, use the built-in file project:

```csharp
var engine = new RazorLightEngineBuilder()
    .UseFileSystemProject("/path/to/templates")
    .Build();
```

### Step 6: Update Caching Logic

RazorLight handles caching internally via `ICachingProvider`. Remove any manual template caching code that was needed for RazorEngine. The `MemoryCachingProvider` (default) caches compiled templates in memory automatically.

### Step 7: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Test template rendering with representative templates
3. Verify dynamic model properties resolve correctly
4. Confirm async call chains propagate correctly through the application

## Troubleshooting

### Template Compilation Errors at Runtime

RazorLight compiles templates at runtime using the Razor SDK. Ensure the project targets a framework that includes the Razor runtime components. If targeting a worker service or console app, add `<PreserveCompilationContext>true</PreserveCompilationContext>` to the project file.

### Missing Model Properties

RazorLight uses `dynamic` models differently than RazorEngine. If using anonymous types, pass them as `ExpandoObject` instances or use strongly-typed models.

### Thread Safety

`RazorLightEngine` is thread-safe and should be registered as a singleton. Creating a new engine per request causes excessive compilation overhead and memory pressure.

### Cached Template Not Updating

During development, the memory caching provider does not detect source changes. Clear the cache or restart the application to pick up template edits.
