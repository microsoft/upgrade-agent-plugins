# TanStack Query, Table, and Router Upgrades

This guidance applies to these TanStack package families:

- **Query:** `@tanstack/react-query`, `@tanstack/react-query-*`, `@tanstack/query-*`
- **Table:** `react-table`, `@types/react-table`, `@tanstack/react-table`,
  `@tanstack/react-table-*`, `@tanstack/table-*`
- **Router:** `@tanstack/react-router`, `@tanstack/react-router-*`, `@tanstack/router-*`

These are three independent products. Upgrade each in-scope package to its own resolved target;
never force Query, Table, and Router onto the same version or major.

## Scope and prerequisites

- Keep direct dependencies from the **same family** in one dependency-group upgrade so adapters,
  core packages, devtools, persistence packages, and Router tooling do not remain stale relative
  to one another. Still resolve every package to its own published version.
- `react-table` and `@types/react-table` are legacy Table v7 package names. When either is in
  scope for a v8 migration, replace `react-table` with `@tanstack/react-table` and remove
  `@types/react-table`; do not treat the legacy packages' latest versions as the migration target.
- Check each target React adapter's declared React peer range. If the target requires React 18 or
  newer and the project is below that floor, include the React core peer upgrade in scope before
  upgrading TanStack. Follow [react.md](./react.md) for a multi-major React migration; do not
  suppress the peer error or force-install.
- TanStack Query v5 requires TypeScript 4.7 or newer. If the compiler is older, make the smallest
  upgrade that reaches 4.7. A multi-major compiler jump follows the structured
  [compiler upgrade](../typescript-compiler-upgrade/compiler-upgrade.md) flow and stops at the
  required floor unless the user also requested a TypeScript upgrade.

## Pre-upgrade audit

Search the package directory before changing versions. Use the findings to choose the applicable
official migration steps.

| Family | Pattern to find | Required action |
| --- | --- | --- |
| Query v4 -> v5 | Positional `useQuery(key, fn, options)`, `useMutation(fn, options)`, or positional `queryClient.*` calls | Run Query's official `remove-overloads` codemod, then manually fix every usage it reports as ambiguous. |
| Query v4 -> v5 | `onSuccess`, `onError`, or `onSettled` on queries | Refactor query callbacks; v5 removed them from queries (mutations still support them). |
| Query v4 -> v5 | `cacheTime`, `useErrorBoundary`, `keepPreviousData`, `isPreviousData`, `hashQueryKey` | Apply the official v5 replacements (`gcTime`, `throwOnError`, placeholder-data APIs, `hashKey`). The existing KB handles the safe mechanical subset on newly-erroring files. |
| Query v4 -> v5 | `useInfiniteQuery` without `initialPageParam` | Add an explicit initial page parameter and verify the next/previous-page functions. |
| Query integrations | `@trpc/react-query` v10 | This peer pins React Query v4. Surface the official coordinated tRPC v10 -> v11 migration (the tRPC package set, React Query v5, React 18.2+, and TypeScript 5.7.2+) and get scope confirmation; do not force Query v5 alone. |
| Table v7 -> v8 | `react-table`, `@types/react-table`, `useTable`, plugin hooks, `Header`/`Cell`, `cell.render(...)` | Follow the official v8 rewrite: move to `@tanstack/react-table`, `useReactTable`, row-model functions, lower-case column options, and `flexRender`. |
| Table v8 -> v9 | `useReactTable`, `get*RowModel()` table options, `sortingFns`, `filterFns`, `table.getState()` | Follow the official v9 migration: use `useTable`, declare `tableFeatures`, move row models and function registries into features, and update state access. |
| Table v8 -> v9 | Pinning APIs using `left`/`right`, `columnSizingInfo`, `sortingFn`, underscore-prefixed internals | Apply the documented logical `start`/`end`, resizing, sorting, and public-API replacements. |
| Router | Direct imports or reads of undocumented/internal router state, `RouterCore`, `RouteMatch`, or `RouterStores` members | Read every changelog entry between the installed and target versions. Router's v1 line has removed exported internals in patch releases; replace them only with the public alternatives named by the changelog. |
| Router | `tsr.config.*`, `routeTree.gen.ts`, `@tanstack/router-plugin`, `@tanstack/router-cli` | Preserve the configured `routesDirectory` and `generatedRouteTree`; update the plugin/CLI with the adapter and regenerate the route tree after install. Never hand-edit the generated file. |

Official sources:

- [TanStack Query: Migrating to v5](https://tanstack.com/query/latest/docs/framework/react/guides/migrating-to-v5)
- [TanStack Table: Migrating to v8](https://tanstack.com/table/v8/docs/guide/migrating)
- [TanStack Table: Migrating to v9 (official repository)](https://github.com/TanStack/table/blob/main/docs/framework/react/guide/migrating.md)
- [TanStack Router changelog](https://github.com/TanStack/router/blob/main/packages/react-router/CHANGELOG.md)
- [TanStack Router file-based routing configuration](https://tanstack.com/router/latest/docs/api/file-based-routing)
- [tRPC: Migrating from v10 to v11](https://trpc.io/docs/migrate-from-v10-to-v11)

## Order of operations

1. **Establish the React and TypeScript floors.** Resolve the target packages' React peer floor
   and any TypeScript 4.7+ prerequisite before the TanStack version bump.
2. **Bump one TanStack family at a time.** Pass all confirmed direct members of that family to
   `typescript_upgrade_package_dependency_group`, with each package resolving its own target.
   Query, Table, and Router are separate calls unless the scan already placed them together and the
   user confirmed the whole group. For Table v7, replace the legacy `react-table` and
   `@types/react-table` packages as documented above instead of upgrading them in place.
3. **Install before source migration.** Call `typescript_install_dependencies`; do not use
   `--force` or legacy-peer-deps to bypass an incompatible React floor.
4. **Apply the official family migration.**
   - **Query v4 -> v5:** run the documented codemod from the installed package. For TypeScript:
     `npx --yes jscodeshift@latest ./path/to/src --extensions=ts,tsx --parser=tsx --transform=./node_modules/@tanstack/react-query/build/codemods/src/v5/remove-overloads/remove-overloads.cjs`.
     Review its output and manually fix every skipped/ambiguous call. Run the project's formatter
     or lint fix afterward because the official guide warns the codemod can change formatting.
   - **Table v7 -> v8:** perform the official package/API rewrite. This is architectural and is not
     safe for a broad regex.
   - **Table v8 -> v9:** migrate to `useTable({ features, columns, data })`. Prefer explicit
     `tableFeatures`; `stockFeatures` is an acceptable temporary migration shortcut.
     `useLegacyTable` is deprecated and must not be the final state. Confirm the bundler and
     TypeScript configuration support v9's ESM-only, ES2022 output.
   - **Router:** read the official changelog across the exact installed-to-target range, replace
     affected exported internals with the documented public API, then run the project's Router
     plugin or CLI so `routeTree.gen.ts` matches the upgraded packages.
   - **tRPC integration:** if `@trpc/react-query` v10 blocks Query v5, do not downgrade Query
     silently or edit around the incompatible types. Ask to include the official tRPC v11
     migration. If approved, upgrade the tRPC package set together, establish its React 18.2 and
     TypeScript 5.7.2 floors, and apply the tRPC migration guide; otherwise report the Query major
     as blocked.
5. **Compile and run the standard verify loop.** Re-read the relevant official migration section
   for each remaining error category instead of adding casts or deleting generated files.

## Blockers

- **React below the target adapter's peer floor:** upgrade React first. Do not force-install.
- **Table v9 build target:** v9 is ESM-only and targets ES2022. A CommonJS-only or older-target
  toolchain may need a separate bundler/runtime modernization; report that explicitly rather than
  rewriting Table APIs while the package cannot load.
- **Router generated-file churn:** a missing or stale Router plugin/CLI configuration blocks a
  trustworthy upgrade. Restore generation from `tsr.config.*`; never manually patch
  `routeTree.gen.ts`.
- **Use of removed internals:** Router and Table internal APIs require a contextual refactor to
  documented public state/methods. Do not hide these errors with `as any`.

## Validation

- Run `typescript_compile_package` and resolve all new TypeScript errors.
- Run the project's **existing** focused tests for Query hooks/cache behavior, Table sorting/
  filtering/pagination/selection, and Router navigation/loaders/search params as applicable.
- Do not install Jest, Vitest, ts-jest, or another test framework solely to manufacture validation
  for this dependency upgrade. If the existing test/build/runtime path is unavailable because of
  environment or credentials, record the validation as blocked or inconclusive instead of adding
  unrelated test tooling and lockfile churn.
- Call `typescript_validate_runtime`. These libraries manage asynchronous state and UI behavior;
  compile success alone cannot detect stale Query transitions, broken Table interactions, or
  Router navigation and generated-route regressions.
- For Router, confirm the generated route tree is clean after a fresh generation and that no
  source imports a deleted internal member.

## Telemetry

After the TanStack upgrade attempt (success or failure), call `typescript_report_telemetry` once:

- `eventType`: `"group_upgrade"`
- `group`: `"tanstack"`
- `sessionId`: from the scan response
- `success`: whether install, compile, and required runtime validation passed
- `fromVersion`: starting major of the primary requested family
- `toVersion`: target major of the primary requested family
- `strategy`: `"single-shot"`
- `codemodsRun`: `1` when the Query v5 codemod ran; otherwise `0`
- `failureReason`: if failed, e.g. `"react_peer_floor"`, `"table_toolchain_blocker"`,
  `"router_codegen_failed"`, or `"compile_errors_remaining"`

This is not the terminal event. Return to the calling workflow, which finishes with
`typescript_write_upgrade_summary`.
