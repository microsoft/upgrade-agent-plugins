# modernize-dashboard canvas extension

Canvas extension that mirrors the .NET Upgrade dashboard
(`src/dashboard/`) inside the GitHub App side panel.

## Shipping

This extension is bundled into the shipped `upgrade-agent` Copilot CLI plugin
by the plugin generator (`utils/generate-plugin`), under
`extensions/modernize-dashboard/`. The generator bundles the canvas
**by default**, so the published `copilot-cli-plugin` (and
`copilot-cli-plugin-with-claude`) artifacts carry the canvas; pass
`--skip-canvas-extension` to opt out. `tools/install-local.ps1`
bundles the same allowlisted subset into the local orchestrator plugin by
default (`-SkipCanvasExtension` opts out).

Once shipped, the CLI runtime discovers it as
`plugin:upgrade-agent:modernize-dashboard` and loads it **only where the host
enables the `EXTENSIONS` feature flag**. The generator ships an allowlisted
subset (`extension.mjs`, `README.md`, `lib/`, `canvas/`) plus a sanitized
`package.json`; `test/`, `bin/`, `node_modules`, `install-local.*`, and
`playwright.config.mjs` are excluded. The host injects `@github/copilot-sdk`
at runtime, so no `node_modules` ships.

## Prerequisites

You'll need the following installed before running or installing this extension:

- **The GitHub Copilot App (desktop)** — this extension surfaces as a *canvas*
  in the side panel of the GitHub App. It will not load in the standalone
  Copilot CLI or in VS / VS Code. Make sure you're on a build that supports
  the canvas extension API.
- **Node.js 20 or newer** — the extension is pure ES modules. `node --test`
  is used for unit tests, so 20+ is required. Verify with `node --version`.
- **npm 10 or newer** — ships with Node 20. Used to install peer dependencies
  and run the test scripts. Verify with `npm --version`.
- **`@github/copilot-sdk`** — declared as a **peer** dependency. The host
  Copilot app provides this at runtime when the extension is loaded as a
  canvas. For local dev / standalone CLI / running tests, `npm install` in
  this folder will pull it in.
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

The standalone CLI (`bin/modernize-dashboard`) only needs Node + a target
repo — the GitHub Copilot App is not required for that mode.

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
- **Dependencies** — `dependencies-health.json` (`DependencyHealthProducer`
  lookup chain) with packages + per-project compatibility tables.
- **Assessment** — `assessment.json` summary, severity/category bar charts,
  and per-project incident table.

Data is served from a loopback HTTP server on `127.0.0.1:0`. The iframe pulls
state via `GET /api/state` and subscribes to `GET /events` (Server-Sent Events)
for live updates as the activity log grows.

## Install (POC)

A helper script handles install/uninstall. By default it installs into
**user scope** at `$COPILOT_HOME/extensions/modernize-dashboard/` (where
`$COPILOT_HOME` defaults to `~/.copilot`), so the canvas shows up in every
session — no workspace setup required. extensionId becomes
`user:modernize-dashboard`.

```powershell
# Default: user scope, copy + npm install
.\install-local.ps1

# User scope, but symlink so edits are live (needs Developer Mode or admin)
.\install-local.ps1 -Symlink

# Project scope instead — only available in the specified workspace
.\install-local.ps1 -Workspace C:\path\to\test-workspace

# Skip npm install (iterating on canvas/ assets only)
.\install-local.ps1 -SkipInstall

# Remove it
.\install-local.ps1 -Uninstall
.\install-local.ps1 -Workspace C:\path\to\test-workspace -Uninstall
```

The runtime auto-discovers the extension via the `package.json` it finds and
registers the canvas declared by `extension.mjs` at
`joinSession({ canvases: [...] })`. After editing extension code in symlink
mode, call `extensions_reload` (or restart the agent) to pick it up.

## Canvas surface

- `extensionId`: `user:modernize-dashboard` (or `project:modernize-dashboard` for project-scope installs)
- `canvasId`: `dashboard`
- `displayName`: `Upgrade Dashboard`
- Open input: optional `{ panel?: "overview" | "activity" | "scenario" | "projects" | "dependencies" | "assessment" | "tasks" | "options" | "diagnostics" }` — unknown values fall back to `overview`.
- Actions:
  - `refresh` — force-reload artifact state from disk.
  - `set_panel` — agent-driven tab switch (input: `{ panel: <one of the above> }`).
  - `switch_mode` — relay a request to switch flow mode (input: `{ mode: "guided" | "automatic" }`); posted as a chat message to the host agent.
  - `share_assessment_as_gist` — relay a request to publish the current assessment as a private GitHub gist.
  - `explain_dependency` — relay a request to explain a dependency / version drift (input: `{ packageName: string }`).

## Limitations vs. the Blazor dashboard

This POC is intentionally shallow. It reads the same on-disk artifacts and
renders a flat HTML view. The MCP server's `ServiceHostLifecycleService` spawns
the ServiceHost process to produce `activity.jsonl` — the canvas extension
only reads the file.

### ServiceHost lifecycle

The MCP server (`ServiceHostLifecycleService`) is responsible for spawning and
managing the ServiceHost process. The canvas extension no longer manages the
ServiceHost — it only reads the `activity.jsonl` file produced by it.

For local development, the `CopyServiceHostForLocalDev` MSBuild target in the
MCP `.csproj` copies ServiceHost build output into `$(TargetDir)Dashboard/`
after build, so `dotnet build` is sufficient (no `dotnet publish` required).

- the dashboard's changelog event types (`task_started`, `task_completed`,
  `task_failed`, `file_modified`, `commit_created`, `build_completed`,
  `phase_entered`, `branch_changed`, …) and their human formatting;
- `ProjectDiscovery`'s rules for finding `.csproj`/`.fsproj` and extracting
  `<TargetFramework>`/`<TargetFrameworks>`;
- `AssessmentProducer`'s file-lookup order
  (`scenario/assessment.json` → `scenario/assessment/assessment.json` →
  `.vs/upgrade/assessment/assessment.json`) and the summary metrics + severity
  / category chart data it publishes.
