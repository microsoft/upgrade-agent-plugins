# Assessment Instructions (Phase 1)

Detailed analysis instructions for SKILL.md Phase 1. Read this file completely before starting the assessment.

This file contains **7 required steps**:

| Step | Section | What It Covers |
|------|---------|----------------|
| 1 | Detect Current Aspire Version | Exact version from SDK, packages, config |
| 2 | Determine Target Version | Latest stable or user-specified |
| 3 | Inventory Aspire Components | AppHost, ServiceDefaults, packages, config |
| 4 | Check TFM Requirements | Whether TFM upgrade is needed |
| 5 | Scan for Breaking Changes | Code patterns that need transformation |
| 6 | Check Tooling & Environment | CLI, container runtime, agent/MCP |
| 7 | Present Assessment Summary | Consolidated findings for user review |

---

## Goal

Determine the current Aspire version, inventory all Aspire components, identify what needs to change for the target version, and present a clear upgrade scope to the user.

## Entry Criteria

- Phase 0 (pre-check) from SKILL.md is complete
- Aspire artifacts have been detected
- Current Aspire version has been identified (at least approximately)

## Exit Criteria

- Exact current Aspire version determined
- Target version confirmed
- All breaking changes between source and target identified
- TFM upgrade requirement determined
- Component inventory complete
- User has reviewed assessment summary

---

## Step 1: Detect Current Aspire Version

Determine the exact current version from multiple signals:

### 1.1 AppHost SDK Version

Check the AppHost project file:

```xml
<!-- Format A: Consolidated (13.0+) -->
<Project Sdk="Aspire.AppHost.Sdk/13.0.0">

<!-- Format B: Child element (8.x-9.x) -->
<Project Sdk="Microsoft.NET.Sdk">
  <Sdk Name="Aspire.AppHost.Sdk" Version="9.5.2" />

<!-- Format C: Single-file AppHost (13.0+) -->
#:sdk Aspire.AppHost.Sdk@13.2.0
```

### 1.2 Package Versions

Scan all projects for `Aspire.*` package references. The highest version across all packages indicates the current Aspire version.

### 1.3 Config File Version

Check `aspire.config.json` for `sdk.version` field:
```json
{ "sdk": { "version": "13.2.0" } }
```

### 1.4 Version Classification

Map the detected version to a major version band:

| Detected Version | Band | Era |
|-----------------|------|-----|
| 8.0.0 – 8.2.x | 8.x | First GA (net8.0) |
| 9.0.0 – 9.5.x | 9.x | .NET 9 era |
| 13.0.0 – 13.0.x | 13.0 | .NET 10 launch |
| 13.1.0 – 13.1.x | 13.1 | Bug fixes |
| 13.2.0+ | 13.2 | Latest |

Record: `current_version`, `current_band`, `current_tfm`

---

## Step 2: Determine Target Version

### 2.1 Default Target

Query NuGet for the latest stable `Aspire.AppHost.Sdk` version. Alternatively, if Aspire CLI is installed, use:

```bash
aspire --version
```

### 2.2 User-Specified Target

If the user requested a specific version (e.g., "upgrade to Aspire 13.0"), validate:
- Version exists on NuGet
- Version is newer than current (warn if not)
- Version is not a prerelease (warn if it is, ask for confirmation)

### 2.3 Version Gap

Determine which version transitions apply:

| Current | Target | Transitions to Apply |
|---------|--------|---------------------|
| 8.x | 13.2 | 8→9 + 9→13.0 + 13.0→13.2 |
| 9.x | 13.2 | 9→13.0 + 13.0→13.2 |
| 13.0 | 13.2 | 13.0→13.2 |
| 13.1 | 13.2 | 13.1→13.2 (minor) |

Record: `target_version`, `version_transitions[]`

---

## Step 3: Inventory Aspire Components

### 3.1 AppHost

| Check | What to Record |
|-------|---------------|
| AppHost project path | `.csproj` or `.cs` file path |
| AppHost format | `project-consolidated` (Sdk= attr), `project-legacy` (child Sdk element), `file-based` (#:sdk) |
| SDK version | From step 1 |
| Registered projects | All `AddProject<>()` calls |
| Infrastructure resources | All `AddRedis()`, `AddPostgres()`, `AddSqlServer()`, etc. |
| Azure publisher | `AddAzureContainerAppsInfrastructure()`, `AddDockerComposeEnvironment()`, etc. |

### 3.2 ServiceDefaults

| Check | What to Record |
|-------|---------------|
| ServiceDefaults project path | `.csproj` path (if exists) |
| ServiceDefaults referenced by | Which projects reference it |
| `AddServiceDefaults()` calls | Which projects call it in their `Program.cs` |

### 3.3 Aspire Packages

Scan all projects and record every `Aspire.*` and `Microsoft.Extensions.ServiceDiscovery.*` package reference with its current version.

Flag packages that need **renaming**:

| Package | Needs Rename? | Target Name |
|---------|--------------|-------------|
| `Aspire.Hosting.NodeJs` | Yes (if upgrading to 13.0+) | `Aspire.Hosting.JavaScript` |
| `Aspire.Hosting.Azure.AIFoundry` | Yes (if upgrading to 13.2+) | `Aspire.Hosting.Foundry` |
| `Aspire.Hosting` | Yes (if still present from 8.x) | `Aspire.Hosting.AppHost` |
| `Aspire.Hosting.Azure.Provisioning` | Yes (if still present from 8.x) | `Aspire.Hosting.Azure` |

Flag packages that should be **removed**:

| Package | Remove When? |
|---------|-------------|
| `Aspire.Hosting.AppHost` | Upgrading to 13.0+ (included by SDK) |

### 3.4 Configuration Files

| File | Status |
|------|--------|
| `aspire.config.json` | Present / absent |
| `.aspire/settings.json` | Present / absent (legacy) |
| `apphost.run.json` | Present / absent (legacy) |

If legacy files are present and `aspire.config.json` is absent → config migration needed.

---

## Step 4: Check TFM Requirements

### 4.1 Required TFM for Target Version

| Target Aspire | Required TFM |
|--------------|-------------|
| 8.x | net8.0+ |
| 9.x | net8.0+ (net9.0 recommended) |
| 13.x | net10.0 |

### 4.2 Current TFM Check

Scan all projects for `<TargetFramework>` / `<TargetFrameworks>`. Record:
- Projects already on required TFM → no change needed
- Projects below required TFM → TFM upgrade needed
- Multi-targeted projects → add/update the required TFM in the list

### 4.3 TFM Upgrade Feasibility

For each project needing TFM upgrade, check:
- NuGet package compatibility with target TFM (use `dotnet restore --dry-run` or similar)
- Known incompatible packages (e.g., packages that only support up to net9.0)

Record: `projects_needing_tfm_upgrade[]`, `tfm_blockers[]`

---

## Step 5: Scan for Breaking Changes

**Load**: [breaking-changes.md](breaking-changes.md) — the version-to-version change matrix.

For each version transition in `version_transitions[]`, scan the codebase for affected patterns:

### 5.1 Automated (engine handles)

These are detected for informational purposes — the engine transforms will fix them automatically:

| Pattern | Grep/Search | Applies When |
|---------|------------|-------------|
| `AzureConstructResource` | Type name in code files | 8.x→9.0 |
| `UseEmulator` | Method calls | 8.x→9.0 |
| `.AsAzurePostgresFlexibleServer()` | Chained method calls | 8.x→9.0 |
| `AddNpmApp` | Method calls | 9.x→13.0 |
| `AddNodeApp` with 3 args | Invocation pattern | 9.x→13.0 |
| `WithSecretBuildArg` | Method calls | 13.0→13.2 |
| `AddAzureAIFoundry` | Method calls | 13.0→13.2 |
| `AddLifecycleHook` / `TryAddLifecycleHook` | Method calls | 9.x→13.0 |

Count matches for each to report in the assessment summary.

### 5.2 Advisory (warning-only, requires manual review)

| Pattern | Grep/Search | Applies When | Impact |
|---------|------------|-------------|--------|
| `IDistributedApplicationLifecycleHook` | Interface implementation | 9.x→13.0 | Structural refactoring needed |
| `WithPublishingCallback` | Method calls | 9.x→13.0 | Replaced by `WithPipelineStepFactory` |
| `DefaultAzureCredential` | Type usage | Any→13.0+ | Behavior change in Azure deployments |
| `services__` | String literals | Any→13.2 | Env var naming change |
| `BeforeResourceStartedEvent` | Event subscription | Any→13.2 | Timing change |

Record: `automated_changes[]` with counts, `advisory_changes[]` with locations

---

## Step 6: Check Tooling & Environment

### 6.1 Aspire CLI

```bash
aspire --version
```

| Result | Action |
|--------|--------|
| Not installed | Task: install CLI |
| Installed, older than target | Task: update CLI |
| Installed, matches target | No action |

### 6.2 Container Runtime

```bash
docker --version
# or
podman --version
```

Warn if not available — Aspire works but infrastructure resources won't start.

### 6.3 Aspire Agent/MCP/Skills

Check for:
- `.github/skills/aspire/` directory — Aspire skill files
- MCP configuration — check if Aspire MCP tools are available

If not present and upgrading to 13.0+, recommend `aspire agent init` as a post-upgrade step.

### 6.4 `aspire doctor` (optional)

If Aspire CLI is available, run `aspire doctor` for comprehensive environment diagnostics.

---

## Step 7: Present Assessment Summary

Compile all findings into a summary for the user:

> **Aspire Upgrade Assessment**
>
> **Version**: {current_version} → {target_version}
> **TFM**: {current_tfm} → {required_tfm} ({N} projects need TFM update)
>
> **Components found:**
> - AppHost: {path} ({format})
> - ServiceDefaults: {path or "not found"}
> - Aspire packages: {count} across {project_count} projects
>
> **Automated changes** ({total_count}):
> - {count} package version upgrades
> - {count} package renames ({list})
> - {count} breaking API changes (auto-fixed)
> - AppHost SDK: {consolidation needed / already current}
> - Config files: {migration needed / already current}
>
> **Manual review needed** ({advisory_count}):
> - {list of advisory items with file locations}
>
> **Environment:**
> - Aspire CLI: {version or "not installed"}
> - Container runtime: {available / not available}
> - Agent/MCP: {configured / needs setup}

---

## Checklist

Before proceeding to Phase 2 (User Configuration):

- [ ] Current Aspire version determined precisely
- [ ] Target version confirmed
- [ ] All version transitions identified
- [ ] AppHost format identified
- [ ] ServiceDefaults presence checked
- [ ] All Aspire packages inventoried with versions
- [ ] Package renames identified
- [ ] TFM upgrade requirement determined
- [ ] Breaking change patterns scanned and counted
- [ ] Advisory items identified with locations
- [ ] Tooling status checked (CLI, container runtime, agent/MCP)
- [ ] Assessment summary presented to user
