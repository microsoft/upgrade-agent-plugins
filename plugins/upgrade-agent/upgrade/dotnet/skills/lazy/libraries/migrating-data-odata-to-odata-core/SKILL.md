---
name: migrating-data-odata-to-odata-core
description: >
  Migrates the obsolete Microsoft.Data.OData (OData v1–v3) to
  Microsoft.OData.Core for OData v4 serialization.
  Use ONLY when Microsoft.Data.OData has been flagged as obsolete or
  deprecated and must be replaced — not for version-bump scenarios
  where Microsoft.Data.OData is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Microsoft.Data.OData to Microsoft.OData.Core Migration

## Overview

Migrate projects from the OData v1–v3 serialization library (`Microsoft.Data.OData`) to the OData v4 library (`Microsoft.OData.Core`). Beyond the namespace rename, this migration involves significant type renames (e.g., `ODataEntry` → `ODataResource`) and updated reader/writer APIs with async support.

> **Related skills:** migrating-data-edm-to-odata, migrating-data-services-client

## Wire-Contract Gate

Before replacement in any server-side project or library serving Framework HTTP endpoints, first run the
`migrating-webapi-odata` wire-compatibility gate, including non-OData responses.
Require a scoped PASS, or evidence-backed NOT APPLICABLE from its applicability
check for code with no affected HTTP consumers. On STOP, unknown evidence, or an
unavailable gate, do not execute the package, serialization, or troubleshooting
conversion instructions below. Keep dependencies needed by the live host.
A namespace migration cannot preserve v3/Atom serialization.

## Package Reference Changes

### Old Reference (Remove)

```xml
<PackageReference Include="Microsoft.Data.OData" Version="5.*" />
```

### New Reference (Add)

```xml
<PackageReference Include="Microsoft.OData.Core" Version="{latest-stable-version}" />
```

Use tools or [NuGet](https://www.nuget.org/packages/Microsoft.OData.Core) to find the latest stable version. The `Microsoft.OData.Core` package depends on `Microsoft.OData.Edm` — if the project also references `Microsoft.Data.Edm`, apply the migrating-data-edm-to-odata skill first.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect Microsoft.Data.OData usage
- [ ] Step 2: Update package references
- [ ] Step 3: Update namespace declarations
- [ ] Step 4: Rename types
- [ ] Step 5: Update reader/writer patterns
- [ ] Step 6: Update batch operations
- [ ] Step 7: Build and verify
```

### Step 1: Detect Microsoft.Data.OData Usage

Scan the project for:
- `using Microsoft.Data.OData;` and sub-namespace imports
- Types such as `ODataMessageReader`, `ODataMessageWriter`, `ODataEntry`, `ODataFeed`, `ODataBatchReader`
- Package reference to `Microsoft.Data.OData` in the project file

If the project already references `Microsoft.OData.Core`, no migration is needed.

### Step 2: Update Package References

Only for the approved scope from the Wire-Contract Gate, replace the old package
reference with the new one (see "Package Reference Changes" above). For centralized
package management, retain old versions still required by protected projects.

### Step 3: Update Namespace Declarations

Replace all namespace references:

| Old Namespace | New Namespace |
|---------------|---------------|
| `Microsoft.Data.OData` | `Microsoft.OData` |
| `Microsoft.Data.OData.Query` | `Microsoft.OData.UriParser` |
| `Microsoft.Data.OData.Atom` | Removed — Atom format is not supported in v4 |

The v4 library uses `Microsoft.OData` as the root namespace (not `Microsoft.OData.Core`). The package name and the namespace differ.

### Step 4: Rename Types

These core types were renamed to align with OData v4 terminology:

| Old Type (v1–v3) | New Type (v4) | Notes |
|-------------------|---------------|-------|
| `ODataEntry` | `ODataResource` | Represents a single entity or complex type instance |
| `ODataFeed` | `ODataResourceSet` | Represents a collection of resources |
| `ODataNavigationLink` | `ODataNestedResourceInfo` | Represents a link to nested resources |
| `ODataBatchOperationRequestMessage` | `ODataBatchOperationRequestMessage` | Same name, but namespace changed |
| `ODataCollectionValue` | `ODataCollectionValue` | Same name, additional properties for type annotation |

### Step 5: Update Reader/Writer Patterns

The reader/writer APIs gained async overloads and changed method names:

```csharp
// Old (v1-v3) — reading an entry
ODataReader reader = messageReader.CreateODataEntryReader();
while (reader.Read())
{
    if (reader.State == ODataReaderState.EntryEnd)
    {
        ODataEntry entry = (ODataEntry)reader.Item;
    }
}

// New (v4) — reading a resource
ODataReader reader = messageReader.CreateODataResourceReader();
while (reader.Read())
{
    if (reader.State == ODataReaderState.ResourceEnd)
    {
        ODataResource resource = (ODataResource)reader.Item;
    }
}
```

Key method renames:
- `CreateODataEntryReader()` → `CreateODataResourceReader()`
- `CreateODataFeedReader()` → `CreateODataResourceSetReader()`
- `CreateODataEntryWriter()` → `CreateODataResourceWriter()`
- `CreateODataFeedWriter()` → `CreateODataResourceSetWriter()`

For async code, use the `Async` suffixed variants (e.g., `CreateODataResourceReaderAsync()`).

### Step 6: Update Batch Operations

```csharp
// Old (v1-v3)
ODataBatchReader batchReader = messageReader.CreateODataBatchReader();

// New (v4) — synchronous
ODataBatchReader batchReader = messageReader.CreateODataBatchReader();

// New (v4) — async (preferred)
ODataBatchReader batchReader = await messageReader.CreateODataBatchReaderAsync();
```

The batch reader state enum values are the same, but prefer the async API for new code. The v4 batch format uses the multipart/mixed or JSON batch format depending on configuration.

### Step 7: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Resolve remaining compilation errors — most will be type renames and namespace changes
3. Run existing tests to verify serialization/deserialization behavior
4. If the project serves OData endpoints, verify that clients can still read responses (v4 payload format differs from v3)

## Troubleshooting

### Atom Format References

OData v4 does not support Atom. For an HTTP contract requiring Atom, STOP and
follow `migrating-webapi-odata` preservation guidance; do not switch it to JSON.
For non-serving code with a recorded NOT APPLICABLE, change an internal format
only after confirming its consumers can change with it.

### Missing CreateODataEntryReader Method

This method was renamed to `CreateODataResourceReader()`. Update all call sites and the corresponding state checks (e.g., `ODataReaderState.EntryEnd` → `ODataReaderState.ResourceEnd`).

### Payload Compatibility with v3 Clients

Required v3 compatibility means STOP for that endpoint, not permission to replace
its packages. Keep the v3 endpoint intact. A separate v4 endpoint requires its
own scoped PASS and an owner-approved plan; it never licenses cleanup of the
v3 endpoint's dependencies. `ODataMessageWriterSettings` cannot make v4 emit v3.
