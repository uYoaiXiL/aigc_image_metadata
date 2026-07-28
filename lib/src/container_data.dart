import 'dart:typed_data';

import 'models.dart';

final class ContainerData {
  const ContainerData({
    required this.format,
    required this.width,
    required this.height,
    required this.standardXmpPackets,
    required this.legacyAigcPayloads,
    required this.parsed,
  });

  final AigcImageFormat format;
  final int width;
  final int height;
  final List<String> standardXmpPackets;
  final List<String> legacyAigcPayloads;
  final Object parsed;
}

abstract interface class ContainerCodec {
  ContainerData parse(Uint8List bytes, AigcMetadataLimits limits);

  Uint8List writeCanonical(
    ContainerData target,
    List<int> xmpBytes,
    AigcExistingXmpPolicy existingXmpPolicy,
  );
}
