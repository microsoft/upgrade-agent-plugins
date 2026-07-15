---
name: generating-upgrade-test-baseline
description: >
  Generates behavior-locking tests before a .NET upgrade using the external dotnet-test plugin. Use when
  executing a generate-test-baseline task for projects with upgrade compatibility risks.
metadata:
  traits: (CopilotCli|VsCode|GitHubCopilotApp) & (.NET|CSharp|VisualBasic|DotNetCore)
  discovery: lazy
  importance: high
---

# Generating an Upgrade Test Baseline

Use the external `code-testing-generator` agent to create tests that lock in current behavior before
the upgrade changes production code. The generator owns test-framework detection, test-project
selection or creation, implementation, build, test, fix, lint, and final validation.

## Prerequisite

Read the `## Test Baseline` status from `scenario-instructions.md`. If it is not `enabled`, complete
`generate-test-baseline` as skipped without invoking the generator.

The `code-testing-generator` agent from the `dotnet-test` plugin is required. If it is unavailable,
load `managing-dotnet-test-installation` and follow it before continuing.

## Requirements

- Generate tests only for production projects, never for test projects.
- Do not change production code while establishing the baseline.
- Keep generation within the project scope recorded in `scenario-instructions.md`.
- Treat `API.0003` behavioral changes as must-cover upgrade risks.

## Prepare the Generator Brief

1. Read the `## Test Baseline` block from `scenario-instructions.md`. Use its `Projects` list as the
   exact production-project scope.
2. For each project, query the assessment for:
   - `API.0003` issues as must-cover behavioral changes.
   - `API.0002` and `API.0001` issues as priority seeds.
   - The issue location, code sample, and documentation URL when available.
3. Invoke `code-testing-generator` with a goal-oriented brief:

```text
## Goal
Create a regression safety-net before upgrading {ProjectScope} from {current TFM} to {target TFM}.
Lock in current observable behavior so post-upgrade validation can detect regressions.

## Scope
Generate tests only for: {ProjectScope}
Do not modify production code.

## Must cover
{API.0003 call sites and documented behavior changes}

## Priority seeds
{API.0002 and API.0001 call sites}

## Additional research
Within the project scope, identify other behavior likely to change during this upgrade, including
package behavior, serialization, culture and formatting, date/time, ordering, hashing, regex,
encoding, file I/O, and concurrency. Prefer depth on plausible upgrade risks over broad coverage.
```

The brief supplies upgrade-specific risk context; it does not replace the generator's own research,
planning, or validation pipeline.

## Integrate the Result

After `code-testing-generator` succeeds:

1. Update `scenario-instructions.md`: under `## Test Baseline`, add the project-file path of every
   test project used beneath `Test projects`.
2. If the generator created a test project:
   - Confirm the project is registered in the repository's solution file.
   - Update `plan.md`: add the new project-file path to the applicable upgrade task description so the
     normal conversion flow retargets it to the target framework before `validate-test-baseline`.
     Do not add scope details to `tasks.md`; it tracks task status only.
3. Complete the task when the generator reports that the generated tests build and pass on the
   pre-upgrade code.

## Generation Failure

Failure to establish a green baseline must not block the upgrade. Follow the
[Test Coverage generation-failure flow](../../../scenarios/dotnet-version-upgrade/upgrade-options/test-coverage.md#generation-failure)
for the user decision and required option-state updates.
