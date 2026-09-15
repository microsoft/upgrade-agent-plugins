---
name: migrating-azure-sdk-to-track2
description: >
  Migrates deprecated Azure SDK for .NET packages to supported Track 2 replacements across service
  families and both planes, using the official catalog and .NET design guidelines while preserving
  behavior. Use when replacing WindowsAzure.Storage, WindowsAzure.ServiceBus, Microsoft.Azure.ServiceBus,
  Microsoft.Azure.KeyVault, Microsoft.Azure.EventHubs, Microsoft.Azure.EventGrid, Microsoft.Azure.Search,
  Microsoft.Azure.Storage.*, Microsoft.Azure.CognitiveServices.*, Microsoft.Azure.Management.* or
  *.Fluent packages, Microsoft.WindowsAzure.*, Microsoft.Rest.ClientRuntime, or
  Microsoft.Azure.Services.AppAuthentication. Triggers for "migrate Track 1 to Track 2", "replace
  deprecated Azure SDK packages", and "modernize Azure client libraries". Package replacement must
  be an agreed goal, not a side effect of a framework retarget or a supported-package version bump.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Migrating the Azure SDK for .NET to Track 2

## Scope

Owns package selection and source migration across Azure service families. **Package presence or
deprecation alone does not authorize replacement.** Proceed only when replacement is requested or
approved in the scenario plan; during a framework/version-only upgrade, report the opportunity and
ask before expanding scope. A blocked replacement is reported, not silently added to the task.

Hand off rather than duplicating:

| Situation | Skill |
|---|---|
| Functions triggers, bindings, or host model | `migrating-azure-functions-startup`, `migrating-azure-functions-to-v2` |
| `Microsoft.Azure.DocumentDB[.Core]` → `Microsoft.Azure.Cosmos` | `migrating-documentdb-to-cosmos` |
| `Microsoft.Azure.CosmosDB.BulkExecutor` | `migrating-cosmosdb-bulk-executor` |
| ADAL used for general-purpose user sign-in, not for Azure SDK tokens | `migrating-adal-to-msal` |
| `packages.config` or non-SDK-style project mechanics | `managing-legacy-dotnet-packages` |
| Capturing a test baseline before migrating | `generating-upgrade-test-baseline` |

`Microsoft.Azure.Cosmos.Table` is **not** a Cosmos handoff despite the name — it replaces with
`Azure.Data.Tables` and belongs here. Load a handoff skill by exact ID with
`get_instructions(query='<skill-name>', kind='skill')`; passing `kind` alone only lists skills, and
selection usually returns just one skill, so never assume one is already loaded.

**Read the `ref/` files when their step is reached, not upfront.** Loading them all at the start
spends context on planes and services this migration does not touch.

## Gate: do the Track 2 patterns apply at all?

Check before applying `Response<T>`, `Pageable<T>`, `WaitUntil`, `<X>ClientOptions`, or
`RequestFailedException` to anything. Not every package under a Microsoft or Azure prefix is an
`Azure.Core` client; device, relay, and protocol SDKs wrap MQTT, AMQP, or WCF directly, and forcing
the shapes onto them produces code that cannot work.

- **No `Azure.Core` dependency → the patterns do not apply.** A reliable negative test: read the
  replacement's nuspec or run `dotnet list package --include-transitive`. `Microsoft.Azure.Devices.Client`
  and `Microsoft.Azure.Relay` depend on neither.
- **An `Azure.Core` dependency is not proof they do apply.** `Microsoft.Azure.Cosmos` depends on it
  and still throws `CosmosException`. The positive test is the client's own surface — `get_type_info`,
  and confirm its operations return `Response<T>` or `Pageable<T>`.

**Run the gate per package, not per prefix**, because neighbouring names land on opposite sides:
`Microsoft.Azure.Devices.Client` is the IoT device SDK and is not an `Azure.Core` client, while
`Microsoft.Azure.Devices.DigitalTwin.Client` replaces with `Azure.DigitalTwins.Core` and is one.
Also confirm the replacement is the **same live service** — a `Replace` value can name a redesigned
service whose concepts do not correspond, which is a rewrite for the user to scope.

## The Track 2 contract

The **[.NET Azure SDK design guidelines](https://azure.github.io/azure-sdk/dotnet_introduction.html)**
remain the primary source for shared conventions. Read their migration consequences in
[ref/track2-contract.md](ref/track2-contract.md). Resolve authority by the question:

| Question | Authority |
|---|---|
| Expected design conventions and their meaning | The .NET design guidelines |
| APIs, defaults and behavior of the selected package version | Its installed surface, XML docs and version-matched SDK/service documentation |
| Package status and candidate replacements | The official catalog; verify service equivalence |
| Type renames, splits and migration steps | Official .NET migration guide and replacement samples, checked against the installed API |

Repository prose is a claim to verify. Guidelines do not create APIs missing from an installed
library, and deviations are not limited to named examples here. Preserve valid library-specific
behavior; a stale migration guide is not a reason to rewrite guidelines-conformant code.

Five parts of the contract carry most of the rewrite:

- **`Response<T>` wraps an HTTP result.** Use `.Value` for the model and `GetRawResponse().Status`
  for HTTP status; implicit conversion can hide the wrapper in assignments.
- **`Pageable<T>` / `AsyncPageable<T>` replace segmented listing.** `await foreach` over the result;
  continuation tokens and page size live on `.AsPages()`. Page size is a request hint, not a result
  limit.
- **`Operation<T>` with `WaitUntil` first is how long operations work.** `WaitUntil.Completed` blocks;
  `WaitUntil.Started` returns as soon as the service accepts the request.
- **`RequestFailedException` replaces the Track 1 exception type for HTTP services.** `Status` for the
  HTTP code, `ErrorCode` for the service error string. A `catch` naming `StorageException`,
  `CloudException`, or `KeyVaultErrorException` still compiles while the legacy package is referenced,
  then stops catching anything once it is removed. Client-side deadline cancellation needs separate handling.
- **`TokenCredential` (defined in `Azure.Core`, implemented by `Azure.Identity`) is the Entra
  credential abstraction.** Clients are immutable, thread-safe, and meant to be cached — construct one
  per application and share it. Key, SAS, shared-key, and connection-string credentials remain valid
  where the service offers them.

**The contract is not universal, so confirm it per client rather than assuming it.** The guidelines
were written for request/response REST services, and the AMQP-based messaging libraries deliberately
diverge: `ServiceBusSender.SendMessageAsync` returns a bare `Task`, `ScheduleMessageAsync` returns
`Task<long>`, `CreateMessageBatchAsync` returns `ValueTask<ServiceBusMessageBatch>`, and failures
throw `ServiceBusException` — `EventHubsException` for Event Hubs. Storage exposes constructible service
clients at each resource level, a hierarchy the guidelines permit. Read the actual surface with
`get_type_info` before porting a call to `Response<T>` or retargeting a `catch`.

## Workflow

Track progress through the eight steps below in the active scenario.

### Step 1: Inventory Azure package references

Call `get_project_dependencies` for each project in scope. It reports whether Central Package
Management is enabled, every package with its version, and **which file defines it**, so you do not
edit the wrong one. Collect:

- `Microsoft.Azure.*` — the largest legacy family, plus some current packages
- `Microsoft.WindowsAzure.*` and `WindowsAzure.*` — always legacy
- `Azure.*` — mostly current, but roughly 29 are deprecated because the service retired
- `Microsoft.Rest.*` — the Track 1 runtime, which exists only to support legacy packages
- `Microsoft.Extensions.Azure` — current, relevant when wiring clients into DI

Also record transitive references — a legacy package pulled in transitively still blocks the
migration if it forces an incompatible `Azure.Core`.

**Then search the whole repository, because the dependency graph does not see everything.**
`get_project_dependencies` reports only what the projects you point it at reference, and files
outside that reactor are where a migration is most often left half-done:

```powershell
Get-ChildItem -Recurse -File |
  Where-Object { $_.FullName -notmatch '(\\|/)(\.git|bin|obj|node_modules|packages)(\\|/)' } |
  Select-String -Pattern '\bMicrosoft\.(Azure|WindowsAzure|Rest|ServiceBus)\b|\bWindowsAzure\b|\bAzure\.'
```

Places the graph misses: projects in no `.sln`, `Directory.Build.props`/`.targets`,
`Directory.Packages.props`, other `*.props`/`*.targets`, `packages.config`, `*.nuspec`, `app.config`
and `web.config` binding redirects, Dockerfiles, CI YAML, deployment scripts, and `README` snippets.
This is a broad inventory, not a deprecation verdict: classify every hit against the catalog and
approved scope. It includes `Microsoft.ServiceBus` source/assembly names and `Azure.*` packages
that may themselves be deprecated. Record legacy namespaces and types, including unqualified usages,
for the completion search; preserve supported packages and out-of-scope uses.

### Step 2: Resolve each package against the official catalog

```text
https://raw.githubusercontent.com/Azure/azure-sdk/main/_data/releases/latest/dotnet-packages.csv
```

Match on the exact `Package` value and record `Type`, `Support`, `EOLDate`, `Replace`, and
`ReplaceGuide`. Fetch once and reuse the parsed result — it is about 1,200 rows.
[ref/package-catalog.md](ref/package-catalog.md) has the field semantics, the lookup rules, the cases
where the columns mislead, and the offline fallback. Three rules that are got wrong most often:

- **Resolve the replacement too.** Some `Replace` values name packages that are themselves
  deprecated. When that happens the service is retiring: report it, do not migrate.
- **`Replace == NA` does not mean retired.** It means the catalog cannot name one successor. Read
  `ReplaceGuide` first — it may be a one-to-many split, a successor named only in prose, a guide for a
  *different language*, or a genuine retirement. Only the last is a stop-and-report.
- **Do not take versions from `VersionGA`.** It ignores the project's target framework. Use
  `get_supported_package_version`, and prefer stable: a `-beta` or `-preview` package is a support
  commitment for the user to accept, not something to adopt silently.

### Step 3: Classify and route

| Classification | Signal | Action |
|---|---|---|
| Deprecated with a live replacement | `Support == deprecated`, `Replace` names a supported package | Migrate. The main path. |
| Deprecated, replacement also deprecated | resolved target is itself `deprecated` | Stop and report — the service is retiring. |
| Deprecated, `Replace` is `NA` | read `ReplaceGuide` | Split, prose successor, wrong language, or retirement. |
| Deprecated, no replacement and no guide | both `NA` or blank | Stop and report. About a third of the deprecated catalog. |
| Likely legacy, not in catalog | `Microsoft.Azure*` / `WindowsAzure*` prefix, no row | Check NuGet deprecation metadata, then the naming heuristics. |
| Track 1 runtime or test infrastructure | `Microsoft.Rest.ClientRuntime*`, `Microsoft.Azure.Common*`, `Microsoft.WindowsAzure.Common*` | Remove once the last consumer is gone. |
| Current | `Azure.*` with active or blank support | Leave alone. |

`Type == compat` does not change the routing, but it warns that the row may be a repackaging within
the same generation (`Microsoft.Azure.Jobs` → `Microsoft.Azure.WebJobs`), leaving no client shape to
rewrite. Decide from the resolved target: `Microsoft.Azure.Storage.Common` → `Azure.Storage.Common`
is `compat`-typed and is a real track migration.

**Route on the resolved replacement, not on the catalog's `Type` column.** `Type` describes the
legacy package, and it misroutes: `Microsoft.Hadoop.Client` is typed `client` and replaces with
`Azure.ResourceManager.HDInsight`.

- Replacement is `Azure.ResourceManager`, or starts with `Azure.ResourceManager.` → read
  [ref/management-plane.md](ref/management-plane.md) **before writing any ARM code**. Match the exact
  core package too: `Microsoft.Azure.Management.Fluent`, `...ResourceManager[.Fluent]`, and
  `...ManagementGroups` all resolve to bare `Azure.ResourceManager`, and it is the core library
  rather than a provider — derive the `Azure.ResourceManager.<Provider>` packages from code usage.

  Four ARM rules are load-bearing enough to state here, though the ref carries the detail:

  - `armClient.GetXResource(id)` returns an unfetched handle. Retain the resource returned by
    `GetAsync()` before reading `.Data`; fetching does not populate the original handle.
  - Check update semantics per operation. PATCH can preserve omitted top-level properties while
    replacing a supplied collection: a VM patch containing only one tag removes the other tags.
    Use `AddTagAsync` for additive tags. A partial `CreateOrUpdate` PUT can also clear omitted state;
    use the supported operation or preserve required state. If semantics or concurrency protection
    cannot be established, stop that mutation and report the decision needed; never guess a merge.
  - `WaitUntil` has no default, so every create, update, and delete site must be touched. Old blocking
    call → `Completed`; old `Begin*` → `Started`; **cannot tell → `Completed`**, which costs latency
    rather than correctness.
  - A Fluent chain creates resources implicitly. Track 2 creates nothing implicitly, so the chain
    becomes explicit creates in dependency order, each passing its `.Id` to the next. Enumerate the
    resources the chain actually creates before rewriting, and diff the list afterwards.
- Replacement is any other `Azure.*` → the data-plane path in this file.
- Replacement is neither (`Microsoft.Graph`, `Microsoft.Azure.Cosmos`, `Microsoft.Azure.WebJobs.*`) →
  no mechanical port applies. Follow the guide; treat `Microsoft.Graph` as a rewrite.
- A package can land in both planes — `Azure.Monitor.Query` splits across data-plane and
  management-plane targets. Handle each half on its own path.

### Step 4: Derive the real replacement set from code usage

`Replace` is a hint, not an instruction. Inspect the code and add only what is used.

**Packages that split.** `WindowsAzure.Storage` splits across `Azure.Storage.Blobs`,
`Azure.Storage.Queues`, `Azure.Storage.Files.Shares`, and `Azure.Data.Tables` — the catalog's
suggestion of `Azure.Storage.Common` is a shared dependency, not a client library.
`Microsoft.Azure.KeyVault` splits across `.Secrets`, `.Keys`, and `.Certificates`.
`Microsoft.Azure.Management.Fluent` fans out to one `Azure.ResourceManager.*` package per provider
the code touches.

**Packages that need a companion.** Event Hubs processor code needs both `Azure.Messaging.EventHubs`
and `Azure.Messaging.EventHubs.Processor`, and almost every migration needs `Azure.Identity`. The
reverse also happens: `ServiceBusAdministrationClient` ships inside `Azure.Messaging.ServiceBus`, so
administration needs no second package.

### Step 5: Apply package reference changes

**Add the new packages before removing the old ones** — rewriting against a package that is not yet
referenced produces a wall of unresolved-type errors that hides the real problems. Follow the
project's existing package management mode: `<PackageVersion>` in `Directory.Packages.props` with
versionless `<PackageReference>` under Central Package Management, otherwise the version on the
`<PackageReference>`.

Once no source file references the old namespaces, remove the legacy `<PackageReference>` entries,
any orphaned `<PackageVersion>` entries, the Track 1 runtime packages, and
`Microsoft.Azure.Services.AppAuthentication` / `Microsoft.IdentityModel.Clients.ActiveDirectory`.

For packages sharing `Azure.Core`, incompatible versions can produce restore/build diagnostics such
as NU1605, or runtime assembly-load failures. Resolve the offending dependency within the project's
package policy instead of suppressing the warning or pinning `Azure.Core` blindly.

### Step 6: Rewrite the source

Work one service at a time and finish it — running both generations for the same service produces
ambiguous-reference errors, because the type names collide by design.

**Consult the contract first**, then confirm the selected client's actual surface and documented
behavior. Do not invent a synchronous method, response wrapper or exception type to fit a generic rule.

Use `get_namespace_info` and `get_type_info` to inspect the defining package and actual API surface.
With scenario assessment data they can also recover types from removed or replaced dependencies;
they do not automatically infer semantic renames such as `CloudBlobClient` to `BlobServiceClient`.
For renamed or split types, consult the official .NET migration guide or the replacement's README
and samples, then inspect the candidate target type. **Record the guide URL for each package** for
Step 8; use it for mappings and named behavior changes within the authority boundaries above.

The goal is **functional equivalence, not feature expansion**. Do not adopt a capability the legacy
code did not have, and do not move files or rename the application's own namespaces and types to
mirror the new SDK's layout. Only the SDK types and `using` directives change.

**Migrate tests with the code.** Inspect the target's mocking surface: protected constructor,
virtual members and `<Service>ModelFactory` for output models. Port wrappers, subclasses and DTO
construction as needed; broken tests are not a deferred follow-up.

**Before rewriting credentials, read** [ref/authentication.md](ref/authentication.md). It covers
choosing a credential rather than defaulting to `DefaultAzureCredential` everywhere.

**Keep the existing authentication mode, and carry every parameter of the existing identity across.**
If the legacy code used a connection string or an account key, the port keeps doing so; moving to
Entra needs a data-plane role assignment and is a separate, reported decision. Report retained
secret-bearing connection strings and account keys as modernization findings without exposing values.
Three invariants, each of which fails silently at runtime rather than at build time:

- **Never substitute `DefaultAzureCredential` for a credential that named a specific identity.** A
  service principal, certificate, or auth file identifies one principal; `DefaultAzureCredential`
  resolves to whatever the host offers. Port tenant, client ID, and secret or certificate explicitly.
- **A user-assigned managed identity's client ID must survive**, or the credential binds to the
  system-assigned identity instead.
- **A sovereign cloud needs both halves** — authority host on the credential *and* endpoint or
  environment on the client. Setting only the authority calls the public endpoint.

For `AzureServiceTokenProvider`, inspect constructor configuration and `AzureServicesAuthConnectionString`
before selecting a replacement; some modes have no direct equivalent. If identity/configuration cannot
be established, leave that migration blocked and ask the owner. Do not guess an identity.

### Step 7: Run the behavior audit

Read [ref/behavior-audit.md](ref/behavior-audit.md) and audit all four shapes.

### Step 8: Validate and report

**Execute the completion gates and show their results; do not assert success without the search.**

1. Build the affected projects, main **and test**. If a test baseline was captured before the
   migration, tests must pass at or above it and every new failure is fixed rather than deferred —
   acceptable only when shown to be pre-existing. Where no baseline exists,
   `generating-upgrade-test-baseline` captures one; take it *before* changing code.
2. **Re-run Step 1 across the whole repo and reconcile every hit.** Supported `Azure.*` references
   are expected; a broad prefix match is not a failure. Report supported/out-of-scope exceptions
   explicitly, including surviving transitive references.
3. Search the recorded retired package IDs, namespace/assembly names (including `Microsoft.ServiceBus`),
   client types, aliases and exception catches. Show zero unexplained in-scope remnants; resolving
   unqualified names may require reference search. Do not treat package-only grep as source coverage.
4. Walk [ref/track2-contract.md](ref/track2-contract.md), then the guide URLs from Step 6. Validate
   against the installed APIs and preserved behavior, not an imagined universal shape. Fix actual
   migration defects; do not rewrite valid library-specific behavior to satisfy generic guidelines.
5. Confirm versions came from `get_supported_package_version` or the repo's package policy. Name any
   prerelease reference and why it was unavoidable.
6. Produce the findings table from Step 7, covering all four shapes per migrated service, and report
   every package that could not be migrated with its EOL date and guide URL.

## The four defect shapes

A clean build proves almost nothing about an SDK migration. These four shapes cover the defects that
survive one, and they apply on both planes. [ref/behavior-audit.md](ref/behavior-audit.md) has the
questions to ask for each.

1. **External contract** — anything outside this codebase reading or writing the same bytes: message
   and blob bodies, serialization, encoding, persisted checkpoints, event schema, wire protocol.
   *Instance:* Track 1 `CloudQueue.EncodeMessage` defaulted to **`true`**, while Track 2
   `QueueClientOptions.MessageEncoding` defaults to **`None`**. A bare port silently **stops**
   Base64-encoding and breaks interop in both directions. The polarity is the reverse of the common
   assumption — do not restate it from memory.
2. **Operation contract** — the same call, different behavior: option defaults the legacy code set
   explicitly, knob *scope* changes, callback and result **cardinality**, conditional and concurrency
   semantics, replace-versus-patch, absence behavior, LRO completion.
   *Instance:* `ServiceBusProcessorOptions.AutoCompleteMessages` defaults to `true` — exactly as
   Track 1 did. Legacy code that turned it off for manual settlement, ported without that line, gets
   every handler path that returns without settling completed automatically, including paths that
   deliberately left the message locked for a retry. The hazard is a **dropped explicit setting, not a
   changed default.**
3. **Boundary and topology** — public members dropped from a wrapper, same-name types with changed
   roles, package splits and merges, what resource a client is *bound* to, parent-child hierarchy.
   *Instance:* `SearchIndexClient` exists in both generations with **opposite roles** — data plane
   bound to one index in Track 1, index management within a Search service in Track 2. A mechanical
   rename compiles and silently retargets the code at index management. The data-plane replacement is
   `SearchClient`, via `SearchIndexClient.GetSearchClient(name)`.
   *Also:* custom `HttpClient` handlers can remain behind `ClientOptions.Transport` using
   `HttpClientTransport`. If converting a handler to `HttpPipelinePolicy` instead, register it via
   `options.AddPolicy(policy, HttpPipelinePosition.PerCall | PerRetry)` in the intended order;
   converting the class without registration silently drops its behavior.
4. **Operational** — identity and authorization, transport, client lifetime and disposal, concurrency
   defaults, pinned API versions, service retirement.
   *Instance:* Cosmos changed its default connection mode from `Gateway` to `Direct`, which opens TCP
   straight to backend replicas over a wide port range. It works on a laptop and times out behind a
   firewall, App Service, or proxy.

### Other measured instances

Worked examples of the shapes above, not a checklist to scan. Most families have no entry here, and
the shapes still apply to them.

- **Service Bus body compatibility follows the producer, not just the package.** `BrokeredMessage(object)`
  normally uses binary-XML `DataContractSerializer`; stream/custom-serializer overloads need their own
  format. `Microsoft.Azure.ServiceBus.Message` carries caller-serialized bytes; Track 2 uses
  `BinaryData`. Preserve that encoding rather than assuming JSON. If formats must coexist, retain
  both readers and an explicit discriminator/try order; binary DCS needs
  `XmlDictionaryReader.CreateBinaryReader`. Read the bounded interop procedure and quota example in
  [ref/behavior-audit.md](ref/behavior-audit.md) before changing serialization. Unknown producer format
  or safe limits means ask/report, not guessing or draining the backlog into the DLQ.
- **Event Hubs changed handler cardinality.** `IEventProcessor.ProcessEventsAsync` received a *batch*
  (`MaxBatchSize` defaulted to 10); `ProcessEventAsync` receives **one event**, so checkpoint-per-batch
  ported directly becomes up to 10x the checkpoint-store writes. It compiles and costs money. Legacy
  `EventProcessorHost` checkpoints from either legacy generation are not directly readable by the new
  store. Plan checkpoint conversion and cutover; obtain approval for any reset or changed starting
  position rather than silently replaying or skipping events.
- **`DateTime` to `DateTimeOffset` is not a safe implicit conversion.** `new DateTimeOffset(dt)` on a
  `Kind == Unspecified` value applies the machine's offset — an eight-hour error on a Pacific host.
  Where the legacy member is documented as UTC (the `*Utc` naming generally), reinterpret with
  `DateTime.SpecifyKind(v, DateTimeKind.Utc)` rather than converting; where the intended kind cannot
  be established, leave it with a `TODO` and report unchecked. Widening a public signature to
  `DateTimeOffset` is also a caller-visible break.
- **Storage timeout scope changed.** `MaximumExecutionTime` applied across all retries;
  `RetryOptions.NetworkTimeout` bounds individual network operations. Include retry delays in
  estimates; preserve a total budget with a deadline `CancellationTokenSource` linked to caller
  cancellation and propagated through the whole call. Deadline expiry now raises
  `OperationCanceledException`, not `RequestFailedException`: retain timeout recovery separately,
  without swallowing caller cancellation. `ServerTimeout` is a distinct server-side hint with no
  direct `BlobClientOptions` equivalent; preserve it where supported or report the gap.

Further worked examples — Key Vault's soft-delete sequencing and metadata-only secret listings,
`CloudEvent` shipping in `Azure.Core` rather than the Event Grid package, and the stale pop receipt
from `UpdateMessageAsync` — are in [ref/behavior-audit.md](ref/behavior-audit.md).

## Standing rules

- **Unknown preconditions do not authorize behavior changes.** Assume external producers, backlog
  and deployment constraints remain unless confirmed otherwise. Preserve the known contract; if no
  safe branch can be established, stop that change and report it.
- **Never report an unverified default as preserved.** Verify both generations from version-matched
  documentation/source or a targeted probe; otherwise report unchecked.
- **Never invent a replacement package, and read `NA` narrowly.** When `Replace` is blank or `NA`,
  read `ReplaceGuide` first. `NA` means the Azure SDK team ships no successor, not that none exists:
  packages that merely *integrate* with Azure — SQL Server providers, logging sinks, OpenTelemetry
  exporters — can have one shipped by another team, so check NuGet before reporting a dead end. When
  there is genuinely nothing, report it. A guessed package name produces code that cannot work.
- **Do not run Track 1 and Track 2 side by side for one service.** The type names collide. Migrate a
  service completely, or not at all in this pass.
- **Version numbers come from `get_supported_package_version`, never from a guide.** Guides are frozen
  at authoring time and are routinely years stale.
- **A `Microsoft.Azure.*` prefix is not proof of deprecation,** and an `Azure.*` prefix is not proof of
  health. `Microsoft.Azure.Cosmos` and `Microsoft.Azure.WebJobs.*` are current migration targets;
  around 29 `Azure.*` packages are deprecated.

## Reporting

Report **Preserved** with evidence (or why not applicable), **Changed deliberately** with the
old/new behavior and cost, or **Unchecked** with the missing evidence. A deliberate increase from
checkpoint-per-batch to checkpoint-per-event is not "preserved"; neither is an untested assumption.

**Cover all four shapes per migrated service, not four rows for the whole migration.** One clean
Storage row does not show that Search was audited. Group services into one row only when the evidence
genuinely is shared, and say which services it covers. Produce the table whether the migration ran as
one task or several, list each rewritten wrapper's public members before and after rather than
asserting none were dropped, and name any unreachable branch you deleted along with why it was dead.

## Troubleshooting

**Service Bus processor will not start.** Register both `ProcessMessageAsync` and `ProcessErrorAsync`
before calling `StartProcessingAsync()`. Omitting either handler throws `InvalidOperationException`.

**Ambiguous type references after adding the new packages.** Both generations are referenced at once.
Expected mid-migration; it resolves when the legacy package goes. To compile in between, use a `using`
alias rather than fully qualifying every use.

**`Azure.Core` version conflict (NU1605, or a runtime `FileLoadException`).** Some `Azure.*` package in
the graph is pinned to an older version. Find it with `dotnet list package --include-transitive` and
raise that package rather than adding a direct `Azure.Core` reference.

**Catalog unreachable.** The naming heuristics in [ref/package-catalog.md](ref/package-catalog.md)
generate **candidates only** — renames and splits defeat prefix substitution. Confirm the package
exists and serves the intended role before referencing it, and mark
the classification provisional; if it cannot be confirmed, report it unchecked.

**Package not in the catalog at all.** The catalog covers packages the Azure SDK team owns. Most
`Microsoft.Azure.WebJobs.Extensions.*`, `Microsoft.Graph`, ADAL, and community packages have no row.
Check the package's NuGet deprecation metadata instead.

**A `client`-typed package that is not a .NET package.** The `wastorage*` and
`Microsoft.Azure.Storage.CPP*` rows are C++ packages whose `ReplaceGuide` points at the C++ SDK. In a
.NET project one of these is a native dependency — report it and do not follow the guide.

**Build is green and tests pass, but you have not run Step 7.** The migration is not done. That is
where the defects are.
