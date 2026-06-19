---
name: migrating-wcf-to-corewcf
description: >
  Migrates server-side WCF services from .NET Framework to CoreWCF for .NET 6+. Converts hosting,
  configuration, bindings, behavior extensions, and APM-style contracts. Use when a project
  references System.ServiceModel via GAC, contains .svc files, uses ServiceHost, or needs WCF
  endpoints rehosted in ASP.NET Core. Also handles mixed client/server projects by preserving
  client packages.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# WCF to CoreWCF Migration Skill

## Purpose
Migrate .NET Framework WCF services to CoreWCF for .NET 6+ by converting service hosting, configuration, and dependencies while preserving service functionality.

## Repository Conventions

### Execution Rules
- Follow steps below in order and follow every bullet point exactly — do not summarize or skip
- When registering services in DI, add a construction delegate if the constructor has non-injectable parameters (e.g., `string`, `int`). Use `builder.Configuration["appSettings:<key>"] ?? <default>` for unknown values
- **Build the current project only** — not the whole solution. Build after completing all steps and fix all WCF-related build errors iteratively until clean
- If a build error suggests a missing binding, security misconfiguration, or ambiguous service contract issue, search the original WCF configuration (`web.config`/`app.config`, `ServiceHostFactory` subclasses, startup code) for the intended setting. If a clear match is found, apply it. If the original intent is ambiguous or no match exists, present the error with your findings and suggested options to the user rather than guessing

## Workflow

Migration Progress:
- [ ] Step 1: Check WCF dependencies
- [ ] Step 2: Verify project is SDK-style / .NET 6+
- [ ] Step 3: Swap NuGet packages and update usings
- [ ] Step 4: Rehost services in ASP.NET Core
- [ ] Step 5: Migrate behavior extensions
- [ ] Step 6: Remove .svc files and clean project metadata
- [ ] Step 7: Migrate remaining config to code
- [ ] Step 8: Handle binding gaps
- [ ] Step 9: Convert APM contracts to Task-based async
- [ ] Step 10: Update tests

### Step 1: Check WCF Dependencies

If analysis results already contain WCF dependency information, use those. Otherwise, check for references in these categories:

| Category | References | Action |
|----------|------------|--------|
| Server-side WCF (.NET Fx) | `System.ServiceModel` and other `System.ServiceModel.*` via `<Reference>` (GAC) | Primary migration target → proceed with remaining steps |
| WCF client (.NET Core NuGet) | `System.ServiceModel.Primitives`, `.Http`, `.NetTcp` | May be client-only (`ChannelFactory<T>`, `ClientBase<T>`). Do not remove blindly — see Step 3 |
| CoreWCF (already migrated) | `CoreWCF.Primitives`, `.ConfigurationManager`, `.Http`, `.WebHttp`, `.NetTcp` | Skip conversion; only validate config/hosting patterns |

If none found, skip and inform user there is nothing to do.

### Step 2: Ensure Project is Converted to .NET Core

If WCF migration is part of the .NET Framework upgrade, project should already be upgraded to new .NET version and SDK-style. If it is not, switch to plan steps doing project .NET version upgrade and come back to WCF feature upgrade after that.

However, if WCF migration is done separately per user request, check that project is SDK-style and targets .NET version 6.0 or above. If it is not, let user know and ask them to upgrade project to newer .NET version first.

### Step 3: Update Project WCF Dependencies to CoreWCF Packages

Add CoreWCF NuGet packages based on the bindings and features actually used by the project:
- `CoreWCF.Primitives` — always required
- `CoreWCF.Http` — if the project uses HTTP-based bindings (`BasicHttpBinding`, `WSHttpBinding`, etc.)
- `CoreWCF.WebHttp` — if the project uses `WebHttpBinding` or REST-style endpoints
- `CoreWCF.NetTcp` — if the project uses `NetTcpBinding`
- `CoreWCF.ConfigurationManager` — if the project reads WCF configuration from `web.config`/`app.config`

Determine which bindings are in use by examining `web.config`/`app.config` `<bindings>` sections and any binding instances created in code. Only add packages the project actually needs.

Before removing any `System.ServiceModel.*` references, search for `ChannelFactory<` and `ClientBase<` usage. If found, keep client NuGet packages and only migrate server-side pieces; inform user which packages were retained. If no client usage, remove all `System.ServiceModel.*` dependencies.

Search the project for all files containing `using System.ServiceModel` statements. For each, replace the `System.ServiceModel` portion of the namespace with `CoreWCF` (the sub-namespace structure is the same — e.g., `System.ServiceModel.Channels` → `CoreWCF.Channels`). Apply this to both service contract interfaces and implementation classes. If a file mixes server and client code, keep `System.ServiceModel` usings for client types only.

### Step 4: Rehost Services in ASP.NET Core

- Ensure the project has a `Program.cs` with standard ASP.NET Core host setup
- Search for all `[ServiceContract]` interfaces, their implementations, `.svc` files, and `ServiceHost` usages to discover every service, endpoint path, and binding

Register each discovered service using this pattern:
```csharp
services.AddServiceModelServices();
services.AddServiceModelMetadata();
app.UseServiceModel(builder =>
{
    // Repeat for each service discovered in the project:
    builder.AddService<DiscoveredService>();
    builder.AddServiceEndpoint<DiscoveredService, IDiscoveredContract>(
        new /* binding matching original */(), "/original/path/Service.svc");
});

var serviceMetadataBehavior = app.Services.GetRequiredService<ServiceMetadataBehavior>();
serviceMetadataBehavior.HttpGetEnabled = true;
```

`services.AddServiceModelMetadata()` is required for WSDL/metadata. Derive endpoint paths from the original `.svc` file locations — you **must** preserve the original subfolder structure.

**Endpoint path ordering:** Register more specific paths first (e.g., `/Services/MyService.svc/wshttp` before `/Services/MyService.svc`).

**ServiceHost mutations** (`.Credentials`, `.Description`, `.Authorization`) must move into `ConfigureServiceHostBase<TService>`. Search for any code that directly modifies `ServiceHost` properties (often in `ServiceHostFactory` subclasses or startup code) and relocate it into the appropriate delegate for each service.

### Step 5: Migrate Behavior Extensions

- Search `web.config`/`app.config` for `behaviorExtensions` elements. If none are found, skip this step.
- For each extension found, use the `type` attribute to locate the `BehaviorExtensionElement` subclass, then check its `BehaviorType` property for the actual behavior class and `CreateBehavior()` for how it's instantiated.

**Service behaviors** (`IServiceBehavior`): Register via DI — CoreWCF automatically discovers and applies them. Do **not** add them inside `ConfigureServiceHostBase`.

If the project has **only one service** (or a behavior should apply to every service), use a plain registration:
```csharp
builder.Services.AddSingleton<IServiceBehavior, MyServiceBehavior>();
```

If the project has **multiple services** and a behavior should apply to only some of them, use **keyed DI** with the service type as the key so CoreWCF scopes it correctly:
```csharp
// Only applies to OrderService, not to other services in the project
builder.Services.AddKeyedSingleton<IServiceBehavior, MyServiceBehavior>(typeof(OrderService));
```
Without keyed registration, every `IServiceBehavior` registered in the container will be applied to **all** hosted services, which is almost never the intent when different services had different behavior configurations.

**Endpoint behaviors** (`IEndpointBehavior`): Use `ConfigureServiceHostBase<TService>` (prefer over `ConfigureAllServiceHostBase` to avoid cross-applying). **Skip system endpoints** (`endpoint.IsSystemEndpoint`).

After registration, you **must**:
- Remove classes implementing `BehaviorExtensionElement` (delete file if it only contains those)
- Remove `<behaviorExtensions>` from config (remove `<extensions>` too if it only contained `<behaviorExtensions>`)

### Step 6: Address Hosting Differences

- CoreWCF does not support `.svc` activation. Remove `.svc` files only — **keep `.svc.cs`** if they contain service implementation
- Remove `<Content>` and `<Compile Update>` / `<DependentUpon>` metadata for `.svc` items from project file (SDK-style includes `.svc.cs` by default). When deleting files, use applicable tool; if no such tools then use other available tools to delete files
- For IIS with **non-HTTP/HTTPS endpoints** (e.g., `net.tcp`), configure the app to auto-start and stay running to simulate WCF-style activation. This is not needed for HTTP/HTTPS-only services

### Step 7: Migrate Configuration

Migrate remaining WCF configuration from `web.config`/`app.config` to code. Check for and handle each of these:

| Config Element | Migration Target |
|---------------|------------------|
| `<serviceThrottling>` (`maxConcurrentCalls`, `maxConcurrentSessions`, `maxConcurrentInstances`) | Configure via `ServiceThrottlingBehavior` registered in DI |
| `<serviceDebug includeExceptionDetailInFaults>` | Configure via `ServiceDebugBehavior` in DI |
| `<serviceCredentials>` (certificates, user-name validation) | Configure in `ConfigureServiceHostBase<TService>` — see Step 8 for security notes |
| `<dataContractSerializer maxItemsInObjectGraph>` | Configure via `DataContractSerializerOperationBehavior` |
| `<protocolMapping>` | Not supported in CoreWCF — configure bindings explicitly in `UseServiceModel` |
| Custom `<appSettings>` used by service logic | Migrate to `appsettings.json` and inject via `IConfiguration` or `IOptions<T>` |

If the project uses `CoreWCF.ConfigurationManager`, some `<system.serviceModel>` sections can remain in a config file and be loaded via `builder.AddServiceModelConfigurationManagerFile("wcf.config")`. This is an alternative to migrating everything to code — useful for complex configurations. Confirm with the user which approach they prefer.

### Step 8: Handle Security and Binding Gaps

Some WCF binding features are not supported or behave differently in CoreWCF. Check for these and notify the user:

| WCF Feature | CoreWCF Status | Alternative |
|-------------|---------------|-------------|
| `NetTcpBinding` with TCP port sharing | Not supported | Use separate ports per service, or switch to HTTP-based binding |
| `WSDualHttpBinding` | Not supported | Use `BasicHttpBinding` or `WSHttpBinding` with a callback alternative |
| `NetNamedPipeBinding` | Not supported | Use `NetTcpBinding` or HTTP-based binding |
| `MsmqBinding` / MSMQ transport | Not supported | Use a message queue library (e.g., RabbitMQ, Azure Service Bus) |
| `TransactionScope` flowing across service boundaries | Limited support | Verify with user; may require architectural changes |
| `reliableSession` | Supported on `NetTcpBinding` only | For HTTP bindings, remove reliable session config |

**Security configuration caution:** WCF security settings (`<security mode>`, `<transport>`, `<message>`, certificate configuration) are critical to migrate correctly. Do not silently change security modes. If the original service uses `Transport`, `Message`, or `TransportWithMessageCredential` security, preserve the same mode in CoreWCF. If CoreWCF does not support the exact security configuration, present the gap to the user with options — do not downgrade security silently.

Inform the user of any unsupported features found and document them in the task's progress notes.

### Step 9: Handle APM-Style Service Contracts (Begin/End Pattern)

Search for `[OperationContract(AsyncPattern = true)]` and `IAsyncResult` methods. If none found, skip this step. CoreWCF does not support APM — convert `BeginX`/`EndX` pairs to `Task<TResult> XAsync(...)` (remove `AsyncPattern = true`).

Inspect the `Begin`/`End` method bodies to decide which conversion strategy to use:

**Strategy A — Real APM underneath:** The `Begin` method delegates to an inherently asynchronous API that returns `IAsyncResult` (e.g., `Stream.BeginRead`, `Socket.BeginSend`, a third-party async I/O library). Wrap the pair with `Task<TResult>.Factory.FromAsync`, passing the Begin/End methods and parameters directly — do **not** use the overload that takes a pre-started `IAsyncResult` (severe performance issues):
```csharp
public Task<string> FooAsync(string param1, int param2)
{
    return Task<string>.Factory.FromAsync(this.BeginFoo, this.EndFoo, param1, param2, null);
}
```

**Strategy B — No real APM underneath:** The `Begin`/`End` methods perform synchronous work (e.g., direct database calls, in-memory computation, file I/O via synchronous APIs) and only used the APM pattern because WCF required `AsyncPattern = true` for async contracts. In this case do **not** wrap them with `Task.Factory.FromAsync`. Instead, remove the `Begin`/`End` pair entirely and rewrite the operation as a straightforward method:
- Use `async Task<TResult>` with `await` if the work can be converted to truly async calls (e.g., replacing `DbCommand.ExecuteReader()` with `await ExecuteReaderAsync()`)
- Use a synchronous body returning `Task.FromResult<TResult>(result)` if no async alternative exists

After converting, update all callers to use the new Task-based signatures.

### Step 10: Update Tests

- Search for tests that self-host services via `ServiceHost`. These will not compile after migration
- Convert `ServiceHost`-based test setup to use `WebApplicationFactory<Program>` with `HttpClient`. This requires the test project to reference the web host project and may need `InternalsVisibleTo` or a public `Program` class
- Add CoreWCF package references to the test project if it references service contracts directly
- Ensure the base address in tests points to the CoreWCF service endpoint
- If the test infrastructure changes are significant, present the approach to the user before proceeding

## Success Criteria

- [ ] Server-side `System.ServiceModel` replaced with CoreWCF (client packages retained if needed)
- [ ] `using` statements updated from `System.ServiceModel` to `CoreWCF` namespaces
- [ ] Services hosted via Program.cs with `AddServiceModelMetadata()`; endpoints ordered specific-first
- [ ] Service behaviors registered via DI (keyed by service type when multiple services exist); endpoint behaviors + ServiceHost mutations migrated to `ConfigureServiceHostBase<TService>`; system endpoints skipped
- [ ] `.svc` files removed (`.svc.cs` preserved); APM contracts converted to Task-based async
- [ ] Project builds without WCF errors; tests updated; user notified of unsupported features/retained packages
