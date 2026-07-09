---
name: nuget-package-upgrade
description: >
  Upgrade one or more NuGet packages from their current version to a target version across a
  project, several projects, a folder, a solution, or the whole repository. Use when the user
  wants to bump, update, or upgrade a specific NuGet package (or packages) to a given version
  or to the latest supported version, detect breaking API changes introduced by the new
  version, and fix the resulting code. User-initiated — match the user's stated package(s)
  and version intent.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: medium
  weight: 6000
  traits: .NET|CSharp|VisualBasic|DotNetCore
  scenarioTraitsSet: [.NET]
  post-completion:
    suggest-actions:
      - generate-report
---

# NuGet Package Upgrade Scenario

Upgrade one or more NuGet packages to a target version across a chosen scope, detect
source-breaking public API changes introduced between the old and new versions, and fix the
affected code.

## Scenario Overview

**Goal**: Move the named package(s) from their current version to a target version while keeping
the scoped projects compiling and their tests passing.

This scenario is **user-initiated**. The user names the package(s) to upgrade and, optionally,
the target version. Do not auto-discover packages to upgrade — act on what the user asked for.

## Workflow Stages

Run these stages in order:

0. **Pre-Initialization** — Confirm scope + packages + version policy. Uses the `scenario-initialization` system skill.
1. **Assessment** (quick by default) — Resolve/reconcile versions and diff the API into `apidiff/*.md` + `assessment.md`; full scan is opt-in. Tool: `generate_package_upgrade_assessment`.
2. **Planning** — Triage breaking changes + version divergence. Uses the `plan-generation` system skill to create `plan.md`, `tasks.md`, and `scenario-instructions.md`.
3. **Execution** — Apply version changes (CPM-aware) and fix usages. Uses the system task-execution skill.

## Pre-Initialization

This section is used by the `scenario-initialization` system skill. It defines the
scenario-specific parameters for this scenario.

### Parameters to Confirm

⛔ **Step 1 — Scope.** Determine the scope from the user's request and normalize it to a
concrete set of projects:
- A single **project** → that project.
- **Several projects** → those projects.
- A **folder** → every project under it.
- A **solution** (`.sln`/`.slnx`) → its projects.
- The **whole repo** → all projects in the repo.

Use `get_solution_path` / `get_projects_info` to discover and confirm the project set. Pass the
scope to the assessment tool as `inputMode` (`solution` | `projects` | `folder`) and `paths`.

⛔ **Step 2 — Packages.** Collect the package name(s) the user wants to upgrade. The user must
name at least one package. If the request is ambiguous (e.g. "update my packages"), ask the user
which specific package(s) to upgrade — do not upgrade everything implicitly.

⛔ **Step 3 — Version policy.** For each package, decide the target version:
- **If the user provided a version**, respect it. (The assessment tool validates that the
  version supports each scoped project's target framework and flags any project where it does
  not.)
- **Otherwise**, do not guess and do not resolve the version yourself. The assessment tool is the
  **single source of truth** for version selection: it resolves the newest supported version per
  scoped project and reconciles across them. Run the assessment and use the version it reports — do
  not call `get_supported_package_version` to pre-pick or preview a version for the decision.
- **Stable vs prerelease.** Default to the latest **stable** version. Only include prerelease
  (preview / beta / rc) versions when the user explicitly asks for a preview/prerelease — in that
  case pass `includePrerelease=true` to the assessment tool. When the user says "latest", "newest",
  or "latest stable" (or says nothing about previews), leave `includePrerelease=false` so a preview
  is never selected. If the user named an explicit preview version, pass it as the package `version`
  (that is always honored regardless of the flag).

**Step 4** — Proceed with the confirmed scope, package list, and any user-specified versions,
passing them to `initialize_scenario` and then to the assessment stage.

### Source control defaults (scenario override)

⛔ **Source branch = whatever the repo is currently on — do not substitute another branch.**
A package bump is a lightweight change that belongs on whatever the user is working on now. When
computing source-control defaults during initialization, always set the **source branch** to the
branch the repo is currently checked out on (`git branch --show-current`; if HEAD is detached on a
tag/commit, use that ref) — **whatever that branch is**, including `main`/`master` if that is
genuinely where the user is. The point is: do **not** switch the source to `main`/`master` (or any
other branch) when the user is on a different branch. Only use a source branch other than the
current one if the user explicitly asks for it. The working-branch selection (new branch vs.
current branch) follows the normal `scenario-initialization` defaults.

## Stage Instructions

⛔ **IMPORTANT**: Load each stage's instructions file **only when entering that stage** (not all
upfront).

### Stage 1: Assessment
**When entering this stage, load**: [assessment.md](assessment.md)

Resolves and reconciles versions across the scoped projects and diffs the old→new public API of each
package into per-package `apidiff/{packageId}.apidiff.md` artifacts. **Quick by default**: skips the
expensive semantic scan (no `PkgApi.*` incidents) — the apidiff files plus `Pkg.0001` presence
findings are the breaking-change reference. A full code scan that pinpoints exact breaking-change
locations is **opt-in** (`fullScan=true`) — always offer it to the user. Findings are written to
`assessment.md` (+ JSON).

### Stage 2: Planning
**When entering this stage, load**: [planning.md](planning.md)

Triages the assessment: resolves version divergence across projects (if any) and decides how to
handle each breaking change. Uses the `plan-generation` system skill for file format to produce
`plan.md` and `tasks.md`, and persists execution constraints in `scenario-instructions.md`.

### Stage 3: Execution
**When entering this stage, load**: [execution.md](execution.md)

Applies the version changes (CPM-aware) and fixes the flagged code usages, validating with builds.

## Success Criteria

- [ ] The named package(s) are at the target version across the scoped projects.
- [ ] Version divergence across projects (if any) was resolved per the chosen option.
- [ ] All flagged source-breaking usages are fixed.
- [ ] Scoped projects restore and build without errors.
- [ ] Tests (if any) pass.

## Error Handling

**User-provided version is incompatible with a project's target framework**:
1. Surface the per-project incompatibility from the assessment.
2. Offer options (see `upgrade-options/version-reconciliation.md`): pick the highest common
   compatible version, upgrade the lagging project's TFM first, or exclude that project.

**Projects require different versions of the same package** (divergence):
1. Present the per-project version breakdown from the assessment.
2. Apply the chosen reconciliation option before executing code fixes.
