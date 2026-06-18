# Breaking Changes Reference

Version-to-version breaking change matrix for the Aspire Version Upgrade scenario. Covers all transitions from 8.0 through 13.2.

## Contents

- [Version Transition Matrix](#version-transition-matrix)
  - [8.x → 9.0](#8x--90-automated-by-engine)
  - [9.0 → 9.3](#90--93-automated-by-engine)
  - [9.5 → 13.0](#95--130-automated--advisory)
  - [13.0 → 13.1](#130--131)
  - [13.1 → 13.2](#131--132-automated--advisory)
- [New Capabilities by Version](#new-capabilities-by-version)
- [Migration Guides](#migration-guides)

---

## Version Transition Matrix

### 8.x → 9.0 (Automated by Engine)

Major API overhaul released alongside .NET 9 (November 2024).

#### Type Renames

| Old Type | New Type |
|----------|----------|
| `ExecutableArgsCallbackAnnotation` | `ContainerRuntimeArgsCallbackAnnotation` |
| `AzureConstructResource` | `AzureProvisioningResource` |
| `AzureConstructResourceExtensions` | `AzureProvisioningResourceExtensions` |
| `PythonProjectResource` | `PythonAppResource` |
| `PythonProjectResourceBuilderExtensions` | `PythonAppResourceBuilderExtensions` |
| `ResourceModuleConstruct` | `AzureResourceInfrastructure` |

#### Host Method Renames (AppHost projects)

| Old Method | New Method |
|-----------|------------|
| `AddAzureConstruct` | `AddAzureInfrastructure` |
| `ConfigureConstruct` | `ConfigureInfrastructure` |
| `AddContainerAppsInfrastructure` | `AddAzureContainerAppsInfrastructure` |
| `UseEmulator` | `RunAsEmulator` |
| `UsePersistence` | `WithDataBindMount` |
| `AsDockerfileInManifest` | `PublishAsDockerFile` |
| `AddOracleDatabase` | `AddOracle` |
| `AddPythonProject` | `AddPythonApp` |

#### Host Property Renames

| Old Property | New Property |
|-------------|-------------|
| `EnvironmentCallbackContext.PublisherName` | `EnvironmentCallbackContext.ExecutionContext` |
| `EndpointReference.UriString` | `EndpointReference.Url` |

#### Removed APIs

| API | Notes |
|-----|-------|
| `AzureBicepResource.CreateBicepResourceName` | Removed entirely |

#### Client Method Renames (service projects)

All follow the pattern `AddX` → `AddXClient`:

| Old Method | New Method |
|-----------|------------|
| `AddAzureOpenAI` | `AddAzureOpenAIClient` |
| `AddAzureTableService` | `AddAzureTableClient` |
| `AddAzureServiceBus` | `AddAzureServiceBusClient` |
| `AddAzureSearch` | `AddAzureSearchClient` |
| `AddAzureKeyVaultSecrets` | `AddAzureKeyVaultClient` |
| `AddAzureBlobService` | `AddAzureBlobClient` |
| `AddAzureQueueService` | `AddAzureQueueClient` |
| `AddAzureCosmosDB` | `AddAzureCosmosDBClient` |
| `AddRabbitMQ` | `AddRabbitMQClient` |
| `AddRedis` | `AddRedisClient` |
| `UseServiceDiscovery` | `AddServiceDiscovery` |
| (plus Keyed variants for all of the above) | |

#### Fluent Chain Refactors

| Old Pattern | New Pattern |
|------------|-------------|
| `.AddPostgres(name, login, pwd).AsAzurePostgresFlexibleServer()` | `.AddAzurePostgresFlexibleServer(name).WithPasswordAuthentication(login, pwd)` |
| `.AddPostgres(name).PublishAsAzurePostgresFlexibleServer()` | `.AddAzurePostgresFlexibleServer(name).RunAsContainer()` |
| `.AddRedis(name).AsAzureRedis()` | `.AddAzureRedis(name)` |
| `.AddRedis(name).PublishAsAzureRedis()` | `.AddAzureRedis(name).RunAsContainer().WithAccessKeyAuthentication()` |
| `.AddSqlServer(name).AsAzureSqlDatabase()` | `.AddAzureSqlServer(name)` |
| `.AddSqlServer(name).PublishAsAzureSqlDatabase()` | `.AddAzureSqlServer(name).RunAsContainer()` |

#### Package Renames

| Old Package | New Package |
|------------|-------------|
| `Aspire.Hosting` | `Aspire.Hosting.AppHost` |
| `Aspire.Hosting.Azure.Provisioning` | `Aspire.Hosting.Azure` |

#### Terminology

- "Component" renamed to "Integration" throughout documentation and APIs

---

### 9.0 → 9.3 (Automated by Engine)

Minor release. One notable obsolescence:

| Change | Details |
|--------|---------|
| `AddAzureContainerAppsInfrastructure` obsoleted | Replaced by compute environment APIs. Still compiles with warning. |

### 9.3 → 9.5

No breaking changes. Additive features: Aspire CLI GA, VS Code extension, single-file AppHost preview.

---

### 9.5 → 13.0 (Automated + Advisory)

Major release alongside .NET 10 (November 2025). Rebranded from ".NET Aspire" to "Aspire."

#### TFM Requirement

**.NET 10 SDK required.** All projects must target `net10.0`.

#### AppHost Project Format Change

| Before (9.x) | After (13.0) |
|--------------|-------------|
| `<Project Sdk="Microsoft.NET.Sdk">` with `<Sdk Name="Aspire.AppHost.Sdk" Version="9.5.2" />` child element and `<PackageReference Include="Aspire.Hosting.AppHost" />` | `<Project Sdk="Aspire.AppHost.Sdk/13.0.0">` — no child Sdk element, no Aspire.Hosting.AppHost PackageReference needed |

#### Package Renames

| Old Package | New Package |
|------------|-------------|
| `Aspire.Hosting.NodeJs` | `Aspire.Hosting.JavaScript` |

#### Method Changes (Automated)

| Old | New | Type |
|-----|-----|------|
| `AddNpmApp()` | `AddJavaScriptApp()` | Obsoleted (still compiles with warning) |
| `AddLifecycleHook()` | `AddEventingSubscriber()` | Obsoleted |
| `TryAddLifecycleHook()` | `TryAddEventingSubscriber()` | Obsoleted |

#### AddNodeApp Argument Reorder (Automated)

```csharp
// Before (9.x): AddNodeApp(name, scriptPath, workingDirectory)
builder.AddNodeApp("frontend", "../frontend/server.js", "../frontend");

// After (13.0): AddNodeApp(name, appDirectory, scriptPath)
builder.AddNodeApp("frontend", "../frontend", "server.js");
```

#### Removed APIs (Advisory — requires manual migration)

| API | Replacement | Migration Effort |
|-----|------------|-----------------|
| `WithPublishingCallback` | `WithPipelineStepFactory` + `aspire do` | Medium — structural change |
| `IDistributedApplicationPublisher` | `PipelineStep` | Medium |
| `PublishingContext`, `PublishingCallbackAnnotation` | `aspire do` pipeline system | Medium |
| `IPublishingActivityReporter` and related | Pipeline reporting APIs | Medium |
| Old `WithDebugSupport(debugAdapterId, requiredExtensionId)` overload | New debug support annotation | Low |

#### Obsoleted APIs (still compile, will be removed in future)

| API | Replacement |
|-----|------------|
| `IDistributedApplicationLifecycleHook` | `IDistributedApplicationEventingSubscriber` |
| `AddLifecycleHook<T>()` | `AddEventingSubscriber<T>()` |
| `AddNpmApp()` | `AddJavaScriptApp()` or `AddViteApp()` |

#### Constructor Signature Changes (out of scope — advanced APIs)

| API | Change |
|-----|--------|
| `AllocatedEndpoint` constructor | Added `NetworkIdentifier` parameter, removed `containerHostAddress` |
| `ParameterProcessor` constructor | Changed parameters |
| `ProcessArgumentValuesAsync` / `ProcessEnvironmentVariableValuesAsync` | Removed `containerHostName` parameter |

#### Behavioral Changes (warning-only)

| Change | Impact |
|--------|--------|
| `DefaultAzureCredential` now uses only `ManagedIdentityCredential` in Azure deployments | Auth may break if relying on `EnvironmentCredential` |

---

### 13.0 → 13.1

Bug fixes only. No breaking changes.

---

### 13.1 → 13.2 (Automated + Advisory)

#### Package Renames

| Old Package | New Package |
|------------|-------------|
| `Aspire.Hosting.Azure.AIFoundry` | `Aspire.Hosting.Foundry` |

#### Method Changes (Automated)

| Old | New | Type |
|-----|-----|------|
| `AddAzureAIFoundry()` | `AddFoundry()` | Breaking rename |
| `WithSecretBuildArg()` | `WithBuildSecret()` | Breaking rename |

#### Type Changes (Automated)

| Old | New |
|-----|-----|
| `AzureAIFoundryResource` | `FoundryResource` |
| `AzureAIFoundryProjectResource` | `FoundryProjectResource` |

#### Obsoleted APIs

| API | Notes |
|-----|-------|
| `IAzureContainerRegistry` | Use `ContainerRegistry` property on compute environments |

#### Configuration Changes (Automated)

| Change | Details |
|--------|---------|
| Config file consolidation | `.aspire/settings.json` + `apphost.run.json` → unified `aspire.config.json` |

#### Behavioral Changes (warning-only)

| Change | Impact |
|--------|--------|
| Service discovery env vars use endpoint scheme instead of name | Code reading `services__X__myendpoint__0` may break |
| `BeforeResourceStartedEvent` fires only on actual start | Handlers depending on every-state-change behavior may break |
| Connection property suffix added | Direct env var reads of `DB_HOST` etc. may need update |
| `DefaultAzureCredential` no longer uses parameterless constructor in client integrations | May affect credential resolution |

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

### AIFoundry → Foundry (13.0 → 13.2)

```csharp
// BEFORE (13.0)
var ai = builder.AddAzureAIFoundry("ai");

// AFTER (13.2)
var foundry = builder.AddFoundry("ai");
var project = foundry.AddProject("agents");
var chat = project.AddModelDeployment("chat", FoundryModel.OpenAI.Gpt5Mini);
```

### AddNodeApp Argument Reorder (9.x → 13.0)

```csharp
// BEFORE (9.x): AddNodeApp(name, scriptPath, workingDirectory)
builder.AddNodeApp("frontend", "../frontend/server.js", "../frontend");

// AFTER (13.0): AddNodeApp(name, appDirectory, scriptPath)
builder.AddNodeApp("frontend", "../frontend", "server.js");
```

### AddNpmApp → AddJavaScriptApp (9.x → 13.0)

```csharp
// BEFORE (9.x)
builder.AddNpmApp("frontend", "../frontend", scriptName: "dev");

// AFTER (13.0)
builder.AddJavaScriptApp("frontend", "../frontend")
    .WithRunScript("dev");
```
