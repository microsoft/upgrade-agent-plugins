---
name: migrating-data-edm-to-odata
description: >
  Migrates the obsolete Microsoft.Data.Edm (OData v1–v3 EDM types)
  to Microsoft.OData.Edm for OData v4.
  Use ONLY when Microsoft.Data.Edm has been flagged as obsolete or
  deprecated and must be replaced — not for version-bump scenarios
  where Microsoft.Data.Edm is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Microsoft.Data.Edm to Microsoft.OData.Edm Migration

## Overview

Migrate projects from the OData v1–v3 EDM library (`Microsoft.Data.Edm`) to the OData v4 EDM library (`Microsoft.OData.Edm`). The primary change is a namespace rename, but several model interfaces gained new members and some types were renamed to align with the OData v4 specification.

> **Related skills:** migrating-data-odata-to-odata-core, migrating-data-services-client

## Package Reference Changes

### Old Reference (Remove)

```xml
<PackageReference Include="Microsoft.Data.Edm" Version="5.*" />
```

### New Reference (Add)

```xml
<PackageReference Include="Microsoft.OData.Edm" Version="{latest-stable-version}" />
```

Use tools or [NuGet](https://www.nuget.org/packages/Microsoft.OData.Edm) to find the latest stable version.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect Microsoft.Data.Edm usage
- [ ] Step 2: Update package references
- [ ] Step 3: Update namespace declarations
- [ ] Step 4: Handle API differences
- [ ] Step 5: Update validation calls
- [ ] Step 6: Build and verify
```

### Step 1: Detect Microsoft.Data.Edm Usage

Scan the project for:
- `using Microsoft.Data.Edm;` and sub-namespace imports (`Microsoft.Data.Edm.Library`, `Microsoft.Data.Edm.Validation`, etc.)
- Types such as `IEdmModel`, `EdmCoreModel`, `IEdmEntityType`, `IEdmComplexType`
- Package reference to `Microsoft.Data.Edm` in the project file

If the project already references `Microsoft.OData.Edm`, no migration is needed.

### Step 2: Update Package References

In the project file, replace the old package reference with the new one (see "Package Reference Changes" above). If the project uses centralized package management (`Directory.Packages.props`), update the version there instead.

### Step 3: Update Namespace Declarations

Replace all namespace references:

| Old Namespace | New Namespace |
|---------------|---------------|
| `Microsoft.Data.Edm` | `Microsoft.OData.Edm` |
| `Microsoft.Data.Edm.Library` | `Microsoft.OData.Edm` |
| `Microsoft.Data.Edm.Validation` | `Microsoft.OData.Edm.Validation` |
| `Microsoft.Data.Edm.Csdl` | `Microsoft.OData.Edm.Csdl` |

The `Library` sub-namespace was merged into the root `Microsoft.OData.Edm` namespace in v4.

### Step 4: Handle API Differences

| Old API (v1–v3) | New API (v4) | Action |
|------------------|--------------|--------|
| `EdmMultiplicity` enum | `EdmMultiplicity` (values renamed) | Update enum member references; `EdmMultiplicity.Many` is now consistent across all usage sites |
| `IEdmEntityType.DeclaredKey` | `IEdmEntityType.DeclaredKey` (returns `IEnumerable<IEdmStructuralProperty>`) | Verify key property type alignment — v4 uses structural properties exclusively |
| `EdmCoreModel.Instance` | `EdmCoreModel.Instance` (expanded primitive types) | Review usages; v4 includes additional primitive types like `Edm.Date` and `Edm.TimeOfDay` |
| `IEdmModel.SchemaElements` | `IEdmModel.SchemaElements` (additional element kinds) | Handle new element kinds such as `EdmSchemaElementKind.TypeDefinition` and `EdmSchemaElementKind.Term` |
| `IEdmEntityContainer.FindEntitySet(string)` | `IEdmEntityContainer.FindEntitySet(string)` (returns `IEdmEntitySet` with navigation bindings) | Adapt code that inspects entity set metadata to account for navigation property bindings |

### Step 5: Update Validation Calls

The validation API changed:

```csharp
// Old (v1-v3)
IEnumerable<EdmError> errors;
bool isValid = model.Validate(out errors);

// New (v4)
IEnumerable<EdmError> errors;
bool isValid = CsdlReader.TryParse(reader, out model, out errors);
// Or validate an existing model:
bool isValid = model.Validate(out errors);
```

The `EdmError` type moved to `Microsoft.OData.Edm.Validation`. Update any error inspection code accordingly.

### Step 6: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Resolve any remaining compilation errors — most will be namespace or type-rename issues
3. Run existing tests to verify EDM model construction and query behavior

## Troubleshooting

### Missing Types After Namespace Change

Some types from `Microsoft.Data.Edm.Library` moved directly into `Microsoft.OData.Edm`. If a type is not found after updating namespaces, search for it in the root namespace rather than a sub-namespace.

### New Primitive Types Cause Unexpected Behavior

OData v4 introduced `Edm.Date`, `Edm.TimeOfDay`, and `Edm.Duration` as distinct primitive types. Code that enumerates primitive types or switches on `EdmPrimitiveTypeKind` needs to handle these new values.

### Validation Errors on Previously Valid Models

The v4 validation rules are stricter. Review validation errors carefully — they often indicate model constructs that were tolerated in v3 but are invalid under the OData v4 specification.
