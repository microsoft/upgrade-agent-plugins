---
name: token-usage-prediction
description: Estimate and present the token-usage budget for an upgrade before execution. Call automatically after the assessment artifact is written; call again on demand after the plan and tasks are generated or when the user asks for a re-estimate.
metadata:
  discovery: system
---

# Token Usage Prediction

Pre-execution **token** budget for the active scenario. Lets the user decide
whether to proceed, narrow scope, or switch models before the agent starts
spending tokens. The prediction is token-only — no monetary cost is reported.

## When to call

The tool inspects the session state and routes to the cheapest estimator
that can answer. There are two trigger points:

- **Auto, inline (cheap branches)** — call `predict_token_usage()`:
  - Immediately after `assessment.md` is written, before planning begins.
  - When no scenario is active yet but the user asks "how big will this
    be?" — the tool still returns a baseline estimate.
- **On request (expensive branches)** — only call when the user explicitly
  asks ("recompute estimate", "how many tokens will the plan take now?",
  "estimate for task X"):
  - After `plan.md` + `tasks.md` are written.
  - For a single task by id (pass `task_id`).

Do **not** automatically re-run the tool after every state change. The
task-list and single-task branches can be slow; they are user-initiated.

## How to call

```
predict_token_usage()                                    // model-agnostic aggregate estimate
predict_token_usage(task_id: "T-04")                     // forecast a specific task
predict_token_usage(model_ids: ["gpt-5.4"])              // forecast one model
predict_token_usage(model_ids: ["claude-opus-4.6",       // compare several models
                                "gpt-5.4"])
```

Pass `model_ids` to forecast specific models — one estimate is returned per
model. Use the canonical lower-cased `<family>-<version>` id (the family keeps
any `mini` / `codex` / `pro` variant suffix), e.g. `claude-opus-4.6`,
`claude-sonnet-4.5`, `gpt-5.4`. Pass the model the session is running, or
several to let the user compare and pick a cheaper one. When omitted, a single
model-agnostic estimate is returned from the aggregate dataset.

The tool is read-only, side-effect-free, and does not call any LLM.

## What the tool returns

The payload is token-only:

- `message` — optional human-readable note. Populated when **no** prediction
  could be produced (e.g. no assessment found for the scenario). When present
  and `tokensByModel` is empty, surface the message to the user and stop —
  do not invent numbers.
- `tokensByModel` — one entry per requested model id (or a single
  model-agnostic entry when no `model_ids` were passed). Each entry reports
  **input and output as two independent low / high ranges**:
  - `input` — `{ low, high, display }` input-token range
  - `output` — `{ low, high, display }` output-token range
  - Input and output are priced very differently, so they are reported
    separately and **never summed into a single total**.
- `presentation` — `{ message, followUpInstruction }` — rendering guidance
  from the tool. Follow it.

There is no total, cost, USD, driver-attribution, or metadata field — never
refer to any. If a model has no entry in `tokensByModel`, do not report it.

## How to present

Always show each metric as a **low–high band** — never a single point
estimate — and always show **input and output as separate ranges**. Never
combine them into a total. Keeping them separate is an internal rule — do
**not** print captions, headings, or subtitles that explain it (e.g. "input
and output reported separately", "never summed"). Just show the two bands and
the caveat.

### Headline

```
💡 **Estimated token usage for this {scenario or task}**

Input  — {input.display}
Output — {output.display}
```

When the response covers multiple models, show one row per model:

```
| Model | Input (low – high) | Output (low – high) |
|---|---|---|
| {modelId} | {input.display} | {output.display} |
```

### Mandatory caveat

Always include verbatim:

> ⚠️ These are pre-execution estimates with high variance — agentic coding
> runs can vary by up to ~30× when compilation rabbit holes or backtracks
> hit. Treat the high value as a soft ceiling, not a guarantee. Bands reflect
> the spread of historical benchmark runs collected for this scenario.

### Large-estimate check

If the high band is very large relative to the expected workload, or the
low–high spread is unusually wide, prompt the user to confirm before
continuing — even in Automatic mode. Suggest narrowing scope or switching to
a cheaper model.

### Call to action

- **Automatic mode** (default): "Proceeding. Reply `pause` if you'd like
  to narrow scope or change model first." Then continue.
- **Guided mode**: "Would you like to proceed, narrow scope, or switch
  model before planning?"

## Rules

1. Never show a single point estimate — always the low–high band, and always
   show input and output as separate ranges.
2. Never omit the caveat.
3. Never invent numbers — use only fields from the tool response.
4. Never mention monetary cost, USD, or "no cost data" — the tool is
   token-only by design.
5. Never auto-call the expensive branches — wait for the user to ask.
6. Don't re-run the tool every turn. Only re-run when the assessment or
   plan changes, or when the user explicitly asks.
7. When `tokensByModel` is empty, surface `message` and stop.
8. Never present or compute a combined total — input and output are priced
   differently; report them as separate ranges only.
9. When you know the model the session is running, pass it via `model_ids`;
   pass several ids when the user wants to compare models.
