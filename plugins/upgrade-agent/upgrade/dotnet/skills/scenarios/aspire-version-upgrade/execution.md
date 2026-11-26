# Execution Instructions (Phase 4)

Detailed execution instructions for SKILL.md Phase 4. Read this file completely when entering the execution phase. It supplements the executor's core task-execution steps.

The CLI command reference is at the end of this file: [Aspire CLI Quick Reference](#aspire-cli-quick-reference).

## Contents

- [Task Execution Order](#task-execution-order)
- [Step 0: Check SDK and Target Frameworks](#step-0-check-sdk-and-target-frameworks)
- [Update Aspire CLI](#update-aspire-cli)
- [Step 1: Run aspire agent init](#step-1-run-aspire-agent-init)
- [Step 2: Update Versions](#step-2-update-versions)
- [Step 3: Apply Code and File Changes](#step-3-apply-code-and-file-changes)
- [Step 4: Validation Gate](#step-4-validation-gate)
- [Aspire CLI Quick Reference](#aspire-cli-quick-reference)

---

## Task Execution Order

Execute tasks in the order defined in the approved `plan.md`. The standard order is:

1. Check SDK and target frameworks (Step 0)
2. Update Aspire CLI
3. Run `aspire agent init` (Step 1)
4. Update versions (Step 2)
5. Apply code and file changes (Step 3)
6. Validation gate (Step 4)

All steps are done by hand-editing files and running the Aspire CLI.

---

## Step 0: Check SDK and Target Frameworks

Check minimums only. Do not retarget any project.

| Check | Minimum | If below |
|-------|---------|----------|
| .NET SDK (`dotnet --version`, `global.json`) | Required SDK for the target from [breaking-changes.md](breaking-changes.md#sdk-and-tfm-requirement) (Aspire 13 needs the .NET 10 SDK) | Raise the `global.json` pin to that SDK band; this change must already be listed in the approved plan. If the SDK is not installed, stop and ask the user to install it. |
| TFM of the AppHost, ServiceDefaults and every project that references an `Aspire.*` package | `net8.0` or later through 13.2 (a multi-targeted project needs at least one); for higher targets, the minimum recorded in assessment Step 4.1 | Stop. List the projects and suggest running the .NET Version Upgrade scenario first, then return here. |
| TFM of other projects | Not checked | None |
| .NET 10 SDK installed (`dotnet --list-sdks`), for the Aspire CLI | Any 10.0 SDK, for every target, including 8.x and 9.x | Stop and ask the user to install it. Do not change the `global.json` pin for this. |

Run this before updating the CLI, because the Aspire CLI 13.3 or later runs on .NET 10.

---

## Update Aspire CLI

| State | Command |
|-------|---------|
| Not installed | `dotnet tool install -g aspire.cli` |
| Installed | `aspire update --self --non-interactive` (fallback: `dotnet tool update -g aspire.cli`; CLI 9.x has no `--self`) |

Verify with `aspire --version`. The steps below need CLI 13.3 or later: `docs`, `restore`, `doctor`, `otel` and the smoke-run commands first appear in 13.2.0, and `update --yes` and `agent init --skills` in 13.3.0. If the version is still below 13.3, run the fallback; if it stays below, stop and ask the user to update the CLI.

If assessment Step 4.1 could not check the minimums for a target above 13.2 (the CLI was missing or too old for `aspire docs`), check them now and apply the Step 0 rules to any raised minimum before continuing.

The CLI version is independent of the target Aspire version; a newer CLI can upgrade to an older target.

---

## Step 1: Run `aspire agent init`

Run it as the agent; it does not need the user:

```bash
aspire agent init --non-interactive --nologo --skills aspire --skill-locations github
```

It installs the upstream `aspire` skill only (never pass `--skills all`): `.github/skills/aspire/SKILL.md` and `.github/skills/aspire/references/*.md`. The plan lists this task as optional with these files; skip it if the user declined it. The skill covers general Aspire usage, not upgrades; if the command fails, continue without it.

**Upgrade guidance for targets above 13.2** comes from the Aspire docs, not this skill: `aspire docs get upgrade-aspire-to-the-latest-version` for the general steps, and `aspire docs get whats-new-in-aspire-<major><minor>` (for example `whats-new-in-aspire-133` for 13.3) for each version crossed; its "Breaking changes" section lists what to fix. If a slug is not found, find it with `aspire docs list` (the titles are "What's new in Aspire <version>"); `aspire docs search` does not rank these pages well. If the docs are unreachable (offline), continue with [breaking-changes.md](breaking-changes.md) and the Step 4 gate only, and tell the user that changes after 13.2 that the compiler does not flag may need manual review.

---

## Step 2: Update Versions

First run `dotnet build {solution_path} --no-incremental` and record its `CS0618` and `ASPIRE*` warnings as the baseline for the Step 4 gate. If this build fails, continue without a baseline and treat every such warning as new.

**Target is the latest stable version:**

```bash
aspire update --apphost <apphost.csproj> --channel stable --non-interactive --yes
```

`aspire update` has no version option. It only moves to the latest version on a channel. If it fails (for example, the package feed is unreachable), edit by hand as below.

**Any other target:** edit by hand.

1. Confirm each version exists before writing it: `dotnet package search <id> --exact-match` (add `--prerelease` for preview-only packages such as `Aspire.Hosting.Foundry`).
2. Set the `Aspire.AppHost.Sdk` version and every `Aspire.*` package version to the target. `Microsoft.Extensions.ServiceDiscovery.*` matches the Aspire version only through 9.x; from Aspire 13 it has its own numbers (10.x and later). Never copy the Aspire version to it: for a 9.x target use the same version, otherwise pick the latest stable version that `dotnet package search <id> --exact-match` lists and that restores for the projects' target frameworks.
3. Under central package management (`Directory.Packages.props` with `ManagePackageVersionsCentrally`), edit the `PackageVersion` entries there, not the project files.

**Package renames** (either path; `aspire update` does not rename packages): apply the renames for every version crossed (see [breaking-changes.md](breaking-changes.md)), for example `Aspire.Hosting.NodeJs` becomes `Aspire.Hosting.JavaScript`. Also set the new package's version to the target (or the matching preview version, where its row says so) and confirm it with `dotnet package search <id> --exact-match --prerelease`: the old package's version, which `aspire update` may have left behind (for example 9.x for `Aspire.Hosting.NodeJs`), does not exist for the new ID.

**Crossing from 8.x to a 9.x target** (hand-edit path): add the `Aspire.AppHost.Sdk` element as in [AppHost Project Format (target 9.x)](breaking-changes.md#apphost-project-format-target-9x).

**Crossing from 9.x to 13.0 or later** (either path): convert the AppHost project format, for example `<Project Sdk="Microsoft.NET.Sdk">` plus `<Sdk Name="Aspire.AppHost.Sdk" Version="9.5.2" />` becomes `<Project Sdk="Aspire.AppHost.Sdk/13.x.y">`, and remove the `Aspire.Hosting.AppHost` package. Check the result against [AppHost project file](breaking-changes.md#apphost-project-file), because `aspire update` may not cover every starting shape.

Run `dotnet restore` before Step 3.

---

## Step 3: Apply Code and File Changes

Read only the [breaking-changes.md](breaking-changes.md) sections for the versions crossed. For each version above 13.2, also read the "Breaking changes" section of its `whats-new-in-aspire-<major><minor>` doc (see Step 1).

**Pass 1: changes the build cannot catch.** Search for every item marked **Not caught by the build** in the sections you read and fix it first, for example:

- Every `AddNodeApp` call (arguments 2 and 3 swap in 13.0; see the positional and named cases in [breaking-changes.md](breaking-changes.md#addnodeapp-argument-reorder-9x--130)).
- `aspire.config.json` migration from `.aspire/settings.json` and `apphost.run.json` (13.2+), and missing `launchSettings.json` values. Shapes are in [Project and Configuration File Shapes](breaking-changes.md#project-and-configuration-file-shapes).
- Behavioral changes (credentials, service discovery environment variables, events): fix them when the intent is clear, otherwise list them for the user.

**Pass 2: compiler errors.**

1. `dotnet build {solution_path}`.
2. Fix errors using the rename tables and [Migration Guides](breaking-changes.md#migration-guides).
3. For `CS1061` on an `Add*` method in the AppHost, the hosting package is missing: find it in [Hosting Packages Required by Extension Methods](breaking-changes.md#hosting-packages-required-by-extension-methods) and run `aspire add <integration> --apphost <apphost.csproj> --version <target> --non-interactive`. If the integration name is unknown, run `aspire docs search <method>`.
4. Rebuild until clean.

Structural migrations (lifecycle hooks to eventing subscribers, publishing callbacks to pipeline steps, custom `AllocatedEndpoint` construction) follow the Migration Guides; if a rewrite is unclear, leave it compiling and list it for the user. Treat `AddAzureRedis` to `AddAzureManagedRedis` (13.1+) the same way: switch only if the user approved it in the plan, otherwise list it.

---

## Step 4: Validation Gate

The task is done only when all of these pass:

1. `aspire restore --apphost <apphost.csproj> --non-interactive` succeeds, then `dotnet build {solution_path} --no-incremental` succeeds with no errors.
2. No `CS0618` or `ASPIRE*` warnings come from Aspire APIs beyond the Step 2 baseline, except those from a structural migration you listed for the user in Step 3. Baseline warnings are out of scope; list any that remain for the user.
3. Searching the solution finds none of the old forms from the sections you read, except those of a structural migration you listed for the user in Step 3. Match the old usage, not just the name, because some names stay valid: `AddRedis`, `AddRabbitMQ` and `AddAzureCosmosDB` are old only as client calls in service projects (they are current AppHost methods), `AddAzureKeyVaultSecrets` is old only on the host builder (on `builder.Configuration` it is the current configuration provider), and `AddNodeApp` keeps its name and changes only its arguments.
4. Smoke run: first run `aspire doctor --non-interactive`; if it reports a failure or a stopped container runtime, tell the user what to fix before continuing; if they cannot fix it, skip the smoke run and report it as not done. Otherwise `aspire start --apphost <apphost.csproj> --non-interactive`, `aspire wait <resource>` for the key resources and `aspire describe` to confirm they are healthy. On failure, check `aspire logs <resource>` and `aspire otel logs <resource>` / `aspire otel traces <resource>`, run `aspire stop` so the rebuild is not blocked by locked files, fix and rerun.

Leave the final healthy AppHost running; do not stop it unless the user asks. Give the user the dashboard URL that `aspire start` printed, including its `?t=` login token, and ask them to confirm the application works.

---

## Aspire CLI Quick Reference

| Command | Purpose | Min CLI | Agent-Safe? |
|---------|---------|---------|-------------|
| `aspire --version` | Check CLI version | Any | ✅ Yes |
| `aspire update --self --non-interactive` | Update the CLI itself | 13.0 | ✅ Yes |
| `aspire agent init --non-interactive ...` | Install the upstream `aspire` skill | 13.3 | ✅ Yes |
| `aspire update --apphost <path> --channel stable --non-interactive --yes` | Update to the latest stable version | 13.3 | ✅ Yes |
| `aspire add <integration> --non-interactive` | Add a hosting package | 13.0 | ✅ Yes |
| `aspire restore --apphost <path> --non-interactive` | Restore and generate AppHost SDK code before the build | 13.2 | ✅ Yes |
| `aspire start` / `aspire wait` / `aspire describe` | Smoke run | 13.2 | ✅ Yes |
| `aspire logs` / `aspire otel logs\|traces\|spans <resource>` | Console logs and telemetry of a running AppHost | 13.2 | ✅ Yes |
| `aspire docs get <slug>` / `aspire docs search <term>` / `aspire docs list` | Read aspire.dev docs | 13.2 | ✅ Yes |
| `aspire doctor` | Check the SDK, container runtime and HTTPS certificate before the smoke run | 13.2 | ✅ Yes |
| `aspire stop` | Stop AppHost | 13.2 | Between smoke-run retries, or if the user asks |
| `aspire deploy` | Deploy to Azure | 13.0 | ❌ Interactive — user must run |
