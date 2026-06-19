---
name: user-interaction
description: Pause points and user communication guidelines
metadata:
  discovery: system
---

# User Interaction Guide

Guidelines for communicating with users and handling pause points.

> **This skill covers 8 sections.** Read all before starting work.
>
> | # | Section | Key Content |
> |---|---------|-------------|
> | 1 | Communication Principles | Core interaction guidelines |
> | 2 | Interactive Question Tool | When and how to use `ask_user`/`ask_question` tools |
> | 3 | Pause Points | Mandatory and optional pauses table |
> | 4 | Pause Behaviors | Templates for each pause type |
> | 5 | Progress Reporting | Status update formats |
> | 6 | Handling User Input | Recognized commands (including `recap`) and custom instructions |
> | 7 | Auto-Saving User Preferences | **Critical** — what/when/how to persist user choices |
> | 8 | Error Communication + Best Practices | Error templates, core principles |

## Communication Principles

1. **Be concise**: Get to the point quickly
2. **Be actionable**: Clearly state what user needs to do
3. **Be transparent**: Show progress and next steps
4. **Be patient**: Wait at pause points for user input

## Interactive Question Tool

When you need a decision or confirmation from the user, prefer using the interactive question tool if one is available in your environment:
- In **VS**: `ask_question`
- In **VS Code / Copilot CLI**: `ask_user`

Choose options that fit the situation. If no such tool exists, ask the question as formatted text with clearly labeled options.

## Pause Points

Pause behavior depends on the **flow mode** saved in `scenario-instructions.md` (under `## Preferences > Flow Mode`). Default is **Automatic**.

### Pause Table by Mode

| Pause | Guided | Automatic |
|-------|--------|-----------|
| **Stage Boundary** | **Block** — show stage summary + artifacts, wait for `approve` | **Non-blocking** — surface summary, state proceeding, continue |
| **After Complex Breakdown** | **Block** — show subtasks, wait for `continue` | **Non-blocking** — show subtask list, continue executing |
| **On Blocking Issue** | **Block** — ask for direction | **Block** — ask for direction *(always blocks)* |
| **After Major Task** | Optional — user can say `pause` | No pause |
| **Before High-Risk Change** | **Block** — confirm to proceed | **Block** — confirm to proceed *(always blocks)* |

**Stage Boundary** applies at every scenario-defined stage transition (e.g., after assessment, after planning). The scenario's stage instructions define **what** to present; this skill defines **how** the pause works.

### Key Principle: Automatic Surfaces Without Blocking

In Automatic mode, the agent still **shows** the assessment, plan, and breakdown results — it just doesn't **wait** for approval. Think of it as:
- **Guided**: "Here's what I found. I'm waiting for your go-ahead."
- **Automatic**: "Here's what I found. I'm proceeding — interrupt me if something looks off."

The two **always-block** pauses (blocking issues and high-risk changes) block in both modes because the agent genuinely cannot proceed without user input.

## Pause Behaviors

### ⛔ MANDATORY: Open Artifacts in Editor

**Regardless of flow mode**, always open stage artifacts in the editor when they are created or updated. This ensures user visibility even when the agent doesn't block.

Scenario stage instructions specify which artifacts to produce. Common examples: `assessment.md`, `plan.md`, `tasks.md`. Open each artifact **before** presenting the pause message (Guided) or the non-blocking summary (Automatic).

#### How to Open Files

Use this fallback chain — try each approach in order, use the first one that works:

1. **Search available tools** for one that can open a file in the current IDE/editor (e.g., look for tools whose name or description mentions opening files, revealing files, or showing documents in the editor). Use that tool.
2. **If no such tool exists** (e.g., running in a CLI/terminal context), include the full absolute file path(s) in your response so the user can open them manually.

⛔ **Never automatically launch external programs** (e.g., `notepad.exe`, `code`, `start`, `open`, `xdg-open`) via the terminal to open files. The user's preferred editor is unknown — picking one for them creates a poor experience. Print the paths instead and let the user decide how to open them.

### Stage Boundary Pause

When a scenario stage completes, open its artifacts in the editor, then present a summary. The scenario's stage instructions define the **content** (findings, key metrics). This section defines the **shape** of the pause.

**Guided mode:**
```markdown
## {Stage Name} Complete

{Stage summary — key findings, metrics, artifacts opened}

---
{Universal Post-Pause Footer — see below}
```

**Automatic mode:**
```markdown
## {Stage Name} Complete (proceeding to {next stage})

{Stage summary — key findings, metrics, artifacts opened}

*Proceeding to {next stage}. Say `pause` or `hold on` to switch to Guided mode.*
```

### Universal Post-Pause Footer

Append this footer to **every Guided-mode blocking pause** (stage boundaries, complex breakdown, high-risk confirmation). It gives the user a consistent set of actions.

```markdown
**To proceed:** `approve` or `continue`
**To adjust:** Edit the artifact(s) or tell me what to change
**To switch mode:** Say `continue in automatic mode` to stop pausing at stage boundaries
```

Adapt the wording to context (e.g., "type `approve` to start planning" for assessment, "type `continue` to begin execution" for breakdown) but always include all three action categories: proceed, adjust, switch mode.

### Pause 2: After Breakdown

**Guided mode:**
```markdown
## Task Breakdown Complete

I've broken down **{taskId}** into {N} subtasks:

{subtask list with brief descriptions}

**Review:**
- [tasks/{subtaskId}/task.md]({path}) for each subtask

**To proceed:** Type `continue` to begin execution.
**To modify:** Edit task.md files with custom instructions first.
```

**Automatic mode:**
```markdown
## Task Breakdown: {taskId} → {N} subtasks

{subtask list with brief descriptions}

*Proceeding with first subtask. Say `pause` to review before continuing.*
```

### Pause 3: After Major Task

```markdown
## Task Complete: {taskId}

**Summary:** {brief description}
**Files Modified:** {count}
**Build:** ✅ Passing

**See details:** [progress-details.md]({path})

**Next:** {nextTaskId} - {nextTaskName}

**To proceed:** Type `continue`.
**To pause:** Type `pause` to review before continuing.
```

### Pause 4: On Blocking Issue

*⚡ Continue reading — Sections 5-7 cover user commands, auto-saving preferences, and error handling.*

```markdown
## Blocked: {taskId}

**Issue:** {description}

**Error details:**
```
{error message or details}
```

**Options:**
1. {option 1}
2. {option 2}
3. Manually fix and type `retry`

**Please provide direction on how to proceed.**
```

## Progress Reporting

### During Execution
```markdown
🔄 **Executing:** {taskId} - {taskName}
   Step {current}/{total}: {stepDescription}
```

### After Task Completion
```markdown
✅ **Completed:** {taskId}
   - {N} files modified
   - Build: ✅ | Tests: ✅ ({passed}/{total})
```

### Status Summary
```markdown
## Progress Summary

**Completed:** {completed}/{total} tasks ({percentage}%)
**Current:** {currentTask}
**Remaining:** {remainingTasks}

**Files Modified:** {count}
**Projects Updated:** {updated}/{total}
```

## Handling User Input

### User Intents to Recognize

Match user **intent**, not literal keywords. Users communicate naturally — recognize the meaning.

| Intent | Example phrases | Action |
|--------|----------------|--------|
| **Approve** | "approve", "looks good", "lgtm", "let's do it", "go ahead", "start" | Start execution after assessment/breakdown |
| **Continue** | "continue", "next", "proceed", "keep going", "go on" | Resume after pause point |
| **Pause** | "pause", "wait", "hold on", "stop after this one", "let me review" | Stop after current task |
| **Retry** | "retry", "try again", "give it another shot" | Retry failed operation |
| **Skip** | "skip", "move on", "skip this one", "not now" | Skip current task (mark blocked) |
| **Status** | "status", "where are we?", "how far along?", "progress", "what's left?" | Show current progress |
| **Recap** | "recap", "what happened?", "catch me up", "what did you do?" | Summarize recent activity from `progress-details.md` of completed tasks |
| **Break down** | "break this down", "split this into...", "do X first then Y", "separate this by project" | Decompose current task into subtasks; use user's structure/ordering if provided |
| **Switch to Guided** | "pause", "hold on", "let me review", "switch to guided", "stop after this" | Switch flow mode to Guided; update scenario-instructions.md; pause at next stage boundary |
| **Switch to Automatic** | "just go", "keep going", "don't wait for me", "switch to automatic", "continue without stopping" | Switch flow mode to Automatic; update scenario-instructions.md; stop pausing at stage boundaries |

### Custom Instructions

When user provides specific instructions:
1. Acknowledge the instruction
2. Incorporate into execution
3. Document in task.md or scenario-instructions.md

```markdown
**Understood.** I'll {description of how instruction will be applied}.
```

*⚡ Continue reading — Section 6 (Auto-Saving Preferences) is critical for persisting user decisions.*

## Auto-Saving User Preferences

**CRITICAL**: Any user preference, choice, or decision must be automatically saved to `scenario-instructions.md`.

### What to Save

| User Input | Save To |
|------------|---------|
| Package version preferences | `## User Preferences > ### Technical Preferences` |
| Execution pace (fast/methodical) | `## User Preferences > ### Execution Style` |
| Risk tolerance | `## User Preferences > ### Execution Style` |
| Task-specific instructions | `## User Preferences > ### Custom Instructions > #### {taskId}` |
| Commit strategy preferences | `## Preferences > Commit Strategy` |
| Task-specific instructions | `## User Preferences > ### Custom Instructions > #### {taskId}` |
| Breaking change handling | `## User Preferences > ### Technical Preferences` |
| Testing requirements | `## User Preferences > ### Technical Preferences` |
| Key decisions | `## Decisions` |

### When to Save

Save preferences **immediately** when user:
- Accepts a default option → record the choice
- Specifies a version or configuration → record the preference
- Asks to skip or modify standard behavior → record as custom instruction
- Makes a decision about approach → log in Decisions

### How to Save

After user expresses a preference, update `scenario-instructions.md`.
Create the section and subsection headings on-demand — only when there is
actual content to write. Never create empty placeholder sections or
subsections with filler text like "_(will be recorded here)_".

Example of a populated preferences section:

```markdown
## User Preferences

### Execution Style
- **Pace**: Methodical (user requested)
- **Risk Tolerance**: Conservative

### Technical Preferences
- **Package Versions**: Use latest stable, avoid pre-release
- **Breaking Changes**: Fix immediately, don't defer
- **Testing**: Run all tests after each task

### Custom Instructions
#### 02-leaf-dependencies
- Keep System.Text.Json at 6.0.x for compatibility
- Skip updating Microsoft.Extensions.Logging for now
```

### Example Flow

```
User: "Use the latest EF Core version but keep Newtonsoft.Json at 13.x"

Agent: "**Noted.** I'll use the latest EF Core but keep Newtonsoft.Json at 13.x."

[Agent immediately updates scenario-instructions.md]:
## User Preferences
### Technical Preferences
- **Package Versions**: Latest EF Core, Newtonsoft.Json pinned to 13.x
```

### Initial Scenario Setup

When scenario is initialized, `scenario-instructions.md` may be minimal. As user provides input during assessment review and task execution, the file **grows automatically** with their preferences.

```
Initial: Just scenario overview
After assessment: + User preferences from approval conversation
During execution: + Task-specific instructions as they come up
```

## Error Communication

### Recoverable Errors
```markdown
⚠️ **Warning:** {description}

I'll attempt to continue. If this causes issues, let me know.
```

### Non-Recoverable Errors
```markdown
❌ **Error:** {description}

**Details:** {technical details}

This requires attention before we can continue.
**Options:**
1. {option}
2. {option}

What would you like to do?
```

## Best Practices

1. **Never assume approval** - always wait at mandatory pause points
2. **Show don't tell** - provide file paths users can review
3. **Be specific about actions** - "type `approve`" not "let me know"
4. **Report honestly** - if something failed, say so clearly
5. **Respect user pace** - don't rush through if user wants methodical
6. **Log decisions** - document user choices for future reference
