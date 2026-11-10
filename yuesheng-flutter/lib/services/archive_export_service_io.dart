// ─────────────────────────────────────────────────────────────
// archive_export_service — 教学档案导出 · **io 侧**（写临时文件后分享）
// （T-20261031-03 §九 #4 · 编译期门控）
//
// 平台门面见 `archive_export_service.dart`：
//   export 'archive_export_service_io.dart'
//       if (dart.library.js_interop) 'archive_export_service_web.dart';
// ⇒ native（移动端 / 桌面）走本文件；web 走 `archive_export_service_web.dart`
//   的 stub（抛 `UnsupportedError`）。
//
// ★ 移动端零行为变化：本函数与拆分前**逐字等价**（同临时目录、同文件名、
//   同 mimeType、同 ShareParams）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 写入临时目录并调起系统分享面板
Future<void> shareArchiveExport({
  required String json,
  required String fileName,
  String? subject,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, fileName));
  await file.writeAsString(json, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: subject,
    ),
  );
}
