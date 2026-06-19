---
name: dotnet-version-upgrade
description: Upgrade .NET projects to newer .NET versions, including guidance on current release status, support lifecycle (LTS/STS), and recommended upgrade targets.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: high
  weight: 10000
  traits: (.NET|CSharp|VisualBasic|DotNetCore) & !WebForms
  scenarioTraitsSet: [.NET]
  post-completion:
    suggest-scenarios:
      - aspire-integration
      - aspire-version-upgrade
      - migrating-ef6-code-first-to-ef-core
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

```
┌──────────────────────────────────────────────────┐
│ 0. PRE-INITIALIZATION                            │
│    Gather target framework defaults              │
│    → Uses: scenario-initialization system skill  │
│    → Tool: get_dotnet_upgrade_options            │
└───────────────────────┬──────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────┐
│ 1. ASSESSMENT                                    │
│    Analyze solution, identify risks              │
│    → Creates: assessment.md                      │
└───────────────────────┬──────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────┐
│ 2. PLANNING                                      │
│    Create upgrade plan based on assessment       │
│    → Creates: plan.md, scenario-instructions.md  │
└───────────────────────┬──────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────┐
│ 3. EXECUTION                                     │
│    Execute tasks, validate changes               │
│    → Creates: tasks/*/task.md                    │
│    → Uses: system task-execution skill           │
└──────────────────────────────────────────────────┘
```

## Pre-Initialization

This section is used by the `scenario-initialization` system skill. It defines the scenario-specific parameters and tools for this scenario.

### Tools to Call

⛔ **Step 1**: Call `get_dotnet_upgrade_options(solutionPath, projectPath, targetFramework)` to get:
- Solution and project file paths
- Suggested target framework version
- Available target frameworks for upgrade (with support level and end-of-life dates)

⛔ **Step 2**: Present the options and get user confirmation:

- **If `confirm_options` is in your tool list** (MCP Apps supported): load [confirm-options-mcp.md](confirm-options-mcp.md) and follow it — it contains the full `confirm_options` call, JSON schema, and how to read the returned values.
- **Otherwise** (text fallback): present the options as plain text using this template, then ask the user to confirm or adjust:

  ```
  #### Target Framework
  Upgrade to: **{suggested_tfm} ({support_level})**

  Available options:
  {list of available target frameworks from get_dotnet_upgrade_options}
  ```

  Also present flow mode and (if in a git repo) working branch + commit strategy. Parse the user's reply to extract `targetFramework`, `flowMode`, `workingBranch`, and `commitStrategy`.

  **Handling parameter changes**: if the user changes the target framework, call `get_dotnet_upgrade_options` again to validate the choice against available frameworks. Do NOT re-run `generate_dotnet_upgrade_assessment` — reuse the existing assessment data.

**Step 3** — Proceed with the confirmed values, passing `targetFramework` to `initialize_scenario` and subsequent assessment tools.

## Stage Instructions

⛔ **IMPORTANT**: Load each stage's instructions file **only when entering that stage** (not all upfront).

### Stage 1: Assessment
**When entering this stage, load**: [assessment.md](assessment.md) *(read completely - contains 3 required steps)*

Analyzes the solution and produces the assessment document:
- Solution analysis and dependency mapping
- Package update and vulnerability detection
- Risk identification

### Stage 2: Planning
**When entering this stage, load**: [planning.md](planning.md) *(read completely - contains 5 steps)*

Confirms upgrade options (including strategy) and creates the plan:
- Upgrade options evaluation — strategy, project approach, compatibility, modernization choices
- User reviews and confirms all options in a single upgrade-options.md file
- Task breakdown following chosen strategy's rules
- Dependency ordering and phasing
- Strategy and execution constraints persisted in scenario-instructions.md

### Stage 3: Execution
**When entering this stage, load**: [execution.md](execution.md) *(read completely - contains 6 sections)*

Executes the upgrade tasks using the system task execution skill:
- Reads execution constraints from scenario-instructions.md (distilled during planning)
- Follows plan.md task order (which encodes the strategy structure)
- Decomposition rules in execution.md supplement the system task-execution skill
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
