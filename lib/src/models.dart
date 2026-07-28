import 'dart:typed_data';

/// Supported encoded image containers.
enum AigcImageFormat {
  png,
  jpeg;

  /// Conventional file extension without a leading dot.
  String get extension => switch (this) {
        AigcImageFormat.png => 'png',
        AigcImageFormat.jpeg => 'jpg',
      };

  /// Internet media type for this format.
  String get mimeType => switch (this) {
        AigcImageFormat.png => 'image/png',
        AigcImageFormat.jpeg => 'image/jpeg',
      };
}

/// The seven logical fields carried by `TC260:AIGC`.
final class Tc260AigcMetadata {
  const Tc260AigcMetadata({
    required this.label,
    required this.contentProducer,
    required this.produceId,
    required this.reservedCode1,
    required this.contentPropagator,
    required this.propagateId,
    required this.reservedCode2,
  });

  final String label;
  final String contentProducer;
  final String produceId;
  final String reservedCode1;
  final String contentPropagator;
  final String propagateId;
  final String reservedCode2;

  /// Returns the standard root object with deterministic field order.
  Map<String, Object> toJson() => <String, Object>{
        'AIGC': <String, Object>{
          'Label': label,
          'ContentProducer': contentProducer,
          'ProduceID': produceId,
          'ReservedCode1': reservedCode1,
          'ContentPropagator': contentPropagator,
          'PropagateID': propagateId,
          'ReservedCode2': reservedCode2,
        },
      };

  @override
  bool operator ==(Object other) =>
      other is Tc260AigcMetadata &&
      label == other.label &&
      contentProducer == other.contentProducer &&
      produceId == other.produceId &&
      reservedCode1 == other.reservedCode1 &&
      contentPropagator == other.contentPropagator &&
      propagateId == other.propagateId &&
      reservedCode2 == other.reservedCode2;

  @override
  int get hashCode => Object.hash(
        label,
        contentProducer,
        produceId,
        reservedCode1,
        contentPropagator,
        propagateId,
        reservedCode2,
      );
}

/// Diagnostics about metadata containers found in an image.
final class AigcContainerInfo {
  const AigcContainerInfo({
    required this.standardXmpCount,
    required this.aigcPayloadCount,
    required this.legacyPngTextCount,
    required this.isCanonical,
  });

  final int standardXmpCount;
  final int aigcPayloadCount;
  final int legacyPngTextCount;
  final bool isCanonical;
}

/// Parsed image dimensions, metadata, and container diagnostics.
final class AigcImageInfo {
  const AigcImageInfo({
    required this.format,
    required this.width,
    required this.height,
    required this.metadata,
    required this.container,
  });

  final AigcImageFormat format;
  final int width;
  final int height;
  final Tc260AigcMetadata metadata;
  final AigcContainerInfo container;
}

/// Canonically encoded bytes and their verified interpretation.
final class AigcWriteResult {
  const AigcWriteResult({required this.bytes, required this.image});

  final Uint8List bytes;
  final AigcImageInfo image;
}

enum AigcContainerPolicy { compatible, canonical }

enum AigcPropagationPolicy { standard, requireProducerAsPropagator }

enum AigcDimensionPolicy { requireUnchanged, allowChange }

enum AigcExistingXmpPolicy { reject, replace }

/// Resource limits applied while parsing untrusted encoded images.
final class AigcMetadataLimits {
  const AigcMetadataLimits({
    this.maxImageBytes = 128 * 1024 * 1024,
    this.maxXmpBytes = 1024 * 1024,
    this.maxPngChunkBytes = 64 * 1024 * 1024,
    this.maxContainerCount = 10000,
  })  : assert(maxImageBytes > 0),
        assert(maxXmpBytes > 0),
        assert(maxPngChunkBytes > 0),
        assert(maxContainerCount > 0);

  final int maxImageBytes;
  final int maxXmpBytes;
  final int maxPngChunkBytes;
  final int maxContainerCount;
}
