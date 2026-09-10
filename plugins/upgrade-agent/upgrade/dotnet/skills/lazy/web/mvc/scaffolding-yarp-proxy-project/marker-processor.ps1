# Copyright (c) Microsoft Corporation. All rights reserved.
# Shared marker processor for the YARP proxy scaffold templates.
#
# Dot-sourced by scaffold-project.ps1 and by the test suite. It lives in its own file -- and
# specifically in a *.ps1 file, never a *.psm1 module -- for two reasons:
#
#   1. scaffold-project.ps1 declares mandatory parameters and runs straight through, so a test
#      cannot dot-source it without performing a full scaffold. Extracting the parser is the only
#      way to test the real implementation instead of a second copy, and a second copy is exactly
#      how the marker rules would drift out of sync with the templates they govern.
#   2. build/targets/Skills.targets stages skills\**\* but Authenticode-signs only **\*.ps1 (the
#      SignSkillsScripts target). A .psm1 would ship inside the VSIX unsigned and fail to load
#      under a signed-script execution policy -- while every local test stayed green.

# Every marker kind the templates may use. Anything else is a template authoring error.
#
#   hardening    - net10.0+ only. Forwarded headers, Kestrel TLS policy, response scrubbing.
#   authseam     - the parameterless AddAuthentication() placeholder. Kept only when no real
#                  auth path is wired, because a concrete path registers its own scheme.
#   authpipeline - app.UseAuthentication(). Needed by the hardening *and* by either auth path,
#                  which is why it is a separate kind: stripping it with the hardening on a
#                  sub-net10 shared-cookie scaffold would register a scheme nothing ever runs.
#   swadefault   - the plain AddSystemWebAdapters() call. Replaced, not extended, by remoteauth.
#   sharedcookie - Stage 2 shared cookie: the scheme and cookie-name registration.
#   dpfilesystem - Stage 2 key ring persisted to a directory, protected by an X.509 certificate.
#   dpazureblob  - Stage 2 key ring persisted to Azure Blob Storage, protected by Azure Key Vault.
#   remoteauth   - Stage 1 remote authentication against the Framework app.
#
# The two dp* kinds are SIBLINGS of sharedcookie rather than regions nested inside it, because
# Remove-TemplateMarkers rejects nested markers outright. Exactly one of them survives whenever
# sharedcookie does; see Get-KeepKinds, which refuses to emit neither.
$script:KnownMarkerKinds = @(
    'hardening'
    'authseam'
    'authpipeline'
    'swadefault'
    'sharedcookie'
    'dpfilesystem'
    'dpazureblob'
    'remoteauth'
)

# The accepted -SharedKeyRingProvider values, and the marker kind each one keeps. Declared as one
# map so the parameter's ValidateSet, the keep-kind resolution, and the tests cannot disagree about
# which providers exist -- adding a third topology means adding one entry here.
$script:SharedKeyRingProviders = [ordered]@{
    'filesystem' = 'dpfilesystem'
    'azureblob'  = 'dpazureblob'
}

function Get-SharedKeyRingProviders {
    return @($script:SharedKeyRingProviders.Keys)
}

function Get-KnownMarkerKinds {
    return $script:KnownMarkerKinds
}

<#
.SYNOPSIS
    Strips template marker lines, and the regions they delimit when that region's kind is not
    in $KeepKinds.

.DESCRIPTION
    Marker regions are SEQUENTIAL, never nested. The parser therefore tracks a single open kind
    rather than a depth counter or a stack: that is what keeps several consecutive regions of the
    same kind legal (the templates carry runs of them) while still rejecting a genuinely nested
    pair, which would make the matching close marker ambiguous.

    Every rejection below is deliberate. A malformed marker that is silently tolerated does not
    fail loudly -- it ships generated code with either a literal '//<marker>' comment in it or a
    conditional block that was never made conditional.
#>
function Remove-TemplateMarkers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content,

        # Kinds whose *content* survives. Marker lines themselves are always removed.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$KeepKinds,

        [string[]]$KnownKinds = $script:KnownMarkerKinds
    )

    $lines = $Content -split "`r?`n"
    $kept = [System.Collections.Generic.List[string]]::new()
    $openKind = $null
    $strippedAny = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        # Match marker SHAPE first, then validate the kind, so an unknown kind is reported as an
        # unknown marker rather than passed through as ordinary code.
        $marker = [regex]::Match($trimmed, '^//<(?<close>/?)(?<kind>[A-Za-z][A-Za-z0-9]*)>$')
        if ($marker.Success) {
            $kind = $marker.Groups['kind'].Value
            $isClose = $marker.Groups['close'].Value -eq '/'

            if ($KnownKinds -notcontains $kind) {
                throw "Unknown template marker '$trimmed'. Known marker kinds: $($KnownKinds -join ', '). Fix the template rather than scaffolding a project with an unhandled marker."
            }

            if ($isClose) {
                if ($null -eq $openKind) {
                    throw "Unmatched '//</$kind>' marker in a template file; the scaffold would emit malformed code."
                }
                if ($openKind -ne $kind) {
                    throw "Mismatched template markers: '//<$openKind>' is closed by '//</$kind>'; the scaffold would emit malformed code."
                }
                $openKind = $null
                continue
            }

            if ($null -ne $openKind) {
                throw "Nested template markers: '//<$kind>' opened inside '//<$openKind>'. Marker regions must be sequential, not nested; the scaffold would emit malformed code."
            }

            $openKind = $kind
            continue
        }

        # A line that looks like one of our markers but did not match the canonical shape above is
        # almost always a typo -- '//<shared-cookie>' for '//<sharedcookie>', say. Left alone it is
        # silently emitted into the customer's source as a stray comment AND its region is never
        # processed, so the block it was meant to gate ships unconditionally. Catch the near miss
        # rather than the consequence. The pattern is deliberately narrow (a single bracketed
        # identifier on its own line) so it cannot fire on ordinary commented-out code, and XML doc
        # comments are unaffected because they open with three slashes.
        if ($trimmed -match '^//</?[A-Za-z][A-Za-z0-9_-]*>$') {
            throw "Malformed template marker '$trimmed'. Marker kinds are letters and digits only, so this was not recognised as a marker and its region would be emitted unconditionally. Known marker kinds: $($KnownKinds -join ', ')."
        }

        if ($null -ne $openKind -and $KeepKinds -notcontains $openKind) {
            $strippedAny = $true
            continue
        }

        $kept.Add($line)
    }

    if ($null -ne $openKind) {
        throw "Unbalanced '//<$openKind>' marker in a template file; the scaffold would emit malformed code."
    }

    $result = $kept -join [System.Environment]::NewLine

    # Dropping whole regions leaves runs of blank lines behind. Collapse only when something was
    # actually stripped, and do it AFTER the join against the same newline the join inserted --
    # collapsing the pre-join array, or matching a different newline convention, silently no-ops.
    if ($strippedAny) {
        $nl = [regex]::Escape([System.Environment]::NewLine)
        $result = [regex]::Replace($result, "(?:$nl){3,}", [System.Environment]::NewLine * 2)
        $result = $result -replace "^(?:$nl)+", ''
    }

    return $result
}

<#
.SYNOPSIS
    Resolves which marker kinds survive, given the target framework and the selected auth path.

.DESCRIPTION
    Centralised so the script, the templates, and the tests cannot disagree about the matrix.
    The two non-obvious rules:

      authseam     is dropped when a real auth path is on, because sharedcookie/remoteauth each
                   register their own scheme; keeping the parameterless placeholder as well would
                   emit two AddAuthentication calls and invite the second to reset the default.

      authpipeline survives when hardening is OFF but an auth path is ON. This is the whole reason
                   it is a separate kind. It used to live inside a hardening region, so a
                   sub-net10 shared-cookie scaffold stripped app.UseAuthentication() while still
                   registering a cookie scheme -- an app that authenticates nobody, failing in the
                   exact configuration the shared-cookie feature exists to serve.

      dpfilesystem / dpazureblob are mutually exclusive and exactly one is kept alongside
                   sharedcookie. An unrecognised provider throws rather than keeping neither: a
                   shared-cookie scaffold with no key ring at all compiles, starts, and silently
                   protects tickets with a per-app ephemeral ring -- the same silent-anonymous
                   failure the whole path exists to prevent.
#>
function Get-KeepKinds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$HardeningSupported,

        [bool]$EnableSharedCookieAuth,

        [bool]$EnableRemoteAuth,

        [string]$SharedKeyRingProvider = 'filesystem'
    )

    $anyAuth = $EnableSharedCookieAuth -or $EnableRemoteAuth
    $keep = [System.Collections.Generic.List[string]]::new()

    if ($HardeningSupported) { $keep.Add('hardening') }
    if ($HardeningSupported -and -not $anyAuth) { $keep.Add('authseam') }
    if ($HardeningSupported -or $anyAuth) { $keep.Add('authpipeline') }
    if (-not $EnableRemoteAuth) { $keep.Add('swadefault') }
    if ($EnableRemoteAuth) { $keep.Add('remoteauth') }

    if ($EnableSharedCookieAuth) {
        $keep.Add('sharedcookie')

        # Resolved through the same map the ValidateSet is built from, so a provider that passes
        # parameter binding can never fail to select a key ring here.
        $dpKind = $script:SharedKeyRingProviders[$SharedKeyRingProvider]
        if (-not $dpKind) {
            throw "Unknown shared key ring provider '$SharedKeyRingProvider'. Known providers: $((Get-SharedKeyRingProviders) -join ', '). Refusing to scaffold shared cookie authentication with no Data Protection key ring."
        }
        $keep.Add($dpKind)
    }

    return $keep.ToArray()
}
