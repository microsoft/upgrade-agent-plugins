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
| **Simple** | ALL of: every project targets modern .NET (`net5.0`+), all SDK-style, no incompatible packages, no .NET Framework projects, and no other signals from the trigger index have surfaced | Skip all options EXCEPT Upgrade Strategy. Evaluate strategy, write it to `upgrade-options.md` (strategy-only file), confirm with user, then write compact block to `scenario-instructions.md`. Proceed to Step 2. |
| **Complex** | Any .NET Framework project, incompatible packages, or other signals from the trigger index have surfaced | Proceed with Step 1.5 evaluation below |

---

### Re-entry Check

Before evaluating, check the working folder (`.github/upgrades/{scenarioId}/`):

| State | Action |
|-------|--------|
| `plan.md` exists | Options already confirmed and plan generated — skip Step 1.5, proceed to Step 2 |
| `upgrade-options.md` exists but no `plan.md` | Options written but not yet confirmed — open it, ask user to confirm, do not regenerate |
| Neither exists | Fresh run — proceed with evaluation below |

**CI / headless session**: If `upgrade-options.md` does not exist, fail immediately:
```
ERROR: Upgrade Options not confirmed.
Run in interactive mode first to confirm options, then re-run in CI mode.
```

---

### ⛔ CRITICAL: Step 1.5 must NOT produce visible reasoning in chat

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

### User Confirmation

**Always pause here — even in Automatic mode.** Upgrade options affect the
entire upgrade approach and must be explicitly confirmed by the user.

**If `show_upgrade_options` is in your tool list** (MCP Apps supported):

1. Build the options JSON from your evaluation above (do **not** read any file — construct it in memory).
2. Call `show_upgrade_options(optionsJson=<json>, scenarioFolder=<path>)`. The tool renders an interactive dropdown form in chat and blocks until the user confirms or cancels.
3. Wait for the result and handle:
   - **`confirmed=true`, `changed` is non-empty**: update `upgrade-options.md` to reflect the confirmed selections (move the `**value** (selected)` marker to the confirmed row for each changed option), then write the compact `## Upgrade Options` block to `scenario-instructions.md`. Proceed to Step 2.
   - **`confirmed=true`, `changed` is empty**: write the compact `## Upgrade Options` block to `scenario-instructions.md`. Proceed to Step 2.
   - **`confirmed=false`**: stop immediately. Ask the user how they would like to continue.
   - **`error` returned**: fix the JSON schema error described in the response and call `show_upgrade_options` again immediately. Do not proceed until the form has been shown.
   - **`refreshed=true` returned** (user clicked Refresh): re-read `upgrade-options.md`, rebuild the `optionsJson` from the file contents, then call `show_upgrade_options(optionsJson=<updated json>, stateId=<same stateId>)` immediately. The existing UI frame refreshes in place — do not create a new pending session.

**Otherwise (no `show_upgrade_options` tool)**:
Open `upgrade-options.md` in the editor and pause with:

> Review the upgrade options above. Move `(selected)` to a different row to
> change a selection, or tell me what to adjust. Confirm when ready to proceed.

Wait for user response. Three possible outcomes:

**User confirms as-is**: proceed to Finalize below.

**User edits file directly**: re-read the file, validate Selected values are
recognized options (not typos or unsupported values), confirm back, proceed to Finalize.

**User asks for a change in chat**: update the `(selected)` marker in the relevant option's
table, save the file, wait for final confirmation before proceeding.

---

### Finalize

**If `show_upgrade_options` was used**: the `selections` object in the tool result contains the confirmed values. Use those directly; do **not** re-read `upgrade-options.md` to determine selections (the file may not have been updated yet if `changed` was empty).

**If the markdown flow was used**:
1. Read all `**{value}** (selected)` markers from the option tables
2. Write the compact `## Upgrade Options` block to `scenario-instructions.md`
   using the format defined in [`upgrade-options/upgrade-options-index.md`](upgrade-options/upgrade-options-index.md)
3. Proceed to Step 2 — do not summarize or recap

---

## Step 2: Select Upgrade Strategy

### Assessment Signals

Two categories of signals determine strategy:

**Structural signals** (from dependency graph):
---

## Step 2: Load Strategy & Generate Plan

Read the confirmed strategy from `scenario-instructions.md` (written by Step 1.5 Finalize).
The strategy was selected and confirmed as part of upgrade options — no separate
selection step is needed.

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