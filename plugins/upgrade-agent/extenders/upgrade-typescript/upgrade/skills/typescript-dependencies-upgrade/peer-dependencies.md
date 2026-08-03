# Peer Dependency Analysis

After scanning dependencies with `typescript_scan_dependencies`, analyze the results to identify peer dependencies related to the user's target packages.

## Step 1: Locate Target Packages in Dependency Groups

The scan returns `dependencyGroups` — ordered arrays of dependency group objects, each with a `packages` array of package names grouped by peer dependency relationships. For each package the user wants to upgrade:

1. Find the group(s) in `dependencyGroups` where the `packages` array contains it.
2. Collect all **other packages in those groups** that the user did not explicitly request. These are the peer dependencies.

**Example:** If the user asks to upgrade `react`, and the scan returns a group `{ "packages": ["react", "react-dom", "@types/react"], "containsBundlers": false }`, then `react-dom` and `@types/react` are peer dependencies.

## Step 2: Present Peer Dependencies to the User

If peer dependencies were found, present them clearly:

> The following packages are **peer dependencies** of the packages you want to upgrade. Upgrading them together is recommended to avoid version conflicts and installation errors:
>
> - `react-dom` (peer of `react`)
> - `@types/react` (peer of `react`)
>
> Would you like to include these in the upgrade?

**If no peer dependencies are found** (the target packages are each in their own single-element group), skip this step and proceed directly to the baseline phase.

## Step 3: Build the Final Package List

Based on the user's response:

- **If the user confirms** — add the peer dependencies to the upgrade list.
- **If the user declines** — proceed with only the originally requested packages. Note that this may cause installation or compilation errors due to version mismatches; be prepared to handle them during the upgrade phase.
- **If the user partially confirms** — include only the peer dependencies they accepted.

### React core is a required compatibility group

**Exception:** if `applicableGuidance` from the scan includes a `react.md` entry (an entry whose `file` is `react.md`), treat the React core packages as a **required** compatibility group — do not let the user opt out of including peers that belong to the React core. Specifically, when the user requests an upgrade to any one of `react`, `react-dom`, `@types/react`, or `@types/react-dom`, all four (if present in the manifest) must be upgraded together to the matching React major. Present them as informational ("these will be upgraded together to keep React's typing and runtime in sync") rather than as an optional confirmation. Other React-ecosystem peers in the same group (e.g., `react-router`, `react-redux`, `@testing-library/react`) follow the normal opt-in flow described above.

For React **major** bumps specifically, don't leave those ecosystem companions to chance. The packages known to gate on the React major (e.g. `react-router`/`react-router-dom`, `react-redux`, `@testing-library/react` — see the "Ecosystem peer-dep churn" list in the applicable `react/<major>.md`) frequently block `install` if left stale. When any are present, surface them with an explicit **recommendation to include** them (not a neutral opt-in), so the user makes an informed choice instead of hitting a peer-dependency error at install time.

### React as a peer dependency (libraries)

If `react`/`react-dom` appear only under the manifest's `peerDependencies` — a library that renders React but doesn't own its version — there's nothing to "upgrade" in the usual sense. See react.md ("Libraries that declare React as a peer dependency"): widen the peer range to add the new major and bump the matching `devDependencies` pin. Don't present this as a peer opt-in.

### MUI + Emotion is a compatibility group

**Exception:** if `applicableGuidance` from the scan includes a `mui.md` entry (an entry whose `file` is `mui.md`), treat the MUI cluster as a group that upgrades together. When the user requests any `@mui/*` or `@emotion/*` package, present the rest of the cluster present in the manifest — `@mui/material`, `@mui/icons-material`, the `@mui/x-*` packages, and the `@emotion/react` / `@emotion/styled` styling engine — with an explicit **recommendation to include** them (not a neutral opt-in). Emotion is `@mui/material`'s peer styling engine, and `@mui/x-*` must not lead `@mui/material`'s major, so leaving one behind causes peer-dependency errors at install time. See [mui.md](./mui.md) for the coupling rules.

### i18next is a compatibility group

**Exception:** if `applicableGuidance` from the scan includes an `i18next.md` entry (an entry whose `file` is `i18next.md`), treat the i18next cluster as a group that upgrades together. When the user requests `i18next`, `react-i18next`, or any `i18next-*` plugin, present the rest of the cluster present in the manifest — the `i18next` core, its `react-i18next` binding, and the `i18next-*` plugins (e.g. `i18next-http-backend`, `i18next-browser-languagedetector`, `i18next-fs-backend`) — with an explicit **recommendation to include** them (not a neutral opt-in). Each `react-i18next` major raises its minimum `i18next` peer (e.g. `react-i18next@17` requires `i18next >= 26`), and the plugins are peers of the core, so leaving one behind causes an `ERESOLVE`/peer error or missing-type-export errors at install time. See [i18next.md](./i18next.md) for the coupling rules.

### Karma + Jasmine is a compatibility group

**Exception:** if `applicableGuidance` from the scan includes a `karma-jasmine.md` entry (an entry whose `file` is `karma-jasmine.md`), treat the test stack as a group that upgrades together. When the user requests `karma`, any `karma-*` plugin, `jasmine`/`jasmine-core`, or `@types/jasmine`, present the rest of the cluster present in the manifest — `karma` and its `karma-*` plugins (`karma-jasmine`, `karma-chrome-launcher`, `karma-coverage`, `karma-jasmine-html-reporter`, …), `jasmine-core`, and `@types/jasmine` — with an explicit **recommendation to include** them (not a neutral opt-in). `karma-jasmine@5` pins `karma ^6`, `@types/jasmine`'s major must equal `jasmine-core`'s, and `jasmine-core` must stay on **6.x** while Karma is present (`karma-jasmine` breaks on Jasmine 7), so leaving a member behind — or advancing `jasmine-core` to 7 — causes `ERESOLVE`/peer errors or broken specs. These are **not** upgraded by `ng update`. See [karma-jasmine.md](./karma-jasmine.md) for the coupling rules.

## Step 4: Organize into Upgrade Groups

The final package list may span multiple dependency groups. Preserve the group structure from the scan results:

- For each dependency group from the scan, intersect its `packages` array with the final confirmed package list.
- Drop any groups that become empty after intersection.
- Maintain the original group ordering (priority packages like `typescript` and `@types/node` first).

These filtered groups are what you pass to Phase 2 (Upgrade) in the main SKILL.md — one `typescript_upgrade_package_dependency_group` call per group.
