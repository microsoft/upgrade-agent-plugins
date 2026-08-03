# Planning Stage Instructions

Create an upgrade plan: confirm options (including strategy), then generate ordered tasks.

> **This file covers 5 steps.** Follow sequentially.
>
> | # | Step | Key Action |
> |---|------|------------|
> | 1 | Extract from Assessment | Read assessment signals |
> | 1.5 | Confirm Upgrade Options | Classify complexity → evaluate triggered options (including strategy) → confirm with user |
> | 2 | Load Strategy & Generate Plan | Follow chosen strategy's Planning Instructions |
> | 3 | Save Strategy & Constraints | Persist strategy + execution constraints in scenario-instructions.md |
> | 4 | Edge Cases | Circular deps, single project |

---

## Step 1: Extract from Assessment

### Reading Assessment Data

- **Small assessments** (<30KB): Read `assessment.md` directly
- **Large assessments** (≥30KB): Use `query_dotnet_assessment` tool if available; otherwise read in sections

### Signals to Extract

| Signal | Where to Find | Used For |
|--------|---------------|----------|
| Project count | Solution analysis | Strategy selection |
| Framework spread | Current frameworks per project | Strategy selection |
| Dependency depth | Dependency graph | Strategy selection, task ordering |
| Project types | ClassLibrary / AspNetCore / Worker | Task grouping |
| Project format | SDK-style vs old-style csproj | SDK-style conversion task, CPM eligibility |
| Package management | `PackageReference` vs `packages.config` | SDK-style conversion scope, CPM eligibility |
| Package risks | Security vulns, deprecated packages | Task priority |
| Complexity indicators | LOC, project complexity ratings | Strategy selection |
| Test Coverage recommendations | Global recommendation count and recommended project paths | Test Coverage applicability and generation scope |

Also extract: dependency graph (leaf → root ordering), project-to-project references.

### SDK-Style Project Detection

If any project uses old-style csproj format (identified by `<Project ToolsVersion=...>`,
`packages.config` files, or `<Import Project=...Microsoft.CSharp.targets>`), record:
- Which projects are old-style vs SDK-style
- Which old-style projects are web projects (System.Web) vs class libraries vs tests
- This directly feeds into: Package Management option default logic, SDK-style conversion task
  placement in the plan, and strategy execution ordering

---

## Step 1.5: Confirm Upgrade Options

### Upgrade Complexity Classification

Before evaluating options, classify the upgrade based on signals from Step 1.
**Do not show the classification reasoning or checklist to the user** — determine
the class silently and act on it.

| Class | Criteria | Behavior |
|-------|----------|----------|
| **Simple** | ALL of: every project targets modern .NET (`net5.0`+), all SDK-style, no incompatible packages, no .NET Framework projects, and no other signals from the trigger index have surfaced | Evaluate Upgrade Strategy and, when the assessment recommends Test Coverage, the Test Coverage option. Skip every other option. Write `upgrade-options.md`, then return the gate to the Orchestrator (see **Return the gate to the Orchestrator**). |
| **Complex** | Any .NET Framework project, incompatible packages, or other signals from the trigger index have surfaced | Proceed with Step 1.5 evaluation below |


---

### Re-entry Check

This scenario has a **planning gate**: upgrade options must be confirmed by the user before
the plan is generated. You are a one-shot worker and never pause for the user — the
Orchestrator runs the confirmation and re-dispatches you. So this step runs across **two
dispatches**. Before evaluating, determine which dispatch you are on:

| State | Meaning | Action |
|-------|---------|--------|
| `plan.md` exists | Options confirmed and plan already generated | Skip Step 1.5, proceed to Step 2 |
| The Orchestrator's dispatch includes **confirmed upgrade-option selections** (and no `plan.md` yet) | Gate already resolved — this is the re-dispatch | Skip evaluation. Write the confirmed selections to `scenario-instructions.md` (the compact `## Upgrade Options` block), then proceed to Step 2 to generate the plan |
| `upgrade-options.md` exists but no `plan.md` and no confirmed selections were passed | Options written on a prior dispatch but not yet confirmed | Do not regenerate — return `STATUS: needs_confirmation` with the options payload (see **Return the gate to the Orchestrator**) |
| Neither exists | Fresh run | Proceed with evaluation below |

**CI / headless session**: If `upgrade-options.md` does not exist, fail immediately:
```
ERROR: Upgrade Options not confirmed.
Run in interactive mode first to confirm options, then re-run in CI mode.
```

---

### CRITICAL: Step 1.5 must NOT produce visible reasoning in chat

The entire Step 1.5 — classification, trigger evaluation, option loading, and
default logic — is internal. Nothing from this step should appear in chat:

1. Do NOT show the complexity classification checklist or reasoning
2. Do NOT stream evaluation reasoning, applicability checks, or default logic analysis
3. Do NOT list options, triggers, or conditions in chat
4. If no options are applicable, write the "Not applicable" block to
   `scenario-instructions.md` and proceed to Step 2 without comment
5. If options ARE applicable, generate the file silently and present
   only the file for review — the file is the only presentation mechanism

---

### Evaluation (fresh run only)

Consult the [trigger index](upgrade-options/upgrade-options-index.md) to determine which option
files to load. Only load option files whose trigger condition is already met based
on evidence gathered so far (assessment, project files, user input, conversation).
Do not proactively inspect additional files just to check triggers.

Also scan Available Skills descriptions in context for the prefix `upgrade-option:`
(see [`upgrade-options/upgrade-options-index.md`](upgrade-options/upgrade-options-index.md) for the authoring
convention). For each match, load the skill and evaluate its `## Upgrade Option`
section the same way as built-in options. Custom options go under their declared
category heading in the draft file.

For each loaded option file, evaluate applicability and default logic.
Keep all evaluation reasoning internal — do not write it to any file or to the chat.

For each applicable option (built-in and custom), determine the selected value using this priority:

1. **User-stated preference** — from `scenario-instructions.md`, the initial request,
   or a linked issue/description. Must unambiguously match a recognized option value.
2. **Recommended default** — from the option's default logic.

Track which applicable options were resolved by user preference vs. default.

### Cross-option coherence check

After evaluating all options, verify that selected values are consistent with each
other:

1. For each applicable option, re-read its **"What is NOT configurable"** and
   **Default logic** sections — these contain interaction rules that reference
   other options by name (e.g., "if multi-targeting is selected…",
   "if Windows Compatibility Pack already selected…").
2. If a selected value contradicts or undermines another selected value, adjust
   whichever option has the weaker signal and note the interaction in the `Why`
   column of the draft.
3. The option files are the single source of truth for interaction
   rules — do not invent interactions that are not documented there.

---

### Generate Options File

Upgrade Strategy is always applicable, so at minimum the file contains the
strategy selection. Write `upgrade-options.md` to the working folder using the
format defined in [`upgrade-options/upgrade-options-index.md`](upgrade-options/upgrade-options-index.md).
The Strategy section always appears first.

Rules:
- Include only applicable options — omit non-applicable ones entirely
- Mark the selected value with `**{value}** (selected)` in each option's table: user preference when available, recommended default otherwise
- Include a short description for every value (selected and alternatives)
- Do not present options in chat — the file is the presentation

---

### Return the gate to the Orchestrator

**Do not call `show_upgrade_options` and do not pause here.** You are a one-shot worker; only
the Orchestrator talks to the user. Upgrade options affect the entire upgrade approach and
must be confirmed by the user, but that confirmation is the Orchestrator's job.

After writing `upgrade-options.md`:

1. Build the options JSON from your evaluation above (construct it in memory from the same
   applicable options and selected values — do **not** rely on re-reading the file). This is
   the payload the Orchestrator will pass to `show_upgrade_options`.
2. **Stop. Do not generate the plan or tasks.** Return `STATUS: needs_confirmation` with:
   - a one-line note that upgrade options need user confirmation,
   - the options JSON inline,
   - the `upgrade-options.md` path.

The Orchestrator renders the interactive form (or a text confirmation), collects the user's
selections, and re-dispatches you with the confirmed selections. On that re-dispatch the
Re-entry Check routes you to write the confirmed `## Upgrade Options` block to
`scenario-instructions.md` and continue to Step 2.

---

## Step 2: Select Upgrade Strategy

### Assessment Signals

Two categories of signals determine strategy:

**Structural signals** (from dependency graph):
---

## Step 2: Load Strategy & Generate Plan

Read the confirmed strategy from `scenario-instructions.md` (the confirmed `## Upgrade
Options` block written when the gate was resolved — see the Re-entry Check).
The strategy was selected and confirmed as part of upgrade options — no separate
selection step is needed.

### Apply Test Coverage Option

Read the confirmed Test Coverage value from `scenario-instructions.md`:

- **Skip** or not present: add no test-baseline work.
- **Generate**: follow the `## Generate flow` in
  [`upgrade-options/test-coverage.md`](upgrade-options/test-coverage.md) before generating the plan.
  The flow may satisfy the plugin prerequisite, change the selection to **Skip**, or stop the current
  run.

### Strategy Modifiers

These are not standalone strategies but can be applied on top of any strategy:

- **Side-by-side web migration**: When the Project Approach upgrade option
  selects Side-by-side for ASP.NET Framework web projects, scaffold/migrate
  tasks are injected into the plan alongside the chosen strategy's tasks.
  Old project removal is a post-upgrade step, not a plan task.
  See [planning-rules/framework-migration.md](planning-rules/framework-migration.md)
  for task injection rules.
- **Group segmentation**: For heterogeneous solutions where different project
  groups need different approaches, segment into independent groups and apply
  the best-fit strategy per group.

### Planning Rules (all strategies)

Before loading the strategy file, evaluate these rules against the assessment.

#### Common rules (all project flavors)

- Test project work is always part of the task that caused the need,
  not standalone tasks
- When generating migration tasks that move code between
  projects, note in the description that test references must be updated
- The strategy task template is the authoritative task shape — it includes
  prerequisites as the first task and final validation as the last task

#### Flavor-specific planning guidance

Load only the files matching the assessment signals. These provide
conditional rules for task generation specific to the project types
found in the assessment.

| Flavor | Load when | File |
|--------|-----------|------|
| .NET Framework migration | Any project targets .NET Framework (`net4*`) | [planning-rules/framework-migration.md](planning-rules/framework-migration.md) |
| Modern .NET upgrade | All projects on modern .NET (`net5.0`+) | [planning-rules/modern-upgrade.md](planning-rules/modern-upgrade.md) |

### Load strategy file

Read the chosen strategy file from `strategies/`:
- [all-at-once.md](strategies/all-at-once.md)
- [bottom-up.md](strategies/bottom-up.md)
- [top-down.md](strategies/top-down.md)

### Follow strategy's Planning Instructions

Each strategy file has a **Planning Instructions** section that defines:
- Required plan.md structure (phases, groups, pilot selection, etc.)
- What assessment data to include in the plan
- Strategy declaration block for plan.md

Follow those instructions to generate plan.md.

### Common plan.md requirements (all strategies)

- Use the plan-generation skill's template format exactly:
  ```
  ### {NN}-{short-name}: {task short description}

  {1-3 paragraph description with scope, context, risks}

  **Done when**: {verifiable success criteria}
  ```
- The task ID and task short description MUST be on the same `###` line, separated by a colon

- Task numbering starts at `01`, not `00`
- The description is 1-3 paragraphs (not a one-liner), with enough detail
  for the executor to research and execute — see "Task description richness" below
- Each task describes **what** to upgrade, not **how**
- Task IDs: `{NN}-{short-name}` format where short-name describes the **content** being upgraded, not the strategy position (e.g., `02-foundation-libs`, `03-business-logic`, `04-web-apps`). Never use strategy jargon like `tier1`, `phase1`, `batch-a` as the short-name.
- Include the strategy declaration block from the strategy file
- The strategy template's numbered list is a CHECKLIST of what tasks to include — not a format to copy. Transform each applicable item into the plan-generation template format above.

### Task description richness

Each task's description paragraph (the content block in plan.md, not the
one-line title) should contain enough context for the executor to research
and execute the task effectively. Include:

- **Scope** — which specific projects are affected by this task
- **Assessment context** — key signals from the assessment relevant to
  this task (incompatible package count, API issue count, technologies
  detected in the affected projects)
- **Known risks** — things the assessment flagged that this task will
  encounter (e.g., "23 incompatible packages", "Autofac DI container",
  "OWIN middleware pipeline")
- **Research starting points** — what the executor should investigate
  before starting work (e.g., "check EF6 DbContext initializers",
  "inventory System.Web references in library projects")

The description does NOT need step-by-step execution instructions —
that's the executor's job after research. But it should give the
executor enough starting points to know _what to look at_.

---

## Step 3: Save Strategy & Constraints

The strategy was already confirmed in Step 1.5 (upgrade options) and written
to `scenario-instructions.md` as part of the compact block. Now add execution
constraints distilled from the strategy file:

```markdown
## Strategy
**Selected**: [Strategy Name]
**Rationale**: [Why this strategy fits — cite assessment signals]

### Execution Constraints
- [3-5 bullets distilled from the strategy's Execution Guidelines]
- [Focus on ordering rules, validation checkpoints, and phase transitions]
- [These are what the execution stage needs — not the full strategy doc]
```

**Examples of execution constraints by strategy:**
- **All-at-Once**: "Single atomic upgrade — all projects updated together; validate full solution build after upgrade"
- **Bottom-Up**: "Strict tier ordering: Tier N must complete and validate before Tier N+1; between-tier validation: confirm higher tiers still build"
- **Top-Down**: "Applications first; add multi-targeting to libraries only when needed; Phase 2 (consolidation) only after all apps upgraded"
- **Bottom-Up with side-by-side web migration**: "Strict tier ordering; scaffold must complete before migrate starts; old project remains live during migrate; old project NOT deleted — post-upgrade step"

If user provided custom instructions instead of picking a strategy:
```markdown
## Strategy
**Selected**: Custom
**User instructions**: [paste user's custom strategy instructions]

### Execution Constraints
- [Distill key constraints from user's custom instructions]
```

This persists the strategy so the execution stage operates from scenario-instructions.md without re-reading the strategy file.

### Commit Strategy Default

**Skip this section if the repo is not a git repo** (no `## Source Control` section
in `scenario-instructions.md`).

After selecting the upgrade strategy, check whether the strategy's recommended
commit approach differs from the current Commit Strategy in `scenario-instructions.md`:

| Upgrade Strategy | Recommended Commit Strategy | Rationale |
|-----------------|------------------------|----------|
| All-at-Once | Single Commit at End | One atomic upgrade, one commit |
| Bottom-Up | After Each Task | Each tier validated separately, commit after each |
| Top-Down | After Each Task | Each app upgraded independently |
| Custom / unclear | After Each Task | Safest default |

If the strategy file itself specifies a commit approach (e.g., "prefer single commit"),
follow the strategy file's recommendation over this table.

**If the recommended commit strategy differs from the current value** (set during
pre-initialization), update `scenario-instructions.md` AND inform the user in chat:

> Commit strategy updated to **{new strategy}** (was: {old strategy}) — better fit
> for {strategy name}. You can change this anytime.

If the recommended strategy matches the current value, no message needed.

The user can change this at any time — save their preference to `scenario-instructions.md`.

---

## Step 4: Edge Cases

### Circular Dependencies

Stop and present options:
1. Extract shared interface to new project
2. Merge projects
3. Proceed anyway (may cause build issues)

Get user decision before continuing.

### Single Project

Use All-at-Once strategy (this also applies to single .NET Framework projects).
Simplified plan with single task — no phasing needed.

---

## Transition to Execution

After `plan.md` and `tasks.md` are created and presented (via the plan-generation skill):

- **Guided mode**: Wait for user approval before proceeding. Do not load execution.md yet.
- **Automatic mode**: **Immediately** load this scenario's [execution.md](execution.md) (read it completely) and begin executing the first task. Do not stop, do not wait for user input, do not yield the conversation. The plan has been surfaced — proceed.