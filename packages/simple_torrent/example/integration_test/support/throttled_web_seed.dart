import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// One IPv4-loopback webseed with two distinct multi-file fixtures and one
/// aggregate 512 KiB/s throttle shared by every response.
final class ThrottledWebSeedServer {
  ThrottledWebSeedServer._(this._server) {
    fixtures = <ThrottledTorrentFixture>[_createFixture(1), _createFixture(2)];
  }

  static const fileCount = 32;
  static const fileLength = 256 * 1024;
  static const payloadLength = fileCount * fileLength;
  static const pieceLength = 64 * 1024;
  static const chunkSize = 32 * 1024;

  /// Every full-file response is naturally bounded to this size.
  static const maxResponseLength = fileLength;

  static const chunkDelay = Duration(microseconds: 62500);

  // A client can abandon a response while the native session is being
  // suspended. Some platform HTTP stacks leave flush() or close() pending in
  // that case instead of completing with a socket error. Bound those waits so
  // one dead connection cannot permanently block the aggregate response queue.
  static const responseIoTimeout = Duration(seconds: 5);

  static Future<ThrottledWebSeedServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final webSeed = ThrottledWebSeedServer._(server);
    server.listen(webSeed._handleRequest);
    return webSeed;
  }

  final HttpServer _server;
  final Map<String, _FileRoute> _routes = <String, _FileRoute>{};
  late final List<ThrottledTorrentFixture> fixtures;

  Future<void> _responseTail = Future<void>.value();
  bool _closed = false;

  ThrottledTorrentFixture _createFixture(int variant) {
    final torrentName = 'suspension-fixture-$variant';
    final baseRoute = '/webseed-$variant/';
    final payload = Uint8List.fromList(
      List<int>.generate(
        payloadLength,
        (index) =>
            (index * (29 + variant * 2) + variant * 47 + (index >> 8)) & 0xff,
        growable: false,
      ),
    );
    final state = _FixtureState();
    final files = <ThrottledTorrentFile>[];
    for (var index = 0; index < fileCount; index++) {
      final relativePath = 'part-${index.toString().padLeft(2, '0')}.bin';
      final start = index * fileLength;
      final filePayload = Uint8List.sublistView(
        payload,
        start,
        start + fileLength,
      );
      final file = ThrottledTorrentFile._(
        relativePath: relativePath,
        payload: filePayload,
      );
      files.add(file);
      _routes['$baseRoute$torrentName/$relativePath'] = _FileRoute(
        fixture: state,
        payload: filePayload,
      );
    }
    return ThrottledTorrentFixture._(
      server: this,
      baseRoute: baseRoute,
      state: state,
      fileName: torrentName,
      files: List<ThrottledTorrentFile>.unmodifiable(files),
      payload: payload,
    );
  }

  Uri _uriFor(String route) => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
    path: route,
  );

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final fixture in fixtures) {
      fixture.releaseHeldResponses();
    }
    await _server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final route = _routes[request.uri.path];
    final response = request.response..bufferOutput = false;
    if (route == null) {
      response
        ..statusCode = HttpStatus.notFound
        ..contentLength = 0;
      await response.close();
      return;
    }

    final state = route.fixture;
    if (request.method == 'HEAD') {
      state.headRequestCount++;
    } else if (request.method == 'GET') {
      state.getRequestCount++;
    } else {
      response
        ..statusCode = HttpStatus.methodNotAllowed
        ..contentLength = 0;
      response.headers.set('allow', 'HEAD, GET');
      await response.close();
      return;
    }

    _ResponseTurn? responseTurn;
    try {
      final payload = route.payload;
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final range = _parseRange(rangeHeader, payload.length);
      if (range == null) {
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..contentLength = 0;
        response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..set('content-range', 'bytes */${payload.length}');
        await response.close();
        return;
      }

      // Acquire before setting any successful response headers. This creates a
      // deterministic response boundary without making a queued request look
      // partially served to libtorrent.
      responseTurn = await _beginResponse(state);
      final start = range.$1;
      final end = range.$2;
      final partial = rangeHeader != null;
      response.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
      response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
        ..contentLength = end - start + 1;
      if (partial) {
        response.headers.set(
          'content-range',
          'bytes $start-$end/${payload.length}',
        );
      }
      if (request.method == 'HEAD') {
        await response.close().timeout(responseIoTimeout);
        return;
      }

      for (var offset = start; offset <= end; offset += chunkSize) {
        final chunkEnd = (offset + chunkSize).clamp(0, end + 1);
        await _writeThrottled(
          response,
          state,
          payload.sublist(offset, chunkEnd),
        );
      }
      await response.close().timeout(responseIoTimeout);
    } on Object {
      // Suspending or finalising can abandon an in-flight range.
      // Do not await shutdown here: on iOS the Future itself can remain
      // pending after libtorrent has already closed its end of the socket.
      unawaited(_closeAbandonedResponse(response));
    } finally {
      responseTurn?.complete();
    }
  }

  Future<_ResponseTurn> _beginResponse(_FixtureState state) async {
    final previous = _responseTail;
    final completed = Completer<void>();
    _responseTail = completed.future;
    try {
      await previous;
      await state.acquireResponse();
      return _ResponseTurn(state: state, completed: completed);
    } on Object {
      if (!completed.isCompleted) completed.complete();
      rethrow;
    }
  }

  (int, int)? _parseRange(String? header, int length) {
    if (header == null) return (0, length - 1);
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null;

    final startText = match.group(1)!;
    final endText = match.group(2)!;
    if (startText.isEmpty) {
      final suffixLength = int.tryParse(endText);
      if (suffixLength == null || suffixLength <= 0) return null;
      return ((length - suffixLength).clamp(0, length - 1), length - 1);
    }

    final start = int.tryParse(startText);
    final requestedEnd = endText.isEmpty ? length - 1 : int.tryParse(endText);
    if (start == null ||
        requestedEnd == null ||
        start < 0 ||
        start >= length ||
        requestedEnd < start) {
      return null;
    }
    return (start, requestedEnd.clamp(start, length - 1));
  }

  Future<void> _writeThrottled(
    HttpResponse response,
    _FixtureState state,
    Uint8List chunk,
  ) async {
    if (_closed) return;
    response.add(chunk);
    await response.flush().timeout(responseIoTimeout);
    state.bytesServed += chunk.length;
    await Future<void>.delayed(chunkDelay);
  }

  Future<void> _closeAbandonedResponse(HttpResponse response) async {
    try {
      await response.close().timeout(responseIoTimeout);
    } on Object {
      // The peer is gone or the platform never acknowledged socket shutdown.
    }
  }
}

final class ThrottledTorrentFixture {
  ThrottledTorrentFixture._({
    required this._server,
    required this._baseRoute,
    required this._state,
    required this.fileName,
    required this.files,
    required this.payload,
  });

  final ThrottledWebSeedServer _server;
  final String _baseRoute;
  final _FixtureState _state;

  /// The multi-file torrent's top-level directory name.
  final String fileName;

  final List<ThrottledTorrentFile> files;

  /// All file bytes concatenated in torrent order.
  final Uint8List payload;

  int get pieceLength => ThrottledWebSeedServer.pieceLength;
  int get chunkSize => ThrottledWebSeedServer.chunkSize;
  int get bytesServed => _state.bytesServed;
  int get getRequestCount => _state.getRequestCount;
  int get headRequestCount => _state.headRequestCount;
  int get requestCount => getRequestCount + headRequestCount;
  bool get responsesHeld => _state.responsesHeld;
  int get activeResponseCount => _state.activeResponseCount;
  int get heldResponseCount => _state.heldResponseCount;

  /// The top-level BEP 19 `url-list` base, always ending in `/`.
  Uri get payloadUri => _server._uriFor(_baseRoute);

  Uri uriForFile(ThrottledTorrentFile file) => payloadUri.resolve(
    '${Uri.encodeComponent(fileName)}/${Uri.encodeComponent(file.relativePath)}',
  );

  /// Prevents new successful response headers and bodies from being sent, then
  /// completes once every response already in progress has finished.
  Future<void> holdNewResponsesAndWaitForIdle() =>
      _state.holdNewResponsesAndWaitForIdle();

  /// Allows requests queued by [holdNewResponsesAndWaitForIdle] to proceed.
  void releaseHeldResponses() => _state.releaseHeldResponses();

  late final Uint8List torrentData = _createTorrentData();

  Uint8List _createTorrentData() {
    final pieceHashes = BytesBuilder(copy: false);
    for (var offset = 0; offset < payload.length; offset += pieceLength) {
      final end = (offset + pieceLength).clamp(0, payload.length);
      pieceHashes.add(sha1.convert(payload.sublist(offset, end)).bytes);
    }
    return _bencode(<String, Object>{
      'info': <String, Object>{
        'files': <Object>[
          for (final file in files)
            <String, Object>{
              'length': file.payload.length,
              'path': <Object>[file.relativePath],
            },
        ],
        'name': fileName,
        'piece length': pieceLength,
        'pieces': pieceHashes.takeBytes(),
      },
      'url-list': payloadUri.toString(),
    });
  }
}

final class ThrottledTorrentFile {
  const ThrottledTorrentFile._({
    required this.relativePath,
    required this.payload,
  });

  final String relativePath;
  final Uint8List payload;
}

final class _FixtureState {
  int bytesServed = 0;
  int getRequestCount = 0;
  int headRequestCount = 0;

  bool responsesHeld = false;
  int activeResponseCount = 0;
  int heldResponseCount = 0;
  Completer<void>? _releaseCompleter;
  Completer<void>? _idleCompleter;

  Future<void> acquireResponse() async {
    while (responsesHeld) {
      final release = _releaseCompleter!;
      heldResponseCount++;
      try {
        await release.future;
      } finally {
        heldResponseCount--;
      }
    }
    activeResponseCount++;
  }

  void completeResponse() {
    activeResponseCount--;
    assert(activeResponseCount >= 0);
    if (activeResponseCount != 0) return;
    final idle = _idleCompleter;
    _idleCompleter = null;
    if (idle != null && !idle.isCompleted) idle.complete();
  }

  Future<void> holdNewResponsesAndWaitForIdle() {
    if (!responsesHeld) {
      responsesHeld = true;
      _releaseCompleter = Completer<void>();
    }
    if (activeResponseCount == 0) return Future<void>.value();
    return (_idleCompleter ??= Completer<void>()).future;
  }

  void releaseHeldResponses() {
    if (!responsesHeld) return;
    responsesHeld = false;
    final release = _releaseCompleter;
    _releaseCompleter = null;
    if (release != null && !release.isCompleted) release.complete();
  }
}

final class _FileRoute {
  const _FileRoute({required this.fixture, required this.payload});

  final _FixtureState fixture;
  final Uint8List payload;
}

final class _ResponseTurn {
  _ResponseTurn({required this.state, required this.completed});

  final _FixtureState state;
  final Completer<void> completed;
  bool _isComplete = false;

  void complete() {
    if (_isComplete) return;
    _isComplete = true;
    state.completeResponse();
    if (!completed.isCompleted) completed.complete();
  }
}

Uint8List _bencode(Object value) {
  final output = BytesBuilder(copy: false);
  void encode(Object item) {
    switch (item) {
      case int integer:
        output.add(utf8.encode('i${integer}e'));
      case String string:
        final bytes = utf8.encode(string);
        output
          ..add(utf8.encode('${bytes.length}:'))
          ..add(bytes);
      case Uint8List bytes:
        output
          ..add(utf8.encode('${bytes.length}:'))
          ..add(bytes);
      case List<Object> list:
        output.addByte(0x6c);
        for (final entry in list) {
          encode(entry);
        }
        output.addByte(0x65);
      case Map<String, Object> dictionary:
        output.addByte(0x64);
        final keys = dictionary.keys.toList()..sort();
        for (final key in keys) {
          encode(key);
          encode(dictionary[key]!);
        }
        output.addByte(0x65);
      default:
        throw ArgumentError.value(item, 'value', 'Unsupported bencode type');
    }
  }

  encode(value);
  return output.takeBytes();
}
