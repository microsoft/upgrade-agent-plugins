# Standalone Runtime Validation

Run a one-shot health check of the project as it exists now. The eval plan may build or type-check the project, run tests, start executable entry points, and exercise runtime behavior. Standalone validation reports absolute pass/fail results and writes `.tsupgrader/runtime-validation/standalone-result.json`; it never reads or writes the upgrade baseline or post-upgrade result.

## Step 1 - Resolve the target

Use the project directory the user named as `packageDirectory`. Also determine `rootDirectory`: use the repository or workspace root, or the package directory for a standalone project. Plan authoring may need both if it adds test coverage and calls `typescript_install_dependencies`.

In a monorepo, if several independently runnable packages are plausible and the user did not identify one, ask which package to validate before creating or running a plan.

## Step 2 - Run validation

Call `typescript_validate_runtime` with:

- `packageDirectory`
- `mode: "standalone"` - REQUIRED
- `retryCount: 0`

Do not pass `resetBaseline`; standalone mode has no baseline to reset.

If the tool reports that no eval plan exists, follow [plan-authoring.md](./plan-authoring.md), then call `typescript_validate_runtime` again with the same standalone arguments.

## Step 3 - Diagnose failures

Treat each failure as one of these:

- **Plan defect:** the assertion does not represent the project's real behavior, uses the wrong command or route, has an insufficient timeout, or depends on unstable output. Correct the plan, then rerun it.
- **Application failure:** the plan is valid and exposed a real build, test, startup, route, or user-flow failure. Inspect the output, make the smallest application or configuration fix that addresses the cause, then rerun validation.
- **Environment blocker:** required credentials, services, browsers, platform capabilities, or toolchain components are unavailable. Do not weaken or delete the assertion to force a pass; report the blocker.

When application code changes, use an existing project build or type-check command when available before rerunning. Do not introduce unrelated tooling just to add a second validation layer.

## Step 4 - Retry

After each plan or application fix, call `typescript_validate_runtime` again with `mode: "standalone"` and increment `retryCount`.

Try at most 3 fix-and-retry cycles. If validation still fails, stop with the project in a syntactically valid state and report the remaining failures. There is no upgrade to revert in standalone mode.

## Step 5 - Report

Summarize:

- Whether standalone validation passed, failed, or was blocked.
- Which assertions ran and which remain failing.
- Any plan, source, or configuration changes made.
- The path to `.tsupgrader/runtime-validation/standalone-result.json`.
