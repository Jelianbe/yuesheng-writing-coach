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

/// Fallback 优先级表（5.4.2）
/// rejected / ignored / resolved 症候永远不进入候选池
({String? id, String reason}) _selectFallback(
  List<FocusProblem> problems, {
  SkillLevel? studentSkillLevel,
}) {
  if (problems.isEmpty) {
    _traceSilentSkip('活跃症候列表为空，不注入 L3');
    return (id: null, reason: '活跃症候列表为空，不注入 L3');
  }

  // 候选池：排除 rejected / ignored / resolved
  final candidates = problems
      .where(
        (p) =>
            p.status == 'active' &&
            p.confirmationStatus != ConfirmationStatus.rejected &&
            p.confirmationStatus != ConfirmationStatus.ignored,
      )
      .toList();
  if (candidates.isEmpty) {
    _traceSilentSkip('无可用 active 症候（全部 rejected/ignored/resolved），不注入 L3');
    return (
      id: null,
      reason: '无可用 active 症候（全部 rejected/ignored/resolved），不注入 L3',
    );
  }

  // 优先级 1：confirmed + active，按 severity DESC, confirmed_at DESC
  final confirmed = candidates
      .where((p) => p.confirmationStatus == ConfirmationStatus.confirmed)
      .toList();
  if (confirmed.isNotEmpty) {
    confirmed.sort((a, b) {
      final sv = _kSeverityRank[b.severity]! - _kSeverityRank[a.severity]!;
      if (sv != 0) return sv;
      return (b.confirmedAt ?? 0) - (a.confirmedAt ?? 0);
    });
    final picked = _preferLevelAppropriate(confirmed, studentSkillLevel);
    return (
      id: picked.syndromeId,
      reason:
          'fallback 优先级 1（confirmed + active）：选 ${picked.syndromeId}（severity=${picked.severity.value}${studentSkillLevel != null ? '，层级≤学员当前+1' : ''}）',
    );
  }

  // 优先级 2：suspected + active，按 severity DESC
  final suspected = candidates
      .where((p) => p.confirmationStatus == ConfirmationStatus.suspected)
      .toList();
  if (suspected.isNotEmpty) {
    suspected.sort(
      (a, b) => _kSeverityRank[b.severity]! - _kSeverityRank[a.severity]!,
    );
    final picked = _preferLevelAppropriate(suspected, studentSkillLevel);
    return (
      id: picked.syndromeId,
      reason:
          'fallback 优先级 2（suspected + active）：选 ${picked.syndromeId}（severity=${picked.severity.value}${studentSkillLevel != null ? '，层级≤学员当前+1' : ''}）',
    );
  }

  // 优先级 3：任意 active，按 severity DESC
  candidates.sort(
    (a, b) => _kSeverityRank[b.severity]! - _kSeverityRank[a.severity]!,
  );
  final picked = _preferLevelAppropriate(candidates, studentSkillLevel);
  return (
    id: picked.syndromeId,
    reason:
        'fallback 优先级 3（active）：选 ${picked.syndromeId}（severity=${picked.severity.value}${studentSkillLevel != null ? '，层级≤学员当前+1' : ''}）',
  );
}

/// 频繁切换检测（5.7.3）
/// 若最近 N 轮 focus_id 互不相同（且都有值），且 candidate 与最近一轮不同，判定为频繁切换
bool _isFrequentSwitching(
  String candidateFocusId,
  List<FocusHistoryEntry> focusHistory,
) {
  if (focusHistory.length < FocusSwitch.threshold) return false;

  final recent = focusHistory.take(FocusSwitch.threshold).toList();

  // candidate 与最近一轮相同 → 不是切换，不触发
  if (candidateFocusId == recent.first.focusId) return false;

  // 最近 N 轮 focus_id 互不相同
  final ids = recent.map((h) => h.focusId).toList();
  final uniqueIds = ids.toSet();
  return ids.length == uniqueIds.length;
}

/// 6 项状态校验门控 + fallback 优先级表
///
/// 校验顺序（5.7.1）：
/// 1. 在池中
/// 2. 非 rejected
/// 3. 非 resolved
/// 4. 用户切换（5.7.2 冲突解决）
/// 5. 训练中（5.7.2 冲突解决）
/// 6. 频繁切换（5.7.3 降级）
ResolveFocusOutput resolveTeachingFocus(ResolveFocusInput input) {
  final problems = input.problems;
  final hasUserOverride = input.userFocusOverride != null;
  final candidateFocusId = hasUserOverride
      ? input.userFocusOverride
      : input.aiSuggestedFocusId;
  if (candidateFocusId == null) return _fallbackOutput(input, '');

  final candidateProblem = _findProblem(problems, candidateFocusId);
  if (candidateProblem == null) {
    return _resolveNotInPool(input, candidateFocusId);
  }
  if (candidateProblem.confirmationStatus == ConfirmationStatus.rejected) {
    return _fallbackOutput(input, '候选 focus $candidateFocusId 已被 rejected。');
  }
  if (candidateProblem.status == 'resolved') {
    return _resolveResolved(input, candidateProblem, candidateFocusId);
  }
  if (isInTraining(input.subphase)) {
    return _resolveTrainingSwitch(input, candidateProblem, candidateFocusId);
  }
  // 批次4（4.8 O5）：明确指定症候 ID 的用户覆盖绕过频繁切换降级（用户意图优先）
  if (!hasUserOverride &&
      _isFrequentSwitching(candidateFocusId, input.focusHistory)) {
    return _resolveFrequentSwitch(input, candidateFocusId);
  }
  return ResolveFocusOutput(
    activatedFocusId: candidateFocusId,
    source: hasUserOverride
        ? FocusSource.userOverride
        : FocusSource.aiSuggested,
    reason:
        '${hasUserOverride ? '用户' : 'AI'}建议 focus $candidateFocusId 通过 6 项校验',
  );
}

/// 校验 1：候选不在池中（R-019 二次拆：resolveTeachingFocus）。
ResolveFocusOutput _resolveNotInPool(
  ResolveFocusInput input,
  String candidateFocusId,
) {
  final training = isInTraining(input.subphase);
  final hasUserOverride = input.userFocusOverride != null;
  // 训练中 + 用户切换 + 不在池中 → 拒绝，维持原 focus（5.7.2 第 2 行）
  if (training && hasUserOverride) {
    final kept = _maintainPreviousFocus(
      input.problems,
      _previousFocusId(input),
      candidateFocusId,
      '训练中用户切换 $candidateFocusId 不在池中，维持原 focus',
      (_) => '学员想切换到 $candidateFocusId，但该问题不在当前症候池。建议告知学员当前可用的症候。',
    );
    if (kept != null) return kept;
  }
  return _fallbackOutput(
    input,
    '候选 focus $candidateFocusId 不在 active_problem 池中。',
  );
}

/// 校验 3：候选已 resolved（R-019 二次拆：resolveTeachingFocus）。
ResolveFocusOutput _resolveResolved(
  ResolveFocusInput input,
  FocusProblem candidateProblem,
  String candidateFocusId,
) {
  final training = isInTraining(input.subphase);
  final hasUserOverride = input.userFocusOverride != null;
  // 训练中 + 用户切换 + 已 resolved → 拒绝，维持原 focus（5.7.2 第 2 行）
  if (training && hasUserOverride) {
    final kept = _maintainPreviousFocus(
      input.problems,
      _previousFocusId(input),
      candidateFocusId,
      '训练中用户切换 $candidateFocusId 已 resolved，维持原 focus',
      (prevName) => '学员想切换到 $prevName（$candidateFocusId），但该问题已解决。建议告知学员。',
    );
    if (kept != null) return kept;
  }
  return _fallbackOutput(input, '候选 focus $candidateFocusId 已 resolved。');
}

/// 校验 4 + 5：训练中冲突解决（5.7.2）（R-019 二次拆：resolveTeachingFocus）。
ResolveFocusOutput _resolveTrainingSwitch(
  ResolveFocusInput input,
  FocusProblem candidateProblem,
  String candidateFocusId,
) {
  if (input.userFocusOverride != null) {
    // 训练中 + 用户主动切换 + focus 有效 → 允许切换，注入提示（5.7.2 第 1 行）
    // 批次4（4.8 O5）：提示文案改为「已按要求切换，但建议先完成当前训练」
    return ResolveFocusOutput(
      activatedFocusId: candidateFocusId,
      source: FocusSource.userOverride,
      reason: '训练中用户主动切换到 $candidateFocusId（有效），允许切换',
      rejectReason:
          '已按你的要求切换到 ${candidateProblem.syndromeName}（$candidateFocusId）。若当前还有未完成的训练，建议先完成当前训练再切换，效果更连贯。',
    );
  }
  // 训练中 + AI 自主切换 → 拒绝切换，维持原 focus（5.7.2 第 3 行）
  final kept = _maintainPreviousFocus(
    input.problems,
    _previousFocusId(input),
    candidateFocusId,
    '训练中拒绝 AI 自主切换，维持原 focus',
    (prevName) => '当前正在训练 $prevName，本轮维持原 focus，下一轮再考虑切换。',
  );
  if (kept != null) return kept;
  // 原 focus 无效 → fallback
  return _fallbackOutput(input, '训练中原 focus 无效。');
}

/// 校验 6：频繁切换降级（5.7.3）（R-019 二次拆：resolveTeachingFocus）。
ResolveFocusOutput _resolveFrequentSwitch(
  ResolveFocusInput input,
  String candidateFocusId,
) {
  // 降级：维持上一轮 focus
  final kept = _maintainPreviousFocus(
    input.problems,
    _previousFocusId(input),
    candidateFocusId,
    '频繁切换检测，维持原 focus',
    (_) =>
        '检测到连续 ${FocusSwitch.threshold} 轮切换不同 focus，本轮维持原 focus。如确需切换，请在 teaching_plan.focus_reason 中说明切换的必要性（如：学员进步明显 / 原焦点已解决 / 用户主动要求）。',
  );
  if (kept != null) return kept;
  // 原 focus 无效，仍采用 candidate（降级失败回退）
  return ResolveFocusOutput(
    activatedFocusId: candidateFocusId,
    source: FocusSource.aiSuggested,
    reason: '频繁切换检测但原 focus 无效，采用候选 focus $candidateFocusId',
  );
}

/// 最近一轮 focus id（R-019 三次拆：resolveTeachingFocus）。
String? _previousFocusId(ResolveFocusInput input) {
  return input.focusHistory.isNotEmpty
      ? input.focusHistory.first.focusId
      : null;
}

/// 在症候列表中查找指定 id（R-019 拆出：resolveTeachingFocus）。找不到返回 null。
FocusProblem? _findProblem(List<FocusProblem> problems, String? id) {
  if (id == null) return null;
  for (final p in problems) {
    if (p.syndromeId == id) return p;
  }
  return null;
}

/// 统一 fallback 输出（R-019 拆出：resolveTeachingFocus）。
ResolveFocusOutput _fallbackOutput(ResolveFocusInput input, String prefix) {
  final fb = _selectFallback(
    input.problems,
    studentSkillLevel: input.studentSkillLevel,
  );
  return ResolveFocusOutput(
    activatedFocusId: fb.id,
    source: fb.id != null ? FocusSource.fallback : FocusSource.none,
    reason: prefix + fb.reason,
  );
}

/// 维持原 focus 输出；原 focus 无效返回 null（R-019 拆出：resolveTeachingFocus）。
ResolveFocusOutput? _maintainPreviousFocus(
  List<FocusProblem> problems,
  String? previousFocusId,
  String candidateFocusId,
  String reason,
  String Function(String prevName) buildRejectReason,
) {
  if (previousFocusId == null) return null;
  final prev = _findProblem(problems, previousFocusId);
  if (prev == null ||
      prev.confirmationStatus == ConfirmationStatus.rejected ||
      prev.status == 'resolved') {
    return null;
  }
  return ResolveFocusOutput(
    activatedFocusId: previousFocusId,
    source: FocusSource.aiSuggested,
    reason: reason,
    rejectReason: buildRejectReason(prev.syndromeName),
  );
}
