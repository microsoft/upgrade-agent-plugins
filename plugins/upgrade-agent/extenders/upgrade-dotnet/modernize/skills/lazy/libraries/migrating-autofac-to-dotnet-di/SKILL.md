---
name: migrating-autofac-to-dotnet-di
description: >
  Removes Autofac entirely and migrates to ASP.NET Core built-in DI by mapping container
  registrations, lifetimes, and module patterns. Use when upgrading .NET projects that reference
  Autofac packages, when converting ContainerBuilder registrations, or when replacing Autofac
  modules with IServiceCollection extensions. Triggers for "replace Autofac", "remove Autofac",
  "migrate to built-in DI", "convert dependency injection",
  Autofac.Extensions.DependencyInjection, RegisterType, InstancePerLifetimeScope, and
  ContainerBuilder references in C# or VB.NET projects.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Autofac to ASP.NET Core DI Migration

## Overview

Converts Autofac DI registrations to ASP.NET Core's built-in `IServiceCollection` pattern. The built-in container covers most registration scenarios; assembly scanning requires the Scrutor NuGet package.

> **Related skill:** If the goal is to keep Autofac but modernize its integration with ASP.NET Core, use `integrating-autofac-with-dotnet` instead.

## Verification

Before starting, confirm the project actually uses Autofac. Search for Autofac NuGet references and `ContainerBuilder` usage. If none found, inform the user there is nothing to migrate.

## Workflow

```
Migration Progress:
- [ ] Step 1: Locate Autofac registrations
- [ ] Step 2: Document all registrations
- [ ] Step 3: Remove Autofac code
- [ ] Step 4: Remove Autofac packages
- [ ] Step 5: Create registration helper
- [ ] Step 6: Wire into Program.cs
- [ ] Step 7: Build and verify
```

### Step 1: Locate Autofac registrations

Find `ContainerBuilder` setup code (check `global.asax.cs`, `Startup.cs`, or Autofac module classes).

### Step 2: Document all registrations

Record each service registration and its lifetime scope before removing anything.

### Step 3: Remove Autofac code

Delete the container builder code that will be replaced.

### Step 4: Remove Autofac packages

Remove `Autofac`, `Autofac.Extensions.DependencyInjection`, and any other Autofac-related NuGet packages.

### Step 5: Create registration helper

Add a static helper method that registers all services on `IServiceCollection`, using the lifetime mapping table below.

### Step 6: Wire into Program.cs

Call the helper method from `Program.cs`, passing `builder.Services`.

### Step 7: Build and verify

Build the project, fix any remaining Autofac references, confirm no regressions.

## Lifetime Mapping

| Autofac | ASP.NET Core DI | Notes |
|---------|-----------------|-------|
| `InstancePerDependency()` | `AddTransient<T>()` | Default Autofac lifetime |
| `InstancePerLifetimeScope()` | `AddScoped<T>()` | One per request in web apps |
| `InstancePerRequest()` | `AddScoped<T>()` | Web-specific alias for scoped |
| `SingleInstance()` | `AddSingleton<T>()` | |
| `RegisterInstance(obj)` | `AddSingleton(obj)` | |
| `RegisterAssemblyTypes(...)` | `services.Scan(...)` | Requires Scrutor package |

## Common Patterns

**Interface registration:**
```csharp
// Autofac
builder.RegisterType<MyService>().As<IMyService>().InstancePerLifetimeScope();
// Built-in DI
services.AddScoped<IMyService, MyService>();
```

**Registration helper pattern** — isolates DI setup for testability and keeps `Program.cs` clean:
```csharp
// In Program.cs
var builder = WebApplication.CreateBuilder(args);
RegisterServices(builder.Services, builder.Configuration);
var app = builder.Build();

static void RegisterServices(IServiceCollection services, IConfiguration configuration)
{
    services.AddScoped<IMyService, MyService>();
    services.AddSingleton<IMyOtherService, MyOtherService>();
}
```

## Troubleshooting

- **Missing registrations at runtime** — Compare the documented Autofac registrations against the new helper method. Autofac's default lifetime is `InstancePerDependency` (transient), so unspecified lifetimes should map to `AddTransient`.
- **Assembly scanning** — If the project used `RegisterAssemblyTypes`, add the Scrutor NuGet package (`dotnet add package Scrutor`) and use `services.Scan(...)` to replicate the behavior.

## Success Criteria

- All Autofac packages removed from project files
- No `ContainerBuilder` or Autofac namespace references remain
- All service lifetimes correctly mapped per the table above
- Project builds without errors
