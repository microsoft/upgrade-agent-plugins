# Assessment Instructions (Phase 1)

Detailed analysis instructions for SKILL.md Phase 1. Read this file completely before starting the assessment. This assessment is manual; do not call `generate_dotnet_upgrade_assessment`.

This file contains **7 required steps**:

| Step | Section | What It Covers |
|------|---------|----------------|
| 1 | Detect Current Aspire Version | Exact version from SDK, packages, config |
| 2 | Determine Target Version | Latest stable or user-specified |
| 3 | Inventory Aspire Components | AppHost, ServiceDefaults, packages, config |
| 4 | Check SDK and TFM Minimums | SDK pin change; Aspire projects below the minimum TFM |
| 5 | Scan for Breaking Changes | Code patterns that need changing |
| 6 | Check Tooling & Environment | CLI, container runtime, `aspire` skill |
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
- SDK and TFM minimums checked
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
| 13.1.0 – 13.1.x | 13.1 | Minor release |
| 13.2.0 – 13.2.x | 13.2 | Minor release |

For a version newer than the last row, use its major.minor as the band.

Record: `current_version`, `current_band`, `current_tfm`

---

## Step 2: Determine Target Version

### 2.1 Default Target

Find the latest stable `Aspire.AppHost.Sdk` version on NuGet (prereleases are excluded; the highest version is listed first):

```bash
dotnet package search Aspire.AppHost.Sdk --exact-match
```

Do not use `aspire --version`; it reports the CLI version, not the latest Aspire release.

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
| Any | Above 13.2 | The rows above up to 13.2, then each newer minor version up to the target (13.2→13.3, 13.3→13.4, …), each read from its `whats-new-in-aspire-<major><minor>` doc |

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
| `Aspire.Hosting.Azure.AIFoundry` | Yes (if upgrading to 13.2+) | `Aspire.Hosting.Foundry` (preview-only) |

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

## Step 4: Check SDK and TFM Minimums

### 4.1 Required TFM for Target Version

The minimum applies to the AppHost, ServiceDefaults and every project that references an `Aspire.*` package; other projects are unconstrained.

| Target Aspire | Required TFM | Required SDK |
|--------------|-------------|--------------|
| 8.x | net8.0+ | .NET 8 SDK |
| 9.x | net8.0+ (net9.0 recommended) | .NET 8 SDK or later |
| 13.x (through 13.2) | net8.0+ | .NET 10 SDK |

For targets above 13.2, check whether a newer release raised these minimums: read the "Breaking changes" section of `aspire docs get whats-new-in-aspire-<major><minor>` for each version crossed (for example `whats-new-in-aspire-133`) and `aspire docs get upgrade-aspire-to-the-latest-version`. If the CLI is missing or too old to have `aspire docs` (added in 13.2), record these minimums as not yet checked; execution checks them right after the CLI update.
### 4.2 SDK Pin

If `global.json` pins an SDK older than the required SDK, the plan raises the pin; list the change for user approval. If the required SDK is not installed (`dotnet --list-sdks`), report it.

Execution also needs Aspire CLI 13.3 or later, which runs on .NET 10, for every target (including 8.x and 9.x). If no .NET 10 SDK is installed, report it so the plan includes installing it. This does not change the `global.json` pin.

### 4.3 Aspire Project TFMs

Read `<TargetFramework>` / `<TargetFrameworks>` of the Aspire projects only. This scenario never retargets. If any Aspire project is below the minimum TFM, stop and suggest running the .NET Version Upgrade scenario first.

Record: `sdk_pin_change` (from → to, or none), `aspire_projects_below_min[]`

---

## Step 5: Scan for Breaking Changes

**Load**: [breaking-changes.md](breaking-changes.md) — the version-to-version change matrix.

For each version transition in `version_transitions[]`, scan the codebase for affected patterns:

### 5.1 Mechanical renames and rewrites

These have an exact old → new mapping in [breaking-changes.md](breaking-changes.md) and are fixed by hand-editing:

| Pattern | Grep/Search | Applies When |
|---------|------------|-------------|
| `AzureConstructResource` | Type name in code files | 8.x→9.0 |
| `UseEmulator` | Method calls | 8.x→9.0 |
| `.AsAzurePostgresFlexibleServer()` | Chained method calls | 8.x→9.0 |
| `AddNpmApp` | Method calls | 9.x→13.0 |
| Every `AddNodeApp` call (not caught by the build when arguments 2 and 3 are positional) | Invocation pattern | 9.x→13.0 |
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
| `AddAzureRedis` (including results of the 8.x→9.0 Redis chain rewrite) | Method calls | Any→13.1+ | Replacement `AddAzureManagedRedis` provisions a different Azure resource; the plan lists the switch for user approval |
| `services__` | String literals | Any→13.2 | Env var naming change |
| `BeforeResourceStartedEvent` | Event subscription | Any→13.2 | Timing change |

Record: `mechanical_changes[]` with counts, `advisory_changes[]` with locations

---

## Step 6: Check Tooling & Environment

### 6.1 Aspire CLI

```bash
aspire --version
```

| Result | Action |
|--------|--------|
| Not installed | Task: install CLI |
| Installed | Task: update CLI (execution needs CLI 13.3 or later; the CLI version is independent of the target Aspire version) |

### 6.2 Container Runtime

```bash
podman --version
# or
docker --version
```

Warn if not available — Aspire works but infrastructure resources won't start.

If no runtime is found, suggest a free OCI-compatible runtime first — Podman (Windows/macOS/Linux) or Docker Engine (Linux). Docker Desktop is also a valid choice if the user already has it or is appropriately licensed; note it requires a paid subscription for commercial use in larger organizations, so don't present it as the default.

### 6.3 Aspire Skill

Check whether the upstream `aspire` skill is installed: `.github/skills/aspire/SKILL.md` exists. If not, note it; execution Step 1 can install it with `aspire agent init` (an optional plan task).

### 6.4 `aspire doctor` (optional)

If Aspire CLI is available, run `aspire doctor` for comprehensive environment diagnostics.

---

## Step 7: Present Assessment Summary

Compile all findings into a summary for the user:

> **Aspire Upgrade Assessment**
>
> **Version**: {current_version} → {target_version}
> **.NET SDK**: {current_sdk} → {required_sdk} ({global.json pin raised / no change})
> **Aspire project TFMs**: {all meet net{min} / below minimum: list — stop}
>
> **Components found:**
> - AppHost: {path} ({format})
> - ServiceDefaults: {path or "not found"}
> - Aspire packages: {count} across {project_count} projects
>
> **Changes to apply** ({total_count}):
> - {count} package version upgrades
> - {count} package renames ({list})
> - {count} breaking API changes
> - AppHost SDK: {consolidation needed / already current}
> - Config files: {migration needed / already current}
>
> **Manual review needed** ({advisory_count}):
> - {list of advisory items with file locations}
>
> **Environment:**
> - Aspire CLI: {version or "not installed"}
> - Container runtime: {available / not available}
> - `aspire` skill: {installed / optional install in execution Step 1}

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
- [ ] SDK pin and Aspire project TFM minimums checked
- [ ] Breaking change patterns scanned and counted
- [ ] Advisory items identified with locations
- [ ] Tooling status checked (CLI, container runtime, `aspire` skill)
- [ ] Assessment summary presented to user
