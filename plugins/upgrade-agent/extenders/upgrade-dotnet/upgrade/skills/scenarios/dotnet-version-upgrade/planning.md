# Planning Stage Instructions

Create an upgrade plan: confirm options (including strategy), then generate ordered tasks.

> **This file covers 5 steps.** Follow sequentially.
>
> | # | Step | Key Action |
> |---|------|------------|
> | 1 | Extract from Assessment | Read assessment signals |
> | 1.5 | Confirm Upgrade Options | Classify complexity → evaluate triggered options (including strategy) → confirm with user |
> | 2 | Load Strategy & Generate Plan | Follow chosen strategy's Planning Instructions; record confirmed options in `plan.md` |
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
| Cookie authentication on Framework web projects | Auth signals already surfaced — `<authentication mode="Forms">` or `FormsAuthentication.*`, OWIN/Katana cookie middleware (`UseCookieAuthentication`, `CookieAuthenticationOptions`), ASP.NET Identity cookie sign-in, or a `<machineKey>`-protected authentication cookie, seen while reading the assessment or project files. A bare `Microsoft.Owin.Security.*` or `Microsoft.AspNet.Identity.*` package reference, or a `<machineKey>` entry on its own, is a hint to note rather than proof — those also appear in bearer-token-only and ViewState-only apps. Do not open files to go looking for any of it. Carry a hint forward as a hint: it does not fire the trigger by itself, but where it is the only cookie-auth evidence available, ask the user whether the app signs users in with a cookie rather than letting the question drop — the definitive signals usually sit in `Startup.Auth.cs`, which this step does not open | Cross-App Cookie Authentication trigger |

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
| **Simple** | ALL of: every project targets modern .NET (`net5.0`+), all SDK-style, no incompatible packages, no .NET Framework projects, and no other signals from the trigger index have surfaced | Evaluate Upgrade Strategy and, when the assessment recommends Test Coverage, the Test Coverage option. Skip every other option. Then take the gate to confirmation (see **Confirming the options**). |
| **Complex** | Any .NET Framework project, incompatible packages, or other signals from the trigger index have surfaced | Proceed with Step 1.5 evaluation below |


---

### Re-entry Check

This scenario has a **planning gate**: upgrade options must be confirmed by the user
before the plan is generated. Before evaluating, determine where you are:

| State | Meaning | Action |
|-------|---------|--------|
| `plan.md` exists | Options confirmed and plan already generated | Skip Step 1.5, proceed to Step 2 |
| `scenario-instructions.md` has a `## Upgrade Options` block, or you were dispatched with **confirmed selections** (and no `plan.md` yet) | Gate already resolved | **Treat the confirmed selections as final** — do not re-derive any value, and do not reload option files to re-check applicability, default logic, or alternatives; that work is spent. Write the confirmed selections to `scenario-instructions.md` (the compact `## Upgrade Options` block) and proceed to Step 2, observing the reopening rule below |
| Neither | Fresh run | Proceed with evaluation below |

**Reopening option files after the gate.** Consider only options that appear in the
confirmed `## Upgrade Options` block — an option absent from that block was not
applicable, and its file must never be opened. Among those:

- **Built-in options** — reopen the file **if and only if** the
  [index](upgrade-options/upgrade-options-index.md) marks it **Plan impact: Yes**, and
  read only the sections that row names. Reopening a **Plan impact: No** file is a
  mistake; skipping a **Yes** one silently drops behavior from the plan.
- **Custom options** (from `upgrade-option:` skills) — these have no index row, so the
  marker lives in the skill's own `## Upgrade Option` section. Reopen the skill, read
  its `**Plan impact**:` line, and apply the same rule. If the line is absent, treat it
  as **Yes** and read the whole `## Upgrade Option` section. Reading the marker already
  requires opening the skill, so this fail-safe costs nothing beyond the extra prose,
  and it cannot be linted the way the built-in table can.

**CI / headless session**: if `scenario-instructions.md` has no `## Upgrade Options`
block **and** you were not dispatched with confirmed selections, fail immediately:
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
3. Do NOT narrate which options you loaded, or list triggers or conditions
4. If no options are applicable, write the "Not applicable" block to
   `scenario-instructions.md` and proceed to Step 2 without comment

The **only** thing that may surface is the finished confirmation itself — the
options and their selected values, presented for the user to confirm.

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

1. For each applicable option, re-read its **"What is NOT configurable"**,
   **Default logic**, and **Interactions** sections — these contain interaction
   rules that reference other options by name (e.g., "if multi-targeting is
   selected…", "if Windows Compatibility Pack already selected…").
2. If a selected value contradicts or undermines another selected value, adjust
   whichever option has the weaker signal and note the interaction in the `Why`
   column of the draft.
3. Re-check any option whose **applicability** depends on another option's value —
   the option file says so explicitly when it does. If that value moved during this
   pass, re-evaluate: an option that is no longer applicable drops out of the payload
   entirely (never present a selection the user cannot act on), and one that has
   become applicable is evaluated and added.
4. The option files are the single source of truth for interaction
   rules — do not invent interactions that are not documented there.

---

### Build the Confirmation Payload

Upgrade Strategy is always applicable, so at minimum the payload contains the
strategy selection. Build the payload **in memory** using the schema in
[`upgrade-options/upgrade-options-index.md`](upgrade-options/upgrade-options-index.md).
Strategy always comes first.

Rules:
- Include only applicable options — omit non-applicable ones entirely
- `selected` is the user's stated preference when available, the recommended default otherwise
- Every option needs a `rationale`; every choice needs a `description`
- **Do not write an options file.** There is no `upgrade-options.md`. The payload is
  the only carrier until the user confirms

---

### Confirming the options

Upgrade options affect the entire upgrade approach and **must** be confirmed by the
user before the plan is generated. Who runs that confirmation depends on the host:

| You are | Action |
|---------|--------|
| A **one-shot worker** (you were dispatched by an Orchestrator and have no user channel) | **Stop. Do not generate the plan or tasks.** Return `STATUS: needs_confirmation` with a one-line note, the confirmation payload inline, and nothing else. The Orchestrator owns the user conversation and will re-dispatch you with the confirmed selections. Never call an options-confirmation tool and never pause for the user yourself. |
| The **single agent** that also talks to the user | Run the confirmation yourself using the ladder below, then continue to Step 2 with the confirmed selections. |

**Confirmation ladder** (use the first tier available to you):

1. **`show_upgrade_options`** — if it is in your tool list, call it with the payload.
   It renders an interactive form and blocks until the user confirms or cancels.
2. **Chat + interactive question** — render the payload as text using the
   **Rendering the payload as text** spec in the trigger index, then ask a **single**
   combined question with `ask_user` / `ask_question`. Offer confirming everything as
   one choice and changing something as another. Never ask one question per option.
3. **Plain text only** — same rendered block, then "reply `confirm`, or tell me what
   to change."

For tiers 2 and 3 the rendered block is **your chat response**, not question-tool
content. Interactive question UI vanishes once answered, so options rendered inside
it cannot be reviewed while the user decides what to change. Print the block first,
then ask only "Confirm these upgrade options?" with its choices — never restate
options, values, or alternatives inside the question or its choice labels. If the
user changes something, re-print the full updated block before asking again.

The user may confirm as-is, override individual values, or describe changes in prose
("use top-down and skip test coverage"). Resolve whatever they say into a final
selection set — one value per applicable option — before continuing. If the user
cancels, stop; do not generate a plan.

Once confirmed, write the compact `## Upgrade Options` block to
`scenario-instructions.md` and proceed to Step 2.

---

## Step 2: Load Strategy & Generate Plan

Option **values** come from the confirmed `## Upgrade Options` block in
`scenario-instructions.md` — never from re-reading an option file. Reopen a file only
for its **Plan impact** sections, per the reopening rule in the Re-entry Check.

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
- **Shared-database pin.** When Project Approach is **Side-by-side** and the Framework host's
  configuration carries a connection string to an application database the assessment does not
  show being replaced, both hosts will run against one live database. Add
  `#skill:managing-shared-database-schema` to the description of **every** task whose scope
  touches that database — its schema, a `DbContext`, an entity model, a connection string, a
  migration, a repository, or raw SQL — whatever those tasks happen to be named and whichever
  strategy is in use. The pin attaches the skill deterministically; without it the skill must
  win a relevance ranking against the whole catalog, and it loses to the project-type and
  DbContext skills, which are correct about *moving code* and silent about *not breaking a live
  shared schema*. This rule is not conditional on any flavor file being loaded — see
  [planning-rules/framework-migration.md](planning-rules/framework-migration.md) only for the
  detection detail.

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

- Include an `## Upgrade Options` section recording the confirmed selections, using the
  format in [`upgrade-options/upgrade-options-index.md`](upgrade-options/upgrade-options-index.md).
  `plan.md` is written only after every option is confirmed, so this section is a durable
  record of the final set — write it once and never revise it. Omit the section entirely
  when no options were applicable.
- Use the canonical plan.md template format exactly:
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
- The strategy template's numbered list is a CHECKLIST of what tasks to include — not a format to copy. Transform each applicable item into the plan.md template format above.

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
  "OWIN middleware pipeline"). For a side-by-side web migration, this
  includes whether signed-in users survive the host boundary: if a
  .NET Framework host authenticates browser requests with a cookie and
  no cross-app cookie mechanism was confirmed, record that how identity
  crosses the boundary is unresolved, and that users may have to sign in
  again on the modern host unless the migration establishes it. Do not
  state the sign-out as settled — where the adapters migrate phase can
  actually apply it still wires a pre-option default — and name only
  remedies the evidence supports: retargeting
  the Framework host applies to any such host, whereas sharing the
  cookie itself is only worth raising where OWIN cookie middleware is
  already in evidence. State it as a migration risk in the task's own
  words — do not name or refer to an upgrade option that is not in the
  confirmed set. This note informs the reader; it is not a decision
  record, and no migrate-phase skill branches on it.
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

After the plan is created and presented:

- **Guided mode**: Wait for user approval before proceeding. Do not load execution.md yet.
- **Automatic mode**: **Immediately** load this scenario's [execution.md](execution.md) (read it completely) and begin executing the first task. Do not stop, do not wait for user input, do not yield the conversation. The plan has been surfaced — proceed.