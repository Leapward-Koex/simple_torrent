import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

void main() {
  const generationPath = '.github/workflows/native-bundle-generate.yml';
  const gatePath = '.github/workflows/native-bundle-gate.yml';
  const overlayPath = '.github/scripts/overlay-native-artifacts.sh';
  const attributesPath = '.gitattributes';
  final generation = File(generationPath)
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final gate = File(gatePath).readAsStringSync().replaceAll('\r\n', '\n');
  final overlay = File(overlayPath).readAsStringSync().replaceAll('\r\n', '\n');
  final attributes = File(attributesPath)
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  const iosFrameworkDirectory =
      'packages/simple_torrent_ios/ios/simple_torrent_ios/Frameworks';
  const macosFrameworkDirectory =
      'packages/simple_torrent_macos/macos/simple_torrent_macos/Frameworks';
  const frameworkName = 'SimpleTorrentNative.xcframework';
  const iosFramework = '$iosFrameworkDirectory/$frameworkName';
  const macosFramework = '$macosFrameworkDirectory/$frameworkName';

  final generationTriggerPaths = _between(
    generation,
    '    paths:\n',
    '  workflow_dispatch:',
  );

  final checks = <String, bool>{
    'generation workflow is valid YAML': _isWorkflow(generation),
    'gate workflow is valid YAML': _isWorkflow(gate),
    'generation runs only for canonical master inputs':
        generation.contains('  push:\n    branches:\n      - master') &&
        generation.contains('  workflow_dispatch:') &&
        [
          '.gitattributes',
          'native/CMakeLists.txt',
          'native/dependencies.lock.json',
          'native/include/**',
          'native/src/**',
          'native/platform/**',
          'native/patches/**',
          'native/test/**',
          'tool/native.dart',
          'tool/native.ps1',
          'tool/native.sh',
          'tool/src/native_builder.dart',
          '.github/workflows/native-bundle-generate.yml',
          '.github/scripts/overlay-native-artifacts.sh',
          '.github/scripts/sync-native-notices-from-candidate.sh',
        ].every(generationTriggerPaths.contains),
    'generated outputs cannot retrigger generation':
        !generationTriggerPaths.contains('artifacts.manifest.json') &&
        !generationTriggerPaths.contains('THIRD_PARTY_NOTICES.md') &&
        !generationTriggerPaths.contains('jniLibs') &&
        !generationTriggerPaths.contains('Frameworks') &&
        !generationTriggerPaths.contains('windows/lib'),
    'manual generation rejects a non-master source': generation.contains(
      r'if [[ "$GITHUB_REF" != refs/heads/master ]]',
    ),
    'publication rebases safely or rejects a stale native source':
        generation.contains(
          "'+refs/heads/master:refs/remotes/origin/master'",
        ) &&
        generation.contains(
          r'git diff --no-renames --name-only --diff-filter=ACMRTD -z "$GITHUB_SHA" "$latest_sha"',
        ) &&
        generation.contains(
          'Master changed native generation input or tooling',
        ) &&
        _occurrences(generation, '.gitattributes') >= 2 &&
        generation.contains(
          r'GIT_LFS_SKIP_SMUDGE=1 git checkout --detach "$latest_sha"',
        ) &&
        generation.indexOf(
              r'GIT_LFS_SKIP_SMUDGE=1 git checkout --detach "$latest_sha"',
            ) <
            generation.indexOf('Overlay and validate candidate changes'),
    'generation cancels superseded runs': generation.contains(
      'group: native-bundle-generation\n  cancel-in-progress: true',
    ),
    'build and assembly permissions are read-only':
        generation.startsWith('name: Native bundle generation') &&
        generation.contains('permissions:\n  contents: read') &&
        _occurrences(generation, '      contents: write') == 1 &&
        _occurrences(generation, '      pull-requests: write') == 1,
    'third-party setup is immutable and write token is step-scoped':
        _occurrences(
              generation,
              'subosito/flutter-action@'
              '1a449444c387b1966244ae4d4f8c696479add0b2',
            ) ==
            4 &&
        _occurrences(
              gate,
              'subosito/flutter-action@'
              '1a449444c387b1966244ae4d4f8c696479add0b2',
            ) ==
            2 &&
        !generation.contains('subosito/flutter-action@v2') &&
        !gate.contains('subosito/flutter-action@v2') &&
        generation.contains(
          'ilammy/msvc-dev-cmd@0b201ec74fa43914dc39ae48a89fd1d8cb592756',
        ) &&
        gate.contains(
          'ilammy/msvc-dev-cmd@0b201ec74fa43914dc39ae48a89fd1d8cb592756',
        ) &&
        generation.contains(
          'android-actions/setup-android@9fc6c4e9069bf8d3d10b2204b1fb8f6ef7065407',
        ) &&
        gate.contains(
          'android-actions/setup-android@9fc6c4e9069bf8d3d10b2204b1fb8f6ef7065407',
        ) &&
        gate.contains(
          'reactivecircus/android-emulator-runner@'
          'a421e43855164a8197daf9d8d40fe71c6996bb0d',
        ) &&
        !generation.contains('ilammy/msvc-dev-cmd@v') &&
        !gate.contains('ilammy/msvc-dev-cmd@v') &&
        !generation.contains('android-actions/setup-android@v') &&
        !gate.contains('android-actions/setup-android@v') &&
        !gate.contains('reactivecircus/android-emulator-runner@v') &&
        !generation.contains('    env:\n      GH_TOKEN:') &&
        _occurrences(generation, '          GH_TOKEN: \${{ github.token }}') ==
            4 &&
        _occurrences(generation, '          persist-credentials: false') == 5 &&
        generation.contains(
          'http.https://github.com/.extraheader="AUTHORIZATION: basic \$auth"',
        ),
    'platform build runners match the requested policies':
        generation.contains('runs-on: windows-latest') &&
        generation.contains('runs-on: ubuntu-24.04') &&
        generation.contains('runs-on: macos-26') &&
        !generation.contains('runs-on: windows-2022') &&
        !generation.contains('vsversion: "2022"'),
    'Flutter is bootstrapped before every machine-readable version query':
        _occurrences(generation, 'flutter --version --machine') == 3 &&
        _occurrences(gate, 'flutter --version --machine') == 2 &&
        _occurrences(generation, 'flutter --version | Out-Null') == 1 &&
        _occurrences(gate, 'flutter --version | Out-Null') == 1 &&
        _occurrences(generation, 'flutter --version >/dev/null') == 2 &&
        _occurrences(gate, 'flutter --version >/dev/null') == 1 &&
        _orderedPairOccurrences(
              generation,
              'flutter --version | Out-Null',
              r'$flutterOutput = flutter --version --machine | Out-String',
            ) ==
            1 &&
        _orderedPairOccurrences(
              gate,
              'flutter --version | Out-Null',
              r'$flutterOutput = flutter --version --machine | Out-String',
            ) ==
            1 &&
        _orderedPairOccurrences(
              generation,
              'flutter --version >/dev/null',
              r'flutter_json="$(flutter --version --machine)"',
            ) ==
            2 &&
        _orderedPairOccurrences(
              gate,
              'flutter --version >/dev/null',
              r'flutter_json="$(flutter --version --machine)"',
            ) ==
            1 &&
        _occurrences(
              generation,
              r'$flutterOutput = flutter --version --machine | Out-String',
            ) ==
            1 &&
        _occurrences(
              gate,
              r'$flutterOutput = flutter --version --machine | Out-String',
            ) ==
            1 &&
        _occurrences(generation, r"$jsonStart = $flutterOutput.IndexOf('{')") ==
            1 &&
        _occurrences(gate, r"$jsonStart = $flutterOutput.IndexOf('{')") == 1 &&
        _occurrences(
              generation,
              r'$flutterOutput.Substring($jsonStart, $jsonEnd - $jsonStart + 1)',
            ) ==
            1 &&
        _occurrences(
              gate,
              r'$flutterOutput.Substring($jsonStart, $jsonEnd - $jsonStart + 1)',
            ) ==
            1 &&
        _occurrences(
              generation,
              r'flutter_json="$(flutter --version --machine)"',
            ) ==
            2 &&
        _occurrences(gate, r'flutter_json="$(flutter --version --machine)"') ==
            1 &&
        !generation.contains(
          'flutter --version --machine | ConvertFrom-Json',
        ) &&
        !gate.contains('flutter --version --machine | ConvertFrom-Json') &&
        !generation.contains(
          r'flutter --version --machine | jq -r .frameworkVersion',
        ) &&
        !gate.contains(
          r'flutter --version --machine | jq -r .frameworkVersion',
        ),
    'Android NDK assertions prefer an exact base revision':
        _occurrences(generation, 'key == "Pkg.BaseRevision"') == 1 &&
        _occurrences(gate, 'key == "Pkg.BaseRevision"') == 1 &&
        _occurrences(generation, 'key == "Pkg.Revision"') == 1 &&
        _occurrences(gate, 'key == "Pkg.Revision"') == 1 &&
        _occurrences(generation, 'if (base_count == 1) {') == 1 &&
        _occurrences(gate, 'if (base_count == 1) {') == 1 &&
        _occurrences(generation, 'if (invalid || base_count > 1') == 1 &&
        _occurrences(gate, 'if (invalid || base_count > 1') == 1 &&
        _occurrences(generation, 'raw ~ /^Pkg[.]BaseRevision') == 1 &&
        _occurrences(gate, 'raw ~ /^Pkg[.]BaseRevision') == 1 &&
        _occurrences(generation, 'NF != 2 || base_count != 1') == 1 &&
        _occurrences(gate, 'NF != 2 || base_count != 1') == 1 &&
        _occurrences(
              generation,
              'missing, duplicate, or malformed revision metadata',
            ) ==
            1 &&
        _occurrences(
              gate,
              'missing, duplicate, or malformed revision metadata',
            ) ==
            1 &&
        generation.contains(
          r'''[[ "$ndk_revision" == '${{ steps.toolchains.outputs.android_ndk }}' ]]''',
        ) &&
        gate.contains(
          r'''[[ "$ndk_revision" == '${{ steps.unix_toolchains.outputs.android_ndk }}' ]]''',
        ) &&
        !generation.contains("grep -Eq '^Pkg[.]Revision") &&
        !gate.contains("grep -Eq '^Pkg[.]Revision"),
    'Apple generation is ARM-only':
        generation.contains('Build Apple ARM bundles') &&
        generation.contains(
          'build ios --arch arm64 --arch sim-arm64 --source-sha',
        ) &&
        generation.contains('build macos --arch arm64 --source-sha') &&
        generation.contains(r'[[ "$(uname -m)" == "arm64" ]]') &&
        !generation.contains('sim-x86_64') &&
        !generation.contains('macos-15-intel'),
    'only authenticated downloads are cached':
        _occurrences(generation, 'uses: actions/cache@v4') == 3 &&
        _occurrences(generation, 'path: .native-cache/downloads') == 3 &&
        !generation.contains('path: .native-cache/sources'),
    'all fragments carry and recheck the triggering SHA':
        _occurrences(generation, '--source-sha') >= 5 &&
        [
          'windows',
          'android',
          'ios',
          'macos',
        ].every((platform) => generation.contains('$platform.source-sha')) &&
        generation.contains('Check fragment source SHAs') &&
        generation.contains(
          r"$sourceShaPath = 'build/native/fragments/windows.source-sha'",
        ) &&
        generation.contains(
          r'Set-Content -LiteralPath $sourceShaPath -Value $env:GITHUB_SHA '
          '-NoNewline -Encoding utf8NoBOM',
        ) &&
        generation.contains(
          r'(Get-Content -LiteralPath $sourceShaPath -Raw) '
          r'-cne $env:GITHUB_SHA',
        ) &&
        !generation.contains(
          r'Set-Content -NoNewline build/native/fragments/windows.source-sha',
        ),
    'assembly names all four fragments and refreshes notices':
        ['windows', 'android', 'ios', 'macos'].every(
          (platform) => generation.contains(
            '--fragment "$platform=incoming/build/native/fragments/'
            '$platform.manifest.json"',
          ),
        ) &&
        generation.contains('./tool/native.sh sync-metadata') &&
        generation.contains(
          'bash .github/scripts/sync-native-notices-from-candidate.sh',
        ),
    'candidate is kept outside the repository checkout': generation.contains(
      r'path: ${{ runner.temp }}/native-bundle-candidate',
    ),
    'publish is allowlisted and verifies Git LFS objects':
        generation.contains(
          'Candidate changed a path outside the generated allowlist',
        ) &&
        generation.contains('git check-attr filter') &&
        generation.contains('git lfs fsck --pointers') &&
        generation.contains("-name '*.dll'") &&
        generation.contains("-name '*.lib'") &&
        generation.contains("-name '*.so'") &&
        generation.contains("-name '*.a'"),
    'Apple artifacts are rooted inside their Swift packages':
        _occurrences(generation, iosFramework) == 5 &&
        _occurrences(generation, macosFramework) == 5 &&
        _occurrences(gate, iosFramework) == 2 &&
        _occurrences(gate, macosFramework) == 2 &&
        _occurrences(overlay, 'replace_tree $iosFramework') == 1 &&
        _occurrences(overlay, 'replace_tree $macosFramework') == 1 &&
        _occurrences(attributes, '$iosFrameworkDirectory/**/*.a') == 1 &&
        _occurrences(attributes, '$macosFrameworkDirectory/**/*.a') == 1 &&
        !'$generation\n$gate\n$overlay\n$attributes'.contains(
          'packages/simple_torrent_ios/ios/Frameworks/',
        ) &&
        !'$generation\n$gate\n$overlay\n$attributes'.contains(
          'packages/simple_torrent_macos/macos/Frameworks/',
        ),
    'publish uses one fixed bot branch and no-op detection':
        generation.contains('BOT_BRANCH: bot/native-bundle') &&
        generation.contains('No native bundle changes were produced.') &&
        generation.contains('Close an obsolete fixed-branch PR') &&
        generation.contains(r'gh pr close "$pr_number" --delete-branch') &&
        generation.contains('--force-with-lease=') &&
        generation.contains('.head.repo.full_name == \$repo') &&
        generation.contains('.head.ref == \$ref') &&
        generation.contains('.base.repo.full_name == \$repo') &&
        generation.contains('.base.ref == "master"') &&
        generation.contains('.head.sha == \$sha'),
    'auto-merge is fail-closed behind the stable gate':
        generation.contains(
          'native-bundle-gate is not configured as a strict required check in an active master ruleset',
        ) &&
        generation.contains('strict_required_status_checks_policy == true') &&
        !generation.contains('branches/master/protection') &&
        generation.contains("gh pr merge '\${{ steps.pr.outputs.number }}'") &&
        generation.contains(
          '--auto --squash --delete-branch --match-head-commit "\$expected_head"',
        ),
    'gate runs on every pull request to master':
        gate.contains('  pull_request:\n    branches:\n      - master') &&
        gate.contains('git diff --no-renames --name-only') &&
        gate.contains(
          r'[[ "$HEAD_REPOSITORY" == "$GITHUB_REPOSITORY" && "$HEAD_REF" == bot/native-bundle ]]',
        ),
    'gate behaviorally tests the Unix process supervisor': gate.contains(
      'run: python3 tool/test/run_with_timeout_test.py',
    ),
    'gate checks out LFS content read-only':
        gate.contains('permissions:\n  contents: read') &&
        !gate.contains('contents: write') &&
        !gate.contains(r'ref: ${{ github.event.pull_request.head.sha }}') &&
        gate.contains(r'git ls-tree -r -z --name-only HEAD -- "$prefix"') &&
        gate.contains('git lfs pointer --check --strict --stdin') &&
        gate.contains('Committed binary is not covered by Git LFS') &&
        gate.contains(r'git lfs pull --include="$prefix/**" --exclude=""') &&
        gate.contains(r'git lfs pointer --file="$file"') &&
        gate.contains('tail -n 3'),
    'gate has four independent non-fail-fast platform jobs':
        gate.contains('fail-fast: false') &&
        gate.contains('runner: windows-latest') &&
        !gate.contains('runner: windows-2022') &&
        !gate.contains('vsversion: "2022"') &&
        _occurrences(gate, '- platform: windows') == 1 &&
        _occurrences(gate, '- platform: android') == 1 &&
        _occurrences(gate, '- platform: macos') == 1 &&
        _occurrences(gate, '- platform: ios') == 1,
    'Apple smoke jobs use ARM hosted runners and ARM bundles':
        _occurrences(gate, 'runner: macos-26') == 2 &&
        gate.contains('Verify macOS ARM bundle') &&
        gate.contains('Verify iOS ARM bundle') &&
        gate.contains(r'[[ "$(uname -m)" == "arm64" ]]') &&
        !gate.contains('sim-x86_64') &&
        !gate.contains('macos-15-intel'),
    'Apple smoke jobs explicitly exercise SwiftPM and ARM-only macOS builds':
        gate.contains(
          "if: matrix.platform == 'macos' || matrix.platform == 'ios'",
        ) &&
        _occurrences(gate, 'flutter config --enable-swift-package-manager') ==
            1 &&
        _occurrences(gate, 'flutter config --enable-macos-arm64-only') == 1,
    'iOS smoke creates, boots, and deletes a fresh dedicated simulator':
        gate.contains('xcrun --sdk iphonesimulator --show-sdk-version') &&
        gate.contains(r'.version == $version or') &&
        gate.contains(r'startswith($version + ".")') &&
        gate.contains('xcrun simctl list runtimes --json') &&
        gate.contains(
          r'simulator_name="SimpleTorrent-CI-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"',
        ) &&
        gate.contains(
          r'xcrun simctl create "$simulator_name" "$device_type" "$runtime"',
        ) &&
        gate.contains('xcrun simctl list devices available --json') &&
        gate.contains('.deviceTypeIdentifier // empty') &&
        !gate.contains('.udid // empty') &&
        gate.contains(r'xcrun simctl bootstatus "$udid" -b') &&
        gate.contains(r'xcrun simctl delete "$SIMPLE_TORRENT_DEVICE_ID"') &&
        gate.contains('SIMPLE_TORRENT_DEVICE_ID') &&
        gate.contains('./tool/test-sample.sh ios release') &&
        gate.contains('./tool/test-suspension.sh ios debug'),
    'iOS launch phases have independent outer deadlines and diagnostics':
        RegExp(
          r'Boot a fresh dedicated iOS ARM simulator[\s\S]{0,150}timeout-minutes: 10',
        ).hasMatch(gate) &&
        RegExp(
          r'Build iOS Release and run Simulator Debug XCTest init smoke[\s\S]{0,150}timeout-minutes: 50',
        ).hasMatch(gate) &&
        RegExp(
          r'Run iOS Simulator XCTest deterministic suspension smoke[\s\S]{0,150}timeout-minutes: 35',
        ).hasMatch(gate) &&
        gate.contains('SIMPLE_TORRENT_PREFLIGHT_TIMEOUT_MINUTES=3') &&
        gate.contains('SIMPLE_TORRENT_BUILD_TIMEOUT_MINUTES=15') &&
        gate.contains('SIMPLE_TORRENT_PROCESS_TIMEOUT_MINUTES=10') &&
        gate.contains('SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES=5') &&
        _occurrences(gate, 'SIMPLE_TORRENT_BUILD_TIMEOUT_MINUTES=15') >= 2 &&
        _occurrences(gate, 'SIMPLE_TORRENT_PROCESS_TIMEOUT_MINUTES=10') >= 2 &&
        gate.contains('Capture iOS Simulator failure diagnostics') &&
        gate.contains(
          "if: (failure() || cancelled()) && matrix.platform == 'ios'",
        ) &&
        _occurrences(gate, 'python3 tool/run_with_timeout.py 60') >= 4 &&
        gate.contains('xcrun simctl spawn') &&
        gate.contains(r'''--predicate 'process == "Runner"' ''') &&
        gate.indexOf('Capture iOS Simulator failure diagnostics') <
            gate.indexOf('Shut down iOS Simulator') &&
        gate.indexOf('Shut down iOS Simulator') <
            gate.indexOf('Upload smoke diagnostics') &&
        gate.indexOf(r'''printf 'SIMPLE_TORRENT_DEVICE_ID=%s\n' "$udid"''') <
            gate.indexOf(r'xcrun simctl boot "$udid"') &&
        RegExp(r'Shut down iOS Simulator[\s\S]{0,100}if: always\(\)')
            .hasMatch(gate) &&
        RegExp(r'Upload smoke diagnostics[\s\S]{0,100}if: always\(\)')
            .hasMatch(gate),
    'Android smoke requires KVM hardware acceleration':
        gate.contains('- name: Enable Android emulator KVM access') &&
        gate.contains(
          '''echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |''',
        ) &&
        gate.contains('sudo udevadm control --reload-rules') &&
        gate.contains('sudo udevadm trigger --name-match=kvm') &&
        gate.contains(r'[[ -r /dev/kvm && -w /dev/kvm ]]') &&
        gate.contains(r'"$ANDROID_SDK_ROOT/emulator/emulator" -accel-check') &&
        gate.contains('disable-linux-hw-accel: false') &&
        gate.contains('emulator-options: -no-window -accel on ') &&
        !gate.contains('disable-linux-hw-accel: auto'),
    'each platform performs init and suspension smoke coverage':
        _occurrences(gate, 'SIMPLE_TORRENT_DIAGNOSTICS_SUITE') >= 4 &&
        _occurrences(gate, 'test-suspension') >= 5 &&
        gate.contains('./tool/test-sample.sh macos release') &&
        gate.contains('./tool/test-sample.sh android release') &&
        gate.contains(
          './tool/test-sample.sh android release && '
          './tool/test-suspension.sh android debug',
        ) &&
        gate.contains(r'.\tool\test-sample.ps1 windows -BuildMode release'),
    'public-network tests are not a required gate': !gate
        .toLowerCase()
        .contains('wired'),
    'non-bundle pull requests pass through the stable aggregate check':
        gate.contains('    name: native-bundle-gate') &&
        gate.contains('    if: always()') &&
        gate.contains(r'if [[ "$BUNDLE" != true ]]') &&
        gate.contains('the gate passes without platform jobs.'),
    'Unix workflow scripts are made executable at runtime':
        generation.contains('chmod +x tool/native.sh') &&
        gate.contains('chmod +x tool/native.sh'),
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
  stdout.writeln(
    jsonEncode({'ok': passed, 'suite': 'native-workflow-contract'}),
  );
  if (!passed) exitCode = 1;
}

bool _isWorkflow(String source) {
  try {
    final parsed = loadYaml(source);
    return parsed is YamlMap &&
        parsed['name'] is String &&
        parsed['jobs'] is YamlMap;
  } on YamlException {
    return false;
  }
}

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  if (startIndex < 0 || endIndex < 0) return '';
  return source.substring(startIndex + start.length, endIndex);
}

int _occurrences(String source, String pattern) =>
    RegExp(RegExp.escape(pattern)).allMatches(source).length;

int _orderedPairOccurrences(String source, String first, String second) =>
    RegExp('${RegExp.escape(first)}[\\s\\S]*?${RegExp.escape(second)}')
        .allMatches(source)
        .length;
