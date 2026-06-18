---
name: managing-target-frameworks
description: >
  Manages target frameworks in .NET project files (.csproj, .vbproj, .fsproj). Handles adding,
  removing, replacing, and upgrading target frameworks, including converting between single and
  multi-targeting. Use when user mentions "add TFM", "remove TFM", "retarget", "upgrade target
  framework", "change framework version", "multi-target", "switch to net8.0/net9.0/net10.0", or
  modifies TargetFramework/TargetFrameworks properties.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Manage Project Target Frameworks

## Related Skills
| Action | Skill |
|--------|-------|
| Add/update package references or resolve NuGet version conflicts | **managing-package-references** |
| Modify project properties | **modifying-project-properties** |

Defer to these skills for package versions, CPM, and property edits.

## Workflow

Track progress using this checklist:

```
Task Progress:
- [ ] Step 1: Locate target framework property
- [ ] Step 2: Modify target frameworks
- [ ] Step 3: Restore and resolve errors
- [ ] Step 4: Apply conditional compilation (if needed)
```

### Step 1: Locate the Target Framework Property

Before making changes, determine where the `TargetFramework` or `TargetFrameworks` property is defined. It may be in the project file, a `Directory.Build.props`, or another imported MSBuild file. Use the **modifying-project-properties** skill to locate and understand the property definition.

### Step 2: Modify Target Frameworks

Determine the intended change from user context and apply the matching scenario:

| User intent | Current state | Action |
|-------------|---------------|--------|
| Replace/upgrade an existing TFM with another | Single or multi-targeted | **Replace** the specified TFM |
| Add support for an additional TFM | Single `TargetFramework` | **Add multi-targeting** (rename property to plural `TargetFrameworks`, keep existing TFM, add new one) |
| Add support for an additional TFM | Already uses `TargetFrameworks` | **Append** new TFM to existing list |
| Remove/drop a TFM | Multi-targeted | **Remove** from list (revert to singular if one remains) |

**Replace a TFM** — swap the value in place; preserve the singular/plural property name:

```xml
<!-- Single-targeted: stays singular -->
<TargetFramework>OldTFM</TargetFramework>
<!-- After -->
<TargetFramework>NewTFM</TargetFramework>
```

```xml
<!-- Multi-targeted: replace only the specific TFM -->
<TargetFrameworks>OldTFM;OtherTFM</TargetFrameworks>
<!-- After -->
<TargetFrameworks>NewTFM;OtherTFM</TargetFrameworks>
```

**Add multi-targeting** — convert singular `TargetFramework` to plural `TargetFrameworks` and add the new TFM:

```xml
<!-- Before -->
<TargetFramework>ExistingTFM</TargetFramework>

<!-- After -->
<TargetFrameworks>ExistingTFM;NewTFM</TargetFrameworks>
```

**Append to existing multi-targeted project** — add the new TFM to the existing list:

```xml
<!-- Before -->
<TargetFrameworks>TFM1;TFM2</TargetFrameworks>

<!-- After -->
<TargetFrameworks>TFM1;TFM2;NewTFM</TargetFrameworks>
```

**Remove a TFM** — remove the TFM from the list; revert to singular `TargetFramework` if only one remains:

```xml
<!-- Multiple TFMs remain: stays plural -->
<TargetFrameworks>TFM1;TFM2;TFMToRemove</TargetFrameworks>
<!-- After -->
<TargetFrameworks>TFM1;TFM2</TargetFrameworks>
```

```xml
<!-- One TFM remains: revert to singular -->
<TargetFrameworks>TFM1;TFMToRemove</TargetFrameworks>
<!-- After -->
<TargetFramework>TFM1</TargetFramework>
```

Order TFMs newest to oldest when multiple TFMs are present — MSBuild uses the first TFM as the default for IDE operations and `dotnet run`, so the newest framework provides the best developer experience.

### Step 3: Resolve Errors

Restore first and resolve all NUxxxx errors before building. Then build and resolve MSBxxxx/CSxxxx errors. Common multi-targeting errors:

| Error | Cause | Resolution |
|-------|-------|------------|
| `NU1202: Package not compatible with <TFM>` | Package doesn't support added TFM | Check for a newer package version that supports the TFM, or add a conditional `<PackageReference>` (see below) |
| `NU1202: PackageA -> PackageB -> requires <TFM>` | Transitive dependency incompatible | Update the top-level package, or add a conditional reference excluding it for the incompatible TFM |
| `MSB3644: Reference assemblies not found` | Targeting pack not installed | Advise the user to install the required targeting pack or SDK — the LLM cannot install SDKs |
| `CS0246: Type could not be found` | API not available in added TFM | Add a `#if` directive for TFM-specific code, or find a cross-platform alternative API |
| `CS1061: Type does not contain member` | API differs between TFMs | Find a replacement method or overload available in the new TFM. If no equivalent exists, add a `#if` directive for the specific member call |

**Multi-targeting-specific pattern** — use conditional package references when no single package version works for all TFMs:
```xml
<ItemGroup Condition="'$(TargetFramework)' == 'SpecificTFM'">
  <PackageReference Include="PackageName" />
</ItemGroup>
```

### Step 4: Apply Conditional Compilation (If Needed)

Use `#if` directives **only when APIs genuinely differ** between TFMs. Not every difference needs conditionals — some just need a different overload or parameter. Overusing `#if` makes code harder to maintain and review.

**Preprocessor symbol convention:** MSBuild automatically defines preprocessor symbols for each target framework. The symbol name is the TFM with `.` replaced by `_`, uppercased (e.g., `net10.0` → `NET10_0`, `net48` → `NET48`, `netstandard2.0` → `NETSTANDARD2_0`). These symbols do not need to be declared manually — they are available in any `#if` directive.

```csharp
#if NET10_0_OR_GREATER
    // API available only in .NET 10+
#elif NETFRAMEWORK
    // .NET Framework fallback
#endif
```

Use `_OR_GREATER` suffix symbols (e.g., `NET8_0_OR_GREATER`) when the code applies to a minimum version rather than an exact version. Use `NETFRAMEWORK` for any .NET Framework target, `NETSTANDARD` for any .NET Standard target.

## Anti-Patterns

- ❌ Using singular `TargetFramework` with multiple TFMs — MSBuild silently ignores all but the first value
- ❌ Wrapping every API call in `#if` when only some APIs differ — creates unmaintainable code with unnecessary divergence
- ❌ Stopping after the first TFM builds — each TFM can have different API surfaces, so verify all TFMs compile
- ❌ Editing the project file directly without checking if the property is inherited from `Directory.Build.props` — changes would be overridden by the import
- ❌ Converting `TargetFramework` to `TargetFrameworks` when only a TFM replacement was requested — changes build behavior unnecessarily
- ❌ Leaving `TargetFrameworks` (plural) when only one TFM remains — causes MSBuild to produce a TFM-specific output folder structure instead of a flat `bin/` layout

## Success Criteria

- [ ] TFM replaced in place without changing singular/plural when only a replacement was requested
- [ ] `TargetFramework` changed to `TargetFrameworks` (plural) when adding multi-targeting
- [ ] New TFM appended correctly when project already uses `TargetFrameworks`
- [ ] `TargetFrameworks` reverted to singular `TargetFramework` when only one TFM remains after removal
- [ ] TFMs semicolon-separated, newest to oldest
- [ ] `#if` directives only where APIs genuinely differ
- [ ] All TFMs build successfully

## Resources
- [Multi-targeting](https://learn.microsoft.com/en-us/nuget/create-packages/multiple-target-frameworks-project-file)
- [MSBuild Multi-targeting](https://learn.microsoft.com/en-us/visualstudio/msbuild/net-sdk-multitargeting)
- [Target Frameworks](https://learn.microsoft.com/en-us/dotnet/standard/frameworks)
