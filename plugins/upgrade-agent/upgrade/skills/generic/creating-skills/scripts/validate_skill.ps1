<#
.SYNOPSIS
    Validates a skill directory against Anthropic's best practices.

.DESCRIPTION
    Checks structure, frontmatter, line counts, file paths, reference depth,
    and common anti-patterns. Subjective quality checks (conciseness, freedom
    calibration) require human review.

.PARAMETER SkillPath
    Path to the skill directory containing SKILL.md

.EXAMPLE
    .\validate_skill.ps1 -SkillPath .\my-skill
    .\validate_skill.ps1 .\my-skill
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$SkillPath
)

$ErrorActionPreference = "Stop"

# --- Result tracking ---
$passes = [System.Collections.ArrayList]::new()
$warnings = [System.Collections.ArrayList]::new()
$fails = [System.Collections.ArrayList]::new()

function Add-Pass($Category, $Message) { $null = $passes.Add(@{ Category = $Category; Message = $Message }) }
function Add-Warn($Category, $Message) { $null = $warnings.Add(@{ Category = $Category; Message = $Message }) }
function Add-Fail($Category, $Message) { $null = $fails.Add(@{ Category = $Category; Message = $Message }) }

function Write-Report {
    Write-Host ""
    Write-Host ("=" * 60)
    Write-Host "SKILL VALIDATION REPORT"
    Write-Host ("=" * 60)

    if ($passes.Count -gt 0) {
        Write-Host ""
        Write-Host "PASSED:" -ForegroundColor Green
        foreach ($item in $passes) {
            Write-Host "   [$($item.Category)] $($item.Message)" -ForegroundColor Green
        }
    }

    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "WARNINGS:" -ForegroundColor Yellow
        foreach ($item in $warnings) {
            Write-Host "   [$($item.Category)] $($item.Message)" -ForegroundColor Yellow
        }
    }

    if ($fails.Count -gt 0) {
        Write-Host ""
        Write-Host "FAILURES (must fix):" -ForegroundColor Red
        foreach ($item in $fails) {
            Write-Host "   [$($item.Category)] $($item.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host ("-" * 60)
    Write-Host "Summary: $($passes.Count) passed, $($warnings.Count) warnings, $($fails.Count) failures"

    if ($fails.Count -eq 0 -and $warnings.Count -le 2) {
        Write-Host "Status: READY FOR REVIEW" -ForegroundColor Green
    }
    elseif ($fails.Count -eq 0) {
        Write-Host "Status: FIX WARNINGS before review" -ForegroundColor Yellow
    }
    else {
        Write-Host "Status: BLOCKING ISSUES - must fix" -ForegroundColor Red
    }
}

# --- Parse YAML frontmatter (lightweight, no external deps) ---
function Get-Frontmatter([string]$Content) {
    if (-not $Content.StartsWith("---")) { return $null }

    $endIndex = $Content.IndexOf("`n---", 3)
    if ($endIndex -lt 0) {
        # Try Windows line endings
        $endIndex = $Content.IndexOf("`r`n---", 3)
    }
    if ($endIndex -lt 0) { return $null }

    $yamlBlock = $Content.Substring(3, $endIndex - 3).Trim()
    $result = @{}

    foreach ($line in $yamlBlock -split "`n") {
        $line = $line.Trim()
        if ($line -match "^(\w[\w-]*):\s*(.+)$") {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
            # Strip surrounding quotes if present
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $result[$key] = $value
        }
        elseif ($line -match "^(\w[\w-]*):\s*$") {
            # Multi-line value: collect subsequent indented lines
            $key = $Matches[1]
            $multiValue = ""
            # We'll handle this simply by marking it empty for now
            # Full multi-line YAML parsing would need a real parser
            $result[$key] = ""
        }
    }

    # Handle multi-line description: if description is empty, try to grab
    # everything between 'description:' and the next top-level key or end
    if ($result.ContainsKey("description") -and [string]::IsNullOrWhiteSpace($result["description"])) {
        if ($yamlBlock -match "(?s)description:\s*[|>]?\s*\n((?:\s+.+\n?)+)") {
            $result["description"] = ($Matches[1] -replace "(?m)^\s{2,}", "" ).Trim()
        }
    }

    return $result
}

# --- Begin validation ---

$skillDir = Resolve-Path $SkillPath -ErrorAction SilentlyContinue
if (-not $skillDir) {
    Write-Host "Error: '$SkillPath' does not exist" -ForegroundColor Red
    exit 1
}

$skillMd = Join-Path $skillDir "SKILL.md"
if (-not (Test-Path $skillMd)) {
    Add-Fail "Structure" "SKILL.md not found at skill root"
    Write-Report
    exit 1
}

Add-Pass "Structure" "SKILL.md exists"

$content = Get-Content $skillMd -Raw -Encoding UTF8
$frontmatter = Get-Frontmatter $content

# --- Frontmatter checks ---
if ($null -eq $frontmatter) {
    Add-Fail "Frontmatter" "No valid YAML frontmatter found (must start with ---)"
    Write-Report
    exit 1
}

Add-Pass "Frontmatter" "YAML frontmatter present"

# Name checks
$name = $frontmatter["name"]
if ([string]::IsNullOrWhiteSpace($name)) {
    Add-Fail "Frontmatter" "``name`` field is missing or empty"
}
elseif ($name.Length -gt 64) {
    Add-Fail "Frontmatter" "``name`` is $($name.Length) chars (max 64)"
}
elseif ($name -notmatch "^[a-z0-9-]+$") {
    Add-Fail "Frontmatter" "``name`` contains invalid characters: '$name' (only lowercase, numbers, hyphens)"
}
elseif ($name -match "anthropic|claude") {
    Add-Fail "Frontmatter" "``name`` contains reserved word: '$name'"
}
elseif ($name -match "<") {
    Add-Fail "Frontmatter" "``name`` contains XML tags"
}
else {
    Add-Pass "Frontmatter" "``name`` is valid: '$name'"

    # Naming quality check (warning, not blocking)
    $gerundPrefixes = @("migrating-", "converting-", "managing-", "integrating-", "modifying-", "processing-", "analyzing-", "creating-", "generating-", "configuring-", "deploying-", "testing-", "building-", "validating-", "upgrading-")
    $startsWithGerund = $false
    foreach ($prefix in $gerundPrefixes) {
        if ($name.StartsWith($prefix)) { $startsWithGerund = $true; break }
    }
    if (-not $startsWithGerund) {
        Add-Warn "Naming" "``name`` '$name' does not start with a gerund verb (e.g., migrating-, converting-, managing-)"
    }
}

# Description checks
$desc = $frontmatter["description"]
if ([string]::IsNullOrWhiteSpace($desc)) {
    Add-Fail "Frontmatter" "``description`` field is missing or empty"
}
elseif ($desc.Length -gt 1024) {
    Add-Fail "Frontmatter" "``description`` is $($desc.Length) chars (max 1024)"
}
elseif ($desc -match "<[^>]+>") {
    Add-Fail "Frontmatter" "``description`` appears to contain XML tags"
}
else {
    Add-Pass "Frontmatter" "``description`` present ($($desc.Length) chars)"

    # Third person check
    if ($desc -match "(?i)^(I |I can|You |You can)") {
        Add-Warn "Description" "Should be third person ('Processes files' not 'I can help' or 'You can use')"
    }
    else {
        Add-Pass "Description" "Written in third person"
    }

    # Trigger context check
    $triggerWords = @("use when", "use this", "trigger", "when the user", "also use", "mention")
    $hasTrigger = $false
    foreach ($tw in $triggerWords) {
        if ($desc -match "(?i)$([regex]::Escape($tw))") { $hasTrigger = $true; break }
    }
    if (-not $hasTrigger) {
        Add-Warn "Description" "No trigger context found - add 'Use when...' phrases for better discovery"
    }
    else {
        Add-Pass "Description" "Includes trigger context"
    }

    # Vague description check
    $vaguePatterns = @("helps with", "does stuff", "processes data", "works with files", "general purpose")
    foreach ($vp in $vaguePatterns) {
        if ($desc -match "(?i)$([regex]::Escape($vp))") {
            Add-Warn "Description" "Description seems vague - be more specific about capabilities and triggers"
            break
        }
    }
}

# --- Line count ---
# Get body after frontmatter
$bodyStart = $content.IndexOf("---", 3)
if ($bodyStart -ge 0) {
    $body = $content.Substring($bodyStart + 3).Trim()
}
else {
    $body = $content
}
$bodyLines = ($body -split "`n").Count

if ($bodyLines -gt 500) {
    Add-Warn "Structure" "SKILL.md body is $bodyLines lines (recommended max 500)"
}
else {
    Add-Pass "Structure" "SKILL.md body is $bodyLines lines"
}

# --- File path checks (backslashes in source files) ---
$sourceExtensions = @(".md", ".py", ".sh", ".js", ".ts", ".ps1", ".psm1")
$backslashFiles = @()

Get-ChildItem $skillDir -Recurse -File | Where-Object {
    $sourceExtensions -contains $_.Extension -and $_.Name -ne "SKILL.md"
} | ForEach-Object {
    $fileContent = Get-Content $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($fileContent -and $fileContent -match '["\u0027][^"\u0027]*\\[^"\u0027]*["\u0027]') {
        # Exclude common non-path backslash uses: regex patterns in scripts
        $relativePath = $_.FullName.Substring($skillDir.Path.Length + 1)
        if ($_.Extension -notin @(".py", ".ps1", ".psm1", ".sh")) {
            $backslashFiles += $relativePath
        }
    }
}

if ($backslashFiles.Count -gt 0) {
    Add-Warn "Paths" "Possible Windows-style backslash paths in: $($backslashFiles -join ', ')"
}
else {
    Add-Pass "Paths" "No Windows-style paths detected in content files"
}

# --- Reference depth check ---
$refPattern = [regex]"\[.*?\]\(((?:references|scripts|templates)/[^)]+)\)"
$skillRefs = $refPattern.Matches($body) | ForEach-Object { $_.Groups[1].Value }

$nestedRefs = @()
foreach ($ref in $skillRefs) {
    $refFile = Join-Path $skillDir $ref
    if ((Test-Path $refFile) -and $refFile.EndsWith(".md")) {
        $refContent = Get-Content $refFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($refContent) {
            $subRefs = $refPattern.Matches($refContent) | ForEach-Object { $_.Groups[1].Value }
            if ($subRefs.Count -gt 0) {
                $nestedRefs += "$ref -> [$($subRefs -join ', ')]"
            }
        }
    }
}

if ($nestedRefs.Count -gt 0) {
    Add-Warn "Disclosure" "Nested references detected (max 1 level deep): $($nestedRefs -join '; ')"
}
else {
    Add-Pass "Disclosure" "References are at most one level deep"
}

# --- Reference file TOC check ---
Get-ChildItem $skillDir -Recurse -File -Filter "*.md" | Where-Object { $_.Name -ne "SKILL.md" } | ForEach-Object {
    $fileContent = Get-Content $_.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($fileContent -and $fileContent.Count -gt 100) {
        $top20 = ($fileContent | Select-Object -First 20) -join "`n"
        if ($top20 -notmatch "(?i)(contents|table of contents)") {
            $relativePath = $_.FullName.Substring($skillDir.Path.Length + 1)
            Add-Warn "Disclosure" "$relativePath is $($fileContent.Count) lines but has no table of contents"
        }
    }
}

# --- Time-sensitive content check ---
$timePatterns = @(
    "(?i)before\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{4}",
    "(?i)after\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{4}",
    "(?i)as of\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{4}",
    "(?i)starting\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{4}"
)

$foundTimeSensitive = $false
foreach ($pattern in $timePatterns) {
    if ($body -match $pattern) {
        Add-Warn "Content" "Time-sensitive language detected - consider using an 'old patterns' section"
        $foundTimeSensitive = $true
        break
    }
}

# --- Too many options check ---
if ($body -match "(?i)(?:you can use|options?:?).*?(?:,\s*or\s+){2,}") {
    Add-Warn "Content" "Multiple equivalent options offered without a clear default - provide a recommended approach"
}

# --- Report ---
Write-Report

if ($fails.Count -gt 0) { exit 1 } else { exit 0 }
