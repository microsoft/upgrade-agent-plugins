# Recording a Playwright flow (webapps)

Webapp eval plans should reference at least one recorded Playwright flow so
runtime validation exercises real user behavior instead of only loading a URL.

Each recorded flow uses one handoff:

1. `typescript_prepare_browser_recording` prepares one request for one flow and
   returns the exact child handoff.
2. One fresh `JSTS Playwright Spec Author` child drives the returned
   `playwrightRecorderPath`.
3. The child's final assertion automatically creates and replays the spec.
   Only a passing spec is promoted; success closes the browser session and
   removes the temporary request.

To record several flows, repeat this handoff once per flow: call
`typescript_prepare_browser_recording` again for each spec and launch a new
child each time. The child never writes or edits a spec, and the parent never
drives Playwright.

## Step 0 - Get explicit approval

Before starting:

1. List the 1-4 short flows you intend to record.
2. Explain that preparation may install these pinned packages only under
   `.tsupgrader/runtime-validation/node_modules`:
   - `@playwright/cli@0.1.18`
   - `@playwright/test@1.63.0-alpha-2026-08-05`
3. State that this does not modify the project's `package.json`, lockfile, or
   normal `node_modules`. The isolated toolchain and any approved browser
   download remain as ignored reusable caches.
4. Ask separately whether isolated Chromium may be downloaded when no supported
   system browser and no reusable Playwright browser cache are available.
5. Let the user choose recording or the `http-probe` fallback.

Never record or install anything without explicit approval.

**Unattended / yolo mode:** when the workflow runs non-interactively and no user
is available to approve, explicit approval is not required. Treat recording,
package install, and any needed browser download as pre-approved, skip the
questions above, and call the tool with `installApproved: true` and
`browserDownloadApproved: true`. Fall back to `http-probe` only on a real
failure, never merely because approval is unavailable.

## Step 1 - Start or identify one dev server

Inspect `package.json` and identify the real dev-server script. Start one
background server before the first recording, retain its PID, read the actual
URL from ready output, and probe that exact URL.

Track whether this workflow owns the process:

- If this workflow starts the server, set `serverOwnedByWorkflow = true` and
  retain its PID.
- If a responsive server already exists and the user permits reusing it, set
  `serverOwnedByWorkflow = false`. Never stop or kill that external process.

Keep the same server running across every recording. Do not start or stop a
server per flow.

This recording server is only needed while flows are being recorded. Runtime
validation does not reuse it: the eval plan's own `devServer` block (Step 4)
starts and kills a fresh server around the `playwright-route` assertions. Plan
to stop this recording server once recording is finished (Step 5) so it does
not collide with, or linger past, validation.

## Step 2 - Prepare one flow

Call `typescript_prepare_browser_recording` exactly once:

```json
{
  "packageDirectory": "<absolute package directory>",
  "devServerUrl": "http://localhost:5173",
  "flowName": "add-item-to-cart",
  "flowIntent": "Add the first stable catalog item and verify the cart contains one item.",
  "installApproved": true,
  "browserDownloadApproved": false,
  "headed": true
}
```

Use `headed: true` for a local desktop session and `false` only when the host
cannot display a browser.

Preparation alone owns package installation, browser discovery/download,
browser choice, session policy, flow reservation, and the recorder wrapper.
It prefers system Edge on Windows and a supported system browser elsewhere,
then reuses an already-installed Playwright browser cache (the project's own or
the machine's shared `ms-playwright` cache) when one is present. It downloads
isolated Chromium only when no reusable browser exists, and only with separate
approval.

On preparation failure, use the fallback without launching a child. Do not
probe browser paths, install anything, or reinterpret returned values.

## Step 3 - Launch one fresh child

**Re-verify the dev server immediately before every handoff.** Right after
`typescript_prepare_browser_recording` returns, and just before launching the
child, re-probe the exact `devServerUrl`. The child's first recorder command
(`open`) fails with `ERR_CONNECTION_REFUSED` when the server is down, and a
background server can be reaped between flows or after the tool call that
started it — so a single probe at Step 1 is not enough. If the URL does not
return a successful response:

- When `serverOwnedByWorkflow` is true, restart the same durable server,
  wait for its ready output, and re-probe the exact URL before delegating.
  This stays the one server from Step 1 — do not switch to a per-flow server.
- When `serverOwnedByWorkflow` is false, you may not manage the external
  process; use the `http-probe` fallback for this flow.

Only launch the child once the URL responds.

Invoke the exact returned agent (`JSTS Playwright Spec Author`, id
`jsts-playwright-spec-author`) once in a fresh child context. Send the complete
prepare result unchanged.

The child is sandboxed to `node "<playwrightRecorderPath>" ...` recorder
commands; its full contract lives in the child agent definition. As a single
documented last resort, if `open` still reports the app unreachable in the
child's own session, the child may start the project's **existing** dev script
itself and stop only that server before returning. This is a safety net for
hosts that reap the parent's background server across the handoff; the parent
still owns the primary durable server (Step 1) and must not rely on the child
to start it.

Run flows sequentially. Never re-delegate the same request. The child may
retry a rejected assertion only when the wrapper explicitly preserves the
request for recorder-command repair.

The final `assert-*` recorder command:

- stores the observed assertion;
- materializes one pending spec from Playwright-emitted actions;
- injects the prepared browser channel and localhost-only network guard;
- validates the complete spec contract;
- runs one focused Playwright Test replay;
- closes and deletes the prepared browser session;
- promotes the spec to
  `.tsupgrader/runtime-validation/playwright-scripts/<flow>.spec.ts`;
- releases the reservation and removes capture, launcher, pending spec,
  request state, Playwright CLI data, configs, reports, and test output.

The child returns the exact `status: "recorded"` JSON printed by that command.
The parent must treat the recorder output as immutable and must not inspect,
recreate, edit, replay, promote, or manually heal the spec.

If automatic replay rejects an assertion, the wrapper deletes the temporary
spec, clears only the rejected assertion, and keeps the browser request alive.
The child may take a new snapshot and choose another intent-matched assertion
through recorder commands. It must never edit generated TypeScript. The
wrapper permits at most two assertion repairs. If no stable recorder-command
repair succeeds, the child cancels an active request and the parent uses the
fallback instead of healing the spec. Replay infrastructure failures and an
exhausted retry limit clean the request automatically. Failures in recorded
navigation or interactions also clean the request because changing only the
assertion cannot repair them; use the fallback for that flow.

Each flow gets exactly one prepared attempt. Once an attempt concludes — whether
the spec was promoted or it failed terminally — that flow is closed for the rest
of this workflow: `typescript_prepare_browser_recording` rejects a second request
for the same `flowName` (`duplicate_flow_attempt`). Do not re-prepare a flow that
already concluded; use the `http-probe` fallback for it instead. Preparing a
*different* flow name is still allowed.

If the child cannot complete the flow, it runs the wrapper's `cancel` command
before returning failure. `cancel` closes the browser and removes the abandoned
request.

## Step 4 - Reference the recorded spec

Add the returned `specPath` to the eval plan:

```jsonc
"devServer": {
  "command": "npm",
  "args": ["run", "dev"],
  "url": "http://localhost:5173/"
},
"assertions": [
  {
    "name": "add-item-to-cart",
    "kind": "playwright-route",
    "scriptPath": ".tsupgrader/runtime-validation/playwright-scripts/add-item-to-cart.spec.ts",
    "verificationMethod": "exit-code",
    "expected": "0"
  }
]
```

The normal runtime-validation baseline is the first workflow-level execution
and verification of the accepted spec. The recorder has already run one
focused acceptance replay; post-upgrade validation replays the same spec.

## Step 5 - Stop the workflow-owned dev server

**Stop the recording server after the last flow is recorded — not after runtime
validation.** The dev server from Step 1 is only needed while recording.
**Runtime validation does not reuse it** — the eval plan's `devServer` block
(Step 4) starts and kills its own server around the `playwright-route`
assertions. A recording server left running collides with that eval-plan server
(or gets silently validated against instead of it) and orphans the process
after the workflow ends.

Once every planned flow has recorded or fallen back, run cleanup in a `finally`
path, before you call `typescript_validate_runtime`:

- When `serverOwnedByWorkflow` is true, stop the retained PID and its process
  tree, then verify its port is free.
- When `serverOwnedByWorkflow` is false, leave the existing server running.
  Never stop or kill that external process.

Cleanup is required on success, failure, and cancellation. No workflow-owned
dev server may survive past runtime validation.

**Also release whatever hosted the server, not just its port.** Killing the PID
is not enough to let the workflow exit. When `serverOwnedByWorkflow` is true,
after the process tree is gone also:

- close the background shell / terminal session that launched the server, so no
  host session stays open waiting on it;
- drain or cancel any pending background output reads or stdout/stderr pumps
  attached to that session;
- confirm no workflow-owned child process, browser, or Playwright driver is
  still alive.

A finished workflow must leave nothing running that could keep the top-level
agent process from exiting. After you report the final summary, the process
should be able to exit immediately, with no listening port, no open host
session, and no lingering child process.

## Fallback

Use `http-probe` assertions when approval is declined, preparation fails, the
host cannot launch the exact child, or recording fails.

Do not recreate the flow with selectors, helper scripts, Playwright MCP, MCP
Sampling, or `playwright codegen`.
