---
name: create-eval-plan
description: Author or refresh `.tsupgrader/runtime-validation/eval-plan.json` — the file `typescript_validate_runtime` later replays. Produces or updates the plan and stops; does not invoke validation or interpret results.
---

Produce a valid `.tsupgrader/runtime-validation/eval-plan.json` for the project and save it to disk. For webapps, also record one or more supporting Playwright `.spec.ts` files that the plan references.

## Workflow

### Step 1 — Create or refresh

If `<packageDirectory>/.tsupgrader/runtime-validation/eval-plan.json` does not exist, create one from scratch. If it does exist, read its `projectType` and current assertions, then update only the parts that no longer apply.

### Step 2 — Detect the project type

Read `package.json`, the README, and the source tree. Pick the closest match:

- `electron` in dependencies → **electron**.
- A `bin` field in `package.json`, or `scripts` pointing at a CLI entry such as `bin/<name>.js` → **cli**.
- `react-dom`, `vue`, `svelte`, `solid-js`, `@angular/platform-browser`, `next`, or a dev-server script (`dev` / `start` / `serve`) that boots Vite / webpack-dev-server / Next / Angular CLI → **webapp**.
- `express`, `fastify`, `koa`, `hapi`, `@nestjs/core`, `apollo-server`, `graphql-yoga`, or source that calls `.listen(<port>)` → **server**.
- Otherwise (only consumed via `import`, no executable entry) → **library**.
- Special: VS Code / Babel / Webpack plugins use **plugin**. Build systems like Nx / Lerna use **framework**. Use **other** only as a last resort.

### Step 3 — (Webapps only) record Playwright flows first

If `projectType` is `webapp`, the plan will reference one or more Playwright `.spec.ts` files. Follow [recording.md](./recording.md) end-to-end before authoring the plan.

### Step 4 — Pick the per-type template

Read [per-project-type.md](./per-project-type.md), copy the template for your project's type, and adapt commands, paths, and URLs. For **server** projects, follow the endpoint-discovery procedure in that file — do not invent routes.

### Step 5 — Add the `tests-pass` assertion

Read [tests-assertion.md](./tests-assertion.md) and append the `tests-pass` assertion. If the project has no test script, follow the generation flow in that file before emitting the assertion.

### Step 6 — Apply schema and `output-contains` rules

- Confirm the plan matches the schema: [plan-schema.md](./plan-schema.md).
- For every `output-contains` assertion, confirm the substring is stable: [output-contains.md](./output-contains.md).

### Step 7 — Save

Write the JSON to `<packageDirectory>/.tsupgrader/runtime-validation/eval-plan.json`. Use 2-space indentation. Assertion `name`s must be unique within the file.

### Step 8 — Hand control back

Report what you did in one or two sentences. If you were invoked by another skill, that skill resumes from where it left off. If the user invoked you directly, tell them the plan is saved.

Do not invoke `typescript_validate_runtime` yourself — that's the calling workflow's job.

## Key principles

1. **Author for replay.** Every assertion must be deterministic across runs. Avoid time-of-day output, random ports, or commands whose output drifts.
2. **One assertion = one concern.** Don't pack multiple checks into a single command.
3. **Prefer `exit-code` over `output-contains` when possible.** Exit codes are unambiguous; output strings are fragile.
