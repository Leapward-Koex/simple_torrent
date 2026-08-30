import 'dart:io';

import 'src/native_builder.dart';

Future<void> main(List<String> arguments) async {
  try {
    final invocation = NativeInvocation.parse(arguments);
    final builder = NativeBuilder.fromScript();
    await builder.execute(invocation);
  } on NativeUsageException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(NativeInvocation.usage);
    exitCode = 64;
  } on Object catch (error, stackTrace) {
    stderr.writeln(error);
    if (Platform.environment['SIMPLE_TORRENT_NATIVE_TRACE'] == '1') {
      stderr.writeln(stackTrace);
    }
    stderr.writeln('{"ok":false,"error":${_jsonString(error.toString())}}');
    exitCode = 1;
  }
}

String _jsonString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return '"$escaped"';
}
