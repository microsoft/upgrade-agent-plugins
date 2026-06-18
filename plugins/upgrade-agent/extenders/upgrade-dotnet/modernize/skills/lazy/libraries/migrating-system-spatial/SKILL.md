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

Remove `System.Spatial` and add `Microsoft.Spatial` (see "Package Reference Changes" above). If the project uses OData client or server libraries, ensure they are also updated to OData v4 versions that depend on `Microsoft.Spatial`.

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

If both `System.Spatial` and `Microsoft.Spatial` are referenced (e.g., via transitive dependencies), the compiler will report ambiguous type errors. Remove the `System.Spatial` package and ensure no transitive dependency pulls it in. Use `dotnet list package --include-transitive` to check.

### OData Version Mismatch

`Microsoft.Spatial` is part of the OData v4 ecosystem. If other OData packages in the project still target v3 (e.g., `Microsoft.Data.OData`), they may bring in `System.Spatial` transitively. Upgrade all OData packages to v4 together.

### Missing Extension Methods

If `Distance()` or other extension methods are unresolved after the namespace change, verify that `using Microsoft.Spatial;` is present — the extension methods are in the `GeographyOperationsExtensions` class in the same namespace.
