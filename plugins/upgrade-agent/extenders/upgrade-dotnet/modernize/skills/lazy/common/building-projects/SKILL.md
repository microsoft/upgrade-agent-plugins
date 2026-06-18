---
name: building-projects
description: >
  Build tool selection and orchestration for .NET projects during modernization upgrades.
  Use this skill whenever the agent modifies code files, project files, packages, or
  configuration and needs to validate the build — which is virtually every upgrade task.
  Covers: choosing between `dotnet build` and `msbuild.exe`, restore strategy, targeted vs
  solution builds, resolving MSBuild errors (MSB3086, MSB4019, NETSDK1005, etc.), handling
  multi-targeting scenarios, resource generation failures with .resx files, WPF/WinForms/XAML
  compilation issues, SDK-style vs legacy csproj differences, and recovering when a build fails.
  Also use when diagnosing why a project compiles under one tool but not another, or when
  deciding build scope (single project vs full solution) during iterative migration work.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
  autoMatch: true
---

# Building Projects

## Overview

During .NET modernization, the choice of build tool is not trivial. `dotnet build` and `msbuild.exe`
are not interchangeable — they have different capabilities, different SDK resolution paths, and
different behavior with legacy project features. This skill encodes the expert decision logic so
the agent picks the right tool on the first attempt and recovers intelligently when a build fails.

## Related Skills

| Action | Skill |
|--------|-------|
| Convert legacy project files to SDK-style format | **converting-to-sdk-style** |
| Add/update/remove target frameworks | **managing-target-frameworks** |
| Add/update package references or resolve NuGet version conflicts | **managing-package-references** |
| Modify project properties | **modifying-project-properties** |

Defer to these skills for project format conversion, TFM changes, package management, and property edits.

## Repo-Level Build Skills Take Priority

If the repository contains a custom build skill (e.g., in `.github/skills/`, `.copilot/skills/`,
or a project-level `BUILD.md` with build instructions), defer to that skill for project-specific
build decisions. This skill provides general .NET modernization build logic and should serve as
a fallback when no repo-specific guidance exists.

## IDE Build Tools Take Preference When Available

If the agent is running inside an IDE (Visual Studio, VS Code, Rider) that exposes build-related
tools — such as `build_project`, `build_solution` or similar MCP/Copilot tools —
prefer those over shelling out to the command line. IDE build tools respect the user's local
configuration and surface diagnostics where the user can click-to-navigate.

Fall back to this skill's CLI patterns when the IDE doesn't expose a build tool, the IDE build
tool fails with insufficient error output, the agent needs fine-grained control (targeting a
specific TFM, adjusting verbosity, choosing between `dotnet build` and `msbuild.exe`), or the
agent needs to capture structured build output for automated validation.

## Workflow

Track progress using this checklist:

```
Task Progress:
- [ ] Step 1: Determine the right build tool
- [ ] Step 2: Execute the build
- [ ] Step 3: Diagnose and recover from failures (if any)
- [ ] Step 4: Validate the build output
```

### Step 1: Determine the Right Build Tool

#### Default: Start with `dotnet build`

For SDK-style projects targeting modern .NET only, `dotnet build` is the correct default. It
ships with the .NET SDK, handles NuGet restore implicitly, and works cross-platform.

#### When to switch to `msbuild.exe`

Escalate to the full Visual Studio MSBuild (`msbuild.exe`) when ANY of these conditions apply:

1. **The project has `.resx` files containing images, icons, or binary resources.**
   `dotnet build` uses a portable resource generator that cannot process embedded images.
   Symptom: `MSB3086`, `MSB3552`, or `LC.exe` errors.

2. **The project is WPF or targets `net*-windows` with XAML.**
   WPF's markup compiler requires the full Windows SDK targets that only ship with VS MSBuild.
   Symptom: `MC1000`, `XDG0008`, or missing `Microsoft.WinFX.targets`.

3. **The project is WinForms with designer-generated resources.**
   The `ResGen.exe` that ships with the .NET SDK may lack support for System.Drawing types
   referenced in `.resx` files.

4. **The project multi-targets and includes a `net472` (or any `netXXX` <= `net48`) TFM.**
   Building classic .NET Framework TFMs requires reference assemblies and the full MSBuild
   toolset. `dotnet build` can handle this IF `Microsoft.NETFramework.ReferenceAssemblies`
   is in the project or `Directory.Build.props`, but frequently fails with `NETSDK1005`.

5. **The project uses COM references, VSIX packaging, or T4 templates.**
   These rely on VS-specific targets/tasks that the .NET SDK MSBuild doesn't include.

6. **The solution contains C++/CLI (`vcxproj`) projects.**
   The .NET CLI cannot build these at all.

7. **Legacy (non-SDK-style) project file that hasn't been converted yet.**
   If the project still uses `<Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets">`
   rather than `<Project Sdk="Microsoft.NET.Sdk">`, only `msbuild.exe` will work.

#### Decision flowchart

```
Is the project file SDK-style?
├── NO → Use msbuild.exe (full VS). Stop.
└── YES
    ├── Does it target any net4xx TFM?
    │   ├── YES → Is Microsoft.NETFramework.ReferenceAssemblies present?
    │   │   ├── YES → Try dotnet build first, fall back to msbuild.exe on failure
    │   │   └── NO → Use msbuild.exe (or add the ReferenceAssemblies package first)
    │   └── NO
    │       ├── Does it contain .resx with embedded images/icons?
    │       │   ├── YES → Use msbuild.exe
    │       │   └── NO
    │       │       ├── Is it WPF / has XAML pages?
    │       │       │   ├── YES → Use msbuild.exe
    │       │       │   └── NO → Use dotnet build ✓
    │       └── COM refs / VSIX / T4 / vcxproj?
    │           ├── YES → Use msbuild.exe
    │           └── NO → Use dotnet build ✓
```

### Step 2: Execute the Build

#### Always Restore During Migration

During modernization, NuGet packages change constantly — versions get bumped, packages get
swapped, new ones added, old ones removed. A stale `obj/project.assets.json` is one of the
most common causes of phantom build failures.

**Default behavior: always let restore run.**

- For `dotnet build`: restore runs by default — do not add `--no-restore` during migration.
  Package references change frequently, and skipping restore causes phantom build failures.
- For `msbuild.exe`: use `msbuild /restore` (or `/r`) to run NuGet restore before building.
  This is especially important when already using `msbuild.exe` for the build — mixing
  `dotnet restore` as a separate step with `msbuild /build` can cause resolver mismatches.

**When restore can be skipped:** Only when the current migration step modified nothing but
`.cs` files — no `*proj`, `Directory.Build.props`, `Directory.Packages.props`, or
`nuget.config` was touched. If in doubt, restore. The cost is a few seconds; the cost of
a stale restore is a misleading build result.

#### Build Scope: Targeted vs Full Solution

Building the entire solution on every change is too slow for iterative migration work.
Use two tiers:

**Targeted project build (default during iterative work):**
When the agent modifies a project or its files, build only that specific project:

```sh
dotnet build <specific-project.csproj> -r
msbuild.exe <specific-project.csproj> /restore /t:Build /p:Configuration=Release
```

This gives fast feedback (seconds, not minutes) on whether the migration change compiled.
The agent is iterating — it needs signal on its change, not the entire dependency graph.

**Full solution build (final validation only):**
Build the entire solution when:
- The agent is about to mark a task as complete
- A batch of related migration tasks has finished
- The migration step changed something that could ripple across projects (shared interfaces,
  public API changes, package updates consumed by multiple projects)

```sh
dotnet build <solution.sln> -r
msbuild.exe <solution.sln> /restore /t:Build /p:Configuration=Release
```

Do NOT default to solution builds for every change. Reserve them as a gate check.

#### Build Patterns

**Simple SDK build (happy path):**

```sh
dotnet build <project.csproj> -r
```

**MSBuild build:**

```sh
msbuild.exe <project.csproj> /restore /t:Build /p:Configuration=Release /v:minimal
```

**Clean build (when incremental build is suspect):**

```sh
dotnet build <project.csproj> --no-incremental
```

Or for MSBuild:

```sh
msbuild.exe <project.csproj> /restore /t:Clean;Build /p:Configuration=Release
```

**Debugging restore failures in isolation:**
When restore itself needs diagnosing, run it separately:

```sh
dotnet restore <project.csproj> --verbosity detailed
```

Then build without restore to isolate the compilation phase:

```sh
dotnet build <project.csproj> --no-restore
```

This is a diagnostic pattern only — not the default workflow.

#### Caching Build Tool Decisions

After determining the right build tool for a project, save the decision to
`scenario-instructions.md` so it doesn't need to be re-derived on every build.

Add or update a `## Build Tool Decisions` section:

```markdown
## Build Tool Decisions
- **MyWebApp.csproj**: msbuild.exe (non-SDK-style, System.Web references)
- **Common.csproj**: dotnet build (SDK-style, no special requirements)
- **Tests.csproj**: dotnet build (SDK-style after conversion)
```

On subsequent builds, check this section first:
- If the project is listed → use the cached decision
- If not listed or the project changed → re-read this skill and determine the right tool

### Step 3: Diagnose and Recover from Failures

When a build fails, analyze the error codes and take targeted action rather than blindly retrying.

**Load [references/error-codes.md](references/error-codes.md)** for the full error catalog
with specific recovery actions per error code.

Key recovery principles:

- Capture full build output (use `-v:detailed` or `/v:diag` on retry for more info)
- Parse for specific error codes, not just "build failed"
- Distinguish between compilation errors (CS\*), MSBuild errors (MSB\*), SDK errors (NETSDK\*),
  and NuGet errors (NU\*)
- Report which project within a solution failed (not just "the solution failed")

Do NOT:
- Retry the same command more than once without changing something
- Switch tools without understanding why the first tool failed
- Suppress warnings with `/nowarn` without the user's explicit approval
- Downgrade `TreatWarningsAsErrors` without flagging it

### Step 4: Validate the Build Output

After a successful build during migration, verify:

1. **All warnings fixed** — fix all warnings in the projects being built, not just new ones introduced by this step
2. **Output assembly exists** in the expected `bin/` path
3. **Target framework is correct** — the output folder should match the target TFM (e.g.,
   `net10.0/`), not the old TFM
4. **No implicit fallbacks** — if the project was supposed to drop a TFM, confirm it's gone

## Locating MSBuild

When the decision is `msbuild.exe`, the agent must locate it reliably.

### On Windows

**Priority 1 — `VSINSTALLDIR` environment variable:**
If the agent is running inside Visual Studio or was launched from a VS Developer Command
Prompt, the `VSINSTALLDIR` environment variable is already set and points to the correct
VS installation. Use it directly:

```cmd
"%VSINSTALLDIR%\MSBuild\Current\Bin\MSBuild.exe"
```

This is the preferred approach — it matches the user's active VS context and avoids
picking a different installation than the one they're working with.

**Priority 2 — `vswhere.exe`:**
If `VSINSTALLDIR` is not set (agent running outside VS), use `vswhere.exe`:

```cmd
"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" ^
  -latest -requires Microsoft.Component.MSBuild ^
  -find MSBuild\**\Bin\MSBuild.exe
```

**Priority 3 — well-known paths:**
If neither is available, fall back to well-known paths under `Program Files`.

### On CI / Linux / macOS

Full `msbuild.exe` is generally not available outside Windows+VS. If the project requires it,
flag it as a Windows-only build requirement or suggest restructuring to remove the dependency
(e.g., convert `.resx` to use `LogicalName` with precompiled resources, or extract the WPF layer).

## Multi-Targeting Considerations

Projects that multi-target (e.g., `<TargetFrameworks>net472;net10.0</TargetFrameworks>`) during
a transitional migration phase need special handling:

- `dotnet build` builds ALL TFMs by default. To build just one:

  ```sh
  dotnet build -f net10.0
  ```

- Build the NEW target first to validate migration changes, then optionally build the old target
  to confirm backward compatibility.
- If the old TFM build is no longer needed (migration complete), recommend removing it from
  `<TargetFrameworks>` — defer to the **managing-target-frameworks** skill for the actual edit.

## Anti-Patterns

- ❌ Retrying the same build command without changing anything — wastes time and produces identical errors
- ❌ Switching from `dotnet build` to `msbuild.exe` (or vice versa) without understanding the root cause of the failure
- ❌ Suppressing warnings with `/nowarn` or downgrading `TreatWarningsAsErrors` without explicit user approval
- ❌ Batching all build validation at the end of a migration — invoke this skill after EVERY discrete change that needs build validation; catching failures early keeps the error surface small
- ❌ Running a full solution build when only one project changed — use targeted project builds for faster feedback
- ❌ Ignoring which project within a solution failed — always report the specific project name

## Success Criteria

- [ ] Correct build tool selected based on project characteristics (SDK-style, TFMs, resource types)
- [ ] Build executed with appropriate configuration and verbosity
- [ ] Build errors diagnosed by error code category (CS\*, MSB\*, NETSDK\*, NU\*)
- [ ] Recovery actions targeted to root cause, not blind retries
- [ ] Output assembly exists in the correct TFM-specific `bin/` path
- [ ] All warnings fixed in touched projects — not just new ones, all of them
- [ ] Multi-target builds validated per-TFM when applicable

## Resources

- [dotnet build command](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-build)
- [MSBuild command-line reference](https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild-command-line-reference)
- [SDK-style project overview](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview)
- [Multi-targeting](https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/cross-platform-targeting)
