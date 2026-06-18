---
name: integrating-autofac-with-dotnet
description: >
  Migrates Autofac dependency injection configuration from ASP.NET Framework to ASP.NET Core's
  hosting model while keeping Autofac as the DI container. Use when upgrading projects that use
  Autofac, migrating Global.asax.cs or Startup.cs DI setup to Program.cs, or integrating
  AutofacServiceProviderFactory with the generic host. Triggers for Autofac container registration,
  UseServiceProviderFactory, ContainerBuilder migration, and DependencyResolver removal.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Register Autofac with ASP.NET Core

## Overview

When migrating from ASP.NET Framework to ASP.NET Core, Autofac integration changes significantly. The old pattern of manually building a container and setting `DependencyResolver` is replaced by registering Autofac as the host's service provider factory. This ensures Autofac participates in the standard DI lifecycle rather than bypassing it.

> **Related skill:** If the goal is to remove Autofac entirely and replace with built-in DI, use `migrating-autofac-to-dotnet-di` instead.

## Workflow

```
Migration Progress:
- [ ] Step 1: Verify Autofac usage
- [ ] Step 2: Install required package
- [ ] Step 3: Locate and extract existing registrations
- [ ] Step 4: Register Autofac as service provider factory
- [ ] Step 5: Migrate container registrations
- [ ] Step 6: Remove obsolete integration code
- [ ] Step 7: Validate
```

### Step 1: Verify Autofac usage

- Confirm the project uses Autofac for dependency injection. If not, skip — inform the user there is nothing to do.
- Check if `Program.cs` already calls `UseServiceProviderFactory(new AutofacServiceProviderFactory())`. If so, verify the container configuration is correct and skip remaining steps.

### Step 2: Install required package

Install `Autofac.Extensions.DependencyInjection` with a version matching the project's target framework. This package provides the `AutofacServiceProviderFactory` bridge between Autofac and the .NET hosting model.

### Step 3: Locate and extract existing registrations

Search for Autofac registration code that builds a container — typically in `Global.asax.cs`, `Startup.cs`, or other top-level initialization classes. Record all `ContainerBuilder` registrations and module registrations before removing that code.

> **Why remove first?** The old code manually calls `builder.Build()` and sets a `DependencyResolver`, which conflicts with the host-managed container lifecycle in ASP.NET Core.

### Step 4: Register Autofac as service provider factory

Add to `Program.cs`:

```csharp
builder.Host.UseServiceProviderFactory(new AutofacServiceProviderFactory());
```

### Step 5: Migrate container registrations

Move all extracted registrations into a `ConfigureContainer` block in `Program.cs`:

```csharp
builder.Host.ConfigureContainer<ContainerBuilder>(containerBuilder =>
{
    containerBuilder.RegisterType<MyService>().As<IMyService>();
    containerBuilder.RegisterModule(new MyAutofacModule());
});
```

Omit any calls to `builder.Build()` or resolver setup — the host handles container building automatically.

### Step 6: Remove obsolete integration code

Delete ASP.NET Framework-specific Autofac wiring such as:
- `DependencyResolver.SetResolver(new AutofacDependencyResolver(container));`
- `GlobalConfiguration.Configuration.DependencyResolver = resolver;`
- Manual `ContainerBuilder.Build()` calls in startup code

### Step 7: Validate

- Build the project and fix any compilation errors.
- Verify services resolve correctly at runtime.

## Example

**Before** (Global.asax.cs or Startup.cs):
```csharp
var builder = new ContainerBuilder();
builder.RegisterType<MyService>().As<IMyService>();
builder.RegisterType<MyRepository>().As<IRepository>();
builder.RegisterModule<MyModule>();
var container = builder.Build();
DependencyResolver.SetResolver(new AutofacDependencyResolver(container));
```

**After** (Program.cs):
```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Host.UseServiceProviderFactory(new AutofacServiceProviderFactory());

builder.Host.ConfigureContainer<ContainerBuilder>(containerBuilder =>
{
    containerBuilder.RegisterType<MyService>().As<IMyService>();
    containerBuilder.RegisterType<MyRepository>().As<IRepository>();
    containerBuilder.RegisterModule<MyModule>();
});

var app = builder.Build();
```

## Success Criteria

- `Autofac.Extensions.DependencyInjection` package installed
- `UseServiceProviderFactory` configured in Program.cs
- All registrations and modules migrated to `ConfigureContainer` block
- Obsolete `DependencyResolver` and manual `Build()` calls removed
- Project compiles and services resolve correctly at runtime
