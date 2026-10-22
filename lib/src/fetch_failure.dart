/// Describes a failed fetch attempt, passed to a [FetchStrategy] so it can
/// decide whether and when to retry.
///
/// Mirrors the shape of `FetchFailure` from the discontinued
/// `flutter_image` package so existing strategies port over unchanged.
library;

import 'package:flutter/foundation.dart' show immutable;

/// The outcome of a failed fetch attempt.
@immutable
class FetchFailure {
  /// Creates a failure description.
  const FetchFailure({
    required this.uri,
    required this.httpClientException,
    required this.attempt,
    required this.timestamp,
    this.httpStatusCode,
  });

  /// The requested URL.
  final Uri uri;

  /// The exception thrown by the HTTP client, if any.
  final Object? httpClientException;

  /// Attempt number, starting at 1 for the first failure.
  final int attempt;

  /// When the failure occurred.
  final DateTime timestamp;

  /// The HTTP status code of the failed response, when available.
  ///
  /// Null when the request failed before a response was received
  /// (connection error, timeout, etc.).
  final int? httpStatusCode;

  @override
  String toString() => 'FetchFailure(attempt: $attempt, status: '
      '${httpStatusCode ?? 'none'}, uri: $uri)';
}
