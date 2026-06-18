---
name: scenario-initialization
description: Pre-initialization flow for all scenarios — gathers source control and scenario-specific parameters in one step, then initializes the workflow
metadata:
  discovery: system
---

# Scenario Initialization Guide

Handles the pre-initialization phase that runs **before** `initialize_scenario` is called. This phase gathers all required parameters — both system-level (source control) and scenario-specific — and presents them to the user in a **single consolidated prompt**.

> **This skill covers 4 sections.** Read all before starting initialization.
>
> | # | Section | Key Content |
> |---|---------|-------------|
> | 1 | Overview & Flow | When this runs, what it produces |
> | 2 | Gather All Parameters | Source control detection + scenario-specific tool calls |
> | 3 | Present & Confirm | Single consolidated prompt to the user |
> | 4 | Apply & Initialize | Handle source control, call `initialize_scenario` |

---

## 1. Overview & Flow

This phase runs after a scenario is matched and its instructions are loaded, but **before** `initialize_scenario` creates the workflow folder. The goal is to collect all initialization parameters and get user confirmation in **one interaction** — no wizard-style multi-step Q&A.

> **Two confirmation paths** — which one runs depends on whether the `confirm_options` tool is listed in your tool list:
>
> | Path | When | Behavior |
> |------|------|----------|
> | **Interactive card** | `confirm_options` is available | Call the tool — it shows a rich UI card and blocks until the user clicks Confirm or Cancel |
> | **Text fallback** | `confirm_options` is NOT in your tool list | Present the gathered parameters as text and wait for user reply |

```
Scenario matched + instructions loaded
    ↓
Gather parameters (source control + scenario-specific) ← tool calls, NO user interaction yet
    ↓
confirm_options available?
    ├─ YES → Call confirm_options(title, description, options)  ← REQUIRED when available
    │            Tool blocks and returns { confirmed, values }
    └─ NO  → Present parameters as text ← use Text fallback path in Section 3
    ↓
Apply source control changes (stash, branch switch)
    ↓
Call initialize_scenario ← now on the correct branch
    ↓
Continue to scenario's first stage (e.g., Assessment)
```

## 2. Gather All Parameters

Make all necessary tool calls to collect defaults **before** presenting anything to the user.

### 2.1 Flow Mode Detection

Determine the flow mode from user's request or default to **Automatic**.

| Parameter | Default | Notes |
|-----------|---------|-------|
| **Flow Mode** | Automatic | How the agent pauses. Automatic = run end-to-end, pause only when blocked. Guided = pause after each stage for review. |

**Detecting from user intent**: If the user's message contains cues like "just do it", "go ahead and upgrade everything", "don't stop", "automatic" -> Automatic. If it contains "step by step", "let me review", "guided", "pause after each step" -> Guided. Otherwise -> Automatic (default).

### 2.2 Source Control Detection

Detect whether the user is in a git repository. Use available git tools to determine:

- Whether a git repo exists at the working directory
- Current branch name
- Whether there are pending (uncommitted) changes
- Available branches (to suggest a source branch)

**If NOT in a git repo**: Skip all source control parameters. Only gather scenario-specific parameters.

### 2.3 Compute Source Control Defaults

When in a git repo, prepare these defaults:

| Parameter | Default | Notes |
|-----------|---------|-------|
| **Source branch** | Current branch | The branch work is based on |
| **Working branch** | `{scenarioId}-{short-suffix}` (new) | User may also choose current branch or any existing branch. See branch selection below |
| **Pending changes** | Auto-detected | Default action: **commit** (alternatives: stash, undo) |
| **Commit strategy** | After Each Task | When to commit during execution (alternatives: After Each Phase, Single Commit at End, Manual) |
| **Branch sync** | Auto (Merge) | How to sync the working branch with its source during the upgrade. Alternatives: Auto (Rebase), Manual, Disabled. See the `branch-sync` skill. |

#### Working branch selection

The user can choose one of three options:

1. **New branch** (default) — generate a candidate name (e.g., `upgrade-dotnet-10`). If it already exists locally, pick the next available incrementing suffix in a **single** step: list all existing branches once (e.g., `git branch --list "upgrade-dotnet-10*"`), find the highest existing numeric suffix `N`, and use `N+1` (or use the base name if it doesn't already exist). Do **not** probe candidates one at a time by repeatedly checking `-1`, `-2`, `-3`, …. The user may also supply their own new branch name.
2. **Current branch** — stay on the branch they are already on.
3. **Existing branch** — switch to another branch that already exists locally.

Accept any of these without pushback. Do not insist on creating a new branch.

### 2.4 Scenario-Specific Parameters

The loaded scenario skill may define a **Pre-Initialization** section listing scenario-specific tools to call and parameters to gather. Check the scenario instructions for this section and follow its guidance.

- If the scenario defines pre-init tools → call them and collect the returned parameters
- If the scenario has no pre-init section → source control parameters alone are sufficient

**Important**: Scenario-specific tools may also return source control information (e.g., a scenario-aware working branch name). Use those values — they override the generic defaults from Section 2.2.

## 3. Present & Confirm

### Tool Detection Checklist — run this BEFORE presenting

Check your tool list in this order. **Stop at the first match.**

1. `confirm_options` available? → Use **Section 3.1** (Interactive Card)
2. `ask_question` or `ask_user` available? → Use **Section 3.2** (Text + Interactive Question)
3. Neither available? → Use **Section 3.3** (Text-only Fallback)

⛔ Do NOT skip to Section 3.3 if an interactive tool is available.

---

### 3.1 Interactive Card — `confirm_options` IS in your tool list

⛔ **MANDATORY when available**: Call `confirm_options` — do NOT write a text confirmation to the user. Call this tool immediately after gathering parameters. It handles the interactive UI internally.

⛔ **BLOCKING**: The `confirm_options` tool blocks until the user interacts with the UI. Do NOT write any response to the user while the tool is running. Do NOT proceed to Section 4 until the tool returns `{ confirmed, values }`.

1. Build the `options` JSON array from the gathered parameters, then call `confirm_options`:
   ```
   confirm_options(
     title: "Upgrade .NET projects to .NET 10",
     description: "Review and confirm upgrade settings before we begin.",
     options: "<JSON array string — see structure below>"
   )
   ```

   **Options array structure** (include only what applies):
   ```json
   [
     // Scenario-specific options first (defined by the scenario's Pre-Initialization section):
     {"id":"tfm","type":"select","label":"Target Framework","value":"net10.0",
      "choices":[{"id":"net10.0","label":".NET 10 (LTS)","hint":"LTS"},{"id":"net9.0","label":".NET 9 (STS)","hint":"STS"}]},

     // Flow mode always present:
     {"id":"flowMode","type":"select","label":"Flow Mode","value":"automatic",
      "description":"How the agent pauses during execution",
      "choices":[{"id":"automatic","label":"Automatic","hint":"Run end-to-end, pause only when blocked"},
                 {"id":"guided","label":"Guided","hint":"Pause after each stage for review"}]},

     // Source control — ONLY include these when in a git repo:
     {"id":"workingBranch","type":"text","label":"Working Branch","value":"upgrade-dotnet-10"},
     {"id":"commitStrategy","type":"select","label":"Commit Strategy","value":"after-each-task",
      "choices":[{"id":"after-each-task","label":"After Each Task","hint":"default"},
                 {"id":"after-each-phase","label":"After Each Phase"},
                 {"id":"single","label":"Single Commit at End"},
                 {"id":"manual","label":"Manual"}]},

     // Readonly info fields at the end:
     {"id":"solution","type":"readonly","label":"Solution","value":"<solution path>"}
   ]
   ```
   - `options` must be a **JSON string** (not an object) — stringify the array before passing.
   - **Git fields**: Include `workingBranch` and `commitStrategy` only when in a git repo. Do NOT use `visibleWhen` for git-conditional fields — simply omit them when not in a git repo.
   - `visibleWhen` is for user-driven conditional visibility (e.g., show `branchName` only when user enables `createBranch`).

2. The tool returns one of:
   - **`confirmed: true`** → use `values` dictionary and proceed to Section 4.
   - **`confirmed: false`** → user cancelled — stop and ask how to proceed.

---

### 3.2 Text + Interactive Question — `ask_question`/`ask_user` IS in your tool list (but `confirm_options` is NOT)

### ⛔ CRITICAL: One Response, All Parameters

Present ALL gathered parameters — source control AND scenario-specific — in a **single response**. Do NOT split this into multiple questions.

**Two-step pattern:**

1. **Present** all gathered settings as formatted text (see Response Template below)
2. **Immediately after** the text response, call the interactive question tool with exactly two options:
   - A confirmation option (e.g., "Confirm and start")
   - A change option (e.g., "I want to change something")

⛔ **Do NOT enumerate parameter alternatives as options** (e.g., "Change to .NET 9", "Switch to Guided mode"). This confuses users into thinking alternatives are being recommended.

⛔ **Do NOT skip the tool call.** If `ask_question` or `ask_user` is in your tool list, you MUST call it. Do not fall through to Section 3.3.

---

### 3.3 Text-only Fallback — NO interactive tools available

### ⛔ CRITICAL: One Response, All Parameters

Present ALL gathered parameters — source control AND scenario-specific — in a **single response**. Do NOT split this into multiple questions.

Present using the Response Template below, then add this footer:
```
**To proceed**: Reply `confirm` or `start`
**To change**: Just specify what to adjust
```

---

### Response Template (used by Sections 3.2 and 3.3)

Use this structure, including only the sections that are relevant:

<response_template>
Before we begin, please confirm these settings:

{scenario-specific parameters section — as defined by the scenario's Pre-Initialization section}

#### Flow Mode
Mode: **{flow_mode}** {flow_mode_description}

Available options:
- **Automatic** — Run end-to-end, only pause when blocked or needing your input *(default)*
- **Guided** — Pause after each stage (assessment, plan, breakdowns) for your review

{source control section — only if in a git repo:}

#### Source Control
- Source branch: `{current_branch}`
- Working branch: `{working_branch}` *(new)* — or specify an existing branch name, or reply "use current branch" to stay on `{current_branch}`
- Pending changes: *None* (or: *Detected — will be committed before switching branches. Other options: stash, undo*)
- Commit strategy: **After Each Task** *(alternatives: After Each Phase, Single Commit at End, Manual)*
- Branch sync: **Auto (Merge)** *(alternatives: Auto (Rebase), Manual, Disabled)*
</response_template>

### Adaptation Rules

- **No git repo**: Omit the entire "Source Control" section
- **No pending changes**: Show "Pending changes: *None*"
- **With pending changes**: Show "Pending changes: *Detected — will be committed before switching branches. Other options: stash, undo*"
- **No scenario-specific params**: Show only source control section
- **Scenario provides custom template**: Merge scenario template into this structure

### Handling Parameter Changes

If user wants to change something:

1. Update the parameter value in memory
2. **DO NOT** re-call initialization tools — use the already-gathered data
3. For scenario-specific parameter changes: follow the scenario's Pre-Initialization section for validation guidance
4. For branch changes: if user names an existing branch, switch to it; if user provides a new name, verify it doesn't already exist; if user says "current branch", stay put
5. Confirm the updated parameters with the user

**Parameter changes are NOT a new scenario** — do not restart the flow.

## 4. Apply & Initialize

### Waiting for Confirmation

- **Section 3.1** (`confirmed: true`): The user clicked Confirm in the UI. Use the returned `values` and proceed immediately.
- **Section 3.1** (`confirmed: false`): The user clicked Cancel. Stop and ask how to proceed.
- **Section 3.2**: The user selected "Confirm and start" via the interactive question. Proceed immediately.
- **Section 3.3** (text-only): Wait for the user to reply "confirm", "start", "proceed", "looks good", "continue", or "approve". **Never auto-proceed** — even in Automatic mode with obvious defaults.

> ⛔ **There is no skip.** Do not proceed without `confirmed: true` from the tool or explicit user confirmation of the text fallback. "Automatic mode" means the agent runs without pausing during execution — it does NOT mean skipping the pre-start confirmation.

Once you have confirmation:

### 4.1 Handle Source Control

If in a git repo:

1. **Pending changes**: If detected, apply the user's chosen action (default: commit):
   - **Commit** (default): Stage and commit all pending changes on the current branch with a descriptive message (e.g., "Save work before starting {scenarioId}")
   - **Stash**: Run `git stash` to shelve changes
   - **Undo**: Discard all pending changes (`git checkout -- .`)
2. **Branch**: If user chose current branch, do nothing. If user chose an existing branch, switch to it. If user chose a new branch, create it from the source branch and switch to it.
3. **Verify**: Confirm you're on the correct branch before proceeding

### 4.2 Call `initialize_scenario`

Now that you're on the correct branch:

```
initialize_scenario(scenarioId='<scenario-id>', repoRoot='<path>')
```

This creates the workflow folder and `scenario.json` — but NOT `scenario-instructions.md`.

### 4.3 Create scenario-instructions.md with Confirmed Parameters

⛔ You MUST create this file yourself at the `artifacts.instructionsFile` path returned by `initialize_scenario`.

Write it immediately with all confirmed pre-init parameters:

```markdown
# {Scenario Display Name}

## Preferences
- **Flow Mode**: {Automatic | Guided}
- **{Scenario-Specific Param}**: {confirmed value}

## Source Control
- **Source Branch**: {source_branch}
- **Working Branch**: {working_branch}
- **Commit Strategy**: {commit_strategy}
- **Branch Sync**: {branch_sync}
```

- Always include Flow Mode and all scenario-specific parameters from Section 2.4
- Include `## Source Control` only if in a git repo
- Do **not** write `Last Sync Commit` or `Last Reconciled Commit` at init — the `branch-sync` skill writes `Last Sync Commit` on the first successful sync (it falls back to `git merge-base` until then), and `plan-reconciliation` writes its own field.
- Omit sections that have no confirmed values
- Do NOT add empty placeholder sections (e.g., `## User Preferences` with no content) —
  those sections are created on-demand when preferences are actually expressed
- Do NOT write machine-local paths (absolute file paths to solutions, projects, or
  directories) — these are runtime values available from tools and break when the
  repo is cloned elsewhere. Only write portable, repo-relative values and
  user-confirmed preferences (e.g., target framework, strategy choices).

### 4.4 Call `show_scenario_links` (⛔ MANDATORY if available)

If `show_scenario_links` is in your tool list, call it immediately after `initialize_scenario` returns — **NEVER skip this**:

```
show_scenario_links(
  path='<repoRoot>',
  title='<scenario one-liner description>',
  eventLabel='Scenario initialized',
  eventStatus='initialized'
)
```
⚠️ Do NOT pass `taskId` or `taskProgress` here — those are task-only params.

Most links will be greyed-out at this point (files don't exist yet) — that is expected. If the tool is NOT in your tool list, skip this step entirely — no text fallback needed.

⛔ Also call at these subsequent milestones (MANDATORY when the tool is available):
- After assessment.md written → `eventLabel='Assessment complete'`, `eventStatus='completed'`, `title='<what was assessed>'` — no `taskId`/`taskProgress`
- After plan.md written → `eventLabel='Plan ready'`, `eventStatus='completed'`, `title='<plan summary>'` — no `taskId`/`taskProgress`
- After each `start_task` → `eventLabel='Task started'`, `eventStatus='started'`, `taskId='<id>'`, `taskProgress='<N> of <M>'`, `title='<task description>'`
- After each `complete_task` → `eventLabel='Task completed'`, `eventStatus='completed'`, `taskId='<id>'`, `taskProgress='<N> of <M>'`, `title='<task description>'`

**Parameter guide for `show_scenario_links`:**

| Parameter | Type | Purpose | Example |
|-----------|------|---------|---------|
| `title` | string | One-line task description or summary of what changed | `"Migrated AuthService to MSAL"` |
| `eventLabel` | string | Full descriptive action label — Part 1 of the header | `"Scenario initialized"`, `"Task started"`, `"Task completed"`, `"Assessment complete"` |
| `eventStatus` | string | Icon+color: `"initialized"` (blue dot), `"started"` (blue play), `"completed"` (green check), `"needs_input"` (amber !), `"failed"` (red ✕) | `"completed"` |
| `taskProgress` | string | Task count shown as `"N of M"` — include for task events | `"3 of 10"` |
| `taskId` | string | Task identifier — surfaces task.md + progress-details.md for that task | `"02.01-common-lib"` |

Omit `taskProgress` and `taskId` during initialization and assessment/plan phases.

### 4.5 Continue to Scenario Workflow

Proceed to the scenario's first stage (typically Assessment). The scenario's stage instructions will take over from here.

---

## Integration with Scenario Skills

Scenario skills may define a **Pre-Initialization** section that specifies:
- Scenario-specific tools to call and parameters to gather
- A prompt template fragment for the scenario-specific portion of the consolidated prompt
- Validation rules for parameter changes

Scenario skills should **not** include source control setup in their stage instructions. Source control is handled here at the system level. Scenario stage instructions (e.g., Assessment) should assume:

- If git repo: working branch is already set up
- `initialize_scenario` has already been called
- Workflow folder exists
- Confirmed parameters are saved in `scenario-instructions.md`
