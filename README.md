# aigc_image_metadata

[简体中文](README.zh-CN.md)

A pure Dart package for reading, embedding, transplanting, and verifying
GB 45438-2025 / TC260 AIGC metadata in PNG and JPEG images.

Use it when an image is re-encoded—for example, after adding a visible
watermark—and the original AIGC metadata needs to be restored to the resulting
file.

## Features

- Reads TC260 AIGC metadata from PNG and JPEG images.
- Embeds the standard seven-field AIGC declaration.
- Transplants metadata after image re-encoding.
- Verifies canonical container structure, metadata, format, and dimensions.
- Reports failures through stable typed error codes.
- Applies configurable limits to untrusted image and XMP data.

## Installation

```yaml
dependencies:
  aigc_image_metadata: ^0.1.0
```

```dart
import 'package:aigc_image_metadata/aigc_image_metadata.dart';
```

## Preserve metadata after re-encoding

```dart
const codec = AigcImageMetadataCodec();

final result = codec.transplant(
  sourceBytes: originalBytes,
  reencodedBytes: reencodedBytes,
  expectedFormat: AigcImageFormat.jpeg,
);

final outputBytes = result.bytes;
```

By default, the source and re-encoded image must use the same format and
dimensions. For an intentional resize or crop:

```dart
final result = codec.transplant(
  sourceBytes: originalBytes,
  reencodedBytes: resizedBytes,
  dimensionPolicy: AigcDimensionPolicy.allowChange,
);
```

## Embed metadata for the first time

```dart
const metadata = Tc260AigcMetadata(
  label: '1',
  contentProducer: 'ExampleService',
  produceId: 'IMG-123-1',
  reservedCode1: '',
  contentPropagator: 'ExampleService',
  propagateId: 'IMG-123-1',
  reservedCode2: '',
);

final result = codec.embed(
  encodedBytes: encodedBytes,
  metadata: metadata,
  expectedFormat: AigcImageFormat.png,
  propagationPolicy:
      AigcPropagationPolicy.requireProducerAsPropagator,
);
```

## Read and verify

```dart
final info = codec.read(imageBytes);

print(info.format);
print(info.width);
print(info.height);
print(info.metadata.toJson());
print(info.container.isCanonical);
```

To require canonical output:

```dart
final verified = codec.verifyCanonical(
  bytes: imageBytes,
  expectedMetadata: expectedMetadata,
  expectedFormat: AigcImageFormat.png,
);
```

## Policies

- `AigcContainerPolicy.compatible` accepts supported compatible TC260
  representations while requiring exactly one AIGC payload.
- `AigcContainerPolicy.canonical` requires one standard XMP container and no
  legacy PNG AIGC text container.
- `AigcPropagationPolicy.requireProducerAsPropagator` requires the producer and
  propagator fields, and their IDs, to match.
- `AigcExistingXmpPolicy.reject` prevents accidental removal of existing target
  XMP. Use `replace` only when replacement is intentional.

## Error handling

All public operations throw `AigcMetadataException` on failure. Use its `code`
for application logic and map it to your own user-facing message.

```dart
try {
  codec.read(imageBytes);
} on AigcMetadataException catch (error) {
  switch (error.code) {
    case AigcMetadataErrorCode.metadataMissing:
      // Handle a missing AIGC declaration.
      break;
    default:
      // Handle an invalid or unsupported image.
      break;
  }
}
```

`message` and `offset` are intended for developer diagnostics and should not be
displayed directly to end users.

## Scope

Version 0.1.0 supports PNG and JPEG on Dart VM and Flutter Android/iOS. Web is
not supported.

The package handles TC260 AIGC metadata only. It does not render visible
watermarks, re-encode pixels, save images, or copy EXIF, ICC, IPTC, GPS, C2PA,
or arbitrary third-party XMP metadata.

This package provides engineering utilities and does not constitute legal or
regulatory advice.

## License

[MIT](LICENSE)
