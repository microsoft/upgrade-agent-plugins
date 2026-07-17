# Decomposition Reference

Detailed mechanics for the breakdown hint protocol and subtask design. The main
`task-execution` skill keeps the decision thresholds and the `break_down_task` contract inline;
read this file when you need the full hint format, authoring schema, or replanning/discovery
semantics.

## Contents

- [Breakdown Hint Protocol](#breakdown-hint-protocol)
- [breakdown-context.md Format](#breakdown-contextmd-format)
- [Custom Skill Contribution](#custom-skill-contribution)
- [Subtask Design Principles](#subtask-design-principles)
- [Replanning](#replanning)
- [Discovery Pattern](#discovery-pattern)

## Breakdown Hint Protocol

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

## breakdown-context.md Format

This file is created lazily on first task execution and persists across tasks:

```markdown
## Detected Hints

### hint: {id}
- **Status**: active | resolved
- **Priority**: MUST | SHOULD
- **Evidence**: {what was detected and where}
- **Detected**: {when, during which task}

## Breakdown Decisions

### task: {taskId}
- Broken into {N} subtasks based on hints: {hint-id-1}, {hint-id-2}
```

## Custom Skill Contribution

Custom skills can contribute breakdown hints by:

1. Including `provides: task-breakdown-hints` in the skill's **description** string
2. Adding a `## Breakdown Hints` section with hints in this format:

```markdown
### hint: {unique-id}
**Applies to task types**: {which tasks this is relevant for}
**Condition**: {what to detect}
**Detection**:
- {concrete file/pattern/metadata to look for}
**Recommendation**: {what to do when detected}
**Priority**: MUST | SHOULD
```

Custom hints with the same `hint: {id}` as a scenario hint override it.
Hints are discovered fresh on each task execution — no registration needed.

## Subtask Design Principles

Each subtask should be **atomic** per the criteria in the main skill's Section 1:
- **Unambiguous done state** — verifiable completion (builds, tests pass, no more usages of X)
- **No internal replanning** — if execution would require stopping to decide what to do next, decompose further
- **Clean failure boundary** — partial failure doesn't corrupt the repo; can be retried or rolled back independently

**Minimum 2 subtasks** — if you can't identify at least 2 meaningful subtasks,
the task is probably atomic. Don't decompose into a single subtask — that's
just renaming, not decomposing.

Research and decision-making happen naturally during task execution (see "Research the task" in
the main skill's Section 3) — they don't need to be separate subtasks unless the decision blocks
other subtasks that could otherwise proceed independently.

## Replanning

Calling `break_down_task` again is **declarative/idempotent** — provide the complete list of desired subtasks:

```
break_down_task(parentTaskId, subtasks)
```

- **Existing subtasks with matching IDs** keep their current state (e.g., InProgress stays InProgress)
- **Non-completed subtasks not in the new list** are removed — entries deleted from tasks.md, task folders deleted
- **Completed subtasks are always preserved** — work already done cannot be undone
- **Truly new IDs** are added as Pending

Use when the remaining work needs restructuring, or when discoveries change the subtask plan.

## Discovery Pattern

Work discovered during execution becomes subtasks of the current task:
1. Decompose current task: original scope + discovery → subtasks
2. Call `break_down_task` with all subtasks
3. Parent won't complete until all children complete → siblings stay ordered

For completely new top-level work unrelated to any task, note it under
`## Discoveries` in task.md and surface to the user.
