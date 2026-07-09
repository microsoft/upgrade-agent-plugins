# Stage 2: Planning

Turn the assessment into an ordered, executable plan. Two decisions drive the plan: how to
**reconcile versions** across projects, and how to **handle each breaking change**.

> **File format is enforced by the system `plan-generation` skill.** Load and follow it for the
> exact templates for `plan.md`, `tasks.md`, and `scenario-instructions.md`. This scenario file
> defines **what** to plan; the `plan-generation` skill defines **how** to write the artifacts.
> Do not invent your own document shapes (e.g. a `## {task-id}` heading with `**Status**` /
> `**Description**` fields is **wrong** — tasks.md is a flat emoji checklist).

## Entry Criteria

- `assessment.md` exists and has been reviewed.

## Exit Criteria

- `plan.md` created with ordered tasks (per the `plan-generation` plan.md template).
- `tasks.md` created (per the `plan-generation` tasks.md template — flat emoji checklist, not
  per-task headings).
- Execution constraints (chosen version per package, reconciliation option, CPM decision)
  persisted in `scenario-instructions.md`.

## Steps

### Step 1 — Resolve version selection

For each package, confirm the version to apply:
- **Unified** result → use the recommended version.
- **Divergent** result → choose a reconciliation option. Load
  [upgrade-options/version-reconciliation.md](upgrade-options/version-reconciliation.md) and pick
  one (highest common compatible version, upgrade the lagging project's TFM first, per-project
  pin / CPM `VersionOverride`, or exclude the incompatible project). Confirm with the user when
  the trade-off is material (e.g. excluding a project or changing a TFM).

### Step 2 — Decide package-management mechanics

- Detect whether the repo uses **Central Package Management** (a `Directory.Packages.props`
  exists). The version change must be applied centrally there rather than per project when CPM is
  in use.
- If projects are not on CPM and the upgrade touches many projects, consider proposing CPM (defer
  the mechanics to the `converting-to-cpm` skill). This is optional — do not force it.

### Step 3 — Decide breaking-change handling

Base this on the assessment mode. In **quick mode** the breaking changes come from each package's
`apidiff/{packageId}.apidiff.md` artifact (removed/changed API); in **full mode** they come from
`PkgApi.0001` / `PkgApi.0002` incidents with exact locations. For each
change (or group of related changes), choose:
- **Migrate** — update the calling code to the new API (the default for removed/changed members
  that have a replacement).
- **Pin** — keep the project on the current version if the breaking changes are not worth the
  upgrade for that project (only valid with per-project versions / CPM `VersionOverride`).
- **Accept** — proceed without code changes when the finding is a false positive or the usage is
  already conditionally compiled out.

> In quick mode you won't have exact call-site counts. Plan the fixes from the API diff and let the
> build surface the concrete locations during execution, or ask the user to opt into `fullScan=true`
> if they want exact locations before planning.

### Step 4 — Build the plan

Create the planning artifacts using the **`plan-generation` system skill's templates** — load that
skill and follow its `plan.md` and `tasks.md` specifications exactly.

**`plan.md`** — one task per ordered unit of work, using the plan-generation task template:

```
### {NN}-{slug}: {task name}

{1-3 paragraph intent-based description with scope, context, and the breaking-change handling.}

**Done when**: {verifiable success criteria}
```

Order tasks so that projects exposing the package's types in their own public API are upgraded
before their consumers (bottom-up). Use canonical `NN-slug` task IDs (two-digit zero-padded sequence
+ kebab slug, e.g. `01-upgrade-htmlsanitizer`) as required by the `plan-generation` system skill —
never `T-01` or other letter-prefixed ids, or task tracking will break. For each task record:
- The project(s) covered.
- The version change to apply (and where: `Directory.Packages.props` or the project file).
- The specific breaking-change findings to fix and the chosen handling. Reference the relevant
  `apidiff/{packageId}.apidiff.md` file so execution has the change list at hand.

**`tasks.md`** — the visual progress checklist. Use the plan-generation `tasks.md` template
verbatim: a `# {Scenario} Progress` title, a short `## Overview`, a `**Progress**` line, and a
`## Tasks` section that is a **flat list of `- {emoji} {task-id}: {task name}` bullets** (one per
plan.md task, all `🔲` at creation). Do **not** emit a `##` heading per task and do **not** add
`**Status**` / `**Description**` fields — that shape is wrong and breaks progress tracking.

### Step 5 — Persist constraints

Write a compact block to `scenario-instructions.md`: chosen version per package, reconciliation
option, CPM vs per-project decision, and any excluded projects. Execution reads this.

## Transition to Execution

After `plan.md` and `tasks.md` are created and presented (via the `plan-generation` skill):

- **Guided mode**: Wait for user approval before proceeding. Do not load `execution.md` yet.
- **Automatic mode**: **Immediately** load this scenario's [execution.md](execution.md) and begin
  executing the first task. Do not stop, do not wait for user input. The plan has been surfaced —
  proceed.
