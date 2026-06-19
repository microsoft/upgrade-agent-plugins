---
name: state-management
description: How to manage workflow state and tasks.md files
metadata:
  discovery: system
---

# State Management Guide

Instructions for managing workflow state files.

> **This skill covers 7 sections.** Read all before starting work.
>
> | # | Section | Key Content |
> |---|---------|-------------|
> | 1 | State Files Overview | File purposes, ownership, including task.md |
> | 2 | tasks.md | Template, recent activity format |
> | 3 | Scenario Instructions | Location, preferences format |
> | 4 | State Operations | `get_state`, `start_task`, `complete_task`, `break_down_task` |
> | 5 | Tool-Driven Navigation | Use `availableTasks` from tool responses |
> | 6 | File Consistency & Reconciliation | **Critical** — source of truth hierarchy, drift detection, reconciliation protocol |
> | 7 | Progress Bar Calculation | Counting rules, update timing |

## State Files Overview

| File | Purpose | Updated By |
|------|---------|------------|
| `tasks.md` | Human-readable progress view | Tools (structure) + LLM (activity) |
| `scenario-instructions.md` | Scenario spec and preferences | LLM + User |
| `tasks/{taskId}/task.md` | Per-task description enriched with research — everything needed to execute the task | LLM (enriched during execution) |

## tasks.md

**Location**: `{RepoRoot}/.github/upgrades/{scenarioId}/tasks.md`

**Updated by**:
- Tools: Structure, task hierarchy, statistics
- LLM: Recent activity section

### Template
```markdown
# Migration Progress

**Progress**: 0/{totalTasks} tasks complete <progress value="0" max="100"></progress> 0%
**Status**: In Progress - Task {currentTaskId}
**Started**: {startDate}
**Last Updated**: {lastUpdate}

## Task Hierarchy
{generated from state.json}

**Legend**: ✅ Complete | 🔄 In Progress | 🔲 Pending | ⚠️ Blocked | ❌ Failed

## Current Focus
🔄 **{taskId}**: {taskName}
[Details](tasks/{taskId}/task.md) | [Changes](tasks/{taskId}/progress-details.md)

## Recent Activity
{LLM appends single line per event with timestamp}

## Statistics
- Total Tasks: {totalTasks}
- Completed: {completedTasks} ({percentage}%)
- Files Modified: {filesModified}
- Projects Updated: {projectsUpdated}/{projectsTotal}
```

### Updating Recent Activity

After each significant event, append to Recent Activity:
```markdown
- {timestamp}: {brief description of what happened}
```

Examples:
- `2024-01-15 10:30`: Completed 02.01-common-lib - updated 5 packages
- `2024-01-15 10:45`: Started 02.02-utils-lib
- `2024-01-15 11:00`: Broke down 03-shared-libraries into 3 subtasks

## Scenario Instructions

**Location**: `{RepoRoot}/.github/upgrades/{scenarioId}/scenario-instructions.md`

**This file is ALWAYS IN CONTEXT** when a workflow is active.

Contains:
- Strategy approach
- User preferences (flat key-value list)
- Key decisions made during the workflow
- Custom per-task instructions

### Reading User Preferences

Check the **Preferences** and **Custom Instructions** sections before executing any task:
```markdown
## Preferences
- **Pace**: {Standard | Fast | Methodical}
- {other scenario-specific preferences}

## Custom Instructions
<!-- Task-specific overrides: "For {taskId}: {instruction}" -->
```

## State Operations

### Getting Current State
```
get_state(path)
```
Returns:
- `inProgressTask`: Currently active task (if any)
- `availableTasks`: Tasks ready to execute (no blockers)
- `blockedTasks`: Tasks waiting on dependencies
- `completedTasks`: Finished tasks
- `progress`: Completion statistics
- `staleTaskWarnings`: Tasks stuck in 🔄 from a previous session (see [Stale Task Warnings](#stale-task-warnings))

### Starting a Task
```
start_task(taskId)
```
Returns:
- `task`: Task details (id, name, complexity, projects)
- `folderCreated`: Path to task folder (created JIT)
- `needsBreakdown`: Whether task should be broken down
- `userInstructions`: Content from existing task.md (if pre-created)
- `staleTaskWarnings`: Tasks stuck in 🔄 from a previous session (see [Stale Task Warnings](#stale-task-warnings))

Updates:
- `tasks.md`: Task shown as 🔄 In Progress
- Creates `tasks/{taskId}/` folder if doesn't exist

### Completing a Task
```
complete_task(taskId, filesModified)
```
Returns:
- `completed`: Task that was completed
- `availableTasks`: Next tasks ready to execute
- `blockedTasks`: Tasks still waiting on dependencies
- `progress`: Updated completion statistics

Updates:
- `tasks.md`: Task shown as ✅ Complete, statistics and progress bar updated

### Failing a Task
```
complete_task(taskId, filesModified, failed=true, errorMessage="...")
```
Returns:
- `availableTasks`, `blockedTasks`: For navigation
- `error`: Error message

Updates:
- `tasks.md`: Task shown as ❌ Failed

### Breaking Down a Task
```
break_down_task(parentTaskId, subtasks)
```
Declarative: provide the complete desired subtask list. Calling again reconciles automatically.

Returns:
- `subtasksCreated`: List of created subtasks
- `subtasksRemoved`: List of removed subtask IDs (if any existing children were not in the new list)
- `availableTasks`: First subtask(s) ready to execute
- `blockedTasks`: Subtasks waiting on siblings

Updates:
- `tasks.md`: Shows subtasks in hierarchy
- Creates `tasks/{subtaskId}/` folders (empty, ready for task.md)
- Removes non-completed children not in the new list (entries + task folders)
- Preserves completed subtasks and existing subtasks with matching IDs (keeps their state)

## Tool-Driven Navigation

**Key Principle**: Every state-changing tool returns `availableTasks` - use this to determine the next task to execute.

```
After each tool call:
- If availableTasks is not empty → pick next task from list
- If availableTasks is empty and blockedTasks exist → report blockers
- If availableTasks is empty and no blockedTasks → workflow complete
```

**DO NOT** parse tasks.md to determine next task - use tool responses.

### Stale Task Warnings

`get_state` and `start_task` may return a `staleTaskWarnings` array — tasks that are marked 🔄 In Progress but appear to be left over from a prior session.

Each warning contains:
- `TaskId`: The stale task's ID
- `Description`: What the task is
- `Instruction`: Specific action to take

**Handle stale warnings before starting new work:**
1. Follow the `Instruction` in each warning
2. Assess the task's state — check its task folder for evidence of completed work (e.g., `progress-details.md`, code changes)
3. Call `complete_task(taskId)` to finalize it, or `complete_task(taskId, failed=true)` to abandon it

Stale warnings indicate state inconsistency. Do not ignore them.

*⚡ Continue reading — Sections 6-7 cover file consistency, drift detection, and progress bar calculation.*

## Best Practices

1. **Call `get_state(path)`** at start of each interaction to know current state
2. **Use tools for all state changes** - never edit state files directly
3. **Keep tasks.md readable** - users view this for status
4. **Log decisions** in scenario-instructions.md Decisions section
5. **Update progress after every change** to maintain visibility

## File Consistency & Reconciliation

### Source of Truth Hierarchy

When files conflict, this is the priority order:

1. **plan.md** — authoritative for what tasks exist and their scope
2. **tasks.md** — derived view, can always be regenerated from plan.md + completion state
3. **tasks/{taskId}/task.md** — elaboration only, doesn't define the task list
4. **Tool state** (scenario properties `taskStates`) — authoritative for task states recorded by `start_task`/`complete_task`

### Detecting Drift

`get_state(path)` returns `fileTimestamps` for plan.md, tasks.md, and scenario-instructions.md.

**At the start of each conversation turn:**
1. Call `get_state(path)`
2. Compare `fileTimestamps` against what you last saw
3. If plan.md is newer → re-read it, check if tasks were added/removed/reordered
4. If tasks.md is newer → user probably intended to edit the plan; re-read and treat as plan change
5. If scenario-instructions.md is newer → re-read for updated preferences

### Reconciliation Protocol

**When plan.md changed (tasks added, removed, or reordered):**
1. Re-read plan.md
2. Regenerate tasks.md to match (preserve completion statuses for unchanged tasks)
3. If a removed task had a folder with work in it → warn user before deleting reference

**When tasks.md was edited directly:**
1. Re-read tasks.md to understand user intent
2. Propagate changes back to plan.md if task list changed
3. Regenerate tasks.md cleanly (it's a derived view)

**When user says "I edited X":**
1. Re-read the file they mention
2. Diff against your last known state
3. Propagate changes to dependent files
4. Confirm changes with user before proceeding

### What NOT to Reconcile

- **progress-details.md** files — append-only history, never needs reconciliation
- **task.md elaborations** — these refine scope, they don't define the task list
- **Scenario properties** — managed by tools, not user-editable

*⚡ Continue reading — Section 7 covers progress bar counting rules.*

## Progress Bar Calculation

The **Progress** line in tasks.md tracks completion across all tasks and subtasks:

```
**Progress**: {completed}/{total} tasks complete <progress value="{percent}" max="100"></progress> {percent}%
```

**Counting rules**:
- Count every task and subtask equally (flat count)
- When a parent is broken down, count only its subtasks, not the parent itself
- A task counts as "completed" only when status is ✅
- `total` = all leaf tasks + unbroken parents
- `percent` = floor(completed / total * 100)

**Update this line** after every `complete_task()` or `break_down_task()` call, using the `progress` statistics from the tool response.
