---
name: aspire-version-upgrade
description: >
  Upgrade existing Aspire projects to a newer Aspire version: SDK and package versions, package
  renames, breaking API changes, AppHost format and configuration migration. Does not retarget
  projects. Triggers for "upgrade Aspire", "update Aspire version", "move to latest Aspire",
  or "move from Aspire 9 to 13".
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: medium
  weight: "9500"
  traits: .NET|CSharp|DotNetCore
  scenarioTraitsSet: ".NET"
---

# Aspire Version Upgrade Scenario

Upgrade an existing Aspire project from its current Aspire version to a newer version — handling package renames, breaking API changes, SDK format consolidation, and configuration migration.

> **This scenario is for projects that already use Aspire.** If you need to *add* Aspire to a project that doesn't have it, use the Aspire Integration scenario instead: `get_instructions(kind='scenario', query='aspire-integration')`.

### What This Scenario Covers

- **Package upgrades** — bumps all `Aspire.*` packages to the target version, and `Microsoft.Extensions.ServiceDiscovery.*` packages to the matching release (the same version through 9.x; from Aspire 13 they have their own version numbers)
- **Package renames** — handles package renames across all version transitions (see [breaking-changes.md](breaking-changes.md) for the full list)
- **Code changes** — fixes breaking API changes across all version transitions (type renames, method renames, argument reorders, fluent chain refactors) by hand-editing, guided by [breaking-changes.md](breaking-changes.md) and the compiler
- **SDK and target framework check** — verifies the minimum .NET SDK and target framework; it does not retarget projects
- **AppHost SDK consolidation** — migrates legacy `<Sdk>` child element to `Sdk=` attribute on `<Project>` (13.0+ format)
- **Configuration migration** — migrates legacy config files into the unified format introduced in newer Aspire versions (see [breaking-changes.md](breaking-changes.md) for file mapping details)

### Aspire Version / .NET Version Coupling

Each Aspire version needs a minimum .NET SDK, and a minimum target framework for the AppHost, ServiceDefaults and every project that references an `Aspire.*` package. Other projects are unconstrained.

| Aspire Version | Minimum TFM (Aspire projects) | Required SDK |
|---------------|-------------------------------|--------------|
| 8.x | net8.0 | .NET 8 SDK |
| 9.x | net8.0 (net9.0 recommended) | .NET 8 SDK or later |
| 13.x (through 13.2) | net8.0 | .NET 10 SDK |

For targets above 13.2, check each version's breaking changes with `aspire docs get whats-new-in-aspire-<major><minor>` (see [execution.md](execution.md) Step 1), including any raised minimums. This scenario raises a `global.json` SDK pin when needed but never changes target frameworks; if an Aspire project is below the minimum, it stops and suggests the .NET Version Upgrade scenario first.

> **Example prompts:** *"Upgrade my Aspire project to latest"*, *"Update Aspire to 13.2"*, *"Modernize my Aspire solution"*, *"Move from Aspire 9 to 13"*

---

## Workflow Overview

0. Pre-check — verify this is an Aspire project; detect current version
1. Assessment — inventory components, identify breaking changes, determine target
2. User configuration — confirm target version, SDK change, review scope
3. Planning — generate upgrade plan
4. Execution — check SDK and TFMs, update Aspire CLI, `aspire agent init`, update versions, apply code and file changes
5. Validation — build, run, verify dashboard, user test gate

---

## Phase 0: Pre-Check — Verify Aspire Project

Search for existing Aspire artifacts to confirm this is an Aspire project:

| Signal | Where to Look |
|--------|---------------|
| AppHost project | Any `.csproj` with `Sdk="Aspire.AppHost.Sdk"` or `<Sdk Name="Aspire.AppHost.Sdk">` or `#:sdk Aspire.AppHost.Sdk` in a `.cs`/`.csx` file |
| ServiceDefaults project | Any `.csproj` with `<IsAspireSharedProject>true</IsAspireSharedProject>` |
| Aspire config | `aspire.config.json`, `.aspire/settings.json` |
| Aspire hosting packages | `Aspire.Hosting.*` NuGet references in any project |

**If NO Aspire artifacts found:**

> This solution doesn't appear to use Aspire. Would you like to:
> 1. **Add Aspire** — set up Aspire orchestration from scratch (uses the Aspire Integration scenario)
> 2. **Cancel** — no changes
>
> If you want to add Aspire, I'll switch to the Aspire Integration scenario.

End this scenario if no artifacts found.

**If Aspire artifacts found**, detect the **current Aspire version** from (in priority order):

1. `Aspire.AppHost.Sdk` version in `.csproj` `Sdk="Aspire.AppHost.Sdk/{version}"` attribute
2. `Aspire.AppHost.Sdk` version in child `<Sdk Name="Aspire.AppHost.Sdk" Version="{version}">` element
3. `#:sdk Aspire.AppHost.Sdk@{version}` in single-file AppHost
4. `aspire.config.json` → `sdk.version` field
5. Highest version among `Aspire.Hosting.*` package references
6. `aspire --version` CLI output (if installed)

Record the current version and proceed.

---

## Phase 1: Assessment

Use the standard pre-init workflow — let the user select or create a working branch before making changes.

**Load**: [assessment.md](assessment.md) — read completely before starting this phase. The Aspire assessment is manual; do not call `generate_dotnet_upgrade_assessment`.

The assessment inventories the current Aspire setup and determines what needs to change. It produces:

| Output | Fed Into |
|--------|----------|
| Current Aspire version | Breaking change matrix, SDK and TFM minimums |
| SDK pin and TFMs of Aspire projects | SDK pin task, or stop if a TFM is below the minimum |
| AppHost format (project/file/legacy) | SDK consolidation task |
| Aspire packages inventory | Package rename/removal tasks |
| Obsoleted API usage | Code change tasks |
| Config file format | Config migration task |
| Aspire CLI version | CLI update task |
| ServiceDefaults presence & version | ServiceDefaults update task |

---

## Phase 2: User Configuration

Present the upgrade summary in one consolidated prompt:

> **Aspire Upgrade Assessment**
>
> | | Current | Target |
> |---|---------|--------|
> | **Aspire** | {current_version} | {target_version} |
> | **.NET SDK** | {current_sdk} | {required_sdk} |
>
> **Scope:**
> - `global.json` SDK pin: {will be raised to {required_sdk} / no change}
> - {M} Aspire packages will be upgraded
> - {K} package renames: {list — e.g., NodeJs → JavaScript}
> - {J} breaking API changes will be fixed
> - AppHost SDK format: {will be consolidated / already current}
> - Config files: {will be migrated to aspire.config.json / already current}
>
> **New capabilities in Aspire {target_version}:**
> - {bulleted list from breaking-changes.md feature table}
>
> **⚠️ Manual review needed after upgrade:**
> - {list any warning-only items from assessment — e.g., DefaultAzureCredential behavior}
>
> **Proceed with upgrade?** (You can change the target version or cancel.)

### Handling Target Version Selection

- **Default**: Latest stable Aspire version (query NuGet for `Aspire.AppHost.Sdk` latest stable)
- **User override**: If the user specifies a version (e.g., "upgrade to Aspire 13.0"), use that
- **Validation**: If the requested version is older than the current version, warn and ask for confirmation

Wait for user approval before proceeding.

---

## Phase 3: Planning — Generate plan.md

Follow the canonical plan.md format from your planning instructions. Generate tasks based on the version gap identified in assessment:

### 3.1 Always-Include Tasks

| Order | Task | Description |
|-------|------|-------------|
| 1 | **Check SDK and target frameworks** | Raise the `global.json` SDK pin if needed; stop if an Aspire project is below the minimum TFM |
| 2 | **Update Aspire CLI** | Install or update `aspire.cli` |
| 3 | **Run `aspire agent init`** (optional) | Install the upstream `aspire` skill; list the files it adds: `.github/skills/aspire/SKILL.md` and `.github/skills/aspire/references/*.md`. Mark it optional; the user may remove it from the plan |
| 4 | **Update versions** | `aspire update` for latest stable, otherwise hand-edit SDK and package versions; package renames |
| 5 | **Apply code and file changes** | Fix changes the build cannot catch first, then build and fix compiler errors |
| 6 | **Validation gate** | Clean build, no obsolete-API warnings, old names gone, AppHost smoke run |

### 3.2 Conditional Tasks (based on assessment)

| Condition | Task | Description |
|-----------|------|-------------|
| Target is 13.0 or later and the AppHost has a child `<Sdk Name="Aspire.AppHost.Sdk">` element | **Consolidate AppHost SDK format** | Apply the [AppHost project file](breaking-changes.md#apphost-project-file) table: with `Microsoft.NET.Sdk` (or no `Sdk` attribute) move to `Sdk="Aspire.AppHost.Sdk/{version}"` on `<Project>`, keep any other project SDK; remove the `Aspire.Hosting.AppHost` PackageReference. A 9.x target keeps the child element and the package |
| Legacy config files detected (`.aspire/settings.json`, `apphost.run.json`) | **Migrate config to aspire.config.json** | Merge into unified format |
| `IDistributedApplicationLifecycleHook` usage detected | **Migrate lifecycle hooks** | Warn user to migrate to `IDistributedApplicationEventingSubscriber` (advisory — requires manual structural refactoring) |
| `WithPublishingCallback` usage detected | **Migrate publishing callbacks** | Warn user to migrate to `WithPipelineStepFactory` / `aspire do` (advisory) |
| Target is 13.1 or later and `AddAzureRedis` is used (or produced by the 8.x→9.0 Redis rewrite) | **Switch to Azure Managed Redis** (optional, off by default) | Replace `AddAzureRedis` with `AddAzureManagedRedis`. It deploys Azure Managed Redis, a different Azure resource from Azure Cache for Redis, so list it as optional and do it only if the user opts in; otherwise keep `AddAzureRedis` and list its obsolete warning |
| Upgrading from <13.0 and deployment configured | **Review deployment changes** | Alert user about `aspire do` pipeline replacement, DefaultAzureCredential behavior change |

### 3.3 Present Plan

Save `plan.md` and present to user:

> **Upgrade Plan** ({N} tasks)
>
> {numbered task list with brief descriptions}
>
> **Proceed with this plan?** You can reorder, skip, or add tasks.

Wait for user approval.

---

## Phase 4: Execution

**Load**: [execution.md](execution.md) — read completely when entering this phase. It includes the CLI command reference.

Uses the executor's core task-execution steps for task lifecycle. Execute tasks from the approved `plan.md` sequentially.

### Key Execution Principles

1. **Changes are cumulative** — apply every version section crossed, in order. A project on 8.x needs 8→9, 9→13.0 and 13.0→13.2; a project on 13.0 needs only 13.0→13.2. For a target above 13.2, also apply each newer minor version from its what's-new doc.
2. **`aspire update` moves versions only** — it bumps the SDK and packages to the latest stable version but does not fix code. Code changes come from [breaking-changes.md](breaking-changes.md), the Aspire docs (`aspire docs get`) and the compiler.

Mark each task done in `plan.md` as you complete it.

---

## Phase 5: Validation

If the validation gate task passed and nothing changed since, reuse its build and smoke-run results and go to the completion message. Otherwise run `aspire stop` first if the AppHost is running, so the build is not blocked by locked files, then do 5.1 and 5.2.

### 5.1 Build Verification

Run `aspire restore --apphost <apphost.csproj> --non-interactive`, then build all projects with `dotnet build {solution_path} --no-incremental`. If errors:
- Check for breaking changes in the versions crossed
- **Load**: [breaking-changes.md](breaking-changes.md) to cross-reference errors against known changes
- Fix and rebuild

### 5.2 AppHost Verification

The agent performs validation autonomously using CLI tools:

```bash
# Check the SDK, container runtime and HTTPS certificate; if the user cannot fix a failure, skip the smoke run and report it as not done
aspire doctor --non-interactive --nologo

# Check if an AppHost is already running
aspire ps

# Start the AppHost in the background
aspire start --apphost <apphost.csproj> --non-interactive

# Wait for key services to be ready (use resource names from assessment)
aspire wait <resource> --status healthy

# Verify all resources are visible and healthy
aspire describe

# Check logs and telemetry if something failed
aspire logs <resource>
aspire otel logs <resource>
aspire otel traces <resource>
```

The user can register `aspire agent mcp` as an MCP server; use its tools if present, but never depend on them.

Leave the final healthy AppHost running; run `aspire stop` only before a rebuild (including between smoke-run retries), or if the user asks.

**If all resources are healthy**, present the completion message:

> **Upgrade complete.** Your project has been upgraded to Aspire {target_version}. All {N} tasks finished successfully.
>
> The AppHost is running. Open the dashboard: {dashboard_url_with_t_token}
>
> When you're done, run `aspire stop` before you rebuild or debug from your IDE, so files and ports are released.

**If issues cannot be resolved**, escalate to the user:

> **⚠️ Validation issue:** {describe the problem and what was attempted}.
>
> Please check the Aspire Dashboard and verify your application manually. Reply when the issue is resolved or if you need help.

---

## Build Warnings Policy

**Override for this scenario:** Only fix warnings introduced by the Aspire upgrade (new APIs, renamed types, updated packages). Do not fix pre-existing warnings in the user's projects — those are out of scope. Execution records the warnings of a build taken before the version update, and the gate compares against it.

---

## Error Handling

| Problem | Resolution |
|---------|------------|
| Not an Aspire project | Suggest Aspire Integration scenario |
| Already on latest version | Inform user, offer to verify/fix existing setup |
| Aspire project below the minimum TFM | Stop; suggest the .NET Version Upgrade scenario first |
| Required .NET SDK not installed | Stop; ask the user to install it |
| Build failures after version update | Cross-reference with breaking-changes.md; fix manually or warn |
| Aspire CLI not installed | Prompt: `dotnet tool install -g aspire.cli` |
| Container runtime not available | Warn; suggest a free OCI-compatible runtime first — Podman (Windows/macOS/Linux) or Docker Engine (Linux). Docker Desktop also works and is a valid choice if the user already has it or is appropriately licensed — note it requires a paid subscription for commercial use in larger organizations, so don't present it as the default. |
| AppHost doesn't start after upgrade | Run `aspire doctor --format Json --non-interactive --nologo` to diagnose environment issues (SDK, container runtime). Check `aspire logs <resource>` for failing services. Review `aspire describe` output for resource status. Fix and retry. |
| User has custom hosting extensions | Warn about `AllocatedEndpoint` constructor changes, `NetworkIdentifier` (13.0+) |

---

## Success Criteria

- [ ] All Aspire packages upgraded to target version
- [ ] All package renames applied (NodeJs→JavaScript, AIFoundry→Foundry, etc.)
- [ ] All breaking API changes fixed, including those the build cannot catch
- [ ] .NET SDK and Aspire project TFMs meet the target minimum
- [ ] AppHost SDK version updated
- [ ] AppHost SDK format consolidated (if applicable)
- [ ] Config files migrated to `aspire.config.json` (if applicable)
- [ ] Solution builds without errors or new `CS0618`/`ASPIRE*` warnings from Aspire APIs (except structural migrations listed for the user)
- [ ] AppHost starts and dashboard shows all resources
- [ ] User has verified application functionality
