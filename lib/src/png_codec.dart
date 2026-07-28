import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'container_data.dart';
import 'errors.dart';
import 'models.dart';
import 'xmp_codec.dart';

const pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

final class PngContainerCodec implements ContainerCodec {
  const PngContainerCodec();

  @override
  ContainerData parse(Uint8List bytes, AigcMetadataLimits limits) {
    if (bytes.length < pngSignature.length) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.truncatedImage,
        'The PNG signature is truncated.',
      );
    }
    if (!_matches(bytes, 0, pngSignature)) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.invalidPngStructure,
        'The PNG signature is invalid.',
      );
    }
    final chunks = <PngChunk>[];
    final xmpPackets = <String>[];
    final legacyPayloads = <String>[];
    var offset = pngSignature.length;
    var sawIend = false;
    while (offset < bytes.length) {
      if (chunks.length >= limits.maxContainerCount) {
        throw const AigcMetadataException(
          AigcMetadataErrorCode.invalidPngStructure,
          'The PNG exceeds maxContainerCount.',
        );
      }
      if (offset + 12 > bytes.length) {
        throw AigcMetadataException(
          AigcMetadataErrorCode.truncatedImage,
          'A PNG chunk header is truncated.',
          offset: offset,
        );
      }
      final length = readUint32(bytes, offset);
      if (length > limits.maxPngChunkBytes) {
        throw AigcMetadataException(
          AigcMetadataErrorCode.invalidPngStructure,
          'A PNG chunk exceeds maxPngChunkBytes.',
          offset: offset,
        );
      }
      final end = offset + 12 + length;
      if (end < offset || end > bytes.length) {
        throw AigcMetadataException(
          AigcMetadataErrorCode.truncatedImage,
          'A PNG chunk extends beyond the input.',
          offset: offset,
        );
      }
      final typeBytes = Uint8List.sublistView(bytes, offset + 4, offset + 8);
      final type = _decodeChunkType(typeBytes, offset);
      final data = Uint8List.sublistView(
        bytes,
        offset + 8,
        offset + 8 + length,
      );
      final expectedCrc = readUint32(bytes, offset + 8 + length);
      if (crc32(<int>[...typeBytes, ...data]) != expectedCrc) {
        throw AigcMetadataException(
          AigcMetadataErrorCode.invalidPngCrc,
          'The $type chunk CRC does not match.',
          offset: offset,
        );
      }
      final chunk = PngChunk(
        type: type,
        data: data,
        raw: Uint8List.sublistView(bytes, offset, end),
      );
      chunks.add(chunk);

      if (type == 'IEND') {
        if (length != 0 || end != bytes.length) {
          throw AigcMetadataException(
            AigcMetadataErrorCode.invalidPngStructure,
            'IEND must be empty and final.',
            offset: offset,
          );
        }
        sawIend = true;
      } else if (sawIend) {
        throw AigcMetadataException(
          AigcMetadataErrorCode.invalidPngStructure,
          'A PNG chunk occurs after IEND.',
          offset: offset,
        );
      }

      final text = _readText(chunk, limits);
      if (text != null) {
        if (text.$1 == xmpKeyword) xmpPackets.add(text.$2);
        if (text.$1 == 'AIGC') legacyPayloads.add(text.$2);
      }
      offset = end;
    }
    if (!sawIend) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.invalidPngStructure,
        'PNG IEND is missing.',
      );
    }
    if (chunks.isEmpty ||
        chunks.first.type != 'IHDR' ||
        chunks.where((chunk) => chunk.type == 'IHDR').length != 1 ||
        chunks.first.data.length != 13) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.invalidPngStructure,
        'PNG must start with exactly one 13-byte IHDR.',
      );
    }
    final width = readUint32(chunks.first.data, 0);
    final height = readUint32(chunks.first.data, 4);
    if (width <= 0 || height <= 0) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.invalidPngStructure,
        'PNG dimensions must be positive.',
      );
    }
    return ContainerData(
      format: AigcImageFormat.png,
      width: width,
      height: height,
      standardXmpPackets: xmpPackets,
      legacyAigcPayloads: legacyPayloads,
      parsed: chunks,
    );
  }

  @override
  Uint8List writeCanonical(
    ContainerData target,
    List<int> xmpBytes,
    AigcExistingXmpPolicy existingXmpPolicy,
  ) {
    final chunks = target.parsed as List<PngChunk>;
    if (target.standardXmpPackets.isNotEmpty &&
        existingXmpPolicy == AigcExistingXmpPolicy.reject) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.existingXmpConflict,
        'The target PNG already contains standard XMP.',
      );
    }
    final output = BytesBuilder(copy: false)..add(pngSignature);
    var inserted = false;
    for (final chunk in chunks) {
      final keyword = _textKeyword(chunk);
      if (keyword == xmpKeyword || keyword == 'AIGC') continue;
      output.add(chunk.raw);
      if (chunk.type == 'IHDR' && !inserted) {
        output.add(
          _buildChunk('iTXt', <int>[
            ...ascii.encode(xmpKeyword),
            0,
            0,
            0,
            0,
            0,
            ...xmpBytes,
          ]),
        );
        inserted = true;
      }
    }
    if (!inserted) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.canonicalWriteFailed,
        'PNG IHDR was not available during canonical writing.',
      );
    }
    return output.toBytes();
  }
}

final class PngChunk {
  const PngChunk({required this.type, required this.data, required this.raw});

  final String type;
  final Uint8List data;
  final Uint8List raw;
}

(String, String)? _readText(PngChunk chunk, AigcMetadataLimits limits) {
  if (!const {'tEXt', 'zTXt', 'iTXt'}.contains(chunk.type)) return null;
  final zero = chunk.data.indexOf(0);
  if (zero <= 0 || zero > 79) {
    throw const AigcMetadataException(
      AigcMetadataErrorCode.invalidPngStructure,
      'A PNG text keyword is invalid.',
    );
  }
  final keyword = latin1.decode(chunk.data.sublist(0, zero));
  if (keyword != xmpKeyword && keyword != 'AIGC') return (keyword, '');

  List<int> text;
  if (chunk.type == 'tEXt') {
    text = chunk.data.sublist(zero + 1);
  } else if (chunk.type == 'zTXt') {
    if (zero + 2 > chunk.data.length || chunk.data[zero + 1] != 0) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.invalidPngStructure,
        'A zTXt compression method is invalid.',
      );
    }
    text = _decompressCapped(chunk.data.sublist(zero + 2), limits);
  } else {
    if (zero + 3 > chunk.data.length) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.invalidPngStructure,
        'An iTXt header is truncated.',
      );
    }
    final compressed = chunk.data[zero + 1];
    if ((compressed != 0 && compressed != 1) || chunk.data[zero + 2] != 0) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.invalidPngStructure,
        'The iTXt compression fields are invalid.',
      );
    }
    var cursor = zero + 3;
    for (var field = 0; field < 2; field++) {
      final next = chunk.data.indexOf(0, cursor);
      if (next < 0) {
        throw const AigcMetadataException(
          AigcMetadataErrorCode.invalidPngStructure,
          'The iTXt language or translated keyword is unterminated.',
        );
      }
      cursor = next + 1;
    }
    text = compressed == 1
        ? _decompressCapped(chunk.data.sublist(cursor), limits)
        : chunk.data.sublist(cursor);
  }
  if (text.length > limits.maxXmpBytes) {
    throw const AigcMetadataException(
      AigcMetadataErrorCode.xmpTooLarge,
      'A PNG metadata text value exceeds maxXmpBytes.',
    );
  }
  try {
    return (keyword, utf8.decode(text));
  } catch (error) {
    throw AigcMetadataException(
      AigcMetadataErrorCode.unsafeXmp,
      'A PNG metadata text value is not valid UTF-8: $error',
    );
  }
}

String? _textKeyword(PngChunk chunk) {
  if (!const {'tEXt', 'zTXt', 'iTXt'}.contains(chunk.type)) return null;
  final zero = chunk.data.indexOf(0);
  if (zero <= 0) return null;
  return latin1.decode(chunk.data.sublist(0, zero));
}

List<int> _decompressCapped(List<int> compressed, AigcMetadataLimits limits) {
  final output = BytesBuilder(copy: false);
  try {
    final conversion = zlib.decoder.startChunkedConversion(
      _CappedSink(output, limits.maxXmpBytes),
    );
    conversion
      ..add(compressed)
      ..close();
    return output.toBytes();
  } on AigcMetadataException {
    rethrow;
  } catch (error) {
    throw AigcMetadataException(
      AigcMetadataErrorCode.invalidPngStructure,
      'Compressed PNG metadata is invalid: $error',
    );
  }
}

final class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.output, this.limit);

  final BytesBuilder output;
  final int limit;
  var _length = 0;

  @override
  void add(List<int> data) {
    _length += data.length;
    if (_length > limit) {
      throw const AigcMetadataException(
        AigcMetadataErrorCode.xmpTooLarge,
        'Decompressed PNG metadata exceeds maxXmpBytes.',
      );
    }
    output.add(data);
  }

  @override
  void close() {}
}

String _decodeChunkType(List<int> bytes, int offset) {
  if (bytes.any(
    (byte) =>
        !((byte >= 0x41 && byte <= 0x5a) || (byte >= 0x61 && byte <= 0x7a)),
  )) {
    throw AigcMetadataException(
      AigcMetadataErrorCode.invalidPngStructure,
      'A PNG chunk type contains a non-letter.',
      offset: offset,
    );
  }
  return ascii.decode(bytes);
}

Uint8List _buildChunk(String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  return Uint8List.fromList(<int>[
    ...uint32(data.length),
    ...typeBytes,
    ...data,
    ...uint32(crc32(<int>[...typeBytes, ...data])),
  ]);
}

bool _matches(List<int> bytes, int offset, List<int> expected) =>
    offset + expected.length <= bytes.length &&
    Iterable<int>.generate(
      expected.length,
    ).every((index) => bytes[offset + index] == expected[index]);

int readUint32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

List<int> uint32(int value) => <int>[
      value >>> 24,
      value >>> 16 & 0xff,
      value >>> 8 & 0xff,
      value & 0xff,
    ];

int crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
