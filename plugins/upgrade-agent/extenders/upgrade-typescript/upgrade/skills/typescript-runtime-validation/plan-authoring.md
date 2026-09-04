# Author or Refresh the Eval Plan

Produce a valid `.tsupgrader/runtime-validation/eval-plan.json` for the project and save it to disk. For webapps, also record one or more supporting Playwright `.spec.ts` files that the plan references.

Do not invoke `typescript_validate_runtime` while following this file; return control to the calling runtime-validation workflow after saving the plan.

## Step 1 - Create or refresh

If `<packageDirectory>/.tsupgrader/runtime-validation/eval-plan.json` does not exist, create one from scratch. If it does exist, read its `projectType` and current assertions, then update only the parts that no longer apply.

Preserve the caller's validation context:

- **Upgrade workflow:** use the package scope and upgrade plan already established by the calling skill.
- **Standalone workflow:** cover the project's primary executable or public entry points and the critical behavior documented in its README, routes, commands, or existing tests.

## Step 2 - Detect the project type

Read `package.json` when present, the README, and the source tree. Pick the closest match:

- `electron` in dependencies -> **electron**.
- A `bin` field in `package.json`, or `scripts` pointing at a CLI entry such as `bin/<name>.js` -> **cli**.
- `react-dom`, `vue`, `svelte`, `solid-js`, `@angular/platform-browser`, `next`, or a dev-server script (`dev` / `start` / `serve`) that boots Vite / webpack-dev-server / Next / Angular CLI -> **webapp**.
- `express`, `fastify`, `koa`, `hapi`, `@nestjs/core`, `apollo-server`, `graphql-yoga`, or source that calls `.listen(<port>)` -> **server**.
- Otherwise (only consumed via `import`, no executable entry) -> **library**.
- Special: VS Code / Babel / Webpack plugins use **plugin**. Build systems like Nx / Lerna use **framework**. Use **other** only as a last resort.

## Step 3 - Delegate Playwright recording for webapps

If `projectType` is `webapp`, the plan should reference one or more verified Playwright `.spec.ts` files. Follow [recording.md](./recording.md) end-to-end: the parent starts the dev server, records each flow through the contributed `JSTS Playwright Spec Author` child, and then stops that recording dev server once every flow is recorded ([recording.md](./recording.md) Step 5). Validation manages its own server through the eval plan's `devServer` block, so no recording-phase server should still be running when you call `typescript_validate_runtime`. If child agents or Playwright are unavailable, use the documented `http-probe` fallback instead of writing a browser test by hand.

## Step 4 - Pick the per-type template

Read [per-project-type.md](./per-project-type.md), copy the template for the project's type, and adapt commands, paths, and URLs. For **server** projects, follow the endpoint-discovery procedure in that file; do not invent routes.

## Step 5 - Add the `tests-pass` assertion

Read [tests-assertion.md](./tests-assertion.md) and append the `tests-pass` assertion. If the project has no test script, follow the context-specific generation flow in that file before emitting the assertion.

## Step 6 - Apply schema and `output-contains` rules

- Confirm the plan matches [plan-schema.md](./plan-schema.md).
- For every `output-contains` assertion, confirm the substring is stable using [output-contains.md](./output-contains.md).
- Use structured `cwd`, `env`, and `prependPath` fields whenever a command needs a different directory, environment override, or toolchain PATH. Keep `command` and `args` separate and invoke the executable directly; do not author `cmd.exe /c`, PowerShell, or `sh -c` wrappers for ordinary commands.
- Author package-manager invocations as `command: "npm"`, `"yarn"`, or `"pnpm"` (or `startCommand` for an HTTP probe) with the package-manager args in `args`, never as an absolute path or a `*.cmd` path. The runner resolves the bare package-manager name to the platform-specific entry point beside the selected Node runtime, so whichever package manager the project uses runs on the chosen Node. Use `command` for every other executable too — `node`, `npx`, `git`, `dotnet`, a compiler, or a project script.
- When the workflow selected a specific Node binary, declare it once in the top-level `runtime` object with `kind: "node"`, `executable`, and `expectedVersion`. Use a per-step `runtime` only when that step intentionally requires a different Node — for example, a legacy build script that must run on Node 18 while the dev server and tests run on the project's Node 20. Do not repeat the Node path in command fields.
- Prefer a portable runtime executable such as `"node"` when the environment already selects the right version. An absolute Node path is allowed only when the workflow deliberately selected that installed runtime; never copy a host-resolved npm path into the authored plan.

## Step 7 - Save

Write the JSON to `<packageDirectory>/.tsupgrader/runtime-validation/eval-plan.json`. Use 2-space indentation. Assertion `name`s must be unique within the file.

## Step 8 - Hand control back

Report what changed in one or two sentences, then resume the calling runtime-validation workflow.

## Key principles

1. **Author for replay.** Every assertion must be deterministic across runs. Avoid time-of-day output, random ports, or commands whose output drifts.
2. **One assertion = one concern.** Do not pack multiple checks into a single command.
3. **Prefer `exit-code` over `output-contains` when possible.** Exit codes are unambiguous; output strings are fragile.
