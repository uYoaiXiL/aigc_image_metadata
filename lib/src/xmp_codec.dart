import 'dart:convert';

import 'package:xml/xml.dart';

import 'errors.dart';
import 'models.dart';

const xmpKeyword = 'XML:com.adobe.xmp';
const xmpHeader = 'http://ns.adobe.com/xap/1.0/\x00';
const aigcNamespace = 'http://www.tc260.org.cn/ns/AIGC/1.0/';

const _fieldNames = <String>{
  'Label',
  'ContentProducer',
  'ProduceID',
  'ReservedCode1',
  'ContentPropagator',
  'PropagateID',
  'ReservedCode2',
};

List<String> extractAigcPayloads(String xmp, AigcMetadataLimits limits) {
  final encodedLength = utf8.encode(xmp).length;
  if (encodedLength > limits.maxXmpBytes) {
    throw const AigcMetadataException(
      AigcMetadataErrorCode.xmpTooLarge,
      'The XMP packet exceeds maxXmpBytes.',
    );
  }
  if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(xmp)) {
    throw const AigcMetadataException(
      AigcMetadataErrorCode.unsafeXmp,
      'DTD and entity declarations are not accepted in XMP.',
    );
  }

  try {
    final document = XmlDocument.parse(xmp);
    final payloads = <String>[];
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'AIGC' &&
          element.name.namespaceUri == aigcNamespace) {
        payloads.add(element.innerText);
      }
      for (final attribute in element.attributes) {
        if (attribute.name.local == 'AIGC' &&
            attribute.name.namespaceUri == aigcNamespace) {
          payloads.add(attribute.value);
        }
      }
    }
    return payloads;
  } on AigcMetadataException {
    rethrow;
  } catch (error) {
    throw AigcMetadataException(
      AigcMetadataErrorCode.unsafeXmp,
      'The XMP packet is not safe, well-formed XML: $error',
    );
  }
}

Tc260AigcMetadata parseMetadata(String source) {
  final Map<String, Object?> root;
  try {
    root = StrictJsonObjectParser(source).parse();
  } on AigcMetadataException {
    rethrow;
  } catch (error) {
    throw AigcMetadataException(
      AigcMetadataErrorCode.invalidMetadataJson,
      'The AIGC payload is not valid strict JSON: $error',
    );
  }

  if (root.length != 1 || !root.containsKey('AIGC')) {
    throw const AigcMetadataException(
      AigcMetadataErrorCode.invalidMetadataFields,
      'The JSON root must contain only AIGC.',
    );
  }
  final dataValue = root['AIGC'];
  if (dataValue is! Map<String, Object?>) {
    throw const AigcMetadataException(
      AigcMetadataErrorCode.invalidMetadataFields,
      'AIGC must be an object.',
    );
  }
  final data = dataValue;
  if (data.length != _fieldNames.length ||
      data.keys.toSet().difference(_fieldNames).isNotEmpty ||
      _fieldNames.difference(data.keys.toSet()).isNotEmpty ||
      data.values.any((value) => value is! String)) {
    throw const AigcMetadataException(
      AigcMetadataErrorCode.invalidMetadataFields,
      'AIGC must contain exactly seven case-sensitive string fields.',
    );
  }
  return Tc260AigcMetadata(
    label: data['Label']! as String,
    contentProducer: data['ContentProducer']! as String,
    produceId: data['ProduceID']! as String,
    reservedCode1: data['ReservedCode1']! as String,
    contentPropagator: data['ContentPropagator']! as String,
    propagateId: data['PropagateID']! as String,
    reservedCode2: data['ReservedCode2']! as String,
  );
}

void validateMetadata(
  Tc260AigcMetadata metadata,
  AigcPropagationPolicy propagationPolicy,
) {
  if (metadata.label != '1') {
    throw const AigcMetadataException(
      AigcMetadataErrorCode.invalidMetadataValue,
      'Label must be the string "1".',
    );
  }
  final requiredValues = <String>[
    metadata.contentProducer,
    metadata.produceId,
    metadata.contentPropagator,
    metadata.propagateId,
  ];
  if (requiredValues.any((value) => value.isEmpty)) {
    throw const AigcMetadataException(
      AigcMetadataErrorCode.invalidMetadataValue,
      'Producer, propagator, and their identifiers must not be empty.',
    );
  }
  final values = <String>[
    ...requiredValues,
    metadata.reservedCode1,
    metadata.reservedCode2,
  ];
  if (values.any((value) => value.codeUnits.any((unit) => !_isAllowed(unit)))) {
    throw const AigcMetadataException(
      AigcMetadataErrorCode.invalidMetadataValue,
      'A metadata value contains a character outside the TC260 ASCII range.',
    );
  }
  if (propagationPolicy == AigcPropagationPolicy.requireProducerAsPropagator &&
      (metadata.contentProducer != metadata.contentPropagator ||
          metadata.produceId != metadata.propagateId)) {
    throw const AigcMetadataException(
      AigcMetadataErrorCode.propagationMismatch,
      'The source producer and propagator fields do not match.',
    );
  }
}

List<int> buildCanonicalXmp(Tc260AigcMetadata metadata) {
  final json = jsonEncode(metadata.toJson());
  final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(json);
  return utf8.encode(
    '<?xpacket begin="\ufeff" id="W5M0MpCehiHzreSzNTczkc9d"?>'
    '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
    '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
    '<rdf:Description xmlns:TC260="$aigcNamespace">'
    '<TC260:AIGC>$escaped</TC260:AIGC>'
    '</rdf:Description></rdf:RDF></x:xmpmeta>'
    '<?xpacket end="w"?>',
  );
}

bool _isAllowed(int unit) =>
    unit == 0x21 ||
    (unit >= 0x23 && unit <= 0x5b) ||
    (unit >= 0x5d && unit <= 0x7e);

final class StrictJsonObjectParser {
  StrictJsonObjectParser(this.source);

  final String source;
  var _index = 0;

  Map<String, Object?> parse() {
    final value = _object();
    _space();
    if (_index != source.length) _fail('Trailing JSON data.');
    return value;
  }

  Map<String, Object?> _object() {
    _expect('{');
    final result = <String, Object?>{};
    _space();
    if (_take('}')) return result;
    while (true) {
      final key = _string();
      if (result.containsKey(key)) _fail('Duplicate JSON key: $key.');
      _expect(':');
      _space();
      result[key] = _peek('{') ? _object() : _string();
      _space();
      if (_take('}')) return result;
      _expect(',');
    }
  }

  String _string() {
    _space();
    _expect('"');
    final output = StringBuffer();
    while (_index < source.length) {
      final character = source[_index++];
      if (character == '"') return output.toString();
      if (character != r'\') {
        if (character.codeUnitAt(0) < 0x20) {
          _fail('Unescaped JSON control character.');
        }
        output.write(character);
        continue;
      }
      if (_index >= source.length) _fail('Incomplete JSON escape.');
      final escaped = source[_index++];
      const simple = <String, String>{
        '"': '"',
        r'\': r'\',
        '/': '/',
        'b': '\b',
        'f': '\f',
        'n': '\n',
        'r': '\r',
        't': '\t',
      };
      final simpleValue = simple[escaped];
      if (simpleValue != null) {
        output.write(simpleValue);
        continue;
      }
      if (escaped != 'u' || _index + 4 > source.length) {
        _fail('Invalid JSON escape.');
      }
      final code = int.tryParse(
        source.substring(_index, _index + 4),
        radix: 16,
      );
      if (code == null) _fail('Invalid JSON unicode escape.');
      output.writeCharCode(code);
      _index += 4;
    }
    _fail('Unterminated JSON string.');
  }

  void _space() {
    while (_index < source.length &&
        const {' ', '\n', '\r', '\t'}.contains(source[_index])) {
      _index++;
    }
  }

  bool _peek(String value) {
    _space();
    return _index < source.length && source[_index] == value;
  }

  bool _take(String value) {
    _space();
    if (_index < source.length && source[_index] == value) {
      _index++;
      return true;
    }
    return false;
  }

  void _expect(String value) {
    if (!_take(value)) _fail('Expected $value.');
  }

  Never _fail(String message) => throw AigcMetadataException(
        AigcMetadataErrorCode.invalidMetadataJson,
        message,
      );
}
