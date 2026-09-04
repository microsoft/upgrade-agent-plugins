# Validation Ladder (reference)

Loaded from [execution.md](execution.md). Each script climbs as far as its
dependencies allow; the rung reached is recorded per file and is the completion
evidence for its task.

**Probe the environment once, before Rung 1**, and record what is available.
Both rungs below are environment-dependent, and an agent that discovers this by
hitting a red error mid-loop tends to thrash:

```
$hasPwsh = [bool](Get-Command pwsh -ErrorAction SilentlyContinue)
$hasPssa = [bool](Get-Module -ListAvailable PSScriptAnalyzer)
```

- No `pwsh`: Rungs 1, 3 and 4 are unavailable — there is no validation left.
  **Stop and ask the user to install PowerShell 7**
  (`winget install Microsoft.PowerShell`). Do not continue execution capping
  files at a scan-only rung: remediating files that can never be validated
  produces edited scripts with no evidence they work.
- No `PSScriptAnalyzer`: the primary gate does not exist. **Stop and ask the user
  to install it** (`Install-Module PSScriptAnalyzer -Scope CurrentUser -Force`).
  Do not continue on parse checks alone — a parse-only pass is not a
  compatibility pass, and recording it as progress is how a broken migration
  reaches production looking finished.

Both are Stage 0 prerequisites, so reaching here without them means the
prerequisite gate was skipped. Return to Stage 0 rather than improvising a
reduced ladder.

Never call `Invoke-ScriptAnalyzer` or `pwsh` speculatively to find out whether
they exist.

1. **Parse (needs `pwsh`, otherwise offline).** Prove the *edited* file still parses
   under PS7 with no execution. This is a syntax check on your own edit, not a
   compatibility signal — the compatibility scan already parsed the file
   before you touched it, so a pass here means only "I did not break the syntax":
   ```
   pwsh -NoProfile -Command '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile("FILE",[ref]$null,[ref]$e); $e'
   ```
   **Files marked 5.1-compatible** (partial scope — they still have callers on 5.1)
   must clear this rung on **both** hosts. Repeat the same command with
   `powershell.exe`; the `Parser` type exists there too. A file that parses only
   under `pwsh` has already broken its 5.1 callers.
2. **Static compatibility (needs PSScriptAnalyzer) — primary gate.**
   PSScriptAnalyzer is a Stage 0 prerequisite. If it is absent, stop and install it
   with `Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Scope CurrentUser`
   (ask the user first) rather than proceeding without the gate.

   Use the **generated, validated profile** produced in Stage 0 by
   `New-PSSACompatibilityProfile.ps1` (see the `scanning-powershell-compatibility`
   skill). Do not fall back to the profiles PSScriptAnalyzer ships: those top out
   at PowerShell **7.0.0**, are built on someone else's machine, and — critically
   — inventory whatever module versions that machine happened to have. A module
   whose command surface changed across majors (Pester is the usual example) then
   has the wrong parameter shape recorded, and every call against the estate's
   actual version is misjudged.

   **Never run this rung against a profile whose validation did not pass.** The
   generator writes a `<profile>.validation.json` next to the profile. If its
   `Status` is `FAIL`, the profile is contaminated (a Windows-compatibility shim
   was loaded during generation and removed cmdlets were inventoried as present)
   and this rung produces false *passes* — the worst possible outcome. Regenerate
   in a clean session instead.

   A `WARN` status is usable, but read `MissingCommands` / `MissingTypes` first:
   those items resolve on the host yet were dropped during generation, so every
   use of them will be reported as incompatible. They are the false-positive
   ledger for this run — carry them into triage rather than rediscovering them
   one finding at a time.

   The three `PSUseCompatible*` rules are configured differently and **all three
   need their own settings** — a rule you include but never configure silently
   checks nothing and reports clean:
   - `PSUseCompatibleCommands` and `PSUseCompatibleTypes` take `TargetProfiles`,
     which here is the **full path** to the generated profile.
   - `PSUseCompatibleSyntax` takes `TargetVersions`, which must be the **same
     target version the assessment scanned at**. A re-scan at a different version
     is not comparable to the baseline it is being judged against.

   **Each rule also needs `Enable = $true`** — a rule that carries only
   `TargetProfiles`/`TargetVersions` stays off and reports clean no matter how
   broken the script is (verified against PSScriptAnalyzer 1.25.0):
   ```
   $target = '<path to the generated profile>'
   $targetVersion = '<the target version chosen in Stage 1, e.g. 7.4>'
   $settings = @{
       Rules = @{
           PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @($target) }
           PSUseCompatibleTypes    = @{ Enable = $true; TargetProfiles = @($target) }
           PSUseCompatibleSyntax   = @{ Enable = $true; TargetVersions = @($targetVersion) }
       }
   }
   Invoke-ScriptAnalyzer -Path FILE -IncludeRule PSUseCompatibleCommands,PSUseCompatibleSyntax,PSUseCompatibleTypes -Settings $settings -ErrorVariable pssaErrors
   ```
   An unresolvable profile also yields zero findings, but writes a
   `Could not find file …` error to `$pssaErrors` instead of failing the call.
   **Always check `$pssaErrors` is empty before reading zero findings as a pass** —
   with `-ErrorAction SilentlyContinue` and no `-ErrorVariable`, a bad path is
   indistinguishable from a clean script.

   `Invoke-ScriptAnalyzer -Path` is scalar-only — loop one file at a time. Note
   also that `DiagnosticRecord.ScriptName` is the **leaf filename only**; carry
   the full path yourself if you need to join results back to files.

   Green here means no removed cmdlets/types/syntax remain, *minus* the known
   gaps in the validation record. If the profile did not validate, or
   `$pssaErrors` is non-empty, this rung did **not** run — record it as such
   rather than as a pass.

   Parse errors that PSScriptAnalyzer emits during this rung (for example
   `WorkflowNotSupportedInPowerShellCore`) are **signal, not noise**: they are
   hard blockers that no amount of editing around will fix. Report them
   separately rather than folding them into the finding count.

   For a **5.1-compatible** file, set `TargetVersions = @('5.1', $targetVersion)` so
   `PSUseCompatibleSyntax` flags syntax that either host rejects. Findings against
   the 5.1 target are real failures for that file, not noise. Leave
   `TargetProfiles` on the generated profile — the deferred one-way findings it
   reports are expected, and the deferral list in `scenario-instructions.md` is what
   distinguishes them from regressions.
3. **Command resolution (needs modules).** In `pwsh`:
   ```
   (Get-Command <cmd> -ErrorAction Stop).CommandType
   ```
   **Bare success is not a pass.** If `WindowsCompatibility` or an implicit
   remoting session is loaded, removed cmdlets such as `Get-WmiObject` resolve
   perfectly well — as proxy **functions** into a background Windows PowerShell
   process. Require `CommandType -eq 'Cmdlet'` for a native pass; a `Function`
   means the command only works through the compatibility shim. Record which of
   the two it was, because the shim is a Windows-only, out-of-process crutch that
   this scenario exists to remove.
4. **Behavioral / runtime (environment-bound).** Prefer the estate's **own** test
   entry point over anything you compose yourself — the wrapper carries imports,
   `PSModulePath`, fixtures and tag filters that a bare `Invoke-Pester` omits, and a
   run missing them fails for reasons unrelated to the migration. Classify the suite
   before the first run; an integration suite that mutates real infrastructure is a
   side effect on the user's environment, not a read of it, and needs explicit
   consent. Then three tiers:
   - **4a pure/side-effect-free**: run in a clean `pwsh` sandbox and diff output
     against a 5.1 baseline.
   - **4b read-only against live infra** (WMI→CIM): run old + new and diff the
     *selected properties actually consumed* (CIM returns `CimInstance`, not
     `ManagementObject` — shapes differ).
   - **4c mutating / infra-coupled** (Exchange snap-in, AD writes, cluster ops):
     do **not** auto-execute. Prove the replacement connection path exposes the
     same command surface, use `-WhatIf` in staging where supported, otherwise
     mark `manual-signoff`.

Record `runtimeValidation` per file: `verified | read-only-diff-clean |
whatif-clean | needs-live-env | manual-signoff`.

**A failure at rung 4 is work, not a verdict.** This rung is the only one that
can catch a behaviour change — a different default, a different output shape, an
encoding that moved — so a red result here is the most valuable signal the ladder
produces. Fix it and re-run; do not record `verified` against a failing suite,
and do not weaken or delete the test to get past the gate. If the cause is the
test itself rather than the edit, say so explicitly in the record, and route a
Pester version problem to the `pester-migration` skill. If it cannot be fixed,
report it and record the rung actually reached.
