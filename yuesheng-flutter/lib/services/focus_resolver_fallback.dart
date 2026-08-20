// ─────────────────────────────────────────────────────────────
// focus_resolver 拆分：focus_resolver_fallback.dart（R-019 ≤300 行）
// Fallback 优先级表：_selectFallback/_isFrequentSwitching。迁移自 focus_resolver.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'focus_resolver.dart';
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

