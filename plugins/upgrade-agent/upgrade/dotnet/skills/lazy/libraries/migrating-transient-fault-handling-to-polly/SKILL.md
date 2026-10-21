---
name: migrating-transient-fault-handling-to-polly
description: >
  Migrates the Enterprise Library Transient Fault Handling Application
  Block (EnterpriseLibrary.TransientFaultHandling and its .Data,
  .Configuration, .WindowsAzure.Storage, .ServiceBus and .Caching
  companions, including the
  Microsoft.Practices.EnterpriseLibrary.TransientFaultHandling.ServiceBus
  alias) to the modern .NET resilience stack —
  Microsoft.Extensions.Resilience and the Polly v8 resilience pipelines
  it is built on. Use when a project references one of the packages above,
  or when code uses
  RetryPolicy, RetryManager, RetryPolicyFactory,
  ITransientErrorDetectionStrategy, FixedInterval, Incremental,
  ExponentialBackoff, ReliableSqlConnection, or the
  ExecuteNonQueryWithRetry / ExecuteReaderWithRetry /
  ExecuteScalarWithRetry / OpenWithRetry extension methods. The block
  last shipped in 2013 and targets .NET Framework only, so it blocks
  any upgrade to modern .NET.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Enterprise Library Transient Fault Handling to Polly Migration

## Overview

The Enterprise Library Transient Fault Handling Application Block ("TFH", also called the Transient Fault Handling or Resilience IO block) last shipped as 6.0.1304 in 2013 and targets .NET Framework only. There is no modern-.NET build and none is coming, so every project referencing it is blocked at the target-framework change.

The supported successor is the .NET resilience stack: **`Microsoft.Extensions.Resilience`**, which is built on Polly v8 and brings `Polly.Core` and `Polly.Extensions` in transitively. One reference therefore supplies the whole surface this migration needs — `ResiliencePipelineBuilder` and `RetryStrategyOptions` for pipelines built directly, and `AddResiliencePipeline` with `ResiliencePipelineProvider<string>` for pipelines registered in dependency injection. Everything below is written against the Polly v8 API, because that is the API the package exposes.

This is **not** a drop-in package swap — the two API surfaces share no types. Changing the `PackageReference` without rewriting the call sites leaves the project uncompilable. Plan for code changes in every file that retries.

The structural translation is:

- A `RetryPolicy` built from a `RetryStrategy` plus an `ITransientErrorDetectionStrategy` becomes
- A `ResiliencePipeline` built by `ResiliencePipelineBuilder.AddRetry(new RetryStrategyOptions { ... })`, where the detection strategy becomes the `ShouldHandle` predicate and the retry strategy becomes `MaxRetryAttempts` plus `Delay` plus `BackoffType`.

## Choosing the Target

Make this decision before touching any call site, and record it in the migration notes. Branch 1 is evaluated **per call site**; branches 2 and 3 are a single project-wide choice between them.

1. **The retried operation belongs to an SDK that already retries.** Azure Storage, Service Bus, Cosmos DB, `HttpClient` through `Microsoft.Extensions.Http.Resilience`, and EF Core connection resiliency all retry internally. Delete the wrapper and configure the SDK instead of porting the policy — see Step 6. Decide this for each call site separately: one project commonly has some call sites that qualify and others that still need a pipeline, so a single match here never settles the whole project.
2. **Every call site left over, in a project with dependency injection or a generic host.** Use `Microsoft.Extensions.Resilience` and register named pipelines with `AddResiliencePipeline`. This is the default, and it is what the automated package mapping applies.
3. **Every call site left over, in a project with no DI container** — a class library or a plain console app. `Microsoft.Extensions.Resilience` still works, but it pulls the options, logging and telemetry stack in with it. Narrowing the reference to `Polly.Core` alone and constructing pipelines with `new ResiliencePipelineBuilder()` keeps the dependency graph small. Every API in this skill except `AddResiliencePipeline` and `ResiliencePipelineProvider<string>` is unchanged by that choice.

If the schedule cannot absorb a call-site rewrite right now, a community port (`EnterpriseLibrary.TransientFaultHandling.NetCore` and the `TransientFaultHandling.*` packages) reproduces the old API on .NET Standard 2.0 and unblocks the target-framework change without code changes. It is **not** Microsoft-supported and it is not a destination — treat it as a way to buy time, say so explicitly when recommending it, and leave the real migration scheduled.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="EnterpriseLibrary.TransientFaultHandling" Version="*" />
<!-- Any of these companions may also be present -->
<PackageReference Include="EnterpriseLibrary.TransientFaultHandling.Data" Version="*" />
<PackageReference Include="EnterpriseLibrary.TransientFaultHandling.Configuration" Version="*" />
<PackageReference Include="EnterpriseLibrary.TransientFaultHandling.Caching" Version="*" />
<PackageReference Include="EnterpriseLibrary.TransientFaultHandling.ServiceBus" Version="*" />
<PackageReference Include="EnterpriseLibrary.TransientFaultHandling.WindowsAzure.Storage" Version="*" />
```

The Service Bus companion also ships under a second id,
`Microsoft.Practices.EnterpriseLibrary.TransientFaultHandling.ServiceBus`; treat the two
as the same package.

`EnterpriseLibrary.TransientFaultHandling.Core` is **not** one of these. Despite the name
it is a community port, and its current version (3.1.0) already ships `lib/net8.0`. A
project referencing it is not blocked by this package and needs no migration to retarget —
the same goes for the `*.NetCore` ids. Leave them alone.

Non-SDK-style projects reference these as `<Reference>` elements with `Microsoft.Practices.EnterpriseLibrary.TransientFaultHandling*` assembly names and `HintPath` values under `packages\`. Remove the `packages.config` entries too.

### New References (Add)

Read `Microsoft.Extensions.Resilience` below as "or `Polly.Core` alone, if Choosing the Target picked the no-DI option".

| Companion package present | Add |
|---|---|
| base, `.Configuration` | `Microsoft.Extensions.Resilience` |
| `.Data` | `Microsoft.Extensions.Resilience` and `Microsoft.Data.SqlClient` |
| `.Caching` | `Microsoft.Extensions.Resilience` and a supported cache client (Azure Managed Cache is retired) |
| `.ServiceBus` | Nothing here — `migrating-azure-sdk-to-track2` picks the replacement; do **not** add a resilience pipeline, see Step 6 |
| `.WindowsAzure.Storage` | Nothing here — `migrating-azure-sdk-to-track2` picks the replacements by usage; do **not** add a resilience pipeline, see Step 6 |

Take the version `Microsoft.Extensions.Resilience` resolves to for the project's target framework rather than pinning one; only the 10.x line supports .NET Standard 2.0.

If the retries wrap `HttpClient` calls, prefer `Microsoft.Extensions.Http.Resilience` over hand-building a pipeline — it registers a standard pipeline on the `HttpClient` itself. Note that `Microsoft.Extensions.Http.Polly`, which older guidance recommends for this, is deprecated.

## Workflow

```
Migration Progress:
- [ ] Step 1: Inventory transient fault handling usage
- [ ] Step 2: Update package references
- [ ] Step 3: Translate retry strategies to RetryStrategyOptions
- [ ] Step 4: Translate detection strategies to ShouldHandle predicates
- [ ] Step 5: Replace ExecuteAction call sites
- [ ] Step 6: Replace the SQL, Storage, Service Bus and Caching companions
- [ ] Step 7: Migrate configuration-declared policies
- [ ] Step 8: Build and verify
```

### Step 1: Inventory Transient Fault Handling Usage

Search C# **and** Visual Basic sources for:

- `using Microsoft.Practices.EnterpriseLibrary.TransientFaultHandling` and the `.Data` / `.Configuration` sub-namespaces (`Imports` in Visual Basic)
- Types: `RetryPolicy`, `RetryPolicy<T>`, `RetryManager`, `RetryPolicyFactory`, `RetryStrategy`, `FixedInterval`, `Incremental`, `ExponentialBackoff`, `RetryingEventArgs`
- Custom types implementing `ITransientErrorDetectionStrategy`
- Built-in detection strategies: `SqlDatabaseTransientErrorDetectionStrategy`, `StorageTransientErrorDetectionStrategy`, `ServiceBusTransientErrorDetectionStrategy`, `CacheTransientErrorDetectionStrategy`
- Call sites: `ExecuteAction`, `ExecuteAsync`, and the `.Data` extensions `OpenWithRetry`, `ExecuteNonQueryWithRetry`, `ExecuteReaderWithRetry`, `ExecuteScalarWithRetry`, `ExecuteXmlReaderWithRetry`
- `ReliableSqlConnection` construction
- `<RetryPolicyConfiguration>` sections in `app.config` / `web.config`

Record, per retry policy, the retry count, the interval or backoff values, which exceptions it treats as transient, and whether `firstFastRetry` is set. Those four values are what Step 3 and Step 4 translate. A policy whose values you could not determine is not ready to migrate — do not guess a retry count.

### Step 2: Update Package References

Apply the table above, using the target chosen in Choosing the Target. For multi-targeted projects, condition the old reference to the old TFM and add the resilience reference for the new TFM only.

### Step 3: Translate Retry Strategies to `RetryStrategyOptions`

Both products count *retries*, not total attempts, so `retryCount` maps directly to `MaxRetryAttempts`.

| Enterprise Library | Polly v8 |
|---|---|
| `new FixedInterval(retryCount, retryInterval)` | `BackoffType = DelayBackoffType.Constant`, `MaxRetryAttempts = retryCount`, `Delay = retryInterval` |
| `new Incremental(retryCount, initialInterval, increment)` | `BackoffType = DelayBackoffType.Linear`, `MaxRetryAttempts = retryCount`, `Delay = initialInterval` — exact only when `increment` equals `initialInterval`; otherwise use `DelayGenerator` |
| `new ExponentialBackoff(retryCount, minBackoff, maxBackoff, deltaBackoff)` | `BackoffType = DelayBackoffType.Exponential`, `MaxRetryAttempts = retryCount`, `Delay = minBackoff`, `MaxDelay = maxBackoff`, `UseJitter = true` — **approximate**, see below |
| `RetryPolicy.NoRetry` | Do not build a pipeline; call the operation directly, or use `ResiliencePipeline.Empty` |
| `RetryPolicy.DefaultFixed` | `FixedInterval(10, 1s)` — `DelayBackoffType.Constant`, `MaxRetryAttempts = 10`, `Delay = TimeSpan.FromSeconds(1)`, plus the attempt-0 zero below |
| `RetryPolicy.DefaultProgressive` | `Incremental(10, 1s, 1s)` — `DelayBackoffType.Linear`, `MaxRetryAttempts = 10`, `Delay = TimeSpan.FromSeconds(1)`, plus the attempt-0 zero below |
| `RetryPolicy.DefaultExponential` | `ExponentialBackoff(10, 1s, 30s, 10s)` — use the exact `DelayGenerator` below with those values, plus the attempt-0 zero |
| `policy.Retrying += handler` | `OnRetry = args => { ... ; return default; }` |
| `RetryingEventArgs.CurrentRetryCount` | `OnRetryArguments.AttemptNumber` (zero-based — add 1 for parity with the old one-based count) |
| `RetryingEventArgs.Delay` | `OnRetryArguments.RetryDelay` |
| `RetryingEventArgs.LastException` | `OnRetryArguments.Outcome.Exception` |

`ExponentialBackoff` has no exact equivalent, and the row above does not preserve its schedule. Enterprise Library grows the delay as `minBackoff + (2^attempt - 1) * deltaBackoff`, randomised ±20% — so `deltaBackoff` is the growth step the policy was tuned with, and the randomisation is built in. Polly grows as `Delay * 2^attempt`, so mapping `Delay = minBackoff` reproduces the original only when `deltaBackoff` happens to be close to `minBackoff`; `UseJitter` stands in for the ±20% but is not the same distribution. Treat the row as a starting approximation, and when the exact schedule matters — a policy tuned against a throttling service, or one whose timings appear in an SLA — reproduce it in a `DelayGenerator`:

```csharp
DelayGenerator = args =>
{
    // ±20% applies to the delta alone. Random.Shared is thread-safe; a Random instance is not.
    var delta = (Math.Pow(2, args.AttemptNumber) - 1)
        * deltaBackoff.TotalMilliseconds
        * (0.8 + (Random.Shared.NextDouble() * 0.4));

    // minBackoff is a floor, and the cap is applied last.
    var ms = Math.Min(minBackoff.TotalMilliseconds + delta, maxBackoff.TotalMilliseconds);

    return new ValueTask<TimeSpan?>(TimeSpan.FromMilliseconds(ms));
}
```

The order matters. Randomising the capped total instead of the delta lets the delay
overshoot `maxBackoff` — with a 30s cap it would range from 24s to 36s — and lets the
jitter move `minBackoff`, which Enterprise Library treats as a fixed floor.
`args.AttemptNumber` is already the zero-based count the formula wants; do not add 1 here.

The lambda cannot be `static` — it closes over `minBackoff`, `deltaBackoff` and
`maxBackoff`. When a `DelayGenerator` returns a value, Polly uses it in place of the delay
it would have computed, so `UseJitter` and `MaxDelay` have no effect on that attempt —
which is why the generator has to apply the cap itself.

Record in the migration notes which of the two you used, because the approximation is invisible afterwards.

`firstFastRetry: true` — the Enterprise Library default, and therefore set on all three `RetryPolicy.Default*` policies — has **no** equivalent. Polly always waits `Delay` before the first retry. Preserve it explicitly when the old policy relied on it:

```csharp
DelayGenerator = static args => new ValueTask<TimeSpan?>(
    args.AttemptNumber == 0 ? TimeSpan.Zero : (TimeSpan?)null)
```

Returning `null` from `DelayGenerator` tells Polly to fall back to the configured `BackoffType` for that attempt, so only the first retry is made immediate.

`DelayGenerator` is a **single slot**. If the policy needs both an exact schedule and
`firstFastRetry`, do not assign it twice — the second assignment silently replaces the
first. Combine them in one generator, returning `TimeSpan.Zero` on attempt 0 and the
computed delay otherwise.

A custom `RetryStrategy` subclass that overrides `GetShouldRetry()` has no table entry. Reimplement its interval sequence in a `DelayGenerator` that switches on `args.AttemptNumber`.

### Step 4: Translate Detection Strategies to `ShouldHandle`

`ITransientErrorDetectionStrategy.IsTransient(Exception)` becomes the `ShouldHandle` predicate. The body of `IsTransient` ports across almost verbatim.

Never leave `ShouldHandle` unset. Enterprise Library made the detection strategy a mandatory type parameter, so every old policy has one; Polly defaults to handling **every** exception except `OperationCanceledException`. Omitting the predicate therefore widens the policy instead of preserving it, and retries failures that cannot succeed — see Troubleshooting.

Old:

```csharp
public class MyDetectionStrategy : ITransientErrorDetectionStrategy
{
    public bool IsTransient(Exception ex) =>
        ex is TimeoutException || (ex is WebException we && we.Status == WebExceptionStatus.Timeout);
}

var policy = new RetryPolicy<MyDetectionStrategy>(
    new ExponentialBackoff(5, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(2)));
```

New:

```csharp
var pipeline = new ResiliencePipelineBuilder()
    .AddRetry(new RetryStrategyOptions
    {
        ShouldHandle = static args => new ValueTask<bool>(args.Outcome.Exception switch
        {
            TimeoutException => true,
            WebException we => we.Status == WebExceptionStatus.Timeout,
            _ => false,
        }),
        MaxRetryAttempts = 5,
        BackoffType = DelayBackoffType.Exponential,
        Delay = TimeSpan.FromSeconds(1),
        MaxDelay = TimeSpan.FromSeconds(30),
        UseJitter = true,
    })
    .Build();
```

Keep the existing detection class if it is used in more than one place — delete only the interface implementation and call the plain method from the predicate. That preserves any unit tests covering it.

For the built-in strategies, do not hand-port the error-code lists:

| Built-in strategy | Replacement |
|---|---|
| `SqlDatabaseTransientErrorDetectionStrategy` | Either enable `Microsoft.Data.SqlClient`'s own retry logic (`SqlConfigurableRetryFactory.CreateExponentialRetryProvider`, assigned to `SqlConnection.RetryLogicProvider` / `SqlCommand.RetryLogicProvider`) **or** keep the call site inside a pipeline with a `SqlException` predicate — never both, see below |
| `StorageTransientErrorDetectionStrategy` | Remove — the modern Azure Storage SDK retries internally (see Step 6) |
| `ServiceBusTransientErrorDetectionStrategy` | Remove — `Azure.Messaging.ServiceBus` retries internally (see Step 6) |
| `CacheTransientErrorDetectionStrategy` | Azure Managed Cache is retired; write a predicate for whichever cache client replaces it |

`RetryLogicProvider` and a resilience pipeline are two retry layers, and setting both multiplies the attempts: the pipeline's `MaxRetryAttempts` times the provider's, with the effective delay the product of the two schedules. Pick one per call site. The provider is the better choice when the only transient errors are SQL ones, because it carries Microsoft's maintained error-number list and the skill never has to hand-port it. The pipeline is the better choice when the retried unit is wider than a single command — several statements, or a SQL call plus something else — because the provider only wraps one command.

If `SqlConfigurableRetryFactory` is unavailable in the referenced `Microsoft.Data.SqlClient` version, use the pipeline with a predicate handling `SqlException` filtered on the transient error numbers and `TimeoutException`. Read those numbers from the code being replaced rather than inventing a list.

### Step 5: Replace `ExecuteAction` Call Sites

Polly's execute methods pass a `CancellationToken` into the delegate and use `ValueTask`, not `Task`.

| Enterprise Library | Polly v8 |
|---|---|
| `policy.ExecuteAction(() => DoWork())` | `pipeline.Execute(() => DoWork())` |
| `policy.ExecuteAction(() => GetValue())` | `pipeline.Execute(() => GetValue())` |
| `await policy.ExecuteAsync(() => DoWorkAsync())` | `await pipeline.ExecuteAsync(async ct => await DoWorkAsync(ct), cancellationToken)` |
| `await policy.ExecuteAsync(() => GetValueAsync())` | `await pipeline.ExecuteAsync(async ct => await GetValueAsync(ct), cancellationToken)` |
| `policy.ExecuteAction(action, cancellationToken)` | `pipeline.Execute(_ => action(), cancellationToken)` |

Build each pipeline once and reuse it. `ResiliencePipeline` is thread-safe and immutable; constructing one per call per invocation allocates needlessly and defeats the built-in telemetry. Where the project has dependency injection, register pipelines there:

```csharp
services.AddResiliencePipeline("sql", builder =>
    builder.AddRetry(new RetryStrategyOptions { /* ... */ }));
```

and inject `ResiliencePipelineProvider<string>`, calling `provider.GetPipeline("sql")`. This replaces the `RetryManager.SetDefault(...)` and `RetryManager.Instance.GetRetryPolicy<T>("name")` singleton pattern, which has no counterpart in the new stack and must not be reproduced with a static field.

In a project with no DI container, build the pipeline once with `new ResiliencePipelineBuilder().AddRetry(...).Build()` and hold it in a `static readonly` field on the type that uses it. That is a single immutable pipeline, not the old mutable singleton registry, and it is the one acceptable static here.

Where the old code returned a value, prefer the typed builder so the result type flows: `new ResiliencePipelineBuilder<HttpResponseMessage>()`. The typed builder is also the only way to retry on a *result* rather than an exception — Enterprise Library could not do that at all, so it is never required for parity, only for improvement.

### Step 6: Replace the SQL, Storage, Service Bus and Caching Companions

**`.Data` (`ReliableSqlConnection` and friends).** There is no pipeline equivalent for the connection and command wrappers; they are replaced by ordinary `Microsoft.Data.SqlClient` objects executed through a pipeline.

| Enterprise Library | Replacement |
|---|---|
| `new ReliableSqlConnection(connectionString)` | `new SqlConnection(connectionString)` |
| `new ReliableSqlConnection(cs, connectionPolicy, commandPolicy)` | `new SqlConnection(cs)` plus the pipeline applied at the call site |
| `connection.OpenWithRetry(policy)` | `await pipeline.ExecuteAsync(async ct => await connection.OpenAsync(ct), cancellationToken)` |
| `command.ExecuteNonQueryWithRetry(policy)` | `await pipeline.ExecuteAsync(async ct => await command.ExecuteNonQueryAsync(ct), cancellationToken)` |
| `command.ExecuteScalarWithRetry(policy)` | `await pipeline.ExecuteAsync(async ct => await command.ExecuteScalarAsync(ct), cancellationToken)` |
| `command.ExecuteReaderWithRetry(policy)` | `await pipeline.ExecuteAsync(async ct => await command.ExecuteReaderAsync(ct), cancellationToken)` |
| `command.ExecuteXmlReaderWithRetry(policy)` | `await pipeline.ExecuteAsync(async ct => await command.ExecuteXmlReaderAsync(ct), cancellationToken)` |
| `ReliableSqlConnection.ConnectionString` / `Open()` / `Close()` | The same members on `SqlConnection` |
| `RetryManager.Instance.GetDefaultSqlConnectionRetryPolicy()` | A named pipeline resolved from `ResiliencePipelineProvider<string>` |

Two correctness rules here, both easy to miss:

- **Never retry a non-idempotent command.** `ReliableSqlConnection` retried indiscriminately and so does a naive pipeline. A retried `INSERT` that actually succeeded before the connection dropped duplicates the row. A transaction does **not** make this safe: if the commit succeeds on the server and the acknowledgement is lost in transit, the client sees a transient failure, retries, and writes the rows twice — the outcome is genuinely ambiguous from the client's side, and no retry policy can resolve it. Making a write retryable means making it idempotent: a deterministic key with `MERGE` or `IF NOT EXISTS`, a unique constraint the retry can collide with harmlessly, or a client-generated id the server deduplicates on. Flag any retried `INSERT` or `UPDATE` that has none of those for review instead of migrating it silently.
- **Do not retry inside an open `SqlTransaction`.** The transaction is dead once the connection faults, so a retry inside it operates on a broken handle. Put the pipeline *outside* the `using` that creates the connection and transaction, so the retry re-opens and re-begins. This is about where the pipeline goes, not about whether the write is safe to repeat — that is the rule above.

If `System.Data.SqlClient` is still in use, this migration pairs with `migrating-to-microsoft-data-sqlclient`; run that one first.

**`.WindowsAzure.Storage`** and **`.ServiceBus`.** Do not port these policies to a resilience pipeline. The modern SDKs retry internally, and layering a pipeline on top multiplies the attempt count.

Record the old retry count and backoff values, delete the detection strategy and the policy, then carry those values into the client's own options:

- `Azure.Storage.*` — `clientOptions.Retry` (`MaxRetries`, `Delay`, `MaxDelay`, `Mode`).
- `Azure.Messaging.ServiceBus` — `ServiceBusClientOptions.RetryOptions`.

Choosing which replacement packages the project needs and migrating the client code is **not** this skill's job — `migrating-azure-sdk-to-track2` owns that, and the Track 1 package these companions sit on (`WindowsAzure.Storage`, `WindowsAzure.ServiceBus`) is its subject. It splits by actual usage, including `Azure.Storage.Files.Shares` and `Azure.Data.Tables`, and it will not replace a package just because it is present. Hand off to it the way the SQL case hands off above, and leave the configured retry values as the input it needs.

**`.Caching`.** Azure Managed Cache, the service this companion targeted, is retired. Where it is still referenced, the cache itself must be replaced first — normally with a distributed cache behind `IDistributedCache` — and the retry concern re-expressed against the new client. Report this rather than guessing at a target cache.

### Step 7: Migrate Configuration-Declared Policies

The `.Configuration` companion read `<RetryPolicyConfiguration>` from `app.config` or `web.config` and handed policies out through `RetryPolicyFactory`. The new stack has no configuration-section reader.

1. Read every named policy out of the `<RetryPolicyConfiguration>` section, including `defaultRetryStrategy` and `defaultSqlConnectionRetryStrategy`.
2. Express each one as a named pipeline registered with `AddResiliencePipeline("<same name>", ...)`, keeping the names identical so call sites stay readable.
3. Replace `RetryPolicyFactory.GetRetryPolicy<T>("name")` with `ResiliencePipelineProvider<string>.GetPipeline("name")`, and the nameless `GetRetryPolicy<T>()` overload with the pipeline registered for `defaultRetryStrategy`.
4. Delete the `RetryManager.SetDefault(RetryPolicyFactory.CreateDefault())` bootstrap once the pipelines are registered. `CreateDefault()` returns a `RetryManager` built from the configuration section, not a policy — there is no pipeline name to map it to, and dependency injection now owns the lifetime the singleton used to.
5. Delete the `<RetryPolicyConfiguration>` section and its `<configSections>` declaration.
6. If the values must stay externally configurable, bind them from `appsettings.json` into an options class and read that inside the `AddResiliencePipeline` callback — do not reintroduce a config-section reader.

`RetryPolicyFactory` calls can appear in a project that references `.Configuration` only transitively, so search the whole solution rather than just the projects with a direct reference.

### Step 8: Build and Verify

1. Build the project: `dotnet build`
2. Confirm no `Microsoft.Practices.EnterpriseLibrary.TransientFaultHandling` references remain in source, project files, or `packages.config`
3. Confirm every migrated policy's retry count and backoff values match the inventory from Step 1
4. Run tests covering the retried operations, including the failure paths — a pipeline whose `ShouldHandle` predicate is missing or wrong retries exceptions the old policy never retried, and nothing about that is visible at compile time
5. Check that no operation is retried twice: once by a resilience pipeline and again by an SDK's built-in retry
6. If no resilience pipeline remains — every call site resolved to an SDK that already retries — remove the `Microsoft.Extensions.Resilience` reference the package mapping added. It is applied before Choosing the Target runs, so a project that only wrapped Storage or Service Bus calls ends up with a dependency nothing uses

## Decomposition Rules

When this work is broken into subtasks, keep the pin by restating `#skill:migrating-transient-fault-handling-to-polly` in the description of every subtask that touches retry code.

Split by concern, not by file:

- The target choice from Choosing the Target is made once for the project and restated in every subtask. Two subtasks that pick differently leave the project referencing two resilience stacks.
- One subtask per *policy*, carrying its retry strategy, its detection strategy, and all of its call sites together. Splitting a policy from its call sites leaves the project uncompilable between subtasks.
- Keep the `.Data` and `ReliableSqlConnection` work as its own subtask — it changes the data-access shape, not just the retry shape, and carries the idempotency review from Step 6.
- Keep the Storage and Service Bus companions as their own subtask. Their outcome is *deleting* a policy, not porting one, so grouping them with the pipeline work invites an unnecessary pipeline.
- Configuration-declared policies (Step 7) are a single subtask covering the whole solution, because one config section usually feeds several projects.

## Troubleshooting

### Everything compiles but the wrong things are retried

Omitting `ShouldHandle` does **not** disable retries — the documented default handles every exception except `OperationCanceledException`. Enterprise Library required an `ITransientErrorDetectionStrategy`, so the old policy only retried what that detector classified as transient. Dropping it during migration silently *broadens* the retry set to everything, including failures that will never succeed on a retry: `ArgumentException`, authentication failures, a malformed SQL statement. Each one now costs the full `MaxRetryAttempts` and backoff before surfacing, and on a non-idempotent command it compounds with the duplicate-write hazard in Step 6.

Port `ShouldHandle` explicitly for every migrated policy, even when the old detector looks permissive. Verify with a test that throws a *non*-transient exception and asserts it was attempted exactly once.

Polly's other defaults also differ from the old policy and apply whenever a property is left unset: `MaxRetryAttempts = 3`, `Delay = 2 seconds`, `BackoffType = Constant`, `UseJitter = false`, `MaxDelay = null`. Set each one from the inventory in Step 1 rather than relying on them.

### Retries take far longer than before

Three usual causes: `UseJitter` compounding with an already-long `Delay`; `MaxDelay` left unset so exponential growth is unbounded; or a Polly pipeline stacked on top of an SDK that already retries (Step 6), multiplying attempts.

### `ExecuteAsync` will not compile with an existing async method

Polly v8 passes a `CancellationToken` into the delegate and expects `ValueTask`. Wrap a `Task`-returning method as `async ct => await MyMethodAsync(ct)`. Do not call `.Result` or `.GetAwaiter().GetResult()` inside the delegate to force the shape.

### Duplicate rows after a transient SQL failure

A non-idempotent command was retried. See the idempotency rule in Step 6. The old block had this hazard too, but retry counts and timings change during migration, so latent duplicates can start appearing now.

### `RetryManager.Instance` throws after migration

`RetryManager` has no Polly counterpart and must not be emulated with a static holder. If a `RetryManager.SetDefault` call was removed but consumers remain, those consumers were missed in Step 5; resolve them through `ResiliencePipelineProvider<string>` instead.
