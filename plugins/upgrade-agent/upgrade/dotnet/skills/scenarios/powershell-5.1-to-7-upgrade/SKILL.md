---
name: powershell-5.1-to-7-upgrade
description: >
  Upgrade Windows PowerShell 5.1 scripts (.ps1/.psm1/.psd1) to cross-platform
  PowerShell 7.x. Use when the user asks to upgrade PowerShell scripts, move
  off Windows PowerShell 5.1, migrate WMI to CIM, remove PSSnapins, or make
  scripts run on PowerShell 7 / pwsh. Covers loose scripts that ship alongside a
  .NET repo — NOT binary cmdlet/PowerShell-SDK projects (those use the
  migrating-powershell-sdk lazy skill in the normal .NET version upgrade).
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: default
  weight: 0
  traits: PowerShell
  scenarioTraitsSet: [PowerShell]
---

# PowerShell 5.1 → 7 Upgrade Scenario

Upgrade Windows PowerShell 5.1 scripts so they run on cross-platform
PowerShell 7 (`pwsh`). This scenario targets **loose scripts**
(`.ps1`/`.psm1`/`.psd1`) — build, deploy, and ops automation that ships in a
repository.

## What this migration actually is (edition, not minor version)

The hard part of "5.1 → 7" is a **runtime edition** change, not a version bump:

| | Windows PowerShell | PowerShell 7 |
|---|---|---|
| Edition | **Desktop** | **Core** |
| Runtime | .NET Framework | .NET (Core) |
| Last/target | 5.1 (final Windows PowerShell) | current supported 7 LTS |

Every blocker this scenario detects (PSSnapins, WMI, `*-EventLog`, Windows-only
modules, `powershell.exe`, `#Requires -PSEdition Desktop`) stems from the
**Desktop(.NET Framework) → Core(.NET)** break that happened at the 5.1 → 6.0
boundary — **not** from any specific 7.x minor. Treat the target as "current
supported PowerShell 7 LTS," parameterized as `targetPowerShellVersion` (see
Stage 0), rather than a pinned minor. Rolling forward within 7.x later
(e.g. 7.4 → 7.6) is a routine framework bump, not a re-run of this scenario.

## The compatibility layer is a last resort

`Import-Module -UseWindowsPowerShell` does not port anything. It starts a hidden
**Windows PowerShell 5.1 child process** (`powershell.exe`) and proxies the
module's commands over an implicit remoting session into it. A script that
relies on it still requires Windows PowerShell 5.1 to be installed and still
runs the old code — the 5.1 dependency has been hidden, not removed. It is also
Windows-only, so it forecloses the cross-platform half of the goal.

Consequences that bind every stage:

- **Try natively first, always.** Many "Windows-only" modules are CDXML/CIM
  based and import into PS7 unchanged once the RSAT/optional feature is
  installed. Prefer a real module replacement, then a native import, then a
  supported remote endpoint.
- **A compat-layer landing is a deferral, not a remediation.** Record it as
  deferred with the reason, and count it as such in the report. Do not close a
  task, or claim a blocker remediated, on the strength of a shim.
- **Reach for it only when the alternative is "the script cannot move at all."**
  If most of the estate lands on the shim, the honest finding is that this
  estate is not ready to leave 5.1 — say that instead of reporting a green
  migration.

Objects returned through the layer are deserialized: properties survive,
methods do not. Any downstream `.Method()` call on a proxied object is a defect
even when the import itself succeeds.

## Scope: scripts, not SDK projects

There are two different "PowerShell + .NET" cases. Route correctly:

| Artifact | Route |
|---|---|
| Loose `.ps1` / `.psm1` / `.psd1` scripts | **This scenario.** |
| A `.csproj`/`.vbproj`/`.fsproj` that references `System.Management.Automation` / `PowerShellStandard.Library` (binary cmdlet or PS hosting) | The **`migrating-powershell-sdk`** lazy skill, run as part of `dotnet-version-upgrade`. It is a reference/TFM swap, validated by `dotnet build`. |

A mixed repo has both. Handle the SDK **projects** through the normal .NET
version upgrade, and the **scripts** through this scenario. If a `.psm1` is a
binary module's manifest companion, note the link but still port the script
text here.

## Partial scope

A **partial** migration — a named handful of scripts, or a subtree of a larger
estate — is not a smaller version of the full job. The scripts you do not touch
stay on Windows PowerShell 5.1, and they keep calling the ones you do. Two
consequences drive every later stage:

1. **The selection must be closed over dot-sourcing.** A selected script that
   dot-sources an unselected library is not fixed when the library still calls
   `Get-WmiObject` — it fails at runtime, and nothing catches it, because there is
   no compiler and the scan reports per file. Pull the transitive dot-source
   dependencies of the selection *into* the selection. See
   [assessment.md](assessment.md) Step 4.
2. **Anything shared must stay runnable on 5.1.** Closure drags in shared
   libraries whose *other* callers are out of scope and still 5.1. Some
   remediations are bi-compatible and some are one-way doors that break those
   callers on the spot. This reorders the plan — see the ordering rule and the
   one-way table in [planning.md](planning.md) Step 2.

Record in `scenario-instructions.md` that scope is partial, the selection after
closure, and which files are shared with out-of-scope callers. Execution needs all
three. If the selection closes over so much of the estate that little is left out,
say so and offer a full-scope run instead — partial scope costs bi-compatibility
constraints that a full migration simply does not pay.

## When to use / not use

- **Use** when the user wants scripts to run on PowerShell 7, mentions removing
  snap-ins, WMI→CIM, or "get off Windows PowerShell 5.1".
- **Do not use** for a pure C# cmdlet library (that is `migrating-powershell-sdk`),
  or when the user only wants a syntax/style cleanup with no runtime target
  change.

## Workflow Stages

Run these stages in order:

0. **Pre-Initialization** — Establish prerequisites (PowerShell 7 +
   PSScriptAnalyzer), then confirm script scope + `targetPowerShellVersion` +
   platform intent. Consumed during pre-initialization by the scenario-initializer
   worker.
1. **Assessment** — Inventory every 5.1 → 7 blocker across the scoped scripts into
   `assessment.md` (+ `scan-findings.csv`). Uses the
   `scanning-powershell-compatibility` lazy skill.
2. **Planning** — Bucket findings by blocker class and order the work. Uses the
   `plan-generation` system skill to create `plan.md` and `scenario-instructions.md`.
3. **Execution** — Apply each bucket's remediation via its lazy skill and climb the
   validation ladder per file. Uses the system task-execution skill.

## Pre-Initialization

This section is consumed during pre-initialization by the scenario-initializer worker.
It defines the scenario-specific parameters for this scenario.

### Parameters to Confirm

**Step 0 — Prerequisites.** This scenario needs two tools before any parameter
is worth confirming: **PowerShell 7** (the target engine, and the host the scan
and every validation rung run under) and **PSScriptAnalyzer** (the primary
static gate, Rung 2). Detect both:

```powershell
Get-Command pwsh, powershell -ErrorAction SilentlyContinue |
    Select-Object Name, Version, Source
Get-Module -ListAvailable PSScriptAnalyzer |
    Sort-Object Version -Descending | Select-Object -First 1 Name, Version
```

| Missing | Official install |
|---|---|
| PowerShell 7 — Windows | `winget install --id Microsoft.PowerShell --source winget` |
| PowerShell 7 — other | Follow <https://learn.microsoft.com/powershell/scripting/install/install-powershell> for the platform's package manager |
| PSScriptAnalyzer | `Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Scope CurrentUser` |

**If either is missing, stop and ask the user to install it.** Offer the command
above; never install unprompted. Do not proceed on a degraded path.

These are prerequisites, not preferences, and the reason is specific to this
scenario: **without them the scenario's failure mode is a false pass, not a
missing feature.** An assessment run without PowerShell 7 cannot generate a
compatibility profile, so it cannot see removed commands, parameters, or types —
the bulk of the real work — and reports a short list that reads like a small
migration. An execution run without PSScriptAnalyzer has no primary gate, so
every file "passes" on a parse check alone. Both produce a confident, clean-looking
result that is wrong in the one direction that matters, which is worse than no
result at all. Migrating on that basis means finding the blockers in production.

If the user cannot install them at all, say plainly that the scenario cannot run
here and stop. A partial answer presented as an inventory is the failure this
scenario exists to prevent.

Report both versions found. They belong in the assessment, because scan
fidelity and gate strength both depend on them.

**The assessment is generated *on this host, for this host.*** The compatibility
profile that drives the analysis is built by reflecting over the running
PowerShell 7 installation, so the assessment describes the platform and the
PowerShell build you are standing on. Confirm in Step 3 that this is the
platform the user is actually migrating **to**.

**Step 0b — Module versions to pin.** The profile inventories whatever module
versions are on `PSModulePath` at generation time, so the analysis is only as
accurate as the module set behind it. If the machine's version of a module
differs from the one the estate actually loads, the profile describes a command
surface the scripts never see — and a parameter that exists in the machine's copy
but not the estate's is silently accepted, which is a false negative.

Ask which versions the estate actually targets for any module whose command
surface changed across majors. **Pester is the usual example** — Windows ships an
old copy in-box, and its `Should` has a different parameter shape from modern
Pester, so a profile built over the wrong one disagrees with the test suite about
every assertion. The same reasoning applies to any module the estate pins.

Look in three places, most authoritative last:

1. **Manifests.** `RequiredModules` in any `.psd1`.
2. **Imports in the scripts themselves.** `Import-Module`, `#Requires -Modules`.
3. **The estate's own initialization script.** Repo bootstrap files
   (`init.ps1`, `bootstrap.ps1`, `Setup.ps1`, `build.ps1`, profile scripts,
   `*.psm1` module loaders) and the environment setup steps in CI definitions.
   This is the most authoritative source and the one most often missed: a
   bootstrap that runs `Install-Module Pester -RequiredVersion 5.5.0` or
   prepends a vendored path to `PSModulePath` defines what the estate *actually*
   loads, regardless of what the manifests declare.

```powershell
Get-ChildItem -Path <scope> -Include *.ps1,*.psm1,*.psd1 -Recurse -File |
    Select-String -Pattern 'RequiredModules|Import-Module|#Requires\s+-Modules|Install-Module|PSModulePath'
```

Run the initialization script's module setup before generating the profile where
that is practical — a profile generated against the environment the estate builds
for itself needs no reconciliation afterwards.

Record the answer as `requiredModules` (for example `Pester:5.0:5.99`) and pass
it through to Stage 1.

The pin recorded here is what the estate loads today, which is not necessarily
what it can load on PowerShell 7. Stage 1 probes each one and may raise it; do
not settle the question here.

If the repo pins an old Pester, or pins nothing and has been relying on the
in-box copy, note it as candidate migration work. It is **not** a blocker — old
Pester does load and run under PowerShell 7 — but it shadows any newer Pester
whenever an import is unconstrained, and its assertion syntax disagrees with
modern Pester. Pester 5 runs on both 5.1 and 7.x, so it can be done independently
of the host move. The migration itself is covered by the `pester-migration`
skill; do not work it out here.

**Step 0c — How the estate runs its tests.** Establish this now, not during
execution, because it determines whether the migration can be validated at all.
Two separate questions:

1. **What is the entry point?** Rarely a bare `Invoke-Pester`. Look for a repo-root
   runner (`build.ps1`, `Invoke-Build.ps1`, `psake.ps1`, `test.cmd`), then CI
   definitions (`.github/workflows/*.yml`, `azure-pipelines*.yml`) — CI is the most
   reliable statement of how the suite is actually run — then `tasks.json`,
   `CONTRIBUTING.md`, `README`. The wrapper usually supplies imports, `PSModulePath`,
   fixtures, credentials and tag filters that calling Pester directly omits.
2. **Are the tests safe to run?** PowerShell suites are often not hermetic: they
   create AD objects, write registry keys, restart services, or hit production
   endpoints. Running them is a side effect on the user's environment. Flag
   integration-style suites now and agree what may be executed unattended, so
   execution does not have to stop and ask per task.

Record both as `testEntryPoint` and `testSafety`
(`unit` | `mixed` | `integration` | `none-found`). "No test entry point found" is a
legitimate result — record it rather than inventing a command, and carry it into the
assessment as a validation-confidence caveat.

**Step 1 — Scope.** Determine which scripts are in scope: the whole repo, a
subtree (e.g. `build/`, `deploy/`), or a named handful of scripts. Loose
`.ps1`/`.psm1`/`.psd1` only — see
[Scope: scripts, not SDK projects](#scope-scripts-not-sdk-projects) for the
SDK-project routing rule.

The scan accepts directories and individual files, but normalize to a single
absolute root path anyway so the inventory has one stable base to report against.
For a whole repo or a subtree that root *is* the scope. For a named handful it is
only the nearest common ancestor — record the selected files separately as the
**selection**, and read [Partial scope](#partial-scope) before going further,
because a partial migration is a materially different job from a full one.

**Step 2 — `targetPowerShellVersion`.** The PowerShell 7 release to validate
against. This is an *edition* move (Desktop → Core); the minor only selects the
PSScriptAnalyzer validation profile, not the work.

Do not carry a hardcoded minor in your head — pick it the way the .NET scenario
picks a target framework: from a lifecycle table, taking the **newest LTS that
is still supported**, preferring one already installed on the machine.

| PowerShell | Built on | State | End of support |
|---|---|---|---|
| 7.4 | .NET 8 | LTS | 2026-11-10 |
| 7.5 | .NET 9 | STS | 2026-11-11 |
| 7.6 | .NET 10 | **LTS** | 2028-11-14 |

PowerShell tracks the .NET release train, so an LTS PowerShell sits on an LTS
.NET and shares its end-of-support date (7.6 ↔ .NET 10, both ending
2028-11-14). Selection rule, in order:

1. Newest row with state **LTS** whose end-of-support is later than today.
2. If that release is already installed (Step 0 reports what is), take it.
3. Otherwise still target it, and note it as the version the user should
   install — do not silently downgrade the target to whatever happens to be on
   the box.

Only pin a different minor if the user asks. If today's date is past every row
in the table, the table is stale: say so, use the newest installed 7.x, and do
not invent a version number.

**Then make sure that version is the one you are running.** The choice is not
cosmetic: the compatibility profile is generated by reflecting over the *running*
`pwsh`, so whichever `pwsh` is on `PATH` — not the version agreed here — is what
actually defines the analysis. The two directions are not symmetric:

| Host vs target | Effect | Verdict |
|---|---|---|
| Host newer (generate 7.6, deploy 7.4) | Profile is a superset. Everything added since the target is inventoried as present and its findings suppressed. Code passes the rescan and fails in production. | False negative — warn and fix |
| Host older (generate 7.4, deploy 7.6) | Profile is a subset. Can only over-report. | Safe |

So if the agreed target is not installed, **stop and ask the user to install that
version** before assessing, rather than proceeding on whatever is present. The
version on `PATH` is not a detail the assessment can note and move past — it
silently determines what the analysis can see, and the dangerous direction
produces a clean result rather than an error.

**Step 3 — Platform intent.** Ask two separate questions; they are not the same,
and conflating them silently produces an assessment for the wrong operating
system.

1. **Must the scripts stay Windows-only, or become cross-platform?** Exchange,
   Active Directory, WMI, and cluster work is Windows-bound, and the answer
   changes how much of the estate can reach a native PS7 landing — see
   [The compatibility layer is a last resort](#the-compatibility-layer-is-a-last-resort).
2. **Which platform will the upgraded scripts run on?** Compare it to the host
   you are running on right now (`$PSVersionTable.Platform` /
   `$IsWindows`/`$IsLinux`/`$IsMacOS`).

If the two differ, **stop and say so before assessing.** The compatibility
profile is built by reflecting over the *running* installation, so a profile
generated on macOS has no `Get-CimInstance`, no WMI, no registry provider, and no
Windows-only assemblies — assessing a Windows estate against it reports the
entire estate as broken. The reverse is worse: a Windows-generated profile
assessed for a Linux target reports Windows-only code as *fine*, which is a false
negative in exactly the class the user cares about.

There is no way to generate a profile for a platform you are not on. Either move
to a host of the target platform, or continue and record the mismatch as a
first-class caveat at the top of the assessment.

**Step 4** — Proceed with the confirmed prerequisites, scope, target version,
and platform intent, passing them to `initialize_scenario` and then to the
assessment stage.

## Stage Instructions

**IMPORTANT**: Load each stage's instructions file **only when entering that stage**
(not all upfront).

### Stage 1: Assessment
**When entering this stage, load**: [assessment.md](assessment.md)

Runs the `scanning-powershell-compatibility` scan over the confirmed scope. Writes
the blocker inventory to `assessment.md` with a `scan-findings.csv` lookup table
beside it.

### Stage 2: Planning
**When entering this stage, load**: [planning.md](planning.md)

Buckets findings by blocker class, orders them mechanical-first, and accounts for
dot-source dependency order. Uses the `plan-generation` system skill for file format
to produce `plan.md`, and persists the target version, platform intent, and validation
policy in `scenario-instructions.md`.

### Stage 3: Execution
**When entering this stage, load**: [execution.md](execution.md)

Applies each bucket's remediation via the lazy skill the plan attached to the task,
re-scans to confirm the finding cleared, and validates each file against the validation
ladder.

## Blocker Severity Model

The scan assigns every finding one severity, from the rule catalog. All three
stages key off it:

| Severity | Meaning | Handling |
|---|---|---|
| **Blocker** | Removed in PS7; will not run | Must be remediated (architectural) |
| **Manual** | Works only via a compatibility shim | Needs judgement per call site |
| **AutoFix** | Deterministic mechanical rewrite | Batch-apply early |
| **Advisory** | Still works / code quality | Optional; do not block completion |

## Success Criteria

Rung numbers refer to [validation-ladder.md](validation-ladder.md).

- Every in-scope script parses under `pwsh` (Rung 1) and is clean under
  PSScriptAnalyzer `PSUseCompatible*` for the `targetPowerShellVersion` profile
  (Rung 2).
- All **Blocker**-severity findings are remediated or explicitly deferred with a
  recorded reason.
- Dot-sourced libraries and their callers are consistent (re-scanned).
- Per-file validation rung is recorded; `manual-signoff` items are surfaced as a
  human-review queue rather than claimed complete.
- Anything landing on `Import-Module -UseWindowsPowerShell` is reported as
  **deferred**, with a count. A run whose blockers were cleared mainly by the
  compatibility layer has not met this scenario's goal, and the report must say
  so rather than show green.

Under [partial scope](#partial-scope), additionally: the selection is closed over
dot-sourcing, files shared with 5.1 callers parse under **both** hosts, and the
one-way findings deferred to keep them working are reported as deferred — not as
remediated, and not as failures.

## Constraints

- The scan output is the assessment — do not fabricate a parallel inventory, and
  do not substitute `Select-String`/grep for it. `scanning-powershell-compatibility`
  explains why text search produces both false positives and false negatives here.
- Do not "fix" Advisory-only items (e.g. `$x -eq $null`) as a gate to
  completion; offer them as an optional batch.
- Exchange / AD / cluster behavioral parity requires a live environment this
  agent does not own. Be explicit about that limit; do not claim runtime
  validation you cannot perform.
- SDK/binary cmdlet **projects** are out of scope here — route them to
  `migrating-powershell-sdk`.

## Related skills

Detection lives in one lazy skill; remediation content lives in six more, one per
blocker bucket. Planning attaches the right one to each task with a `#skill:`
marker — see the table in [planning.md](planning.md); do not restate their content
in the plan.

- `scanning-powershell-compatibility` — the detection scan and its rule catalog.
  Used by assessment, by execution's per-file re-scan gate, and by the final
  re-scan. Users extend the catalog to add their own rules.
- `powershell-mechanical-fixups` — batch auto-fixes.
- `migrating-wmi-to-cim`, `replacing-eventlog-with-winevent`,
  `handling-removed-snapins`, `migrating-exchange-management-shell`,
  `fixing-windows-only-modules` — per-blocker remediation.
- `migrating-powershell-sdk` — the sibling case for binary cmdlet/SDK projects.
