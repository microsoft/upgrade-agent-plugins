---
name: migrating-cosmosdb-bulk-executor
description: >
  Migrates from the deprecated
  Microsoft.Azure.CosmosDB.BulkExecutor library to the
  built-in bulk execution support in
  Microsoft.Azure.Cosmos SDK. Use ONLY when
  Microsoft.Azure.CosmosDB.BulkExecutor has been flagged
  as obsolete or deprecated and must be replaced — not for
  version-bump scenarios where
  Microsoft.Azure.CosmosDB.BulkExecutor is still
  supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Cosmos DB BulkExecutor Migration

## Overview

Migrate from the deprecated `Microsoft.Azure.CosmosDB.BulkExecutor` library to the native bulk execution support in `Microsoft.Azure.Cosmos` (V3 SDK). The modern SDK supports bulk operations directly through a client option — no separate library is needed. Individual operations are created as tasks and executed concurrently with `Task.WhenAll`.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="Microsoft.Azure.CosmosDB.BulkExecutor" Version="{any}" />

<!-- The BulkExecutor also pulled in the older V2 SDK; remove if no longer needed -->
<PackageReference Include="Microsoft.Azure.DocumentDB" Version="{any}" />
<PackageReference Include="Microsoft.Azure.DocumentDB.Core" Version="{any}" />
```

### New Reference (Add)

```xml
<PackageReference Include="Microsoft.Azure.Cosmos" Version="{latest-stable}" />
```

Use tools or [NuGet](https://www.nuget.org/packages/Microsoft.Azure.Cosmos) to find the latest stable version.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect BulkExecutor usage
- [ ] Step 2: Update package references
- [ ] Step 3: Replace client initialization
- [ ] Step 4: Convert bulk import operations
- [ ] Step 5: Convert bulk delete operations
- [ ] Step 6: Build and verify
```

### Step 1: Detect BulkExecutor Usage

Scan the project for:
- `using Microsoft.Azure.CosmosDB.BulkExecutor;` and sub-namespaces
- Types: `BulkExecutor`, `IBulkExecutor`, `BulkImportResponse`, `BulkDeleteResponse`
- Methods: `BulkImportAsync`, `BulkDeleteAsync`
- `DocumentClient` usage tied to bulk operations

### Step 2: Update Package References

Remove all `Microsoft.Azure.CosmosDB.BulkExecutor` and legacy `Microsoft.Azure.DocumentDB` references from the project file. Add `Microsoft.Azure.Cosmos` if not already present.

### Step 3: Replace Client Initialization

Enable bulk mode through `CosmosClientOptions`:

```csharp
// Old
var client = new DocumentClient(endpoint, authKey);
var executor = new BulkExecutor(client, collection);
await executor.InitializeAsync();

// New
var client = new CosmosClient(endpoint, authKey, new CosmosClientOptions
{
    AllowBulkExecution = true
});
var container = client.GetContainer(databaseName, containerName);
```

### Step 4: Convert Bulk Import Operations

Replace `BulkImportAsync` with individual `CreateItemAsync` tasks executed concurrently:

```csharp
// Old
BulkImportResponse response = await executor.BulkImportAsync(documents);
Console.WriteLine($"Imported: {response.NumberOfDocumentsImported}");

// New
var tasks = new List<Task<ItemResponse<dynamic>>>();
foreach (var doc in documents)
{
    tasks.Add(container.CreateItemAsync(doc, new PartitionKey(doc.partitionKey)));
}
var responses = await Task.WhenAll(tasks);
Console.WriteLine($"Imported: {responses.Length}");
```

Track failures by wrapping individual tasks with try/catch or by inspecting each `ItemResponse.StatusCode` after completion.

### Step 5: Convert Bulk Delete Operations

Replace `BulkDeleteAsync` with individual `DeleteItemAsync` tasks:

```csharp
// Old
BulkDeleteResponse response = await executor.BulkDeleteAsync(pkTuples);

// New
var tasks = new List<Task<ItemResponse<dynamic>>>();
foreach (var (id, pk) in itemsToDelete)
{
    tasks.Add(container.DeleteItemAsync<dynamic>(id, new PartitionKey(pk)));
}
await Task.WhenAll(tasks);
```

### Step 6: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Verify bulk throughput by running a test batch against a development Cosmos DB container
3. Check that `AllowBulkExecution = true` is set — without it, operations run sequentially and throughput drops significantly

## API Differences

| BulkExecutor (Old) | Cosmos V3 SDK (New) | Notes |
|---------------------|---------------------|-------|
| `BulkExecutor` class | `CosmosClientOptions.AllowBulkExecution = true` | No separate executor object needed |
| `IBulkExecutor` interface | Removed | Use `Container` methods directly |
| `BulkImportAsync(documents)` | `Task.WhenAll(CreateItemAsync(...))` | One task per document |
| `BulkDeleteAsync(pkTuples)` | `Task.WhenAll(DeleteItemAsync(...))` | One task per item |
| `BulkImportResponse` | Individual `ItemResponse<T>` results | Aggregate results manually |
| `BulkDeleteResponse` | Individual `ItemResponse<T>` results | Aggregate results manually |
| `BulkUpdateAsync` | `Task.WhenAll(ReplaceItemAsync(...))` | One task per item |
| `DocumentClient` | `CosmosClient` | V3 client with connection string or endpoint+key |

## Troubleshooting

### Low Throughput After Migration

Verify that `AllowBulkExecution = true` is set on `CosmosClientOptions`. Without this flag, operations are dispatched individually instead of being batched by the SDK's internal transport layer.

### 429 (Too Many Requests) Errors

The V3 SDK retries throttled requests automatically. If errors persist, increase the provisioned RU/s on the container or reduce batch concurrency by limiting the number of concurrent tasks.

### Partition Key Errors

The V3 SDK requires an explicit `PartitionKey` on each operation. Extract the partition key value from each document and pass it to `CreateItemAsync`, `DeleteItemAsync`, or `ReplaceItemAsync`.
