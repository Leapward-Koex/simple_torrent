import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/throttled_web_seed.dart';

void main() {
  test('serves complete bounded multi-file webseed responses', () async {
    final server = await ThrottledWebSeedServer.start();
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });

    final fixture = server.fixtures.first;
    final untouchedFixture = server.fixtures.last;
    final firstFile = fixture.files.first;
    final uri = fixture.uriForFile(firstFile);

    expect(fixture.payload, hasLength(8 * 1024 * 1024));
    expect(fixture.files, hasLength(32));
    expect(
      fixture.files.every((file) => file.payload.length == 256 * 1024),
      isTrue,
    );
    expect(fixture.payloadUri.path, '/webseed-1/');
    expect(uri.path, '/webseed-1/suspension-fixture-1/part-00.bin');

    final head = await _request(client, 'HEAD', uri);
    expect(head.statusCode, HttpStatus.ok);
    expect(head.contentLength, 256 * 1024);
    expect(head.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(head.body, isEmpty);

    final rangeHead = await _request(
      client,
      'HEAD',
      uri,
      range: 'bytes=65536-131071',
    );
    expect(rangeHead.statusCode, HttpStatus.partialContent);
    expect(rangeHead.contentLength, 64 * 1024);
    expect(
      rangeHead.headers.value('content-range'),
      'bytes 65536-131071/262144',
    );
    expect(rangeHead.body, isEmpty);

    final full = await _request(client, 'GET', uri);
    expect(full.statusCode, HttpStatus.ok);
    expect(full.contentLength, 256 * 1024);
    expect(full.body, firstFile.payload);

    final range = await _request(
      client,
      'GET',
      uri,
      range: 'bytes=65536-131071',
    );
    expect(range.statusCode, HttpStatus.partialContent);
    expect(range.contentLength, 64 * 1024);
    expect(range.body, firstFile.payload.sublist(65536, 131072));

    final invalidRange = await _request(
      client,
      'GET',
      uri,
      range: 'bytes=262144-',
    );
    expect(invalidRange.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    expect(invalidRange.contentLength, 0);
    expect(invalidRange.headers.value('content-range'), 'bytes */262144');
    expect(invalidRange.body, isEmpty);

    expect(fixture.headRequestCount, 2);
    expect(fixture.getRequestCount, 3);
    expect(fixture.requestCount, 5);
    expect(fixture.bytesServed, 320 * 1024);
    expect(untouchedFixture.requestCount, 0);
    expect(untouchedFixture.bytesServed, 0);
  });

  test('response hold drains the current body and queues the next', () async {
    final server = await ThrottledWebSeedServer.start();
    final client = HttpClient()..maxConnectionsPerHost = 2;
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });

    final fixture = server.fixtures.first;
    final untouchedFixture = server.fixtures.last;
    final firstFile = fixture.files.first;
    final secondFile = fixture.files[1];

    final currentResponse = _request(
      client,
      'GET',
      fixture.uriForFile(firstFile),
    );
    await _waitUntil(
      () =>
          fixture.activeResponseCount == 1 &&
          fixture.bytesServed >= ThrottledWebSeedServer.chunkSize,
      description: 'the first response to start transmitting',
    );

    var boundaryReached = false;
    final boundary = fixture.holdNewResponsesAndWaitForIdle().then((_) {
      boundaryReached = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fixture.responsesHeld, isTrue);
    expect(fixture.activeResponseCount, 1);
    expect(boundaryReached, isFalse);

    final queuedRequest = await client.openUrl(
      'GET',
      fixture.uriForFile(secondFile),
    );
    final queuedHeaders = queuedRequest.close();
    var queuedHeadersReceived = false;
    queuedHeaders.then<void>(
      (_) => queuedHeadersReceived = true,
      onError: (Object _, StackTrace _) => queuedHeadersReceived = true,
    );
    await _waitUntil(
      () => fixture.getRequestCount == 2,
      description: 'the second request to reach the held fixture',
    );

    final current = await currentResponse;
    expect(current.statusCode, HttpStatus.ok);
    expect(current.body, firstFile.payload);
    await boundary;
    await _waitUntil(
      () => fixture.heldResponseCount == 1,
      description: 'the second response to wait behind the hold',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(boundaryReached, isTrue);
    expect(fixture.activeResponseCount, 0);
    expect(fixture.heldResponseCount, 1);
    expect(queuedHeadersReceived, isFalse);
    expect(fixture.getRequestCount, 2);
    expect(fixture.headRequestCount, 0);
    expect(fixture.bytesServed, 256 * 1024);

    fixture.releaseHeldResponses();
    final queuedResponse = await queuedHeaders;
    final queuedBody = BytesBuilder(copy: false);
    await for (final chunk in queuedResponse) {
      queuedBody.add(chunk);
    }
    await _waitUntil(
      () => fixture.activeResponseCount == 0,
      description: 'the released response to finish',
    );

    expect(queuedResponse.statusCode, HttpStatus.ok);
    expect(queuedResponse.contentLength, 256 * 1024);
    expect(queuedBody.takeBytes(), secondFile.payload);
    expect(fixture.responsesHeld, isFalse);
    expect(fixture.activeResponseCount, 0);
    expect(fixture.heldResponseCount, 0);
    expect(fixture.getRequestCount, 2);
    expect(fixture.headRequestCount, 0);
    expect(fixture.requestCount, 2);
    expect(fixture.bytesServed, 512 * 1024);
    expect(untouchedFixture.requestCount, 0);
    expect(untouchedFixture.bytesServed, 0);
  });

  test('an abandoned held response cannot block later requests', () async {
    final server = await ThrottledWebSeedServer.start();
    final abandoningClient = HttpClient()..maxConnectionsPerHost = 2;
    final replacementClient = HttpClient();
    addTearDown(() async {
      abandoningClient.close(force: true);
      replacementClient.close(force: true);
      await server.close();
    });

    final fixture = server.fixtures.first;
    final replacementFixture = server.fixtures.last;
    final currentResponse = _request(
      abandoningClient,
      'GET',
      fixture.uriForFile(fixture.files.first),
    );
    await _waitUntil(
      () => fixture.activeResponseCount == 1,
      description: 'the initial response to become active',
    );

    final boundary = fixture.holdNewResponsesAndWaitForIdle();
    await currentResponse;
    await boundary;

    final abandonedRequest = await abandoningClient.openUrl(
      'GET',
      fixture.uriForFile(fixture.files[1]),
    );
    final abandonedResponse = abandonedRequest.close();
    unawaited(
      abandonedResponse.then<void>(
        (response) => response.drain<void>(),
        onError: (Object _, StackTrace _) {},
      ),
    );
    await _waitUntil(
      () => fixture.heldResponseCount == 1,
      description: 'the response that will be abandoned to reach the hold',
    );

    abandoningClient.close(force: true);
    fixture.releaseHeldResponses();

    final replacementFile = replacementFixture.files.first;
    final replacement = await _request(
      replacementClient,
      'GET',
      replacementFixture.uriForFile(replacementFile),
    ).timeout(const Duration(seconds: 12));
    expect(replacement.statusCode, HttpStatus.ok);
    expect(replacement.body, replacementFile.payload);
    await _waitUntil(
      () => fixture.activeResponseCount == 0,
      description: 'the abandoned response turn to be released',
    );
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String description,
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed >= const Duration(seconds: 3)) {
      throw TimeoutException('Timed out waiting for $description.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<
  ({int statusCode, int contentLength, HttpHeaders headers, Uint8List body})
>
_request(HttpClient client, String method, Uri uri, {String? range}) async {
  final request = await client.openUrl(method, uri);
  if (range != null) {
    request.headers.set(HttpHeaders.rangeHeader, range);
  }
  final response = await request.close();
  final body = BytesBuilder(copy: false);
  await for (final chunk in response) {
    body.add(chunk);
  }
  return (
    statusCode: response.statusCode,
    contentLength: response.contentLength,
    headers: response.headers,
    body: body.takeBytes(),
  );
}
