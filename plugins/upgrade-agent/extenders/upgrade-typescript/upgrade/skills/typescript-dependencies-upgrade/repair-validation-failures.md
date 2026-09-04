# Repairing Dependabot validation failures

This guidance is currently only for the hidden Dependabot validation agent.
Normal dependency and compiler upgrades use their existing repair workflows.

Read [upgrade-packages.md](./upgrade-packages.md) and reuse its approach to
diagnosing and fixing errors: group related diagnostics, inspect affected files,
prefer fixes that address the root cause, limit failed regex attempts, fall
back to direct edits, and revert failed repair attempts.

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
commit, read all applicable package-family guidance, and inspect installed
package metadata and consuming source. Do not repair unrelated pre-existing
failures.

Preserve the Dependabot security boundary defined by the parent agent. Do not
manufacture a pass with broad type suppression, disabled tests, weakened
assertions, deleted dependencies, or unrelated changes.
