---
name: generate-report
description: Generate a persistent final-report.md summarizing everything the scenario changed
metadata:
  discovery: system
---

# Generate Scenario Report

Produce a comprehensive `final-report.md` artifact in the scenario folder that summarizes the completed scenario for sharing with teammates or stakeholders.

## When to use

Invoke this skill when the user chooses "generate a detailed report" after a scenario completes. Do NOT generate this automatically — it is an on-demand action.

## Report location

Write the report to `final-report.md` in the scenario folder.

## How to generate

### Step 1 — Gather data

Read these files from the scenario folder. Skip any that don't exist.

| File | What to extract |
|------|-----------------|
| `plan.md` | Original plan structure, task IDs, scope |
| `tasks.md` | Final task states (✅ / ❌ / ⏳), hierarchy |
| `scenario-instructions.md` | User preferences, decisions, recorded choices |
| `upgrade-options.md` | Selected options (target TFM, package choices, etc.) |
| `tasks/{taskId}/progress-details.md` | Per-task: files changed, build/test results, issues resolved |
| `tasks/{taskId}/task.md` | Per-task: task spec, scope, acceptance criteria |

Additionally:
- Run `git log --oneline` scoped to the scenario's time range or commits to list all changes committed during this scenario.
- Read detected signals from the most recent `get_state` or `complete_task` response if available — these provide context about what technologies were present in the solution.

If the gathered data is insufficient for a clear Summary (e.g., plan.md doesn't describe what was analyzed), read additional scenario artifacts like `assessment.md` as needed — but only the parts relevant to the report, not the entire file.

### Step 2 — Write the report

Use the template below as the **starting structure**. Follow it section by section. If a section has no applicable data, omit it entirely — do not write empty sections.

**You may add additional sections** when the gathered data contains information that doesn't fit the predefined sections. Use your judgment — if a theme appears across multiple tasks (e.g., "Authentication changes", "Database schema updates", "Test infrastructure"), give it its own section after the standard ones. Use the same formatting style.

### Step 3 — Confirm

After writing, confirm to the user with the full path to the generated report.

---

## Report template

~~~markdown
# {Scenario Name} — Report

**Scenario:** {description from plan.md}
**Outcome:** ✅ Fully completed / ⚠️ Completed with {N} failure(s)
**Projects affected:** {count}
**Tasks:** {completed}/{total} completed

---

## Summary

{2–4 sentence overview: what was upgraded, from what to what, key outcomes. Written for someone who wasn't in the room.}

---

## What Changed

### Packages

{Table of package changes across all projects. Group by change type.}

| Project | Package | Change | From → To |
|---------|---------|--------|-----------|
| ... | ... | Updated / Added / Removed | ... |

### Code Modifications

{Group by category. Common categories for upgrades:}

- **API migrations** — APIs replaced or rewritten (e.g., `HttpModule` → middleware)
- **Configuration changes** — web.config → appsettings.json, startup changes
- **Project file changes** — TFM updates, SDK-style conversions, property changes
- **Build and tooling** — CI/CD updates, build script changes

{For each category, list the key changes with affected files. Be specific but not exhaustive — highlight patterns, not every line.}

### Git Commits

| SHA | Message |
|-----|---------|
| ... | ... |

---

## Task Breakdown

{Use a table when there are 5+ tasks. For fewer, a bullet list is fine. Link to task.md and progress-details.md when they exist.}

| Task | Description | Outcome | Content | Details |
|------|-------------|---------|---------|---------|
| `{taskId}` | {description} | ✅ {one-sentence result} | [task.md](tasks/{taskId}/task.md) | [progress-details.md](tasks/{taskId}/progress-details.md) |
| `{taskId}` | {description} | ❌ {what failed and why} | [task.md](tasks/{taskId}/task.md) | [progress-details.md](tasks/{taskId}/progress-details.md) |

{If any tasks have subtasks, nest them under their parent with indentation. Omit Content/Details links for tasks that don't have the corresponding files.}

---

## Decisions Made

{Key choices recorded in scenario-instructions.md or made during execution. Format as a bullet list.}

- **{Decision}** — {rationale or user preference}
- ...

---

## Build & Test Results

{Final build and test status across affected projects. If all green, say so briefly. If there are failures or warnings, list them.}

| Project | Build | Tests | Warnings |
|---------|-------|-------|----------|
| ... | ✅ | ✅ 42 passed | 0 |

---

## Known Gaps & Follow-up Items

{Anything left incomplete, deferred, or requiring manual attention.}

- **{Item}** — {description and recommended action}
- ...

{If there are no gaps, write: "No known gaps. All tasks completed successfully."}
~~~

## Tone and format

- **Factual and concise** — no marketing language, no celebration
- **Audience: teammates and stakeholders** — assume they understand .NET but weren't watching the upgrade happen
- **Failures are reported honestly** — not downplayed or hidden
- **Tables over prose** — when listing structured data, prefer tables
- **Specific over vague** — "Updated 12 packages across 3 projects" not "Made various package updates"
- **Omit empty sections** — if there are no decisions or no gaps, skip the section entirely rather than writing "None"
