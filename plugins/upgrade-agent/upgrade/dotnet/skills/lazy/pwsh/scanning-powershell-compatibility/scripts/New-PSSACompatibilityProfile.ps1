# Copyright (c) Microsoft Corporation. All rights reserved.
#
# Generates a PSScriptAnalyzer compatibility profile describing the target
# PowerShell host, then validates that the profile is trustworthy before
# anything is scanned against it. Writes the profile plus a sibling
# '<name>.validation.json' recording the verdict.
#
# Called in Stage 1 Assessment, Step 3, before Invoke-PSSACompatibilityScan.ps1,
# which refuses to run against a profile this script marked FAIL. The validation
# ladder re-runs it when the target host or module set changes.
#
# WHY A GENERATED PROFILE
# -----------------------
# PSUseCompatibleCommands and PSUseCompatibleTypes do not know what breaks
# between editions. They know only what a target profile says exists, and flag
# everything absent from it. The profiles PSScriptAnalyzer ships were captured
# on Windows Server 2019 and stop at PowerShell 7.0.0, so findings are reported
# against a machine that is not the target and a module set that is not the
# caller's. Generating on the real target host, with the modules the scripts
# declare, removes those phantom findings.
#
# WHY VALIDATION IS PART OF GENERATION
# ------------------------------------
# Generation is lossy in both directions, and the two are not equally dangerous:
#
#   Something present is MISSING from the profile
#       -> false positives. Noisy, but visible and dismissible.
#   Something absent is PRESENT in the profile
#       -> false negatives. The rule stops reporting, and a clean report is
#          indistinguishable from a clean estate.
#
# The second is what contamination produces. When the compatibility layer is
# engaged, the WinPSCompatSession proxies for Get-WmiObject, Get-EventLog and
# friends are inventoried as real commands -- they resolve, but only by running
# in a Windows PowerShell 5.1 subprocess. The profile then asserts that the
# largest class of edition breakage does not exist, and PSScriptAnalyzer goes
# quiet on all of it. So contamination is a hard failure here, not a warning.
#
# It is checked rather than prevented because a clean session is not the default
# and cannot be reached by launch flags: PowerShell 7 on Windows puts the Windows
# PowerShell module directories on PSModulePath itself, and the layer engages
# lazily on first use, so merely asking whether a command exists can start it.
# Two layers therefore guard generation:
#
#   Before generating   Assert-CleanGeneratingSession refuses to run when the
#                       layer has already engaged. Sub-second, and names the
#                       cause. Re-checked after provisioning.
#   After generating    the profile itself is searched for removed-in-Core
#                       commands, which catches contamination introduced by
#                       generation regardless of how it arose.
#
# Either way the session's PSModulePath, compat-session state and live proxies
# are recorded in the sidecar, so a profile's provenance is auditable later.
#
# HOW VALIDATION WORKS
# --------------------
# Absence is asserted from a fixed list of cmdlets removed in PowerShell Core
# (derived from the rule catalog below). These must NOT appear in the profile;
# if they do, the generating session was contaminated.
#
# Presence is asserted by round-trip against the live host rather than a
# hardcoded expectation, because the correct answer differs per platform and per
# installed module set. Each probe asks the live host first, and the profile is
# only required to agree when the host says the item is genuinely there.
# Commands that resolve as Functions rather than Cmdlets are compat-layer
# proxies and are excluded from the presence check, since counting one as real
# is the contamination this script exists to catch.
#
# Parses under both 5.1 and 7: no ternary, '??', '&&'/'||' or '?.'. Generation
# requires PowerShell 7, and a 5.1 host has to parse the file far enough to
# report that instead of dying on a syntax error.

[CmdletBinding()]
param(
    # Where to write the generated profile JSON.
    [string] $OutputPath = 'pssa-target-profile.json',

    # Platform the migrated scripts must run on. A profile only ever describes
    # the machine it was generated on, so generating on Windows while targeting
    # Linux leaves every Windows-only module inventoried as present and silently
    # suppresses the cross-platform findings the migration exists to surface.
    [ValidateSet('Windows', 'Linux', 'macOS', 'Current')]
    [string] $TargetPlatform = 'Current',

    # PowerShell version the migrated scripts must run on, e.g. '7.4'. A profile
    # describes the *running* interpreter, so this is the version half of the
    # same problem $TargetPlatform solves. Direction matters and is asymmetric:
    #
    #   host NEWER than target (generate on 7.6, deploy to 7.4)
    #       The profile is a superset. Anything added after the target -- new
    #       cmdlets, new parameters, new type members -- is inventoried as
    #       present, so the scan blesses code that fails in production. This is
    #       a false negative, so it warns.
    #
    #   host OLDER than target (generate on 7.4, deploy to 7.6)
    #       The profile is a subset. It can only over-report, so it is safe and
    #       is noted rather than warned about.
    #
    # 'Current' skips the check. Pass the version confirmed in Pre-Initialization
    # rather than letting whatever pwsh is on the box define the target.
    [string] $TargetPSVersion = 'Current',

    # Modules to place on PSModulePath before generating, as 'Name',
    # 'Name:Minimum', or 'Name:Minimum:Maximum'.
    #
    # Pin the line the scripts were written against. A profile built over a
    # different major records that major's surface, and every call the estate
    # makes against the pinned one is then reported as invalid. Pester is the
    # default because Windows ships 3.4.0 in-box while the estate almost always
    # targets 5.x.
    #
    # The maximum matters as much as the minimum: provisioning a newer major
    # than the estate declares reintroduces the mismatch in the other direction.
    [string[]] $RequiredModule = @('Pester:5.0:5.99'),

    # Directory the provisioned modules are saved into.
    [string] $ProvisionModulePath,

    # Generate against whatever is already on PSModulePath.
    [switch] $SkipProvision,

    # Emit the profile without validating it. Not recommended: an unvalidated
    # profile can suppress findings without ever reporting an error.
    [switch] $SkipValidation,

    # Return the result object instead of only printing the report.
    [switch] $PassThru
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# Sentinel list for the absence check: cmdlets removed in PowerShell Core. Any
# of these appearing in a generated profile means the session had the Windows
# PowerShell compatibility shims loaded.
#
# Derived from the rule catalog rather than hand-maintained, so the two can
# never disagree. A hand-kept list drifts out of step as catalog rules are
# added, and the gap is invisible: a contaminated profile just returns PASS.
$catalogPath = Join-Path $PSScriptRoot '../rules/PSCompatibilityRules.psd1'
$RemovedInCore = @()
if (Test-Path -LiteralPath $catalogPath) {
    $catalogRules = (Import-PowerShellDataFile -LiteralPath $catalogPath).Rules

    # Not every flagged command was removed. Send-MailMessage is deprecated but
    # is still a native cmdlet in 7, so treating it as contamination evidence
    # would fail every clean profile. To classify a candidate, run
    # `Get-Command <name>` under a clean `pwsh -NoProfile`: CommandType Cmdlet
    # means native (exclude it), Function means a compatibility proxy, and
    # absent means genuinely removed.
    $NativeInCoreDespiteRule = @('Send-MailMessage')

    $RemovedInCore = @(
        $catalogRules |
            Where-Object { $_.Kind -eq 'Command' } |
            ForEach-Object { $_.Match } |
            Where-Object { $_ -and $NativeInCoreDespiteRule -notcontains $_ } |
            Sort-Object -Unique
    )
}
if ($RemovedInCore.Count -eq 0) {
    throw "Could not derive the contamination sentinel list from '$catalogPath'. Without it a profile built from a shimmed session would validate as clean."
}

# Commands sampled against the live host for the presence check. Spans several
# modules so that a wholly dropped module is caught: a module missing from the
# profile flags every one of its commands across the estate.
$ProbeCommand = @(
    'Get-ChildItem', 'Start-Process', 'Set-Content',
    'Invoke-RestMethod', 'ConvertFrom-Json', 'Write-Host',
    'Get-CimInstance', 'Invoke-CimMethod',
    'Get-WinEvent', 'Get-Counter',
    'Get-Acl', 'Start-Job'
)

# Types sampled against the live host, spanning the assemblies the estate is
# most likely to touch. A type the host loads but the profile omits makes
# PSUseCompatibleTypes flag every use of it.
$ProbeType = @(
    'System.Tuple',
    'System.Net.Http.HttpClient',
    'System.Text.Json.JsonSerializer',
    'System.Xml.XmlDocument',
    'System.Data.SqlClient.SqlConnection',
    'System.Text.RegularExpressions.Regex',
    'System.IO.Compression.ZipFile',
    'System.Security.Cryptography.SHA256',
    'System.Management.Automation.PSObject'
)

function Write-Step {
    param([string] $Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-CurrentPlatformName {
    if ($PSVersionTable.PSVersion.Major -lt 6) { return 'Windows' }
    if ($IsWindows) { return 'Windows' }
    if ($IsLinux) { return 'Linux' }
    if ($IsMacOS) { return 'macOS' }
    return 'Unknown'
}

function Assert-TargetHost {
    param([string] $Requested, [string] $RequestedVersion = 'Current')

    $current = Get-CurrentPlatformName
    if ($PSVersionTable.PSEdition -ne 'Core') {
        throw ("Profile generation must run under the target host. This is " +
            "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)). " +
            "Re-run under pwsh.")
    }

    $resolved = $Requested
    if ($resolved -eq 'Current') { $resolved = $current }

    if ($resolved -ne $current) {
        Write-Warning ("Target platform is '$resolved' but this host is '$current'. A profile " +
            "describes the machine it was generated on, so every module that exists here and " +
            "not on '$resolved' will be recorded as available and its findings suppressed. " +
            "Generate on '$resolved', or treat platform-specific results as unverified.")
    }

    $versionMismatch = $false
    $resolvedVersion = $RequestedVersion
    if ([string]::IsNullOrWhiteSpace($resolvedVersion)) { $resolvedVersion = 'Current' }

    if ($resolvedVersion -ne 'Current') {
        $parsed = $null
        if (-not [version]::TryParse($resolvedVersion, [ref] $parsed)) {
            throw "TargetPSVersion '$resolvedVersion' is not a version. Use a value like '7.4'."
        }

        $hostVersion = $PSVersionTable.PSVersion
        # Compare on major.minor only. A profile does not vary by patch, and
        # demanding an exact patch match would make the check unsatisfiable.
        $hostMm   = [version]::new($hostVersion.Major, $hostVersion.Minor)
        $targetMm = [version]::new($parsed.Major, $parsed.Minor)

        if ($hostMm -gt $targetMm) {
            $versionMismatch = $true
            Write-Warning ("Target is PowerShell $targetMm but this host is $hostMm. The profile " +
                "is generated by reflecting over the running interpreter, so commands, " +
                "parameters and type members added after $targetMm will be inventoried as " +
                "available and their findings suppressed -- code that passes the rescan can " +
                "still fail on $targetMm. Generate on $targetMm, or treat the result as a " +
                "lower bound on the real finding count.")
        }
        elseif ($hostMm -lt $targetMm) {
            Write-Host ("    Note: host is $hostMm, target is $targetMm. The profile is a subset " +
                "of the target, so it can only over-report. Safe direction.")
        }
    }

    return [pscustomobject]@{
        PSVersion       = $PSVersionTable.PSVersion.ToString()
        Platform        = $current
        Target          = $resolved
        TargetPSVersion = $resolvedVersion
        Mismatch        = ($resolved -ne $current)
        VersionMismatch = $versionMismatch
    }
}

function Import-CrossCompatibilityModule {
    $module = Get-Module -ListAvailable PSScriptAnalyzer |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $module) {
        throw ("PSScriptAnalyzer is not installed. Install it with: " +
            "Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Scope CurrentUser")
    }

    $dll = Join-Path $module.ModuleBase 'PSv7/Microsoft.PowerShell.CrossCompatibility.dll'
    if (-not (Test-Path $dll)) {
        throw ("PSScriptAnalyzer $($module.Version) at $($module.ModuleBase) does not carry the " +
            "cross-compatibility collector, so a profile cannot be generated. Reinstall it with: " +
            "Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Scope CurrentUser -Force. " +
            "Do not substitute the profiles PSScriptAnalyzer ships -- they stop at PowerShell 7.0.0 " +
            "and describe an unrelated machine, so scanning against them reports a clean result " +
            "for breakage that is present.")
    }

    Import-Module $dll -Force
    return $module.Version.ToString()
}

function Remove-OutOfRangeVersion {
    param([string] $ModuleRoot, [string] $Minimum, [string] $Maximum)

    if (-not (Test-Path $ModuleRoot)) { return }
    if ([string]::IsNullOrWhiteSpace($Minimum) -and [string]::IsNullOrWhiteSpace($Maximum)) { return }

    foreach ($versionDir in (Get-ChildItem $ModuleRoot -Directory -ErrorAction SilentlyContinue)) {
        $parsed = $null
        if (-not [version]::TryParse($versionDir.Name, [ref]$parsed)) { continue }
        $outOfRange = $false
        if (-not [string]::IsNullOrWhiteSpace($Minimum) -and $parsed -lt [version]$Minimum) { $outOfRange = $true }
        if (-not [string]::IsNullOrWhiteSpace($Maximum) -and $parsed -gt [version]$Maximum) { $outOfRange = $true }
        if ($outOfRange) {
            Write-Host "    pruning $(Split-Path $ModuleRoot -Leaf) $($versionDir.Name) (outside $Minimum..$Maximum)"
            Remove-Item $versionDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-RequiredModule {
    param([string[]] $Specification, [string] $Destination)

    $provisioned = @()
    foreach ($spec in $Specification) {
        $name = $spec
        $minimum = $null
        $maximum = $null
        if ($spec.Contains(':')) {
            $parts = $spec.Split(':')
            $name = $parts[0]
            if ($parts.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($parts[1])) { $minimum = $parts[1] }
            if ($parts.Count -gt 2 -and -not [string]::IsNullOrWhiteSpace($parts[2])) { $maximum = $parts[2] }
        }

        $installed = Get-Module -ListAvailable $name -ErrorAction SilentlyContinue |
            Where-Object {
                ($null -eq $minimum -or $_.Version -ge [version]$minimum) -and
                ($null -eq $maximum -or $_.Version -le [version]$maximum)
            } |
            Sort-Object Version -Descending | Select-Object -First 1

        if ($null -ne $installed) {
            $provisioned += [pscustomobject]@{ Name = $name; Version = $installed.Version.ToString(); Source = 'already-present' }
            continue
        }

        $anyVersion = Get-Module -ListAvailable $name -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending | Select-Object -First 1
        if ($null -ne $anyVersion) { $foundText = $anyVersion.Version.ToString() } else { $foundText = 'none' }
        Write-Host "    $name (found: $foundText, want: $minimum..$maximum) -- saving from PSGallery"

        if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
        $saveArguments = @{ Name = $name; Path = $Destination; Force = $true; ErrorAction = 'Stop' }
        if ($null -ne $minimum) { $saveArguments['MinimumVersion'] = $minimum }
        if ($null -ne $maximum) { $saveArguments['MaximumVersion'] = $maximum }
        Save-Module @saveArguments

        # Prune before reporting. PSUseCompatibleCommands unions parameters
        # across every version of a module present in the profile, so a stray
        # copy outside the pinned range makes parameters look available that the
        # pinned version does not have, masking real findings. Save-Module also
        # leaves earlier runs' versions in place.
        Remove-OutOfRangeVersion -ModuleRoot (Join-Path $Destination $name) -Minimum $minimum -Maximum $maximum

        $saved = Get-ChildItem (Join-Path $Destination $name) -Directory -ErrorAction SilentlyContinue |
            Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        if ($null -ne $saved) { $savedVersion = $saved.Name } else { $savedVersion = 'unknown' }
        $provisioned += [pscustomobject]@{ Name = $name; Version = $savedVersion; Source = 'psgallery' }
    }

    # Prepend so the provisioned copy wins over an in-box module of the same name.
    if (Test-Path $Destination) {
        $env:PSModulePath = $Destination + [System.IO.Path]::PathSeparator + $env:PSModulePath
    }
    return $provisioned
}

function New-TargetProfile {
    param([string] $Destination)

    $arguments = @{ OutFile = $Destination; Validate = $true }

    # Reflecting over the Windows PowerShell assembly tree throws
    # TypeLoadException on System.Runtime.InteropServices._Assembly and aborts
    # generation, so those assemblies are excluded. Exclude assemblies only --
    # applying the same prefix to MODULES drops real modules from the profile
    # and manufactures findings for every command they own.
    if ((Get-CurrentPlatformName) -eq 'Windows') {
        $arguments['ExcludeAssemblyPathPrefix'] = @('C:\Program Files\WindowsPowerShell')
    }

    # Generation emits BadImageFormatException / TypeLoadException warnings for
    # native DLLs it cannot reflect over. Those are expected and not failures.
    New-PSCompatibilityProfile @arguments 3>$null | Out-Null

    if (-not (Test-Path $Destination)) {
        throw "Profile generation reported no error but produced no file at $Destination."
    }
    return (Get-Item $Destination)
}

function Get-ProfileCommandSet {
    param($Profile)

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($module in $Profile.Runtime.Modules.GetEnumerator()) {
        foreach ($version in $module.Value.GetEnumerator()) {
            foreach ($bag in @('Cmdlets', 'Functions', 'Aliases')) {
                $bucket = $version.Value.$bag
                if ($null -eq $bucket) { continue }
                foreach ($name in $bucket.Keys) { [void]$set.Add($name) }
            }
        }
    }
    return $set
}

function Test-ProfileHasType {
    param($Profile, [string] $FullName)

    $index = $FullName.LastIndexOf('.')
    if ($index -lt 0) { return $false }
    $namespace = $FullName.Substring(0, $index)
    $name = $FullName.Substring($index + 1)

    foreach ($assembly in $Profile.Runtime.Types.Assemblies.GetEnumerator()) {
        $types = $assembly.Value.Types
        if ($null -eq $types) { continue }
        $bucket = $types[$namespace]
        if ($null -eq $bucket) { continue }
        if ($bucket.ContainsKey($name)) { return $true }
    }
    return $false
}

function Get-ProfileModuleVersion {
    param($Profile, [string] $Name)

    $versions = @()
    foreach ($module in $Profile.Runtime.Modules.GetEnumerator()) {
        if ($module.Key -ne $Name) { continue }
        foreach ($version in $module.Value.GetEnumerator()) { $versions += $version.Key }
    }
    return $versions
}

function Test-GeneratedProfile {
    param([string] $Path, [string[]] $Specification)

    # -AsHashtable is required: a member of the profile is literally named
    # 'psobject', which collides with the PSObject adapter on a typed conversion.
    $profileData = Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable
    $commands = Get-ProfileCommandSet -Profile $profileData

    $contamination = @()
    foreach ($name in $RemovedInCore) {
        if ($commands.Contains($name)) { $contamination += $name }
    }

    $missing = @()
    $proxies = @()
    foreach ($name in $ProbeCommand) {
        $live = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -eq $live) { continue }
        if ($live.CommandType -ne 'Cmdlet') {
            # A Function here is a Windows PowerShell compat proxy, not a native
            # command. Requiring the profile to contain it would demand exactly
            # the contamination the absence check rejects.
            $proxies += $name
            continue
        }
        if (-not $commands.Contains($name)) { $missing += $name }
    }

    $missingTypes = @()
    foreach ($name in $ProbeType) {
        if ($null -eq ($name -as [type])) { continue }
        if (-not (Test-ProfileHasType -Profile $profileData -FullName $name)) { $missingTypes += $name }
    }

    $status = 'PASS'
    if ($missing.Count -gt 0 -or $missingTypes.Count -gt 0) { $status = 'WARN' }

    # A version of a pinned module that sits outside the requested range but
    # outside the provision directory too (a machine-wide install, or the in-box
    # copy) cannot be pruned and still lands in the profile.
    #
    # Only versions ABOVE the maximum matter. Parameters are unioned across
    # versions, so an extra version can only ADD parameters, never remove them.
    # A newer major therefore masks real findings, while an older one (Windows
    # ships Pester 3.4.0 in-box) contributes a subset and changes nothing.
    $unpinned = @()
    foreach ($spec in $Specification) {
        $parts = $spec.Split(':')
        $name = $parts[0]
        if ($parts.Count -lt 3 -or [string]::IsNullOrWhiteSpace($parts[2])) { continue }
        $maximum = $parts[2]

        foreach ($found in (Get-ProfileModuleVersion -Profile $profileData -Name $name)) {
            $parsed = $null
            if (-not [version]::TryParse($found, [ref]$parsed)) { continue }
            if ($parsed -gt [version]$maximum) { $unpinned += "$name $found (pinned at <= $maximum)" }
        }
    }
    # FAIL rather than WARN. An unpinned module means a version newer than the
    # pin reached the profile, and parameters are unioned across versions, so
    # the newer major masks real findings. That is under-reporting, unlike
    # MissingCommands/MissingTypes, which only over-report. WARN means "usable,
    # treat the gaps as a false-positive ledger", which would label an
    # under-reporting profile harmless.
    if ($unpinned.Count -gt 0) { $status = 'FAIL' }

    if ($contamination.Count -gt 0) { $status = 'FAIL' }

    return [pscustomobject]@{
        Status          = $status
        Contamination   = $contamination
        MissingCommands = $missing
        MissingTypes    = $missingTypes
        UnpinnedModules = $unpinned
        CompatProxies   = $proxies
        CommandCount    = $commands.Count
        AssemblyCount   = $profileData.Runtime.Types.Assemblies.Count
        ModuleCount     = $profileData.Runtime.Modules.Count
    }
}

# --------------------------------------------------------------------------

function Get-SessionProvenance {
    # Facts about the session that is about to generate, recorded into the
    # validation sidecar so a profile can be audited after the fact.
    #
    # Reads already-resolved state only. Asking `Get-Command Get-WmiObject` is
    # itself enough to start a WinPSCompatSession and generate proxies, so a
    # probe written that way would manufacture the contamination it is looking
    # for.
    param([string[]] $RemovedInCore)

    $modulePath = @()
    if (-not [string]::IsNullOrEmpty($env:PSModulePath)) {
        $modulePath = @($env:PSModulePath -split [System.IO.Path]::PathSeparator |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $compatSession = $false
    try {
        $compatSession = [bool] (Get-PSSession -Name 'WinPSCompatSession' -ErrorAction SilentlyContinue)
    }
    catch { }

    $compatModules = @(Get-Module |
        Where-Object { $_.Name -like '*WindowsCompatibility*' } |
        ForEach-Object { $_.Name })

    # Compatibility proxies are injected into the module they shadow, so
    # Get-WmiObject reports Source 'Microsoft.PowerShell.Management'. A
    # removed-in-Core name exported as a FUNCTION by a loaded module is a live
    # shim; the real commands were Cmdlets and no longer exist at all.
    $proxies = New-Object System.Collections.Generic.List[string]
    foreach ($m in @(Get-Module)) {
        if ($null -eq $m.ExportedFunctions) { continue }
        foreach ($fn in @($m.ExportedFunctions.Keys)) {
            if ($RemovedInCore -contains $fn) { [void] $proxies.Add("$fn (from $($m.Name))") }
        }
    }

    return [pscustomobject]@{
        PSModulePath           = $modulePath
        WindowsPowerShellPaths = @($modulePath | Where-Object { $_ -match 'WindowsPowerShell' })
        WinPSCompatSession     = $compatSession
        CompatModulesLoaded    = $compatModules
        LiveProxies            = $proxies.ToArray()
    }
}

function Assert-CleanGeneratingSession {
    # Refuses to generate from a session whose compatibility layer is already
    # active. The post-generation contamination check catches the same fault, but
    # only after a full inventory; this fails in under a second and names the
    # cause instead of the symptom.
    #
    # Note what is NOT checked: PowerShell 7 on Windows puts the Windows
    # PowerShell module directories on PSModulePath by default, so their presence
    # is the normal state and gates nothing. They are recorded, not judged --
    # what matters is whether the compatibility layer actually engaged.
    param($Provenance)

    $reasons = New-Object System.Collections.Generic.List[string]
    if ($Provenance.WinPSCompatSession) {
        [void] $reasons.Add('a WinPSCompatSession is already open in this session')
    }
    if ($Provenance.CompatModulesLoaded.Count -gt 0) {
        [void] $reasons.Add("the compatibility module is loaded: $($Provenance.CompatModulesLoaded -join ', ')")
    }
    if ($Provenance.LiveProxies.Count -gt 0) {
        [void] $reasons.Add("removed-in-Core commands already resolve as proxies: $($Provenance.LiveProxies -join ', ')")
    }
    if ($reasons.Count -eq 0) { return }

    throw ("Refusing to generate: " + ($reasons -join '; ') + ". Commands reachable only through " +
        "the compatibility layer run in a Windows PowerShell 5.1 subprocess, so inventorying them " +
        "as native would make PSScriptAnalyzer silent on the largest class of edition breakage -- " +
        "the exact thing this migration exists to find. Start a fresh 'pwsh -NoProfile' and re-run. " +
        "Use -SkipValidation to override, and do not report a clean scan against the result.")
}

# --------------------------------------------------------------------------

$hostInfo = Assert-TargetHost -Requested $TargetPlatform -RequestedVersion $TargetPSVersion
Write-Step "Host"
Write-Host "    PowerShell $($hostInfo.PSVersion) on $($hostInfo.Platform); target '$($hostInfo.Target)' $($hostInfo.TargetPSVersion)"

# Fail before any expensive work if this session is already shimmed.
$provenance = Get-SessionProvenance -RemovedInCore $RemovedInCore
if (-not $SkipValidation) { Assert-CleanGeneratingSession -Provenance $provenance }
Write-Host "    generating session: compat layer $(if ($provenance.WinPSCompatSession -or $provenance.LiveProxies.Count -gt 0) { 'ENGAGED' } else { 'not engaged' })"

$analyzerVersion = Import-CrossCompatibilityModule
Write-Host "    PSScriptAnalyzer $analyzerVersion cross-compatibility collector loaded"

$provisioned = @()
if (-not $SkipProvision) {
    Write-Step "Provisioning modules"
    if ([string]::IsNullOrWhiteSpace($ProvisionModulePath)) {
        $ProvisionModulePath = Join-Path ([System.IO.Path]::GetTempPath()) 'ps7-upgrade-modules'
    }
    $provisioned = Install-RequiredModule -Specification $RequiredModule -Destination $ProvisionModulePath
    foreach ($item in $provisioned) { Write-Host "    $($item.Name) $($item.Version) [$($item.Source)]" }
}
else {
    Write-Step "Provisioning skipped"
    Write-Warning ("Generating against the ambient module set. If the estate declares Pester 5 " +
        "but this host has only the in-box Pester 3.4.0, expect thousands of spurious parameter findings.")
}

Write-Step "Generating profile"
# Re-checked here because module provisioning runs in between and can import
# something that engages the compatibility layer. This capture is the one
# recorded, since it describes the session the profile is actually built from.
$provenance = Get-SessionProvenance -RemovedInCore $RemovedInCore
if (-not $SkipValidation) { Assert-CleanGeneratingSession -Provenance $provenance }
if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path (Get-Location).Path $OutputPath
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$file = New-TargetProfile -Destination $OutputPath
$stopwatch.Stop()
Write-Host ("    {0} ({1:N2} MB) in {2}s" -f $file.FullName, ($file.Length / 1MB), [int]$stopwatch.Elapsed.TotalSeconds)

if ($SkipValidation) {
    Write-Step "Validation skipped"
    Write-Warning "An unvalidated profile can suppress findings silently. Do not report a clean scan against it."
    if ($PassThru) { return [pscustomobject]@{ ProfilePath = $file.FullName; Validation = $null; Provenance = $provenance; Provisioned = $provisioned } }
    return
}

Write-Step "Validating profile"
$result = Test-GeneratedProfile -Path $file.FullName -Specification $RequiredModule
Write-Host "    $($result.ModuleCount) modules, $($result.CommandCount) command names, $($result.AssemblyCount) assemblies"

if ($result.CompatProxies.Count -gt 0) {
    Write-Host "    compat-layer proxies on this host (excluded from checks): $($result.CompatProxies -join ', ')"
}

if ($result.Contamination.Count -gt 0) {
    Write-Host ''
    Write-Host "FAIL: removed-in-Core commands are present in the profile:" -ForegroundColor Red
    foreach ($name in $result.Contamination) { Write-Host "    $name" -ForegroundColor Red }
    Write-Host ("The generating session had the Windows PowerShell compatibility shims loaded. " +
        "PSScriptAnalyzer will report NOTHING for these commands, which is the single largest " +
        "class of edition breakage. Regenerate in a clean 'pwsh -NoProfile' session.") -ForegroundColor Red
}

if ($result.MissingCommands.Count -gt 0 -or $result.MissingTypes.Count -gt 0) {
    Write-Host ''
    Write-Host "WARN: items resolve on this host but are absent from the profile:" -ForegroundColor Yellow
    foreach ($name in $result.MissingCommands) { Write-Host "    command  $name" -ForegroundColor Yellow }
    foreach ($name in $result.MissingTypes) { Write-Host "    type     $name" -ForegroundColor Yellow }
    Write-Host ("Generation dropped these silently. Every use of them will be reported as " +
        "incompatible. Record them as known false positives so triage does not chase them.") -ForegroundColor Yellow
}

if ($result.UnpinnedModules.Count -gt 0) {
    Write-Host ''
    Write-Host "WARN: module versions newer than the pin reached the profile:" -ForegroundColor Yellow
    foreach ($name in $result.UnpinnedModules) { Write-Host "    $name" -ForegroundColor Yellow }
    Write-Host ("These are installed outside the provision directory, so they could not be pruned. " +
        "Parameters are unioned across versions, so real findings against the pinned line will be " +
        "suppressed. Remove the newer version, or state the risk in the report.") -ForegroundColor Yellow
}

# Fold the host mismatches into Status. Assert-TargetHost only warns about
# them, and a consumer reads Status. Without this, a profile built on Windows
# for a Linux target -- or on 7.6 for a 7.2 target -- records PASS. Both
# conditions under-report, so both fail.
if ($hostInfo.Mismatch) {
    $result.Status = 'FAIL'
    Write-Host ''
    Write-Host ("FAIL: profile generated on '$($hostInfo.Platform)' but the target is '$($hostInfo.Target)'. " +
        "Platform-specific commands and types will be inventoried from the wrong platform, so PSScriptAnalyzer " +
        "goes silent on real breaks. Generate on the target platform.") -ForegroundColor Red
}
if ($hostInfo.VersionMismatch) {
    $result.Status = 'FAIL'
    Write-Host ''
    Write-Host ("FAIL: this host is newer than the requested target PowerShell version. Commands, parameters " +
        "and type members added after the target will be inventoried as available, suppressing real findings. " +
        "Generate on the target version.") -ForegroundColor Red
}

Write-Host ''
Write-Host "PROFILE VALIDATION: $($result.Status)"

$sidecar = [System.IO.Path]::ChangeExtension($file.FullName, '.validation.json')
$payload = [pscustomobject]@{
    ProfilePath     = $file.FullName
    GeneratedAt     = (Get-Date).ToString('o')
    Host            = $hostInfo
    AnalyzerVersion = $analyzerVersion
    Provisioned     = $provisioned
    Provenance      = $provenance
    Validation      = $result
}
$payload | ConvertTo-Json -Depth 6 | Set-Content $sidecar -Encoding UTF8
Write-Host "Validation record: $sidecar"

if ($PassThru) { $payload }

# The exit gate runs even under -PassThru, so a caller gating on the exit code
# sees a FAIL whether or not it also asked for the object. FAIL means the
# profile is untrustworthy in the under-reporting direction: it will report a
# clean estate for code that is broken.
if ($result.Status -eq 'FAIL') { exit 1 }
