# TypeScript Migration

Upgrade TypeScript itself through each major version incrementally before upgrading other packages.

TypeScript 7.0 ships as the `typescript` package (compiler binary `tsc`), the same as earlier majors — a native (Go) port that is behavior-compatible with 6.0. The end goal is the exact `targetTypeScriptVersion` returned by the scan, preserving the user's requested version or major.

## Important Warnings

⛔ **DO NOT call `typescript_upgrade_package_dependency_group` for TypeScript.** Upgrade TypeScript manually.

**Use published stable targets only.** Do not install nightlies, `typescript@next`, or a version discovered from `@typescript/native-preview`. If the requested stable target is unavailable, report the blocker rather than choosing a different target.

🚫 **ONLY fix actual compilation errors. Do NOT change `tsconfig.json` settings unless fixing a specific compiler error.**

⚠️ **ALWAYS attempt to fix errors before reverting.** Even with many errors, try fixing a few — they often have a simple, repeatable solution.

## Upgrade Path

Use the ordered exact `typeScriptUpgradeVersions` returned by the scan. Intermediate majors resolve to published stable versions in the project's configured registry; the final entry is exactly `targetTypeScriptVersion`. For example, a 5.x to 7.0.2 request may resolve to `["6.0.2", "7.0.2"]`.

Do NOT skip major versions. For a same-major upgrade, the list contains only the exact final target. In a monorepo, skip entries below a package project's current version; never downgrade a package project.

Don't proceed to the next version until the build is clean at the current one. Stop at the resolved target, even if a newer minor, major, or prerelease is available.

## For Each Version Hop

1. Read the version-specific guide for the hop:
   - **Upgrading to 5.0 (from 4.x)**: [4to5.md](./4to5.md)
   - **Upgrading within 5.x and to 6.0**: [5to6.md](./5to6.md)
   - **Upgrading to 7.x**: [6to7.md](./6to7.md)
2. Install the exact version for this hop: `npm install -D typescript@<hopVersion>`, `yarn add -D typescript@<hopVersion>`, or `pnpm add -D typescript@<hopVersion>`, using the project's declared package manager. Substitute the exact scan-resolved version; never use a bare major, `latest`, or `next`.
3. Call `typescript_compile_package` to check for errors.
4. Fix errors using the guide's error reference. Re-compile after each batch.
5. Iterate until the build is clean.
6. Call `typescript_report_telemetry` with:
   - `eventType`: `"typescript_migration"`
   - `success`: whether this hop compiled cleanly
   - `fromVersion`: the version before this hop (e.g., `"5.4.5"`)
   - `toVersion`: the exact version after this hop, verified from the installed `typescript` package
   - `upgradeSteps`: `1` (one hop in the upgrade sequence)
7. Proceed to the next version.

After all hops complete, return to the calling workflow. In the rare case you must stop early (a hop fails unrecoverably or the user stops you), still call `typescript_write_upgrade_summary` once with the same `rootDirectory` / `sessionId` and a `content` string noting which hops succeeded, which failed, and the resulting TypeScript version.
