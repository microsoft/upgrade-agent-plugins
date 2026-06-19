---
name: aspire-integration
description: >
  Adds Aspire orchestration to an existing repository for inner-loop development and optional Azure
  deployment readiness. Use when asked to "aspirerify a project", "add Aspire to a solution",
  "integrate Aspire", "set up an AppHost", "add aspire init", or "orchestrate services with Aspire".
  Handles CLI setup, TFM compatibility gating, inter-service communication mapping, and delegates
  AppHost wiring to the Aspire CLI agent skills.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: medium
  weight: 9000
  traits: .NET|CSharp|VisualBasic|DotNetCore
  scenarioTraitsSet: [.NET]
---

# Aspire Integration Scenario

Add Aspire orchestration to an existing repository — unified inner-loop development with the Aspire Dashboard and optional Azure deployment readiness.

Do **not** write AppHost code, detect infrastructure dependencies, or wire services — those belong to the `aspireify` skill. This scenario's contributions are: environment gates, source control, inter-service communication mapping (context for aspireify), integration mode question, Azure publisher code, and scenario lifecycle.

## Workflow Overview

```
Phase 0  PRE-CHECK        → TFM gate; detect existing Aspire artifacts; CLI/skills setup
Phase 1  WORKING BRANCH   → Branch setup and source control hygiene
Phase 2  ANALYSIS         → inter-service communication mapping
Phase 3  USER CONFIG      → Single question: integration mode
Phase 4  PLANNING         → Generate plan.md based on mode choice
Phase 5  EXECUTION        → aspire init; delegate to aspireify; Azure publisher (if chosen)
Phase 6  COMPLETION       → Surface final status, deferred items, next steps
```

---

## Phase 0: Pre-Check — Environment & Compatibility Gates

The cheap gates (TFM, existing artifacts) run first. CLI and skill installs only run if we're definitely continuing — so a user who hard-stops on incompatible TFM or chooses *Quit* on existing-artifact detection has nothing installed.

### 0.1: TFM Compatibility Gate

Scan every `.csproj` in the solution. For each, read `<TargetFramework>` and `<TargetFrameworks>`.

**Compatible TFMs:** `net8.0`, `net9.0`, `net10.0`, or any `net{X}.0` where X ≥ 8. Multi-targeted projects with at least one compatible TFM are compatible.

**Incompatible TFMs:** `net4*` (.NET Framework), `netstandard*`, `netcoreapp*`, `net5.0`, `net6.0`, `net7.0`.

| Result | Action |
|--------|--------|
| **All incompatible** | Hard stop — present message below. Link to .NET Version Upgrade scenario. End this scenario. |
| **Mixed** | Ask: proceed with compatible subset *(recommended)* or upgrade all first then re-run. If proceeding, carry the incompatible list as the aspireify "skip list". |
| **All compatible** | Continue silently. |

<response_template>
❌ **No Compatible Projects Found**

All projects target .NET versions that Aspire does not support (net8.0 or later required):

| Project | Current TFM |
|---------|------------|
| {project} | {tfm} |

**Options:**
1. Upgrade projects first using the **.NET Version Upgrade** scenario, then return here
2. Cancel this scenario
</response_template>

<response_template>
⚠️ **Mixed Compatibility Detected**

| Compatible (will be orchestrated by Aspire) | Incompatible (will be skipped) |
|------------------------------|-------------------------------|
| {project} ({tfm}) | {project} ({tfm} — requires net8.0+) |

**Options:**
1. **Proceed with compatible projects only** *(recommended)* — incompatible projects remain unchanged
2. **Upgrade all projects first** — use the .NET Version Upgrade scenario, then return here
</response_template>

---

### 0.2: Detect Existing Aspire Artifacts

Search for:

| Signal | Where to Look |
|--------|---------------|
| AppHost project | Any `.csproj` with `Sdk="Aspire.AppHost.Sdk"` or `#:sdk Aspire.AppHost.Sdk` in a `.cs` file |
| ServiceDefaults project | Any `.csproj` with `<IsAspireSharedProject>true</IsAspireSharedProject>` |
| Aspire hosting packages | `Aspire.Hosting.*` NuGet references in any project |

**If nothing found** → continue to 0.3. Set internal flag: `aspire_init_needed = true`.

**If artifacts found** → present options:

> **Existing Aspire support detected:**
> {list what was found with paths}
>
> **Options:**
> 1. **Quit** — no changes needed
> 2. **Fix / augment** — add missing resources or projects to the existing AppHost
> 3. **Add new AppHost** — create a separate AppHost for a different subset of projects

- **Quit** → end scenario
- **Fix/augment** → set `aspire_init_needed = false`; continue to 0.3
- **Add new AppHost** → set `aspire_init_needed = true`; continue to 0.3

---

**Load**: [aspire-cli.md](aspire-cli.md) — read before running any commands in the steps below. It defines which commands are agent-safe, which must never be run as an agent, and the correct flags for each.

### 0.3a: Verify / Install Aspire CLI

```bash
aspire --version
```

- **Present** → proceed to 0.3b.
- **Missing** → run `dotnet tool install -g aspire.cli`. If the command fails and cannot be retried automatically, **pause and ask the user to run it manually**:
  > Before continuing, please run this in your terminal:
  > ```
  > dotnet tool install -g aspire.cli
  > ```
  > Reply when done.

**Hard gate**: do not proceed until `aspire --version` succeeds.

### 0.3b: Update Aspire CLI

```bash
dotnet tool update -g aspire.cli
```

Always run when CLI is present — idempotent. Ensures aspireify-required features (`--non-interactive`, `aspire init`, `aspire docs search`, `aspire list integrations`) are available.

If the command fails and cannot be retried automatically, **pause and ask the user to run it manually**:
> Please run this in your terminal:
> ```
> dotnet tool update -g aspire.cli
> ```
> Reply when done.

**Hard gate**: do not proceed with a stale CLI. The workflow depends on CLI features that may not exist in older versions.

### 0.3c: Ensure Aspire Skills Are Installed

Search the repository for existing skill files:
- `.github/skills/aspire/SKILL.md` (or `skill.md`, or any `*aspire*skill*` under `.github/skills/aspire/`)
- `.github/skills/aspireify/SKILL.md` (or `skill.md`, or any `*aspireify*skill*` under `.github/skills/aspireify/`)

- **Both found** → skills are already installed; proceed.
- **Either missing** → run:
  ```bash
  aspire agent init --non-interactive --nologo --skills aspire,aspireify --skill-locations github
  ```
  If the command succeeds, verify both files now exist at `.github/skills/aspire/SKILL.md` and `.github/skills/aspireify/SKILL.md`. Then read both to load the Aspire-specific context before continuing.

  If the command fails and cannot be retried automatically, **pause and ask the user to run it manually**:
  > Before continuing, please run this in your terminal:
  > ```
  > aspire agent init --non-interactive --nologo --skills aspire,aspireify --skill-locations github
  > ```
  > Reply when done.

**Hard gate**: do not proceed until both skill files are present. The aspireify skill is required for Phase 5 — the workflow cannot continue without it.

---

## Phase 1: Working Branch

### 1.1: Source Control Detection

Detect git repo, current branch, and pending changes. Use the standard `scenario-initialization` system skill workflow.

### 1.2: Consolidated Pre-Init Prompt

Present branch strategy, commit approach, and flow mode in **one single prompt**. No multi-step wizard. User confirms or adjusts.

### 1.3: Apply Source Control

Commit or stash pending changes. Create/switch to working branch. The workspace must be clean and on the correct branch before analysis begins.

---

## Phase 2: Analysis

All steps in this phase are **read-only**. No file mutations.

**Load**: [assessment.md](assessment.md) — read completely before starting this phase.

The assessment file covers:
- TFM compatibility (reuse Phase 0.1 results)
- Inter-service communication mapping (unique value-add of this scenario)
- Assessment summary template

### Assessment Outputs

| Output | Used By |
|--------|---------|
| Compatible projects list (paths + TFMs) | aspireify delegation context |
| Incompatible projects skip list | aspireify delegation context |
| Inter-service communication graph | aspireify delegation context — guides `WithReference`/`WaitFor` wiring |

Present the assessment summary to the user before proceeding to Phase 3. Wait for confirmation.

---

## Phase 3: User Configuration

### 3.1: Integration Mode (single question)

> **Integration mode:**
> 1. **Inner-loop only** — AppHost for local development with Aspire Dashboard
> 2. **Inner-loop + Azure-ready** — Also configure Azure publishing so you can deploy when ready (deployment itself is not done during this scenario)
>
> *Recommended: {1 or 2}*
> - Default to **Azure-ready** if any compatible project is a Web API, Worker Service, Azure Functions, Blazor app, or gRPC service
> - Default to **inner-loop only** if all compatible projects are desktop apps or console tools

Wait for answer before proceeding.

---

## Phase 4: Planning

Uses the system **plan-generation** skill for file format.

### 4.1: Plan Shapes

**Inner-loop only (3 tasks):**

| Order | Task ID | Concern |
|-------|---------|---------|
| 1 | `01-environment-setup` | Verify CLI, create AppHost skeleton via `aspire init` |
| 2 | `02-aspireify` | Delegate full AppHost wiring to aspireify skill |
| 3 | `03-complete` | Surface dashboard URL, resource list, skipped projects, deferred items |

**Inner-loop + Azure-ready (4 tasks):**

| Order | Task ID | Concern |
|-------|---------|---------|
| 1 | `01-environment-setup` | Verify CLI, create AppHost skeleton via `aspire init` |
| 2 | `02-aspireify` | Delegate full AppHost wiring to aspireify skill |
| 3 | `03-azure-publisher` | Ask publisher type (ACA/AKS); add packages; write Publish* code; build AppHost |
| 4 | `04-complete` | Surface what was done + instructions to deploy when ready |

> **Completion task vs Phase 6:** The `*-complete` task generates the completion surface (templates in execution.md "Completion Surfaces") and is the last tracked unit of work in `plan.md`. Phase 6 is the scenario-lifecycle wrap-up that runs after the plan is fully done — it refreshes resource state if needed and hands off to a follow-up scenario. The completion *content* is owned by the task; Phase 6 owns the *lifecycle*.

### 4.2: Initialize Task Tracking

Initialize `tasks.md` and `scenario-instructions.md` using the standard `initialize_scenario` system skill.

### 4.3: Present Plan

Save `plan.md` and present it to the user. Wait for approval before starting execution.

---

## Phase 5: Execution

**Load**: [execution.md](execution.md) — read completely when entering this phase.
**Load**: [aspire-cli.md](aspire-cli.md) — CLI command reference.

Uses the system **task-execution** skill for task lifecycle. The execution file supplements task-execution — it does not replace it.

Execute the tasks listed in the approved `plan.md` (3 tasks for inner-loop only, 4 tasks for Azure-ready). For each task, use the matching reference section below — only the tasks present in `plan.md` should run.

| Task | Execution Reference Section | When |
|------|-----------------------------|------|
| `01-environment-setup` | Task 01: Environment Setup | Always |
| `02-aspireify` | Task 02: aspireify Delegation | Always |
| `03-azure-publisher` | Task 03: Azure Publisher Setup | Azure-ready path only |
| `03-complete` / `04-complete` | Completion Surfaces | Always (last task in plan) |

Mark each task done in `plan.md` as you complete it.

---

## Phase 6: Completion

1. Confirm all tasks in `plan.md` are marked done
2. Re-run `aspire describe` if the AppHost was stopped — get current resource status
3. Surface to the user:
   - **Dashboard URL** (with full login token — from aspireify's completion summary; if missing, run `aspire start` and read the URL from its output — that is the canonical source)
   - **Resource list** — name, type, status (Healthy / Skipped / Deferred)
   - **Skipped incompatible projects** — each with actionable next step (link to .NET Version Upgrade)
   - **Deferred items** from aspireify (e.g., OTel not wired for a service) — each with actionable next step
   - *(Azure-ready path)* What was done (publisher packages + Publish* code). Instruction: *"Run `aspire deploy` in your terminal, use the Aspire CLI directly, or any preferred deployment tool when you're ready to deploy to Azure. First run will ask for Azure subscription, resource group, and region."*
4. Suggest next scenario: *"Run `aspire-version-upgrade` when you want to move to a newer Aspire version"*

---

## Build Warnings Policy

Only fix warnings introduced by Aspire integration (new AppHost code from Task 03, new package references). Do not fix pre-existing warnings in the user's projects — those are out of scope.

## Error Handling

| Problem | Resolution |
|---------|------------|
| No compatible projects (all < net8.0) | Phase 0.1 hard stop — link to .NET Version Upgrade scenario |
| Aspire CLI install fails | Check .NET SDK is installed; try `dotnet tool install -g aspire.cli --add-source https://api.nuget.org/v3/index.json` |
| `aspire agent init` fails | Check network; retry `aspire agent init --non-interactive --nologo --skills aspire,aspireify --skill-locations github` |
| `aspire init` fails | Check AppHost SDK version availability on NuGet; surface the CLI's error message to the user |
| aspireify reports an error | Read aspireify's error message; diagnose; do not retry without understanding the failure |
| Azure publisher build failure | Check package version conflicts between AppHost SDK and publisher packages; fix and rebuild |
