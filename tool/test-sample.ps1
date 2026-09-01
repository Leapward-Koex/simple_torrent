[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Platform,

    [string]$DeviceId = $env:SIMPLE_TORRENT_DEVICE_ID,

    [string]$TimeoutMinutes = $(
        if ($env:SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES) {
            $env:SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES
        } else {
            '45'
        }
    ),

    [switch]$KeepOnFailure,

    [string]$BuildMode = $(
        if ($env:SIMPLE_TORRENT_BUILD_MODE) {
            $env:SIMPLE_TORRENT_BUILD_MODE
        } else {
            'debug'
        }
    ),

    [Parameter(DontShow = $true)]
    [string]$TestFile = $(
        if ($env:SIMPLE_TORRENT_TEST_FILE) {
            $env:SIMPLE_TORRENT_TEST_FILE
        } else {
            'integration_test/wired_download_test.dart'
        }
    ),

    [Parameter(DontShow = $true)]
    [string]$DiagnosticsSuite = $(
        if ($env:SIMPLE_TORRENT_DIAGNOSTICS_SUITE) {
            $env:SIMPLE_TORRENT_DIAGNOSTICS_SUITE
        } else {
            'test-sample'
        }
    )
)

$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$requestedPlatform = if ([string]::IsNullOrWhiteSpace($Platform)) {
    'unknown'
} else {
    $Platform.Trim().ToLowerInvariant()
}
$supportedPlatforms = @('windows', 'android', 'macos', 'ios')
$diagnosticPlatform = if ($requestedPlatform -in $supportedPlatforms) {
    $requestedPlatform
} else {
    'unknown'
}
$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$diagnosticsRoot = Join-Path $repoRoot "build\$DiagnosticsSuite\$diagnosticPlatform-$timestamp"
New-Item -ItemType Directory -Force -Path $diagnosticsRoot | Out-Null
$logPath = Join-Path $diagnosticsRoot 'flutter-test.log'
$resultPath = Join-Path $diagnosticsRoot 'result.json'
New-Item -ItemType File -Force -Path $logPath | Out-Null

$script:resolvedTimeoutMinutes = $null
$script:selectedTargetPlatform = $null
$script:selectedEmulator = $null
$script:lastFlutterExitCode = $null
$script:handlingFailure = $false
$script:testExecutionMode = 'debug'
$script:releaseArtifactBuilt = $false
$normalizedBuildMode = if ([string]::IsNullOrWhiteSpace($BuildMode)) {
    'unknown'
} else {
    $BuildMode.Trim().ToLowerInvariant()
}
$script:testExecutionMode = if (
    $normalizedBuildMode -eq 'release' -and $requestedPlatform -ne 'ios'
) {
    'profile'
} else {
    'debug'
}

function Write-TestResult {
    param(
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [string]$ErrorMessage
    )

    $result = [ordered]@{
        passed = $Passed
        platform = $requestedPlatform
        device = $DeviceId
        targetPlatform = $script:selectedTargetPlatform
        emulator = $script:selectedEmulator
        timeoutMinutes = $script:resolvedTimeoutMinutes
        buildMode = $normalizedBuildMode
        testExecutionMode = $script:testExecutionMode
        releaseArtifactBuilt = $script:releaseArtifactBuilt
        testFile = $TestFile
        keepOnFailure = $KeepOnFailure.IsPresent -or
            $env:SIMPLE_TORRENT_KEEP_ON_FAILURE -match '^(1|true|yes)$'
        exitCode = $ExitCode
        log = $logPath
        result = $resultPath
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    if ($ErrorMessage) { $result.error = $ErrorMessage }
    $json = $result | ConvertTo-Json -Compress
    $json | Set-Content -LiteralPath $resultPath -Encoding utf8
    Write-Output "SIMPLE_TORRENT_TEST_RESULT=$json"
}

trap {
    if ($script:handlingFailure) { exit 1 }
    $script:handlingFailure = $true
    $message = $_.Exception.Message
    "ERROR: $message" | Add-Content -LiteralPath $logPath -Encoding utf8
    Write-TestResult -Passed $false -ExitCode 1 -ErrorMessage $message
    exit 1
}

if ($requestedPlatform -notin $supportedPlatforms) {
    throw 'Usage: tool/test-sample.ps1 <windows|android|macos|ios> [-BuildMode debug|release]'
}
$Platform = $requestedPlatform
if ($normalizedBuildMode -notin @('debug', 'release')) {
    throw 'SIMPLE_TORRENT_BUILD_MODE must be debug or release.'
}

$parsedTimeout = 0
if (-not [int]::TryParse($TimeoutMinutes, [ref]$parsedTimeout) -or
    $parsedTimeout -lt 1 -or $parsedTimeout -gt 240) {
    throw 'SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES must be an integer from 1 to 240.'
}
$script:resolvedTimeoutMinutes = $parsedTimeout
$keep = $KeepOnFailure.IsPresent -or
    $env:SIMPLE_TORRENT_KEEP_ON_FAILURE -match '^(1|true|yes)$'

$exampleRoot = Join-Path $repoRoot 'packages\simple_torrent\example'
if (-not (Test-Path -LiteralPath (Join-Path $exampleRoot 'pubspec.yaml'))) {
    throw "Example package not found at $exampleRoot"
}

$flutterExecutable = $null
$useFvm = $false
if ($env:SIMPLE_TORRENT_FLUTTER) {
    $flutterExecutable = (Resolve-Path -LiteralPath $env:SIMPLE_TORRENT_FLUTTER).Path
} elseif ($env:FLUTTER_ROOT) {
    $candidates = @(
        (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'),
        (Join-Path $env:FLUTTER_ROOT 'bin\flutter')
    )
    $candidate = $candidates | Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if ($candidate) { $flutterExecutable = $candidate }
} elseif (Get-Command flutter -ErrorAction SilentlyContinue) {
    $flutterExecutable = (Get-Command flutter).Source
} elseif (Get-Command fvm -ErrorAction SilentlyContinue) {
    $flutterExecutable = (Get-Command fvm).Source
    $useFvm = $true
} else {
    $candidate = Join-Path $env:USERPROFILE 'fvm\default\bin\flutter.bat'
    if (Test-Path -LiteralPath $candidate) { $flutterExecutable = $candidate }
}
if (-not $flutterExecutable) {
    throw 'Flutter was not found. Put flutter on PATH or set SIMPLE_TORRENT_FLUTTER.'
}

function Invoke-Flutter {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    if ($useFvm) {
        & $flutterExecutable flutter @Arguments
    } else {
        & $flutterExecutable @Arguments
    }
    $script:lastFlutterExitCode = $LASTEXITCODE
}

$deviceStderrPath = Join-Path $diagnosticsRoot 'flutter-devices.stderr.log'
$deviceJson = (Invoke-Flutter devices --machine 2> $deviceStderrPath | Out-String)
$deviceExitCode = $script:lastFlutterExitCode
'Flutter devices:' | Add-Content -LiteralPath $logPath -Encoding utf8
$deviceJson | Add-Content -LiteralPath $logPath -Encoding utf8
if ((Test-Path -LiteralPath $deviceStderrPath) -and
    (Get-Item -LiteralPath $deviceStderrPath).Length -gt 0) {
    'Flutter device diagnostics:' |
        Add-Content -LiteralPath $logPath -Encoding utf8
    Get-Content -Raw -LiteralPath $deviceStderrPath |
        Add-Content -LiteralPath $logPath -Encoding utf8
}
if ($deviceExitCode -ne 0) { throw 'flutter devices failed.' }
try {
    $devices = @($deviceJson | ConvertFrom-Json)
} catch {
    throw "flutter devices returned invalid JSON: $($_.Exception.Message)"
}

$device = $null
if ($DeviceId) {
    $device = $devices |
        Where-Object { $_.id -eq $DeviceId } |
        Select-Object -First 1
    if (-not $device) {
        throw "Flutter device '$DeviceId' was not found."
    }
} else {
    $device = switch ($Platform) {
        'windows' {
            $devices |
                Where-Object {
                    $_.isSupported -and $_.targetPlatform -like 'windows-*'
                } |
                Sort-Object id |
                Select-Object -First 1
        }
        'android' {
            $devices |
                Where-Object {
                    $_.isSupported -and $_.targetPlatform -like 'android-*'
                } |
                Sort-Object `
                    @{ Expression = { if ($_.targetPlatform -eq 'android-x64') { 0 } else { 1 } } },
                    @{ Expression = { if ($_.emulator) { 0 } else { 1 } } },
                    id |
                Select-Object -First 1
        }
        'macos' {
            $devices |
                Where-Object {
                    $_.isSupported -and $_.targetPlatform -eq 'darwin'
                } |
                Sort-Object id |
                Select-Object -First 1
        }
        'ios' {
            $devices |
                Where-Object {
                    $_.isSupported -and
                        $_.targetPlatform -eq 'ios' -and
                        $_.emulator -eq $true
                } |
                Sort-Object id |
                Select-Object -First 1
        }
    }
}
if (-not $device) {
    throw "No supported $Platform device is available. Start/connect one or set SIMPLE_TORRENT_DEVICE_ID."
}
if (-not $device.isSupported) {
    throw "Flutter device '$($device.id)' is not supported."
}
$script:selectedTargetPlatform = [string]$device.targetPlatform
$script:selectedEmulator = [bool]$device.emulator
$targetMatches = switch ($Platform) {
    'windows' { $script:selectedTargetPlatform -like 'windows-*' }
    'android' { $script:selectedTargetPlatform -like 'android-*' }
    'macos' { $script:selectedTargetPlatform -eq 'darwin' }
    'ios' {
        $script:selectedTargetPlatform -eq 'ios' -and
            $script:selectedEmulator
    }
}
if (-not $targetMatches) {
    throw "Flutter device '$($device.id)' targets '$($device.targetPlatform)', not $Platform."
}
$DeviceId = [string]$device.id
"Selected device: $DeviceId ($($script:selectedTargetPlatform))" |
    Add-Content -LiteralPath $logPath -Encoding utf8

$defineArguments = @(
    "--dart-define=SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES=$parsedTimeout",
    "--dart-define=SIMPLE_TORRENT_KEEP_ON_FAILURE=$($keep.ToString().ToLowerInvariant())",
    "--dart-define=SIMPLE_TORRENT_EXPECTED_PLATFORM=$Platform"
)
$testArguments = if (
    $normalizedBuildMode -eq 'release' -and $Platform -ne 'ios'
) {
    # Flutter deliberately rejects non-web `flutter drive --release` because a
    # release app has no VM service for the driver. Build the actual release
    # consumer artifact first, then exercise the same bundled native binary in
    # the closest supported driven mode. Keep both facts explicit in result.json.
    @(
        'drive',
        '--driver=test_driver/integration_test.dart',
        "--target=$TestFile",
        '-d', $DeviceId,
        '--profile'
    ) + $defineArguments
} else {
    @(
        'test',
        $TestFile,
        '-d', $DeviceId
    ) + $defineArguments
}

Push-Location $exampleRoot
try {
    # Flutter writes diagnostics to stderr during successful runs. Treat those
    # as log records rather than terminating PowerShell errors.
    $ErrorActionPreference = 'Continue'
    if ($normalizedBuildMode -eq 'release') {
        $releaseBuildArguments = switch ($Platform) {
            'windows' { @('build', 'windows', '--release') }
            'android' { @('build', 'apk', '--release') }
            'macos' { @('build', 'macos', '--release') }
            'ios' { @('build', 'ios', '--release', '--no-codesign') }
        }
        "Building actual $Platform Release artifact before the $($script:testExecutionMode) integration run." |
            Tee-Object -FilePath $logPath -Append
        $script:lastFlutterExitCode = $null
        Invoke-Flutter @releaseBuildArguments 2>&1 |
            Tee-Object -FilePath $logPath -Append
        $releaseBuildExitCode = if ($null -eq $script:lastFlutterExitCode) {
            1
        } else {
            $script:lastFlutterExitCode
        }
        if ($releaseBuildExitCode -ne 0) {
            throw "Flutter Release build failed with exit code $releaseBuildExitCode."
        }
        $script:releaseArtifactBuilt = $true
    }
    $script:lastFlutterExitCode = $null
    Invoke-Flutter @testArguments 2>&1 | Tee-Object -FilePath $logPath -Append
    $testExitCode = if ($null -eq $script:lastFlutterExitCode) {
        1
    } else {
        $script:lastFlutterExitCode
    }
} finally {
    $ErrorActionPreference = 'Stop'
    Pop-Location
}

$errorMessage = if ($testExitCode -eq 0) {
    $null
} else {
    "Flutter integration test failed with exit code $testExitCode."
}
Write-TestResult `
    -Passed ($testExitCode -eq 0) `
    -ExitCode $testExitCode `
    -ErrorMessage $errorMessage
exit $testExitCode
