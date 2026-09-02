import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

void main() {
  const buildPath = '.github/workflows/native-bundle-build.yml';
  const generationPath = '.github/workflows/native-bundle-generate.yml';
  const gatePath = '.github/workflows/native-bundle-gate.yml';
  const overlayPath = '.github/scripts/overlay-native-artifacts.sh';
  const noticeSyncPath =
      '.github/scripts/sync-native-notices-from-candidate.sh';
  const attributesPath = '.gitattributes';
  final build = File(buildPath).readAsStringSync().replaceAll('\r\n', '\n');
  final generation = File(generationPath)
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final gate = File(gatePath).readAsStringSync().replaceAll('\r\n', '\n');
  final overlay = File(overlayPath).readAsStringSync().replaceAll('\r\n', '\n');
  final noticeSync = File(noticeSyncPath)
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
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
    'reusable build workflow is valid YAML': _isWorkflow(build),
    'generation workflow is valid YAML': _isWorkflow(generation),
    'gate workflow is valid YAML': _isWorkflow(gate),
    'reusable build requires an exact source SHA input':
        build.contains(
          'on:\n  workflow_call:\n    inputs:\n      source_sha:',
        ) &&
        build.contains('        required: true\n        type: string') &&
        build.contains(r'  NATIVE_SOURCE_SHA: ${{ inputs.source_sha }}') &&
        _occurrences(build, r'          ref: ${{ inputs.source_sha }}') == 4 &&
        !build.contains(r'${{ github.sha }}') &&
        !build.contains(r'$GITHUB_SHA') &&
        !build.contains('  push:') &&
        !build.contains('  pull_request:'),
    'generation runs only for canonical master inputs':
        generation.contains('  push:\n    branches:\n      - master') &&
        generation.contains('  workflow_dispatch:') &&
        [
          '.gitattributes',
          '.lfsconfig',
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
          '.github/workflows/native-bundle-build.yml',
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
    'master generation delegates exact-SHA builds and alone publishes':
        generation.contains('  build-native-bundle:\n') &&
        generation.contains('    needs: validate-source') &&
        generation.contains(
          '    uses: ./.github/workflows/native-bundle-build.yml',
        ) &&
        generation.contains(r'      source_sha: ${{ github.sha }}') &&
        generation.contains(
          '  publish:\n    name: Publish native bundle pull request\n'
          '    needs: build-native-bundle',
        ) &&
        _occurrences(generation, '      contents: write') == 1 &&
        _occurrences(generation, '      pull-requests: write') == 1 &&
        !build.contains('Publish native bundle pull request') &&
        !gate.contains('Publish native bundle pull request'),
    'publication rebases safely or rejects a stale native source':
        generation.contains(
          "'+refs/heads/master:refs/remotes/origin/master'",
        ) &&
        generation.contains(
          'git diff --no-renames --name-only --diff-filter=ACMRTD -z',
        ) &&
        generation.contains(
          r'"$GITHUB_SHA" "$latest_sha" > "$changed_paths"',
        ) &&
        generation.contains(r'changed_paths="$(mktemp)"') &&
        generation.contains("while IFS= read -r -d '' path; do") &&
        generation.contains(r'done < "$changed_paths"') &&
        generation.contains(
          'Master changed native generation input or tooling',
        ) &&
        _occurrences(generation, '.gitattributes') >= 2 &&
        _occurrences(generation, '.lfsconfig') >= 2 &&
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
    'build, assembly, and pull-request permissions are read-only':
        build.startsWith('name: Build native bundle candidate') &&
        build.contains('permissions:\n  contents: read') &&
        _occurrences(build, '      contents: read') == 4 &&
        !build.contains('contents: write') &&
        !build.contains('pull-requests: write') &&
        gate.contains('permissions:\n  contents: read') &&
        !gate.contains('contents: write') &&
        !gate.contains('pull-requests: write') &&
        _occurrences(generation, '      contents: write') == 1 &&
        _occurrences(generation, '      pull-requests: write') == 1,
    'third-party setup is immutable and write token is step-scoped':
        _occurrences(
              build,
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
        !build.contains('subosito/flutter-action@v2') &&
        !gate.contains('subosito/flutter-action@v2') &&
        build.contains(
          'ilammy/msvc-dev-cmd@0b201ec74fa43914dc39ae48a89fd1d8cb592756',
        ) &&
        gate.contains(
          'ilammy/msvc-dev-cmd@0b201ec74fa43914dc39ae48a89fd1d8cb592756',
        ) &&
        build.contains(
          'android-actions/setup-android@9fc6c4e9069bf8d3d10b2204b1fb8f6ef7065407',
        ) &&
        gate.contains(
          'android-actions/setup-android@9fc6c4e9069bf8d3d10b2204b1fb8f6ef7065407',
        ) &&
        gate.contains(
          'reactivecircus/android-emulator-runner@'
          'a421e43855164a8197daf9d8d40fe71c6996bb0d',
        ) &&
        !build.contains('ilammy/msvc-dev-cmd@v') &&
        !gate.contains('ilammy/msvc-dev-cmd@v') &&
        !build.contains('android-actions/setup-android@v') &&
        !gate.contains('android-actions/setup-android@v') &&
        !gate.contains('reactivecircus/android-emulator-runner@v') &&
        !generation.contains('    env:\n      GH_TOKEN:') &&
        !build.contains('GH_TOKEN:') &&
        !gate.contains('GH_TOKEN:') &&
        _occurrences(generation, '          GH_TOKEN: \${{ github.token }}') ==
            4 &&
        _occurrences(build, '          persist-credentials: false') == 4 &&
        _occurrences(generation, '          persist-credentials: false') == 1 &&
        generation.contains(
          'http.https://github.com/.extraheader="AUTHORIZATION: basic \$auth"',
        ),
    'platform build runners match the requested policies':
        build.contains('runs-on: windows-latest') &&
        build.contains('runs-on: ubuntu-24.04') &&
        build.contains('runs-on: macos-26') &&
        !build.contains('runs-on: windows-2022') &&
        !build.contains('vsversion: "2022"'),
    'Flutter is bootstrapped before every machine-readable version query':
        _occurrences(build, 'flutter --version --machine') == 3 &&
        _occurrences(gate, 'flutter --version --machine') == 2 &&
        _occurrences(build, 'flutter --version | Out-Null') == 1 &&
        _occurrences(gate, 'flutter --version | Out-Null') == 1 &&
        _occurrences(build, 'flutter --version >/dev/null') == 2 &&
        _occurrences(gate, 'flutter --version >/dev/null') == 1 &&
        _orderedPairOccurrences(
              build,
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
              build,
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
              build,
              r'$flutterOutput = flutter --version --machine | Out-String',
            ) ==
            1 &&
        _occurrences(
              gate,
              r'$flutterOutput = flutter --version --machine | Out-String',
            ) ==
            1 &&
        _occurrences(build, r"$jsonStart = $flutterOutput.IndexOf('{')") == 1 &&
        _occurrences(gate, r"$jsonStart = $flutterOutput.IndexOf('{')") == 1 &&
        _occurrences(
              build,
              r'$flutterOutput.Substring($jsonStart, $jsonEnd - $jsonStart + 1)',
            ) ==
            1 &&
        _occurrences(
              gate,
              r'$flutterOutput.Substring($jsonStart, $jsonEnd - $jsonStart + 1)',
            ) ==
            1 &&
        _occurrences(build, r'flutter_json="$(flutter --version --machine)"') ==
            2 &&
        _occurrences(gate, r'flutter_json="$(flutter --version --machine)"') ==
            1 &&
        !build.contains('flutter --version --machine | ConvertFrom-Json') &&
        !gate.contains('flutter --version --machine | ConvertFrom-Json') &&
        !build.contains(
          r'flutter --version --machine | jq -r .frameworkVersion',
        ) &&
        !gate.contains(
          r'flutter --version --machine | jq -r .frameworkVersion',
        ),
    'Android NDK assertions prefer an exact base revision':
        _occurrences(build, 'key == "Pkg.BaseRevision"') == 1 &&
        _occurrences(gate, 'key == "Pkg.BaseRevision"') == 1 &&
        _occurrences(build, 'key == "Pkg.Revision"') == 1 &&
        _occurrences(gate, 'key == "Pkg.Revision"') == 1 &&
        _occurrences(build, 'if (base_count == 1) {') == 1 &&
        _occurrences(gate, 'if (base_count == 1) {') == 1 &&
        _occurrences(build, 'if (invalid || base_count > 1') == 1 &&
        _occurrences(gate, 'if (invalid || base_count > 1') == 1 &&
        _occurrences(build, 'raw ~ /^Pkg[.]BaseRevision') == 1 &&
        _occurrences(gate, 'raw ~ /^Pkg[.]BaseRevision') == 1 &&
        _occurrences(build, 'NF != 2 || base_count != 1') == 1 &&
        _occurrences(gate, 'NF != 2 || base_count != 1') == 1 &&
        _occurrences(
              build,
              'missing, duplicate, or malformed revision metadata',
            ) ==
            1 &&
        _occurrences(
              gate,
              'missing, duplicate, or malformed revision metadata',
            ) ==
            1 &&
        build.contains(
          r'''[[ "$ndk_revision" == '${{ steps.toolchains.outputs.android_ndk }}' ]]''',
        ) &&
        gate.contains(
          r'''[[ "$ndk_revision" == '${{ steps.unix_toolchains.outputs.android_ndk }}' ]]''',
        ) &&
        !build.contains("grep -Eq '^Pkg[.]Revision") &&
        !gate.contains("grep -Eq '^Pkg[.]Revision"),
    'Apple candidate builds are ARM-only':
        build.contains('Build Apple ARM bundles') &&
        build.contains(
          'build ios --arch arm64 --arch sim-arm64 --source-sha',
        ) &&
        build.contains('build macos --arch arm64 --source-sha') &&
        build.contains(r'[[ "$(uname -m)" == "arm64" ]]') &&
        !build.contains('sim-x86_64') &&
        !build.contains('macos-15-intel'),
    'only authenticated downloads are cached':
        _occurrences(build, 'uses: actions/cache@v4') == 3 &&
        _occurrences(build, 'path: .native-cache/downloads') == 3 &&
        !build.contains('path: .native-cache/sources'),
    'all fragments carry and recheck the triggering SHA':
        _occurrences(build, '--source-sha') >= 5 &&
        [
          'windows',
          'android',
          'ios',
          'macos',
        ].every((platform) => build.contains('$platform.source-sha')) &&
        build.contains('Check fragment source SHAs') &&
        build.contains(
          r"$sourceShaPath = 'build/native/fragments/windows.source-sha'",
        ) &&
        build.contains(
          r'Set-Content -LiteralPath $sourceShaPath -Value $env:NATIVE_SOURCE_SHA '
          '-NoNewline -Encoding utf8NoBOM',
        ) &&
        build.contains(
          r'(Get-Content -LiteralPath $sourceShaPath -Raw) '
          r'-cne $env:NATIVE_SOURCE_SHA',
        ) &&
        build.contains(
          r'test "$(cat "incoming/build/native/fragments/${platform}.source-sha")" = "$NATIVE_SOURCE_SHA"',
        ) &&
        !build.contains(
          r'Set-Content -NoNewline build/native/fragments/windows.source-sha',
        ),
    'assembly names all four fragments and refreshes notices':
        ['windows', 'android', 'ios', 'macos'].every(
          (platform) => build.contains(
            '--fragment "$platform=incoming/build/native/fragments/'
            '$platform.manifest.json"',
          ),
        ) &&
        build.contains('./tool/native.sh sync-metadata') &&
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
        _occurrences('$build\n$generation', iosFramework) == 5 &&
        _occurrences('$build\n$generation', macosFramework) == 5 &&
        _occurrences(gate, iosFramework) == 3 &&
        _occurrences(gate, macosFramework) == 3 &&
        _occurrences(overlay, 'replace_tree $iosFramework') == 1 &&
        _occurrences(overlay, 'replace_tree $macosFramework') == 1 &&
        _occurrences(attributes, '$iosFrameworkDirectory/**/*.a') == 1 &&
        _occurrences(attributes, '$macosFrameworkDirectory/**/*.a') == 1 &&
        !'$build\n$generation\n$gate\n$overlay\n$attributes'.contains(
          'packages/simple_torrent_ios/ios/Frameworks/',
        ) &&
        !'$build\n$generation\n$gate\n$overlay\n$attributes'.contains(
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
    'gate classifies source and bundle changes and rejects mixed pull requests':
        gate.contains('bundle: \${{ steps.changes.outputs.bundle }}') &&
        gate.contains('source: \${{ steps.changes.outputs.source }}') &&
        [
          '.gitattributes',
          'native/CMakeLists.txt',
          'native/dependencies.lock.json',
          'native/include/*',
          'native/src/*',
          'native/platform/*',
          'native/patches/*',
          'native/test/*',
          'tool/native.dart',
          'tool/native.ps1',
          'tool/native.sh',
          'tool/test-sample.ps1',
          'tool/test-sample.sh',
          'tool/test-suspension.ps1',
          'tool/test-suspension.sh',
          'tool/run_with_timeout.py',
          'tool/test/run_with_timeout_test.py',
          'tool/src/native_builder.dart',
          '.github/workflows/native-bundle-build.yml',
          '.github/workflows/native-bundle-gate.yml',
          '.github/workflows/native-bundle-generate.yml',
          '.github/scripts/overlay-native-artifacts.sh',
          '.github/scripts/sync-native-notices-from-candidate.sh',
        ].every(gate.contains) &&
        gate.contains(
          'git diff --no-renames --name-only --diff-filter=ACMRTD -z',
        ) &&
        gate.contains(r'"$BASE_SHA...$HEAD_SHA" > "$changed_paths"') &&
        gate.contains(r'changed_paths="$(mktemp)"') &&
        gate.contains("while IFS= read -r -d '' path; do") &&
        gate.contains(r'done < "$changed_paths"') &&
        [
          '.lfsconfig',
          'THIRD_PARTY_NOTICES.md',
          'packages/simple_torrent_windows/THIRD_PARTY_NOTICES.md',
          'packages/simple_torrent_android/THIRD_PARTY_NOTICES.md',
          'packages/simple_torrent_ios/THIRD_PARTY_NOTICES.md',
          'packages/simple_torrent_macos/THIRD_PARTY_NOTICES.md',
        ].every(gate.contains) &&
        _occurrences(gate, '.lfsconfig') == 1 &&
        gate.indexOf('.lfsconfig') >
            gate.indexOf(
              '.github/scripts/sync-native-notices-from-candidate.sh',
            ) &&
        gate.indexOf('.lfsconfig') < gate.indexOf('THIRD_PARTY_NOTICES.md') &&
        gate.contains(r'if [[ "$source" == true && "$bundle" == true ]]') &&
        gate.contains(
          'A pull request may not mix canonical native inputs with generated bundle files.',
        ),
    'workflow path enumeration is NUL-safe and fail-closed':
        !generation.contains('< <(') &&
        !gate.contains('< <(') &&
        generation.contains(r'git diff --name-only -z > "$tracked_paths"') &&
        generation.contains(
          r'git ls-files --others --exclude-standard -z > "$untracked_paths"',
        ) &&
        generation.contains(
          r'sort -zu "$tracked_paths" "$untracked_paths" > "$changed_paths"',
        ) &&
        generation.contains(r'-print0 > "$binary_paths"') &&
        gate.contains(r'-print0 > "$binary_paths"') &&
        gate.contains(
          r'git ls-tree -r -z --name-only HEAD -- "$prefix" > "$tree_paths"',
        ),
    'notice synchronization is portable to macOS BSD userland':
        noticeSync.contains(r'chmod 0644 "$output"') &&
        !noticeSync.contains('chmod --reference') &&
        !noticeSync.contains('mv --') &&
        !noticeSync.contains('rm -rf --'),
    'source pull requests build and overlay an exact-SHA candidate':
        gate.contains('  build-candidate:\n') &&
        gate.contains("    if: needs.classify.outputs.source == 'true'") &&
        gate.contains(
          '    uses: ./.github/workflows/native-bundle-build.yml',
        ) &&
        gate.contains(r'      source_sha: ${{ github.sha }}') &&
        gate.contains('          name: native-bundle-candidate') &&
        gate.contains('          path: .native-bundle-candidate') &&
        gate.contains(
          r'bash .github/scripts/overlay-native-artifacts.sh "$candidate"',
        ) &&
        gate.contains(
          r'install -m 0644 "$candidate/native/artifacts.manifest.json" native/artifacts.manifest.json',
        ) &&
        gate.contains(
          r'bash .github/scripts/sync-native-notices-from-candidate.sh "$candidate"',
        ) &&
        gate.contains(r'git check-attr filter -- "$path"') &&
        gate.contains('Candidate binary is not covered by a Git LFS rule') &&
        gate.contains('(( binary_count > 0 ))') &&
        gate.contains("if: needs.classify.outputs.bundle == 'true'"),
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
        gate.contains('sudo udevadm settle') &&
        gate.contains(r'[[ -c /dev/kvm ]]') &&
        gate.contains('sudo chmod 0666 /dev/kvm') &&
        gate.contains(r'[[ -r /dev/kvm && -w /dev/kvm ]]') &&
        gate.contains(r'"$ANDROID_SDK_ROOT/emulator/emulator" -accel-check') &&
        gate.indexOf('sudo udevadm trigger --name-match=kvm') <
            gate.indexOf('sudo udevadm settle') &&
        gate.indexOf('sudo udevadm settle') <
            gate.indexOf(r'[[ -c /dev/kvm ]]') &&
        gate.indexOf(r'[[ -c /dev/kvm ]]') <
            gate.indexOf('sudo chmod 0666 /dev/kvm') &&
        gate.indexOf('sudo chmod 0666 /dev/kvm') <
            gate.indexOf(r'[[ -r /dev/kvm && -w /dev/kvm ]]') &&
        gate.indexOf(r'[[ -r /dev/kvm && -w /dev/kvm ]]') <
            gate.indexOf(
              r'"$ANDROID_SDK_ROOT/emulator/emulator" -accel-check',
            ) &&
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
    'all pull-request modes pass through the stable aggregate check':
        gate.contains('    name: native-bundle-gate') &&
        gate.contains('    if: always()') &&
        gate.contains('      - build-candidate') &&
        gate.contains(
          r'BUILD_CANDIDATE_RESULT: ${{ needs.build-candidate.result }}',
        ) &&
        gate.contains(r'if [[ "$SOURCE" == true ]]') &&
        gate.contains(r'if [[ "$SOURCE" != true && "$BUNDLE" != true ]]') &&
        gate.contains('the gate passes without platform jobs.'),
    'Unix workflow scripts are made executable at runtime':
        build.contains('chmod +x tool/native.sh') &&
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
