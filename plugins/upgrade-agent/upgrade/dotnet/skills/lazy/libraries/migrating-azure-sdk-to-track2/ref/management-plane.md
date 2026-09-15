# The management plane

Applies when the resolved replacement is `Azure.ResourceManager.*`. That is roughly two-thirds of the
deprecated catalog — around 259 `mgmt`-typed packages — so this is the common case, not the exotic
one.

Route here on the **resolved replacement**, not on the catalog's `Type` column.
`Microsoft.Hadoop.Client` is typed `client` and replaces with `Azure.ResourceManager.HDInsight`.

## Contents

- [Package mapping](#package-mapping)
- [Client construction](#client-construction)
- [The resource hierarchy](#the-resource-hierarchy)
- [Models become `*Data` types](#models-become-data-types)
- [Long-running operations](#long-running-operations)
- [Listing and paging](#listing-and-paging)
- [Error handling](#error-handling)
- [Fluent](#fluent)
- [When the provider package does not cover the resource](#when-the-provider-package-does-not-cover-the-resource)
- [Troubleshooting](#troubleshooting)

## Package mapping

The common case is `Microsoft.Azure.Management.<X>` → `Azure.ResourceManager.<X>`, and the `.Fluent`
variant maps to the same target — there is no Fluent flavor in Track 2.

**Do not rely on that pattern.** Provider renames, splits and core-package targets defeat prefix
substitution. Resolve every package through the catalog and verify its role; use the pattern only
for offline candidates. See [package-catalog.md](package-catalog.md) for concrete exceptions.

Two mappings leave this file's scope entirely despite being `mgmt`-typed:

- `Microsoft.Azure.Management.Graph.RBAC[.Fluent]` → `Microsoft.Graph`. A different service with a
  different permission model and no `ArmClient` involvement — a rewrite, not a port.
- `Microsoft.Azure.Management.{Media, MixedReality, AppPlatform, HybridData, ChangeAnalysis}` name
  `Azure.ResourceManager.*` replacements that are **themselves deprecated** because the service is
  retiring. Report these instead of migrating them.

`Azure.ResourceManager` and `Azure.Identity` are always required. Add provider packages only for
providers the code actually touches — `Microsoft.Azure.Management.Fluent` reached every provider
through one reference, so a naive port pulls in dozens of unnecessary packages.

## Client construction

One `ArmClient` replaces every per-provider client.

```csharp
// Old — one client per provider, each with a SubscriptionId property
ServiceClientCredentials credentials = await ApplicationTokenProvider.LoginSilentAsync(
    tenantId, clientId, clientSecret);
var computeClient = new ComputeManagementClient(credentials) { SubscriptionId = subscriptionId };
var networkClient = new NetworkManagementClient(credentials) { SubscriptionId = subscriptionId };

// New — carry the same principal across; do not substitute DefaultAzureCredential
var credential = new ClientSecretCredential(tenantId, clientId, clientSecret);
var armClient = new ArmClient(credential, subscriptionId);
```

```csharp
// Old — Fluent
var credentials = SdkContext.AzureCredentialsFactory.FromFile(authFilePath);
IAzure azure = Azure.Configure().Authenticate(credentials).WithDefaultSubscription();

// New — read the auth file's values and pass them explicitly, including the subscription
var armClient = new ArmClient(
    new ClientSecretCredential(tenantId, clientId, clientSecret),
    subscriptionId);
```

`ArmClient` is thread-safe and caches resource metadata, so create one per application and inject it
rather than constructing one per operation. The management plane accepts only `TokenCredential` — no
keys, no connection strings. The Fluent auth-file format has no Track 2 equivalent, and replacing it
with `DefaultAzureCredential` silently changes both the principal and the subscription; see
[authentication.md](authentication.md).

## The resource hierarchy

Most Track 2 resources have three companion types. Recognizing them makes the rest mechanical:

| Type | Role | Example |
|---|---|---|
| `<X>Resource` | A resource you can operate on. Has `.Id`, `.Data`, and its own operations. | `VirtualMachineResource` |
| `<X>Data` | The plain data model — the old Track 1 model class. Reached via `.Data`. | `VirtualMachineData` |
| `<X>Collection` | The set of that resource under a parent. Where you create, get, and list. | `VirtualMachineCollection` |

Navigate down from the client instead of passing name tuples to a flat operation group:

```csharp
// Old
VirtualMachine vm = await computeClient.VirtualMachines.GetAsync(rgName, vmName);

// New
SubscriptionResource subscription = await armClient.GetDefaultSubscriptionAsync();
ResourceGroupResource resourceGroup = await subscription.GetResourceGroups().GetAsync(rgName);
VirtualMachineResource vm = await resourceGroup.GetVirtualMachines().GetAsync(vmName);
```

When the resource ID is already known, skip the walk. This is the better shape for code that stores
IDs, and it avoids two network calls:

```csharp
ResourceIdentifier vmId = VirtualMachineResource.CreateResourceIdentifier(subscriptionId, rgName, vmName);
VirtualMachineResource vm = armClient.GetVirtualMachineResource(vmId);
vm = (await vm.GetAsync()).Value;
```

`armClient.GetXResource(id)` returns a lightweight handle **without calling Azure**. `GetAsync()`
returns a new, populated resource; it does not populate the original handle. Retain the returned
resource before reading `.Data`, or the original handle still throws `InvalidOperationException`.
Test `resource.HasData` when it is not obvious where the handle came from.

Track 1 listing method names varied by provider — Compute used `List(rg)` and `ListAll()`, while many
other providers used `ListByResourceGroup(rg)` and `List()`. The Track 2 shape is uniform, so map by
intent rather than by the old method name:

| Track 1 intent | Track 2 |
|---|---|
| Get one resource by name | `collection.Get(name)` or `armClient.GetXResource(id).Get()` |
| Create or update | `collection.CreateOrUpdate(WaitUntil.Completed, name, data)` |
| Delete | `resource.Delete(WaitUntil.Completed)` |
| Update in place | `resource.Update(WaitUntil.Completed, patch)` only after verifying merge/replacement semantics; see partial updates below. |
| List within a resource group | `resourceGroup.GetVirtualMachines()` |
| List across the subscription | `subscription.GetVirtualMachines()` |
| `client.SubscriptionId` | Passed to `ArmClient`, or read from `resource.Id.SubscriptionId` |
| String-concatenated resource IDs | `ResourceIdentifier` / `<X>Resource.CreateResourceIdentifier(...)` |
| `Region.USEast`, `"westus2"` | `AzureLocation.EastUS`, `AzureLocation.WestUS2` |

## Models become `*Data` types

Names mostly carry over, but required constructor arguments and read-only collections change how
they are initialized.

```csharp
// Old — location as a settable string, collections assigned wholesale
var vnet = new VirtualNetwork
{
    Location = "westus2",
    AddressSpace = new AddressSpace { AddressPrefixes = new List<string> { "10.0.0.0/16" } },
    Subnets = new List<Subnet> { new Subnet { Name = "default", AddressPrefix = "10.0.0.0/24" } }
};

// New — location is a strong type, collections are read-only and appended to
var vnetData = new VirtualNetworkData
{
    Location = AzureLocation.WestUS2,
    Subnets = { new SubnetData { Name = "default", AddressPrefix = "10.0.0.0/24" } }
};
vnetData.AddressPrefixes.Add("10.0.0.0/16");
```

Two patterns need explicit checking:

- **Read-only collections.** `Subnets`, `AddressPrefixes`, `Tags`, and similar have no setter. Code
  that assigned a whole list fails to compile, which is fine. Code that assigned `null` to mean
  "leave unset" needs review, because the Track 2 equivalent is "do not touch the collection".
- **Renamed and retyped properties.** Track 2 applies .NET naming rules and replaces loose strings
  with strong types: `HardwareProfile.VmSize` becomes `VirtualMachineSizeType`, `IpConfigurations`
  becomes `IPConfigurations`, `Location` becomes `AzureLocation`, and nested `SubResource { Id = ... }`
  references usually collapse to a direct `ResourceIdentifier` property such as `AvailabilitySetId`.

Use `get_type_info` on the new `*Data` type for the real member list rather than guessing the rename.

### Partial updates and collection replacement

`.Data` is a local snapshot; mutating it alone does not update Azure. Check the operation's contract
before choosing a patch or a full `CreateOrUpdate`. PATCH does not imply that entries in a supplied
dictionary are merged: a `VirtualMachinePatch` with only `env=prod` replaces the VM's existing tags.
For an additive tag change, preserve the other tags with the dedicated helper:

```csharp
VirtualMachineResource vm = await resourceGroup.GetVirtualMachines().GetAsync(vmName);

VirtualMachineResource updatedVm = (await vm.AddTagAsync("env", "prod")).Value;
```

Patch types are per-provider (`VirtualMachinePatch`, `StorageAccountPatch`, …). When using one,
distinguish omitted top-level properties from entries inside a supplied collection; preserve existing
entries when the intended operation is additive. `SetTagsAsync` replaces the tag set, so it is not
equivalent to `AddTagAsync`.

Some resources have no `Update` and require `CreateOrUpdate` with a complete `*Data`. A partial PUT
can clear omitted state. When the legacy code performed a partial update, use the supported patch
operation or retrieve and preserve the existing state required by the service's PUT contract.
Inspect the resource's actual methods before choosing. Type metadata establishes members, not
server-side merge behavior. Use the provider's version-matched service/SDK contract. If semantics
cannot be established, prefer a verified dedicated additive helper; otherwise read/preserve the
complete intended collection only with documented update semantics and concurrency protection
(for example a supported ETag condition). An unprotected read-modify-write can lose concurrent
changes. If no safe path is established, leave the mutation blocked and report the decision needed.

## Long-running operations

Track 1 exposed two methods per long operation: a blocking one that polled, and a `Begin*` one that
returned immediately. Track 2 has a single method whose first argument states the intent.

```csharp
// Old — blocking
VirtualMachine vm = await computeClient.VirtualMachines.CreateOrUpdateAsync(rgName, vmName, model);

// Old — start independent VMs and poll later
var lro = await computeClient.VirtualMachines.BeginCreateOrUpdateAsync(rgName, vmName, model);
var otherLro = await computeClient.VirtualMachines.BeginCreateOrUpdateAsync(rgName, otherVmName, otherModel);

// New — blocking
ArmOperation<VirtualMachineResource> operation =
    await vmCollection.CreateOrUpdateAsync(WaitUntil.Completed, vmName, vmData);
VirtualMachineResource vm = operation.Value;

// New — start both independent operations before waiting for either
ArmOperation<VirtualMachineResource> operation =
    await vmCollection.CreateOrUpdateAsync(WaitUntil.Started, vmName, vmData);
ArmOperation<VirtualMachineResource> otherOperation =
    await vmCollection.CreateOrUpdateAsync(WaitUntil.Started, otherVmName, otherVmData);
Response<VirtualMachineResource>[] completed =
    await Task.WhenAll(operation.WaitForCompletionAsync().AsTask(),
        otherOperation.WaitForCompletionAsync().AsTask());
```

`WaitUntil` has no default, so every create, update, and delete call site must be touched. Choose
`WaitUntil.Completed` where the old code awaited the blocking overload and `WaitUntil.Started` where
it used `Begin*`. **When you cannot tell which, choose `Completed`** — it is the behavior-preserving
branch, and the cost is latency rather than a broken sequence.

Reading `.Value` on a `WaitUntil.Started` operation before completion throws, so starting several
operations in parallel means collecting the operations first and awaiting them all afterwards.
Only overlap work that was independent in the original flow. If the legacy `Begin*` call never
polled, keep `Started` without adding a wait; report that completion remains unobserved.

## Listing and paging

`IPage<T>` and manual `ListNext(nextPageLink)` loops become `Pageable<T>` / `AsyncPageable<T>`, which
fetch pages transparently.

```csharp
// Old — names varied by provider; Compute used ListAll/ListAllNext
IPage<VirtualMachine> page = await computeClient.VirtualMachines.ListAllAsync();
do
{
    foreach (var vm in page) { Process(vm); }
    page = page.NextPageLink is null
        ? null
        : await computeClient.VirtualMachines.ListAllNextAsync(page.NextPageLink);
}
while (page is not null);

// New
await foreach (VirtualMachineResource vm in subscription.GetVirtualMachinesAsync())
{
    Process(vm);
}
```

Listing yields `<X>Resource` objects, not data models — read `.Data` for properties, and call
operations directly on the item without re-fetching. Use `.AsPages()` only when the continuation
token or page size genuinely matters.

`await foreach` requires C# 8, which many .NET Framework and non-SDK-style projects do not have.
Check `LangVersion` first; where raising it is out of scope, use the synchronous `Pageable<T>`
overload in a plain `foreach`.

To test existence, `collection.ExistsAsync(name)` replaces catching a 404, and
`collection.GetIfExistsAsync(name)` returns a `NullableResponse<T>` when both the check and the value
are needed.

## Error handling

```csharp
// Old
catch (CloudException ex) when (ex.Response.StatusCode == HttpStatusCode.NotFound)

// New
catch (RequestFailedException ex) when (ex.Status == 404)
```

`RequestFailedException` is the exception type for every `Azure.ResourceManager.*` call, which is
uniformly HTTP. It exposes
`Status` for the HTTP code and `ErrorCode` for the ARM error string (`ResourceNotFound`,
`ResourceGroupNotFound`, …), which is the more precise thing to branch on. `CloudException`,
`ErrorResponseException`, and `Microsoft.Rest.ValidationException` all disappear — argument validation
now throws standard `ArgumentException` types before any request is sent.

**A Track 1 call that threw on 404 makes any null check after it dead code.** Deleting that branch is
correct; deleting it silently is not. Say so in the report.

## Fluent

The Fluent builder has no Track 2 equivalent, and this is the hardest part of the management plane.
Each `.With*()` call becomes a property on the `*Data` object, and `.Create()` becomes
`CreateOrUpdate`.

```csharp
// Old
var vnet = azure.Networks.Define(vnetName)
    .WithRegion(Region.USEast)
    .WithExistingResourceGroup(rgName)
    .WithAddressSpace("10.0.0.0/16")
    .WithSubnet("default", "10.0.0.0/24")
    .Create();

// New
var vnetData = new VirtualNetworkData
{
    Location = AzureLocation.EastUS,
    AddressPrefixes = { "10.0.0.0/16" },
    Subnets = { new SubnetData { Name = "default", AddressPrefix = "10.0.0.0/24" } }
};
ResourceGroupResource resourceGroup = await subscription.GetResourceGroups().GetAsync(rgName);
ArmOperation<VirtualNetworkResource> operation = await resourceGroup.GetVirtualNetworks()
    .CreateOrUpdateAsync(WaitUntil.Completed, vnetName, vnetData);
VirtualNetworkResource vnet = operation.Value;
```

| Fluent | Track 2 |
|---|---|
| `.Define(name)` … `.Create()` | Build `<X>Data`, then `collection.CreateOrUpdate(WaitUntil.Completed, name, data)` |
| `.Update()` … `.Apply()` | Build the provider's `<X>Patch` and call `resource.Update(WaitUntil.Completed, patch)` |
| `.WithRegion(Region.X)` | `Location = AzureLocation.X` |
| `.WithExistingResourceGroup(rg)` | Reach the collection through that `ResourceGroupResource` |
| `.WithNewResourceGroup(name)` | Create the resource group first — see below |
| `azure.X.GetById(id)` | `armClient.GetXResource(new ResourceIdentifier(id)).Get().Value` |
| `azure.X.DeleteById(id)` | `armClient.GetXResource(new ResourceIdentifier(id)).Delete(WaitUntil.Completed)` |
| `azure.X.List()` | Provider subscription listing: `subscription.GetXs()`; use `GetXsAsync()` for async enumeration |
| `SdkContext.RandomResourceName(...)` | No equivalent — generate names in application code |

Provider subscription listings return pageable results directly. Use `GetAllAsync()` only on an
actual collection, such as `subscription.GetResourceGroups()`, after checking its surface.

### Unrolling the implicit dependency graph

**This is the failure mode that makes Fluent ports go wrong.** A Fluent chain builds a graph of
resources and creates them in an order Fluent worked out. Track 2 creates nothing implicitly, so the
graph has to be rewritten as explicit creates in dependency order, each passing its `.Id` to the next.

```csharp
// Old — one chain; the VM is not the only thing created
var vm = azure.VirtualMachines.Define(vmName)
    .WithRegion(Region.USEast)
    .WithNewResourceGroup(rgName)              // separate resource
    .WithNewPrimaryNetwork("10.0.0.0/28")      // separate resource, plus a subnet
    .WithPrimaryPrivateIPAddressDynamic()
    .WithNewPrimaryPublicIPAddress(dnsLabel)   // separate resource
    .WithPopularLinuxImage(...)                // a NIC is created too, though nothing names it
    .WithRootUsername(user).WithSsh(key)
    .Create();
```

**Do not enumerate this syntactically.** `.WithNew*()` is not a reliable marker in either direction:

- Some `.WithNew*()` calls contribute *inline* payload rather than a separate resource. A data disk
  added by size is part of the VM's own PUT body; a data disk added as an `ICreatable<IDisk>` is a
  separate resource with its own ID.
- Some resources are created with no `.WithNew*()` spelling at all. The primary NIC above is the
  common example, and a network defined by address space brings a subnet with it.
- An `ICreatable<T>` can be built in a local variable or a helper and passed in, so it never appears
  in the chain you are reading.

Work the graph instead:

1. **Resolve what the chain actually creates.** Follow every `ICreatable<T>` it references, including
   ones built outside the chain, and add the resources the Fluent API creates implicitly for the
   resource type being defined. `.WithExisting*()` calls are lookups, not creates — resolve those to
   an existing resource or ID.
2. **Separate inline payload from separate resources.** Inline settings become properties on the one
   `*Data` object. Separate resources become their own `CreateOrUpdate` call.
3. **Order by dependency** and create each one, capturing its `.Id` and setting that
   `ResourceIdentifier` on the next `*Data`. Fluent passed these references for you.
4. **Use `WaitUntil.Completed` for every dependency.** A dependency created with `WaitUntil.Started`
   may not exist when the dependent create references its ID.
5. **Reproduce generated names.** `SdkContext.RandomResourceName` and Fluent's implicit naming have no
   Track 2 equivalent, so any resource Fluent named for you now needs a name chosen in application
   code — and that name is visible in Azure.
6. **Check lifecycle and sharing.** Fluent's `.WithNewResourceGroup` created a group whose lifetime
   the calling code may have assumed. Deleting a resource in Track 2 does not delete anything it
   implicitly created, and a resource that was shared between two chains must not be created twice.
7. **Do not convert a create into a lookup.** `.WithNew*()` must become a `CreateOrUpdate`, not a
   `Get` against a resource assumed to already exist, and `.WithExisting*()` must not become a create.
   Both compile; the first fails only on a clean subscription, and the second overwrites or duplicates
   infrastructure someone else owns.
8. **Preserve deferred creation.** A chain that captured `ICreatable`-style handles and created them
   later, or in a batch, is expressing ordering the application depends on. Do not collapse it into
   eager creates at the original call sites just because Track 2 has no builder.

**If the graph cannot be reconstructed with confidence — a helper builds the `ICreatable` set
elsewhere, or the implicit resources for the type are not documented — stop and report it unchecked
rather than porting a partial chain.** A missing implicit resource surfaces as a create failing on a
reference that does not exist, which points nowhere near the cause.

Because a chain's resource count is not obvious from reading it, **enumerate the created resources
before rewriting and diff the list afterwards.** This is shape 3 in
[behavior-audit.md](behavior-audit.md), applied to infrastructure rather than to a wrapper class.

## When the provider package does not cover the resource

`Azure.ResourceManager.<X>` packages lag their Track 1 counterparts, most often for newer or
preview-only service features. A Track 1 package can expose a resource that the stable Track 2
provider has no typed surface for at all, and the gap is invisible until you look: the package
restores, the client exists, and only the specific collection is missing.

Confirm before concluding it. Call `get_type_info` on the provider's resource type and look for the
collection accessor, or search the package's XML documentation for the resource name. Absence there
is the answer — not a prerelease package.

When the typed surface genuinely does not exist, use the generic resource escape hatch in
`Azure.ResourceManager` rather than taking a prerelease dependency:

```csharp
// Pin the API version for each resource type the typed package does not model.
var options = new ArmClientOptions();
options.SetApiVersion(new ResourceType("Microsoft.Contoso/widgets/gadgets"), "2026-01-01-preview");

var armClient = new ArmClient(credential, subscriptionId, options);
var gadgetId = widgetId.AppendChildResource("gadgets", gadgetName);

var data = new GenericResourceData(location)
{
    Properties = BinaryData.FromObjectAsJson(new Dictionary<string, object> { ["target"] = target })
};
GenericResource gadget = (await armClient.GetGenericResources()
    .CreateOrUpdateAsync(WaitUntil.Completed, gadgetId, data)).Value;
```

Three obligations come with this, and skipping them turns the escape hatch into a defect:

- **Derive the request body from the Track 1 generated model, not from memory.** Those property names
  are the wire contract. Read them off the model type you are replacing before hand-rolling the JSON,
  and preserve every field the old code set.
- **Pin the API version explicitly** with `SetApiVersion` for each affected resource type. Without it
  the generic client picks a default that may not include the feature.
- **Comment the pinned version and report it.** A hardcoded preview API version in source is a
  maintenance liability with no compiler reminder. Say which resources use the escape hatch and what
  would let them move back to typed models.

Prefer this to a prerelease package. A `-beta` or `-preview` provider package is a dependency decision
for the user, not a default: surface it with its tradeoff, and check `get_supported_package_version`
for the newest **stable** version first.

## Troubleshooting

**`InvalidOperationException` reading `resource.Data`.** The resource came from
`armClient.GetXResource(id)`, which does not call Azure. Assign the resource returned by `GetAsync()`
before reading `.Data`; merely awaiting and discarding the result leaves the original handle unfetched.

**Property not found after renaming the type.** Track 2 renamed members to match .NET conventions and
flattened many `SubResource` wrappers into `ResourceIdentifier` properties. Call `get_type_info` on
the `*Data` type for the real member list.

**Compile error assigning to a collection property.** Collections on `*Data` types are read-only. Use
an object initializer block or `.Add(...)`.

**`RequestFailedException` with status 403 after migrating.** The credential changed identity. The old
code often used a service principal from a config file while `DefaultAzureCredential` picks up a
developer or managed identity instead.

**Provider package cannot be found.** Not every Track 1 provider has a Track 2 package — some services
retired. Confirm against the catalog before assuming the name is wrong.

**Operations complete far faster than before, then downstream code fails.** A `WaitUntil.Started` was
used where the old code blocked.

**A create fails referencing a resource that does not exist.** A Fluent `.WithNew*()` was not unrolled
into an explicit create.

**An update cleared fields nobody touched.** Check for a partial PUT or a PATCH that replaced a
supplied collection. For additive tags, use `AddTagAsync` rather than sending a one-entry tag set.
