# Stage 3: Execution

Execute the plan task by task using the system task-execution skill. Each task arrives
with its blocker's remediation skill attached (via the `#skill:` marker the plan wrote),
applies that remediation, re-scans to confirm the finding cleared, and climbs the
validation ladder.

## Entry Criteria

- `plan.md` and `scenario-instructions.md` exist.

## Exit Criteria

- All **Blocker**-severity findings remediated or explicitly deferred with a recorded
  reason.
- Dot-sourced libraries and their callers consistent (callers re-scanned after the
  library changed).
- Per-file validation rung recorded; `manual-signoff` items surfaced as a human-review
  queue rather than claimed complete.

## 1. Probe the environment once, up front

Before the first task, probe for `pwsh` and PSScriptAnalyzer and record the result — see
[validation-ladder.md](validation-ladder.md). Doing this once avoids discovering a
missing dependency by hitting a red error mid-loop, which tends to make an agent thrash.
Never call `Invoke-ScriptAnalyzer` or `pwsh` speculatively to find out whether they
exist.

## 2. Apply the remediation

For each task:

1. Read `scenario-instructions.md` for `targetPowerShellVersion`, the resolved
   PSScriptAnalyzer profile, and the platform intent.
2. Query `scan-findings.csv` for this task's blocker id(s) to get exact
   `File,Line,Snippet` locations. Query per blocker id or per file — never read the CSV
   whole.
3. **Triage the PSScriptAnalyzer findings before editing.** Load
   `triaging-powershell-analyzer-findings` and classify each one. About 90% of the
   analyzer findings the catalog does not corroborate are false positives, and they
   fall into four classes with mechanical tests — a function defined elsewhere in
   the estate, an abbreviated parameter prefix, a symbol the profile dropped during
   generation, or a provider dynamic parameter. Editing before classifying rewrites
   working code.

   This applies to the **analyzer result set only**. Every row in
   `scan-findings.csv` is a curated pattern match and is never triaged here. The
   sidecar runs only rules PSScriptAnalyzer does not cover, so a sidecar row is
   never a duplicate of an analyzer row at the rule level and never something the
   analyzer has already judged. (`exchange-snapin` overlays the same *site* as
   PSSA's generic `snapin` finding on purpose — it names the snap-in. That is one
   site with two findings, not a false positive.) Ledgering a sidecar Blocker away
   as an analyzer false positive is a false negative in the highest-severity
   class.
4. Load the bucket's remediation skill by exact name —
   `get_instructions(kind='skill', query='<skill-name>')`, taking the name from the
   task's `#skill:` marker (or the table in [planning.md](planning.md) for an older
   plan) — and apply it to the located call sites. Load it before editing: each skill
   carries the cmdlet mapping and the non-obvious semantic traps for its bucket, and a
   blind rename from the finding's snippet alone will introduce silent behaviour
   changes.
5. Fix dot-sourced libraries before their callers, and re-scan callers afterwards.
6. If the task is marked **5.1-compatible** (its files have callers left on 5.1),
   apply only the bi-compatible remediations and leave the one-way findings open with
   a recorded reason — see the table in [planning.md](planning.md) Step 2. The
   remediation skills assume a PS7 target and will happily suggest `-AsByteStream` or
   `utf8NoBOM`; that constraint comes from `scenario-instructions.md`, not from them.
7. If the only way you cleared a finding was `-UseWindowsPowerShell` (or implicit
   remoting to a 5.1 session), that finding is **deferred, not remediated**. Record it
   on the deferral list with the reason, and do not mark it fixed. The shim spawns a
   real Windows PowerShell 5.1 process behind the session, so the file still depends on
   5.1 and is still Windows-only — see the scenario SKILL.md, *The compatibility layer
   is a last resort*. Try the native import, a PS7-targeted successor module, and
   remoting first, in that order.

8. **Raising a module to a PowerShell 7-capable version is a behaviour change, not a
   version-string edit.** Assessment Step 2a records which pins are Shimmed or
   Blocked and the lowest version that loads natively. When a task acts on one:

   - Update **every** place the pin appears, not just the manifest —
     `RequiredModules`, `#Requires -Modules`, and any `Install-Module` or
     `PSModulePath` line in the bootstrap and CI definitions. A manifest raised
     while the bootstrap still installs the old version changes nothing about
     what actually loads.
   - Read the module's own breaking-change notes for the majors being crossed and
     treat the call sites as work. Reaching a PowerShell 7-capable version almost
     always crosses a major, which is where the removed parameters and renamed
     output types live.
   - **Regenerate the compatibility profile afterwards and re-baseline.** The
     profile inventories the module's command surface, so the one built in
     assessment describes the version you just replaced. Re-scans compared against
     it are measuring the wrong thing.
   - If the task is marked **5.1-compatible**, check first whether the new version
     still supports 5.1. The publishing pattern that adds PowerShell 7 support
     usually drops 5.1 in the same major, which makes the bump one-way — the
     rule in item 6 applies.

## 3. Validate

Per task:

1. **Re-scan with both detectors.** A task is gated on *both* result sets, because
   each sees things the other cannot.
   - **PSScriptAnalyzer**, via the wrapper
     `pwsh -NoProfile -File <skill>/scripts/Invoke-PSSACompatibilityScan.ps1`,
     against the same generated profile the assessment used. Do not hand-roll
     `Invoke-ScriptAnalyzer` here: it has four silent-false-pass traps (the rule
     needs `Enable = $true` or it checks nothing and reports clean; a relative
     profile path yields 0 findings and 1 error; `ScriptName` is leaf-only; and
     `-Path` is wildcard-enabled, so a file like `build[1].ps1` returns zero
     findings *and* zero errors). The wrapper encodes all of them, and a re-scan
     is the gate that declares a file done. Subtract the false-positive ledger
     before comparing: un-ledgered findings on touched files are regressions.
     Never re-generate the profile mid-run — a different profile makes the
     before/after counts incomparable.
   - **The catalog sidecar**, to confirm the task's blocker id(s) are gone.
     Pass the **same** `-AdditionalRulesPath` the Stage-1 scan used. A re-scan run
     without the contributed catalog silently reports contributed findings under
     the generic rule they supersede, so a task keyed to a contributed id sees that
     id absent and passes green while the code is untouched. The gate is only valid
     when both scans were run with the same rules.

   Write both re-scan outputs to a **scratch path**, never over `scan-findings.csv`: a
   subtree re-scan that overwrote the Stage-1 output would replace the full-scope
   baseline with a partial inventory, destroying the record every later task queries.
   On a 5.1-compatible task the deliberately deferred findings **will** still show up;
   that is the expected result, not a failed gate. Check the deferral list before
   treating a surviving finding as unfinished work.
2. **Run the tests the way the project runs them.** A static re-scan proves the old
   construct is gone; it cannot prove the replacement is right. Pester is the common
   case but rarely the whole entry point — most estates wrap it.

   **Find the project's own test direction first, and prefer it over calling
   `Invoke-Pester` yourself.** The wrapper usually supplies module imports, a
   `PSModulePath`, fixtures, credentials, tags and exclusions that a bare
   `Invoke-Pester` silently omits, and a run missing them fails for reasons that
   have nothing to do with the migration. Look, in order:

   - A repo-root runner: `build.ps1`, `Invoke-Build.ps1`, `psake.ps1`, `RunTests.ps1`,
     `Makefile`, `test.cmd`.
   - CI definitions: `.github/workflows/*.yml`, `azure-pipelines*.yml`, `.gitlab-ci.yml`.
     These are the most reliable statement of how the suite is *actually* run.
   - `*.build.ps1` / `PesterConfiguration` files, `tasks.json`, `CONTRIBUTING.md`, `README`.

   Record the command you used. If you find no direction at all, say so rather than
   inventing one — "no test entry point found" is a real assessment result.

   **Classify before running, not after.** PowerShell test suites are frequently not
   hermetic: they create AD objects, write registry keys, restart services, hit
   production endpoints, or assume a domain-joined host. Running them is a side
   effect on the user's environment, not a read of it. Before the first run, check
   for `New-`/`Set-`/`Remove-`/`Restart-` against live infra, `-ComputerName`
   pointing off-box, hard-coded server or share names, and tags such as
   `Integration`/`E2E`/`RequiresAdmin`.

   | Suite | Action |
   |---|---|
   | Unit — mocked, no external state | Run it. This is the gate. |
   | Unknown / unclassified | Ask before the first run, then classify. |
   | Integration — mutates real environment | **Do not auto-run.** Warn the user, name what it touches, and get explicit consent. Prefer a staging target or the suite's unit-only tag. If neither exists, mark `manual-signoff` and say the gate did not run. |

   A destructive test run is a worse outcome than an unvalidated task, so when the
   classification is uncertain, stop and ask.

   **Import the recorded pin explicitly** when invoking Pester directly. Use the
   version from the `requiredModules` pin captured in Stage 0 Step 0b, the same
   way the assessment probe does:

   ```powershell
   pwsh -NoProfile -Command "Import-Module Pester -RequiredVersion <pinned>; Invoke-Pester -Path <touched tests> -Output Detailed"
   ```

   When the estate pins no exact version, bound the major on both sides rather
   than only the floor:

   ```powershell
   pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99.99; Invoke-Pester -Path <touched tests> -Output Detailed"
   ```

   Windows ships Pester 3.4.0 in-box and `Import-Module Pester` with no constraint
   loads it, at which point every `Should -Be` fails with a parameter-binding error
   that has nothing to do with the migration. A floor alone does not fix this
   safely: `-MinimumVersion` resolves to the **highest** version that satisfies it,
   so on a host that also has Pester 6.x or 7.x the suite runs under a major the
   estate never targeted, and `Should`'s parameter shape changes again.

   **The test suite may itself be migration work.** Pester 3.x does load and run
   under PowerShell 7, so a 3.x suite is usually not a hard blocker. Two things
   specific to this scenario make the pinned version matter anyway:

   - The in-box Pester **shadows** a newer pinned one whenever an import is
     unconstrained, which is what makes the effective version ambiguous.
   - `PSUseCompatibleCommands` unions parameters across every version of a module
     present during profile generation, and old `Should` declares no `param()`
     block. Leaving 3.x on `PSModulePath` while generating the profile therefore
     manufactures phantom findings against `Should -Be`.

   Raise it as its own task when the estate pins 3.x or pins nothing; skip it when
   a 5.x pin is already in place. Pester 5 runs on both 5.1 and 7.x, so it needs
   no sequencing against the host migration and does not break the 5.1 baseline.

   **Do not work out the Pester migration here.** Load the `pester-migration`
   skill, which covers v3→v4, v4→v5 (the Discovery/Run split) and v5→v6:
   `gh skills install github/awesome-copilot pester-migration`, or read it at
   <https://github.com/github/awesome-copilot/tree/main/skills/pester-migration>
   if skill installation is unavailable in this runtime.

   If the tests were already failing before the change, record that baseline first —
   a pre-existing failure is not a regression, and discovering it after the edit
   costs an hour of misdirected debugging.

   **A failing test is work, not a verdict.** When a test fails *because of* the
   migration, fix it and re-run; do not record the task as done with a red suite,
   and do not weaken or delete the test to make it pass. Runtime failures are the
   point of this rung — they are the breaks static analysis structurally cannot
   find, so a failure here is the highest-value signal in the whole scenario.
   Work the failure back to one of:

   - **The edit is wrong.** The replacement cmdlet has different defaults or
     output shape (`Get-CimInstance` returns different property types than
     `Get-WmiObject`; a rewritten `Out-File` now emits UTF-8). Fix the edit.
   - **The test encodes 5.1 behaviour.** It asserts a BOM, a UTF-16 byte count,
     or a Windows-only path. Update the assertion, and say so in the task record —
     this is a real behaviour change the user needs to know about.
   - **The test itself needs migrating.** Route to `pester-migration`.
   - **Pre-existing failure.** Confirm against the baseline and leave it alone.

   If it cannot be fixed, stop and report it rather than marking the file done at
   a rung it did not reach.
3. **Climb the ladder.** Take each touched file as far up
   [validation-ladder.md](validation-ladder.md) as its dependencies allow, and record the
   highest rung reached plus the `runtimeValidation` value. Never silently mark a file
   done at a rung it did not reach.

A task is complete when its findings cleared **and** its files reached the rung the plan
required. If the rung is unreachable in this environment (no live Exchange, no AD), say
so explicitly and mark those files `needs-live-env` or `manual-signoff` — do not claim
runtime validation you cannot perform.

## 4. Decomposition hints

Supplement the system task-execution skill with these scenario-specific breakdown rules:
- Split a large bucket by subtree, or by dot-source cluster (a library plus its callers),
  so a failed pass has a small blast radius.
- Keep a library fix and its caller re-scan in the same task or in adjacent dependent
  tasks — a library changed without its callers re-scanned leaves the estate
  inconsistent.
- The Exchange bucket is usually worth its own breakdown: connection-path replacement is
  a research step that settles a pattern once, then applies broadly.

## 5. Completion

After all tasks: re-run the `scanning-powershell-compatibility` scan over the full
scope, writing to a scratch path, and compare against the assessment baseline. Report
remaining findings by severity, the per-file validation rung distribution, and the
`manual-signoff` queue. Leave `assessment.md` and `scan-findings.csv` as the Stage-1
record — do not overwrite them with the closing scan.

Under partial scope, report against the **closed selection**, not the estate — the
scan covers the common ancestor, so its totals include files nobody asked you to fix.
Separately list the findings deferred to keep shared files running on 5.1, and say
plainly that those files are now bi-compatible rather than migrated: they are done
only once their remaining 5.1 callers move.

Report the compatibility-layer deferrals as their own count, separate from the
5.1-compatibility deferrals above. A run whose blockers were cleared mainly by
`-UseWindowsPowerShell` has not migrated the estate and must not be reported as
green — those files still require Windows PowerShell 5.1 on every machine that
runs them.
