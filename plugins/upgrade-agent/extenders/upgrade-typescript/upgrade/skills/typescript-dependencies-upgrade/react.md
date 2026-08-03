# React Upgrades

The four React **core** packages — `react`, `react-dom`, `@types/react`, `@types/react-dom` — must move together to the **same** React major; never bump one without the others. That same-major rule applies to those four only.

These rules constrain how the React group is processed within the standard `typescript_upgrade_package_dependency_group` flow — they do **not** replace it. When you make that call:

- **Pass the whole group as it enters Phase 2.** For an all-packages request that's the entire scan group; for a scoped request it's the requested packages plus the peers confirmed in Phase 0 (with the React core four always included, per [peer-dependencies.md](./peer-dependencies.md)).
- **Do not strip the call down to just the core four.** The scan grouped these packages because they are peer-coupled and meant to upgrade together; dropping the rest is what creates the install/peer conflicts this skill exists to avoid.
- **Upgrade "react"-named members to their own latest version, not React's.** Group members that merely have "react" in their name (`react-icons`, `html-react-parser`, `react-helmet`, etc.) are still upgraded — but to **their own** latest compatible version, NOT forced onto React's major number (there is no `react-icons@19` that tracks React 19).
- **Revert, don't pre-exclude, a broken non-core member.** If upgrading one of those non-core members introduces breakage you can't resolve, fall back to reverting just that package per [upgrade-packages.md](./upgrade-packages.md) — don't pre-emptively exclude it from the group.

`applicableGuidance` — the ordered list of guidance entries returned in the `typescript_scan_dependencies` response (defined in SKILL.md and generate-plan.md) — includes a `react/<major>.md` entry for each React major the upgrade crosses. **Reading every per-major file it lists is REQUIRED — do not skip them and do not treat them as optional reference.** Read them in full and apply them cumulatively: each documents the breaking changes introduced in that major, and a single-shot jump (e.g. 17 → 19) must still handle every major it passes through. The Pre-upgrade audit table below is a *detection* checklist only — it tells you what to grep for, not how to fix it, and it is **not** a substitute for the per-major files, which carry the fix details, TS-specific failure modes, and ecosystem peer requirements the table omits. Do NOT rationalize skipping them ("react.md already summarized the highlights", "the per-major file is probably just a longer version of the table", "I'll consult it only if I get stuck"). Read only the files the scan listed — don't read per-major files it didn't list.

## Scope: web React only

This guidance targets **web React** (`react` + `react-dom`). React Native versions independently of web React and upgrades through its own tooling (`react-native upgrade` / the RN Upgrade Helper), which is outside this tool's scope. If the project is React Native — `react-native` in `package.json`, or source that imports from `'react-native'` — treat the React upgrade as a blocker (reason: "react-native / out of scope") and follow "Handling a React blocker" below: a React-only request stops and reports; an all-packages request leaves React untouched and continues with the other dependency groups.

## Strategy: single-shot upgrade

Go directly from the current major to the target major in one pass. Do NOT hop major-by-major (e.g. 17 → 18 → 19) unless the user explicitly asks — going straight to the target avoids leaving the project in an inconsistent intermediate state, and the per-major guidance already covers every major you cross. Reading and upgrading are separate steps: you still read **every** per-major file the scan listed (per the REQUIRED rule above) and apply them cumulatively — read all the majors you cross, then upgrade once.

## Pre-upgrade audit

Before changing version pins, search the package directory for patterns that will need attention (`grep`/`rg`). Report what you find — these are inputs to the migration plan, not yet fixed.

| Pattern to find | What to do |
| --- | --- |
| `ReactDOM.render(` | Needs `createRoot` migration (codemod handles most cases). |
| `ReactDOM.hydrate(` | Needs `hydrateRoot` migration. |
| `ReactDOM.findDOMNode(` | Removed in 19. No automated migration — refactor to use refs. |
| `unmountComponentAtNode(` | Replace with `root.unmount()`. |
| `ref="..."` or `this.refs.` | String refs deprecated/removed; migrate to callback or `useRef`/`createRef`. |
| `__SECRET_INTERNALS_` | Internal API access; breaks across upgrades. Refactor to public API. |
| `childContextTypes` / `contextTypes` | Legacy context; migrate to `React.createContext`. |
| `react-test-renderer/shallow` | Removed in 19; switch to `react-shallow-renderer` or migrate the test. |
| `react-scripts` / `react-scripts-ts` in `package.json` | CRA blocker — see below. |

## CRA blocker

If `react-scripts` (or its abandoned TypeScript fork `react-scripts-ts`) is in `package.json`, the project uses Create React App, which never gained React 19 support. Migrating its build tooling to Vite, Next, Remix, or another modern bundler is outside this tool's scope. Treat this as a React blocker (reason: "CRA / react-scripts") and follow "Handling a React blocker" below.

## Handling a React blocker

When React cannot be upgraded — CRA, or a peer dependency with no compatible version — what you do depends on scope:

- **The user asked only to upgrade React** → report the blocker and its reason via `typescript_write_upgrade_summary`, then stop. Nothing else is in scope.
- **The user asked to upgrade all packages** → do NOT halt the workflow. Revert any React-related `package.json` edits and reinstall to restore the baseline lockfile, then continue with the remaining dependency groups. Record React as blocked in the Phase 4 summary.

Never downgrade React or pin it below the target to work around a blocker.

## Order of operations

Bump versions and reinstall **before** touching source, then run codemods and manual fixes. Editing source before the versions resolve tends to regress.

1. **Bump versions together.** Update `react`, `react-dom`, `@types/react`, and `@types/react-dom` to the target React major as one group via `typescript_upgrade_package_dependency_group`.
2. **Match the types version to a real published version.** Do NOT assume `@types/react@<reactVersion>` exists — the `@types/react*` packages don't track React's version exactly. Query `npm view @types/react version` and `npm view @types/react-dom version` and pin to those. If the project's own source references React types but `@types/react`/`@types/react-dom` are not in `package.json` (resolved only transitively), add them explicitly at the matching major — as `devDependencies` for the project's own build, and additionally under `peerDependencies` if it's a library that exposes React types in its public API — so the type version is controlled rather than floating. Don't add `@types/*` packages the project doesn't actually compile against.
3. **Reinstall to update the lockfile.** Call `typescript_install_dependencies`. If install reports `Could not resolve dependency` or `Conflicting peer dependency`, follow "Peer-dep resolution" below.
4. **Run the React codemod recipe — REQUIRED.** Run `npx --yes codemod@latest react/<major>/migration-recipe --no-interactive --allow-dirty` (use the target major; add `-t <packageDirectory>` to scope it). All three flags are mandatory: `npx --yes` auto-confirms npx's package-install prompt (which `--no-interactive` does not suppress) so the run doesn't stall on stdin, `--no-interactive` stops it prompting and stalling, and `--allow-dirty` is required because the working tree is **always** dirty at this point (you just bumped versions and reinstalled) — without it the codemod refuses to run and the step silently never happens. Substitute `yarn dlx` / `pnpm dlx` for `npx --yes` per the project's package manager. This recipe is **explicitly permitted** despite Key Principle #9: it rewrites source files, it does not install dependencies or repair the package-manager toolchain. It covers `ReactDOM.render` → `createRoot`, string-ref migration, the `act` import update, `useFormState` → `useActionState`, and `prop-types` → TS prop types. It does **not** rewrite React's TypeScript types — that's the next step. If the codemod binary genuinely cannot run (offline/blocked registry), don't fabricate having run it — record `codemodsRun: 0` and apply the per-major fixes manually instead.
5. **Run the TypeScript codemod (TypeScript projects) — REQUIRED.** The migration recipe above does not touch TS types. Run `npx --yes types-react-codemod@latest preset-19 ./<packageDirectory> --no-interactive --allow-dirty` (use the matching preset for the target major; substitute the `dlx` form per package manager). For codebases with heavy `element.props` access, also run its `react-element-default-any-props` transform. This clears the bulk of the `ReactElement`-default-`unknown`, `JSX` → `React.JSX`, and `useRef`-requires-argument breakages enumerated in `react/19.md`. Same carve-out as step 4 — it transforms source, it doesn't install anything. Codemods can leave stylistic output (extra semicolons, quote style) that a strict eslint or a `prepare`/`postinstall` hook rejects — if the project has such a hook, run its `lint --fix` (e.g. `yarn lint --fix`) after the codemods so the next install doesn't fail.
6. **Apply manual fixes from per-major guidance.** Work through each `react/<major>.md` the scan listed and address what the codemods don't cover.
7. **Compile and verify.** Call `typescript_compile_package` and resolve remaining errors with the standard verify loop. Re-read the per-major guidance when an error category matches one of its sections.

## Stale TypeScript can flood node_modules with phantom errors

`@types/react@19` ships `.d.ts` files written with modern TypeScript syntax (inline `import { type X }`, `abstract new (...)`, `const` type params). If the project's `typescript` compiler is too old to parse them, a **React-only** bump can surface thousands of errors *inside* `node_modules/@types/react` (`TS1005`, `TS1183`, `TS2304`, …) even though your own source is fine. This is the classic symptom of a React bump outrunning the compiler — don't mistake it for a broken upgrade.

This does **not** mean you should run the full TypeScript migration (that stays out of scope on a React-only request). Treat it as a compile error *caused by the requested upgrade* and apply the minimal fix:

- Bump `typescript` (and `@types/node` if needed) just enough to parse the new type definitions — the smallest version that clears the `node_modules` parse errors, not the latest.
- If raising the compiler isn't viable, set `"skipLibCheck": true` in `tsconfig.json` so the new `.d.ts` files aren't type-checked. This is a minimal, scoped tsconfig tweak — not a TS migration. In projects that build at multiple targets via project references (e.g. a `tsconfig.node.json` that only compiles `vite.config.ts`, or a separate browser/server config), the config that blows up is often a *referenced* tsconfig that doesn't `extend` the root and so never inherited `skipLibCheck`/`lib` — apply the fix to that specific referenced config, not just the root one.

Do not edit files under `node_modules`, and do not downgrade `@types/react` to dodge this.

## Libraries that declare React as a peer dependency

If `react`/`react-dom` appear only under `peerDependencies` — typical for libraries that render React but don't own the version — the upgrade tools won't "bump" anything, because a peer range isn't a pinned dependency. To support the new major, **widen the peer range** instead of pinning: e.g. `"react": "^17.0.0 || ^18.0.0 || ^19.0.0"`. Keep the already-supported majors in the range unless the user asked to drop them. Then bump the matching `devDependencies` pin (libraries usually pin a concrete `react`/`@types/react` in devDeps for their own build and tests) to the target major so the code is actually compiled and tested against it.

**Validate the compatibility claim — don't just assert it.** Widening the peer range to add a new major is a public statement that the library *works* with that React version, so it must be backed by actually building and testing against it. Be aware: because this path edits `package.json` by hand and does **not** call `typescript_upgrade_package_dependency_group`, the runtime-validation gate that normally blocks an unvalidated upgrade will **not** fire here — nothing forces the check, so it is on you to run it. Concretely, when `validateRuntime` is true:
- **Baseline first (Phase 1):** before changing anything, run `typescript_validate_runtime` to record the library building/testing against its current React. (If no eval plan exists, invoke `create-eval-plan` — for a library the plan is typically a build + test assertion, not an http-probe.)
- **Install the target React in devDependencies** (add a pin if the library doesn't already have one) so the library is genuinely compiled and tested against the new major — a widened range with nothing installed at that major proves nothing.
- **Post-upgrade (Phase 3):** after widening + installing, run `typescript_validate_runtime` again and confirm no regressions vs. the baseline.

A peer-range widen with no build/test against the new major is an unverified claim — do not report it as a successful upgrade.

## Peer-dep resolution

Don't wait for install to fail to think about React-ecosystem companions. When bumping the React **major**, the libraries that gate on it — `react-router`/`react-router-dom`, `react-redux`, `@testing-library/react`, and the others listed under "Ecosystem peer-dep churn" in the applicable `react/<major>.md` — frequently block `install` if left stale. For an all-packages request they're already in scope. For a React-only request, proactively surface the ones that are present and recommend including them (see peer-dependencies.md) rather than leaving them stale and discovering the conflict at install time.

When `typescript_install_dependencies` fails with peer-dependency errors:

1. **Try a library upgrade first.** The usual cause is an outdated React-ecosystem library with no version compatible with the target React major yet. Check the library's releases — a newer major is often available. Bump it and reinstall.
2. **Fall back to overrides/resolutions only when no compatible version exists.** Mark them as temporary debt:
   - npm: `"overrides": { "<package>": "<version>" }`
   - Yarn: `"resolutions": { "<package>": "<version>" }`
3. **Never silently downgrade React** to satisfy a peer — landing the target major is the goal.

## Validation

- The standard Phase 3 `typescript_compile_package` call still applies — do not skip it.
- If `validateRuntime` is true, call `typescript_validate_runtime` — REQUIRED, do not skip. React breakages (strict-mode behavior, removed APIs, hydration) often surface only at runtime. Follow the Phase 3 rules in [SKILL.md](./SKILL.md) and the flow in [runtime-validation.md](./runtime-validation.md).

## Telemetry

After the React upgrade attempt (success or failure), call `typescript_report_telemetry` once with:

- `eventType`: `"group_upgrade"`
- `group`: `"react"`
- `sessionId`: from the scan response
- `success`: whether the upgrade landed (compile + install both passed)
- `fromVersion`: starting React major as a string (e.g. `"18"`)
- `toVersion`: target React major as a string (e.g. `"19"`)
- `strategy`: `"single-shot"`
- `codemodsRun`: count of codemod recipes invoked — typically `2` (the `react/<major>/migration-recipe` plus `types-react-codemod preset-19`); `0` if neither could run (manual fixes only)
- `failureReason`: if failed, e.g. `"cra_blocker"`, `"peer_dep_unresolved"`, `"compile_errors_remaining"`

This is **not** the terminal event. Return to the calling workflow, which finishes with `typescript_write_upgrade_summary`.
