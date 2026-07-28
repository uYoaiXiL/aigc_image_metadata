# aigc_image_metadata

[简体中文](README.zh-CN.md)

Read, embed, transplant, and verify the seven-field TC260 AIGC declaration in
PNG and JPEG files. The package is intended for GB 45438-2025 engineering flows
where pixel re-encoding would otherwise discard container-level XMP.

> This package provides technical metadata utilities, not legal or regulatory
> advice. Confirm the requirements that apply to your product and jurisdiction.

## Supported formats

- PNG standard XMP in `iTXt`, plus compatible reads of legacy AIGC text chunks
- JPEG Adobe XMP in APP1
- TC260 element and RDF attribute representations
- Dart VM and Flutter Android/iOS
- Web is not supported in 0.1.0 because bounded zlib decoding uses `dart:io`

The package only manages the TC260 `AIGC` object and its seven string fields.
It does not render visible watermarks, encode pixels, save to a gallery, or copy
EXIF, ICC, IPTC, GPS, or arbitrary third-party XMP.

## Installation

```yaml
dependencies:
  aigc_image_metadata: ^0.1.0
```

For local development next to a Flutter application:

```yaml
dependencies:
  aigc_image_metadata:
    path: ../aigc_image_metadata
```

## Quick start: preserve metadata after re-encoding

```dart
import 'dart:typed_data';
import 'package:aigc_image_metadata/aigc_image_metadata.dart';

Uint8List preserveAigc(Uint8List original, Uint8List reencoded) {
  const codec = AigcImageMetadataCodec();
  final result = codec.transplant(
    sourceBytes: original,
    reencodedBytes: reencoded,
    sourcePropagationPolicy:
        AigcPropagationPolicy.requireProducerAsPropagator,
  );
  return result.bytes;
}
```

The default requires source and target dimensions to match. For an intentional
crop or resize, pass `dimensionPolicy: AigcDimensionPolicy.allowChange`.

## Initial embedding

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

final result = const AigcImageMetadataCodec().embed(
  encodedBytes: encodedImage,
  metadata: metadata,
  expectedFormat: AigcImageFormat.png,
  propagationPolicy: AigcPropagationPolicy.requireProducerAsPropagator,
);
```

`embed` rejects existing standard XMP by default. Use
`existingXmpPolicy: AigcExistingXmpPolicy.replace` only when deleting all target
standard XMP is intentional.

## Reading and auditing

```dart
final info = const AigcImageMetadataCodec().read(bytes);
print(info.metadata.toJson());
print(info.container.standardXmpCount);
print(info.container.isCanonical);
```

`compatible` reads element, RDF attribute, and legacy PNG forms but still
requires exactly one AIGC payload in the complete file. `canonical` requires one
standard XMP packet, one payload, and no legacy PNG AIGC text container.

## Validation policies

- `AigcPropagationPolicy.standard` validates all seven fields, `Label`, required
  values, and the TC260 character range.
- `requireProducerAsPropagator` additionally requires the producer/propagator
  and both identifiers to match, as expected for an initial backend output.
- `requireUnchanged` protects transplant operations from accidental resizing.
- `AigcExistingXmpPolicy.reject` prevents silent deletion of target XMP;
  `replace` explicitly authorizes canonical replacement.

## Error handling

Every public failure is an `AigcMetadataException`. Branch on its stable `code`.
The `message` and `offset` are developer diagnostics and **must not be displayed
directly to end users**.

```dart
try {
  codec.read(untrustedBytes);
} on AigcMetadataException catch (error) {
  switch (error.code) {
    case AigcMetadataErrorCode.metadataMissing:
      showLocalizedMessage('The image has no verifiable AI declaration.');
    default:
      showLocalizedMessage('The image could not be verified.');
  }
}
```

## Canonical output

- PNG: one uncompressed UTF-8 XMP `iTXt` named `XML:com.adobe.xmp`, directly
  after IHDR.
- JPEG: one Adobe XMP APP1 directly after SOI.

Writing preserves the target file's non-XMP chunks, segments, and compressed
scan/image data byte-for-byte. `embed` and `transplant` always re-read and
structurally verify their output. `verifyCanonical` does not fully decode raster
pixels; use your image decoder as an additional displayability check.

## Metadata preservation policy

Transplant copies only the validated seven-field logical AIGC object from the
source. It deliberately does not copy unrelated metadata. Target non-XMP data is
retained, while target standard XMP is either rejected or explicitly replaced.

Incorrect usage:

```dart
final reencoded = encodePixels(original); // XMP was probably lost.
save(reencoded); // Incorrect: transplant was never called.
```

## Security limits

`AigcMetadataLimits` caps image bytes, XMP bytes, PNG chunk bytes, and container
count. Compressed PNG text is decoded through a capped sink. DTD and entity
declarations, malformed UTF-8, duplicate JSON keys, malformed lengths, and CRC
errors are rejected.

## Interoperability

Canonical JSON uses the exact `AIGC` root and seven case-sensitive field names.
Canonical XMP uses `http://www.tc260.org.cn/ns/AIGC/1.0/`. Projects should keep
sanitized backend-produced PNG/JPEG fixtures and verify them with both the Dart
package and the backend Java validator.

## Contributing, security, and license

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Licensed
under the [MIT License](LICENSE).
