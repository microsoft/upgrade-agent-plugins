# Execution Reference (Phase 5)

Detailed implementation instructions for Phase 5 tasks. Loaded during Phase 5 of SKILL.md.

## Contents

- [Task 01: Environment Setup](#task-01-environment-setup)
- [Task 02: aspireify Delegation](#task-02-aspireify-delegation)
- [Task 03: Azure Publisher Setup](#task-03-azure-publisher-setup-azure-ready-path-only)
- [Completion Surfaces](#completion-surfaces)

For Aspire CLI command details, see [aspire-cli.md](aspire-cli.md).

---

## Task 01: Environment Setup

### Step 1: Re-verify Aspire CLI

```bash
aspire --version
```

Lightweight sanity check — confirms the CLI is still present before making any mutations. If missing (unexpected at this point — Phase 0 should have caught this), stop and return to Phase 0 rather than reinstalling silently.

### Step 2: Run aspire init (conditional)

Run only if `aspire_init_needed = true` from Phase 0.

```bash
aspire init --non-interactive --suppress-agent-init --nologo
```

- `--non-interactive`: agent-safe, no interactive prompts
- `--suppress-agent-init`: skills already installed in Phase 0.3c — skip re-initialization
- `--nologo`: suppresses the banner for clean output

**What `aspire init` creates:** an AppHost and associated config. The exact layout is determined by the aspireify/aspire skills — do not inspect or relocate any files `aspire init` created. After it completes, record the AppHost path (the `.csproj` directory for full-project mode, or the `apphost.cs` file for single-file mode).

---

## Task 02: aspireify Delegation

The `aspireify` skill owns the complete AppHost wiring process. The job here is to invoke it with rich context and wait for the completion summary.

Do **not** duplicate any of aspireify's steps. Do **not** write AppHost code, scaffold ServiceDefaults, run package installs, or validate the running app — aspireify does all of that.

### How to Invoke aspireify (read this first)

The `aspireify` skill was installed by Phase 0.3c (`aspire agent init`). It lives at:

```
.github/skills/aspireify/SKILL.md   (relative to the repository root)
```

Because this skill was dropped onto disk **after this session started**, the agent runtime may not have auto-discovered it. To guarantee invocation:

1. **Read the file directly**: Open `.github/skills/aspireify/SKILL.md` from the repository root using your file-read tool.
2. **Follow its workflow**: Execute all steps defined in aspireify's skill in order.
3. **Read referenced files on demand**: aspireify references supporting files under `.github/skills/aspireify/references/`. Open each one when aspireify's workflow tells you to.
4. **Pass the context block below**: Before executing any aspireify step, paste the context block in the next section as your initial framing prompt — this seeds aspireify's decisions and lets it skip git/discovery checks UA already did.

If the file is not present at that path, Phase 0.3c failed silently — re-run `aspire agent init --non-interactive --nologo --skills aspire,aspireify --skill-locations github` and retry.

### Delegation Context

Fill in the placeholders below from earlier phases. This is the framing prompt referenced in step 4 above.

```
I need you to complete the Aspire initialization for this repository using the aspireify skill.

## Source Control Context
Workspace is clean and on branch "{branch_name — run `git branch --show-current` to get the current branch}". All source control setup is already done —
skip any git status checks or branch operations.

## TFM Compatibility Context
Compatible projects (include in AppHost):
{for each compatible project: "- {relative-path} ({tfm})"}

Incompatible projects (exclude — do not add to AppHost):
{for each incompatible project: "- {relative-path} ({tfm}) — requires net8.0+"}

## Inter-Service Communication Graph
{paste complete graph from assessment.md Step 2.1 — omit this section entirely if assessment found nothing}

Use this graph to guide WithReference() and WaitFor() wiring in the AppHost. These relationships
were detected by static analysis and should complement, not override, your own discovery.

## AppHost Status
{One of:}
- New AppHost — created by aspire init at {relative-path-to-apphost-dir-or-file}
- Existing AppHost at {relative-path} — aspire init was skipped
```

### Waiting for aspireify

aspireify is complete when it prints its final summary:

```
✅ Aspire init complete!

Dashboard: {URL with login token}

Resources:
  {name}  {type}  {status}
  ...

{deferred items if any}
```

Read this summary and carry forward:
- Dashboard URL (with login token)
- Resource list and statuses
- Any deferred items (e.g., OTel not configured for a service)

Do **not** re-run any step aspireify already completed. Do **not** modify the AppHost code aspireify wrote.

### If aspireify Reports a Failure or Gets Stuck

aspireify is self-healing — it diagnoses and fixes its own errors before reporting done. If it escalates a problem to you or the user:

- **Architectural decision needed** (e.g., unclear service relationship, ambiguous config): answer the question using context from the assessment phase (inter-service graph, project list), then let aspireify continue.
- **Environment blocker** (e.g., container runtime not running, build failure): surface the specific error and the fix to the user. Do not attempt to patch aspireify's work — resolve the blocker and ask aspireify to retry the failed step.
- **Unresolvable failure**: record the error in the completion summary under "Deferred items". Do not silently skip it.

---

## Task 03: Azure Publisher Setup (Azure-ready path only)

Skip entirely if user chose inner-loop only in Phase 3.1.

> **UA ownership note:** The aspireify/aspire skills handle inner-loop orchestration but do not cover Azure deployment publisher setup. UA owns this task as gap coverage. If the Aspire team adds publisher support to their skills in a future version, delegate here instead.

### Step 1: Ask Publisher Type

> **Azure publisher type:**
> 1. **Azure Container Apps (ACA)** *(recommended for most scenarios)* — scale-to-zero, standard Aspire experience
> 2. **Azure Kubernetes Service (AKS)** — for high-scale workloads or existing K8s environments

Wait for answer before proceeding.

### Step 2: Add Publisher Packages

These commands are **non-interactive and agent-safe**:

```bash
# ACA:
aspire add azure-appcontainers

# AKS:
aspire add azure-aks
```

⚠️ `aspire add` adds NuGet packages only — it does **not** write AppHost code. Write the publish configuration code in Step 3.

### Step 3: Write Publish* Code

Edit the AppHost code aspireify wrote (`Program.cs` or single-file AppHost). The AppHost already contains the full set of `AddProject<>()`, `AddRedis()`, `AddPostgres()`, etc. calls — your job is to chain a `Publish*` call onto each one, not to decide which projects belong in the AppHost (that was aspireify's job).

**Rules:**
- For each `builder.AddProject<>("name")` call → chain `.PublishAsAzureContainerApp(...)` (ACA) or `.PublishAsKubernetesService(...)` (AKS)
- For each infrastructure resource (`AddRedis`, `AddPostgres`, `AddSqlServer`, `AddAzureServiceBus`, …) → chain the matching Azure-managed variant (`PublishAsAzureRedis`, `PublishAsAzurePostgresFlexibleServer`, …)
- **Do NOT** add publish config to desktop apps if aspireify added one via `AddProject<>` (rare — typically a MAUI client) — leave inner-loop-only
- **Do NOT** edit the ServiceDefaults project — it has no `AddProject<>` entry in the AppHost

**ACA pattern:**

```csharp
// Add ACA environment (once, near the top)
var acaEnv = builder.AddAzureContainerAppEnvironment("aca-env");

// Each deployable .NET project
var api = builder.AddProject<Projects.MyApi>("api")
    .WithReference(cache)
    .WaitFor(cache)
    .PublishAsAzureContainerApp((infra, app) =>
    {
        app.Template.Scale.MinReplicas = 1;
    });

// Infrastructure — use Azure-managed variants
var cache = builder.AddRedis("cache")
    .PublishAsAzureRedis();

var db = builder.AddPostgres("pg").AddDatabase("mydb")
    .PublishAsAzurePostgresFlexibleServer();
```

**AKS pattern:**

```csharp
// Add K8s environment (once)
builder.AddKubernetesEnvironment("k8s-env")
    .WithProperties(env =>
    {
        env.DefaultImagePullPolicy = "Always";
    });

// Each deployable project
var api = builder.AddProject<Projects.MyApi>("api")
    .PublishAsKubernetesService(resource =>
    {
        resource.Deployment!.Spec.RevisionHistoryLimit = 5;
    });
```

**After writing code, verify:**
- Every `builder.AddProject<>(...)` in the AppHost has a `Publish*` chained on (except desktop apps if any)
- Every infrastructure resource has a matching Azure-managed `PublishAs*`
- No new `AddProject<>` calls were added — only the existing ones got publishers

### Step 4: Build AppHost

```bash
dotnet build {AppHost.csproj}
```

Fix any compilation errors — common causes:
- Package version conflicts between AppHost SDK and publisher packages
- Missing `Publish*` extension methods (check publisher package was added by `aspire add`)
- Incompatible publisher package version for the current AppHost SDK version

### Step 5: Startup Smoke-Test

Build passing is not sufficient — publisher packages and `Publish*` configuration can cause runtime failures. Verify the AppHost starts cleanly:

```bash
aspire start
aspire wait {first-resource-name}
aspire describe
aspire stop
```

**What to check in `aspire describe` output:**
- All expected resources appear (projects + infrastructure)
- No resource is in a `Failed` or `Error` state
- Publisher resources (e.g., `aca-env`, `k8s-env`) appear in the resource list

**If startup fails:**
- `aspire logs {resource-name}` to get failure details
- Common causes: publisher package version mismatch with AppHost SDK, `Publish*` call on an unsupported resource type
- Fix the issue and repeat Steps 4–5

---

## Completion Surfaces

After all tasks are marked done, surface the following.

### Inner-Loop Only

```
✅ Aspire integration complete!

Dashboard: {full dashboard URL with login token — from aspireify summary}

Resources:
  {name}  {type}  {status}
  ...

Skipped projects (incompatible TFM):
  {project} ({tfm}) — upgrade using the .NET Version Upgrade scenario when ready

Deferred items:
  {item} — {actionable next step}
```

> **Fallback:** If aspireify's summary is missing the URL or login token, run `aspire start` and use the URL printed by the CLI — that is the canonical source.

### Azure-Ready (additional)

After the inner-loop summary, add:

```
Azure deployment readiness:
  Publisher: {ACA / AKS}
  All deployable projects have Publish* configuration.
  AppHost builds successfully.

When you're ready to deploy:
  Run `aspire deploy` in your terminal, use the Aspire CLI directly, or any
  preferred deployment tool. First run will ask for Azure subscription,
  resource group, and region.
```
