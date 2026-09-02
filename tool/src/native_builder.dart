import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

const nativeArtifactManifestSchemaVersion = 2;
const nativeBuilderVersion = '2.1.1';
const simpleTorrentNativeAbiVersion = 2;
const nativePlatformProvenanceSchemaVersion = 1;
const nativeInputFingerprintSchemaVersion = 1;

const _supportedAndroidArchitectures = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
const _appleStaticArchiveName = 'libsimple_torrent_native.a';
const _generatedNoticeStart = '<!-- BEGIN GENERATED NATIVE DEPENDENCIES -->';
const _generatedNoticeEnd = '<!-- END GENERATED NATIVE DEPENDENCIES -->';

enum NativeAction {
  build,
  verify,
  clean,
  purgeCache,
  assemble,
  syncMetadata,
  help,
}

enum NativeTarget { windows, android, ios, macos }

extension NativeTargetName on NativeTarget {
  String get cliName => name;

  static NativeTarget parse(String value) {
    return NativeTarget.values.firstWhere(
      (target) => target.cliName == value.toLowerCase(),
      orElse: () => throw NativeUsageException(
        'Unknown platform "$value". Expected windows, android, ios, or macos.',
      ),
    );
  }
}

final class NativeUsageException implements Exception {
  NativeUsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class NativeInvocation {
  const NativeInvocation({
    required this.action,
    this.target,
    this.architectures = const <String>[],
    this.offline = false,
    this.dryRun = false,
    this.purgeName,
    this.sourceSha,
    this.manifestFragments = const <NativeTarget, String>{},
    this.outputPath,
  });

  final NativeAction action;
  final NativeTarget? target;
  final List<String> architectures;
  final bool offline;
  final bool dryRun;
  final String? purgeName;
  final String? sourceSha;
  final Map<NativeTarget, String> manifestFragments;
  final String? outputPath;

  static const usage = '''
Usage:
  tool/native.ps1 build <windows|android|ios|macos> [--arch <arch>] [--offline]
  tool/native.ps1 verify <windows|android|ios|macos>
  tool/native.ps1 clean <windows|android|ios|macos>
  tool/native.ps1 purge-cache [all|libtorrent|boost|openssl|mozilla-ca-bundle|tools]
  tool/native.ps1 assemble --source-sha <git-sha>
    --fragment windows=<manifest> --fragment android=<manifest>
    --fragment ios=<manifest> --fragment macos=<manifest> [--output <manifest>]
  tool/native.ps1 sync-metadata

The shell equivalent is tool/native.sh. --arch may be repeated or contain a
comma-separated list. On Android, --arch replaces the complete staged ABI set.
Pass --source-sha to build in CI so independently built manifest fragments can
be authenticated and assembled. The source SHA must be a full 40-character Git
commit ID.
Set SIMPLE_TORRENT_NATIVE_TRACE=1 for stack traces.''';

  static NativeInvocation parse(List<String> arguments) {
    if (arguments.isEmpty ||
        arguments.first == 'help' ||
        arguments.first == '--help') {
      return const NativeInvocation(action: NativeAction.help);
    }

    final actionName = arguments.first;
    final action = switch (actionName) {
      'build' => NativeAction.build,
      'verify' => NativeAction.verify,
      'clean' => NativeAction.clean,
      'purge-cache' => NativeAction.purgeCache,
      'assemble' => NativeAction.assemble,
      'sync-metadata' => NativeAction.syncMetadata,
      _ => throw NativeUsageException('Unknown native command "$actionName".'),
    };

    if (action == NativeAction.syncMetadata) {
      if (arguments.length != 1) {
        throw NativeUsageException('sync-metadata accepts no arguments.');
      }
      return const NativeInvocation(action: NativeAction.syncMetadata);
    }

    if (action == NativeAction.assemble) {
      String? sourceSha;
      String? outputPath;
      final fragments = <NativeTarget, String>{};
      for (var index = 1; index < arguments.length; index++) {
        final argument = arguments[index];
        String takeValue(String option) {
          if (index + 1 >= arguments.length) {
            throw NativeUsageException('$option requires a value.');
          }
          return arguments[++index];
        }

        if (argument == '--source-sha') {
          sourceSha = takeValue(argument);
        } else if (argument.startsWith('--source-sha=')) {
          sourceSha = argument.substring('--source-sha='.length);
        } else if (argument == '--output') {
          outputPath = takeValue(argument);
        } else if (argument.startsWith('--output=')) {
          outputPath = argument.substring('--output='.length);
        } else if (argument == '--fragment') {
          _parseManifestFragment(takeValue(argument), fragments);
        } else if (argument.startsWith('--fragment=')) {
          _parseManifestFragment(
            argument.substring('--fragment='.length),
            fragments,
          );
        } else {
          final named = RegExp(
            r'^--(windows|android|ios|macos)-manifest(?:=(.*))?$',
          ).firstMatch(argument);
          if (named == null) {
            throw NativeUsageException('Unknown option "$argument".');
          }
          final value = named.group(2)?.isNotEmpty == true
              ? named.group(2)!
              : takeValue('--${named.group(1)}-manifest');
          _addManifestFragment(
            NativeTargetName.parse(named.group(1)!),
            value,
            fragments,
          );
        }
      }
      if (sourceSha == null || !_isFullGitSha(sourceSha)) {
        throw NativeUsageException(
          'assemble requires --source-sha with a full 40-character Git SHA.',
        );
      }
      final missing = NativeTarget.values
          .where((target) => !fragments.containsKey(target))
          .map((target) => target.cliName)
          .toList();
      if (missing.isNotEmpty) {
        throw NativeUsageException(
          'assemble is missing manifest fragments for ${missing.join(', ')}.',
        );
      }
      return NativeInvocation(
        action: action,
        sourceSha: sourceSha.toLowerCase(),
        manifestFragments: Map.unmodifiable(fragments),
        outputPath: outputPath,
      );
    }

    if (action == NativeAction.purgeCache) {
      if (arguments.length > 2) {
        throw NativeUsageException(
          'purge-cache accepts at most one cache name.',
        );
      }
      return NativeInvocation(
        action: action,
        purgeName: arguments.length == 2 ? arguments[1] : 'all',
      );
    }

    if (arguments.length < 2) {
      throw NativeUsageException('$actionName requires a platform.');
    }
    final target = NativeTargetName.parse(arguments[1]);
    var offline = false;
    var dryRun = false;
    String? sourceSha;
    final architectures = <String>[];
    for (var index = 2; index < arguments.length; index++) {
      final argument = arguments[index];
      switch (argument) {
        case '--offline':
          offline = true;
        case '--dry-run':
          dryRun = true;
        case '--source-sha':
          if (index + 1 >= arguments.length) {
            throw NativeUsageException('--source-sha requires a value.');
          }
          sourceSha = arguments[++index];
        case '--arch':
          if (index + 1 >= arguments.length) {
            throw NativeUsageException('--arch requires a value.');
          }
          architectures.addAll(
            arguments[++index].split(',').where((value) => value.isNotEmpty),
          );
        default:
          if (argument.startsWith('--arch=')) {
            architectures.addAll(
              argument
                  .substring('--arch='.length)
                  .split(',')
                  .where((value) => value.isNotEmpty),
            );
          } else if (argument.startsWith('--source-sha=')) {
            sourceSha = argument.substring('--source-sha='.length);
          } else {
            throw NativeUsageException('Unknown option "$argument".');
          }
      }
    }
    if (action != NativeAction.build && architectures.isNotEmpty) {
      throw NativeUsageException('--arch is only valid with build.');
    }
    if (action != NativeAction.build && (offline || dryRun)) {
      throw NativeUsageException(
        '--offline and --dry-run are only valid with build.',
      );
    }
    if (sourceSha != null && !_isFullGitSha(sourceSha)) {
      throw NativeUsageException(
        '--source-sha must be a full 40-character Git commit ID.',
      );
    }
    if (action != NativeAction.build && sourceSha != null) {
      throw NativeUsageException('--source-sha is only valid with build.');
    }
    return NativeInvocation(
      action: action,
      target: target,
      architectures: architectures,
      offline: offline,
      dryRun: dryRun,
      sourceSha: sourceSha?.toLowerCase(),
    );
  }

  static void _parseManifestFragment(
    String value,
    Map<NativeTarget, String> fragments,
  ) {
    final separator = value.indexOf('=');
    if (separator <= 0 || separator == value.length - 1) {
      throw NativeUsageException(
        '--fragment must use <platform>=<manifest-path>.',
      );
    }
    _addManifestFragment(
      NativeTargetName.parse(value.substring(0, separator)),
      value.substring(separator + 1),
      fragments,
    );
  }

  static void _addManifestFragment(
    NativeTarget target,
    String path,
    Map<NativeTarget, String> fragments,
  ) {
    if (path.trim().isEmpty) {
      throw NativeUsageException(
        'Manifest path for ${target.cliName} may not be empty.',
      );
    }
    if (fragments.containsKey(target)) {
      throw NativeUsageException(
        'Duplicate ${target.cliName} manifest fragment.',
      );
    }
    fragments[target] = path;
  }
}

final class AppleXcframeworkLibrary {
  const AppleXcframeworkLibrary({
    required this.identifier,
    required this.libraryPath,
    required this.architectures,
    required this.platform,
    this.variant,
  });

  final String identifier;
  final String libraryPath;
  final List<String> architectures;
  final String platform;
  final String? variant;
}

bool _isFullGitSha(String value) =>
    RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(value);

const _nativeHeaderExtensions = ['.h', '.hh', '.hpp', '.hxx'];

bool isNativeHeaderArtifactPath(String path) {
  final lower = path.toLowerCase();
  return _nativeHeaderExtensions.any(lower.endsWith);
}

String canonicalNativeHeaderText(String content) =>
    content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

void validateCanonicalNativeHeaderBytes(String path, List<int> bytes) {
  if (!isNativeHeaderArtifactPath(path)) return;
  try {
    utf8.decode(bytes);
  } on FormatException {
    throw StateError('Native artifact header is not valid UTF-8: $path');
  }
  if (bytes.contains(0x0d)) {
    throw StateError(
      'Native artifact header must use canonical LF line endings: $path',
    );
  }
}

final class DependencySpec {
  const DependencySpec({
    required this.name,
    required this.version,
    required this.archive,
    required this.url,
    required this.sha256,
    this.license,
  });

  factory DependencySpec.fromJson(String name, Map<String, Object?> json) {
    return DependencySpec(
      name: name,
      version: json['version']! as String,
      archive: json['archive']! as String,
      url: json['url']! as String,
      sha256: (json['sha256']! as String).toLowerCase(),
      license: json['license'] as String?,
    );
  }

  final String name;
  final String version;
  final String archive;
  final String url;
  final String sha256;
  final String? license;
}

final class NativeBuilder {
  NativeBuilder._(this.repositoryRoot, this.lock)
    : cacheRoot = Directory(_join(repositoryRoot.path, '.native-cache')),
      buildRoot = Directory(_join(repositoryRoot.path, 'build', 'native'));

  factory NativeBuilder.fromScript() {
    final toolDirectory = File.fromUri(Platform.script).parent;
    return NativeBuilder.fromRepository(toolDirectory.parent);
  }

  factory NativeBuilder.fromRepository(Directory root) {
    final lockFile = File(_join(root.path, 'native', 'dependencies.lock.json'));
    if (!lockFile.existsSync()) {
      throw StateError('Native dependency lock is missing: ${lockFile.path}');
    }
    final lock =
        jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>;
    return NativeBuilder._(root, lock);
  }

  final Directory repositoryRoot;
  final Directory cacheRoot;
  final Directory buildRoot;
  final Map<String, Object?> lock;

  int get sourceDateEpoch => lock['sourceDateEpoch']! as int;

  Map<String, Object?> get toolchains =>
      (lock['toolchains']! as Map).cast<String, Object?>();

  Map<String, DependencySpec> get dependencies {
    final values = (lock['dependencies']! as Map).cast<String, Object?>();
    return values.map(
      (name, value) => MapEntry(
        name,
        DependencySpec.fromJson(name, (value! as Map).cast<String, Object?>()),
      ),
    );
  }

  Map<String, DependencySpec> get tools {
    final values = (lock['tools']! as Map).cast<String, Object?>();
    return values.map(
      (name, value) => MapEntry(
        name,
        DependencySpec.fromJson(name, (value! as Map).cast<String, Object?>()),
      ),
    );
  }

  Map<String, DependencySpec> get assets {
    final values = (lock['assets']! as Map).cast<String, Object?>();
    return values.map(
      (name, value) => MapEntry(
        name,
        DependencySpec.fromJson(name, (value! as Map).cast<String, Object?>()),
      ),
    );
  }

  Future<void> execute(NativeInvocation invocation) async {
    switch (invocation.action) {
      case NativeAction.help:
        stdout.writeln(NativeInvocation.usage);
      case NativeAction.build:
        await _build(invocation);
      case NativeAction.verify:
        await verify(invocation.target!);
      case NativeAction.clean:
        await clean(invocation.target!);
      case NativeAction.purgeCache:
        await purgeCache(invocation.purgeName ?? 'all');
      case NativeAction.assemble:
        await assemble(
          invocation.manifestFragments,
          sourceSha: invocation.sourceSha!,
          outputPath: invocation.outputPath,
        );
      case NativeAction.syncMetadata:
        await syncMetadata();
    }
  }

  Future<void> _build(NativeInvocation invocation) async {
    final target = invocation.target!;
    final architectures = normalizedArchitectures(
      target,
      invocation.architectures,
    );
    _log('Building ${target.cliName} (${architectures.join(', ')})');
    if (invocation.dryRun) {
      final commands = generatedCommands(target, architectures);
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(commands));
      _result('build', target, ok: true, extra: {'dryRun': true});
      return;
    }
    if (invocation.sourceSha case final sourceSha?) {
      await validateSourceShaMatchesCheckout(sourceSha);
    }

    await _requireProgram('cmake');
    await _assertPinnedBuildToolchains(target, offline: invocation.offline);
    final sources = <String, Directory>{};
    for (final spec in dependencies.values) {
      sources[spec.name] = await _prepareSource(
        spec,
        offline: invocation.offline,
      );
    }

    File? caBundle;
    if (target == NativeTarget.ios || target == NativeTarget.macos) {
      caBundle = await _prepareAsset(
        assets['mozilla-ca-bundle']!,
        offline: invocation.offline,
      );
    }

    switch (target) {
      case NativeTarget.windows:
        await _buildWindows(sources, offline: invocation.offline);
      case NativeTarget.android:
        await _buildAndroid(
          sources,
          architectures,
          offline: invocation.offline,
        );
      case NativeTarget.ios:
        await _buildIos(sources, architectures, caBundle!);
      case NativeTarget.macos:
        await _buildMacos(sources, architectures, caBundle!);
    }
    await canonicalizeStagedArtifactHeaders(target);
    await _writeArtifactManifest(
      target,
      architectures,
      sourceSha: invocation.sourceSha,
    );
    await verify(target);
    _result('build', target, ok: true, extra: {'architectures': architectures});
  }

  List<String> normalizedArchitectures(
    NativeTarget target,
    List<String> requested,
  ) {
    final defaults = switch (target) {
      NativeTarget.windows => const ['x64'],
      NativeTarget.android => _supportedAndroidArchitectures,
      NativeTarget.ios => const ['arm64', 'sim-arm64'],
      NativeTarget.macos => const ['arm64'],
    };
    final allowed = defaults.toSet();
    final result = requested.isEmpty ? defaults : requested;
    final invalid = result.where((arch) => !allowed.contains(arch)).toList();
    if (invalid.isNotEmpty) {
      throw NativeUsageException(
        'Unsupported ${target.cliName} architecture(s): ${invalid.join(', ')}. '
        'Expected one of ${defaults.join(', ')}.',
      );
    }
    return result.toSet().toList(growable: false);
  }

  Map<String, Object?> generatedCommands(
    NativeTarget target,
    List<String> architectures,
  ) {
    final minimums = toolchains;
    final commands = <Map<String, Object?>>[];
    for (final arch in architectures) {
      commands.add({
        'step': 'openssl',
        'arch': arch,
        'configureTarget': _opensslTarget(target, arch),
        'static': true,
        if (target == NativeTarget.android)
          'environment': {
            'ANDROID_NDK_ROOT': '<ndk>',
            'ANDROID_NDK': '<ndk>',
            'CC': 'clang',
            'CXX': 'clang++',
            'PATH': '<ndk-llvm-toolchain-bin>:<path>',
            if (Platform.isWindows) ...{
              'PERL': '<git-for-windows-posix-perl>',
              'PERL5LIB': '<pinned-perl-pure-modules>',
              'MSYS2_ENV_CONV_EXCL':
                  'PERL5LIB;ANDROID_NDK_ROOT;ANDROID_NDK;ANDROID_NDK_HOME',
            },
          },
        if (target == NativeTarget.ios || target == NativeTarget.macos)
          'environment': _appleDeploymentEnvironment(target),
      });
      commands.add({
        'step': 'cmake',
        'arch': arch,
        'arguments': cmakeArguments(target, arch, '<openssl-prefix>'),
      });
      if (target == NativeTarget.android) {
        commands.add({
          'step': 'strip',
          'arch': arch,
          'tool': '<ndk-llvm-toolchain-bin>/llvm-strip',
          'arguments': ['--strip-unneeded'],
        });
      }
    }
    if (target == NativeTarget.windows) {
      commands.add({
        'step': 'ctest',
        'target': 'simple_torrent_native_session_suspension_test',
        'arguments': [
          '--build-config',
          'Release',
          '--output-on-failure',
          '--no-tests=error',
        ],
      });
    }
    if (target == NativeTarget.ios || target == NativeTarget.macos) {
      commands.add({
        'step': 'embedded-ca-bundle',
        'version': assets['mozilla-ca-bundle']!.version,
        'sha256': assets['mozilla-ca-bundle']!.sha256,
      });
      commands.add({
        'step': 'xcframework',
        'minimum': target == NativeTarget.ios
            ? minimums['iosMinimum']
            : minimums['macosMinimum'],
      });
    }
    return {
      'platform': target.cliName,
      'architectures': architectures,
      'commands': commands,
    };
  }

  List<String> cmakeArguments(
    NativeTarget target,
    String architecture,
    String opensslPrefix,
  ) {
    final args = <String>[
      '-S',
      _unix(_join(repositoryRoot.path, 'native')),
      '-DCMAKE_BUILD_TYPE=Release',
      '-DSTN_BUILD_TESTS=${target == NativeTarget.windows ? 'ON' : 'OFF'}',
      '-DSTN_PLATFORM=${target.cliName}',
      '-DSTN_BUILD_SHARED=${target == NativeTarget.ios || target == NativeTarget.macos ? 'OFF' : 'ON'}',
      '-DSTN_LIBTORRENT_SOURCE=<libtorrent-source>',
      '-DBOOST_ROOT=<boost-source>',
      '-DOPENSSL_ROOT_DIR=${_unix(opensslPrefix)}',
      '-DOPENSSL_USE_STATIC_LIBS=TRUE',
    ];
    switch (target) {
      case NativeTarget.windows:
        args.addAll([
          '-G',
          'Ninja',
          '-DCMAKE_SYSTEM_VERSION=${toolchains['windowsSdk']}',
          '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded',
        ]);
      case NativeTarget.android:
        args.addAll([
          '-G',
          'Ninja',
          '-DCMAKE_TOOLCHAIN_FILE=<ndk>/build/cmake/android.toolchain.cmake',
          '-DANDROID_ABI=$architecture',
          '-DANDROID_PLATFORM=android-${toolchains['androidApi']}',
          '-DANDROID_STL=c++_static',
          '-DSTN_ANDROID_JNI=ON',
        ]);
      case NativeTarget.ios:
        final simulator = architecture.startsWith('sim-');
        args.addAll([
          '-G',
          'Ninja',
          '-DCMAKE_SYSTEM_NAME=iOS',
          '-DCMAKE_OSX_SYSROOT=${simulator ? 'iphonesimulator' : 'iphoneos'}',
          '-DCMAKE_OSX_ARCHITECTURES=${architecture.replaceFirst('sim-', '')}',
          '-DCMAKE_OSX_DEPLOYMENT_TARGET=${toolchains['iosMinimum']}',
        ]);
      case NativeTarget.macos:
        args.addAll([
          '-G',
          'Ninja',
          '-DCMAKE_OSX_ARCHITECTURES=$architecture',
          '-DCMAKE_OSX_DEPLOYMENT_TARGET=${toolchains['macosMinimum']}',
        ]);
    }
    return args;
  }

  Future<Directory> _prepareSource(
    DependencySpec spec, {
    required bool offline,
  }) async {
    final downloads = Directory(_join(cacheRoot.path, 'downloads'));
    final sources = Directory(_join(cacheRoot.path, 'sources'));
    await downloads.create(recursive: true);
    await sources.create(recursive: true);
    final archive = File(_join(downloads.path, spec.archive));
    await _ensureArchive(spec, archive, offline: offline);

    final destination = Directory(
      _join(sources.path, '${spec.name}-${spec.version}'),
    );
    final stamp = File(_join(destination.path, '.simple-torrent-source.json'));
    final patches = await _sourcePatchRecords(spec);
    final identity = <String, Object?>{
      'schemaVersion': 2,
      'archive': spec.archive,
      'sha256': spec.sha256,
      'patches': patches,
    };
    if (destination.existsSync() && stamp.existsSync()) {
      try {
        final value = (jsonDecode(await stamp.readAsString()) as Map)
            .cast<String, Object?>();
        if (jsonEncode(value['identity']) == jsonEncode(identity)) {
          final fingerprint = await _directoryFingerprint(
            destination,
            excludedFile: stamp,
          );
          if (jsonEncode(value['files']) == jsonEncode(fingerprint) &&
              await _sourcePatchesAreApplied(spec, destination)) {
            return destination;
          }
        }
      } on FormatException {
        // Re-extract a partially written or old cache entry.
      } on TypeError {
        // Re-extract a cache using an older stamp schema.
      }
    }
    if (destination.existsSync()) {
      await _deleteDirectoryWithin(destination, cacheRoot);
    }

    final extracting = Directory(
      _join(cacheRoot.path, 'extracting', '${spec.name}-${spec.version}'),
    );
    if (extracting.existsSync()) {
      await _deleteDirectoryWithin(extracting, cacheRoot);
    }
    await extracting.create(recursive: true);
    _log('Extracting ${spec.archive}');
    await _run('cmake', [
      '-E',
      'tar',
      'xf',
      archive.path,
    ], workingDirectory: extracting);
    final entries = await extracting.list(followLinks: false).toList();
    final directories = entries.whereType<Directory>().toList();
    final files = entries.whereType<File>().toList();
    if (directories.length == 1 && files.isEmpty) {
      await _renameEntityWithin(directories.single, destination, cacheRoot);
    } else {
      await destination.create(recursive: true);
      for (final entry in entries) {
        await _renameEntityWithin(
          entry,
          File(_join(destination.path, _basename(entry.path))),
          cacheRoot,
        );
      }
    }
    await _applySourcePatches(spec, destination);
    await stamp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'identity': identity, 'files': await _directoryFingerprint(destination)})}\n',
    );
    if (extracting.existsSync()) {
      await _deleteDirectoryWithin(extracting, cacheRoot);
    }
    return destination;
  }

  Future<List<Map<String, Object?>>> _sourcePatchRecords(
    DependencySpec spec,
  ) async {
    if (spec.name != 'boost' || spec.version != '1.91.0') return const [];
    final patch = File(
      _join(
        repositoryRoot.path,
        'native',
        'patches',
        'boost-1.91.0-android-x86_64-long-double.patch',
      ),
    );
    if (!patch.existsSync()) {
      throw StateError('Required Boost compatibility patch is missing.');
    }
    final patchText = (await patch.readAsString()).replaceAll('\r\n', '\n');
    if (patchText != _expectedBoostLongDoublePatch) {
      throw StateError(
        'Boost compatibility patch does not match its canonical transform.',
      );
    }
    return [
      {'path': _relativePath(patch.path), 'sha256': await Sha256.file(patch)},
    ];
  }

  static const _boostLongDoubleOriginal =
      '#elif defined(__i386) || defined(__i386__) || defined(_M_IX86) \\\n'
      '    || defined(__amd64) || defined(__amd64__)  || defined(_M_AMD64) \\\n'
      '    || defined(__x86_64) || defined(__x86_64__) || defined(_M_X64)';

  static const _boostLongDoublePatched =
      '#elif (LDBL_MANT_DIG == 64) && (defined(__i386) || defined(__i386__) || defined(_M_IX86) \\\n'
      '    || defined(__amd64) || defined(__amd64__)  || defined(_M_AMD64) \\\n'
      '    || defined(__x86_64) || defined(__x86_64__) || defined(_M_X64))';

  static const _expectedBoostLongDoublePatch =
      '--- a/boost/math/special_functions/detail/fp_traits.hpp\n'
      '+++ b/boost/math/special_functions/detail/fp_traits.hpp\n'
      '@@ -305,9 +305,10 @@ template<> struct fp_traits_non_native<long double, double_precision>\n'
      ' \n'
      ' // long double (>64 bits), x86 and x64 -----------------------------------------\n'
      ' \n'
      '-#elif defined(__i386) || defined(__i386__) || defined(_M_IX86) \\\n'
      '+#elif (LDBL_MANT_DIG == 64) && (defined(__i386) || defined(__i386__) || defined(_M_IX86) \\\n'
      '     || defined(__amd64) || defined(__amd64__)  || defined(_M_AMD64) \\\n'
      '-    || defined(__x86_64) || defined(__x86_64__) || defined(_M_X64)\n'
      '+    || defined(__x86_64) || defined(__x86_64__) || defined(_M_X64))\n'
      ' \n'
      ' // Intel extended double precision format (80 bits)\n'
      ' \n';

  File _boostLongDoubleHeader(Directory source) => File(
    _join(
      source.path,
      'boost',
      'math',
      'special_functions',
      'detail',
      'fp_traits.hpp',
    ),
  );

  Future<bool> _sourcePatchesAreApplied(
    DependencySpec spec,
    Directory source,
  ) async {
    if (spec.name != 'boost' || spec.version != '1.91.0') return true;
    final header = _boostLongDoubleHeader(source);
    if (!header.existsSync()) return false;
    return (await header.readAsString()).contains(_boostLongDoublePatched);
  }

  Future<void> _applySourcePatches(
    DependencySpec spec,
    Directory source,
  ) async {
    if (spec.name != 'boost' || spec.version != '1.91.0') return;
    final header = _boostLongDoubleHeader(source);
    if (!header.existsSync()) {
      throw StateError('Boost fp_traits.hpp is missing; cannot apply patch.');
    }
    final content = await header.readAsString();
    if (content.contains(_boostLongDoublePatched)) return;
    if (!content.contains(_boostLongDoubleOriginal)) {
      throw StateError(
        'Boost fp_traits.hpp no longer matches the pinned patch preimage.',
      );
    }
    _log('Applying Android x86_64 long-double compatibility patch to Boost');
    await header.writeAsString(
      content.replaceFirst(_boostLongDoubleOriginal, _boostLongDoublePatched),
    );
  }

  Future<File> _prepareAsset(
    DependencySpec spec, {
    required bool offline,
  }) async {
    final downloads = Directory(_join(cacheRoot.path, 'downloads'));
    await downloads.create(recursive: true);
    final file = File(_join(downloads.path, spec.archive));
    await _ensureArchive(spec, file, offline: offline);
    return file;
  }

  Future<void> _ensureArchive(
    DependencySpec spec,
    File archive, {
    required bool offline,
  }) async {
    if (archive.existsSync()) {
      final actual = await Sha256.file(archive);
      if (actual == spec.sha256) {
        _log('Using cached ${spec.archive}');
        return;
      }
      await archive.delete();
      if (offline) {
        throw StateError(
          'Cached ${spec.archive} failed SHA-256 verification and --offline was set.',
        );
      }
    } else if (offline) {
      throw StateError('${spec.archive} is not cached and --offline was set.');
    }

    final partial = File('${archive.path}.partial');
    if (partial.existsSync()) await partial.delete();
    _log('Downloading ${spec.name} ${spec.version}');
    final client = HttpClient()
      ..userAgent = 'simple_torrent-native-builder/$nativeBuilderVersion';
    try {
      final request = await client.getUrl(Uri.parse(spec.url));
      request.followRedirects = true;
      request.maxRedirects = 10;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Download returned HTTP ${response.statusCode}',
          uri: Uri.parse(spec.url),
        );
      }
      final output = partial.openWrite();
      await response.pipe(output);
    } finally {
      client.close(force: true);
    }
    final actual = await Sha256.file(partial);
    if (actual != spec.sha256) {
      await partial.delete();
      throw StateError(
        'SHA-256 mismatch for ${spec.archive}: expected ${spec.sha256}, got $actual.',
      );
    }
    await _renameEntityWithin(partial, archive, cacheRoot);
  }

  Future<void> clean(NativeTarget target) async {
    final directory = Directory(_join(buildRoot.path, target.cliName));
    if (directory.existsSync()) {
      await _deleteDirectoryWithin(directory, buildRoot);
    }
    _result('clean', target, ok: true);
  }

  Future<void> pruneUnrequestedAndroidArtifacts(
    List<String> architectures,
  ) async {
    final requested = normalizedArchitectures(
      NativeTarget.android,
      architectures,
    ).toSet();
    final jniLibraries = Directory(
      _join(
        repositoryRoot.path,
        'packages',
        'simple_torrent_android',
        'android',
        'src',
        'main',
        'jniLibs',
      ),
    );
    for (final architecture in _supportedAndroidArchitectures) {
      if (requested.contains(architecture)) continue;
      final library = File(
        _join(jniLibraries.path, architecture, 'libsimple_torrent_native.so'),
      );
      final type = FileSystemEntity.typeSync(library.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.link) {
        throw StateError(
          'Refusing to delete non-file Android artifact: ${library.path}',
        );
      }
      await _deleteFileWithin(library, jniLibraries);
      _log('Removed unrequested staged Android ABI $architecture');
    }
  }

  Future<void> purgeCache(String name) async {
    final allowed = {'all', ...dependencies.keys, ...assets.keys, 'tools'};
    if (!allowed.contains(name)) {
      throw NativeUsageException(
        'Unknown cache "$name". Expected ${allowed.join(', ')}.',
      );
    }
    if (!cacheRoot.existsSync()) {
      stdout.writeln('{"ok":true,"command":"purge-cache","removed":"none"}');
      return;
    }
    if (name == 'all') {
      await _deleteDirectoryWithin(cacheRoot, repositoryRoot);
    } else if (name == 'tools') {
      final directory = Directory(_join(cacheRoot.path, 'tools'));
      if (directory.existsSync()) {
        await _deleteDirectoryWithin(directory, cacheRoot);
      }
      final downloads = Directory(_join(cacheRoot.path, 'downloads'));
      for (final spec in tools.values) {
        final archive = File(_join(downloads.path, spec.archive));
        if (archive.existsSync()) await archive.delete();
      }
    } else if (assets.containsKey(name)) {
      final spec = assets[name]!;
      final file = File(_join(cacheRoot.path, 'downloads', spec.archive));
      if (file.existsSync()) await file.delete();
    } else {
      final spec = dependencies[name]!;
      final source = Directory(
        _join(cacheRoot.path, 'sources', '${spec.name}-${spec.version}'),
      );
      if (source.existsSync()) await _deleteDirectoryWithin(source, cacheRoot);
      final archive = File(_join(cacheRoot.path, 'downloads', spec.archive));
      if (archive.existsSync()) await archive.delete();
    }
    stdout.writeln(
      jsonEncode({'ok': true, 'command': 'purge-cache', 'removed': name}),
    );
  }

  Future<void> _deleteDirectoryWithin(
    Directory target,
    Directory parent,
  ) async {
    _requireStrictlyWithin(target, parent, operation: 'delete');
    await _retryFileSystemOperation('delete ${target.path}', () async {
      if (target.existsSync()) await target.delete(recursive: true);
    });
  }

  Future<void> _deleteFileWithin(File target, Directory parent) async {
    _requireStrictlyWithin(target, parent, operation: 'delete');
    await _retryFileSystemOperation('delete ${target.path}', () async {
      final type = FileSystemEntity.typeSync(target.path, followLinks: false);
      if (type != FileSystemEntityType.notFound) await target.delete();
    });
  }

  Future<void> _prepareTemporaryFileWithin(
    File target,
    Directory parent, {
    required String operation,
  }) async {
    _requireStrictlyWithin(target, parent, operation: operation);
    final type = FileSystemEntity.typeSync(target.path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.file:
        await _deleteFileWithin(target, parent);
        return;
      case FileSystemEntityType.link:
        throw StateError(
          'Refusing to $operation through a symbolic link: ${target.path}',
        );
      default:
        throw StateError(
          'Refusing to $operation through a non-file path: ${target.path}',
        );
    }
  }

  Future<void> _renameEntityWithin(
    FileSystemEntity source,
    FileSystemEntity destination,
    Directory parent,
  ) async {
    _requireStrictlyWithin(source, parent, operation: 'rename');
    _requireStrictlyWithin(destination, parent, operation: 'rename');
    await _retryFileSystemOperation(
      'rename ${source.path} to ${destination.path}',
      () async {
        if (!source.existsSync() && destination.existsSync()) return;
        await source.rename(destination.path);
      },
    );
  }

  void _requireStrictlyWithin(
    FileSystemEntity target,
    Directory parent, {
    required String operation,
  }) {
    final targetPath = _canonical(target.absolute.path);
    final parentPath = _canonical(parent.absolute.path);
    if (targetPath == parentPath ||
        !targetPath.startsWith('$parentPath${Platform.pathSeparator}')) {
      throw StateError('Refusing to $operation unsafe path: ${target.path}');
    }

    final repositoryResolved = _canonical(
      repositoryRoot.resolveSymbolicLinksSync(),
    );
    final parentResolved = _canonical(parent.resolveSymbolicLinksSync());
    if (parentResolved != repositoryResolved &&
        !parentResolved.startsWith(
          '$repositoryResolved${Platform.pathSeparator}',
        )) {
      throw StateError(
        'Refusing to $operation through a parent path outside the repository: '
        '${parent.path}',
      );
    }

    var probe = target.absolute.path;
    final targetExists =
        FileSystemEntity.typeSync(probe, followLinks: false) !=
        FileSystemEntityType.notFound;
    while (FileSystemEntity.typeSync(probe, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final ancestor = Directory(probe).parent.path;
      if (ancestor == probe) {
        throw StateError('Cannot resolve a safe ancestor for ${target.path}.');
      }
      probe = ancestor;
    }
    final probeType = FileSystemEntity.typeSync(probe, followLinks: false);
    final resolvedProbe = _canonical(switch (probeType) {
      FileSystemEntityType.directory => Directory(
        probe,
      ).resolveSymbolicLinksSync(),
      FileSystemEntityType.link => Link(probe).resolveSymbolicLinksSync(),
      _ => File(probe).resolveSymbolicLinksSync(),
    });
    final insideResolvedParent = resolvedProbe.startsWith(
      '$parentResolved${Platform.pathSeparator}',
    );
    if ((targetExists && resolvedProbe == parentResolved) ||
        (resolvedProbe != parentResolved && !insideResolvedParent)) {
      throw StateError(
        'Refusing to $operation path that resolves outside ${parent.path}: '
        '${target.path}',
      );
    }
  }

  Future<void> _retryFileSystemOperation(
    String description,
    Future<void> Function() operation,
  ) async {
    const maximumAttempts = 12;
    for (var attempt = 1; attempt <= maximumAttempts; attempt++) {
      try {
        await operation();
        return;
      } on FileSystemException catch (error) {
        if (attempt == maximumAttempts) rethrow;
        final exponent = attempt > 5 ? 5 : attempt;
        final delay = Duration(milliseconds: 100 * (1 << exponent));
        _log(
          'Filesystem operation was temporarily unavailable '
          '($description, attempt $attempt/$maximumAttempts): '
          '${error.osError?.message ?? error.message}. Retrying in '
          '${delay.inMilliseconds} ms.',
        );
        await Future<void>.delayed(delay);
      }
    }
  }

  Future<void> _requireProgram(String executable) async {
    final result = await Process.run(
      Platform.isWindows ? 'where.exe' : 'which',
      [executable],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw StateError('Required tool "$executable" was not found in PATH.');
    }
  }

  Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool capture = false,
  }) async {
    _log('\$ ${_displayCommand(executable, arguments)}');
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory?.path,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = process.stdout.transform(utf8.decoder).listen((data) {
      if (capture) {
        stdoutBuffer.write(data);
      } else {
        stdout.write(data);
      }
    }).asFuture<void>();
    final stderrDone = process.stderr.transform(utf8.decoder).listen((data) {
      if (capture) {
        stderrBuffer.write(data);
      } else {
        stderr.write(data);
      }
    }).asFuture<void>();
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    final result = ProcessResult(
      process.pid,
      exitCode,
      stdoutBuffer.toString(),
      stderrBuffer.toString(),
    );
    if (exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        'Command failed with exit code $exitCode. ${stderrBuffer.toString()}',
        exitCode,
      );
    }
    return result;
  }

  void _log(String message) => stdout.writeln('[native] $message');

  void _result(
    String command,
    NativeTarget target, {
    required bool ok,
    Map<String, Object?> extra = const {},
  }) {
    stdout.writeln(
      jsonEncode({
        'ok': ok,
        'command': command,
        'platform': target.cliName,
        ...extra,
      }),
    );
  }

  Future<void> _buildWindows(
    Map<String, Directory> sources, {
    required bool offline,
  }) async {
    if (!Platform.isWindows) {
      throw StateError('Windows native artifacts must be built on Windows.');
    }
    final environment = await _visualStudioEnvironment();
    final perl = await _findPerl(offline: offline);
    final nasm = await _findNasm(offline: offline);
    environment['PATH'] = [
      nasm.parent.path,
      perl.parent.path,
      environment['PATH'] ?? Platform.environment['PATH'] ?? '',
    ].join(';');
    // Strawberry Perl does not ship the locale data needed for inherited
    // C.UTF-8 locales. Keep every Windows native child on its portable locale.
    environment['LC_ALL'] = 'C';
    environment['LANG'] = 'C';
    environment['SOURCE_DATE_EPOCH'] = sourceDateEpoch.toString();
    final vcToolsPath = environment['VCTOOLSINSTALLDIR'];
    if (vcToolsPath == null || vcToolsPath.isEmpty) {
      throw StateError('vcvars64.bat did not report VCToolsInstallDir.');
    }
    var nmake = File(_join(vcToolsPath, 'bin', 'Hostx64', 'x64', 'nmake.exe'));
    if (!nmake.existsSync()) {
      nmake = await _findFile(Directory(vcToolsPath), 'nmake.exe');
    }

    final platformBuild = Directory(_join(buildRoot.path, 'windows', 'x64'));
    await platformBuild.create(recursive: true);
    final opensslPrefix = await _buildOpenSsl(
      target: NativeTarget.windows,
      architecture: 'x64',
      source: sources['openssl']!,
      platformBuild: platformBuild,
      perl: perl.path,
      // Process.start resolves the executable against the parent process PATH
      // before applying this child environment. Use the absolute vcvars path.
      make: nmake.path,
      environment: environment,
      toolIdentity: {
        'compiler': 'msvc',
        'msvcToolset': environment['VCTOOLSVERSION'],
        'windowsSdk': environment['WINDOWSSDKVERSION'],
        'perl': {
          'version': tools['perl-windows-x64']!.version,
          'archiveSha256': tools['perl-windows-x64']!.sha256,
        },
        'nasm': {
          'version': tools['nasm-windows-x64']!.version,
          'archiveSha256': tools['nasm-windows-x64']!.sha256,
        },
      },
    );
    final nativeBuild = Directory(_join(platformBuild.path, 'simple-torrent'));
    await nativeBuild.create(recursive: true);
    final arguments = _resolvedCmakeArguments(
      NativeTarget.windows,
      'x64',
      opensslPrefix,
      sources,
    )..add('-DCMAKE_MAKE_PROGRAM=${_unix(await _findNinja())}');
    await _run('cmake.exe', arguments, environment: environment);
    await _run('cmake.exe', [
      '--build',
      nativeBuild.path,
      '--config',
      'Release',
      '--parallel',
      '--target',
      'simple_torrent_native',
      'simple_torrent_native_session_suspension_test',
    ], environment: environment);
    await _run('ctest.exe', [
      '--test-dir',
      nativeBuild.path,
      '--build-config',
      'Release',
      '--output-on-failure',
      '--no-tests=error',
    ], environment: environment);

    final dll = await _findFile(nativeBuild, 'simple_torrent_native.dll');
    final importLibrary = await _findFile(
      nativeBuild,
      'simple_torrent_native.lib',
    );
    final package = Directory(
      _join(repositoryRoot.path, 'packages', 'simple_torrent_windows'),
    );
    await _stageFile(
      dll,
      File(
        _join(
          package.path,
          'windows',
          'lib',
          'x64',
          'simple_torrent_native.dll',
        ),
      ),
    );
    await _stageFile(
      importLibrary,
      File(
        _join(
          package.path,
          'windows',
          'lib',
          'x64',
          'simple_torrent_native.lib',
        ),
      ),
    );
    await _stageFile(
      File(
        _join(
          repositoryRoot.path,
          'native',
          'include',
          'simple_torrent_native.h',
        ),
      ),
      File(
        _join(package.path, 'windows', 'include', 'simple_torrent_native.h'),
      ),
    );
  }

  Future<void> _buildAndroid(
    Map<String, Directory> sources,
    List<String> architectures, {
    required bool offline,
  }) async {
    final ndk = await _findAndroidNdk(offline: offline);
    final host = Platform.isWindows
        ? 'windows-x86_64'
        : Platform.isMacOS
        ? 'darwin-x86_64'
        : 'linux-x86_64';
    final toolchainBin = Directory(
      _join(ndk.path, 'toolchains', 'llvm', 'prebuilt', host, 'bin'),
    );
    if (!toolchainBin.existsSync()) {
      throw StateError(
        'NDK LLVM toolchain was not found at ${toolchainBin.path}.',
      );
    }
    final strip = File(
      _join(
        toolchainBin.path,
        Platform.isWindows ? 'llvm-strip.exe' : 'llvm-strip',
      ),
    );
    if (!strip.existsSync()) {
      throw StateError(
        'The pinned NDK does not contain llvm-strip at ${strip.path}.',
      );
    }
    final make = Platform.isWindows
        ? File(_join(ndk.path, 'prebuilt', host, 'bin', 'make.exe')).path
        : 'make';
    if (Platform.isWindows && !File(make).existsSync()) {
      throw StateError('The pinned NDK does not contain make.exe at $make.');
    }
    // OpenSSL's Android configuration requires POSIX path semantics. The
    // pinned native Windows Perl is intentionally still prepared and checked:
    // it supplies the complete, checksummed pure-module tree missing from the
    // compact POSIX Perl bundled with Git for Windows.
    final pinnedPerl = await _findPerl(offline: offline);
    final perl = Platform.isWindows ? await _findGitPosixPerl() : pinnedPerl;
    final perlModules = Platform.isWindows
        ? await _prepareAndroidPerlModules(pinnedPerl)
        : null;
    final perlRuntime = await _captureVersion(perl.path, const [
      '-e',
      r'print "$^O $^V"',
    ]);
    final gitVersion = Platform.isWindows
        ? await _captureVersion('git.exe', const ['--version'])
        : null;
    final clangVersion = await _captureVersion(
      _join(toolchainBin.path, Platform.isWindows ? 'clang.exe' : 'clang'),
      const ['--version'],
    );
    final ndkPath = Platform.isWindows ? _msysPath(ndk.path) : _unix(ndk.path);
    final environment = <String, String>{
      'ANDROID_NDK_ROOT': ndkPath,
      'ANDROID_NDK': ndkPath,
      'ANDROID_NDK_HOME': ndkPath,
      // Do not inherit a host compiler selection into OpenSSL's Android
      // Configure probe. Its Android target replaces these with the
      // architecture/API-specific NDK wrappers after locating clang.
      'CC': 'clang',
      'CXX': 'clang++',
      'SOURCE_DATE_EPOCH': sourceDateEpoch.toString(),
      if (perlModules != null) ...{
        // Prevent MSYS from rewriting the drive colon back into PERL5LIB. Git
        // Perl treats a converted `C:/...` value as two search paths.
        'PERL5LIB': _msysPath(perlModules.path),
        'MSYS2_ENV_CONV_EXCL':
            'PERL5LIB;ANDROID_NDK_ROOT;ANDROID_NDK;ANDROID_NDK_HOME',
      },
      'PATH': [
        _unix(toolchainBin.path),
        if (File(make).isAbsolute) _unix(File(make).parent.path),
        _unix(perl.parent.path),
        Platform.environment['PATH'] ?? '',
      ].join(Platform.isWindows ? ';' : ':'),
    };

    // A partial build defines the complete staged Android ABI set. Remove only
    // the known library filename for each unrequested supported ABI so an old
    // binary can never be inventoried as output from this invocation.
    await pruneUnrequestedAndroidArtifacts(architectures);

    for (final architecture in architectures) {
      final platformBuild = Directory(
        _join(buildRoot.path, 'android', architecture),
      );
      await platformBuild.create(recursive: true);
      final opensslPrefix = await _buildOpenSsl(
        target: NativeTarget.android,
        architecture: architecture,
        source: sources['openssl']!,
        platformBuild: platformBuild,
        perl: perl.path,
        make: make,
        environment: environment,
        toolIdentity: {
          'androidNdk': toolchains['androidNdk'],
          'clang': clangVersion,
          'perl': perlRuntime,
          'git': ?gitVersion,
          if (Platform.isWindows)
            'perlModules': {
              'version': tools['perl-windows-x64']!.version,
              'archiveSha256': tools['perl-windows-x64']!.sha256,
            },
        },
      );
      final nativeBuild = Directory(
        _join(platformBuild.path, 'simple-torrent'),
      );
      await nativeBuild.create(recursive: true);
      final arguments = _resolvedCmakeArguments(
        NativeTarget.android,
        architecture,
        opensslPrefix,
        sources,
        ndk: ndk,
      )..add('-DCMAKE_MAKE_PROGRAM=${_unix(await _findNinja())}');
      await _run('cmake', arguments, environment: environment);
      await _run('cmake', [
        '--build',
        nativeBuild.path,
        '--parallel',
        '--target',
        'simple_torrent_native',
      ], environment: environment);
      final library = await _findFile(
        nativeBuild,
        'libsimple_torrent_native.so',
      );
      final strippedLibrary = File(
        _join(platformBuild.path, 'libsimple_torrent_native.stripped.so'),
      );
      if (strippedLibrary.existsSync()) await strippedLibrary.delete();
      await library.copy(strippedLibrary.path);
      await _run(strip.path, [
        '--strip-unneeded',
        strippedLibrary.path,
      ], environment: environment);
      final package = Directory(
        _join(repositoryRoot.path, 'packages', 'simple_torrent_android'),
      );
      await _stageFile(
        strippedLibrary,
        File(
          _join(
            package.path,
            'android',
            'src',
            'main',
            'jniLibs',
            architecture,
            'libsimple_torrent_native.so',
          ),
        ),
      );
      await _stageFile(
        File(
          _join(
            repositoryRoot.path,
            'native',
            'include',
            'simple_torrent_native.h',
          ),
        ),
        File(
          _join(
            package.path,
            'android',
            'src',
            'main',
            'cpp',
            'include',
            'simple_torrent_native.h',
          ),
        ),
      );
    }
  }

  Future<void> _buildIos(
    Map<String, Directory> sources,
    List<String> architectures,
    File caBundle,
  ) async {
    _requireAppleHost('iOS');
    final merged = <String, File>{};
    for (final architecture in architectures) {
      merged[architecture] = await _buildAppleSlice(
        target: NativeTarget.ios,
        architecture: architecture,
        sources: sources,
        caBundle: caBundle,
      );
    }
    final frameworkBuild = Directory(
      _join(buildRoot.path, 'ios', 'xcframework'),
    );
    if (frameworkBuild.existsSync()) {
      await _deleteDirectoryWithin(frameworkBuild, buildRoot);
    }
    await frameworkBuild.create(recursive: true);
    final arguments = <String>['-create-xcframework'];
    final device = merged['arm64'];
    if (device != null) {
      arguments.addAll([
        '-library',
        device.path,
        '-headers',
        _join(repositoryRoot.path, 'native', 'include'),
      ]);
    }
    final simulatorSlices = [merged['sim-arm64']].whereType<File>().toList();
    if (simulatorSlices.isNotEmpty) {
      final simulator = File(
        _join(frameworkBuild.path, _appleStaticArchiveName),
      );
      if (simulatorSlices.length == 1) {
        await simulatorSlices.single.copy(simulator.path);
      } else {
        await _run('xcrun', [
          'lipo',
          '-create',
          ...simulatorSlices.map((file) => file.path),
          '-output',
          simulator.path,
        ]);
      }
      arguments.addAll([
        '-library',
        simulator.path,
        '-headers',
        _join(repositoryRoot.path, 'native', 'include'),
      ]);
    }
    final output = Directory(
      _join(frameworkBuild.path, 'SimpleTorrentNative.xcframework'),
    );
    arguments.addAll(['-output', output.path]);
    await _run('xcodebuild', arguments);
    await _stageDirectory(
      output,
      Directory(
        _join(
          repositoryRoot.path,
          'packages',
          'simple_torrent_ios',
          'ios',
          'simple_torrent_ios',
          'Frameworks',
          'SimpleTorrentNative.xcframework',
        ),
      ),
    );
  }

  Future<void> _buildMacos(
    Map<String, Directory> sources,
    List<String> architectures,
    File caBundle,
  ) async {
    _requireAppleHost('macOS');
    final slices = <File>[];
    for (final architecture in architectures) {
      slices.add(
        await _buildAppleSlice(
          target: NativeTarget.macos,
          architecture: architecture,
          sources: sources,
          caBundle: caBundle,
        ),
      );
    }
    final frameworkBuild = Directory(
      _join(buildRoot.path, 'macos', 'xcframework'),
    );
    if (frameworkBuild.existsSync()) {
      await _deleteDirectoryWithin(frameworkBuild, buildRoot);
    }
    await frameworkBuild.create(recursive: true);
    final universal = File(_join(frameworkBuild.path, _appleStaticArchiveName));
    if (slices.length == 1) {
      await slices.single.copy(universal.path);
    } else {
      await _run('xcrun', [
        'lipo',
        '-create',
        ...slices.map((file) => file.path),
        '-output',
        universal.path,
      ]);
    }
    final output = Directory(
      _join(frameworkBuild.path, 'SimpleTorrentNative.xcframework'),
    );
    await _run('xcodebuild', [
      '-create-xcframework',
      '-library',
      universal.path,
      '-headers',
      _join(repositoryRoot.path, 'native', 'include'),
      '-output',
      output.path,
    ]);
    await _stageDirectory(
      output,
      Directory(
        _join(
          repositoryRoot.path,
          'packages',
          'simple_torrent_macos',
          'macos',
          'simple_torrent_macos',
          'Frameworks',
          'SimpleTorrentNative.xcframework',
        ),
      ),
    );
  }

  Future<Map<String, Object?>> canonicalNativeInputFingerprint(
    NativeTarget target,
  ) async {
    final inputs = <String, File>{};

    void addFile(File file) {
      final type = FileSystemEntity.typeSync(file.path, followLinks: false);
      if (type != FileSystemEntityType.file) {
        throw StateError(
          'Canonical native input is missing or is not a file: ${file.path}',
        );
      }
      _requireStrictlyWithin(file, repositoryRoot, operation: 'fingerprint');
      inputs[_relativePath(file.path)] = file;
    }

    Future<void> addDirectory(Directory directory) async {
      final type = FileSystemEntity.typeSync(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.directory) {
        throw StateError(
          'Canonical native input directory is missing: ${directory.path}',
        );
      }
      _requireStrictlyWithin(
        directory,
        repositoryRoot,
        operation: 'fingerprint',
      );
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Link) {
          throw StateError(
            'Canonical native inputs may not contain links: ${entity.path}',
          );
        }
        if (entity is File) addFile(entity);
      }
    }

    for (final relative in [
      ['native', 'CMakeLists.txt'],
      ['native', 'dependencies.lock.json'],
      ['tool', 'native.dart'],
      ['tool', 'native.ps1'],
      ['tool', 'native.sh'],
      ['tool', 'src', 'native_builder.dart'],
    ]) {
      addFile(File(_joinRelative(repositoryRoot.path, relative.join('/'))));
    }
    for (final relative in [
      ['native', 'include'],
      ['native', 'src'],
      ['native', 'patches'],
      ['native', 'test'],
    ]) {
      await addDirectory(
        Directory(_joinRelative(repositoryRoot.path, relative.join('/'))),
      );
    }
    final platformDirectoryName = switch (target) {
      NativeTarget.android => 'android',
      NativeTarget.windows => 'windows',
      NativeTarget.ios || NativeTarget.macos => 'apple',
    };
    final platformDirectory = Directory(
      _join(repositoryRoot.path, 'native', 'platform', platformDirectoryName),
    );
    if (platformDirectory.existsSync()) {
      await addDirectory(platformDirectory);
    }

    final paths = inputs.keys.toList()..sort();
    final files = <Map<String, Object?>>[];
    for (final path in paths) {
      final normalized = (await inputs[path]!.readAsString())
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      final bytes = utf8.encode(normalized);
      files.add({
        'path': path,
        'size': bytes.length,
        'sha256': Sha256.bytes(bytes),
      });
    }
    final identity = <String, Object?>{
      'schemaVersion': nativeInputFingerprintSchemaVersion,
      'normalization': 'utf8-lf-v1',
      'target': target.cliName,
      'files': files,
    };
    return {
      ...identity,
      'sha256': Sha256.bytes(utf8.encode(jsonEncode(identity))),
    };
  }

  Future<Map<String, Object?>> expectedArtifactManifestProvenance() async {
    final dependencyRecords = <String, Object?>{};
    for (final entry in dependencies.entries) {
      dependencyRecords[entry.key] = {
        'version': entry.value.version,
        'archiveSha256': entry.value.sha256,
        'patches': await _sourcePatchRecords(entry.value),
      };
    }
    final assetRecords = <String, Object?>{};
    for (final entry in assets.entries) {
      assetRecords[entry.key] = {
        'version': entry.value.version,
        'sha256': entry.value.sha256,
      };
    }
    final auxiliaryToolRecords = <String, Object?>{};
    for (final entry in tools.entries) {
      auxiliaryToolRecords[entry.key] = {
        'version': entry.value.version,
        'archiveSha256': entry.value.sha256,
      };
    }
    return {
      'schemaVersion': nativeArtifactManifestSchemaVersion,
      'builderVersion': nativeBuilderVersion,
      'nativeAbi': simpleTorrentNativeAbiVersion,
      'sourceDateEpoch': sourceDateEpoch,
      'dependencies': dependencyRecords,
      'assets': assetRecords,
      'auxiliaryTools': auxiliaryToolRecords,
      'toolchains': toolchains,
    };
  }

  Future<Map<String, Object?>> expectedPlatformBuildProvenance(
    NativeTarget target,
    List<String> architectures, {
    Map<String, Object?>? artifactInputs,
  }) async {
    final pinnedInputs =
        artifactInputs ?? await expectedArtifactManifestProvenance();
    return {
      'schemaVersion': nativePlatformProvenanceSchemaVersion,
      'target': target.cliName,
      'artifactInputs': pinnedInputs,
      'recipe': {
        'architectures': architectures,
        'minimum': switch (target) {
          NativeTarget.windows => toolchains['windowsMinimum'],
          NativeTarget.android => 'API ${toolchains['androidApi']}',
          NativeTarget.ios => toolchains['iosMinimum'],
          NativeTarget.macos => toolchains['macosMinimum'],
        },
        'buildType': 'Release',
        'opensslLinkage': 'static',
        'features': _nativeFeatures(target),
        'buildFlags': _reproducibleBuildFlags(target),
      },
      'nativeInputs': await canonicalNativeInputFingerprint(target),
    };
  }

  Future<void> validateArtifactManifestProvenance(
    Map<String, Object?> manifest,
  ) async {
    final expected = await expectedArtifactManifestProvenance();
    for (final entry in expected.entries) {
      if (!_jsonValuesEqual(manifest[entry.key], entry.value)) {
        throw StateError(
          'Artifact manifest provenance mismatch for ${entry.key}; rebuild '
          'native artifacts with the current lock and builder.',
        );
      }
    }
  }

  Future<void> validatePlatformBuildProvenance(
    NativeTarget target,
    Map<String, Object?> platform,
  ) async {
    final rawArchitectures = platform['architectures'];
    if (rawArchitectures is! List ||
        rawArchitectures.any((value) => value is! String)) {
      throw StateError(
        'Artifact manifest has invalid ${target.cliName} architectures.',
      );
    }
    final expected = await expectedPlatformBuildProvenance(
      target,
      rawArchitectures.cast<String>(),
    );
    if (!_jsonValuesEqual(platform['buildProvenance'], expected)) {
      throw StateError(
        'Artifact manifest ${target.cliName} build provenance does not match '
        'the current native inputs; rebuild that platform.',
      );
    }
  }

  Map<String, Object?> composeArtifactManifest({
    required Map<String, Object?> existingManifest,
    required Map<String, Object?> rootProvenance,
    required NativeTarget target,
    required Map<String, Object?> targetPlatform,
  }) {
    final existingPlatforms = existingManifest['platforms'];
    if (existingPlatforms != null && existingPlatforms is! Map) {
      throw StateError('Existing artifact manifest platforms are invalid.');
    }
    final platforms = <String, Object?>{
      if (existingPlatforms is Map)
        ...existingPlatforms.cast<String, Object?>(),
    };
    // Replace only the platform that was just built. In particular, do not
    // copy current lock/source provenance into preserved platform records.
    platforms[target.cliName] = targetPlatform;
    final hostToolsByPlatform = <String, Object?>{};
    for (final entry in platforms.entries) {
      final platform = entry.value;
      if (platform is Map && platform['hostTools'] is Map) {
        hostToolsByPlatform[entry.key] = platform['hostTools'];
      }
    }
    return {
      ...rootProvenance,
      'hostTools': hostToolsByPlatform,
      'platforms': platforms,
    };
  }

  Future<void> _writeArtifactManifest(
    NativeTarget target,
    List<String> architectures, {
    String? sourceSha,
  }) async {
    final manifestFile = File(
      _join(repositoryRoot.path, 'native', 'artifacts.manifest.json'),
    );
    Map<String, Object?> manifest = {};
    if (manifestFile.existsSync()) {
      manifest = (jsonDecode(await manifestFile.readAsString()) as Map)
          .cast<String, Object?>();
    }
    final files = await _artifactFiles(target);
    if (files.isEmpty) {
      throw StateError('No staged ${target.cliName} artifacts were found.');
    }
    final records = <Map<String, Object?>>[];
    for (final file in files) {
      records.add({
        'path': _relativePath(file.path),
        'size': await file.length(),
        'sha256': await Sha256.file(file),
      });
    }
    records.sort(
      (left, right) =>
          (left['path']! as String).compareTo(right['path']! as String),
    );
    final recordedArchitectures = target == NativeTarget.android
        ? _androidArchitecturesInRecords(records)
        : architectures;
    if (target == NativeTarget.android) {
      validateAndroidArtifactInventory(
        records.map((record) => record['path']! as String),
        architectures,
      );
      if (!_sameStringSet(recordedArchitectures, architectures)) {
        throw StateError(
          'Staged Android architectures (${recordedArchitectures.join(', ')}) '
          'do not match this build (${architectures.join(', ')}).',
        );
      }
    }
    final hostTools = await _hostToolVersions(target);
    final provenance = await expectedArtifactManifestProvenance();
    final platformRecord = <String, Object?>{
      'architectures': recordedArchitectures,
      'minimum': switch (target) {
        NativeTarget.windows => toolchains['windowsMinimum'],
        NativeTarget.android => 'API ${toolchains['androidApi']}',
        NativeTarget.ios => toolchains['iosMinimum'],
        NativeTarget.macos => toolchains['macosMinimum'],
      },
      'buildType': 'Release',
      'opensslLinkage': 'static',
      'features': _nativeFeatures(target),
      'buildFlags': _reproducibleBuildFlags(target),
      'hostTools': hostTools,
      'buildProvenance': await expectedPlatformBuildProvenance(
        target,
        recordedArchitectures,
        artifactInputs: provenance,
      ),
      'files': records,
      'fragmentSourceSha': ?sourceSha,
    };
    final output = composeArtifactManifest(
      existingManifest: manifest,
      rootProvenance: provenance,
      target: target,
      targetPlatform: platformRecord,
    );
    if (sourceSha != null) output['fragmentSourceSha'] = sourceSha;
    final temporary = File('${manifestFile.path}.tmp');
    _requireStrictlyWithin(
      manifestFile,
      repositoryRoot,
      operation: 'write manifest',
    );
    await _prepareTemporaryFileWithin(
      temporary,
      repositoryRoot,
      operation: 'write manifest',
    );
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(output)}\n',
    );
    if (manifestFile.existsSync()) await manifestFile.delete();
    await _renameEntityWithin(temporary, manifestFile, repositoryRoot);
  }

  Future<void> assemble(
    Map<NativeTarget, String> fragmentPaths, {
    required String sourceSha,
    String? outputPath,
  }) async {
    await validateSourceShaMatchesCheckout(sourceSha);
    final fragments = <NativeTarget, File>{};
    for (final entry in fragmentPaths.entries) {
      fragments[entry.key] = File(entry.value).isAbsolute
          ? File(entry.value)
          : File(_joinRelative(repositoryRoot.path, entry.value));
    }
    final manifest = await assembleManifestFragments(
      fragments,
      sourceSha: sourceSha,
    );
    final output = outputPath == null
        ? File(_join(repositoryRoot.path, 'native', 'artifacts.manifest.json'))
        : (File(outputPath).isAbsolute
              ? File(outputPath)
              : File(_joinRelative(repositoryRoot.path, outputPath)));
    _requireStrictlyWithin(output, repositoryRoot, operation: 'write manifest');
    await output.parent.create(recursive: true);
    final temporary = File('${output.path}.tmp');
    await _prepareTemporaryFileWithin(
      temporary,
      repositoryRoot,
      operation: 'write manifest',
    );
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    if (output.existsSync()) await output.delete();
    await _renameEntityWithin(temporary, output, repositoryRoot);
    stdout.writeln(
      jsonEncode({
        'ok': true,
        'command': 'assemble',
        'output': _relativePath(output.path),
        'platforms': NativeTarget.values
            .map((target) => target.cliName)
            .toList(),
      }),
    );
  }

  Future<Map<String, Object?>> assembleManifestFragments(
    Map<NativeTarget, File> fragments, {
    required String sourceSha,
  }) async {
    if (!_isFullGitSha(sourceSha)) {
      throw StateError('Assembly source SHA must be a full Git commit ID.');
    }
    if (fragments.length != NativeTarget.values.length ||
        NativeTarget.values.any((target) => !fragments.containsKey(target))) {
      throw StateError(
        'Assembly requires exactly one manifest fragment for every platform.',
      );
    }
    final canonicalFragments = <String>{};
    final rootProvenance = await expectedArtifactManifestProvenance();
    final platforms = <String, Object?>{};
    final hostTools = <String, Object?>{};
    final allArtifactPaths = <String>{};

    for (final target in NativeTarget.values) {
      final fragmentFile = fragments[target]!;
      final fragmentType = FileSystemEntity.typeSync(
        fragmentFile.path,
        followLinks: false,
      );
      if (fragmentType == FileSystemEntityType.notFound) {
        throw StateError(
          '${target.cliName} manifest fragment is missing: ${fragmentFile.path}',
        );
      }
      if (fragmentType != FileSystemEntityType.file) {
        throw StateError(
          '${target.cliName} manifest fragment must be a regular file, not a '
          'link or special entry: ${fragmentFile.path}',
        );
      }
      final resolvedFragment = _canonical(
        fragmentFile.resolveSymbolicLinksSync(),
      );
      if (!canonicalFragments.add(resolvedFragment)) {
        throw StateError(
          'A manifest fragment was supplied for more than one platform: '
          '${fragmentFile.path}',
        );
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(await fragmentFile.readAsString());
      } on FormatException catch (error) {
        throw StateError(
          '${target.cliName} manifest fragment is not valid JSON: $error',
        );
      }
      if (decoded is! Map) {
        throw StateError(
          '${target.cliName} manifest fragment must contain a JSON object.',
        );
      }
      final fragment = decoded.cast<String, Object?>();
      final allowedRootKeys = {
        ...rootProvenance.keys,
        'fragmentSourceSha',
        'hostTools',
        'platforms',
      };
      if (!_sameStringSet(fragment.keys, allowedRootKeys)) {
        throw StateError(
          '${target.cliName} manifest fragment has missing or unknown '
          'top-level fields.',
        );
      }
      await validateArtifactManifestProvenance(fragment);
      if (fragment['fragmentSourceSha'] != sourceSha.toLowerCase()) {
        throw StateError(
          '${target.cliName} manifest fragment was not built from '
          '$sourceSha.',
        );
      }
      final rawPlatforms = fragment['platforms'];
      if (rawPlatforms is! Map) {
        throw StateError(
          '${target.cliName} manifest fragment has no platforms object.',
        );
      }
      final rawPlatform = rawPlatforms[target.cliName];
      if (rawPlatform is! Map) {
        throw StateError(
          '${target.cliName} manifest fragment has no named platform record.',
        );
      }
      final platform = rawPlatform.cast<String, Object?>();
      if (platform['fragmentSourceSha'] != sourceSha.toLowerCase()) {
        throw StateError(
          '${target.cliName} platform record has mixed source provenance.',
        );
      }
      final allowedPlatformKeys = {
        'architectures',
        'minimum',
        'buildType',
        'opensslLinkage',
        'features',
        'buildFlags',
        'hostTools',
        'buildProvenance',
        'files',
        'fragmentSourceSha',
      };
      if (platform.keys.any((key) => !allowedPlatformKeys.contains(key)) ||
          !allowedPlatformKeys.every(platform.containsKey)) {
        throw StateError(
          '${target.cliName} platform record has missing or unknown fields.',
        );
      }
      final expectedArchitectures = normalizedArchitectures(target, const []);
      final rawArchitectures = platform['architectures'];
      if (rawArchitectures is! List ||
          !_jsonValuesEqual(rawArchitectures, expectedArchitectures)) {
        throw StateError(
          '${target.cliName} fragment is not a complete release build; '
          'expected ${expectedArchitectures.join(', ')}.',
        );
      }
      _validateTargetManifestProvenance(target, fragment, platform);
      await validatePlatformBuildProvenance(target, platform);
      final records = await _validateFragmentArtifactRecords(target, platform);
      for (final record in records) {
        final path = record['path']! as String;
        if (!allArtifactPaths.add(path)) {
          throw StateError('Duplicate artifact path across fragments: $path');
        }
      }
      final platformHostTools = (platform['hostTools']! as Map)
          .cast<String, Object?>();
      hostTools[target.cliName] = _canonicalJsonValue(platformHostTools);
      platforms[target.cliName] = {
        'architectures': expectedArchitectures,
        'minimum': platform['minimum'],
        'buildType': platform['buildType'],
        'opensslLinkage': platform['opensslLinkage'],
        'features': _canonicalJsonValue(platform['features']),
        'buildFlags': List<Object?>.from(platform['buildFlags']! as List),
        'hostTools': _canonicalJsonValue(platformHostTools),
        'buildProvenance': _canonicalJsonValue(platform['buildProvenance']),
        'files': records,
      };
    }

    // fragmentSourceSha is intentionally not persisted. It authenticates the
    // fan-in operation, while the canonical input fingerprints in each
    // platform record provide durable provenance without making a later
    // identical manual rebuild produce a manifest-only diff.
    return {...rootProvenance, 'hostTools': hostTools, 'platforms': platforms};
  }

  Future<List<Map<String, Object?>>> _validateFragmentArtifactRecords(
    NativeTarget target,
    Map<String, Object?> platform,
  ) async {
    final rawFiles = platform['files'];
    if (rawFiles is! List ||
        rawFiles.isEmpty ||
        rawFiles.any((record) => record is! Map)) {
      throw StateError(
        '${target.cliName} fragment has invalid or empty file records.',
      );
    }
    final records = <Map<String, Object?>>[];
    for (final rawRecord in rawFiles.cast<Map>()) {
      final record = rawRecord.cast<String, Object?>();
      if (!_sameStringSet(record.keys, const ['path', 'size', 'sha256']) ||
          record['path'] is! String ||
          record['size'] is! int ||
          (record['size']! as int) < 0 ||
          record['sha256'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(record['sha256']! as String)) {
        throw StateError(
          '${target.cliName} fragment contains a malformed file record.',
        );
      }
      records.add({
        'path': validateArtifactRelativePath(record['path']! as String),
        'size': record['size'],
        'sha256': record['sha256'],
      });
    }
    records.sort(
      (left, right) =>
          (left['path']! as String).compareTo(right['path']! as String),
    );
    await validateStagedArtifactInventory(
      target,
      records.map((record) => record['path']! as String),
    );
    for (final record in records) {
      final relative = record['path']! as String;
      final file = File(_joinRelative(repositoryRoot.path, relative));
      if (!file.existsSync() ||
          !_pathIsWithin(
            repositoryRoot.path,
            file.resolveSymbolicLinksSync(),
          )) {
        throw StateError(
          'Artifact is missing or escapes the repository: $relative',
        );
      }
      if (await file.length() != record['size']) {
        throw StateError('Artifact size mismatch during assembly: $relative');
      }
      if (await Sha256.file(file) != record['sha256']) {
        throw StateError(
          'Artifact checksum mismatch during assembly: $relative',
        );
      }
      if (isNativeHeaderArtifactPath(relative)) {
        validateCanonicalNativeHeaderBytes(relative, await file.readAsBytes());
      }
    }
    return records;
  }

  Future<void> syncMetadata() async {
    _validateDeclaredLicenses();
    final noticeTargets = <String, NativeTarget?>{
      'THIRD_PARTY_NOTICES.md': null,
      'packages/simple_torrent_windows/THIRD_PARTY_NOTICES.md':
          NativeTarget.windows,
      'packages/simple_torrent_android/THIRD_PARTY_NOTICES.md':
          NativeTarget.android,
      'packages/simple_torrent_ios/THIRD_PARTY_NOTICES.md': NativeTarget.ios,
      'packages/simple_torrent_macos/THIRD_PARTY_NOTICES.md':
          NativeTarget.macos,
    };
    for (final entry in noticeTargets.entries) {
      final file = File(_joinRelative(repositoryRoot.path, entry.key));
      if (!file.existsSync()) {
        throw StateError('Third-party notice is missing: ${entry.key}');
      }
      final rawContent = await file.readAsString();
      final content = rawContent
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      final firstStart = content.indexOf(_generatedNoticeStart);
      final firstEnd = content.indexOf(_generatedNoticeEnd);
      if (firstStart < 0 ||
          firstEnd < firstStart ||
          content.indexOf(_generatedNoticeStart, firstStart + 1) >= 0 ||
          content.indexOf(_generatedNoticeEnd, firstEnd + 1) >= 0) {
        throw StateError(
          '${entry.key} must contain exactly one bounded generated native '
          'dependency table.',
        );
      }
      final replacement =
          '$_generatedNoticeStart\n\n'
          '${renderNativeDependencyTable(entry.value)}\n\n'
          '$_generatedNoticeEnd';
      final updated = content.replaceRange(
        firstStart,
        firstEnd + _generatedNoticeEnd.length,
        replacement,
      );
      if (updated != rawContent) await file.writeAsString(updated);
    }
    stdout.writeln(
      jsonEncode({
        'ok': true,
        'command': 'sync-metadata',
        'files': noticeTargets.keys.toList(),
      }),
    );
  }

  String renderNativeDependencyTable(NativeTarget? target) {
    _validateDeclaredLicenses();
    final rows = <List<String>>[
      [
        'libtorrent',
        dependencies['libtorrent']!.version,
        dependencies['libtorrent']!.license!,
      ],
      [
        'Boost',
        dependencies['boost']!.version,
        dependencies['boost']!.license!,
      ],
      [
        'OpenSSL',
        dependencies['openssl']!.version,
        dependencies['openssl']!.license!,
      ],
      if (target == null || target == NativeTarget.android)
        [
          'LLVM libc++ / libc++abi${target == null ? ' (Android only)' : ''}',
          'Android NDK ${toolchains['androidNdk']}',
          'Apache-2.0 WITH LLVM-exception',
        ],
      if (target == null ||
          target == NativeTarget.ios ||
          target == NativeTarget.macos)
        [
          'Mozilla CA certificate bundle',
          assets['mozilla-ca-bundle']!.version,
          assets['mozilla-ca-bundle']!.license!,
        ],
    ];
    return [
      '| Component | Pinned version | License (SPDX) |',
      '| --- | --- | --- |',
      ...rows.map((row) => '| ${row.join(' | ')} |'),
    ].join('\n');
  }

  void _validateDeclaredLicenses() {
    const reviewedLicenses = <String, String>{
      'libtorrent': 'BSD-3-Clause',
      'boost': 'BSL-1.0',
      'openssl': 'Apache-2.0',
      'mozilla-ca-bundle': 'MPL-2.0',
    };
    for (final entry in reviewedLicenses.entries) {
      final spec = dependencies[entry.key] ?? assets[entry.key];
      if (spec == null || spec.license != entry.value) {
        throw StateError(
          'License identifier for ${entry.key} is missing or changed '
          '(expected ${entry.value}, found ${spec?.license ?? 'none'}). '
          'Review the complete upstream license text before updating the '
          'builder\'s accepted license identifier.',
        );
      }
    }
    for (final entry in [...dependencies.entries, ...assets.entries]) {
      if (!reviewedLicenses.containsKey(entry.key) ||
          entry.value.license == null) {
        throw StateError(
          'Unknown license metadata for ${entry.key}; review the complete '
          'license text before generating notices.',
        );
      }
    }
  }

  Map<String, Object?> _nativeFeatures(NativeTarget target) => {
    'cxxStandard': 17,
    'cAbi': true,
    'libtorrentLinkage': 'static',
    'opensslLinkage': 'static',
    'cxxRuntimeLinkage': switch (target) {
      NativeTarget.windows || NativeTarget.android => 'static',
      NativeTarget.ios || NativeTarget.macos => 'system',
    },
    'dht': true,
    'extensions': true,
    'encryption': true,
    'logging': false,
    'deprecatedApis': false,
    'sharedOutput':
        target == NativeTarget.windows || target == NativeTarget.android,
    'minimumTarget': switch (target) {
      NativeTarget.windows => toolchains['windowsMinimum'],
      NativeTarget.android => 'API ${toolchains['androidApi']}',
      NativeTarget.ios => toolchains['iosMinimum'],
      NativeTarget.macos => toolchains['macosMinimum'],
    },
  };

  List<String> _reproducibleBuildFlags(NativeTarget target) => [
    'CMAKE_BUILD_TYPE=Release',
    'SOURCE_DATE_EPOCH=$sourceDateEpoch',
    'CXX_STANDARD=17',
    'TORRENT_LINKING_STATIC=1',
    'BOOST_ALL_NO_LIB=1',
    'build_tests=OFF',
    'build_examples=OFF',
    'build_tools=OFF',
    'python-bindings=OFF',
    'deprecated-functions=OFF',
    'logging=OFF',
    'encryption=ON',
    'dht=ON',
    if (target == NativeTarget.windows) ...[
      'MSVC_RUNTIME_LIBRARY=MultiThreaded',
      '/Brepro',
      '/experimental:deterministic',
      '/pathmap:<source>=.',
      '/PDBALTPATH:%_PDB%',
      'WINVER=0x0A00',
    ] else ...[
      '-ffile-prefix-map=<source>=.',
      '-ffile-prefix-map=<build>=build',
    ],
    if (target == NativeTarget.android) ...[
      'ANDROID_PLATFORM=android-${toolchains['androidApi']}',
      'ANDROID_STL=c++_static',
      '-Wl,--exclude-libs,ALL',
      'llvm-strip=--strip-unneeded',
    ],
    if (target == NativeTarget.ios)
      'CMAKE_OSX_DEPLOYMENT_TARGET=${toolchains['iosMinimum']}',
    if (target == NativeTarget.macos)
      'CMAKE_OSX_DEPLOYMENT_TARGET=${toolchains['macosMinimum']}',
    if (target == NativeTarget.ios || target == NativeTarget.macos)
      'ZERO_AR_DATE=1',
  ];

  Future<Map<String, Object?>> _hostToolVersions(NativeTarget target) async {
    return expectedHostTools(target);
  }

  Map<String, Object?> expectedHostTools(NativeTarget target) => {
    'cmake': toolchains['cmake'],
    'ninja': toolchains['ninja'],
    if (target == NativeTarget.windows) ...{
      'msvcToolset': toolchains['msvcToolset'],
      'windowsSdk': toolchains['windowsSdk'],
    },
    if (target == NativeTarget.android) 'androidNdk': toolchains['androidNdk'],
    if (target == NativeTarget.ios || target == NativeTarget.macos)
      'xcode': toolchains['xcode'],
  };

  Future<void> _assertPinnedBuildToolchains(
    NativeTarget target, {
    required bool offline,
  }) async {
    final cmakeVersion = await _captureVersion(
      Platform.isWindows ? 'cmake.exe' : 'cmake',
      const ['--version'],
    );
    _requireVersionMarker(
      'CMake',
      cmakeVersion,
      'cmake version ${toolchains['cmake']}',
    );
    final ninjaVersion = await _captureVersion(
      Platform.isWindows ? 'ninja.exe' : 'ninja',
      const ['--version'],
    );
    if (ninjaVersion?.trim() != toolchains['ninja']) {
      throw StateError(
        'Ninja ${toolchains['ninja']} is required; found '
        '${ninjaVersion ?? 'no executable'}.',
      );
    }

    switch (target) {
      case NativeTarget.windows:
        if (!Platform.isWindows) return;
        final environment = await _visualStudioEnvironment();
        final actualMsvc = environment['VCTOOLSVERSION']?.trim() ?? '';
        final expectedMsvc = toolchains['msvcToolset']! as String;
        if (actualMsvc != expectedMsvc &&
            !actualMsvc.startsWith('$expectedMsvc.')) {
          throw StateError(
            'MSVC $expectedMsvc is required; vcvars selected $actualMsvc.',
          );
        }
        final actualSdk =
            environment['WINDOWSSDKVERSION']?.replaceAll('\\', '').trim() ?? '';
        if (actualSdk != toolchains['windowsSdk']) {
          throw StateError(
            'Windows SDK ${toolchains['windowsSdk']} is required; vcvars '
            'selected $actualSdk.',
          );
        }
        return;
      case NativeTarget.android:
        await _findAndroidNdk(offline: offline);
        return;
      case NativeTarget.ios:
      case NativeTarget.macos:
        _requireAppleHost(target.cliName);
        final xcodeVersion = await _captureVersion('xcodebuild', const [
          '-version',
        ]);
        _requireVersionMarker(
          'Xcode',
          xcodeVersion,
          'Xcode ${toolchains['xcode']}',
        );
        return;
    }
  }

  void _requireVersionMarker(
    String tool,
    String? actual,
    String expectedMarker,
  ) {
    if (actual == null ||
        !actual
            .split(RegExp(r'[\r\n|]+'))
            .any((line) => line.trim() == expectedMarker)) {
      throw StateError(
        '$tool $expectedMarker is required; found ${actual ?? 'no executable'}.',
      );
    }
  }

  Future<String?> _captureVersion(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        runInShell: false,
      );
      if (result.exitCode != 0) return null;
      final lines = '${result.stdout}\n${result.stderr}'
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(2);
      final value = lines.join(' | ');
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  void _validateTargetManifestProvenance(
    NativeTarget target,
    Map<String, Object?> manifest,
    Map<String, Object?> platform,
  ) {
    final expectedPlatformValues = <String, Object?>{
      'minimum': switch (target) {
        NativeTarget.windows => toolchains['windowsMinimum'],
        NativeTarget.android => 'API ${toolchains['androidApi']}',
        NativeTarget.ios => toolchains['iosMinimum'],
        NativeTarget.macos => toolchains['macosMinimum'],
      },
      'buildType': 'Release',
      'opensslLinkage': 'static',
      'features': _nativeFeatures(target),
      'buildFlags': _reproducibleBuildFlags(target),
    };
    for (final entry in expectedPlatformValues.entries) {
      if (!_jsonValuesEqual(platform[entry.key], entry.value)) {
        throw StateError(
          'Artifact manifest ${target.cliName}.${entry.key} does not match '
          'the current builder.',
        );
      }
    }

    final rawArchitectures = platform['architectures'];
    if (rawArchitectures is! List ||
        rawArchitectures.isEmpty ||
        rawArchitectures.any((value) => value is! String)) {
      throw StateError(
        'Artifact manifest has invalid ${target.cliName} architectures.',
      );
    }
    final architectures = rawArchitectures.cast<String>();
    final allowed = normalizedArchitectures(target, const []).toSet();
    if (architectures.toSet().length != architectures.length ||
        architectures.any((architecture) => !allowed.contains(architecture))) {
      throw StateError(
        'Artifact manifest has unsupported or duplicate ${target.cliName} '
        'architectures.',
      );
    }

    final platformHostTools = platform['hostTools'];
    final rootHostTools = manifest['hostTools'];
    if (platformHostTools is! Map ||
        rootHostTools is! Map ||
        !_jsonValuesEqual(rootHostTools[target.cliName], platformHostTools)) {
      throw StateError(
        'Artifact manifest host-tool provenance is inconsistent for '
        '${target.cliName}.',
      );
    }
    if (!_jsonValuesEqual(platformHostTools, expectedHostTools(target))) {
      throw StateError(
        'Artifact manifest ${target.cliName} host tools do not match the '
        'pinned toolchains.',
      );
    }
  }

  Future<void> verify(NativeTarget target) async {
    final manifestFile = File(
      _join(repositoryRoot.path, 'native', 'artifacts.manifest.json'),
    );
    if (!manifestFile.existsSync()) {
      throw StateError(
        'Artifact manifest is missing. Build ${target.cliName} first.',
      );
    }
    final manifest = (jsonDecode(await manifestFile.readAsString()) as Map)
        .cast<String, Object?>();
    // Validate lock-, patch-, builder-, and ABI-derived provenance before any
    // path, checksum, or binary from the manifest is trusted.
    await validateArtifactManifestProvenance(manifest);
    final rawPlatforms = manifest['platforms'];
    if (rawPlatforms is! Map) {
      throw StateError('Artifact manifest platforms section is invalid.');
    }
    final platforms = rawPlatforms.cast<String, Object?>();
    final platform = platforms[target.cliName];
    if (platform is! Map) {
      throw StateError(
        'Artifact manifest has no ${target.cliName} entry. Build it first.',
      );
    }
    final platformRecord = platform.cast<String, Object?>();
    final fragmentSourceSha = manifest['fragmentSourceSha'];
    if (fragmentSourceSha != null &&
        (fragmentSourceSha is! String ||
            !_isFullGitSha(fragmentSourceSha) ||
            platformRecord['fragmentSourceSha'] != fragmentSourceSha)) {
      throw StateError(
        'Artifact manifest fragment source provenance is inconsistent for '
        '${target.cliName}.',
      );
    }
    _validateTargetManifestProvenance(target, manifest, platformRecord);
    await validatePlatformBuildProvenance(target, platformRecord);
    final rawFiles = platformRecord['files'];
    if (rawFiles is! List || rawFiles.any((record) => record is! Map)) {
      throw StateError(
        'Artifact manifest has invalid ${target.cliName} file records.',
      );
    }
    final records = rawFiles.cast<Map>();
    final architectures = (platformRecord['architectures']! as List)
        .cast<String>();
    final manifestPaths = <String>[];
    for (final rawRecord in records) {
      final record = rawRecord.cast<String, Object?>();
      final rawPath = record['path'];
      if (rawPath is! String) {
        throw StateError(
          'Artifact manifest has a non-string ${target.cliName} file path.',
        );
      }
      manifestPaths.add(validateArtifactRelativePath(rawPath));
    }
    // Enumerate the staging roots independently. Exact set equality prevents
    // an unmanifested stale ABI or any other extra file from being trusted by
    // omission, while links and paths escaping the repository fail closed.
    await validateStagedArtifactInventory(target, manifestPaths);
    for (final rawRecord in records) {
      final record = rawRecord.cast<String, Object?>();
      final rawRelative = record['path']! as String;
      final relative = validateArtifactRelativePath(rawRelative);
      final file = File(_joinRelative(repositoryRoot.path, relative));
      if (!_pathIsWithin(repositoryRoot.path, file.absolute.path)) {
        throw StateError('Unsafe artifact path in manifest: $rawRelative');
      }
      if (!file.existsSync()) {
        throw StateError('Artifact is missing: $relative');
      }
      if (!_pathIsWithin(
        repositoryRoot.path,
        file.resolveSymbolicLinksSync(),
      )) {
        throw StateError(
          'Artifact path resolves outside the repository: $rawRelative',
        );
      }
      final size = await file.length();
      if (size != record['size']) {
        throw StateError('Artifact size mismatch: $relative');
      }
      final digest = await Sha256.file(file);
      if (digest != record['sha256']) {
        throw StateError('Artifact checksum mismatch: $relative');
      }
      if (isNativeHeaderArtifactPath(relative)) {
        validateCanonicalNativeHeaderBytes(relative, await file.readAsBytes());
      }
    }
    switch (target) {
      case NativeTarget.windows:
        await _verifyWindows(records);
      case NativeTarget.android:
        await _verifyAndroid(records, architectures);
      case NativeTarget.ios:
      case NativeTarget.macos:
        await _verifyApple(target, records);
    }
    _result('verify', target, ok: true, extra: {'files': records.length});
  }

  Future<Directory> _buildOpenSsl({
    required NativeTarget target,
    required String architecture,
    required Directory source,
    required Directory platformBuild,
    required String perl,
    required String make,
    required Map<String, String> environment,
    required Map<String, Object?> toolIdentity,
  }) async {
    final root = Directory(_join(platformBuild.path, 'openssl'));
    final build = Directory(_join(root.path, 'build'));
    final installRoot = Directory(_join(root.path, 'install-root'));
    final stamp = File(_join(root.path, '.simple-torrent-openssl-build.json'));
    final prefix = Directory(
      _join(installRoot.path, 'simple-torrent', 'openssl'),
    );
    final libraryName = Platform.isWindows && target == NativeTarget.windows
        ? 'libssl.lib'
        : 'libssl.a';
    final cryptoLibraryName =
        Platform.isWindows && target == NativeTarget.windows
        ? 'libcrypto.lib'
        : 'libcrypto.a';
    final sslLibrary = File(_join(prefix.path, 'lib', libraryName));
    final alternateSsl = File(_join(prefix.path, 'lib64', libraryName));
    final cryptoLibrary = File(_join(prefix.path, 'lib', cryptoLibraryName));
    final alternateCrypto = File(
      _join(prefix.path, 'lib64', cryptoLibraryName),
    );
    final configureOptions = <String>[
      'no-shared',
      'no-tests',
      'no-docs',
      'no-module',
      'no-apps',
      '--prefix=/simple-torrent/openssl',
      '--openssldir=/simple-torrent/ssl',
      if (target == NativeTarget.android)
        '-D__ANDROID_API__=${toolchains['androidApi']}',
    ];
    final identity = <String, Object?>{
      'schemaVersion': 1,
      'builderVersion': nativeBuilderVersion,
      'dependencyVersion': dependencies['openssl']!.version,
      'dependencySha256': dependencies['openssl']!.sha256,
      'target': target.cliName,
      'architecture': architecture,
      'sourceDateEpoch': sourceDateEpoch,
      'androidApi': target == NativeTarget.android
          ? toolchains['androidApi']
          : null,
      'prefixMapRecipe': target == NativeTarget.windows
          ? 'msvc-pathmap-v1'
          : 'relative-prefix-map-v1',
      'configureTarget': _opensslTarget(target, architecture),
      'configureOptions': configureOptions,
      'toolIdentity': toolIdentity,
    };
    var reusable = false;
    if ((sslLibrary.existsSync() || alternateSsl.existsSync()) &&
        (cryptoLibrary.existsSync() || alternateCrypto.existsSync()) &&
        stamp.existsSync()) {
      try {
        final recorded = (jsonDecode(await stamp.readAsString()) as Map)
            .cast<String, Object?>();
        final ssl = sslLibrary.existsSync() ? sslLibrary : alternateSsl;
        final crypto = cryptoLibrary.existsSync()
            ? cryptoLibrary
            : alternateCrypto;
        reusable =
            jsonEncode(recorded['identity']) == jsonEncode(identity) &&
            recorded['sslSha256'] == await Sha256.file(ssl) &&
            recorded['cryptoSha256'] == await Sha256.file(crypto) &&
            jsonEncode(recorded['prefixFiles']) ==
                jsonEncode(await _directoryFingerprint(prefix));
      } on FormatException {
        reusable = false;
      } on TypeError {
        reusable = false;
      }
    }
    if (reusable) {
      _log(
        'Using built OpenSSL ${dependencies['openssl']!.version} for $architecture',
      );
      return prefix;
    }
    if (root.existsSync()) {
      await _deleteDirectoryWithin(root, buildRoot);
    }
    await root.create(recursive: true);
    await build.create(recursive: true);
    await installRoot.create(recursive: true);
    final buildEnvironment = Map<String, String>.of(environment);
    final reproducibleFlags = target == NativeTarget.windows
        ? [
            '/Brepro',
            '/experimental:deterministic',
            '/pathmap:${_unix(source.path)}=third_party/openssl',
            '/pathmap:${_unix(build.path)}=build/openssl',
          ]
        : [
            // OpenSSL exposes its CFLAGS through build-info. Relative mappings
            // keep that metadata reproducible without recording the checkout.
            '-ffile-prefix-map=.=build/openssl',
            '-fdebug-prefix-map=.=build/openssl',
          ];
    if (target == NativeTarget.windows) {
      // OpenSSL deliberately compiles CFLAGS into its build-info string. MSVC
      // also honors options from CL, which keeps the path maps effective
      // without leaking their host-side source paths into libcrypto.
      buildEnvironment['CL'] = [
        if ((buildEnvironment['CL'] ?? '').trim().isNotEmpty)
          buildEnvironment['CL']!.trim(),
        ...reproducibleFlags,
      ].join(' ');
    } else {
      for (final variable in ['CFLAGS', 'CXXFLAGS']) {
        buildEnvironment[variable] = [
          if ((buildEnvironment[variable] ?? '').trim().isNotEmpty)
            buildEnvironment[variable]!.trim(),
          ...reproducibleFlags,
        ].join(' ');
      }
    }
    final configuration = <String>[
      // Git for Windows Perl treats backslashes in the script path as escape
      // characters, which makes FindBin resolve OpenSSL's bundled Perl modules
      // relative to the build directory. Forward slashes work for both native
      // Windows Perl distributions and Git Perl.
      _unix(_join(source.path, 'Configure')),
      _opensslTarget(target, architecture),
      ...configureOptions,
    ];
    await _run(
      perl,
      configuration,
      workingDirectory: build,
      environment: buildEnvironment,
    );
    if (target == NativeTarget.windows) {
      await _run(
        make,
        ['/NOLOGO', '/S', 'build_libs'],
        workingDirectory: build,
        environment: buildEnvironment,
      );
      await _run(
        make,
        ['/NOLOGO', '/S', 'DESTDIR=${_unix(installRoot.path)}', 'install_sw'],
        workingDirectory: build,
        environment: buildEnvironment,
      );
    } else {
      await _run(
        make,
        ['-s', '-j${Platform.numberOfProcessors}', 'build_libs'],
        workingDirectory: build,
        environment: buildEnvironment,
      );
      await _run(
        make,
        ['-s', 'DESTDIR=${_unix(installRoot.path)}', 'install_sw'],
        workingDirectory: build,
        environment: buildEnvironment,
      );
    }
    final builtSsl = sslLibrary.existsSync() ? sslLibrary : alternateSsl;
    final builtCrypto = cryptoLibrary.existsSync()
        ? cryptoLibrary
        : alternateCrypto;
    if (!builtSsl.existsSync() || !builtCrypto.existsSync()) {
      throw StateError(
        'OpenSSL did not install both required static archives.',
      );
    }
    await stamp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'identity': identity, 'sslSha256': await Sha256.file(builtSsl), 'cryptoSha256': await Sha256.file(builtCrypto), 'prefixFiles': await _directoryFingerprint(prefix)})}\n',
    );
    return prefix;
  }

  List<String> _resolvedCmakeArguments(
    NativeTarget target,
    String architecture,
    Directory opensslPrefix,
    Map<String, Directory> sources, {
    Directory? ndk,
    File? caBundle,
  }) {
    final nativeBuild = Directory(
      _join(buildRoot.path, target.cliName, architecture, 'simple-torrent'),
    );
    final result = cmakeArguments(target, architecture, opensslPrefix.path)
        .map(
          (argument) => argument
              .replaceAll(
                '<libtorrent-source>',
                _unix(sources['libtorrent']!.path),
              )
              .replaceAll('<boost-source>', _unix(sources['boost']!.path))
              .replaceAll('<ndk>', _unix(ndk?.path ?? '<ndk>')),
        )
        .toList();
    result.insertAll(2, ['-B', _unix(nativeBuild.path)]);
    result.addAll([
      '-DSTN_SOURCE_DATE_EPOCH=$sourceDateEpoch',
      '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
    ]);
    if (target != NativeTarget.windows) {
      final defaultLibrary = Directory(_join(opensslPrefix.path, 'lib'));
      final libraryDirectory = defaultLibrary.existsSync()
          ? defaultLibrary
          : Directory(_join(opensslPrefix.path, 'lib64'));
      result.addAll([
        '-DOPENSSL_INCLUDE_DIR=${_unix(_join(opensslPrefix.path, 'include'))}',
        '-DOPENSSL_SSL_LIBRARY=${_unix(_join(libraryDirectory.path, 'libssl.a'))}',
        '-DOPENSSL_CRYPTO_LIBRARY=${_unix(_join(libraryDirectory.path, 'libcrypto.a'))}',
      ]);
    }
    if (caBundle != null) {
      result.add('-DSTN_CA_BUNDLE_FILE=${_unix(caBundle.path)}');
    }
    return result;
  }

  Future<File> _buildAppleSlice({
    required NativeTarget target,
    required String architecture,
    required Map<String, Directory> sources,
    required File caBundle,
  }) async {
    final platformBuild = Directory(
      _join(buildRoot.path, target.cliName, architecture),
    );
    await platformBuild.create(recursive: true);
    final perlPath =
        (await _which('perl')) ??
        (throw StateError('Perl is required to build OpenSSL on Apple hosts.'));
    final environment = <String, String>{
      'SOURCE_DATE_EPOCH': sourceDateEpoch.toString(),
      ..._appleDeploymentEnvironment(target),
    };
    final opensslPrefix = await _buildOpenSsl(
      target: target,
      architecture: architecture,
      source: sources['openssl']!,
      platformBuild: platformBuild,
      perl: perlPath,
      make: 'make',
      environment: environment,
      toolIdentity: {
        'xcode': await _captureVersion('xcodebuild', const ['-version']),
        'clang': await _captureVersion('xcrun', const ['clang', '--version']),
        'perl': await _captureVersion(perlPath, const [
          '-e',
          r'print "$^O $^V"',
        ]),
        'deploymentTarget': target == NativeTarget.ios
            ? toolchains['iosMinimum']
            : toolchains['macosMinimum'],
      },
    );
    final nativeBuild = Directory(_join(platformBuild.path, 'simple-torrent'));
    await nativeBuild.create(recursive: true);
    final arguments = _resolvedCmakeArguments(
      target,
      architecture,
      opensslPrefix,
      sources,
      caBundle: caBundle,
    )..add('-DCMAKE_MAKE_PROGRAM=${_unix(await _findNinja())}');
    await _run('cmake', arguments, environment: environment);
    await _run('cmake', [
      '--build',
      nativeBuild.path,
      '--parallel',
      '--target',
      'simple_torrent_native',
    ], environment: environment);
    final native = await _findFile(nativeBuild, _appleStaticArchiveName);
    final libtorrent = await _findFile(nativeBuild, 'libtorrent-rasterbar.a');
    final libssl = await _findFile(opensslPrefix, 'libssl.a');
    final libcrypto = await _findFile(opensslPrefix, 'libcrypto.a');
    final merged = File(_join(platformBuild.path, _appleStaticArchiveName));
    if (merged.existsSync()) await merged.delete();
    await _run('xcrun', [
      'libtool',
      '-static',
      '-o',
      merged.path,
      native.path,
      libtorrent.path,
      libssl.path,
      libcrypto.path,
    ], environment: environment);
    return merged;
  }

  Future<Map<String, String>> _visualStudioEnvironment() async {
    final vswhere = File(
      _join(
        Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)',
        'Microsoft Visual Studio',
        'Installer',
        'vswhere.exe',
      ),
    );
    if (!vswhere.existsSync()) {
      throw StateError('Visual Studio Installer vswhere.exe was not found.');
    }
    final result = await _run(vswhere.path, [
      '-latest',
      '-version',
      '[17.0,19.0)',
      '-products',
      '*',
      '-requires',
      'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
      '-property',
      'installationPath',
    ], capture: true);
    final installation = (result.stdout as String).trim();
    if (installation.isEmpty) {
      throw StateError(
        'Visual Studio 2022 or 2026 C++ build tools are not installed.',
      );
    }
    final vcvars = File(
      _join(installation, 'VC', 'Auxiliary', 'Build', 'vcvars64.bat'),
    );
    if (!vcvars.existsSync()) {
      throw StateError('vcvars64.bat was not found at ${vcvars.path}.');
    }
    final environmentResult = await _run('cmd.exe', [
      '/d',
      '/s',
      '/c',
      'call',
      vcvars.path,
      '${toolchains['windowsSdk']}',
      '-vcvars_ver=${toolchains['msvcToolset']}',
      '>nul',
      '&&',
      'set',
    ], capture: true);
    final environment = <String, String>{};
    for (final line in const LineSplitter().convert(
      environmentResult.stdout as String,
    )) {
      final separator = line.indexOf('=');
      if (separator > 0) {
        // Windows treats environment variable names case-insensitively, while
        // Dart's map does not. Normalising avoids emitting both `Path` (from
        // vcvars) and `PATH` (our prepended tools), where CreateProcess may
        // choose the stale parent path and fail to locate nmake/cl.
        environment[line.substring(0, separator).toUpperCase()] = line
            .substring(separator + 1);
      }
    }
    return environment;
  }

  Future<File> _findPerl({required bool offline}) async {
    if (Platform.isWindows) {
      // OpenSSL's native Windows build requires a complete Perl distribution.
      // The same pinned archive supplies pure modules to Git's POSIX Perl for
      // Android builds, keeping both paths reproducible and offline-capable.
      final directory = await _prepareTool(
        tools['perl-windows-x64']!,
        offline: offline,
      );
      return _findFile(directory, 'perl.exe');
    }
    final command = await _which('perl');
    if (command != null) return File(command);
    throw StateError('Perl was not found in PATH.');
  }

  Future<File> _findGitPosixPerl() async {
    if (!Platform.isWindows) {
      final command = await _which('perl');
      if (command != null) return File(command);
      throw StateError('A POSIX Perl executable was not found in PATH.');
    }

    final candidates = <File>[];
    final git = await _which('git.exe');
    if (git != null) {
      try {
        final execPath = await Process.run(git, const [
          '--exec-path',
        ], runInShell: false);
        final reported = execPath.exitCode == 0
            ? execPath.stdout.toString().trim()
            : '';
        if (reported.isNotEmpty) {
          var directory = Directory(reported);
          for (var level = 0; level < 8; level++) {
            candidates.add(
              File(_join(directory.path, 'usr', 'bin', 'perl.exe')),
            );
            final parent = directory.parent;
            if (parent.path == directory.path) break;
            directory = parent;
          }
        }
      } on ProcessException {
        // Fall through to executable-path and standard-install discovery.
      }
      var directory = File(git).parent;
      for (var level = 0; level < 6; level++) {
        candidates.add(File(_join(directory.path, 'usr', 'bin', 'perl.exe')));
        final parent = directory.parent;
        if (parent.path == directory.path) break;
        directory = parent;
      }
    }
    for (final programFiles in {
      Platform.environment['ProgramW6432'],
      Platform.environment['ProgramFiles'],
      r'C:\Program Files',
    }.whereType<String>()) {
      candidates.add(
        File(_join(programFiles, 'Git', 'usr', 'bin', 'perl.exe')),
      );
    }

    for (final candidate in candidates) {
      if (!candidate.existsSync()) continue;
      try {
        final probe = await Process.run(candidate.path, const [
          '-e',
          r'print $^O',
        ], runInShell: false);
        final operatingSystem = probe.exitCode == 0
            ? probe.stdout.toString().trim().toLowerCase()
            : '';
        if (operatingSystem == 'msys') {
          _log('Using Git for Windows POSIX Perl at ${candidate.path}');
          return candidate;
        }
      } on ProcessException {
        // A portable/shim candidate may be incomplete; try the next root.
      }
    }
    throw StateError(
      'Git for Windows POSIX Perl was not found. Install Git for Windows '
      '(required by Flutter) with its standard usr/bin tools; no separate '
      'Perl installation is needed.',
    );
  }

  Future<Directory> _prepareAndroidPerlModules(File pinnedPerl) async {
    final distribution = pinnedPerl.parent.parent;
    final sourceRoot = Directory(_join(distribution.path, 'lib'));
    final modules = <String>[_join('Locale', 'Maketext'), 'ExtUtils', 'Pod'];
    for (final module in modules) {
      final source = Directory(_join(sourceRoot.path, module));
      if (!source.existsSync()) {
        throw StateError(
          'Pinned Perl is missing the required pure module directory: '
          '${source.path}',
        );
      }
    }

    final destination = Directory(
      _join(buildRoot.path, 'android', 'perl-modules'),
    );
    if (destination.existsSync()) {
      await _deleteDirectoryWithin(destination, buildRoot);
    }
    await destination.create(recursive: true);
    for (final module in modules) {
      final target = Directory(_join(destination.path, module));
      await target.parent.create(recursive: true);
      await _run('cmake', [
        '-E',
        'copy_directory',
        _join(sourceRoot.path, module),
        target.path,
      ]);
    }
    return destination;
  }

  Future<File> _findNasm({required bool offline}) async {
    if (Platform.isWindows) {
      final directory = await _prepareTool(
        tools['nasm-windows-x64']!,
        offline: offline,
      );
      return _findFile(directory, 'nasm.exe');
    }
    final command = await _which('nasm');
    if (command == null) {
      throw StateError('NASM was not found in PATH.');
    }
    return File(command);
  }

  Future<Directory> _prepareTool(
    DependencySpec spec, {
    required bool offline,
  }) async {
    final downloads = Directory(_join(cacheRoot.path, 'downloads'));
    await downloads.create(recursive: true);
    final archive = File(_join(downloads.path, spec.archive));
    await _ensureArchive(spec, archive, offline: offline);
    final destination = Directory(
      _join(cacheRoot.path, 'tools', '${spec.name}-${spec.version}'),
    );
    final stamp = File(_join(destination.path, '.simple-torrent-tool.json'));
    final identity = <String, Object?>{
      'schemaVersion': 2,
      'name': spec.name,
      'version': spec.version,
      'archive': spec.archive,
      'archiveSha256': spec.sha256,
    };
    if (destination.existsSync() && stamp.existsSync()) {
      try {
        final recorded = (jsonDecode(await stamp.readAsString()) as Map)
            .cast<String, Object?>();
        if (jsonEncode(recorded['identity']) == jsonEncode(identity)) {
          final fingerprint = await _directoryFingerprint(
            destination,
            excludedFile: stamp,
          );
          if (jsonEncode(recorded['files']) == jsonEncode(fingerprint)) {
            return destination;
          }
        }
      } on FormatException {
        // Re-extract an incomplete or stale tool cache.
      } on TypeError {
        // Re-extract a stamp using an old schema.
      }
    }
    if (destination.existsSync()) {
      await _deleteDirectoryWithin(destination, cacheRoot);
    }
    final extracting = Directory('${destination.path}.extracting');
    if (extracting.existsSync()) {
      await _deleteDirectoryWithin(extracting, cacheRoot);
    }
    await extracting.create(recursive: true);
    await _run('cmake', [
      '-E',
      'tar',
      'xf',
      archive.path,
    ], workingDirectory: extracting);
    final entries = await extracting.list(followLinks: false).toList();
    if (entries.length == 1 && entries.single is Directory) {
      await _renameEntityWithin(entries.single, destination, cacheRoot);
      await _deleteDirectoryWithin(extracting, cacheRoot);
    } else {
      await _renameEntityWithin(extracting, destination, cacheRoot);
    }
    await stamp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'identity': identity, 'files': await _directoryFingerprint(destination)})}\n',
    );
    return destination;
  }

  Future<Directory> _findAndroidNdk({required bool offline}) async {
    final revision = toolchains['androidNdk']! as String;
    final explicit = Platform.environment['ANDROID_NDK'];
    final sdk =
        Platform.environment['ANDROID_SDK_ROOT'] ??
        Platform.environment['ANDROID_SDK'];
    final candidates = <Directory>[
      if (explicit != null) Directory(explicit),
      if (sdk != null) Directory(_join(sdk, 'ndk', revision)),
    ];
    for (final candidate in candidates) {
      if (await _validNdk(candidate, revision)) return candidate;
    }
    if (offline) {
      throw StateError(
        'Android NDK $revision is not installed and --offline was set.',
      );
    }
    if (sdk == null) {
      throw StateError(
        'Set ANDROID_SDK_ROOT (or ANDROID_SDK) so NDK $revision can be installed.',
      );
    }
    final sdkManagerCandidates = [
      File(
        _join(
          sdk,
          'cmdline-tools',
          'latest',
          'bin',
          Platform.isWindows ? 'sdkmanager.bat' : 'sdkmanager',
        ),
      ),
      File(
        _join(
          sdk,
          'tools',
          'bin',
          Platform.isWindows ? 'sdkmanager.bat' : 'sdkmanager',
        ),
      ),
    ];
    File? sdkManager;
    for (final candidate in sdkManagerCandidates) {
      if (candidate.existsSync()) {
        sdkManager = candidate;
        break;
      }
    }
    if (sdkManager == null) {
      throw StateError(
        'Android command-line tools are missing; cannot install NDK $revision.',
      );
    }
    await _run(sdkManager.path, ['--install', 'ndk;$revision']);
    final installed = Directory(_join(sdk, 'ndk', revision));
    if (!await _validNdk(installed, revision)) {
      throw StateError(
        'sdkmanager did not install the expected NDK $revision.',
      );
    }
    return installed;
  }

  Future<bool> _validNdk(Directory directory, String revision) async {
    final properties = File(_join(directory.path, 'source.properties'));
    if (!properties.existsSync()) return false;
    final content = await properties.readAsString();
    return androidNdkSourcePropertiesMatchRevision(content, revision);
  }

  Future<void> validateSourceShaMatchesCheckout(String sourceSha) async {
    if (!_isFullGitSha(sourceSha)) {
      throw StateError('Source SHA must be a full Git commit ID.');
    }
    ProcessResult result;
    try {
      result = await Process.run(
        'git',
        [
          '-c',
          "safe.directory=${repositoryRoot.absolute.path.replaceAll('\\', '/')}",
          'rev-parse',
          '--verify',
          'HEAD',
        ],
        workingDirectory: repositoryRoot.path,
        runInShell: false,
      );
    } on ProcessException catch (error) {
      throw StateError(
        'Git is required to authenticate native fragment source SHAs: $error',
      );
    }
    final checkoutSha = '${result.stdout}'.trim().toLowerCase();
    if (result.exitCode != 0 || !_isFullGitSha(checkoutSha)) {
      throw StateError(
        'Cannot resolve the checked-out Git commit for native generation: '
                '${result.stderr}'
            .trim(),
      );
    }
    if (checkoutSha != sourceSha.toLowerCase()) {
      throw StateError(
        'Native generation source SHA $sourceSha does not match checked-out '
        'commit $checkoutSha.',
      );
    }
  }

  Future<String> _findNinja() async {
    final command = await _which(Platform.isWindows ? 'ninja.exe' : 'ninja');
    if (command == null) {
      throw StateError('Ninja is required and was not found in PATH.');
    }
    return command;
  }

  Future<String?> _which(String executable) async {
    final finder = Platform.isWindows ? 'where.exe' : 'which';
    final result = await Process.run(finder, [executable], runInShell: false);
    if (result.exitCode != 0) return null;
    final lines = const LineSplitter().convert(result.stdout.toString().trim());
    return lines.isEmpty ? null : lines.first;
  }

  Future<File> _findFile(Directory root, String basename) async {
    if (!root.existsSync()) {
      throw StateError(
        'Cannot find $basename because ${root.path} does not exist.',
      );
    }
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is File &&
          _basename(entry.path).toLowerCase() == basename.toLowerCase()) {
        return entry;
      }
    }
    throw StateError('$basename was not produced beneath ${root.path}.');
  }

  Future<List<Map<String, Object?>>> _directoryFingerprint(
    Directory root, {
    File? excludedFile,
  }) async {
    if (!root.existsSync()) return const [];
    final rootPath = root.absolute.path;
    final candidates = <List<String>>[];
    final records = <Map<String, Object?>>[];
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is Link) {
        throw StateError(
          'Authenticated tool/build caches may not contain links: ${entry.path}',
        );
      }
      if (entry is! File ||
          (excludedFile != null &&
              _canonical(entry.path) == _canonical(excludedFile.path))) {
        continue;
      }
      final absolute = entry.absolute.path;
      if (!absolute.startsWith('$rootPath${Platform.pathSeparator}')) {
        throw StateError('Cache entry escaped its root: ${entry.path}');
      }
      candidates.add([
        absolute,
        absolute.substring(rootPath.length + 1).replaceAll('\\', '/'),
      ]);
    }
    candidates.sort((left, right) => left[1].compareTo(right[1]));
    if (candidates.isNotEmpty) {
      var workerCount = Platform.numberOfProcessors;
      if (workerCount > 8) workerCount = 8;
      if (workerCount > candidates.length) workerCount = candidates.length;
      final work = List.generate(workerCount, (_) => <List<String>>[]);
      for (var index = 0; index < candidates.length; index++) {
        work[index % workerCount].add(candidates[index]);
      }
      final batches = workerCount == 1
          ? [await _hashFingerprintCandidates(work.single)]
          : await Future.wait(
              work.map(
                (batch) => Isolate.run(() => _hashFingerprintCandidates(batch)),
              ),
            );
      for (final batch in batches) {
        records.addAll(batch);
      }
    }
    records.sort(
      (left, right) =>
          (left['path']! as String).compareTo(right['path']! as String),
    );
    return records;
  }

  Future<void> _stageFile(File source, File destination) async {
    if (!source.existsSync()) {
      throw StateError('Build output is missing: ${source.path}');
    }
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.staging');
    if (temporary.existsSync()) await temporary.delete();
    await source.copy(temporary.path);
    if (await Sha256.file(source) != await Sha256.file(temporary)) {
      await temporary.delete();
      throw StateError('Staging checksum mismatch for ${destination.path}.');
    }
    if (destination.existsSync()) await destination.delete();
    await _renameEntityWithin(temporary, destination, repositoryRoot);
  }

  Future<void> _stageDirectory(Directory source, Directory destination) async {
    if (!source.existsSync()) {
      throw StateError('Build output is missing: ${source.path}');
    }
    await destination.parent.create(recursive: true);
    final temporary = Directory('${destination.path}.staging');
    if (temporary.existsSync()) {
      await _deleteDirectoryWithin(temporary, repositoryRoot);
    }
    await _run('cmake', ['-E', 'copy_directory', source.path, temporary.path]);
    if (destination.existsSync()) {
      await _deleteDirectoryWithin(destination, repositoryRoot);
    }
    await _renameEntityWithin(temporary, destination, repositoryRoot);
  }

  List<Directory> _artifactRoots(NativeTarget target) => switch (target) {
    NativeTarget.windows => [
      Directory(
        _join(
          repositoryRoot.path,
          'packages',
          'simple_torrent_windows',
          'windows',
          'lib',
        ),
      ),
      Directory(
        _join(
          repositoryRoot.path,
          'packages',
          'simple_torrent_windows',
          'windows',
          'include',
        ),
      ),
    ],
    NativeTarget.android => [
      Directory(
        _join(
          repositoryRoot.path,
          'packages',
          'simple_torrent_android',
          'android',
          'src',
          'main',
          'jniLibs',
        ),
      ),
      Directory(
        _join(
          repositoryRoot.path,
          'packages',
          'simple_torrent_android',
          'android',
          'src',
          'main',
          'cpp',
          'include',
        ),
      ),
    ],
    NativeTarget.ios => [
      Directory(
        _join(
          repositoryRoot.path,
          'packages',
          'simple_torrent_ios',
          'ios',
          'simple_torrent_ios',
          'Frameworks',
          'SimpleTorrentNative.xcframework',
        ),
      ),
    ],
    NativeTarget.macos => [
      Directory(
        _join(
          repositoryRoot.path,
          'packages',
          'simple_torrent_macos',
          'macos',
          'simple_torrent_macos',
          'Frameworks',
          'SimpleTorrentNative.xcframework',
        ),
      ),
    ],
  };

  Future<List<String>> stagedArtifactPaths(NativeTarget target) async {
    final files = await _artifactFiles(target);
    return files
        .map((file) => _relativePath(file.path))
        .toList(growable: false);
  }

  Future<void> canonicalizeStagedArtifactHeaders(NativeTarget target) async {
    for (final file in await _artifactFiles(target)) {
      final relative = _relativePath(file.path);
      if (!isNativeHeaderArtifactPath(relative)) continue;

      final originalBytes = await file.readAsBytes();
      late final String original;
      try {
        original = utf8.decode(originalBytes);
      } on FormatException {
        throw StateError('Staged native header is not valid UTF-8: $relative');
      }
      if (!originalBytes.contains(0x0d)) {
        validateCanonicalNativeHeaderBytes(relative, originalBytes);
        continue;
      }

      final canonicalBytes = utf8.encode(canonicalNativeHeaderText(original));
      final temporary = File(
        _join(
          buildRoot.path,
          'canonical-headers',
          '${Sha256.bytes(utf8.encode(relative))}.tmp',
        ),
      );
      _requireStrictlyWithin(file, repositoryRoot, operation: 'canonicalize');
      await temporary.parent.create(recursive: true);
      await _prepareTemporaryFileWithin(
        temporary,
        repositoryRoot,
        operation: 'canonicalize',
      );
      try {
        await temporary.writeAsBytes(canonicalBytes, flush: true);
        validateCanonicalNativeHeaderBytes(
          relative,
          await temporary.readAsBytes(),
        );
        await _renameEntityWithin(temporary, file, repositoryRoot);
      } finally {
        if (temporary.existsSync()) {
          await _deleteFileWithin(temporary, repositoryRoot);
        }
      }
    }
  }

  Future<void> validateStagedArtifactInventory(
    NativeTarget target,
    Iterable<String> manifestPaths,
  ) async {
    validateExactStagedArtifactPaths(
      target,
      manifestPaths,
      await stagedArtifactPaths(target),
    );
  }

  Future<List<File>> _artifactFiles(NativeTarget target) async {
    final roots = _artifactRoots(target);
    final result = <File>[];
    for (final root in roots) {
      final rootType = FileSystemEntity.typeSync(root.path, followLinks: false);
      if (rootType == FileSystemEntityType.notFound) continue;
      if (rootType != FileSystemEntityType.directory) {
        throw StateError(
          'Artifact staging root is not a directory: ${root.path}',
        );
      }
      _requireStrictlyWithin(root, repositoryRoot, operation: 'inventory');
      await for (final entry in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is Link) {
          throw StateError(
            'Artifact staging roots may not contain links: ${entry.path}',
          );
        }
        if (entry is File || entry is Directory) {
          _requireStrictlyWithin(entry, repositoryRoot, operation: 'inventory');
          if (entry is File) result.add(entry);
          continue;
        }
        throw StateError(
          'Artifact staging roots contain an unsupported entry: ${entry.path}',
        );
      }
    }
    result.sort(
      (left, right) =>
          _relativePath(left.path).compareTo(_relativePath(right.path)),
    );
    return result;
  }

  Future<void> _verifyWindows(List<Map> records) async {
    final dllRecord = records.cast<Map<String, Object?>>().firstWhere(
      (record) => (record['path']! as String).endsWith('.dll'),
      orElse: () => throw StateError('Windows DLL is missing from manifest.'),
    );
    final file = File(
      _joinRelative(repositoryRoot.path, dllRecord['path']! as String),
    );
    final bytes = await file.readAsBytes();
    if (bytes.length < 0x40 || bytes[0] != 0x4d || bytes[1] != 0x5a) {
      throw StateError('Windows artifact is not a PE DLL: ${file.path}');
    }
    final data = ByteData.sublistView(bytes);
    final peOffset = data.getUint32(0x3c, Endian.little);
    if (peOffset + 6 >= bytes.length ||
        data.getUint16(peOffset + 4, Endian.little) != 0x8664) {
      throw StateError('Windows DLL is not x86_64: ${file.path}');
    }
    _verifyBinaryStrings(file, bytes);
    final environment = await _visualStudioEnvironment();
    final vcToolsPath = environment['VCTOOLSINSTALLDIR'];
    if (vcToolsPath == null || vcToolsPath.isEmpty) {
      throw StateError('vcvars64.bat did not report VCToolsInstallDir.');
    }
    var dumpbin = File(
      _join(vcToolsPath, 'bin', 'Hostx64', 'x64', 'dumpbin.exe'),
    );
    if (!dumpbin.existsSync()) {
      dumpbin = await _findFile(Directory(vcToolsPath), 'dumpbin.exe');
    }
    final exportResult = await _run(
      dumpbin.path,
      ['/NOLOGO', '/EXPORTS', file.path],
      capture: true,
      environment: environment,
    );
    _verifyRequiredSuspensionExports(file, exportResult.stdout as String);
    final strings = latin1.decode(bytes, allowInvalid: true).toLowerCase();
    final dllNames = RegExp(r'[a-z0-9_.-]+\.dll')
        .allMatches(strings)
        .map((match) => match.group(0)!)
        .toSet();
    for (final dllName in dllNames) {
      if (dllName.startsWith('libssl') ||
          dllName.startsWith('libcrypto') ||
          dllName.startsWith('torrent-rasterbar') ||
          dllName.startsWith('vcruntime') ||
          dllName.startsWith('msvcp') ||
          dllName == 'ucrtbase.dll' ||
          dllName.startsWith('api-ms-win-crt-') ||
          RegExp(r'^msvcr\d').hasMatch(dllName)) {
        throw StateError(
          'Windows DLL has a forbidden dynamic dependency: $dllName.',
        );
      }
    }
  }

  Future<void> _verifyAndroid(
    List<Map> records,
    List<String> architectures,
  ) async {
    final binaries = records
        .cast<Map<String, Object?>>()
        .where((record) => (record['path']! as String).endsWith('.so'))
        .toList();
    if (architectures.isEmpty || binaries.length != architectures.length) {
      throw StateError(
        'Expected one Android library for each manifest architecture '
        '(${architectures.join(', ')}), found ${binaries.length}.',
      );
    }
    final expectedMachines = {
      'arm64-v8a': 183,
      'armeabi-v7a': 40,
      'x86_64': 62,
    };
    final ndk = await _findAndroidNdk(offline: true);
    final host = Platform.isWindows
        ? 'windows-x86_64'
        : Platform.isMacOS
        ? 'darwin-x86_64'
        : 'linux-x86_64';
    final readelf = File(
      _join(
        ndk.path,
        'toolchains',
        'llvm',
        'prebuilt',
        host,
        'bin',
        Platform.isWindows ? 'llvm-readelf.exe' : 'llvm-readelf',
      ),
    );
    if (!readelf.existsSync()) {
      throw StateError(
        'Pinned Android NDK readelf was not found at ${readelf.path}.',
      );
    }
    for (final record in binaries) {
      final relative = record['path']! as String;
      final architecture = expectedMachines.keys.firstWhere(
        (candidate) => relative.replaceAll('\\', '/').contains('/$candidate/'),
        orElse: () => throw StateError(
          'Android artifact has an unsupported ABI path: $relative',
        ),
      );
      if (!architectures.contains(architecture)) {
        throw StateError(
          '$relative is not listed in the manifest architectures.',
        );
      }
      final file = File(_joinRelative(repositoryRoot.path, relative));
      final bytes = await file.readAsBytes();
      if (bytes.length < 20 ||
          bytes[0] != 0x7f ||
          bytes[1] != 0x45 ||
          bytes[2] != 0x4c ||
          bytes[3] != 0x46) {
        throw StateError('Android artifact is not ELF: $relative');
      }
      final machine = ByteData.sublistView(bytes).getUint16(18, Endian.little);
      if (machine != expectedMachines[architecture]) {
        throw StateError(
          '$relative has ELF machine $machine, expected '
          '${expectedMachines[architecture]}.',
        );
      }
      _verifyBinaryStrings(file, bytes);
      final symbolResult = await _run(readelf.path, [
        '--dyn-syms',
        '--wide',
        file.path,
      ], capture: true);
      _verifyRequiredSuspensionExports(file, symbolResult.stdout as String);
      final result = await _run(readelf.path, [
        '--dynamic',
        file.path,
      ], capture: true);
      final dynamic = (result.stdout as String).toLowerCase();
      if (!dynamic.contains('soname') ||
          !dynamic.contains('libsimple_torrent_native.so')) {
        throw StateError('$relative has no expected SONAME.');
      }
      for (final forbidden in [
        'libssl.so',
        'libcrypto.so',
        'libc++_shared.so',
      ]) {
        if (dynamic.contains(forbidden)) {
          throw StateError('$relative dynamically depends on $forbidden.');
        }
      }
      final sectionsResult = await _run(readelf.path, [
        '--sections',
        file.path,
      ], capture: true);
      final sections = (sectionsResult.stdout as String).toLowerCase();
      if (RegExp(r'\.debug_[a-z0-9_]+').hasMatch(sections) ||
          RegExp(r'\] \.symtab\b').hasMatch(sections) ||
          RegExp(r'\] \.strtab\b').hasMatch(sections)) {
        throw StateError(
          '$relative contains debug or static symbol-table sections; '
          'stage only llvm-strip --strip-unneeded release artifacts.',
        );
      }
    }
  }

  List<String> _androidArchitecturesInRecords(
    List<Map<String, Object?>> records,
  ) {
    const supported = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
    final result = <String>[];
    for (final architecture in supported) {
      final marker = '/$architecture/libsimple_torrent_native.so';
      if (records.any(
        (record) =>
            (record['path']! as String).replaceAll('\\', '/').endsWith(marker),
      )) {
        result.add(architecture);
      }
    }
    return result;
  }

  Future<void> _verifyApple(NativeTarget target, List<Map> records) async {
    _requireAppleHost(target.cliName);
    final typedRecords = records.cast<Map<String, Object?>>();
    final binaryRecords = typedRecords
        .where((record) => (record['path']! as String).endsWith('.a'))
        .toList();
    if (binaryRecords.isEmpty) {
      throw StateError(
        '${target.cliName} XCFramework contains no static library.',
      );
    }
    final plistRecords = typedRecords
        .where((record) => (record['path']! as String).endsWith('/Info.plist'))
        .toList();
    if (plistRecords.length != 1) {
      throw StateError(
        '${target.cliName} XCFramework must contain exactly one Info.plist.',
      );
    }
    final plist = File(
      _joinRelative(
        repositoryRoot.path,
        plistRecords.single['path']! as String,
      ),
    );
    final plistResult = await _run('/usr/bin/plutil', [
      '-convert',
      'json',
      '-o',
      '-',
      plist.path,
    ], capture: true);
    final decodedPlist = jsonDecode(plistResult.stdout as String);
    if (decodedPlist is! Map) {
      throw StateError('${plist.path} did not decode to a plist dictionary.');
    }
    final libraries = validateAppleXcframeworkMetadata(
      target,
      decodedPlist.cast<String, Object?>(),
    );
    final frameworkRoot = plist.parent;
    final expectedBinaryPaths = <String>{};
    for (final library in libraries) {
      final relativeWithinFramework = validateArtifactRelativePath(
        '${library.identifier}/${library.libraryPath}',
      );
      final file = File(
        _joinRelative(frameworkRoot.path, relativeWithinFramework),
      );
      if (!_pathIsWithin(frameworkRoot.path, file.absolute.path)) {
        throw StateError(
          'XCFramework library path escapes its bundle: '
          '$relativeWithinFramework',
        );
      }
      expectedBinaryPaths.add(_canonical(file.path));
      final lipoResult = await _run('xcrun', [
        'lipo',
        '-archs',
        file.path,
      ], capture: true);
      final actualArchitectures = parseLipoArchitectures(
        lipoResult.stdout as String,
      );
      if (!_sameStringSet(actualArchitectures, library.architectures) ||
          actualArchitectures.length != library.architectures.length) {
        throw StateError(
          '${file.path} has lipo architectures '
          '${actualArchitectures.join(', ')}, but Info.plist declares '
          '${library.architectures.join(', ')}.',
        );
      }
      final bytes = await file.readAsBytes();
      _verifyBinaryStrings(file, bytes);
      final symbolResult = await _run('xcrun', [
        'nm',
        '-gU',
        file.path,
      ], capture: true);
      _verifyRequiredSuspensionExports(file, symbolResult.stdout as String);
      final strings = latin1.decode(bytes, allowInvalid: true);
      if (!strings.contains('-----BEGIN CERTIFICATE-----')) {
        throw StateError(
          '${file.path} does not embed the pinned Apple CA bundle.',
        );
      }
    }
    final manifestBinaryPaths = binaryRecords
        .map(
          (record) => _canonical(
            _joinRelative(repositoryRoot.path, record['path']! as String),
          ),
        )
        .toSet();
    if (!_sameStringSet(manifestBinaryPaths, expectedBinaryPaths) ||
        manifestBinaryPaths.length != binaryRecords.length) {
      throw StateError(
        '${target.cliName} XCFramework libraries do not exactly match '
        'Info.plist.',
      );
    }
  }

  void _verifyBinaryStrings(File file, Uint8List bytes) {
    final strings = latin1.decode(bytes, allowInvalid: true);
    for (final marker in binaryVersionMarkers()) {
      if (!strings.contains(marker)) {
        throw StateError(
          '${file.path} does not embed version marker "$marker".',
        );
      }
    }
    final lower = strings.toLowerCase();
    final repositoryPath = repositoryRoot.absolute.path.toLowerCase();
    if (lower.contains(repositoryPath) ||
        lower.contains(repositoryPath.replaceAll('\\', '/')) ||
        lower.contains(r'c:\dev\simple_torrent')) {
      throw StateError('${file.path} embeds a developer-specific source path.');
    }
  }

  List<String> binaryVersionMarkers() {
    final libtorrent = dependencies['libtorrent']!.version;
    final openssl = dependencies['openssl']!.version;
    final boostParts = dependencies['boost']!.version.split('.');
    if (boostParts.length < 2 ||
        boostParts.take(2).any((part) => int.tryParse(part) == null)) {
      throw StateError(
        'Pinned Boost version cannot be converted to BOOST_LIB_VERSION: '
        '${dependencies['boost']!.version}',
      );
    }
    final boost = '${boostParts[0]}_${boostParts[1]}';
    return [
      'simple_torrent_native/2.0.0',
      'libtorrent/$libtorrent',
      'OpenSSL/$openssl',
      'Boost/$boost',
      'libtorrent=$libtorrent;boost=$boost;openssl=$openssl',
    ];
  }

  void _verifyRequiredSuspensionExports(File file, String exportTable) {
    for (final symbol in const [
      'simple_torrent_manager_set_transfers_suspended',
      'simple_torrent_manager_transfers_suspended',
    ]) {
      final exported = RegExp(
        '(^|\\s)_?${RegExp.escape(symbol)}(?=\\s|\$)',
        multiLine: true,
      ).hasMatch(exportTable);
      if (!exported) {
        throw StateError(
          '${file.path} does not export the required C ABI symbol $symbol.',
        );
      }
    }
  }

  void _requireAppleHost(String platformName) {
    if (!Platform.isMacOS) {
      throw StateError(
        '$platformName artifacts must be built on macOS with Xcode.',
      );
    }
  }

  Map<String, String> _appleDeploymentEnvironment(NativeTarget target) =>
      switch (target) {
        NativeTarget.ios => {
          'ZERO_AR_DATE': '1',
          'IPHONEOS_DEPLOYMENT_TARGET': toolchains['iosMinimum']! as String,
        },
        NativeTarget.macos => {
          'ZERO_AR_DATE': '1',
          'MACOSX_DEPLOYMENT_TARGET': toolchains['macosMinimum']! as String,
        },
        NativeTarget.windows || NativeTarget.android => const {},
      };

  String _relativePath(String path) {
    final root = _canonical(repositoryRoot.path);
    final absolute = _canonical(path);
    if (!absolute.startsWith('$root${Platform.pathSeparator}')) {
      throw StateError('Artifact is outside the repository: $path');
    }
    return path
        .substring(repositoryRoot.absolute.path.length + 1)
        .replaceAll('\\', '/');
  }
}

String _opensslTarget(NativeTarget target, String architecture) {
  return switch (target) {
    NativeTarget.windows => 'VC-WIN64A',
    NativeTarget.android => switch (architecture) {
      'arm64-v8a' => 'android-arm64',
      'armeabi-v7a' => 'android-arm',
      'x86_64' => 'android-x86_64',
      _ => throw ArgumentError.value(architecture),
    },
    NativeTarget.ios => switch (architecture) {
      'arm64' => 'ios64-xcrun',
      'sim-arm64' => 'iossimulator-arm64-xcrun',
      _ => throw ArgumentError.value(architecture),
    },
    NativeTarget.macos => switch (architecture) {
      'arm64' => 'darwin64-arm64-cc',
      _ => throw ArgumentError.value(architecture),
    },
  };
}

String _displayCommand(String executable, List<String> arguments) => [
  executable,
  ...arguments.map(
    (value) => value.contains(RegExp(r'[\s"]'))
        ? '"${value.replaceAll('"', r'\"')}"'
        : value,
  ),
].join(' ');

String _join(
  String first,
  String second, [
  String? third,
  String? fourth,
  String? fifth,
  String? sixth,
  String? seventh,
  String? eighth,
  String? ninth,
  String? tenth,
  String? eleventh,
  String? twelfth,
]) {
  final values = [
    first,
    second,
    third,
    fourth,
    fifth,
    sixth,
    seventh,
    eighth,
    ninth,
    tenth,
    eleventh,
    twelfth,
  ].whereType<String>();
  return values.join(Platform.pathSeparator);
}

String _joinRelative(String root, String relative) => [
  root,
  ...relative.replaceAll('\\', '/').split('/'),
].join(Platform.pathSeparator);

String _basename(String path) =>
    path.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).last;

List<String> parseLipoArchitectures(String output) => output
    .trim()
    .split(RegExp(r'\s+'))
    .where((value) => value.isNotEmpty)
    .toList(growable: false);

bool androidNdkSourcePropertiesMatchRevision(
  String sourceProperties,
  String expectedRevision,
) {
  final revisions = <String, String>{};
  const revisionKeys = ['Pkg.BaseRevision', 'Pkg.Revision'];
  for (final rawLine in sourceProperties.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) continue;
    String? recognizedKey;
    for (final key in revisionKeys) {
      if (line == key ||
          line.startsWith('$key=') ||
          line.startsWith('$key ') ||
          line.startsWith('$key\t') ||
          line.startsWith('$key:')) {
        recognizedKey = key;
        break;
      }
    }
    if (recognizedKey == null) continue;
    final separator = line.indexOf('=');
    if (separator < 0) return false;
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    if (key != recognizedKey || value.isEmpty || revisions.containsKey(key)) {
      return false;
    }
    revisions[key] = value;
  }
  final actualRevision = revisions.containsKey('Pkg.BaseRevision')
      ? revisions['Pkg.BaseRevision']
      : revisions['Pkg.Revision'];
  return actualRevision == expectedRevision;
}

List<AppleXcframeworkLibrary> validateAppleXcframeworkMetadata(
  NativeTarget target,
  Map<String, Object?> plist,
) {
  if (target != NativeTarget.ios && target != NativeTarget.macos) {
    throw StateError('XCFramework metadata is only valid for Apple targets.');
  }
  final rawLibraries = plist['AvailableLibraries'];
  if (rawLibraries is! List ||
      rawLibraries.isEmpty ||
      rawLibraries.any((value) => value is! Map)) {
    throw StateError('XCFramework Info.plist has invalid AvailableLibraries.');
  }
  final libraries = <AppleXcframeworkLibrary>[];
  final identifiers = <String>{};
  for (final raw in rawLibraries.cast<Map>()) {
    final value = raw.cast<String, Object?>();
    final identifier = value['LibraryIdentifier'];
    final libraryPath = value['LibraryPath'];
    final binaryPath = value['BinaryPath'];
    final platform = value['SupportedPlatform'];
    final variant = value['SupportedPlatformVariant'];
    final rawArchitectures = value['SupportedArchitectures'];
    if (identifier is! String ||
        identifier.isEmpty ||
        identifier.contains('/') ||
        identifier.contains('\\') ||
        !identifiers.add(identifier) ||
        libraryPath is! String ||
        libraryPath != _appleStaticArchiveName ||
        binaryPath != _appleStaticArchiveName ||
        platform is! String ||
        (variant != null && variant is! String) ||
        (variant is String && variant.isEmpty) ||
        rawArchitectures is! List ||
        rawArchitectures.isEmpty ||
        rawArchitectures.any((arch) => arch is! String)) {
      throw StateError('XCFramework Info.plist has a malformed library entry.');
    }
    validateArtifactRelativePath(libraryPath);
    final architectures = rawArchitectures.cast<String>();
    if (architectures.toSet().length != architectures.length) {
      throw StateError(
        'XCFramework library $identifier declares duplicate architectures.',
      );
    }
    libraries.add(
      AppleXcframeworkLibrary(
        identifier: identifier,
        libraryPath: libraryPath,
        architectures: List.unmodifiable(architectures),
        platform: platform,
        variant: variant as String?,
      ),
    );
  }

  String signature(AppleXcframeworkLibrary library) {
    final architectures = [...library.architectures]..sort();
    return '${library.platform}|${library.variant ?? ''}|'
        '${architectures.join(',')}';
  }

  final actual = libraries.map(signature).toSet();
  final expected = switch (target) {
    NativeTarget.ios => const {'ios||arm64', 'ios|simulator|arm64'},
    NativeTarget.macos => const {'macos||arm64'},
    NativeTarget.windows || NativeTarget.android => const <String>{},
  };
  if (actual.length != libraries.length ||
      actual.length != expected.length ||
      !actual.containsAll(expected)) {
    throw StateError(
      '${target.cliName} XCFramework has incorrect platform, variant, or '
      'architecture metadata; expected ${expected.join(' and ')}.',
    );
  }
  return libraries;
}

String validateArtifactRelativePath(String relative) {
  final normalized = relative.replaceAll('\\', '/');
  final segments = normalized.split('/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      normalized.contains('\u0000') ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw StateError('Unsafe artifact path in manifest: $relative');
  }
  return normalized;
}

void validateAndroidArtifactInventory(
  Iterable<String> relativePaths,
  Iterable<String> architectures,
) {
  final expected = architectures
      .map(
        (architecture) =>
            'packages/simple_torrent_android/android/src/main/jniLibs/'
            '$architecture/libsimple_torrent_native.so',
      )
      .toSet();
  final binaries = relativePaths
      .map((path) => path.replaceAll('\\', '/'))
      .where((path) => path.endsWith('.so'))
      .toList(growable: false);
  if (binaries.length != expected.length ||
      !_sameStringSet(binaries, expected)) {
    throw StateError(
      'Staged Android shared libraries do not exactly match the requested '
      'architectures.',
    );
  }
}

void validateExactStagedArtifactPaths(
  NativeTarget target,
  Iterable<String> manifestPaths,
  Iterable<String> stagedPaths,
) {
  final manifest = manifestPaths
      .map(validateArtifactRelativePath)
      .toList(growable: false);
  final staged = stagedPaths
      .map(validateArtifactRelativePath)
      .toList(growable: false);
  final manifestSet = manifest.toSet();
  final stagedSet = staged.toSet();
  if (manifestSet.length != manifest.length) {
    throw StateError(
      'Artifact manifest contains duplicate normalized ${target.cliName} paths.',
    );
  }
  if (stagedSet.length != staged.length) {
    throw StateError(
      'Artifact staging roots contain duplicate normalized '
      '${target.cliName} paths.',
    );
  }
  final missing = manifestSet.difference(stagedSet).toList()..sort();
  final unmanifested = stagedSet.difference(manifestSet).toList()..sort();
  if (missing.isNotEmpty || unmanifested.isNotEmpty) {
    throw StateError(
      'Staged ${target.cliName} artifact inventory does not match its manifest'
      '${missing.isEmpty ? '' : '; missing: ${missing.join(', ')}'}'
      '${unmanifested.isEmpty ? '' : '; unmanifested: ${unmanifested.join(', ')}'}.',
    );
  }
}

bool _sameStringSet(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}

bool _jsonValuesEqual(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_jsonValuesEqual(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_jsonValuesEqual(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

Object? _canonicalJsonValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJsonValue(value[key]),
    };
  }

  if (value is List) {
    return value.map(_canonicalJsonValue).toList(growable: false);
  }
  return value;
}

bool _pathIsWithin(String root, String candidate) {
  var canonicalRoot = _canonical(root);
  var canonicalCandidate = _canonical(candidate);
  if (Platform.isWindows) {
    canonicalRoot = canonicalRoot.toLowerCase();
    canonicalCandidate = canonicalCandidate.toLowerCase();
  }
  return canonicalCandidate.startsWith(
    '$canonicalRoot${Platform.pathSeparator}',
  );
}

String _unix(String path) => path.replaceAll('\\', '/');

String _msysPath(String path) {
  final normalized = _unix(File(path).absolute.path);
  final drive = RegExp(r'^([A-Za-z]):(?:/|$)').firstMatch(normalized);
  if (drive == null) return normalized;
  final suffix = normalized.substring(2);
  return '/${drive.group(1)!.toLowerCase()}$suffix';
}

String _canonical(String path) {
  var value = Directory(path).absolute.path;
  while (value.endsWith(Platform.pathSeparator)) {
    value = value.substring(0, value.length - 1);
  }
  return Platform.isWindows ? value.toLowerCase() : value;
}

Future<List<Map<String, Object?>>> _hashFingerprintCandidates(
  List<List<String>> candidates,
) async {
  final records = <Map<String, Object?>>[];
  for (final candidate in candidates) {
    final file = File(candidate[0]);
    records.add({
      'path': candidate[1],
      'size': await file.length(),
      'sha256': await Sha256.file(file),
    });
  }
  return records;
}

/// Small dependency-free SHA-256 implementation so the builder works before
/// `dart pub get` and can authenticate every archive in an empty workspace.
final class Sha256 {
  static const _initial = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];

  static const _round = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  static Future<String> file(File file) async {
    final digest = Sha256();
    await for (final chunk in file.openRead()) {
      digest.add(chunk);
    }
    return digest.close();
  }

  static String bytes(List<int> bytes) {
    final digest = Sha256()..add(bytes);
    return digest.close();
  }

  final _hash = List<int>.from(_initial);
  final _pending = BytesBuilder(copy: false);
  var _length = 0;

  void add(List<int> bytes) {
    _length += bytes.length;
    _pending.add(bytes);
    final data = _pending.takeBytes();
    var offset = 0;
    while (data.length - offset >= 64) {
      _compress(Uint8List.sublistView(data, offset, offset + 64));
      offset += 64;
    }
    if (offset < data.length) {
      _pending.add(Uint8List.sublistView(data, offset));
    }
  }

  String close() {
    final bitLength = _length * 8;
    final tail = BytesBuilder(copy: false)
      ..add(_pending.takeBytes())
      ..addByte(0x80);
    while ((tail.length + 8) % 64 != 0) {
      tail.addByte(0);
    }
    final lengthBytes = ByteData(8)..setUint64(0, bitLength, Endian.big);
    tail.add(lengthBytes.buffer.asUint8List());
    final data = tail.takeBytes();
    for (var offset = 0; offset < data.length; offset += 64) {
      _compress(Uint8List.sublistView(data, offset, offset + 64));
    }
    return _hash.map((value) => value.toRadixString(16).padLeft(8, '0')).join();
  }

  void _compress(Uint8List block) {
    final words = List<int>.filled(64, 0);
    final bytes = ByteData.sublistView(block);
    for (var index = 0; index < 16; index++) {
      words[index] = bytes.getUint32(index * 4, Endian.big);
    }
    for (var index = 16; index < 64; index++) {
      final x = words[index - 15];
      final y = words[index - 2];
      final s0 = _rotateRight(x, 7) ^ _rotateRight(x, 18) ^ (x >> 3);
      final s1 = _rotateRight(y, 17) ^ _rotateRight(y, 19) ^ (y >> 10);
      words[index] =
          (words[index - 16] + s0 + words[index - 7] + s1) & 0xffffffff;
    }

    var a = _hash[0];
    var b = _hash[1];
    var c = _hash[2];
    var d = _hash[3];
    var e = _hash[4];
    var f = _hash[5];
    var g = _hash[6];
    var h = _hash[7];
    for (var index = 0; index < 64; index++) {
      final upper =
          _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final choose = (e & f) ^ ((~e) & g);
      final temp1 =
          (h + upper + choose + _round[index] + words[index]) & 0xffffffff;
      final lower =
          _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (lower + majority) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    _hash[0] = (_hash[0] + a) & 0xffffffff;
    _hash[1] = (_hash[1] + b) & 0xffffffff;
    _hash[2] = (_hash[2] + c) & 0xffffffff;
    _hash[3] = (_hash[3] + d) & 0xffffffff;
    _hash[4] = (_hash[4] + e) & 0xffffffff;
    _hash[5] = (_hash[5] + f) & 0xffffffff;
    _hash[6] = (_hash[6] + g) & 0xffffffff;
    _hash[7] = (_hash[7] + h) & 0xffffffff;
  }

  static int _rotateRight(int value, int amount) =>
      ((value >> amount) | (value << (32 - amount))) & 0xffffffff;
}
