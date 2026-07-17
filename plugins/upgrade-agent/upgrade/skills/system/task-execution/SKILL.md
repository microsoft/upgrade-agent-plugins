---
name: task-execution
description: Full task lifecycle — assess, break down, execute, validate, complete
metadata:
  discovery: system
---

# Task Lifecycle Guide

Covers the entire task lifecycle: research → assess decomposition → break down or execute → validate → complete → commit.

## ⛔ Task Completion Requirements (read first)

Every task must meet ALL of these before calling `complete_task`:

1. **All "Done when" criteria met** — verify EVERY item in the task.md "Done when" section individually. A passing build alone is not sufficient — each criterion must be independently checked. See Section 4.
2. **Build succeeds** — zero errors in all projects you modified and their dependents
3. **All warnings fixed** — fix every warning in projects you touched, not just new ones. Projects must build warning-free. Never suppress warnings (`#pragma warning disable`, `/nowarn`, `<NoWarn>`) without explicit user approval.
4. **Tests pass** — run and pass tests for affected projects
5. **progress-details.md written** — write `tasks/{taskId}/progress-details.md` documenting what changed. This is mandatory for every task, not optional.
6. **Only `start_task` / `break_down_task` create task folders** — never create task.md files directly (you can edit them after additional research was done, but the initial creation must be via the tool to ensure state consistency).

> **This skill covers 8 numbered sections (plus §6.5, a sub-section between §6 and §7).** Read all before starting work.
>
> | # | Section | Key Content |
> |---|---------|-------------|
> | 1 | Assess Decomposition Need | Scope inventory, decomposition triggers, breakdown hint protocol (hint-file format & custom-skill hints → `references/decomposition.md`) |
> | 2 | Break Down | Subtask ID convention, atomicity, core strategies, `break_down_task` usage (replanning & discovery → `references/decomposition.md`) |
> | 3 | Execute | `start_task`, skills evaluation, research, decomposition assessment, order of operations |
> | 4 | Validate | "Done when" criteria verification, build/test requirements, failure handling |
> | 5 | Complete | `complete_task` params, progress-details.md, **all-tasks-complete → post-completion transition** |
> | 6 | Commit | Git commit strategy — when/how to commit after task completion (application detail → `references/committing-and-syncing.md`) |
> | 6.5 | Branch Sync & Plan Reconciliation | After commit, sync the working branch with its source; if commits were merged in, reconcile the plan (mechanics → `references/committing-and-syncing.md`) |
> | 7 | Workflow Files | File audience/purpose reference table |
> | 8 | Error Recovery + Communication | Build errors, test failures, blocked tasks, reporting (steps → `references/execution-details.md`) |

---

## 1. Assess Decomposition Need

After `start_task`, determine whether the task is **atomic** (executable as-is) or needs **decomposition** into subtasks.

### Scope Inventory

Before deciding whether to decompose, catalog the task's scope. Write a brief
inventory into `tasks/{taskId}/task.md` under `## Scope Inventory`:

1. **Projects affected** — list every project this task will modify
2. **Distinct concerns** — group the changes by technical domain
   (e.g., "package updates", "API migration", "config migration", "DI changes")
3. **Change signals** — query assessment data per project (package/API issue counts, key technologies detected); the task description summarizes but omits full per-project detail.
4. **Skill matches** — which loaded skills have Breakdown Hints or Strategies for this scope?

For obviously simple tasks (single project, one concern, <10 changes) a mental inventory is fine; write it out for any task spanning multiple projects or concerns. Keep the scope inventory and decomposition assessment internal — don't show the analysis to the user.

### Atomicity Criteria

A task is atomic when:
- Its completion state is unambiguous (verifiable: builds, tests pass, API migrated)
- It has no internal decision points that would require replanning mid-execution
- A single execution scope can hold all needed context
- It won't leave the repo in an ambiguous intermediate state if it partially fails

### Decomposition Triggers

Evaluate these criteria against the task. **Any single trigger is sufficient to decompose.**

**1. Unknown scope** — You don't yet know what the task fully entails. The task must first be decomposed into a discovery/research subtask whose output defines the remaining subtasks.

**2. Internal decision points** — Completing the work requires making a choice that affects *what* work gets done (not just *how*). The decision is a task boundary — it must complete before downstream work can be planned.

**3. Dependency on another subtask's output** — If part B needs an artifact, state, or validation result produced by part A, they must be separate tasks regardless of individual simplicity.

**4. Parallelization opportunity** — Independent pieces of work benefit from splitting to enable concurrent execution. In large repos with many projects, this matters for throughput.

**5. Failure blast radius** — If partial failure would leave the repo in an ambiguous intermediate state that's hard to reason about or roll back, split into pieces with clean before/after boundaries.

**6. Validation gate** — Any point where correctness must be verified before proceeding is a natural task boundary. The validation itself is part of the task, and its outcome determines whether downstream tasks are unblocked.

**7. Context isolation** — Two pieces of work require completely different context (deep knowledge of different projects, different technology stacks). Separate tasks keep execution focused.

**8. User request** — The user explicitly asks to break down the task (e.g., "break this down", "split this into...", "do X first then Y"). If the user provides subtask structure or ordering, use it as the basis for the breakdown.

### Extended Assessment

Check all available skill sources for additional decomposition guidance:
- **Scenario skill** and its referenced files (loaded via `get_instructions(kind='scenario', ...)`)
- **`<task_related_skills>`** returned by `start_task` for this specific task
- **Available Skills list** in the system prompt — scan for relevant skills by technology or pattern

Look for `## Breakdown Hints` or `## Decomposition Rules` sections in any loaded skill.
These provide domain-specific signals (when to decompose) and strategies (how to decompose).

### Breakdown Hint Protocol

Scenario skills and custom skills can contribute **breakdown hints** — structured
conditions that signal when a task should be decomposed and how.

At breakdown assessment time:

1. Check `breakdown-context.md` in the scenario folder for cached hints (skip resolved ones)
2. Load scenario skill's `## Breakdown Hints` section
3. Scan loaded skills with `provides: task-breakdown-hints` in their description
4. Evaluate applicable hints against current task
5. If ANY MUST-priority hint fires → task MUST be broken down
6. If 2+ SHOULD-priority hints fire → task SHOULD be broken down
7. Record decisions in `breakdown-context.md`

Custom skill hints with the same `hint: {id}` override scenario hints.

📖 **For the `breakdown-context.md` file format and how custom skills author breakdown hints, read [references/decomposition.md](references/decomposition.md).**

### Decision

**Decompose when** ANY decomposition trigger fires — core or skill-contributed.

**Execute directly when** no triggers fire: scope is known, no decision points, no internal dependencies, failure is contained, context is focused.

> **Note**: Complexity of work alone does not determine decomposition need. A complex but well-scoped single-project upgrade may be atomic. A simple change spanning 10 projects with dependencies between them requires decomposition.
>
> **Never skip a task because it looks complex** — if a task feels too hard to execute directly, that's a decomposition trigger, not a reason to jump to the next task. Break it down into subtasks instead.

*⚡ Continue reading — Section 2 covers subtask design principles and `break_down_task` usage.*

---

## 2. Break Down (if needed)

### Subtask ID Convention

Dot notation encodes hierarchy:
- `02-leaf-dependencies` → Parent task
- `02.01-common-lib` → First subtask (direct child)
- `02.02-utils-lib` → Second subtask (direct child)

Always add direct children of the parent task.

### Subtask Design Principles

Each subtask should be **atomic** per the Section 1 criteria: an unambiguous done state, no internal replanning, and a clean failure boundary. **Require at least 2 meaningful subtasks** — if you can't identify two, the task is probably atomic (decomposing into one is just renaming). Research and decisions happen naturally during execution and don't need separate subtasks unless a decision blocks otherwise-independent work.

### Select Breakdown Strategy

Check all available skill sources for domain-specific strategies before falling back to core strategies:
- **Scenario skill** — may define decomposition patterns specific to the upgrade type
- **`<task_related_skills>`** from `start_task` — task-specific recommendations
- **Available Skills** — scan for skills matching the task's technology or pattern

Skills may define `## Breakdown Strategies` or `## Decomposition Rules` sections with patterns. When available, prefer these over core strategies.

**Core strategies** (always available):

| Strategy | When | Pattern |
|----------|------|---------|
| **By dependency order** | Work items have ordering constraints | Leaf → mid → root, validate at each step |
| **By project** | Scope spans independent projects | One subtask per project or logical group |
| **By concern** | Single project has multiple independent changes | One subtask per concern (middleware, auth, controllers) |
| **By decision gate** | A choice blocks downstream work | Discovery subtask → implementation → validation |

When multiple strategies could apply, prefer: skill-contributed > scenario-specific > core.

### Using break_down_task

1. Determine subtasks using your chosen strategy
2. Call `break_down_task(parentTaskId, subtasks)` with a JSON array:
   ```json
   [{"id": "02.01-data-access", "description": "Update data layer", "content": "## Objective\n..."},
    {"id": "02.02-services", "description": "Update service layer", "content": "## Objective\n..."}]
   ```
   Each entry needs: `id` (dot-notation), `description` (short), `content` (full task.md body)
3. **Pause behavior depends on flow mode**. **Guided mode**: pause for user review. **Automatic mode**: show structure, proceed immediately.

### Replanning & Discovery

📖 **For idempotent `break_down_task` replanning semantics and the discovery pattern (turning work found mid-execution into subtasks), read [references/decomposition.md](references/decomposition.md).**

*⚡ Continue reading — Sections 3-5 cover execution flow, validation, and completion.*

---

## 3. Execute

### Start Task

```
start_task(taskId)
```

Returns: `taskId`, `taskFolder`, `folderCreated`, `taskContent` (task.md content, potentially enriched with related skills), `staleTaskWarnings`

`start_task()` creates the task folder JIT if needed (`folderCreated`). **task.md is a living document** — seeded by `break_down_task` or `start_task`, then enriched with research findings during execution; treat it as your working plan.

#### ⚠️ Handling Stale Task Warnings

If `start_task`/`get_state` returns a `staleTaskWarnings` array, resolve each one **before** starting new work — follow its `Instruction` and `complete_task` it (or `complete_task(taskId, failed=true)` to abandon). 📖 **See [references/execution-details.md](references/execution-details.md).**

### ⛔ Execution Order Rule

**Execute tasks in the order returned by `availableTasks` from `complete_task` or `get_state`.** Never skip a task, never reorder tasks. If a task looks too complex after starting it, decompose it (Section 1-2) — don't jump ahead to an easier task.

**Always call `start_task(taskId)` — even when resuming a previously started task.**
`start_task` is idempotent and returns task content + matched skills every time.
If you skip it (e.g., because `get_state` already told you a task is in-progress),
you miss skill matching and lose access to task-related guidance.

**After calling start_task, follow these steps in order:**

#### Step 0: Ensure scenario-instructions.md is in context

If you haven't read `scenario-instructions.md` in this session, read it now.
It contains preferences (flow mode, commit strategy), upgrade options,
strategy constraints, and user decisions that affect every task. This file
is your persistent memory across sessions — always have it in context
before executing tasks.

#### Step 1: Load skills for this task

⛔ **Do this BEFORE any other work — before research, before decomposition assessment, before execution.**

`start_task` returns a `<task_related_skills>` block at the end of `taskContent` — skills pre-matched to this task's scope. Each entry includes the skill's description.

```
<task_related_skills>
  <skill name="skill-name" path="/path/to/skill">Description</skill>
  ...
</task_related_skills>
```

**Consider each skill and load the relevant ones now:**
1. Read every `<skill>` description. For each one, ask: will I be doing work this skill covers?
2. If yes — read `{path}/skill.md` NOW, before proceeding. Be generous when judging relevance: if a skill covers **any part** of your upcoming work, load it. Don't assume you already know what the skill contains — skills have repo-specific patterns, tool selection logic, and error handling you won't guess correctly.
3. Scan **Available Skills** in the system prompt for additional matches. Load any that apply.
4. If you can only recall VAGUE CONCEPTS from a skill but not its SPECIFIC instructions (tool names, decomposition patterns, file references), your context was compressed — reload the skill. When in doubt, reload. Re-reading a skill takes seconds; executing without it causes mistakes that take much longer to fix.

Do not narrate skill selection to the user.

#### Step 2: Research the task

**Research happens BEFORE decomposition** — what you discover during
research determines whether the task needs breaking down.

1. **Read the task description carefully** — it should contain scope,
   affected projects, assessment context, and research starting points
2. **Run scope inventory** — catalog projects affected, distinct concerns,
   change signals from assessment data, and skill matches (see Section 1)
3. **Investigate starting points** — read project files, check metadata,
   run tools as needed to understand the actual work
4. **Enrich `tasks/{taskId}/task.md`** with your findings —
   add the details you discovered (affected files, dependencies, packages to update,
   API changes, decisions made) directly into the document so it becomes a complete
   reference for executing this task. Weave findings
   into the existing task description so anyone reading task.md sees everything needed
   to understand and execute the task.

For single-project tasks modifying ≤3 files with no package changes, a brief mental assessment is sufficient — but you MUST still write a 2-3 line summary in `tasks/{taskId}/task.md` of what you checked and found. The exception is about research depth, not skipping the written record.

#### Already-Done Check

After research, verify whether the task's objective is **already met** — a prior task may have completed the work as a side effect (e.g., a batch package update that touched this task's project too). Check the done-when criteria directly: are packages already at the target version? Is the API already migrated? Does the project already build?

If the task is already complete:
1. ⛔ Write `progress-details.md` — note which prior task completed this work and the evidence (build passes, API already migrated, packages at target version, etc.). This is mandatory even for already-done tasks.
2. Call `complete_task` — skip execution and validation
3. Commit if applicable per strategy (artifact-only commit)

#### Step 3: Assess decomposition need

Apply Section 1 criteria **against your research findings** (not just
the task description). Research often reveals complexity that wasn't
apparent from the description alone.

If decomposition is needed → `break_down_task()` (Section 2) → pause for user review (Guided mode) or proceed (Automatic mode) → recurse. If atomic → proceed to Step 4. Don't show decomposition reasoning to the user: if breaking down, state why in one sentence; if atomic, say nothing.

#### Step 4: Execute

### Order of Operations

1. **Package updates first**: Update NuGet packages
2. **Framework changes**: Update target framework if needed
3. **Code modifications**: Fix breaking changes, update APIs
4. **Configuration**: Update app settings, connection strings
5. **Tests**: Update test code to match changes

### Change Guidelines

Make incremental, testable changes; keep them within task scope; document non-obvious fixes in `task.md`.

### Delegated Execution & Direct tasks.md Edits

📖 **When delegating a task to a sub-agent (mandatory `sub-agent-delegation` skill + artifact rules) or editing `tasks.md`/`task.md` directly (cosmetic edits are fine; structural changes go through tools), read [references/execution-details.md](references/execution-details.md).**

*⚡ Continue reading — Sections 4-8 cover validation, completion, commit strategy, branch sync, workflow files, error recovery, and communication.*

---

## 4. Validate

### ⛔ Validation = Verify EVERY "Done When" Criterion

The **"Done when"** section in task.md is your validation checklist — not just "does it build." **Before calling `complete_task`, independently verify EVERY "Done when" item**: run the build, run the tests, confirm code changes exist, attempt runtime verification, etc.

⛔ **Do NOT skip items because previous tasks succeeded or the build passes.** A passing build is ONE criterion — each item must be checked separately. Non-automatable items (e.g., "verify UI shows X") must be documented in `progress-details.md` for user verification.

### Post-Task Build Invariant

After completing ANY top-level task, the **entire solution** must build. If your changes break other projects — those referencing modified projects (transitive breaks), consuming changed APIs/packages, or test projects referencing modified code — fix them as part of this task. If the solution built before this task and doesn't after, this task caused the regression and must fix it; "out of scope" is not a valid excuse.

### Required Validations

- **Build**: `dotnet build {projectPath}` for SDK-style projects. For non-SDK-style
  projects (old-style csproj), `dotnet build` won't work — use `msbuild {projectPath}`
  or build the solution file instead.
- **Tests**: `dotnet test {testProjectPath}` for SDK-style test projects.
  For non-SDK-style test projects, use `vstest.console` or build and run via the
  solution's test runner.

**Use default configuration only.** Do not build multiple configurations (e.g., both Debug and Release separately) unless user or task explicitly asking for it.

### Handling Failures

- **Build fails**: Fix errors before marking complete
- **Tests fail**: Investigate and fix, or document as known issue
- **Build warnings**: Fix all warnings in projects you touched (see Handling Warnings)
- **Blocked**: Call `complete_task` with `failed=true` and clear error message

**General rule**: If you've attempted to fix the same issue 3+ times with different approaches and remain stuck, pause and ask the user for guidance rather than continuing to retry.

### Handling Warnings

**Warnings are treated like errors.** After a successful build, fix every warning in the projects you touched (not just ones you caused) — they must build warning-free. On the **final task**, build the full solution and clear all remaining warnings. **Never suppress silently** (`#pragma warning disable`, `/nowarn`, `<NoWarn>`) without the user's explicit approval.

### No-Change Short Circuit

If task execution produced **no file modifications** (the work was already done, or the task was research/planning only):
- **Build**: Skip — a successful build from a prior task remains valid when nothing has changed.
- **Tests**: Skip only if tests for this task's affected projects already passed in a prior task during this session. If unsure whether they were run, run them — tests are cheap relative to the bugs they catch.

Proceed directly to Section 5 (Complete).

---

## 5. Complete

### Success

⛔ **Before calling `complete_task`**, you MUST write `tasks/{taskId}/progress-details.md`. This is not optional — even for small tasks.

`progress-details.md` contains:
- What was actually changed in the repo (files modified, packages updated, APIs migrated)
- Build/test results
- Issues encountered and how they were resolved
- Any deviations from the original plan in task.md

This is the detailed evidence of work done. It complements task.md (which is the enriched task description).

```
complete_task(taskId, filesModified)
```

Returns: `completed`, `availableTasks`, `blockedTasks`, `progress`, `allTasksComplete`, `postCompletion`

⚠️ **Always check `allTasksComplete`** — when `true`, the scenario is finished and you must enter the post-completion phase (see "All Tasks Complete" below).

Use `availableTasks` to pick the next task — **do not parse files**.

### Failure

**Before calling complete_task with failed=true**, you MUST write `tasks/{taskId}/progress-details.md` — even for failures. Record:
- What was attempted and what partial changes were made
- The error or blocker that caused the failure
- Build/test output at the point of failure
- Any diagnostic information that would help a retry or manual fix

```
complete_task(taskId, filesModified, failed=true, errorMessage="...")
```

Requires user intervention to continue.

**On failure**: Do NOT commit. Leave changes in the working tree so the user (or a retry) can inspect them.

### Retry on Error

If `complete_task` returns an error message indicating the task was not found or the file write failed, **call `complete_task` again with the same arguments**. The error response will include a retry instruction — follow it. Do not skip completion or move to the next task without resolving the failure.

⚠️ **After `complete_task` succeeds, proceed to Section 6 (Commit) before moving to the next task.** Do not skip the commit step.

### All Tasks Complete

When `complete_task` returns `allTasksComplete: true`, the scenario is entering its **post-completion phase** — this is a transition, not an endpoint.

1. **Complete the commit** (Section 6) for the final task as usual.
2. **Load the `post-scenario-completion` workflow skill** and follow it — do not improvise a completion summary from memory.
3. The skill will direct you to check for scenario-specific post-completion instructions if available.

---

## 6. Commit (if applicable)

Commit happens **after** all task completion maintenance — after `progress-details.md` is written, `complete_task` is called, and `tasks.md` is updated. This ensures every commit is a complete snapshot: code changes **and** workflow artifact changes together.

If the repo is not a git repo, skip this section entirely.

### Commit Strategies

| Strategy | When to commit | Commit message |
|----------|---------------|----------------|
| **After Each Task** | After every successful task completion | `upgrade({taskId}): {brief description}` |
| **After Each Phase** | After the last task in each top-level group completes | `upgrade({phase}): {brief description of phase scope}` |
| **Single Commit at End** | Only after the very last task completes | `upgrade: {scenario description}` |
| **Manual** | Never — user handles commits themselves | N/A |

### System Default

If no commit strategy is set in `scenario-instructions.md` (e.g., scenario planning instructions didn't specify one), use **After Each Task** as the default. This is the safest option — each task produces an atomic, revertible commit.

### Applying the Strategy

Read `Commit Strategy` from `scenario-instructions.md`, decide whether a commit is due now, and if so stage **everything** that changed — code **and** workflow artifacts (`tasks.md`, `progress-details.md`, `task.md`, anything under `.github/upgrades/`) — with `git add -A`, then commit using the strategy's message format. **Artifact-only tasks still commit** when the strategy says to: the state change is a meaningful snapshot, and skipping it breaks the "one commit per task" guarantee.

📖 **For phase-boundary rules, the full stage list, and the artifact-only rationale, read [references/committing-and-syncing.md](references/committing-and-syncing.md).**

---

## 6.5 Branch Sync & Plan Reconciliation (if applicable)

After the task is committed (§6) and **before** picking the next task, sync the working branch with its source and — if the sync merged in any commits — reconcile the plan against the new structure. The working tree is clean, the task is durable, and conflicts are easiest to resolve while upgrade context is fresh.

**Skip this section entirely** if any hold:
- Not a git repo.
- `Branch Sync` is `Disabled` in `scenario-instructions.md`.
- The just-committed task is the **last** task (let the user do the final merge/PR).
- Source branch equals working branch.
- A sync already failed at this same boundary in this session.

Otherwise, run branch sync and then plan reconciliation. 📖 **See [references/committing-and-syncing.md](references/committing-and-syncing.md)** for the exact sequence — it loads the `branch-sync` skill, then loads `plan-reconciliation` only if a merge brought in ≥1 commit. Do not duplicate either skill's logic here.

---

## 7. Workflow Files

| File | Audience | Purpose |
|------|----------|--------|
| `tasks/{taskId}/task.md` | LLM | Task description enriched with research findings — everything needed to execute the task |
| `tasks/{taskId}/progress-details.md` | User | Per-task change record — what actually changed, build/test results, issues resolved |
| `tasks.md` | Both | Task hierarchy with status. Lines may include auto-generated Content and Progress links — system-managed, not manually edited. |
| `scenario-instructions.md` | Both | Scenario spec, user preferences, always in context |

---

## 8. Error Recovery & Communication

### Error Recovery

📖 **For build-error, test-failure, and blocked-task recovery steps — and when to search for skills mid-task — read [references/execution-details.md](references/execution-details.md).**

---

### Reporting

After completing each task:
- Report success/failure clearly
- Show key files modified
- Check flow mode:
  - **Automatic**: proceed to next available task immediately
  - **Guided**: pause for user approval before next task
  - If no next task or blocked: pause and report status
- Provide progress percentage
