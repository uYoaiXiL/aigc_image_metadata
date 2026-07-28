import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aigc_image_metadata/aigc_image_metadata.dart';
import 'package:image/image.dart' as image;
import 'package:test/test.dart';

const metadata = Tc260AigcMetadata(
  label: '1',
  contentProducer: 'Amelink',
  produceId: 'IMG-123-1',
  reservedCode1: '',
  contentPropagator: 'Amelink',
  propagateId: 'IMG-123-1',
  reservedCode2: '',
);

void main() {
  group('public values', () {
    test('format properties and metadata equality are stable', () {
      expect(AigcImageFormat.png.extension, 'png');
      expect(AigcImageFormat.jpeg.extension, 'jpg');
      expect(AigcImageFormat.png.mimeType, 'image/png');
      expect(AigcImageFormat.jpeg.mimeType, 'image/jpeg');
      expect(metadata, equals(metadata));
      expect(metadata.hashCode, equals(metadata.hashCode));
      expect(metadata.toJson(), <String, Object>{
        'AIGC': <String, Object>{
          'Label': '1',
          'ContentProducer': 'Amelink',
          'ProduceID': 'IMG-123-1',
          'ReservedCode1': '',
          'ContentPropagator': 'Amelink',
          'PropagateID': 'IMG-123-1',
          'ReservedCode2': '',
        },
      });
    });

    test('typed exception includes code and optional offset', () {
      const error = AigcMetadataException(
        AigcMetadataErrorCode.invalidPngCrc,
        'bad crc',
        offset: 8,
      );
      expect(error.toString(), contains('invalidPngCrc'));
      expect(error.toString(), contains('byte 8'));
    });
  });

  for (final format in AigcImageFormat.values) {
    group(format.name, () {
      final codec = const AigcImageMetadataCodec();
      late Uint8List plain;

      setUp(() {
        plain = _encode(format, width: 24, height: 32);
      });

      test('detects, embeds, reads, verifies, and decodes', () {
        final inputBefore = Uint8List.fromList(plain);
        final result = codec.embed(
          encodedBytes: plain,
          metadata: metadata,
          expectedFormat: format,
          propagationPolicy: AigcPropagationPolicy.requireProducerAsPropagator,
        );

        expect(codec.detectFormat(result.bytes), format);
        expect(plain, inputBefore, reason: 'the input must not be mutated');
        expect(result.image.metadata, metadata);
        expect(result.image.width, 24);
        expect(result.image.height, 32);
        expect(result.image.container.standardXmpCount, 1);
        expect(result.image.container.aigcPayloadCount, 1);
        expect(result.image.container.legacyPngTextCount, 0);
        expect(result.image.container.isCanonical, isTrue);
        expect(image.decodeImage(result.bytes), isNotNull);

        final verified = codec.verifyCanonical(
          bytes: result.bytes,
          expectedMetadata: metadata,
          expectedFormat: format,
          expectedWidth: 24,
          expectedHeight: 32,
        );
        expect(verified.metadata, metadata);
      });

      test('transplants without changing compressed image data', () {
        final source = codec
            .embed(
              encodedBytes: plain,
              metadata: metadata,
              expectedFormat: format,
            )
            .bytes;
        final reencoded = _encode(format, width: 24, height: 32, seed: 2);
        final preservedBefore = format == AigcImageFormat.png
            ? _pngChunkData(reencoded, 'IDAT')
            : _jpegScanAndFollowing(reencoded);

        final result = codec.transplant(
          sourceBytes: source,
          reencodedBytes: reencoded,
          expectedFormat: format,
          sourcePropagationPolicy:
              AigcPropagationPolicy.requireProducerAsPropagator,
        );

        final preservedAfter = format == AigcImageFormat.png
            ? _pngChunkData(result.bytes, 'IDAT')
            : _jpegScanAndFollowing(result.bytes);
        expect(preservedAfter, preservedBefore);
        expect(result.image.metadata, metadata);
        expect(image.decodeImage(result.bytes), isNotNull);
      });

      test('rejects existing XMP unless replacement is explicit', () {
        final canonical = codec
            .embed(
              encodedBytes: plain,
              metadata: metadata,
            )
            .bytes;
        expect(
          () => codec.embed(encodedBytes: canonical, metadata: metadata),
          throwsAigc(AigcMetadataErrorCode.existingXmpConflict),
        );

        final replaced = codec.embed(
          encodedBytes: canonical,
          metadata: metadata,
          existingXmpPolicy: AigcExistingXmpPolicy.replace,
        );
        expect(replaced.bytes, canonical, reason: 'canonical write is stable');
      });

      test('enforces expected format and dimensions', () {
        final source = codec
            .embed(
              encodedBytes: plain,
              metadata: metadata,
            )
            .bytes;
        final otherFormat = format == AigcImageFormat.png
            ? AigcImageFormat.jpeg
            : AigcImageFormat.png;
        expect(
          () => codec.embed(
            encodedBytes: plain,
            metadata: metadata,
            expectedFormat: otherFormat,
          ),
          throwsAigc(AigcMetadataErrorCode.formatMismatch),
        );
        expect(
          () => codec.transplant(
            sourceBytes: source,
            reencodedBytes: _encode(format, width: 12, height: 16),
          ),
          throwsAigc(AigcMetadataErrorCode.dimensionsMismatch),
        );
        final resized = codec.transplant(
          sourceBytes: source,
          reencodedBytes: _encode(format, width: 12, height: 16),
          dimensionPolicy: AigcDimensionPolicy.allowChange,
        );
        expect((resized.image.width, resized.image.height), (12, 16));
      });
    });
  }

  group('metadata policies and strict parsing', () {
    const codec = AigcImageMetadataCodec();

    test('requires the initial propagation relationship when requested', () {
      const mismatch = Tc260AigcMetadata(
        label: '1',
        contentProducer: 'Producer',
        produceId: 'P-1',
        reservedCode1: '',
        contentPropagator: 'Propagator',
        propagateId: 'P-2',
        reservedCode2: '',
      );
      final encoded = _encode(AigcImageFormat.png, width: 8, height: 8);
      expect(
        () => codec.embed(encodedBytes: encoded, metadata: mismatch),
        returnsNormally,
      );
      expect(
        () => codec.embed(
          encodedBytes: encoded,
          metadata: mismatch,
          propagationPolicy: AigcPropagationPolicy.requireProducerAsPropagator,
        ),
        throwsAigc(AigcMetadataErrorCode.propagationMismatch),
      );
    });

    test('rejects invalid label, empty required value, and bad characters', () {
      final encoded = _encode(AigcImageFormat.png, width: 8, height: 8);
      for (final invalid in <Tc260AigcMetadata>[
        _copyMetadata(label: '2'),
        _copyMetadata(produceId: ''),
        _copyMetadata(contentProducer: 'not allowed'),
      ]) {
        expect(
          () => codec.embed(encodedBytes: encoded, metadata: invalid),
          throwsAigc(AigcMetadataErrorCode.invalidMetadataValue),
        );
      }
    });

    test('accepts compatible RDF attribute representation', () {
      final bytes = _pngWithPayload(_validPayload(), attribute: true);
      expect(codec.read(bytes).metadata, metadata);
    });

    test('rejects duplicate payloads and missing metadata', () {
      expect(
        () => codec.read(_pngWithPayload(_validPayload(), copies: 2)),
        throwsAigc(AigcMetadataErrorCode.metadataDuplicated),
      );
      expect(
        () => codec.read(_encode(AigcImageFormat.png, width: 8, height: 8)),
        throwsAigc(AigcMetadataErrorCode.metadataMissing),
      );
    });

    test('rejects duplicate JSON keys, fields, values, and unsafe XML', () {
      final duplicateKey = _validPayload().replaceFirst(
        '"Label":"1",',
        '"Label":"1","Label":"1",',
      );
      final missingField = _validPayload().replaceFirst(
        ',"ReservedCode2":""',
        '',
      );
      expect(
        () => codec.read(_pngWithPayload(duplicateKey)),
        throwsAigc(AigcMetadataErrorCode.invalidMetadataJson),
      );
      expect(
        () => codec.read(_pngWithPayload(missingField)),
        throwsAigc(AigcMetadataErrorCode.invalidMetadataFields),
      );
      expect(
        () => codec.read(
          _pngWithPayload(
            _validPayload(),
            xmlPrefix: '<!DOCTYPE x [<!ENTITY e "boom">]>',
          ),
        ),
        throwsAigc(AigcMetadataErrorCode.unsafeXmp),
      );
      expect(
        () => codec.read(
          _pngWithPayload(_validPayload(), xmlPrefix: '<broken>'),
        ),
        throwsAigc(AigcMetadataErrorCode.unsafeXmp),
      );
    });

    test('strict JSON handles valid and invalid escape boundaries', () {
      final escaped = _validPayload()
          .replaceFirst('IMG-123-1', r'IMG-123\u002d1')
          .replaceFirst('IMG-123-1', r'IMG-123\/1');
      expect(
          codec.read(_pngWithPayload(escaped)).metadata.produceId, 'IMG-123-1');
      for (final invalid in <String>[
        _validPayload().replaceFirst('IMG-123-1', r'IMG-123\q1'),
        '${_validPayload()} trailing',
        _validPayload().replaceFirst('IMG-123-1', 'IMG-123\n1'),
        _validPayload().replaceFirst('IMG-123-1', r'IMG-123\uZZZZ'),
      ]) {
        expect(
          () => codec.read(_pngWithPayload(invalid)),
          throwsAigc(AigcMetadataErrorCode.invalidMetadataJson),
        );
      }
    });

    test('reads compressed PNG XMP and caps decompression', () {
      final ztxt = _pngWithPayload(_validPayload(), textKind: _TextKind.ztxt);
      final compressedItxt = _pngWithPayload(
        _validPayload(),
        textKind: _TextKind.compressedItxt,
      );
      expect(codec.read(ztxt).metadata, metadata);
      expect(codec.read(compressedItxt).metadata, metadata);

      final limited = AigcImageMetadataCodec(
        limits: const AigcMetadataLimits(maxXmpBytes: 32),
      );
      expect(
        () => limited.read(compressedItxt),
        throwsAigc(AigcMetadataErrorCode.xmpTooLarge),
      );
      expect(
        () => codec.read(
          _pngWithPayload(_validPayload(), textKind: _TextKind.invalidZlib),
        ),
        throwsAigc(AigcMetadataErrorCode.invalidPngStructure),
      );
      expect(
        () => codec.read(
          _pngWithPayload(_validPayload(), textKind: _TextKind.invalidUtf8),
        ),
        throwsAigc(AigcMetadataErrorCode.unsafeXmp),
      );
    });
  });

  group('container and resource errors', () {
    test('returns stable errors for unsupported, oversized, and truncated data',
        () {
      const codec = AigcImageMetadataCodec();
      expect(
        () => codec.detectFormat(Uint8List.fromList(<int>[1, 2, 3])),
        throwsAigc(AigcMetadataErrorCode.unsupportedFormat),
      );
      final limited = AigcImageMetadataCodec(
        limits: const AigcMetadataLimits(maxImageBytes: 2),
      );
      expect(
        () => limited.detectFormat(Uint8List(3)),
        throwsAigc(AigcMetadataErrorCode.imageTooLarge),
      );
      expect(
        () => codec.read(Uint8List.fromList(<int>[0xff, 0xd8, 0xff])),
        throwsAigc(AigcMetadataErrorCode.truncatedImage),
      );
    });

    test('rejects PNG CRC corruption and structure errors', () {
      const codec = AigcImageMetadataCodec();
      final valid = codec
          .embed(
            encodedBytes: _encode(AigcImageFormat.png, width: 8, height: 8),
            metadata: metadata,
          )
          .bytes;
      final corrupted = Uint8List.fromList(valid)..[29] ^= 1;
      expect(
        () => codec.read(corrupted),
        throwsAigc(AigcMetadataErrorCode.invalidPngCrc),
      );
      final noIend = Uint8List.fromList(valid.sublist(0, valid.length - 12));
      expect(
        () => codec.read(noIend),
        throwsAigc(AigcMetadataErrorCode.invalidPngStructure),
      );
    });

    test('rejects malformed JPEG and oversized XMP limits', () {
      const codec = AigcImageMetadataCodec();
      final jpeg = _encode(AigcImageFormat.jpeg, width: 8, height: 8);
      final malformed = Uint8List.fromList(jpeg)..[2] = 0;
      expect(
        () => codec.read(malformed),
        throwsAigc(AigcMetadataErrorCode.invalidJpegStructure),
      );
      final tinyXmp = AigcImageMetadataCodec(
        limits: const AigcMetadataLimits(maxXmpBytes: 16),
      );
      expect(
        () => tinyXmp.embed(encodedBytes: jpeg, metadata: metadata),
        throwsAigc(AigcMetadataErrorCode.xmpTooLarge),
      );
    });

    test('rejects JPEG marker, length, EOI, SOF, and XMP boundaries', () {
      const codec = AigcImageMetadataCodec();
      final cases = <Uint8List>[
        Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0x00]),
        Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xd9, 0x00]),
        Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xe0]),
        Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xe0, 0x00, 0x01]),
        Uint8List.fromList(<int>[
          0xff,
          0xd8,
          0xff,
          0xc0,
          0x00,
          0x05,
          8,
          0,
          0,
          0xff,
          0xd9,
        ]),
      ];
      for (final bytes in cases) {
        expect(() => codec.read(bytes), throwsA(isA<AigcMetadataException>()));
      }

      final jpeg = _encode(AigcImageFormat.jpeg, width: 8, height: 8);
      final invalidXmp = _insertJpegApp1(jpeg, <int>[0xff]);
      expect(
        () => codec.read(invalidXmp),
        throwsAigc(AigcMetadataErrorCode.unsafeXmp),
      );
      final limitedContainers = AigcImageMetadataCodec(
        limits: const AigcMetadataLimits(maxContainerCount: 1),
      );
      expect(
        () => limitedContainers.read(jpeg),
        throwsAigc(AigcMetadataErrorCode.invalidJpegStructure),
      );
    });

    test('rejects PNG length, chunk, keyword, and limit boundaries', () {
      const codec = AigcImageMetadataCodec();
      final png = _encode(AigcImageFormat.png, width: 8, height: 8);
      expect(
        () => codec.read(Uint8List.fromList(png.sublist(0, 9))),
        throwsAigc(AigcMetadataErrorCode.truncatedImage),
      );
      final oversizedLength = Uint8List.fromList(png)
        ..setRange(8, 12, <int>[0x7f, 0xff, 0xff, 0xff]);
      expect(
        () => codec.read(oversizedLength),
        throwsAigc(AigcMetadataErrorCode.invalidPngStructure),
      );
      final invalidType = Uint8List.fromList(png)..[12] = 0;
      expect(
        () => codec.read(invalidType),
        throwsAigc(AigcMetadataErrorCode.invalidPngStructure),
      );
      final limitedContainers = AigcImageMetadataCodec(
        limits: const AigcMetadataLimits(maxContainerCount: 1),
      );
      expect(
        () => limitedContainers.read(png),
        throwsAigc(AigcMetadataErrorCode.invalidPngStructure),
      );
      final limitedChunk = AigcImageMetadataCodec(
        limits: const AigcMetadataLimits(maxPngChunkBytes: 12),
      );
      expect(
        () => limitedChunk.read(png),
        throwsAigc(AigcMetadataErrorCode.invalidPngStructure),
      );
      expect(
        () => codec.read(_pngWithRawText(<int>[0])),
        throwsAigc(AigcMetadataErrorCode.invalidPngStructure),
      );
    });

    test('verification reports metadata and dimension mismatches', () {
      const codec = AigcImageMetadataCodec();
      final canonical = codec
          .embed(
            encodedBytes: _encode(AigcImageFormat.png, width: 8, height: 8),
            metadata: metadata,
          )
          .bytes;
      expect(
        () => codec.verifyCanonical(
          bytes: canonical,
          expectedMetadata: _copyMetadata(produceId: 'OTHER'),
        ),
        throwsAigc(AigcMetadataErrorCode.verificationFailed),
      );
      expect(
        () => codec.verifyCanonical(
          bytes: canonical,
          expectedMetadata: metadata,
          expectedWidth: 99,
        ),
        throwsAigc(AigcMetadataErrorCode.dimensionsMismatch),
      );
    });
  });

  test('10,000 deterministic mutations never leak implementation exceptions',
      () {
    const codec = AigcImageMetadataCodec(
      limits: AigcMetadataLimits(maxImageBytes: 4096),
    );
    var state = 0x12345678;
    for (var seed = 0; seed < 10000; seed++) {
      state = (1103515245 * state + 12345) & 0x7fffffff;
      final length = state % 96;
      final bytes = Uint8List(length);
      for (var index = 0; index < bytes.length; index++) {
        state = (1103515245 * state + 12345) & 0x7fffffff;
        bytes[index] = state & 0xff;
      }
      try {
        codec.read(bytes);
      } catch (error) {
        expect(error, isA<AigcMetadataException>(), reason: 'seed $seed');
      }
    }
  });
}

Matcher throwsAigc(AigcMetadataErrorCode code) => throwsA(
      isA<AigcMetadataException>().having((error) => error.code, 'code', code),
    );

Uint8List _encode(
  AigcImageFormat format, {
  required int width,
  required int height,
  int seed = 1,
}) {
  final value = image.Image(width: width, height: height);
  image.fill(
    value,
    color: image.ColorRgb8(seed * 17 % 255, seed * 31 % 255, seed * 47 % 255),
  );
  return Uint8List.fromList(
    format == AigcImageFormat.png
        ? image.encodePng(value)
        : image.encodeJpg(value, quality: 90),
  );
}

Tc260AigcMetadata _copyMetadata({
  String? label,
  String? contentProducer,
  String? produceId,
}) =>
    Tc260AigcMetadata(
      label: label ?? metadata.label,
      contentProducer: contentProducer ?? metadata.contentProducer,
      produceId: produceId ?? metadata.produceId,
      reservedCode1: metadata.reservedCode1,
      contentPropagator: metadata.contentPropagator,
      propagateId: metadata.propagateId,
      reservedCode2: metadata.reservedCode2,
    );

String _validPayload() => jsonEncode(metadata.toJson());

Uint8List _pngWithPayload(
  String payload, {
  int copies = 1,
  bool attribute = false,
  String xmlPrefix = '',
  _TextKind textKind = _TextKind.itxt,
}) {
  final png = _encode(AigcImageFormat.png, width: 8, height: 8);
  final ihdrEnd = 8 + 12 + _uint32At(png, 8);
  final escaped = attribute
      ? const HtmlEscape(HtmlEscapeMode.attribute).convert(payload)
      : const HtmlEscape(HtmlEscapeMode.element).convert(payload);
  final node = attribute
      ? '<rdf:Description xmlns:TC260="http://www.tc260.org.cn/ns/AIGC/1.0/" TC260:AIGC="$escaped"/>'
      : '<rdf:Description xmlns:TC260="http://www.tc260.org.cn/ns/AIGC/1.0/"><TC260:AIGC>$escaped</TC260:AIGC></rdf:Description>';
  final xmp = utf8.encode(
    '$xmlPrefix<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">$node</rdf:RDF></x:xmpmeta>',
  );
  final keyword = ascii.encode('XML:com.adobe.xmp');
  final (chunkType, chunkData) = switch (textKind) {
    _TextKind.itxt => (
        'iTXt',
        <int>[...keyword, 0, 0, 0, 0, 0, ...xmp],
      ),
    _TextKind.compressedItxt => (
        'iTXt',
        <int>[...keyword, 0, 1, 0, 0, 0, ...zlib.encode(xmp)],
      ),
    _TextKind.ztxt => (
        'zTXt',
        <int>[...keyword, 0, 0, ...zlib.encode(xmp)],
      ),
    _TextKind.invalidZlib => (
        'zTXt',
        <int>[...keyword, 0, 0, 1, 2, 3],
      ),
    _TextKind.invalidUtf8 => (
        'tEXt',
        <int>[...keyword, 0, 0xff],
      ),
  };
  final chunk = _pngChunk(chunkType, chunkData);
  final output = BytesBuilder()..add(png.sublist(0, ihdrEnd));
  for (var index = 0; index < copies; index++) {
    output.add(chunk);
  }
  output.add(png.sublist(ihdrEnd));
  return output.toBytes();
}

enum _TextKind { itxt, compressedItxt, ztxt, invalidZlib, invalidUtf8 }

Uint8List _pngWithRawText(List<int> textData) {
  final png = _encode(AigcImageFormat.png, width: 8, height: 8);
  final ihdrEnd = 8 + 12 + _uint32At(png, 8);
  return Uint8List.fromList(<int>[
    ...png.sublist(0, ihdrEnd),
    ..._pngChunk('tEXt', textData),
    ...png.sublist(ihdrEnd),
  ]);
}

Uint8List _insertJpegApp1(Uint8List jpeg, List<int> xmp) {
  final payload = <int>[
    ...ascii.encode('http://ns.adobe.com/xap/1.0/\x00'),
    ...xmp,
  ];
  final length = payload.length + 2;
  return Uint8List.fromList(<int>[
    0xff,
    0xd8,
    0xff,
    0xe1,
    length >> 8,
    length & 0xff,
    ...payload,
    ...jpeg.sublist(2),
  ]);
}

List<int> _pngChunkData(Uint8List bytes, String wanted) {
  final output = <int>[];
  var offset = 8;
  while (offset + 12 <= bytes.length) {
    final length = _uint32At(bytes, offset);
    final type = ascii.decode(bytes.sublist(offset + 4, offset + 8));
    if (type == wanted) {
      output.addAll(bytes.sublist(offset + 8, offset + 8 + length));
    }
    offset += length + 12;
    if (type == 'IEND') break;
  }
  return output;
}

List<int> _jpegScanAndFollowing(Uint8List bytes) {
  for (var index = 2; index + 1 < bytes.length; index++) {
    if (bytes[index] == 0xff && bytes[index + 1] == 0xda) {
      return bytes.sublist(index);
    }
  }
  return const <int>[];
}

Uint8List _pngChunk(String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  return Uint8List.fromList(<int>[
    ..._uint32(data.length),
    ...typeBytes,
    ...data,
    ..._uint32(_crc32(<int>[...typeBytes, ...data])),
  ]);
}

int _uint32At(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

List<int> _uint32(int value) => <int>[
      value >>> 24,
      value >>> 16 & 0xff,
      value >>> 8 & 0xff,
      value & 0xff,
    ];

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
