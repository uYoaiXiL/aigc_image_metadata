# aigc_image_metadata

[English](https://github.com/uYoaiXiL/aigc_image_metadata/blob/main/README.md)

一个纯 Dart 图片元数据包，用于读取、首次写入、移植和验证 PNG、JPEG 图片中的
GB 45438-2025 / TC260 AIGC 隐式标识。

当图片经过重新编码，例如添加可见水印后，可使用本包将原图的 AIGC 元数据恢复到
最终文件中。

## 功能

- 读取 PNG、JPEG 图片中的 TC260 AIGC 元数据。
- 写入标准七字段 AIGC 标识。
- 在图片重新编码后移植原有标识。
- 验证容器结构、元数据、格式和尺寸。
- 使用稳定的类型化错误码报告失败。
- 对不可信图片和 XMP 数据执行资源限制。

## 安装

```yaml
dependencies:
  aigc_image_metadata: ^0.1.0
```

```dart
import 'package:aigc_image_metadata/aigc_image_metadata.dart';
```

## 重编码后保留标识

```dart
const codec = AigcImageMetadataCodec();

final result = codec.transplant(
  sourceBytes: originalBytes,
  reencodedBytes: reencodedBytes,
  expectedFormat: AigcImageFormat.jpeg,
);

final outputBytes = result.bytes;
```

默认要求原图与重编码图片的格式和尺寸保持一致。合法缩放或裁剪时可显式允许尺寸变化：

```dart
final result = codec.transplant(
  sourceBytes: originalBytes,
  reencodedBytes: resizedBytes,
  dimensionPolicy: AigcDimensionPolicy.allowChange,
);
```

## 首次写入标识

```dart
const metadata = Tc260AigcMetadata(
  label: '1',
  contentProducer: 'ExampleService',
  produceId: 'IMG-123-1',
  reservedCode1: '',
  contentPropagator: 'ExampleService',
  propagateId: 'IMG-123-1',
  reservedCode2: '',
);

final result = codec.embed(
  encodedBytes: encodedBytes,
  metadata: metadata,
  expectedFormat: AigcImageFormat.png,
  propagationPolicy:
      AigcPropagationPolicy.requireProducerAsPropagator,
);
```

## 读取与验证

```dart
final info = codec.read(imageBytes);

print(info.format);
print(info.width);
print(info.height);
print(info.metadata.toJson());
print(info.container.isCanonical);
```

要求图片采用规范容器结构时：

```dart
final verified = codec.verifyCanonical(
  bytes: imageBytes,
  expectedMetadata: expectedMetadata,
  expectedFormat: AigcImageFormat.png,
);
```

## 策略说明

- `AigcContainerPolicy.compatible` 接受本包支持的 TC260 兼容表达，但全文件只能
  存在一个 AIGC 载荷。
- `AigcContainerPolicy.canonical` 要求一个标准 XMP 容器，且不存在旧版 PNG
  AIGC 文本块。
- `AigcPropagationPolicy.requireProducerAsPropagator` 要求生产者与传播者、生成
  ID 与传播 ID 分别一致。
- `AigcExistingXmpPolicy.reject` 防止意外删除目标图已有的 XMP。只有明确需要
  替换时才使用 `replace`。

## 错误处理

所有公开操作失败时都会抛出 `AigcMetadataException`。业务代码应根据 `code`
处理，并映射为自己的用户提示。

```dart
try {
  codec.read(imageBytes);
} on AigcMetadataException catch (error) {
  switch (error.code) {
    case AigcMetadataErrorCode.metadataMissing:
      // 处理缺少 AIGC 标识的情况。
      break;
    default:
      // 处理图片无效或格式不受支持的情况。
      break;
  }
}
```

`message` 和 `offset` 仅用于开发诊断，不应直接展示给终端用户。

## 支持边界

v0.1.0 支持 Dart VM 和 Flutter Android/iOS 上的 PNG、JPEG 图片，暂不支持 Web。

本包只处理 TC260 AIGC 元数据，不绘制可见水印、不重新编码像素、不保存图片，也不
复制 EXIF、ICC、IPTC、GPS、C2PA 或任意第三方 XMP 元数据。

本包提供工程能力，不构成法律或监管意见。

## 许可证

[MIT](LICENSE)
