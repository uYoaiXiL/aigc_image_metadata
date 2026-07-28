# AIGC Image Metadata Package Requirements

## 1. Scope

`aigc_image_metadata` is a pure Dart package for reading, embedding,
transplanting, and verifying the seven-field TC260 AIGC metadata used by
GB 45438-2025 images. Version 0.1.0 supports PNG and JPEG on Dart VM and
Flutter Android/iOS.

The package does not render visible watermarks, re-encode pixels, save files to
the gallery, copy arbitrary EXIF/ICC/IPTC/GPS metadata, or provide legal advice.

## 2. User stories

1. As an app developer, I want to transplant the original AIGC declaration
   after pixel re-encoding so the final image remains traceable.
2. As a backend developer, I want to embed a validated seven-field declaration
   into a newly generated PNG or JPEG.
3. As an auditor, I want to inspect container counts, dimensions, and metadata
   without using a pixel decoder.
4. As a security-conscious integrator, I want malformed files to fail with
   stable error codes rather than parser implementation exceptions.

## 3. Acceptance criteria

### R1. Public API and portability

- The package shall export only the public types listed in the approved plan
  from `package:aigc_image_metadata/aigc_image_metadata.dart`.
- While running on Dart VM or Flutter Android/iOS, the package shall parse and
  write PNG and JPEG without depending on Flutter.
- The package shall not claim Web support in version 0.1.0.

### R2. Metadata validation

- When metadata is read or written, the package shall require exactly the seven
  case-sensitive TC260 fields, all represented as strings.
- When standard validation is requested, the package shall require `Label` to
  equal `"1"` and validate required identifiers against the agreed ASCII range.
- When producer-as-propagator validation is requested, the package shall also
  require the producer/propagator and produce/propagate identifiers to match.

### R3. Container parsing

- When a PNG is read, the package shall validate its signature, IHDR, chunk
  bounds, CRC values, IEND, text-container structure, and configured limits.
- When a JPEG is read, the package shall validate SOI, segment bounds, scan
  structure, EOI, dimensions, and configured limits.
- When compatible mode is used, the package shall accept TC260 element, RDF
  attribute, or legacy PNG `AIGC` representations only if exactly one AIGC
  payload exists in the whole image.
- When canonical mode is used, the package shall require exactly one standard
  XMP container, one AIGC payload, and no legacy PNG AIGC text container.

### R4. Canonical writing

- When embedding into PNG, the package shall write one uncompressed XMP iTXt
  immediately after IHDR and preserve all target non-XMP chunks byte-for-byte.
- When embedding into JPEG, the package shall write one Adobe XMP APP1 directly
  after SOI and preserve all target non-XMP segments and scan bytes byte-for-byte.
- When a target contains standard XMP and the policy is `reject`, the package
  shall fail without changing the input.
- When the policy is `replace`, the package shall remove all target standard XMP
  containers before writing one canonical packet.
- After every embed or transplant operation, the package shall re-read and
  verify the canonical output before returning it.

### R5. Transplant safety

- When transplanting, the package shall validate the source using the selected
  propagation policy and require source, target, and optional expected formats
  to agree.
- Unless dimension changes are explicitly allowed, the package shall reject a
  target whose dimensions differ from the source.
- The package shall not copy source EXIF, ICC, IPTC, GPS, or unrelated XMP into
  the target image.

### R6. Errors and limits

- For every public operation, malformed or hostile input shall either succeed
  or throw `AigcMetadataException`; raw XML, JSON, zlib, `RangeError`, and
  `FormatException` errors shall not cross the public boundary.
- Before allocating or decompressing untrusted content, the package shall apply
  configured image, XMP, chunk, and container limits as early as practical.
- The package documentation shall state that exception messages are diagnostic
  and must not be shown directly to end users.

### R7. App integration

- When the Flutter app processes a backend image, it shall read the source with
  `requireProducerAsPropagator`, render its visible watermark, transplant the
  original TC260 metadata, and pixel-decode the final bytes before saving.
- User-facing failures shall continue to use localized generic messages and
  shall not expose package diagnostics.

### R8. Documentation and verification

- The package shall include synchronized English and Chinese READMEs, Dartdoc,
  changelog, security policy, contributing guide, MIT license, and a pure Dart
  example.
- Package CI-ready checks shall include formatting, analysis, tests, coverage,
  dependency downgrade, and publish dry-run commands.
- Formal publication shall not occur without separate user authorization.

## 4. Non-goals

- Generic XMP editing or lossless preservation of arbitrary metadata.
- Visible watermark generation, image decoding/encoding, gallery integration,
  Web support, or regulatory certification.
