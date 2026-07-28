import 'dart:convert';
import 'dart:typed_data';

import 'container_data.dart';
import 'errors.dart';
import 'models.dart';
import 'xmp_codec.dart';

final class JpegContainerCodec implements ContainerCodec {
  const JpegContainerCodec();

  @override
  ContainerData parse(Uint8List bytes, AigcMetadataLimits limits) {
    if (bytes.length < 2) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.truncatedImage,
        'The JPEG SOI marker is truncated.',
      );
    }
    if (bytes[0] != 0xff || bytes[1] != 0xd8) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.invalidJpegStructure,
        'The JPEG SOI marker is invalid.',
      );
    }

    final pieces = <JpegPiece>[];
    final xmpPackets = <String>[];
    int? width;
    int? height;
    var offset = 2;
    var sawEoi = false;
    var containerCount = 0;

    while (offset < bytes.length) {
      if (++containerCount > limits.maxContainerCount) {
        throw const AigcMetadataException(
          AigcMetadataErrorCode.invalidJpegStructure,
          'The JPEG exceeds maxContainerCount.',
        );
      }
      final markerStart = offset;
      if (bytes[offset] != 0xff) {
        throw AigcMetadataException(
          AigcMetadataErrorCode.invalidJpegStructure,
          'Expected a JPEG marker.',
          offset: offset,
        );
      }
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (offset >= bytes.length) {
        throw AigcMetadataException(
          AigcMetadataErrorCode.truncatedImage,
          'A JPEG marker is truncated.',
          offset: markerStart,
        );
      }
      final marker = bytes[offset++];
      if (marker == 0x00 || marker == 0xd8) {
        throw AigcMetadataException(
          AigcMetadataErrorCode.invalidJpegStructure,
          'An invalid marker occurs outside scan data.',
          offset: markerStart,
        );
      }
      if (marker == 0xd9) {
        pieces.add(
          JpegPiece(
            marker: marker,
            payload: Uint8List(0),
            raw: Uint8List.sublistView(bytes, markerStart, offset),
          ),
        );
        if (offset != bytes.length) {
          throw AigcMetadataException(
            AigcMetadataErrorCode.invalidJpegStructure,
            'Data occurs after JPEG EOI.',
            offset: offset,
          );
        }
        sawEoi = true;
        break;
      }
      if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
        pieces.add(
          JpegPiece(
            marker: marker,
            payload: Uint8List(0),
            raw: Uint8List.sublistView(bytes, markerStart, offset),
          ),
        );
        continue;
      }
      if (offset + 2 > bytes.length) {
        throw AigcMetadataException(
          AigcMetadataErrorCode.truncatedImage,
          'A JPEG segment length is truncated.',
          offset: offset,
        );
      }
      final length = _readUint16(bytes, offset);
      final end = offset + length;
      if (length < 2 || end < offset || end > bytes.length) {
        throw AigcMetadataException(
          AigcMetadataErrorCode.invalidJpegStructure,
          'A JPEG segment length is invalid.',
          offset: markerStart,
        );
      }
      final payload = Uint8List.sublistView(bytes, offset + 2, end);
      pieces.add(
        JpegPiece(
          marker: marker,
          payload: payload,
          raw: Uint8List.sublistView(bytes, markerStart, end),
        ),
      );
      if (_isSof(marker)) {
        if (payload.length < 5) {
          throw AigcMetadataException(
            AigcMetadataErrorCode.invalidJpegStructure,
            'A JPEG SOF segment is truncated.',
            offset: markerStart,
          );
        }
        if (width != null || height != null) {
          throw AigcMetadataException(
            AigcMetadataErrorCode.invalidJpegStructure,
            'Multiple JPEG SOF segments are not accepted.',
            offset: markerStart,
          );
        }
        height = _readUint16(payload, 1);
        width = _readUint16(payload, 3);
      }
      if (marker == 0xe1 && _startsWithHeader(payload)) {
        final packetBytes = payload.sublist(ascii.encode(xmpHeader).length);
        if (packetBytes.length > limits.maxXmpBytes) {
          throw const AigcMetadataException(
            AigcMetadataErrorCode.xmpTooLarge,
            'A JPEG XMP packet exceeds maxXmpBytes.',
          );
        }
        try {
          xmpPackets.add(utf8.decode(packetBytes));
        } catch (error) {
          throw AigcMetadataException(
            AigcMetadataErrorCode.unsafeXmp,
            'A JPEG XMP packet is not valid UTF-8: $error',
          );
        }
      }
      offset = end;
      if (marker == 0xda) {
        final entropyStart = offset;
        offset = _scanToNextMarker(bytes, offset);
        if (offset > entropyStart) {
          pieces.add(
            JpegPiece(
              marker: -1,
              payload: Uint8List(0),
              raw: Uint8List.sublistView(bytes, entropyStart, offset),
            ),
          );
        }
      }
    }
    if (!sawEoi) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.truncatedImage,
        'JPEG EOI is missing.',
      );
    }
    if (width == null || height == null || width <= 0 || height <= 0) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.invalidJpegStructure,
        'JPEG dimensions are missing or invalid.',
      );
    }
    return ContainerData(
      format: AigcImageFormat.jpeg,
      width: width,
      height: height,
      standardXmpPackets: xmpPackets,
      legacyAigcPayloads: const <String>[],
      parsed: pieces,
    );
  }

  @override
  Uint8List writeCanonical(
    ContainerData target,
    List<int> xmpBytes,
    AigcExistingXmpPolicy existingXmpPolicy,
  ) {
    if (target.standardXmpPackets.isNotEmpty &&
        existingXmpPolicy == AigcExistingXmpPolicy.reject) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.existingXmpConflict,
        'The target JPEG already contains standard XMP.',
      );
    }
    final header = ascii.encode(xmpHeader);
    final payloadLength = header.length + xmpBytes.length;
    if (payloadLength + 2 > 0xffff) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.xmpTooLarge,
        'The canonical XMP packet does not fit in a JPEG APP1 segment.',
      );
    }
    final output = BytesBuilder(copy: false)
      ..add(const <int>[0xff, 0xd8])
      ..add(<int>[
        0xff,
        0xe1,
        (payloadLength + 2) >> 8,
        (payloadLength + 2) & 0xff,
        ...header,
        ...xmpBytes,
      ]);
    for (final piece in target.parsed as List<JpegPiece>) {
      if (piece.marker == 0xe1 && _startsWithHeader(piece.payload)) continue;
      output.add(piece.raw);
    }
    return output.toBytes();
  }
}

final class JpegPiece {
  const JpegPiece({
    required this.marker,
    required this.payload,
    required this.raw,
  });

  final int marker;
  final Uint8List payload;
  final Uint8List raw;
}

int _scanToNextMarker(Uint8List bytes, int offset) {
  while (offset < bytes.length) {
    if (bytes[offset] != 0xff) {
      offset++;
      continue;
    }
    final markerStart = offset;
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) {
      throw AigcMetadataException(
        AigcMetadataErrorCode.truncatedImage,
        'JPEG scan data ends in an incomplete marker.',
        offset: markerStart,
      );
    }
    final marker = bytes[offset];
    if (marker == 0x00 || (marker >= 0xd0 && marker <= 0xd7)) {
      offset++;
      continue;
    }
    return markerStart;
  }
  throw const AigcMetadataException(
    AigcMetadataErrorCode.truncatedImage,
    'JPEG scan data has no terminating marker.',
  );
}

bool _startsWithHeader(List<int> payload) {
  final header = ascii.encode(xmpHeader);
  return payload.length >= header.length &&
      Iterable<int>.generate(
        header.length,
      ).every((index) => payload[index] == header[index]);
}

int _readUint16(List<int> bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

bool _isSof(int marker) => const <int>{
      0xc0,
      0xc1,
      0xc2,
      0xc3,
      0xc5,
      0xc6,
      0xc7,
      0xc9,
      0xca,
      0xcb,
      0xcd,
      0xce,
      0xcf,
    }.contains(marker);
