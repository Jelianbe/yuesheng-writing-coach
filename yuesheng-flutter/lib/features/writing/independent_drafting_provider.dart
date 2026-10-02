// ─────────────────────────────────────────────────────────────
// independent_drafting_provider — M4 独立起稿模式开关状态（ADR-C134 批3）
//
// 入口性质（R-027 停线项 3 合法例外）：
//   本开关是**学员主动声明**介入递减（学员说「这次我自己来」），
//   不是系统探测——故合法。默认 false（教练正常介入）。
//
// 状态隔离：按 chapterId family 隔离（每章独立开关），会话内有效
// （不持久化到 KV——ADR-C134 §5.3 只要求「至少会话内」；跨会话是否记住
// 由后续批裁定，本批不引入配置面）。
//
// 消费方：
//   ① 教练面板按钮行的开关 UI（写）；
//   ② writing_page_document_controller._recordCompletionEvent（读）——
//     独立起稿期间触发成稿时，给 completion 事件打 independent_drafting 标记，
//     供里程碑证据卡观测（C133 判据沿用：只记不判，无成败布尔）。
//
// R-009：本 provider 只是一个 bool 开关状态，不含任何达标线/打分/自动加码逻辑。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// M4 独立起稿模式开关（按章节隔离，会话内有效）。
///
/// true = 学员本次主动声明「自己来」：教练只给结构性提问，不代写；
/// 期间达成写作目标的 completion 事件会被打上 independent_drafting 标记。
/// false = 默认（教练正常介入）。
final independentDraftingProvider = StateProvider.family<bool, String>(
  (ref, chapterId) => false,
);
