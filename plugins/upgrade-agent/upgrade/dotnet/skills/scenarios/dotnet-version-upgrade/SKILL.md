---
name: dotnet-version-upgrade
description: Upgrade .NET projects to newer .NET versions, including guidance on current release status, support lifecycle (LTS/STS), and recommended upgrade targets.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: high
  weight: 10000
  traits: .NET|CSharp|VisualBasic|DotNetCore
  scenarioTraitsSet: [.NET]
  post-completion:
    suggest-scenarios:
      - aspire-integration
      - aspire-version-upgrade
      - migrating-ef6-code-first-to-ef-core
      - winforms-feature-adoption
      - dotnet-arm64-migration
    suggest-actions:
      - generate-report
---

# .NET Version Upgrade Scenario

Upgrade .NET projects from their current target framework to a newer version of .NET.

## Current Facts

<!-- Last updated: 2025-11-12 -->

| Version | Status | Support Level | End of Life |
|---------|--------|---------------|-------------|
| .NET 10 | GA | LTS | 2028-11-14 |
| .NET 9 | GA | STS | 2026-11-10 |
| .NET 8 | GA | LTS | 2026-11-10 |
| .NET 11 | Preview | — | 2030-11-12 (projected) |

> **Staleness check:** If the user asks about a version listed as **Preview** above, verify its current status using an internet search tool before answering — it may have shipped since this data was last updated.

## Scenario Overview

**Goal**: Migrate one or more .NET projects to a target framework version while maintaining functionality.

## Workflow Stages

Run these stages in order:

0. **Pre-Initialization** — Confirm target framework + source-control + flow parameters, then set up source control, call `initialize_scenario`, and write `scenario-instructions.md`. Consumed during pre-initialization by the dedicated `DotnetVersionScenarioInitializer` gatherer. Tool: `get_dotnet_upgrade_options`.
1. **Assessment** — Analyze the solution and identify risks. Creates `assessment.md`.
2. **Planning** — Create the upgrade plan based on the assessment. Creates `plan.md`.
3. **Execution** — Execute tasks and validate changes. Creates `tasks/*/task.md`. Uses the executor's execution steps.

## Pre-Initialization

This section is consumed during pre-initialization by the dedicated `DotnetVersionScenarioInitializer`
gatherer. It defines the scenario-specific parameters and tools for this scenario.

### Tools to Call

**Step 1**: Call `get_dotnet_upgrade_options(solutionPath, projectPath, targetFramework)` to get:
- Solution and project file paths
- Suggested target framework version
- Available target frameworks for upgrade (with support level and end-of-life dates)

**Step 2**: Assemble the `confirmFields` list — one entry per user-confirmable parameter, in
display order: **Target Framework first** (suggested value first, then the available frameworks
from `get_dotnet_upgrade_options`), then flow mode, then — **only in a git repo** — the working
branch and commit strategy. These feed the single combined confirmation.

  **One combined confirmation:** the framework is **one** parameter among several. It MUST appear
  in the same single confirmation — alongside flow mode, source-control (git only), and any other
  gathered parameters — never as its own separate question.

**Step 3** — With `confirmFields`, git facts, and `initializeDescription` assembled, proceed to the
combined confirmation and then to `initialize_scenario`.

## Stage Instructions

**IMPORTANT**: Load each stage's instructions file **only when entering that stage** (not all upfront).

### Stage 1: Assessment
**When entering this stage, load**: [assessment.md](assessment.md) *(read completely - contains 3 required steps)*

Analyzes the solution and produces the assessment document:
- Solution analysis and dependency mapping
- Package update and vulnerability detection
- Risk identification

**Assessment gatherer:** this stage is handled by the dedicated `DotnetVersionAssessor` (the generic
**Assessor** is the fallback if the dedicated one is unavailable or returns `BLOCKED`). It works from
these inputs:
- `scenario id`, repo/workspace path, and the workflow folder
- the assessment parameters from pre-init: `inputMode`, `paths`, `targetFramework`
- the `scenario-instructions.md` path (fallback source)

### Stage 2: Planning
**When entering this stage, load**: [planning.md](planning.md) *(read completely - contains 5 steps)*

Confirms upgrade options (including strategy) and creates the plan:
- Upgrade options evaluation — strategy, project approach, compatibility, modernization choices
- **Planning gate**: upgrade options are evaluated and returned for a single combined
  confirmation; the confirmed selections are persisted before the plan is generated
- Task breakdown following chosen strategy's rules
- Dependency ordering and phasing
- Strategy and execution constraints persisted in scenario-instructions.md

### Stage 3: Execution
**When entering this stage, load**: [execution.md](execution.md) *(read completely - contains 7 sections)*

Executes the upgrade tasks using the executor's core task-execution steps:
- Reads execution constraints from scenario-instructions.md (distilled during planning)
- Follows plan.md task order (which encodes the strategy structure)
- Decomposition rules in execution.md supplement the core execution steps
  (stub resolution subtasks, package replacement research, multi-targeting mechanics)

## Success Criteria

- [ ] All projects target the specified framework version
- [ ] All package updates applied (no security vulnerabilities)
- [ ] Solution builds without errors
- [ ] All tests pass
- [ ] No dependency conflicts

## Error Handling

**Build errors after upgrade**:
1. Identify the failing project
2. Check for breaking changes in the framework version
3. Apply fixes from known patterns
4. If stuck, ask user for direction

**Circular dependencies**:
1. Identify the cycle
2. Recommend architectural changes to break the cycle
3. Proceed with user approval

**Incompatible packages**:
1. Check for package updates that support target framework
2. If no compatible version, document as blocking issue
3. Suggest alternatives or workarounds
