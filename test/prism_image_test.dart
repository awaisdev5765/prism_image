import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prism_image/prism_image.dart';

// flutter_test installs a fake HttpClient that answers 400 to everything;
// clear it so the local test server can be reached.
void _disableFakeHttpOverrides() {
  HttpOverrides.global = null;
}

/// A valid 1x1 red PNG.
final Uint8List kRedPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  // The decode callback the framework would pass to loadImage.
  Future<ui.Codec> decode(
    ui.ImmutableBuffer buffer, {
    ui.TargetImageSizeCallback? getTargetSize,
    int? width,
    int? height,
    bool allowUpscaling = true,
    String? debugLabel,
  }) {
    return PaintingBinding.instance.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: getTargetSize,
    );
  }

  /// Starts a local HTTP server that fails the first [failures] requests
  /// with [status] and serves a 1x1 PNG afterwards.
  Future<(HttpServer, List<int>)> startCountingServer({
    required int failures,
    int status = 500,
  }) async {
    final requests = <int>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri.path.hashCode);
      if (requests.length <= failures) {
        request.response.statusCode = status;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.parse('image/png');
      request.response.add(kRedPngBytes);
      await request.response.close();
    });
    return (server, requests);
  }

  Future<ui.Image> loadAndAwaitImage(NetworkImageWithRetry provider) {
    final key = provider;
    final completer = provider.loadImage(key, decode);
    final done = Completer<ui.Image>();
    completer.addListener(ImageStreamListener(
      (info, _) => done.complete(info.image),
      onError: (Object error, StackTrace? stack) =>
          done.completeError(error, stack ?? StackTrace.empty),
    ));
    return done.future;
  }

  group('NetworkImageWithRetry', () {
    tearDown(() async {});

    test('decode callback works with a real PNG', () async {
      final buffer = await ui.ImmutableBuffer.fromUint8List(kRedPngBytes);
      final codec = await decode(buffer);
      expect(codec.frameCount, greaterThanOrEqualTo(1));
    });

    testWidgets('succeeds on first attempt when server is healthy',
        (tester) async {
      await tester.runAsync(() async {
        _disableFakeHttpOverrides();
        final (server, requests) = await startCountingServer(failures: 0);
        addTearDown(server.close);

        final provider = NetworkImageWithRetry(
          'http://127.0.0.1:${server.port}/img.png',
          client: http.Client(),
          fetchStrategy: const FetchStrategyBuilder(
            maxTries: 3,
            initialPause: Duration.zero,
            jitter: 0,
          ).build(),
        );

        final image = await loadAndAwaitImage(provider);
        expect(image.width, 1);
        expect(requests.length, 1);
      });
    });

    testWidgets('retries transient 500s and succeeds', (tester) async {
      await tester.runAsync(() async {
        _disableFakeHttpOverrides();
        final (server, requests) = await startCountingServer(failures: 2);
        addTearDown(server.close);

        final provider = NetworkImageWithRetry(
          'http://127.0.0.1:${server.port}/img.png',
          client: http.Client(),
          fetchStrategy: const FetchStrategyBuilder(
            maxTries: 5,
            initialPause: Duration.zero,
            jitter: 0,
          ).build(),
        );

        final image = await loadAndAwaitImage(provider);
        expect(image.width, 1);
        // 2 failed attempts + 1 success
        expect(requests.length, 3);
      });
    });

    testWidgets('throws NetworkImageRetryException after exhausting retries',
        (tester) async {
      await tester.runAsync(() async {
        _disableFakeHttpOverrides();
        final (server, requests) = await startCountingServer(failures: 99);
        addTearDown(server.close);

        final provider = NetworkImageWithRetry(
          'http://127.0.0.1:${server.port}/img.png',
          client: http.Client(),
          fetchStrategy: const FetchStrategyBuilder(
            maxTries: 3,
            initialPause: Duration.zero,
            jitter: 0,
          ).build(),
        );

        await expectLater(
          loadAndAwaitImage(provider),
          throwsA(isA<NetworkImageRetryException>()
              .having((e) => e.attempts, 'attempts', 3)),
        );
        expect(requests.length, 3);
      });
    });

    testWidgets('does not retry non-transient status codes', (tester) async {
      await tester.runAsync(() async {
        _disableFakeHttpOverrides();
        final (server, requests) =
            await startCountingServer(failures: 99, status: 404);
        addTearDown(server.close);

        final provider = NetworkImageWithRetry(
          'http://127.0.0.1:${server.port}/img.png',
          client: http.Client(),
          fetchStrategy: const FetchStrategyBuilder(
            maxTries: 5,
            initialPause: Duration.zero,
            jitter: 0,
          ).build(),
        );

        await expectLater(
          loadAndAwaitImage(provider),
          throwsA(isA<NetworkImageRetryException>()
              .having((e) => e.lastStatusCode, 'lastStatusCode', 404)),
        );
        // 404 is not transient: exactly one attempt, no retries.
        expect(requests.length, 1);
      });
    });
  });
}
