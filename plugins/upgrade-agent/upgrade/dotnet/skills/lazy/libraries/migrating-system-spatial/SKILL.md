---
name: migrating-system-spatial
description: >
  Migrates the obsolete System.Spatial (OData v1–v3 spatial
  types) to Microsoft.Spatial for OData v4. Use ONLY when
  System.Spatial has been flagged as obsolete or deprecated
  and must be replaced — not for version-bump scenarios where
  System.Spatial is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# System.Spatial to Microsoft.Spatial Migration

## Overview

Migrate from `System.Spatial` (OData v3) to `Microsoft.Spatial` (OData v4). This is primarily a namespace change — the spatial type APIs (`GeographyPoint`, `GeometryPoint`, `GeographyLineString`, etc.) remain largely compatible. The main work is updating `using` directives and adjusting any `SpatialFormatter` or extension method references.

## Wire-Contract Gate

Before replacement in any server-side project or library serving Framework HTTP endpoints, first run the
`migrating-webapi-odata` wire-compatibility gate, including non-OData responses.
Require a scoped PASS, or evidence-backed NOT APPLICABLE from its applicability
check for code with no affected HTTP consumers. On STOP, unknown evidence, or an
unavailable gate, do not execute the conversion or troubleshooting instructions
below. Retain the protected host's spatial and OData dependencies.
For client-only code, confirm the remote service supports the proposed protocol;
do not upgrade the server or shared dependencies to satisfy this client change.

## Package Reference Changes

### Old Reference (Remove)

```xml
<PackageReference Include="System.Spatial" Version="{old-version}" />
```

### New Reference (Add)

```xml
<PackageReference Include="Microsoft.Spatial" Version="{version}" />
```

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect System.Spatial usage
- [ ] Step 2: Update project file references
- [ ] Step 3: Update namespace references
- [ ] Step 4: Adjust API differences
- [ ] Step 5: Build and verify
```

### Step 1: Detect System.Spatial Usage

Scan the project for:
- `using System.Spatial;` statements
- Types: `GeographyPoint`, `GeometryPoint`, `GeographyLineString`, `GeometryLineString`, `GeographyPolygon`, `GeometryPolygon`
- `SpatialFormatter` and `GeoJsonObjectFormatter` usage
- `GeographyOperationsExtensions` method calls (e.g., `Distance`)

### Step 2: Update Project File References

Only within the approved scope from the Wire-Contract Gate, replace `System.Spatial`
with `Microsoft.Spatial`. Check OData client/server dependency compatibility;
do not automatically upgrade them to v4. Gate server-side changes separately
and retain packages used by a protected endpoint.

### Step 3: Update Namespace References

Replace all namespace references:

```csharp
// Old
using System.Spatial;

// New
using Microsoft.Spatial;
```

This covers all spatial types — the type names themselves are unchanged.

### Step 4: Adjust API Differences

| System.Spatial (Old) | Microsoft.Spatial (New) | Notes |
|---------------------|------------------------|-------|
| `System.Spatial.GeographyPoint` | `Microsoft.Spatial.GeographyPoint` | Same API, different namespace |
| `System.Spatial.GeometryPoint` | `Microsoft.Spatial.GeometryPoint` | Same API, different namespace |
| `System.Spatial.SpatialFormatter` | `Microsoft.Spatial.SpatialFormatter` | Same API, different namespace |
| `System.Spatial.GeoJsonObjectFormatter` | `Microsoft.Spatial.GeoJsonObjectFormatter` | Improved GeoJSON support in v4 |
| `System.Spatial.GeographyOperationsExtensions` | `Microsoft.Spatial.GeographyOperationsExtensions` | Extension methods for Distance, Length, etc. |
| `SpatialValidator.Create()` | `SpatialValidator.Create()` | Same API, different namespace |

Factory methods like `GeographyPoint.Create(latitude, longitude)` retain the same signature. No code changes beyond the namespace are needed for these calls.

### Step 5: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Verify spatial operations produce correct results (e.g., distance calculations, point creation)
3. If the project includes OData endpoints, confirm spatial query filters (`geo.distance`, `geo.intersects`) still work

## Troubleshooting

### Ambiguous Type References

Inspect `dotnet list package --include-transitive` and qualify or alias types
when both namespaces are needed. Remove an old dependency only within the
approved scope and only if no protected consumer still needs it.

### OData Version Mismatch

`Microsoft.Spatial` belongs to the OData v4 stack. V3 dependencies may still need
`System.Spatial`; that mismatch is not authorization to upgrade all OData
packages. For serving projects, return to `migrating-webapi-odata` before any
server dependency change. On STOP, preserve the v3 stack or split the projects.

### Missing Extension Methods

If `Distance()` or other extension methods are unresolved after the namespace change, verify that `using Microsoft.Spatial;` is present — the extension methods are in the `GeographyOperationsExtensions` class in the same namespace.
