---
name: migrating-azure-functions-to-v2
description: >
  Migrates Azure Functions projects from legacy HostBuilder or in-process model to the modern
  Version 2.x pattern using IHostApplicationBuilder and Application Insights. Use when upgrading
  Azure Functions to isolated worker V2, replacing HostBuilder with
  FunctionsApplication.CreateBuilder, or adding Application Insights telemetry. Triggers for
  project files (.csproj, .vbproj, .fsproj) with Microsoft.Azure.Functions.Worker or
  Microsoft.NET.Sdk.Functions packages, and Program.cs files using HostBuilder patterns.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Azure Functions Version 2.x Migration

## Overview

Migrate Azure Functions projects to the Version 2.x hosting pattern (`IHostApplicationBuilder` via `FunctionsApplication.CreateBuilder`), replacing the legacy `HostBuilder` or in-process model, and enabling Application Insights telemetry.

> **Related skill:** For migrating from in-process Startup hooks to the isolated worker model first, use `migrating-azure-functions-startup`.

Two migration scenarios:
1. **In-process → Isolated V2**: From in-process model directly to isolated worker with V2
2. **Legacy Isolated → V2**: From isolated worker with legacy `HostBuilder` to V2

### Prerequisites
- Target framework must be .NET 8.0 or later (upgrade framework first if needed)
- For in-process apps: must be ready to migrate to isolated worker model

Reference: https://aka.ms/AAyl34o

## Workflow

Track migration progress:

```
Migration Progress:
- [ ] Phase 1: Identify current model
- [ ] Phase 2: Planning
- [ ] Phase 3, Step 1: Update package references
- [ ] Phase 3, Step 2: Create or update Program.cs
- [ ] Phase 3, Step 3: Update function signatures
- [ ] Phase 3, Step 4: Update dependency injection
- [ ] Phase 3, Step 5: Update host.json
```

### Phase 1: Identify Current Model

#### In-Process Model Indicators

**Package references in the project file:**
```xml
<PackageReference Include="Microsoft.NET.Sdk.Functions" Version="4.x.x" />
<PackageReference Include="Microsoft.Azure.WebJobs.Extensions.Http" Version="3.x.x" />
```

**Function code pattern:**
```csharp
public class MyFunctions
{
    [FunctionName("MyHttpFunction")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Function, "get")] HttpRequest req,
        ILogger log)
    {
        // Function code
    }
}
```

**Key indicator**: In-process apps do NOT have a `Program.cs` file (or have minimal one)

#### Legacy Isolated Worker Model Indicators

**Package references in the project file:**
```xml
<PackageReference Include="Microsoft.Azure.Functions.Worker" Version="1.x.x" />
<PackageReference Include="Microsoft.Azure.Functions.Worker.Sdk" Version="1.x.x" />
```

**Program.cs pattern:**
```csharp
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices((context, services) =>
    {
        // Service registrations here
    })
    .Build();

host.Run();
```

**Key indicators:**
- Uses `new HostBuilder()`
- Configuration wrapped in `ConfigureServices((context, services) => { ... })`
- Accesses configuration via `context.Configuration`

### Phase 2: Planning

#### For In-Process Projects

**Review function signatures:**
- List all functions needing signature updates
- Note trigger types and bindings used

**Check dependency injection:**
- Identify constructor-injected services in function classes
- Note use of `ExecutionContext` or `ILogger` parameters

**Document service configuration:**
- Note where services currently registered
- Identify custom configuration needed

#### For Legacy Isolated Projects

**Examine current `Program.cs`:**
- Note all service registrations in `ConfigureServices`
- Identify configuration access patterns using `context.Configuration`
- Check for custom host configuration

**Verify function signatures:**
- Ensure functions use isolated worker patterns
- Confirm use of `[Function]` attribute (not `[FunctionName]`)

#### Common Planning (Both Models)

**Check package versions:**
- Document current package versions
- Note if Application Insights packages present

**Verify Application Insights setup:**
- Check existing telemetry configuration
- Review `host.json` settings

**Determine ASP.NET Core integration:**
- Check if project uses ASP.NET Core middleware or HTTP abstractions
- Use `ConfigureFunctionsWebApplication()` if the project needs ASP.NET Core middleware pipeline (e.g., custom middleware, model binding). Otherwise use `ConfigureFunctionsWorkerDefaults()` for simpler setups.
- Reference: https://aka.ms/AAyl351

### Phase 3: Execution

#### Step 1: Update Package References

**For In-Process Projects (to Isolated V2):**

Remove:
```xml
<PackageReference Include="Microsoft.NET.Sdk.Functions" Version="4.x.x" />
<PackageReference Include="Microsoft.Azure.WebJobs.Extensions.Http" Version="3.x.x" />
<PackageReference Include="Microsoft.Azure.Functions.Extensions" Version="1.x.x" />
```

Add:
```xml
<PackageReference Include="Microsoft.Azure.Functions.Worker" Version="2.0.0" />
<PackageReference Include="Microsoft.Azure.Functions.Worker.Sdk" Version="2.0.0" />
<PackageReference Include="Microsoft.Azure.Functions.Worker.Extensions.Http" Version="3.2.0" />
<PackageReference Include="Microsoft.Azure.Functions.Worker.ApplicationInsights" Version="1.0.0" />
<PackageReference Include="Microsoft.ApplicationInsights.WorkerService" Version="2.22.0" />
```

**For Legacy Isolated Projects (Upgrade to V2):**

Update:
```xml
<!-- Before -->
<PackageReference Include="Microsoft.Azure.Functions.Worker" Version="1.x.x" />
<PackageReference Include="Microsoft.Azure.Functions.Worker.Sdk" Version="1.x.x" />

<!-- After -->
<PackageReference Include="Microsoft.Azure.Functions.Worker" Version="2.0.0" />
<PackageReference Include="Microsoft.Azure.Functions.Worker.Sdk" Version="2.0.0" />
```

Add if not present:
```xml
<PackageReference Include="Microsoft.Azure.Functions.Worker.ApplicationInsights" Version="1.0.0" />
<PackageReference Include="Microsoft.ApplicationInsights.WorkerService" Version="2.22.0" />
```

#### Step 2: Create or Update Program.cs

**For In-Process Projects: Create New Program.cs**

In-process projects typically don't have `Program.cs`. Create one in project root.

**Standard Functions (without ASP.NET Core integration):**
```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWorkerDefaults();

// Enable Application Insights telemetry
builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

// Add service registrations
// Example:
// builder.Services.AddSingleton<IMyService, MyService>();
// builder.Services.AddHttpClient();

// Access configuration directly
// var connectionString = builder.Configuration["ConnectionString"];
// builder.Services.AddSingleton<IDatabase>(new Database(connectionString));

builder.Build().Run();
```

**With ASP.NET Core integration:**
```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication(); // Use this for ASP.NET Core integration

// Enable Application Insights telemetry
builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

// Add service registrations

builder.Build().Run();
```

**Important:** `FunctionsApplication.CreateBuilder` replaces both `Host.CreateDefaultBuilder()` and `new HostBuilder()` because V2 requires the `IHostApplicationBuilder` interface for proper integration with the Functions runtime.

**For Legacy Isolated Projects: Migrate Existing Program.cs**

Transform from legacy pattern to Version 2.x.

**Before (Legacy HostBuilder):**
```csharp
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices((context, services) =>
    {
        services.AddSingleton<IMyService, MyService>();
        services.AddHttpClient();
        
        var connectionString = context.Configuration["ConnectionString"];
        services.AddSingleton<IDatabase>(new Database(connectionString));
    })
    .Build();

host.Run();
```

**After (Version 2.x IHostApplicationBuilder):**
```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWorkerDefaults();

// Enable Application Insights telemetry
builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

// Migrate service registrations (no ConfigureServices callback)
builder.Services.AddSingleton<IMyService, MyService>();
builder.Services.AddHttpClient();

// Configuration accessed directly via builder.Configuration
var connectionString = builder.Configuration["ConnectionString"];
builder.Services.AddSingleton<IDatabase>(new Database(connectionString));

builder.Build().Run();
```

**Key migration changes:**
1. Replace `new HostBuilder()` with `FunctionsApplication.CreateBuilder(args)`
2. Remove `ConfigureServices((context, services) => { ... })` callback wrapper
3. Access services directly via `builder.Services` instead of callback `services` parameter
4. Access configuration via `builder.Configuration` instead of `context.Configuration`
5. Add Application Insights telemetry calls
6. Use `builder.Build().Run()` instead of `host.Run()`

#### Step 3: Update Function Signatures (In-Process Only)

If migrating from in-process, update function signatures:

**Before (In-Process):**
```csharp
[FunctionName("MyHttpFunction")]
public async Task<IActionResult> Run(
    [HttpTrigger(AuthorizationLevel.Function, "get")] HttpRequest req,
    ILogger log)
{
    log.LogInformation("Processing request");
    return new OkObjectResult("Success");
}
```

**After (Isolated V2):**
```csharp
[Function("MyHttpFunction")]
public async Task<HttpResponseData> Run(
    [HttpTrigger(AuthorizationLevel.Function, "get")] HttpRequestData req)
{
    _logger.LogInformation("Processing request");
    
    var response = req.CreateResponse(HttpStatusCode.OK);
    await response.WriteStringAsync("Success");
    return response;
}
```

**Key changes:**
- `[FunctionName]` → `[Function]`
- `HttpRequest` → `HttpRequestData`
- `IActionResult` → `HttpResponseData`
- `ILogger` injected via constructor instead of parameter
- Use `req.CreateResponse()` to create responses

#### Step 4: Update Dependency Injection (In-Process Only)

**Before (In-Process with Startup.cs):**
```csharp
[assembly: FunctionsStartup(typeof(MyNamespace.Startup))]

public class Startup : FunctionsStartup
{
    public override void Configure(IFunctionsHostBuilder builder)
    {
        builder.Services.AddSingleton<IMyService, MyService>();
    }
}
```

**After (Isolated V2 in Program.cs):**
```csharp
var builder = FunctionsApplication.CreateBuilder(args);
builder.Services.AddSingleton<IMyService, MyService>();
builder.Build().Run();
```

#### Step 5: Update host.json (If Needed)

For V2, Application Insights is configured via code. Remove Application Insights configuration from `host.json` if present:

**Before:**
```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  }
}
```

**After:**
```json
{
  "version": "2.0"
}
```

Application Insights is now configured via:
```csharp
builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();
```

## Success Criteria

- Project targets .NET 8.0 or later
- Package references updated to V2 (2.0.0+)
- Program.cs uses FunctionsApplication.CreateBuilder pattern
- No HostBuilder() or Host.CreateDefaultBuilder() usage
- Service registrations use builder.Services directly
- Configuration accessed via builder.Configuration
- Application Insights telemetry configured
- If from in-process: Function signatures updated to isolated pattern
- If from in-process: [FunctionName] replaced with [Function]
- Project builds without errors
- All functions execute correctly
- Telemetry data flowing to Application Insights

## References

- [Version 2.x Model](https://aka.ms/AAyl34o)
- [ASP.NET Core Integration](https://aka.ms/AAyl351)
- [Migrate to isolated worker](https://learn.microsoft.com/en-us/azure/azure-functions/migrate-dotnet-to-isolated-model?tabs=net8)
- [Isolated process guide](https://learn.microsoft.com/en-us/azure/azure-functions/dotnet-isolated-process-guide?tabs=hostbuilder%2Cwindows)
