import 'dart:typed_data';

import 'container_data.dart';
import 'errors.dart';
import 'jpeg_codec.dart';
import 'models.dart';
import 'png_codec.dart';
import 'xmp_codec.dart';

/// Reads, writes, transplants, and verifies TC260 AIGC image metadata.
final class AigcImageMetadataCodec {
  const AigcImageMetadataCodec({this.limits = const AigcMetadataLimits()});

  /// Limits applied to every operation.
  final AigcMetadataLimits limits;

  /// Detects PNG or JPEG from the encoded signature.
  AigcImageFormat detectFormat(Uint8List bytes) => _guard(() {
        _validateLimits();
        _checkImageSize(bytes);
        return _detectFormat(bytes);
      });

  /// Reads and validates one TC260 AIGC declaration.
  AigcImageInfo read(
    Uint8List bytes, {
    AigcContainerPolicy containerPolicy = AigcContainerPolicy.compatible,
    AigcPropagationPolicy propagationPolicy = AigcPropagationPolicy.standard,
  }) =>
      _guard(() {
        _validateLimits();
        return _readInternal(
          bytes,
          containerPolicy: containerPolicy,
          propagationPolicy: propagationPolicy,
        );
      });

  /// Embeds [metadata] into an already encoded image.
  ///
  /// The output is always re-read and verified before it is returned.
  AigcWriteResult embed({
    required Uint8List encodedBytes,
    required Tc260AigcMetadata metadata,
    AigcImageFormat? expectedFormat,
    AigcPropagationPolicy propagationPolicy = AigcPropagationPolicy.standard,
    AigcExistingXmpPolicy existingXmpPolicy = AigcExistingXmpPolicy.reject,
  }) =>
      _guard(() {
        _validateLimits();
        return _embedInternal(
          encodedBytes: encodedBytes,
          metadata: metadata,
          expectedFormat: expectedFormat,
          propagationPolicy: propagationPolicy,
          existingXmpPolicy: existingXmpPolicy,
        );
      });

  /// Moves the TC260 declaration from [sourceBytes] to [reencodedBytes].
  ///
  /// No unrelated source metadata is copied. Dimensions must remain unchanged
  /// unless [dimensionPolicy] explicitly allows a change.
  AigcWriteResult transplant({
    required Uint8List sourceBytes,
    required Uint8List reencodedBytes,
    AigcImageFormat? expectedFormat,
    AigcPropagationPolicy sourcePropagationPolicy =
        AigcPropagationPolicy.standard,
    AigcDimensionPolicy dimensionPolicy = AigcDimensionPolicy.requireUnchanged,
    AigcExistingXmpPolicy targetXmpPolicy = AigcExistingXmpPolicy.reject,
  }) =>
      _guard(() {
        _validateLimits();
        final source = _readInternal(
          sourceBytes,
          containerPolicy: AigcContainerPolicy.compatible,
          propagationPolicy: sourcePropagationPolicy,
        );
        final target = _parseContainer(reencodedBytes);
        if (source.format != target.format ||
            (expectedFormat != null &&
                (source.format != expectedFormat ||
                    target.format != expectedFormat))) {
          throw const AigcMetadataException(
            AigcMetadataErrorCode.formatMismatch,
            'Source, target, and expected image formats must match.',
          );
        }
        if (dimensionPolicy == AigcDimensionPolicy.requireUnchanged &&
            (source.width != target.width || source.height != target.height)) {
          throw const AigcMetadataException(
            AigcMetadataErrorCode.dimensionsMismatch,
            'The re-encoded image dimensions differ from the source.',
          );
        }
        return _embedParsed(
          target: target,
          metadata: source.metadata,
          propagationPolicy: sourcePropagationPolicy,
          existingXmpPolicy: targetXmpPolicy,
        );
      });

  /// Verifies canonical structure, metadata, format, and optional dimensions.
  ///
  /// This does not fully decode raster pixels. Applications should separately
  /// use their image decoder before displaying or saving untrusted output.
  AigcImageInfo verifyCanonical({
    required Uint8List bytes,
    required Tc260AigcMetadata expectedMetadata,
    AigcImageFormat? expectedFormat,
    int? expectedWidth,
    int? expectedHeight,
  }) =>
      _guard(() {
        _validateLimits();
        return _verifyCanonicalInternal(
          bytes: bytes,
          expectedMetadata: expectedMetadata,
          expectedFormat: expectedFormat,
          expectedWidth: expectedWidth,
          expectedHeight: expectedHeight,
        );
      });

  AigcWriteResult _embedInternal({
    required Uint8List encodedBytes,
    required Tc260AigcMetadata metadata,
    required AigcImageFormat? expectedFormat,
    required AigcPropagationPolicy propagationPolicy,
    required AigcExistingXmpPolicy existingXmpPolicy,
  }) {
    final target = _parseContainer(encodedBytes);
    if (expectedFormat != null && target.format != expectedFormat) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.formatMismatch,
        'The encoded image format does not match expectedFormat.',
      );
    }
    return _embedParsed(
      target: target,
      metadata: metadata,
      propagationPolicy: propagationPolicy,
      existingXmpPolicy: existingXmpPolicy,
    );
  }

  AigcWriteResult _embedParsed({
    required ContainerData target,
    required Tc260AigcMetadata metadata,
    required AigcPropagationPolicy propagationPolicy,
    required AigcExistingXmpPolicy existingXmpPolicy,
  }) {
    validateMetadata(metadata, propagationPolicy);
    final xmp = buildCanonicalXmp(metadata);
    if (xmp.length > limits.maxXmpBytes) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.xmpTooLarge,
        'The canonical XMP packet exceeds maxXmpBytes.',
      );
    }
    final output = _codecFor(
      target.format,
    ).writeCanonical(target, xmp, existingXmpPolicy);
    if (output.length > limits.maxImageBytes) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.imageTooLarge,
        'The canonical output exceeds maxImageBytes.',
      );
    }
    final verified = _verifyCanonicalInternal(
      bytes: output,
      expectedMetadata: metadata,
      expectedFormat: target.format,
      expectedWidth: target.width,
      expectedHeight: target.height,
    );
    return AigcWriteResult(bytes: output, image: verified);
  }

  AigcImageInfo _verifyCanonicalInternal({
    required Uint8List bytes,
    required Tc260AigcMetadata expectedMetadata,
    required AigcImageFormat? expectedFormat,
    required int? expectedWidth,
    required int? expectedHeight,
  }) {
    final image = _readInternal(
      bytes,
      containerPolicy: AigcContainerPolicy.canonical,
      propagationPolicy: AigcPropagationPolicy.standard,
    );
    if (expectedFormat != null && image.format != expectedFormat) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.formatMismatch,
        'The verified image format differs from the expected format.',
      );
    }
    if ((expectedWidth != null && image.width != expectedWidth) ||
        (expectedHeight != null && image.height != expectedHeight)) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.dimensionsMismatch,
        'The verified image dimensions differ from the expected dimensions.',
      );
    }
    if (image.metadata != expectedMetadata) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.verificationFailed,
        'The verified metadata differs from the expected seven fields.',
      );
    }
    return image;
  }

  AigcImageInfo _readInternal(
    Uint8List bytes, {
    required AigcContainerPolicy containerPolicy,
    required AigcPropagationPolicy propagationPolicy,
  }) {
    final container = _parseContainer(bytes);
    final payloads = <String>[
      for (final packet in container.standardXmpPackets)
        ...extractAigcPayloads(packet, limits),
      ...container.legacyAigcPayloads,
    ];
    if (payloads.isEmpty) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.metadataMissing,
        'No TC260 AIGC payload was found.',
      );
    }
    if (payloads.length != 1) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.metadataDuplicated,
        'AIGC metadata must occur exactly once in the whole image.',
      );
    }
    final isCanonical = container.standardXmpPackets.length == 1 &&
        payloads.length == 1 &&
        container.legacyAigcPayloads.isEmpty;
    if (containerPolicy == AigcContainerPolicy.canonical && !isCanonical) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.verificationFailed,
        'The image does not use one canonical standard XMP container.',
      );
    }
    final metadata = parseMetadata(payloads.single);
    validateMetadata(metadata, propagationPolicy);
    return AigcImageInfo(
      format: container.format,
      width: container.width,
      height: container.height,
      metadata: metadata,
      container: AigcContainerInfo(
        standardXmpCount: container.standardXmpPackets.length,
        aigcPayloadCount: payloads.length,
        legacyPngTextCount: container.legacyAigcPayloads.length,
        isCanonical: isCanonical,
      ),
    );
  }

  ContainerData _parseContainer(Uint8List bytes) {
    _checkImageSize(bytes);
    final format = _detectFormat(bytes);
    return _codecFor(format).parse(bytes, limits);
  }

  AigcImageFormat _detectFormat(Uint8List bytes) {
    if (bytes.length >= pngSignature.length &&
        Iterable<int>.generate(
          pngSignature.length,
        ).every((index) => bytes[index] == pngSignature[index])) {
      return AigcImageFormat.png;
    }
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return AigcImageFormat.jpeg;
    }
    throw const AigcMetadataException(
      AigcMetadataErrorCode.unsupportedFormat,
      'Only PNG and JPEG are supported.',
    );
  }

  ContainerCodec _codecFor(AigcImageFormat format) => switch (format) {
        AigcImageFormat.png => const PngContainerCodec(),
        AigcImageFormat.jpeg => const JpegContainerCodec(),
      };

  void _checkImageSize(Uint8List bytes) {
    if (bytes.length > limits.maxImageBytes) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.imageTooLarge,
        'The encoded image exceeds maxImageBytes.',
      );
    }
  }

  void _validateLimits() {
    if (limits.maxImageBytes <= 0 ||
        limits.maxXmpBytes <= 0 ||
        limits.maxPngChunkBytes <= 0 ||
        limits.maxContainerCount <= 0) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.verificationFailed,
        'All metadata limits must be greater than zero.',
      );
    }
  }

  T _guard<T>(T Function() operation) {
    try {
      return operation();
    } on AigcMetadataException {
      rethrow;
    } catch (error) {
      throw AigcMetadataException(
        AigcMetadataErrorCode.verificationFailed,
        'An unexpected metadata processing failure was contained: $error',
      );
    }
  }
}
