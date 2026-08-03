# MUI + Emotion Upgrades

MUI ships as a cluster that must move together:

- **Core:** `@mui/material`, `@mui/icons-material`
- **X packages:** `@mui/x-date-pickers` (and `-pro` / `@mui/x-data-grid*`, `@mui/x-tree-view*`, `@mui/x-charts*` if present)
- **Styling engine:** `@emotion/react`, `@emotion/styled` — MUI's default peer styling engine

Bump them to the **same MUI major together**; never advance `@mui/material` while leaving `@mui/icons-material` or the X packages behind.

## Scope: coupling rules

- **Emotion is a required peer of `@mui/material`.** `@mui/material` declares `@emotion/react` (`^11.5.0`) and `@emotion/styled` (`^11.3.0`) as (optional) peer dependencies — optional only because `@mui/styled-engine-sc` can substitute styled-components, but Emotion is the default. If the project uses Emotion, upgrade `@emotion/react` / `@emotion/styled` **in the same group** as `@mui/material`. Emotion's own major (v10 → v11) is a breaking change and must land **before or with** MUI v5 (MUI v5 requires Emotion v11).
- **`@mui/x-*` tracks the `@mui/material` major.** `@mui/x-date-pickers` v9 accepts `@mui/material` `^7.3.0 || ^9.0.0` — it may trail `@mui/material` by one major but must not lead it. Move the X packages with the core; do not bump `@mui/material` to v9 while pinning an X package at a major that only supports v5/v6.
- These rules **constrain** the standard `typescript_upgrade_package_dependency_group` flow — they do not replace it. Pass the whole scanned MUI/Emotion group into Phase 2; don't strip it down to just `@mui/material`.

## Strategy: single-shot bump, cumulative codemods

The upgrade tool resolves each package to its **latest** version (currently `@mui/material` **v9** — note MUI skipped v8, going v7 → v9). Go directly to that target in one version bump, then run the official codemods for **every major you cross**, in ascending order and cumulatively — the same read-all-majors / upgrade-once model as React. Reading and upgrading are separate steps: understand every major's breaking changes first, bump once, then apply each major's codemods in turn.

## Order of operations

Bump versions and reinstall **before** touching source, then run codemods and manual fixes.

1. **Bump the whole cluster together** to the target major via `typescript_upgrade_package_dependency_group` — core, icons, X packages, and Emotion in one group.
2. **Reinstall** with `typescript_install_dependencies`. If install reports a peer conflict, it is almost always an X package or Emotion left at an incompatible major — align it and reinstall (see "Peer-dep resolution" in [peer-dependencies.md](./peer-dependencies.md)).
3. **Run the official MUI codemods for each major crossed — REQUIRED.** Prefix `npx` with `--yes` (or use `yarn dlx` / `pnpm dlx`) so the npx install prompt doesn't stall the run. These codemods rewrite source only — they are **explicitly permitted** despite Key Principle #9 (they transform source, they do not install dependencies or repair the toolchain). If a codemod binary genuinely cannot run (offline/blocked registry), don't fabricate having run it — apply the per-major fixes manually instead.

   **Material UI core (`@mui/codemod`):**
   - `@material-ui/*` → `@mui/*` rebrand (only if coming from v4): `npx --yes @mui/codemod@latest v5.0.0/preset-safe <path>`
   - v5 → v6: `npx --yes @mui/codemod@latest v6.0.0/grid-v2-props <path>`, then `list-item-button-prop`, `sx-prop`, `system-props`, `theme-v6`, and `styled` as needed (there is **no** `v6.0.0/preset-safe`; run the individual transforms).
   - v6 → v7: `npx --yes @mui/codemod@latest v7.0.0/grid-props <path>`, then `input-label-size-normal-medium` and `lab-removed-components` (again, **no** `v7.0.0/preset-safe`).
   - v7 → v9: `npx --yes @mui/codemod@latest deprecations/all <path>` — every API deprecated in v6/v7 is removed in v9.

   **MUI X (`@mui/x-codemod` — note the different package name):**
   - Pickers/Data Grid v6 → v7: `npx --yes @mui/x-codemod@latest v7.0.0/preset-safe <path>`
   - v7 → v8: `npx --yes @mui/x-codemod@latest v8.0.0/preset-safe <path>` (handles the `AdapterDateFns` path renames below)

   **Emotion:** Emotion ships **no** codemod. The v10 → v11 package renames are mechanical import swaps — the regex KB fixes them on files that still error, and they are listed in the audit table below.
4. **Apply manual fixes** the codemods don't cover (audit table + "Manual-only changes" below).
5. **Compile and verify.** Call `typescript_compile_package` and resolve remaining errors with the standard verify loop.

## Pre-upgrade audit

Before changing version pins, search the package directory (`grep`/`rg`) for patterns that will need attention. These are inputs to the plan, not yet fixed. Most are handled automatically by a codemod or the mechanical rename pass, as noted.

| Pattern to find | What to do |
| --- | --- |
| `@material-ui/core`, `@material-ui/icons`, `@material-ui/*` | v4 package names. Rebrand to `@mui/material` / `@mui/icons-material` / `@mui/*` (codemod `v5.0.0/preset-safe`). |
| `createMuiTheme` | Renamed to `createTheme` in v5, **removed in v7**. Renamed automatically on files that error. |
| `experimentalStyled` | Removed in v7 → `styled` from `@mui/material/styles`. Renamed automatically. |
| `@emotion/core` | Renamed to `@emotion/react` in Emotion v11. Import renamed automatically. |
| `emotion-theming` | Merged into `@emotion/react` in v11 (`ThemeProvider`, `useTheme`, `withTheme`). Import renamed automatically. |
| `Unstable_Grid2`, `<Grid item`, `<Grid xs=` | Grid was refactored across v6/v7 (`Grid2` → `Grid`, breakpoint props → `size`/`offset`, old Grid → `GridLegacy`). Use the Grid codemods — **do not** hand-write regex for Grid (the same name means different things at different majors). |
| `@mui/lab/Alert`, `@mui/lab/Autocomplete`, … | Several components moved from `@mui/lab` to `@mui/material` in v7 (codemod `v7.0.0/lab-removed-components`). Only the moved components change; `@mui/lab` still exists for others. |
| `import ... from '@mui/styles'`, `makeStyles`, `withStyles` | Legacy JSS styling — deprecated since v5. See "Blockers" below. |
| `onBackdropClick`, `<Hidden` | Removed in v7 — **manual** refactor (no codemod). See "Manual-only changes". |
| `AdapterDateFns` / `AdapterDateFnsV3` from `@mui/x-date-pickers` | Adapter import paths were renamed in x-date-pickers v8 (`AdapterDateFns` now = date-fns v3; date-fns v2 → `AdapterDateFnsV2`). Handled by `@mui/x-codemod v8.0.0/preset-safe`. |

## Manual-only changes (no codemod)

These are context-dependent refactors — surface them in the plan and fix by hand:

- **`onBackdropClick` (Dialog/Modal), removed in v7** → use `onClose` with a reason check: `onClose={(event, reason) => { if (reason === 'backdropClick') handleClose(); }}`.
- **`Hidden` component, removed in v7** → replace with the `sx` prop (`sx={{ display: { xs: 'block', md: 'none' } }}`) or `useMediaQuery`.
- **Deep imports past one path level, broken in v7** (Node `exports` enforced) → e.g. `@mui/material/styles/createTheme` → `import { createTheme } from '@mui/material/styles'`.

## Blockers

- **`@mui/styles` (JSS).** This is MUI's legacy JSS styling solution, deprecated since v5 and not recommended. Migrating off it (to the Emotion-based `styled` API, or `tss-react/mui` as a `makeStyles` drop-in) can be a substantial, manual effort that is separate from the version bump. If the project depends heavily on `@mui/styles`, treat that migration as its own tracked work item and report it — don't silently leave broken JSS styling. Do not assert the package was removed; confirm against its npm page if the target major matters.
- **styled-components as the engine.** If the project uses `@mui/styled-engine-sc` instead of Emotion, keep it on styled-components — don't swap the engine to Emotion as part of a version bump.

## Validation

- The standard Phase 3 `typescript_compile_package` call still applies — do not skip it.
- If `validateRuntime` is true, call `typescript_validate_runtime` — REQUIRED. MUI is a UI library: theme/styling regressions, removed props, and Grid layout changes often surface only at runtime, not at compile time. Follow the Phase 3 rules in [SKILL.md](./SKILL.md) and [runtime-validation.md](./runtime-validation.md).

## Telemetry

After the MUI + Emotion upgrade attempt (success or failure), call `typescript_report_telemetry` once with:

- `eventType`: `"group_upgrade"`
- `group`: `"mui"`
- `sessionId`: from the scan response
- `success`: whether the upgrade landed (compile + install both passed)
- `fromVersion`: starting `@mui/material` major as a string (e.g. `"5"`)
- `toVersion`: target `@mui/material` major as a string (e.g. `"9"`)
- `strategy`: `"single-shot"`
- `codemodsRun`: count of codemod recipes run (`@mui/codemod` + `@mui/x-codemod`); `0` if none could run (manual fixes only)
- `failureReason`: if failed, e.g. `"mui_styles_blocker"`, `"peer_dep_unresolved"`, `"compile_errors_remaining"`

This is **not** the terminal event. Return to the calling workflow, which finishes with `typescript_write_upgrade_summary`.
