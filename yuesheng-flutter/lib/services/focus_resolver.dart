// ─────────────────────────────────────────────────────────────
// 教学焦点激活状态校验门控 — 复刻 services/focus-resolver.ts
// 设计文档：5.4.2 Fallback 优先级表 / 5.7 6 项状态校验门控
//
// 职责：AI 建议 focus ≠ 自动生效，需通过 6 项校验后激活；
// 校验失败时按 5.4.2 优先级表选 fallback。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import '../config/shared_constants.dart';
import '../types/teaching_types.dart';
import 'syndrome_skill_levels.dart';

part 'focus_resolver_fallback.dart';
part 'focus_resolver_resolve.dart';
/// 批次6（6.4 O5）：静默跳过 debug 计数器——沉淀「断链」可见性，
/// 不改跳过行为（focus 未激活 = 教学断链，便于排查为什么没注入 L3）。
int _silentSkipCount = 0;

/// 记录静默跳过日志（仅 kDebugMode 输出）
void _traceSilentSkip(String reason) {
  if (kDebugMode) {
    _silentSkipCount++;
    debugPrint('[FocusResolver] 静默跳过 #$_silentSkipCount：$reason');
  }
}

/// resolver 输入
class ResolveFocusInput {
  final List<FocusProblem> problems;
  final String? aiSuggestedFocusId;
  final String? userFocusOverride;
  final TeachingSubphase? subphase;
  final List<FocusHistoryEntry> focusHistory;

  /// 批次60：学员当前技能层级（软引导——fallback 优先选层级 ≤ 当前+1 的症候）
  final SkillLevel? studentSkillLevel;

  const ResolveFocusInput({
    required this.problems,
    required this.aiSuggestedFocusId,
    required this.userFocusOverride,
    required this.subphase,
    required this.focusHistory,
    this.studentSkillLevel,
  });
}

/// focus 历史条目
class FocusHistoryEntry {
  final String focusId;
  final int timestamp;
  const FocusHistoryEntry({required this.focusId, required this.timestamp});
}

/// focus 来源
enum FocusSource {
  aiSuggested('ai_suggested'),
  userOverride('user_override'),
  fallback('fallback'),
  none('none');

  final String value;
  const FocusSource(this.value);
}

/// resolver 输出
class ResolveFocusOutput {
  final String? activatedFocusId;
  final FocusSource source;
  final String reason;
  final String? rejectReason;

  const ResolveFocusOutput({
    required this.activatedFocusId,
    required this.source,
    required this.reason,
    this.rejectReason,
  });
}

/// 判定是否处于训练中（5.7.6）
/// subphase === 'PRACTICE' || 'FEEDBACK'
bool isInTraining(TeachingSubphase? subphase) {
  return subphase == TeachingSubphase.practice ||
      subphase == TeachingSubphase.feedback;
}

const Map<Severity, int> _kSeverityRank = {
  Severity.l3: 3,
  Severity.l2: 2,
  Severity.l1: 1,
};

/// 批次60：软引导——在已排序候选中优先选「层级 ≤ 学员当前层级+1」的症候。
///
/// 全部越级时回退全候选（层级是引导不是拦截，AI 自主判断优先）。
FocusProblem _preferLevelAppropriate(
  List<FocusProblem> sorted,
  SkillLevel? studentSkillLevel,
) {
  if (studentSkillLevel == null || sorted.isEmpty) return sorted.first;
  final maxLevel = studentSkillLevel.index + 2; // 当前层级+1（L1 index 0 → 上限 L2）
  final appropriate = sorted.where((p) {
    final level = skillLevelOf(p.syndromeId);
    if (level == null) return true; // 未知层级不拦截
    return level.index + 1 <= maxLevel;
  }).toList();
  return (appropriate.isNotEmpty ? appropriate : sorted).first;
}

