import 'dart:convert';
import 'dart:io';

void main() {
  final powershell = File('tool/test-sample.ps1').readAsStringSync();
  final shell = File('tool/test-sample.sh').readAsStringSync();
  final powershellSuspension = File('tool/test-suspension.ps1')
      .readAsStringSync();
  final shellSuspension = File('tool/test-suspension.sh').readAsStringSync();

  final checks = <String, bool>{
    'PowerShell builds the real Windows Release artifact': powershell.contains(
      "@('build', 'windows', '--release')",
    ),
    'PowerShell builds the real Android Release artifact': powershell.contains(
      "@('build', 'apk', '--release')",
    ),
    'PowerShell drives non-web release validation in supported Profile mode':
        RegExp(r"'drive',[\s\S]{0,350}'--profile'").hasMatch(powershell),
    'PowerShell does not attempt unsupported Release-mode Flutter Driver':
        !RegExp(r"'drive',[\s\S]{0,350}'--release'").hasMatch(powershell),
    'PowerShell reports the actual build and driven modes separately':
        powershell.contains('testExecutionMode') &&
        powershell.contains('releaseArtifactBuilt'),
    'shell builds the real Windows Release artifact': shell.contains(
      'build windows --release',
    ),
    'shell builds the real Android Release artifact': shell.contains(
      'build apk --release',
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
    'PowerShell suspension wrapper selects the deterministic test':
        powershellSuspension.contains(
          'integration_test/transfer_suspension_test.dart',
        ),
    'shell suspension wrapper selects the deterministic test': shellSuspension
        .contains('integration_test/transfer_suspension_test.dart'),
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
