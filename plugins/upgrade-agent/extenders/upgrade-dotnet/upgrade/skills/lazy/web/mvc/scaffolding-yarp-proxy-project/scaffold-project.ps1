# Copyright (c) Microsoft Corporation. All rights reserved.
# Scaffold ASP.NET Core project with YARP proxy for side-by-side migration.
# Copies template files from the skill's tmpl/ folder and applies variable substitution.

param(
    [Parameter(Mandatory)]
    [string]$OldProjectPath,

    [Parameter(Mandatory)]
    [string]$SolutionPath,

    [Parameter(Mandatory)]
    [string]$TargetFramework,

    [string]$NewProjectName,

    [ValidateSet('MVC', 'WebAPI')]
    [string]$ProjectType = 'MVC',

    [Parameter(Mandatory)]
    [string]$OldAppUrl,

    [string]$SystemWebAdaptersVersion = '2.3.0',

    [string]$YarpVersion = '2.3.0',

    [string[]]$TrustedProxies,

    [string[]]$TrustedNetworks,

    [string[]]$AllowedForwardedHosts,

    [string]$TemplatesRoot
)

$ErrorActionPreference = 'Stop'

# Normalize once, here: the TFM is both classified below and substituted into the generated
# .csproj, so trimming only at the classification sites would still emit
# '<TargetFramework> net10.0 </TargetFramework>' and fail the build.
$TargetFramework = $TargetFramework.Trim()

# The hardened scaffold uses the non-obsolete forwarded-headers API
# (ForwardedHeadersOptions.KnownIPNetworks + System.Net.IPNetwork), which only exists in
# ASP.NET Core 10.0+. Below net10.0 the hardening is stripped from the generated files and a
# warning is emitted, so the caller still gets a working (unhardened) proxy — matching the VS
# transformer, which degrades rather than aborting. Refusing outright would leave a caller on
# an older target with no scaffold at all.
#
# A TFM *list* is rejected rather than classified. The template emits a single
# <TargetFramework> element, so 'net10.0;net8.0' would produce an invalid project either way;
# worse, classifying only the first entry would harden a project that also targets net8.0 and
# fail to compile (CS1061). The VS transformer evaluates every resolved target and disables
# hardening if any is below net10.0 — here there is only ever one, so say so explicitly.
if ($TargetFramework -match '[;,]') {
    Write-Error "TargetFramework '$TargetFramework' lists multiple targets. This scaffold creates a single-target proxy project, so pass exactly one moniker, e.g. -TargetFramework net10.0."
    return
}
$tfmMatch = [regex]::Match($TargetFramework, '^net(?<major>\d+)\.(?<minor>\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
if (-not $tfmMatch.Success) {
    # A .NET Framework moniker here is a category error, not a typo: this scaffold creates the
    # ASP.NET Core front-end that proxies *to* the Framework app. Framework is the proxy's
    # backend, never its host, so say that rather than reporting a parse failure.
    if ($TargetFramework -match '^(net[1-4]\d{1,2}|v[1-4]\.\d)$') {
        Write-Error "TargetFramework '$TargetFramework' is a .NET Framework moniker. This scaffold creates the new ASP.NET Core proxy project, which cannot run on .NET Framework -- the Framework app is the proxy's backend (set via -OldAppUrl), not its host. Pass the TFM the new Core project will target, e.g. -TargetFramework net10.0."
        return
    }

    Write-Error "Could not parse TargetFramework '$TargetFramework'. Expected a .NET (Core) moniker like 'net10.0' -- this is the TFM of the new proxy project, not of the app being migrated."
    return
}
# TryParse rather than an [int] cast: the major-version group is unbounded, so a pathological
# moniker ('net99999999999999.0') would abort with a raw .NET cast exception instead of the
# guidance above. Mirrors YarpCodeTransformer.SupportsHardening, which guards the same way.
$tfmMajor = 0
if (-not [int]::TryParse($tfmMatch.Groups['major'].Value, [ref]$tfmMajor)) {
    Write-Error "Could not parse TargetFramework '$TargetFramework': '$($tfmMatch.Groups['major'].Value)' is not a valid .NET major version. Expected a moniker like 'net10.0' -- this is the TFM of the new proxy project, not of the app being migrated."
    return
}
$hardeningSupported = $tfmMajor -ge 10
# -TrustedProxies/-TrustedNetworks/-AllowedForwardedHosts only mean anything when the
# forwarded-headers hardening is
# emitted. Honoring them silently against an unhardened scaffold would write trust settings that
# no code reads — an operator would believe the proxy is restricted when nothing enforces it.
if (-not $hardeningSupported -and
    ($PSBoundParameters.ContainsKey('TrustedProxies') -or $PSBoundParameters.ContainsKey('TrustedNetworks') -or $PSBoundParameters.ContainsKey('AllowedForwardedHosts'))) {
    Write-Error "-TrustedProxies/-TrustedNetworks/-AllowedForwardedHosts cannot be applied to a '$TargetFramework' target: the forwarded-headers hardening they configure requires net10.0 or later. Re-run with -TargetFramework net10.0, or drop these parameters and add forwarded headers by hand (see 'Targeting below net10.0' in SKILL.md)."
    return
}

# Resolve paths
$OldProjectPath = Resolve-Path $OldProjectPath
$SolutionPath = Resolve-Path $SolutionPath
$OldProjectDir = Split-Path $OldProjectPath -Parent
$ParentDir = Split-Path $OldProjectDir -Parent

if (-not $NewProjectName) {
    $NewProjectName = [System.IO.Path]::GetFileNameWithoutExtension($OldProjectPath) + '.Core'
}

# Validate project name uniqueness
$NewProjectDir = Join-Path $ParentDir $NewProjectName
$NewProjectPath = Join-Path $NewProjectDir "$NewProjectName.csproj"

if (Test-Path $NewProjectDir) {
    Write-Error "Directory already exists: $NewProjectDir. Choose a different project name."
    return
}

# Check solution for name conflict
$slnCheck = Get-Content $SolutionPath -Raw
if ($slnCheck -match [regex]::Escape("`"$NewProjectName`"")) {
    Write-Error "A project named '$NewProjectName' already exists in the solution. Choose a different name."
    return
}

# Locate template folder
if (-not $TemplatesRoot) {
    $TemplatesRoot = Join-Path $PSScriptRoot 'tmpl'
}

$templateKey = if ($ProjectType -eq 'WebAPI') { 'webapi' } else { 'mvc' }
$templateDir = Join-Path $TemplatesRoot $templateKey

if (-not (Test-Path $templateDir)) {
    Write-Error "Template directory not found: $templateDir"
    return
}

$HttpsPort = Get-Random -Minimum 7100 -Maximum 7999
$HttpPort = Get-Random -Minimum 5100 -Maximum 5999
$NewPort = Get-Random -Minimum 60000 -Maximum 65000
$NewSslPort = Get-Random -Minimum 44300 -Maximum 44399

Write-Host "Creating side-by-side project: $NewProjectName" -ForegroundColor Cyan
Write-Host "  Old project : $OldProjectPath"
Write-Host "  New project : $NewProjectPath"
Write-Host "  Template    : $templateDir"
Write-Host "  TFM         : $TargetFramework"
Write-Host "  Type        : $ProjectType"
Write-Host "  Proxy target: $OldAppUrl"
Write-Host "  Ports       : HTTPS=$HttpsPort, HTTP=$HttpPort, IIS=$NewPort, IIS-SSL=$NewSslPort"
if ($PSBoundParameters.ContainsKey('TrustedProxies')) { Write-Host "  Trusted proxies : $($TrustedProxies -join ', ')" }
if ($PSBoundParameters.ContainsKey('TrustedNetworks')) { Write-Host "  Trusted networks: $($TrustedNetworks -join ', ')" }
if ($PSBoundParameters.ContainsKey('AllowedForwardedHosts')) { Write-Host "  Allowed forwarded hosts: $($AllowedForwardedHosts -join ', ')" }

# Variable map: template placeholder -> value
$substitutions = @{
    '$TargetFramework$'          = $TargetFramework
    '$SystemWebAdaptersVersion$' = $SystemWebAdaptersVersion
    '$YarpVersion$'              = $YarpVersion
    '$ProjectName$'              = $NewProjectName
    '$HttpsPort$'                = $HttpsPort.ToString()
    '$HttpPort$'                 = $HttpPort.ToString()
    '$NewPort$'                  = $NewPort.ToString()
    '$NewSslPort$'               = $NewSslPort.ToString()
    '$OldAppUrl$'                = $OldAppUrl
}

function Remove-HardeningMarkers {
    param([string]$Content, [bool]$KeepHardening)

    # tmpl/*/Program.cs delimits each hardening block with '//<hardening>' / '//</hardening>'.
    # On net10.0+ only the marker lines are dropped, leaving the hardening intact. Below net10.0
    # the marked blocks are dropped whole, because the forwarded-headers block references
    # ForwardedHeadersOptions.KnownIPNetworks (net10.0+) and would not compile.
    $lines = $Content -split "`r?`n"
    $kept = [System.Collections.Generic.List[string]]::new()
    $depth = 0

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '//<hardening>') {
            # Nesting is never intended and would make the matching '//</hardening>' ambiguous.
            if ($depth -ne 0) {
                throw "Nested '//<hardening>' marker in a template file; the scaffold would emit malformed code."
            }
            $depth++
            continue
        }
        if ($trimmed -eq '//</hardening>') {
            # A stray close means the file's markers are wrong; silently accepting it would
            # keep code that was meant to be stripped below net10.0.
            if ($depth -eq 0) {
                throw "Unmatched '//</hardening>' marker in a template file; the scaffold would emit malformed code."
            }
            $depth--
            continue
        }
        if ($depth -gt 0 -and -not $KeepHardening) {
            continue
        }
        $kept.Add($line)
    }

    if ($depth -ne 0) {
        throw "Unbalanced '//<hardening>' marker in a template file; the scaffold would emit malformed code."
    }

    $result = $kept -join [System.Environment]::NewLine

    # Removing whole blocks can leave runs of blank lines behind; collapse them.
    if (-not $KeepHardening) {
        $nl = [regex]::Escape([System.Environment]::NewLine)
        $result = [regex]::Replace($result, "(?:$nl){3,}", [System.Environment]::NewLine * 2)
        $result = $result -replace "^(?:$nl)+", ''
    }

    return $result
}

function Copy-TemplateWithSubstitutions {
    param([string]$Source, [string]$Destination, [hashtable]$Vars, [bool]$KeepHardening = $true)

    # Pure .NET — no PowerShell path cmdlets at all
    $sourceDir = [System.IO.DirectoryInfo]::new($Source)
    if (-not $sourceDir.Exists) { Write-Error "Source not found: $Source"; return }

    [System.IO.Directory]::CreateDirectory($Destination) | Out-Null

    foreach ($file in $sourceDir.GetFiles('*', [System.IO.SearchOption]::AllDirectories)) {
        # Get path relative to source
        $relativePath = $file.FullName.Substring($sourceDir.FullName.TrimEnd('\').Length + 1)

        # Rename ProjectName.csproj
        if ($relativePath -like '*ProjectName.csproj') {
            $relativePath = $relativePath.Replace('ProjectName.csproj', "$NewProjectName.csproj")
        }

        # Flatten appsettings\<env>.json → appsettings.<env>.json
        $relativePath = $relativePath -replace '^appsettings\\(.+)', 'appsettings.$1'

        $destFile = [System.IO.Path]::Combine($Destination, $relativePath)
        $destDir = [System.IO.Path]::GetDirectoryName($destFile)

        # Create parent directory if needed
        if (-not [System.IO.Directory]::Exists($destDir)) {
            [System.IO.Directory]::CreateDirectory($destDir) | Out-Null
        }

        # Read, substitute, write
        $content = [System.IO.File]::ReadAllText($file.FullName)
        foreach ($key in $Vars.Keys) {
            $content = $content.Replace($key, $Vars[$key])
        }

        # launchSettings.json templates author "sslPort" as a quoted placeholder
        # (e.g. "sslPort": "$NewSslPort$") so the template itself is valid JSON;
        # unquote the substituted value here since IIS Express expects sslPort
        # as a JSON number, not a string.
        $content = $content -replace '("sslPort":\s*)"(\d+)"', '$1$2'

        # Strip hardening markers (and, below net10.0, the blocks they delimit) from Program.cs.
        if ($relativePath -like '*Program.cs') {
            $content = Remove-HardeningMarkers -Content $content -KeepHardening $KeepHardening
        }

        # appsettings.json ships a ForwardedHeaders section that only the hardened Program.cs
        # binds. Leaving it in an unhardened scaffold is worse than omitting it: an operator
        # could add trusted proxies there and believe the proxy is restricted while no code
        # reads the section. The regex assumes the block is a flat object followed by another
        # property (hence the trailing comma), so verify the removal instead of trusting it —
        # a silent no-op here is exactly the fail-open this strip exists to prevent.
        if (-not $KeepHardening -and $relativePath -like '*appsettings.json') {
            $content = [regex]::Replace($content, '\s*"ForwardedHeaders":\s*\{[^{}]*\},', '')
            if ($content -match '"ForwardedHeaders"') {
                throw "Failed to strip the 'ForwardedHeaders' section from $relativePath for the unhardened '$TargetFramework' scaffold. The template's JSON shape changed (the section must be a flat object followed by another property); fix the strip rather than shipping a trust surface no code enforces."
            }
        }

        [System.IO.File]::WriteAllText($destFile, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "    -> $relativePath"
    }
}

Copy-TemplateWithSubstitutions -Source $templateDir -Destination $NewProjectDir -Vars $substitutions -KeepHardening $hardeningSupported
Write-Host "  Files created from template." -ForegroundColor Green

if (-not $hardeningSupported) {
    Write-Warning "Scaffolded WITHOUT proxy security hardening: it requires net10.0 or later because it uses ForwardedHeadersOptions.KnownIPNetworks (introduced in .NET 10), and '$TargetFramework' is older. The forwarded-headers, Kestrel TLS, and authentication hardening were omitted, and appsettings.json has no ForwardedHeaders section. This proxy is NOT a hardened security boundary. Retarget to net10.0 and re-scaffold, or add the hardening by hand -- see 'Targeting below net10.0' in SKILL.md."
}

# Thread operator-supplied trusted proxy/network values into the generated appsettings.json.
# Uses targeted string replacement + UTF8-no-BOM write (not ConvertTo-Json) to preserve the
# template's key order and formatting and to avoid PowerShell 5.1 BOM issues. When a parameter
# is omitted, the template's secure loopback defaults remain in place.
function ConvertTo-JsonArrayLiteral {
    param([string[]]$Values)
    if (-not $Values -or $Values.Count -eq 0) { return '[]' }
    $items = $Values | ForEach-Object { '"' + ($_ -replace '\\', '\\' -replace '"', '\"') + '"' }
    return '[ ' + ($items -join ', ') + ' ]'
}

# Replace the JSON array value of $PropertyName with $Literal. A MatchEvaluator is used instead
# of the -replace operator so a '$' inside an operator-supplied value is treated literally rather
# than as a $1/$& backreference (injection), and an IsMatch guard turns a missing property into a
# hard error instead of a silent no-op that would leave the insecure default trust in place.
function Set-JsonArrayProperty {
    param(
        [string]$Json,
        [string]$PropertyName,
        [string]$Literal
    )
    $regex = [regex]::new('("' + [regex]::Escape($PropertyName) + '":\s*)\[[^\]]*\]')
    if (-not $regex.IsMatch($Json)) {
        throw "Could not find the '$PropertyName' array in appsettings.json; forwarded-headers trust configuration was not applied."
    }
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $m.Groups[1].Value + $Literal }
    return $regex.Replace($Json, $evaluator, 1)
}

if ($PSBoundParameters.ContainsKey('TrustedProxies') -or $PSBoundParameters.ContainsKey('TrustedNetworks') -or $PSBoundParameters.ContainsKey('AllowedForwardedHosts')) {
    $appsettingsPath = Join-Path $NewProjectDir 'appsettings.json'
    if (-not (Test-Path $appsettingsPath)) {
        throw "Cannot apply forwarded-headers trust configuration: '$appsettingsPath' was not found."
    }

    $appsettingsJson = [System.IO.File]::ReadAllText($appsettingsPath)
    if ($PSBoundParameters.ContainsKey('TrustedProxies')) {
        $literal = ConvertTo-JsonArrayLiteral $TrustedProxies
        $appsettingsJson = Set-JsonArrayProperty -Json $appsettingsJson -PropertyName 'TrustedProxies' -Literal $literal
    }
    if ($PSBoundParameters.ContainsKey('TrustedNetworks')) {
        $literal = ConvertTo-JsonArrayLiteral $TrustedNetworks
        $appsettingsJson = Set-JsonArrayProperty -Json $appsettingsJson -PropertyName 'TrustedNetworks' -Literal $literal
    }
    if ($PSBoundParameters.ContainsKey('AllowedForwardedHosts')) {
        # Targets ForwardedHeaders:AllowedHosts, not the sibling top-level "AllowedHosts": "*"
        # (host filtering): Set-JsonArrayProperty only matches an array value, and the top-level
        # key holds a string.
        $literal = ConvertTo-JsonArrayLiteral $AllowedForwardedHosts
        $appsettingsJson = Set-JsonArrayProperty -Json $appsettingsJson -PropertyName 'AllowedHosts' -Literal $literal
    }
    [System.IO.File]::WriteAllText($appsettingsPath, $appsettingsJson, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Applied forwarded-headers trust configuration to appsettings.json." -ForegroundColor Green
}

Write-Host "  Adding to solution..." -ForegroundColor Cyan
dotnet sln $SolutionPath add $NewProjectPath
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to add project to solution"; return }
Write-Host "  Added to solution." -ForegroundColor Green

# Find new project GUID and link old project
$slnContent = Get-Content $SolutionPath -Raw
$escapedName = [regex]::Escape($NewProjectName)
$slnMatch = [regex]::Match($slnContent, "Project\([^)]+\)\s*=\s*`"$escapedName`"\s*,\s*`"[^`"]+`"\s*,\s*`"\{([0-9A-Fa-f-]+)\}`"")
$newProjectGuid = if ($slnMatch.Success) { $slnMatch.Groups[1].Value } else { $null }

if ($newProjectGuid) {
    Write-Host "  New project GUID: $newProjectGuid" -ForegroundColor Cyan
    $oldCsproj = Get-Content $OldProjectPath -Raw
    if ($oldCsproj -notmatch '_MigrateToProjectGuid') {
        # Insert into the FIRST (unconditional) PropertyGroup only. The previous `-replace` rewrote
        # EVERY match, and a classic Framework csproj carries one PropertyGroup per configuration, so
        # three duplicate copies landed in a project file the customer owns. String .Insert() is used
        # rather than a regex replacement so a '$' anywhere in the value can never be read as a
        # backreference.
        $closeTagIndex = $oldCsproj.IndexOf('</PropertyGroup>')
        if ($closeTagIndex -ge 0) {
            # Match the file's existing newline convention rather than forcing one.
            $nl = if ($oldCsproj.Contains("`r`n")) { "`r`n" } else { "`n" }
            $lineStart = $oldCsproj.LastIndexOf("`n", $closeTagIndex) + 1
            $beforeTag = $oldCsproj.Substring($lineStart, $closeTagIndex - $lineStart)
            $indent = [regex]::Match($beforeTag, '^[ \t]*').Value
            $element = "$indent  <_MigrateToProjectGuid>$newProjectGuid</_MigrateToProjectGuid>"
            if ([string]::IsNullOrWhiteSpace($beforeTag)) {
                # </PropertyGroup> is on its own line: add the property as the line above it.
                $oldCsproj = $oldCsproj.Insert($lineStart, "$element$nl")
            } else {
                # Single-line <PropertyGroup>...</PropertyGroup>: break before the closing tag, so the
                # property lands INSIDE the group. Inserting at the line start would put it outside,
                # which MSBuild rejects.
                $oldCsproj = $oldCsproj.Insert($closeTagIndex, "$nl$element$nl$indent")
            }
            # WriteAllText rather than Set-Content -Encoding utf8NoBOM: that encoding name only exists
            # in PowerShell 6+, so it hard-fails on Windows PowerShell 5.1 (the default powershell.exe).
            [System.IO.File]::WriteAllText($OldProjectPath, $oldCsproj, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  Linked old project via _MigrateToProjectGuid." -ForegroundColor Green
        } else {
            Write-Warning "Could not find a </PropertyGroup> in '$OldProjectPath' to add _MigrateToProjectGuid to. Add <_MigrateToProjectGuid>$newProjectGuid</_MigrateToProjectGuid> manually."
        }
    }
} else {
    Write-Warning "Could not find new project GUID in solution. Add _MigrateToProjectGuid manually."
}

Write-Host "  Building new project..." -ForegroundColor Cyan
dotnet build $NewProjectPath --nologo -v:q
if ($LASTEXITCODE -eq 0) { Write-Host "  Build succeeded." -ForegroundColor Green }
else { Write-Warning "Build failed. Check the project configuration." }

Write-Host "`nScaffolding complete: $NewProjectPath" -ForegroundColor Green
Write-Host "ProxyTo: $OldAppUrl (in launchSettings.json)" -ForegroundColor Cyan