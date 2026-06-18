---
name: azure-migrate
description: >
  Migrates applications to Azure cloud services by starting an app modernization migration session.
  Use when user wants to migrate to Azure, start Azure migration, get help migrating an application to Azure,
  see Azure migration options, or start app modernization for Azure. Triggers for "migrate to Azure",
  "Azure migration", "move to Azure", "cloud migration", and "app modernization" requests.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: high
  weight: 10000
  traits: .NET|CSharp|VisualBasic|DotNetCore
  scenarioTraitsSet: [MigrateToAzure, .NET, DotNetCore]
---

# Azure Migration Scenario

Migrate applications to Azure using the App Modernization migration session tool.

## Scenario Overview

**Goal**: Delegate application migration to Azure by invoking the `start_app_mod_migration_session` tool, which handles assessment, planning, and execution through a dedicated migration agent.

## Workflow

This scenario delegates entirely to the migration tool. There are no separate assessment or planning stages — the tool manages the full migration workflow.

### Execute Migration

Call `start_app_mod_migration_session` to begin the migration.

The tool will start a new session with azure migration agents that will:
- Analyze the application architecture
- Identify Azure service targets
- Generate migration plans
- Execute the migration with user guidance

No additional orchestration is needed from this scenario skill.
