# Radix UI Upgrades

Radix ships as **one cluster that must move together**:

- **Primitives:** every `@radix-ui/react-*` package (`react-dialog`, `react-dropdown-menu`, `react-tooltip`, `react-select`, `react-tabs`, …)
- **Shared internals:** `@radix-ui/react-slot`, `@radix-ui/react-primitive`, `@radix-ui/react-context`, `@radix-ui/react-compose-refs`, `@radix-ui/primitive`, `@radix-ui/react-presence`, … — usually transitive, but frequently hoisted into the manifest by scaffolds (shadcn/ui declares `@radix-ui/react-slot` directly)
- **Unified entry point:** `radix-ui` (one package re-exporting all primitives)
- **Design system + tokens:** `@radix-ui/themes`, `@radix-ui/colors`
- **Icons:** `@radix-ui/react-icons`

## Scope: coupling rules

- **The primitives pin their shared internals to EXACT versions.** This is the single most important
  fact about upgrading Radix. `@radix-ui/react-dialog@1.1.23` declares
  `"@radix-ui/react-primitive": "2.1.10"`, `"@radix-ui/react-slot": "1.3.3"`,
  `"@radix-ui/react-context": "1.2.2"`, `"@radix-ui/primitive": "1.1.7"` — **exact, no caret**.
  Every other primitive does the same. So if you advance `@radix-ui/react-dialog` but leave
  `@radix-ui/react-tooltip` on an older version, the two demand *different exact versions of the same
  internal package*, npm installs **both**, and the duplicated `.d.ts` declarations become
  structurally distinct nominal types. The result is a flood of errors like:

  ```
  error TS2719: Type 'PrimitiveDivProps' is not assignable to type 'PrimitiveDivProps'.
  Two different types with this name exist, but they are unrelated.
  ```

  These errors appear in files you never edited, and they are **caused by the partial upgrade
  itself** — not by a breaking change in any package.

- **Radix is therefore an all-or-nothing group.** Upgrade **every** `@radix-ui/*` package present in
  the manifest together, or **none** of them. A partial Radix upgrade is *worse than no upgrade*: it
  desynchronizes internal pins that were previously consistent. This is a **required** compatibility
  group (like the React core) — see [peer-dependencies.md](./peer-dependencies.md). If the cluster
  genuinely cannot be moved as a unit, leave the whole cluster at its current versions and report
  why; do **not** ship a subset.

- **`@radix-ui/react-slot` is both a direct dependency and an exact-pinned transitive one.** It is the
  most common source of duplicate-type errors, because scaffolds put it in `dependencies` while every
  other primitive also pins its own exact copy. Always include it in the group.

- **Radix binds to React, but never *requires* a React upgrade.** Every primitive declares
  `react`/`react-dom` with the range `^16.8 || ^17.0 || ^18.0 || ^19.0` — deliberately wide. A Radix
  upgrade is therefore **always satisfiable on the React major the project already has**. Do **not**
  bump `react`, `react-dom`, `@types/react`, or `@types/react-dom` on Radix's behalf.

  If `@types/react` does not match the installed `react` major, that is a **check-and-report** item,
  not something to fix here: both type packages are declared as **optional** peers with the range `*`,
  so a mismatch never fails the install and surfaces only at compile time. Report it and route the
  change through the normal React/peer flow ([peer-dependencies.md](./peer-dependencies.md)); do not
  add it to the Radix lockstep set. Recent Radix releases are dominated by React 19/19.2 fixes (stale
  `onEscapeKeyDown`/`onDismiss` handlers on React 19.2; infinite re-render loops in React 19 from
  unstable composed-ref callbacks; `Slot` re-render loops from a new ref callback each render; focus
  management in React 19.2+), so *if* React is being upgraded independently in this same run, let
  React's guidance go first — that is all `runAfter: react` means.

- These rules **constrain** the standard `typescript_upgrade_package_dependency_group` flow — they do
  not replace it. Pass the whole scanned Radix group into Phase 2; don't strip it down to the one
  package the user named.

## The lockstep set is Radix-only — bound the group before you upgrade

This is the guardrail that keeps the rule above from turning into a framework-wide upgrade.

The scan's `dependencyGroups` are built from **peer-dependency** relationships, so the group containing
`@radix-ui/react-dialog` also contains `react`, `react-dom`, `@types/react`, and — transitively — the
rest of the app's React ecosystem (`next`, `next-auth`, `lucide-react`, …). Passing that group through
unfiltered because "Radix must move in lockstep" will bump **all of it**, producing unrequested major
jumps like React 18→19 and Next 13→16 that the user never asked for and that no Radix package needs.

So, before calling `typescript_upgrade_package_dependency_group`:

1. **Intersect the group down to Radix members only** — the names matching `@radix-ui/*` plus the
   unified `radix-ui`. That intersection is the lockstep set.
2. **Everything else in that dependency group is NOT part of the Radix requirement.** `react`,
   `react-dom`, `@types/react`, `@types/react-dom`, `next`, and every other ecosystem package follow
   the **normal opt-in peer flow** in [peer-dependencies.md](./peer-dependencies.md). They are in the
   group because they are peers, not because Radix needs them moved.
3. **Never let a Radix upgrade introduce a major bump in a non-Radix package.** If resolving the Radix
   set appears to require one, that is a signal to stop and report — not to proceed. The only
   version floor Radix actually imposes is `react >= 16.8`.

"All-or-nothing" applies **within** the Radix cluster. It is not a licence to widen scope beyond it.

## Strategy: lockstep bump, no codemod

There is **no Radix codemod** — no `@radix-ui/codemod` package exists on npm, and the official Themes
upgrade guide prescribes manual find-and-replace. So the flow is: bump the whole cluster to latest in
one step, then apply the documented renames by hand for any major crossed.

The primitives are all still on **major 1** (e.g. `@radix-ui/react-dialog` latest is `1.1.x`), so for
the primitives this is a **minor/patch** bump, not a major migration — which is exactly why treating
it as "just a version bump" is so tempting and so often wrong. The real majors in this cluster live in
`@radix-ui/themes` (v1 → v2 → v3) and `@radix-ui/colors` (v3).

## Order of operations

1. **Collect the whole cluster.** List every dependency matching `@radix-ui/*` plus `radix-ui` from the
   manifest — including any hoisted internals (`@radix-ui/react-slot`, `@radix-ui/react-primitive`,
   `@radix-ui/react-compose-refs`, `@radix-ui/react-context`, `@radix-ui/primitive`).
2. **Check for user-authored pins first** (see "Respect user-authored pins" below). If one exists,
   stop and report it rather than rewriting it.
3. **Bump the Radix set together** via `typescript_upgrade_package_dependency_group` — one group
   containing the `@radix-ui/*` members **and nothing else** (see "The lockstep set is Radix-only"
   above). If React is independently in scope this run, its guidance has already been applied.
4. **Reinstall** with `typescript_install_dependencies`.
5. **Verify the internals actually deduplicated — REQUIRED.** This is the check that catches the
   dominant failure mode, and it must happen *before* you start "fixing" type errors:

   Check **every** internal you collected in step 1, not just the common ones:

   ```
   npm ls @radix-ui/react-primitive @radix-ui/react-slot @radix-ui/react-context \
          @radix-ui/primitive @radix-ui/react-compose-refs @radix-ui/react-presence
   ```

   (`yarn why <pkg>` / `pnpm why <pkg>` for the other package managers.) If more than one version of
   any of them is listed, the cluster is still partially upgraded — **go back to step 3 and include
   the stragglers**. Do not attempt to fix the resulting `TS2719` errors in source; they are a
   symptom, and editing source to work around them is wrong. `npm dedupe` may collapse the tree once
   the manifest ranges are consistent, but it cannot fix genuinely divergent exact pins.
6. **Apply the documented renames** for any `@radix-ui/themes` major crossed (audit table below).
7. **Compile and verify.** Call `typescript_compile_package` and resolve remaining errors with the
   standard verify loop.

## Respect user-authored pins — do not rewrite them

A pin the user wrote is a deliberate signal. Distinguish it from Radix's own internal pins:

- **Radix's internal exact pins** live inside the *published* packages' `dependencies`. They are not
  in the user's manifest and are not peer dependencies. Never try to change them; converge them by
  moving the siblings (above).
- **A user-authored exact pin** (e.g. `"@radix-ui/react-slot": "1.0.2"`, no caret/tilde) or an existing
  `overrides` / `resolutions` / `pnpm.overrides` entry for a Radix package is a deliberate decision —
  often pinned to work around exactly this duplication. **Do not widen, bump, or delete it.** Report
  it as a blocker: name the pin, explain that it forces a second copy of that internal and blocks the
  lockstep upgrade, and recommend the specific version that the rest of the cluster resolves to. Let
  the user decide.
- **Do not add a new `overrides` / `resolutions` block** to force deduplication. It is a repo-wide
  dependency-resolution policy change with blast radius far beyond Radix, and it *masks* the real
  problem (stale siblings) rather than fixing it. Prefer the lockstep bump. If the cluster truly
  cannot be aligned, surface `overrides` as a recommendation for the user to make — don't apply it.

## Pre-upgrade audit

Search the package directory (`grep`/`rg`) for these before changing version pins. The Themes rows
apply only when crossing that `@radix-ui/themes` major.

| Pattern to find | What to do |
| --- | --- |
| More than one version of any shared internal in `npm ls` (`react-primitive`, `react-slot`, `react-context`, `primitive`, `react-compose-refs`, `react-presence`) | Pre-existing duplication. Fix by aligning the cluster, not by editing source. |
| `@radix-ui/react-slot`, `@radix-ui/react-primitive`, `@radix-ui/react-compose-refs` in `dependencies` | Hoisted internals. Must be upgraded in the same group as the primitives that pin them. |
| `className` passed to `Dialog.Portal` / `Sheet…Portal` (the shadcn/ui `dialog.tsx`, `sheet.tsx` scaffold) | `@radix-ui/react-dialog` **1.0.5** narrowed `DialogPortalProps` to `{children, container, forceMount}`; 1.0.4 extended `Omit<PortalProps,'asChild'>`, which carried `className`. Any project upgrading off 1.0.4 gets `TS2339: Property 'className' does not exist on type 'DialogPortalProps'`. Drop `className` from the Portal wrapper (keep it on `Overlay`/`Content`). |
| `overrides` / `resolutions` / `pnpm.overrides` mentioning `@radix-ui` | User-authored. Report as a blocker; do not rewrite. |
| `React.CSSProperties` used with Radix CSS custom properties (e.g. `style={{ '--radix-…': … }}`) | Radix **removed its global `React.CSSProperties` augmentation** from the emitted declaration files. Code that relied on it now errors; add a local `as React.CSSProperties` cast or your own module augmentation. |
| `virtualRef={…}` on a Popper/Popover anchor | The `virtualRef` prop type was widened to accept `RefObject<Measurable \| null>`. Widening only — existing code stays valid. |
| `Component.displayName` read off a Radix part | Parts now use named render functions instead of `displayName` assignments (a tree-shaking change). Don't key logic off `displayName`. |
| `use-sync-external-store` shim imported directly | Radix now uses React's built-in `useSyncExternalStore` (React 18+). The CJS-only shim previously broke ESM-only browser bundles. |
| `DialogRoot`, `DialogTrigger`, `DialogContent`, `TabsRoot`, `SelectRoot`, … (Themes) | **Themes v3:** named exports for multi-part components were dropped. Use dot notation (`Dialog.Root`, `Dialog.Trigger`, `Dialog.Content`). Affects `AlertDialog`, `Callout`, `ContextMenu`, `Dialog`, `DropdownMenu`, `HoverCard`, `Popover`, `RadioGroup`, `Select`, `Table`, `Tabs`, `TextField`. |
| `TextField.Input` (Themes) | **Themes v3:** `TextField` has only `Root` and `Slot`. Used *without* `TextField.Root` → rename to `TextField.Root`; used *within* `TextField.Root` → remove it and move its props onto `Root`. A `TextField.Slot` to the right of the old `Input` needs `side="right"`. |
| `shrink=` / `grow=` on Themes layout components | **Themes v3:** renamed to `flexShrink` / `flexGrow`. |
| `width="1"`…`width="9"` / `height="…"` on Themes layout components | **Themes v3:** these no longer map to the space scale. Replace with explicit values (`1`→`4px`, `2`→`8px`, `3`→`12px`, `4`→`16px`, `5`→`24px`, `6`→`32px`, `7`→`40px`, `8`→`48px`, `9`→`64px`) or `var(--space-N)`. Update responsive object syntax too. |
| Prop definitions / helpers imported from `@radix-ui/themes` root | **Themes v3:** internals moved to the `@radix-ui/themes/props` and `@radix-ui/themes/helpers` subpaths. |
| `--color-surface-accent`, `--accent-9-contrast` (and `--red-9-contrast`, …), `--color-focus-root`, `--color-selection-root`, `--color-autofill-root`, `--color-page-background`, `--gray-2-translucent`, `--tabs-trigger-*-letter-spacing` | **Themes v3** CSS token renames — see "Themes v3 token renames" below. CSS-only, so the compiler will not catch these. |
| `<Badge size="2"`, `<Section size="3"` (Themes) | **Themes v3:** `Badge` gained a `size="3"` and its `size="2"` is much smaller — map `size="2"` → `size="3"`. `Section` gained a `size="3"` — map `size="3"` → `size="4"`. |

### Themes v3 token renames (CSS, not type-checked)

- `--color-surface-accent` → `--accent-surface`
- `--accent-9-contrast` → `--accent-contrast` (and `--red-9-contrast` → `--red-contrast`, and so on for every scale)
- `--color-autofill-root` → `--focus-a3`; `--color-focus-root` → `--focus-8`; `--color-selection-root` → `--focus-a5`
- `--color-page-background` → removed; `Theme` no longer sets the body background. Use `--color-background` on `.radix-themes`.
- `--gray-2-translucent` (and the other tinted grays) → removed. Use `--color-panel-translucent` with a backdrop blur.
- `--tabs-trigger-active-letter-spacing` → `--tab-active-letter-spacing` (likewise `-active-word-`, `-inactive-letter-`, `-inactive-word-`)

## Blockers

- **Do not widen scope beyond Radix.** A Radix upgrade that appears to require bumping `react`,
  `next`, or any other non-Radix package has escaped its boundary — see "The lockstep set is
  Radix-only". Stop and report rather than proceeding; Radix's only real floor is `react >= 16.8`.
- **`@radix-ui/react-icons` 2.x is a pre-release.** The `latest` tag is `1.3.2`; every `2.0.0-*` build
  is published under the `next` tag only. Resolve it to `latest` — do **not** advance to a `next`-tag
  version as part of a routine upgrade.
- **Migrating to the unified `radix-ui` package is a source refactor, not a version bump.** Radix added
  `radix-ui` so that primitives stay current "without worrying about conflicting or duplicate
  dependencies" — it is the *strategic* fix for everything described above, since one package means one
  copy of each internal. But adopting it means rewriting every `@radix-ui/react-*` import across the
  codebase (`import * as Dialog from "@radix-ui/react-dialog"` → `import { Dialog } from "radix-ui"`,
  or the per-primitive subpath `import { Dialog } from "radix-ui/dialog"`). **Recommend it, do not
  perform it** as part of a dependency upgrade. Report it as a follow-up.
- **A user-authored pin or `overrides` entry blocking the lockstep upgrade** — report it (above);
  don't rewrite it.
- **`@radix-ui/themes` major migrations are partly CSS.** The token renames above are invisible to
  `tsc`. A clean compile does **not** mean a clean Themes upgrade.

## Validation

- The standard Phase 3 `typescript_compile_package` call still applies — do not skip it.
- Re-run the `npm ls` dedupe check from step 5 after the final install. A single version of each
  shared internal is the signal that the cluster is coherent.
- Call `typescript_validate_runtime` — REQUIRED. Radix is a headless UI
  library: focus management, dismiss/escape behavior, portal mounting, and the Themes token renames
  regress at runtime with no compile error. Follow the Phase 3 rules in [SKILL.md](./SKILL.md) and
  [runtime-validation.md](./runtime-validation.md).

## Telemetry

After the Radix upgrade attempt (success or failure), call `typescript_report_telemetry` once with:

- `eventType`: `"group_upgrade"`
- `group`: `"radix"`
- `sessionId`: from the scan response
- `success`: whether the upgrade landed (compile + install both passed)
- `fromVersion`: starting `@radix-ui/themes` major as a string (e.g. `"2"`), or the primitives' major (`"1"`) when Themes isn't present
- `toVersion`: target major as a string (e.g. `"3"`)
- `strategy`: `"lockstep"`
- `codemodsRun`: `0` — Radix ships no codemod
- `failureReason`: if failed, e.g. `"duplicate_internal_versions"`, `"user_pin_blocks_lockstep"`, `"scope_would_exceed_radix"`, `"themes_major_manual_fixes"`, `"compile_errors_remaining"`

This is **not** the terminal event. Return to the calling workflow, which finishes with
`typescript_write_upgrade_summary`.
