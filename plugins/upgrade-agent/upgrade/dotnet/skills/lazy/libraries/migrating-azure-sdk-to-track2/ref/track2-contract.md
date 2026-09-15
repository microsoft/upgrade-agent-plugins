# The Track 2 Contract

The [.NET Azure SDK design guidelines](https://azure.github.io/azure-sdk/dotnet_introduction.html)
define shared design conventions. This file describes their migration consequences; the installed
package's actual APIs and version-matched documentation establish what it implements.

Read it as the target you are porting *to*. Two limits on how universally it applies:

- **It describes `Azure.Core` clients that call HTTP REST services.** The guidelines say so
  explicitly. AMQP-based libraries diverge: `ServiceBusSender.SendMessageAsync` returns a bare `Task`,
  `ScheduleMessageAsync` returns `Task<long>`, and failures throw `ServiceBusException` rather than
  `RequestFailedException`. Event Hubs behaves the same way with `EventHubsException`.
- **Individual libraries deviate from individual guidelines.** These are design rules for new
  libraries, not invariants you can rely on when reading an existing one. Where a rule below matters
  to a port, confirm it against the actual client surface with `get_type_info`.

When a package is not an `Azure.Core` client at all, none of this applies — check the gate in
`SKILL.md` first.

## Contents

- [Why Track 2 is a new package and not an upgrade](#why-track-2-is-a-new-package-and-not-an-upgrade)
- [Clients](#clients)
- [Subclients and resource affinity](#subclients-and-resource-affinity)
- [Service methods](#service-methods)
- [Return types](#return-types)
- [Paging](#paging)
- [Long-running operations](#long-running-operations)
- [Exceptions](#exceptions)
- [Client options](#client-options)
- [Credentials](#credentials)
- [Models](#models)
- [Support for mocking](#support-for-mocking)
- [Serialization and dependencies](#serialization-and-dependencies)
- [Target frameworks](#target-frameworks)

## Why Track 2 is a new package and not an upgrade

The guidelines forbid API-breaking changes in any release of an existing package, and require a new
package with new assembly names, new namespaces, and new type names when a break is unavoidable.
Track 2 *is* that new package. This is why there is never an in-place version bump from Track 1, why
both generations can be referenced at once, and why the type names collide.

Namespaces generally follow `Azure.<group>.<service>[.<feature>]`, for example `Azure.Storage.Blobs`,
`Azure.Security.KeyVault.Secrets`, and `Azure.ResourceManager.Compute`. The guidelines' approved
namespace groups are a design taxonomy, **not an inventory of supported packages**. Their
`Azure.Cosmos` and `Azure.Media` entries do not establish migration targets: Cosmos DB still ships
as `Microsoft.Azure.Cosmos`, and retired Media packages require a catalog/service-status check.
Resolve real package and namespace names from the catalog and `get_namespace_info`, not a prefix
substitution or membership test. A package name matches the main namespace of its component.

Nothing is placed directly under the `Azure` namespace, so a bare `Azure.Something` type is either
`Azure.Core` itself (`Response`, `Pageable<T>`, `ETag`, `RequestFailedException`) or not an Azure SDK
type at all.

## Clients

### Shape

```csharp
public class ConfigurationClient
{
    public ConfigurationClient(string connectionString);
    public ConfigurationClient(string connectionString, ConfigurationClientOptions options);
    public ConfigurationClient(Uri uri, TokenCredential credential, ConfigurationClientOptions options = default);
    protected ConfigurationClient();   // mocking

    public virtual Response<ConfigurationSetting> Get(string key, CancellationToken cancellationToken = default);
    public virtual Task<Response<ConfigurationSetting>> GetAsync(string key, CancellationToken cancellationToken = default);
}
```

Guidelines that hold for every client:

- Named with a `Client` suffix, a class rather than a struct, and placed in the package's root
  namespace.
- **Immutable and thread-safe.** Every public member is safe to call concurrently.
- The simplest constructor takes only what is needed to reach the service, and uses no default
  parameter values.
- Options are a `ClientOptions` subclass named `<Client>Options`, with no default constructor.

### Consequence for migrating code

- **Cache and share the client.** Track 1 code commonly built a client per operation, often from a
  parsed account or connection string. Track 2 clients are designed to be constructed once and
  reused — a singleton in DI, registered with `Microsoft.Extensions.Azure`. Constructing per call is
  not just wasteful; for clients holding an AMQP connection it changes connection behavior.
- **There is no account or context object.** Entry points like `CloudStorageAccount` are gone.
  Construct the service client directly from a connection string or an endpoint plus a credential.
- **Client immutability means configuration is constructor-only.** Track 1 code that mutated a client
  property after construction, or set a per-operation options object on the client, has no direct
  port: the setting moves either to `<Client>Options` at construction, or to a per-call parameter.

## Subclients and resource affinity

Service clients are constructible. Resource and operation-group subclients are reached through a
factory method and have no public constructor.

| Kind | Naming | Reached by |
|---|---|---|
| Service client | `Client` suffix | constructor |
| Resource client | no suffix | `Get<Resource>(id)` |
| Operation group client | no suffix | `Get<Group>Client()` |
| Long-running operation | `Operation` suffix | returned from the service method |
| Page enumeration | `Pageable<T>` | `Get<Resource>s(...)` |

For example, `ContainerRegistryClient.GetRepository(name)` returns a `ContainerRepository` resource
subclient. Obtain it from the service client rather than constructing it directly.

**Consequence.** A client is *bound* to the resource it was obtained for, and that binding is part of
the contract. Porting a Track 1 call that took the resource name as a method argument into a Track 2
client that was constructed for a different resource compiles and then operates on the wrong target.
Check what each client instance is bound to, not just that the method names line up.

### Additional service clients

The guidelines also permit a service client at each level of a resource hierarchy. Storage uses
this shape: `BlobServiceClient.GetBlobContainerClient(name).GetBlobClient(name)` navigates between
service clients, and `BlobContainerClient` and `BlobClient` also have public constructors. Preserve
valid direct construction; do not impose resource-subclient constructor rules on these clients.

## Service methods

- HTTP clients generally offer sync/async pairs differing by the `Async` suffix. AMQP service
  operations in Service Bus and Event Hubs are async-only; inspect each member before porting.
- All service methods are `virtual`, and so are properties and methods returning other clients.
- An optional `CancellationToken cancellationToken = default` is the last parameter (or
  `RequestContext context` on protocol methods).
- Client parameters are validated; service parameters are not — the service validates those.

**Consequence.** APM (`Begin*`/`End*`) and callback-based operations move to the task-based API.
Remove a sync-over-async wrapper only when the target really provides the equivalent synchronous
operation. Otherwise make the call chain async and report the propagated signature change. If a
public synchronous boundary cannot change, raise that compatibility decision instead of inventing
a sync method, blocking blindly, or deleting the wrapper's behavior.

## Return types

Every HTTP service call returns `Response<T>`, `Response`, or their `Task<>` equivalents. Methods on
AMQP-based libraries do not — check the surface.

- `Response<T>` carries the deserialized model plus the raw response. Reach the model with `.Value`,
  or rely on the implicit conversion to `T`.
- `GetRawResponse()` exposes status code, headers, and content.
- Unstructured payloads are `Stream` for large content, `byte[]` for small, and
  `ReadOnlyMemory<byte>` for slices.

**Consequence.**

- A Track 1 method that returned the model directly now returns a wrapper. Assignments compile
  through the implicit conversion, but anything that inspected an HTTP status must move to
  `GetRawResponse().Status` or to the exception.
- **Absence behavior is the trap.** Track 1 APIs varied: some returned `null` for a missing resource,
  some threw. Track 2 `Get*` methods throw `RequestFailedException` with `Status == 404`. A ported
  null check becomes dead code and the throw escapes. Where the library offers an explicit
  `Exists`-style call or a `*IfExists` variant, prefer it over catching.

## Paging

Collection-returning methods return `Pageable<T>` or `AsyncPageable<T>`, named `Get<Resource>s`.

```csharp
await foreach (BlobItem item in containerClient.GetBlobsAsync())
{
    // one item at a time
}

// page-level control, including continuation tokens and a server page size hint
await foreach (Page<BlobItem> page in containerClient.GetBlobsAsync().AsPages(pageSizeHint: 100))
{
}
```

**Consequence.**

- `*Segmented(continuationToken)` `do`/`while` loops become `await foreach`. The continuation token
  is still reachable, but only through `.AsPages()`.
- **Page size is not a result limit.** `pageSizeHint` controls the request; it does not cap how many
  items the enumeration yields. Track 1 code that used a page size as a `Take` must be ported to an
  explicit limit.
- **Cardinality changes are silent.** Where Track 1 handed a *batch* to a callback and the Track 2
  shape enumerates *items*, any per-invocation work — a checkpoint, a commit, a log line, a metered
  call — now happens once per item instead of once per batch. This compiles and costs money.

## Long-running operations

LRO methods return a subclass of `Operation<T>` and take `WaitUntil` as their **first** parameter.

```csharp
// wait for completion
var operation = await client.StartSomethingAsync(WaitUntil.Completed, ...);
T result = operation.Value;

// start and poll manually
var operation = await client.StartSomethingAsync(WaitUntil.Started, ...);
await operation.WaitForCompletionAsync();
```

`Operation<T>` exposes `HasCompleted`, `HasValue`, `Value` (which throws unless succeeded), `Id`,
`UpdateStatus`, and `WaitForCompletion`. Some libraries still use the older pattern, where LRO methods
carry a `Start` prefix and take no `WaitUntil`.

**Consequence.** Operations that were effectively synchronous in Track 1 are now explicitly
long-running, and `WaitUntil` forces a decision. `WaitUntil.Started` returns as soon as the service
accepts the request, so any code that depended on the operation having finished — most often a delete
followed by a recreate — needs `WaitUntil.Completed` or an awaited `WaitForCompletionAsync()`.
Choosing `Started` to keep the old timing is how a delete/recreate turns into a conflict.

## Exceptions

Failures of an HTTP service call throw `RequestFailedException` or a subtype, carrying `Status` and
`ErrorCode`. Libraries do not introduce new exception types unless there is a distinct programmatic
handling scenario — and the messaging libraries are exactly that case, throwing `ServiceBusException`
and `EventHubsException` instead. Confirm the replacement's exception type before retargeting a
`catch`.

**Consequence.** Every Track 1 exception type disappears: `StorageException`, `CloudException`,
`KeyVaultErrorException`, `MessagingException`, `AdalException`, and the rest. A `catch` block naming
one of them still compiles as long as the legacy package is referenced, and stops catching anything
once it is removed. Retarget each one and map the status source:

| Track 1 | Track 2 |
|---|---|
| `StorageException.RequestInformation.HttpStatusCode` | `RequestFailedException.Status` |
| `CloudException.Response.StatusCode` | `RequestFailedException.Status` |
| service-specific error code property | `RequestFailedException.ErrorCode` |

Catching `RequestFailedException` broadly where Track 1 caught one narrow type widens the handler.
Filter on `Status` or `ErrorCode` to keep the original scope.

This table maps service failures, not every client-side failure. In particular, a total deadline
implemented with cancellation needs separate timeout handling as described under client options.

## Client options

```csharp
public class BlobClientOptions : ClientOptions
{
    public BlobClientOptions(ServiceVersion version = ServiceVersion.V2024_11_04);
    public enum ServiceVersion { V2021_02_12 = 1, /* ... */ }
}
```

`ClientOptions` supplies `Retry`, `Diagnostics`, and `Transport`. The `ServiceVersion` enum is the
first constructor parameter, starts at 1, and defaults to the latest supported version; value 0 is
reserved and throws.

**Consequence.**

- Clients call the newest service API version by default. Pinning is possible and is the right move
  when the target service is an older stamp — but a pin is a decision that must be reported, not a
  silent default.
- **Retry and timeout knobs changed scope, not just name.** Track 1 `MaximumExecutionTime` bounded
  the operation across retries; `RetryOptions.NetworkTimeout` bounds individual network operations.
  Include retry backoff in duration estimates, but do not treat attempt count times network timeout
  as an exact total bound. Preserve a whole-call budget with a deadline `CancellationTokenSource`,
  linked to the caller's token, and pass its token through all requests, transfers, and page reads.
- **Preserve timeout recovery separately from caller cancellation.** Legacy deadline expiry could
  be caught as `StorageException`; a canceled deadline token raises `OperationCanceledException`
  (including `TaskCanceledException`), not `RequestFailedException`. Retain the old timeout fallback
  only when the deadline source is canceled and the caller's token is not. Otherwise propagate
  cancellation. Do not fabricate `RequestFailedException` or absorb explicit caller cancellation.
- **`ServerTimeout` is a separate server-side request hint.** It is neither a network timeout nor
  a whole-call budget, and has no direct `BlobClientOptions` equivalent. Check the target operation
  for support; report any setting that cannot be preserved instead of silently dropping it.
- **Preserve custom HTTP transport configuration.** For a caller-owned `HttpClient`, set
  `options.Transport = new HttpClientTransport(httpClient)` before constructing the SDK client.
  Carry over proxy, TLS and handler behavior, and account for the client's own timeout alongside
  the SDK deadline/retry settings. Preserve lifetime and ownership: disposing the transport also
  disposes its wrapped client. An existing handler need not be rewritten as `HttpPipelinePolicy`;
  if a policy conversion is appropriate, preserve its behavior, order and registration.
- Track 1 per-request options objects passed to individual calls generally become either
  constructor-time client options or per-call parameters — check which, because moving a per-call
  setting to the client silently widens its scope.

## Credentials

- `TokenCredential` is defined in `Azure.Core`; `Azure.Identity` supplies the implementations
  (`DefaultAzureCredential`, `ClientSecretCredential`, `ManagedIdentityCredential`, …). Every client
  that supports Entra ID takes the `Azure.Core` abstraction.
- Clients re-read the credential before every request, so a rotated **token** needs no new client.
  That does not make a credential's own configuration mutable: `ClientSecretCredential` and
  `EnvironmentCredential` capture their settings at construction. `AzureKeyCredential.Update` and
  `AzureSasCredential.Update` are the mutable cases.
- Connection strings are offered only where the portal offers one, and cannot roll over.

The full legacy-to-`Azure.Identity` map is in [authentication.md](authentication.md).

## Models

- Service-controlled properties are get-only; user-settable ones have public setters.
- Large libraries put output models in a `.Models` subnamespace.
- Collection properties are `IReadOnlyList<T>`/`IList<T>` or `IReadOnlyDictionary<K,V>`/
  `IDictionary<K,V>`.
- Known value sets are `enum`; sets the service can extend are an *extensible enum* — a
  `readonly struct` with well-known static fields that still accepts unknown values.
- Models are constructed in tests through a static `<Service>ModelFactory`, not through public
  constructors.
- `Azure.ETag` represents ETags; `MatchConditions`/`RequestConditions` carry conditional headers;
  `System.Uri` represents URIs; `BinaryData` carries payloads.

**Consequence.**

- **Equality semantics change.** Track 1 generated DTOs were plain classes with reference equality,
  so `Contains`, `Distinct`, `Equals`, and `Except` against them compared identity and usually never
  matched. Track 2 models may implement `IEquatable<T>`. Porting such a call faithfully preserves a
  latent bug; porting it onto a value-equal model changes behavior. Either way it needs a decision,
  not a mechanical rename.
- **Extensible enums are not enums.** They do not support an exhaustive `switch` over all cases, have
  no `Enum.Parse`, and compare by value through their own operators.
- Tests and fixtures that constructed Track 1 DTOs directly need the model factory.

## Support for mocking

The guidelines require every client library to be mockable without a live service, and specify how:

- A `protected` parameterless constructor on clients, subclients, and `Operation<T>` subclasses.
- `virtual` service methods, `virtual` properties, and `virtual` methods that return other clients.
- Instance methods rather than extension methods, because extension methods cannot be mocked.
- A static `<Service>ModelFactory` in the model namespace for constructing model graphs, since model
  types deliberately lack public constructors.

**Consequence for migrating tests.** Inspect wrappers, client subclasses and DTO construction against
the target's actual mocking surface. Preserve wrapper behavior and public contracts; remove
indirection only after establishing it is redundant. Use the model factory where required for output
fixtures and check its overloads: the
guidelines require older ones to be hidden with `[EditorBrowsable(Never)]` and stripped of default
values when properties are added, so an existing call can bind to a different overload after an
upgrade.

A test project left uncompilable is not a follow-up item. It is the only thing that would have caught
the rest of the migration.

## Serialization and dependencies

Track 2 libraries serialize with `System.Text.Json` and depend on little beyond `Azure.Core`. The
guidelines forbid depending on unapproved third-party packages, and name `Newtonsoft.Json` as
specifically replaced.

**Consequence.** `Newtonsoft.Json` attributes on models carried over from Track 1 — `[JsonProperty]`,
custom `JsonConverter`s, `NullValueHandling` — are not honored by `System.Text.Json`. Property
casing, null handling, and enum handling all differ. Any model that crosses a persistence or wire
boundary must be checked rather than assumed. Note the exception: `Microsoft.Azure.Cosmos` is *not*
an `Azure.Core` client and still serializes with Newtonsoft by default.

## Target frameworks

Every library targets `netstandard2.0` and usually the current LTS .NET as well. A Track 2 package
therefore restores on .NET Framework 4.6.1 and later — the framework is rarely the blocker for
adopting one.
