# Test Coverage

**Category**: Reliability

**Applicable when**:
- The assessment recommends coverage for at least one project. The assessment computes
  this per project and exposes it via `query_dotnet_assessment`:
  - **global** `summary` → `Projects recommended for Test Coverage: {N}` (the
    `TestCoverageRecommendedProjectCount` field). Applicable when `N > 0`.
  - **per-project** `summary` (scope `global/project`) → `Test Coverage recommended: true`
    (the `TestCoverageRecommended` field, with `Difficulty` and `API issues` shown alongside).
  - The assessment's `assessment.md` "Projects Compatibility" table also shows a **Test Coverage**
    column (`🧪 Recommended`) per project.

  A project is flagged when its **Difficulty** is `Medium`/`High` **or** it has any **API issues**
  (breaking / incompatible / behavioral-change APIs). **Test projects are excluded** — coverage is
  generated for production code, not for test projects.

**The `dotnet-test` plugin's availability does NOT gate whether this option is offered** — only *how*
**Generate** is fulfilled (see "Options" and "Generate flow"):
- If the `code-testing-generator` agent is **available**, **Generate** runs it directly.
- If it is **not available**, choosing **Generate** first prompts the user to install the `dotnet-test`
  plugin via the host-appropriate steps in `managing-dotnet-test-installation`. If the user declines,
  or the host can't install it, **Generate** falls back to **Skip**.

**Not applicable when**:
- The assessment recommends coverage for **no** project
  (`TestCoverageRecommendedProjectCount == 0`) — no behavior risk to guard.

**Default logic**:
- Default to **Skip** (disabled) — even when the assessment flags one or more projects. This is
  **opt-in**: still show the option so the user can turn it on, but do not enter the test stage
  unless they explicitly choose **Generate**. Generating tests adds extra time and tokens, so it is
  off by default.
- When flagged (`TestCoverageRecommendedProjectCount > 0`), present **Skip** as the selected default
  and note that **Generate** is available and recommended for higher per-project Difficulty
  (Medium/High) / API-issue counts, so the user can opt in with eyes open.

**Options**:
- **Generate** — before the upgrade, AI-generate tests that lock in current behavior for the risky
  areas and get them passing on the original code; after the upgrade, re-run them to detect
  regressions. Adds extra time and token usage. If the required test-generation plugin is unavailable,
  installation will be offered.
- **Skip** *(default)* — do not generate coverage; the upgrade proceeds without the test stage.

**Stored as**: `Upgrade Options > Reliability > Test Coverage`

## Generate flow

Apply this section only after the user confirms **Generate**.

1. Check whether `code-testing-generator` is visible to the main agent; do not probe the shell or
   file system.
2. If it is unavailable, load and follow `managing-dotnet-test-installation`. Continue only when that
   flow returns with `code-testing-generator` available. If it stops the current run or changes Test
   Coverage to **Skip**, take no further action.
3. Append this block to `scenario-instructions.md`, listing every project where
   `TestCoverageRecommended=true`:

```markdown
## Test Baseline
- Status: enabled
- Projects:
  - {recommended project path}
- Test projects:
```

The user can narrow the generation scope by deleting entries from `Projects` before execution.

4. During plan generation, inject:

   - **`generate-test-baseline`** as the first task. It loads `generating-upgrade-test-baseline`,
     invokes `code-testing-generator`, and establishes a passing pre-upgrade baseline.
   - **`validate-test-baseline`** as the last task. It re-runs the recorded baseline test projects
     after the upgrade and handles failures using the validation flow in `execution.md`.

These tasks are the exception to the rule that test work belongs to the upgrade task that caused it.

## Generation failure

If `code-testing-generator` cannot produce a green pre-upgrade baseline, explain the failure and ask
the user how they want to proceed. Suggest continuing the upgrade without generated tests, but follow
another direction if the user provides one.

If the user chooses to continue without generated tests:

1. Update `upgrade-options.md` so **Test Coverage** selects **Skip**.
2. Update `scenario-instructions.md`:
   - Under `## Upgrade Options` → `### Reliability`, change `Test Coverage` to `Skip`.
   - Under `## Test Baseline`, change `Status` to `skipped`.
3. Continue the upgrade without a test baseline.
