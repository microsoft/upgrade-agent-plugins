# Copyright (c) Microsoft Corporation. All rights reserved.
#
# Runs PSScriptAnalyzer's three compatibility rules over a script estate against
# a generated target profile, annotates each finding from the rule catalog, and
# writes the result as a JSON envelope.
#
# Called in Stage 1 Assessment, Step 3a, as the scenario's primary detector,
# once New-PSSACompatibilityProfile.ps1 has produced and validated the profile
# passed to -ProfilePath. Execution re-runs it to confirm findings cleared.
#
# The three rules and the question each answers:
#   PSUseCompatibleCommands  does this command or parameter exist on the target?
#   PSUseCompatibleTypes     does this .NET type or member exist on the target?
#   PSUseCompatibleSyntax    does this syntax parse on the target version?
#
# Four call-site details decide whether a run reports real results or a
# convincing zero. All four are applied below:
#
#   1. -TargetProfiles must be absolute. PSScriptAnalyzer resolves a relative
#      value against its own bundled compatibility_profiles folder rather than
#      the working directory, does not find the profile there, and returns zero
#      findings plus one -ErrorVariable entry.
#   2. -IncludeRule must name the compatibility rules. A Settings hashtable
#      configures the rules it names; it does not restrict the run to them. So
#      without -IncludeRule the whole default rule set fires as well, and style
#      findings land in the compatibility result set.
#   3. Enable = $true must be set per rule. Each compatibility rule is off by
#      default and checks nothing when merely named.
#   4. DiagnosticRecord.ScriptName is the leaf filename only, so the full path
#      is carried separately. Otherwise two same-named scripts in different
#      directories collapse into one row.
#
# Invoke-ScriptAnalyzer takes a scalar -Path, so files are enumerated here and
# analysed one at a time. That also lets an unreadable subtree be counted rather
# than dropped, so a partial scan is never reportable as a clean one.
#
# Parses under both 5.1 and 7: no ternary, '??', '&&'/'||' or '?.'. The scan
# needs PowerShell 7, and a 5.1 host has to parse the file far enough to report
# that instead of dying on a syntax error.

[CmdletBinding()]
param(
    # Files and/or directories to analyse. Directories are walked recursively.
    [Parameter(Mandatory = $true)]
    [string[]] $Path,

    # The profile produced by New-PSSACompatibilityProfile.ps1. Resolved to an
    # absolute path internally -- see 1 above.
    [Parameter(Mandatory = $true)]
    [string] $ProfilePath,

    # Target version for PSUseCompatibleSyntax, e.g. '7.4'. Syntax checking is
    # version-based and does not read the profile.
    [string] $TargetPSVersion = '7.4',

    # Where to write the findings. '.csv' writes CSV, anything else JSON.
    [string] $OutputPath = 'pssa-findings.json',

    [ValidateSet('Auto', 'Csv', 'Json', 'Both')]
    [string] $OutputFormat = 'Auto',

    [string[]] $Include = @('*.ps1', '*.psm1', '*.psd1'),

    [string[]] $ExcludeDirectory = @('.git', 'node_modules', 'bin', 'obj', 'packages', '.vs'),

    # The rule catalog, used here as a knowledge table rather than a detector.
    # A PSScriptAnalyzer diagnostic says a command is unavailable and stops
    # there: its Severity is always 'Warning', and it carries no category, no
    # remediation and no skill routing. The catalog supplies all four. The join
    # is an exact lookup on the structured Command and Parameter properties PSSA
    # puts on each diagnostic, so it never parses the message text.
    [string] $RulesPath = (Join-Path $PSScriptRoot '../rules/PSCompatibilityRules.psd1'),

    # Contributed catalogs, applied after the base one so an organisation can
    # override the shipped remediation for a command it has its own answer for.
    [string[]] $AdditionalRulesPath = @(),

    # Emit the findings to the pipeline as well as to disk.
    [switch] $PassThru
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$MaxSnippet = 200

function New-Set {
    param([string[]] $Items)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($i in $Items) { $null = $set.Add($i) }
    # The leading comma matters: PowerShell enumerates collections on return, so
    # a bare 'return $set' yields a string[] whose .Contains is case-sensitive.
    return , $set
}

# --- preconditions ------------------------------------------------------------

if ($PSVersionTable.PSEdition -ne 'Core') {
    Write-Warning "Running under $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion). The compatibility rules are meant to run under the PowerShell 7 host being targeted."
}

$pssa = Get-Module -ListAvailable PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $pssa) {
    # A hard stop, not a downgrade to a lesser scan. Without the analyzer the
    # primary detector does not exist, and any inventory produced here would
    # read as clean.
    throw "PSScriptAnalyzer is not installed. It is a prerequisite for this scenario, not an optional enhancement: without it the primary detector does not exist and the scan cannot distinguish a clean estate from an unanalysed one. Install with: Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Scope CurrentUser"
}
Import-Module PSScriptAnalyzer -ErrorAction Stop

if (-not (Test-Path -LiteralPath $ProfilePath)) {
    throw "Target profile not found: $ProfilePath. Generate it first with New-PSSACompatibilityProfile.ps1."
}
# Trap 1. Must be absolute before it reaches PSScriptAnalyzer.
$resolvedProfile = (Resolve-Path -LiteralPath $ProfilePath).Path

# The generator writes a sibling validation file recording whether the profile
# is trustworthy. A contaminated profile inventories commands that do not exist
# on the target, so scanning against one returns passes for code that is broken.
# This refuses to scan rather than produce that result.
$validationPath = [System.IO.Path]::ChangeExtension($resolvedProfile, $null).TrimEnd('.') + '.validation.json'
$validationStatus = 'not-found'
$validationLedger = [ordered]@{ MissingCommands = @(); MissingTypes = @() }
if (Test-Path -LiteralPath $validationPath) {
    $v = Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
    # The generator nests its result under .Validation. Reading .Status off the
    # root yields $null, which compares unequal to 'FAIL' and would let a
    # contaminated profile through.
    $vr = $v.Validation
    if ($null -eq $vr) {
        throw "Validation file $validationPath has no .Validation object. It was not produced by New-PSSACompatibilityProfile.ps1, or its format changed. Refusing to scan against an unverified profile."
    }
    $validationStatus = "$($vr.Status)"
    if ($null -ne $vr.MissingCommands) { $validationLedger.MissingCommands = @($vr.MissingCommands) }
    if ($null -ne $vr.MissingTypes) { $validationLedger.MissingTypes = @($vr.MissingTypes) }
    if ($validationStatus -eq 'FAIL') {
        throw "Target profile failed validation ($validationPath). It is contaminated and will report false passes -- code that is broken will be reported clean. Regenerate it from a clean PowerShell session (no WindowsCompatibility, no implicit remoting) before scanning."
    }
    if ($validationStatus -ne 'PASS' -and $validationStatus -ne 'WARN') {
        throw "Target profile validation status is '$validationStatus', which this script does not recognise. Refusing to scan rather than guess whether the profile is trustworthy."
    }
}
else {
    Write-Warning "No validation file beside the profile ($validationPath). Cannot confirm the profile is uncontaminated; a contaminated profile reports false passes."
}

# --- knowledge index ----------------------------------------------------------
#
# Detection is PSScriptAnalyzer's alone. This index answers only "now that PSSA
# has found it, what do we know about it": category, real severity, remediation
# prose, and which lazy skill performs the rewrite.
#
# Two lookup shapes, because PSSA reports two shapes of finding:
#   Command   -- 'Get-WmiObject' is not available.        Parameter is empty.
#   Parameter -- 'Get-Service' is available, '-ComputerName' is not.
#
# So a Command-kind rule keys on the command name and a Parameter-kind rule keys
# on 'command|parameter'. A Parameter finding does not fall back to the
# command-level entry: Get-Service itself is fine, only the parameter is gone,
# so inheriting the command's Blocker severity would overstate it.

$knowledgeByCommand   = @{}
$knowledgeByParameter = @{}
$knowledgeCatalogs    = New-Object System.Collections.Generic.List[string]

function Add-KnowledgeCatalog {
    param([string] $CatalogPath)

    if ([string]::IsNullOrWhiteSpace($CatalogPath)) { return }
    if (-not (Test-Path -LiteralPath $CatalogPath)) {
        throw "Rule catalog not found: $CatalogPath. Pass -RulesPath, or -AdditionalRulesPath '' to scan without enrichment."
    }
    $resolved = (Resolve-Path -LiteralPath $CatalogPath).Path
    $loaded = Import-PowerShellDataFile -LiteralPath $resolved
    if ($null -eq $loaded -or -not $loaded.ContainsKey('Rules')) {
        throw "Rule catalog $resolved has no 'Rules' key. It is not a compatibility catalog."
    }
    [void] $knowledgeCatalogs.Add($resolved)

    foreach ($r in @($loaded.Rules)) {
        if ($null -eq $r) { continue }
        $skill = ''
        if ($r.ContainsKey('Skill')) { $skill = "$($r.Skill)" }
        $entry = [pscustomobject]@{
            RuleId      = "$($r.Id)"
            Category    = "$($r.Category)"
            Severity    = "$($r.Severity)"
            Skill       = $skill
            Remediation = "$($r.Remediation)"
        }
        # Later catalogs overwrite earlier ones: that is how a contributed
        # catalog replaces the shipped answer for a command.
        if ($r.Kind -eq 'Command') {
            foreach ($m in @($r.Match)) { $knowledgeByCommand["$m"] = $entry }
        }
        elseif ($r.Kind -eq 'Parameter' -and $r.ContainsKey('OnCommand')) {
            foreach ($c in @($r.OnCommand)) {
                foreach ($m in @($r.Match)) { $knowledgeByParameter["$c|$m"] = $entry }
            }
        }
    }
}

Add-KnowledgeCatalog -CatalogPath $RulesPath
foreach ($extra in @($AdditionalRulesPath)) { Add-KnowledgeCatalog -CatalogPath $extra }

# --- file enumeration ---------------------------------------------------------

$excludeSet = New-Set $ExcludeDirectory
$files = New-Object System.Collections.Generic.List[string]

$skippedDirs   = New-Object System.Collections.Generic.List[object]
$skippedLinks  = New-Object System.Collections.Generic.List[string]
$missingInputs = New-Object System.Collections.Generic.List[string]

foreach ($p in $Path) {
    if (-not (Test-Path -LiteralPath $p)) {
        [void] $missingInputs.Add($p)
        Write-Warning "Path not found, skipped: $p"
        continue
    }
    $item = Get-Item -LiteralPath $p
    if ($item.PSIsContainer) {
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push($item.FullName)
        while ($stack.Count -gt 0) {
            $dir = $stack.Pop()
            try {
                foreach ($f in [System.IO.Directory]::EnumerateFiles($dir)) {
                    $name = [System.IO.Path]::GetFileName($f)
                    foreach ($pattern in $Include) {
                        if ($name -like $pattern) { [void] $files.Add($f); break }
                    }
                }
                foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir)) {
                    if ($excludeSet.Contains([System.IO.Path]::GetFileName($sub))) { continue }
                    if ([System.IO.File]::GetAttributes($sub) -band [System.IO.FileAttributes]::ReparsePoint) {
                        [void] $skippedLinks.Add($sub)
                        continue
                    }
                    $stack.Push($sub)
                }
            }
            catch {
                # Enumeration failed on this directory, so its whole subtree is
                # unscanned, not just the directory itself.
                [void] $skippedDirs.Add([pscustomobject]@{
                    Path   = $dir
                    Reason = $_.Exception.Message
                })
                Write-Warning "Skipped unreadable directory (subtree not scanned): $dir -- $($_.Exception.Message)"
            }
        }
    }
    else {
        [void] $files.Add($item.FullName)
    }
}

# --- analysis -----------------------------------------------------------------

# Points 2 and 3: Enable = $true on every rule, and -IncludeRule on every call.
$settings = @{
    Rules = @{
        PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @($resolvedProfile) }
        PSUseCompatibleTypes    = @{ Enable = $true; TargetProfiles = @($resolvedProfile) }
        PSUseCompatibleSyntax   = @{ Enable = $true; TargetVersions = @($TargetPSVersion) }
    }
}
$compatRules = @('PSUseCompatibleCommands', 'PSUseCompatibleTypes', 'PSUseCompatibleSyntax')

$findings = New-Object System.Collections.Generic.List[object]
$enrichedCount = 0
$failedFiles = New-Object System.Collections.Generic.List[object]

$i = 0
foreach ($file in $files) {
    $i++
    if ($i % 200 -eq 0) {
        Write-Progress -Activity 'PSScriptAnalyzer compatibility scan' -Status "$i / $($files.Count)" -PercentComplete (($i / $files.Count) * 100)
    }

    $pssaErrors = $null
    $records = $null
    try {
        # Invoke-ScriptAnalyzer has no -LiteralPath and its -Path is
        # wildcard-enabled, so a path containing wildcard characters is treated
        # as a pattern. 'build[1].ps1' becomes a character class that matches
        # nothing: PSSA returns zero findings AND zero errors, and the file is
        # counted as scanned without having been analysed. Escaping makes the
        # path literal.
        $literal = [System.Management.Automation.WildcardPattern]::Escape($file)
        $records = Invoke-ScriptAnalyzer -Path $literal -Settings $settings `
            -IncludeRule $compatRules -ErrorVariable pssaErrors -ErrorAction SilentlyContinue
    }
    catch {
        [void] $failedFiles.Add([pscustomobject]@{ File = $file; Reason = $_.Exception.Message })
        continue
    }

    # An analyzer error means this file's zero findings prove nothing. Recording
    # it is what separates "analysed and clean" from "not analysed".
    if ($null -ne $pssaErrors -and @($pssaErrors).Count -gt 0) {
        [void] $failedFiles.Add([pscustomobject]@{
            File   = $file
            Reason = ($pssaErrors | ForEach-Object { "$_" }) -join '; '
        })
    }

    foreach ($r in @($records)) {
        if ($null -eq $r) { continue }
        $snippet = "$($r.Extent.Text)"
        if ($snippet.Length -gt $MaxSnippet) { $snippet = $snippet.Substring(0, $MaxSnippet) }
        $snippet = $snippet -replace '\s+', ' '

        # Attach catalog knowledge to the finding. Only Commands records carry a
        # .Command; Syntax and Types records do not, and with StrictMode off
        # that reads as $null rather than throwing. Those findings go out
        # unenriched and are counted as such below, so a catalog gap surfaces as
        # a number instead of as findings that read as low-value.
        $cmdName   = "$($r.Command)"
        $paramName = "$($r.Parameter)"
        $k = $null
        if (-not [string]::IsNullOrEmpty($cmdName)) {
            if (-not [string]::IsNullOrEmpty($paramName)) {
                if ($knowledgeByParameter.ContainsKey("$cmdName|$paramName")) { $k = $knowledgeByParameter["$cmdName|$paramName"] }
            }
            elseif ($knowledgeByCommand.ContainsKey($cmdName)) {
                $k = $knowledgeByCommand[$cmdName]
            }
        }
        $catalogRuleId = ''
        $category      = ''
        $catalogSev    = ''
        $skill         = ''
        $remediation   = ''
        if ($null -ne $k) {
            $catalogRuleId = $k.RuleId
            $category      = $k.Category
            $catalogSev    = $k.Severity
            $skill         = $k.Skill
            $remediation   = $k.Remediation
            $enrichedCount++
        }

        [void] $findings.Add([pscustomobject]@{
            # Point 4: ScriptName is the leaf only, so the full path goes here.
            File     = $file
            Line     = $r.Extent.StartLineNumber
            Column   = $r.Extent.StartColumnNumber
            RuleName = "$($r.RuleName)"
            # PSSA's own severity, which is 'Warning' for every compatibility
            # finding it emits. Triage on CatalogSeverity instead.
            Severity = "$($r.Severity)"
            Message  = "$($r.Message)"
            Snippet  = $snippet
            Command         = $cmdName
            Parameter       = $paramName
            CatalogRuleId   = $catalogRuleId
            Category        = $category
            CatalogSeverity = $catalogSev
            Skill           = $skill
            Remediation     = $remediation
        })
    }
}
Write-Progress -Activity 'PSScriptAnalyzer compatibility scan' -Completed

# --- output -------------------------------------------------------------------

$sorted = @($findings | Sort-Object File, Line, RuleName)

$coverageGaps = $skippedDirs.Count + $missingInputs.Count + $failedFiles.Count

$ext = [System.IO.Path]::GetExtension($OutputPath)
$fmt = $OutputFormat
if ($fmt -eq 'Auto') {
    $fmt = 'Json'
    if ($ext -eq '.csv') { $fmt = 'Csv' }
}

$csvPath = $null
$jsonPath = $null
if ($fmt -eq 'Csv') { $csvPath = $OutputPath }
if ($fmt -eq 'Json') { $jsonPath = $OutputPath }
if ($fmt -eq 'Both') {
    $base = [System.IO.Path]::ChangeExtension($OutputPath, $null).TrimEnd('.')
    $csvPath = "$base.csv"
    $jsonPath = "$base.json"
}

foreach ($p in @($csvPath, $jsonPath)) {
    if ([string]::IsNullOrEmpty($p)) { continue }
    $d = Split-Path -Parent $p
    if (-not [string]::IsNullOrEmpty($d) -and -not (Test-Path -LiteralPath $d)) {
        $null = New-Item -ItemType Directory -Path $d -Force
    }
}

if ($csvPath) {
    $sorted | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
}

if ($jsonPath) {
    $coverageStatus = 'complete'
    if ($coverageGaps -gt 0) { $coverageStatus = 'incomplete' }

    # Flatten to arrays before building the envelope. @() over a non-empty
    # List[object] throws "Argument types do not match" from the enumerable
    # binder in some PowerShell builds, and a pipeline evaluated inside the
    # [ordered]@{} literal hits the same binder, so every value is computed
    # first.
    $unreadableDirs = $skippedDirs.ToArray()
    $missingPaths   = $missingInputs.ToArray()
    $notFollowed    = $skippedLinks.ToArray()
    $analyzerFailed = $failedFiles.ToArray()
    $filesWithFindings = @($sorted | Group-Object File).Count

    $byRule = [ordered]@{}
    foreach ($g in @($sorted | Group-Object RuleName | Sort-Object Count -Descending)) {
        $byRule[$g.Name] = $g.Count
    }

    $envelope = [ordered]@{
        schema    = 'pssa-compatibility-scan/1'
        host      = [ordered]@{
            edition  = "$($PSVersionTable.PSEdition)"
            version  = "$($PSVersionTable.PSVersion)"
            platform = "$($PSVersionTable.Platform)"
        }
        scannedAt = (Get-Date).ToUniversalTime().ToString('o')
        analyzer  = [ordered]@{
            version         = "$($pssa.Version)"
            rules           = $compatRules
            targetProfile   = $resolvedProfile
            profileValidation = $validationStatus
            targetPSVersion = $TargetPSVersion
        }
        # Items the profile is known to be missing. A finding that names one of
        # these is an artifact of profile generation rather than a blocker.
        # Carried here so the consumer does not have to re-derive them.
        falsePositiveLedger = $validationLedger
        scope = [ordered]@{
            requested        = @($Path)
            include          = @($Include)
            excludeDirectory = @($ExcludeDirectory)
            filesScanned     = $files.Count
        }
        # Everything this scan did not see. status 'complete' is the only value
        # that licenses reading a zero as clean. analyzerFailed counts as much
        # as unreadableDirs: a file the analyzer errored on contributed zero
        # findings without having been analysed.
        coverage = [ordered]@{
            status           = $coverageStatus
            unreadableDirs   = $unreadableDirs
            missingInputs    = $missingPaths
            notFollowedLinks = $notFollowed
            analyzerFailed   = $analyzerFailed
        }
        counts = [ordered]@{
            total             = $sorted.Count
            filesWithFindings = $filesWithFindings
            byRule            = $byRule
            # An unenriched finding is one PSSA reported that the catalog has no
            # entry for: real, but with no category, severity or remediation
            # attached. Counted so a catalog gap shows up as a number rather
            # than as findings that read as low-value.
            enriched          = $enrichedCount
            unenriched        = ($sorted.Count - $enrichedCount)
        }
        # The catalogs whose knowledge was joined onto these findings. Recorded
        # for provenance; nothing in this list can add or remove a finding.
        knowledgeCatalogs = $knowledgeCatalogs.ToArray()
        findings = @($sorted)
    }
    # -Depth 8 covers the nested finding objects. The default of 2 truncates the
    # findings array to type names, producing a file that looks structured but
    # carries no findings.
    $envelope | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $jsonPath -Encoding UTF8
}

Write-Host ''
Write-Host 'PSScriptAnalyzer compatibility scan (primary detection)'
Write-Host "  host          : $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
Write-Host "  analyzer      : $($pssa.Version)"
Write-Host "  profile       : $resolvedProfile"
Write-Host "  validation    : $validationStatus"
Write-Host "  syntax target : $TargetPSVersion$(if (-not $PSBoundParameters.ContainsKey('TargetPSVersion')) { ' (DEFAULT -- not supplied)' })"
Write-Host "  files scanned : $($files.Count)"
Write-Host "  files w/ finds: $(@($sorted | Group-Object File).Count)"

if ($coverageGaps -gt 0) {
    Write-Host "  coverage      : INCOMPLETE -- $($skippedDirs.Count) unreadable dir(s), $($missingInputs.Count) missing input path(s), $($failedFiles.Count) file(s) the analyzer could not process"
}
else {
    Write-Host "  coverage      : complete"
}

Write-Host "  findings      : $($sorted.Count)"
Write-Host "  enriched      : $enrichedCount of $($sorted.Count) matched to a catalog rule ($($sorted.Count - $enrichedCount) without remediation detail)"
if ($csvPath)  { Write-Host "  output (csv)  : $csvPath" }
if ($jsonPath) { Write-Host "  output (json) : $jsonPath" }

if ($coverageGaps -gt 0) {
    Write-Host ''
    Write-Host '  COVERAGE GAPS -- this scan did not see the whole scope.'
    Write-Host '  Zero findings under these paths means "not looked at", not "clean".'
    foreach ($m in ($missingInputs | Select-Object -First 20)) {
        Write-Host "    missing input : $m"
    }
    foreach ($s in ($skippedDirs | Select-Object -First 20)) {
        Write-Host "    unreadable    : $($s.Path)"
        Write-Host "                    $($s.Reason)"
    }
    foreach ($fe in ($failedFiles | Select-Object -First 20)) {
        Write-Host "    not analysed  : $($fe.File)"
        Write-Host "                    $($fe.Reason)"
    }
    if ($failedFiles.Count -gt 20) { Write-Host "    ... and $($failedFiles.Count - 20) more not analysed" }
}

if ($skippedLinks.Count -gt 0) {
    Write-Host ''
    Write-Host "  $($skippedLinks.Count) junction/symlink dir(s) not followed (by design; use -Verbose to list)."
    foreach ($l in $skippedLinks) { Write-Verbose "Not followed (reparse point): $l" }
}

Write-Host ''
Write-Host 'By catalog severity (the triage order; PSSA''s own severity is Warning for all of these):'
$sorted | Where-Object { $_.CatalogSeverity } | Group-Object CatalogSeverity | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-28} {1}" -f $_.Name, $_.Count)
}
if ($enrichedCount -lt $sorted.Count) {
    Write-Host ("  {0,-28} {1}" -f '(no catalog entry)', ($sorted.Count - $enrichedCount))
}

Write-Host ''
Write-Host 'By rule:'
$sorted | Group-Object RuleName | Sort-Object Count -Descending | ForEach-Object {
    Write-Host ("  {0,-28} {1}" -f $_.Name, $_.Count)
}

Write-Host ''
Write-Host '  Static analysis over-reports in two known classes -- unresolved local'
Write-Host '  functions and abbreviated parameters. Triage before planning; see the'
Write-Host '  triaging-powershell-analyzer-findings skill.'

if ($PassThru) { $sorted }

# Exit non-zero when the scan found something to act on, so a caller can gate on
# it. A coverage gap also exits non-zero: a partial scan must not read as clean.
if ($sorted.Count -gt 0 -or $coverageGaps -gt 0) { exit 1 }
exit 0
