param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("pre", "post")]
    [string]$Phase,
    [string]$HookInputJson
)

function Write-Success {
    [Console]::Out.WriteLine('{"continue":true}')
    exit 0
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$name]) {
            $value = $Object.PSObject.Properties[$name].Value
            if ($null -ne $value) {
                return $value
            }
        }
    }

    return $null
}

function Get-TimestampText {
    param([object]$Value)

    # PowerShell 7 parses ISO JSON timestamps into dates; preserve their UTC offset.
    if ($Value -is [DateTime] -or $Value -is [DateTimeOffset]) {
        return $Value.ToString("o")
    }

    return [string]$Value
}

function Get-NormalizedToolCalls {
    param([object]$Payload)

    $inputEnvelope = Get-PropertyValue $Payload @("input")
    if ($null -eq $inputEnvelope) {
        $inputEnvelope = $Payload
    }

    $batchedCalls = Get-PropertyValue $inputEnvelope @("toolCalls", "tool_calls")
    if ($null -ne $batchedCalls) {
        $sessionId = [string](Get-PropertyValue $inputEnvelope @("sessionId", "session_id"))
        $workingDirectory = [string](Get-PropertyValue $inputEnvelope @("cwd", "workingDirectory", "working_directory"))
        foreach ($call in @($batchedCalls)) {
            [pscustomobject]@{
                SessionId = $sessionId
                WorkingDirectory = $workingDirectory
                EventId = [string](Get-PropertyValue $call @("id", "tool_use_id", "toolUseId", "tool_call_id", "toolCallId"))
                ToolName = [string](Get-PropertyValue $call @("name", "toolName", "tool_name"))
                ToolInput = Get-PropertyValue $call @("args", "toolArgs", "tool_input")
                ToolResponse = Get-PropertyValue $call @("result", "toolResult", "tool_result", "toolResponse", "tool_response")
            }
        }
        return
    }

    [pscustomobject]@{
        SessionId = [string](Get-PropertyValue $inputEnvelope @("session_id", "sessionId"))
        WorkingDirectory = [string](Get-PropertyValue $inputEnvelope @("cwd", "working_directory", "workingDirectory"))
        EventId = [string](Get-PropertyValue $inputEnvelope @("tool_use_id", "toolUseId", "tool_call_id", "toolCallId", "timestamp"))
        ToolName = [string](Get-PropertyValue $inputEnvelope @("tool_name", "toolName"))
        ToolInput = Get-PropertyValue $inputEnvelope @("tool_input", "toolArgs")
        ToolResponse = Get-PropertyValue $inputEnvelope @("tool_response", "toolResponse", "tool_result", "toolResult", "result")
    }
}

function Test-PathWithinRoot {
    param(
        [string]$Path,
        [string]$Root
    )

    try {
        $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $comparison = if ([IO.Path]::DirectorySeparatorChar -eq '\') {
            [StringComparison]::OrdinalIgnoreCase
        } else {
            [StringComparison]::Ordinal
        }

        return $fullPath.Equals($fullRoot, $comparison) -or
            $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, $comparison) -or
            $fullPath.StartsWith($fullRoot + [IO.Path]::AltDirectorySeparatorChar, $comparison)
    } catch {
        return $false
    }
}

function Get-RoutedSessionId {
    param(
        [string]$PayloadSessionId,
        [string]$WorkingDirectory,
        [string]$TempRoot
    )

    $normalizedWorkingDirectory = if ([IO.Path]::IsPathRooted($WorkingDirectory)) {
        [IO.Path]::GetFullPath($WorkingDirectory)
    } else {
        $null
    }
    if ($null -ne $normalizedWorkingDirectory) {
        $routeDirectory = [IO.Path]::Combine($TempRoot, "UA", "upgrades", "build-observations", "routes")
        $matches = @()
        foreach ($routeFile in @(Get-ChildItem -LiteralPath $routeDirectory -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
            try {
                $route = Get-Content -LiteralPath $routeFile.FullName -Raw | ConvertFrom-Json
                $updated = [DateTimeOffset]::MinValue
                if (-not [DateTimeOffset]::TryParse((Get-TimestampText $route.updatedUtc), [ref]$updated) -or
                    $updated -lt [DateTimeOffset]::UtcNow.AddMinutes(-1) -or
                    $updated -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
                    continue
                }

                if (@($route.workspaceRoots | Where-Object {
                    Test-PathWithinRoot $normalizedWorkingDirectory ([string]$_)
                }).Count -eq 0) {
                    continue
                }

                $parsed = [Guid]::Empty
                if ([Guid]::TryParse([string]$route.sessionId, [ref]$parsed)) {
                    $matches += $parsed.ToString("D")
                }
            } catch {
            }
        }

        $matches = @($matches | Select-Object -Unique)
        if ($matches.Count -eq 1) {
            return $matches[0]
        }
        if ($matches.Count -gt 1) {
            return $null
        }
    }

    $parsedPayloadSession = [Guid]::Empty
    if ([Guid]::TryParse($PayloadSessionId, [ref]$parsedPayloadSession)) {
        try {
            $sessionPath = [IO.Path]::Combine(
                $TempRoot,
                "UA",
                "upgrades",
                "sessions",
                $parsedPayloadSession.ToString("D"),
                "session.json")
            $session = Get-Content -LiteralPath $sessionPath -Raw -ErrorAction Stop | ConvertFrom-Json
            $roots = @($session.workspace.repoRoot, $session.workspace.workspaceFolder) |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            if ($null -eq $normalizedWorkingDirectory -or
                @($roots | Where-Object {
                    Test-PathWithinRoot $normalizedWorkingDirectory ([string]$_)
                }).Count -gt 0) {
                return $parsedPayloadSession.ToString("D")
            }
        } catch {
        }
    }

    return $null
}

function Get-Sha256 {
    param([string]$Value)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace("-", "")
    } finally {
        $sha256.Dispose()
    }
}

function Append-Observation {
    param(
        [string]$Path,
        [object]$Record
    )

    $line = ($Record | ConvertTo-Json -Compress -Depth 6) + [Environment]::NewLine
    $lockPath = "$Path.lock"
    $lockStream = $null
    try {
        for ($attempt = 0; $attempt -lt 20 -and $null -eq $lockStream; $attempt++) {
            try {
                $lockStream = [IO.File]::Open(
                    $lockPath,
                    [IO.FileMode]::CreateNew,
                    [IO.FileAccess]::Write,
                    [IO.FileShare]::None)
            } catch [IO.IOException] {
                Start-Sleep -Milliseconds 25
            }
        }

        if ($null -ne $lockStream) {
            [IO.File]::AppendAllText($Path, $line, [Text.Encoding]::UTF8)
        }
    } finally {
        if ($null -ne $lockStream) {
            $lockStream.Dispose()
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-HookDiagnostic {
    param(
        [string]$TelemetryDirectory,
        [Exception]$Exception
    )

    try {
        [IO.Directory]::CreateDirectory($TelemetryDirectory) | Out-Null
        $record = [pscustomobject]@{
            timestampUtc = [DateTime]::UtcNow.ToString("o")
            eventName = "unhandledException"
            phase = $Phase
            exceptionType = $Exception.GetType().FullName
            hresult = $Exception.HResult
        }
        Append-Observation ([IO.Path]::Combine($TelemetryDirectory, "hook-diagnostics.jsonl")) $record
    } catch [IO.IOException] {
    } catch [UnauthorizedAccessException] {
    } catch [Security.SecurityException] {
    } catch [ArgumentException] {
    }
}

function Test-ClaimHookEvent {
    param(
        [string]$StateDirectory,
        [string]$SessionId,
        [string]$EventId,
        [string]$ToolName,
        [string]$Command
    )

    if ([string]::IsNullOrWhiteSpace($EventId)) {
        return $true
    }

    $claimDirectory = [IO.Path]::Combine($StateDirectory, "hook-events")
    [IO.Directory]::CreateDirectory($claimDirectory) | Out-Null
    foreach ($staleClaim in @(Get-ChildItem -LiteralPath $claimDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-1) })) {
        Remove-Item -LiteralPath $staleClaim.FullName -Force -ErrorAction SilentlyContinue
    }

    $claimHash = (Get-Sha256 "$SessionId`n$Phase`n$EventId`n$($ToolName.ToLowerInvariant())`n$Command").ToLowerInvariant()
    $claimPath = [IO.Path]::Combine($claimDirectory, "$claimHash.claim")
    try {
        $stream = [IO.File]::Open($claimPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Dispose()
        return $true
    } catch [IO.IOException] {
        return $false
    }
}

function Save-State {
    param(
        [string]$StateDirectory,
        [string]$CorrelationHash,
        [object]$State
    )

    $stateName = "{0}-{1:D20}-{2}.json" -f $CorrelationHash, [DateTime]::UtcNow.Ticks, [Guid]::NewGuid().ToString("N")
    $state | ConvertTo-Json -Compress -Depth 5 |
        Set-Content -LiteralPath ([IO.Path]::Combine($StateDirectory, $stateName)) -Encoding UTF8
}

function Remove-StaleStates {
    param([string]$StateDirectory)

    $cutoff = [DateTime]::UtcNow.AddHours(-24)
    foreach ($staleState in @(Get-ChildItem -LiteralPath $StateDirectory -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LastWriteTimeUtc -lt $cutoff -and
            $_.Name -match '^[0-9a-f]{64}-\d{20}-[0-9a-f]{32}\.json(?:\.\d+\.claim)?$'
        })) {
        Remove-Item -LiteralPath $staleState.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Claim-State {
    param(
        [string]$StateDirectory,
        [string]$CorrelationHash
    )

    $mutex = [Threading.Mutex]::new($false, "UA.BuildObservations")
    try {
        if (-not $mutex.WaitOne([TimeSpan]::FromSeconds(1))) {
            return $null
        }

        $stateFile = Get-ChildItem -LiteralPath $StateDirectory -Filter "$CorrelationHash-*.json" -File |
            Sort-Object Name |
            Select-Object -First 1
        if ($null -eq $stateFile) {
            return $null
        }

        $claimPath = "$($stateFile.FullName).$PID.claim"
        Move-Item -LiteralPath $stateFile.FullName -Destination $claimPath
        return $claimPath
    } finally {
        try {
            $mutex.ReleaseMutex()
        } catch {
        }
        $mutex.Dispose()
    }
}

function Get-ExitCodeDetails {
    param([object]$Payload, [object]$ToolResponse, [string]$ResponseText)

    $trailerMatch = [regex]::Match(
        $ResponseText,
        '(?m)<shellId:\s*[^>\r\n]*?\s+completed with exit code\s+(?<code>-?\d+)>\s*$')
    $trailerExitCode = if ($trailerMatch.Success) { $trailerMatch.Groups["code"].Value } else { $null }
    $directExitCode = Get-PropertyValue $ToolResponse @("exit_code", "exitCode")
    $telemetry = Get-PropertyValue $ToolResponse @("toolTelemetry", "tool_telemetry")
    $metrics = Get-PropertyValue $telemetry @("metrics")
    $metricsExitCode = Get-PropertyValue $metrics @("exit_code", "exitCode")
    $payloadExitCode = Get-PropertyValue $Payload @("exit_code", "exitCode")
    $properties = Get-PropertyValue $telemetry @("properties")
    $hasNonzeroCategory = [string](Get-PropertyValue $properties @("shell_error_category", "shellErrorCategory")) -eq "command_nonzero_exit"
    $resultType = [string](Get-PropertyValue $ToolResponse @("resultType", "result_type"))

    $exitCodeValue = $trailerExitCode
    $source = "textResultTrailer"
    if ($null -eq $exitCodeValue) {
        $exitCodeValue = $directExitCode
        $source = "direct"
    }
    if ($null -eq $exitCodeValue) {
        $exitCodeValue = $metricsExitCode
        $source = "metrics"
    }
    if ($null -eq $exitCodeValue) {
        $exitCodeValue = $payloadExitCode
        $source = "payload"
    }

    if ($null -ne $exitCodeValue) {
        $numericExitCode = 0.0
        if ([double]::TryParse(
            [string]$exitCodeValue,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$numericExitCode) -and
            $numericExitCode -eq [Math]::Truncate($numericExitCode) -and
            $numericExitCode -ge [int]::MinValue -and
            $numericExitCode -le [int]::MaxValue) {
            return [pscustomobject]@{
                ExitCode = [int]$numericExitCode
                Source = $source
                HasTrailerExitCode = $null -ne $trailerExitCode
                HasDirectExitCode = $null -ne $directExitCode
                HasMetricsExitCode = $null -ne $metricsExitCode
                HasPayloadExitCode = $null -ne $payloadExitCode
                HasNonzeroCategory = $hasNonzeroCategory
                ResultType = $resultType
            }
        }
    }

    return $null
}

function Get-ResponseText {
    param([object]$ToolResponse)

    if ($ToolResponse -is [string]) {
        return [string]$ToolResponse
    }

    $text = Get-PropertyValue $ToolResponse @("textResultForLlm", "text_result_for_llm")
    if ($null -eq $text) {
        return ""
    }

    return [string]$text
}

function Remove-QuotedCommandText {
    param([string]$Command)

    $characters = $Command.ToCharArray()
    $quote = [char]0
    for ($index = 0; $index -lt $characters.Length; $index++) {
        $character = $characters[$index]
        if ($quote -eq [char]0) {
            if ($character -eq "'" -or $character -eq '"') {
                $quote = $character
                $characters[$index] = " "
            } elseif ($character -eq '`' -and $index + 1 -lt $characters.Length) {
                $characters[$index] = " "
                $index++
                $characters[$index] = " "
            }

            continue
        }

        $characters[$index] = " "
        if ($quote -eq '"' -and $character -eq '`' -and $index + 1 -lt $characters.Length) {
            $index++
            $characters[$index] = " "
        } elseif ($character -eq $quote) {
            if ($index + 1 -lt $characters.Length -and $characters[$index + 1] -eq $quote) {
                $index++
                $characters[$index] = " "
            } else {
                $quote = [char]0
            }
        }
    }

    return -join $characters
}

function Process-ToolCall {
    param(
        [object]$Payload,
        [object]$Call,
        [string]$TempRoot,
        [string]$TelemetryDirectory,
        [string]$StateDirectory
    )

    if ($Call.ToolName -notmatch '^(bash|Bash|powershell|PowerShell|run_in_terminal|execute|shell)$') {
        return
    }

    $command = [string](Get-PropertyValue $Call.ToolInput @("command", "script", "input"))
    if ([string]::IsNullOrWhiteSpace($command)) {
        return
    }
    $isAsync = [string](Get-PropertyValue $Call.ToolInput @("mode")) -eq "async" -or
        [bool](Get-PropertyValue $Call.ToolInput @("detach"))

    $recognitionCommand = Remove-QuotedCommandText $command
    $commentIndex = $recognitionCommand.IndexOf("#", [StringComparison]::Ordinal)
    $invocationCommand = if ($commentIndex -ge 0) { $command.Substring(0, $commentIndex) } else { $command }
    $recognitionCommand = if ($commentIndex -ge 0) {
        $recognitionCommand.Substring(0, $commentIndex)
    } else {
        $recognitionCommand
    }
    if ($recognitionCommand -match '[;&|]' -or $recognitionCommand -match '[\r\n]') {
        return
    }
    $buildMatch = [regex]::Match(
        $recognitionCommand,
        '(?i)^\s*(?:dotnet(?:\.exe)?\s+(?<operation>build)(?=\s|$)|(?<msbuild>msbuild(?:\.exe)?)(?=\s|$))')
    if (-not $buildMatch.Success) {
        return
    }

    $sessionId = Get-RoutedSessionId $Call.SessionId $Call.WorkingDirectory $TempRoot
    if ([string]::IsNullOrWhiteSpace($sessionId)) {
        return
    }

    $operation = "build"
    if ($buildMatch.Groups["msbuild"].Success) {
        $targetMatch = [regex]::Match(
            $invocationCommand,
            '(?i)(?:^|\s)[/-](?:t|target):(?:"(?<targets>[^"]+)"|''(?<targets>[^'']+)''|(?<targets>[^\s;&|]+))')
        if ($targetMatch.Success) {
            $msbuildTargets = @(
                $targetMatch.Groups["targets"].Value.Split(@(",", ";"), [StringSplitOptions]::RemoveEmptyEntries) |
                    ForEach-Object { $_.Trim().ToLowerInvariant() }
            )
            if (-not ($msbuildTargets | Where-Object { $_ -eq "build" -or $_ -eq "rebuild" } | Select-Object -First 1)) {
                return
            }
        }
    }

    $workingDirectory = $Call.WorkingDirectory
    $targetMatches = [regex]::Matches($invocationCommand, '(?i)(?:"(?<path>[^"]+\.(?:slnx?|csproj|fsproj|vbproj))"|''(?<path>[^'']+\.(?:slnx?|csproj|fsproj|vbproj))''|(?<path>[^\s;&|]+\.(?:slnx?|csproj|fsproj|vbproj)))')
    $targetPaths = @()
    foreach ($match in $targetMatches) {
        $path = $match.Groups["path"].Value
        if (-not [IO.Path]::IsPathRooted($path) -and -not [string]::IsNullOrWhiteSpace($workingDirectory)) {
            $path = [IO.Path]::GetFullPath([IO.Path]::Combine($workingDirectory, $path))
        }

        if ([IO.Path]::IsPathRooted($path)) {
            $targetPaths += $path
        }
    }

    if ($targetPaths.Count -eq 0 -and $buildMatch.Groups["operation"].Success) {
        $argumentsMatch = [regex]::Match(
            $invocationCommand,
            '(?is)^\s*dotnet(?:\.exe)?\s+build(?=\s|$)(?<arguments>.*)$')
        $directoryTargets = @()
        $optionsWithValues = @(
            "-a", "--arch",
            "--artifacts-path",
            "-c", "--configuration",
            "--configfile",
            "-f", "--framework",
            "-o", "--output",
            "--packages",
            "-p", "--property",
            "-r", "--runtime",
            "-s", "--source",
            "-v", "--verbosity"
        )
        $skipNextArgument = $false
        foreach ($argumentMatch in [regex]::Matches(
            $argumentsMatch.Groups["arguments"].Value,
            '(?:"(?<path>[^"]+)"|''(?<path>[^'']+)''|(?<path>[^\s;&|]+))')) {
            $path = $argumentMatch.Groups["path"].Value
            if ($skipNextArgument) {
                $skipNextArgument = $false
                continue
            }

            if ($path.StartsWith("-") -or $path.StartsWith("/")) {
                $skipNextArgument = $optionsWithValues -contains $path.ToLowerInvariant()
                continue
            }

            if (-not [IO.Path]::IsPathRooted($path) -and -not [string]::IsNullOrWhiteSpace($workingDirectory)) {
                $path = [IO.Path]::GetFullPath([IO.Path]::Combine($workingDirectory, $path))
            }

            if ([IO.Path]::IsPathRooted($path) -and [IO.Directory]::Exists($path)) {
                $directoryTargets += $path
            }
        }

        $directoryTargets = @($directoryTargets | Select-Object -Unique)
        if ($directoryTargets.Count -eq 1) {
            $targetPaths += $directoryTargets[0]
        } elseif ($directoryTargets.Count -gt 1) {
            return
        }
    }

    if ($targetPaths.Count -eq 0 -and [IO.Path]::IsPathRooted($workingDirectory)) {
        $targetPaths = @($workingDirectory)
    }

    $scope = if ($targetPaths | Where-Object { $_ -match '(?i)\.slnx?$' } | Select-Object -First 1) {
        "solution"
    } elseif ($targetPaths | Where-Object { $_ -match '(?i)\.(?:csproj|fsproj|vbproj)$' } | Select-Object -First 1) {
        "project"
    } else {
        "repository"
    }

    [IO.Directory]::CreateDirectory($StateDirectory) | Out-Null
    Remove-StaleStates $StateDirectory

    $correlationHash = Get-Sha256 "$sessionId`n$($Call.ToolName.ToLowerInvariant())`n$workingDirectory`n$command"
    $observationPath = [IO.Path]::Combine($TelemetryDirectory, "build-observations-$sessionId.jsonl")

    if ($Phase -eq "pre") {
        if ($isAsync) {
            return
        }

        if (-not (Test-ClaimHookEvent $StateDirectory $sessionId $Call.EventId $Call.ToolName $command)) {
            return
        }

        $state = [pscustomobject]@{
            attemptId = [Guid]::NewGuid().ToString()
            startedAtUtc = [DateTime]::UtcNow.ToString("o")
            operation = $operation
            scope = $scope
            targetPaths = @($targetPaths | Select-Object -Unique -First 20)
        }
        Save-State $StateDirectory $correlationHash $state
        Append-Observation $observationPath ([pscustomobject]@{
            recordKind = "started"
            sessionId = $sessionId
            attemptId = $state.attemptId
            startedAtUtc = $state.startedAtUtc
            operation = $state.operation
            scope = $state.scope
            targetPaths = $state.targetPaths
        })
        return
    }

    if (-not (Test-ClaimHookEvent $StateDirectory $sessionId $Call.EventId $Call.ToolName $command)) {
        return
    }

    $claimPath = Claim-State $StateDirectory $correlationHash
    if ([string]::IsNullOrWhiteSpace($claimPath)) {
        return
    }

    if ($isAsync) {
        Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
        return
    }

    $responseText = Get-ResponseText $Call.ToolResponse
    $exitCodeDetails = Get-ExitCodeDetails $Payload $Call.ToolResponse $responseText
    if ($null -eq $exitCodeDetails) {
        Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
        return
    }
    $exitCode = [int]$exitCodeDetails.ExitCode

    try {
        $state = Get-Content -LiteralPath $claimPath -Raw | ConvertFrom-Json
    } finally {
        Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
    }

    $diagnosticPattern = '(?:CS|FS|BC|NU|MSB|NETSDK|NET|SDK|VSTEST)\d{3,5}'
    $errorMatches = [regex]::Matches($responseText, "(?i)\berror\s+(?<code>$diagnosticPattern)\b")
    $warningMatches = [regex]::Matches($responseText, "(?i)\bwarning\s+(?<code>$diagnosticPattern)\b")
    $errorDiagnosticCodes = @(
        $errorMatches |
            ForEach-Object { $_.Groups["code"].Value.ToUpperInvariant() } |
            Sort-Object -Unique |
            Select-Object -First 10
    )
    $warningDiagnosticCodes = @(
        $warningMatches |
            ForEach-Object { $_.Groups["code"].Value.ToUpperInvariant() } |
            Sort-Object -Unique |
            Select-Object -First 10
    )
    $diagnosticCodes = @(
        @($errorDiagnosticCodes) + @($warningDiagnosticCodes) |
            Sort-Object -Unique |
            Select-Object -First 10
    )
    $errorCount = $errorMatches.Count
    $warningCount = $warningMatches.Count

    $outcome = if ($exitCode -eq 0 -and $errorCount -eq 0) {
        "succeeded"
    } elseif ($responseText -match '(?i)\bcancel(?:led|ed)?\b') {
        "cancelled"
    } elseif ($exitCode -eq 124 -or $responseText -match '(?i)\btimed?\s*out\b') {
        "timedOut"
    } else {
        "failed"
    }
    $failurePhase = if ($errorDiagnosticCodes | Where-Object { $_ -match '^NU' } | Select-Object -First 1) {
        "restore"
    } elseif ($errorDiagnosticCodes | Where-Object { $_ -match '^(CS|FS|BC)' } | Select-Object -First 1) {
        "compile"
    } else {
        "unknown"
    }
    $failureCategory = if ($outcome -eq "cancelled") {
        "cancelled"
    } elseif ($outcome -eq "timedOut") {
        "timeout"
    } elseif ($outcome -eq "succeeded") {
        "unknown"
    } elseif ($errorDiagnosticCodes -contains "NU1101") {
        "packageNotFound"
    } elseif ($responseText -match '(?i)\b(?:401|unauthorized|authentication)\b') {
        "packageFeedAuthentication"
    } elseif ($errorDiagnosticCodes -contains "NU1107" -or $errorDiagnosticCodes -contains "NU1605") {
        "packageVersionConflict"
    } elseif ($errorDiagnosticCodes -contains "MSB4019") {
        "missingMSBuildImport"
    } elseif ($errorDiagnosticCodes -contains "MSB4236") {
        "missingSdk"
    } elseif ($errorDiagnosticCodes -contains "NETSDK1147") {
        "missingWorkload"
    } elseif ($errorDiagnosticCodes -contains "NETSDK1045") {
        "unsupportedTargetFramework"
    } elseif ($errorDiagnosticCodes | Where-Object { $_ -match '^(CS|FS|BC)' } | Select-Object -First 1) {
        "compilationError"
    } else {
        "unknown"
    }

    if ($exitCodeDetails.ResultType -eq "success" -and ($exitCode -ne 0 -or $errorCount -gt 0)) {
        Append-Observation ([IO.Path]::Combine($TelemetryDirectory, "hook-classification-diagnostics.jsonl")) ([pscustomobject]@{
            timestampUtc = [DateTime]::UtcNow.ToString("o")
            phase = "post-classification"
            operation = [string]$state.operation
            exitCodeSource = [string]$exitCodeDetails.Source
            parsedExitCode = $exitCode
            resultType = [string]$exitCodeDetails.ResultType
            hasTrailerExitCode = [bool]$exitCodeDetails.HasTrailerExitCode
            hasDirectExitCode = [bool]$exitCodeDetails.HasDirectExitCode
            hasMetricsExitCode = [bool]$exitCodeDetails.HasMetricsExitCode
            hasPayloadExitCode = [bool]$exitCodeDetails.HasPayloadExitCode
            hasNonzeroCategory = [bool]$exitCodeDetails.HasNonzeroCategory
            errorCount = $errorCount
            derivedOutcome = $outcome
        })
    }

    Append-Observation $observationPath ([pscustomobject]@{
        recordKind = "completed"
        sessionId = $sessionId
        attemptId = [string]$state.attemptId
        startedAtUtc = Get-TimestampText $state.startedAtUtc
        completedAtUtc = [DateTime]::UtcNow.ToString("o")
        operation = [string]$state.operation
        scope = [string]$state.scope
        outcome = $outcome
        failurePhase = $failurePhase
        failureCategory = $failureCategory
        errorCount = $errorCount
        warningCount = $warningCount
        errorDiagnosticCodes = $errorDiagnosticCodes
        warningDiagnosticCodes = $warningDiagnosticCodes
        diagnosticCodes = $diagnosticCodes
        targetPaths = @($state.targetPaths)
    })
}

$tempRoot = if (-not [string]::IsNullOrWhiteSpace($env:DOTNET_UPGRADEASSISTANT_DIAGNOSTICS_ROOT_PATH)) {
    $env:DOTNET_UPGRADEASSISTANT_DIAGNOSTICS_ROOT_PATH
} elseif ($env:TEMP) {
    $env:TEMP
} else {
    [IO.Path]::GetTempPath()
}
$telemetryDirectory = [IO.Path]::Combine($tempRoot, "UA", "upgrades", "build-observations")
try {
    $inputJson = if ($PSBoundParameters.ContainsKey('HookInputJson')) {
        $HookInputJson
    } else {
        [Console]::In.ReadToEnd()
    }
    $payload = $inputJson | ConvertFrom-Json
    $stateDirectory = [IO.Path]::Combine($telemetryDirectory, "state")

    foreach ($call in @(Get-NormalizedToolCalls $payload)) {
        Process-ToolCall $payload $call $tempRoot $telemetryDirectory $stateDirectory
    }
} catch {
    if (-not [string]::IsNullOrWhiteSpace($telemetryDirectory)) {
        Write-HookDiagnostic $telemetryDirectory $_.Exception
    }
}

Write-Success
