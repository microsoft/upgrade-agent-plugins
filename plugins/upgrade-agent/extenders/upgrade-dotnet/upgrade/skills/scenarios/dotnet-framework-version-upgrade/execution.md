# Execution Stage Instructions

## Contents

- [Section 1: Before Editing Project Files](#section-1-before-editing-project-files)
- [Section 2: TFM Upgrade Mechanics](#section-2-tfm-upgrade-mechanics)
- [Section 3: Package Updates](#section-3-package-updates)
- [Section 4: Build Validation](#section-4-build-validation)

Scenario-specific execution guidance for .NET Framework version upgrade tasks.
Supplements the system `task-execution` skill — does not replace it.

---

## Section 1: Before Editing Project Files

⚠️ **If running in Visual Studio** (VS trait present / `unload_project` tool available):

Before modifying the target framework for any project:
1. Call `unload_project({projectPath})` before editing the project file.
2. Edit the `<TargetFrameworkVersion>` element for legacy projects, or `<TargetFramework>`/`<TargetFrameworks>` for SDK-style projects.
3. Call `reload_project({projectPath})` after saving the file.

This is required because VS holds a cached in-memory project model that does not reflect
on-disk changes until the project is reloaded.

If NOT in Visual Studio, skip the unload/reload calls — the file edit is sufficient.

### Example (VS)

```
1. unload_project("src/MyProject/MyProject.csproj")
2. Edit MyProject.csproj: <TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion> → <TargetFrameworkVersion>v4.8.1</TargetFrameworkVersion>
3. reload_project("src/MyProject/MyProject.csproj")
```

### Example (CLI / VS Code)

```
1. Edit MyProject.csproj: <TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion> → <TargetFrameworkVersion>v4.8.1</TargetFrameworkVersion>
```

---

## Section 2: TFM Upgrade Mechanics

### Legacy project file (most common)

Legacy .NET Framework projects use `<TargetFrameworkVersion>` in a `<PropertyGroup>`:

```xml
<PropertyGroup>
  <TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>
</PropertyGroup>
```

**Change to:**

```xml
<PropertyGroup>
  <TargetFrameworkVersion>v4.8.1</TargetFrameworkVersion>
</PropertyGroup>
```

**Important**: The value uses `v` prefix and dot-separated version (`v4.8.1`), NOT the TFM short name (`net481`).

#### How to identify legacy projects

Legacy project files have these characteristics:
- Root element: `<Project ToolsVersion="..." ...>` (has `ToolsVersion` attribute)
- Explicit import of `Microsoft.CSharp.targets` or similar language targets
- Explicit `<Compile Include="...">` items for each source file
- May have `packages.config` in the project directory

### SDK-style project file (uncommon for .NET Framework)

SDK-style projects targeting .NET Framework use `<TargetFramework>`:

```xml
<PropertyGroup>
  <TargetFramework>net472</TargetFramework>
</PropertyGroup>
```

**Change to:**

```xml
<PropertyGroup>
  <TargetFramework>net481</TargetFramework>
</PropertyGroup>
```

#### How to identify SDK-style projects

- Root element: `<Project Sdk="Microsoft.NET.Sdk">` (has `Sdk` attribute)
- No explicit `<Compile>` items (uses globbing)
- No `<Import>` of targets files

### Existing multi-targeting (rare)

Do not introduce new multi-targeting. If an SDK-style project already multi-targets including a Framework TFM:

```xml
<TargetFrameworks>net472;netstandard2.0</TargetFrameworks>
```

Replace only the Framework TFM: `net472` → `net481`; preserve the non-Framework targets.

---

## Section 3: Package Updates

If the assessment or plan identified NuGet packages that need updating or retargeting for net481 compatibility:

1. **Load the `managing-legacy-dotnet-packages` skill** for detailed instructions.
2. Follow the skill's workflows for the project's package management format:
   - **packages.config**: Update package versions when needed, retarget `targetFramework` attributes to `net481`, restore/reinstall packages as needed, and verify HintPath values.
   - **PackageReference in legacy project files**: Edit version attribute directly in project XML.
3. Run `msbuild {SolutionPath} /t:Restore /p:Configuration=Debug` after package metadata or version changes so restore uses MSBuild for old-style projects. If MSBuild restore is unavailable for a packages.config solution, use `nuget restore` as a fallback.

### Do NOT Use

- `dotnet add package` — may not work correctly with legacy project files.
- `managing-package-references` skill — designed for SDK-style projects with CPM support.
- `convert_project_to_sdk_style` tool for default Framework version upgrades — use it only if the user explicitly requested SDK-style conversion and that conversion was planned separately.

---

## Section 4: Build Validation

After completing TFM and package changes, validate with a build.

### Old-style projects

```powershell
msbuild {SolutionPath} /t:Build /p:Configuration=Debug
```

Or using the dotnet wrapper:

```powershell
dotnet msbuild {SolutionPath} /t:Build /p:Configuration=Debug
```

### SDK-style projects (if any)

```powershell
dotnet build {ProjectPath}
```

### Build Failure Troubleshooting

| Error Pattern | Likely Cause | Fix |
|---------------|-------------|-----|
| Missing assembly reference | Package version incompatible with net481 | Update package to net481-compatible version |
| `CS0234` / `CS0246` (type not found) | Namespace moved in newer framework version | Add correct `using` or assembly reference |
| HintPath not found | Package restored to different path | Update HintPath in csproj to match new package version path |
| `MSB3644` (reference assemblies not found) | .NET Framework 4.8.1 Developer Pack not installed | Install from https://go.microsoft.com/fwlink/?linkid=2088631 |

### Final Validation

After successful build:
1. Run existing unit tests if present (`msbuild /t:Test` or test runner).
2. Record build result in the task's `task.md`.
3. Mark task as complete.
