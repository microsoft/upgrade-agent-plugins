---
name: managing-package-references
description: >
  Manages .NET package references and dependencies in project files. Handles adding, removing, and updating
  PackageReference, ProjectReference, and FrameworkReference items. Supports both standard package management
  and Central Package Management (CPM) with Directory.Packages.props. Use when modifying NuGet packages,
  updating package versions, adding project references, working with project files (.csproj, .vbproj, .fsproj) or .props files, or managing
  CPM configurations. Also triggers for "add package", "update dependency", "remove NuGet reference",
  "PackageVersion", and "FrameworkReference" tasks.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Project Package Management

## Overview

Manage package and dependency references in `<ItemGroup>` elements of .NET project files.

**Item types:** PackageReference (NuGet), ProjectReference, FrameworkReference, PackageVersion (CPM)

**Key insight:** Packages can be defined in imported files (Directory.Build.props, Directory.Packages.props), not just in project files. Always discover where packages are defined before modifying them — editing the wrong file causes silent failures or version conflicts.

## Required Tools

### get_project_dependencies

Discover dependencies and CPM status before any modification — the workflow differs completely depending on the result.

```
get_project_dependencies(solution-file-path, path-to-project-file)
```

**Output provides:**
- Whether CPM is enabled
- All import files in the chain
- Each package with its version and "defined in" location

### Additional Discovery

- `view` — Read the project file, Directory.Build.props, or Directory.Packages.props directly
- `grep` — Search for a package across files: `grep -r "Newtonsoft.Json" /repo --include="*.csproj" --include="*.vbproj" --include="*.fsproj"`
- `find` — Locate management files: `find /repo -name "Directory.Packages.props" -o -name "Directory.Build.props"`
- `dotnet list package` — List packages with available updates

## Two Package Management Modes

### Standard (Non-CPM)

PackageReference includes version directly:
```xml
<PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
```

### Central Package Management (CPM)

Versions are centralized in Directory.Packages.props; project file references omit versions. This ensures consistent versioning across all projects in a repository.

```xml
<!-- Directory.Packages.props -->
<PackageVersion Include="Newtonsoft.Json" Version="13.0.3" />

<!-- Project file — NO version attribute -->
<PackageReference Include="Newtonsoft.Json" />
```

**CPM Detection:** `get_project_dependencies` output starts with "This project uses NuGet Central Package Management (CPM)".

## Workflow

```
Task Progress:
- [ ] Step 1: Discover current state
- [ ] Step 2: Choose mode and execute
- [ ] Step 3: Verify
```

### Step 1: Discover Current State

Always call `get_project_dependencies` first.

```
get_project_dependencies /repo/MySolution.sln /repo/src/MyApp/MyProject.csproj
```

Extract: (1) CPM enabled? (2) Existing packages (3) Where each is defined (4) Import files

### Step 2: Choose Mode and Execute

- **CPM enabled →** Follow CPM operations below
- **CPM not enabled →** Follow Standard operations below

### Step 3: Verify

Run `dotnet restore` or `dotnet build` to confirm the change is valid.

## Standard Mode Operations

### Add Package
```xml
<PackageReference Include="Serilog" Version="3.1.1" />
```

### Update Package Version

Find where defined via `get_project_dependencies`, then update the version in that file:
```xml
<!-- Before -->
<PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
<!-- After -->
<PackageReference Include="Newtonsoft.Json" Version="13.0.4" />
```

### Remove Package

Remove the entire `<PackageReference ... />` line from the project file.

## CPM Mode Operations

### Add Package (Two Steps Required)

CPM splits version declaration from reference to enforce consistent versions across projects.

**Step A — Add version to Directory.Packages.props:**
```xml
<PackageVersion Include="Serilog" Version="3.1.1" />
```

**Step B — Add reference (no version) to project file:**
```xml
<PackageReference Include="Serilog" />
```

### Update Package Version

Only modify Directory.Packages.props — project files have no version to change. This automatically updates all projects using that package.

```xml
<!-- In Directory.Packages.props -->
<PackageVersion Include="Newtonsoft.Json" Version="13.0.4" />
```

### Remove Package

1. Remove `<PackageReference>` from the project file
2. Check if other projects still use the package: `grep -r "PackageName" /repo --include="*.csproj" --include="*.vbproj" --include="*.fsproj"`
3. If no other projects reference it, also remove `<PackageVersion>` from Directory.Packages.props — leaving orphaned entries clutters the central file

## Project References

Same in both modes. Use relative paths with forward slashes:

```xml
<ProjectReference Include="../MyApp.Core/MyApp.Core.csproj" />
```

## Framework References

Used for ASP.NET Core, WPF, WinForms shared frameworks. No version attribute needed — the version comes from the SDK.

```xml
<FrameworkReference Include="Microsoft.AspNetCore.App" />
```

Common frameworks: `Microsoft.AspNetCore.App`, `Microsoft.WindowsDesktop.App.WPF`, `Microsoft.WindowsDesktop.App.WindowsForms`

## Common Patterns

### Full CPM Structure
```xml
<!-- /repo/Directory.Packages.props -->
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <PackageVersion Include="Serilog" Version="3.1.1" />
    <PackageVersion Include="Newtonsoft.Json" Version="13.0.3" />
  </ItemGroup>
</Project>

<!-- Projects reference without version -->
<ItemGroup>
  <PackageReference Include="Serilog" />
</ItemGroup>
```

### Centralized Packages via Directory.Build.props (Non-CPM)
```xml
<!-- /repo/Directory.Build.props — projects inherit these automatically -->
<ItemGroup>
  <PackageReference Include="Serilog" Version="3.1.1" />
</ItemGroup>
```

## CPM Version Attribute Rules

In CPM projects, `<PackageReference>` must not have a `Version` attribute — including one causes version conflicts and build errors.

| Attribute | In CPM Project | Action |
|-----------|---------------|--------|
| `Version="1.0"` | Invalid | Remove it; ensure version exists in Directory.Packages.props |
| `VersionOverride="2.0-beta"` | Valid but rare | Intentional CPM bypass; leave alone unless asked to change |
| No version attribute | Correct | Normal CPM behavior |

## Red Flags

- Adding `Version` attribute to `PackageReference` when CPM is enabled — the most common CPM mistake
- Modifying packages without running `get_project_dependencies` first — risk editing the wrong file
- Removing `PackageVersion` from Directory.Packages.props when other projects still reference it
- Updating version in project file instead of Directory.Packages.props in CPM mode
- Mixing CPM and non-CPM in the same repo

## Troubleshooting

**Package version not respected (CPM):** Check that the project's `PackageReference` has no `Version` attribute. If `Version` is present (not `VersionOverride`), remove it and ensure the version is in Directory.Packages.props.

**CPM not working:** Verify Directory.Packages.props contains `<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>` and is in the repo root. Requires .NET SDK 6.0.300+.

**Can't find where package is defined:** Run `get_project_dependencies` first. If still unclear: `grep -r "PackageName" /repo --include="*.csproj" --include="*.vbproj" --include="*.fsproj" --include="*.props"`

## Related Skills

For PropertyGroup modifications (TargetFramework, etc.), see: **project-properties-modification** skill
