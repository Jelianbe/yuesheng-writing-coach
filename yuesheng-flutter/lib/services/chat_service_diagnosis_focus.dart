// ─────────────────────────────────────────────────────────────
// chat_service_diagnosis 方法级拆分：chat_service_diagnosis_focus.dart（R-019 ≤300 行）
// 逐字迁移自 chat_service_diagnosis.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_service.dart';

extension ChatServiceDiagnosisFocus on ChatService {
  /// 批次1（O1）：Teacher 升级阀——某症候严重度达阈值或诊断次数达阈值时，
  /// 绕过心流窗口（持续写作学员「编辑器活跃 120s」恒真 → 建议永远出不来 →
  /// identified 永不前进 → M4-A 永不满足）。返回 true 时允许建议正常输出。
  Future<bool> _shouldBypassFlowWindow(
    String sessionId,
    List<ActiveProblemView> activeProblems,
  ) async {
    if (activeProblems.isEmpty) return false;
    // 严重度阈值：存在 L3 重度症候即绕过
    if (activeProblems.any((p) {
      final sev = Severity.fromString(p.severity);
      return sev != null && sev.index >= kFlowBypassMinSeverity.index;
    })) {
      return true;
    }
    // 诊断次数阈值：某症候累计诊断次数达阈值即绕过（统计失败降级为不绕过）
    try {
      final history = await _studentModelRepo.getTeachingHistory(sessionId);
      for (final p in activeProblems) {
        final diagnosisCount = history.where((r) {
          if (r['type'] != 'diagnosis') return false;
          final syndromes = r['syndromes'];
          return syndromes is List && syndromes.contains(p.syndromeId);
        }).length;
        if (diagnosisCount >= kFlowBypassDiagnosisCount) return true;
      }
    } catch (e) {
      debugPrint('[SafeRun] 升级阀诊断次数统计失败，降级为不绕过: $e');
    }
    return false;
  }

  /// 从用户消息解析 focus 切换意图
  ///
  /// 只解析明确的 P\d+ 编号匹配（"我想练 P003"等），代词"这个"暂不实现
  String? _parseUserFocusFromMessage(
    String content,
    List<ActiveProblemView> activeProblems,
  ) {
    // 批次4（4.5 O9）：放宽覆盖表达变体（先练练/练一下/我想练/想先解决/聚焦/主攻等）
    final patterns = [
      RegExp(r'我想?先?(?:解决|练|练习|练练|练一下)\s*(P\d+)', caseSensitive: false),
      RegExp(r'先?(?:解决|练|练习|练练|练一下)(?:一练)?\s*(P\d+)', caseSensitive: false),
      RegExp(r'(?:聚焦|专注|主攻|重点练)\s*(P\d+)', caseSensitive: false),
    ];

    final activeIds = activeProblems.map((p) => p.syndromeId).toSet();

    for (final pattern in patterns) {
      final match = pattern.firstMatch(content);
      if (match != null && match.groupCount >= 1) {
        final id = match.group(1)!.toUpperCase();
        if (activeIds.contains(id)) return id;
      }
    }
    return null;
  }

  /// 构建 focus 历史条目（从诊断历史提取最近 N 条 focus_id）
  Future<List<_FocusHistoryItem>> _buildFocusHistory(String sessionId) async {
    try {
      final diagnoses = await _diagnosisRepo.listDiagnosisHistory(sessionId);
      final threshold = FocusSwitch.threshold;
      final items = <_FocusHistoryItem>[];
      for (final d in diagnoses.take(threshold)) {
        final focusId = d.currentTeachingFocusId;
        if (focusId != null && focusId.isNotEmpty) {
          items.add(
            _FocusHistoryItem(focusId: focusId, timestamp: d.timestamp),
          );
        }
      }
      return items;
    } catch (e) {
      debugPrint('[SafeRun] loadAttachedFilesForManuscript 失败: $e');
      return [];
    }
  }

  /// 映射 focus-resolver 的 FocusSource 到 chat_context_builder 的 FocusSource
  FocusSource _mapFocusSource(focus.FocusSource source) {
    switch (source) {
      case focus.FocusSource.aiSuggested:
        return FocusSource.aiSuggested;
      case focus.FocusSource.userOverride:
        return FocusSource.userOverride;
      case focus.FocusSource.fallback:
        return FocusSource.fallback;
      case focus.FocusSource.none:
        return FocusSource.none;
    }
  }
}
