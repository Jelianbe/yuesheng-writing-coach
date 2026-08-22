// ─────────────────────────────────────────────────────────────
// chat_service_send 步骤块提取：chat_service_send_diagnosis_lock.dart（R-019 ≤300 行）
// 逐字迁移自 chat_service_send.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_service.dart';

extension ChatServiceSendDiagnosisLock on ChatService {
  Future<String?> _injectDiagnosisLock({
    required String sessionId,
    required String content,
    required List<ActiveProblemView> activeProblems,
    required TeachingSubphase? currentSubphase,
    required BeginnerLevel? beginnerLevel,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    // 6. 跨轮次诊断锁定注入（若有活跃症候）
    // trainingSyndromeId 用于 appendTeachingHistory 写 training 记录（批次1-7-2）
    String? trainingSyndromeId;
    if (activeProblems.isNotEmpty) {
      // 6.1 focus-resolver 6 项校验门控
      final aiSuggestedFocusId = await _diagnosisRepo.getLatestTeachingFocus(
        sessionId,
      );
      final focusHistory = await _buildFocusHistory(sessionId);
      final userFocusOverride = _parseUserFocusFromMessage(
        content,
        activeProblems,
      );

      // 转换为 focus-resolver 输入类型
      final focusProblems = activeProblems
          .map(
            (p) => FocusProblem(
              syndromeId: p.syndromeId,
              syndromeName: p.syndromeName,
              severity: Severity.fromString(p.severity) ?? Severity.l2,
              confirmationStatus:
                  ConfirmationStatus.fromString(p.confirmationStatus) ??
                  ConfirmationStatus.suspected,
              status: 'active',
              confirmedAt: p.confirmedAt,
            ),
          )
          .toList();

      final focusResult = focus.resolveTeachingFocus(
        focus.ResolveFocusInput(
          problems: focusProblems,
          aiSuggestedFocusId: aiSuggestedFocusId,
          userFocusOverride: userFocusOverride,
          subphase: currentSubphase,
          focusHistory: focusHistory
              .map(
                (h) => focus.FocusHistoryEntry(
                  focusId: h.focusId,
                  timestamp: h.timestamp,
                ),
              )
              .toList(),
          // 批次60：学员当前技能层级（fallback 软优先层级≤当前+1）
          studentSkillLevel: skillLevelForBeginner(beginnerLevel),
        ),
      );

      // 6.2 若有拒绝理由，注入提示给 AI
      if (focusResult.rejectReason != null) {
        messages.add(
          ChatMessage(
            role: 'system',
            content: '# Focus 切换提示\n\n${focusResult.rejectReason}',
          ),
        );
      }

      if (focusResult.activatedFocusId != null) {
        trainingSyndromeId = focusResult.activatedFocusId;
      }

      // 6.3 训练评估注入
      final focusSyndromeId =
          focusResult.activatedFocusId ?? activeProblems.first.syndromeId;
      final focusProblem = activeProblems
          .where((p) => p.syndromeId == focusSyndromeId)
          .firstOrNull;
      if (focusProblem != null) {
        // 批次60：介入级别注入（逐步撤除脚手架，独立于训练评估）
        // D3（批次8）：综合 severity + 复发信号；7.2（批次16）：performance_gate 表现感知
        try {
          // 7.2：一次拉取训练历史得表现（totalCount = 训练次数），
          // 替代 countTrainingForSyndrome 单独查询，避免「次数+表现」双倍 I/O
          final performance = await computeTrainingPerformance(
            _studentModelRepo,
            sessionId,
            focusSyndromeId,
          );
          final trainingCount = performance?.totalCount ?? 0;
          // D3：复发信号 = 该症候曾毕业（跨 session resolved），本 session 又活跃
          bool relapse = false;
          try {
            relapse = await _diagnosisRepo.hasResolvedHistory(focusSyndromeId);
          } catch (e) {
            debugPrint('[SafeRun] 复发信号查询失败降级 false: $e');
          }
          final currentSeverity =
              Severity.fromString(focusProblem.severity) ?? Severity.l2;
          final intervention = interventionLevelForTrainingCount(
            trainingCount,
            currentSeverity: currentSeverity,
            relapse: relapse,
            performance: performance,
          );
          // D3 / 7.2：修正原因说明（命中时注入，帮助 AI 校准教学力度）
          final adjustmentNote = _buildInterventionAdjustmentNote(
            trainingCount: trainingCount,
            currentSeverity: currentSeverity,
            relapse: relapse,
            performance: performance,
          );
          messages.add(
            ChatMessage(
              role: 'system',
              content:
                  '# 训练介入级别（逐步撤除脚手架）\n\n'
                  '本症候已训练 $trainingCount 次，本轮采用介入级别：'
                  '${intervention.value}（${intervention.label}）。'
                  '${adjustmentNote.isEmpty ? '' : '$adjustmentNote\n'}'
                  '按级别组织训练：\n'
                  '- I do：给完整示范参考 + 常见错误提醒 + 自查锚点，让学员先看懂\n'
                  '- We do：常见错误提醒 + 自查锚点保留，示范改为引导方向，学员动手写为主\n'
                  '- You do：只给自查锚点，不做示范，学员独立练习 + 你来点评\n'
                  '（本注入是参考输入，具体执行由你按学员情况判断）',
            ),
          );
        } catch (e) {
          debugPrint('[SafeRun] 训练评估注入失败不阻断主流程: $e');
        }
        try {
          final trainingInput = await buildTrainingInputForActiveSyndrome(
            _studentModelRepo,
            sessionId,
            focusSyndromeId,
            ActiveProblemMeta(
              currentSeverity:
                  Severity.fromString(focusProblem.severity) ?? Severity.l2,
            ),
            // v19：传 DiagnosisRepo 让 startingTeachingState 优先读持久化起点
            diagnosisRepo: _diagnosisRepo,
          );
          if (trainingInput != null) {
            final summary = buildEvaluationSummary(
              focusSyndromeId,
              trainingInput,
            );
            // T2 修复：FSM 状态迁移时写回 DB（与 EvaluationService 同款逻辑）
            if (summary.teachingState != trainingInput.teachingState) {
              try {
                await _diagnosisRepo.updateTeachingState(
                  sessionId,
                  focusSyndromeId,
                  summary.teachingState.value,
                );
                // 正向达标：mastered → 立即解锁
                if (summary.teachingState == TeachingState.mastered) {
                  try {
                    await _diagnosisRepo.resolveSyndromesBatch(sessionId, [
                      focusSyndromeId,
                    ]);
                  } catch (e) {
                    debugPrint('[SafeRun] resolveSyndromesBatch 内层: $e');
                  }
                  // B1：达标→解锁同时插入阶段总结卡，汇总该症候进展
                  await _insertPhaseSummaryOnMastered(
                    sessionId,
                    focusSyndromeId,
                    focusProblem.syndromeName,
                    trainingInput.passRateInput.totalCount,
                  );
                }
              } catch (e) {
                debugPrint('[SafeRun] FSM updateTeachingState 外层: $e');
              }
            }
            if (summary.contextInjection.isNotEmpty) {
              messages.add(
                ChatMessage(role: 'system', content: summary.contextInjection),
              );
            }
          }
          // T1 修复：注入当前焦点症候的完整训练教学知识
          // （核心本质/教学要点/常见误区/严重度参考/教学素材库）
          try {
            final trainingKnowledge = getTrainingContent([focusSyndromeId]);
            if (trainingKnowledge.isNotEmpty) {
              markStage(BudgetStageNames.trainingKnowledge);
              messages.add(
                ChatMessage(role: 'system', content: trainingKnowledge),
              );
            }
          } catch (e) {
            debugPrint('[SafeRun] 知识库注入失败不阻断主流程: $e');
          }
        } catch (e) {
          debugPrint('[SafeRun] 训练上下文构建失败不阻断主流程: $e');
        }
      }

      // 6.4 L3 结构化症候详情
      final activeSyndromeViews = activeProblems
          .map(
            (p) => ActiveSyndromeView(
              syndromeId: p.syndromeId,
              syndromeName: p.syndromeName,
              severity: Severity.fromString(p.severity) ?? Severity.l2,
              confirmationStatus: ConfirmationStatus.fromString(
                p.confirmationStatus,
              ),
            ),
          )
          .toList();

      // 2026-08-18 批次：文笔画像→技法旁路路由（设计 docs/2026-08-18-*.md）
      // 五维非健康值→文笔层技法候选，门控通过才注入；失败不阻断主流程
      String? styleTechniqueSection;
      try {
        final latestStyleProfile = await _studentModelRepo
            .getLatestStyleProfile();
        final suggestion = routeStyleTechniques(
          styleProfile: latestStyleProfile,
          activeProblems: activeSyndromeViews,
          // 症候级 mastered → 技法集合派生（active_problem.teaching_state）
          masteredTechniqueIds: deriveMasteredTechniqueIds(activeProblems),
          focusSyndromeId: focusResult.activatedFocusId,
        );
        styleTechniqueSection = formatStyleTechniqueSection(suggestion);
      } catch (e) {
        debugPrint('[SafeRun] 文笔画像旁路路由失败不阻断主流程: $e');
      }

      final structuredContext = buildStructuredSyndromeContext(
        activeSyndromeViews,
        activeFocus: ActiveFocusContext(
          focusId: focusResult.activatedFocusId,
          source: _mapFocusSource(focusResult.source),
          reason: focusResult.reason,
        ),
        styleTechniqueSection: styleTechniqueSection,
      );
      markStage(BudgetStageNames.l3Structure);
      messages.add(ChatMessage(role: 'system', content: structuredContext));

      // 批次60：学员技能层级软引导（AI 自主判断优先，仅提示不硬性）
      final studentSkillLevel = skillLevelForBeginner(beginnerLevel);
      if (studentSkillLevel != null) {
        messages.add(
          ChatMessage(
            role: 'system',
            content:
                '# 学员技能层级\n\n'
                '学员当前技能层级：${studentSkillLevel.value} ${studentSkillLevel.label}。\n'
                '反馈建议：优先给当前层级+1 以内的问题做重点反馈；'
                '若诊断出更高层级的问题可以提及，但作为次要项，不要一次展开超出学员理解范围的内容。',
          ),
        );
      }
    }
    return trainingSyndromeId;
  }
}
