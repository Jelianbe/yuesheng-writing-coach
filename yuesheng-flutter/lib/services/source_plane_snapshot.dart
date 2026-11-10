// ─────────────────────────────────────────────────────────────
// 源面落盘（B0c 前半件 · 纯 instrumentation · R-027 零报批）· **平台门面**
// （T-20261031-03 裁 2 · 编译期门控）
//
// 语义（施工单 `.ai/reports/2026-11-09-B0c前半件施工单.md` §2）：
//   诊断时把 D1/D2/D3 源面文本落盘留痕，供 L0-① 锚定闸与 R1 假红率
//   人评「对源面复验」。载体 = 应用文档目录 JSON 快照（零 DB 迁移、
//   不触 schemaVersion 50 / build_runner 生成链）。
//
// ★ 为什么是门面：落盘侧要平台 io 库（File / Directory / Platform）⇒
//   整份归 io 侧；但接线方 `source_plane_capture.dart` 必须保持**无 io 依赖**
//   （否则 web 编译期就红）。⇒ 本文件只做**条件导出**：
//     · native（移动端 / 桌面）→ `source_plane_snapshot_io.dart`（真实实现）
//     · web                    → `source_plane_snapshot_web.dart`（stub，恒返回 null）
//
// ★ 平台无关的纯逻辑（域枚举 / 消息桩 / 快照 DTO / sha 锚）在
//   `source_plane_snapshot_core.dart`，io / web 两侧共用同一份实现
//   （**不复制逻辑、不新增 A→B 静态映射表**）。
//
// ★ 硬边界（违反即红）：
//   1. 本文件不进任何 prompt / schema / 判据真源（F-5 泄漏教训）；
//   2. 不触诊断结论与弱证据闸的可达化（行为变更归 L0-①，挂 AER）；
//   3. 不截断源面文本（截断 = 逐字复验失效）⇒ 超限直接拒绝保存；
//   4. 诊断链接线 = `source_plane_capture.dart`（B0c 后半件），本文件只管存取。
// ─────────────────────────────────────────────────────────────

export 'source_plane_snapshot_io.dart'
    if (dart.library.js_interop) 'source_plane_snapshot_web.dart';
