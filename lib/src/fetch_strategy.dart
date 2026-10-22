/// Retry-strategy types for `prism_image`.
///
/// Same shapes as the discontinued `flutter_image` package, so existing
/// strategies port over unchanged.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'fetch_failure.dart';

/// Decides whether and when to retry a failed fetch.
///
/// Called at least once per fetch (first call receives a null [FetchFailure],
/// which indicates the first attempt). Returning instructions means
/// "retry after [FetchInstructions/waitFor]"; returning null means "give up
/// and surface the error".
typedef FetchStrategy = Future<FetchInstructions?> Function(
  Uri uri,
  FetchFailure? failure,
);

/// The verdict of a [FetchStrategy]: wait [waitFor], then retry.
@immutable
class FetchInstructions {
  /// Creates instructions to retry after waiting [waitFor].
  const FetchInstructions({required this.waitFor});

  /// How long to wait before the next attempt.
  final Duration waitFor;

  @override
  String toString() => 'FetchInstructions(waitFor: $waitFor)';
}

/// Predicate over HTTP status codes that returns true for codes worth
/// retrying. The default matches the classic transient set.
typedef TransientHttpStatusCodePredicate = bool Function(int statusCode);

/// The status codes the original `flutter_image` treated as transient.
const Set<int> kDefaultTransientHttpStatusCodes = <int>{
  408, // request timeout
  500, // internal server error
  502, // bad gateway
  503, // service unavailable
  504, // gateway timeout
  598, // (informal) network read timeout
  599, // (informal) network connect timeout
};

/// Default predicate: the classic transient status-code set.
bool defaultTransientHttpStatusCodePredicate(int statusCode) =>
    kDefaultTransientHttpStatusCodes.contains(statusCode);

/// Builds common retry strategies: exponential backoff with optional
/// jitter, bounded by attempt count, with a pluggable predicate for which
/// HTTP status codes count as transient.
class FetchStrategyBuilder {
  /// Creates a strategy builder.
  const FetchStrategyBuilder({
    this.maxTries = 3,
    this.initialPause = const Duration(milliseconds: 100),
    this.backOffFactor = 1.5,
    this.maxPause = const Duration(minutes: 1),
    this.jitter = 0.25,
    this.transientHttpStatusCodePredicate =
        defaultTransientHttpStatusCodePredicate,
  });

  /// Maximum number of attempts before giving up.
  final int maxTries;

  /// Pause before the first retry.
  final Duration initialPause;

  /// Multiplier applied to the pause after each failed attempt.
  final double backOffFactor;

  /// Upper bound for any single pause.
  final Duration maxPause;

  /// Relative random jitter applied to each pause (0 disables).
  final double jitter;

  /// Decides which HTTP status codes are retryable.
  final TransientHttpStatusCodePredicate transientHttpStatusCodePredicate;

  /// Builds the [FetchStrategy].
  FetchStrategy build() {
    return (uri, failure) async {
      final attempt = failure?.attempt ?? 0;
      if (attempt >= maxTries) return null;

      final statusCode = failure?.httpStatusCode;
      if (statusCode != null &&
          !transientHttpStatusCodePredicate(statusCode)) {
        return null;
      }

      var pauseMs = initialPause.inMilliseconds.toDouble();
      for (var i = 1; i < attempt; i++) {
        pauseMs *= backOffFactor;
      }
      if (jitter > 0) {
        pauseMs += pauseMs * jitter * (2.0 * pseudoRandom() - 1.0);
      }
      final pause = Duration(
        milliseconds: pauseMs
            .clamp(0, maxPause.inMilliseconds.toDouble())
            .round(),
      );
      return FetchInstructions(waitFor: pause);
    };
  }
}

/// Deterministic lightweight jitter source: keeps test runs reproducible
/// without pulling dart:math Random seeding on every call.
double pseudoRandom() {
  _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
  return _seed / 0x7fffffff;
}

int _seed = 20260101;
