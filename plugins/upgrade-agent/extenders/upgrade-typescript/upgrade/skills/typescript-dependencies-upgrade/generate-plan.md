# Scan & Baseline Instructions

## Phase 0 — Scan Dependencies

Call `typescript_scan_dependencies` with:
- `rootDirectory` — the repository root.
- `packageDirectory` — optional; provide if upgrading a specific package in a monorepo.
- `requestedPackages` — REQUIRED. The explicit list of packages the user named (e.g., `["react", "axios"]`). Pass `[]` (empty array) when the user asked to upgrade everything. Omit only if intent is genuinely unknown.
- `skill` — REQUIRED. Pass `"typescript-dependencies-upgrade"`.

Review the scan results. The tool returns structured JSON including:
- `packageManager` — npm, yarn, or pnpm
- `isMonorepo` — whether the project is a monorepo
- `applicableGuidance` — an ordered list of guidance **entries** the agent must read before proceeding, already sorted into execution order. Each entry is a self-describing object: `file` (skill-relative path, e.g. `react.md`, `react/19.md`), `framework` (e.g. `react`), `mode` (`replaces` = the file drives Phase 2 for its packages, e.g. `angular.md`; `constrains` = the file constrains the standard flow, e.g. `react.md`), and — on a framework's primary entry — optional `runAfter` (frameworks that must be handled first), `fromMajor`/`toMajor` (the version delta), and a one-line `summary`. Example: `[{"file":"react.md","framework":"react","mode":"constrains","fromMajor":18,"toMajor":19,"summary":"…"}, {"file":"react/19.md","framework":"react","mode":"constrains"}]`. An empty list means no framework-specific guidance applies.
- `typeScriptMigrationNeeded` — whether the project's TypeScript is outdated (a project fact, independent of the requested scope). If true, the response also includes `currentTypeScriptVersion` and `targetTypeScriptVersion`. Whether you act on it is gated by scope — see below.
- `featureFlags` — which optional validation phases are enabled:
  - `validateRuntime` — validate the app runs after upgrades
  - `validateBundlerChanges` — validate build after bundler upgrades
  - `runNpmAudit` — fix security vulnerabilities after upgrades
  - `disableKnowledgeBase` — skip knowledge base fixes
- `packages` — array of packages with their `directory` and `dependencyGroups`. Each dependency group is an object with:
  - `packages` — ordered list of package names to upgrade together
  - `containsBundlers` — true if any package in the group is a bundler/build tool (webpack, vite, esbuild, rollup, tsup, etc.)
- `sessionId` — pass this to all subsequent tool calls

For very large monorepos the response may be summarized — see [monorepo.md](./monorepo.md) for the truncation contract and how to drill into a summarized package.

**If `typeScriptMigrationNeeded` is true and TypeScript is in scope** (the user asked for all packages, or named `typescript`), read [compiler-upgrade.md](../typescript-compiler-upgrade/compiler-upgrade.md) for guidance.

**If `applicableGuidance` is non-empty**, read the `file` of every entry (in the order given — the list is already sorted so any framework another one `runAfter` comes first) before proceeding to Phase 1. The list is already scoped to your upgrade — a framework's guidance is listed only when that framework's packages are actually in scope (e.g. a Jest-only request on a React app won't include `react.md`), so read exactly what's listed and nothing more. Honor each entry's `mode`: a `replaces` entry (e.g. `angular.md`) drives Phase 2 for its packages in place of the default flow; a `constrains` entry (e.g. `react.md`) keeps the standard per-group flow but adds mandatory rules. Each guidance file is also self-describing — its header restates its `mode`/`runAfter` and it states when in the workflow its rules apply.

**If `isMonorepo` is true**, read [monorepo.md](./monorepo.md) for monorepo handling.

## Phase 1 — Establish Baseline

Before making any changes, verify the project works:

1. Call `typescript_install_dependencies` with `rootDirectory` and `packageDirectory`. If it fails or hangs because of a package-manager/toolchain problem (missing or wrong-versioned `npm`/`yarn`/`pnpm`/`corepack`, lockfile/integrity mismatch), stop and report the blocker via `typescript_write_upgrade_summary` — do not try to repair the toolchain (see Key Principle #9 in [SKILL.md](./SKILL.md)).
2. Call `typescript_compile_package` with `rootDirectory` and `packageDirectory`.
3. If `validateBundlerChanges` is true and **any dependency group has `containsBundlers: true`**, call `typescript_build_package` with `rootDirectory` and `packageDirectory` to establish a bundler build baseline.
4. If `validateRuntime` is true, establish a runtime baseline — read [runtime-validation.md](./runtime-validation.md).

Record the baseline: install success, number of pre-existing build errors, test pass/fail counts.