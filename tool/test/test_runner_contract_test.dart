import 'dart:convert';
import 'dart:io';

void main() {
  final powershell = File('tool/test-sample.ps1').readAsStringSync();
  final shell = File('tool/test-sample.sh').readAsStringSync();
  final timeoutSupervisor = File('tool/run_with_timeout.py').readAsStringSync();
  final powershellSuspension = File('tool/test-suspension.ps1')
      .readAsStringSync();
  final shellSuspension = File('tool/test-suspension.sh').readAsStringSync();
  final transferSuspension = File(
    'packages/simple_torrent/example/integration_test/'
    'transfer_suspension_test.dart',
  ).readAsStringSync();

  final checks = <String, bool>{
    'PowerShell accepts all four native platforms': powershell.contains(
      "@('windows', 'android', 'macos', 'ios')",
    ),
    'PowerShell maps macOS to Flutter targetPlatform darwin': RegExp(
      r"'macos'[\s\S]{0,250}targetPlatform -eq 'darwin'",
    ).hasMatch(powershell),
    'PowerShell requires an iOS emulator': RegExp(
      r"'ios'[\s\S]{0,300}targetPlatform -eq 'ios'[\s\S]{0,120}emulator -eq \$true",
    ).hasMatch(powershell),
    'PowerShell builds the real Windows Release artifact': powershell.contains(
      "@('build', 'windows', '--release')",
    ),
    'PowerShell builds the real Android Release artifact': powershell.contains(
      "@('build', 'apk', '--release')",
    ),
    'PowerShell builds the real macOS Release artifact': powershell.contains(
      "@('build', 'macos', '--release')",
    ),
    'PowerShell performs an unsigned iOS device Release link build': powershell
        .contains("@('build', 'ios', '--release', '--no-codesign')"),
    'PowerShell runs iOS Release requests in Debug on the simulator':
        powershell.contains(
          r"$normalizedBuildMode -eq 'release' -and $Platform -ne 'ios'",
        ) &&
        powershell.contains(
          r"$normalizedBuildMode -eq 'release' -and $requestedPlatform -ne 'ios'",
        ),
    'PowerShell drives non-web release validation in supported Profile mode':
        RegExp(r"'drive',[\s\S]{0,350}'--profile'").hasMatch(powershell),
    'PowerShell does not attempt unsupported Release-mode Flutter Driver':
        !RegExp(r"'drive',[\s\S]{0,350}'--release'").hasMatch(powershell),
    'PowerShell reports the actual build and driven modes separately':
        powershell.contains('testExecutionMode') &&
        powershell.contains('releaseArtifactBuilt'),
    'PowerShell writes diagnostics for preflight failures':
        powershell.contains('trap {') &&
        powershell.contains(r'Write-TestResult -Passed $false'),
    'shell consumes Flutter machine-readable device metadata': shell.contains(
      'devices --machine',
    ),
    'shell maps macOS to Flutter targetPlatform darwin': shell.contains(
      'return target == "darwin"',
    ),
    'shell requires an iOS emulator': shell.contains(
      'return target == "ios" and device.get("emulator") is True',
    ),
    'shell builds the real Windows Release artifact': shell.contains(
      'build windows --release',
    ),
    'shell builds the real Android Release artifact': shell.contains(
      'build apk --release',
    ),
    'shell builds the real macOS Release artifact': shell.contains(
      'build macos --release',
    ),
    'shell performs an unsigned iOS device Release link build': shell.contains(
      'build ios --release --no-codesign',
    ),
    'shell runs iOS Release requests in Debug on the simulator': shell.contains(
      r'[[ "$build_mode" == "release" && "$platform" != "ios" ]]',
    ),
    'shell drives non-web release validation in supported Profile mode': RegExp(
      r'drive[\s\S]{0,350}--profile',
    ).hasMatch(shell),
    'shell does not attempt unsupported Release-mode Flutter Driver': !RegExp(
      r'drive[\s\S]{0,350}--release',
    ).hasMatch(shell),
    'shell reports the actual build and driven modes separately':
        shell.contains('testExecutionMode') &&
        shell.contains('releaseArtifactBuilt'),
    'shell writes diagnostics for preflight failures':
        shell.contains('unexpected_failure') &&
        shell.contains(r'\"passed\":false'),
    'shell gives discovery, Release builds, and integration runs hard deadlines':
        shell.contains('SIMPLE_TORRENT_PREFLIGHT_TIMEOUT_MINUTES') &&
        shell.contains('SIMPLE_TORRENT_BUILD_TIMEOUT_MINUTES') &&
        shell.contains('SIMPLE_TORRENT_PROCESS_TIMEOUT_MINUTES') &&
        shell.split(r'python3 "$script_dir/run_with_timeout.py"').length == 4,
    'shell reports process deadline expiry in structured diagnostics':
        shell.contains('preflightTimeoutMinutes') &&
        shell.contains('processTimeoutMinutes') &&
        shell.contains('buildTimeoutMinutes') &&
        shell.contains('process deadline') &&
        shell.contains('124'),
    'Unix timeout supervisor isolates and terminates the full process group':
        timeoutSupervisor.contains('start_new_session=True') &&
        timeoutSupervisor.contains('os.killpg') &&
        timeoutSupervisor.contains('_process_group_exists') &&
        timeoutSupervisor.contains('signal.SIGTERM') &&
        timeoutSupervisor.contains('signal.SIGKILL') &&
        timeoutSupervisor.contains('subprocess.TimeoutExpired') &&
        timeoutSupervisor.contains('Command exited with descendants') &&
        timeoutSupervisor.contains('_TIMEOUT_EXIT_CODE = 124'),
    'Unix timeout supervisor forwards workflow cancellation signals':
        timeoutSupervisor.contains('forward_signal') &&
        timeoutSupervisor.contains('signal.SIGINT') &&
        timeoutSupervisor.contains('signal.SIGHUP'),
    'PowerShell suspension wrapper selects the deterministic test':
        powershellSuspension.contains(
          'integration_test/transfer_suspension_test.dart',
        ),
    'shell suspension wrapper selects the deterministic test': shellSuspension
        .contains('integration_test/transfer_suspension_test.dart'),
    'deterministic suspension test accepts all four native platforms':
        transferSuspension.contains(
          "anyOf('windows', 'android', 'macos', 'ios')",
        ),
    'deterministic suspension test cleans up after failures':
        transferSuspension.contains('} finally {') &&
        transferSuspension.contains('_deleteWithRetry(root)'),
  };

  var passed = true;
  for (final entry in checks.entries) {
    if (entry.value) {
      stdout.writeln('PASS: ${entry.key}');
    } else {
      passed = false;
      stderr.writeln('FAIL: ${entry.key}');
    }
  }
  stdout.writeln(jsonEncode({'ok': passed, 'suite': 'test-runner-contract'}));
  if (!passed) exitCode = 1;
}
