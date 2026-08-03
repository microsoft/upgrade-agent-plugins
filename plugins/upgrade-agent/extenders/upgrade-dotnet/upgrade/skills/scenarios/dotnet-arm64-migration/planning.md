# Stage 2: Planning

Turn the assessment into an ordered, executable plan. The plan's job is to **triage** each ARM64
finding (auto-fixable / guided / flag-only), **order** the interdependent fixes (notably
`Arm64.0001`↔`Arm64.0012`), and record the **package bump-vs-replace** and **CPM** decisions.

## Contents

- [Entry Criteria](#entry-criteria)
- [Steps](#steps)
  - [Step 1 — Classify every finding](#step-1--classify-every-finding)
  - [Step 2 — Correlate `Arm64.0001` with `Arm64.0012` (ordering)](#step-2--correlate-arm640001-with-arm640012-ordering)
  - [Step 3 — Decide bump-vs-replace for native packages (`0004`/`0005`)](#step-3--decide-bump-vs-replace-for-native-packages-00040005)
  - [Step 4 — Build the plan](#step-4--build-the-plan)
  - [Step 5 — Persist constraints](#step-5--persist-constraints)
- [Exit Criteria](#exit-criteria)
- [Transition to Execution](#transition-to-execution)


> **File format is enforced by the system `plan-generation` skill.** Load and follow it for the
> exact templates for `plan.md`, `tasks.md`, and `scenario-instructions.md`. This scenario file
> defines **what** to plan; the `plan-generation` skill defines **how** to write the artifacts.
> Do not invent your own document shapes (e.g. a `## {task-id}` heading with `**Status**` /
> `**Description**` fields is **wrong** — `tasks.md` is a flat emoji checklist).

## Entry Criteria

- `assessment.md` exists and has been reviewed.
- Whether `Arm64.0012` reported 32-bit interop is known (the `0001` ordering input).

## Exit Criteria

- `plan.md` created with ordered tasks (per the `plan-generation` plan.md template).
- `tasks.md` created (per the `plan-generation` tasks.md template — flat emoji checklist, not
  per-task headings).
- Execution constraints (finding classification, `0001`/`0012` ordering, package decisions, CPM
  decision) persisted in `scenario-instructions.md`.

## Steps

### Step 1 — Classify every finding

Sort each assessment finding into one of three buckets:

| Bucket | Rules | Handling |
|---|---|---|
| ✅ **Auto-fixable** | `0002` (RID casing + additive arm64); `0004` (safe bump only); `0001` (**only when `0012` is empty** — see Step 2); `0010` (**opt-in auto-apply**: Linux Dockerfile → multi-arch, and the GitHub Actions CI leg via `scaffold_arm64_ci_leg`) | Apply mechanically in Execution, validate with a build. |
| ⚠️ **Guided** | `0001` (when `0012` present); `0003` (deployment mode); `0004` (major bump / TFM raise / replace); `0005` (incompatible package swap); `0006` (intrinsics guard + fallback); `0010` (win-arm64 → CI-only, and non-GitHub CI providers) | Author reviews/approves each change; scaffold + explain, never silent-rewrite. |
| ❌ **Flag-only** | `0007`, `0008` (awareness); `0009` (concurrency); `0012` (32-bit interop — also an ordering input) | Record as annotated review tasks; do not modify code. |

### Step 2 — Correlate `Arm64.0001` with `Arm64.0012` (ordering)

This is the key ordering decision. `Arm64.0001` removes the x86 assumption
(`PlatformTarget=x86` / `Prefer32Bit=true`):
- **If `Arm64.0012` reported zero 32-bit interop findings for the project** → `0001` is
  **auto-fixable**. Schedule the removal.
- **If `Arm64.0012` reported any 32-bit interop** (`<COMReference>`, VSTO/Office add-in, or native
  x86 P/Invoke) → downgrade `0001` to **guided**. Removing the x86 assumption while a 32-bit COM
  component / VSTO add-in / native x86 P/Invoke is still in play ships a binary that builds clean
  but throws `BadImageFormatException` at load — which the cross-compile Gate **cannot** catch.
  Schedule the interop cleanup **first**, then apply `0001` once the interop is gone. `0001` is a
  guided task the user completes after clearing interop, not a permanent block — no re-assessment
  is required.

### Step 3 — Decide bump-vs-replace for native packages (`0004`/`0005`)

For each NuGet finding:
- **`0004` with a safe arm64 version** (lowest version that keeps the TFM, avoids a major-version
  jump, has no deprecation/security advisory, and leaves restore green) → plan a **safe bump**.
- **`0004` with only a major bump / TFM raise / no arm64 version** → **guided**: present the
  options (accept the major bump, raise the TFM first, or replace the package) and let the user pick.
- **`0005` (arm64-incompatible / unmaintained)** → **guided API swap**: identify the arm64-capable
  replacement and plan the code changes it implies.

**CPM blast-radius guard.** When Central Package Management is in use, a version bump edits
`Directory.Packages.props` `<PackageVersion>` and therefore affects **every** consumer. Auto-apply
a central bump **only** when all consumers are in scope + compatible **and** a solution-wide restore
stays green. Otherwise downgrade it to **guided** so the user accepts the wider blast radius. Defer
CPM mechanics to the `converting-to-cpm` skill.

### Step 4 — Build the plan

Create the planning artifacts using the **`plan-generation` system skill's templates** — load that
skill and follow its `plan.md` and `tasks.md` specifications exactly.

**`plan.md`** — one task per ordered unit of work, using the plan-generation task template:

```
### {NN}-{slug}: {task name}

{1-3 paragraph intent-based description with scope, context, and the fix handling.}

**Done when**: {verifiable success criteria}
```

Order tasks so mechanical, low-risk edits land first and dependent edits follow:
1. `0012` interop cleanup (where it gates `0001`).
2. `0002` RID additions / casing, `0003` deployment-mode decision.
3. `0004` safe bumps (then guided package decisions).
4. `0001` platform-target removal (auto or post-interop guided).
5. `0006` intrinsic guards.
6. Annotate `0007`/`0008`/`0009` as review tasks.
7. `0010` infra: remediate Linux Dockerfiles (multi-arch) and scaffold the GitHub Actions CI leg
   (`scaffold_arm64_ci_leg`); annotate win-arm64 (CI-only) and non-GitHub CI providers as guided tasks.

Use canonical `NN-slug` task IDs (two-digit zero-padded sequence + kebab slug, e.g.
`01-clear-com-interop`) as required by the `plan-generation` system skill — never `T-01` or other
letter-prefixed ids, or task tracking will break. For each task record the project(s) covered, the
specific rule findings addressed, and the chosen handling.

**`tasks.md`** — the visual progress checklist. Use the plan-generation `tasks.md` template
verbatim: a `# {Scenario} Progress` title, a short `## Overview`, a `**Progress**` line, and a
`## Tasks` section that is a **flat list of `- {emoji} {task-id}: {task name}` bullets** (one per
plan.md task, all `🔲` at creation). Do **not** emit a `##` heading per task and do **not** add
`**Status**` / `**Description**` fields — that shape is wrong and breaks progress tracking.

### Step 5 — Persist constraints

Write a compact block to `scenario-instructions.md`: each finding's classification, the
`0001`/`0012` ordering per project, the package bump/replace decisions, the CPM decision, and the
confirmed target RID(s). Execution and Validation read this.

## Transition to Execution

After `plan.md` and `tasks.md` are created and presented (via the `plan-generation` skill):

- **Guided mode**: Wait for user approval before proceeding. Do not load `execution.md` yet.
- **Automatic mode**: **Immediately** load this scenario's [execution.md](execution.md) and begin
  executing the first task. Do not stop, do not wait for user input. The plan has been surfaced —
  proceed.
