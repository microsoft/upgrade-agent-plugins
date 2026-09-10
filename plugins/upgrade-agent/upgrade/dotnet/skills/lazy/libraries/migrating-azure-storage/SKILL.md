---
name: migrating-azure-storage
description: >
  Migrates the deprecated WindowsAzure.Storage to the
  modern Azure SDK storage libraries (Azure.Storage.Blobs,
  Azure.Storage.Queues, Azure.Storage.Files.Shares,
  Azure.Data.Tables). Use ONLY when WindowsAzure.Storage
  has been flagged as obsolete or deprecated and must be
  replaced — not for version-bump scenarios where
  WindowsAzure.Storage is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Azure Storage Migration

## Overview

Migrate from the monolithic `WindowsAzure.Storage` (or `Microsoft.Azure.Storage.*`) package to the modern Azure SDK storage libraries. The legacy SDK used `CloudStorageAccount` as a single entry point for all storage services. The new SDK splits into service-specific packages with dedicated client types. All new clients are thread-safe, reusable, and support both connection string and `Azure.Identity`-based authentication.

## Package Reference Changes

### Old References (Remove)

```xml
<!-- Monolithic legacy package -->
<PackageReference Include="WindowsAzure.Storage" Version="{old-version}" />

<!-- Or the split legacy packages -->
<PackageReference Include="Microsoft.Azure.Storage.Blob" Version="{old-version}" />
<PackageReference Include="Microsoft.Azure.Storage.Queue" Version="{old-version}" />
<PackageReference Include="Microsoft.Azure.Storage.File" Version="{old-version}" />
<PackageReference Include="Microsoft.Azure.Cosmos.Table" Version="{old-version}" />
```

### New References (Add)

Add only the packages for storage services the project uses:

```xml
<PackageReference Include="Azure.Storage.Blobs" Version="{version}" />
<PackageReference Include="Azure.Storage.Queues" Version="{version}" />
<PackageReference Include="Azure.Storage.Files.Shares" Version="{version}" />
<PackageReference Include="Azure.Data.Tables" Version="{version}" />
```

> **Note:** Table storage uses `Azure.Data.Tables`, a separate package from the `Azure.Storage.*` family. It supports both Azure Table Storage and Azure Cosmos DB Table API.

Optionally add `Azure.Identity` for Azure AD–based authentication.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect legacy Azure Storage usage
- [ ] Step 2: Update project file references
- [ ] Step 3: Replace storage account initialization
- [ ] Step 4: Migrate blob operations
- [ ] Step 5: Migrate queue operations
- [ ] Step 6: Migrate table operations
- [ ] Step 7: Migrate file share operations
- [ ] Step 8: Build and verify
```

### Step 1: Detect Legacy Azure Storage Usage

Scan the project for:
- `using Microsoft.WindowsAzure.Storage;` or `using Microsoft.Azure.Storage;` statements
- `CloudStorageAccount.Parse(...)` or `CloudStorageAccount.TryParse(...)` calls
- Client types: `CloudBlobClient`, `CloudBlobContainer`, `CloudBlockBlob`, `CloudQueue`, `CloudTable`, `CloudFileShare`
- Determine which storage services are used to add only the needed new packages

### Step 2: Update Project File References

Remove legacy packages and add the relevant new packages (see "Package Reference Changes" above). Only add packages for services the project actually uses.

### Step 3: Replace Storage Account Initialization

The new SDK does not use `CloudStorageAccount`. Create service-specific clients directly:

```csharp
// Old
var account = CloudStorageAccount.Parse(connectionString);
var blobClient = account.CreateCloudBlobClient();

// New
var blobServiceClient = new BlobServiceClient(connectionString);

// Or with Azure AD authentication
var blobServiceClient = new BlobServiceClient(
    new Uri("https://myaccount.blob.core.windows.net"),
    new DefaultAzureCredential());
```

### Step 4: Migrate Blob Operations

| WindowsAzure.Storage (Old) | Azure.Storage.Blobs (New) |
|----------------------------|--------------------------|
| `CloudBlobClient` | `BlobServiceClient` |
| `CloudBlobContainer` | `BlobContainerClient` |
| `CloudBlockBlob` | `BlobClient` |
| `CloudAppendBlob` | `AppendBlobClient` |
| `CloudPageBlob` | `PageBlobClient` |
| `container.CreateIfNotExistsAsync()` | `container.CreateIfNotExistsAsync()` (same) |
| `blob.UploadFromStreamAsync(stream)` | `await blob.UploadAsync(stream)` |
| `blob.DownloadToStreamAsync(stream)` | `await blob.DownloadToAsync(stream)` |
| `blob.ExistsAsync()` | `await blob.ExistsAsync()` (same) |
| `blob.DeleteIfExistsAsync()` | `await blob.DeleteIfExistsAsync()` (same) |
| `container.ListBlobsSegmentedAsync(...)` | `container.GetBlobsAsync(...)` (async enumerable) |

Paginated listing changes from segmented tokens to `IAsyncEnumerable`:

```csharp
// Old
BlobContinuationToken token = null;
do {
    var segment = await container.ListBlobsSegmentedAsync(token);
    token = segment.ContinuationToken;
} while (token != null);

// New
await foreach (var blobItem in container.GetBlobsAsync())
{
    // Process each blob
}
```

### Step 5: Migrate Queue Operations

| WindowsAzure.Storage (Old) | Azure.Storage.Queues (New) |
|----------------------------|---------------------------|
| `CloudQueueClient` | `QueueServiceClient` |
| `CloudQueue` | `QueueClient` |
| `queue.AddMessageAsync(new CloudQueueMessage(text))` | `await queue.SendMessageAsync(text)` |
| `queue.GetMessageAsync()` | `await queue.ReceiveMessageAsync()` |
| `queue.DeleteMessageAsync(message)` | `await queue.DeleteMessageAsync(message.MessageId, message.PopReceipt)` |

> **Note:** The new SDK base64-encodes message content by default. To disable: `new QueueClientOptions { MessageEncoding = QueueMessageEncoding.None }`.

### Step 6: Migrate Table Operations

Table storage moved to a separate package (`Azure.Data.Tables`):

| Old (CloudTable) | New (Azure.Data.Tables) |
|------------------|------------------------|
| `CloudTableClient` | `TableServiceClient` |
| `CloudTable` | `TableClient` |
| `TableOperation.Insert(entity)` | `await tableClient.AddEntityAsync(entity)` |
| `TableOperation.InsertOrReplace(entity)` | `await tableClient.UpsertEntityAsync(entity)` |
| `TableOperation.Retrieve(pk, rk)` | `await tableClient.GetEntityAsync<T>(pk, rk)` |
| `table.ExecuteQuerySegmentedAsync(query, token)` | `tableClient.QueryAsync<T>(filter)` (async enumerable) |
| `DynamicTableEntity` | `TableEntity` (dictionary-like access) |

Entities must implement `ITableEntity` (or use the built-in `TableEntity` class).

### Step 7: Migrate File Share Operations

| WindowsAzure.Storage (Old) | Azure.Storage.Files.Shares (New) |
|----------------------------|----------------------------------|
| `CloudFileClient` | `ShareServiceClient` |
| `CloudFileShare` | `ShareClient` |
| `CloudFileDirectory` | `ShareDirectoryClient` |
| `CloudFile` | `ShareFileClient` |
| `file.UploadFromStreamAsync(stream)` | `await file.UploadAsync(stream)` |
| `file.DownloadToStreamAsync(stream)` | `await file.DownloadAsync()` then read from stream |

Skip this step if the project does not use Azure File Shares.

### Step 8: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Test each storage service used by the project (blob upload/download, queue send/receive, table CRUD, file operations)
3. Verify authentication works with the chosen method (connection string or Azure AD)
4. Confirm paginated listings work correctly with async enumerables

## Troubleshooting

### CloudStorageAccount Not Found

The new SDK does not include `CloudStorageAccount`. Replace with service-specific client constructors that accept a connection string directly (e.g., `new BlobServiceClient(connectionString)`).

### Base64-Encoded Queue Messages

The new `QueueClient` base64-encodes messages by default. If interoperating with code using the old SDK, set `MessageEncoding = QueueMessageEncoding.None` in `QueueClientOptions` to maintain compatibility.

### Table Entity Serialization Errors

Entities must implement `ITableEntity` with `PartitionKey`, `RowKey`, `Timestamp`, and `ETag` properties. If using `DynamicTableEntity` from the old SDK, switch to `TableEntity` which provides dictionary-style property access.

### Mixed Old and New SDK References

Transitive dependencies may pull in both old and new packages, causing ambiguous type references. Use `dotnet list package --include-transitive` to identify conflicts and add explicit package references to force the new versions.
