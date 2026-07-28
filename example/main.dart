import 'dart:io';
import 'dart:typed_data';

import 'package:aigc_image_metadata/aigc_image_metadata.dart';

void main(List<String> arguments) {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run example/main.dart original reencoded output',
    );
    exitCode = 64;
    return;
  }
  final original = Uint8List.fromList(File(arguments[0]).readAsBytesSync());
  final reencoded = Uint8List.fromList(File(arguments[1]).readAsBytesSync());
  const codec = AigcImageMetadataCodec();
  try {
    final result = codec.transplant(
      sourceBytes: original,
      reencodedBytes: reencoded,
    );
    File(arguments[2]).writeAsBytesSync(result.bytes, flush: true);
    stdout.writeln('Wrote canonical ${result.image.format.mimeType}.');
  } on AigcMetadataException catch (error) {
    stderr.writeln('Metadata operation failed (${error.code.name}).');
    exitCode = 1;
  }
}
