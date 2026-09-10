---
name: migrating-bond-interfaces
description: >
  Migrates from the obsolete Microsoft.Bond.Interfaces
  package to the unified Bond.CSharp SDK for Bond
  serialization. Use ONLY when Microsoft.Bond.Interfaces
  has been flagged as obsolete or deprecated and must be
  replaced — not for version-bump scenarios where
  Microsoft.Bond.Interfaces is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Microsoft.Bond.Interfaces to Bond.CSharp Migration

## Overview

Migrate from the legacy `Microsoft.Bond.Interfaces` package to the unified `Bond.CSharp` SDK. `Microsoft.Bond.Interfaces` provided a subset of Bond types (interfaces and base classes) without the full runtime or compiler. `Bond.CSharp` is the consolidated package that bundles `Bond.Core`, `Bond.IO`, `Bond.JSON`, `Bond.Reflection`, and the `gbc` schema compiler, providing everything needed for Bond serialization on modern .NET.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="Microsoft.Bond.Interfaces" Version="*" />
<!-- Also remove if present — these are replaced by Bond.CSharp -->
<PackageReference Include="Microsoft.Bond" Version="*" />
<PackageReference Include="Microsoft.Bond.Core.CSharp" Version="*" />
```

### New Reference (Add)

```xml
<!-- Unified package: includes runtime, IO, JSON, reflection, and gbc compiler -->
<PackageReference Include="Bond.CSharp" Version="{latest-stable}" />
```

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect Bond usage
- [ ] Step 2: Update package references
- [ ] Step 3: Regenerate schema code (if applicable)
- [ ] Step 4: Update namespace references
- [ ] Step 5: Handle API differences
- [ ] Step 6: Build and verify
```

### Step 1: Detect Bond Usage

Scan the project for:
- `using Bond;` and `using Bond.IO;` statements
- `using Microsoft.Bond;` statements (old namespace)
- References to Bond types: `IBonded<T>`, `Bonded<T>`, `BondDataType`, schema-attributed structs
- `.bond` schema files in the project
- Generated `_types.cs` or `_grpc.cs` files from the gbc compiler

### Step 2: Update Package References

Remove `Microsoft.Bond.Interfaces`, `Microsoft.Bond`, and `Microsoft.Bond.Core.CSharp` package references. Add `Bond.CSharp` in the project file.

`Bond.CSharp` includes MSBuild targets that automatically compile `.bond` schema files during build. If the project previously used a manual gbc invocation, the build-integrated compiler may replace it.

### Step 3: Regenerate Schema Code (If Applicable)

If the project contains `.bond` schema files:

1. Remove previously generated C# files (typically `*_types.cs`, `*_grpc.cs`)
2. Ensure `.bond` files are included in the project (Bond.CSharp auto-discovers them)
3. Build the project — `Bond.CSharp` runs `gbc` automatically and generates fresh code

If the project only consumes pre-generated Bond types without `.bond` files, skip this step.

### Step 4: Update Namespace References

| Old Namespace | New Namespace |
|---------------|---------------|
| `Microsoft.Bond` | `Bond` |
| `Microsoft.Bond.IO` | `Bond.IO` |
| `Microsoft.Bond.Tag` | `Bond.Tag` |

Most types keep the same name — only the root namespace prefix changes from `Microsoft.Bond` to `Bond`.

### Step 5: Handle API Differences

The core Bond types are largely the same, but some patterns differ:

| Old (Microsoft.Bond.Interfaces) | New (Bond.CSharp) | Notes |
|----------------------------------|-------------------|-------|
| `IBonded<T>` interface | `IBonded<T>` (same) | Interface is unchanged |
| `Bonded<T>` class | `Bonded<T>` (same) | Implementation is unchanged |
| Manual serializer setup | `new Serializer<T>(protocol)` | Use the typed serializer API |
| Custom protocol readers | `CompactBinaryReader<T>`, `FastBinaryReader<T>` | Concrete reader types from Bond.IO |

If the project used only the interfaces from `Microsoft.Bond.Interfaces` (e.g., `IBonded<T>`, `BondDataType`), the migration is primarily a namespace change.

### Step 6: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. If `.bond` schemas are present, verify the generated code compiles correctly
3. Run serialization round-trip tests — serialize and deserialize representative objects to confirm data fidelity
4. Verify interoperability with existing Bond-serialized data stores or services

## Troubleshooting

### gbc Compiler Not Found

`Bond.CSharp` ships gbc as a build tool. If the build fails with a missing gbc error, ensure the `Bond.CSharp` package restored correctly. Run `dotnet restore --force` to refresh the package cache.

### Schema Compilation Errors

If `.bond` schema files reference types from other schemas, ensure all dependent `.bond` files are in the project. The gbc compiler resolves imports relative to the project directory. Add `<BondImportDirectory>` in the project file to specify additional import paths:

```xml
<ItemGroup>
  <BondImportDirectory Include="path/to/shared/schemas" />
</ItemGroup>
```

### Missing Types After Migration

If the project previously referenced only `Microsoft.Bond.Interfaces` for a subset of types, `Bond.CSharp` provides the full type set. Verify that `using Bond;` replaces `using Microsoft.Bond;` in all files.

### Binary Compatibility

Bond's wire format is stable across versions. Data serialized with the old Microsoft.Bond packages is compatible with Bond.CSharp. No data migration is needed.
