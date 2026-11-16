// ─────────────────────────────────────────────────────────────
// diagnosis_drop_log — 诊断块被拒 / 字段静默丢弃的日志片段
//
// 【为什么从 DiagnosisFlowHandler 迁出】
//   纯函数（零字段依赖、零 IO、零 async），却占用存量超限文件的行数预算：
//   门禁 5 的文件级判据（≤300 行，基线模式**变胖容差 0 行**）下，任何一行都是
//   净债务。迁到独立顶层函数后：
//   ① handler 净减行数（A2 施工必须做到净零增量）；
//   ② 该函数可直接单测（此前是私有方法，外部无法构造场景覆盖）；
//   ③ 与 `diagnosis_failure_reason.dart` 同层，形成「诊断链日志文案」的一处收口。
//
// 【口径：逐字不变】
//   输出格式、判定条件、join 分隔符全部与原实现逐字一致 —— 迁移不是重构。
//   `rejectReason == null && notes.isEmpty` ⇒ 返回空串（不产生 ` | ` 前缀）。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/services/diagnosis_parser.dart' show ParseResult;

/// 拼装「被拒原因 / 静默丢弃字段」日志片段（ADR-C63，N1 / N26）。
///
/// 无被拒原因且无丢弃字段时返回空串（调用方直接拼接不产生多余分隔符）。
String diagnosisDropLog(ParseResult r) {
  if (r.rejectReason == null && r.notes.isEmpty) return '';
  final parts = <String>[];
  if (r.rejectReason != null) {
    parts.add('被拒原因=${r.rejectReason}');
  }
  if (r.notes.isNotEmpty) {
    parts.add('静默丢弃=${r.notes.join(",")}');
  }
  return ' | ${parts.join(" | ")}';
}
