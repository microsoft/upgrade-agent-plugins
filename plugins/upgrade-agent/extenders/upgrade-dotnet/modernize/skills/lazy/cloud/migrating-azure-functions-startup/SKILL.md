---
name: migrating-azure-functions-startup
description: >
  Migrates Azure Functions projects from in-process Startup hooks (FunctionsStartup,
  IFunctionsHostBuilder) to the isolated worker model with Program.cs service registration. Use
  when upgrading Azure Functions from in-process to isolated, migrating Startup.cs to Program.cs,
  removing Microsoft.Azure.Functions.Extensions, or converting FunctionsHostBuilderContext to
  HostBuilderContext. Triggers for Startup.cs, FunctionsStartup,
  ConfigureFunctionsWorkerDefaults, ConfigureFunctionsWebApplication, and project files (.csproj,
  .vbproj, .fsproj) referencing Microsoft.NET.Sdk.Functions.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Azure Functions Startup Hooks Migration

## Overview

Migrate Azure Functions from the in-process model (using `FunctionsStartup` and `IFunctionsHostBuilder`) to the isolated worker model, moving all service registrations and configuration from `Startup.cs` into `Program.cs`.

> **Related skill:** For upgrading an already-isolated project to the V2 hosting pattern (IHostApplicationBuilder), use `migrating-azure-functions-to-v2` instead.

The startup file may not be named `Startup.cs`.Identify it by looking for classes inheriting `FunctionsStartup`, usage of `IFunctionsHostBuilder` or `FunctionsHostBuilderContext`, or the `[assembly: FunctionsStartup(...)]` attribute. Throughout this skill, "Startup.cs" refers to whichever file contains these patterns.

## Workflow

Track progress using this checklist:

```
Migration Progress:
- [ ] Phase 1, Step 1: Get target framework
- [ ] Phase 1, Step 2: Determine in-process vs isolated
- [ ] Phase 1, Step 3: Determine upgrade path
- [ ] Phase 1, Step 4: Check ASP.NET Core integration
- [ ] Phase 2, Step 1: Remove obsolete packages
- [ ] Phase 2, Step 2: Comment out Startup.cs
- [ ] Phase 2, Step 3: Create or update Program.cs
- [ ] Phase 2, Step 4: Migrate service registrations
- [ ] Phase 2, Step 5: Handle build failures
- [ ] Phase 2, Step 6: Verify
```

### Phase 1: Assessment

#### Step 1: Get Target Framework

Open the project file and note `<TargetFramework>` (net6.0, net8.0, net9.0, etc.).

#### Step 2: Determine In-Process vs Isolated

**In-process indicators** (project file):
```xml
<PackageReference Include="Microsoft.NET.Sdk.Functions" Version="4.x.x" />
<PackageReference Include="Microsoft.Azure.WebJobs.Extensions.Http" Version="3.x.x" />
```

**Isolated indicators** (project file):
```xml
<PackageReference Include="Microsoft.Azure.Functions.Worker" Version="x.x.x" />
<PackageReference Include="Microsoft.Azure.Functions.Worker.Sdk" Version="x.x.x" />
```

Additional signals: in-process uses `[FunctionName]` attribute; isolated has `Program.cs` with a host builder.

#### Step 3: Determine Upgrade Path

- **Already isolated** → skip to Phase 2.
- **.NET 8 in-process** → ask user whether to also upgrade the framework, or just switch to isolated model.
- **.NET 6 in-process** → upgrade to .NET 8+ using isolated worker model (start .NET upgrade scenario flow).

#### Step 4: Check ASP.NET Core Integration

Determine whether the project uses ASP.NET Core integration. This controls the builder method in Program.cs:
- **With ASP.NET Core** → `ConfigureFunctionsWebApplication()`
- **Without** → `ConfigureFunctionsWorkerDefaults()`

### Phase 2: Execution

#### Step 1: Remove Obsolete Packages

Remove `Microsoft.Azure.Functions.Extensions` from the project file. This package only supports in-process and causes build conflicts with the isolated model.

#### Step 2: Comment Out Startup.cs

Comment out the entire class rather than deleting the file — this preserves the original code as a rollback reference until the user verifies the migration works.

```csharp
// Logic has been moved to Program.cs. Delete this file once migration is verified.
/*
[assembly: FunctionsStartup(typeof(MyNamespace.Startup))]

namespace MyNamespace
{
    public class Startup : FunctionsStartup
    {
        public override void Configure(IFunctionsHostBuilder builder)
        {
            builder.Services.AddSingleton<IMyService, MyService>();
        }
    }
}
*/
```

#### Step 3: Create or Update Program.cs

Use the appropriate builder method based on Step 4 above.

**Without ASP.NET Core integration:**
```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices((context, services) =>
    {
        // Migrated from Startup.cs
    })
    .Build();

host.Run();
```

**With ASP.NET Core integration:**
```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWebApplication()
    .ConfigureServices((context, services) =>
    {
        // Migrated from Startup.cs
    })
    .Build();

host.Run();
```

#### Step 4: Migrate Service Registrations

Move all registrations from `IFunctionsHostBuilder.Services` into the `ConfigureServices` lambda.

If `FunctionsHostBuilderContext` was used, replace with `HostBuilderContext` and add a comment explaining the scope change — in the in-process model, custom configuration could influence the host; in isolated mode it applies to the worker only.

**Before (Startup.cs):**
```csharp
public override void Configure(IFunctionsHostBuilder builder)
{
    var context = builder.GetContext();
    var connectionString = context.Configuration["ConnectionStrings:MyDb"];

    builder.Services.AddSingleton<IMyService, MyService>();
    builder.Services.AddDbContext<MyDbContext>(options =>
        options.UseSqlServer(connectionString));
}
```

**After (Program.cs):**
```csharp
.ConfigureServices((context, services) =>
{
    // Note: Custom configuration sources now apply to worker only (not host).
    var connectionString = context.Configuration["ConnectionStrings:MyDb"];

    services.AddSingleton<IMyService, MyService>();
    services.AddDbContext<MyDbContext>(options =>
        options.UseSqlServer(connectionString));
})
```

#### Step 5: Handle Build Failures

If build errors persist after migration, add a placeholder to signal incomplete migration and notify the user that manual review is required:

```csharp
.ConfigureServices((context, services) =>
{
    throw new NotImplementedException(
        "Migrate services from Startup.cs to ConfigureServices within Program.cs.");
})
```

#### Step 6: Verify

Confirm:
- Isolated worker packages are referenced; no in-process packages remain
- `Microsoft.Azure.Functions.Extensions` is removed
- Startup.cs is commented out with a deletion note
- Program.cs uses the correct builder method
- All service registrations and configuration are migrated
- Project builds without errors

Notify the user to review the migration, test all functions, and delete `Startup.cs` once verified.

## Success Criteria

- Project uses isolated worker model (`Microsoft.Azure.Functions.Worker` packages)
- No in-process packages remain (`Microsoft.NET.Sdk.Functions`, `Microsoft.Azure.WebJobs.*`)
- `Microsoft.Azure.Functions.Extensions` removed
- Startup.cs commented out (not deleted) with migration note
- Program.cs uses correct builder method
- All service registrations migrated; `FunctionsHostBuilderContext` replaced with `HostBuilderContext`
- Project builds without errors

## References

- [Migrate to isolated worker model](https://learn.microsoft.com/en-us/azure/azure-functions/migrate-dotnet-to-isolated-model?tabs=net8)
- [Isolated process guide](https://learn.microsoft.com/en-us/azure/azure-functions/dotnet-isolated-process-guide?tabs=hostbuilder%2Cwindows)
- [Dependency injection in Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-dotnet-dependency-injection)
- [ASP.NET Core integration](https://learn.microsoft.com/en-us/azure/azure-functions/dotnet-isolated-process-guide?tabs=hostbuilder%2Cwindows#aspnet-core-integration)
