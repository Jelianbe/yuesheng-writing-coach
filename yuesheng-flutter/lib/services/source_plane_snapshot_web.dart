// ─────────────────────────────────────────────────────────────
// 源面落盘 · **web 侧 stub**（T-20261031-03 裁 2 · 编译期门控）
//
// 平台门面见 `source_plane_snapshot.dart`：
//   export 'source_plane_snapshot_io.dart'
//       if (dart.library.js_interop) 'source_plane_snapshot_web.dart';
//
// ★ 裁值（DECISIONS §4-459 裁 2）：web 侧**一律返回 null**。
//   与 capture 的既有语义（「全 catch 失败 / 挂起 / 超限一律 null」）兼容
//   ⇒ **诊断主链零影响**，仅 web 首发少一份快照仪器数据。
//
// ★ 平台无关的纯逻辑（域枚举 / 消息桩 / 快照 DTO / sha 锚）在
//   `source_plane_snapshot_core.dart`，io / web 两侧共用同一份实现
//   （**不复制逻辑**）。
//
// ★ 硬边界（沿用 B0c 原件）：本文件不进任何 prompt / schema / 判据真源；
//   不触诊断结论；不截断源面文本。
// ─────────────────────────────────────────────────────────────

import 'source_plane_snapshot_core.dart';

export 'source_plane_snapshot_core.dart';

/// 快照存储（web 侧）：浏览器无文件系统 ⇒ **一律没有快照**。
class SourcePlaneStore {
  static const int kMaxSnapshots = 50;
  static const int kMaxCharsPerDomain = 122900;
  static const String kSubDir = 'source_plane';

  SourcePlaneStore({int Function()? now});

  /// web 无文件可落 ⇒ 恒返回 null（与「失败 / 挂起 / 超限一律 null」同语义）。
  Future<SourcePlaneSnapshot?> save({
    required SourcePlaneDomain domain,
    required String chapterText,
    Iterable<SourcePlaneMessage> messages = const <SourcePlaneMessage>[],
    String settingText = '',
  }) async => null;

  /// web 无文件可读 ⇒ 恒返回 null。
  Future<SourcePlaneSnapshot?> load(String snapshotId) async => null;

  /// web 无快照可列 ⇒ 恒返回空清单。
  Future<List<String>> listIds() async => const <String>[];
}
