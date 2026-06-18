---
name: migrating-data-services-client
description: >
  Migrates the obsolete Microsoft.Data.Services.Client (WCF Data
  Services) to Microsoft.OData.Client for OData v4 client access.
  Use ONLY when Microsoft.Data.Services.Client has been flagged as
  obsolete or deprecated and must be replaced — not for version-bump
  scenarios where Microsoft.Data.Services.Client is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Microsoft.Data.Services.Client to Microsoft.OData.Client Migration

## Overview

Migrate projects from the WCF Data Services client (`Microsoft.Data.Services.Client`) to the OData v4 client (`Microsoft.OData.Client`). This migration requires updating namespaces, regenerating client proxy classes with OData v4 tooling, and adapting to behavior changes in LINQ query translation and batch operations.

> **Related skills:** migrating-data-edm-to-odata, migrating-data-odata-to-odata-core

## Package Reference Changes

### Old Reference (Remove)

```xml
<PackageReference Include="Microsoft.Data.Services.Client" Version="5.*" />
```

### New Reference (Add)

```xml
<PackageReference Include="Microsoft.OData.Client" Version="{latest-stable-version}" />
```

Use tools or [NuGet](https://www.nuget.org/packages/Microsoft.OData.Client) to find the latest stable version. The `Microsoft.OData.Client` package depends on `Microsoft.OData.Core` and `Microsoft.OData.Edm`.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect Microsoft.Data.Services.Client usage
- [ ] Step 2: Update package references
- [ ] Step 3: Update namespace declarations
- [ ] Step 4: Regenerate client proxy classes
- [ ] Step 5: Update DataServiceContext usage
- [ ] Step 6: Update batch and query operations
- [ ] Step 7: Build and verify
```

### Step 1: Detect Microsoft.Data.Services.Client Usage

Scan the project for:
- `using System.Data.Services.Client;` or `using Microsoft.Data.Services.Client;` statements
- Types such as `DataServiceContext`, `DataServiceQuery<T>`, `DataServiceCollection<T>`
- Generated proxy classes (typically a `.cs` file with `DataServiceContext`-derived classes)
- Package reference to `Microsoft.Data.Services.Client` in the project file

If the project already references `Microsoft.OData.Client`, no migration is needed.

### Step 2: Update Package References

In the project file, replace the old package reference with the new one (see "Package Reference Changes" above). If the project uses centralized package management (`Directory.Packages.props`), update the version there instead.

### Step 3: Update Namespace Declarations

Replace all namespace references:

| Old Namespace | New Namespace |
|---------------|---------------|
| `System.Data.Services.Client` | `Microsoft.OData.Client` |
| `System.Data.Services.Common` | `Microsoft.OData.Client` |

### Step 4: Regenerate Client Proxy Classes

The generated proxy classes from WCF Data Services (via "Add Service Reference" or `DataSvcUtil.exe`) are not compatible with the v4 client. Regenerate them:

1. **OData Connected Service** (Visual Studio): Add a Connected Service reference pointing to the OData v4 endpoint's `$metadata` URL
2. **OData CLI** (`Microsoft.OData.Cli`): Run from the command line:
   ```
   dotnet tool install -g Microsoft.OData.Cli
   odata-cli generate -m https://service-url/$metadata -o GeneratedProxy.cs -ns MyNamespace
   ```

Delete the old generated proxy file after regeneration. The new proxy uses `Microsoft.OData.Client.DataServiceContext` as the base class.

### Step 5: Update DataServiceContext Usage

The core CRUD operations (`AddObject`, `UpdateObject`, `DeleteObject`, `SaveChanges`) have the same signatures but the namespace changes. Additional differences:

| Old Pattern (v1–v3) | New Pattern (v4) | Notes |
|----------------------|-------------------|-------|
| `context.MergeOption = MergeOption.AppendOnly` | `context.MergeOption = MergeOption.AppendOnly` | Same API, namespace change only |
| `context.SaveChanges(SaveChangesOptions.Batch)` | `context.SaveChanges(SaveChangesOptions.BatchWithSingleChangeset)` | Batch option was renamed for clarity |
| `context.Credentials = ...` | `context.HttpRequestTransportMessage` or `HttpClient` handler | Credential handling moved to HTTP pipeline; use `SendingRequest2` event or inject an `HttpClient` with configured handlers |
| `context.ResolveType` delegate | `context.ResolveType` delegate | Same pattern; verify type names match v4 metadata |

### Step 6: Update Batch and Query Operations

**Batch operations:**
```csharp
// Old (v1-v3)
context.SaveChanges(SaveChangesOptions.Batch);

// New (v4)
context.SaveChanges(SaveChangesOptions.BatchWithSingleChangeset);
// Or for independent operations:
context.SaveChanges(SaveChangesOptions.BatchWithIndependentOperations);
```

**LINQ query differences:**
- `Expand()` now supports nested expansions: `context.Products.Expand(p => p.Category.Expand(c => c.Supplier))`
- `AddQueryOption()` still works but prefer LINQ operators for type safety
- Some LINQ operators that were silently evaluated client-side in v3 now throw `NotSupportedException` in v4 — move unsupported operations after `ToList()` to evaluate them client-side explicitly

### Step 7: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Resolve remaining compilation errors — most will be namespace changes and proxy class updates
3. Run existing tests, paying attention to:
   - LINQ queries that may translate differently in v4
   - Batch operations using the renamed options
   - Authentication flows if credentials were configured on the old context

## Troubleshooting

### Generated Proxy Not Compiling

Ensure the OData service exposes a v4-compatible `$metadata` endpoint. If the service is still OData v3, upgrade the service first or use the v3 client until the service is migrated.

### LINQ Queries Throwing NotSupportedException

The v4 client is stricter about which LINQ operators it translates to OData query options. Move unsupported operations (e.g., complex projections, local function calls) to execute client-side after materializing results with `ToList()` or `AsEnumerable()`.

### Authentication Failures

The v4 client does not support the `Credentials` property in the same way. Use the `SendingRequest2` event to attach authentication headers, or configure an `HttpClient` with a `DelegatingHandler` for token-based authentication:

```csharp
context.SendingRequest2 += (sender, args) =>
{
    args.RequestMessage.SetHeader("Authorization", "Bearer " + token);
};
```

### SaveChanges Batch Option Not Found

`SaveChangesOptions.Batch` was replaced with `SaveChangesOptions.BatchWithSingleChangeset`. Update all call sites to use the new enum value.
