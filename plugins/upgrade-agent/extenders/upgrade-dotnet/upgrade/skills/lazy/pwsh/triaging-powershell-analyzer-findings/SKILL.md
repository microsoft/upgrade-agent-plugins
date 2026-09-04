---
name: triaging-powershell-analyzer-findings
description: >
  Decide whether a PSScriptAnalyzer PSUseCompatibleCommands / PSUseCompatibleTypes
  finding is a real PowerShell 5.1 → 7.x break or one of four measured false-positive
  classes: a function defined elsewhere in the estate, an abbreviated parameter
  prefix such as '-fore', a symbol the compatibility profile dropped during
  generation, or a provider dynamic parameter such as 'Set-ItemProperty -Type'.
  Each class has a mechanical test that settles it. Use during the
  powershell-5.1-to-7-upgrade scenario's execution stage, before editing any file
  the analyzer flagged.
metadata:
  discovery: lazy
  traits: PowerShell
---

# Triaging PowerShell analyzer findings

`PSUseCompatibleCommands` reports a command or parameter as unavailable when it
is **absent from the compatibility profile**. Absence is a proxy for "removed in
7", and the proxy is imperfect in four ways.

Expect the large majority of `PSUseCompatibleCommands` findings to be false
positives, concentrated in the four classes below rather than scattered. Each
class has a test you can run, so **do not edit a flagged line until you have
classified it**.

The reverse error matters more. This scenario optimises for *not missing real
breaks*, which is why the analyzer is run in its noisy configuration. The price
is this triage step. Skipping it produces churn — rewriting working code — not
safety.

## Before you start

Two inputs make most of this mechanical:

- **`<profile>.validation.json`**, written next to the profile by
  `New-PSSACompatibilityProfile.ps1`. Its `MissingCommands` and `MissingTypes`
  arrays are class 3 *enumerated up front*. Read it once.
- **The target host itself.** `Get-Command` and `Get-Member` under
  `pwsh -NoProfile` are ground truth. The profile is a snapshot; the host is the
  thing you are migrating to.

```powershell
# The result object is nested under .Validation -- reading $v.MissingCommands
# directly returns $null, which looks exactly like "no known false positives"
# and silently empties the ledger.
$v = Get-Content .github/upgrades/{scenarioId}/target-profile.validation.json -Raw | ConvertFrom-Json
$v.Validation.MissingCommands   # e.g. Get-WinEvent, Get-Counter
$v.Validation.MissingTypes      # e.g. System.Data.SqlClient.SqlConnection
```

## Read the enrichment before triaging

`Invoke-PSSACompatibilityScan.ps1` joins each PSSA finding against the rule
catalog and stamps five extra fields onto it. The join is deterministic — PSSA
exposes structured `Command` and `Parameter` properties, so a Command-kind rule
matches on the command and a Parameter-kind rule on the command/parameter pair.
You do not need to re-derive any of it.

| Field | What it gives you |
|-------|-------------------|
| `CatalogRuleId` | Stable id, e.g. `wmi-cmdlet`. Use it when recording outcomes. |
| `Category` | Grouping for the assessment, e.g. `Wmi`, `Remoting`, `PSSnapin`. |
| `CatalogSeverity` | **Triage on this.** `Blocker` / `Manual` / `Advisory`. |
| `Skill` | The lazy skill that performs the rewrite, when one exists. |
| `Remediation` | The specific fix, already written. |

`Severity` is PSSA's own field and is `Warning` for **every** compatibility
finding it emits. Ordering work by it tells you nothing; order by
`CatalogSeverity`.

A finding with an empty `CatalogRuleId` is **unenriched**: PSSA is confident the
command is unavailable, but the catalog has no entry describing what to do about
it. That is the judgement case, not a false positive — treat it as real, and work
out the replacement from the target host (`Get-Command` under `pwsh -NoProfile`)
before classifying it below. The scan reports `counts.enriched` and
`counts.unenriched` so the size of that gap is a number rather than a silence.

## Class 1 — the function is defined in the estate

**Symptom.** A finding on a name that is obviously local: `Write-Log`,
`Get-ConfigValue`, `Invoke-Retry`. Usually the largest of the four classes, and a
single file can carry dozens — including calls to a function defined a few lines
above.

**Cause.** PSScriptAnalyzer has no symbol table and does not follow
`.` dot-sourcing or `Import-Module` of a local path. It resolves against the
profile only, so every helper in the repo looks like a missing cmdlet.

**Test.** Search the estate for a definition.

```powershell
Get-ChildItem -Path <root> -Include *.ps1,*.psm1 -Recurse -File |
  Select-String -Pattern "^\s*(function|filter)\s+(global:|script:)?Write-Log\b"
```

`Select-String` has no `-Recurse`, and handing it a *directory* via `-Path`
returns nothing at all without erroring — which under the rule below would
convert every locally-defined helper into a "real" break. Enumerate first.

`workflow` is deliberately **not** in that alternation. `workflow` was removed in
PowerShell 7: a file defining one does not parse at all, so the function never
exists. Finding `workflow Write-Log { … }` is proof of a **Blocker**, not proof
of a false positive — treating it as a definition would file the one construct
that guarantees the break into the ledger that dismisses findings.

- Definition found → **false positive**. Record it and move on.
- Defined as `workflow` → **Blocker**. The whole file fails to parse under 7;
  rewrite the workflow before triaging anything else in it.
- No definition, and it is not a cmdlet on the host → **real**, but usually a
  *missing dependency*, not a 5.1→7 break. Find which module or dot-sourced file
  was expected to supply it before rewriting anything.

**Do not** "fix" this class by adding shims or renaming. Nothing is broken.

## Class 2 — abbreviated parameter prefix

**Symptom.** A finding naming a parameter that is a truncation of a real one:
`-fore` for `-ForegroundColor`, `-Type` for `-TypeName` on `New-Object`, `-Recu`
for `-Recurse`. Typically the second-largest class.

**Cause.** [Acknowledged upstream][pssa-src], not a bug:

> Ideally we would go through each command and emulate the parameter binding
> algorithm … but this is very involved. For now, we'll just check that the
> parameters exist.

Real binding resolves any unambiguous prefix. Aliases *are* handled — the profile
loader merges `ParameterAliases` into `Parameters` — but prefixes get no such
treatment, because resolving one requires knowing the command's full parameter
set including dynamics.

[pssa-src]: https://github.com/PowerShell/PSScriptAnalyzer/blob/main/Rules/CompatibilityRules/UseCompatibleCommands.cs

**Test.** Ask the host whether the token is an unambiguous prefix.

```powershell
$cmd = 'Write-Host'; $tok = 'fore'
$hits = @((Get-Command $cmd).Parameters.Keys | Where-Object { $_ -like "$tok*" })
$hits.Count   # 1 => unambiguous prefix, false positive; 0 => real; >1 => genuinely ambiguous
```

- Exactly one match → **false positive**.
- Zero matches → **real**. Treat it as a removed parameter.
- More than one → the script is genuinely ambiguous and fails at runtime on both
  versions. Rare, but a real bug worth fixing.

**Preferred resolution: expand it.** Rewriting `-fore` to `-ForegroundColor` is
behaviour-preserving, is what a reviewer would ask for anyway, and removes the
finding permanently instead of parking it in a ledger that has to be re-applied
on every re-scan. Expand where you are already editing the file; ledger the rest.

## Class 3 — the profile dropped it during generation

**Symptom.** A finding on something that plainly exists in 7:
`Get-WinEvent`, `Get-Counter`, `[System.Data.SqlClient.SqlConnection]`.

**Cause.** Profile generation is lossy. Some modules and assemblies do not
enumerate cleanly, so their commands and types never reach the profile. This is
why the generator round-trips a sentinel set through the live runtime and writes
what it lost to `.validation.json`.

**Test.** Membership in `MissingCommands` / `MissingTypes`. If the symbol is
there, it was pre-declared as a known drop — **false positive**, no further work.

If it is *not* in the list, confirm against the host before dismissing it:

```powershell
pwsh -NoProfile -Command "(Get-Command Get-WinEvent).CommandType"
```

`Cmdlet` means it resolves natively → false positive; add it to the ledger.
`Function` means you are seeing a **compatibility shim, not the real command** —
the finding is *real* and the profile may be contaminated. Stop and re-read
`validation-ladder.md` Rung 2.

## Class 4 — provider dynamic parameter

**Symptom.** A parameter that exists only for certain providers or certain
parameter sets. `Set-ItemProperty -Type` is the common one.

**Cause.** `-Type` is not a static parameter of `Set-ItemProperty`; it is
contributed by the **Registry provider** and only exists when `-Path` points at
one. Verified on the target host:

```powershell
(Get-Command Set-ItemProperty).Parameters.ContainsKey('Type')                       # False
(Get-Command Set-ItemProperty -Path 'HKLM:\SOFTWARE').Parameters.ContainsKey('Type') # True
```

The profile records the static set, so every registry call looks wrong. It is not
— `-Type` behaves identically on 5.1 and 7.

**Test.** Re-resolve the command with the `-Path` the script actually uses. If
the parameter appears, it is a **false positive**. Note this also distinguishes
class 4 from class 2: `New-Object -Type` is a *prefix* of `-TypeName`
(`New-Object` has no dynamic parameters at all), while `Set-ItemProperty -Type`
is a genuine dynamic parameter. Both are false positives; the reasoning differs,
and only class 2 should be expanded in place.

## Recording the outcome

Every dismissal goes in the false-positive ledger at
`.github/upgrades/{scenarioId}/analyzer-false-positives.md`, one row each:

| File | Line | Symbol | Class | Evidence |
|---|---|---|---|---|
| `Deploy/Publish.ps1` | 412 | `Write-Log` | 1 | defined `Common/Logging.ps1:18` |
| `Deploy/Publish.ps1` | 55 | `-fore` | 2 | unique prefix of `-ForegroundColor`; expanded |
| `Db/Restore.ps1` | 9 | `Get-WinEvent` | 3 | `validation.json` `MissingCommands` |
| `Setup/Registry.ps1` | 77 | `-Type` | 4 | dynamic under Registry provider |

The ledger is an input to validation, not a postscript to it. Rung 2 re-runs the
analyzer after every change; without the ledger the same false positives come back
and nobody can tell them from new regressions.

**A ledger entry is a claim, not a licence.** Each row must name the evidence
that settled it. "Looks like a false positive" is not evidence. If a finding does
not fit one of the four classes, it is **real until proven otherwise** — that is
the direction this scenario errs in deliberately.

## The silent direction: where PSUseCompatibleTypes says nothing

The four classes above are all over-reporting. `PSUseCompatibleTypes` has one
under-reporting mode, and it matters more.

The rule only judges a type when **that type's namespace appears in the target
profile**. If the whole namespace is absent, it emits nothing — deliberately, so
that user-defined types are not reported as missing framework types. The effect is
inverted severity: a type from a namespace .NET partly carries gets flagged, and a
type from a namespace .NET never carried at all is silent.

So a clean `PSUseCompatibleTypes` result is evidence about types in *known*
namespaces only. Do not read it as "this script uses no unavailable types."

Check any namespace the script uses that you have not seen the analyzer comment
on:

```powershell
# Does the profile know this namespace at all?
$p = Get-Content <profile>.json -Raw | ConvertFrom-Json -AsHashtable -Depth 30
$ns = 'System.Web.Script.Serialization'
$p.Runtime.Types.Assemblies.Values.Where({ $_.Types -and $_.Types.ContainsKey($ns) }).Count
# 0 => the analyzer cannot judge this namespace; its silence means nothing
```

The catalog sidecar's `framework-only-namespace` rule covers the namespaces this
is known to hit. Treat that rule's findings as authoritative even when PSSA is
quiet about the same line — that is the case it is there for.

**Resolving is not the same as working.** On Windows, `Add-Type -AssemblyName`
can load a .NET Framework assembly out of the GAC under PowerShell 7, and the type
binds successfully. The failure surfaces at the first real call, as a
`TypeLoadException`. A type that resolves under `pwsh` is therefore not evidence
of support — exercise the code path before dismissing a finding.

## What this skill does not do

It does not triage the catalog sidecar's findings. Those are pattern matches
against a curated list, so they have the opposite error profile: high precision,
incomplete recall. A catalog finding is real unless the pattern matched something
inside a string or comment, which the `Fidelity` column already reports.
