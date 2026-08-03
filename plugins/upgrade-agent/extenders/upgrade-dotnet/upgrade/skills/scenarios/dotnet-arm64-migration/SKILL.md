---
name: dotnet-arm64-migration
description: >
  Migrate one or more .NET projects to run on ARM64 (Apple Silicon, Windows on ARM,
  Linux/Alpine arm64, cloud arm64 like AWS Graviton / Azure Ampere). Use when the user
  wants to add arm64 support, target ARM64, build/publish for an arm64 runtime identifier
  (win-arm64, linux-arm64, linux-musl-arm64, osx-arm64), fix x86/x64 assumptions, resolve
  missing arm64 native NuGet assets, guard x86 hardware intrinsics, or run on Graviton /
  Ampere / Apple Silicon. User-initiated — match the user's stated intent to move a
  codebase onto ARM64. Not for general framework or package version upgrades.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: medium
  weight: 6000
  traits: (.NET|CSharp|VisualBasic|DotNetCore|DotNetFramework)
  scenarioTraitsSet: [.NET]
  post-completion:
    suggest-actions:
      - generate-report
---

# .NET ARM64 Migration Scenario

Make one or more .NET projects build, publish, and run correctly on an ARM64 runtime
identifier (`win-arm64`, `linux-arm64`, `linux-musl-arm64`, `osx-arm64`), fixing the
project-file, NuGet native-asset, source-code, and infrastructure surfaces that assume
x86/x64.

## Scenario Overview

**Goal**: Move the scoped project(s) onto ARM64 — correct RID/platform settings, resolve
arm64-capable native package assets, guard x86-only hardware intrinsics, and surface the
remaining awareness/concurrency findings — validated by a cross-compile Gate (and native
run/test when the host itself is arm64).

This scenario is **user-initiated**. The user asks to target ARM64; act on the scope they
name. Do not auto-migrate unrelated projects.

**What this scenario proves and does not prove.** Milestone A delivers detection, the
mechanical fixes, and a cross-compile **Gate** that proves *restore + native-asset
resolution + IL compilation* for the target RID. The Gate does **not** prove that native
libraries load, that P/Invoke entry points resolve, or that concurrency behaves correctly
on arm64 — those require execution on matching-RID hardware (native run, emulated Smoke, or
CI). Always tell the user this boundary; never present a green Gate as arm64 correctness
certification.

**Language coverage.** The project-file/RID (`0001`–`0003`), NuGet native-asset
(`0004`/`0005`), and infrastructure (`0010`) surfaces are language-agnostic and apply to
both C# and Visual Basic projects. The **source-code** rules (`0006`–`0009` and the code
portion of `0012`) analyze **C# only** — Visual Basic projects do not receive
architecture-sensitive source-code analysis (x86 intrinsics, native-interop, bitness, or
concurrency hazards). For a VB project, manually review those hazards; the automated scan
will not surface them.

## Workflow Stages

Run these stages in order:

0. **Pre-Initialization** — Confirm scope + target RID(s); detect host OS+arch; run the
   **.NET Framework → modern-.NET decision gate** (and the **< 4.8.1 viability hard-block**)
   before assessment. Uses the `scenario-initialization` system skill.
1. **Assessment** — Detect the four ARM64 surfaces (project / NuGet / code / infra) into
   `assessment.md` (+ JSON). Tool: `generate_arm64_migration_assessment`.
2. **Planning** — Triage findings into auto-fixable / guided / flag-only; order the
   `0001`↔`0012` fixes; decide package bump-vs-replace. Uses the `plan-generation` system skill.
3. **Execution** — Apply the project-file, RID, package, and intrinsic-guard fixes; leave
   review/flag findings as annotated tasks. Uses the `task-execution` system skill.
4. **Validation** — Host-adaptive ladder: cross-compile Gate always; native build/run/test
   when the host matches the target RID.

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

Use `get_solution_path` / `get_projects_info` to discover and confirm the project set. Pass
the scope to the assessment tool as `inputMode` (`solution` | `projects` | `folder`) and
`paths` (semicolon-delimited).

⛔ **Step 2 — Target RID(s).** Confirm the arm64 runtime identifier(s) to target, a subset
of `{ win-arm64, linux-arm64, linux-musl-arm64, osx-arm64 }`:
- If the user named a target (e.g. "Graviton" → `linux-arm64`, "Apple Silicon" → `osx-arm64`,
  "Windows on ARM" → `win-arm64`, "Alpine/musl" → `linux-musl-arm64`), use it.
- Otherwise **do not guess** — leave `targetRids` unset and let the tool infer per project
  from project type and current RIDs, then confirm the inferred set with the user.
- RIDs are **always lowercase**. A RID that does not match a project's OS family is rejected
  per project by the tool — never force a cross-OS RID onto a project.
- `linux-musl-arm64` is **never inferred**; only target it when the user explicitly asks for
  musl/Alpine, because a glibc `linux-arm64` native asset is not reliably loadable on musl.

⛔ **Step 3 — .NET Framework decision gate (before assessment).** Cheaply read each project's
TFM. For any project targeting **.NET Framework**, surface the modernize-first recommendation
as an explicit decision gate — do **not** proceed silently:
- **(a) Accept modernization** → hand off to the `dotnet-version-upgrade` scenario **first**. Because
  there is no automatic scenario-chaining primitive, how you re-enter ARM64 depends on the **Flow Mode**:
  - **Guided Flow Mode** — stop after the version upgrade completes and tell the user to **re-invoke
    this ARM64 scenario**. Do **not** silently auto-resume the ARM64 intent; leave the ARM64 migration
    for a fresh, user-initiated run so the modernization can be reviewed on its own.
  - **Automatic Flow Mode** — you may run `dotnet-version-upgrade` and then continue into this ARM64
    scenario in the same pass, but only if you: (1) **record it explicitly as a two-phase effort**
    (Phase 1 = `dotnet-version-upgrade`, Phase 2 = `dotnet-arm64-migration`) in
    `scenario-instructions.md` and the run summary; and (2) **re-run the ARM64 assessment against the
    modernized project** before applying any arm64 fix — never carry findings over from a
    pre-modernization assessment (the TFM, RIDs, and project style all change during modernization).
- **(b) Decline modernization** → proceed with ARM64 on .NET Framework, **but** apply the
  **< 4.8.1 viability hard-block first**: arm64 is only supported on .NET Framework 4.8.1+.
  A project below 4.8.1 that declines modernization is **stopped at the gate** with a clear
  message ("ARM64 needs .NET Framework 4.8.1+ or modernization to .NET") rather than being
  given unbuildable arm64 fixes. Remove that project from scope.
- **Mixed solution** (some Framework, some modern): apply the gate **per Framework project**.
  Modern projects proceed straight to assessment unaffected.

⛔ **Step 4 — Exclusions.** Collect any projects removed from scope at this gate (e.g. a
`< 4.8.1` project that declined modernization). Pass them to the assessment tool as
`excludedProjects` (semicolon-delimited), or downgrade a `solution`/`folder` scope to
`inputMode=projects` with only the surviving paths — so the tool never assesses a blocked
project.

**Step 5** — Proceed with the confirmed scope, target RID(s), and exclusions, passing them
to `initialize_scenario` and then to the assessment stage.

## Stage Instructions

⛔ **IMPORTANT**: Load each stage's instructions file **only when entering that stage** (not
all upfront).

### Stage 1: Assessment
**When entering this stage, load**: [assessment.md](assessment.md)

Runs `generate_arm64_migration_assessment` over the confirmed scope, detecting the four
ARM64 surfaces (project-file settings, NuGet native assets, source-code hazards, infra) and
writing `assessment.md` (+ JSON).

### Stage 2: Planning
**When entering this stage, load**: [planning.md](planning.md)

Triages each finding into auto-fixable / guided / flag-only, correlates `Arm64.0001` with
`Arm64.0012` to decide the ordered platform-target fix, and chooses bump-vs-replace for
native packages. Uses the `plan-generation` system skill to produce `plan.md`, `tasks.md`,
and `scenario-instructions.md`.

### Stage 3: Execution
**When entering this stage, load**: [execution.md](execution.md)

Applies the mechanical fixes (project-file, RID, safe package bumps, intrinsic guards) and
leaves review/flag findings as annotated tasks, validating with builds. Uses the
`task-execution` system skill.

### Stage 4: Validation
**When entering this stage, load**: [validation.md](validation.md)

Runs the host-adaptive validation ladder: the cross-compile Gate always, plus native
build/run/test when the host OS+arch (and libc flavor for musl) matches the target RID.

## Success Criteria

- [ ] Every scoped project declares an arm64 RID for its target OS with correct lowercase casing.
- [ ] `PlatformTarget=x86` / `Prefer32Bit=true` removed where safe, or handled as a guided
      task when 32-bit interop (`Arm64.0012`) is present.
- [ ] NuGet packages with native assets are at an arm64-capable version (safe bump) or the
      guided replacement/major-bump decision is recorded.
- [ ] Unguarded `System.Runtime.Intrinsics.X86` uses have an `…IsSupported` guard + fallback.
- [ ] Awareness (`0007`/`0008`) and concurrency (`0009`) findings are surfaced as review tasks.
- [ ] The cross-compile **Gate** (build + publish for the target RID) passes for every scoped
      project — and the user is reminded this proves packaging/compile, not runtime correctness.
- [ ] Native run/test passed when the host matched the target RID; otherwise real-hardware /
      CI validation was recommended.

## Error Handling

**Framework project below 4.8.1 declines modernization** (Pre-Init):
1. Stop that project at the gate — do not emit arm64 fixes it cannot build.
2. State the two viable paths: upgrade to .NET Framework 4.8.1+, or modernize to .NET via
   `dotnet-version-upgrade`. Exclude the project from scope and continue with the rest.

**Target RID does not match a project's OS family**:
1. The tool rejects it per project with a message — surface that to the user.
2. Confirm the correct RID for that project's OS, or exclude the project.

**`Arm64.0004` reports no safe arm64 version** (only a major bump / TFM raise / replacement):
1. Do not auto-apply — present the guided options from the assessment.
2. Let the user choose: accept the major bump, raise the TFM first, or replace the package.

**Cross-compile Gate fails**:
1. Report the unresolved packaging / native-asset / compile issue — do not mark the migration
   complete.
2. Common causes: a package still missing an arm64 native asset (`Arm64.0004`), or an
   unresolved x86 assumption. Return to Execution for that finding.
