---
name: dashboard-canvas
description: Mechanics for opening the Upgrade Dashboard canvas panel — the exact canvasId and instanceId to send, when extensionId is required, how to handle registration errors, and the open_dashboard fallback. Load only on hosts that expose an open_canvas tool and list the Upgrade Dashboard canvas.
metadata:
  discovery: system
---

# Upgrade Dashboard Canvas

Only load this skill on a host that actually has the canvas — an `open_canvas` tool **and** an
Upgrade Dashboard (`canvasId: dashboard`) in its available canvases. On plain CLI, Visual Studio and
VS Code the canvas does not exist; skip it silently there and use `open_dashboard` and the
`show_scenario_links` chips instead.

The dashboard is a live side-panel view of the active scenario's progress, assessment, dependency
health, tasks and activity. Open it *for* the user — they should never have to add it by hand
through the panel's `+` menu.

## When to open it

Once per session, the first time a scenario is active — whether `get_state` reports one at
startup, `initialize_scenario` creates one, or `resume_scenario` picks one up. Open it *for* the
user; they should never have to add it by hand through the panel's `+` menu.

## The call

```
open_canvas(canvasId: "dashboard",
            instanceId: "plugin-upgrade-agent-upgrade-agent-dashboard-dashboard")
```

Once it opens successfully you are done for the session — do not open it again.

### Do not shorten the `instanceId`

That value is not arbitrary. It is the id the host itself derives when the user opens this same
dashboard through the `+` menu: the canvas's `extensionId` and `canvasId` joined with `-`, then
every run of characters outside `A-Za-z0-9._-` replaced by `-`. Panels are keyed on `instanceId`
**alone**, so this exact string is what makes an agent-opened and a user-opened dashboard converge on
one panel. Any other value silently stacks a second dashboard next to theirs. Reuse it on every call.

### Do not send `extensionId` on the first attempt

The host documents it as optional — it exists only to break a tie when two extensions both publish a
canvas called `dashboard`. Sending a hardcoded value turns a lookup that would have succeeded into
`Canvas "…/dashboard" is not registered` whenever the host recorded our provider under a different
id, because that is a *different* lookup from the plain `canvasId` one.

Add an `extensionId` **only** when the host answers `Canvas "dashboard" is provided by multiple
extensions` — that reply is how it tells you the `extensionId` is genuinely required, and it lists
the ids to choose from. Use the exact Upgrade Dashboard id **from that list**. Ours is normally
`plugin:upgrade-agent:upgrade-agent-dashboard`, but if the host lists a different one the host's
value wins — an id that is not in the list fails identically on every retry.

## Timing

Never make `open_canvas` your first tool call of a session, and never call it in the same burst as
`get_state` / `initialize_scenario` / `resume_scenario`. The dashboard extension launches together
with the session and finishes registering a few hundred milliseconds later, so an open fired
immediately loses a race it did not need to enter — and the failure surfaces to the user as an error
card you cannot suppress afterwards.

Let the scenario work happen first (finish the initialize/resume step, write
`scenario-instructions.md`, emit `show_scenario_links`), then open the canvas. By then registration
has long since completed.

## When the open fails

Registration errors — `Canvas "…/dashboard" is not registered`, or
`No canvas "dashboard" is registered` — mean the extension has not finished registering yet, or the
host recorded it under a provider id you did not ask for. Either way this is **expected and not
fatal**.

1. If you sent an `extensionId` that the host never asked for, drop it and retry with `canvasId`
   alone — a different and more forgiving lookup. **If the host had told you the canvas is provided
   by multiple extensions, keep that `extensionId` on every retry** — dropping it only walks you back
   into the ambiguity error and the two failures alternate forever.
2. Retry the same call **up to two more times, spaced out** — never back to back. Put real work
   between attempts (your next `get_state`, file read, or task action); any real tool call takes far
   longer than the gap, so a spaced retry normally succeeds.
3. After a third failure, stop retrying and fall back to `open_dashboard`. Give the user its URL so
   they still get a dashboard — at most once per session, offered simply as a link.

Never surface the canvas failure itself to the user as an error.

## Related tools are not substitutes

- **`open_dashboard`** launches the Blazor web dashboard on a local URL. Do not call it *instead of*
  opening the canvas when the canvas is available — only as the fallback above, after a canvas open
  has actually failed.
- **`show_scenario_links`** emits progress chips. It does not launch a dashboard and is never a
  substitute for the canvas. Nothing here relaxes the **MANDATORY** `show_scenario_links` calls in
  the task-execution flow — emit every one of them exactly as specified, whether or not the canvas
  is open.
