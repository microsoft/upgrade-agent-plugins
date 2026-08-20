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

    # Only used by -SharedKeyRingProvider azureblob. Unlike the two above these are not template
    # substitutions: the packages are added to the generated .csproj only when that provider is
    # chosen, so a filesystem scaffold's project file is byte-identical to one produced before this
    # feature existed and never references Azure at all.
    [string]$AzureDataProtectionBlobsVersion = '1.5.3',

    [string]$AzureDataProtectionKeysVersion = '1.6.3',

    [string[]]$TrustedProxies,

    [string[]]$TrustedNetworks,

    [string[]]$AllowedForwardedHosts,

    # --- Shared cookie authentication (Stage 2 interop) -----------------------------------------
    # Every companion below is REQUIRED when the switch is on and REJECTED when it is off. None
    # has a default: a default key ring location is the "the other host cannot decrypt this" bug in
    # disguise, and a default scheme or cookie name silently matches no real Framework host while
    # passing every test we could write. See D4/D6 in the design notes.
    [switch]$EnableSharedCookieAuth,

    # Where the shared Data Protection key ring lives. 'filesystem' is a directory both hosts can
    # read, protected by an X.509 certificate. 'azureblob' is an Azure Storage blob protected by a
    # key in Azure Key Vault -- the shape a multi-instance or multi-slot deployment needs, because
    # instances do not share a local disk.
    #
    # This has a default only because one topology has to be the unsurprising one for an on-premises
    # scaffold; it is NOT a safe fallback. Choosing the wrong provider produces an app that starts
    # and signs nobody in, exactly like every other companion here. The ValidateSet is kept in step
    # with marker-processor.ps1's provider map by Get-SharedKeyRingProviders, which Get-KeepKinds
    # resolves through and a test asserts against.
    [ValidateSet('filesystem', 'azureblob')]
    [string]$SharedKeyRingProvider = 'filesystem',

    # -- 'filesystem' provider only --
    [string]$SharedKeyRingPath,

    [string]$SharedCertificateThumbprint,

    # -- 'azureblob' provider only --
    [string]$SharedKeyRingUri,

    [string]$SharedKeyVaultKeyId,

    # -- required by both providers --
    [string]$SharedApplicationName,

    [string]$SharedCookieName,

    [string]$SharedCookieScheme,

    # --- Remote authentication (Stage 1 interop) ------------------------------------------------
    [switch]$EnableRemoteAuth,

    # Defaults to -OldAppUrl: the Framework app being proxied is the remote app by definition.
    [string]$RemoteAppUrl,

    [string]$RemoteAppApiKey,

    # Skip the closing 'dotnet build'. For callers that only want files on disk, and for tests
    # that assert on generated content rather than compilation.
    [switch]$SkipBuild,

    [string]$TemplatesRoot
)

$ErrorActionPreference = 'Stop'

# The marker processor is shared with the test suite: this script's mandatory parameters and
# straight-line flow make it impossible to dot-source without performing a real scaffold, so the
# parser lives in its own file rather than being reimplemented (and left to drift) in a test.
. (Join-Path $PSScriptRoot 'marker-processor.ps1')

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
# Anchored at BOTH ends, because the moniker is written verbatim into <TargetFramework> in the
# generated .csproj. A prefix match accepts 'net10.0&oops': it parses as major 10, scaffolds happily,
# prints a success banner, and leaves behind a project that is not well-formed XML -- the same failure
# the Version="..." attributes below are validated against. The optional trailing group is the platform
# moniker ('net10.0-windows', 'net10.0-windows10.0.19041.0'), which is legal and must keep working.
# Digit classes throughout this script are spelled [0-9], never \d: .NET's \d matches every Unicode
# decimal digit, so 'net10.０' (U+FF10) satisfied \d and reached <TargetFramework> as a moniker
# MSBuild cannot load. The major group survived only incidentally, because int.TryParse below rejects
# a full-width digit; the minor group is never parsed, so nothing else would have caught it.
$tfmMatch = [regex]::Match($TargetFramework, '^net(?<major>[0-9]+)\.(?<minor>[0-9]+)(?<platform>-[a-zA-Z0-9.]+)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
if (-not $tfmMatch.Success) {
    # A .NET Framework moniker here is a category error, not a typo: this scaffold creates the
    # ASP.NET Core front-end that proxies *to* the Framework app. Framework is the proxy's
    # backend, never its host, so say that rather than reporting a parse failure.
    if ($TargetFramework -match '^(net[1-4][0-9]{1,2}|v[1-4]\.[0-9])$') {
        Write-Error "TargetFramework '$TargetFramework' is a .NET Framework moniker. This scaffold creates the new ASP.NET Core proxy project, which cannot run on .NET Framework -- the Framework app is the proxy's backend (set via -OldAppUrl), not its host. Pass the TFM the new Core project will target, e.g. -TargetFramework net10.0."
        return
    }

    # A moniker that starts out valid and then carries trailing characters is a different mistake from
    # an unrecognizable one, and it is the dangerous one: it used to be accepted. Name the sink so the
    # operator can see why a character that looks harmless is not.
    if ($TargetFramework -match '^net[0-9]+\.[0-9]+') {
        Write-Error "TargetFramework '$TargetFramework' has unexpected characters after the moniker. It is written verbatim into <TargetFramework> in the generated .csproj, so a character such as '&', '<', '>' or '`"' produces a project MSBuild cannot load. Pass a bare moniker like 'net10.0', or a platform moniker like 'net10.0-windows'."
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

# --- Authentication interop validation ----------------------------------------------------------
# Fail fast, exactly like -TrustedProxies above. Every rule here exists because its silent
# alternative produces an app that starts, serves requests, and authenticates nobody -- there is no
# exception and no log entry, only a user who appears signed out. A wrong default is therefore
# strictly worse than a refusal.
if ($EnableSharedCookieAuth -and $EnableRemoteAuth) {
    Write-Error "-EnableSharedCookieAuth and -EnableRemoteAuth are mutually exclusive. Shared cookie authentication has both apps read one cookie; remote authentication has this app ask the .NET Framework app who the user is. Pick one -- see 'Authentication interop' in SKILL.md."
    return
}

$sharedCookieCommonCompanions = @{
    'SharedApplicationName' = $SharedApplicationName
    'SharedCookieName'      = $SharedCookieName
    'SharedCookieScheme'    = $SharedCookieScheme
}
# Companions owned by exactly one key ring provider. Each group is required by its own provider and
# REJECTED by every other, so '-SharedKeyRingProvider azureblob -SharedKeyRingPath C:\keys' is an
# error rather than a value that silently configures nothing -- the same rule the switch-less
# orphan check below applies, one level down.
$sharedCookieProviderCompanions = @{
    'filesystem' = [ordered]@{
        'SharedKeyRingPath'           = $SharedKeyRingPath
        'SharedCertificateThumbprint' = $SharedCertificateThumbprint
    }
    'azureblob'  = [ordered]@{
        'SharedKeyRingUri'    = $SharedKeyRingUri
        'SharedKeyVaultKeyId' = $SharedKeyVaultKeyId
    }
}
# Flattened, for the "supplied without -EnableSharedCookieAuth" check, which must fire on every
# companion regardless of which provider owns it.
$sharedCookieCompanions = @{}
foreach ($key in $sharedCookieCommonCompanions.Keys) { $sharedCookieCompanions[$key] = $sharedCookieCommonCompanions[$key] }
foreach ($group in $sharedCookieProviderCompanions.Values) {
    foreach ($key in $group.Keys) { $sharedCookieCompanions[$key] = $group[$key] }
}

$remoteAuthCompanions = @{
    'RemoteAppUrl'   = $RemoteAppUrl
    'RemoteAppApiKey' = $RemoteAppApiKey
}

# Parameter name -> the appsettings.json property it configures. Kept beside the companion map so a
# companion cannot be added to one without the other. Both the strip and the write below read it,
# and Set-/Remove-JsonStringProperty throw on any name the template does not carry.
$sharedCookieJsonKeys = @{
    'SharedKeyRingPath'           = 'KeyRingPath'
    'SharedCertificateThumbprint' = 'CertificateThumbprint'
    'SharedKeyRingUri'            = 'KeyRingUri'
    'SharedKeyVaultKeyId'         = 'KeyVaultKeyId'
}

# A companion supplied without its switch is rejected rather than ignored: silently dropping it
# leaves the operator believing auth was configured when no auth code was emitted at all.
if (-not $EnableSharedCookieAuth) {
    # -SharedKeyRingProvider is checked by name rather than by value because it is the one
    # shared-cookie parameter with a default, so an unbound value is indistinguishable from a
    # deliberate '-SharedKeyRingProvider filesystem'.
    $orphans = @($sharedCookieCompanions.Keys) + @('SharedKeyRingProvider') |
        Where-Object { $PSBoundParameters.ContainsKey($_) } | Sort-Object
    if ($orphans) {
        Write-Error "$(($orphans | ForEach-Object { "-$_" }) -join ', ') require -EnableSharedCookieAuth. Without the switch no shared-cookie code is emitted, so these values would configure nothing."
        return
    }
}
if (-not $EnableRemoteAuth) {
    $orphans = $remoteAuthCompanions.Keys | Where-Object { $PSBoundParameters.ContainsKey($_) } | Sort-Object
    if ($orphans) {
        Write-Error "$(($orphans | ForEach-Object { "-$_" }) -join ', ') require -EnableRemoteAuth. Without the switch no remote-authentication code is emitted, so these values would configure nothing."
        return
    }
}

if ($EnableSharedCookieAuth) {
    # A companion belonging to a provider that was not selected is rejected, not ignored -- exactly
    # like a companion supplied without the switch. Ignoring it would leave the operator holding a
    # -SharedKeyRingPath they believe is in force while the app persists its ring to a blob.
    $foreignCompanions = @()
    foreach ($provider in $sharedCookieProviderCompanions.Keys) {
        if ($provider -eq $SharedKeyRingProvider) { continue }
        $foreignCompanions += @($sharedCookieProviderCompanions[$provider].Keys | Where-Object { $PSBoundParameters.ContainsKey($_) })
    }
    if ($foreignCompanions) {
        Write-Error "$(($foreignCompanions | Sort-Object | ForEach-Object { "-$_" }) -join ', ') belong to a key ring provider other than '$SharedKeyRingProvider', which does not honour them. Pass -SharedKeyRingProvider for the topology you want, or drop these parameters."
        return
    }

    # Missing and empty are the same failure: -SharedKeyRingPath '' must not fall back to a local
    # per-app key ring, and -SharedCookieScheme '' must not fall back to Core's default "Cookies",
    # which matches no Katana AuthenticationType that was not deliberately named that.
    $requiredCompanions = @{}
    foreach ($key in $sharedCookieCommonCompanions.Keys) {
        $requiredCompanions[$key] = $sharedCookieCommonCompanions[$key]
    }
    foreach ($key in $sharedCookieProviderCompanions[$SharedKeyRingProvider].Keys) {
        $requiredCompanions[$key] = $sharedCookieProviderCompanions[$SharedKeyRingProvider][$key]
    }

    $missing = $requiredCompanions.Keys | Where-Object { [string]::IsNullOrWhiteSpace($requiredCompanions[$_]) } | Sort-Object
    if ($missing) {
        Write-Error "-EnableSharedCookieAuth with -SharedKeyRingProvider $SharedKeyRingProvider requires $(($missing | ForEach-Object { "-$_" }) -join ', '). These have no defaults on purpose: the cookie name and scheme must match the .NET Framework app exactly, and the key ring must be the one that app already uses. A default would produce an app that silently authenticates nobody. See README.SHAREDCOOKIE.md in the generated project."
        return
    }

    # Both azureblob companions become System.Uri while the generated app builds its host, so a
    # malformed value crashes at startup rather than at first sign-in. The scheme check is the part
    # that earns its keep: Uri.TryCreate accepts 'C:\keys\app' as an absolute file: URI, so an
    # operator who pastes a filesystem path into the blob provider would otherwise sail through
    # validation and get an app that persists its ring nowhere the other host can read.
    #
    # The well-formedness check is the same clause -OldAppUrl and -RemoteAppUrl carry, and it is here
    # for the same reason: 'https://acct.blob.core.windows.net/keys/ring\foo' is NOT well-formed but
    # DOES parse, and Uri silently normalizes the backslash to '/'. Without this clause the app
    # persists its key ring to a different blob than the operator named, which fails exactly like a
    # wrong topology -- at the first authenticated request, with nothing in any log.
    if ($SharedKeyRingProvider -eq 'azureblob') {
        $azureUriCompanions = @(
            @{ Name = 'SharedKeyRingUri';    Value = $SharedKeyRingUri;    What = 'the Azure Storage blob holding the key ring' }
            @{ Name = 'SharedKeyVaultKeyId'; Value = $SharedKeyVaultKeyId; What = 'the Azure Key Vault key protecting it' }
        )
        foreach ($companion in $azureUriCompanions) {
            $parsedUri = $null
            if (-not [uri]::IsWellFormedUriString($companion.Value, [System.UriKind]::Absolute) -or
                -not [uri]::TryCreate($companion.Value, [System.UriKind]::Absolute, [ref]$parsedUri) -or
                $parsedUri.Scheme -notin @('http', 'https')) {
                Write-Error "-$($companion.Name) must be a well-formed absolute http or https URI naming $($companion.What); '$($companion.Value)' is not. A filesystem path belongs to -SharedKeyRingProvider filesystem, not azureblob."
                return
            }
        }
    }
}

# The Azure package versions are read only when the azureblob key ring provider is selected, so
# passing them anywhere else configures nothing. Same rule as every other companion: reject rather
# than ignore.
$azurePackageVersionParameters = @('AzureDataProtectionBlobsVersion', 'AzureDataProtectionKeysVersion')
if (-not ($EnableSharedCookieAuth -and $SharedKeyRingProvider -eq 'azureblob')) {
    $orphanVersions = $azurePackageVersionParameters | Where-Object { $PSBoundParameters.ContainsKey($_) } | Sort-Object
    if ($orphanVersions) {
        Write-Error "$(($orphanVersions | ForEach-Object { "-$_" }) -join ', ') apply only to '-EnableSharedCookieAuth -SharedKeyRingProvider azureblob'. No Azure Data Protection package is added to the generated project otherwise, so these versions would configure nothing."
        return
    }
}

# Blank is how every other companion in this script spells "not supplied". An explicit empty version
# writes Version="" into the generated project, which pins nothing, still satisfies the
# package-presence check further down, and fails restore in the customer's project long after this
# script has printed a success banner. This has to cover *every* version parameter, not just the
# Azure pair: the pattern check below deliberately skips blank values (so an omitted parameter
# falling back to its default is not re-validated), which means blank would otherwise reach the
# attribute unchecked by either guard.
$allPackageVersionParameters = @('SystemWebAdaptersVersion', 'YarpVersion') + $azurePackageVersionParameters
foreach ($versionParameter in $allPackageVersionParameters) {
    if ($PSBoundParameters.ContainsKey($versionParameter) -and
        [string]::IsNullOrWhiteSpace($PSBoundParameters[$versionParameter])) {
        Write-Error "-$versionParameter was supplied but is blank. Omit it to take the version this script has verified against the feed, or pass a real version; an empty value emits Version=`"`" and fails restore in the generated project."
        return
    }
}

# -OldAppUrl is raw-substituted into launchSettings.json (and printed as the proxy target), so unlike
# every auth companion it never passes through a JSON escaper. A value containing '"' breaks the file
# outright; worse, a backslash sequence that happens to be a legal JSON escape is silently rewritten
# ('...\foo' becomes U+000C + 'oo'), so the file still parses and the proxy quietly points somewhere
# else. Requiring a well-formed absolute http/https URI rejects both: RFC well-formedness is what
# excludes the quote and the backslash (both are illegal unencoded in a URI), and the scheme check is
# what excludes a Windows path, which otherwise parses happily as an absolute file: URI.
$parsedOldAppUrl = $null
if (-not [uri]::IsWellFormedUriString($OldAppUrl, [System.UriKind]::Absolute) -or
    -not [uri]::TryCreate($OldAppUrl, [System.UriKind]::Absolute, [ref]$parsedOldAppUrl) -or
    $parsedOldAppUrl.Scheme -notin @('http', 'https')) {
    Write-Error "-OldAppUrl must be a well-formed absolute http or https URL (for example 'https://localhost:44300'). '$OldAppUrl' is not, and it is written verbatim into launchSettings.json, where a stray quote breaks the file and a backslash sequence can silently rewrite the proxy target."
    return
}

# Every version parameter is concatenated straight into a Version="..." XML attribute. '&', '<', '>'
# and '"' make the generated .csproj malformed, so restore never starts -- and the failure surfaces
# in the customer's project, long after this script has printed a success banner. Escaping would be
# worse than rejecting: Version="1.0.0&amp;oops" is well-formed XML carrying a version that does not
# exist. Require something NuGet could actually resolve.
# Each dot-separated identifier in the pre-release and build-metadata parts must be non-empty, which
# is what rules out '1.0.0-alpha.' and '1.0.0-alpha..beta'. Those contain no XML-hazardous character,
# so they produce a well-formed .csproj carrying a version NuGet cannot resolve -- the restore error
# this check exists to prevent, just reached by a different route than '&'.
# The digit classes are spelled [0-9] rather than \d on purpose: .NET's \d matches every Unicode
# decimal digit, so '\u{FF12}.3.0' (a full-width 2) satisfies \d, produces well-formed XML, and fails
# restore -- the same end state as '&', reached by a route that looks like a valid version.
$nugetVersionPattern = '^[0-9]+(\.[0-9]+){0,3}(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
foreach ($versionParameter in $allPackageVersionParameters) {
    $versionValue = (Get-Variable -Name $versionParameter -ValueOnly)
    if (-not [string]::IsNullOrWhiteSpace($versionValue) -and $versionValue -notmatch $nugetVersionPattern) {
        Write-Error "-$versionParameter value '$versionValue' is not a valid NuGet version. It is written verbatim into a Version=`"...`" attribute, so a character such as '&', '<', '>' or '`"' produces a .csproj that is not well-formed XML and cannot be restored."
        return
    }
}

if ($EnableRemoteAuth) {
    if ([string]::IsNullOrWhiteSpace($RemoteAppApiKey)) {
        Write-Error "-EnableRemoteAuth requires -RemoteAppApiKey. It must be the same value the .NET Framework app exposes as the 'RemoteAppApiKey' app setting."
        return
    }

    # System.Web adapters rejects a non-GUID API key on the first request it authenticates, not at
    # host start: AddRemoteAppServer registers the options with .ValidateDataAnnotations() and no
    # .ValidateOnStart(), and the only code that resolves them is the per-request module. Catching it
    # here turns a runtime failure in the customer's app into a parameter error in the scaffold --
    # which matters more precisely because the runtime failure is deferred: the Framework host starts
    # clean and looks healthy right up until the first user tries to sign in. The all-zero GUID parses
    # but is rejected just the same, so it has to be excluded explicitly.
    $parsedApiKey = [guid]::Empty
    if (-not [guid]::TryParse($RemoteAppApiKey, [ref]$parsedApiKey)) {
        Write-Error "-RemoteAppApiKey must be a GUID; '$RemoteAppApiKey' is not. System.Web adapters rejects a non-GUID key on the first request it authenticates, so the Framework host starts clean and then fails at the first sign-in. Generate one with [guid]::NewGuid()."
        return
    }
    if ($parsedApiKey -eq [guid]::Empty) {
        Write-Error "-RemoteAppApiKey cannot be the empty GUID. System.Web adapters rejects it just as it rejects a malformed key. Generate one with [guid]::NewGuid()."
        return
    }

    if (-not $PSBoundParameters.ContainsKey('RemoteAppUrl')) {
        $RemoteAppUrl = $OldAppUrl
    }
    if ([string]::IsNullOrWhiteSpace($RemoteAppUrl)) {
        Write-Error "-RemoteAppUrl cannot be empty. Omit it to default to -OldAppUrl ('$OldAppUrl'), which is the .NET Framework app this proxy fronts."
        return
    }

    # Same gate as -OldAppUrl and the azureblob companions. This value IS JSON-escaped on its way into
    # appsettings.json, so it cannot corrupt the file -- but the generated Program.cs does
    # new Uri(Configuration["RemoteApp:Url"]), and a pasted Windows path parses there as an absolute
    # file: URI. The app starts, and remote authentication fails at the first request against a target
    # that was never a server. Reject it here, where the parameter name is still in hand.
    $parsedRemoteAppUrl = $null
    if (-not [uri]::IsWellFormedUriString($RemoteAppUrl, [System.UriKind]::Absolute) -or
        -not [uri]::TryCreate($RemoteAppUrl, [System.UriKind]::Absolute, [ref]$parsedRemoteAppUrl) -or
        $parsedRemoteAppUrl.Scheme -notin @('http', 'https')) {
        Write-Error "-RemoteAppUrl must be a well-formed absolute http or https URL (for example 'https://localhost:44300'). '$RemoteAppUrl' is not: it is the address this proxy calls to authenticate each request, so a filesystem path or a scheme-less host cannot work even though it is written into appsettings.json without complaint."
        return
    }

    # The API key and the forwarded authenticate request both cross this link. Over plain HTTP to
    # anything but the loopback adapter they are readable on the wire, so say so once, here, rather
    # than leaving it to be discovered in production. Not an error: plain HTTP is normal in local
    # development, and the remote app's address is often not under the caller's control.
    $remoteUri = $null
    if ([System.Uri]::TryCreate($RemoteAppUrl, [System.UriKind]::Absolute, [ref]$remoteUri) -and
        $remoteUri.Scheme -eq 'http' -and -not $remoteUri.IsLoopback) {
        Write-Warning "-RemoteAppUrl '$RemoteAppUrl' uses plain HTTP to a non-loopback host. The API key and every forwarded authentication request will cross the network in cleartext. Use HTTPS before this reaches a shared or production environment."
    }

    # -SystemWebAdaptersVersion is checked above only for NuGet well-formedness, which is the right bar
    # everywhere else: it exists so an operator can pin around a bad package build, and neither the
    # no-auth nor the shared-cookie scaffold depends on behaviour that varies by adapters version.
    # Remote auth does. AddAuthenticationClient(isDefaultScheme: false) is what stops every request the
    # catch-all MapForwarder handles from making an authenticate round trip to the Framework app, and it
    # holds only because the adapters *also* register an internal sentinel scheme -- which denies .NET 7+
    # the lone scheme it would otherwise auto-promote to the default. Not every release does that.
    # Measured by registering the exact chain the templates emit and reading the scheme provider back:
    #
    #   2.3.0 -> schemes { __SystemWebAdapters_<guid>, Remote }, DefaultAuthenticateScheme <null>
    #   2.0.0 -> schemes { Remote },                             DefaultAuthenticateScheme "Remote"
    #
    # So on 2.0.0 the isDefaultScheme: false argument is accepted and silently inverted: the project
    # restores, builds and starts, and every forwarded request is authenticated remotely. Refuse rather
    # than scaffold a security control that is already off. This is a floor, not a pin -- newer versions
    # are allowed, because the failure being guarded is a downgrade below what this scaffold emits for.
    $minimumRemoteAuthAdaptersVersion = '2.3.0'

    # Compare the numeric core only. Blank cannot arrive here -- an explicitly blank version is
    # rejected above and the parameter's own default is not blank -- and the pattern check guarantees
    # 1-4 dot-separated [0-9]+ groups followed by an optional -prerelease and +build. So absent groups
    # are zero and every part parses, as bigint because [int] would overflow on a long-but-legal group
    # and throw where this is meant to reject cleanly. Build metadata is dropped before the pre-release
    # test, or the '-' inside '+sha-1' would read as a pre-release marker.
    $adaptersVersionCore = ($SystemWebAdaptersVersion -split '\+', 2)[0]
    $suppliedParts = [bigint[]](($adaptersVersionCore -split '-', 2)[0] -split '\.')
    $minimumParts = [bigint[]]($minimumRemoteAuthAdaptersVersion -split '\.')
    $versionComparison = 0
    for ($versionPart = 0; $versionPart -lt 4 -and $versionComparison -eq 0; $versionPart++) {
        $supplied = if ($versionPart -lt $suppliedParts.Count) { $suppliedParts[$versionPart] } else { [bigint]::Zero }
        $minimum = if ($versionPart -lt $minimumParts.Count) { $minimumParts[$versionPart] } else { [bigint]::Zero }
        $versionComparison = $supplied.CompareTo($minimum)
    }

    # A pre-release of the floor sorts below the floor, per SemVer: 2.3.0-preview.1 is not 2.3.0.
    if ($versionComparison -lt 0 -or ($versionComparison -eq 0 -and $adaptersVersionCore.Contains('-'))) {
        Write-Error "-EnableRemoteAuth requires -SystemWebAdaptersVersion $minimumRemoteAuthAdaptersVersion or newer; '$SystemWebAdaptersVersion' is older. The proxy registers the remote scheme with isDefaultScheme: false so that requests handled by the catch-all forwarder are not each authenticated against the .NET Framework app. That depends on the adapters registering an internal sentinel scheme, which older releases do not: on 2.0.0 the argument is accepted and 'Remote' becomes the default scheme anyway, so every forwarded request makes an authenticate round trip and nothing reports it. Scaffold with $minimumRemoteAuthAdaptersVersion or newer, or use -EnableSharedCookieAuth, which does not depend on this behaviour."
        return
    }
}

$anyAuth = $EnableSharedCookieAuth -or $EnableRemoteAuth

# Resolve paths.
#
# -LiteralPath and .ProviderPath are both load-bearing here. Without -LiteralPath, a directory whose
# name legally contains '[' or ']' is read as a wildcard and resolves to nothing; the failure then
# surfaces several lines later as "Cannot bind argument to parameter 'Path' because it is an empty
# string", naming neither the parameter nor the path. Without .ProviderPath, a UNC path resolves to
# 'Microsoft.PowerShell.Core\FileSystem::\\server\share\...' and every System.IO call in this script
# rejects it with "The given path's format is not supported."
$resolvedOldProject = Resolve-Path -LiteralPath $OldProjectPath -ErrorAction SilentlyContinue
if (-not $resolvedOldProject) {
    Write-Error "-OldProjectPath '$OldProjectPath' could not be resolved. Pass the full path to the existing .NET Framework project file, for example 'C:\src\OldApp\OldApp.csproj'."
    return
}
$OldProjectPath = $resolvedOldProject.ProviderPath

# -OldProjectPath must be the project *file*, not the directory holding it. A directory resolves and
# splits without complaint, so without this guard the scaffold treats the directory as the project,
# creates the new project one level too high, edits the customer's solution to point at it, and only
# then fails on the old-project read - leaving a wrongly-placed project and a modified solution
# behind. With a trailing separator it is worse: GetFileNameWithoutExtension returns '', so the
# default name becomes '.Core' and a project literally named '.Core' is added to the solution.
if (-not (Test-Path -LiteralPath $OldProjectPath -PathType Leaf) -or
    [System.IO.Path]::GetExtension($OldProjectPath) -notlike '.*proj') {
    Write-Error "-OldProjectPath must be the existing project file itself (for example 'C:\src\OldApp\OldApp.csproj'). '$OldProjectPath' is not a project file, and scaffolding from a directory would place the new project in the wrong folder."
    return
}

$resolvedSolution = Resolve-Path -LiteralPath $SolutionPath -ErrorAction SilentlyContinue
if (-not $resolvedSolution) {
    Write-Error "-SolutionPath '$SolutionPath' could not be resolved. Pass the full path to the existing .sln or .slnx file."
    return
}
$SolutionPath = $resolvedSolution.ProviderPath

$OldProjectDir = Split-Path $OldProjectPath -Parent
$ParentDir = Split-Path $OldProjectDir -Parent

if (-not $NewProjectName) {
    $NewProjectName = [System.IO.Path]::GetFileNameWithoutExtension($OldProjectPath) + '.Core'
}

# -NewProjectName reaches three sinks with three different failure modes, so validate once here rather
# than at each one -- and before Join-Path, so a rejected name creates nothing.
#   1. A directory name. 'Contoso\Legacy' is not exotic, it is how people write project names, and
#      Join-Path silently turns it into a NESTED directory. '..' is worse: it resolves out of the
#      parent entirely.
#   2. The .csproj filename.
#   3. A profile key in launchSettings.json, raw-substituted with no JSON escaper in the path -- the
#      same hazard -OldAppUrl documents. A backslash either breaks the parse outright ('\P' is not a
#      legal escape) or, when it happens to form one, is silently rewritten: 'Foo\nBar' becomes
#      'Foo' + U+000A + 'Bar', and the profile no longer matches the folder.
# GetInvalidFileNameChars covers the whole JSON hazard set as a side effect: '"', '\' and every C0
# control are in it, alongside the path separators and ':'.
if ($NewProjectName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    Write-Error "-NewProjectName '$NewProjectName' contains a character that cannot appear in a file name. It becomes a folder name, a .csproj file name, and a profile key in launchSettings.json, so a path separator would nest the project inside an unintended folder and a backslash or quote would corrupt that file. Pass a plain name such as 'Contoso.Legacy.Core'."
    return
}

# Windows silently strips a trailing dot or surrounding whitespace from a directory name, so these
# scaffold successfully and leave a folder whose name no longer matches the .csproj inside it or the
# launchSettings profile that names it. '.' and '..' are caught here too.
if ($NewProjectName -ne $NewProjectName.Trim() -or $NewProjectName.EndsWith('.')) {
    Write-Error "-NewProjectName '$NewProjectName' starts or ends with whitespace or ends with '.'. Windows strips those from a folder name, so the project folder would not match the .csproj file or the launchSettings.json profile named after it. Pass a plain name such as 'Contoso.Legacy.Core'."
    return
}

# Validate project name uniqueness
$NewProjectDir = Join-Path $ParentDir $NewProjectName
$NewProjectPath = Join-Path $NewProjectDir "$NewProjectName.csproj"

if (Test-Path -LiteralPath $NewProjectDir) {
    Write-Error "Directory already exists: $NewProjectDir. Choose a different project name."
    return
}

# Check solution for name conflict.
#
# Two spellings, because this guard has to hold for both solution formats and they share no token.
# A .sln records the project name as a bare quoted field (Project(...) = "Legacy.Core", ...), while
# a .slnx records only <Project Path="dir/Legacy.Core.csproj" /> and drops the name entirely -- so
# matching the bare name alone made this guard a silent no-op on every .slnx. The file name is the
# only token both formats carry, and it is anchored to a separator or the opening quote so that
# 'Legacy.Core.csproj' cannot be matched inside 'My.Legacy.Core.csproj'.
#
# What the guard is actually protecting against, verified rather than assumed: 'dotnet sln add'
# does NOT refuse a name that already exists at a different path. It adds a second project with
# the same name and exits 0, on both formats, and the resulting solution still builds. So the
# collision is never reported by the tooling -- the operator simply ends up with two projects
# called the same thing and no indication anything went wrong. On .sln this guard already caught
# the typo before that happened; on .slnx it did not, and that inconsistency is what is fixed here.
$slnCheck = Get-Content -LiteralPath $SolutionPath -Raw
$projectNameToken = [regex]::Escape("`"$NewProjectName`"")
$projectFileToken = '[\\/"]' + [regex]::Escape("$NewProjectName.csproj") + '"'
if ($slnCheck -match $projectNameToken -or $slnCheck -match $projectFileToken) {
    Write-Error "A project named '$NewProjectName' already exists in the solution. Choose a different name."
    return
}

# Locate template folder
if (-not $TemplatesRoot) {
    $TemplatesRoot = Join-Path $PSScriptRoot 'tmpl'
}

$templateKey = if ($ProjectType -eq 'WebAPI') { 'webapi' } else { 'mvc' }
$templateDir = Join-Path $TemplatesRoot $templateKey

if (-not (Test-Path -LiteralPath $templateDir)) {
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
# Deliberately excludes -RemoteAppApiKey. Everything printed here can land in a CI log.
if ($EnableSharedCookieAuth) {
    Write-Host "  Auth interop: shared cookie" -ForegroundColor Cyan
    Write-Host "    Key ring    : $SharedKeyRingProvider"
    if ($SharedKeyRingProvider -eq 'azureblob') {
        Write-Host "      Blob      : $SharedKeyRingUri"
        Write-Host "      Vault key : $SharedKeyVaultKeyId"
    } else {
        Write-Host "      Path      : $SharedKeyRingPath"
        Write-Host "      Cert      : $SharedCertificateThumbprint"
    }
    Write-Host "    App name    : $SharedApplicationName"
    Write-Host "    Cookie name : $SharedCookieName"
    Write-Host "    Scheme      : $SharedCookieScheme"
}
if ($EnableRemoteAuth) {
    Write-Host "  Auth interop: remote authentication" -ForegroundColor Cyan
    Write-Host "    Remote app  : $RemoteAppUrl"
    Write-Host "    API key     : (not shown)"
}

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

function Copy-TemplateWithSubstitutions {
    param([string]$Source, [string]$Destination, [hashtable]$Vars, [string[]]$KeepKinds)

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

        # Read, substitute, write.
        # One pass over the template, not one pass per placeholder: sequential String.Replace calls
        # re-scan text that a previous replacement inserted, so any operator value containing a
        # placeholder token gets substituted a second time. -NewProjectName 'Foo$HttpsPort$Bar'
        # produced the folder 'Foo$HttpsPort$Bar' and the launchSettings profile key 'Foo7915Bar',
        # leaving the profile pointing at a project that does not exist. Worse, hashtable
        # enumeration order is unspecified, so whether it happened at all depended on hash order.
        # A single MatchEvaluator pass consumes each token exactly once and leaves unknown
        # '$Something$' text alone.
        $content = [System.IO.File]::ReadAllText($file.FullName)
        $content = [regex]::Replace($content, '\$[A-Za-z][A-Za-z0-9]*\$', {
            param($match)
            if ($Vars.ContainsKey($match.Value)) { $Vars[$match.Value] } else { $match.Value }
        })

        # launchSettings.json templates author "sslPort" as a quoted placeholder
        # (e.g. "sslPort": "$NewSslPort$") so the template itself is valid JSON;
        # unquote the substituted value here since IIS Express expects sslPort
        # as a JSON number, not a string.
        $content = $content -replace '("sslPort":\s*)"([0-9]+)"', '$1$2'

        # Strip template markers (and, for kinds not kept, the blocks they delimit) from Program.cs.
        if ($relativePath -like '*Program.cs') {
            $content = Remove-TemplateMarkers -Content $content -KeepKinds $KeepKinds
        }

        # appsettings.json ships configuration sections that only the corresponding Program.cs code
        # binds. Leaving a section behind when its code was stripped is worse than omitting it: an
        # operator reads a populated "SharedDP" or "ForwardedHeaders" block as "this is configured"
        # when nothing reads it.
        #
        # These four predicates are INDEPENDENT on purpose. Nesting the auth strips inside the
        # hardening one would make them dead code on net10.0 -- the default and recommended TFM --
        # so the auth sections would ship in every scaffold with both switches off.
        #
        # Each regex assumes its section is a flat object followed by another property (hence the
        # trailing comma), so verify the removal rather than trusting it: a silent no-op here is
        # exactly the fail-open these strips exist to prevent.
        if ($relativePath -like '*appsettings.json') {
            $sectionsToStrip = [System.Collections.Generic.List[string]]::new()
            if ($KeepKinds -notcontains 'hardening') { $sectionsToStrip.Add('ForwardedHeaders') }
            if ($KeepKinds -notcontains 'sharedcookie') {
                $sectionsToStrip.Add('SharedDP')
                $sectionsToStrip.Add('SharedCookie')
            }
            if ($KeepKinds -notcontains 'remoteauth') { $sectionsToStrip.Add('RemoteApp') }

            foreach ($section in $sectionsToStrip) {
                $content = [regex]::Replace($content, '\s*"' + [regex]::Escape($section) + '":\s*\{[^{}]*\},', '')
                if ($content -match ('"' + [regex]::Escape($section) + '"')) {
                    throw "Failed to strip the '$section' section from $relativePath. The template's JSON shape changed (the section must be a flat object followed by another property); fix the strip rather than shipping a configuration surface no code reads."
                }
            }
        }

        [System.IO.File]::WriteAllText($destFile, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "    -> $relativePath"
    }
}

$keepKinds = Get-KeepKinds -HardeningSupported $hardeningSupported `
    -EnableSharedCookieAuth ([bool]$EnableSharedCookieAuth) `
    -EnableRemoteAuth ([bool]$EnableRemoteAuth) `
    -SharedKeyRingProvider $SharedKeyRingProvider

Copy-TemplateWithSubstitutions -Source $templateDir -Destination $NewProjectDir -Vars $substitutions -KeepKinds $keepKinds
Write-Host "  Files created from template." -ForegroundColor Green

# The handoff notes live in tmpl/auth/, OUTSIDE $templateDir, because Copy-TemplateWithSubstitutions
# copies every file under tmpl/<mvc|webapi>/ recursively -- a note placed there would land in every
# scaffold regardless of switch. Resolved from $PSScriptRoot rather than $TemplatesRoot so a caller
# that repoints -TemplatesRoot at a copied template pair still gets the note instead of silently
# scaffolding an auth project with no instructions for the .NET Framework half.
if ($anyAuth) {
    $authNoteName = if ($EnableSharedCookieAuth) { 'README.SHAREDCOOKIE.md' } else { 'README.REMOTEAUTH.md' }
    $authNoteSource = Join-Path (Join-Path (Join-Path $PSScriptRoot 'tmpl') 'auth') $authNoteName
    if (-not (Test-Path -LiteralPath $authNoteSource)) {
        throw "Authentication handoff note not found: $authNoteSource. The generated project configures only the ASP.NET Core half of the interop, so scaffolding without the note would leave the caller with no instructions for the .NET Framework half."
    }

    $authNoteDest = Join-Path $NewProjectDir $authNoteName
    [System.IO.File]::WriteAllText($authNoteDest, [System.IO.File]::ReadAllText($authNoteSource), [System.Text.UTF8Encoding]::new($false))
    if (-not (Test-Path -LiteralPath $authNoteDest)) {
        throw "Failed to write the authentication handoff note to $authNoteDest."
    }
    Write-Host "    -> $authNoteName" -ForegroundColor Green
}

if (-not $hardeningSupported) {
    # The authentication half of this sentence is conditional: 'authpipeline' (app.UseAuthentication)
    # survives a sub-net10 scaffold whenever an auth path is on, so claiming it was omitted would be
    # false in exactly the configuration a user is most likely to be checking.
    $authClause = if ($anyAuth) {
        "The forwarded-headers and Kestrel TLS hardening were omitted, and appsettings.json has no ForwardedHeaders section. The authentication interop you requested WAS emitted and is unaffected."
    } else {
        "The forwarded-headers, Kestrel TLS, and authentication hardening were omitted, and appsettings.json has no ForwardedHeaders section."
    }
    Write-Warning "Scaffolded WITHOUT proxy security hardening: it requires net10.0 or later because it uses ForwardedHeadersOptions.KnownIPNetworks (introduced in .NET 10), and '$TargetFramework' is older. $authClause This proxy is NOT a hardened security boundary. Retarget to net10.0 and re-scaffold, or add the hardening by hand -- see 'Targeting below net10.0' in SKILL.md."
}

# The Azure Data Protection packages are ADDED to the generated .csproj rather than shipped in the
# template and stripped when unused, so the far more common filesystem scaffold still produces a
# project file byte-identical to one from before this feature existed. Azure.Identity is
# deliberately absent: it arrives transitively through both packages, so pinning a third version
# here would be one more thing to keep current in exchange for nothing.
if ($EnableSharedCookieAuth -and $SharedKeyRingProvider -eq 'azureblob') {
    $projectXml = [System.IO.File]::ReadAllText($NewProjectPath)

    # Exactly one ItemGroup is a property of the template, and the insertion is only unambiguous
    # while it holds. If a second one is ever added, whoever adds it has to decide which group the
    # packages belong in -- so fail loudly here rather than silently picking the first.
    $itemGroupCloses = [regex]::Matches($projectXml, '</ItemGroup>')
    if ($itemGroupCloses.Count -ne 1) {
        throw "Expected exactly one </ItemGroup> in '$NewProjectPath' but found $($itemGroupCloses.Count); refusing to guess where the Azure Data Protection package references belong."
    }

    $nl = if ($projectXml.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lineStart = $projectXml.LastIndexOf("`n", $itemGroupCloses[0].Index) + 1
    $azurePackages = @(
        '    <PackageReference Include="Azure.Extensions.AspNetCore.DataProtection.Blobs" Version="' + $AzureDataProtectionBlobsVersion + '" />'
        '    <PackageReference Include="Azure.Extensions.AspNetCore.DataProtection.Keys" Version="' + $AzureDataProtectionKeysVersion + '" />'
    )
    $projectXml = $projectXml.Insert($lineStart, ($azurePackages -join $nl) + $nl)

    # Verify rather than assume: without both packages the generated project does not compile at
    # all, and a scaffold that reports success and leaves a broken project behind is worse than one
    # that fails here.
    foreach ($packageId in @('Azure.Extensions.AspNetCore.DataProtection.Blobs', 'Azure.Extensions.AspNetCore.DataProtection.Keys')) {
        if ($projectXml -notmatch [regex]::Escape("Include=`"$packageId`"")) {
            throw "Failed to add a PackageReference for '$packageId' to '$NewProjectPath'; the generated project would not compile against the azureblob key ring provider."
        }
    }

    [System.IO.File]::WriteAllText($NewProjectPath, $projectXml, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Added Azure Data Protection package references for the azureblob key ring provider." -ForegroundColor Green
}

# Thread operator-supplied trusted proxy/network values into the generated appsettings.json.
# Uses targeted string replacement + UTF8-no-BOM write (not ConvertTo-Json) to preserve the
# template's key order and formatting and to avoid PowerShell 5.1 BOM issues. When a parameter
# is omitted, the template's secure loopback defaults remain in place.
function ConvertTo-JsonArrayLiteral {
    param([string[]]$Values)
    if (-not $Values -or $Values.Count -eq 0) { return '[]' }
    # Delegate per item rather than repeating the escape inline: the scalar helper is the one that
    # knows about control characters, and a second copy of the escape here is how the array path came
    # to accept a raw tab long after the scalar path stopped.
    $items = $Values | ForEach-Object { ConvertTo-JsonStringLiteral -Value $_ }
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

# Scalar siblings of the two functions above. These are separate rather than reused because
# Set-JsonArrayProperty's regex matches only '[...]' -- pointing it at a string property throws on
# the IsMatch guard, and ConvertTo-JsonArrayLiteral would write '[ "value" ]' into a field bound as
# a string. Same escaping, same MatchEvaluator, different value shape.
function ConvertTo-JsonStringLiteral {
    param([string]$Value)
    # Order matters: escape backslashes first, or the backslash introduced by escaping a quote
    # would itself be escaped. This is the whole point of routing auth values through here --
    # a plain Windows path like C:\keys\app produces the illegal JSON escape \k, and the failure
    # surfaces only when the customer's app binds its configuration, long after 'dotnet build'
    # reported success (it never parses appsettings.json).
    $escaped = $Value -replace '\\', '\\' -replace '"', '\"'

    # Control characters have to go too, and this is easy to miss because PowerShell's own
    # ConvertFrom-Json accepts them: a raw tab or newline inside a string is legal to that parser
    # and illegal to System.Text.Json, which is what ASP.NET Core actually binds appsettings.json
    # with. Left unescaped, a pasted value containing one produces a file that every check here
    # calls valid and that kills the customer's host at startup.
    $controlEvaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        switch ([int]$m.Value[0]) {
            8       { '\b' }
            9       { '\t' }
            10      { '\n' }
            12      { '\f' }
            13      { '\r' }
            default { '\u{0:x4}' -f [int]$m.Value[0] }
        }
    }

    return '"' + [regex]::Replace($escaped, '[\x00-\x1F]', $controlEvaluator) + '"'
}

function Set-JsonStringProperty {
    param(
        [string]$Json,
        [string]$PropertyName,
        [string]$Literal
    )
    $regex = [regex]::new('("' + [regex]::Escape($PropertyName) + '":\s*)"[^"]*"')
    $matchCount = $regex.Matches($Json).Count
    if ($matchCount -eq 0) {
        throw "Could not find the '$PropertyName' string property in appsettings.json; authentication interop configuration was not applied."
    }
    # Writing the first of several same-named properties would silently configure the wrong section,
    # and the result is still valid JSON that builds and starts. Refuse instead.
    if ($matchCount -gt 1) {
        throw "Found $matchCount '$PropertyName' string properties in appsettings.json; refusing to guess which one to configure. Rename the colliding property or extend this script to take a section-qualified path."
    }
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $m.Groups[1].Value + $Literal }
    return $regex.Replace($Json, $evaluator, 1)
}

function Remove-JsonStringProperty {
    param(
        [string]$Json,
        [string]$PropertyName
    )
    # Matches the whole line including its trailing comma and newline. Every removable property sits
    # ahead of one that is always kept ("ApplicationName" closes the SharedDP section), so a trailing
    # comma always exists; removing a LAST property would leave a dangling comma and invalid JSON.
    # That ordering is a template invariant a static test pins, and the throw below is what fires if
    # someone reorders the section without reading this.
    $regex = [regex]::new('[ \t]*"' + [regex]::Escape($PropertyName) + '":\s*"[^"]*",\r?\n')
    $matchCount = $regex.Matches($Json).Count
    if ($matchCount -eq 0) {
        throw "Could not find a comma-terminated '$PropertyName' string property in appsettings.json; the unused key ring provider's configuration keys were not removed. If '$PropertyName' has become the last property in its section, move it ahead of one that is always kept."
    }
    if ($matchCount -gt 1) {
        throw "Found $matchCount '$PropertyName' string properties in appsettings.json; refusing to guess which one to remove."
    }
    return $regex.Replace($Json, '', 1)
}

if ($PSBoundParameters.ContainsKey('TrustedProxies') -or $PSBoundParameters.ContainsKey('TrustedNetworks') -or $PSBoundParameters.ContainsKey('AllowedForwardedHosts')) {
    $appsettingsPath = Join-Path $NewProjectDir 'appsettings.json'
    if (-not (Test-Path -LiteralPath $appsettingsPath)) {
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

# Auth values go through Set-JsonStringProperty rather than the $substitutions map, because that
# map is applied by a raw String.Replace over every copied file with no JSON escaping at all.
if ($anyAuth) {
    $appsettingsPath = Join-Path $NewProjectDir 'appsettings.json'
    if (-not (Test-Path -LiteralPath $appsettingsPath)) {
        throw "Cannot apply authentication interop configuration: '$appsettingsPath' was not found."
    }

    $appsettingsJson = [System.IO.File]::ReadAllText($appsettingsPath)

    if ($EnableSharedCookieAuth) {
        # The template ships the keys for BOTH key ring topologies. The ones the chosen provider does
        # not use are REMOVED, not left blank: a leftover empty "KeyRingPath" beside a configured
        # "KeyRingUri" reads as a setting someone forgot to fill in, and filling it in does nothing
        # at all, because with the azureblob chain emitted no line of the app ever reads it.
        foreach ($provider in ($sharedCookieProviderCompanions.Keys | Sort-Object)) {
            if ($provider -eq $SharedKeyRingProvider) { continue }
            foreach ($parameterName in $sharedCookieProviderCompanions[$provider].Keys) {
                $appsettingsJson = Remove-JsonStringProperty -Json $appsettingsJson -PropertyName $sharedCookieJsonKeys[$parameterName]
            }
        }

        foreach ($parameterName in $sharedCookieProviderCompanions[$SharedKeyRingProvider].Keys) {
            $appsettingsJson = Set-JsonStringProperty -Json $appsettingsJson `
                -PropertyName $sharedCookieJsonKeys[$parameterName] `
                -Literal (ConvertTo-JsonStringLiteral $sharedCookieProviderCompanions[$SharedKeyRingProvider][$parameterName])
        }

        $appsettingsJson = Set-JsonStringProperty -Json $appsettingsJson -PropertyName 'ApplicationName' -Literal (ConvertTo-JsonStringLiteral $SharedApplicationName)
        # Each of these property names is unique across the whole file, and 'Name' cannot match
        # 'ApplicationName' because the pattern anchors on the opening quote. That is an invariant of
        # the template, not luck — Set-JsonStringProperty throws if it is ever broken.
        $appsettingsJson = Set-JsonStringProperty -Json $appsettingsJson -PropertyName 'Name' -Literal (ConvertTo-JsonStringLiteral $SharedCookieName)
        $appsettingsJson = Set-JsonStringProperty -Json $appsettingsJson -PropertyName 'Scheme' -Literal (ConvertTo-JsonStringLiteral $SharedCookieScheme)
    }

    if ($EnableRemoteAuth) {
        $appsettingsJson = Set-JsonStringProperty -Json $appsettingsJson -PropertyName 'Url' -Literal (ConvertTo-JsonStringLiteral $RemoteAppUrl)
        $appsettingsJson = Set-JsonStringProperty -Json $appsettingsJson -PropertyName 'ApiKey' -Literal (ConvertTo-JsonStringLiteral $RemoteAppApiKey)
    }

    [System.IO.File]::WriteAllText($appsettingsPath, $appsettingsJson, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Applied authentication interop configuration to appsettings.json." -ForegroundColor Green

    if ($EnableRemoteAuth) {
        Write-Warning "The remote-app API key was written to appsettings.json in plain text. That is fine for local development only. Before committing, move it out: dotnet user-secrets init; dotnet user-secrets set ""RemoteApp:ApiKey"" ""<the GUID>"" -- run both from '$NewProjectDir'."
    }
}

Write-Host "  Adding to solution..." -ForegroundColor Cyan
dotnet sln $SolutionPath add $NewProjectPath
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to add '$NewProjectPath' to solution '$SolutionPath'. The project directory '$NewProjectDir' was already created and is left in place; delete it before retrying, or add the project to the solution manually."; return }
Write-Host "  Added to solution." -ForegroundColor Green

# Find new project GUID and link old project
$slnContent = Get-Content -LiteralPath $SolutionPath -Raw
$escapedName = [regex]::Escape($NewProjectName)
$slnMatch = [regex]::Match($slnContent, "Project\([^)]+\)\s*=\s*`"$escapedName`"\s*,\s*`"[^`"]+`"\s*,\s*`"\{([0-9A-Fa-f-]+)\}`"")
$newProjectGuid = if ($slnMatch.Success) { $slnMatch.Groups[1].Value } else { $null }

if ($newProjectGuid) {
    Write-Host "  New project GUID: $newProjectGuid" -ForegroundColor Cyan
    # Get-Content -Raw would read this with Windows PowerShell 5.1's default encoding, which is
    # the ANSI codepage for any file without a BOM. A UTF-8-no-BOM project file - the modern
    # default - containing a single non-ASCII character then round-trips through the UTF-8 write
    # below as mojibake: '(c)' (C2 A9) is read as two ANSI characters and written back as C3 82
    # C2 A9. That silently corrupts a file the customer owns, in a step whose only job is to add
    # one property. Decode strictly as UTF-8 first and fall back to ANSI only when that fails,
    # which is exactly the case where the file really is legacy-encoded.
    $oldBytes = [System.IO.File]::ReadAllBytes($OldProjectPath)
    $oldHadBom = $oldBytes.Length -ge 3 -and $oldBytes[0] -eq 0xEF -and $oldBytes[1] -eq 0xBB -and $oldBytes[2] -eq 0xBF
    $oldBomOffset = if ($oldHadBom) { 3 } else { 0 }
    # GetEncoding(0) is the ANSI codepage, NOT [System.Text.Encoding]::Default. Default is the ANSI
    # codepage only on Windows PowerShell 5.1; on PowerShell 7 (.NET Core) it is UTF-8, so it would
    # re-decode the very bytes that just failed the strict UTF-8 attempt below and turn each one into
    # U+FFFD - which the write further down would then persist over the customer's file, corrupting
    # exactly the legacy-encoded project this fallback exists to preserve. No host is pinned for this
    # script, so both are reachable.
    $ansiEncoding = [System.Text.Encoding]::GetEncoding(0)
    $oldWasAnsi = $false
    try {
        $oldCsproj = ([System.Text.UTF8Encoding]::new($false, $true)).GetString($oldBytes, $oldBomOffset, $oldBytes.Length - $oldBomOffset)
    } catch [System.Text.DecoderFallbackException] {
        # Decodes the whole array, BOM bytes included, unlike the UTF-8 path above. That is
        # deliberate: the ANSI encoding emits no preamble, so a BOM skipped here would be dropped by
        # the write rather than preserved. Round-tripped through ANSI the three bytes are 'i>>?',
        # which re-encodes to EF BB BF unchanged.
        $oldCsproj = $ansiEncoding.GetString($oldBytes)
        $oldWasAnsi = $true
    }
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
            # Write back in the encoding the file already used. Unconditionally emitting UTF-8-no-BOM
            # would rewrite every byte of a BOM'd or ANSI project file, turning a one-property edit
            # into a whole-file change in the customer's next diff.
            $oldEncoding = if ($oldWasAnsi) { $ansiEncoding } else { [System.Text.UTF8Encoding]::new($oldHadBom) }
            [System.IO.File]::WriteAllText($OldProjectPath, $oldCsproj, $oldEncoding)
            Write-Host "  Linked old project via _MigrateToProjectGuid." -ForegroundColor Green
        } else {
            Write-Warning "Could not find a </PropertyGroup> in '$OldProjectPath' to add _MigrateToProjectGuid to. Add <_MigrateToProjectGuid>$newProjectGuid</_MigrateToProjectGuid> manually."
        }
    }
} else {
    # .slnx does not record project GUIDs at all -- the format deliberately drops them -- so the
    # match above can never succeed there. Saying "add it manually" without naming a GUID is not
    # actionable, so distinguish the two causes and give the caller something to act on.
    if ([System.IO.Path]::GetExtension($SolutionPath) -eq '.slnx') {
        $generatedGuid = [guid]::NewGuid().ToString().ToUpperInvariant()
        Write-Warning "'$SolutionPath' is a .slnx solution, which does not store project GUIDs, so the old project could not be linked automatically. Add <_MigrateToProjectGuid>$generatedGuid</_MigrateToProjectGuid> to a PropertyGroup in '$OldProjectPath', and add <ProjectGuid>{$generatedGuid}</ProjectGuid> to '$NewProjectPath' so the two agree."
    } else {
        Write-Warning "Could not find a GUID for '$NewProjectName' in '$SolutionPath', so the old project was not linked. Add <_MigrateToProjectGuid> to '$OldProjectPath' manually, using the GUID the solution records for the new project."
    }
}

$buildFailed = $false
if ($SkipBuild) {
    Write-Host "  Skipping build (-SkipBuild)." -ForegroundColor Yellow
} else {
    Write-Host "  Building new project..." -ForegroundColor Cyan
    dotnet build $NewProjectPath --nologo -v:q
    if ($LASTEXITCODE -eq 0) { Write-Host "  Build succeeded." -ForegroundColor Green }
    else { $buildFailed = $true; Write-Warning "Build failed. Check the project configuration." }
}

# The project files are on disk and are still worth keeping even when the build fails, so this is
# not a fatal error. But announcing "Scaffolding complete" straight after "Build failed" reads as
# success to both a human and an agent scanning stdout, so the banner has to reflect what happened.
if ($buildFailed) {
    Write-Host "`nScaffolding finished WITH A FAILED BUILD: $NewProjectPath" -ForegroundColor Red
    Write-Host "The project files were created, but the project does not compile yet. Fix the build" -ForegroundColor Red
    Write-Host "before continuing; do not treat this scaffold as done." -ForegroundColor Red
} else {
    Write-Host "`nScaffolding complete: $NewProjectPath" -ForegroundColor Green
}
Write-Host "ProxyTo: $OldAppUrl (in launchSettings.json)" -ForegroundColor Cyan
if ($anyAuth) {
    $authNoteName = if ($EnableSharedCookieAuth) { 'README.SHAREDCOOKIE.md' } else { 'README.REMOTEAUTH.md' }
    Write-Host "`nNEXT STEP: only the ASP.NET Core half of the authentication interop is configured." -ForegroundColor Yellow
    if ($EnableSharedCookieAuth) {
        Write-Host "Until the .NET Framework half is wired, users will simply appear signed out." -ForegroundColor Yellow
    }
    else {
        Write-Host "Until the .NET Framework half is wired, the authentication round trip to the old app will fail." -ForegroundColor Yellow
        Write-Host "Remote auth is registered as a non-default scheme: a plain [Authorize] returns a 500. Use" -ForegroundColor Yellow
        Write-Host "[Authorize(AuthenticationSchemes = RemoteAppAuthenticationDefaults.AuthenticationScheme)]." -ForegroundColor Yellow
    }
    Write-Host "See $authNoteName in the new project." -ForegroundColor Yellow
}
