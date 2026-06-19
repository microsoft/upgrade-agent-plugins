# Execution Stage Instructions

Scenario-specific execution guidance for .NET version upgrade tasks.
Supplements the system `task-execution` skill — does not replace it.

> **This file covers 6 sections.**
>
> | # | Section | Key Content |
> |---|---------|-------------|
> | 0 | Assessment Consultation | Querying per-project assessment data during task research |
> | 1 | SDK-Style Conversion | Converting old-style csproj projects before TFM upgrade |
> | 2 | Stub Marker Format | Consistent comment format for all generated stubs |
> | 3 | Decomposition Rules | Stub discovery, stub resolution, package replacement research |
> | 4 | Multi-Targeting Mechanics | MSBuild conditions for package references and API calls |
> | 5 | Tasks Breakdown Hints | Per-flavor decomposition hints for complex tasks |

---

## Section 0: Assessment Consultation

During the **Research** step (system task-execution skill, Section 3 Step 2),
query the assessment for each project in the task's scope. The task description
contains a summary, but it does not contain the full per-project issue and
feature data. You must retrieve this yourself.

### When to query

Query assessment data for every task that modifies projects — SDK-style
conversion, TFM upgrade, scaffold, migrate, and remaining project tasks.
Skip only for prerequisites and final validation.

### What to query

For each project in the task's scope, run:

```json
{ "query": "summary", "scope": "global/project", "params": { "projectPath": "{path}" } }
```

This returns: issue counts by severity, affected features, package details,
and technologies detected. Then for any project with issues:

```json
{ "query": "list_issues", "scope": "global/project", "params": { "projectPath": "{path}" } }
```

This returns the actual issues — breaking API changes, incompatible packages,
deprecated patterns — that the task must address.

### What to record

Enrich `task.md` with per-project findings:

- **Issues to address** — list issues from the assessment relevant to this
  task's work (package incompatibilities, API breaks, deprecated patterns)
- **Features detected** — technologies the assessment flagged for this project
  (e.g., EF6, Autofac, OWIN, System.Web usage patterns) that affect how
  the work should be done
- **Package actions** — packages that need version bumps, replacements, or
  removal, with the assessment's recommended target versions

### Why this matters

The task description gives research *starting points* — the assessment gives
the *complete inventory* of what needs to change in each project. Without
querying it, you'll miss issues that weren't mentioned in the plan summary
and discover them only when builds fail.

---

## Section 1: SDK-Style Conversion

When the solution contains non-SDK-style projects (old-style csproj with
`<Project ToolsVersion=...>`, `packages.config`, or `<Import Project=...Microsoft.CSharp.targets>`),
these must be converted to SDK-style **before** any TFM changes, package upgrades,
or multi-targeting modifications. SDK-style conversion is a mechanical, low-risk
transformation that makes all subsequent upgrade steps possible.

### Which projects to convert

| Project type | Convert? |
|---|---|
| Class libraries (no System.Web) | **Yes** — always, these are safe to convert |
| Test projects | **Yes** — convert alongside or before the libraries they test |
| Console / Worker apps | **Yes** — straightforward conversion |
| Web projects (MVC/WebAPI with System.Web) where **in-place rewrite** selected | **Yes** — convert as part of the rewrite preparation |
| Web projects where **side-by-side** selected | **No** — the old project stays as-is; the new ASP.NET Core project is scaffolded SDK-style |
| Projects using WCF server-side hosting | **Yes with caution** — may need manual review of service configuration |

### Using the `convert_project_to_sdk_style` tool

Each project conversion should use the `convert_project_to_sdk_style` tool, which:
- Converts old-style csproj to SDK-style format
- Migrates `packages.config` to `PackageReference`
- Removes redundant imports, assembly references covered by the SDK
- Preserves project-specific MSBuild properties and custom targets

> **Sequential only**: Always call this tool one project at a time and wait for
> each call to complete before starting the next. Never invoke multiple conversions
> in parallel — the underlying MSBuild engine uses shared global state that is not
> safe for concurrent access.

### Conversion ordering

Convert projects **bottom-up in dependency order**:
1. Leaf libraries first (no project-to-project references)
2. Libraries that depend on already-converted projects
3. Test projects (after the projects they test)
4. Entry-point applications last

After each project conversion:
- Build the solution to verify no regressions
- If the project used `packages.config`, verify restored packages match

### Task decomposition

**If only 1-3 projects need SDK-style conversion**:
- Handle as a single task with sequential per-project conversion

**If 4+ projects need conversion**:
- Break down by dependency tier (same tiers used in bottom-up strategy):
  - Subtask per tier, each converting all projects in that tier
  - Build validation after each tier completes
- Alternatively, if all projects are independent (flat dependency graph),
  group into batches of 3-5 projects per subtask

### Validation after SDK-style conversion

Before proceeding to TFM upgrade tasks:
1. All converted projects build successfully on their **original** target framework
2. All tests pass (the SDK-style conversion must be behavior-preserving)
3. No leftover `packages.config` files in converted projects
4. Solution file references are intact

> **Important**: SDK-style conversion does NOT change the target framework.
> A `net472` project remains `net472` after conversion — it's just in SDK-style format.
> TFM changes happen in subsequent upgrade tasks.

---

## Section 2: Stub Marker Format

All generated stub files and stub classes **must** use a standardized comment header
so they can be reliably discovered later via grep.

### Format

```csharp
// STUB:package {PackageName} | types: {Type1}, {Type2}, ... | task: {taskId}
```
```csharp
// STUB:api {OriginalApiName} | replacement: {unknown|ApiName} | task: {taskId}
```

- `STUB:package` — stub generated for a missing NuGet package (Unsupported Packages option)
- `STUB:api` — stub generated for a changed/removed BCL API (Unsupported API Handling option)
- `types:` — lists the stubbed types in this file
- `replacement:` — `unknown` if no replacement identified yet, or the target API name
- `task:` — the task ID that created the stub (for traceability)

Place the marker as the **first line** of each stub file. If adding stub types
inline within an existing file, place the marker directly above the stub class/method.

### Example

```csharp
// STUB:package OldLib.Compression | types: FastCompressor, CompressionOptions | task: 02-leaf-libs
namespace OldLib.Compression;

/// <summary>Stub — provides compilable surface for FastCompressor while replacement is researched.</summary>
public class FastCompressor
{
    public byte[] Compress(byte[] data) => throw new NotImplementedException("STUB");
}
```

### Discovery

To find all stubs in a project or solution, grep for `// STUB:`:

```
grep -r "// STUB:" --include="*.cs" {projectPath}
```

This is the **only** tracking mechanism for stubs — no separate registry file.
The source code is the source of truth.

---

## Section 3: Decomposition Rules

The system task-execution skill checks for `## Decomposition Rules` during its
Extended Assessment (Section 1). These rules supplement the core decomposition
triggers — they fire in addition to, not instead of, the system triggers.

### Stub Discovery at Task Start

**When**: During the "Research and enrich task.md" step (system task-execution
Section 3, Step 3), before making any code changes.

**Action**: For each project in the current task's scope, grep for `// STUB:`:

```
grep -r "// STUB:" --include="*.cs" {projectPath}
```

If stubs are found in any affected project:
1. List them in `task.md` under a `## Stubs Found` heading (file path, marker line)
2. These stubs become part of the task's scope
3. Apply the Stub Resolution decomposition trigger below

If no stubs found, proceed normally — no decomposition needed for stubs.

### Stub Resolution Tasks

**Trigger**: A task's scope includes projects containing `// STUB:` markers
(discovered via grep above), OR a task was explicitly created to resolve stubs.

**Always decompose** when stub resolution is part of a task's scope. Each stub file
or group of related stubs becomes its own subtask chain:

```
{parentTaskId}/
├── {id}.01-research-{stub-name}     (discover replacement: alternative package, API pattern, or rewrite approach)
├── {id}.02-implement-{stub-name}    (replace stub with real code, update all consuming files)
└── {id}.03-validate-{stub-name}     (build + test, confirm no regressions)
```

**Research subtask** scope:
- Identify replacement package or API
- Evaluate API surface compatibility with the stubbed interface
- Document approach in `task.md` before proceeding to implementation
- If no viable replacement found, report to user — do not guess

**Implementation subtask** scope:
- Remove stub file
- Add replacement package reference (if applicable) or implement replacement code
- Update all files that consumed the stubbed types
- May touch multiple projects if the stub was in a shared library

**Validation subtask** scope:
- Build the affected project(s) and all dependents
- Run tests covering the replaced functionality
- Confirm no remaining references to the stub file

**Grouping**: If multiple stubs come from the same package or relate to the same
API surface, group them into a single research → implement → validate chain
rather than creating separate chains per stub.

### Package Replacement Research

**Trigger**: A task requires replacing an incompatible NuGet package and the
assessment did not identify a known replacement.

This is a specialization of the stub resolution pattern. The research subtask
should:
1. Search NuGet for packages providing the same namespace/types
2. Check the original package's repository for migration guidance or successor packages
3. Evaluate whether the functionality can be replaced with built-in .NET APIs
4. If multiple candidates exist, document trade-offs in `task.md` and pick the
   closest API-compatible option (or ask the user in Guided mode)

---

## Section 4: Multi-Targeting Mechanics

When Project Approach selects multi-targeting, package references and
API calls for the old TFM must coexist with the new TFM in a single project file.

### Conditioned Package References

For packages that are incompatible with the new TFM but needed by the old TFM:

```xml
<!-- Old TFM keeps old package -->
<ItemGroup Condition="'$(TargetFramework)' == 'net472'">
  <PackageReference Include="OldPackage" Version="1.0.0" />
</ItemGroup>

<!-- New TFM uses replacement (if any) -->
<ItemGroup Condition="'$(TargetFramework)' == '{targetTfm}'">
  <PackageReference Include="NewPackage" Version="2.0.0" />
</ItemGroup>
```

If no replacement package exists for the new TFM, omit the new-TFM `ItemGroup`
entirely — the code path for that TFM uses stubs or rewritten code instead.

### Conditioned API Calls

For BCL APIs that differ between TFMs:

```csharp
#if NET472
    var result = LegacyApi.DoSomething();
#else
    var result = ModernApi.DoSomething();
#endif
```

This is mechanical — applied automatically for multi-targeted projects regardless
of the Unsupported API Handling selection. That option only controls what happens when the modern
replacement is *complex* (requires research or architectural changes).

---

## Section 5: Breakdown Hints

Breakdown hints are evaluated at **execution time** when assessing whether a
task needs decomposition. They provide scenario-specific decomposition signals
and recommendations that supplement the core triggers in the task-execution skill.

**Progressive disclosure**: Hints are organized by project flavor. Only load
the hint file(s) relevant to the current task's scope.

### Flavor Index

| Flavor | Load when | File |
|--------|-----------|------|
| Common | Always | [breakdown-hints/common.md](breakdown-hints/common.md) |
| .NET Framework migration | Task scope includes projects migrating from .NET Framework | [breakdown-hints/framework-migration.md](breakdown-hints/framework-migration.md) |
| ASP.NET Framework web migration | Task scope includes ASP.NET Framework web projects (System.Web, MVC, WebAPI) | [breakdown-hints/framework-web-migration.md](breakdown-hints/framework-web-migration.md) |
| Test | Task scope includes test projects or task modifies projects with test dependents | [breakdown-hints/test.md](breakdown-hints/test.md) |

### How to Use

1. During scope inventory (task-execution skill Section 1), identify which
   project flavors are in the current task's scope
2. Load only the matching hint files from the table above
3. Evaluate each hint's detection conditions
4. Record results in `breakdown-context.md`
5. Use triggered hints to inform subtask structure

**Tool**: Use `get_code_dependencies(projectPath, filePath)` during task research
to get a Roslyn-based dependency graph for any controller, class, or view.
This is especially useful when breaking down web migration tasks — it reveals
what each controller depends on (DI services, views, packages, project references)
so subtasks can be scoped accurately.

Custom skills can contribute additional hints using the protocol defined
in the task-execution system skill (see `provides: task-breakdown-hints`).
