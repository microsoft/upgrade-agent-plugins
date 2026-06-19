---
name: tasks-consistency
description: How to reconcile tasks.md with plan.md when plan changes are detected
metadata:
  discovery: system
---

# Tasks Consistency Check

Instructions for reconciling tasks.md with plan.md when the plan has been modified. Plan.md is the **source of truth** for what top-level tasks exist and their scope. Tasks.md is a **derived view** that must stay in sync.

> **This skill covers 5 sections.** Read all before starting reconciliation.
>
> | # | Section | Key Content |
> |---|---------|-------------|
> | 1 | When to Run + File Locations | Triggers, file paths |
> | 2 | Consistency Rules | 5 rules governing reconciliation |
> | 3 | Reconciliation Workflow | 8-step procedure (read, diff, remove, add, reorder, sync, stats, log) |
> | 4 | Edge Cases | Completed subtask removal, ID renames, subtask-level plan detail |
> | 5 | Important + Checklist | **Critical** — direct file editing rules, verification checklist |

**Approach**: Read the actual markdown files, edit them directly, and let the underlying tools recalculate state from the updated files on next access. Do not rely on tool APIs for reading state here — they may have stale cached data. You are the reconciler.

## When to Run

- `get_state(path)` returns a `tasksOutOfSync` warning (plan.md was modified after tasks.md)
- User explicitly asks to reconcile or sync tasks with the plan
- After any direct edit to plan.md

## File Locations

All paths relative to scenario root: `{RepoRoot}/.github/upgrades/{scenarioId}/`

| File | Purpose |
|------|---------|
| `plan.md` | Authoritative task list — source of truth |
| `tasks.md` | Derived progress view — must match plan |
| `tasks/{taskId}/task.md` | Per-task detail — content mirrors plan section |
| `tasks/{taskId}/progress-details.md` | Execution artifacts — evidence of work done |

## Consistency Rules

1. **Plan wins** — top-level tasks in plan.md are authoritative
2. **Subtasks are preserved** — subtasks in tasks.md that belong to a surviving parent are never removed
3. **Task state is preserved** — completion status of unchanged tasks carries over
4. **Order matches plan** — top-level task order in tasks.md must match plan.md task order
5. **task.md files reflect plan** — each `tasks/{taskId}/task.md` must match the plan's task content

## Reconciliation Workflow

### Step 1: Read the Files

Read the actual files directly — do not use tool APIs for this since they may reflect pre-edit state.

1. **Read `plan.md`** — parse each `### {taskId}: {taskName}` section to extract:
   - Task ID, task name
   - Content (the paragraphs under the heading)
   - Done-when criteria (the `**Done when**:` line)
   - Order (position in the file)

2. **Read `tasks.md`** — parse the Task Hierarchy section to extract:
   - Each task line: emoji state, task ID, description, indentation depth
   - Parent-child relationships from indentation
   - The Progress line and other sections

   > **Note:** Task lines may have auto-generated trailing links like `([Content](tasks/{id}/task.md), [Progress](tasks/{id}/progress-details.md))`. These are appended by the system when the corresponding files exist. **Ignore them when parsing** — extract only the description before any `(` that starts a link group. When inserting new lines, use the plain format without links — the system adds them on the next regeneration.

Build two lists: `planTasks[]` (from plan.md) and `currentTasks[]` (from tasks.md).

### Step 2: Compute Differences

Compare by task ID:

| Plan has | Tasks.md has | Action |
|----------|-------------|--------|
| ✅ Task X | ✅ Task X | **Keep** — preserve state and subtasks |
| ✅ Task X | ❌ Missing | **Add** — new task, state 🔲 |
| ❌ Missing | ✅ Task X | **Remove** — see Step 3 for safety checks |
| ✅ Task X (changed content) | ✅ Task X | **Update** — sync task.md file |

Also check: is the order of surviving tasks different?

### Step 3: Handle Removals

For each top-level task in tasks.md that is **not** in plan.md:

1. **Check for work** — read the `tasks/{taskId}/` folder:
   - If `progress-details.md` exists or subtask folders have content → **stop and warn user**, list what would be lost
   - Wait for explicit confirmation before proceeding
   - If empty or no folder → safe to remove silently
2. **Edit tasks.md** — remove the task line and all its indented subtask lines
3. **Delete task folder** — remove `tasks/{taskId}/` directory and all its contents

### Step 4: Handle Additions

For each top-level task in plan.md that is **not** in tasks.md:

1. **Edit tasks.md** — insert at the correct position matching plan.md order:
   ```
   - 🔲 {taskId}: {taskName}
   ```
2. **Create task folder** — create `tasks/{taskId}/` directory
3. **Create `tasks/{taskId}/task.md`** — write:
   ```markdown
   # {taskId}: {taskName}

   {content from plan.md task section, including Done-when}
   ```
4. **No subtasks** — new tasks start without subtasks; breakdown happens during execution

*⚡ Continue reading — Steps 5-8 cover reordering, task.md syncing, statistics, and logging.*

### Step 5: Handle Reordering

If the set of tasks is the same but their order in plan.md differs from tasks.md:

1. **Edit tasks.md** — rearrange top-level task lines (and their subtask blocks) to match plan.md order
2. **Preserve subtask nesting** — when a parent moves, all its indented children move with it

### Step 6: Sync task.md Files

For each top-level task that exists in both plan.md and tasks.md:

1. **Read `tasks/{taskId}/task.md`**
2. **Compare** with the corresponding plan.md section (`### {taskId}: {taskName}` and its content)
3. If content differs:
   - **Rewrite the task.md** with updated content from plan.md
   - **Preserve** any execution-added sections below the plan content (subtask details, notes added during work)
   - Format:
     ```markdown
     # {taskId}: {taskName}

     {updated content from plan.md, including Done-when}
     ```

### Step 7: Update tasks.md Statistics

After all edits to tasks.md, recalculate and update inline:

1. **Progress line** — recount tasks: `**Progress**: {completed}/{total} tasks complete <progress value="{pct}" max="100"></progress> {pct}%`
2. **Status line** — update current task reference if the in-progress task changed
3. **Last Updated** — set to current timestamp
4. **Legend** — ensure present: `**Legend**: ✅ Complete | 🔄 In Progress | 🔲 Pending | ⚠️ Blocked | ❌ Failed`

*⚡ Continue reading — Edge cases and the verification checklist are essential for correct reconciliation.*

## Edge Cases

### Task with Completed Subtasks Being Removed

If a removed top-level task has completed (✅) subtasks or `progress-details.md` files:

1. **Always warn user first** — show which tasks/subtasks would be lost and what work was done
2. Wait for explicit user confirmation before removing
3. If user declines, skip that removal and note the discrepancy

### Task ID Changed in Plan

If a task ID was renamed (same content, different ID):

1. Treat as a **remove + add** (IDs are the matching key)
2. Warn user that task `{oldId}` will be removed and `{newId}` added
3. Suggest the user update plan.md to restore the original ID if the rename was unintentional

### Plan Has Subtask-Level Detail

Plan.md only defines top-level tasks. If the plan includes subtask-like structure:

1. Only match on top-level task IDs (format: `NN-taskname`)
2. Ignore any subtask detail in plan.md for consistency purposes
3. Subtasks are created during execution via task breakdown

## Important

- **Read files directly** — tool APIs may have cached/stale state. Always read the markdown files yourself.
- **Edit files directly** — write to tasks.md, task.md files, and folders yourself. The tools will recalculate state from the updated files on their next invocation.
- **Do not use `complete_task()` / `start_task()`** — those tools are for normal workflow execution, not bulk reconciliation. Direct edits are correct here.
- **Emoji format** — task lines use markdown list syntax: `- {emoji} {taskId}: {description}` with 3-space indentation per nesting level.
- **Subtask indentation** — depth 1 = 3 spaces, depth 2 = 6 spaces, etc.

## Checklist

Before marking reconciliation complete, verify:

- [ ] Every top-level task in plan.md has a corresponding entry in tasks.md
- [ ] No orphan tasks in tasks.md that don't exist in plan.md (unless user declined removal)
- [ ] Top-level task order in tasks.md matches plan.md
- [ ] Each `tasks/{taskId}/task.md` reflects current plan.md content
- [ ] All subtasks of surviving parents are preserved with their states
- [ ] Progress line in tasks.md is recalculated
- [ ] Execution log updated with reconciliation summary
