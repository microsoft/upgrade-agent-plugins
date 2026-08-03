# i18next Upgrades

i18next ships as a cluster that must move together:

- **Core:** `i18next` — the framework-agnostic engine.
- **React binding:** `react-i18next` — hooks (`useTranslation`), the `Trans` component, `initReactI18next`.
- **Plugins:** `i18next-*` (e.g. `i18next-http-backend`, `i18next-fs-backend`, `i18next-browser-languagedetector`, `i18next-icu`, `i18next-resources-to-backend`) and any `@i18next/*` package.

Bump them to the **same i18next generation together**; the biggest cause of failed i18next upgrades is a peer/type mismatch left behind when one member trails.

## Scope: coupling rules

- **`react-i18next`'s i18next peer floor tracks its own major.** Each react-i18next major raises its minimum `i18next` peer — e.g. `react-i18next@17` requires `i18next >= 26.0.1`, and `react-i18next@13` was the release that adopted i18next v23's redesigned types (requires `i18next >= 23.0.1`). Upgrade `i18next` and `react-i18next` **in the same group**; leaving `i18next` behind produces an `ERESOLVE` peer error at install, and leaving it ahead produces missing-type-export errors (`react-i18next` imports internal type helpers from `i18next`).
- **i18next v23+ requires TypeScript ≥ 5.0 — treat the compiler floor as a required prerequisite, not optional config.** i18next v23 redesigned its types for TypeScript 5 and v24 dropped TypeScript 4 entirely (for TS 4 the last compatible core is `i18next@22.5.1`). Compare the project's current `typescript` (from the scan) to this floor: already on TS 5+ needs no change; a small gap (e.g. TS 4.9) is a minimal upgrade-induced bump to 5.0; a **multi-major gap** (TS 3.x / 4.0–4.8) is a de-facto compiler migration — upgrade TypeScript first via [compiler-upgrade.md](../typescript-compiler-upgrade/compiler-upgrade.md), **capped at the TypeScript 5.x line** (the i18next floor — stop before 6.0; the latest 5.x is fine, just don't drag an i18next-scoped request to 6/7). This TypeScript upgrade is in scope even when the request is scoped to i18next, because i18next v23+ cannot install or compile without it — exactly like a required peer.
- **Plugins track the core.** `i18next-*` plugins are peers of `i18next` and expose plugin interfaces that change with the core major (e.g. `i18next-http-backend` v4 tracks i18next v24+). Move them with the core; don't pin a plugin at a major built against an older i18next.
- **The TypeScript augmentation file is part of the upgrade.** If the project has an `i18next.d.ts` (or `@types/i18next.d.ts`) augmenting `CustomTypeOptions`, it uses i18next's type surface and must be updated in lockstep — several of the redesigned type names changed (see the audit table). Treat it as source that the upgrade touches, not config to leave alone.
- These rules **constrain** the standard `typescript_upgrade_package_dependency_group` flow — they do not replace it. Pass the whole scanned i18next group into Phase 2; don't strip it down to just `i18next`.

## Strategy: single-shot bump, cumulative per-major changes

The tool resolves each package to its **latest** version (currently `i18next` v26, `react-i18next` v17). Go directly to that target in one version bump, then apply the changes for **every major you cross**, in ascending order and cumulatively. Reading and upgrading are separate steps: understand every major's breaking changes first, bump once, then work through each major's fixes.

Major-by-major breaking changes (i18next core, from the official migration guide):

- **v22 → v23 — TypeScript type redesign.** Types were rewritten for speed. Requires `strict` (or `strictNullChecks`) in `tsconfig` and **TypeScript 5**. Several exported types were renamed/removed: `TFuncKey` → `ParseKeys`, `StringMap` → `$Dictionary` (no longer exported), `KeysWithSeparator` → `JoinKeys`, `DefaultTFuncReturn`/`DefaultTFuncReturnWithObject` → `DefaultTReturn`, and `NormalizeByTypeOptions` / `NormalizeReturn` removed. `returnNull` now defaults to **`false`**. Official codemods (run via `npx codemod`): `i18next/23/add-namespace-type-annotation`, `i18next/23/replace-keys`, `i18next/23/remove-options`. `setDebug` was removed.
- **v23 → v24 — runtime/env breaking.** The old i18next **JSON v3 format** was removed — convert resources to **v4** (see Blockers). The `Intl` API is now **mandatory** (no fallback) — add a polyfill on old runtimes. `initImmediate` was **renamed to `initAsync`**. The `jsonFormat` option was removed (`compatibilityJSON` now only accepts `v4`). Only TypeScript > 5 is supported; Node < 14 dropped.
- **v24 → v25 — language resolution.** `changeLanguage` call ordering was fixed and `getBestMatchFromCodes` now falls back to a language code with the same script. This can change which language resolves for a given input — verify fallback behavior after upgrading.
- **v25 → v26 — legacy format removal.** The monolithic `interpolation.format` function is **removed**; use the Formatter API (`i18next.services.formatter.add()` / `.addCached()`) or a custom Formatter module. `initImmediate` (removed) and `showSupportNotice` (removed). `enableSelector` defaults to `true`.

`react-i18next` moves with the core; its notable recent change is **v17.0.0**, where `transKeepBasicHtmlNodesFor` serialization was corrected — if you rely on **auto-generated** `Trans` keys (no explicit `i18nKey`) that contain indexed tags for kept HTML elements with interpolation children, those extracted translation strings change and the translation files need updating.

## Order of operations

Clear the TypeScript floor and remove stale stub types first, then bump versions and reinstall **before** touching source, then apply codemods and manual fixes.

1. **Clear the TypeScript floor.** i18next v23+ requires TypeScript ≥ 5.0 (see coupling rules). If the project's `typescript` is below it, upgrade TypeScript first — a small gap (e.g. 4.9) via a minimal bump to 5.0, a multi-major gap (e.g. TS 3.x / 4.0–4.8) via [compiler-upgrade.md](../typescript-compiler-upgrade/compiler-upgrade.md)'s structured per-major handling **capped at the TypeScript 5.x line** (stop before 6.0 — the latest 5.x is fine; don't continue to 6/7 for an i18next-scoped request). Do this before bumping i18next.
2. **Remove deprecated stub types.** If `@types/i18next` or `@types/react-i18next` appear in `package.json`, delete them — i18next (≥ v15) and react-i18next (≥ v11.4) bundle their own types, and the DefinitelyTyped stubs shadow them and cause stale/duplicate-type errors.
3. **Bump the whole cluster together** to the target via `typescript_upgrade_package_dependency_group` — `i18next`, `react-i18next`, and every `i18next-*` plugin in one group.
4. **Reinstall** with `typescript_install_dependencies`. An `ERESOLVE`/peer conflict here is almost always a member (a plugin, or `i18next` itself) left at an incompatible major — align it and reinstall (see "React as a peer dependency" and the group rules in [peer-dependencies.md](./peer-dependencies.md)). Separately, the reinstall can re-resolve **unrelated transitive `@types/*`** — e.g. hoist or duplicate a newer `@types/react` (v18) that a React-17 app can't compile against. If new errors after reinstall trace to a duplicated/newer `@types/react`, pin `@types/react` and `@types/react-dom` to the app's **existing** major via `resolutions` (yarn) / `overrides` (npm, pnpm); do **not** upgrade React types as part of an i18next upgrade.
5. **Run the official i18next codemods for each major crossed where one exists.** Prefix `npx` with `--yes` so the install prompt doesn't stall the run. These rewrite source only — they are **explicitly permitted** despite Key Principle #9 (they transform source, they do not install dependencies or repair the toolchain). If a codemod binary genuinely cannot run (offline/blocked registry), don't fabricate having run it — apply the per-major fixes manually.
   - v23 type renames: `npx --yes codemod i18next/23/replace-keys <path>`, `npx --yes codemod i18next/23/add-namespace-type-annotation <path>`, `npx --yes codemod i18next/23/remove-options <path>`.
   - (Optional) v25.4 selector API opt-in: `@i18next-selector/codemod` — only if adopting `enableSelector`.
6. **Update the TypeScript augmentation** (`i18next.d.ts`) and apply the manual fixes the codemods don't cover (audit table + "Manual-only changes" below).
7. **Compile and verify.** Call `typescript_compile_package` and resolve remaining errors with the standard verify loop.

## Pre-upgrade audit

Before changing version pins, search the package directory (`grep`/`rg`) for patterns that will need attention. These are inputs to the plan, not yet fixed.

| Pattern to find | What to do |
| --- | --- |
| `TFuncKey`, `StringMap`, `KeysWithSeparator`, `DefaultTFuncReturn`, `NormalizeByTypeOptions`, `NormalizeReturn` | Renamed/removed types in v23 (`ParseKeys`, `$Dictionary`, `JoinKeys`, `DefaultTReturn`). Fix with the `i18next/23/*` codemods. |
| `i18next.d.ts`, `@types/i18next.d.ts`, `CustomTypeOptions` | The type augmentation — update to the v23+ type surface and confirm `resources`/`defaultNS` still match the translation files (see TypeScript section). |
| `@types/i18next`, `@types/react-i18next` as dependencies in `package.json` | Deprecated DefinitelyTyped stubs — i18next (≥ v15) and react-i18next (≥ v11.4) bundle their own types. Remove these packages; leaving them installed shadows the real bundled types and causes stale/duplicate-type errors. |
| no augmentation file but `useTranslation` / `t(` used with typed keys | The redesigned types are the main source of new TS errors after this upgrade — add an `i18next.d.ts` (TypeScript section) so keys/returns type-check. |
| `initImmediate` | Renamed to `initAsync` in v24, removed in v26. Replace. |
| `interpolation: { format:` | The legacy format function is removed in v26 → migrate to `i18n.services.formatter.add('name', ...)`. |
| `compatibilityJSON: 'v3'`, `jsonFormat`, plural keys like `key_plural` / `key_0` / `key_1` | i18next JSON v3 format — removed in v24. Convert resources to v4 (see Blockers). |
| `returnNull` | Default flipped to `false` in v23. If code relies on `t()` returning `null` for missing keys, set `returnNull: true` explicitly (and in `CustomTypeOptions`). |
| `showSupportNotice` | Removed in v26 — delete from init options. |
| `changeLanguage(` | v25 changed language resolution/`getBestMatchFromCodes`. Verify the resolved language/fallback is still correct. |
| `Trans` with no `i18nKey` (auto-generated keys) | react-i18next v17 changed `transKeepBasicHtmlNodesFor` serialization for kept HTML with interpolation children — re-check/re-extract affected translation strings. |

## TypeScript type augmentation

i18next's redesigned types (v23+) are the dominant reason this cluster introduces many new TS errors. Get the augmentation right rather than suppressing it:

- Ensure `tsconfig` `compilerOptions` has `strict` **or** `strictNullChecks: true`, and TypeScript 5 (i18next > v23 drops TS4 — for TS4 the last compatible core is `i18next@22.5.1`).
- Provide a declaration file (recommended `src/@types/i18next.d.ts`) that augments `CustomTypeOptions` with `defaultNS` and `resources`, per the [official TypeScript guide](https://www.i18next.com/overview/typescript):

  ```typescript
  import { resources, defaultNS } from "./i18n";
  declare module "i18next" {
    interface CustomTypeOptions {
      defaultNS: typeof defaultNS;
      resources: (typeof resources)["en"];
    }
  }
  ```

- If the project set `returnObjects: true` or `returnNull` behavior, mirror those in `CustomTypeOptions` so the `t` return type matches runtime.
- `react-i18next` reuses the same augmentation — no separate `react-i18next.d.ts` is required for key typing once `CustomTypeOptions` is set (react-i18next >= 13 + i18next >= 23).

## Manual-only changes (no codemod)

- **`interpolation.format` → Formatter API (v26).** Move each `format` branch to `i18next.services.formatter.add('name', (value, lng, options) => ...)` and reference it as `{{value, name}}` in translations.
- **`initImmediate` → `initAsync` (v24).**
- **Language-resolution check (v25).** Re-verify `changeLanguage`/detector fallback picks the intended language after the `getBestMatchFromCodes` behavior change.

## Blockers

- **JSON v3 → v4 translation-format migration.** If the project uses `compatibilityJSON: 'v3'` or v3 plural suffixes (`_plural`, `_0`, `_1`, …), the **translation resource files** (not code) must be converted to the v4 ICU-style suffixes (`_one`, `_other`, …). Use the [i18next-v4-format-converter](https://github.com/i18next/i18next-v4-format-converter) tool. This is a data migration that can be substantial and is easy to get subtly wrong — treat it as its own tracked work item and report it; don't hand-edit plural keys blindly.
- **`Intl` polyfill (v24+).** i18next no longer falls back when `Intl` is missing. On old runtimes/browsers add polyfills for `Intl.PluralRules` and `Intl.getCanonicalLocales` before init.
- **`next-i18next` present.** `next-i18next` bundles compatible `i18next`/`react-i18next` ranges. Bump `next-i18next` to its own matching major **together** with the cluster; do not advance `i18next`/`react-i18next` past what the installed `next-i18next` supports, or SSR translation loading breaks. If no compatible `next-i18next` exists yet, treat the i18next bump as blocked and report it.

## Validation

- The standard Phase 3 `typescript_compile_package` call still applies — do not skip it.
- If `validateRuntime` is true, call `typescript_validate_runtime` — REQUIRED. i18next failures (missing translations after a v3→v4 format mismatch, wrong resolved language after the v25 change, a broken Formatter migration) often surface only at runtime, not at compile time. Follow the Phase 3 rules in [SKILL.md](./SKILL.md) and [runtime-validation.md](./runtime-validation.md).

## Telemetry

After the i18next upgrade attempt (success or failure), call `typescript_report_telemetry` once with:

- `eventType`: `"group_upgrade"`
- `group`: `"i18next"`
- `sessionId`: from the scan response
- `success`: whether the upgrade landed (compile + install both passed)
- `fromVersion`: starting `i18next` major as a string (e.g. `"22"`)
- `toVersion`: target `i18next` major as a string (e.g. `"26"`)
- `strategy`: `"single-shot"`
- `codemodsRun`: count of codemod recipes run (the `i18next/23/*` transforms); `0` if none could run (manual fixes only)
- `failureReason`: if failed, e.g. `"json_v4_migration_blocker"`, `"peer_dep_unresolved"`, `"next_i18next_incompatible"`, `"compile_errors_remaining"`

This is **not** the terminal event. Return to the calling workflow, which finishes with `typescript_write_upgrade_summary`.
