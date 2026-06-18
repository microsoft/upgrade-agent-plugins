---
name: modifying-project-properties
description: >
  Modifies .NET project properties in PropertyGroup elements within .csproj, .vbproj, and
  Directory.Build.props files. Handles TargetFramework, LangVersion, Nullable, OutputType,
  TreatWarningsAsErrors, and other MSBuild configuration settings. Use when asked to "change
  TargetFramework", "update project settings", "enable nullable", "set LangVersion", or modify
  any build property. Also triggers for Directory.Build.props changes, conditional PropertyGroup
  handling, and centralized vs project-specific property decisions.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Project Properties Modification

## Overview

Modify .NET project properties in `<PropertyGroup>` elements. Properties may be defined across multiple files in the MSBuild import chain, so always discover where a property is defined before modifying it — changing the wrong file creates confusing overrides or has no effect.

**Common properties:** TargetFramework, LangVersion, Nullable, OutputType, AssemblyName, TreatWarningsAsErrors, ImplicitUsings

## Import Chain

Properties can be defined in multiple locations, evaluated in this order:

```
SDK imports → Directory.Build.props → Project file → Directory.Build.targets → SDK imports
```

| Location | Purpose |
|---|---|
| Directory.Build.props | Centralized defaults for all projects |
| .csproj/.vbproj | Project-specific settings and overrides |
| Directory.Build.targets | Post-evaluation defaults |
| Explicit `<Import>` | Custom shared configuration |

Later definitions override earlier ones, which is why project-file properties override Directory.Build.props values.

## Workflow

### Step 1: Discover Import Chain

```bash
get_project_dependencies <path-to-csproj>
```

This reveals which .props/.targets files are imported and where packages are referenced. Always run this first — properties are often not where you expect.

Supplement with direct file inspection:

```bash
# Find all props files
find . -name "Directory.Build.props"
# Search for a specific property across all project files
grep -r "TargetFramework" . --include="*.csproj" --include="*.vbproj" --include="*.fsproj" --include="*.props"
```

### Step 2: Find the Property

Search each file in the import chain for the target property. Pay attention to `Condition` attributes — they limit when a property applies:

```xml
<!-- This only applies in Debug builds -->
<PropertyGroup Condition="'$(Configuration)'=='Debug'">
  <Optimize>false</Optimize>
</PropertyGroup>
```

### Step 3: Choose Modification Location

| Scenario | Action | Why |
|---|---|---|
| Property in Directory.Build.props | Modify there | Respect centralization; changing elsewhere creates a confusing override |
| Property in project file | Modify project file | It's an intentional override |
| Property doesn't exist | Ask user | User decides if it should be centralized or project-specific |

**Centralization guidance:**
- **Usually centralized:** TargetFramework, LangVersion, Nullable, TreatWarningsAsErrors
- **Usually project-specific:** OutputType, AssemblyName, RootNamespace

### Step 4: Apply the Change

Use `str_replace` on the correct file.

When modifying conditional properties:
- Understand whether the property should remain conditional or become unconditional
- If removing a condition, preserve other properties in that PropertyGroup
- If the property appears in multiple conditional groups, decide whether to update all or extract to unconditional

### Step 5: Report Impact

Tell the user which file was modified and the blast radius:

```
✅ Updated TargetFramework to net8.0 in Directory.Build.props
⚠️  This affects ALL projects in the repository.
```

```
Task Progress:
- [ ] Step 1: Discover import chain with get_project_dependencies
- [ ] Step 2: Find existing property definition(s)
- [ ] Step 3: Determine correct modification location
- [ ] Step 4: Apply the change
- [ ] Step 5: Report impact to user
```

## Examples

### Centralized Property Update

**Task:** Update TargetFramework to net8.0

1. Run `get_project_dependencies` → find Directory.Build.props in import chain
2. Find `<TargetFramework>net48</TargetFramework>` in Directory.Build.props
3. Modify Directory.Build.props (centralized location):
   ```
   str_replace Directory.Build.props
   old: <TargetFramework>net48</TargetFramework>
   new: <TargetFramework>net8.0</TargetFramework>
   ```
4. Report: "Updated in Directory.Build.props — affects all projects"

### Project-Specific Override

**Task:** Set LangVersion to 12.0 for ExperimentalProject.csproj

1. Find `<LangVersion>11.0</LangVersion>` in Directory.Build.props
2. Find `<LangVersion>preview</LangVersion>` override in ExperimentalProject.csproj
3. Modify the project file (respect the intentional override):
   ```
   str_replace ExperimentalProject.csproj
   old: <LangVersion>preview</LangVersion>
   new: <LangVersion>12.0</LangVersion>
   ```
4. Report: "Updated in ExperimentalProject.csproj — overrides default (11.0) from Directory.Build.props"

### Adding a New Property

**Task:** Enable nullable reference types

1. Search all files — property not found
2. Ask user: "Apply to all projects (Directory.Build.props) or just this project?"
3. User chooses centralized → add inside existing PropertyGroup:
   ```
   str_replace Directory.Build.props
   old:   <LangVersion>11.0</LangVersion>
     </PropertyGroup>
   new:   <LangVersion>11.0</LangVersion>
       <Nullable>enable</Nullable>
     </PropertyGroup>
   ```
4. Report: "Enabled nullable in Directory.Build.props — all projects affected, expect new warnings"

### Conditional Property Modification

**Task:** Set Optimize=true unconditionally (currently conditional)

Found in Directory.Build.props:
```xml
<PropertyGroup Condition="'$(Configuration)'=='Debug'">
  <Optimize>false</Optimize>
  <DebugType>full</DebugType>
</PropertyGroup>
<PropertyGroup Condition="'$(Configuration)'=='Release'">
  <Optimize>true</Optimize>
  <DebugType>portable</DebugType>
</PropertyGroup>
```

**Option A — Extract to unconditional group** (preserves other conditional properties):
```xml
<PropertyGroup>
  <Optimize>true</Optimize>
</PropertyGroup>
<PropertyGroup Condition="'$(Configuration)'=='Debug'">
  <DebugType>full</DebugType>
</PropertyGroup>
<PropertyGroup Condition="'$(Configuration)'=='Release'">
  <DebugType>portable</DebugType>
</PropertyGroup>
```

**Option B — Update within conditions** (simpler, keeps structure):
Change `<Optimize>false</Optimize>` to `<Optimize>true</Optimize>` in Debug group only.

## Property Reference

| Category | Properties |
|---|---|
| Framework/Language | TargetFramework, LangVersion, ImplicitUsings |
| Code Quality | Nullable, TreatWarningsAsErrors, WarningLevel, NoWarn |
| Output | OutputType (Exe/Library/WinExe), AssemblyName, RootNamespace |
| Build | Deterministic, DebugType, Optimize |

## Red Flags

- **Never modify without discovering imports first** — the property may not be where you expect, and changing the wrong file creates silent conflicts
- **Never add a property to the project file when it exists in Directory.Build.props** — this creates a confusing override that's hard to debug
- **Never ignore Condition attributes** — modifying a conditional property without understanding the condition can break specific build configurations
- **Never assume property is in the project file** — most shared settings live in Directory.Build.props

**Watch for:** Multiple Directory.Build.props files (nearest to project wins), intentional overrides in project files, Condition attributes on PropertyGroup or individual properties.

## Troubleshooting

| Problem | Solution |
|---|---|
| Property not taking effect | Check for Condition attributes limiting when it applies; check for overrides in project file |
| Changed Directory.Build.props but one project unaffected | Project has explicit override in the project file; check for excluding Condition |
| Unexpected property value | Run `dotnet msbuild /pp` to see fully evaluated project with all imports resolved |
| Multiple Directory.Build.props — which wins? | Nearest to project file: repo root → src/ → src/MyApp/ |

## Related Skills

For package management (ItemGroup elements), see the **project-package-management** skill.
