# aigc_image_metadata

[English](README.md)

用于读取、首次写入、移植和验证 PNG/JPEG 文件内 TC260 七字段 AIGC
隐式标识。适用于 GB 45438-2025 工程链路，解决图片像素重新编码后 XMP
容器元数据丢失的问题。

> 本包只提供元数据工程能力，不构成法律或监管意见。请结合产品适用地区和
> 最新审核口径进行确认。

## 支持范围

- PNG 标准 XMP `iTXt`，并兼容读取旧版 AIGC 文本块
- JPEG Adobe XMP APP1
- TC260 元素形式和 RDF 属性形式
- Dart VM、Flutter Android/iOS
- v0.1.0 使用 `dart:io` 做有上限的 zlib 解压，不支持 Web

本包只处理 TC260 `AIGC` 对象及七个字符串字段，不绘制可见水印、不编码
像素、不保存相册，也不复制 EXIF、ICC、IPTC、GPS 或任意第三方 XMP。

## 安装

```yaml
dependencies:
  aigc_image_metadata: ^0.1.0
```

当插件项目与 Flutter 应用位于同一级目录时，可在本地开发中使用：

```yaml
dependencies:
  aigc_image_metadata:
    path: ../aigc_image_metadata
```

## 快速开始：重编码后保留标识

```dart
import 'dart:typed_data';
import 'package:aigc_image_metadata/aigc_image_metadata.dart';

Uint8List preserveAigc(Uint8List original, Uint8List reencoded) {
  const codec = AigcImageMetadataCodec();
  return codec.transplant(
    sourceBytes: original,
    reencodedBytes: reencoded,
    sourcePropagationPolicy:
        AigcPropagationPolicy.requireProducerAsPropagator,
  ).bytes;
}
```

默认要求源图和目标图尺寸一致。合法裁剪或缩放时，必须显式传入
`dimensionPolicy: AigcDimensionPolicy.allowChange`。

## 首次写入

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

final result = const AigcImageMetadataCodec().embed(
  encodedBytes: encodedImage,
  metadata: metadata,
  expectedFormat: AigcImageFormat.png,
  propagationPolicy: AigcPropagationPolicy.requireProducerAsPropagator,
);
```

`embed` 默认拒绝目标图已有的标准 XMP。只有明确允许删除全部目标标准 XMP
时，才传入 `existingXmpPolicy: AigcExistingXmpPolicy.replace`。

## 读取与审计

```dart
final info = const AigcImageMetadataCodec().read(bytes);
print(info.metadata.toJson());
print(info.container.standardXmpCount);
print(info.container.isCanonical);
```

`compatible` 可读取元素、RDF 属性和旧版 PNG 形式，但全文件仍只能有一个
AIGC 载荷。`canonical` 要求一个标准 XMP、一个载荷、零旧版 PNG 文本块。

## 校验策略

- `standard` 校验七字段、`Label`、必填值和 TC260 字符范围。
- `requireProducerAsPropagator` 额外要求生产者/传播者及两个 ID 分别相等，
  适合校验后端首次生成文件。
- `requireUnchanged` 防止移植时意外改变尺寸。
- `reject` 防止静默删除目标 XMP；`replace` 表示调用方明确授权规范化替换。

## 错误处理

所有公开失败都是 `AigcMetadataException`。业务应根据稳定的 `code` 映射自己
的本地化提示。`message` 和 `offset` 只用于开发诊断，**禁止直接展示给终端
用户**。

## 规范输出

- PNG：IHDR 后一个未压缩 UTF-8 XMP `iTXt`，关键字为
  `XML:com.adobe.xmp`。
- JPEG：SOI 后一个 Adobe XMP APP1。

写入过程逐字节保留目标图非 XMP Chunk、Segment 和压缩扫描/图像数据。
`embed`、`transplant` 都会重新读取并验证输出。`verifyCanonical` 不做完整
像素解码，调用方仍需使用自己的图片解码器确认可显示。

## 元数据保留边界

移植只从源图复制经过校验的七字段逻辑对象，不复制源图其他元数据。目标图
非 XMP 数据保留；目标标准 XMP 要么拒绝，要么在明确授权后全部替换。

错误示例：

```dart
final reencoded = encodePixels(original); // XMP 很可能已丢失
save(reencoded); // 错误：没有调用 transplant
```

## 安全限制

`AigcMetadataLimits` 限制图片、XMP、PNG Chunk 和容器数量。压缩 PNG 文本
通过有上限的 Sink 解压；DTD、实体、非法 UTF-8、重复 JSON key、错误长度和
CRC 都会被拒绝。

## 跨语言互操作

规范 JSON 使用大小写严格的 `AIGC` 根和七个字段；XMP 命名空间为
`http://www.tc260.org.cn/ns/AIGC/1.0/`。建议保存脱敏的后端 PNG/JPEG 样本，
同时通过本 Dart 包和 Java 后端校验器验证。

## 贡献、安全与许可证

参见 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。本包
采用 [MIT License](LICENSE)。
