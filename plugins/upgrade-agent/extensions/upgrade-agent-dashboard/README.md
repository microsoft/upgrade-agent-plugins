# upgrade-agent-dashboard canvas extension

Canvas extension that mirrors the .NET Upgrade dashboard
(`src/dashboard/`) inside the GitHub App side panel.

## Shipping

This extension is bundled into the shipped `upgrade-agent` Copilot CLI plugin
by the plugin generator (`utils/generate-plugin`), under
`extensions/upgrade-agent-dashboard/`. The generator bundles the canvas
**by default**, so the published `copilot-cli-plugin` (and
`copilot-cli-plugin-with-claude`) artifacts carry the canvas; pass
`--skip-canvas-extension` to opt out. `tools/install-local.ps1`
bundles the same allowlisted subset into the local orchestrator plugin by
default (`-SkipCanvasExtension` opts out).

Once shipped, the CLI runtime discovers it as
`plugin:upgrade-agent:upgrade-agent-dashboard` and loads it **only where the host
enables the `EXTENSIONS` feature flag**. The generator ships an allowlisted
subset (generated `dist/extension.mjs`, flattened to root `extension.mjs`, plus
`README.md` and `canvas/app/`) and a sanitized
`package.json`; `test/`, `bin/`, `node_modules`, `install-local.*`, and
authored HTML/TypeScript are excluded. Vite builds the browser surface and
esbuild bundles `extension.ts` to `dist/extension.mjs`. The host injects `@github/copilot-sdk`
at runtime, so no `node_modules` ships.

## Prerequisites

You'll need the following installed before running or installing this extension:

- **The GitHub Copilot App (desktop)** — this extension surfaces as a *canvas*
  in the side panel of the GitHub App. It will not load in the standalone
  Copilot CLI or in VS / VS Code. Make sure you're on a build that supports
  the canvas extension API.
- **Node.js 20 or newer** — the extension uses TypeScript, React, and ES modules. `node --test`
  is used for unit tests, so 20+ is required. Verify with `node --version`.
- **npm 10 or newer** — ships with Node 20. Used to install peer dependencies
  and run the test scripts. Verify with `npm --version`.
- **`@github/copilot-sdk`** — declared as a **peer** dependency. The host
  Copilot app provides this at runtime when the extension is loaded as a
  canvas. Use `npm ci --omit=peer` when building or testing locally.
- **PowerShell 5.1+ or `cmd.exe`** — for running `install-local.ps1` /
  `install-local.cmd`. The cmd variant exists specifically so you don't
  need PowerShell.
- **Playwright browsers** (only if you'll run E2E tests) — `npm run test:e2e`
  will prompt to install Chromium on first run, or run `npx playwright install
  chromium` explicitly.
- **A repo with `.github/upgrades/scenarios/...` artifacts** — the dashboard
  is read-only; it surfaces files produced by the .NET upgrade agent. To
  see anything meaningful, point it at a repo that has already run through
  (or is in the middle of) an upgrade session. An empty repo will
  render a "no active scenario" empty state.

The standalone CLI command (`upgrade-agent-dashboard`) only needs Node + a
target repo — the GitHub Copilot App is not required for that mode. Its source
is `bin/upgrade-agent-dashboard.ts`; `npm run build` emits the executable
`dist/upgrade-agent-dashboard.mjs`.

## What it shows

A tabbed view of the same artifacts the Blazor dashboard reads:

- **Activity** — tail of `<repo>/.git/upgrade/activity.jsonl` (falls back to
  `.vs/upgrade/activity.jsonl`), formatted per `ChangelogEventTypes`.
- **Tasks** — parsed `<scenario>/tasks.md` (emoji-prefixed lines via
  `TasksProducer`'s format) with progress, overview, and a hierarchical
  state-badged list.
- **Scenario** — the auto-detected scenario from
  `<repo>/.github/upgrades/scenarios/*/scenario.json`.
- **Projects** — `*.csproj`/`*.fsproj` discovered the same way as
  `Dashboard.Core.Providers.Build.ProjectDiscovery`, with target frameworks
  read from the XML.
- **Dependencies** — `<scenario>/dependencies-health.json` with packages +
  per-project compatibility tables.
- **Assessment** — `<scenario>/assessment.json` summary, severity/category bar
  charts, and per-project incident table.

### Diagnostics (debug only, hidden)

Path probes, repo-root resolution source, and env-var echoes are still built
into the snapshot and rendered into an overlay, but **nothing in the UI opens
it** — there is no tab and no icon. It is reachable only by:

- the `set_panel` canvas action with `{ panel: "diagnostics" }` (i.e. asking
  the agent to open the diagnostics panel), or
- `?panel=diagnostics` on the URL in standalone CLI mode
  (`upgrade-agent-dashboard --panel diagnostics`).

This keeps a support/debugging affordance available without shipping it as
part of the product surface.

Data is served from a loopback HTTP server on `127.0.0.1:0`. The webview pulls
state via `GET /api/state` and subscribes to `GET /events` (Server-Sent Events)
for live updates as the activity log grows.

## Frontend development

The canvas uses an incremental React-island architecture. The existing shell,
shared CSS, SSE subscription, and panels not yet migrated remain in
`canvas/index.html`. `canvas/src/Overview.tsx` owns only Overview and is
rendered from the existing `render(state)` flow. Its IDs and classes intentionally
match the previous DOM renderer so the browser tests remain the contract.
Overview-specific static styles live beside it in `canvas/src/Overview.css`;
Vite extracts those rules into a hashed CSS asset during the build.

```powershell
npm ci --omit=peer
npm run typecheck
npm run build
npm run test:unit
npm run test:e2e
```

`npm run build` emits `canvas/app/index.html`, hashed Vite assets under
`canvas/app/assets/`, generated `dist/extension.mjs`, and generated
`dist/upgrade-agent-dashboard.mjs`, plus individual generated helpers under
`dist/lib/`. These outputs are ignored and must be regenerated after editing
browser sources, `extension.ts`, `bin/upgrade-agent-dashboard.ts`, or `lib/*.ts`.

Tests are authored in TypeScript. Playwright runs `test/e2e/*.test.ts` directly;
the unit-test build emits Node 20-compatible `dist/test/unit/*.test.mjs` before
`node --test` executes them.

## Install (POC)

A helper script handles install/uninstall. By default it installs into
**user scope** at `$COPILOT_HOME/extensions/upgrade-agent-dashboard/` (where
`$COPILOT_HOME` defaults to `~/.copilot`), so the canvas shows up in every
session — no workspace setup required. extensionId becomes
`user:upgrade-agent-dashboard`.

```powershell
# Default: build, then install at user scope
.\install-local.ps1

# User scope, but link generated runtime files (needs Developer Mode or admin)
.\install-local.ps1 -Symlink

# Project scope instead — only available in the specified workspace
.\install-local.ps1 -Workspace C:\path\to\test-workspace

# Reuse existing canvas/app/ and dist/extension.mjs output
.\install-local.ps1 -SkipInstall

# Remove it
.\install-local.ps1 -Uninstall
.\install-local.ps1 -Workspace C:\path\to\test-workspace -Uninstall
```

The runtime discovers only a root file named `extension.mjs`; it does not use
`package.json.main`. Installers therefore flatten generated
`dist/extension.mjs` to root `extension.mjs`, which registers the canvas at
`joinSession({ canvases: [...] })`. After editing extension code in symlink
mode, run `npm run build`, then call `extensions_reload` (or restart the agent)
to pick it up.

## Canvas surface

- `extensionId`: `user:upgrade-agent-dashboard` (or `project:upgrade-agent-dashboard` for project-scope installs)
- `canvasId`: `dashboard`
- `displayName`: `Upgrade Agent Dashboard`
- Open input: optional `{ panel?: "overview" | "activity" | "scenario" | "projects" | "dependencies" | "assessment" | "tasks" | "options" | "diagnostics" }` — unknown values fall back to `overview`. `diagnostics` is a debug-only overlay with no UI affordance (see [Diagnostics](#diagnostics-debug-only-hidden)).
- Actions:
  - `refresh` — force-reload artifact state from disk.
  - `set_panel` — agent-driven tab switch (input: `{ panel: <one of the above> }`).
  - `switch_mode` — relay a request to switch flow mode (input: `{ mode: "guided" | "automatic" }`); posted as a chat message to the host agent.
  - `share_assessment_as_gist` — relay a request to publish the current assessment as a private GitHub gist.
  - `explain_dependency` — relay a request to explain a dependency / version drift (input: `{ packageName: string }`).
  - `push_context` — hand the agent a summary of what the user is currently looking at in the canvas.

## Limitations vs. the Blazor dashboard

This POC reads the same on-disk artifacts and is migrating one panel at a time
from imperative DOM rendering to React. The MCP server's `ServiceHostLifecycleService` spawns
the ServiceHost process to produce `activity.jsonl` — the canvas extension
only reads the file.

### ServiceHost lifecycle

The MCP server (`ServiceHostLifecycleService`) is responsible for spawning and
managing the ServiceHost process. The canvas extension no longer manages the
ServiceHost — it only reads the `activity.jsonl` file produced by it.

For local development, the `CopyServiceHostForLocalDev` MSBuild target in the
MCP `.csproj` copies ServiceHost build output into `$(TargetDir)Dashboard/`
after build, so `dotnet build` is sufficient (no `dotnet publish` required).

### Behaviour it mirrors

The canvas re-implements, rather than shares, a handful of Blazor dashboard
behaviours. When those change on the .NET side, the corresponding
`lib/*.ts` source and its test-only `dist/lib/*.mjs` output need the same change:

- the activity event types (`task_started`, `task_completed`,
  `task_failed`, `file_modified`, `commit_created`, `build_completed`,
  `phase_entered`, `branch_changed`, …) and their human formatting;
- `ProjectDiscovery`'s rules for finding `.csproj`/`.fsproj` and extracting
  `<TargetFramework>`/`<TargetFrameworks>`;
- the summary metrics + severity / category chart data `AssessmentProducer`
  publishes. Note the canvas reads `assessment.json` and
  `dependencies-health.json` only from the scenario folder, which is where the
  current writers put them; the Blazor readers retain extra defensive
  fallbacks (`<scenario>/assessment/`, `.vs/upgrade/assessment/`) that no
  writer targets.
