---
name: plan-generation
description: How to create plans, scenario-instructions, and progress documents
metadata:
  discovery: system
---

# Plan Generation Guide

Instructions for creating planning artifacts after assessment is approved.

> **This skill covers 5 sections.** Read all before starting work.
>
> | # | Section | Key Content |
> |---|---------|-------------|
> | 1 | Planning Flow | Sequence from assessment approval to user review |
> | 2 | Reading Assessment Data | How to handle large assessments |
> | 3 | plan.md Specification | Template, task description guidelines, naming, sizing |
> | 4 | scenario-instructions.md Specification | Template, preferences format, append-only decisions |
> | 5 | tasks.md Specification + Presenting Plan | Template, status emojis, approval triggers |

## Planning Flow

```
Assessment approved
    ↓
Load scenario planning instructions (if available)
    ↓
Extract key information from assessment.md
    ↓
Apply scenario-specific planning logic
    ↓
Create plan.md with tasks
    ↓
Create/update scenario-instructions.md
    ↓
Initialize tasks.md
    ↓
Present summary, wait for approval
```

**Important**: Scenario skills may have planning-stage instructions. Load and follow them in combination with these generic instructions. Scenario instructions define **what** to plan (e.g., strategy selection, task ordering rules). This skill defines **how** to write the artifacts.

## Reading Assessment Data

`assessment.md` can be large (sometimes too large for context). Check scenario planning instructions (if present) for how to read assessment data:

- Some scenarios provide specialized query tools for assessment data
- If no specialized tool available, read `assessment.md` directly
- For large assessments, read in sections relevant to current planning step

## Planning Artifacts

| Document | Purpose | Who Reads |
|----------|---------|-----------|
| `plan.md` | Task descriptions, scope | User (review), Executor (task lookup) |
| `scenario-instructions.md` | Strategy, preferences, decisions | Executor (ongoing reference) |
| `tasks.md` | Visual progress tracking | User (status), Executor (overview) |

---

## plan.md Specification

### Purpose

Reference document containing task descriptions. Created during planning, queried on-demand during execution. Executor loads relevant sections when starting tasks.

### Template

<plan-template>
# {Scenario Name} Plan

## Overview

**Target**: {what's being modernized}
**Scope**: {qualitative size — e.g., "3 projects, ~2k LOC" or "large solution, 45 projects"}

## Tasks

### {task-id}: {task name}

{Description of what needs to happen and why. Intent-based, 1-3 paragraphs.}

{Optional: affected items, key concerns — only when helpful}

**Done when**: {concrete, verifiable success criteria — what must be true when this task is complete}

---

### {next-task-id}: {task name}
...
</plan-template>

### Allowed Sections

plan.md must contain **only** the sections shown in the template above: `## Overview` and `## Tasks`. Do not add extra top-level sections. Common sections LLMs add that do **not** belong in plan.md:

| Section | Why it's excluded |
|---------|-------------------|
| Rollback Plan / Rollback Instructions | Users know how to use git (`git reset`, `git revert`). Not actionable. |
| Estimated Timeline / Time Estimates | LLMs cannot accurately estimate duration. Misleading. |
| Risk Matrix / Risk Assessment | Already in assessment.md — don't duplicate. |
| Prerequisites / Assumptions | Belongs in scenario-instructions.md or assessment.md. |
| Dependencies / Dependency Graph | Already in assessment.md — don't duplicate. |
| Notes / Additional Considerations | Catch-all that accumulates noise. Put concerns in relevant tasks. |

If a scenario strategy file adds sections to plan.md (e.g., a strategy declaration block), those are allowed — they come from the strategy, not from LLM improvisation.

### Task Description Guidelines

**Include:**
- Intent-based scope (what, not how)
- Key concerns when relevant
- Specific items when helpful
- **Success criteria** — concrete conditions that can be verified (builds succeed, tests pass, specific APIs replaced, etc.)

**Omit:**
- Exhaustive listings (reference assessment.md)
- Step-by-step execution instructions
- Metadata that lives elsewhere (risk, dependencies)
- **Numeric scores or ratings** (no "complexity: 8/10", "risk: high 7/10")
- **Time estimates** (no "estimated 2 days", "~4 hours") — LLM cannot accurately estimate duration
- **Invented metrics** — only use data directly from assessment, never fabricate numbers
- **Rollback instructions** — users manage rollback via git; not useful in a task description
- **Prerequisites or assumptions** — the task's position in the plan implies ordering; don't restate

### Qualitative Sizing

Use plain descriptors when characterizing scope, never numeric scores:

| Do | Don't |
|----|-------|
| "small project, minimal dependencies" | "complexity: 3/10" |
| "large solution with heavy inter-project refs" | "estimated effort: 8/10" |
| "straightforward — no breaking changes expected" | "risk score: low (2/5)" |

### Task ID Format

Task IDs **must** follow the canonical format `NN-slug` — a **two-digit, zero-padded** sequence
number, a hyphen, then a lowercase kebab-case slug (letters, digits, hyphens). Sub-tasks use a
dotted sequence: `NN.NN-slug`.

| Valid | Invalid | Why invalid |
|-------|---------|-------------|
| `01-upgrade-htmlsanitizer` | `T-01` | No letter prefix — sequence must be digits |
| `02-core-contracts` | `1-core` | Sequence must be two digits (`01`, not `1`) |
| `02.01-data-access` | `02_data_access` | Use hyphens, not underscores |
| `03-web-apps` | `Task3` | Must be `NN-slug` |

The state tools (`start_task` / `complete_task`) parse this format. IDs that don't match (e.g.
`T-01`) are silently ignored and task tracking breaks — always emit `NN-slug` ids.

### Task Naming

Task IDs must describe **what is being done**, not the strategy slot or structural position. A user reading just the task list should understand the work without knowing the strategy.

**Never use strategy jargon as task names** — words like `tier`, `phase`, `batch`, `layer`, `group`, `step`, or `stage` describe the *plan structure*, not the *work content*. Use the actual content being upgraded.

| Avoid | Prefer | Why |
|-------|--------|-----|
| `02-tier1` | `02-foundation-libs` | Names the projects, not the tier |
| `03-tier2` | `03-business-logic` | Describes what's in the tier |
| `04-tier3` | `04-web-apps` | Reader knows what gets upgraded |
| `phase-1-batch-a` | `02-data-access` | Describes the concern |
| `dependency-layer-0` | `02-core-contracts` | Names the actual libraries |
| `task-batch-final` | `06-integration-validation` | Describes the validation scope |
| `group-a` | `03-legacy-services` | Names the group's content |

**Guideline**: If you removed the sequence number, would the name still tell you what work happens? `tier1` → no. `foundation-libs` → yes.

### Item Listings

Include when helpful, omit when not:

```markdown
# Few items - list them
Affects UserService, OrderService, PaymentService.

# Pattern-based
Affects all repositories in src/services/.

# Too many
~25 components. Query assessment for full list.
```

*⚡ Continue reading — Sections 4-5 cover scenario-instructions.md and tasks.md specifications.*

---

## scenario-instructions.md Specification

### Purpose

Living document for user preferences and key decisions. Always in context when workflow is active. User can edit to influence behavior. Keep it minimal — no information that belongs in plan.md or assessment.md.

### Template

<scenario-instructions-template>
# {Scenario Name}

## Strategy
{chosen approach — one line}

## Preferences
- **Flow Mode**: {Automatic | Guided}
- **Commit Strategy**: {After Each Task | After Each Phase | Single Commit at End | Manual}
- **Pace**: {Standard | Fast | Methodical}
- {scenario-specific key-value pairs, one per line}

## Decisions
- {decision} — {brief context}

## Custom Instructions
<!-- Task-specific overrides: "For {taskId}: {instruction}" -->
</scenario-instructions-template>

### Guidelines

- **Flat and scannable**: No nested headers, no tables, no dates
- **One line per item**: Each preference or decision is a single line
- **Append-only for Decisions**: New decisions go at the bottom
- **User-editable**: Custom Instructions section for per-task overrides
- **No duplication**: Task descriptions → plan.md, inventory → assessment.md, progress → tasks.md

### Commit Strategy Default

**Always write a Commit Strategy value** when creating `scenario-instructions.md`. Use this priority order:

1. **Scenario planning instructions** — if the scenario's planning file specifies a commit default for the chosen strategy, use that
2. **User preference** — if the user already expressed a preference (e.g., during pre-init), use that
3. **System default** — if neither scenario nor user specified, use **After Each Task**

This ensures every scenario has a visible, editable commit strategy — even scenarios that don't mention commits at all.

*⚡ Continue reading — Section 5 covers tasks.md template and how to present the plan for approval.*

---

## tasks.md Specification

### Purpose

Visual progress document for user consumption. Updated automatically after each task completion.

### Template

Follow the `tasks_template` template below, replacing placeholders with actual data, never add new sections or content outside of the specified in the template.

<tasks_template>
# {Scenario} Progress

## Overview

[Brief description of the upgrade - 2-3 sentences maximum describing what is being upgraded and the approach being used.]

**Progress**: 0/X tasks complete <progress value="0" max="100"></progress> 0%

## Tasks

- {emoji} {task-id}: {task name}
- {emoji} {task-id}: {task name}
...
</tasks_template>

### Status Emoji Mapping

| Status | Emoji |
|--------|-------|
| completed | ✅ |
| in-progress | 🔄 |
| pending (not started) | 🔲 |
| blocked/failed | ❌ |

---

## Presenting Plan to User

After creating all documents:
- **Open `plan.md` and `tasks.md` in the editor** (regardless of flow mode) so the user can see them. Follow the **How to Open Files** fallback chain from the user-interaction skill: first search your available tools for one that opens files in the IDE; if none exists, include the full file paths in your response. Never launch external programs via the terminal.
- Present a summary per flow mode:

### Guided Mode
1. **Summarize** key metrics (task count, strategy, commit strategy, estimated effort)
2. **Reference** the opened documents
3. **Mention commit strategy** — e.g., "Commits: after each task. Say `commit at the end` or `I'll commit myself` to change."
4. **Pause and wait** for explicit approval before execution

Recognize the **approve intent** — user may say "approve", "looks good", "lgtm", "let's do it", "go ahead", "start", or similar. Match meaning, not literal keywords.

DO NOT proceed to execution until user approves.

### Automatic Mode
1. **Summarize** key metrics (task count, strategy, commit strategy, estimated effort)
2. **Reference** the opened documents
3. **Mention commit strategy** — e.g., "Commits: after each task. Say `commit at the end` or `I'll commit myself` to change."
4. **State that you are proceeding** to execution — e.g., "Proceeding to execution. Say `pause` to review first."
5. **Continue immediately** — load the scenario's execution-stage instructions and start the first task in the same response. Do not stop, do not yield the conversation back to the user, do not wait for approval. The user can interrupt with `pause` if needed.
