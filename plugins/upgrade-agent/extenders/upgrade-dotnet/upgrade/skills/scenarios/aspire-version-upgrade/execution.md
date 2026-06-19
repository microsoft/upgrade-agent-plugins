# Execution Instructions (Phase 4)

Detailed execution instructions for SKILL.md Phase 4. Read this file completely when entering the execution phase.

## Contents

- [Task Execution Order](#task-execution-order)
- [Task: Update Aspire CLI](#task-update-aspire-cli)
- [Task: Upgrade TFM](#task-upgrade-tfm)
- [Task: Run Aspire Transforms](#task-run-aspire-transforms)
- [Task: Build and Fix Errors](#task-build-and-fix-errors)
- [Task: Run aspire agent init](#task-run-aspire-agent-init)
- [Task: Validation Gate](#task-validation-gate)
- [Aspire CLI Quick Reference](#aspire-cli-quick-reference)

This file **supplements** the system task-execution skill — it provides Aspire-upgrade-specific implementation details for each task type.

**Also load these shared references:**
- [../aspire-integration/aspire-cli.md](../aspire-integration/aspire-cli.md) — CLI command reference with agent-safe/unsafe prescriptions

---

## Task Execution Order

Execute tasks in the order defined in the approved `plan.md`. The standard order is:

```
1. Update Aspire CLI
2. Upgrade TFM (if needed)
3. Run Aspire transforms (packages, code, SDK)
4. Consolidate AppHost SDK format (if needed)
5. Migrate config files (if needed)
6. Build and fix errors
7. Run aspire agent init (if needed)
8. Validation gate (user confirms)
```

---

## Task: Update Aspire CLI

### If not installed:
```bash
dotnet tool install -g aspire.cli
```

### If outdated:
```bash
# Preferred (13.2+):
aspire update --self

# Fallback:
dotnet tool update -g aspire.cli
```

### Verification:
```bash
aspire --version
```

---

## Task: Upgrade TFM

Update `<TargetFramework>` across all projects that need it.

### Implementation

For each project needing TFM upgrade:

1. Open the `.csproj` file
2. Replace `<TargetFramework>{old_tfm}</TargetFramework>` with `<TargetFramework>{new_tfm}</TargetFramework>`
3. For multi-targeted projects: update the relevant TFM in `<TargetFrameworks>` list

### TFM Mapping

| Target Aspire | Required TFM Change |
|--------------|-------------------|
| 13.x | All projects → `net10.0` |
| 9.x | Recommended: `net9.0` (net8.0 still works) |

### Important Notes

- Update **all** projects in the solution, not just Aspire-specific ones — `net10.0` runtime must be consistent
- ServiceDefaults project must also be updated
- AppHost project must also be updated
- Test projects should be updated too
- If using `global.json` to pin SDK version, update it to match (e.g., `10.0.100` for net10.0)

### After TFM Update

Run `dotnet restore` to ensure all packages resolve against the new TFM before proceeding to transforms.

---

## Task: Run Aspire Transforms

This is where the Upgrade Assistant engine does the heavy lifting. The engine applies all applicable transformers based on the project's traits:

### What the Engine Handles Automatically

| Transform | Engine Component | What It Does |
|-----------|-----------------|-------------|
| Package version bumps | `AspirePackageMapTransformer` | Upgrades all `Aspire.*` packages to latest via `Aspire.packagemap.json` |
| Package renames | `AspirePackageMapTransformer` | NodeJs→JavaScript, AIFoundry→Foundry, Hosting→Hosting.AppHost |
| Type renames | `AspireTypeMapTransformer` | `AzureConstructResource`→`AzureProvisioningResource`, AIFoundry types, etc. |
| Method renames | `AspireMemberMapTransformer` | `UseEmulator`→`RunAsEmulator`, `AddNpmApp`→`AddJavaScriptApp`, `WithSecretBuildArg`→`WithBuildSecret`, etc. |
| Client method renames | `AspireMemberMapTransformer` | `AddAzureOpenAI`→`AddAzureOpenAIClient`, `AddRedis`→`AddRedisClient`, etc. |
| Fluent chain refactors | `AspireTwoChainedFunctionsTransformer` | `.AddPostgres().AsAzure...()`→`.AddAzurePostgres...()` patterns |
| AddNodeApp arg swap | `AspireAddNodeAppArgumentTransformer` | Swaps args 2 & 3 for 13.0 signature change |
| SDK version update | `ProjectSdkTransformer` | Updates `Aspire.AppHost.Sdk` to latest version |
| SDK format consolidation | `ProjectSdkTransformer` | Migrates child `<Sdk>` to `Sdk=` attribute, removes redundant `Aspire.Hosting.AppHost` |
| Extension method packages | `AspireExtensionMethodsPackagesTransformer` | Discovers used extension methods and adds required packages |
| Config migration | `AspireConfigJsonMigrationTransformer` | Merges legacy config files to `aspire.config.json` |
| Launch settings | `LaunchSettingsJsonTransformer` | Ensures HTTPS/OTLP endpoints configured |
| Lifecycle hook warning | `AspireLifecycleHookTransformer` | Warns about obsolete `IDistributedApplicationLifecycleHook` |

### Running the Engine

The Upgrade Assistant agent invokes the engine through the standard upgrade workflow. The Aspire traits (`UpgradeAspireApplication`, `AspireHost`) gate which transformers run:

- **All Aspire projects** get: package transforms, type/member maps, extension method discovery
- **AppHost projects only** get: SDK transformer, launch settings, chain transforms, config migration

### What the Engine Does NOT Handle (manual steps)

After the engine runs, check for these patterns that require manual intervention:

| Pattern | Action |
|---------|--------|
| `IDistributedApplicationLifecycleHook` implementations | Warn user — needs structural refactoring to `IDistributedApplicationEventingSubscriber`. Load [breaking-changes.md](breaking-changes.md) section "Migration Guides" for code examples |
| `WithPublishingCallback` usage | Warn user — replaced by `WithPipelineStepFactory` + `aspire do`. Provide migration example |
| `AllocatedEndpoint` direct construction | Warn user — constructor signature changed in 13.0 (added `NetworkIdentifier`) |
| Custom `IDistributedApplicationPublisher` | Warn user — replaced by `PipelineStep` |

---

## Task: Build and Fix Errors

After all transforms run:

```bash
dotnet build {solution_path}
```

### Common Post-Transform Errors

| Error | Likely Cause | Fix |
|-------|-------------|-----|
| `CS0246: type or namespace 'X' not found` | Package rename missed a using directive | Add `using` for new namespace or install missing package |
| `CS1503: argument type mismatch` | Argument reorder didn't cover all overloads | Check method signature and adjust arguments manually |
| `CS0619: 'X' is obsolete` | Using an API marked `[Obsolete]` | Review the obsolescence message and migrate to recommended replacement |
| `CS0117: 'X' does not contain a definition for 'Y'` | API removed without replacement in maps | Check [breaking-changes.md](breaking-changes.md) for the migration path |
| `NETSDK1045: current SDK does not support target` | .NET SDK not installed for target TFM | Install the required SDK version |

### Iterative Fix Cycle

1. Build
2. Review errors
3. Fix the most common/blocking errors first
4. Rebuild
5. Repeat until clean

---

## Task: Run `aspire agent init`

⚠️ **This is a user action — never run it as the agent.**

If the assessment determined that Aspire agent/MCP/skills are not configured:

> **Set up Aspire AI agent integration:**
>
> Aspire {target_version} includes AI agent support with MCP server, skill files, and CLI agent commands.
>
> Please run this in your terminal:
> ```
> aspire agent init
> ```
>
> This will:
> - Install Aspire-specific skill files in your repo
> - Configure MCP server for AI agent access to your running AppHost
> - Set up `aspire agent mcp` for live telemetry access
>
> ⏸️ **Please run it now and reply when done.** (You can skip this — it's optional but recommended.)

Wait for user to confirm or skip.

---

## Task: Validation Gate

### Start and Verify

```bash
# Start the AppHost
aspire start

# Check all resources are running
aspire describe

# Verify environment health
aspire doctor
```

Or use Aspire MCP tools if available for live inspection.

### User Confirmation

> **⏸️ Validation checkpoint:**
>
> The solution builds and the AppHost starts successfully.
>
> **Please verify:**
> 1. Open the Aspire Dashboard and confirm all services appear
> 2. Test your application's core functionality
> 3. Check for any error logs or failed health checks in the dashboard
>
> **Does everything work correctly?**

Wait for user confirmation before proceeding to post-upgrade guidance.

### Cleanup

```bash
aspire stop
```

---

## Aspire CLI Quick Reference

For the full CLI command reference with agent-safe/unsafe prescriptions, load [../aspire-integration/aspire-cli.md](../aspire-integration/aspire-cli.md).

Key commands for the upgrade workflow:

| Command | Purpose | Agent-Safe? |
|---------|---------|-------------|
| `aspire --version` | Check CLI version | ✅ Yes |
| `aspire update` | Update all Aspire packages | ✅ Yes |
| `aspire update --self` | Update the CLI itself | ✅ Yes |
| `aspire doctor` | Environment diagnostics | ✅ Yes |
| `aspire start` | Start AppHost (detached) | ✅ Yes |
| `aspire describe` | View resource state | ✅ Yes |
| `aspire stop` | Stop AppHost | ✅ Yes |
| `aspire agent init` | Initialize agent/MCP/skills | ❌ Interactive — user must run |
| `aspire deploy` | Deploy to Azure | ❌ Interactive — user must run |
