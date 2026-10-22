# Changelog

## 0.1.0

- Initial release: `NetworkImageWithRetry` image provider with configurable
  retry strategies — exponential backoff with jitter, transient status-code
  predicate, injectable HTTP client. Drop-in replacement for the
  discontinued `flutter_image`.
