---
name: dotnet-framework-version-upgrade
description: >
  Upgrade .NET Framework projects to .NET Framework 4.8.1 (net481),
  staying on full .NET Framework without migrating to modern .NET (net8.0+).
  Use when user explicitly asks to upgrade to .NET Framework 4.8.1,
  upgrade to the latest .NET Framework version, or stay on full/Windows .NET Framework.
  Preserves legacy vs SDK-style project format unless the user explicitly requests SDK-style conversion.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: default
  weight: 0
  traits: (.NET|CSharp|VisualBasic)&DotNetFramework
  scenarioTraitsSet: [.NET, DotNetFramework]
---

# .NET Framework Version Upgrade Scenario

Upgrade .NET Framework projects from their current framework version (e.g., net472) to .NET Framework 4.8.1 (net481), staying on full .NET Framework.

## Scenario Overview

**Goal**: Upgrade one or more .NET Framework projects to net481 while maintaining functionality. Preserve each project's existing project format: legacy projects stay legacy unless the user explicitly requests SDK-style conversion, and SDK-style projects stay SDK-style.

**Target**: Always `net481` (.NET Framework 4.8.1) — the latest and final .NET Framework release.

**When to use**: User explicitly requests a .NET Framework version upgrade on Windows, asks to "stay on .NET Framework", "upgrade to 4.8.1", or "upgrade to latest .NET Framework".

**When NOT to use**: If the user wants to migrate to modern .NET (net8.0+), use the `dotnet-version-upgrade` scenario instead. If the user is invoking from a non-Windows platform, explain that this scenario is intended for Windows because full .NET Framework and its reference assemblies are Windows-only.

## Key Differences from dotnet-version-upgrade

| Concern | dotnet-version-upgrade | This scenario |
|---------|------------------------|---------------|
| **TFM XML** | SDK: `<TargetFramework>net8.0</TargetFramework>` | Legacy: `<TargetFrameworkVersion>v4.8.1</TargetFrameworkVersion>`; SDK-style Framework projects use `net481` |
| **Build tool** | `dotnet build` | `msbuild` |
| **Package management** | `PackageReference` + `dotnet add package` | `packages.config` + manual XML editing |
| **SDK-style conversion** | Mandatory first step | Not done by default — legacy vs SDK-style project format is preserved unless the user explicitly requests conversion |
| **Planning** | Strategies menu, side-by-side web, multi-targeting | Always All-at-Once or simple Bottom-Up |
| **Options** | 12 upgrade-option files evaluated | None — no configurable options |

## Workflow Stages

```
┌──────────────────────────────────────────────────────┐
│ 0. PRE-INITIALIZATION                                │
│    Target = net481 (fixed — no options tool call)    │
│    Platform = Windows                                │
│    Confirm which projects to upgrade                 │
│    → Uses: scenario-initialization system skill      │
└──────────────────────────────┬───────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────┐
│ 1. ASSESSMENT                                        │
│    → Tool: generate_dotnet_upgrade_assessment()      │
│    → Focus: NuGet compatibility, minor API changes   │
│    → Creates: assessment.md                          │
└──────────────────────────────┬───────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────┐
│ 2. PLANNING                                          │
│    → Strategy: All-at-Once (≤10 projects)            │
│                Bottom-Up by dep order (10+ projects)  │
│    → Tasks: TFM bump + NuGet retarget/update         │
│    → Creates: plan.md, scenario-instructions.md      │
└──────────────────────────────┬───────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────┐
│ 3. EXECUTION                                         │
│    → Edit TargetFrameworkVersion / TargetFramework(s) │
│    → Retarget packages.config metadata               │
│    → Build: msbuild (legacy) / dotnet build          │
│    → Creates: tasks/*/task.md, execution-log.md      │
└──────────────────────────────────────────────────────┘
```

## Pre-Initialization

This section is used by the `scenario-initialization` system skill. It defines the scenario-specific parameters and tools for this scenario.

### Tools to Call

Do not call `get_dotnet_upgrade_options` during pre-initialization; this scenario has a fixed target (`net481`) and that tool returns modern .NET targets.

Before continuing, check the current platform. If the agent is running on Linux, macOS, or another non-Windows platform, inform the user that this scenario is not intended for that environment because full .NET Framework 4.8.1 build validation depends on Windows reference assemblies and tooling. Do not start the assessment until the user switches to a Windows environment.

Confirm the project scope from the user's request or the loaded solution/project context. If all selected .NET Framework projects already target net481, inform the user and exit gracefully.

### Prompt Template

Include this in the consolidated prompt:

```
#### Target Framework
Upgrade to: **.NET Framework 4.8.1 (net481)**

Platform: **Windows required**

Project format: Preserve existing project format. Legacy projects remain legacy unless the user explicitly requests SDK-style conversion; SDK-style projects remain SDK-style.
```

### Handling Parameter Changes

- If the user asks for a different .NET Framework target, explain that this scenario targets net481 because it is the latest and final .NET Framework release.
- If the user changes the project scope, update the selected project list without changing the fixed target.
- If the user asks to migrate to modern .NET, switch to the `dotnet-version-upgrade` scenario instead.
- If the user explicitly asks to convert legacy projects to SDK-style as part of this work, treat that as an additional project-format conversion scope. Confirm it separately, then route conversion work through `sdk-style-conversion` / `converting-to-sdk-style`; do not manually rewrite project files in this scenario.
- Record in `scenario-instructions.md`: `targetFramework: net481`, `targetFrameworkVersion: v4.8.1`.

## Stage Instructions

Load each stage's instructions file only when entering that stage.

### Stage 1: Assessment
**When entering this stage, load**: [assessment.md](assessment.md) *(read completely - contains 3 required steps)*

Analyzes selected .NET Framework projects and produces the assessment document:
- Project inventory with current framework and project format (legacy vs SDK-style)
- Package management format and package compatibility signals
- Risks and recommendation for net481

### Stage 2: Planning
**When entering this stage, load**: [planning.md](planning.md) *(read completely - contains 3 required steps)*

Creates a fixed-target plan:
- All-at-Once for small project sets
- Bottom-Up dependency ordering for larger project sets
- Legacy-vs-SDK-style preservation by default
- Package metadata/version tasks when needed

### Stage 3: Execution
**When entering this stage, load**: [execution.md](execution.md) *(read completely - contains 4 sections)*

Executes the plan while preserving existing project system:
- Legacy `<TargetFrameworkVersion>` edits for legacy projects
- SDK-style `<TargetFramework>` or `<TargetFrameworks>` edits for SDK-style projects
- Legacy package metadata and restore/build validation

## Success Criteria

- All selected .NET Framework projects target .NET Framework 4.8.1 (`net481` or `v4.8.1`, depending on project system).
- Existing project formats are preserved by default: legacy projects remain legacy, and SDK-style projects remain SDK-style.
- SDK-style conversion is performed only when the user explicitly requests and confirms that additional scope.
- Package metadata and references are consistent with the new target framework.
- The upgraded solution or selected projects build successfully.
- Existing tests pass when present and runnable in the environment.

## Prerequisites

This scenario is intended for Windows only. Build validation requires the .NET Framework 4.8.1 Developer Pack/reference assemblies, which are Windows-specific. If validation fails with missing reference assemblies, install the Developer Pack before treating the upgrade as broken.

## Constraints

- Do not invoke `convert_project_to_sdk_style` for the default Framework version upgrade path. Use it only when the user explicitly requested SDK-style conversion and that conversion was planned as separate scope.
- **Never invoke** `get_dotnet_upgrade_options` — it returns only modern .NET targets.
- **Do not introduce new multi-targeting** — if an existing SDK-style project already multi-targets, preserve multi-targeting and update only the .NET Framework TFM.
- **No strategies menu** — strategy is determined by project count only.
- Use `managing-legacy-dotnet-packages` skill for package updates (not `managing-package-references`).
