# Behavior audit

Type renames are the easy half of an Azure SDK migration: the compiler finds anything you get wrong.
This file covers the other half — the changes that leave a green build, passing tests, and a report
claiming success, while behavior differs in production.

It applies to **both planes**. These failure shapes recur across libraries, including those with
different SDK designs; verify the selected package rather than assuming universal APIs.

Read the gate and the two rules **before writing code**. Work the four shapes before declaring the
migration done.

## Contents

- [Gate: do the Track 2 patterns even apply?](#gate-do-the-track-2-patterns-even-apply)
- [Two rules that decide most calls](#two-rules-that-decide-most-calls)
- [How to establish a fact](#how-to-establish-a-fact)
- [The four defect shapes](#the-four-defect-shapes)
- [Service Bus body interoperability](#service-bus-body-interoperability)
- [Further measured instances](#further-measured-instances)
- [Auditing a family you know nothing about](#auditing-a-family-you-know-nothing-about)
- [Reporting](#reporting)

## Gate: do the Track 2 patterns even apply?

Check this **before** applying `Response<T>`, `Pageable<T>`, `WaitUntil`, `<X>ClientOptions`, or
`RequestFailedException` to anything. Not every package under a Microsoft or Azure prefix is an
`Azure.Core` client. Device, relay, and protocol SDKs wrap MQTT, AMQP, or WCF directly and follow
none of these conventions; forcing the generic shapes onto them produces code that cannot work.

The dependency is a reliable **negative** test — read the replacement package's nuspec, or run
`dotnet list package --include-transitive`:

- **No `Azure.Core` dependency** → the generic patterns do not apply. Migrate from the package's own
  README and samples instead. Verified examples: `Microsoft.Azure.Devices.Client` (IoT device SDK)
  and `Microsoft.Azure.Relay`.
- **An `Azure.Core` dependency is not proof that they do apply.** `Microsoft.Azure.Cosmos` depends on
  `Azure.Core` yet throws `CosmosException` rather than `RequestFailedException` and serializes with
  Newtonsoft. The positive test is the client's own surface: call `get_type_info` on the replacement
  client and confirm its operations return `Response<T>` or `Pageable<T>` before assuming the shared
  patterns hold.

Also confirm the replacement is the **same live service**, not merely the name the catalog gave you.
A `Replace` value can point at a redesigned service with different concepts, or at something already
retired. If the target's core resource concepts do not correspond to the legacy ones, this is a
rewrite for the user to scope, not a migration to perform.

## Two rules that decide most calls

**When a precondition cannot be verified, take the behavior-preserving branch.** Much of the guidance
here is conditional — "unless the queue is drained", "if the network is constrained", "when the
legacy code relied on the old default". You usually cannot observe these: not in-flight messages, not
other repositories, not Functions in another subscription, not the deployment network. Treat every
such condition as **false unless the user confirms it**, and take the branch that keeps the legacy
behavior. Never infer "safe to change" from the absence of evidence in this solution's source; a
producer or consumer outside the repository is the normal case.

**Never report an unverified default as preserved.** Preserving a default requires knowing *both*
values. If you could not establish the legacy value and the new value, do not guess which option
preserves behavior — leave the call site unchanged with a `TODO` and report the item as unchecked.
"Behavior preserved" written against an unchecked default is worse than reporting the gap.

## How to establish a fact

Do not resolve a behavioral question from memory, from the migration guide's prose, or from the
target repository's own README — all three are wrong often enough to matter, and a wrong default
written into a plan gets faithfully implemented.

| To find | Use | Not |
|---|---|---|
| Shared design conventions and their meaning | The [.NET design guidelines](https://azure.github.io/azure-sdk/dotnet_introduction.html), via `ref/track2-contract.md` | treating generic rules as proof of an installed API |
| Call sites of a legacy type | Repository text search, or an IDE reference search | `get_type_info`, which returns type metadata and never references |
| Members of a type, its defining package, documented replacements | `get_type_info`, `get_namespace_info`, `get_member_info` | recall |
| What a member *means* — the unit a timeout applies to, whether a flag is on | The package's XML documentation in the NuGet cache | the member name, frequently a near-synonym of a different concept |
| The **runtime default value** of an option | A throwaway console project that instantiates the options type and prints the property | `get_type_info`, which lists members but does not evaluate defaults |

The probe is the tiebreaker and takes about a minute:

```csharp
// Reference both generations, print the two values side by side.
Console.WriteLine(new QueueClientOptions().MessageEncoding);              // None
Console.WriteLine(new ServiceBusProcessorOptions().AutoCompleteMessages); // True
```

## The four defect shapes

### 1. External contract

Anything outside this codebase that reads or writes the same bytes: message and blob bodies,
serialization format, encoding, persisted processor state and checkpoints, event schema, and the wire
protocol itself. If the new library writes or reads differently, the migration compiles and then
fails on data that already exists — often destructively, because a handler that dead-letters on a
deserialization failure drains the backlog to the dead-letter queue.

*Ask:* what wrote the data this code reads, and what reads the data it writes? Assume an external
producer or consumer exists unless the user confirms otherwise. Are serializer choice, attributes,
date and time kinds, enum handling, and property naming all preserved?

*The contract is not only data at rest.* Log lines, console output, and exception messages the
application emits are consumed by log queries, alert rules, dashboards, and scripts that parse
stdout. Track 2 changes the text a caught exception produces, and a rewritten wrapper often rewords
its own messages in passing. Keep application-emitted text unchanged unless the change is the point,
and treat a reworded log line as a **changed deliberately** row rather than incidental cleanup.

*Canonical instance:* Track 1 `CloudQueue.EncodeMessage` defaulted to `true` while Track 2
`QueueClientOptions.MessageEncoding` defaults to `None`, so a bare port silently **stops**
Base64-encoding and breaks interop in both directions.

### 2. Operation contract

The same call, with different behavior. The largest shape. It covers option defaults that no longer
match what the legacy code set explicitly; a knob whose *scope* changed, such as a whole-operation
timeout replaced by a per-attempt one; callback or result **cardinality**, where a batch handler
became a per-item handler, a listing that returned values now returns only properties, or a call
returns a handle rather than the object; conditional and concurrency semantics such as ETags, locks,
pop receipts, and `ifMatch`; replace-versus-patch on updates, where omitting a field now clears it;
absence behavior, where a miss that returned null now throws; deadline exception behavior, where
timeout recovery must survive without absorbing caller cancellation; and long-running-operation
completion, where a call that used to block now returns immediately.

*Ask:* for every options object the legacy code populated, does each property it set have a
corresponding line in the new one? For every knob, what unit does it apply to? For every handler, was
it doing per-batch work? For every update, does it replace or merge? For every "not found", what
happens now?

*Watch for comparisons that were already broken.* Track 1 model types are generated DTOs that
generally do **not** implement value equality, so legacy `Contains`, `Equals`, `Distinct`, or
`Remove` calls against a freshly constructed model silently matched nothing. Track 2 models sometimes
*do* implement `IEquatable<T>`. Either way the call needs a decision: porting it faithfully preserves
a latent bug, and porting it onto a value-equal model changes behavior. Replace it with an explicit
field comparison and report it as a fix rather than burying it.

*Watch for workarounds the new library made redundant.* Track 1 code accumulated compensating
logic — a retry wrapper, a hand-rolled paging loop, a manual provider registration, a polling loop
around an operation, a custom backoff. Where `Azure.Core` now does that by default, porting the
workaround faithfully **doubles it up**: retries multiply, polling races the SDK's own poller. Before
porting compensating logic, check whether the behavior is now built in, and report removing it rather
than deleting it silently.

The manual-settlement example in `SKILL.md` owns the Service Bus rule; do not infer that automatic
completion overrides an explicit abandon or dead-letter.

### 3. Boundary and topology

The shape of the code's own surface, and of the client graph beneath it. Covers public members
dropped from a wrapper, where an alternate credential path is the usual casualty; type names that
survived with a different meaning or an inverted role; a monolithic package that split into several,
or several that merged; the resource a client is *bound* to — vault, index, namespace, container,
endpoint, subscription — which frequently moves from a per-call argument to a constructor argument;
and parent-child hierarchy, where Track 2 does not implicitly create parents that Track 1 created for
you.

*Ask:* list the public members of every wrapper class before the rewrite and diff after — a member
with no in-repo caller vanishes silently and the build stays green. For every type whose simple name
is unchanged, confirm namespace and role. For every client, what is it bound to, and does that match
what the old call passed per invocation?

*Report the member list, not a verdict.* "No entry point was dropped" is the easiest claim in this
audit to get wrong, because consolidating three factory methods into one context object feels like
nothing was lost. Put the before and after member names in the report and let the reader judge. If a
member is gone because its capability moved, say where it moved to.

*Canonical instance:* `SearchIndexClient` exists in both generations with opposite roles. In Track 1
(`Microsoft.Azure.Search`) it is a **data-plane** client bound to one index, exposing `.Documents`.
In Track 2 (`Azure.Search.Documents.Indexes`) it is an **index-management** client within the Search
service, not the ARM control plane (`Azure.ResourceManager.Search`). A mechanical rename keeps the
type name but retargets document operations at index management. Document operations use
`SearchClient`, reached through `SearchIndexClient.GetSearchClient(name)`.

### 4. Operational

Everything that only appears once deployed. Covers identity and authorization, where a changed
credential resolves to a different principal and control-plane roles do not grant data-plane access;
transport, where a client changes how it reaches the service and needs ports a locked-down network
does not allow; client lifetime, where a client meant to be a long-lived singleton is constructed per
request, an async-disposable one is never disposed, or a processor is never started or stopped;
concurrency and throughput defaults; a pinned service API version that hides newer features; and
service retirement or redesign, where the correct answer is to stop and report rather than migrate.

*Ask:* does the new client reach the service the same way? Are its lifetime and disposal handled?
Does the migrated identity hold the same role assignments? Is the target actually the same service?

*Canonical instance:* Cosmos changed its default connection mode from `Gateway` to `Direct`, which
opens TCP connections straight to backend replicas over a wide outbound port range. It works on a
developer machine and times out behind a restrictive firewall, App Service, or proxy.

## Service Bus body interoperability

Establish the producer overload, serializer, model/known types and existing content-type/version
markers. `BrokeredMessage(object)` normally produces binary DCS XML; a stream overload may contain
raw JSON or another format, and a custom `XmlObjectSerializer` needs its own reader. The
[official interop sample](https://github.com/Azure/azure-sdk-for-net/blob/Azure.Messaging.ServiceBus_7.20.1/sdk/servicebus/Azure.Messaging.ServiceBus/samples/Sample08_Interop.md)
shows binary XML around a JSON string, not every possible legacy message.

Preserve the existing wire format in both directions, including external consumers. Do not introduce
JSON or dual-read merely because the SDK changed. If an approved transition requires both formats:

1. Prefer an established version/content-type discriminator. For unmarked data known to be only
   binary DCS or JSON, try the legacy binary reader first, then JSON on a fresh/reset stream only
   after a format-recognition failure. Validate the expected root/type; do not accept a partial parse.
2. Do not retry another parser after a size/quota breach, cancellation, I/O or application failure.
   Catch only the expected parser failures; preserve the existing reject/dead-letter policy and
   report unsupported formats rather than silently dropping or acknowledging them.
3. Use `XmlDictionaryReader.CreateBinaryReader`, not `XmlReader.Create`. Match the original DCS
   type/known types. For the official sample that type is `string`, followed by JSON deserialization.
4. Bound encoded body bytes **before** parsing, reader quotas and DCS graph size separately. Derive
   production limits from the accepted payload contract and representative largest/deepest messages.
   If limits or the format cannot be established, ask/report before deploying the change.

Example bounded profile for a **small-message fixture**, not Azure defaults or universal production
limits: 256 KiB encoded body, depth 32, 64 Ki characters per string, 64 Ki array elements, 4 KiB per
reader read, 16 Ki name-table characters, and 65,536 graph items. Validate every boundary against
the application's legitimate payloads before adopting it; do not copy `.Max` from the interop sample
or invent production caps that reject valid messages.

```csharp
const int maxBodyBytes = 256 * 1024;
if (received.Body.ToMemory().Length > maxBodyBytes)
{
    throw new SerializationException("Message body exceeds the configured limit.");
}
var quotas = new XmlDictionaryReaderQuotas
{
    MaxDepth = 32,
    MaxStringContentLength = 64 * 1024,
    MaxArrayLength = 64 * 1024,
    MaxBytesPerRead = 4096,
    MaxNameTableCharCount = 16 * 1024
};
var serializer = new DataContractSerializer(typeof(string), new DataContractSerializerSettings
{
    MaxItemsInObjectGraph = 65_536
});
using Stream body = received.Body.ToStream();
using XmlDictionaryReader reader = XmlDictionaryReader.CreateBinaryReader(body, quotas);
string json = (string)serializer.ReadObject(reader);
```

This is only the bounded legacy-reader branch; it is not a dual-reader implementation or permission
to swallow its exception. Quota breaches can share exception types with malformed input, so do not
implement fallback with a broad `catch (SerializationException)`; use a discriminator or a
verified distinction, and report ambiguity. Validate DCS, raw stream/custom formats, and any approved
JSON transition; include maximum-size and over-limit cases before claiming wire compatibility.

## Further measured instances

Worked examples, not a checklist. `SKILL.md` carries the ones whose *direction* is load-bearing;
these are the rest.

- **Key Vault delete is a long-running operation** followed by `PurgeDeletedSecret` under soft
  delete, so delete-then-recreate needs an awaited purge or conflict handling (shape 2, LRO
  completion). Both legacy `GetSecrets` and Track 2 `GetPropertiesOfSecrets` return **metadata only**.
  Preserve per-secret GETs only when values are actually required; do not add them to a metadata-only
  inventory. They require `secrets/get` in addition to `secrets/list` (shape 2, result completeness).
- **`Azure.Messaging.CloudEvent` ships in `Azure.Core`**, not the Event Grid package (shape 3,
  package boundary). The event schema is fixed when the topic is provisioned, and the wrong one is
  rejected at publish time rather than compile time (shape 1).
- **`UpdateMessageAsync` returns a new pop receipt** and leaves the caller's copy stale; discarding it
  makes the later delete fail with 404 (shape 2, concurrency token).
- **`Microsoft.Azure.Cosmos` v3 refuses to build without an explicit `Newtonsoft.Json` reference**
  and serializes with Newtonsoft by default while the rest of Track 2 uses `System.Text.Json`
  (shape 1, serialization).

## Auditing a family you know nothing about

Most deprecated Azure packages have no worked example anywhere in this skill, and that is by design —
there are several hundred of them and any enumeration would be both incomplete and stale. The four
shapes apply regardless. For an unfamiliar family:

1. Clear the [gate](#gate-do-the-track-2-patterns-even-apply): an `Azure.Core` client, and the same
   live service.
2. Fetch the `ReplaceGuide` URL from the catalog and read its behavior-change section. Confirm the
   guide is for .NET. Use it for mappings, the design guidelines for conventions, and the selected
   package/service documentation for actual semantics. Verify claims against that version; do not
   force a generic shape over a valid library-specific API.
3. Diff the legacy options object against the new `<X>ClientOptions` property by property, reading
   XML docs for any knob whose scope is unclear (shape 2).
4. Compare handler, callback, and listing signatures across generations for a cardinality change
   (shape 2).
5. Ask what wrote any data the code reads, and what reads what it writes (shape 1).
6. For every type whose simple name is unchanged, confirm namespace and role; for every client,
   confirm which resource it is bound to (shape 3).
7. List the public members of every wrapper class before rewriting it, and diff after (shape 3).
8. Check credential, transport, lifetime, and disposal against the legacy code (shape 4).

Steps 3 through 8 need no per-service knowledge and take minutes. They are where the defects that
survive a clean build actually live.

On the management plane, distinguish omitted top-level properties from a supplied collection.
A PATCH can replace that collection: sending one VM tag does not preserve the other tags.
A partial `CreateOrUpdate` PUT can also clear omitted state. An LRO that Track 1 blocked on
returns immediately at `WaitUntil.Started`. See
[management-plane.md](management-plane.md).

## Reporting

Report to the user, and to `tasks.md` when a scenario is active, using one row per finding:

| Package or type | Shape | Outcome | Evidence, or "unchecked" | Action taken, or decision needed |
|---|---|---|---|---|

**Every shape gets a row, including the ones that came back clean.** The enumeration is the point: a
shape with no row is indistinguishable from a shape nobody looked at. Produce this table whether the
migration ran as one task or as several — it is an output of the migration, not of a particular
decomposition. Research notes in a planning file do not substitute for it, because the reader of the
summary never sees them.

**`Outcome` is one of three values, and collapsing the middle one is the failure this section exists
to prevent:**

- **Preserved** — the legacy behavior still holds. Point at the line that preserves it.
- **Changed deliberately** — the new behavior differs and that was a considered choice. State the old
  behavior, the new one, **and the cost**. "Checkpointing moved from once per batch to once per event,
  up to a 10x increase in checkpoint-store writes" is a changed-deliberately row. Writing that as
  "checkpointing preserved" is wrong even though the intent was sound and the semantics survived:
  frequency, cost, and volume are behavior too, and the reader cannot see the tradeoff you weighed.
- **Unchecked** — could not be exercised, typically because credentials or an emulator were
  unavailable. A deferred check reported as deferred is fine. A deferred check reported as preserved
  is not.

Also name any public member removed, and say where its capability went.

**Say when removed code was unreachable.** A migration frequently exposes a branch that could never
run — a null check against a Track 1 call that threw on failure rather than returning null, a retry
around an operation that already retried, a comparison that never matched. Deleting it is correct.
Deleting it silently is not: a reviewer reads the diff, sees a guard or a diagnostic disappear, and
has to reconstruct the old library's behavior to find out whether something was lost. Name the branch
and say why it was dead.
