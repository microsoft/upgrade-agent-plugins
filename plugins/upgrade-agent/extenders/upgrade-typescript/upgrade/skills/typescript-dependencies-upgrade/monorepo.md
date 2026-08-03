# Monorepo Handling

Monorepos contain multiple packages in a single repository, typically managed by npm workspaces, Yarn workspaces, pnpm workspaces, Lerna, Nx, or Turborepo.

## Upgrade Strategy

1. **Install at the root first** — call `typescript_install_dependencies` with the root directory to install all dependencies.
2. **Upgrade member packages one at a time** — the scan results contain multiple entries in the `packages` array. For each member package, complete the full upgrade cycle (upgrade → fix → validate) before moving to the next.
3. **Respect dependency order** — if package A depends on package B, upgrade B first.

## Common Patterns

- **Shared dependencies** — often pinned at the root and hoisted
- **Internal packages** — workspace packages that depend on each other (e.g., `"@myorg/utils": "workspace:*"`)
- **Build order** — monorepo tools often have a build/test order based on the dependency graph

## Large Monorepos: Summary Mode

For very large monorepos, `typescript_scan_dependencies` returns a partial response with `truncated: true`. Bundler-containing packages keep their full `dependencyGroups` inline as priority entries; the rest are summarized to `{ directory, groupCount, totalDependencies, containsBundlers }` without `dependencyGroups`. Packages with no updateable dependencies (very common — internal-only workspace members often have only `workspace:*` references) are omitted from the response entirely; their count is reported as `omittedPackageCount`.

When you need the full groups for a summarized package, call `typescript_scan_dependencies` again with `packageDirectory` set to that package's `directory`. The single-package response is never truncated. Do not re-call the tool with the same arguments expecting the inline groups to appear — they will not.
