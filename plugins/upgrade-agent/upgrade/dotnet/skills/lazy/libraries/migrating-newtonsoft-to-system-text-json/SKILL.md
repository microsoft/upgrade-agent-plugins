---
name: migrating-newtonsoft-to-system-text-json
description: >
  Migrates .NET projects from Newtonsoft.Json to System.Text.Json, updating package references,
  code files, and handling API differences. Use when asked to "migrate Newtonsoft", "switch to
  System.Text.Json", "replace Newtonsoft.Json", or "upgrade JSON library". Triggers for
  .csproj/.vbproj files referencing Newtonsoft.Json and .cs/.vb files using Newtonsoft.Json
  namespaces. Also applies when modernizing .NET dependencies or removing third-party JSON
  libraries.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Newtonsoft.Json to System.Text.Json Migration

## Overview

Migrate .NET projects from `Newtonsoft.Json` to `System.Text.Json`, including package references, code files, and configuration changes while preserving application behavior.

## Scope Determination

- If a single project is specified, migrate that project only.
- If a solution is specified, migrate all projects in the solution referencing `Newtonsoft.Json`.
- NuGet package names, assembly names, and project names are **case-insensitive** — account for this when searching for and removing dependencies.

## Workflow

Complete all steps in order without pausing between them. Continue until the migration is finished or user input is genuinely required. Ordering matters because later steps depend on earlier ones (e.g., code updates rely on package references being correct first).

```
Migration Progress:
- [ ] Step 1: Update package dependencies
- [ ] Step 2: Update code files
- [ ] Step 3: Validate migration
- [ ] Step 4: Build verification
```

### Step 1: Update Package Dependencies

For each project with an **explicit** dependency on `Newtonsoft.Json` in the project file or imported MSBuild targets (skip projects that only receive it transitively to avoid adding unnecessary new package references):

1. Remove the `Newtonsoft.Json` package reference and assembly reference from the project file.
2. Add a `System.Text.Json` package reference with a version supporting the project's target framework. Use tools to determine the best version; fall back to manual determination if unavailable.
3. If using Central Package Management (CPM):
   - Remove the `Newtonsoft.Json` `PackageVersion` entry from `Directory.Packages.props`.
   - Add `System.Text.Json` `PackageReference` without a version in project files.
   - Add a `System.Text.Json` `PackageVersion` entry to `Directory.Packages.props`.

### Step 2: Update Code Files

Update code files in affected projects **and** projects that depend on them (transitive dependents may use `Newtonsoft.Json` types received through project references):

1. Search for all code files using `Newtonsoft.Json` — prefer search tools when available, passing root folders for all affected projects.
2. Replace `Newtonsoft.Json` API usage with `System.Text.Json` equivalents. Preserve business logic, comments, and formatting. Never add placeholder code.
3. Handle using statements correctly:
   - If a file still uses Newtonsoft API after partial conversion, replace `Newtonsoft.Json` usings with appropriate `System.Text.Json` usings.
   - If no Newtonsoft API remains after conversion, remove the usings entirely — do not replace them with `System.Text.Json` usings.
   - If no `Newtonsoft.Json` usings existed originally, do not add `System.Text.Json` usings.
   - Skip comments and string literal constants when checking for Newtonsoft API usage.
4. Add namespace-specific usings when replacement types live in sub-namespaces. For example, replacing `JsonPropertyAttribute` with `JsonPropertyNameAttribute` requires `using System.Text.Json.Serialization;` because the type moved from the root namespace to a child namespace.
5. Track any code that cannot be cleanly converted or has potential runtime behavior changes — flag these for the user.

### Step 3: Validate Migration

Search all affected projects for any remaining `Newtonsoft.Json` references. If any are found, return to Step 2. Repeat until no references remain. This loop catches references missed in large solutions where transitive dependencies can hide usages.

### Step 4: Build Verification

Build all modified projects. Fix all build errors before proceeding — iterating until the build succeeds ensures the migration is mechanically correct.

## API Differences

### Key Behavioral Differences

| Behavior | Newtonsoft.Json | System.Text.Json |
|----------|----------------|------------------|
| Property name matching | Case-insensitive by default | Case-sensitive by default — use `PropertyNameCaseInsensitive` if needed |
| Character escaping | Permissive | Escapes more characters for XSS protection |
| Comments/trailing commas | Allowed by default | Requires `ReadCommentHandling` and `AllowTrailingCommas` |
| Numbers in quotes | Accepted | Requires `NumberHandling` configuration |
| Quote style | Single quotes and unquoted names allowed | Requires double quotes per RFC 8259 |

### Common Type Mappings

| Newtonsoft.Json | System.Text.Json |
|-----------------|------------------|
| `JsonPropertyAttribute` | `JsonPropertyNameAttribute` (in `System.Text.Json.Serialization`) |
| `NullValueHandling.Ignore` | `DefaultIgnoreCondition` global option |
| `[JsonConstructor]` | `[JsonConstructor]` (same attribute exists) |
| `PreserveReferencesHandling` | `ReferenceHandler` global setting |
| `TypeNameHandling` | `JsonDerivedTypeAttribute` for polymorphism |
| `JsonConvert.SerializeObject()` | `JsonSerializer.Serialize()` |
| `JsonConvert.DeserializeObject()` | `JsonSerializer.Deserialize()` |

### Target Framework Support

System.Text.Json is included in:
- .NET Core 3.1+
- .NET Standard 2.0+ (via NuGet package)
- .NET Framework 4.6.2+ (via NuGet package)

## Success Criteria

- No `Newtonsoft.Json` references remain in affected projects
- All modified projects build without errors
- Any unconvertible patterns or behavioral changes flagged for the user
