---
name: post-scenario-completion
description: Generic guidance for presenting scenario completion and next-step recommendations to the user
metadata:
  discovery: system
---

# Post-Scenario Completion

Apply this guidance whenever a scenario completes (when `complete_task` returns `allTasksComplete: true`).

## 1. Present a completion summary

Show the user a concise summary of what just happened. Structure it as:

```
✅ **{Scenario name} complete**

**What changed:** {N} tasks completed across {M} projects.
{If failures exist: ⚠️ {F} tasks encountered issues — see details below.}
```

Keep it to 3–5 lines. This is an orientation, not a report. Do not list every file changed.

## 2. Highlight failures (if any)

If `blockedTasks` or failed tasks were present at completion:
- List them with a one-line description of what failed
- Do NOT paper over failures — the user needs to know what requires manual attention

## 3. Build the "Next Steps" section

The next-steps section combines **scenario-specific suggestions** (from the scenario's `post-completion.md`) with **generic actions** (defined below). You must present them in a single, consistently formatted block.

### Step 3a — Load scenario-specific suggestions

If the tool result includes `postCompletionInstructionsPath`, read that file. It contains:
- **Applicability checks** the agent MUST perform before including each suggestion (e.g., check whether a package is present, read scenario-instructions.md for recorded decisions). Only include suggestions whose conditions are met.
- **Description text** for each applicable suggestion.

⚠️ **You are the filter.** The scenario file lists *candidate* suggestions — you must verify each one against the actual project state. Never present a suggestion without first confirming it applies. If none of the scenario-specific suggestions apply, skip this part entirely — do not show an empty section.

**Use `detectedSignals` to shortcut applicability checks.** When `complete_task` returns a `detectedSignals` field, use those pre-computed signals to determine applicability instead of scanning files with the LLM. For example, if signals include `NeedsEfCoreUpgrade`, you know EF6 is present without reading project files. Only fall back to LLM-based discovery when no relevant signal exists for a given check. Never tell the user you are checking signals or that "no signals are available" — this is an internal optimization invisible to the user.

### Step 3b — Append generic actions (always included)

After any scenario-specific suggestions, always append these two items:

1. **Generate detailed change report**
2. **Discover more opportunities**

### Step 3c — Format everything using the template below

Present the heading `🚀 Next Steps`, then each item as a block separated by `---`. Use this exact structure:

```
🚀 Next Steps

{emoji} **{Title}**
{1–3 sentence description explaining what this does and why it's valuable.}

Would you like me to {action verb phrase}?

---

📊 **Generate detailed change report**
I can generate a comprehensive report summarizing everything that was upgraded, including all files changed, decisions made, and validation results.

Would you like me to generate the detailed change report?

---

🔍 **Discover more modernization opportunities**
Want me to scan your solution for other modernization opportunities?

When the user says yes, load the `scenario-discovery` skill: `get_instructions(kind='skill', query='scenario-discovery')` — and follow it.
```

**Formatting rules:**
- Each suggestion gets a relevant emoji, bold title, description paragraph, and a CTA question
- Separate items with `---`
- Scenario-specific suggestions come first, generic actions last
- The description should help the user understand *why* they'd want this — not just *what* it is

## 4. Wait for user input

After presenting the summary and next steps, **stop and wait**. Do not automatically start the next scenario. The user drives what happens next.
