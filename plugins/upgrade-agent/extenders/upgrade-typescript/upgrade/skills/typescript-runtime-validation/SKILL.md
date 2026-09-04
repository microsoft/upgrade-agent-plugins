---
name: typescript-runtime-validation
description: Validate a JavaScript or TypeScript project by authoring and replaying an eval plan that can build or type-check, run tests, start the project, probe endpoints, and exercise browser flows. Use this directly or when another Modernizer skill delegates its required validation.
---

Validate the target project by replaying `.tsupgrader/runtime-validation/eval-plan.json` with `typescript_validate_runtime`.

Here, **runtime validation means the complete project-specific validation plan**, not only checks against an already-running application. Depending on the project, the plan may install dependencies, compile or build, run tests, launch a CLI/server/app, probe routes, and replay browser flows.

## Choose the workflow

- **Called from `typescript-dependencies-upgrade` or `typescript-compiler-upgrade`:** read [upgrade-workflow.md](./upgrade-workflow.md). Use `mode: "upgrade"` and preserve the caller's `rootDirectory`, `packageDirectory`, and `sessionId`.
- **Invoked directly by the user:** read [standalone-workflow.md](./standalone-workflow.md). Use `mode: "standalone"` so the health check cannot create, consume, reset, or satisfy an upgrade baseline.

Never use standalone mode during an upgrade, and never fabricate an upgrade workflow for a direct health check.

## Eval-plan ownership

This skill owns the eval-plan authoring guidance. When the tool reports that no plan exists, follow [plan-authoring.md](./plan-authoring.md) and its linked references, then resume the selected workflow.

## Key principles

1. **Run one MCP tool at a time.** Wait for each call to complete before starting another.
2. **Keep the plan deterministic.** The same plan must be safely replayable without manual cleanup or volatile inputs.
3. **Separate plan defects from application failures.** Fix an invalid assertion rather than changing working application code to satisfy it.
4. **Do not weaken checks to manufacture a pass.** Report environment or credential blockers explicitly.
5. **Use the captured browser boundary.** For each browser flow, call `typescript_prepare_browser_recording` once and invoke the exact returned `JSTS Playwright Spec Author` child once; repeat this per flow to record multiple specs. Its final assertion creates and cleans the spec automatically; never hand-author selectors or let the child write the spec.
