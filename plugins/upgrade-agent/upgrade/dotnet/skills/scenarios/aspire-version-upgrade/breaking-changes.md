# Breaking Changes Reference

Frozen breaking-change reference for the Aspire Version Upgrade scenario, covering 8.x through 13.2. Every change listed here must be applied by hand-editing source, project and JSON files. For targets above 13.2, read the "Breaking changes" section of `aspire docs get whats-new-in-aspire-<major><minor>` for each newer version crossed.

How to read the markers:

- Unmarked rename or removal: the build fails until it is fixed (missing type or member).
- **CS0618 warning only**: the old API is obsolete but still compiles. Search for it, because a warning is easy to miss.
- **Not caught by the build**: the old code compiles cleanly, or the change is in behavior or in a JSON file. Search for these explicitly; a green build does not mean they are done.

## Contents

- [Version Transition Matrix](#version-transition-matrix)
  - [8.x → 9.0](#8x--90)
  - [9.0 → 9.3](#90--93)
  - [9.3 → 9.5](#93--95)
  - [9.5 → 13.0](#95--130)
  - [13.0 → 13.1](#130--131)
  - [13.1 → 13.2](#131--132)
- [Project and Configuration File Shapes](#project-and-configuration-file-shapes)
- [Hosting Packages Required by Extension Methods](#hosting-packages-required-by-extension-methods)
- [New Capabilities by Version](#new-capabilities-by-version)
- [Migration Guides](#migration-guides)

---

## Version Transition Matrix

### 8.x → 9.0

Major API overhaul released alongside .NET 9 (November 2024).

#### Type Renames

| Old Type | New Type |
|----------|----------|
| `Aspire.Hosting.ApplicationModel.ExecutableArgsCallbackAnnotation` | `Aspire.Hosting.ApplicationModel.ContainerRuntimeArgsCallbackAnnotation` |
| `Aspire.Hosting.AzureConstructResource` | `Aspire.Hosting.Azure.AzureProvisioningResource` (namespace changed) |
| `Aspire.Hosting.AzureConstructResourceExtensions` | `Aspire.Hosting.AzureProvisioningResourceExtensions` |
| `Aspire.Hosting.ResourceModuleConstruct` | `Aspire.Hosting.Azure.AzureResourceInfrastructure` (namespace changed) |
| `Aspire.Hosting.Python.PythonProjectResource` | `Aspire.Hosting.Python.PythonAppResource` |
| `Aspire.Hosting.PythonProjectResourceBuilderExtensions` | `Aspire.Hosting.PythonAppResourceBuilderExtensions` |

#### AppHost Project Format (target 9.x)

An 8.x AppHost has no `Aspire.AppHost.Sdk`. For a 9.x target, add `<Sdk Name="Aspire.AppHost.Sdk" Version="V" />` as the first child of `<Project>` (V is the target) and keep the `Aspire.Hosting.AppHost` PackageReference, set to V. For a target of 13.0 or later, use [AppHost project file](#apphost-project-file) instead.

#### Host Method Renames (AppHost projects)

| Old Method | New Method |
|-----------|------------|
| `AddAzureConstruct` | `AddAzureInfrastructure` |
| `ConfigureConstruct` | `ConfigureInfrastructure` |
| `AzureContainerAppExtensions.AddContainerAppsInfrastructure` | `AddAzureContainerAppsInfrastructure` (itself obsoleted in 9.3, see below) |
| `AzureStorageExtensions.UseEmulator` | `RunAsEmulator` |
| `AzureStorageExtensions.UsePersistence` | `WithDataBindMount` |
| `ExecutableResourceBuilderExtensions.AsDockerfileInManifest` | `PublishAsDockerFile` |
| `OracleDatabaseBuilderExtensions.AddOracleDatabase` | `AddOracle` |
| `PythonProjectResourceBuilderExtensions.AddPythonProject` | `PythonAppResourceBuilderExtensions.AddPythonApp` (sample in [Migration Guides](#addpythonproject--addpythonapp-8x--90)) |

#### Host Property Renames

| Old Property | New Property |
|-------------|-------------|
| `EnvironmentCallbackContext.PublisherName` | `EnvironmentCallbackContext.ExecutionContext` |
| `EndpointReference.UriString` | `EndpointReference.Url` |

#### Removed APIs

| API | Notes |
|-----|-------|
| `AzureBicepResource.CreateBicepResourceName` | Removed entirely, with no replacement |

#### Client Method Renames (service projects, namespace `Microsoft.Extensions.Hosting`)

Each `AddX` becomes `AddXClient`, and each `AddKeyedX` becomes `AddKeyedXClient`:

| Old Method | New Method |
|-----------|------------|
| `AddAzureOpenAI` | `AddAzureOpenAIClient` |
| `AddAzureTableService` | `AddAzureTableClient` |
| `AddAzureServiceBus` | `AddAzureServiceBusClient` |
| `AddAzureSearch` | `AddAzureSearchClient` |
| `builder.AddAzureKeyVaultSecrets(...)` on the host builder only | `AddAzureKeyVaultClient` (keep `builder.Configuration.AddAzureKeyVaultSecrets(...)`: it is the current configuration provider) |
| `AddAzureBlobService` | `AddAzureBlobClient` |
| `AddAzureQueueService` | `AddAzureQueueClient` |
| `AddAzureCosmosDB` | `AddAzureCosmosDBClient` |
| `AddRabbitMQ` | `AddRabbitMQClient` |
| `AddRedis` | `AddRedisClient` |
| `AspireKeyVaultExtensions.AddKeyVaultSecrets` (8.0 preview name) | `AddAzureKeyVaultSecrets` |
| `ServiceDiscoveryHttpClientBuilderExtensions.UseServiceDiscovery` | `AddServiceDiscovery` (namespace `Microsoft.Extensions.DependencyInjection`) |

#### Fluent Chain Refactors

The two-call chain becomes a single Azure resource call; the second call is deleted or replaced. Samples are in [Migration Guides](#azure-fluent-chains-8x--90).

| Old Pattern | New Pattern |
|------------|-------------|
| `AddSqlServer(name).AsAzureSqlDatabase()` | `AddAzureSqlServer(name)` |
| `AddSqlServer(name).PublishAsAzureSqlDatabase()` | `AddAzureSqlServer(name).RunAsContainer()` |
| `AddRedis(name).AsAzureRedis()` | `AddAzureRedis(name).WithAccessKeyAuthentication()` |
| `AddRedis(name).PublishAsAzureRedis()` | `AddAzureRedis(name).RunAsContainer().WithAccessKeyAuthentication()` |
| `AddPostgres(name, user, pwd).AsAzurePostgresFlexibleServer()` | `AddAzurePostgresFlexibleServer(name).WithPasswordAuthentication(user, pwd)` |
| `AddPostgres(name, user, pwd).PublishAsAzurePostgresFlexibleServer()` | `AddAzurePostgresFlexibleServer(name).RunAsContainer().WithPasswordAuthentication(user, pwd)` |

If the original call has other arguments (for example a port), carry them over by hand. The `AddAzure*` calls need the matching `Aspire.Hosting.Azure.*` package; see [Hosting Packages](#hosting-packages-required-by-extension-methods). For a 13.1+ target, the resulting `AddAzureRedis` is obsolete; see [13.0 → 13.1](#130--131).

#### Terminology

- "Component" renamed to "Integration" throughout documentation and APIs

---

### 9.0 → 9.3

Minor release. One notable obsolescence:

| Change | Details |
|--------|---------|
| `AddAzureContainerAppsInfrastructure` obsoleted | Replaced by compute environment APIs (`AddAzureContainerAppEnvironment`). **CS0618 warning only.** Treat as removed. |

### 9.3 → 9.5

No breaking changes. Additive features: Aspire CLI GA, VS Code extension, single-file AppHost preview.

---

### 9.5 → 13.0

Major release alongside .NET 10 (November 2025). Rebranded from ".NET Aspire" to "Aspire."

#### SDK and TFM Requirement

| Item | Minimum for 13.x |
|------|------------------|
| .NET SDK (for building and for the Aspire CLI) | .NET 10 SDK |
| TFM of the AppHost, ServiceDefaults and every project that references an `Aspire.*` package | `net8.0` or later |
| TFM of other projects | Not constrained by Aspire |

Retargeting to `net10.0` is not required. Recheck this minimum for 13.3 and later.

#### AppHost Project Format Change

| Before (9.x) | After (13.0) |
|--------------|-------------|
| `<Project Sdk="Microsoft.NET.Sdk">` with `<Sdk Name="Aspire.AppHost.Sdk" Version="9.5.2" />` child element and `<PackageReference Include="Aspire.Hosting.AppHost" />` | `<Project Sdk="Aspire.AppHost.Sdk/13.0.0">`, with no child Sdk element and no `Aspire.Hosting.AppHost` PackageReference |

See [AppHost project file](#apphost-project-file) for every starting shape.

#### Package Renames

| Old Package | New Package |
|------------|-------------|
| `Aspire.Hosting.NodeJs` | `Aspire.Hosting.JavaScript` (first stable 13.0.0) |

#### Method Changes

| Old | New | Build |
|-----|-----|-------|
| `NodeAppHostingExtension.AddNpmApp()` | `JavaScriptAppHostingExtension.AddJavaScriptApp()` plus `.WithRunScript(...)` | **CS0618 warning only** |
| `DistributedApplicationLifecycleHookExtensions.AddLifecycleHook<T>()` | `DistributedApplicationEventingExtensions.AddEventingSubscriber<T>()` | **CS0618 warning only** |
| `DistributedApplicationLifecycleHookExtensions.TryAddLifecycleHook<T>()` | `DistributedApplicationEventingExtensions.TryAddEventingSubscriber<T>()` | **CS0618 warning only** |
| Classes implementing `IDistributedApplicationLifecycleHook` | Implement `IDistributedApplicationEventingSubscriber` instead; this is a rewrite, not a rename | **CS0618 warning only** |
| `AddNodeApp(name, scriptPath, workingDirectory)` | `AddNodeApp(name, appDirectory, scriptPath)`: arguments 2 and 3 swap | **Not caught by the build** |

The `AddNodeApp` change applies to every call. When arguments 2 and 3 are passed by position (even after a named `name:`), both are strings, so the old order compiles and fails only at run time: swap them. A named `workingDirectory:` argument no longer exists and fails the build: rename it to `appDirectory:`. In every case, make sure `scriptPath` is relative to `appDirectory`. Samples are in [Migration Guides](#addnodeapp-argument-reorder-9x--130).

#### Removed APIs (manual migration)

| API | Replacement | Migration Effort |
|-----|------------|-----------------|
| `WithPublishingCallback` | `WithPipelineStepFactory` + `aspire do` | Medium (structural change) |
| `IDistributedApplicationPublisher` | `PipelineStep` | Medium |
| `PublishingContext`, `PublishingCallbackAnnotation` | `aspire do` pipeline system | Medium |
| `IPublishingActivityReporter` and related | Pipeline reporting APIs | Medium |
| Old `WithDebugSupport(debugAdapterId, requiredExtensionId)` overload | New debug support annotation | Low |

#### Constructor Signature Changes (out of scope: advanced APIs)

| API | Change |
|-----|--------|
| `AllocatedEndpoint` constructor | Added `NetworkIdentifier` parameter, removed `containerHostAddress` |
| `ParameterProcessor` constructor | Changed parameters |
| `ProcessArgumentValuesAsync` / `ProcessEnvironmentVariableValuesAsync` | Removed `containerHostName` parameter |

#### Behavioral Changes

| Change | Impact | Build |
|--------|--------|-------|
| `DefaultAzureCredential` now uses only `ManagedIdentityCredential` in Azure deployments | Auth may break if relying on `EnvironmentCredential` | **Not caught by the build** |

---

### 13.0 → 13.1

#### Obsoleted APIs

| API | Notes | Build |
|-----|-------|-------|
| `AzureRedisExtensions.AddAzureRedis` | Replaced by `AddAzureManagedRedis`, which provisions Azure Managed Redis, a different Azure resource from Azure Cache for Redis. Switch only if the user approved it in the plan; otherwise keep `AddAzureRedis` and list it for the user. | **CS0618 warning only** |

---

### 13.1 → 13.2

#### Package Renames

| Old Package | New Package |
|------------|-------------|
| `Aspire.Hosting.Azure.AIFoundry` (last version 13.1.x, preview only) | `Aspire.Hosting.Foundry` (first version 13.2.0, still preview: use the `-preview` version that matches the target) |

#### Method Changes

| Old | New |
|-----|-----|
| `AzureAIFoundryExtensions.AddAzureAIFoundry()` | `FoundryExtensions.AddFoundry()` |
| `ContainerResourceBuilderExtensions.WithSecretBuildArg()` | `WithBuildSecret()` |

#### Type Changes

| Old | New |
|-----|-----|
| `Aspire.Hosting.Azure.AzureAIFoundryResource` | `Aspire.Hosting.Foundry.FoundryResource` (namespace changed) |
| `Aspire.Hosting.Azure.AzureAIFoundryProjectResource` | `Aspire.Hosting.Foundry.FoundryProjectResource` (namespace changed) |

#### Obsoleted APIs

| API | Notes |
|-----|-------|
| `Aspire.Hosting.Azure.IAzureContainerRegistry` | Use the `ContainerRegistry` property on compute environments. Treat as removed. |

#### Configuration Changes

| Change | Details | Build |
|--------|---------|-------|
| Config file consolidation | `.aspire/settings.json` + `apphost.run.json` → unified `aspire.config.json`; see [aspire.config.json](#aspireconfigjson-132) | **Not caught by the build** |

#### Behavioral Changes

| Change | Impact | Build |
|--------|--------|-------|
| Service discovery env vars use endpoint scheme instead of name | Code reading `services__X__myendpoint__0` may break | **Not caught by the build** |
| `BeforeResourceStartedEvent` fires only on actual start | Handlers depending on every-state-change behavior may break | **Not caught by the build** |
| Connection property suffix added | Direct env var reads of `DB_HOST` etc. may need update | **Not caught by the build** |
| `DefaultAzureCredential` no longer uses parameterless constructor in client integrations | May affect credential resolution | **Not caught by the build** |

---

## Project and Configuration File Shapes

All three are **not caught by the build**.

### AppHost project file

Applies to the AppHost only, when the target is 13.0 or later. Let `V` be the target version.

| Starting shape | Result |
|----------------|--------|
| `<Project Sdk="Microsoft.NET.Sdk">` (or no `Sdk` attribute) with a child `<Sdk Name="Aspire.AppHost.Sdk" Version="..." />` | `<Project Sdk="Aspire.AppHost.Sdk/V">`; delete the child element |
| Some other `Project Sdk` with a child `<Sdk Name="Aspire.AppHost.Sdk" ... />` | Keep both; set the child element's `Version="V"` |
| `<Project Sdk="Aspire.AppHost.Sdk/x">` | Change `x` to `V` |
| No Aspire SDK at all | Add `<Sdk Name="Aspire.AppHost.Sdk" Version="V" />` as the first child of `<Project>` |

In every case, delete the `Aspire.Hosting.AppHost` PackageReference (and its `PackageVersion` entry under central package management), because the 13.x SDK includes it.

### aspire.config.json (13.2+)

Applies to the AppHost directory, and only when `aspire.config.json` does not exist yet. Build it from the old files:

| Source | Becomes |
|--------|---------|
| `.aspire/settings.json` → `appHostPath` | `appHost.path`. The old value is relative to the `.aspire/` folder; rebase it to be relative to the AppHost directory and use forward slashes. |
| `.aspire/settings.json` → `channel` | `channel` (copied as is) |
| `apphost.run.json` → `profiles` | `profiles` (copied as is) |

```jsonc
// .aspire/settings.json (before)
{ "appHostPath": "../MyApp.AppHost.csproj", "channel": "stable" }

// aspire.config.json (after, in the AppHost directory)
{
  "appHost": { "path": "MyApp.AppHost.csproj" },
  "channel": "stable",
  "profiles": { /* copied from apphost.run.json */ }
}
```

Leave the old files in place unless the user asks to delete them.

### launchSettings.json

Applies to `Properties/launchSettings.json` of every Aspire project. Add values only when they are missing, and never overwrite existing ones. Put the `https` profile first in `profiles`. Pick ports in the ranges shown, avoiding any port already used in the `http` profile.

```jsonc
{
  "profiles": {
    "https": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": true,
      // https: 17000-17300; http: reuse the http profile's port, else 15000-15300
      "applicationUrl": "https://localhost:17123;http://localhost:15123",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development",
        "DOTNET_ENVIRONMENT": "Development",
        // AppHost only: 21000-21300
        "DOTNET_DASHBOARD_OTLP_ENDPOINT_URL": "https://localhost:21123",
        // 22000-22300
        "DOTNET_RESOURCE_SERVICE_ENDPOINT_URL": "https://localhost:22123"
      }
    },
    // only when an "http" profile already exists; never create it
    "http": {
      "environmentVariables": {
        // add only if missing
        "DOTNET_RESOURCE_SERVICE_ENDPOINT_URL": "http://localhost:22124"
      }
    }
  }
}
```

---

## Hosting Packages Required by Extension Methods

Hosting integrations ship as separate packages. When the AppHost calls one of these methods, it must reference the package at the target version. If the package is missing, the build fails with an unknown-method error; use this table to find the package to add.

| Methods | Package |
|---------|---------|
| `AddRedis` | `Aspire.Hosting.Redis` |
| `AddOracle`, `AddOracleDatabase` | `Aspire.Hosting.Oracle` |
| `AddMySql` | `Aspire.Hosting.MySql` |
| `AddPostgres` | `Aspire.Hosting.PostgreSQL` |
| `AddKafka` | `Aspire.Hosting.Kafka` |
| `AddMongoDB` | `Aspire.Hosting.MongoDB` |
| `AddRabbitMQ` | `Aspire.Hosting.RabbitMQ` |
| `AddSqlServer` | `Aspire.Hosting.SqlServer` |
| `AsAzureSqlDatabase`, `PublishAsAzureSqlDatabase`, `AddAzureSqlServer` | `Aspire.Hosting.Azure.Sql` |
| `AddNodeApp`, `AddJavaScriptApp`, `AddViteApp` | `Aspire.Hosting.JavaScript` (13.0+) |
| `AddPythonApp`, `AddPythonModule`, `AddUvicornApp`, `AddPythonExecutable` | `Aspire.Hosting.Python` |
| `AddAzureAppConfiguration` | `Aspire.Hosting.Azure.AppConfiguration` |
| `AddAzureApplicationInsights` | `Aspire.Hosting.Azure.ApplicationInsights` |
| `AddAzureCosmosDB` | `Aspire.Hosting.Azure.CosmosDB` |
| `AddAzureKeyVault` | `Aspire.Hosting.Azure.KeyVault` |
| `AddAzureSearch` | `Aspire.Hosting.Azure.Search` |
| `AddAzureServiceBus` | `Aspire.Hosting.Azure.ServiceBus` |
| `AddAzureSignalR` | `Aspire.Hosting.Azure.SignalR` |
| `AddAzureStorage`, `AddDataLake`, `AddDataLakeFileSystem` | `Aspire.Hosting.Azure.Storage` |
| `AddAzureOpenAI` | `Aspire.Hosting.Azure.CognitiveServices` |
| `AddBicepTemplate` | `Aspire.Hosting.Azure` |
| `AddFoundry` | `Aspire.Hosting.Foundry` (13.2+, preview) |
| `AddAzureVirtualNetwork`, `AddNatGateway` | `Aspire.Hosting.Azure.Network` |
| `AddOrleans` | `Aspire.Hosting.Orleans` |
| `AddDockerComposeEnvironment` | `Aspire.Hosting.Docker` |
| `AddMauiProject` | `Aspire.Hosting.Maui` |

---

## New Capabilities by Version

Use this table in Phase 6 (Post-Upgrade) to inform users of new features.

### New in 9.0
- `WaitFor` / `WaitForCompletion` — resource dependency ordering
- Health check integration with `WaitFor`
- Persistent containers (`WithLifetime(ContainerLifetime.Persistent)`)
- Container-to-container networking
- Resource commands in dashboard
- CORS configuration for dashboard

### New in 9.1 – 9.5
- Resource graph visualization in dashboard
- Nested resources
- Custom domains for ACA
- Existing Azure resource support
- `EndpointProperty.HostAndPort`
- `WithEntrypoint` for containers
- Aspire CLI (`aspire new`, `aspire run`, `aspire add`, `aspire update`)
- VS Code extension
- Single-file AppHost support (preview)
- `WithComputeEnvironment` API

### New in 13.0
- **TypeScript AppHost** (preview) — `createBuilder()` in TypeScript
- **Single-file AppHost** GA — `#:sdk Aspire.AppHost.Sdk@13.0.0` with `#:package` directives
- **First-class Python support** — `AddPythonApp`, `AddPythonModule`, `AddUvicornApp`, `WithUv()`, `WithPip()`
- **First-class JavaScript support** — `AddJavaScriptApp`, `AddViteApp`, package manager auto-detection
- **`aspire do` pipeline system** — composable build/deploy/publish workflows
- **`aspire init`** — initialize Aspire in existing repos
- **Multi-language connection properties** — URI, JDBC, individual properties for cross-language support
- **Certificate trust across languages** — automatic for Python, Node.js, containers
- **Simplified service URL env vars** — `API_HTTP`, `API_HTTPS` for non-.NET apps
- **Container files as build artifacts** — `PublishWithContainerFiles`
- **MAUI integration** — `AddMauiProject` for mobile app orchestration
- **MCP server in dashboard** — AI agent integration
- **Deployment state management** — persistent Azure config across deploys
- **Named references** — `WithReference(db, "primary")`
- **Connection properties** — `GetConnectionProperty("Host")`
- **Network identifiers** — `KnownNetworkIdentifiers.DefaultAspireContainerNetwork`

### New in 13.1
- Bug fixes and stability improvements

### New in 13.2
- **`aspire start` / `aspire stop` / `aspire ps`** — detached mode (background AppHost)
- **`aspire describe`** — CLI resource monitoring
- **`aspire doctor`** — environment diagnostics
- **`aspire secret`** — user secrets management
- **`aspire export`** — telemetry data export
- **`aspire agent`** (renamed from `aspire mcp`) — AI agent integration
- **`aspire docs`** — documentation from CLI
- **`aspire wait`** — block until resource is ready
- **VS Code extension major update** — Activity Bar panel, CodeLens, gutter decorations
- **TypeScript AppHost improvements** — code generation, debugging
- **Dashboard data export/import** — telemetry export as JSON
- **Dashboard telemetry HTTP API** — programmatic telemetry access
- **Set parameters from dashboard** — interactive parameter management
- **Docker Compose publishing** GA — `AddDockerComposeEnvironment`
- **Microsoft Foundry** — `AddFoundry`, model deployments, hosted agents
- **Azure Virtual Network** — `AddAzureVirtualNetwork`, subnets, NAT gateways, private endpoints
- **Azure Data Lake Storage** integration
- **MongoDB Entity Framework Core** integration
- **Bun support** — `WithBun()` for JavaScript apps
- **`WithMcpServer`** — declare MCP endpoints in app model
- **Project rebuilds** — `aspire resource api rebuild`
- **Contextual endpoint resolution** — `Caller` and `Network` on `ValueProviderContext`
- **`WithBuildSecret`** — cleaner container build secret API
- **`aspire.config.json`** — unified configuration file
- **Isolated mode** — `--isolated` for parallel development

---

## Migration Guides

### Azure Fluent Chains (8.x → 9.0)

```csharp
// BEFORE (8.x)
var sql = builder.AddSqlServer("sql").AsAzureSqlDatabase();
var cache = builder.AddRedis("cache").PublishAsAzureRedis();
var pg = builder.AddPostgres("pg", user, password).AsAzurePostgresFlexibleServer();

// AFTER (9.0+)
var sql = builder.AddAzureSqlServer("sql");
var cache = builder.AddAzureRedis("cache").RunAsContainer().WithAccessKeyAuthentication();
var pg = builder.AddAzurePostgresFlexibleServer("pg").WithPasswordAuthentication(user, password);
```

### AddPythonProject → AddPythonApp (8.x → 9.0)

```csharp
// BEFORE (8.x)
builder.AddPythonProject("api", "../api", "main.py");

// AFTER (9.0+)
builder.AddPythonApp("api", "../api", "main.py");
```

### Lifecycle Hooks → Eventing Subscribers (9.x → 13.0)

```csharp
// BEFORE (9.x)
public class MyHook : IDistributedApplicationLifecycleHook
{
    public async Task BeforeStartAsync(
        DistributedApplicationModel model,
        CancellationToken cancellationToken)
    {
        // Logic before start
    }
}

builder.Services.TryAddLifecycleHook<MyHook>();

// AFTER (13.0)
public class MySubscriber : IDistributedApplicationEventingSubscriber
{
    public Task SubscribeAsync(
        IDistributedApplicationEventing eventing,
        DistributedApplicationExecutionContext executionContext,
        CancellationToken cancellationToken)
    {
        eventing.Subscribe<BeforeStartEvent>((@event, ct) =>
        {
            var model = @event.Model;
            // Logic before start
            return Task.CompletedTask;
        });

        return Task.CompletedTask;
    }
}

builder.Services.TryAddEventingSubscriber<MySubscriber>();
```

### Publishing Callbacks → Pipeline Steps (9.x → 13.0)

```csharp
// BEFORE (9.x)
var api = builder.AddProject<Projects.Api>("api")
    .WithPublishingCallback(async (context, cancellationToken) =>
    {
        await CustomDeployAsync(context, cancellationToken);
    });

// AFTER (13.0)
var api = builder.AddProject<Projects.Api>("api")
    .WithPipelineStepFactory(context =>
    {
        return new PipelineStep()
        {
            Name = "CustomDeployStep",
            Action = CustomDeployAsync,
            RequiredBySteps = [WellKnownPipelineSteps.Publish]
        };
    });
```

### AddNodeApp Argument Reorder (9.x → 13.0)

Positional calls are not caught by the build: both orders compile.

```csharp
// BEFORE (9.x): AddNodeApp(name, scriptPath, workingDirectory)
builder.AddNodeApp("frontend", "../frontend/server.js", "../frontend");

// AFTER (13.0): AddNodeApp(name, appDirectory, scriptPath), scriptPath relative to appDirectory
builder.AddNodeApp("frontend", "../frontend", "server.js");

// Named form: workingDirectory no longer exists (build error)
// BEFORE: builder.AddNodeApp("frontend", scriptPath: "../frontend/server.js", workingDirectory: "../frontend");
builder.AddNodeApp("frontend", appDirectory: "../frontend", scriptPath: "server.js");
```

### AddNpmApp → AddJavaScriptApp (9.x → 13.0)

Also replace the `Aspire.Hosting.NodeJs` package with `Aspire.Hosting.JavaScript`.

```csharp
// BEFORE (9.x)
builder.AddNpmApp("frontend", "../frontend", scriptName: "dev");

// AFTER (13.0)
builder.AddJavaScriptApp("frontend", "../frontend")
    .WithRunScript("dev");
```

### AIFoundry → Foundry (13.0 → 13.2)

Also replace the `Aspire.Hosting.Azure.AIFoundry` package with `Aspire.Hosting.Foundry`.

```csharp
// BEFORE (13.0)
var ai = builder.AddAzureAIFoundry("ai");

// AFTER (13.2)
var foundry = builder.AddFoundry("ai");
var project = foundry.AddProject("agents");
var chat = project.AddModelDeployment("chat", FoundryModel.OpenAI.Gpt5Mini);
```
