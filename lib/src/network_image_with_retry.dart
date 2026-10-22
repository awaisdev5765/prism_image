import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'fetch_failure.dart';
import 'fetch_strategy.dart';

/// An [ImageProvider] that fetches the image at [url] over the network and
/// retries transient failures according to a [fetchStrategy].
///
/// Drop-in replacement for `NetworkImageWithRetry` from the discontinued
/// `flutter_image` package: same constructor shape, same default strategy
/// behavior (exponential backoff with jitter, transient status codes only).
///
/// ```dart
/// const Image(image: NetworkImageWithRetry('https://example.com/photo.png'))
/// ```
class NetworkImageWithRetry extends ImageProvider<NetworkImageWithRetry> {
  /// Creates a retrying network image provider.
  const NetworkImageWithRetry(
    this.url, {
    this.scale = 1.0,
    this.fetchStrategy = defaultFetchStrategy,
    this.headers,
    this.client,
  });

  /// The default strategy: 3 attempts, exponential backoff (starting at
  /// 100 ms, ×1.5 each retry, ±25% jitter), transient status codes only.
  ///
  /// A static method tear-off so it can be used as a const default value.
  static Future<FetchInstructions?> defaultFetchStrategy(
    Uri uri,
    FetchFailure? failure,
  ) {
    return const FetchStrategyBuilder().build()(uri, failure);
  }

  /// The URL from which the image will be fetched.
  final String url;

  /// The scale to place in the [ImageInfo] of the decoded image.
  final double scale;

  /// The strategy used to fetch the [url] and retry on failure.
  ///
  /// Called at least once; first call receives a null [FetchFailure]
  /// (first attempt). Returning null gives up; otherwise the value says
  /// how long to wait before the next attempt.
  final FetchStrategy fetchStrategy;

  /// HTTP headers applied to the request (e.g. `Authorization`).
  final Map<String, String>? headers;

  /// Optional injectable HTTP client. Defaults to a shared [http.Client].
  ///
  /// Provided so retry behavior can be tested without real network access.
  final http.Client? client;

  @override
  Future<NetworkImageWithRetry> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<NetworkImageWithRetry>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    NetworkImageWithRetry key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadWithRetry(key, decode),
      scale: key.scale,
      informationCollector: () sync* {
        yield ErrorDescription('Image provider: $this');
        yield ErrorDescription('Image key: $key');
      },
    );
  }

  Future<ui.Codec> _loadWithRetry(
    NetworkImageWithRetry key,
    ImageDecoderCallback decode,
  ) async {
    final client = this.client ?? http.Client();
    final uri = Uri.parse(key.url);
    FetchFailure? failure;

    while (true) {
      try {
        final request = http.Request('GET', uri)..followRedirects = true;
        key.headers?.forEach((name, value) {
          request.headers[name] = value;
        });
        final response =
            await http.Response.fromStream(await client.send(request));
        if (response.statusCode != 200) {
          throw _HttpException(response.statusCode);
        }
        final buffer =
            await ui.ImmutableBuffer.fromUint8List(response.bodyBytes);
        return await decode(buffer);
      } catch (error) {
        final statusCode = error is _HttpException ? error.statusCode : null;
        failure = FetchFailure(
          uri: uri,
          httpClientException: error,
          attempt: (failure?.attempt ?? 0) + 1,
          timestamp: DateTime.now(),
          httpStatusCode: statusCode,
        );
        final instructions = await fetchStrategy(uri, failure);
        if (instructions == null) {
          throw NetworkImageRetryException(
            uri: uri,
            attempts: failure.attempt,
            lastException: error,
            lastStatusCode: statusCode,
          );
        }
        await Future<void>.delayed(instructions.waitFor);
      }
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is! NetworkImageWithRetry) return false;
    return other.url == url &&
        other.scale == scale &&
        other.fetchStrategy == fetchStrategy;
  }

  @override
  int get hashCode => Object.hash(url, scale, fetchStrategy);

  @override
  String toString() =>
      'NetworkImageWithRetry("$url", scale: $scale)';
}

/// Wraps non-200 responses so the strategy can inspect the status code.
class _HttpException implements Exception {
  const _HttpException(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'HTTP $statusCode';
}

/// Thrown when all retry attempts are exhausted.
class NetworkImageRetryException implements Exception {
  NetworkImageRetryException({
    required this.uri,
    required this.attempts,
    required this.lastException,
    this.lastStatusCode,
  });

  final Uri uri;
  final int attempts;
  final Object lastException;
  final int? lastStatusCode;

  @override
  String toString() => 'NetworkImageRetryException: failed to load $uri '
      'after $attempts attempts. Last error: $lastException'
      '${lastStatusCode != null ? ' (HTTP $lastStatusCode)' : ''}';
}
