// ─────────────────────────────────────────────────────────────
// SuggestionAdoptionService — 建议采纳动作统一入口（批次5 5.1）
//
// 收敛「采纳建议到章节」动作（AdoptSuggestionSheet.show + 采纳后
// 刷新），写作页 / 未来聊天页共用同一路径，防两套实现漂移。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../widgets/adopt_suggestion_sheet.dart';

/// 打开「采纳建议」弹窗并等待用户完成采纳/撤销。
///
/// [chapterId] 采纳目标章节；[suggestion] 建议原文；[onAdopted]
/// 采纳/撤销成功后由调用方刷新章节内容（写作页刷新 store + 编辑器）。
void adoptSuggestionToChapter(
  BuildContext context, {
  required String chapterId,
  required String suggestion,
  required Future<void> Function() onAdopted,
}) {
  AdoptSuggestionSheet.show(
    context,
    chapterId: chapterId,
    suggestion: suggestion,
    onAdopted: onAdopted,
  );
}
