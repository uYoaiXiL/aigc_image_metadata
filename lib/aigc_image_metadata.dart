/// TC260 AIGC metadata support for PNG and JPEG images.
library;

export 'src/codec.dart' show AigcImageMetadataCodec;
export 'src/errors.dart' show AigcMetadataErrorCode, AigcMetadataException;
export 'src/models.dart'
    show
        AigcContainerInfo,
        AigcContainerPolicy,
        AigcDimensionPolicy,
        AigcExistingXmpPolicy,
        AigcImageFormat,
        AigcImageInfo,
        AigcMetadataLimits,
        AigcPropagationPolicy,
        AigcWriteResult,
        Tc260AigcMetadata;
