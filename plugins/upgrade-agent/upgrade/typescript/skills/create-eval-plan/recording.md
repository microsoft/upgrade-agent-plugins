# Recording a Playwright flow (webapps)

Webapp eval plans should reference at least one recorded Playwright flow so that runtime validation exercises a real user path, not just a page-load smoke test.

## Step 0 — Confirm with the user before recording

Recording is the slowest part of plan creation (~1–3 min per flow). Before invoking `typescript_record_browser_flow` for the first time, list the flows you intend to record and ask the user whether to record them or skip recording in favor of `http-probe` assertions against the dev server URL.

## Step 1 — Make sure a dev server is running

Inspect `<packageDirectory>/package.json` `scripts` and find the launcher (`dev`, `start`, `serve`, …). Start it yourself (use your host's shell tool) **as a background / non-blocking process** so your turn does not hang waiting for it. Wait for the "ready" / "Local:" line in its output, then note the URL — common defaults are `http://localhost:3000`, `:5173` (Vite), `:4200` (Angular).

If multiple candidate scripts exist, ask the user which one is the dev server (`start` often launches the production build).

**Port precheck (shared machines).** Read the actual port from the dev server's own "Local:" / "ready" line — do not assume the default. On a busy machine the default port may be taken, and dev servers (Vite, CRA, …) silently fall back to the next free port (e.g. `3000 → 3002`), which also breaks any hard-coded frontend→backend proxy. Whatever port it actually bound to MUST be the port you pass as `devServerUrl` below **and** the `devServer.url` in the eval plan (Step 3). If the app pins a required port (e.g. a frontend that proxies to a fixed backend port), make sure that port is free before starting — free it or reconfigure the app rather than recording against the fallback port.

**Record the PID** you started — you will kill it in Step 4. If you cannot start the server in the background (host limitation), tell the user and stop; do not try to record without a server.

## Step 2 — Call `typescript_record_browser_flow` once per flow you want to record

A typical webapp needs **1–4 recorded flows** — pick the ones whose breakage would hurt most (landing-page render, primary CTA, login, checkout, …). Decide the list BEFORE recording so you don't backtrack. For each flow, call the tool once:

```jsonc
{
  "packageDirectory": "<absolute path to the package>",
  "devServerUrl": "http://localhost:5173",
  "flowName": "login-and-view-dashboard",
  "hints": "sign in as alice@example.com / hunter2, then click Reports"  // optional
}
```

`hints` is plain free-text guidance passed to the LLM that drives the browser — use it for anything it can't infer from the page (test credentials, "the cart icon is in the top-right", "ignore the cookie banner"). One spec is saved per call to `<packageDirectory>/.tsupgrader/runtime-validation/playwright-scripts/<flowName>.spec.ts`. **Repeat for each flow before moving on to Step 3.**

The tool spawns `@playwright/mcp` internally with `--codegen typescript` and drives the recording through MCP sampling on your host — you do **not** need to install `@playwright/mcp` in your MCP host configuration. The spec is **generated deterministically** from `@playwright/mcp`'s own per-call codegen output (the LLM only drives the browser — it never writes spec code), so selectors and URLs match exactly what was executed. The recorded spec is written to `<packageDirectory>/.tsupgrader/runtime-validation/playwright-scripts/<flowName>.spec.ts`.

Record short, focused flows (5–15 interactions). One flow per call. Skip flows whose assertions would depend on volatile data (timestamps, GUIDs, real user accounts).

**Render preflight.** Before recording, the tool navigates to `devServerUrl` and snapshots the page to confirm the app actually rendered. If it returns `outcome: "app_unreachable"` (navigation failed) or `outcome: "app_not_rendering"` (server responded but no UI mounted), the target app — not the recording tool — is broken. Open `devServerUrl` in a browser, fix the dev server (check its console for build/runtime errors, wrong host/port binding, or a crash-looping bundler), then re-run recording.

## Step 3 — Reference the specs in `eval-plan.json`

For each saved spec, add one `playwright-route` assertion. You do NOT need to start the dev server before running `typescript_validate_runtime` — the runner spawns the top-level `devServer` block itself and kills it after, including on failure. Just declare it once:

```jsonc
"devServer": {
  "command": "npm",
  "args": ["run", "dev"],
  "url": "http://localhost:5173/"
},
"assertions": [
  {
    "name": "login-and-view-dashboard",
    "kind": "playwright-route",
    "scriptPath": ".tsupgrader/runtime-validation/playwright-scripts/login-and-view-dashboard.spec.ts",
    "verificationMethod": "exit-code",
    "expected": "0"
  }
]
```

`scriptPath` is relative to the package directory. (The recording you just captured uses a dev server you started manually in Step 1; the saved spec itself does not — it only assumes the URL is reachable. `typescript_validate_runtime` provides that URL from the plan's `devServer` block.)

## Step 4 — Stop the dev server (MANDATORY)

Kill the background process you started in Step 1, using the PID you recorded. **Do not skip this step**, even if recording failed — a leaked dev server will hold the port and break subsequent runs, baselines, and post-upgrade validation. Verify the port is free before reporting success.

## Fallback: host without sampling support

If `typescript_record_browser_flow` returns an `outcome: "no_capability"` error, your MCP host doesn't expose the `sampling` capability. Record manually instead:

1. Install `@playwright/mcp` in your host's MCP configuration (or use your host's built-in browser tools).
2. Drive the flow yourself using `browser_navigate` / `browser_click` / `browser_snapshot` / `browser_fill`.
3. Save the spec to `<packageDirectory>/.tsupgrader/runtime-validation/playwright-scripts/<flowName>.spec.ts` by hand. It must:
   - `import { test, expect } from '@playwright/test';`
   - Contain at least one `test('...', async ({ page }) => { ... })` block.
   - Start with `await page.goto('<dev-server-url>');`.
   - End with at least one `expect(...)` on stable content.

## Avoid these pitfalls

- **Don't record against a random port.** Pin the port via config so the recording replays identically.
- **Don't write assertions on timestamps, GUIDs, or counters** — they regress every run.
- **Don't put multiple `test()` blocks per spec** unless they share setup.
