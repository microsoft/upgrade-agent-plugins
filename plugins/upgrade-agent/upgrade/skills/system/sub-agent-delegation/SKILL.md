---
name: sub-agent-delegation
description: How to compose sub-agent job descriptions and validate their output
metadata:
  discovery: system
---

# Sub-Agent Delegation Guide

How to compose job descriptions for sub-agents and validate their output. Load this skill every time you delegate work to a sub-agent.

## Orchestrator Role

You are the **orchestrator**. You drive the workflow lifecycle (`start_task`, `complete_task`, `break_down_task`, `get_state`). Sub-agents execute specific jobs you assign. They don't know about the workflow — they only know the instructions you give them.

### Never Delegate

- Calling workflow tools: `start_task`, `complete_task`, `break_down_task`, `get_state`, `initialize_scenario`, `resume_scenario`
- Deciding whether to decompose, skip, or reorder tasks
- Creating task folders or task.md files (only `start_task` / `break_down_task` do this)

---

## Job Types

| Job | Typical scope |
|-----|--------------|
| **Research a task** | Investigate projects, discover affected files, identify patterns, write findings |
| **Execute code changes** | Make specific code changes, fix build errors/warnings, run tests |
| **Build & validate** | Build projects, run tests, report results |
| **Explore (read-only)** | Investigate and report back — no file writes |

These are common patterns, not an exhaustive list. Any scoped, well-described work can be delegated.

---

## Job Description Template

⛔ **Use this template every time you delegate.** Fill in every section — empty sections mean the sub-agent lacks critical context.

```markdown
## Job: {job_type} for task {taskId}

### Context
Read `{workflow_folder}/scenario-instructions.md` before starting — it contains
user preferences, upgrade options, and decisions that affect your work. Follow any
preferences that apply to your scope (e.g., pinned package versions, framework choices).

### Scope
{Exact projects, files, or areas of concern. Be specific — list paths, not descriptions.}

### Actions
{What to do: research these projects, update target framework, fix build errors, etc.}

### Skills
These skills contain domain-specific patterns and rules for this work.
⛔ Before starting, review each skill description below. For any skill that covers
work you are about to do, read `{path}/skill.md` — it contains tested patterns,
tool selection logic, and error handling you will not guess correctly on your own.
Be generous: if a skill covers ANY part of your job (e.g., `building-projects`
when you will be building), read it. Do not skip skills assuming you already know
the content.

{Paste the <task_related_skills> block from start_task here}

### Artifact Requirements
{Include ALL that apply to this job:}

**Research artifact** (for research and execute jobs):
Enrich `{workflow_folder}/tasks/{taskId}/task.md` with your findings — add the
details you discovered directly into the document so it becomes a complete
reference for executing the task. Include:
- Projects affected and why
- Files to modify (list paths)
- Packages to update (current → target versions)
- API changes or migration patterns discovered
- Decisions made and rationale

**Progress artifact** (for execute jobs):
Write to `{workflow_folder}/tasks/{taskId}/progress-details.md`:
- Files modified (list each)
- Build result (0 errors, 0 warnings — or details of remaining issues)
- Test result (which tests ran, pass/fail)
- Issues encountered and how they were resolved
- Any deviations from the requested changes

### Quality Bar
- Fix ALL build warnings in projects you touch, not just errors
- Run tests for affected projects
- Do not suppress warnings (`#pragma warning disable`, `/nowarn`, `<NoWarn>`) without explicit user approval
{Add any task-specific quality requirements from scenario-instructions.md}

### Boundaries
- Do NOT call `start_task`, `complete_task`, `break_down_task`, `get_state`, `initialize_scenario`, or `resume_scenario`
- Do NOT create new task folders
- Return your results to me when done — I handle workflow state

### Report Back
When done, report:
- Files changed (list)
- Build status (errors, warnings)
- Test status (pass/fail, which tests)
- Issues or blockers encountered
- Whether artifacts (enriched task.md, progress-details.md) were written
```

---

## Pre-Spawn Checklist

⛔ **Verify ALL before sending the job:**

1. `scenario-instructions.md` path is included in Context
2. Skills list is forwarded (from `start_task`'s `<task_related_skills>`)
3. Artifact paths are correct (match the actual task folder under `.github/upgrades/{scenarioId}/`)
4. No empty mandatory sections in the template
5. Quality bar includes "fix all warnings"
6. Boundaries section is present (no workflow tool calls)

If the orchestrator already read a skill and knows a specific section is critical for the job (e.g., a migration pattern the sub-agent will definitely need), paste that section directly into the Actions or Skills section — don't rely solely on the sub-agent loading it.

---

## Post-Return Checklist

⛔ **Verify ALL before calling `complete_task`:**

1. `tasks/{taskId}/task.md` has been enriched with research findings (not just the original stub)
2. `tasks/{taskId}/progress-details.md` exists with content (for execute jobs)
3. Build: 0 errors, 0 warnings in touched projects
4. Tests: pass for affected projects

**If ANY item is missing:**
- Write the artifact yourself from the sub-agent's reported results
- If build/warnings weren't fixed, fix them yourself or re-delegate with explicit instructions
- Do NOT call `complete_task` until all items are verified

---

## Job Type Quick Reference

### Research Job

Focus: investigation and documentation, minimal or no code changes.

Template overrides:
- Artifact Requirements: Enrich task.md only (no progress-details.md)
- Quality Bar: thoroughness of investigation, not build status
- Report Back: findings, recommended approach, files that will need changes

### Execute Job

Focus: code changes with full validation.

Template overrides:
- Artifact Requirements: both enriched task.md and progress artifact
- Quality Bar: full build + test + warning-free
- Report Back: all files changed, build/test status, issues resolved

### Explore Job

Focus: read-only investigation, report back to orchestrator.

Template overrides:
- Artifact Requirements: none — report back in the return message only
- Quality Bar: n/a
- Boundaries: add "Do not modify any files"
- Report Back: findings in structured format
