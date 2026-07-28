/// Stable categories for failures reported by this package.
enum AigcMetadataErrorCode {
  unsupportedFormat,
  imageTooLarge,
  truncatedImage,
  invalidPngStructure,
  invalidPngCrc,
  invalidJpegStructure,
  unsafeXmp,
  xmpTooLarge,
  metadataMissing,
  metadataDuplicated,
  invalidMetadataJson,
  invalidMetadataFields,
  invalidMetadataValue,
  propagationMismatch,
  formatMismatch,
  dimensionsMismatch,
  existingXmpConflict,
  canonicalWriteFailed,
  verificationFailed,
}

/// A typed failure from an AIGC metadata operation.
///
/// [message] is intended for developer diagnostics. Do not expose it directly
/// to end users; map [code] to an application-owned localized message instead.
final class AigcMetadataException implements Exception {
  const AigcMetadataException(this.code, this.message, {this.offset});

  /// Machine-readable failure category.
  final AigcMetadataErrorCode code;

  /// Developer-facing diagnostic text.
  final String message;

  /// Byte offset associated with a container error, when available.
  final int? offset;

  @override
  String toString() {
    final location = offset == null ? '' : ' at byte $offset';
    return 'AigcMetadataException(${code.name}$location): $message';
  }
}
