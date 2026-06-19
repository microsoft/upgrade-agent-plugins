---
name: managing-legacy-dotnet-packages
description: >
  Manages NuGet packages in old-style .NET Framework projects (.NET Framework 4.x).
  Handles both packages.config (classic NuGet) and PackageReference in non-SDK-style
  csproj files. Use when updating, adding, or removing NuGet packages in projects that
  use packages.config, have old-style csproj format (ToolsVersion attribute), or target
  .NET Framework without SDK-style project format. Also triggers for "nuget update",
  "packages.config", "update package in old project", or "HintPath" tasks.
metadata:
  traits: (.NET|CSharp|VisualBasic)&DotNetFramework
  discovery: lazy
---

# Legacy .NET Framework Package Management

## Overview

Manage NuGet packages in old-style .NET Framework projects where packages use `packages.config` (classic NuGet format) or `PackageReference` in non-SDK-style csproj files.

**This skill is different from `managing-package-references`** which handles SDK-style projects with `PackageReference` and Central Package Management (CPM). Legacy .NET Framework projects have different package management mechanics.

## Detecting Package Management Format

Before modifying packages, determine which format the project uses:

| Indicator | Format | Management Approach |
|-----------|--------|-------------------|
| `packages.config` file in project directory | Classic NuGet | Edit `packages.config` XML + update HintPath in csproj |
| `<PackageReference>` in csproj WITHOUT `Sdk` attribute on `<Project>` | PackageReference in old-style | Edit version in csproj XML directly |
| `<Reference>` with `<HintPath>` containing `packages\` path | Classic NuGet (assembly reference) | Update HintPath when package version changes |
| No packages.config AND no PackageReference | No NuGet packages | Nothing to manage |

### Quick Detection Steps

1. Check for `packages.config` in the project directory.
2. If not found, check csproj for `<PackageReference>` elements.
3. Check if csproj root is `<Project Sdk="...">` (SDK-style) or `<Project ToolsVersion="...">` (old-style).

## Workflow: packages.config Projects

### Understanding packages.config

`packages.config` is an XML file listing all NuGet packages and their versions:

```xml
<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="Newtonsoft.Json" version="13.0.1" targetFramework="net472" />
  <package id="System.Net.Http" version="4.3.4" targetFramework="net472" />
</packages>
```

The csproj file references the package assemblies via `<Reference>` with `<HintPath>`:

```xml
<Reference Include="Newtonsoft.Json, Version=13.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
  <HintPath>..\packages\Newtonsoft.Json.13.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
</Reference>
```

### Updating a Package Version

To update a package (e.g., Newtonsoft.Json from 13.0.1 to 13.0.3):

1. **Update `packages.config`**: Change the `version` attribute.
   ```xml
   <package id="Newtonsoft.Json" version="13.0.3" targetFramework="net481" />
   ```
   Also update `targetFramework` to `net481` if upgrading the project TFM.

2. **Update `<HintPath>` in csproj**: The HintPath contains the version number in the path.
   ```xml
   <!-- Before -->
   <HintPath>..\packages\Newtonsoft.Json.13.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
   <!-- After -->
   <HintPath>..\packages\Newtonsoft.Json.13.0.3\lib\net45\Newtonsoft.Json.dll</HintPath>
   ```

   ⚠️ **Important**: The `lib\{tfm}\` subfolder in the HintPath depends on which TFM the package ships for. After restore, check the actual folder name. Common patterns:
   - `lib\net45\` — works for net45 through net481
   - `lib\net472\` — specific to net472+
   - `lib\net48\` — specific to net48+
   - `lib\netstandard2.0\` — .NET Standard (works on .NET Framework 4.6.1+)

3. **Restore packages**: Run `msbuild {SolutionPath/ProjectPath} /t:Restore`. If MSBuild restore is unavailable for a packages.config solution, use `nuget restore` as a fallback.

4. **Verify HintPath**: After restore, confirm the DLL exists at the expected path. If the package ships different TFM folders for the new version, update the HintPath accordingly.

5. **Build**: Run `msbuild {SolutionPath/ProjectPath} /t:Build` to verify the project compiles.

### Adding a New Package

1. Add entry to `packages.config`:
   ```xml
   <package id="PackageName" version="1.0.0" targetFramework="net481" />
   ```

2. Add `<Reference>` to csproj with appropriate `<HintPath>`:
   ```xml
   <Reference Include="PackageName">
     <HintPath>..\packages\PackageName.1.0.0\lib\net45\PackageName.dll</HintPath>
   </Reference>
   ```

3. Run `msbuild {SolutionPath/ProjectPath} /t:Restore`. If MSBuild restore is unavailable for a packages.config solution, use `nuget restore` as a fallback.

### Removing a Package

1. Remove the `<package>` entry from `packages.config`.
2. Remove the corresponding `<Reference>` from the csproj.
3. Remove any `using` directives for the package's namespaces if no longer needed.

## Workflow: PackageReference in Old-Style csproj

Some old-style projects use `<PackageReference>` instead of `packages.config`. This is less common but valid.

### Updating a Package Version

Edit the `Version` attribute directly in the csproj:

```xml
<!-- Before -->
<PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
<!-- After -->
<PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
```

Then run `msbuild {SolutionPath/ProjectPath} /t:Restore` so restore uses MSBuild for old-style projects.

### Adding a New Package

Add a `<PackageReference>` element to an `<ItemGroup>`:

```xml
<ItemGroup>
  <PackageReference Include="PackageName" Version="1.0.0" />
</ItemGroup>
```

⚠️ **Do NOT use `dotnet add package`** — it may attempt to convert the project to SDK-style format or produce incorrect XML for old-style projects.

### Removing a Package

Remove the `<PackageReference>` element from the csproj.

## Key Differences from SDK-Style Package Management

| Feature | Legacy (this skill) | SDK-Style (`managing-package-references`) |
|---------|-------------------|-----------------------------------------|
| Package file | `packages.config` | None (inline in csproj) |
| Version location | `packages.config` + HintPath | `<PackageReference Version="...">` |
| Central Package Management | Not supported | Supported via `Directory.Packages.props` |
| `dotnet add package` | Do NOT use | Recommended |
| Assembly references | Explicit `<Reference>` with HintPath | Automatic |
| Restore command | `msbuild /t:Restore` (`nuget restore` fallback for packages.config when needed) | `dotnet restore` |
| Package folder | `packages/` at solution root | Global cache (`~/.nuget/packages/`) |

## Common Issues

### HintPath version mismatch after package update

**Symptom**: Build error — assembly not found.
**Cause**: `packages.config` version was updated but `<HintPath>` in csproj still points to old version.
**Fix**: Update the version number in the HintPath to match the new package version.

### Package not compatible with target framework

**Symptom**: NuGet restore warning about package not supporting target framework.
**Cause**: Package doesn't have a compatible TFM folder.
**Fix**: Find a compatible version of the package, or check if a newer version supports net481.

### Mixed package management in solution

**Symptom**: Some projects use `packages.config`, others use `PackageReference`.
**Cause**: Projects were created at different times or partially migrated.
**Fix**: Handle each project according to its format. Do NOT convert between formats during a Framework version upgrade.

## Build Validation

After package changes, always build with `msbuild`:

```powershell
msbuild {SolutionPath} /t:Build /p:Configuration=Debug
```

Or using the dotnet wrapper:

```powershell
dotnet msbuild {SolutionPath} /t:Build /p:Configuration=Debug
```
