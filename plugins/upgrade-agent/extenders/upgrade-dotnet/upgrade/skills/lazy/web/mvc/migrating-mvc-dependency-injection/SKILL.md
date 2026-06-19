---
name: migrating-mvc-dependency-injection
description: >
  Migrates dependency injection configuration from ASP.NET Framework MVC and WebAPI projects to
  ASP.NET Core built-in DI or modernized third-party container integration. Use when upgrading
  projects that use DependencyResolver.SetResolver, config.DependencyResolver, custom
  IControllerFactory, custom IHttpControllerActivator, ServiceLocator.Current, or third-party
  containers (Autofac, Unity, Ninject, Castle Windsor). Also triggers for "migrate dependency
  injection", "convert DI container", "replace DependencyResolver", PerRequest lifetime mapping,
  IControllerActivator migration, and property injection patterns.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC/WebAPI Dependency Injection Migration

## Overview

Migrate `DependencyResolver`-based DI from ASP.NET MVC and WebAPI to ASP.NET Core's built-in `IServiceCollection`/`IServiceProvider` pattern, or modernize third-party container integration. ASP.NET Core has DI built into the framework — the `DependencyResolver` and `IDependencyScope` APIs no longer exist.

> **Related skills:**
> - To remove Autofac entirely and use built-in DI: see `migrating-autofac-to-dotnet-di`
> - To keep Autofac but modernize its integration: see `integrating-autofac-with-dotnet`

## Workflow

```
Migration Progress:
- [ ] Step 1: Inventory DI usage
- [ ] Step 2: Map service registrations and lifetimes
- [ ] Step 3: Register services in Program.cs
- [ ] Step 4: Migrate or remove third-party container
- [ ] Step 5: Migrate controller factory customizations
- [ ] Step 6: Eliminate Service Locator usage
- [ ] Step 7: Remove obsolete DI code
- [ ] Step 8: Build and verify
```

### Step 1: Inventory DI Usage

Search the project for these patterns to determine the migration scope:

| Pattern | Indicates |
|---------|-----------|
| `DependencyResolver.SetResolver` | MVC DI resolver |
| `config.DependencyResolver =` or `GlobalConfiguration.Configuration.DependencyResolver` | WebAPI DI resolver |
| `ContainerBuilder`, `IUnityContainer`, `IKernel`, `IWindsorContainer` | Third-party container |
| `ServiceLocator.Current` | Service Locator anti-pattern |
| `IControllerFactory` | Custom MVC controller factory |
| `IHttpControllerActivator` | Custom WebAPI controller activator |
| Property injection (`[Dependency]`, `InjectProperty`) | Property injection patterns |

Record every service registration and its lifetime before changing anything.

### Step 2: Map Service Registrations and Lifetimes

Document all service registrations from the existing container configuration. Map each lifetime to its ASP.NET Core equivalent:

| Framework Lifetime | ASP.NET Core | Method |
|--------------------|-------------|--------|
| Per-request / `InstancePerRequest` / `HierarchicalLifetimeManager` | Scoped | `AddScoped<TService, TImpl>()` |
| Singleton / `SingleInstance` / `ContainerControlledLifetimeManager` | Singleton | `AddSingleton<TService, TImpl>()` |
| Transient / `InstancePerDependency` / `TransientLifetimeManager` | Transient | `AddTransient<TService, TImpl>()` |
| Per-thread / `PerThreadLifetimeManager` | Scoped | `AddScoped<TService, TImpl>()` |
| `ExternallyControlledLifetimeManager` | Transient | `AddTransient<TService, TImpl>()` |

Per-thread lifetime maps to Scoped because ASP.NET Core processes each request on a single thread from the thread pool, making the semantics equivalent for web scenarios.

### Step 3: Register Services in Program.cs

Move all service registrations to `builder.Services` in `Program.cs`. Create an extension method to keep `Program.cs` clean when there are many registrations:

**Before** (Global.asax.cs or App_Start):
```csharp
var container = new UnityContainer();
container.RegisterType<IOrderService, OrderService>(new HierarchicalLifetimeManager());
container.RegisterType<IRepository, SqlRepository>(new TransientLifetimeManager());
DependencyResolver.SetResolver(new UnityDependencyResolver(container));
```

**After** (Program.cs):
```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllersWithViews();
builder.Services.RegisterApplicationServices();

// Extension method in a separate file
public static class ServiceRegistration
{
    public static IServiceCollection RegisterApplicationServices(this IServiceCollection services)
    {
        services.AddScoped<IOrderService, OrderService>();
        services.AddTransient<IRepository, SqlRepository>();
        return services;
    }
}
```

If `HttpContext.Current` was used anywhere in the project, register the accessor:

```csharp
builder.Services.AddHttpContextAccessor();
```

### Step 4: Migrate or Remove Third-Party Container

Choose the appropriate path based on the container in use and the desired outcome.

#### Option A: Replace with built-in DI (recommended for simple registrations)

Remove the third-party container entirely. Map all registrations to `IServiceCollection` using the lifetime table in Step 2. Remove all container-specific NuGet packages.

#### Option B: Keep the third-party container with Core integration

When the project relies on advanced container features (modules, decorators, interceptors, child containers), keep the container but modernize the integration.

**Autofac:**
```csharp
// Install: Autofac.Extensions.DependencyInjection
builder.Host.UseServiceProviderFactory(new AutofacServiceProviderFactory());
builder.Host.ConfigureContainer<ContainerBuilder>(containerBuilder =>
{
    containerBuilder.RegisterModule<MyModule>();
});
```

**Unity:**
```csharp
// Install: Unity.Microsoft.DependencyInjection
builder.Host.UseUnityServiceProvider(container =>
{
    container.RegisterType<IMyService, MyService>();
});
```

**Castle Windsor:**
```csharp
// Install: Castle.Windsor.MsDependencyInjection
var windsorContainer = new WindsorContainer();
windsorContainer.Install(FromAssembly.This());
builder.Host.UseServiceProviderFactory(
    new WindsorServiceProviderFactory(windsorContainer));
```

**Ninject:** No official ASP.NET Core integration exists. Migrate all registrations to built-in DI (Option A) or switch to Autofac. Do not attempt to create a custom adapter — the `IServiceProvider` contract has subtleties that break under a naive wrapper.

### Step 5: Migrate Controller Factory Customizations

ASP.NET Core replaces both `IControllerFactory` (MVC) and `IHttpControllerActivator` (WebAPI) with `IControllerActivator`.

If the custom factory only existed to enable constructor injection, remove it entirely — ASP.NET Core injects constructor dependencies into controllers by default.

If the factory contains custom logic (e.g., selecting controller types dynamically, applying cross-cutting concerns):

**Before** (MVC):
```csharp
public class CustomControllerFactory : DefaultControllerFactory
{
    protected override IController GetControllerInstance(
        RequestContext requestContext, Type controllerType)
    {
        // Custom logic here
        return (IController)_container.Resolve(controllerType);
    }
}
```

**After:**
```csharp
public class CustomControllerActivator : IControllerActivator
{
    public object Create(ControllerContext context)
    {
        var controllerType = context.ActionDescriptor.ControllerTypeInfo.AsType();
        // Custom logic here
        return context.HttpContext.RequestServices.GetRequiredService(controllerType);
    }

    public void Release(ControllerContext context, object controller)
    {
        (controller as IDisposable)?.Dispose();
    }
}

// Register in Program.cs
builder.Services.AddSingleton<IControllerActivator, CustomControllerActivator>();
```

### Step 6: Eliminate Service Locator Usage

Replace all `ServiceLocator.Current.GetInstance<T>()` calls with constructor injection. The Service Locator pattern hides dependencies and makes testing difficult — ASP.NET Core does not support it.

**Before:**
```csharp
public class OrderProcessor
{
    public void Process()
    {
        var service = ServiceLocator.Current.GetInstance<IOrderService>();
        service.Execute();
    }
}
```

**After:**
```csharp
public class OrderProcessor
{
    private readonly IOrderService _orderService;

    public OrderProcessor(IOrderService orderService)
    {
        _orderService = orderService;
    }

    public void Process()
    {
        _orderService.Execute();
    }
}
```

For locations where constructor injection is not possible (e.g., static methods, legacy code paths that cannot be refactored immediately), inject `IServiceProvider` and resolve explicitly as a temporary measure:

```csharp
var service = serviceProvider.GetRequiredService<IOrderService>();
```

Mark these as technical debt with a TODO comment — they should eventually be refactored to constructor injection.

### Step 7: Remove Obsolete DI Code

Remove all Framework-specific DI artifacts:

- `DependencyResolver.SetResolver(...)` calls
- `GlobalConfiguration.Configuration.DependencyResolver = ...` assignments
- Custom `IDependencyResolver` implementations
- Custom `IDependencyScope` implementations
- `ServiceLocator.SetLocatorProvider(...)` calls
- `CommonServiceLocator` package reference
- Third-party container packages (if Option A was chosen in Step 4)

### Step 8: Build and Verify

Build the project and verify:

1. All services resolve at startup — missing registrations cause `InvalidOperationException` at first request
2. Scoped services are not injected into singletons — this is a common lifetime mismatch bug that ASP.NET Core validates by default in Development environment
3. `IHttpContextAccessor` is registered if any service depends on `HttpContext`

## Property Injection

The built-in container does not support property injection. If the project used property injection (Autofac `PropertiesAutowired()`, Unity `[Dependency]` attribute, Ninject `[Inject]` attribute):

1. **Preferred:** Convert to constructor injection — add the dependency as a constructor parameter
2. **If constructor injection is impractical** (e.g., deep inheritance hierarchies): keep a third-party container that supports property injection (Autofac with `PropertiesAutowired()` works with ASP.NET Core integration)

## Success Criteria

- No `DependencyResolver`, `IDependencyScope`, or `ServiceLocator` references remain
- All service lifetimes correctly mapped per the lifetime table
- Third-party container either removed or integrated via `UseServiceProviderFactory`
- Custom controller factory logic migrated to `IControllerActivator` or removed
- No property injection without explicit third-party container support
- `IHttpContextAccessor` registered if `HttpContext` access is needed outside controllers
- Project builds without errors
- Services resolve correctly at runtime
