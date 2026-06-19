# Aspire CLI Command Reference

Quick reference for Aspire CLI commands used in this scenario. See [aspire.dev/reference/cli](https://aspire.dev/reference/cli/commands/aspire/) for full documentation.

---

## Agent-Safe Commands (non-interactive)

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `aspire --version` | Check CLI version | Phase 0.3a, Task 01 re-verify |
| `dotnet tool install -g aspire.cli` | Install Aspire CLI | Phase 0.3a — if missing |
| `dotnet tool update -g aspire.cli` | Update Aspire CLI | Phase 0.3b — always run when CLI present |
| `aspire agent init --non-interactive --nologo --skills aspire,aspireify --skill-locations github` | Install aspire + aspireify skills | Phase 0.3c — if skills missing |
| `aspire init --non-interactive --suppress-agent-init --nologo` | Create AppHost skeleton + aspire.config.json | Task 01 Step 2 — agent-safe with these flags |
| `aspire add azure-appcontainers` | Add ACA publisher packages | Task 03 Step 2 — non-interactive |
| `aspire add azure-aks` | Add AKS publisher packages | Task 03 Step 2 — non-interactive |
| `aspire describe` | Describe resources in a running AppHost | Phase 6 — get final resource status |
| `aspire ps` | List running AppHosts | Check if AppHost already running |
| `aspire add --list` | List all available integration aliases | Look up integration aliases before running `aspire add` |
| `aspire docs search <topic>` | Search Aspire documentation by topic | Look up guidance when wiring AppHost code or Publish* calls |
| `aspire docs api search <query>` | Search the Aspire API reference | Look up Aspire APIs/types when writing AppHost or publisher code |

---

## `aspire init` — Agent-Safe Usage

`aspire init` with the correct flags is **agent-safe**:

```bash
aspire init --non-interactive --suppress-agent-init --nologo
```

- `--non-interactive`: skips all interactive prompts, uses defaults
- `--suppress-agent-init`: skips the internal `aspire agent init` step (skills already installed by Phase 0.3c)
- `--nologo`: suppresses the banner for clean output

**Pre-flight check**: Phase 0.2 detects existing AppHost projects. If an AppHost is already present, `aspire init` is skipped (handled by the `aspire_init_needed` flag). UA does not separately probe for `aspire.config.json` — that is internal Aspire CLI state.

**What `aspire init` produces** depends on the repository type — the exact layout is determined by the Aspire CLI. Do not inspect, move, or recreate any files it creates.

---

## Commands UA May Call After aspireify Completes

During Task 02, aspireify owns the AppHost wiring and runs whatever Aspire CLI commands it needs internally — UA does not enumerate or shadow that work. After aspireify finishes, UA may call a small set of runtime commands for post-delegation verification (e.g., the Task 03 Step 5 smoke-test):

| Command | UA usage |
|---------|----------|
| `aspire start` | Start the AppHost for smoke-test or to retrieve the dashboard URL |
| `aspire wait <resource>` | Wait for a resource to reach a ready state |
| `aspire describe` | Inspect resources in a running AppHost (also Phase 6) |
| `aspire logs <resource>` | Diagnose a resource that failed to start |
| `aspire stop` | Stop the AppHost after smoke-test |

Any other Aspire CLI command observed in aspireify's output is aspireify's concern. Do not invoke aspireify-internal commands directly from UA.

---

## `aspire add` — Two Categories of Aliases

 `aspire add` is the same command in both cases; the behavior is determined by which alias you pass. Do not confuse these alias categories:

| Alias Category | Who calls it | Examples | What it does |
|------|-------------|---------|--------------|
| **Hosting integrations** | aspireify internally | `postgres`, `redis`, `kafka` | Adds `Aspire.Hosting.*` packages for inner-loop orchestration |
| **Publishing targets** | UA (Task 03) | `azure-appcontainers`, `azure-aks` | Adds deployment publisher packages |

UA only calls the publishing-target alias. Never call hosting-integration aliases directly — aspireify owns those.

### Publisher Aliases

| Alias | Package Added | Use Case |
|-------|---------------|----------|
| `azure-appcontainers` | `Aspire.Hosting.Azure.AppContainers` | ACA deployment (recommended default) |
| `azure-aks` | `Aspire.Hosting.Azure.AKS` | AKS deployment |

Run `aspire add --list` to see all available aliases.

---

## Commands to NEVER Run as Agent

| Command | Why |
|---------|-----|
| `aspire deploy` / `aspire do <step>` | Requires interactive Azure authentication — user must run manually |
| `dotnet workload install aspire` | The Aspire workload is obsolete — never install it |
