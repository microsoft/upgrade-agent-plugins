---
name: converting-to-cpm
description: >
  Converts .NET projects and solutions to NuGet Central Package Management (CPM) with
  Directory.Packages.props. Use when the user wants to centralize, convert, align, or sync NuGet
  package versions across multiple projects, resolve version conflicts or mismatches, or get versions
  consistent across a solution or repository. Also triggers when packages are out of sync or drifting
  across projects.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Convert to Central Package Management

Migrate .NET projects from per-project package versioning to NuGet Central Package Management (CPM), centralizing all package versions into a single `Directory.Packages.props`.

## When to Use

- User wants to adopt CPM for a repository, solution, or project
- Package versions are scattered across project files and the user wants a single source of truth
- User mentions `Directory.Packages.props`, CPM, or centralizing NuGet versions
- User wants to align or sync a package version across multiple projects — suggest CPM if not already enabled
- Package versions are out of sync or conflicting across projects

## When Not to Use

- CPM is already fully enabled for all in-scope projects
- Projects use `packages.config` (must first migrate to `PackageReference`)
- User explicitly wants a custom MSBuild property file without CPM

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| Scope | Yes | A project file, solution file, or directory containing .NET projects to convert |
| Version conflict strategy | No | How to resolve version conflicts. Do not assume a default — ask the user when conflicts are detected. |

## Workflow

### Step 1: Determine scope

- **Single project**: User specifies a project file.
- **Solution**: User specifies a `.sln`/`.slnx`. List projects with `dotnet sln list`.
- **Repository/directory**: Find all project files recursively from the first common ancestor directory.

If the scope is unclear, ask the user.

### Step 2: Establish baseline build

Verify the scope builds successfully and capture baseline artifacts. See [baseline-comparison.md](references/baseline-comparison.md) for the full procedure. If the baseline build fails, stop and inform the user — the scope must build cleanly before conversion. Do not delete artifacts — they are needed for the post-conversion comparison.

### Step 3: Check for existing CPM

Search for `Directory.Packages.props` in scope or ancestor directories. If CPM is already fully enabled, inform the user and stop. If the file exists without CPM enabled, ask the user how to proceed.

### Step 4: Audit package references

Run `dotnet package list --format json` across all in-scope projects. Scan `<Import>` elements for shared `.props`/`.targets` files containing package references.

Check for complexities per [audit-complexities.md](references/audit-complexities.md): version conflicts, MSBuild property-based versions, conditional references, security advisories, existing `VersionOverride` usage.

Present audit results to the user before proceeding — a table of packages, versions, and consuming projects, plus any conflicts or complexities requiring decisions.

For version conflicts, present each individually with resolution options and trade-offs. Do not upgrade any package beyond the highest version already in use — note advisories as follow-up items instead. Ask the user to decide on each conflict before proceeding.

### Step 5: Create or update Directory.Packages.props

Create with `dotnet new packagesprops` (.NET 8+) or manually. Add `<PackageVersion>` entries for each unique package. See [directory-packages-props.md](references/directory-packages-props.md) for placement, conditional versions, and `VersionOverride` patterns.

### Step 6: Update project files

Remove `Version` from every `<PackageReference>` that has a corresponding `<PackageVersion>`. Also update shared `.props`/`.targets` files from step 4. Use `VersionOverride` (with user confirmation) when a project needs a different version than the central one. Do not reformat or reorganize unchanged lines.

### Step 7: Handle MSBuild version properties

For `PackageReference` items that used MSBuild properties for versions, determine whether to inline or keep the property reference. See [msbuild-property-handling.md](references/msbuild-property-handling.md) for the decision workflow, import order requirements, and cleanup procedure. Clean up inlined properties only after validation succeeds in step 8.

### Step 8: Restore and validate

Run a clean restore and build, capturing post-conversion artifacts. See [baseline-comparison.md](references/baseline-comparison.md) for the procedure. If errors occur, see [validation-and-errors.md](references/validation-and-errors.md) for NuGet error codes and multi-TFM guidance.

Do not delete any artifacts — `baseline.binlog`, `after-cpm.binlog`, `baseline-packages.json`, `after-cpm-packages.json` are deliverables for the user.

### Step 9: Post-conversion report

Create a `convert-to-cpm.md` file alongside the artifacts — do not substitute inline chat output. Include:

- Conversion overview (scope, project count, packages centralized, anything skipped)
- Version conflict resolutions and their impact per project
- Baseline vs. result package comparison tables (see [baseline-comparison.md](references/baseline-comparison.md))
- Risk assessment (low/moderate/high based on whether versions changed)
- Follow-up items checklist (security advisories, deprecated packages, `VersionOverride` alignment opportunities)

## Validation

- [ ] Baseline build succeeded before any changes
- [ ] `Directory.Packages.props` has `ManagePackageVersionsCentrally` set to `true`
- [ ] Every in-scope `PackageReference` has no `Version` attribute or uses `VersionOverride`
- [ ] Every referenced package has a corresponding `PackageVersion` entry
- [ ] `dotnet restore` and `dotnet build` succeed from a clean state
- [ ] Package list comparison shows no unexpected version changes
- [ ] No orphaned version properties remain (unless intentionally kept)