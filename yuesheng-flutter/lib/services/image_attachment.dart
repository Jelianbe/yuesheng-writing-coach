// ─────────────────────────────────────────────────────────────
// image_attachment — 图片输入链路（C144 I1 · 截图→教练看）
//
// 职责：
//   1. pickImage：image_picker 相册选图 → bytes + mime（取消/失败返回 null）
//   2. imageBytesToDataUri：bytes → `data:<mime>;base64,...`
//   3. buildImageContentBlock：bytes+mime → ChatContentBlock.imageUrl
//      （挂到 ChatMessage.contentBlocks 即随请求体送 LLM 多模态）
//
// R-009 / R-027 边界（红线）：
//   本服务只做「选图 → 编码 → 挂到消息」，**不生成任何「看图总结/评判」
//   指令文本**。图片作为作者引用材料进入既有教学链，对图片内容的教学解读
//   仍走既有诊断口径。零新增 prompt 面。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'decode_guard.dart';
import 'llm_client.dart';

/// 选中的图片（字节 + MIME，不落地公网 URL）
class PickedImage {
  final Uint8List bytes;
  final String mimeType; // 'image/png' | 'image/jpeg' | 'image/gif' ...

  const PickedImage({required this.bytes, required this.mimeType});
}

/// 从相册选图（对齐 pickDocument 的容错契约：取消/失败返回 null，不抛崩页）。
///
/// 平台通道失败（无实现/权限拒绝/用户取消）经 decode_guard 留痕后返回 null。
Future<PickedImage?> pickImage() async {
  try {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedImage(bytes: bytes, mimeType: mimeTypeFromName(file.name));
  } catch (e, st) {
    logDecodeFailure(field: 'imagePick', error: e, stack: st);
    return null;
  }
}

/// 字节 → `data:<mime>;base64,...`（OpenAI image_url content block 要求的 data URI）
String imageBytesToDataUri(Uint8List bytes, String mimeType) =>
    'data:$mimeType;base64,${base64Encode(bytes)}';

/// 直接把选中图片包成 image_url content block（送 LLM 的最小单元）。
ChatContentBlock buildImageContentBlock(Uint8List bytes, String mimeType) =>
    ChatContentBlock.imageUrl(imageBytesToDataUri(bytes, mimeType));

/// 按扩展名推断 MIME（image_picker 的 XFile 不直接给 mime）。
/// 未识别一律回落 `image/png`（多数截图/录屏为 PNG）。
String mimeTypeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  return 'image/png';
}
