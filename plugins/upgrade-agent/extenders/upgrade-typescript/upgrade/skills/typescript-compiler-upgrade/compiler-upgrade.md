# TypeScript Migration

Upgrade TypeScript itself through each major version incrementally before upgrading other packages.

`@typescript/native-preview` IS TypeScript 7 — same compiler, rewritten as a native binary. The end goal is always `@typescript/native-preview` (7.x).

## Important Warnings

⛔ **DO NOT call `typescript_upgrade_package_dependency_group` for TypeScript.** Upgrade TypeScript manually.

✅ **You ARE authorized to install pre-release/experimental TypeScript versions** — including `@typescript/native-preview`.

🚫 **ONLY fix actual compilation errors. Do NOT change `tsconfig.json` settings unless fixing a specific compiler error.**

⚠️ **ALWAYS attempt to fix errors before reverting.** Even with many errors, try fixing a few — they often have a simple, repeatable solution.

## Upgrade Path

Upgrade through this sequence, starting at whatever version is higher than where you started:

```
4.9 → 5.0 → 5.5 → 5.9 → 6.0 → 7.0
```

Do NOT skip major versions. If `currentTypeScriptVersion` is already 7.x, the project has `@typescript/native-preview` — upgrade it directly to `targetTypeScriptVersion`.

Don't proceed to the next version until the build is clean at the current one. Repeat until you've reached the latest version, which may be a `.minor` version (e.g. `7.1`) — use `targetTypeScriptVersion` from the scan results as the final target.

## For Each Version Hop

1. Read the version-specific guide for the hop:
   - **Upgrading to 5.0 (from 4.x)**: [4to5.md](./4to5.md)
   - **Upgrading within 5.x and to 6.0**: [5to6.md](./5to6.md)
   - **Upgrading to 7.x**: [6to7.md](./6to7.md)
2. Install the target version using the command from the guide.
3. Call `typescript_compile_package` to check for errors.
4. Fix errors using the guide's error reference. Re-compile after each batch.
5. Iterate until the build is clean.
6. Call `typescript_report_telemetry` with:
   - `eventType`: `"typescript_migration"`
   - `success`: whether this hop compiled cleanly
   - `fromVersion`: the version before this hop (e.g., `"5.4.5"`)
   - `toVersion`: the version after this hop — for the 7.x hop, use `targetTypeScriptVersion` from the scan results
   - `upgradeSteps`: `1` (one hop in the upgrade sequence)
7. Proceed to the next version.

After all hops complete, return to the calling workflow. In the rare case you must stop early (a hop fails unrecoverably or the user stops you), still call `typescript_write_upgrade_summary` once with the same `rootDirectory` / `sessionId` and a `content` string noting which hops succeeded, which failed, and the resulting TypeScript version.
