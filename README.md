# Prism Image

![pub version](https://img.shields.io/pub/v/prism_image) ![pub points](https://img.shields.io/pub/points/prism_image?label=points&color=green) ![pub likes](https://img.shields.io/pub/likes/prism_image?label=likes&color=red)

Resilient network image loading for Flutter — the maintained replacement
for the discontinued [`flutter_image`](https://pub.dev/packages/flutter_image)
package.

`NetworkImageWithRetry` is a drop-in `ImageProvider` that retries
transient network failures with exponential backoff and jitter — the same
behavior and API shape as the original, freshly implemented with zero
external dependencies beyond `package:http`.

## Usage

```dart
import 'package:prism_image/prism_image.dart';

const Image(
  image: NetworkImageWithRetry('https://example.com/photo.png'),
)
```

### Custom retry strategy

```dart
final provider = NetworkImageWithRetry(
  'https://example.com/photo.png',
  fetchStrategy: const FetchStrategyBuilder(
    maxTries: 5,                       // attempts before giving up
    initialPause: Duration(seconds: 1),// first retry delay
    backOffFactor: 2.0,                // exponential multiplier
    jitter: 0.25,                      // ±25% randomness
    transientHttpStatusCodePredicate: (code) => code >= 500,
  ).build(),
  headers: {'Authorization': token},
);
```

### Which status codes retry by default

408, 500, 502, 503, 504, 598, 599 — override with
`transientHttpStatusCodePredicate` to customize.

## Migrating from flutter_image

Same API shape — rename the import and you're done:

| flutter_image | prism_image |
|---|---|
| `NetworkImageWithRetry(url)` | `NetworkImageWithRetry(url)` |
| `FetchStrategyBuilder(maxTries: ...)` | `FetchStrategyBuilder(maxTries: ...)` |
| `FetchFailure`, `FetchInstructions` | `FetchFailure`, `FetchInstructions` |
| `defaultTransientHttpStatusCodePredicate` | `defaultTransientHttpStatusCodePredicate` |

Part of the [Prism](https://pub.dev/packages/prism_markdown) family — a
cohesive suite of well-tested, pure-Flutter packages.

## License

MIT
