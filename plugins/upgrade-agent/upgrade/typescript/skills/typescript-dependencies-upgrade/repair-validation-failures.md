# Repairing Dependabot validation failures

This guidance is currently only for the hidden Dependabot validation agent.
Normal dependency and compiler upgrades use their existing repair workflows.

Read [upgrade-packages.md](./upgrade-packages.md), but reuse only its
error-resolution discipline: group related diagnostics, inspect affected files,
prefer fixes that address the root cause, limit failed regex attempts, fall
back to direct edits, and revert failed repair attempts. Do not call its upgrade
or verification tools, select target versions, iterate upgrade groups, run its
audit phase, or follow instructions to upgrade to latest.

Do not call `typescript_upgrade_package_dependency_group` or
`typescript_verify_upgrade` in this scenario. Those tools require workflow
state created by `typescript_upgrade_package_dependency_group`. Dependabot's
update is already applied, so use these substitutions:

- For dependency-selection changes, update `package.json`, then call
  `typescript_install_dependencies` with `scenario: "dependabot"`. The tool
  runs `npm install` and regenerates the lockfile; do not edit the lockfile
  directly.
- For compile repairs, apply a focused regex or direct edit and call
  `typescript_compile_package` with `scenario: "dependabot"` after each attempt.
- For build, test, startup, HTTP, or browser failures, rerun the narrow failing
  assertion, then rerun the complete standalone runtime-validation plan.

Before editing, reproduce the failure, compare it with the pre-Dependabot
commit, and inspect installed package metadata and consuming source. Dependabot
already selected and applied the update, so do not load package-selection,
package-family upgrade, or compiler-upgrade guidance. Do not repair unrelated
pre-existing failures.

## Resolve peer-dependency failures

When installation reports `ERESOLVE` or another peer-resolution failure:

1. Identify the exact dependent package, its installed or selected version, the
   required peer range, and the conflicting manifest or lockfile version.
2. Query the configured registry for the selected package's published
   `peerDependencies` and for candidate versions of peers already present in the
   project. Do not change registry routing or authentication.
3. Preserve the Dependabot package and its minimum secure version. Prefer
   aligning an existing peer or companion package already in the same
   compatibility set. Change the Dependabot selection only when no compatible
   peer version exists, and then move it forward to a compatible secure release
   rather than downgrading it.
4. Make the smallest manifest edit, call
   `typescript_install_dependencies` with `scenario: "dependabot"` to regenerate
   the lockfile, and inspect the resulting dependency-file diff.
5. Never use `--force`, `--legacy-peer-deps`, broad overrides, or unrelated
   package upgrades to manufacture a successful install. If no compatible set
   exists within the worker's retry limit, report
   `peer_dependency_resolution_failed`.

Preserve the Dependabot security boundary defined by the parent agent. Do not
manufacture a pass with broad type suppression, disabled tests, weakened
assertions, deleted dependencies, or unrelated changes.
