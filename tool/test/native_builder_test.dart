import 'dart:convert';
import 'dart:io';

import '../src/native_builder.dart';

Future<void> main() async {
  final repository = Directory.current;
  final builder = NativeBuilder.fromRepository(repository);

  final invocation = NativeInvocation.parse([
    'build',
    'android',
    '--arch',
    'arm64-v8a,x86_64',
    '--offline',
  ]);
  _expect(invocation.target == NativeTarget.android, 'parses Android target');
  _expect(invocation.offline, 'parses --offline');
  _expect(
    invocation.architectures.join(',') == 'arm64-v8a,x86_64',
    'parses comma-separated architectures',
  );

  final androidCommands = builder.generatedCommands(
    NativeTarget.android,
    const ['arm64-v8a'],
  );
  final androidText = androidCommands.toString();
  for (final expected in [
    'ANDROID_NDK_ROOT',
    'ANDROID_NDK',
    'CC: clang',
    'CXX: clang++',
    'ndk-llvm-toolchain-bin',
    if (Platform.isWindows) ...[
      'git-for-windows-posix-perl',
      'pinned-perl-pure-modules',
      'MSYS2_ENV_CONV_EXCL',
      'PERL5LIB',
    ],
  ]) {
    _expect(
      androidText.contains(expected),
      'Android OpenSSL command contains $expected',
    );
  }
  _expect(
    androidText.contains('step: strip') &&
        androidText.contains('<ndk-llvm-toolchain-bin>/llvm-strip') &&
        androidText.contains('--strip-unneeded'),
    'Android commands strip release artifacts with the pinned NDK tool',
  );
  _expect(
    androidText.contains('-DSTN_BUILD_TESTS=OFF'),
    'Android artifact builds omit maintainer-only native tests',
  );
  final windowsText = builder.generatedCommands(NativeTarget.windows, const [
    'x64',
  ]).toString();
  _expect(
    windowsText.contains('-DSTN_BUILD_TESTS=ON') &&
        windowsText.contains('step: ctest') &&
        windowsText.contains('simple_torrent_native_session_suspension_test') &&
        windowsText.contains('--no-tests=error'),
    'Windows command generation faithfully includes the native suspension test',
  );
  _expect(
    validateArtifactRelativePath(r'packages\plugin\artifact.bin') ==
        'packages/plugin/artifact.bin',
    'normalizes safe artifact manifest separators',
  );
  for (final unsafePath in [
    r'..\outside.bin',
    '../outside.bin',
    r'C:\outside.bin',
    '/outside.bin',
    'packages//artifact.bin',
  ]) {
    _expectThrows(
      () => validateArtifactRelativePath(unsafePath),
      'rejects unsafe artifact manifest path $unsafePath',
    );
  }
  const stagedArm64 =
      'packages/simple_torrent_android/android/src/main/jniLibs/'
      'arm64-v8a/libsimple_torrent_native.so';
  validateAndroidArtifactInventory(
    const [
      stagedArm64,
      'packages/simple_torrent_android/android/src/main/cpp/include/'
          'simple_torrent_native.h',
    ],
    const ['arm64-v8a'],
  );
  _expect(true, 'accepts an exact requested Android artifact inventory');
  _expectThrows(
    () => validateAndroidArtifactInventory(
      const [
        stagedArm64,
        'packages/simple_torrent_android/android/src/main/jniLibs/'
            'x86/libsimple_torrent_native.so',
      ],
      const ['arm64-v8a'],
    ),
    'rejects an unrequested stale Android SO before manifest writing',
  );
  _expectThrows(
    () => validateAndroidArtifactInventory(const [], const ['arm64-v8a']),
    'rejects a missing requested Android SO before manifest writing',
  );
  for (final target in NativeTarget.values) {
    validateExactStagedArtifactPaths(
      target,
      const [r'packages\plugin\artifact.bin'],
      const ['packages/plugin/artifact.bin'],
    );
    _expect(
      true,
      '${target.cliName} staged inventory compares normalized paths',
    );
    _expectThrows(
      () => validateExactStagedArtifactPaths(
        target,
        const ['packages/plugin/artifact.bin'],
        const ['packages/plugin/artifact.bin', 'packages/plugin/stale.bin'],
      ),
      '${target.cliName} staged inventory rejects an unmanifested file',
    );
    _expectThrows(
      () => validateExactStagedArtifactPaths(target, const [
        'packages/plugin/artifact.bin',
      ], const []),
      '${target.cliName} staged inventory rejects a missing file',
    );
  }
  _expectThrows(
    () => validateExactStagedArtifactPaths(
      NativeTarget.windows,
      const [r'packages\plugin\artifact.bin', 'packages/plugin/artifact.bin'],
      const ['packages/plugin/artifact.bin'],
    ),
    'staged inventory rejects duplicate normalized manifest paths',
  );

  final iosArchitectures = builder.normalizedArchitectures(
    NativeTarget.ios,
    const [],
  );
  _expect(
    iosArchitectures.join(',') == 'arm64,sim-arm64,sim-x86_64',
    'uses all required iOS slices',
  );
  final ios = builder.generatedCommands(NativeTarget.ios, iosArchitectures);
  final iosText = ios.toString();
  for (final expected in [
    'ios64-xcrun',
    'iossimulator-arm64-xcrun',
    'iossimulator-x86_64-xcrun',
    '15.0',
    'embedded-ca-bundle',
    '2026-08-13',
    'f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9',
    'IPHONEOS_DEPLOYMENT_TARGET',
    '15.0',
  ]) {
    _expect(iosText.contains(expected), 'iOS command contains $expected');
  }

  final macosArchitectures = builder.normalizedArchitectures(
    NativeTarget.macos,
    const [],
  );
  final macos = builder.generatedCommands(
    NativeTarget.macos,
    macosArchitectures,
  );
  final macosText = macos.toString();
  for (final expected in [
    'darwin64-arm64-cc',
    'darwin64-x86_64-cc',
    'MACOSX_DEPLOYMENT_TARGET',
    '12.0',
  ]) {
    _expect(macosText.contains(expected), 'macOS command contains $expected');
  }

  final temporary = await Directory.systemTemp.createTemp('stn-sha-test-');
  try {
    final file = File('${temporary.path}${Platform.pathSeparator}abc.txt');
    await file.writeAsString('abc');
    _expect(
      await Sha256.file(file) ==
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      'SHA-256 implementation matches the standard vector',
    );
  } finally {
    await temporary.delete(recursive: true);
  }

  final pruningRoot = await Directory.systemTemp.createTemp(
    'stn-android-stage-test-',
  );
  try {
    final lockDirectory = Directory(
      '${pruningRoot.path}${Platform.pathSeparator}native',
    );
    await lockDirectory.create(recursive: true);
    await File('native/dependencies.lock.json').copy(
      '${lockDirectory.path}${Platform.pathSeparator}dependencies.lock.json',
    );
    final pruningBuilder = NativeBuilder.fromRepository(pruningRoot);
    final jniRoot = Directory(
      [
        pruningRoot.path,
        'packages',
        'simple_torrent_android',
        'android',
        'src',
        'main',
        'jniLibs',
      ].join(Platform.pathSeparator),
    );
    final libraries = <String, File>{};
    final sentinels = <String, File>{};
    for (final architecture in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      final directory = Directory(
        '${jniRoot.path}${Platform.pathSeparator}$architecture',
      );
      await directory.create(recursive: true);
      libraries[architecture] = await File(
        '${directory.path}${Platform.pathSeparator}'
        'libsimple_torrent_native.so',
      ).writeAsString(architecture);
      sentinels[architecture] = await File(
        '${directory.path}${Platform.pathSeparator}keep.txt',
      ).writeAsString('keep');
    }
    await pruningBuilder.pruneUnrequestedAndroidArtifacts(const ['x86_64']);
    _expect(
      libraries['x86_64']!.existsSync() &&
          !libraries['arm64-v8a']!.existsSync() &&
          !libraries['armeabi-v7a']!.existsSync(),
      'partial Android staging retains only the requested known ABI binary',
    );
    _expect(
      sentinels.values.every((file) => file.existsSync()),
      'partial Android staging does not broadly delete ABI directories',
    );
  } finally {
    await pruningRoot.delete(recursive: true);
  }

  final inventoryRoot = await Directory.systemTemp.createTemp(
    'stn-artifact-inventory-test-',
  );
  try {
    final nativeDirectory = Directory(
      '${inventoryRoot.path}${Platform.pathSeparator}native',
    );
    await nativeDirectory.create(recursive: true);
    await File('native/dependencies.lock.json').copy(
      '${nativeDirectory.path}${Platform.pathSeparator}'
      'dependencies.lock.json',
    );
    final inventoryBuilder = NativeBuilder.fromRepository(inventoryRoot);
    final targetFiles = <NativeTarget, String>{
      NativeTarget.windows:
          'packages/simple_torrent_windows/windows/lib/x64/'
          'simple_torrent_native.dll',
      NativeTarget.android:
          'packages/simple_torrent_android/android/src/main/jniLibs/x86_64/'
          'libsimple_torrent_native.so',
      NativeTarget.ios:
          'packages/simple_torrent_ios/ios/Frameworks/'
          'SimpleTorrentNative.xcframework/ios-arm64/'
          'libsimple_torrent_native.a',
      NativeTarget.macos:
          'packages/simple_torrent_macos/macos/Frameworks/'
          'SimpleTorrentNative.xcframework/macos-universal/'
          'libsimple_torrent_native.a',
    };
    for (final entry in targetFiles.entries) {
      final staged = File(
        [
          inventoryRoot.path,
          ...entry.value.split('/'),
        ].join(Platform.pathSeparator),
      );
      await staged.parent.create(recursive: true);
      await staged.writeAsString('artifact');
      await inventoryBuilder.validateStagedArtifactInventory(entry.key, [
        entry.value,
      ]);
      _expect(
        true,
        '${entry.key.cliName} verifier accepts an exact live staged tree',
      );
      final extra = File(
        '${staged.parent.path}${Platform.pathSeparator}unmanifested.bin',
      );
      await extra.writeAsString('stale');
      await _expectThrowsAsync(
        () => inventoryBuilder.validateStagedArtifactInventory(entry.key, [
          entry.value,
        ]),
        '${entry.key.cliName} verifier enumerates and rejects an extra staged file',
      );
      await extra.delete();
      await staged.delete();
      await _expectThrowsAsync(
        () => inventoryBuilder.validateStagedArtifactInventory(entry.key, [
          entry.value,
        ]),
        '${entry.key.cliName} verifier enumerates and rejects a missing staged file',
      );
    }
  } finally {
    await inventoryRoot.delete(recursive: true);
  }

  final expectedProvenance = await builder.expectedArtifactManifestProvenance();
  await builder.validateArtifactManifestProvenance(expectedProvenance);
  _expect(true, 'accepts manifest provenance derived from the current lock');

  Map<String, Object?> cloneExpectedProvenance() =>
      (jsonDecode(jsonEncode(expectedProvenance)) as Map)
          .cast<String, Object?>();

  final provenanceMutations = <(String, void Function(Map<String, Object?>))>[
    (
      'rejects a stale manifest schema',
      (manifest) => manifest['schemaVersion'] = 999,
    ),
    (
      'rejects a stale native builder version',
      (manifest) => manifest['builderVersion'] = '1.0.0',
    ),
    (
      'rejects a stale native C ABI version',
      (manifest) => manifest['nativeAbi'] = 1,
    ),
    (
      'rejects a stale reproducibility epoch',
      (manifest) => manifest['sourceDateEpoch'] = 0,
    ),
    (
      'rejects a stale dependency version',
      (manifest) =>
          ((manifest['dependencies']! as Map)['libtorrent']!
                  as Map)['version'] =
              '0.0.0',
    ),
    (
      'rejects a stale dependency archive checksum',
      (manifest) =>
          ((manifest['dependencies']! as Map)['openssl']!
              as Map)['archiveSha256'] = '0'.padLeft(
            64,
            '0',
          ),
    ),
    (
      'rejects a changed canonical patch path',
      (manifest) =>
          ((((manifest['dependencies']! as Map)['boost']! as Map)['patches']!
                          as List)
                      .single
                  as Map)['path'] =
              'native/patches/other.patch',
    ),
    (
      'rejects a changed canonical patch checksum',
      (manifest) =>
          ((((manifest['dependencies']! as Map)['boost']! as Map)['patches']!
                      as List)
                  .single
              as Map)['sha256'] = '0'.padLeft(
            64,
            '0',
          ),
    ),
    (
      'rejects a stale pinned toolchain',
      (manifest) =>
          (manifest['toolchains']! as Map)['androidNdk'] = 'untrusted',
    ),
  ];
  for (final mutation in provenanceMutations) {
    await _expectThrowsAsync(() async {
      final manifest = cloneExpectedProvenance();
      mutation.$2(manifest);
      await builder.validateArtifactManifestProvenance(manifest);
    }, mutation.$1);
  }

  final expectedAndroidBuildProvenance = await builder
      .expectedPlatformBuildProvenance(NativeTarget.android, const ['x86_64']);
  final androidPlatformRecord = <String, Object?>{
    'architectures': const ['x86_64'],
    'buildProvenance': expectedAndroidBuildProvenance,
  };
  await builder.validatePlatformBuildProvenance(
    NativeTarget.android,
    androidPlatformRecord,
  );
  _expect(
    true,
    'accepts target build provenance from current canonical native inputs',
  );

  Map<String, Object?> cloneJsonMap(Map<String, Object?> value) =>
      (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();

  for (final mutation in <(String, void Function(Map<String, Object?>))>[
    (
      'rejects a target provenance dependency mutation',
      (platform) {
        final build = platform['buildProvenance']! as Map;
        final inputs = build['artifactInputs']! as Map;
        final dependencies = inputs['dependencies']! as Map;
        final libtorrent = dependencies['libtorrent']! as Map;
        libtorrent['archiveSha256'] = '0'.padLeft(64, '0');
      },
    ),
    (
      'rejects a target canonical input digest mutation',
      (platform) {
        final build = platform['buildProvenance']! as Map;
        final nativeInputs = build['nativeInputs']! as Map;
        nativeInputs['sha256'] = '0'.padLeft(64, '0');
      },
    ),
    (
      'rejects a target canonical input file mutation',
      (platform) {
        final build = platform['buildProvenance']! as Map;
        final nativeInputs = build['nativeInputs']! as Map;
        final firstFile = (nativeInputs['files']! as List).first as Map;
        firstFile['sha256'] = '0'.padLeft(64, '0');
      },
    ),
    (
      'rejects a target native build recipe mutation',
      (platform) {
        final build = platform['buildProvenance']! as Map;
        final recipe = build['recipe']! as Map;
        recipe['buildType'] = 'Debug';
      },
    ),
  ]) {
    await _expectThrowsAsync(() async {
      final platform = cloneJsonMap(androidPlatformRecord);
      mutation.$2(platform);
      await builder.validatePlatformBuildProvenance(
        NativeTarget.android,
        platform,
      );
    }, mutation.$1);
  }

  final staleAndroidPlatform = cloneJsonMap(androidPlatformRecord);
  (((staleAndroidPlatform['buildProvenance']! as Map)['artifactInputs']!
          as Map)['builderVersion'] =
      'stale-builder');
  final staleAndroidBefore = jsonEncode(staleAndroidPlatform);
  final expectedWindowsBuildProvenance = await builder
      .expectedPlatformBuildProvenance(NativeTarget.windows, const ['x64']);
  final composedManifest = builder.composeArtifactManifest(
    existingManifest: {
      'platforms': {'android': staleAndroidPlatform},
    },
    rootProvenance: expectedProvenance,
    target: NativeTarget.windows,
    targetPlatform: {
      'architectures': const ['x64'],
      'hostTools': const <String, Object?>{},
      'buildProvenance': expectedWindowsBuildProvenance,
    },
  );
  final composedPlatforms = (composedManifest['platforms']! as Map);
  _expect(
    jsonEncode(composedPlatforms['android']) == staleAndroidBefore,
    'rebuilding Windows preserves stale Android provenance verbatim',
  );
  _expect(
    (composedPlatforms['windows']! as Map)['buildProvenance'] ==
        expectedWindowsBuildProvenance,
    'rebuilding Windows replaces only the Windows provenance record',
  );
  await _expectThrowsAsync(
    () => builder.validatePlatformBuildProvenance(
      NativeTarget.android,
      (composedPlatforms['android']! as Map).cast<String, Object?>(),
    ),
    'preserved stale Android provenance still fails current verification',
  );

  final fingerprintRoot = await Directory.systemTemp.createTemp(
    'stn-native-input-test-',
  );
  try {
    Future<File> writeInput(String relative, String content) async {
      final file = File(
        [
          fingerprintRoot.path,
          ...relative.split('/'),
        ].join(Platform.pathSeparator),
      );
      await file.parent.create(recursive: true);
      return file.writeAsString(content);
    }

    await writeInput(
      'native/dependencies.lock.json',
      await File('native/dependencies.lock.json').readAsString(),
    );
    await writeInput('native/CMakeLists.txt', 'cmake\r\n');
    await writeInput('native/include/api.h', 'api\r\n');
    final mutableInput = await writeInput(
      'native/src/core.cpp',
      'same\r\ncontent\r\n',
    );
    await writeInput('native/patches/example.patch', 'patch\r\n');
    await writeInput('native/test/session_suspension_test.cpp', 'test\r\n');
    await writeInput('tool/native.dart', 'entry\r\n');
    await writeInput('tool/native.ps1', 'powershell\r\n');
    await writeInput('tool/native.sh', 'shell\r\n');
    await writeInput('tool/src/native_builder.dart', 'builder\r\n');
    final fingerprintBuilder = NativeBuilder.fromRepository(fingerprintRoot);
    final crlfFingerprint = await fingerprintBuilder
        .canonicalNativeInputFingerprint(NativeTarget.windows);
    await mutableInput.writeAsString('same\ncontent\n');
    final lfFingerprint = await fingerprintBuilder
        .canonicalNativeInputFingerprint(NativeTarget.windows);
    _expect(
      jsonEncode(crlfFingerprint) == jsonEncode(lfFingerprint),
      'canonical native input fingerprint normalizes host line endings',
    );
    await mutableInput.writeAsString('changed\ncontent\n');
    final changedFingerprint = await fingerprintBuilder
        .canonicalNativeInputFingerprint(NativeTarget.windows);
    _expect(
      changedFingerprint['sha256'] != lfFingerprint['sha256'],
      'canonical native input fingerprint changes with native source content',
    );
    final fingerprintPaths = ((changedFingerprint['files']! as List))
        .cast<Map>()
        .map((record) => record['path']);
    _expect(
      fingerprintPaths.contains('native/CMakeLists.txt') &&
          fingerprintPaths.contains('native/include/api.h') &&
          fingerprintPaths.contains('native/src/core.cpp') &&
          fingerprintPaths.contains('native/patches/example.patch') &&
          fingerprintPaths.contains(
            'native/test/session_suspension_test.cpp',
          ) &&
          fingerprintPaths.contains('tool/src/native_builder.dart'),
      'canonical fingerprint covers native core, tests, patches, and builder inputs',
    );
  } finally {
    await fingerprintRoot.delete(recursive: true);
  }

  _expect(
    File('native/dependencies.lock.json').existsSync(),
    'dependency lock exists',
  );
  final dependencyLock = await File('native/dependencies.lock.json')
      .readAsString();
  _expect(
    dependencyLock.contains('cacert-2026-08-13.pem') &&
        dependencyLock.contains(
          'f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9',
        ),
    'Apple CA bundle URL and checksum are pinned',
  );
  _expect(
    (await File(
      'native/CMakeLists.txt',
    ).readAsString()).contains('STN_CA_BUNDLE_FILE'),
    'native build accepts the pinned CA bundle input',
  );
  final nativeCmake = await File('native/CMakeLists.txt').readAsString();
  _expect(
    nativeCmake.contains('NO_CMAKE_FIND_ROOT_PATH') &&
        nativeCmake.contains('set(Boost_INCLUDE_DIR'),
    'cross builds use the pinned Boost headers outside the target sysroot',
  );
  _expect(
    nativeCmake.contains('enable_testing()') &&
        nativeCmake.contains('PROPERTIES TIMEOUT 30'),
    'Windows native suspension CTest is always registered and time-bounded',
  );
  final boostPatch = File(
    'native/patches/boost-1.91.0-android-x86_64-long-double.patch',
  );
  _expect(boostPatch.existsSync(), 'pinned Boost x86_64 patch exists');
  _expect(
    (await boostPatch.readAsString()).contains('LDBL_MANT_DIG == 64'),
    'Boost patch routes IEEE-128 Android x86_64 long double correctly',
  );
  _expect(
    (await File(
      '.gitattributes',
    ).readAsString()).contains('/native/patches/*.patch text eol=lf'),
    'native patch identity uses stable LF bytes on every host',
  );
  _expect(
    (await File(
      'native/include/simple_torrent_native.h',
    ).readAsString()).contains('simple_torrent_embedded_ca_bundle'),
    'C ABI exposes the embedded CA bundle bytes',
  );
  final builderSource = (await File(
    'tool/src/native_builder.dart',
  ).readAsString()).replaceAll('\r\n', '\n');
  for (final expected in [
    '_findGitPosixPerl',
    '_prepareAndroidPerlModules',
    "_join('Locale', 'Maketext')",
    "'ExtUtils'",
    "'Pod'",
    "'MSYS2_ENV_CONV_EXCL'",
    '-DOPENSSL_SSL_LIBRARY=',
    '-DOPENSSL_CRYPTO_LIBRARY=',
    '.simple-torrent-openssl-build.json',
    "'relative-prefix-map-v1'",
    "'-ffile-prefix-map=.=build/openssl'",
    "'configureOptions': configureOptions",
    "'toolIdentity': toolIdentity",
    "'sslSha256'",
    "'cryptoSha256'",
    "'prefixFiles'",
    "'--exec-path'",
    "operatingSystem == 'msys'",
    "result['posixPerl']",
    "'.simple-torrent-tool.json'",
    '_directoryFingerprint',
    'resolveSymbolicLinksSync',
    '_sourcePatchRecords',
    '_sourcePatchesAreApplied',
    '_expectedBoostLongDoublePatch',
    "'patches': await _sourcePatchRecords(entry.value)",
    'excludedFile: stamp',
    'await pruneUnrequestedAndroidArtifacts(architectures);',
    "environment['LC_ALL'] = 'C';",
    "environment['LANG'] = 'C';",
    'await validateArtifactManifestProvenance(manifest);',
    'await validatePlatformBuildProvenance(target, platformRecord);',
    'canonicalNativeInputFingerprint',
    "'buildProvenance': await expectedPlatformBuildProvenance(",
    'await validateStagedArtifactInventory(target, manifestPaths);',
    'followLinks: false',
    'entry is Link',
    "'--no-tests=error'",
    "'/EXPORTS'",
    "'--dyn-syms'",
    "'nm'",
    "'-gU'",
  ]) {
    _expect(
      builderSource.contains(expected),
      'Windows Android bootstrap contains $expected',
    );
  }
  final copiedAndroidLibrary = builderSource.indexOf(
    'await library.copy(strippedLibrary.path);',
  );
  final strippedAndroidLibrary = builderSource.indexOf(
    "await _run(strip.path, [\n        '--strip-unneeded',",
  );
  final stagedAndroidLibrary = builderSource.indexOf(
    'await _stageFile(\n        strippedLibrary,',
  );
  _expect(
    builderSource.contains('libsimple_torrent_native.stripped.so') &&
        copiedAndroidLibrary >= 0 &&
        strippedAndroidLibrary > copiedAndroidLibrary &&
        stagedAndroidLibrary > strippedAndroidLibrary,
    'Android staging strips a copied intermediate before publication',
  );
  final inventoryValidation = builderSource.indexOf(
    'await validateStagedArtifactInventory(target, manifestPaths);',
  );
  final artifactChecksum = builderSource.indexOf(
    'final digest = await Sha256.file(file);',
    inventoryValidation,
  );
  _expect(
    inventoryValidation >= 0 && artifactChecksum > inventoryValidation,
    'verifier compares the live staged set before artifact checksums',
  );
  final artifactEnumerationStart = builderSource.indexOf(
    'Future<List<File>> _artifactFiles',
  );
  final artifactEnumerationEnd = builderSource.indexOf(
    'Future<void> _verifyWindows',
    artifactEnumerationStart,
  );
  final artifactEnumerationSource = builderSource.substring(
    artifactEnumerationStart,
    artifactEnumerationEnd,
  );
  _expect(
    artifactEnumerationSource.contains('followLinks: false') &&
        artifactEnumerationSource.contains('entry is Link') &&
        artifactEnumerationSource.contains('_requireStrictlyWithin('),
    'staged-file enumeration rejects links and repository escapes',
  );
  final manifestFlagsStart = builderSource.indexOf(
    'List<String> _reproducibleBuildFlags',
  );
  final manifestFlagsEnd = manifestFlagsStart < 0
      ? -1
      : builderSource.indexOf(
          'Future<Map<String, Object?>> _hostToolVersions',
          manifestFlagsStart,
        );
  final manifestFlagsSource = manifestFlagsStart >= 0 && manifestFlagsEnd > 0
      ? builderSource.substring(manifestFlagsStart, manifestFlagsEnd)
      : '';
  _expect(
    manifestFlagsSource.contains("if (target == NativeTarget.android) ...[") &&
        manifestFlagsSource.contains("'llvm-strip=--strip-unneeded'"),
    'Android manifest build flags record release stripping',
  );
  _expect(
    builderSource.contains(r"RegExp(r'\.debug_[a-z0-9_]+')") &&
        builderSource.contains(r"RegExp(r'\] \.symtab\b')") &&
        builderSource.contains(r"RegExp(r'\] \.strtab\b')"),
    'Android verifier rejects debug and static symbol-table sections',
  );
  _expect(
    builderSource.contains("import 'dart:isolate';") &&
        builderSource.contains('if (workerCount > 8) workerCount = 8;') &&
        builderSource.contains(
          'if (workerCount > candidates.length) workerCount = candidates.length;',
        ) &&
        builderSource.contains('Isolate.run('),
    'directory fingerprints use at most eight bounded isolate workers',
  );
  _expect(
    builderSource.contains(
          "NativeTarget.windows || NativeTarget.android => 'static'",
        ) &&
        builderSource.contains(
          "NativeTarget.ios || NativeTarget.macos => 'system'",
        ),
    'manifest records target-specific C++ runtime linkage',
  );
  _expect(
    builderSource.contains("'hostTools': hostTools") &&
        builderSource.contains('hostToolsByPlatform[entry.key]'),
    'manifest preserves host tool versions per platform',
  );
  final opensslBuildStart = builderSource.indexOf(
    'Future<Directory> _buildOpenSsl',
  );
  final opensslIdentityStart = builderSource.indexOf(
    'final identity = <String, Object?>{',
    opensslBuildStart,
  );
  final opensslIdentityEnd = builderSource.indexOf(
    'var reusable = false;',
    opensslIdentityStart,
  );
  final opensslIdentitySource = builderSource.substring(
    opensslIdentityStart,
    opensslIdentityEnd,
  );
  _expect(
    !opensslIdentitySource.contains('LC_ALL') &&
        !opensslIdentitySource.contains('LANG'),
    'portable Windows locale does not invalidate the OpenSSL cache recipe',
  );
  for (final forbiddenWindowsRuntime in [
    'vcruntime',
    'msvcp',
    'ucrtbase.dll',
    'api-ms-win-crt-',
  ]) {
    _expect(
      builderSource.contains(forbiddenWindowsRuntime),
      'Windows verifier rejects $forbiddenWindowsRuntime',
    );
  }
  _expect(
    File('native/licenses/llvm-libcxx.txt').existsSync() &&
        File(
          'packages/simple_torrent_android/third_party_licenses/llvm-libcxx.txt',
        ).existsSync(),
    'Android static libc++ terms are distributed',
  );
  final androidJni = await File(
    'native/platform/android/simple_torrent_android.cpp',
  ).readAsString();
  final androidAdapter = (await File(
    'packages/simple_torrent_android/android/src/main/kotlin/'
    'com/leapwardkoex/simple_torrent/simple_torrent/SimpleTorrentPlugin.kt',
  ).readAsString()).replaceAll('\r\n', '\n');
  _expect(
    androidJni.contains('jobject QueryResult') &&
        androidJni.contains('MapPut(env, map, "code"') &&
        androidJni.contains('MapPut(env, map, "value"'),
    'Android JNI queries preserve native result codes in an envelope',
  );
  for (final query in [
    'nativeActiveIds',
    'nativeExists',
    'nativeState',
    'nativeTorrentInfo',
    'nativeLastError',
  ]) {
    _expect(
      androidAdapter.contains(
            'completeNativeQuery(\n                    $query',
          ) ||
          androidAdapter.contains(
            'completeNativeQuery(\n                $query',
          ),
      'Android adapter decodes $query without collapsing failures',
    );
  }

  final applePackages = {
    'ios': {
      'minimum': '15',
      'root': 'packages/simple_torrent_ios/ios',
      'package': 'simple_torrent_ios',
    },
    'macos': {
      'minimum': '12',
      'root': 'packages/simple_torrent_macos/macos',
      'package': 'simple_torrent_macos',
    },
  };
  for (final entry in applePackages.entries) {
    final values = entry.value;
    final root = values['root']!;
    final packageName = values['package']!;
    final packageFile = File('$root/$packageName/Package.swift');
    final podspec = File('$root/$packageName.podspec');
    final source = File(
      '$root/$packageName/Sources/$packageName/SimpleTorrentPlugin.swift',
    );
    _expect(packageFile.existsSync(), '${entry.key} SwiftPM manifest exists');
    _expect(podspec.existsSync(), '${entry.key} CocoaPods fallback exists');
    _expect(source.existsSync(), '${entry.key} Swift adapter exists');
    final packageText = await packageFile.readAsString();
    final podspecText = await podspec.readAsString();
    final sourceText = await source.readAsString();
    _expect(
      packageText.contains('SimpleTorrentNative.xcframework'),
      '${entry.key} SwiftPM uses only the local XCFramework',
    );
    _expect(
      podspecText.contains("Frameworks/SimpleTorrentNative.xcframework"),
      '${entry.key} podspec uses only the local XCFramework',
    );
    for (final framework in [
      'CoreFoundation',
      'Security',
      'SystemConfiguration',
    ]) {
      _expect(
        packageText.contains('.linkedFramework("$framework")') &&
            podspecText.contains("'$framework'"),
        '${entry.key} links required $framework system framework',
      );
    }
    _expect(
      packageText.contains(values['minimum']!) &&
          podspecText.contains("'${values['minimum']}.0'"),
      '${entry.key} minimum deployment is pinned',
    );
    for (final forbidden in [
      '/Users/',
      '/usr/local/',
      'Homebrew',
      'startFromTorrent',
    ]) {
      _expect(
        !'$packageText\n$podspecText\n$sourceText'.contains(forbidden),
        '${entry.key} files omit $forbidden',
      );
    }
    for (final method in ['updateConfig', 'startFromData', 'startFromFile']) {
      _expect(sourceText.contains('"$method"'), '${entry.key} handles $method');
    }
    for (final adapterRequirement in [
      'simple_torrent_embedded_ca_bundle',
      'applicationSupportDirectory',
      'SSL_CERT_FILE',
      'options: .atomic',
      'nativeCreationLock',
      'maxBufferedEvents',
      'metadataBuffer',
      'listenForMetadata',
      '"eventType": "stats"',
      '"eventType": "metadata"',
      '"v2": metadata.isV2 != 0',
      'if call.method == "init", arguments?["config"] == nil',
      'not_initialized',
      'invalid_magnet',
      'invalid_torrent_data',
      'invalid_torrent_file',
    ]) {
      _expect(
        sourceText.contains(adapterRequirement),
        '${entry.key} adapter contains $adapterRequirement',
      );
    }
  }
  stdout.writeln('{"ok":true,"suite":"native-builder"}');
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError('FAILED: $description');
  stdout.writeln('PASS: $description');
}

void _expectThrows(void Function() operation, String description) {
  try {
    operation();
  } on StateError {
    stdout.writeln('PASS: $description');
    return;
  }
  throw StateError('FAILED: $description');
}

Future<void> _expectThrowsAsync(
  Future<void> Function() operation,
  String description,
) async {
  try {
    await operation();
  } on StateError {
    stdout.writeln('PASS: $description');
    return;
  }
  throw StateError('FAILED: $description');
}
