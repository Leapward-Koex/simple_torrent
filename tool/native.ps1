[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $NativeArguments
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = Split-Path -Parent $scriptDirectory
$dartCommand = Get-Command dart -ErrorAction SilentlyContinue
$dartCandidates = @(
    $(if ($dartCommand) {
        $commandPath = $dartCommand.Source
        if ([IO.Path]::GetFileName($commandPath) -ieq 'dart.exe') {
            $commandPath
        } else {
            Join-Path (Split-Path -Parent $commandPath) 'cache\dart-sdk\bin\dart.exe'
        }
    }),
    (Join-Path $repositoryRoot '.fvm\flutter_sdk\bin\cache\dart-sdk\bin\dart.exe'),
    $(if ($env:FLUTTER_ROOT) {
        Join-Path $env:FLUTTER_ROOT 'bin\cache\dart-sdk\bin\dart.exe'
    }),
    $(if ($env:USERPROFILE) {
        Join-Path $env:USERPROFILE 'fvm\default\bin\cache\dart-sdk\bin\dart.exe'
    }),
    $(if ($dartCommand) { $dartCommand.Source })
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

if ($dartCandidates.Count -eq 0) {
    throw 'Dart was not found. Install Flutter 3.44 or newer, or add dart to PATH.'
}
# Flutter's bin/dart.bat runs the Flutter bootstrap and may wait on its global
# startup lock. The builder needs only the Dart VM, so prefer the SDK binary.
$dartExecutable = $dartCandidates[0]

& $dartExecutable (Join-Path $scriptDirectory 'native.dart') @NativeArguments
exit $LASTEXITCODE
