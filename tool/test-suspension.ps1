[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Platform,

    [string]$DeviceId = $env:SIMPLE_TORRENT_DEVICE_ID,

    [string]$TimeoutMinutes = $(
        if ($env:SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES) {
            $env:SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES
        } else {
            '5'
        }
    ),

    [switch]$KeepOnFailure,

    [string]$BuildMode = $(
        if ($env:SIMPLE_TORRENT_BUILD_MODE) {
            $env:SIMPLE_TORRENT_BUILD_MODE
        } else {
            'debug'
        }
    )
)

$arguments = @{
    Platform = $Platform
    TimeoutMinutes = $TimeoutMinutes
    BuildMode = $BuildMode
    TestFile = 'integration_test/transfer_suspension_test.dart'
    DiagnosticsSuite = 'test-suspension'
}
if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
    $arguments['DeviceId'] = $DeviceId
}
if ($KeepOnFailure.IsPresent) {
    $arguments['KeepOnFailure'] = $true
}

& (Join-Path $PSScriptRoot 'test-sample.ps1') @arguments
exit $LASTEXITCODE
