// ─────────────────────────────────────────────────────────────
// whole_chapter_mode_provider — M4 第二格「独立成完整章」模式开关状态
//   （ADR-C137 批1；在 C134 M4a「这次我自己来」之上扩展）
//
// 入口性质（与 M4a 同，R-027 合法例外）：
//   本开关是**学员主动声明**介入进一步递减（学员说「这一章我自己写」），
//   不是系统探测/强制——故合法。默认 false（教练正常介入）。
//
// 与 M4a 的关系（ADR-C137 §2.1 / §4.1）：
//   - M4a「这次我自己来」= 独立**起稿**（本次会话内教练只给结构性提问）；
//   - 本开关「这一章我自己写」= 独立**成完整章**：目标字数达成前教练只做
//     **最小支持**（存在感提示，学员提问才深答；批2 才接对话层 prompt，本批不碰）。
//   - 两者语义叠加：任一为 true，completion 事件都打 independent_drafting 标记
//     （见 writing_page_document_controller._recordCompletionEvent）。
//
// 边界守 R-009（最高条款）：
//   - **可随时退回**：学员点退出即回到教练正常介入，无强制/锁定路径
//     （ADR §2 不做项：不实现系统强制无支架会话）；
//   - 本 provider 只是一个 bool 开关状态，不含任何达标线/打分/代写/处方逻辑。
//
// 状态隔离：按 chapterId family 隔离（每章独立开关），会话内有效
//   （与 M4a 同纪律：跨会话是否记住由后续批裁定，本批不引入配置面）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// M4 第二格「完整章模式」开关（按章节隔离，会话内有效）。
///
/// true = 学员主动声明「这一章我自己写」：目标字数达成前教练只做最小支持，
/// 不主动点评/不替写/不催更；达成写作目标的 completion 事件打 independent_drafting 标记。
/// false = 默认（教练正常介入）。可随时点退出退回求助（无强制锁定）。
final wholeChapterDraftingProvider = StateProvider.family<bool, String>(
  (ref, chapterId) => false,
);
