# Committing & Syncing Reference

Detailed mechanics for applying a commit strategy and for branch sync / plan reconciliation. The
main `task-execution` skill keeps the commit strategy table, the system default, and the "when to
sync" trigger inline; read this file when you're actually staging a commit or running a branch
sync.

## Contents

- [Applying the Commit Strategy](#applying-the-commit-strategy)
- [What to Stage](#what-to-stage)
- [Artifact-Only Commits](#artifact-only-commits)
- [Branch Sync & Plan Reconciliation Mechanics](#branch-sync--plan-reconciliation-mechanics)

## Applying the Commit Strategy

1. Read `Commit Strategy` from `scenario-instructions.md`
2. Determine if a commit is due at this point based on the strategy
3. If yes: stage **all** modified files — both code changes and workflow artifacts — and commit with the appropriate message format
4. If no: proceed to the next task — changes stay in the working tree

For **After Each Phase**: a "phase" is a top-level task group. If tasks are flat (no subtasks),
treat each task as its own phase (equivalent to After Each Task). If tasks have subtasks, the phase
boundary is when the parent task completes.

## What to Stage

Always stage **everything** that changed during the task, including:
- **Code changes**: source files, project files, config files modified by the task
- **Workflow artifacts**: `tasks.md`, `tasks/{taskId}/progress-details.md`, `tasks/{taskId}/task.md`, and any other files under `.github/upgrades/` that were updated

Use `git add -A` (or stage all modified/new files in the scenario and code directories) to ensure nothing is missed.

## Artifact-Only Commits

Some tasks produce no code changes — for example, research tasks, planning tasks, or tasks that
only update documentation/configuration. **Still commit** if the strategy says to. The workflow
artifact updates (`tasks.md` state change, `progress-details.md`) are meaningful changes that
should be captured. Skipping the commit would leave the task's completion state uncommitted,
breaking the "one commit per task" guarantee that users expect from the After Each Task strategy.

## Branch Sync & Plan Reconciliation Mechanics

Run these steps only when the main skill's Section 6.5 trigger says to (git repo, sync enabled, not
the last task, source ≠ working branch, no prior failed sync at this boundary):

1. Load and run the `branch-sync` skill (`get_instructions(kind='skill', query='branch-sync')`). It owns strategy interpretation, divergence detection, conflict resolution, build validation, rollback, `Last Sync Commit` persistence, and user messaging.
2. **If `branch-sync` reports a successful merge of ≥1 commit**, load and run the `plan-reconciliation` skill (`get_instructions(kind='skill', query='plan-reconciliation')`). It owns structural diff, proposal generation, user confirmation, plan application, and `Last Reconciled Commit` persistence. Skip step 2 when `Branch Sync` is `Manual` (no auto-merge) or when `branch-sync` reported no-op or rollback.
3. If `branch-sync` reports rollback, mark this boundary as "sync attempted, failed" so the next boundary's guard kicks in, then continue to the next task.

Do not duplicate either skill's logic here.
