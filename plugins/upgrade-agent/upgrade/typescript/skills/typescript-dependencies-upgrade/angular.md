# Angular Projects

Angular projects have specific upgrade requirements due to the framework's tight coupling between packages. Follow this procedure **before** TypeScript migration and **before** upgrading any non-Angular dependency groups.

**Do NOT use `typescript_upgrade_package_dependency_group` for Angular packages** (`@angular/*`, `@angular-devkit/*`). Instead, use the Angular CLI's `ng update` command, which runs migration schematics that handle breaking config changes (like `buildTarget` schema migrations in `angular.json`). **Exception:** in an Nx workspace (`nx.json` present), use `nx migrate` instead of `ng update` — see [Nx workspaces](#nx-workspaces-nxjson-present).

## TypeScript Compatibility

Angular does **not** yet support TypeScript 7. If the scan reports `typeScriptMigrationNeeded: true`, **cap the TypeScript upgrade at TypeScript 6**. Do NOT proceed to TypeScript 7. Upgrade Angular first, then TypeScript — `ng update` manages the TypeScript version at each hop. When the TypeScript migration phase runs, follow the TypeScript 6 guide ([5to6.md](../typescript-compiler-upgrade/5to6.md)); its `moduleResolution: "bundler"` / `exports`-map fixes are especially common with Angular's package `exports`.

## Nx workspaces (`nx.json` present)

If the repo root has an `nx.json`, the Angular versions are governed by Nx (`@nrwl/*` / `@nx/*`), and **`ng update` does not apply** — drive the upgrade with `nx migrate` per major instead. The pre-flight, TypeScript-6, and per-hop validation guidance below still apply; only the upgrade command changes. Known Nx pitfalls (do these from the start):

- **Pin the exact Nx patch every hop.** A floating-major `nx migrate @nrwl/workspace@N` crashes (`Cannot read properties of undefined (reading 'schematics')`). Use a concrete patch per hop (e.g. `@13.10.6`, `@14.8.6`, `@15.9.7`, `@16.10.0`, …), then `nx migrate --run-migrations` and prune broken entries (below).
- **CLI entry point moves at v13; `@nrwl/*` → `@nx/*` scope rename at v16.** From Nx 13, invoke `node node_modules/nx/bin/nx.js` — the old `@nrwl/cli/bin/nx.js` throws `MODULE_NOT_FOUND`. At Nx 16, `nx migrate --run-migrations` renames the `@nrwl/*` packages to the `@nx/*` scope (the `@nrwl/*` aliases stop being published at Nx 20).
- **The `@nrwl/angular` alias caps Angular.** Migrating `@nrwl/workspace` leaves Angular behind. After each Nx hop, bump Angular explicitly per major: `nx migrate @angular/core@N @angular/cli@N` (and `@angular/material@N` / `@angular/cdk@N` if present), then `--run-migrations`. On the final hop, use each package's own exact entry from the scan group's `targetVersions` when present and keep `@N` for untargeted Angular packages; verify every explicitly targeted package landed on its requested patch.
- **Prune broken migrations.** Some `migrations.json` entries fail (`split-configuration` "missing a factory"; Angular schematics throwing `tree.readText is not a function` on a stale Nx devkit; project-config migrations on `package.json`-based projects). Remove the failing entries from `migrations.json`, keep the Angular source migrations that run, and rely on the final build to surface anything truly needed.
- **Old Nx executors can't build Angular 22.** If `nx build` fails because the workspace's `@nx/angular` executor is too old, build the target **directly** — Angular CLI for apps (`node node_modules/@angular/cli/bin/ng build <project>`), `ng-packagr` for libraries, `tsc -p` for plain-TS libs. Libraries consumed via tsconfig `paths` type-check as part of the app build, so a separate lib build is often unnecessary.

In addition to the standard pre-flight, for Nx also remove any `ngcc`/`decorate` postinstall script and set `NX_SKIP_PROVENANCE_CHECK=true` for the migration commands.

## Pre-flight (do this ONCE, before the hop loop)

These one-time checks make each hop's install succeed on the first try. When `ng update`'s internal install fails silently, its migration schematics are **skipped**, which is the most common cause of a "successful" hop that left broken code — so spend the time here, not in per-hop retries.

### Preserve the build configuration

Before the Phase 1 baseline, inspect `angular.json`, the package scripts, and any custom builder configuration. Record which scripts and named configurations produce the deployed application, which workspace libraries must build first, and which plugins supply feature flags, environment values, HTML transforms, or workers.

### Keep every CLI invocation unattended

Set `CI=true` and `NG_CLI_ANALYTICS=false` for **all** Angular commands, including baseline builds, prerequisite workspace builds, each hop's build/postbuild, and the final clean-install build. Setting `CI=true` only on `ng update` does not affect a later command in a fresh shell; repeat these environment settings in every new shell or command invocation. Angular's first-run analytics question can otherwise stall `ng build` before compilation. Do not opt into analytics or wait for interactive input.

- **PowerShell:** `$env:CI = "true"; $env:NG_CLI_ANALYTICS = "false"` before the existing build or migration command.
- **Bash / sh:** prefix each existing build or migration command with `CI=true NG_CLI_ANALYTICS=false`.

Keep `NG_DISABLE_VERSION_CHECK=1` on migrations as described below. These are command-scoped environment settings, not a reason to rewrite the project's build scripts or runtime-validation plan.

### Node version & per-hop runtime policy
Select Node from the [published Angular compatibility ranges](https://angular.dev/reference/versions), not just a minimum floor. All versions within a listed range are supported; there is no separate, stricter "recommended" minimum. A caret range stays within its Node major: `^20.19.0` means `>=20.19.0 <21.0.0`, not any newer Node.

| Angular | Supported Node.js ranges |
|---|---|
| 12 | `^12.14.0 || ^14.15.0` |
| 13 | `^12.20.0 || ^14.15.0 || ^16.10.0` |
| 14 | `^14.15.0 || ^16.10.0` |
| 15 | `^14.20.0 || ^16.13.0 || ^18.10.0` |
| 16 | `^16.14.0 || ^18.10.0` |
| 17 | `^18.13.0 || ^20.9.0` |
| 18 – 19 | `^18.19.1 || ^20.11.1 || ^22.0.0` |
| 20 – 21 | `^20.19.0 || ^22.12.0 || ^24.0.0` |
| 22 | `^22.22.3 || ^24.15.0 || ^26.0.0` |

Verify the exact Angular release against the linked table before each hop. The selected runtime must also satisfy the migration CLI and the project's build tools; use an overlapping supported range for the starting and destination versions where possible. Older Node versions here are temporary migration runtimes, not recommendations for the final deployment.

**Do NOT silently lower the requested Angular target just because the currently active shell Node is too old, and do NOT jump straight to the newest Node (e.g., Node 24) for the entire migration when starting from an older Angular major (e.g., Angular 12–15) that doesn't support it.** Follow this policy:

| Situation | Required behavior |
|---|---|
| **A compatible Node is already installed** | Select it explicitly (via `nvm`, `fnm`, `volta`, or prepending its bin directory to `PATH`) for installs, migrations, builds, and validation. |
| **No compatible Node exists on the machine** | Provision an isolated, workflow-owned Node runtime where installation is permitted (e.g., `fnm install` / `nvm install` into a local cache, or downloading a standalone Node archive into a temporary directory and prepending its bin directory to `PATH`). **Never replace or overwrite the machine's global Node installation.** |
| **The project pins Node in `.nvmrc`, Volta, `engines`, CI, or containers** | Treat changing those project files as a project-level requirement change requiring appropriate scope/approval — not merely a temporary tool switch. Only update them when upgrading the project's runtime target is in scope, and call out any updated pins in the upgrade summary. |
| **Node cannot be upgraded or provisioned** | Upgrade to the highest Angular major supported by the available Node runtime, then **report the requested/latest Angular target as blocked (`success: false` in `typescript_report_telemetry` with `failureReason` explaining the Node blocker)**. A compatible lower-version upgrade is partial completion, not full success at "latest". |

- **Per-hop Node switching:** For Angular 12 → 22, an example sequence using overlapping supported ranges is Node 14.20.x for 12 → 13, Node 16.14.x for 13 → 16, Node 18.19.1 or a newer 18.x release for 16 → 19, and Node 22.22.3 or a newer 22.x patch for 19 → 22. Recheck the CLI and build-tool requirements for each hop instead of treating this example as a substitute for their compatibility ranges.
- **Preserve the original pre-upgrade baseline:** Never call `resetBaseline` in `typescript_validate_runtime` after modifying `package.json` or lockfiles just to accommodate a newer Node runtime. Keep the original pre-upgrade baseline intact and account for the runtime transition during validation.

### Install compatibility (so `ng update`'s internal install doesn't fail)
- **Peer-dependency conflicts (npm 7+):** ensure `legacy-peer-deps=true` is set in the project-root `.npmrc` (append the line if `.npmrc` already exists; create it only if absent). **Never overwrite or delete existing `.npmrc` lines** (`registry=`, `_authToken`, `cafile`, `strict-ssl`, scoped `@org:registry` entries), as doing so breaks enterprise/private registry authentication.
- **`ngcc` / `decorate` postinstall scripts:** Angular 16+ removed `ngcc`. If `package.json` `scripts.postinstall` runs `ngcc` (or an Angular `decorate`/`ngcc` step), remove it before crossing into v16 — it errors once the binary is gone and blocks installs.
- **`node-sass`:** replace `node-sass` with `sass` (Dart Sass). `node-sass` fails to build its native binding on Node 18+/24.

### One clean install
Do a single clean install now (`npx -y rimraf node_modules`, then `typescript_install_dependencies`). After this, rely on `ng update`'s built-in install for each hop — do **not** wipe `node_modules` every hop.

## Step-by-Step Angular Upgrade Procedure

Angular major versions **must** be upgraded one at a time (e.g., 16 → 17 → 18 → 19 → 20 → 21 → 22). You cannot skip major versions.

**First, detect the workspace type.** If the repo root has an `nx.json`, follow the [Nx workspaces](#nx-workspaces-nxjson-present) section above for the upgrade command (`nx migrate` per major) instead of the `ng update` loop below — the rest of this procedure (pre-flight, validation, TypeScript 6) is unchanged.

**Package manager:** The commands below use `npx` to invoke the Angular CLI. If the scan returned a different `packageManager`, substitute accordingly:
- **yarn:** use `yarn dlx` instead of `npx`
- **pnpm:** use `pnpm dlx` instead of `npx`

### 1. Detect the current Angular major version

Use `fromMajor` from the `angular.md` entry in `applicableGuidance` when present; otherwise read `@angular/core` from `package.json` (dependencies or devDependencies) and extract the major version number.

### 2. Determine the target Angular major version

From the scan's `packages[].dependencyGroups`, collect the `targetVersions` entries for every Angular package into one exact-target map. If that map is non-empty, derive the terminal Angular major from its values; all explicitly targeted Angular packages must share that major, but they may have different patch versions. Otherwise use `toMajor` from the `angular.md` entry in `applicableGuidance` (or check the latest via `npm view @angular/core version`). Ensure you have selected or provisioned a compatible Node runtime for intermediate hops and the terminal major (see [Node version & per-hop runtime policy](#node-version--per-hop-runtime-policy)).

### 3. Loop: upgrade one major version at a time

For each major version `N` from `(current + 1)` to the target major (switching the active `PATH` Node runtime beforehand whenever hop `N` enters a new Node compatibility range):

**a.** Run `ng update` for the core Angular packages (this installs the new versions internally). Use bare major `@N` (without `^`) for intermediate hops. On the final hop, construct each package spec independently: use that package's exact `targetVersions` entry when present, otherwise use `@N`.

⚠️ **CRITICAL — Prevent `ng update` from bootstrapping `@angular/cli@latest` (v22) during intermediate hops:**
Two separate traps in `@angular/cli` can cause an intermediate hop (e.g. Angular 13) to download and execute `@angular/cli@22`:
1. **Never pass a caret (`@^N`) to `ng update` or `npx -p`:** `@angular/cli`'s internal `getCLIUpdateRunnerVersion` parses `pkg.split('@')[2]` with a digit-only regex (`/^\d/`). Passing `@angular/core@^13` yields `'^13'`, which fails to parse and falls back to `'latest'` (`@angular/cli@22`)! Always pass `@N` (e.g. `@angular/cli@13 @angular/core@13`) or an exact `X.Y.Z` version.
2. **Always set `NG_DISABLE_VERSION_CHECK=1`:** Without `NG_DISABLE_VERSION_CHECK=1`, `@angular/cli` either delegates to the workspace's older local `node_modules/@angular/cli` or invokes `checkCLIVersion` to bootstrap a temporary CLI from npm. Setting `NG_DISABLE_VERSION_CHECK=1` forces the exact `-p @angular/cli@N` binary to execute the hop directly.

For unattended runs, set `CI=true` and `NG_CLI_ANALYTICS=false` as well as `NG_DISABLE_VERSION_CHECK=1` so optional migration and analytics prompts do not stall the workflow. Keep the unattended environment on subsequent builds too. Do not add `--no-interactive` to `ng update`; Angular CLI versions can reject it as an unknown argument. Keep the CLI and package specs pinned to the hop major.

Run each hop with bare major `@N`:
- **PowerShell:**
  ```powershell
  $env:CI = "true"; $env:NG_CLI_ANALYTICS = "false"; $env:NG_DISABLE_VERSION_CHECK = "1"; npx -y -p @angular/cli@N ng update @angular/cli@N @angular/core@N --allow-dirty --force
  ```
- **Bash / sh:**
  ```bash
  CI=true NG_CLI_ANALYTICS=false NG_DISABLE_VERSION_CHECK=1 npx -y -p @angular/cli@N ng update @angular/cli@N @angular/core@N --allow-dirty --force
  ```

Final exact-target example (the CLI and Core patches are intentionally independent):
```powershell
$env:CI = "true"; $env:NG_CLI_ANALYTICS = "false"; $env:NG_DISABLE_VERSION_CHECK = "1"; npx -y -p @angular/cli@18.2.8 ng update @angular/cli@18.2.8 @angular/core@18.2.7 --allow-dirty --force
```

*Note for Angular libraries/wrappers without `@angular/cli` in `package.json`:* If `package.json` declares `@angular/core` but not `@angular/cli`, passing `@angular/cli@N` to `ng update` logs `Package '@angular/cli' is not a dependency`. In that case, keep `-p @angular/cli@N` on `npx` to supply the runner binary, and pass only the installed Angular packages (e.g., `npx -y -p @angular/cli@N ng update @angular/core@N --allow-dirty --force` with `CI=true`, `NG_CLI_ANALYTICS=false`, and `NG_DISABLE_VERSION_CHECK=1`).

After each hop, inspect both the manifest and installed build-tool versions in the active workspace. A Core migration can leave a library's `@angular/compiler-cli`, `@angular-devkit/build-angular`, or `ng-packagr` on the previous major. Align the declared tools to releases compatible with the hop's Angular and TypeScript versions, then call `typescript_install_dependencies` in that workspace before building. Verify the installed versions actually satisfy those declarations using `npm ls` from the workspace root (see step **d**); an install reporting success is not sufficient. Check third-party builders' published peer ranges instead of assuming their version numbers match Angular. Do not add a CLI dependency merely to obtain the temporary runner, and do not advance to the next major while the current workspace build is broken.

**b.** If the project uses `@angular/material`, also update it using the same pinned CLI major and `NG_DISABLE_VERSION_CHECK=1`. Use its explicit exact target on the final hop when provided; otherwise use `@N`:
```powershell
$env:CI = "true"; $env:NG_CLI_ANALYTICS = "false"; $env:NG_DISABLE_VERSION_CHECK = "1"; npx -y -p @angular/cli@N ng update @angular/material@N --allow-dirty --force
```
(Skip this if `@angular/material` is not in `package.json`.)

**c.** Build the affected application or library with its existing workspace script, including prerequisite workspace libraries and the production configurations identified in pre-flight. Keep the hop-compatible Node runtime selected on `PATH`, and set `CI=true NG_CLI_ANALYTICS=false` on the build itself. In an npm monorepo, explicitly select the affected member with `npm run build --workspace <workspace-name-or-path>` from the root, rather than accidentally invoking the unrelated root build. For a stock application without a wrapper script:
```bash
CI=true NG_CLI_ANALYTICS=false npx --no-install ng build
```
In PowerShell, set `$env:CI = "true"; $env:NG_CLI_ANALYTICS = "false"` before the same build command. Validate the entire existing lifecycle, including prebuild/postbuild; a successful `ng build` alone is insufficient when a packaging hook fails.

**d.** If the build reports missing modules, package-export errors, or a toolchain mismatch, inspect installed versions before repeating installs. From the **workspace root**, run `npm ls @angular/compiler-cli @angular-devkit/build-angular ng-packagr typescript --workspace <workspace-name-or-path>` for tools declared by the affected member (omit `--workspace` for a standalone project). Use the existing Yarn/pnpm equivalent for those projects; never switch package managers.

If an installed tool does not satisfy its manifest range, inspect the root lockfile and any intentional overrides. A stale workspace lockfile can retain the previous major even after `ng update` reports success. For npm, try a targeted reinstall from the **workspace root**, naming each mismatched package at its **declared range**, for example:
```text
npm install "@angular/compiler-cli@<declared-range>" "@angular-devkit/build-angular@<declared-range>" "ng-packagr@<declared-range>" --workspace <workspace-name-or-path> --ignore-scripts
```
Include only mismatched packages already declared by that member, preserve their dependency sections and ranges, and retain the scenario's existing peer-resolution policy; do not introduce a new peer bypass. For Yarn/pnpm, use the project's workspace-targeted install equivalent without changing package managers. Then call `typescript_install_dependencies` with `rootDirectory` and the affected `packageDirectory`, rerun the version inspection, and rebuild. **Deleting `node_modules` alone does not fix stale lockfile resolutions.** Do not repeatedly perform the same successful install while the same invalid versions remain, remove dependencies, or delete the entire lockfile as a first-line repair. If versions are correct but installed files are missing, a clean reinstall may instead be appropriate. Skip recovery when the build and installed toolchain are already healthy; keep the current-hop build gate.

**If the targeted npm install still retains the same invalid versions, repair the persisted resolutions instead of looping.** A successful install using `--package-lock=false` only repairs the current tree; a later install can restore the stale versions. Do not use that as the completed fix or leave a second member lockfile in a root-lockfile workspace.

For a **version 3 npm workspace lockfile**, use this scoped fallback after confirming the stale member-local entries and ruling out intentional overrides:

1. Preserve a backup of the root lockfile outside the repository and inspect its existing diff. Identify the exact `packages["<member>/node_modules/<package>"]` keys whose installed versions contradict that member's declarations. Do not change the manifest ranges to match stale versions.
2. Using a JSON-aware edit, remove **only those stale package entries and their nested `.../node_modules/...` lock subtrees** from the root lockfile. Remove only the corresponding installed external-package directories and generated `node_modules/.package-lock.json` metadata at the root/member if present. Do not delete source workspaces, linked workspace directories, unrelated entries, or the entire root lockfile; do not handcraft versions, URLs, or integrity hashes.
3. From the **workspace root**, run `npm install --package-lock-only --ignore-scripts` with the repository's existing peer-resolution policy so npm regenerates the removed resolutions in the tracked root lockfile. Then call `typescript_install_dependencies` for the affected member and inspect both `npm ls` and the resolved lock entries before rebuilding. Preserve unrelated resolutions and review the lockfile diff; if npm changes unrelated versions, investigate rather than accepting broad churn.

Use the repository's CI npm version and lock-affecting options throughout; do not switch package managers or introduce peer-conflict bypasses. If a command runs with `--prefix`, do not assume it inherits the root `.npmrc`: carry forward only the already-established policy explicitly. For other lockfile formats, use their package manager's supported repair instead of applying version-3-specific edits.

**e.** If the build fails, inspect the errors. Common issues after each hop:
- **`buildTarget` schema errors** — Check the installed builder's schema and migrate the serve target's `browserTarget`/`buildTarget` option as needed. Do not replace a custom build pipeline just to rename this option. See the "Common Issues" section below.
- **Peer dependency warnings** — Usually safe to ignore during intermediate hops since the next hop will align versions.

**f.** Verify the final manifest. Every Angular package with a `targetVersions` entry must equal its own exact requested target; untargeted Angular packages must land on the terminal major. Note that `ng update` writes `^` or `~` prefixes into `package.json` even when passed an exact `X.Y.Z` version — for any package in `targetVersions`, edit `package.json` to strip the leading `^` or `~` so the declared version string matches `targetVersions` verbatim.

### 4. After all Angular hops complete

**Prove the lockfile repair is persistent before declaring the Angular upgrade complete.** After the final exact-version pins and companion dependency edits, run the repository's clean locked install from the lockfile-owning root with the same npm version, configuration, and peer policy that CI uses (for npm, use the CI install command, typically `npm ci`; for Yarn/pnpm, the existing immutable/frozen install equivalent). Add `--ignore-scripts` only if CI also disables install scripts; otherwise include the install lifecycle scripts in this verification. Do this once at completion, not after every healthy hop. A clean install must succeed without rewriting the tracked lockfile, and the installed Angular tools must still satisfy the manifests. Then regenerate prerequisite workspace outputs using the existing scripts and rerun the affected production build with `CI=true NG_CLI_ANALYTICS=false`, including its packaging hooks. If later dependency edits change a manifest, synchronize the owning lockfile and repeat this check before reporting final success. Do not claim success from a previously working `node_modules` tree if the clean install fails, dependencies revert to an older hop, or the post-install build breaks. Repair the lockfile using the scoped recovery above and recheck; otherwise report the upgrade as incomplete.

1. ⛔ **Runtime validation — REQUIRED.** Invoke the shared `typescript-runtime-validation` skill in upgrade mode now, using the same plan-authoring, browser-recording, fallback, and retry/rollback flow as other webapps. Do not add Angular-specific runtime-validation requirements. Report any failed or partial outcome before returning to the main workflow.

2. **Return to the calling workflow** (SKILL.md) to continue with the remaining upgrade phases (TypeScript migration, non-Angular packages, etc.). When upgrading non-Angular dependency groups, **exclude** any groups that contain `@angular/*` or `@angular-devkit/*` packages — those are already upgraded.

## Validating an Angular build (`compile_package` / `write_upgrade_summary`)

For Angular projects the **authoritative compile signal is `ng build` / ng-packagr** (and the `validate_runtime` `app-builds` assertion) — not raw `tsc`. `typescript_compile_package` and the `write_upgrade_summary` rebuild type-check the tree with raw `tsc`, which is **not** representative of a multi-project or library Angular workspace and will surface false errors. Two things to do:

- **Before** calling `typescript_compile_package` or `typescript_write_upgrade_summary` on a multi-project/library workspace, normalize the base `tsconfig.json` so the raw-`tsc` pass doesn't choke on files outside the build graph: **exclude test files** (`**/*.spec.ts`, `cypress/**`, `e2e/**`) and ensure the base config lists the ambient `types` the project relies on (e.g. `"types": ["jasmine", "node"]`). Without this, raw `tsc` reports hundreds of false `Cannot find name 'describe'/'cy'` errors.
- **Treat as known false positives** (note them in the summary, do NOT chase or "fix" them) any residual raw-`tsc` errors that are confined to: spec/test files, Angular **library source** (decorator errors like `TS1206`/`TS1240`, which raw `tsc` cannot compile — only `ngc`/ng-packagr can), or `exports`-map resolution under a library's legacy `moduleResolution: node` (e.g. `Cannot find module '@angular/common/http'`). If `ng build` / ng-packagr is clean for the upgraded targets, the build is good regardless of these.

## Telemetry

After all Angular hops are complete (or if the upgrade fails at a particular hop), call `typescript_report_telemetry` with:
- `eventType`: `"group_upgrade"`
- `group`: `"angular"`
- `sessionId`: from the scan response
- `success`: whether the full requested/target Angular upgrade succeeded (`false` if the upgrade stopped at a lower compatible major, a required Node runtime could not be provisioned, or an upgrade-introduced build/test/runtime failure remains)
- `fromVersion`: the starting Angular major version (e.g., `"16"`)
- `toVersion`: the Angular major version actually reached (e.g., `"22"`, or `"16"` if blocked from reaching `"22"`)
- `strategy`: `"major-by-major"` (Angular upgrades one major at a time via `ng update`)
- `upgradeSteps`: the number of major version hops performed (e.g., `6` for 16→22)
- `failureReason`: (if `success` is `false`) a brief description of why the requested target could not be reached (e.g., `"node_runtime_blocked: stopped at Angular 16; Node 22.22.3+ could not be provisioned for Angular 22"`)

`typescript_report_telemetry` is **not** the terminal event. Return to `SKILL.md` which finishes with `typescript_write_upgrade_summary`. In the rare case you must stop early instead of returning, still call `typescript_write_upgrade_summary` once before exiting.

## Common Issues

### `buildTarget` schema errors
Inspect the installed serve builder's schema before changing `browserTarget` to `buildTarget`. This option rename does not require replacing the application's build builder. For stock Angular builders, use the CLI's supported application-builder migration when applicable; do not copy a fresh application's configuration over a customized workspace.

### Custom builders and production feature flags

Prefer a compatible release of an existing custom builder, such as `@angular-builders/custom-webpack`, over replacing it with `@angular/build:application` merely because the default builder is newer.

If a builder replacement is necessary, read `customWebpackConfig`, `DefinePlugin` inputs, HTML transforms, and scripts that generate build configuration before removing them. Preserve their behavior, including runtime-selected feature flags, worker support, asset paths, and deployment profiles. A TypeScript `declare` for a build-time constant does not define it in JavaScript: losing its replacement can compile successfully and then crash at bootstrap with `APP_FEATURE_EDITOR is not defined`.

When replacing plugin constants with Angular `define` options, preserve the original configuration inputs rather than hardcoding the values from one local build. Each effective named configuration must supply every referenced constant; do not assume partial `define` maps merge across options and configurations. Build the actual release/deployment scripts, not only `npm run build`, and use the shared runtime-validation workflow. Keep the old builder until equivalent behavior is implemented and verified, or report the migration as blocked.

### Strict version mismatches
Angular will refuse to build if `@angular/*` packages are misaligned. All `@angular/*` packages in a project must be the same major version.

For independently built applications such as microfrontends that share an Angular runtime, compiler-generated code may use a different patch version from the runtime only when both versions have the same minor version. Angular guarantees compiler ABI stability across patches of one minor, but not across minor versions.

### RxJS coupling
Angular versions are often tied to specific RxJS versions. The `ng update` schematics usually handle this, but if you see RxJS errors after an upgrade hop, check `package.json` for version mismatches and align RxJS to the version expected by that Angular major.

### Decorator metadata changes
Older Angular versions used different decorator compilation. If upgrading across many majors (e.g., 14 → 22), expect intermediate hops to handle these transitions.

### Stale or inconsistent `node_modules`
The hop loop relies on `ng update`'s internal install and does not wipe `node_modules` each hop. If a hop fails with module-resolution or native-binding errors that a plain reinstall doesn't fix, do a one-off clean reinstall as a recovery step: `npx -y rimraf node_modules`, then `typescript_install_dependencies`. Use this only when needed — not on every hop.

### Module system changes
Angular has moved toward standalone components (replacing NgModules). The `ng update` schematics may offer to migrate your code. Accept the migrations when prompted.

### Legacy View Engine libraries (`NG6002` on Angular 16+)
Angular 16 removed the Angular Compatibility Compiler (`ngcc`). Third-party libraries published only in legacy View Engine format fail on Angular 16+ with `NG6002: Appears in the NgModule.imports of ..., but itself has errors`. If a hop into Angular 16+ hits `NG6002`:
- Upgrade that third-party library to an Ivy-compatible release, or replace known abandoned View Engine packages with their maintained Ivy forks (e.g., replace `ng5-slider` with `@angular-slider/ngx-slider`, or replace `ngx-useful-swiper` with `swiper`).
- If an internal/private library has no Ivy build available and blocks compilation at v16+, stop at Angular 15 (the final `ngcc`-supported major) and document the blocker in the upgrade summary.
