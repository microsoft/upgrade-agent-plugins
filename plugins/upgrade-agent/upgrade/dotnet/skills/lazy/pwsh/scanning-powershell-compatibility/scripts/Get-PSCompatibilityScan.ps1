# Copyright (c) Microsoft Corporation. All rights reserved.
#
# Windows PowerShell 5.1 -> PowerShell 7.x compatibility scan (sidecar).
#
# Walks a tree of scripts with the PowerShell parser, applies the declarative
# rule catalog in rules/PSCompatibilityRules.psd1, and writes one row per
# finding as CSV, a JSON envelope, or both.
#
# Called in Stage 1 Assessment, Step 3b, after Invoke-PSSACompatibilityScan.ps1.
# PSScriptAnalyzer is the primary detector; this covers what it is structurally
# unable to see -- encoding and other behavioral changes, parameter values, type
# accelerators, module availability, COM, and deprecated-but-present cmdlets --
# and supplies the severity and Skill routing metadata for every finding,
# including PSScriptAnalyzer's. The two result sets are joined on CatalogRuleId
# during triage.
#
# Matching runs over parser output rather than file text, so every token is
# classified before a rule sees it. Comments, comment-based help and ordinary
# string literals are out of scope structurally, and unambiguous parameter
# prefixes resolve to their full names, so '-Enc Byte' matches a rule written
# against '-Encoding'.
#
# Parses under both 5.1 and 7: no ternary, '??', '&&'/'||', '?.' or 'clean {}'.
# 5.1 is the guaranteed-present host on Windows, and the only host that can
# fully parse a script containing 'workflow'.
#
# TWO FIDELITY LEVELS
# -------------------
# Full   - the file parsed; the AST is walked and every rule kind applies.
# Tokens - the file did not parse under this host. The token stream survives the
#          failure fully classified, so name-based rules (Command, Keyword, Type,
#          Module, StringLiteral, MemberAccess, RequiresEdition, RequiresVersion)
#          still apply, and CommandArgument rules degrade to a broad unanchored
#          match. The kinds that need real AST shape -- Parameter,
#          ParameterValue, MissingParameter, NullComparison, FileRedirection --
#          cannot be evaluated at all. The run summary names the specific active
#          rules that were skipped.
#
# A file usually reaches only Tokens fidelity because PowerShell 7 refuses
# 'workflow' outright, which is itself a Blocker finding -- so the degraded file
# is the one that most needs migrating. Re-run under 5.1 to bring those files to
# Full fidelity. Genuinely malformed scripts also land here, and are reported
# separately so they are never mistaken for clean ones.

[CmdletBinding()]
param(
    # Files or directories to scan.
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]] $Path,

    # Rule catalog. Point this at your own copy to replace the shipped rules
    # outright. To *add* rules while keeping the shipped ones, use
    # -AdditionalRulesPath instead -- see "Extending the catalog" in SKILL.md.
    [string] $RulesPath,

    # Extra rule catalogs merged on top of the base one. A rule whose Id matches
    # a base rule replaces it; any other rule is added. This is the path an
    # organisation uses to contribute its own snap-in and module knowledge
    # without forking the shipped catalog.
    [string[]] $AdditionalRulesPath,

    # Where to write the findings. The format follows the extension unless
    # -OutputFormat says otherwise: '.json' writes JSON, anything else CSV.
    [string] $OutputPath = 'scan-findings.csv',

    # Csv  -- flat findings table, one row per finding. The canonical artifact;
    #         planning and execution query it by RuleId and File.
    # Json -- an envelope carrying the findings plus the run metadata: host,
    #         catalogs, coverage gaps, degraded files and the counts. Use it when
    #         a downstream tool needs those signals, which a flat CSV cannot
    #         carry and which otherwise exist only as console text.
    # Both -- writes both, siblings of -OutputPath.
    # Auto -- infer from the -OutputPath extension.
    [ValidateSet('Auto', 'Csv', 'Json', 'Both')]
    [string] $OutputFormat = 'Auto',

    [string[]] $Include = @('*.ps1', '*.psm1', '*.psd1'),

    # Directory names skipped wholesale, at any depth.
    [string[]] $ExcludeDirectory = @('.git', 'node_modules', 'bin', 'obj', 'packages', '.vs')
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$MaxSnippet = 200
$IC = [System.StringComparison]::OrdinalIgnoreCase

function New-Set {
    param([string[]] $Items)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($i in $Items) { $null = $set.Add($i) }
    # The leading comma matters: PowerShell enumerates collections on return, so
    # a bare 'return $set' yields a string[] whose .Contains is case-sensitive.
    return , $set
}

function Find-RequiresToken {
    # A script can carry several #Requires directives; point each finding at the
    # one that actually produced it rather than at whichever came first.
    param($ReqTokens, [string] $Needle)
    foreach ($t in @($ReqTokens)) {
        if ($t.Text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return @{ Line = $t.Extent.StartLineNumber; Text = $t.Text }
        }
    }
    if (@($ReqTokens).Count -gt 0) {
        $f = @($ReqTokens)[0]
        return @{ Line = $f.Extent.StartLineNumber; Text = $f.Text }
    }
    return @{ Line = 1; Text = '' }
}

function Test-AnyContains {
    param([string] $Value, [string[]] $Needles)
    if ([string]::IsNullOrEmpty($Value)) { return $false }
    foreach ($n in $Needles) {
        if ($Value.IndexOf($n, $IC) -ge 0) { return $true }
    }
    return $false
}

# --- load the rule catalog ----------------------------------------------------

if ([string]::IsNullOrWhiteSpace($RulesPath)) {
    $RulesPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'rules/PSCompatibilityRules.psd1'
}
if (-not (Test-Path -LiteralPath $RulesPath)) {
    throw "Rule catalog not found: $RulesPath"
}

# Import-PowerShellDataFile parses restricted data-language literals and never
# evaluates code, so a hand-edited or third-party rule file cannot execute
# anything. Keep it: dot-sourcing or Invoke-Expression would make a contributed
# catalog an arbitrary-code path.
$catalog = Import-PowerShellDataFile -LiteralPath $RulesPath
$rules = @($catalog.Rules)
if ($rules.Count -eq 0) { throw "Rule catalog '$RulesPath' defines no rules." }

# --- merge additional catalogs ------------------------------------------------

# Every catalog file that fed this run. Excluded from enumeration below so a
# catalog living inside the scanned tree is not scanned as a script: its Match
# strings would match themselves and report as findings.
$catalogFiles = New-Object System.Collections.Generic.List[string]
$catalogFiles.Add((Resolve-Path -LiteralPath $RulesPath).ProviderPath)

$addedCount = 0
$overriddenIds = New-Object System.Collections.Generic.List[string]

foreach ($extra in @($AdditionalRulesPath)) {
    if ([string]::IsNullOrWhiteSpace($extra)) { continue }
    if (-not (Test-Path -LiteralPath $extra)) {
        throw "Additional rule catalog not found: $extra"
    }
    $catalogFiles.Add((Resolve-Path -LiteralPath $extra).ProviderPath)

    $extraCatalog = Import-PowerShellDataFile -LiteralPath $extra
    foreach ($r in @($extraCatalog.Rules)) {
        if ([string]::IsNullOrWhiteSpace($r.Id)) {
            throw "A rule in '$extra' has no Id. Id is the join key between the findings CSV, the plan and the re-scan gate; it is required."
        }
        if ([string]::IsNullOrWhiteSpace($r.Kind)) {
            throw "Rule '$($r.Id)' in '$extra' has no Kind."
        }

        # Match by Id so a contributed rule can correct a shipped one in place --
        # the id stays stable, so plans written against it keep resolving.
        $existing = -1
        for ($i = 0; $i -lt $rules.Count; $i++) {
            if ($rules[$i].Id -eq $r.Id) { $existing = $i; break }
        }
        if ($existing -ge 0) {
            $rules[$existing] = $r
            $overriddenIds.Add($r.Id)
        }
        else {
            $rules += $r
            $addedCount++
        }
    }
}

foreach ($r in $rules) {
    # Materialise the match list once. The scan loops run per AST node across
    # the whole estate, so wrapping $r.Match in @(...) inside them would
    # allocate an array on every iteration.
    $r['MatchArray'] = [string[]] @($r.Match)
    $r['MatchSet'] = New-Set $r['MatchArray']
    if ($r.ContainsKey('OnCommand')) { $r['CommandSet'] = New-Set @($r.OnCommand) }
    if (-not $r.ContainsKey('MatchMode')) { $r['MatchMode'] = 'Exact' }
    # Optional gate: report the missing parameter only when one of these is
    # present on the call. Tee-Object writes a file only under -FilePath, so
    # without the gate the rule also fires on `Tee-Object -Variable`, which
    # writes nothing.
    #
    # Must be conditional: @($null) is a ONE-element array, not an empty one, so
    # setting this unconditionally makes every rule look gated and suppresses
    # the whole MissingParameter family.
    if ($r.ContainsKey('RequiresParameter')) {
        $r['RequiresArray'] = [string[]] @($r.RequiresParameter)
    }
    else {
        $r['RequiresArray'] = [string[]] @()
    }
}

# Fail closed on a malformed rule. Get-RulesOfKind selects by exact Kind name, so
# a misspelled Kind ('Commands') loads fine, counts in the rule total the console
# prints, and is never dispatched by any matcher -- a contributed blocker rule
# would appear accepted while never being applied.
$KnownKinds = @{}
foreach ($k in @(
        'Command', 'Keyword', 'Type', 'StringLiteral', 'Parameter', 'ParameterValue',
        'MissingParameter', 'Module', 'RequiresEdition', 'RequiresVersion',
        'NullComparison', 'FileRedirection', 'MemberAccess', 'StaticMember',
        'CommandArgument')) { $KnownKinds[$k] = $true }

# These kinds dispatch on AST shape, not on a name list, so an empty Match is
# correct for them -- the shipped 'null-on-right' rule is exactly this case.
$StructuralKinds = @{ 'NullComparison' = $true; 'FileRedirection' = $true }

# Kinds that describe something *about a command* need to say which command;
# without OnCommand the matcher has nothing to anchor to.
$CommandAnchoredKinds = @{
    'Parameter'       = $true
    'ParameterValue'  = $true
    'MissingParameter' = $true
    'CommandArgument' = $true
}

foreach ($r in $rules) {
    if (-not $KnownKinds.ContainsKey($r.Kind)) {
        throw ("Rule '$($r.Id)' has unknown Kind '$($r.Kind)'. Valid kinds: " +
            (($KnownKinds.Keys | Sort-Object) -join ', ') +
            ". An unknown Kind loads but is never applied, so the rule would silently do nothing.")
    }
    if ($r['MatchArray'].Count -eq 0 -and -not $StructuralKinds.ContainsKey($r.Kind)) {
        throw "Rule '$($r.Id)' (Kind '$($r.Kind)') has no Match values, so it can never fire."
    }
    if ($CommandAnchoredKinds.ContainsKey($r.Kind) -and -not $r.ContainsKey('OnCommand')) {
        throw "Rule '$($r.Id)' (Kind '$($r.Kind)') has no OnCommand, so it has no command to anchor to and can never fire."
    }
    if ([string]::IsNullOrWhiteSpace($r.Category)) {
        throw "Rule '$($r.Id)' has no Category. Category drives assessment grouping."
    }
    if ([string]::IsNullOrWhiteSpace($r.Severity)) {
        throw "Rule '$($r.Id)' has no Severity. Severity drives the exit gate and the plan ordering."
    }
}

# Rules carrying SupersededBy are knowledge, not detectors. PSScriptAnalyzer owns
# detection for anything it covers, so a superseded rule must not emit a finding:
# two detectors for one defect means the totals have to be reconciled by
# subtraction, and a static subtraction is fail-open -- it discounts a row even
# when the analyzer did not fire there.
#
# They are still loaded, schema-validated, and carry their full payload, because
# they do two jobs unrelated to emitting rows:
#   1. New-PSSACompatibilityProfile.ps1 derives its contamination sentinel list
#      from Command-kind Match values, which come from these rules. Dropping the
#      entries would leave the profile validator with nothing to check.
#   2. Invoke-PSSACompatibilityScan.ps1 joins them onto the analyzer's output to
#      supply the Category, Severity, Skill and Remediation PSSA does not carry.
$knowledgeOnly = @($rules | Where-Object { $_.ContainsKey('SupersededBy') })
$activeRules = @($rules | Where-Object { -not $_.ContainsKey('SupersededBy') })

function Get-RulesOfKind {
    param([string] $Kind)
    # Comma-wrapped: PowerShell unrolls an array returned from a function, so a
    # kind matching one rule would come back as a bare hashtable and a kind
    # matching none as $null. Callers treat these as arrays -- e.g.
    # `$RulesParameter + $RulesParamValue` would become hashtable addition and
    # throw, and .Count on a lone hashtable reports its key count instead of 1.
    # The outer comma survives the unroll and hands back the array intact.
    return , @($activeRules | Where-Object { $_.Kind -eq $Kind })
}

$RulesCommand = Get-RulesOfKind 'Command'
$RulesKeyword = Get-RulesOfKind 'Keyword'
$RulesType = Get-RulesOfKind 'Type'
$RulesString = Get-RulesOfKind 'StringLiteral'
$RulesParameter = Get-RulesOfKind 'Parameter'
$RulesParamValue = Get-RulesOfKind 'ParameterValue'
$RulesMissingParam = Get-RulesOfKind 'MissingParameter'
$RulesModule = Get-RulesOfKind 'Module'
$RulesReqEdition = Get-RulesOfKind 'RequiresEdition'
$RulesReqVersion = Get-RulesOfKind 'RequiresVersion'
$RulesNullCompare = Get-RulesOfKind 'NullComparison'
$RulesRedirection = Get-RulesOfKind 'FileRedirection'
$RulesMemberAccess = Get-RulesOfKind 'MemberAccess'
$RulesStaticMember = Get-RulesOfKind 'StaticMember'
$RulesCommandArg = Get-RulesOfKind 'CommandArgument'

# Kinds the token pass cannot evaluate because they need real AST shape, not just
# a classified name. Derived into a rule-ID list so the degraded-file warning
# names the rules that were actually skipped instead of a hand-maintained kind
# list that drifts every time a kind is added.
$TokenBlindKinds = @{
    'Parameter'        = $true
    'ParameterValue'   = $true
    'MissingParameter' = $true
    'NullComparison'   = $true
    'FileRedirection'  = $true
    # A member token carries no owning type, so the token pass cannot tell
    # [System.Text.Encoding]::Default from any other ::Default.
    'StaticMember'     = $true
}
$tokenBlindRuleIds = @($activeRules | Where-Object { $TokenBlindKinds.ContainsKey($_.Kind) } | ForEach-Object { $_.Id })

# CommandArgument rules are indexed by the command they anchor to, for the same
# reason as $CommandRuleIndex below.
$CommandArgRuleIndex = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[object]]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($r in $RulesCommandArg) {
    foreach ($c in @($r.OnCommand)) {
        if (-not $CommandArgRuleIndex.ContainsKey($c)) {
            $CommandArgRuleIndex[$c] = New-Object System.Collections.Generic.List[object]
        }
        $CommandArgRuleIndex[$c].Add($r)
    }
}

# Command lookups are indexed by name so a command node costs one hash probe
# instead of one Contains() per Command rule. This runs a few hundred thousand
# times on a real estate.
$CommandRuleIndex = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[object]]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($r in $RulesCommand) {
    foreach ($m in $r['MatchArray']) {
        if (-not $CommandRuleIndex.ContainsKey($m)) {
            $CommandRuleIndex[$m] = New-Object System.Collections.Generic.List[object]
        }
        $CommandRuleIndex[$m].Add($r)
    }
}

# Every Parameter/ParameterValue/MissingParameter rule is scoped to named
# commands, so a command outside this set can skip argument inspection entirely.
# Guard the assumption: a rule added later without OnCommand would otherwise be
# silently dropped.
$ParamScopedCommands = New-Set @()
$ParamRulesAreScoped = $true
foreach ($r in @($RulesParameter + $RulesParamValue + $RulesMissingParam)) {
    if (-not $r.ContainsKey('OnCommand')) { $ParamRulesAreScoped = $false; continue }
    foreach ($c in @($r.OnCommand)) { $null = $ParamScopedCommands.Add($c) }
}

# Only commands that bring a module into the session. Get-Module inspects and
# Remove-Module unloads; neither creates a dependency on the module being
# importable under PowerShell 7, so neither is an import for rule purposes.
$ModuleImportCommands = New-Set @('Import-Module', 'ipmo')

# New-Object constructs a type from a string argument, which no TypeExpressionAst
# ever covers. It has no built-in alias, so the name alone is the whole set.
$NewObjectCommands = New-Set @('New-Object')

# --- findings accumulator -----------------------------------------------------

$findings = New-Object System.Collections.Generic.List[object]
$fileStatus = New-Object System.Collections.Generic.List[object]

# One rule firing twice on one line is one thing to fix, not two. A single line
# can express the same construct in two matchable forms --
# '[Windows.Forms.Form] $f = New-Object Windows.Forms.Form' is both a type
# constraint and a New-Object argument -- which would inflate blocker totals and
# put the same site in the plan twice.
$seenFindings = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

function Add-Finding {
    param(
        [string] $File,
        $Rule,
        [int] $Line,
        [string] $Snippet,
        [string] $Fidelity
    )
    $s = $Snippet
    if ($null -eq $s) { $s = '' }
    $s = $s.Trim()
    if ($s.Length -gt $MaxSnippet) { $s = $s.Substring(0, $MaxSnippet) }
    if (-not $seenFindings.Add("$File|$Line|$($Rule.Id)")) { return }
    $findings.Add([pscustomobject]@{
            File       = $File
            Line       = $Line
            RuleId     = $Rule.Id
            Category   = $Rule.Category
            Severity   = $Rule.Severity
            Fidelity   = $Fidelity
            # Retained so the CSV/JSON schema stays stable for anything already
            # consuming it. It is always 'catalog': superseded rules are filtered
            # out before matching, so every finding that reaches here came from an
            # active rule.
            DetectedBy = 'catalog'
            Snippet    = $s
        })
}

function Add-NodeFinding {
    param([string] $File, $Rule, $Node)
    $line = $Node.Extent.StartLineNumber
    $snippet = ''
    try { $snippet = $Node.Extent.StartScriptPosition.Line } catch { }
    Add-Finding -File $File -Rule $Rule -Line $line -Snippet $snippet -Fidelity 'Full'
}

function Test-StaticMemberMatch {
    # Rules are written against the full type name ('System.Text.Encoding::Default'),
    # but PowerShell resolves shortened forms too -- estates use both
    # '[System.Net.ServicePointManager]' and '[Net.ServicePointManager]'. Matching on
    # a dotted suffix accepts either without letting an unrelated 'MyText.Encoding'
    # match, because the character before the suffix must be a namespace separator.
    param([string] $Pair, [string[]] $Patterns)
    foreach ($p in $Patterns) {
        if ($Pair.Equals($p, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($Pair.Length -gt $p.Length -and
            $Pair.EndsWith($p, [System.StringComparison]::OrdinalIgnoreCase) -and
            $Pair[$Pair.Length - $p.Length - 1] -eq '.') {
            return $true
        }
    }
    return $false
}

function Get-NewObjectTypeName {
    # The type handed to New-Object is a plain argument, either positional or via
    # -TypeName, and parameters may appear in any order. Anything computed
    # ('New-Object $t') is skipped rather than guessed at.
    param($Elements, [int] $Count)
    # -Strict is New-Object's only switch; every other parameter consumes the
    # element after it, which must not be mistaken for the positional type.
    for ($i = 1; $i -lt $Count; $i++) {
        $el = $Elements[$i]
        if ($el -isnot [System.Management.Automation.Language.CommandParameterAst]) {
            # First positional argument is the type name.
            if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                return [string] $el.Value
            }
            return $null
        }
        $pn = $el.ParameterName
        $isTypeName = -not [string]::IsNullOrEmpty($pn) -and
            'TypeName'.StartsWith($pn, [System.StringComparison]::OrdinalIgnoreCase)
        # '-TypeName:Foo' carries its value on the parameter node itself.
        if ($null -ne $el.Argument) {
            if ($isTypeName -and
                $el.Argument -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                return [string] $el.Argument.Value
            }
            continue
        }
        if ($pn -and 'Strict'.StartsWith($pn, [System.StringComparison]::OrdinalIgnoreCase) -and -not $isTypeName) {
            continue
        }
        if ($i + 1 -lt $Count -and
            $Elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
            $v = $Elements[$i + 1]
            $i++
            if ($isTypeName -and
                $v -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                return [string] $v.Value
            }
        }
    }
    return $null
}

# --- file enumeration ---------------------------------------------------------

$excludeSet = New-Set $ExcludeDirectory
$files = New-Object System.Collections.Generic.List[string]

# Coverage gaps. A scan that quietly failed to read part of the tree must never
# be reportable as a clean scan, so every path not enumerated is recorded here
# and surfaced in the summary alongside the finding counts.
$skippedDirs    = New-Object System.Collections.Generic.List[object]
$skippedLinks   = New-Object System.Collections.Generic.List[string]
$missingInputs  = New-Object System.Collections.Generic.List[string]

# Directories pruned by -ExcludeDirectory. Recorded rather than dropped: the
# defaults are .NET build-output conventions, and a PowerShell estate may keep
# production scripts in a folder called 'bin'. Silent pruning would let those
# scripts vanish from a tree the scan still reports as clean.
$prunedDirs     = New-Object System.Collections.Generic.List[string]

# The rule catalogs are never scan targets. A contributed catalog commonly lives
# in the repo being scanned and '*.psd1' is in the default -Include, so without
# this every rule's Match strings would match themselves and be reported as
# findings against the catalog.
$catalogSet = New-Set @($catalogFiles)

foreach ($p in $Path) {
    if (-not (Test-Path -LiteralPath $p)) {
        [void] $missingInputs.Add($p)
        Write-Warning "Path not found, skipped: $p"
        continue
    }
    $item = Get-Item -LiteralPath $p
    if ($item.PSIsContainer) {
        # Enumerate with System.IO over an explicit stack. The walk has to
        # produce the same set on both hosts and prune before descending: 5.1
        # ignores -Include when it is combined with -LiteralPath -Recurse and
        # returns every file in the tree, and -Recurse descends into excluded
        # directories before they can be filtered. Enumerating paths also avoids
        # materialising a FileInfo per entry across a large estate.
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push($item.FullName)
        while ($stack.Count -gt 0) {
            $dir = $stack.Pop()
            try {
                foreach ($f in [System.IO.Directory]::EnumerateFiles($dir)) {
                    $name = [System.IO.Path]::GetFileName($f)
                    foreach ($pattern in $Include) {
                        if ($name -like $pattern) { $files.Add($f); break }
                    }
                }
                foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir)) {
                    if ($excludeSet.Contains([System.IO.Path]::GetFileName($sub))) {
                        [void] $prunedDirs.Add($sub)
                        continue
                    }
                    # Do not follow junctions or symlinks: they can cycle or escape the tree.
                    if ([System.IO.File]::GetAttributes($sub) -band [System.IO.FileAttributes]::ReparsePoint) {
                        [void] $skippedLinks.Add($sub)
                        continue
                    }
                    $stack.Push($sub)
                }
            }
            catch {
                # Enumeration failed, so this directory's files AND all its
                # children go unenumerated. Recorded and surfaced in the summary
                # so the skipped subtree is not read as clean.
                [void] $skippedDirs.Add([pscustomobject]@{
                    Path   = $dir
                    Reason = $_.Exception.Message
                })
                Write-Warning "Skipped unreadable directory (subtree not scanned): $dir -- $($_.Exception.Message)"
            }
        }
    }
    else {
        $files.Add($item.FullName)
    }
}

$files = @($files | Sort-Object -Unique | Where-Object { -not $catalogSet.Contains($_) })
Write-Verbose "Scanning $($files.Count) file(s) with $($rules.Count) rule(s) from $RulesPath"

# --- scan ---------------------------------------------------------------------

$anyPred = { $true }

# Allocated once and cleared per command node rather than per node: the scan
# visits hundreds of thousands of command nodes on a real estate.
$seenParams = New-Set @()

foreach ($file in $files) {

    $tokens = $null
    $errors = $null
    $ast = $null
    $threw = $false
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref] $tokens, [ref] $errors)
    }
    catch {
        $threw = $true
    }

    $errorCount = 0
    if ($null -ne $errors) { $errorCount = @($errors).Count }
    $parsedClean = (-not $threw) -and ($null -ne $ast) -and ($errorCount -eq 0)

    $firstError = ''
    if ($errorCount -gt 0) { $firstError = @($errors)[0].Message }

    $fileStatus.Add([pscustomobject]@{
            File       = $file
            Fidelity   = $(if ($parsedClean) { 'Full' } else { 'Tokens' })
            ParseError = $firstError
        })

    # ---------------------------------------------------------------- token pass
    # Always available -- the tokenizer runs before the parse error is raised, so
    # the stream is complete and correctly classified even for a rejected file.
    if (-not $parsedClean) {
        if ($null -eq $tokens) { continue }

        $prevWasModuleCommand = $false
        foreach ($t in @($tokens)) {
            $text = $t.Text
            if ([string]::IsNullOrEmpty($text)) { continue }
            $line = $t.Extent.StartLineNumber
            $snippet = ''
            try { $snippet = $t.Extent.StartScriptPosition.Line } catch { }

            $flags = [string] $t.TokenFlags
            $isCommandName = $flags.IndexOf('CommandName', $IC) -ge 0

            # A module name given to Import-Module is just a bare Identifier in the
            # token stream -- nothing marks it as a module. Carry the fact that the
            # previous command was a module import across one token to reach it.
            if ($prevWasModuleCommand -and -not $isCommandName -and
                ($t.Kind -eq 'Identifier' -or $t.Kind -eq 'Generic' -or
                $t.Kind -eq 'StringLiteral' -or $t.Kind -eq 'StringExpandable')) {
                foreach ($r in $RulesModule) {
                    if ($r.MatchSet.Contains($text.Trim('"', "'"))) {
                        Add-Finding -File $file -Rule $r -Line $line -Snippet $snippet -Fidelity 'Tokens'
                    }
                }
            }
            if ($t.Kind -ne 'Parameter') {
                $prevWasModuleCommand = $isCommandName -and $ModuleImportCommands.Contains($text)
            }

            if ($isCommandName) {
                foreach ($r in $RulesCommand) {
                    if ($r.MatchSet.Contains($text)) {
                        Add-Finding -File $file -Rule $r -Line $line -Snippet $snippet -Fidelity 'Tokens'
                    }
                }
            }
            elseif ($flags.IndexOf('TypeName', $IC) -ge 0) {
                foreach ($r in $RulesType) {
                    $hit = $false
                    if ($r.MatchMode -eq 'Contains') { $hit = Test-AnyContains $text @($r.Match) }
                    else { $hit = $r.MatchSet.Contains($text) }
                    if ($hit) {
                        Add-Finding -File $file -Rule $r -Line $line -Snippet $snippet -Fidelity 'Tokens'
                    }
                }
            }
            elseif ($flags.IndexOf('Keyword', $IC) -ge 0) {
                foreach ($r in $RulesKeyword) {
                    if ($r.MatchSet.Contains($text)) {
                        Add-Finding -File $file -Rule $r -Line $line -Snippet $snippet -Fidelity 'Tokens'
                    }
                }
            }
            elseif ($flags.IndexOf('MemberName', $IC) -ge 0) {
                foreach ($r in $RulesMemberAccess) {
                    if ($r.MatchSet.Contains($text)) {
                        Add-Finding -File $file -Rule $r -Line $line -Snippet $snippet -Fidelity 'Tokens'
                    }
                }
            }
            elseif ($t.Kind -eq 'StringLiteral' -or $t.Kind -eq 'StringExpandable' -or
                $t.Kind -eq 'Generic' -or $t.Kind -eq 'Identifier') {
                # Generic/Identifier are included to stay consistent with the AST
                # pass, where an unquoted command argument is a
                # StringConstantExpressionAst and so already matches StringLiteral
                # rules. Without them 'Add-PSSnapin Contoso.Foo' would match at
                # Full fidelity but not at Tokens, so a degraded file would lose
                # its specific rule and fall back to the generic one. Command
                # names cannot reach here: $isCommandName is handled earlier in
                # this chain.
                foreach ($r in $RulesString) {
                    if (Test-AnyContains $text @($r.Match)) {
                        Add-Finding -File $file -Rule $r -Line $line -Snippet $snippet -Fidelity 'Tokens'
                    }
                }
                # CommandArgument rules lose their command anchor here: once the
                # parse has failed the token stream has no reliable notion of
                # "argument of X". They match broadly instead, trading precision
                # for recall rather than dropping a Blocker rule on the files
                # that are hardest to read. Findings carry Fidelity='Tokens' so
                # triage can tell the two apart.
                foreach ($r in $RulesCommandArg) {
                    $bare = $text.Trim('"', "'")
                    if ([string]::IsNullOrEmpty($bare)) { continue }
                    if ($r.MatchMode -eq 'Contains') {
                        if (Test-AnyContains $bare @($r.Match)) {
                            Add-Finding -File $file -Rule $r -Line $line -Snippet $snippet -Fidelity 'Tokens'
                        }
                    }
                    elseif ($r.MatchSet.Contains($bare)) {
                        Add-Finding -File $file -Rule $r -Line $line -Snippet $snippet -Fidelity 'Tokens'
                    }
                }
            }
            elseif ($t.Kind -eq 'Comment' -and $text.IndexOf('#requires', $IC) -ge 0) {
                if ($text.IndexOf('-psedition', $IC) -ge 0) {
                    foreach ($r in $RulesReqEdition) {
                        foreach ($m in @($r.Match)) {
                            if ($text.IndexOf($m, $IC) -ge 0) {
                                Add-Finding -File $file -Rule $r -Line $line -Snippet $text -Fidelity 'Tokens'
                            }
                        }
                    }
                }
                if ($text -match '(?i)-version\s+(\d+)') {
                    foreach ($r in $RulesReqVersion) {
                        if ($r.MatchSet.Contains($Matches[1])) {
                            Add-Finding -File $file -Rule $r -Line $line -Snippet $text -Fidelity 'Tokens'
                        }
                    }
                }
                if ($text.IndexOf('-module', $IC) -ge 0) {
                    foreach ($r in $RulesModule) {
                        foreach ($m in @($r.Match)) {
                            if ($text.IndexOf($m, $IC) -ge 0) {
                                Add-Finding -File $file -Rule $r -Line $line -Snippet $text -Fidelity 'Tokens'
                            }
                        }
                    }
                }
            }
        }
        continue
    }

    # ------------------------------------------------------------------ AST pass

    # #Requires is metadata hoisted onto the script block rather than a node in
    # the tree, so it is read off ScriptRequirements and located via the comment
    # tokens.
    $req = $ast.ScriptRequirements
    if ($null -ne $req) {
        $reqTokens = @()
        foreach ($t in @($tokens)) {
            if ($t.Kind -eq 'Comment' -and $t.Text -match '^\s*#requires') { $reqTokens += $t }
        }

        if ($null -ne $req.RequiredPSEditions) {
            foreach ($ed in $req.RequiredPSEditions) {
                foreach ($r in $RulesReqEdition) {
                    if ($r.MatchSet.Contains([string] $ed)) {
                        $tk = Find-RequiresToken $reqTokens '-psedition'
                        Add-Finding -File $file -Rule $r -Line $tk.Line -Snippet $tk.Text -Fidelity 'Full'
                    }
                }
            }
        }

        if ($null -ne $req.RequiredPSVersion) {
            foreach ($r in $RulesReqVersion) {
                if ($r.MatchSet.Contains([string] $req.RequiredPSVersion.Major)) {
                    $tk = Find-RequiresToken $reqTokens '-version'
                    Add-Finding -File $file -Rule $r -Line $tk.Line -Snippet $tk.Text -Fidelity 'Full'
                }
            }
        }

        if ($null -ne $req.RequiredModules) {
            foreach ($m in $req.RequiredModules) {
                if ($null -eq $m.Name) { continue }
                foreach ($r in $RulesModule) {
                    if ($r.MatchSet.Contains($m.Name)) {
                        $tk = Find-RequiresToken $reqTokens '-module'
                        Add-Finding -File $file -Rule $r -Line $tk.Line -Snippet $tk.Text -Fidelity 'Full'
                    }
                }
            }
        }
    }

    # One walk of the tree; every rule kind dispatches off the node type. The
    # branch bodies use literal IndexOf rather than -match, which costs
    # substantially more per call and runs here for every node of every script.
    foreach ($n in $ast.FindAll($anyPred, $true)) {

        if ($n -is [System.Management.Automation.Language.CommandAst]) {
            $name = $n.GetCommandName()
            if ($null -eq $name) { continue }

            $hitRules = $null
            if ($CommandRuleIndex.TryGetValue($name, [ref] $hitRules)) {
                foreach ($r in $hitRules) { Add-NodeFinding $file $r $n }
            }

            $elements = $n.CommandElements
            $count = $elements.Count

            # Module names given positionally to Import-Module et al.
            if ($ModuleImportCommands.Contains($name)) {
                for ($i = 1; $i -lt $count; $i++) {
                    $el = $elements[$i]
                    if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        foreach ($r in $RulesModule) {
                            if ($r.MatchSet.Contains($el.Value)) { Add-NodeFinding $file $r $n }
                        }
                    }
                }
            }

            # New-Object names its type as a string argument, so no
            # TypeExpressionAst is produced and the Type branch below cannot see
            # it. This is the dominant construction idiom in 5.1-era code, so
            # without this branch every Type rule under-reports.
            # 'New-Object System.Windows.Forms.Form' is missed by
            # PSScriptAnalyzer too: on Windows that type really is available, and
            # only the platform constraint makes it a finding.
            if ($RulesType.Count -gt 0 -and $NewObjectCommands.Contains($name)) {
                $tv = Get-NewObjectTypeName $elements $count
                if (-not [string]::IsNullOrEmpty($tv)) {
                    # Exact rules match against TypeName.Name in the Type branch --
                    # the short name -- so test that here too, or the same rule would
                    # fire on '[EventLog]' and stay silent on
                    # 'New-Object System.Diagnostics.EventLog'.
                    $short = $tv
                    $dot = $tv.LastIndexOf('.')
                    if ($dot -ge 0 -and $dot -lt $tv.Length - 1) { $short = $tv.Substring($dot + 1) }
                    foreach ($r in $RulesType) {
                        $hit = $false
                        if ($r.MatchMode -eq 'Contains') {
                            foreach ($m in $r.MatchArray) {
                                if ($tv.IndexOf($m, $IC) -ge 0) { $hit = $true; break }
                            }
                        }
                        else { $hit = $r.MatchSet.Contains($short) }
                        if ($hit) { Add-NodeFinding $file $r $n }
                    }
                }
            }

            # CommandArgument: a literal that only means something as an argument
            # of a specific command. Anchoring to the command is the whole point --
            # the same text in prose, a here-string or test data is not a finding.
            $argRules = $null
            if ($CommandArgRuleIndex.TryGetValue($name, [ref] $argRules)) {
                for ($i = 1; $i -lt $count; $i++) {
                    $el = $elements[$i]
                    if ($el -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -and
                        $el -isnot [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                        continue
                    }
                    $av = [string] $el.Value
                    if ([string]::IsNullOrEmpty($av)) { continue }
                    foreach ($r in $argRules) {
                        if ($r.MatchMode -eq 'Contains') {
                            foreach ($m in $r.MatchArray) {
                                if ($av.IndexOf($m, $IC) -ge 0) { Add-NodeFinding $file $r $n; break }
                            }
                        }
                        elseif ($r.MatchSet.Contains($av)) { Add-NodeFinding $file $r $n }
                    }
                }
            }

            # Parameter-shaped rules. PowerShell resolves unambiguous parameter
            # prefixes, so '-Enc' really is '-Encoding'; only the parser knows
            # that, and only the parser can tell a real parameter from the
            # literal text '-Encoding' sitting inside a string argument.
            if (-not ($ParamRulesAreScoped -and -not $ParamScopedCommands.Contains($name))) {
                $seenParams.Clear()
                $splatted = $false

                for ($i = 1; $i -lt $count; $i++) {
                    $el = $elements[$i]

                    if ($el -is [System.Management.Automation.Language.VariableExpressionAst]) {
                        if ($el.Splatted) { $splatted = $true }
                        continue
                    }
                    if (-not ($el -is [System.Management.Automation.Language.CommandParameterAst])) { continue }

                    $pn = $el.ParameterName
                    if ([string]::IsNullOrEmpty($pn)) { continue }

                    # Resolve the prefix to the full parameter name each rule cares
                    # about, then record the resolved name.
                    foreach ($r in $RulesParameter) {
                        if ($r.CommandSet -and -not $r.CommandSet.Contains($name)) { continue }
                        foreach ($full in $r.MatchArray) {
                            if ($full.StartsWith($pn, $IC)) {
                                $null = $seenParams.Add($full)
                                Add-NodeFinding $file $r $n
                            }
                        }
                    }

                    foreach ($r in $RulesParamValue) {
                        if ($r.CommandSet -and -not $r.CommandSet.Contains($name)) { continue }
                        $target = [string] $r.OnParameter
                        if (-not $target.StartsWith($pn, $IC)) { continue }
                        $null = $seenParams.Add($target)

                        $val = $el.Argument
                        if ($null -eq $val -and ($i + 1) -lt $count) { $val = $elements[$i + 1] }
                        if ($null -ne $val -and
                            $val -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                            $r.MatchSet.Contains($val.Value)) {
                            Add-NodeFinding $file $r $n
                        }
                    }

                    foreach ($r in $RulesMissingParam) {
                        if ($r.CommandSet -and -not $r.CommandSet.Contains($name)) { continue }
                        foreach ($full in $r.MatchArray) {
                            if ($full.StartsWith($pn, $IC)) { $null = $seenParams.Add($full) }
                        }
                        foreach ($full in $r.RequiresArray) {
                            if ($full.StartsWith($pn, $IC)) { $null = $seenParams.Add($full) }
                        }
                    }
                }

                # Splatting hides the parameter set entirely, so a splatted call is
                # never reported absent: a false positive here becomes a
                # must-remediate item on someone's plan.
                if (-not $splatted) {
                    foreach ($r in $RulesMissingParam) {
                        if ($r.CommandSet -and -not $r.CommandSet.Contains($name)) { continue }
                        if ($r.RequiresArray.Count -gt 0) {
                            $gate = $false
                            foreach ($req in $r.RequiresArray) {
                                if ($seenParams.Contains($req)) { $gate = $true; break }
                            }
                            if (-not $gate) { continue }
                        }
                        foreach ($full in $r.MatchArray) {
                            if (-not $seenParams.Contains($full)) { Add-NodeFinding $file $r $n }
                        }
                    }
                }
            }
        }
        elseif ($n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            $v = $n.Value
            if ([string]::IsNullOrEmpty($v)) { continue }
            # Inlined rather than calling Test-AnyContains: this is the single
            # hottest branch in the scan (string constants are the most common
            # node type after variables) and a PowerShell function call per rule
            # per node dominates the runtime.
            foreach ($r in $RulesString) {
                foreach ($m in $r.MatchArray) {
                    if ($v.IndexOf($m, $IC) -ge 0) { Add-NodeFinding $file $r $n; break }
                }
            }
        }
        elseif ($n -is [System.Management.Automation.Language.MemberExpressionAst]) {
            # Covers InvokeMemberExpressionAst too -- it derives from
            # MemberExpressionAst, so both '$r.ParsedHtml' and '$r.Forms.Item(0)'
            # land here. Only a literal member name is checkable; a computed
            # member ('$r.$name') is skipped rather than guessed at.
            $mn = $n.Member
            if ($mn -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $mv = [string] $mn.Value
                if (-not [string]::IsNullOrEmpty($mv)) {
                    foreach ($r in $RulesMemberAccess) {
                        if ($r.MatchSet.Contains($mv)) { Add-NodeFinding $file $r $n }
                    }

                    # StaticMember pairs the member with its owning type, so
                    # '[System.Text.Encoding]::Default' is a finding while
                    # '::UTF8' and every unrelated '::Default' are not. Matching a
                    # bare member name here would be context-blind.
                    if ($RulesStaticMember.Count -gt 0 -and $n.Static -and
                        $n.Expression -is [System.Management.Automation.Language.TypeExpressionAst]) {
                        $tfn = [string] $n.Expression.TypeName.FullName
                        if (-not [string]::IsNullOrEmpty($tfn)) {
                            $pair = "$tfn::$mv"
                            foreach ($r in $RulesStaticMember) {
                                if (Test-StaticMemberMatch $pair $r.MatchArray) { Add-NodeFinding $file $r $n }
                            }
                        }
                    }
                }
            }
        }
        elseif ($n -is [System.Management.Automation.Language.TypeExpressionAst] -or
            $n -is [System.Management.Automation.Language.TypeConstraintAst]) {
            $tn = $n.TypeName
            if ($null -eq $tn) { continue }
            foreach ($r in $RulesType) {
                $hit = $false
                if ($r.MatchMode -eq 'Contains') {
                    $full = [string] $tn.FullName
                    foreach ($m in $r.MatchArray) {
                        if ($full.IndexOf($m, $IC) -ge 0) { $hit = $true; break }
                    }
                }
                elseif ($null -ne $tn.Name) {
                    $hit = $r.MatchSet.Contains($tn.Name)
                }
                if ($hit) { Add-NodeFinding $file $r $n }
            }
        }
        elseif ($n -is [System.Management.Automation.Language.UsingStatementAst]) {
            if ($n.UsingStatementKind -eq 'Module' -and $null -ne $n.Name) {
                foreach ($r in $RulesModule) {
                    if ($r.MatchSet.Contains($n.Name.Value)) { Add-NodeFinding $file $r $n }
                }
            }
        }
        elseif ($n -is [System.Management.Automation.Language.BinaryExpressionAst]) {
            if ($RulesNullCompare.Count -eq 0) { continue }
            $op = [string] $n.Operator
            if ($op -eq 'Ieq' -or $op -eq 'Ceq' -or $op -eq 'Ine' -or $op -eq 'Cne') {
                $right = $n.Right
                if ($right -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $right.VariablePath.UserPath -eq 'null') {
                    foreach ($r in $RulesNullCompare) { Add-NodeFinding $file $r $n }
                }
            }
        }
        elseif ($n -is [System.Management.Automation.Language.FileRedirectionAst]) {
            # MergingRedirectionAst (2>&1) is a different type and never reaches
            # here, so stream merges are excluded structurally rather than by test.
            # '> $null' is a discard, not a file write, and carries no encoding.
            if ($RulesRedirection.Count -eq 0) { continue }
            $loc = $n.Location
            if ($loc -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $loc.VariablePath.UserPath -eq 'null') {
                continue
            }
            $op = if ($n.Append) { '>>' } else { '>' }
            foreach ($r in $RulesRedirection) {
                if ($r.MatchSet.Contains($op)) { Add-NodeFinding $file $r $n }
            }
        }
        elseif ($n -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            # Only reachable under Windows PowerShell 5.1: PowerShell 7 refuses to
            # parse a workflow at all, and those files are caught by the token pass.
            if ($n.IsWorkflow) {
                foreach ($r in $RulesKeyword) {
                    if ($r.MatchSet.Contains('workflow')) { Add-NodeFinding $file $r $n }
                }
            }
        }
    }
}

# --- supersession -------------------------------------------------------------
# Intra-catalog only, and unrelated to the SupersededBy key: this collapses two
# *active* rules that match the same line for the same remediation, so the
# blocker is counted once and lands in one bucket.
#
# The shipped catalog has one such relationship, 'exchange-snapin' over
# 'snapin', and 'snapin' is knowledge-only, so nothing is suppressed there in
# practice. The machinery exists for contributed catalogs, which routinely add a
# specific rule alongside an active generic one.

$supersededBy = @{}
foreach ($r in $rules) {
    if ($r.ContainsKey('Supersedes')) {
        foreach ($victim in @($r.Supersedes)) {
            # A victim can have many superseders, so this accumulates rather than
            # assigns. With a scalar, only the last superseder would suppress the
            # generic finding and every other one would be double-counted.
            if (-not $supersededBy.ContainsKey($victim)) {
                $supersededBy[$victim] = New-Object System.Collections.Generic.List[string]
            }
            $supersededBy[$victim].Add($r.Id)
        }
    }
}

if ($supersededBy.Count -gt 0) {
    $kept = New-Object System.Collections.Generic.List[object]
    $byLine = $findings | Group-Object -Property File, Line
    foreach ($grp in $byLine) {
        $idsHere = New-Set @($grp.Group | ForEach-Object { $_.RuleId })
        foreach ($f in $grp.Group) {
            $winners = $supersededBy[$f.RuleId]
            $suppressed = $false
            if ($null -ne $winners) {
                foreach ($w in $winners) {
                    if ($idsHere.Contains($w)) { $suppressed = $true; break }
                }
            }
            if ($suppressed) { continue }
            $kept.Add($f)
        }
    }
    $findings = $kept
}

# --- output -------------------------------------------------------------------

$sorted   = @($findings | Sort-Object File, Line, RuleId)
$degraded = @($fileStatus | Where-Object { $_.Fidelity -eq 'Tokens' })

# Every finding here comes from an active rule: superseded rules are filtered out
# before matching and never emit, so $primary equals $sorted. It is kept as a
# separate name because the console and the envelope both report "primary
# findings", meaning the blockers this scan found that PSScriptAnalyzer does not.
$primary = $sorted

# Coverage is "did this scan actually look", not "did it enumerate". A degraded
# file was enumerated and read, but the rules that need a parsed AST never ran
# against it, so a zero from those rules is "not checked" rather than "not
# present" -- the same thing an unreadable directory means, arrived at a
# different way. Counting it here is what makes the exit code agree with the
# console: without it, a tree whose only blocker sits in a file containing
# `workflow` prints "coverage : complete", "findings : 0 primary" and exits 0.
# Invoke-PSSACompatibilityScan.ps1 counts its own unanalyzable files the same
# way; the two gates must not disagree.
$coverageGaps = $skippedDirs.Count + $missingInputs.Count + $degraded.Count

# Resolve which artifacts to write. 'Auto' follows the extension so a caller can
# just ask for a .json path; explicit values win.
$ext = [System.IO.Path]::GetExtension($OutputPath)
$fmt = $OutputFormat
if ($fmt -eq 'Auto') { $fmt = if ($ext -eq '.json') { 'Json' } else { 'Csv' } }

$csvPath = $null
$jsonPath = $null
switch ($fmt) {
    'Csv'  { $csvPath = $OutputPath }
    'Json' { $jsonPath = $OutputPath }
    'Both' {
        $base = [System.IO.Path]::ChangeExtension($OutputPath, $null).TrimEnd('.')
        $csvPath = "$base.csv"
        $jsonPath = "$base.json"
    }
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
    # The envelope carries more than the findings. Coverage gaps and
    # degraded-parse files decide whether the finding count can be trusted at
    # all, and in CSV form they survive only as console text. A consumer that
    # reads the findings array and ignores 'coverage' can mistake an unreadable
    # subtree for a clean one.
    $coverageStatus = 'complete'
    if ($coverageGaps -gt 0) { $coverageStatus = 'incomplete' }

    # Every value below is computed before the literal. A pipeline evaluated
    # inside an [ordered]@{} literal binds through PSToObjectArrayBinder and
    # throws "Argument types do not match" at runtime, so the envelope is
    # assembled from plain variables only.
    $extraCatalogs = @($catalogFiles | Select-Object -Skip 1)
    $filesWithFindings = @($sorted | Group-Object File).Count
    $degradedFiles = @($degraded | ForEach-Object {
        [ordered]@{ file = $_.File; parseError = "$($_.ParseError)" }
    })
    $bySeverity = [ordered]@{}
    foreach ($g in @($primary | Group-Object Severity | Sort-Object Name)) {
        $bySeverity[$g.Name] = $g.Count
    }
    $byRule = [ordered]@{}
    foreach ($g in @($sorted | Group-Object RuleId | Sort-Object Count -Descending)) {
        $byRule[$g.Name] = $g.Count
    }

    # .ToArray() rather than @(): @() over a non-empty List[object] can throw
    # "Argument types do not match" from the enumerable binder. Only $skippedDirs
    # is List[object] and needs this, but all four go through the same conversion
    # so they do not drift apart.
    $unreadableDirs = $skippedDirs.ToArray()
    $missingPaths   = $missingInputs.ToArray()
    $notFollowed    = $skippedLinks.ToArray()
    $pruned         = $prunedDirs.ToArray()

    $envelope = [ordered]@{
        schema   = 'powershell-compatibility-scan/1'
        host     = [ordered]@{
            edition  = "$($PSVersionTable.PSEdition)"
            version  = "$($PSVersionTable.PSVersion)"
            platform = "$($PSVersionTable.Platform)"
        }
        scannedAt = (Get-Date).ToUniversalTime().ToString('o')
        catalogs  = [ordered]@{
            base               = $RulesPath
            additional         = $extraCatalogs
            ruleCount          = $rules.Count
            activeRuleCount    = $activeRules.Count
            knowledgeOnlyCount = $knowledgeOnly.Count
            knowledgeOnlyIds   = @($knowledgeOnly | ForEach-Object { $_.Id })
            addedCount         = $addedCount
            overriddenIds      = @($overriddenIds)
        }
        scope = [ordered]@{
            requested        = @($Path)
            include          = @($Include)
            excludeDirectory = @($ExcludeDirectory)
            filesScanned     = $files.Count
        }
        # 'complete' is the only value that licenses reading a zero as clean.
        coverage = [ordered]@{
            status           = $coverageStatus
            unreadableDirs   = $unreadableDirs
            missingInputs    = $missingPaths
            notFollowedLinks = $notFollowed
            excludedDirs     = $pruned
        }
        fidelity = [ordered]@{
            degradedCount = $degraded.Count
            # Structural rules were not applied to these files, so their absence
            # of structural findings is not evidence.
            degradedFiles = $degradedFiles
        }
        counts = [ordered]@{
            total   = $sorted.Count
            primary = $primary.Count
            filesWithFindings      = $filesWithFindings
            bySeverity             = $bySeverity
            byRule                 = $byRule
        }
        findings = @($sorted)
    }
    # -Depth matters: the default of 2 truncates the findings array into type
    # names and silently produces a file that looks structured but holds nothing.
    $envelope | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $jsonPath -Encoding UTF8
}

# The summary is what the agent reads. The findings file is a lookup table -- on
# a large estate it is tens of thousands of rows and must be queried per file or
# per rule id, never read whole.
Write-Host ''
Write-Host "PowerShell 5.1 -> 7 compatibility scan"
Write-Host "  host          : $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
Write-Host "  rules         : $($activeRules.Count) active from $RulesPath"
if ($knowledgeOnly.Count -gt 0) {
    Write-Host "                  $($knowledgeOnly.Count) knowledge-only (PSScriptAnalyzer detects these; run Invoke-PSSACompatibilityScan.ps1)"
}
if ($addedCount -gt 0 -or $overriddenIds.Count -gt 0) {
    # Surface contributions explicitly. A silently-merged catalog is a scan whose
    # results cannot be reproduced from the shipped rules alone.
    Write-Host "  contributed   : $addedCount added, $($overriddenIds.Count) overridden"
    if ($overriddenIds.Count -gt 0) {
        Write-Host "    overrides   : $($overriddenIds -join ', ')"
    }
    foreach ($c in ($catalogFiles | Select-Object -Skip 1)) {
        Write-Host "    from        : $c"
    }
}
Write-Host "  files scanned : $($files.Count)"
Write-Host "  files w/ finds: $(@($sorted | Group-Object File).Count)"

if ($coverageGaps -gt 0) {
    $parts = @()
    if ($skippedDirs.Count)   { $parts += "$($skippedDirs.Count) unreadable dir(s)" }
    if ($missingInputs.Count) { $parts += "$($missingInputs.Count) missing input path(s)" }
    if ($degraded.Count)      { $parts += "$($degraded.Count) file(s) that did not parse" }
    Write-Host "  coverage      : INCOMPLETE -- $($parts -join ', ')"
}
else {
    Write-Host "  coverage      : complete"
}

Write-Host "  findings      : $($primary.Count) primary"
if ($csvPath)  { Write-Host "  output (csv)  : $csvPath" }
if ($jsonPath) { Write-Host "  output (json) : $jsonPath" }

if ($degraded.Count -gt 0) {
    Write-Host ''
    Write-Host "  $($degraded.Count) file(s) did not parse under this host -- scanned at Tokens fidelity."
    Write-Host '  These count as coverage gaps: the rules below never ran against them.'
    if ($tokenBlindRuleIds.Count -gt 0) {
        Write-Host "  These rules need a parsed AST and were NOT applied to those files:"
        Write-Host "    $($tokenBlindRuleIds -join ', ')"
        Write-Host "  A clean result for those rules on those files means 'not checked', not 'not present'."
    }
    foreach ($d in ($degraded | Select-Object -First 20)) {
        Write-Host "    $($d.File)"
        Write-Host "      $($d.ParseError)"
    }
    if ($degraded.Count -gt 20) { Write-Host "    ... and $($degraded.Count - 20) more" }
}

# The degraded files are reported by the block above, so this one covers only the
# paths that were never read at all. It stays silent when the sole gap is a parse
# failure rather than printing a heading with nothing under it.
if ($missingInputs.Count -gt 0 -or $skippedDirs.Count -gt 0) {
    Write-Host ''
    Write-Host '  COVERAGE GAPS -- this scan did not see the whole scope.'
    Write-Host '  Zero findings under these paths means "not looked at", not "clean".'
    Write-Host '  Record them as skipped paths and treat the scan as partial.'
    foreach ($m in ($missingInputs | Select-Object -First 20)) {
        Write-Host "    missing input : $m"
    }
    foreach ($s in ($skippedDirs | Select-Object -First 20)) {
        Write-Host "    unreadable    : $($s.Path)"
        Write-Host "                    $($s.Reason)"
    }
    if ($skippedDirs.Count -gt 20) { Write-Host "    ... and $($skippedDirs.Count - 20) more unreadable dir(s)" }
}

# Reparse points are skipped by design, to avoid cycles and escaping the tree.
# Reported at a lower volume than a true gap, because a junction usually points
# back inside a tree that was already walked -- but a symlinked subtree of real
# scripts would be invisible, so the count is never hidden entirely.
if ($skippedLinks.Count -gt 0) {
    Write-Host ''
    Write-Host "  $($skippedLinks.Count) junction/symlink dir(s) not followed (by design; use -Verbose to list)."
    foreach ($l in $skippedLinks) { Write-Verbose "Not followed (reparse point): $l" }
}

# Excluded directories are pruned by request, so this is not a coverage gap. It is
# still reported: the defaults name .NET build-output folders, and an estate that
# keeps real scripts in 'bin' or 'packages' would otherwise read as clean.
if ($prunedDirs.Count -gt 0) {
    Write-Host ''
    Write-Host "  $($prunedDirs.Count) dir(s) pruned by -ExcludeDirectory ($($ExcludeDirectory -join ', ')); use -Verbose to list."
    Write-Host '  If this estate keeps scripts in any of those, re-run with a narrower -ExcludeDirectory.'
    foreach ($d in $prunedDirs) { Write-Verbose "Excluded by -ExcludeDirectory: $d" }
}

Write-Host ''
Write-Host 'By severity (primary findings only):'
$primary | Group-Object Severity | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-10} {1}" -f $_.Name, $_.Count)
}

# A scan with no findings is not a clean tree. This catalog does not look for the
# sites PSScriptAnalyzer already reports -- Get-WmiObject, snap-ins, event-log
# and DSC cmdlets are the high-volume ones -- so an estate whose blockers are all
# of that kind reaches here with an empty severity block. Say so, or the summary
# reads as "no blockers" for a scan that never looked for them.
if ($primary.Count -eq 0 -and $knowledgeOnly.Count -gt 0) {
    Write-Host ("  none -- but this scan does not cover the {0} rule(s) PSScriptAnalyzer owns." -f $knowledgeOnly.Count)
    Write-Host "  Run Invoke-PSSACompatibilityScan.ps1 before reading this tree as clean."
}

Write-Host ''
Write-Host 'By rule:'
$sorted | Group-Object RuleId | Sort-Object Count -Descending | ForEach-Object {
    Write-Host ("  {0,-30} {1}" -f $_.Name, $_.Count)
}

# Non-zero exit when anything the migration must act on was found, so a caller
# can gate on it. Advisory-only findings do not fail the scan.
#
# A coverage gap also fails. Otherwise a mistyped -Path, an unreadable subtree,
# or a file that would not parse exits 0 with zero findings while the envelope
# says coverage is incomplete -- a clean bill of health for a scan that never
# looked. The PSSA wrapper gates the same way; the two must not disagree.
#
# Sites covered by a superseded rule do not gate here, because this scan does not
# look for them. PSScriptAnalyzer reports those, and Invoke-PSSACompatibilityScan.ps1
# is the gate for them. Run both; neither alone is a complete re-scan.
$actionable = @($sorted | Where-Object { $_.Severity -ne 'Advisory' })
if ($actionable.Count -gt 0 -or $coverageGaps -gt 0) { exit 1 }
exit 0
