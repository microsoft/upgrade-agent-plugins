# Execution Details Reference

Situational execution mechanics and troubleshooting that the main `task-execution` skill points
to when relevant. None of this is per-task hot-path — read the section you need when you hit that
situation (a stale-task warning, a delegated sub-agent, a direct tasks.md edit, or a build/test
failure).

## Contents

- [Handling Stale Task Warnings](#handling-stale-task-warnings)
- [Delegated Execution Checklist](#delegated-execution-checklist)
- [Direct Edits to tasks.md](#direct-edits-to-tasksmd)
- [Error Recovery](#error-recovery)

## Handling Stale Task Warnings

`start_task` (and `get_state`) may return a `staleTaskWarnings` array — tasks stuck in 🔄 from a previous session that were never completed.

Each warning contains:
- `TaskId`: The stale task's ID
- `Description`: What the task is
- `Instruction`: Specific action to take — **follow this instruction**

**Before proceeding with the current task**, handle each stale warning:
1. Read the `Instruction` field and follow it
2. Assess the task's state — check its task folder for evidence of completed work (e.g., `progress-details.md`, code changes)
3. Call `complete_task(taskId)` to finalize it, or `complete_task(taskId, failed=true)` to abandon it

Do not ignore stale task warnings — they indicate state inconsistency that must be resolved before new work begins.

## Delegated Execution Checklist

When delegating task execution to a sub-agent:

1. **Load the `sub-agent-delegation` skill** — `get_instructions(kind='skill', query='sub-agent-delegation')`. It contains a mandatory job description template and checklists. Use it every time.
2. Your job description MUST include artifact instructions:
   - "Enrich `tasks/{taskId}/task.md` with your research findings — add affected files, dependencies, packages, patterns discovered directly into the document"
   - "Write `tasks/{taskId}/progress-details.md` with: files modified, build/test results, issues resolved"
   - "Do NOT call `complete_task` — return results to me"
3. After the sub-agent returns, run the post-return checklist from the skill: verify artifacts exist and quality bar is met before calling `complete_task`.

## Direct Edits to tasks.md

**Cosmetic changes** to task descriptions, names, or content don't require tool calls. If the user asks to rename a task, change its description, or adjust task content — edit `tasks.md` and/or `tasks/{taskId}/task.md` files directly.

Tools are for **structural operations** (add subtasks, change state, complete task) where state-machine consistency matters. The task snapshot re-parses `tasks.md` on each access, so direct edits are picked up automatically.

> **Auto-generated links:** Task lines in `tasks.md` may end with auto-generated Content and Progress links. These are system-managed — do not add, remove, or update them manually. If your edit drops them, they are re-added on the next regeneration.

## Error Recovery

### Build Errors
1. **Search for relevant skills first** — `get_instructions(kind='skill', query='<technology or error pattern>')`. Skills often contain specific fix patterns for common build errors (MSBuild issues, SDK-style vs legacy, multi-targeting, etc.).
2. Analyze error messages
3. Check for missing package references
4. Look for API changes in upgraded packages
5. Consider rolling back and breaking down further

### Test Failures
1. Identify failing tests
2. Determine if failure is expected (API change) or regression
3. Update tests for expected changes
4. Document unexpected failures for user review

### Blocked Tasks
1. Identify blocker cause
2. Consider alternative approaches
3. Ask user for direction if needed

### When to Search for Skills Mid-Task

Call `get_instructions(kind='skill', query='<topic>')` during task execution when:
- You encounter **repeated build/test failures** that aren't resolving with basic fixes
- You're working with a **technology not covered** by the skills loaded at task start (e.g., WPF, Entity Framework, a specific migration pattern)
- The task scope expanded during research and **new domains** emerged that weren't anticipated by `start_task`'s skill matching
