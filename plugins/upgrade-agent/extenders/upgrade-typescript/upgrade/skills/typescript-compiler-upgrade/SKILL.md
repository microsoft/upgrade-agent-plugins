---
name: typescript-compiler-upgrade
description: Upgrade the typescript npm package (the TypeScript compiler) to a newer version through incremental major-version migrations. Use this when asked to upgrade, update, or migrate typescript itself — especially to TypeScript 7 or @typescript/native-preview. Do NOT use this for upgrading other npm packages (use typescript-dependencies-upgrade instead).
---

You are a skilled TypeScript developer specializing in migrating projects across major TypeScript versions. Your role is to upgrade TypeScript itself through each major version incrementally, fixing compilation errors at each step.

**You have access to MCP tools from the JSTSUpgradeAssistant server.** Use them for dependency scanning, compilation, and telemetry. Do not manually edit `package.json` dependency versions for packages other than TypeScript — this skill only migrates the TypeScript compiler.

## Phase 0 — Detect Current Version

1. **Call `typescript_scan_dependencies`** with:
   - `rootDirectory` — the repository root.
   - `requestedPackages: ["typescript"]` — REQUIRED. This skill only ever upgrades the typescript package.
   - `skill: "typescript-compiler-upgrade"` — REQUIRED.
2. **Save the `sessionId`** from the response — pass it to every subsequent MCP tool call.
3. If `typeScriptMigrationNeeded` is `false`, inform the user that TypeScript is already up to date and stop. If true, the response also includes `currentTypeScriptVersion` and `targetTypeScriptVersion`.

## Phase 1 — Baseline

1. **Call `typescript_install_dependencies`** with `rootDirectory` and `sessionId` to ensure dependencies are installed.
2. **Call `typescript_compile_package`** with `rootDirectory`, `packageDirectory` (use the repository root unless upgrading a specific package in a monorepo), and `sessionId` to verify the project builds before making changes.
3. If `validateRuntime` is true, run baseline runtime validation per [runtime-validation.md](../typescript-dependencies-upgrade/runtime-validation.md).
4. If the baseline build fails, inform the user of pre-existing errors before proceeding.

## Phase 2 — Migrate

Read [compiler-upgrade.md](./compiler-upgrade.md) and follow its instructions to upgrade TypeScript through each major version incrementally. Pass the `sessionId` from Phase 0 to every subsequent MCP tool call.

## Phase 3 — Validation

After all version hops are complete, run validation to ensure the migration didn't introduce runtime regressions:

1. **Post-upgrade compile — REQUIRED, do not skip.** Always call `typescript_compile_package` with `rootDirectory`, `packageDirectory`, and `sessionId`. This is what locks in the post-upgrade compile-error count and lets the workflow be measured. **Even if `typescript_verify_upgrade` already reported "complete" during the version hops, you must still call `typescript_compile_package` here** — the verify-loop only updates per-package state; the workflow-level post-upgrade snapshot is recorded only by this tool. Skipping this step forces the workflow into the `inconclusive` bucket on dashboards.
2. **Runtime validation** — If `validateRuntime` is true in the scan results: read [runtime-validation.md](../typescript-dependencies-upgrade/runtime-validation.md). This catches issues that compilation alone misses — runtime type errors, module resolution failures, or changed emit behavior.

## Phase 4 — Summary

After all version hops are complete:

1. Call the `typescript_write_upgrade_summary` MCP tool with `rootDirectory` and a `content` string. Pass the same `sessionId`. The tool emits the workflow/summary observation event automatically. In the `content`, summarize for the user:
   - Starting TypeScript version and ending TypeScript version.
   - Which version hops succeeded and which failed.
   - Any notable edits you had to make.
   - Bugs in usercode you found (see [Usercode Bugs](#usercode-bugs)) — offer to remove the `// @ts-ignore` comments you added.
   - If you had to stop before reaching the latest version, explain what happened.
2. Present the returned summary to the user.

Call `typescript_write_upgrade_summary` exactly once per workflow. In the rare case you must stop early (unrecoverable error or explicit user stop), still call it with `content` describing the partial state.

## Key Principles

1. **Preserve valid code.** Every change you make must produce syntactically valid TypeScript (`.ts` and `.tsx`).
2. **Run ONE tool at a time.** Wait for each MCP tool to complete before starting the next.

## Forbidden Fixes

Do not paper over upgrade errors with suppression escape hatches. Specifically:

- Do not use `ignoreDeprecations` to silence errors on the way to a target version that won't support it (TypeScript 7 removes the deprecated options entirely). See the per-version guides for when `ignoreDeprecations` is acceptable.
- Do not add `// @ts-ignore`, `// @ts-expect-error`, or `// @ts-nocheck` to silence new errors.
- Do not use `any` (or widen a type to `any`) just to make an error go away.
- Do not disable `tsconfig.json` strictness flags (`strict`, `noImplicitAny`, `strictNullChecks`, `skipLibCheck`, etc.).

If a real fix is genuinely out of scope, revert the upgrade for that package rather than committing a suppression. The lone exception is a genuine pre-existing usercode bug — see below.

## Common Issues

All versions of TypeScript may include updates to the DOM. These are not specifically documented anywhere. Use your best judgment to determine how to fix these, keeping in mind that you should not be making runtime-affecting changes unless absolutely justified.

## Usercode Bugs

Newer versions of TypeScript may sometimes find *unambiguous problems* in the user's code that were not caught by previous versions. Sometimes you will be able to easily determine the correct fix (i.e. what was intended). If you can't determine the correct fix, add a temporary `@ts-ignore` comment to suppress the error so you can continue with the upgrade process:

```ts
// @ts-ignore BUG: This is always a runtime error! Fix as appropriate depending on intended meaning
const p = "foo" in 42;
```

When you're done, remove the `@ts-ignore` part of the comment, but leave behind the explanation of why the code is wrong. Report all bugs you found in the summary.

This is the only acceptable use of `@ts-ignore` — for genuine pre-existing usercode bugs, **not** for silencing errors caused by the upgrade itself (see [Forbidden Fixes](#forbidden-fixes)).

## `@types` dependencies

You may need to update `@types` dependencies alongside the main TypeScript version. Check the `package.json` for any `@types/` entries and update them to the latest version compatible with the corresponding core dependency.
