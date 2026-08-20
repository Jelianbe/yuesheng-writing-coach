// ─────────────────────────────────────────────────────────────
// focus_resolver 拆分：focus_resolver_resolve.dart（R-019 ≤300 行）
// 主入口：resolveTeachingFocus（6 项状态校验门控）。迁移自 focus_resolver.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'focus_resolver.dart';
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
  final aiSuggestedFocusId = input.aiSuggestedFocusId;
  final userFocusOverride = input.userFocusOverride;
  final subphase = input.subphase;
  final focusHistory = input.focusHistory;

  final training = isInTraining(subphase);
  final previousFocusId = focusHistory.isNotEmpty
      ? focusHistory.first.focusId
      : null;
  final hasUserOverride = userFocusOverride != null;

  // 确定候选 focus：用户切换优先（5.7.2）
  final candidateFocusId = hasUserOverride
      ? userFocusOverride
      : aiSuggestedFocusId;

  // 无候选 → fallback
  if (candidateFocusId == null) {
    final fb = _selectFallback(
      problems,
      studentSkillLevel: input.studentSkillLevel,
    );
    return ResolveFocusOutput(
      activatedFocusId: fb.id,
      source: fb.id != null ? FocusSource.fallback : FocusSource.none,
      reason: fb.reason,
    );
  }

  FocusProblem? candidateProblem;
  try {
    candidateProblem = problems.firstWhere(
      (p) => p.syndromeId == candidateFocusId,
    );
  } catch (_) {
    candidateProblem = null;
  }

  // 校验 1：在池中
  if (candidateProblem == null) {
    // 训练中 + 用户切换 + 不在池中 → 拒绝，维持原 focus（5.7.2 第 2 行）
    if (training && hasUserOverride && previousFocusId != null) {
      FocusProblem? prev;
      try {
        prev = problems.firstWhere((p) => p.syndromeId == previousFocusId);
      } catch (_) {
        prev = null;
      }
      if (prev != null &&
          prev.confirmationStatus != ConfirmationStatus.rejected &&
          prev.status != 'resolved') {
        return ResolveFocusOutput(
          activatedFocusId: previousFocusId,
          source: FocusSource.aiSuggested,
          reason: '训练中用户切换 $candidateFocusId 不在池中，维持原 focus $previousFocusId',
          rejectReason: '学员想切换到 $candidateFocusId，但该问题不在当前症候池。建议告知学员当前可用的症候。',
        );
      }
    }
    final fb = _selectFallback(
      problems,
      studentSkillLevel: input.studentSkillLevel,
    );
    return ResolveFocusOutput(
      activatedFocusId: fb.id,
      source: fb.id != null ? FocusSource.fallback : FocusSource.none,
      reason: '候选 focus $candidateFocusId 不在 active_problem 池中。${fb.reason}',
    );
  }

  // 校验 2：非 rejected
  if (candidateProblem.confirmationStatus == ConfirmationStatus.rejected) {
    final fb = _selectFallback(
      problems,
      studentSkillLevel: input.studentSkillLevel,
    );
    return ResolveFocusOutput(
      activatedFocusId: fb.id,
      source: fb.id != null ? FocusSource.fallback : FocusSource.none,
      reason: '候选 focus $candidateFocusId 已被 rejected。${fb.reason}',
    );
  }

  // 校验 3：非 resolved
  if (candidateProblem.status == 'resolved') {
    // 训练中 + 用户切换 + 已 resolved → 拒绝，维持原 focus（5.7.2 第 2 行）
    if (training && hasUserOverride && previousFocusId != null) {
      FocusProblem? prev;
      try {
        prev = problems.firstWhere((p) => p.syndromeId == previousFocusId);
      } catch (_) {
        prev = null;
      }
      if (prev != null &&
          prev.confirmationStatus != ConfirmationStatus.rejected &&
          prev.status != 'resolved') {
        return ResolveFocusOutput(
          activatedFocusId: previousFocusId,
          source: FocusSource.aiSuggested,
          reason:
              '训练中用户切换 $candidateFocusId 已 resolved，维持原 focus $previousFocusId',
          rejectReason:
              '学员想切换到 ${candidateProblem.syndromeName}（$candidateFocusId），但该问题已解决。建议告知学员。',
        );
      }
    }
    final fb = _selectFallback(
      problems,
      studentSkillLevel: input.studentSkillLevel,
    );
    return ResolveFocusOutput(
      activatedFocusId: fb.id,
      source: fb.id != null ? FocusSource.fallback : FocusSource.none,
      reason: '候选 focus $candidateFocusId 已 resolved。${fb.reason}',
    );
  }

  // 校验 1-3 通过，candidate 有效

  // 校验 4 + 5：训练中冲突解决（5.7.2）
  if (training) {
    if (hasUserOverride) {
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
    if (previousFocusId != null) {
      FocusProblem? prev;
      try {
        prev = problems.firstWhere((p) => p.syndromeId == previousFocusId);
      } catch (_) {
        prev = null;
      }
      if (prev != null &&
          prev.confirmationStatus != ConfirmationStatus.rejected &&
          prev.status != 'resolved') {
        return ResolveFocusOutput(
          activatedFocusId: previousFocusId,
          source: FocusSource.aiSuggested,
          reason: '训练中拒绝 AI 自主切换，维持原 focus $previousFocusId',
          rejectReason:
              '当前正在训练 ${prev.syndromeName}（$previousFocusId），本轮维持原 focus，下一轮再考虑切换。',
        );
      }
    }
    // 原 focus 无效 → fallback
    final fb = _selectFallback(
      problems,
      studentSkillLevel: input.studentSkillLevel,
    );
    return ResolveFocusOutput(
      activatedFocusId: fb.id,
      source: fb.id != null ? FocusSource.fallback : FocusSource.none,
      reason: '训练中原 focus ${previousFocusId ?? '无'} 无效。${fb.reason}',
    );
  }

  // 非训练中

  // 校验 6：频繁切换检测（5.7.3）
  // 批次4（4.8 O5）：明确指定症候 ID 的用户覆盖绕过频繁切换降级（用户意图优先），
  // 仅保留安全门控（在池中/非 rejected/非 resolved 已在前方校验）
  if (!hasUserOverride &&
      _isFrequentSwitching(candidateFocusId, focusHistory)) {
    // 降级：维持上一轮 focus
    if (previousFocusId != null) {
      FocusProblem? prev;
      try {
        prev = problems.firstWhere((p) => p.syndromeId == previousFocusId);
      } catch (_) {
        prev = null;
      }
      if (prev != null &&
          prev.confirmationStatus != ConfirmationStatus.rejected &&
          prev.status != 'resolved') {
        return ResolveFocusOutput(
          activatedFocusId: previousFocusId,
          source: FocusSource.aiSuggested,
          reason: '频繁切换检测，维持原 focus $previousFocusId',
          rejectReason:
              '检测到连续 ${FocusSwitch.threshold} 轮切换不同 focus，本轮维持原 focus。如确需切换，请在 teaching_plan.focus_reason 中说明切换的必要性（如：学员进步明显 / 原焦点已解决 / 用户主动要求）。',
        );
      }
    }
    // 原 focus 无效，仍采用 candidate（降级失败回退）
    return ResolveFocusOutput(
      activatedFocusId: candidateFocusId,
      source: hasUserOverride
          ? FocusSource.userOverride
          : FocusSource.aiSuggested,
      reason: '频繁切换检测但原 focus 无效，采用候选 focus $candidateFocusId',
    );
  }

  // 全部校验通过
  return ResolveFocusOutput(
    activatedFocusId: candidateFocusId,
    source: hasUserOverride
        ? FocusSource.userOverride
        : FocusSource.aiSuggested,
    reason:
        '${hasUserOverride ? '用户' : 'AI'}建议 focus $candidateFocusId 通过 6 项校验',
  );
}
