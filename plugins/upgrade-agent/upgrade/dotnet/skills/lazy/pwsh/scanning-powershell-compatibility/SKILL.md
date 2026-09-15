---
name: scanning-powershell-compatibility
description: >
  Detect Windows PowerShell 5.1 → 7.x compatibility blockers across a tree of
  .ps1/.psm1/.psd1 files. Two parts: generate and validate a PSScriptAnalyzer
  compatibility profile for the target host (the primary detector, covering
  removed commands/parameters/types), then run a small parser-driven catalog
  as a sidecar for what PSScriptAnalyzer is structurally blind to — encoding
  and other behavioral changes, parameter values, type accelerators, module
  availability, COM, and deprecated-but-present cmdlets. Produces
  scan-findings.csv keyed by rule id, which seeds the assessment, the plan, and
  the execution re-scan gate. Use during the powershell-51-to-7-upgrade
  scenario, or any time you need a reproducible inventory of PowerShell
  compatibility blockers.
  DO NOT USE FOR: scanning C#/.NET code, PSScriptAnalyzer style rules, or
  verifying that a fix works (that is the validation ladder's job).
  INVOKES: scripts/New-PSSACompatibilityProfile.ps1,
  scripts/Get-PSCompatibilityScan.ps1.
metadata:
  discovery: lazy
  traits: PowerShell
---

# Scanning PowerShell 5.1 → 7 Compatibility

## Relationship to PSScriptAnalyzer

**PSScriptAnalyzer is the primary detector. This catalog is a deliberately small
sidecar for the classes it is structurally unable to see.** Do not run this scan
as a replacement for `PSUseCompatibleCommands` / `PSUseCompatibleTypes` /
`PSUseCompatibleSyntax`; run it alongside them.

### What PSScriptAnalyzer does better

It enumerates the entire command and type surface of the target runtime, so it
catches *every* removed cmdlet, *every* removed parameter, and *every* removed
type — including ones nobody thought to write a rule for. A curated catalog can
only ever contain what someone remembered. For removed-API detection, that
completeness wins outright, and this catalog should not compete with it.

### What PSScriptAnalyzer cannot see, by construction

It infers breakage from **absence** from an inventory. Anything that still exists
in PowerShell 7 but *behaves differently* is invisible to it, no matter how
badly it breaks:

| Blind spot | Example | Why it is invisible |
|---|---|---|
| Behavioral change | `"x" \| Out-File f.txt` — 5.1 writes 16 bytes UTF-16LE+BOM, 7.x writes 7 bytes UTF-8 no BOM | `Get-Command Out-File` resolves on both |
| Deprecated-but-present | `Send-MailMessage` | still ships in 7 |
| Parameter *values* | `-Encoding Byte`, `-Algorithm MACTripleDES`, `Add-Type -Language VisualBasic` | the parameter exists; only the value is gone |
| Type accelerators | `[wmi]"root\cimv2:Win32_Process"` | accelerators are not types |
| Module availability | `Import-Module PSScheduledJob` / `ActiveDirectory` | it checks commands, not imports |
| String literals | hardcoded `powershell.exe`, the Exchange snap-in id | not an AST command |
| COM | `New-Object -ComObject` | `New-Object` exists |
| Platform intent | Windows-only code targeted at Linux | the profile is the *host*, so it looks fine |

Encoding is typically the largest genuine finding class in the whole scan, and
PSScriptAnalyzer reports **zero** of it.

It also has **no symbol table and no interprocedural analysis**. It reports a
function as unavailable in the very file that defines it a few lines above, and
it never follows a dot-source into a library. It also does not resolve
abbreviated parameters — `-fore` for `-ForegroundColor` is reported as missing.
See [the upstream rule source][pssa-cmds], which explicitly defers parameter
binding: *"Ideally we would go through each command and emulate the parameter
binding algorithm … but this is very involved. For now, we'll just check that the
parameters exist."* Those two classes dominate its false positives; see the
`triaging-powershell-analyzer-findings` skill.

[pssa-cmds]: https://github.com/PowerShell/PSScriptAnalyzer/blob/main/Rules/CompatibilityRules/UseCompatibleCommands.cs

### The division of labour

Every `Command`-kind target in the catalog was probed against
`PSUseCompatibleCommands` with a validated profile to decide which side owns it.
The two superseded `Parameter`-kind rules were probed the same way:
`PSUseCompatibleCommands` reports removed *parameters* as well as removed
commands, so `Restart-Computer -Protocol` and `Get-Service -ComputerName` are
both caught even though the commands themselves still ship in 7.

| Catalog rules | PSSA coverage | Handling |
|---|---|---|
| `snapin`, `wmi-cmdlet`, `eventlog-cmdlet`, `computer-cmdlet`, `controlpanel-cmdlet`, `transaction-cmdlet`, `counter-cmdlet`, `workflow-job-cmdlet`, `dsc-cmdlet`, `convertfrom-string`, `web-service-proxy`, `export-binarymilog`, `service-computername`, `dcom-protocol` | full | `SupersededBy = 'PSUseCompatibleCommands'` |
| `workflow` | full | `SupersededBy = 'PSUseCompatibleSyntax'` |
| `null-on-right` | n/a — not a migration break | `SupersededBy = 'PSPossibleIncorrectComparisonWithNull'`, which this scan deliberately does **not** enable. `$x -eq $null` behaves identically in 5.1 and 7, so it is latent-bug cleanup rather than migration work and would only add noise. Carried as knowledge so the remediation text is on hand if a reader hits one. |
| `send-mailmessage` | **none** — still ships in 7 | primary |
| `wmi-accelerator`, `windows-only-gui`, `windows-only-assembly`, `windows-only-module`, `framework-only-namespace`, `servicepointmanager`, `blocked-module`, `unavailable-module`, `winpscompat-module`, `native-in-ps7-module`, `com-object`, `encoding-byte`, `encoding-default`, `outfile-output-encoding`, `clixml-output-encoding`, `tee-output-encoding`, `ansi-output-encoding`, `csv-output-encoding`, `redirection-output-encoding`, `add-type-visualbasic`, `removed-hash-algorithm`, `powershell-exe`, `exchange-snapin`, `webrequest-parsedhtml`, `requires-*` | **none** | primary |

The table is exhaustive: every id in `PSCompatibilityRules.psd1` appears in
exactly one row. If you add a rule, add it here too — a rule missing from the
table is indistinguishable from a rule nobody measured.

Superseded rules are **knowledge-only**: they do not run, and they never emit a
finding. Detection for anything in the first two rows is PSScriptAnalyzer's
alone; the third row is detected by nobody, on purpose. The rule bodies stay in
the catalog because they still do two jobs that
have nothing to do with detection:

- **Enrichment.** `Invoke-PSSACompatibilityScan.ps1` joins each PSSA finding
  against them on `Command` (and on `Command` + `Parameter` for `Parameter`-kind
  rules) and stamps back the category, the real severity, the remediation prose
  and the `Skill` that performs the rewrite. PSSA supplies none of those — its
  own `Severity` is `Warning` for every compatibility finding it emits.
- **Profile contamination sentinels.** `New-PSSACompatibilityProfile.ps1` derives
  its "these must be absent from a clean 7 profile" probe list from the
  `Command`-kind rules. Every sentinel comes from a superseded rule; delete them
  and the generator has nothing left to validate against.

This is why the split is *knowledge vs detection* rather than *keep vs delete*.
It also removes a failure mode: when the same break could be reported by two
detectors, the deduplication was a static catalog attribute rather than a real
join against the analyzer's output, so a supersession that stopped being true
would fail open. With one detector there is nothing to deduplicate.

Two consequences for anyone extending the catalog:

- Do not add new rules that merely assert "this command is gone". Confirm
  against the profile first; if PSScriptAnalyzer reports it, tag the rule
  `SupersededBy` — it becomes enrichment, not a second detector.
- Rules for the blind-spot table above belong here, and nowhere else.

**When measuring coverage, always pass `-IncludeRule`.** A `Settings` hashtable
*configures* the rules it names but does not restrict the run to them, so the
default rule set fires as well. That is how `Send-MailMessage` first appeared to
be covered — the hit was `PSUseCmdletCorrectly` complaining about missing
mandatory parameters, not a compatibility finding at all.

## Generating the compatibility profile

PSScriptAnalyzer's accuracy is entirely determined by the profile behind it, and
**the profiles it ships are not fit for this purpose**: they top out at
PowerShell **7.0.0**, they were built on someone else's machine, and they
inventory whatever module versions that machine happened to have.

Generate one on the target host instead:

```powershell
pwsh -NoProfile -File <skill>/scripts/New-PSSACompatibilityProfile.ps1 -OutputPath .github/upgrades/<scenarioId>/target-profile.json -TargetPlatform Windows -TargetPSVersion 7.4
```

`-TargetPlatform` and `-TargetPSVersion` do **not** change what is generated —
a profile only ever describes the interpreter it ran under. A platform mismatch
or a host that is newer than the target makes validation **`FAIL`**: the generator
exits 1 and the scan wrapper refuses the profile. These profiles can inventory
capabilities absent from the target, suppressing real findings. Version checks
compare major/minor, not patch versions. A host older than the target can only
over-report from the version difference; that direction is noted and does not
itself fail validation. Run this under the `pwsh` the user is actually migrating
to: for the example above, use PowerShell 7.4 on Windows, not 7.5/7.6 with
`-TargetPSVersion 7.4`.

The script does three things:

1. **Provisions modules** onto `PSModulePath` before reflecting. The default pins
   `Pester:5.0:5.99`. Windows ships Pester **3.4.0** in-box, whose `Should` takes
   no declared parameters at all (raw `$args`), so a profile built over it
   records zero parameters and rejects every `-Be`/`-Match`/`-Throw` — a single
   wrong module version can dominate the whole report with false findings. It
   also prunes versions *newer* than the pin, because the analyzer unions
   parameters across versions and a newer major silently masks real findings.
2. **Generates** the profile against the running host.
3. **Validates** it by round-tripping sentinels, and writes a
   `<profile>.validation.json` beside it.

### Reading the validation result

| Status | Meaning | Action |
|---|---|---|
| `PASS` | Sentinels agree with the host | Use it |
| `WARN` | Items resolve on the host but were dropped from the profile | Use it, and carry `MissingCommands`/`MissingTypes` as a known-false-positive ledger |
| `FAIL` | Contamination, an unpinned module newer than the pin, platform mismatch, or the generating host is newer than the target | **Do not use it.** Correct every cause recorded in the sidecar and regenerate |

All four `FAIL` causes can suppress real findings. A sidecar recording `FAIL`
is always refused: the wrapper reports its recorded causes and has no override
for that verdict. A missing sidecar only produces a warning before scanning,
with `profileValidation: 'not-found'`. `-SkipValidation` does not write a new
sidecar; it does not remove an existing one either. Never skip validation or
delete a sidecar to claim a clean compatibility result, and never treat a scan
without validation as clean.

| Sidecar field | Cause and remedy |
|---|---|
| `Validation.Contamination` | Removed commands were inventoried through compatibility proxies. Regenerate in a clean session with no `WindowsCompatibility` or implicit remoting. |
| `Validation.UnpinnedModules` | Module versions newer than the pin reached the profile. Remove those versions from the generating host's `PSModulePath` and regenerate with the requested pins. |
| `Host.Mismatch` | The generating platform differs from the target. Generate on the target platform. |
| `Host.VersionMismatch` | The generating host is newer than `-TargetPSVersion`. Generate on the target PowerShell major/minor version. |

A clean session alone does not fix module, platform, or version mismatches.
For contamination specifically, if `WindowsCompatibility` or an implicit remoting
session was loaded during generation, its proxy functions for `Get-WmiObject` and
`Get-EventLog` get inventoried as real commands, and the analyzer then goes
**silent on every WMI site in the estate**. That is a false *pass*.
The check distinguishes them by `CommandType`: native commands are `Cmdlet`,
compatibility shims are `Function`.

That distinction is not optional, because a bare presence test is guaranteed to
be wrong here. On Windows, PowerShell 7 keeps the Windows PowerShell module path
on `$env:PSModulePath`, so calling a removed command in a stock `pwsh -NoProfile`
silently autoloads the 5.1 module through the compatibility layer and answers
with a generated proxy. `Get-Command Get-WmiObject` therefore *succeeds* on a
perfectly clean host. Only `CommandType` separates the two:

```powershell
$c = Get-Command Get-WmiObject; $c.CommandType   # Function => shim, Cmdlet => native
```

A `WARN` is normal and useful. On a stock Windows 11 host it reports
`Get-WinEvent`, `Get-Counter`, and `System.Data.SqlClient.SqlConnection` — all
three work at runtime but are dropped during generation, so every use of them
would otherwise be chased as a real blocker. Getting that list *before* triage
instead of discovering it finding-by-finding is the point of the rung.

## Running PSScriptAnalyzer against the profile

Use the wrapper, not a hand-rolled `Invoke-ScriptAnalyzer` call:

```powershell
pwsh -NoProfile -File <skill>/scripts/Invoke-PSSACompatibilityScan.ps1 -Path <scope-root> -ProfilePath .github/upgrades/<scenarioId>/target-profile.json -TargetPSVersion 7.4 -OutputPath .github/upgrades/<scenarioId>/pssa-findings.json
```

The direct call has four traps, and **three of them fail by reporting a clean
estate**, which on primary detection is the worst possible failure mode:

| Trap | Symptom if you get it wrong |
|---|---|
| `TargetProfiles` must be an **absolute** path | A bare name resolves against PSScriptAnalyzer's own bundled profile folder, not your working directory. Measured: relative → `findings=0 errors=1`; absolute → `findings=1 errors=0` |
| `-IncludeRule` is mandatory | A `Settings` hashtable configures named rules but does not restrict the run, so the whole default rule set also fires and style findings inflate the compatibility inventory |
| `Enable = $true` per rule | Omit it and the rule silently checks nothing |
| `ScriptName` is the leaf filename | Findings cannot be joined back to a path unless you carry it yourself |

The wrapper closes all four. It also refuses to run against a profile whose
validation status is `FAIL`, carries `MissingCommands`/`MissingTypes` into the
output as `falsePositiveLedger`, and tracks files the analyzer could not process
— a file that errored contributed zero findings *without being analyzed*, which
is not the same as clean. Any such file makes the run `coverage: INCOMPLETE` and
exits non-zero.

| Parameter | Purpose |
|---|---|
| `-Path` | One or more files or directories |
| `-ProfilePath` | The generated profile. Mandatory; resolved to absolute |
| `-TargetPSVersion` | Syntax target for `PSUseCompatibleSyntax` |
| `-OutputPath` / `-OutputFormat` | As the sidecar scanner — `Auto`, `Csv`, `Json`, `Both` |
| `-PassThru` | Emit the findings as objects as well as writing the file |

Exit code is `1` on findings **or** on any coverage gap, `0` only on a clean and
complete run.

## Why not just search for the strings

Text search cannot tell code from prose, and PowerShell estates are full of
prose that looks like code:

- Comment-based help almost always contains `.EXAMPLE  Get-WmiObject -Class Win32_BIOS`.
- A comment reading `# do not call powershell.exe here` is not a call.
- A here-string containing a script template is data, not code.
- `-Enc Byte` **is** `-Encoding Byte` — PowerShell resolves unambiguous
  parameter prefixes, and no regex knows the parameter set.
- `Add-Content @splat` may or may not set `-Encoding`; only the parser can see
  that the parameter set is hidden behind splatting and that the call must
  therefore *not* be reported.

Every one of those is a false positive or a false negative under `grep` /
`Select-String`, and a false positive here becomes a must-remediate item on
someone's migration plan. Use the parser.

## Prerequisite: locate a host

The scan runs under PowerShell itself. Before scanning, establish which hosts
are available and tell the user which one you used — the choice affects
fidelity (see below).

```powershell
Get-Command pwsh, powershell -ErrorAction SilentlyContinue |
    Select-Object Name, Version, Source
```

- **`pwsh` (PowerShell 7.x)** — **required**. It is the target engine, so its
  verdict is the one that matters, and it is the only host that can generate the
  PSScriptAnalyzer compatibility profile the primary detector runs against. If
  it is missing, stop and have it installed; PowerShell 7 is a hard-stop
  prerequisite for this scenario.
- **`powershell` (Windows PowerShell 5.1)** — use it *in addition* to `pwsh`
  when the estate contains workflows (see below), never as a substitute for it.
  A sidecar scan under 5.1 cannot stand in for the primary detector.
- **Neither** — stop. Report that the scan cannot run and that PowerShell 7 is
  required for the migration regardless. Do not fall back to `Select-String`
  and present the result as an inventory.

The script only reads files and writes its output file. It never executes the
scripts it scans.

## Running the scan

Check for contributed rules first (see *Organisation knowledge* below) — a scan
run without them reports internal snap-ins as generic, unremediated blockers.

```powershell
pwsh -NoProfile -File <skill>/scripts/Get-PSCompatibilityScan.ps1 -Path <scope-root> -AdditionalRulesPath .github/upgrades/<scenarioId>/contributed-rules.psd1 -OutputPath .github/upgrades/<scenarioId>/scan-findings.csv
```

Drop `-AdditionalRulesPath` when no skill contributed anything.

Useful parameters:

| Parameter | Purpose |
|---|---|
| `-Path` | One or more files or directories. Accepts a partial selection directly — no need to scan the whole repo. |
| `-OutputPath` | Where the findings CSV lands. |
| `-AdditionalRulesPath` | One or more extra catalogs merged onto the shipped rules. When adding or changing rules, read [Custom rules](ref/custom-rules.md). |
| `-RulesPath` | Replace the shipped catalog outright. Rarely what you want. |
| `-Include` | File patterns. Default `*.ps1, *.psm1, *.psd1`. |
| `-ExcludeDirectory` | Directory names skipped at any depth. Default `.git, node_modules, bin, obj, packages, .vs`. Pruned directories are listed in the summary and in `coverage.excludedDirs` — the defaults are .NET build-output names, and a PowerShell estate is free to keep production scripts in a folder called `bin`. Check that notice before reading a low finding count as a clean tree. |
| `-OutputFormat` | `Auto` (default — infers from the `-OutputPath` extension), `Csv`, `Json`, or `Both`. |

`Json` writes an envelope rather than a bare array: the findings plus the run
metadata needed to tell two scans apart (host, catalog files loaded, contributed
rule count, coverage status, counts by rule). Two scans of the same tree with
different catalogs are different scans, and the bare rows do not say so. `Both`
writes the CSV at `-OutputPath` and the JSON beside it.

Exit code is `1` when anything non-`Advisory` was found **or** when coverage is
incomplete — an unreadable directory, a `-Path` that resolved to nothing, or a
file that did not parse. `0` means clean *and* complete, so the call can gate a
pipeline step on it.

**Write the CSV outside the scanned tree**, or into a directory that is in
`-ExcludeDirectory`. Otherwise a later re-scan picks up its own output. Rule
catalogs need no such care — the scan excludes every catalog it loaded from its
own enumeration.

## Reading the result

The script prints the summary you should read: counts by severity, counts by
rule id, and the list of files that could not be fully parsed.

**`scan-findings.csv` is a lookup table, not reading material.** On a real
estate it is tens of thousands of rows and will blow out the context window.
Query it per file or per rule id when you reach that item in the execution
loop; never read it whole.

Columns: `File, Line, RuleId, Category, Severity, Fidelity, DetectedBy, Snippet`

`DetectedBy` is `catalog` on every row. It is retained so the schema is stable
for anything already consuming it, but it no longer carries a decision: the
sidecar only runs its **active** rules, and every finding it emits is one
PSScriptAnalyzer does not report. Superseded rules are knowledge-only and never
reach this file — their content arrives instead as the `CatalogRuleId`,
`Category`, `CatalogSeverity`, `Skill` and `Remediation` columns stamped onto the
*PSSA* findings by `Invoke-PSSACompatibilityScan.ps1`.

The two outputs do not duplicate each other at the rule level. Add both to the
plan.

One exception is deliberate. `exchange-snapin` (the only rule carrying
`Supersedes`) overlays a specific answer on a generic analyzer finding: PSSA
reports `Add-PSSnapin Microsoft.Exchange...` as the generic `snapin` Blocker,
and the sidecar adds the Exchange-specific remediation for the same site. One
site, two findings. Count it once and plan from the specific one.

```powershell
# every file affected by one rule
Import-Csv scan-findings.csv | Where-Object RuleId -eq 'send-mailmessage' |
    Group-Object File | Select-Object Name, Count

# everything in one file
Import-Csv scan-findings.csv | Where-Object File -eq $target
```

The exit code is non-zero if any non-`Advisory` finding remains, because as an
execution re-scan gate a leftover blocker is a blocker.

## Fidelity: `Full` vs `Tokens`

Every finding carries a `Fidelity` column.

- **`Full`** — the file parsed cleanly and the syntax tree was walked. Every
  rule applies.
- **`Tokens`** — the file did not parse *under the host that ran the scan*. The
  token stream survives a parse failure intact and is still fully classified,
  so name-based rules (commands, keywords, types, modules, string literals,
  member names) still apply and comments are still excluded. `CommandArgument`
  rules degrade to a broad unanchored match — deliberately trading precision for
  recall, since dropping a Blocker on an unparseable file is the worse error.
  Rules that need real tree shape cannot be evaluated at all: `Parameter`,
  `ParameterValue`, `MissingParameter`, `NullComparison`, `FileRedirection` and
  `StaticMember`. That includes `com-object` and `encoding-default`, both easy to
  overlook. The run summary lists
  the exact rule IDs that were skipped, so read it rather than inferring; a clean
  result for those rules on a degraded file means *not checked*, not *not
  present*.

The most common cause is **`workflow`**, which PowerShell 7 refuses to parse at
all (`Workflow is not supported in PowerShell 6+`). That is itself a Blocker
finding, so a degraded file is usually the file that most needs migrating.

**A degraded file counts as a coverage gap**, so the run reports
`coverage : INCOMPLETE` and exits `1` even when it found nothing. That is
deliberate: the rules it skipped are the ones most likely to hold the blocker,
so a `0` exit would be the scan's clean bill of health for a file it never
finished reading.

If the summary reports degraded files, **re-run the scan under Windows
PowerShell 5.1** for those paths — 5.1 parses workflows, so they come back at
`Full` fidelity:

```powershell
$degraded = Import-Csv scan-findings.csv |
    Where-Object Fidelity -eq 'Tokens' |
    Select-Object -ExpandProperty File -Unique
powershell -NoProfile -File <skill>/scripts/Get-PSCompatibilityScan.ps1 -Path $degraded -OutputPath .github/upgrades/<scenarioId>/scan-findings-51.csv
```

Genuinely malformed scripts also land at `Tokens` fidelity, and the summary
prints the parse error for each. Do not silently ignore those — a script that
does not parse under *either* host is broken today, which is a finding in its
own right and worth raising with the user.

## Severity model

| Severity | Meaning | Migration impact |
|---|---|---|
| `Blocker` | The construct does not exist in PowerShell 7. | Must be fixed. The script fails, usually at the first call. |
| `Manual` | Works only through a compatibility layer or only on Windows. | Needs a human decision; there is no single correct rewrite. |
| `AutoFix` | Deterministic mechanical rewrite. | Safe to apply in bulk, still needs review. |
| `Advisory` | Still runs; behaviour or output changed. | Not a blocker. Often a latent bug worth fixing while the file is open. |

`Advisory` findings do **not** fail the scan and must not be presented as
migration blockers.

The six encoding rules in particular fire on a large fraction of any real
estate, so report them as counts, not as a task list. They are split by behaviour
so the count means something:

| Rule | What changes |
|---|---|
| `outfile-output-encoding` (`Out-File`) | **every** file, including pure ASCII: 5.1 wrote UTF-16LE + BOM, 7 writes UTF-8 no BOM |
| `clixml-output-encoding` (`Export-Clixml`) | same as above, on serialized state another process reads back |
| `tee-output-encoding` (`Tee-Object -FilePath`) | same as above; note `-Encoding` does not exist on 5.1's `Tee-Object` |
| `redirection-output-encoding` (`>`, `>>`) | same as above, and `-Encoding` cannot be passed at all |
| `ansi-output-encoding` (`Set-Content`, `Add-Content`) | only non-ASCII: ANSI code page → UTF-8 |
| `csv-output-encoding` (`Export-Csv`) | only non-ASCII, and it is a *fix* — 5.1 wrote ASCII and substituted `?` |

The first four are the ones you cannot dismiss with "our data is all ASCII".

## Extending the catalog

When adding or overriding rules, read [Custom rules and snap-in maps](ref/custom-rules.md).
Never edit the shipped catalog in a customer repo; keep rules as restricted data, not code.

## Organisation knowledge: contributed rules and snap-in maps

**Before running the scan**, check Available Skills for
`provides: powershell-compatibility-rules` and check for mappings the user gave in
conversation. If either exists, read [Custom rules and snap-in maps](ref/custom-rules.md)
before projecting that knowledge into `contributed-rules.psd1` and passing it as
`-AdditionalRulesPath`.

Precedence is shipped catalog, then contribution skills, then conversation mappings.
Keep projected rules in `.github/upgrades/<scenarioId>/contributed-rules.psd1`, per operation,
and name any contribution skill the user's mapping overrides.

After a scan reports generic `snapin` findings, ask for a replacement module or explicit
"no replacement" for each distinct snap-in in `Snippet`. If mappings are supplied, read the
reference, project them and re-run so the findings and remediation agree. Re-run only when
new mappings were actually received.

## Stability contract

`Id` values are the join key between the findings CSV, the assessment, plan
tasks, and the execution re-scan gate. **Never reuse or repurpose an id.**
Adding rules is safe; renaming one silently breaks every plan written against
the old name.

Narrowing a rule counts as repurposing. If a rule's meaning changes, retire the
id and add a new one — otherwise a scan run before the change and one run after
are silently incomparable, and a dropped count reads as progress.

**Retired ids** (never to be reused):

| Id | Retired in favour of | Reason |
|---|---|---|
| `default-output-encoding` | `outfile-output-encoding`, `ansi-output-encoding`, `csv-output-encoding` | Originally covered `Out-File`, `Set-Content`/`Add-Content` and `Export-Csv` as one class. Measurement showed the three have *different* 5.1 encodings and only `Out-File` changes pure-ASCII bytes, so one count could not be acted on. |

## What this skill does not do

It is an **inventory**, not a verification. It tells you what is there before
the migration and confirms the count reached zero after. It cannot tell you the
rewrite is *correct* — a `Get-CimInstance` call with the wrong property name
scans clean and fails at runtime. Proving the fix works is the validation
ladder's job: parse check, PSScriptAnalyzer `PSUseCompatible*`, then actually
running the script under `pwsh`.
