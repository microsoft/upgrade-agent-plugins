---
name: aspire-version-upgrade
description: >
  Upgrade existing Aspire projects to a newer Aspire version. Also handles TFM upgrades —
  preferred when the solution contains Aspire projects, since the Aspire version drives the
  required TFM. Triggers for "upgrade Aspire", "update Aspire version", "move to latest Aspire",
  or any .NET upgrade request on a solution with Aspire artifacts.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: medium
  weight: 9500
  traits: .NET|CSharp|DotNetCore
  scenarioTraitsSet: [.NET]
---

# Aspire Version Upgrade Scenario

Upgrade an existing Aspire project from its current Aspire version to a newer version — handling package renames, breaking API changes, TFM upgrades, SDK format consolidation, and configuration migration.

> **This scenario is for projects that already use Aspire.** If you need to *add* Aspire to a project that doesn't have it, use the [Aspire Integration](../aspire-integration/SKILL.md) scenario instead.

### What This Scenario Covers

- **Package upgrades** — bumps all `Aspire.*` and `Microsoft.Extensions.ServiceDiscovery.*` packages to the target version
- **Package renames** — handles package renames across all version transitions (see [breaking-changes.md](breaking-changes.md) for the full list)
- **Code transforms** — auto-fixes breaking API changes across all version transitions (type renames, method renames, argument reorders, fluent chain refactors)
- **TFM upgrades** — updates target frameworks to match the target Aspire version requirements (e.g., net10.0 for Aspire 13.x)
- **AppHost SDK consolidation** — migrates legacy `<Sdk>` child element to `Sdk=` attribute on `<Project>` (13.0+ format)
- **Configuration migration** — migrates legacy config files into the unified format introduced in newer Aspire versions (see [breaking-changes.md](breaking-changes.md) for file mapping details)

### Aspire Version / .NET Version Coupling

Aspire versions require specific minimum .NET versions:

| Aspire Version | Required .NET | Notes |
|---------------|---------------|-------|
| 8.x | net8.0+ | First GA release |
| 9.x | net8.0+ (net9.0 recommended) | Full feature set requires net9.0 |
| 13.x | net10.0 | .NET 10 required |

**The Aspire version upgrade drives the TFM**, not the other way around. If the target Aspire version requires a newer TFM, the scenario upgrades it automatically. Users should not upgrade TFM without upgrading Aspire — that creates a version mismatch.

> **Example prompts:** *"Upgrade my Aspire project to latest"*, *"Update Aspire to 13.2"*, *"Modernize my Aspire solution"*, *"Move from Aspire 9 to 13"*

---

## Workflow Overview

```
Phase 0  PRE-CHECK       → Verify this is an Aspire project; detect current version
Phase 1  ASSESSMENT       → Inventory components, identify breaking changes, determine target
Phase 2  USER CONFIG      → Confirm target version, TFM change, review scope
Phase 3  PLANNING         → Generate upgrade plan
Phase 4  EXECUTION        → Run transforms, update TFMs, migrate config
Phase 5  VALIDATION       → Build, run, verify dashboard, user test gate
```

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

**Load**: [assessment.md](assessment.md) — read completely before starting this phase.

The assessment inventories the current Aspire setup and determines what needs to change. It produces:

| Output | Fed Into |
|--------|----------|
| Current Aspire version | Breaking change matrix, TFM requirements |
| Current TFM(s) | Whether TFM upgrade is needed |
| AppHost format (project/file/legacy) | SDK consolidation task |
| Aspire packages inventory | Package rename/removal tasks |
| Obsoleted API usage | Code transform tasks |
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
> | **TFM** | {current_tfm} | {required_tfm} |
>
> **Scope:**
> - {N} projects will have TFM updated ({current_tfm} → {required_tfm})
> - {M} Aspire packages will be upgraded
> - {K} package renames: {list — e.g., NodeJs → JavaScript}
> - {J} breaking API changes will be auto-fixed
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

Uses the system **plan-generation** skill for file format. Generate tasks based on the version gap identified in assessment:

### 3.1 Always-Include Tasks

| Order | Task | Description |
|-------|------|-------------|
| 1 | **Update Aspire CLI** | Install or update `aspire.cli` to match target version |
| 2 | **Upgrade TFM** | Update `<TargetFramework>` in all projects (if TFM change needed) |
| 3 | **Run Aspire upgrade transforms** | Apply all engine transforms in a single pass: package version bumps, package renames, API map renames, chain transforms, argument reorders, AppHost SDK update and consolidation |
| 4 | **Build and fix errors** | Build all projects, resolve any remaining compilation errors |
| 5 | **Validation gate** | Start AppHost, verify dashboard, user confirms apps work |

### 3.2 Conditional Tasks (based on assessment)

| Condition | Task | Description |
|-----------|------|-------------|
| Legacy `<Sdk>` child element detected | **Consolidate AppHost SDK format** | Migrate to `Sdk="Aspire.AppHost.Sdk/{version}"` on `<Project>`, remove redundant `Aspire.Hosting.AppHost` PackageReference |
| Legacy config files detected (`.aspire/settings.json`, `apphost.run.json`) | **Migrate config to aspire.config.json** | Merge into unified format |
| `aspire agent init` not yet run | **Initialize Aspire agent** | Prompt user to run `aspire agent init` for MCP/skills support |
| `IDistributedApplicationLifecycleHook` usage detected | **Migrate lifecycle hooks** | Warn user to migrate to `IDistributedApplicationEventingSubscriber` (advisory — requires manual structural refactoring) |
| `WithPublishingCallback` usage detected | **Migrate publishing callbacks** | Warn user to migrate to `WithPipelineStepFactory` / `aspire do` (advisory) |
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

**Load**: [execution.md](execution.md) — read completely when entering this phase.
**Load**: [../aspire-integration/aspire-cli.md](../aspire-integration/aspire-cli.md) — CLI command reference.

Uses the system **task-execution** skill for task lifecycle. Execute tasks from the approved `plan.md` sequentially.

### Key Execution Principles

1. **TFM changes first, then Aspire transforms** — the engine transformers expect the project to be loadable, so TFM must be valid before running package/code transforms

2. **Aspire transforms are additive** — the engine applies all applicable transforms regardless of source version. The API maps have entries for 8→9 AND 9→13 AND 13.0→13.2 changes. If a project is on 8.x, all three sets apply. If on 13.0, only the 13.0→13.2 set fires (the 8→9 entries don't match since those APIs were already renamed).

3. **Build after transforms, before validation** — always build after transforms to catch any issues the engine didn't handle (e.g., new constructor signatures, removed APIs)

4. **`aspire agent init` is a user action** — never run it as the agent; it's interactive. Prompt and wait.

5. **Relationship to `aspire update`** — the Aspire CLI's `aspire update` command handles package version bumps and SDK updates natively. The engine transforms go further: they also fix code-level breaking changes (API renames, argument reorders, chain refactors) that `aspire update` does not handle. After engine transforms run, suggest running `aspire update` as a verification step to catch any packages the engine may have missed.

Mark each task done in `plan.md` as you complete it.

---

## Phase 5: Validation

### 5.1 Build Verification

Build all projects in the solution. If errors:
- Check for breaking changes not covered by the engine transforms
- **Load**: [breaking-changes.md](breaking-changes.md) to cross-reference errors against known changes
- Fix and rebuild

### 5.2 AppHost Verification

The agent performs validation autonomously using CLI tools:

```bash
# Check if an AppHost is already running
aspire ps

# Start the AppHost in the background
aspire start

# Wait for key services to be ready (use resource names from assessment)
aspire wait <resource> --status Running

# Verify all resources are visible and healthy
aspire describe

# Check logs if something failed
aspire logs <resource>

# Stop when done
aspire stop
```

Or if Aspire MCP tools are available, use them for live resource inspection.

**If all resources are healthy**, present the completion message:

> **Upgrade complete.** Your project has been upgraded to Aspire {target_version}. All {N} tasks finished successfully.

**If issues cannot be resolved**, escalate to the user:

> **⚠️ Validation issue:** {describe the problem and what was attempted}.
>
> Please check the Aspire Dashboard and verify your application manually. Reply when the issue is resolved or if you need help.

---

## Build Warnings Policy

**Override for this scenario:** Only fix warnings introduced by the Aspire upgrade (new APIs, renamed types, updated packages). Do not fix pre-existing warnings in the user's projects — those are out of scope.

---

## Error Handling

| Problem | Resolution |
|---------|------------|
| Not an Aspire project | Suggest Aspire Integration scenario |
| Already on latest version | Inform user, offer to verify/fix existing setup |
| TFM upgrade fails (incompatible dependencies) | Identify blocking packages, suggest alternatives or multi-targeting |
| Build failures after transforms | Cross-reference with breaking-changes.md; fix manually or warn |
| Aspire CLI not installed | Prompt: `dotnet tool install -g aspire.cli` |
| Container runtime not available | Warn; suggest a free OCI-compatible runtime first — Podman (Windows/macOS/Linux) or Docker Engine (Linux). Docker Desktop also works and is a valid choice if the user already has it or is appropriately licensed — note it requires a paid subscription for commercial use in larger organizations, so don't present it as the default. |
| AppHost doesn't start after upgrade | Run `aspire doctor --format Json --non-interactive --nologo` to diagnose environment issues (SDK, container runtime). Check `aspire logs <resource>` for failing services. Review `aspire describe` output for resource status. Fix and retry. |
| User has custom hosting extensions | Warn about `AllocatedEndpoint` constructor changes, `NetworkIdentifier` (13.0+) |

---

## Success Criteria

- [ ] All Aspire packages upgraded to target version
- [ ] All package renames applied (NodeJs→JavaScript, AIFoundry→Foundry, etc.)
- [ ] All breaking API changes auto-fixed by engine transforms
- [ ] TFM updated to match target Aspire version requirements
- [ ] AppHost SDK version updated
- [ ] AppHost SDK format consolidated (if applicable)
- [ ] Config files migrated to `aspire.config.json` (if applicable)
- [ ] Solution builds without errors
- [ ] AppHost starts and dashboard shows all resources
- [ ] User has verified application functionality
