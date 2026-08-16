// ignore_for_file: invalid_use_of_protected_member
part of 'growth_detail_page.dart';

extension _GrowthContent on _GrowthDetailPageState {

  String _cognitiveStyleLabel(CognitiveStyle style) {
    switch (style) {
      case CognitiveStyle.analytical:
        return '分析型';
      case CognitiveStyle.intuitive:
        return '直觉型';
      case CognitiveStyle.mixed:
        return '混合型';
    }
  }

  Widget _buildContent(GrowthState state) {
    final profile = state.profile;
    final hasDiagnoses =
        state.diagnosisHistory.isNotEmpty || state.activeProblems.isNotEmpty;

    // 批次65（B62h）：同类症候复发率（至少出现 2 次才有复发意义）
    final recurrences = state.syndromeRecurrences
        .where((r) => r.occurrences >= 2)
        .toList();

    // 空状态：无诊断 + 无画像
    if (!hasDiagnoses && (profile == null || profile.totalSessions == 0)) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(
                    Icons.insights_outlined,
                    size: 32,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '暂无诊断数据',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 批次 51c：成长总览卡（对齐 RN GrowthOverviewCard）
        if (state.overview != null)
          GrowthOverviewCard(
            totalWords: state.overview!.totalWords,
            diagnosisCount: state.overview!.totalDiagnoses,
            resolvedCount: state.overview!.totalResolved,
            aiInterventions: state.overview!.aiInterventions,
            onViewDetail: _openProgressDetail,
          ),
        if (state.overview != null) ...[
          const SizedBox(height: 12),
          _OverviewGrid(overview: state.overview!),
        ],
        const SizedBox(height: 12),
        // 能力画像卡片
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '能力画像',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ProficiencyRing(
                    level: profile?.proficiency ?? ProficiencyLevel.beginner,
                    confidence: profile?.confidence ?? 0,
                  ),
                ),
                const SizedBox(height: 16),
                if (profile?.cognitiveStyle != null) ...[
                  _InfoRow(
                    label: '认知风格',
                    value: _cognitiveStyleLabel(profile!.cognitiveStyle!.style),
                  ),
                  const SizedBox(height: 8),
                ],
                _InfoRow(
                  label: '总会话数',
                  value: '${profile?.totalSessions ?? 0}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 批次53c：写作风格画像（有 style_profile 时展示，对齐 writing-style.ts 五维坐标）
        if (state.styleProfile != null) ...[
          _Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '写作风格',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      // 批次57：风格纠正入口（纠错非重写）
                      TextButton(
                        onPressed: () => _openStyleCorrection(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          '纠正',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.styleProfile!.summary,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: '感官偏好',
                    value: _sensoryLabel(state.styleProfile!.sensory),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '节奏偏好',
                    value: _rhythmLabel(state.styleProfile!.rhythm),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '叙事距离',
                    value: _narrativeLabel(
                      state.styleProfile!.narrativeDistance,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '语气质地',
                    value: _toneLabel(state.styleProfile!.toneTexture),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '结构本能',
                    value: _structureLabel(state.styleProfile!.structure),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // 症候分布列表（批次 48：按教学状态分组，对齐 RN StudentProfilePanel syndromeGroups）
        if (state.activeProblems.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '症候分布',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ..._buildSyndromeGroups(state, profile),
        ],
        const SizedBox(height: 12),
        // 批次65（B62h）：同类症候复发率（「出现→好转→再犯」聚合）
        if (recurrences.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, top: 4, bottom: 8),
            child: Text(
              '同类症候复发率',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          _Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '同一种问题，好转后是否再次出现',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (int i = 0; i < recurrences.length; i++) ...[
                    _RecurrenceRow(recurrence: recurrences[i]),
                    if (i < recurrences.length - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // 诊断历史时间线
        if (state.diagnosisHistory.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '诊断历史',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          _Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _Timeline(items: state.diagnosisHistory),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // 批次 51c：能力图谱（对齐 RN AbilityChart）
        AbilityChart(scores: state.abilityScores),
        const SizedBox(height: 12),
        // 批次 51c：写作成长曲线（对齐 RN WritingCurveChart，14 天）
        WritingCurveChart(points: state.writingCurve),
        const SizedBox(height: 12),
        // 批次 51c：症候追踪历史（对齐 RN SyndromeHistoryList，最多 10 条）
        SyndromeHistoryList(events: state.syndromeHistory, limit: 10),
        const SizedBox(height: 12),
        // 批次 51c：查看学习进度详情（对齐 RN growth-detail progressLink）
        _ProgressLink(onTap: _openProgressDetail),
      ],
    );
  }

  /// 按教学状态分组渲染症候列表（批次 48，对齐 RN syndromeGroups 顺序：
  /// in_progress → identified → consolidating → mastered，标题复用 SYNDROME_GROUP_TITLES）
  List<Widget> _buildSyndromeGroups(
    GrowthState state,
    StudentProfile? profile,
  ) {
    // 分组顺序（RN StudentProfilePanel.tsx renderSyndromeGroup 调用顺序）
    const order = [
      TeachingState.inProgress,
      TeachingState.identified,
      TeachingState.consolidating,
      TeachingState.mastered,
    ];
    const titles = {
      TeachingState.inProgress: '练习中',
      TeachingState.identified: '待诊断',
      TeachingState.consolidating: '巩固中',
      TeachingState.mastered: '已掌握',
    };

    // 症候 → 教学状态（画像聚合；无画像记录时归入 identified，对齐 RN byState ?? identified 兜底）
    TeachingState stateOf(ActiveProblemView p) {
      final agg = profile?.syndromeProfile[p.syndromeId];
      return agg?.teachingState ?? TeachingState.identified;
    }

    final widgets = <Widget>[];
    for (final ts in order) {
      final items = state.activeProblems
          .where((p) => stateOf(p) == ts)
          .toList();
      if (items.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
          child: Text(
            titles[ts]!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      );
      for (final problem in items) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            problem.syndromeName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '严重度 ${problem.severity}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 教学状态徽章（画像聚合：profile.syndromeProfile[症候ID]）
                    if (profile?.syndromeProfile[problem.syndromeId] != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TeachingStateBadge(
                          state: profile!
                              .syndromeProfile[problem.syndromeId]!
                              .teachingState,
                          size: TeachingStateBadgeSize.sm,
                          showLabel: true,
                        ),
                      ),
                    _SeverityChip(severity: problem.severity),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}
