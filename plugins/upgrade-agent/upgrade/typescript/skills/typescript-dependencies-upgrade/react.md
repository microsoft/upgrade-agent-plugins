# React Upgrades

The four React **core** packages — `react`, `react-dom`, `@types/react`, `@types/react-dom` — must move together to the **same** React major; never bump one without the others. That same-major rule applies to those four only.

These rules constrain how the React group is processed within the standard `typescript_upgrade_package_dependency_group` flow — they do **not** replace it. When you make that call:

- **Pass the whole group as it enters Phase 2.** For an all-packages request that's the entire scan group; for a scoped request it's the requested packages plus the peers confirmed in Phase 0 (with the React core four always included, per [peer-dependencies.md](./peer-dependencies.md)).
- **Do not strip the call down to just the core four.** The scan grouped these packages because they are peer-coupled and meant to upgrade together; dropping the rest is what creates the install/peer conflicts this skill exists to avoid.
- **Upgrade "react"-named members to their own requested target, or their own latest version when untargeted—not React's version.** Group members that merely have "react" in their name (`react-icons`, `html-react-parser`, `react-helmet`, etc.) are still upgraded, but are NOT forced onto React's major number (there is no `react-icons@19` that tracks React 19).
- **Revert, don't pre-exclude, a broken non-core member.** If upgrading one of those non-core members introduces breakage you can't resolve, fall back to reverting just that package per [upgrade-packages.md](./upgrade-packages.md) — don't pre-emptively exclude it from the group.

`applicableGuidance` — the ordered list of guidance entries returned in the `typescript_scan_dependencies` response (defined in SKILL.md and generate-plan.md) — includes a `react/<major>.md` entry for each React major the upgrade crosses. **Reading every per-major file it lists is REQUIRED — do not skip them and do not treat them as optional reference.** Read them in full and apply them cumulatively: each documents the breaking changes introduced in that major, and a single-shot jump (e.g. 17 → 19) must still handle every major it passes through. The Pre-upgrade audit table below is a *detection* checklist only — it tells you what to grep for, not how to fix it, and it is **not** a substitute for the per-major files, which carry the fix details, TS-specific failure modes, and ecosystem peer requirements the table omits. Do NOT rationalize skipping them ("react.md already summarized the highlights", "the per-major file is probably just a longer version of the table", "I'll consult it only if I get stuck"). Read only the files the scan listed — don't read per-major files it didn't list.

## Scope: web React only

This guidance targets **web React** (`react` + `react-dom`). React Native versions independently of web React and upgrades through its own tooling (`react-native upgrade` / the RN Upgrade Helper), which is outside this tool's scope. If the project is React Native — `react-native` in `package.json`, or source that imports from `'react-native'` — treat the React upgrade as a blocker (reason: "react-native / out of scope") and follow "Handling a React blocker" below: a React-only request stops and reports; an all-packages request leaves React untouched and continues with the other dependency groups.

## Strategy: single-shot upgrade

When the calling workflow's SKILL.md defines a Phase 2 fast-path checkpoint, first run the blocker checks (React Native scope above, "CRA blocker" below); blocked entries follow "Handling a React blocker" and are excluded from the checkpoint. Then start with it for the remaining entries: bump straight to the target (no React 18.3 preflight) and validate before any codemod. If the checkpoint passes, you are done. If it does not, continue forward from the target with step 4 of "Order of operations" below; do not step back to 18.3. Without the checkpoint (it is not defined, or it does not apply, e.g. a `replaces`-mode framework is also in scope), use the preflight: for a React 19 upgrade, first upgrade to React 18.3 and address the warnings it surfaces before upgrading to React 19. React 18.3 is identical to 18.2 except for warnings about deprecated APIs and other changes needed for React 19, and the official React 19 upgrade guide recommends this preparatory step. After that preflight, go directly to the target major rather than hopping through any other intermediate releases unless the user explicitly asks. Reading and upgrading are separate steps: still read **every** per-major file the scan listed and apply them cumulatively.

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

If `react-scripts` (or its abandoned TypeScript fork `react-scripts-ts`) is in the `package.json` currently being upgraded, that package uses Create React App, which never gained React 19 support. Migrating its build tooling to Vite, Next, Remix, or another modern bundler is outside this tool's scope. Treat that package entry as a React blocker (reason: "CRA / react-scripts") and follow "Handling a React blocker" below.

This check is package-scoped, not repository-scoped. In a monorepo, a CRA example, fixture, or documentation site does not block upgrading a separate library package that declares React. Do not abandon the repository-wide request merely because `react-scripts` appears somewhere under the repository root: mark only the scan entry whose own manifest declares it as blocked, then continue processing every other React-declaring entry.

## Handling a React blocker

When React cannot be upgraded — CRA, or a peer dependency with no compatible version — what you do depends on scope:

- **The user asked only to upgrade React in a standalone package** → report the blocker and its reason via `typescript_write_upgrade_summary`, then stop. Nothing else is in scope.
- **The user asked to upgrade React in a monorepo** → mark that package entry as blocked and continue with every other React-declaring entry from the scan. Stop the whole React upgrade only when every in-scope declaration is blocked.
- **The user asked to upgrade all packages** → do NOT halt the workflow. Revert any React-related `package.json` edits and reinstall to restore the baseline lockfile, then continue with the remaining dependency groups. Record React as blocked in the Phase 4 summary.

Never downgrade React or pin it below the target to work around a blocker.

## Order of operations

Bump versions and reinstall **before** touching source, then run codemods and manual fixes. Editing source before the versions resolve tends to regress.

1. **Bump versions together.** Update `react`, `react-dom`, `@types/react`, and `@types/react-dom` to the target React major as one group via `typescript_upgrade_package_dependency_group`.
2. **Match the types version to a real published version.** Do NOT assume `@types/react@<reactVersion>` exists — the `@types/react*` packages don't track React's version exactly. Query `npm view @types/react version` and `npm view @types/react-dom version` and pin to those. If the project's own source references React types but `@types/react`/`@types/react-dom` are not in `package.json` (resolved only transitively), add them explicitly at the matching major — as `devDependencies` for the project's own build, and additionally under `peerDependencies` if it's a library that exposes React types in its public API — so the type version is controlled rather than floating. Don't add `@types/*` packages the project doesn't actually compile against.
3. **Reinstall to update the lockfile.** Call `typescript_install_dependencies`. If install reports `Could not resolve dependency` or `Conflicting peer dependency`, follow "Peer-dep resolution" below.
   **Fast-path checkpoint (when SKILL.md defines one and it applies):** steps 1–3 were its bump, so run only its validation step now; do not bump again. If it passes, stop here. Steps 4–7 apply only when it does not.
4. **Run language-scoped React codemods — REQUIRED.** Apply the safety gate below before invoking a recipe. The React 19 recipe includes `react/prop-types-typescript`, which generates TypeScript interfaces and annotations: **never run that recipe over `.js`/`.jsx` or a mixed-language directory**. For JavaScript inputs, invoke the applicable runtime transforms separately (`react/19/replace-reactdom-render`, `react/19/replace-string-ref`, `react/19/replace-act-import`, `react/19/replace-use-form-state`), scoped to the inventoried source paths, and review their output as JavaScript. For TypeScript-only paths, the recipe is allowed. The current CLI uses `npx --yes codemod@latest run <transform-or-recipe> --target <sourcePath> --no-interactive --allow-dirty`; check the resolved version's `--help` before running it. Substitute `yarn dlx` / `pnpm dlx` per the project's package manager. `npx --yes` handles the package-execution prompt; `--no-interactive` and `--allow-dirty` are codemod options. Source transforms are explicitly permitted despite Key Principle #9. If a transform cannot run, record the exact blocker and apply the per-major fixes manually; never fabricate execution or completion.
5. **Run the TypeScript codemod on TypeScript inputs only — REQUIRED when applicable.** The recipe does not perform the React type-API migration. For React 19, run `npx --yes types-react-codemod@latest preset-19 <typescriptSourcePath> --yes`, repeating for the in-scope TS source paths as needed (substitute the `dlx` form per package manager). The final `--yes` belongs to **types-react-codemod** and accepts its preset prompt; `--no-interactive` and `--allow-dirty` are not supported by this tool. Its default file discovery covers `.ts`/`.tsx`, not JavaScript; inspect the inventory for unsupported extensions or syntax rather than assuming everything was processed. Use the matching preset for other React majors. Audit the preset's selected transforms and output, including any widened types; prefer explicit prop shapes over newly introduced `any`. Apply the parser-coverage and import checks below before accepting the result.
6. **Apply manual fixes from per-major guidance.** Work through each `react/<major>.md` the scan listed and address what the codemods don't cover.
7. **Compile, lint, and verify.** Call `typescript_compile_package` and resolve remaining errors with the standard verify loop. Then run the repository's existing lint/format scripts and remove obsolete imports or declarations made unused by the codemods; a successful compile does not prove transformed JavaScript passes `no-unused-vars`. Re-read the per-major guidance when an error category matches one of its sections.

### Codemod safety gate

These checks supplement steps 4–5: they cover transform inputs, output, and files the runner failed to process. Use step 7 for the overall compile/lint/verify loop.

- **Inventory and preserve the starting state.** Before each transform, record the source paths, file extensions, applicable migration patterns, existing edits, and the repository's parser/build/lint commands. Include JSX in `.js` when the repository supports it, and separately account for Flow, declaration files, and `.mts`/`.cts` inputs. Exclude dependencies, generated output, and unrelated packages. Scope by the files' actual language, not by the presence of a root `tsconfig.json`.
- **Keep the source language.** Do not introduce interfaces, type aliases, parameter annotations, type-only imports, or assertions into `.js`/`.jsx`, and do not rename files or enable TypeScript merely to accommodate codemod output. Apply JavaScript-compatible manual fixes and existing JSDoc conventions where appropriate. If a transform emits invalid syntax, repair or undo only its edits while preserving the pre-transform user and upgrade changes.
- **Account for every parser failure and skipped applicable file.** Retain the tool version, exact command, exit status, output summary, and failing paths. Exit 0 alone is not completion: runners can print parser errors while exiting successfully. Compare the processed paths with the inventory; distinguish a verified no-op from a file that was never parsed. Retry affected files with a parser/configuration that the tool actually supports and that matches the repository. If that is unsupported, apply the migration manually and run the repository's own parser/build checks on those files. Do not pass an invented `--parser` flag or rename a source file to trick an extension-selected parser. Unresolved files remain explicitly incomplete, even if other files transformed successfully.
- **Repair bindings and imports before hooks or another install.** Check generated bindings for collisions, shadowing, and self-references such as `const root = createRoot(root)`. Give the DOM container and React root distinct names, and keep subsequent render/unmount references consistent. Run existing import-order, unused-import, and formatting autofixes, then check the resulting diff and rerun the checks. Keep directive prologues such as `"use client"` ahead of imports. Remove a legacy ReactDOM import after root migration only when no remaining API uses it; preserve mixed uses such as `ReactDOM.createPortal`, intentional side-effect imports, and comments. Merge new named/type imports according to the repository's rules without changing runtime import semantics. Fix remaining ordering errors manually; do not disable lint rules or install a new formatter.
- **Check transform coverage against the input inventory.** Report which inventoried files were transformed, manually repaired, unchanged after inspection, or still blocked. A passing compile does not prove that the codemod processed every applicable file; do not claim completion while any file remains unaccounted for.

When validating a React codemod change, cover `.js` (including repository-supported JSX), `.jsx`, `.ts`, and `.tsx`: PropTypes inputs must not acquire TS syntax in JavaScript; typed JSX/ref patterns must migrate in TypeScript; parser failures must remain visible; new imports must pass the existing ordering rules. Include a root-only ReactDOM use, a mixed-use case, a DOM container already named `root`, and an already-migrated control that remains unchanged.

## Stale TypeScript can flood node_modules with phantom errors

`@types/react@19` ships `.d.ts` files written with modern TypeScript syntax (inline `import { type X }`, `abstract new (...)`, `const` type params). If the project's `typescript` compiler is too old to parse them, a **React-only** bump can surface thousands of errors *inside* `node_modules/@types/react` (`TS1005`, `TS1183`, `TS2304`, …) even though your own source is fine. This is the classic symptom of a React bump outrunning the compiler — don't mistake it for a broken upgrade.

This does **not** mean you should run the full TypeScript migration (that stays out of scope on a React-only request). Treat it as a compile error *caused by the requested upgrade* and apply the minimal fix:

- Bump `typescript` (and `@types/node` if needed) just enough to parse the new type definitions — the smallest version that clears the `node_modules` parse errors, not the latest.
- If raising the compiler isn't viable, set `"skipLibCheck": true` in `tsconfig.json` so the new `.d.ts` files aren't type-checked. This is a minimal, scoped tsconfig tweak — not a TS migration. In projects that build at multiple targets via project references (e.g. a `tsconfig.node.json` that only compiles `vite.config.ts`, or a separate browser/server config), the config that blows up is often a *referenced* tsconfig that doesn't `extend` the root and so never inherited `skipLibCheck`/`lib` — apply the fix to that specific referenced config, not just the root one.

Do not edit files under `node_modules`, and do not downgrade `@types/react` to dodge this.

## Libraries that declare React as a peer dependency

If `react`/`react-dom` appear only under `peerDependencies` — typical for libraries that render React but don't own the version — the upgrade tools won't "bump" anything, because a peer range isn't a pinned dependency. To support the new major, **widen the peer range** instead of pinning: e.g. `"react": "^17.0.0 || ^18.0.0 || ^19.0.0"`. Keep the already-supported majors in the range unless the user asked to drop them. Then bump the matching `devDependencies` pin (libraries usually pin a concrete `react`/`@types/react` in devDeps for their own build and tests) to the target major so the code is actually compiled and tested against it.

In a monorepo, process **every package entry returned by the scan that declares React**, including peer-only member packages. Root `pnpm.overrides`, npm `overrides`, and Yarn `resolutions` control installed versions only; they do not update those public peer declarations and do not count as completing the requested upgrade.

A blocked application or example does not block a separate library entry. Widen the library's peer range, pin its development copy to the requested target, and validate that library against the target before moving on.

**Validate the compatibility claim — don't just assert it.** Widening the peer range to add a new major is a public statement that the library *works* with that React version, so it must be backed by actually building and testing against it. Be aware: because this path edits `package.json` by hand and does **not** call `typescript_upgrade_package_dependency_group`, the runtime-validation gate that normally blocks an unvalidated upgrade will **not** fire here — nothing forces the check, so it is on you to run it. Concretely:
- **Baseline first (Phase 1):** before changing anything, invoke the `typescript-runtime-validation` skill in upgrade mode to record the library building/testing against its current React. For a library, the eval plan is typically a build + test assertion, not an http-probe.
- **Install the target React in devDependencies** (add a pin if the library doesn't already have one) so the library is genuinely compiled and tested against the new major — a widened range with nothing installed at that major proves nothing.
- **Post-upgrade (Phase 3):** after widening + installing, invoke the `typescript-runtime-validation` skill in upgrade mode again and confirm no regressions vs. the baseline.

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
- Invoke the `typescript-runtime-validation` skill in upgrade mode — REQUIRED. React breakages (strict-mode behavior, removed APIs, hydration) often surface only at runtime. Follow the Phase 3 rules in [SKILL.md](./SKILL.md).

## Telemetry

After the React upgrade attempt (success or failure), call `typescript_report_telemetry` once with:

- `eventType`: `"group_upgrade"`
- `group`: `"react"`
- `sessionId`: from the scan response
- `success`: whether the upgrade landed (compile + install both passed)
- `fromVersion`: starting React major as a string (e.g. `"18"`)
- `toVersion`: target React major as a string (e.g. `"19"`)
- `strategy`: `"single-shot"`
- `codemodsRun`: number of codemod command invocations, including failed attempts and retries. One recipe command counts as `1`, regardless of how many transforms it contains; four separately invoked transform commands count as `4`. Do not count the recipe's internal transforms again. Use `0` when no codemod command was invoked, including when the fast-path checkpoint passed. This is not a transformation or changed-file count and must not be used to compare migration coverage or success. Describe parser failures and incomplete coverage in the summary.
- `failureReason`: if failed, e.g. `"cra_blocker"`, `"peer_dep_unresolved"`, `"compile_errors_remaining"`

This is **not** the terminal event. Return to the calling workflow, which finishes with `typescript_write_upgrade_summary`.
