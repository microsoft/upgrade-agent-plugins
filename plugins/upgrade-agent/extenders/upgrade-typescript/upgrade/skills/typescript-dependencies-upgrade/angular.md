# Angular Projects

Angular projects have specific upgrade requirements due to the framework's tight coupling between packages. Follow this procedure **before** TypeScript migration and **before** upgrading any non-Angular dependency groups.

**Do NOT use `typescript_upgrade_package_dependency_group` for Angular packages** (`@angular/*`, `@angular-devkit/*`). Instead, use the Angular CLI's `ng update` command, which runs migration schematics that handle breaking config changes (like `buildTarget` schema migrations in `angular.json`). **Exception:** in an Nx workspace (`nx.json` present), use `nx migrate` instead of `ng update` — see [Nx workspaces](#nx-workspaces-nxjson-present).

## TypeScript Compatibility

Angular does **not** yet support TypeScript 7 (`@typescript/native-preview`). If the scan reports `typeScriptMigrationNeeded: true`, **cap the TypeScript upgrade at TypeScript 6**. Do NOT proceed to TypeScript 7. Upgrade Angular first, then TypeScript — `ng update` manages the TypeScript version at each hop. When the TypeScript migration phase runs, follow the TypeScript 6 guide ([5to6.md](../typescript-compiler-upgrade/5to6.md)); its `moduleResolution: "bundler"` / `exports`-map fixes are especially common with Angular's package `exports`.

## Nx workspaces (`nx.json` present)

If the repo root has an `nx.json`, the Angular versions are governed by Nx (`@nrwl/*` / `@nx/*`), and **`ng update` does not apply** — drive the upgrade with `nx migrate` per major instead. The pre-flight, TypeScript-6, and per-hop validation guidance below still apply; only the upgrade command changes. Known Nx pitfalls (do these from the start):

- **Pin the exact Nx patch every hop.** A floating-major `nx migrate @nrwl/workspace@N` crashes (`Cannot read properties of undefined (reading 'schematics')`). Use a concrete patch per hop (e.g. `@13.10.6`, `@14.8.6`, `@15.9.7`, `@16.10.0`, …), then `nx migrate --run-migrations` and prune broken entries (below).
- **CLI entry point moves at v13; `@nrwl/*` → `@nx/*` scope rename at v16.** From Nx 13, invoke `node node_modules/nx/bin/nx.js` — the old `@nrwl/cli/bin/nx.js` throws `MODULE_NOT_FOUND`. At Nx 16, `nx migrate --run-migrations` renames the `@nrwl/*` packages to the `@nx/*` scope (the `@nrwl/*` aliases stop being published at Nx 20).
- **The `@nrwl/angular` alias caps Angular.** Migrating `@nrwl/workspace` leaves Angular behind. After each Nx hop, bump Angular explicitly per major: `nx migrate @angular/core@N @angular/cli@N` (and `@angular/material@N` / `@angular/cdk@N` if present), then `--run-migrations`.
- **Prune broken migrations.** Some `migrations.json` entries fail (`split-configuration` "missing a factory"; Angular schematics throwing `tree.readText is not a function` on a stale Nx devkit; project-config migrations on `package.json`-based projects). Remove the failing entries from `migrations.json`, keep the Angular source migrations that run, and rely on the final build to surface anything truly needed.
- **Old Nx executors can't build Angular 22.** If `nx build` fails because the workspace's `@nx/angular` executor is too old, build the target **directly** — Angular CLI for apps (`node node_modules/@angular/cli/bin/ng build <project>`), `ng-packagr` for libraries, `tsc -p` for plain-TS libs. Libraries consumed via tsconfig `paths` type-check as part of the app build, so a separate lib build is often unnecessary.

In addition to the standard pre-flight, for Nx also remove any `ngcc`/`decorate` postinstall script and set `NX_SKIP_PROVENANCE_CHECK=true` for the migration commands.

## Pre-flight (do this ONCE, before the hop loop)

These one-time checks make each hop's install succeed on the first try. When `ng update`'s internal install fails silently, its migration schematics are **skipped**, which is the most common cause of a "successful" hop that left broken code — so spend the time here, not in per-hop retries.

### Node version
Read the target Angular major's required Node range (e.g., Angular 20+ needs Node ≥ 20.19, Angular 22 needs Node ≥ 24.15). Compare against the host (`node --version`). If the host is below the floor, locate a compatible Node (e.g., an installed `nvm`/`fnm` version) and use it for **all** subsequent `ng`/install/`validate_runtime` steps. A too-old Node causes confusing mid-hop failures and false runtime-validation results.

### Install compatibility (so `ng update`'s internal install doesn't fail)
- **Peer-dependency conflicts (npm 7+):** add `legacy-peer-deps=true` to a project-root `.npmrc` (create it if absent). Modern npm's strict peer resolution otherwise aborts `ng update`'s internal install.
- **`ngcc` / `decorate` postinstall scripts:** Angular 16+ removed `ngcc`. If `package.json` `scripts.postinstall` runs `ngcc` (or an Angular `decorate`/`ngcc` step), remove it before crossing into v16 — it errors once the binary is gone and blocks installs.
- **`node-sass`:** replace `node-sass` with `sass` (Dart Sass). `node-sass` fails to build its native binding on Node 18+/24.

### One clean install
Do a single clean install now (`npx -y rimraf node_modules`, then `typescript_install_dependencies`). After this, rely on `ng update`'s built-in install for each hop — do **not** wipe `node_modules` every hop.

## Step-by-Step Angular Upgrade Procedure

Angular major versions **must** be upgraded one at a time (e.g., 16 → 17 → 18 → 19 → 20 → 21). You cannot skip major versions.

**First, detect the workspace type.** If the repo root has an `nx.json`, follow the [Nx workspaces](#nx-workspaces-nxjson-present) section above for the upgrade command (`nx migrate` per major) instead of the `ng update` loop below — the rest of this procedure (pre-flight, validation, TypeScript 6) is unchanged.

**Package manager:** The commands below use `npx` to invoke the Angular CLI. If the scan returned a different `packageManager`, substitute accordingly:
- **yarn:** use `yarn dlx` instead of `npx`
- **pnpm:** use `pnpm dlx` instead of `npx`

### 1. Detect the current Angular major version

Read `@angular/core` from `package.json` (dependencies or devDependencies) and extract the major version number.

### 2. Determine the target Angular major version

Use the latest stable Angular major version as the target. You can check this via a shell command (e.g., `npm view @angular/core version` — this queries the npm registry and works regardless of which package manager the project uses).

### 3. Loop: upgrade one major version at a time

For each major version `N` from `(current + 1)` to `target`:

**a.** Run `ng update` for the core Angular packages (this installs the new versions internally):
```
npx ng update @angular/cli@^N @angular/core@^N --allow-dirty --force
```

**b.** If the project uses `@angular/material`, also update it:
```
npx ng update @angular/material@^N --allow-dirty --force
```
(Skip this if `@angular/material` is not in `package.json`.)

**c.** Build to verify the upgrade succeeded:
```
npx ng build
```

**d.** Only reinstall if the build reports missing modules or a lockfile mismatch (i.e. `ng update`'s internal install didn't fully apply) — call `typescript_install_dependencies` with `rootDirectory` and `packageDirectory`. If that still fails, fall back to a clean reinstall (`npx -y rimraf node_modules` then `typescript_install_dependencies`). Skip this step entirely when the build already succeeded.

**e.** If the build fails, inspect the errors. Common issues after each hop:
- **`buildTarget` schema errors** — The `ng update` schematics should have migrated `angular.json` automatically. If they didn't, check that `angular.json` uses the new `application` builder format (Angular 17+). See the "Common Issues" section below.
- **Peer dependency warnings** — Usually safe to ignore during intermediate hops since the next hop will align versions.

**f.** Verify you landed on the expected version by re-reading `@angular/core` from `package.json`.

### 4. After all Angular hops complete

1. ⛔ **Runtime validation** — If `validateRuntime` is true, run runtime validation now (read [runtime-validation.md](./runtime-validation.md)). Do NOT return to the main workflow until runtime validation passes. Fix any errors before proceeding.

2. **Return to the calling workflow** (SKILL.md) to continue with the remaining upgrade phases (TypeScript migration, non-Angular packages, etc.). When upgrading non-Angular dependency groups, **exclude** any groups that contain `@angular/*` or `@angular-devkit/*` packages — those are already upgraded.

## Validating an Angular build (`compile_package` / `write_upgrade_summary`)

For Angular projects the **authoritative compile signal is `ng build` / ng-packagr** (and, when `validateRuntime` is true, the `validate_runtime` `app-builds` assertion) — not raw `tsc`. `typescript_compile_package` and the `write_upgrade_summary` rebuild type-check the tree with raw `tsc`, which is **not** representative of a multi-project or library Angular workspace and will surface false errors. Two things to do:

- **Before** calling `typescript_compile_package` or `typescript_write_upgrade_summary` on a multi-project/library workspace, normalize the base `tsconfig.json` so the raw-`tsc` pass doesn't choke on files outside the build graph: **exclude test files** (`**/*.spec.ts`, `cypress/**`, `e2e/**`) and ensure the base config lists the ambient `types` the project relies on (e.g. `"types": ["jasmine", "node"]`). Without this, raw `tsc` reports hundreds of false `Cannot find name 'describe'/'cy'` errors.
- **Treat as known false positives** (note them in the summary, do NOT chase or "fix" them) any residual raw-`tsc` errors that are confined to: spec/test files, Angular **library source** (decorator errors like `TS1206`/`TS1240`, which raw `tsc` cannot compile — only `ngc`/ng-packagr can), or `exports`-map resolution under a library's legacy `moduleResolution: node` (e.g. `Cannot find module '@angular/common/http'`). If `ng build` / ng-packagr is clean for the upgraded targets, the build is good regardless of these.

## Telemetry

After all Angular hops are complete (or if the upgrade fails at a particular hop), call `typescript_report_telemetry` with:
- `eventType`: `"group_upgrade"`
- `group`: `"angular"`
- `sessionId`: from the scan response
- `success`: whether the full Angular upgrade succeeded
- `fromVersion`: the starting Angular major version (e.g., `"16"`)
- `toVersion`: the target Angular major version (e.g., `"21"`)
- `strategy`: `"major-by-major"` (Angular upgrades one major at a time via `ng update`)
- `upgradeSteps`: the number of major version hops performed (e.g., `5` for 16→21)
- `failureReason`: (if failed) a brief description of why the upgrade failed

`typescript_report_telemetry` is **not** the terminal event. Return to `SKILL.md` which finishes with `typescript_write_upgrade_summary`. In the rare case you must stop early instead of returning, still call `typescript_write_upgrade_summary` once before exiting.

## Common Issues

### `buildTarget` schema errors
Angular 17+ migrated from the `@angular-devkit/build-angular:browser` builder to `@angular-devkit/build-angular:application`. The `ng update` schematics handle this automatically, but if the migration didn't run or was incomplete:
- Open `angular.json`
- In `architect.build`, check that `builder` is `@angular-devkit/build-angular:application`
- The `buildTarget` property and related options may need manual adjustment — compare against a freshly generated Angular project of the same version for reference

### Strict version mismatches
Angular will refuse to build if `@angular/*` packages are misaligned. All `@angular/*` packages in a project must be the same major version.

### RxJS coupling
Angular versions are often tied to specific RxJS versions. The `ng update` schematics usually handle this, but if you see RxJS errors after an upgrade hop, check `package.json` for version mismatches and align RxJS to the version expected by that Angular major.

### Decorator metadata changes
Older Angular versions used different decorator compilation. If upgrading across many majors (e.g., 14 → 21), expect intermediate hops to handle these transitions.

### Stale or inconsistent `node_modules`
The hop loop relies on `ng update`'s internal install and does not wipe `node_modules` each hop. If a hop fails with module-resolution or native-binding errors that a plain reinstall doesn't fix, do a one-off clean reinstall as a recovery step: `npx -y rimraf node_modules`, then `typescript_install_dependencies`. Use this only when needed — not on every hop.

### Module system changes
Angular has moved toward standalone components (replacing NgModules). The `ng update` schematics may offer to migrate your code. Accept the migrations when prompted.
