---
name: migrating-documentdb-to-cosmos
description: >
  Migrates from the deprecated Microsoft.Azure.DocumentDB SDK (V2)
  to the modern Microsoft.Azure.Cosmos SDK (V3) for Azure Cosmos DB.
  Use ONLY when Microsoft.Azure.DocumentDB has been flagged as
  deprecated or obsolete and must be replaced — not for version-bump
  scenarios where the V2 SDK is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# DocumentDB to Cosmos SDK Migration

## Overview

Migrate from the legacy `Microsoft.Azure.DocumentDB` (V2) SDK to the modern `Microsoft.Azure.Cosmos` (V3) SDK. The V3 SDK introduces a new object model (`CosmosClient` → `Database` → `Container`) and requires explicit partition keys on most operations. All data-plane calls are async-first, and the `Document` base class is replaced by generic types or `dynamic`.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="Microsoft.Azure.DocumentDB" Version="{any}" />
<!-- Or the .NET Core variant -->
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
- [ ] Step 1: Detect DocumentDB SDK usage
- [ ] Step 2: Update package references
- [ ] Step 3: Replace client and resource model
- [ ] Step 4: Convert CRUD operations
- [ ] Step 5: Update queries
- [ ] Step 6: Migrate error handling
- [ ] Step 7: Build and verify
```

### Step 1: Detect DocumentDB SDK Usage

Scan the project for:
- `using Microsoft.Azure.Documents;` and `using Microsoft.Azure.Documents.Client;`
- Types: `DocumentClient`, `Document`, `DocumentCollection`, `ResourceResponse`
- Methods: `CreateDocumentAsync`, `ReadDocumentAsync`, `ReplaceDocumentAsync`, `DeleteDocumentAsync`
- `RequestOptions` and `FeedOptions` usage

### Step 2: Update Package References

Remove `Microsoft.Azure.DocumentDB` or `Microsoft.Azure.DocumentDB.Core` from the project file. Add `Microsoft.Azure.Cosmos`.

### Step 3: Replace Client and Resource Model

```csharp
// Old
var client = new DocumentClient(new Uri(endpoint), authKey);

// New
var client = new CosmosClient(endpoint, authKey);
var database = client.GetDatabase(databaseName);
var container = database.GetContainer(containerName);
```

The V3 SDK uses a hierarchy: `CosmosClient` → `Database` → `Container`. There is no need to construct URI links manually — use the fluent getter methods instead.

### Step 4: Convert CRUD Operations

```csharp
// Old — Create
ResourceResponse<Document> response = await client.CreateDocumentAsync(
    collectionUri, document, new RequestOptions { PartitionKey = new PartitionKey(pk) });

// New — Create
ItemResponse<MyItem> response = await container.CreateItemAsync(
    item, new PartitionKey(pk), new ItemRequestOptions());

// Old — Read
Document doc = await client.ReadDocumentAsync<Document>(
    documentUri, new RequestOptions { PartitionKey = new PartitionKey(pk) });

// New — Read
ItemResponse<MyItem> response = await container.ReadItemAsync<MyItem>(
    id, new PartitionKey(pk));

// Old — Delete
await client.DeleteDocumentAsync(documentUri,
    new RequestOptions { PartitionKey = new PartitionKey(pk) });

// New — Delete
await container.DeleteItemAsync<MyItem>(id, new PartitionKey(pk));
```

### Step 5: Update Queries

```csharp
// Old
var query = client.CreateDocumentQuery<MyItem>(collectionUri,
    new SqlQuerySpec("SELECT * FROM c WHERE c.status = @status",
        new SqlParameterCollection { new SqlParameter("@status", "active") }),
    new FeedOptions { EnableCrossPartitionQuery = true });

// New
var query = container.GetItemQueryIterator<MyItem>(
    new QueryDefinition("SELECT * FROM c WHERE c.status = @status")
        .WithParameter("@status", "active"));

var results = new List<MyItem>();
while (query.HasMoreResults)
{
    FeedResponse<MyItem> page = await query.ReadNextAsync();
    results.AddRange(page);
}
```

Cross-partition queries are enabled by default in V3 — remove `EnableCrossPartitionQuery` settings.

### Step 6: Migrate Error Handling

```csharp
// Old
try { /* operation */ }
catch (DocumentClientException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
{ /* handle */ }

// New
try { /* operation */ }
catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
{ /* handle */ }
```

### Step 7: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Run existing tests against a Cosmos DB emulator or development account
3. Verify partition key values are passed to every CRUD and query operation

## API Differences

| DocumentDB V2 (Old) | Cosmos V3 (New) | Notes |
|----------------------|-----------------|-------|
| `DocumentClient` | `CosmosClient` | New connection model with builder options |
| `Database` (V2 resource) | `Database` (V3 proxy) | Obtained via `CosmosClient.GetDatabase()` |
| `DocumentCollection` | `Container` | Obtained via `Database.GetContainer()` |
| `Document` class | Generic `T` or `dynamic` | No base class required for items |
| `CreateDocumentAsync` | `Container.CreateItemAsync<T>` | Partition key is a required parameter |
| `ReadDocumentAsync` | `Container.ReadItemAsync<T>` | Takes id + partition key, not a URI |
| `ReplaceDocumentAsync` | `Container.ReplaceItemAsync<T>` | Takes id + partition key |
| `DeleteDocumentAsync` | `Container.DeleteItemAsync<T>` | Takes id + partition key |
| `CreateDocumentQuery` | `Container.GetItemQueryIterator<T>` | Uses `QueryDefinition` for parameterized queries |
| `RequestOptions` | `ItemRequestOptions` / `QueryRequestOptions` | Split into operation-specific options |
| `FeedOptions` | `QueryRequestOptions` | `EnableCrossPartitionQuery` removed (always on) |
| `DocumentClientException` | `CosmosException` | Unified exception type with `StatusCode` |
| URI-based resource links | Id-based fluent accessors | No manual URI construction needed |

## Troubleshooting

### Partition Key Required Errors

The V3 SDK requires an explicit `PartitionKey` on most item operations. If the V2 code relied on a default or single-partition collection, add the partition key path to the container configuration and pass it with each call.

### Missing `Document` Base Class

V3 does not require items to inherit from `Document`. Replace `Document` with a plain POCO or `dynamic`. If code accesses `Document.Id` or `Document.SelfLink`, map `Id` to a property on the POCO and remove `SelfLink` references (V3 does not use self-links).

### Query Pagination Changes

V3 queries return a `FeedIterator` that must be iterated with `HasMoreResults` / `ReadNextAsync`. Replace any synchronous `AsEnumerable()` or `ToList()` calls on the old `IDocumentQuery` with the async iteration pattern.

### Connection String Format

V3 accepts either an endpoint+key pair or an `AccountEndpoint=...;AccountKey=...` connection string. If the V2 code parsed connection strings manually, switch to the single-string `CosmosClient(connectionString)` constructor.
