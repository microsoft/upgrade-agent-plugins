# Runtime Validation

Validates that the project still runs correctly after the upgrade by replaying a project-specific eval plan via `typescript_validate_runtime`. Covers every project type (webapp, server, CLI, Electron, library, framework, plugin).

> **Runtime validation is mandatory** whenever `featureFlags.validateRuntime` is true: call `typescript_validate_runtime` once in Phase 1 (baseline) and once in Phase 3 (post-upgrade) — same plan, two endpoints. The baseline is enforced: `typescript_upgrade_package_dependency_group` returns `runtime_baseline_missing` until it has run.

## Eval plan basics

A plan looks like this (full schema lives under the `create-eval-plan` skill):

```jsonc
{
  "projectType": "webapp",
  "setup":   [ { "command": "npm", "args": ["install"] } ],
  "assertions": [
    { "name": "tsc-builds", "kind": "process",
      "command": "npx", "args": ["tsc", "--noEmit"],
      "verificationMethod": "exit-code", "expected": "0" }
  ]
}
```

Three assertion kinds: `process` (spawn a command, check exit code or stdout), `http-probe` (start a server, GET URLs), `playwright-route` (replay a saved Playwright script).

For plans with `playwright-route` assertions, declare the dev server once at the top level via `devServer` — the runner starts it before assertions and kills it (process tree) after. You do not need to start or stop a dev server yourself.

## When there is no plan

The tool returns instructions telling you to author one. **Invoke the `create-eval-plan` skill immediately — do not ask the user whether to proceed.** After the skill saves the plan, re-call `typescript_validate_runtime`. Do not hand-write a plan from this skill.

## Baseline (Phase 1)

Call `typescript_validate_runtime` with `packageDirectory`. The tool:
1. Loads the plan (or returns guidance to author one).
2. Runs `setup[]`, then runs each assertion.
3. Persists the result to `.tsupgrader/runtime-validation/baseline-result.json`.

Do not pass `resetBaseline` on the first call — it's only for discarding an existing baseline.

**A red baseline is not automatically a problem — diagnose *why* before reacting.** Two cases:
- **Plan defect** (the assertion is wrong, not the project): a `tests-pass` assertion using the wrong runner/flags, an `http-probe` whose URL the dev server doesn't actually serve or that fires during dev-server warmup, too short a timeout. **Fix the plan** so the baseline is green — otherwise the comparison is meaningless.
- **Genuine pre-existing failure** (the project itself is broken before any upgrade — it doesn't build, or its tests already fail): don't upgrade on top of a broken baseline. Stop and report via `typescript_write_upgrade_summary`, recommending the user fix the failing build/tests first; regression signal measured against an already-broken baseline is unreliable. Never fabricate a fix to force it green.

**Capture this baseline before any package is upgraded.** The baseline is the *pre-upgrade* state — if you've already bumped a version or run an install for the upgrade, the baseline is contaminated and every "pre-existing failure" it records is suspect. Run it every workflow where `validateRuntime` is true (it's not optional), and run it before Phase 2, not after. If you realize you upgraded first, reset to the pre-upgrade state and re-baseline; if you can't, say so in the summary rather than presenting a post-upgrade run as the baseline.

## Post-upgrade (Phase 3)

Call `typescript_validate_runtime` with `packageDirectory`. The tool reruns the same plan and compares per-assertion:

- **Regression** (was-pass → now-fail) — surfaced for you to triage and fix.
- **Pre-existing failure** (was-fail → still-fail) — ignored.
- **Improvement** (was-fail → now-pass) — informational.

The response includes baseline and post-upgrade output samples side by side.

## Plan-hash mismatch

If the plan on disk has been edited between baseline and post-upgrade, the tool aborts and tells you to pass `resetBaseline: true` to start over. Do not edit the plan mid-upgrade.

## Retry loop

On regressions:
1. Fix the application code (correlate failures against the packages you just upgraded).
2. Call `typescript_compile_package` to verify your fix compiles.
3. Call `typescript_validate_runtime` again with `retryCount` incremented.
4. Iterate up to 3 times. If still failing, revert the upgrade.

The plan is not regenerated between retries — replay determinism is the point.
