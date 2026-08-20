// ─────────────────────────────────────────────────────────────
// chat_service_send 步骤块提取：chat_service_send_persist.dart（R-019 ≤300 行）
// 逐字迁移自 chat_service_send.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_service.dart';

extension ChatServiceSendPersist on ChatService {
  Future<void> _commitDiagnosisAndSuggestions({
    required String sessionId,
    required ParsedDiagnosis? diagnosis,
    required String messageId,
    required ReferenceItem? primaryRef,
    required TeacherResult? teacherResult,
    required bool rapidFire,
    required bool flowBypassed,
    required List<GenUiComponent>? genuiComponents,
  }) async {
      // B-1：若有 GenUI 组件，确定性插入 genui 卡片（不阻断主流程）
      if (genuiComponents != null && genuiComponents.isNotEmpty) {
        try {
          await insertGenuiCard(
            _sessionRepo,
            sessionId,
            GenuiCardPayload(components: genuiComponents),
          );
        } catch (e) {
          debugPrint('[SafeRun] GenUI 卡片插入失败不阻断主流程: $e');
        }
      }

      // 11. 若有诊断：commitDiagnosisWithHistory + phase-mapper resolver
      if (diagnosis != null) {
        try {
          await _diagnosisService.commitDiagnosisWithHistory(
            DiagnosisInput(
              sessionId: sessionId,
              messageId: messageId,
              syndromes: diagnosis.syndromes.map((s) => s.toJson()).toList(),
              suggestedActions: diagnosis.suggestedActions,
              confidence: diagnosis.confidence,
              rootCauseAnalysis: diagnosis.rootCauseAnalysis,
              nextFocus: diagnosis.nextFocus,
              feedbackSummary: diagnosis.feedbackSummary,
              currentTeachingFocusId: diagnosis.currentTeachingFocusId,
              focusReason: diagnosis.focusReason,
              teachingMode: diagnosis.teachingMode?.value,
              targetRefType: primaryRef?.refType,
              targetRefId: primaryRef?.refId,
            ),
          );

          // 批次1（C3）：新诊断提交 = 旧训练轮终结 → 重置子阶段，防 feedback 残留
          //（阶段不变时 subphase 不再永久残留；阶段变化路径也会重置，双保险）
          try {
            await _stateRepo.updateSubphase(sessionId, null);
          } catch (e) {
            debugPrint('[SafeRun] 诊断后重置子阶段失败: $e');
          }

          // phase-mapper resolver 接线 + M4-A/M4-B/M4-C 阶段迁移（批次6 D1 抽取为共享方法）
          // 供 sendMessage 与 commitDiagnosisFromContent 复用，保证两条诊断路径行为一致
          await _applyPhaseMigration(
            sessionId: sessionId,
            diagnosis: diagnosis,
          );

          // AUDIT-REF-5: 诊断完成后确定性插入诊断结果卡片
          // 真源：chat-service.ts L742-755
          try {
            await insertDiagnosisResultCard(
              _sessionRepo,
              sessionId,
              DiagnosisResultCardPayload(
                syndromeCount: diagnosis.syndromes.length,
                syndromes: diagnosis.syndromes
                    .map(
                      (s) => DiagnosisSyndromeCard(
                        syndromeId: s.syndromeId,
                        name: s.name,
                        severity: s.severity.value,
                        evidenceCount: s.evidence.length,
                      ),
                    )
                    .toList(),
                suggestedActions: diagnosis.suggestedActions,
                confidence: diagnosis.confidence,
                diagnosisId: messageId,
              ),
            );
          } catch (e) {
            debugPrint('[SafeRun] 诊断卡片插入失败不阻断主流程: $e');
          }

          // 批次53：诊断附带 style_profile 时沉淀写作风格画像
          // 独立 try-catch（落库失败不阻断诊断主流程）
          final styleProfile = diagnosis.styleProfile;
          if (styleProfile != null) {
            try {
              await _studentModelRepo.updateStyleProfile(
                sessionId,
                styleProfile,
              );
            } catch (e) {
              debugPrint('[SafeRun] 风格画像落库失败不阻断主流程: $e');
            }
          }
        } catch (e) {
          debugPrint('[SafeRun] 诊断写入失败不阻断消息存储: $e');
        }
      }

      // R6：Diagnosis 分支 Teacher suggestion 写入（两分支复用 persistTeacherSuggestion）
      // 真源：chat-service.ts L762-765（位于 if(diagnosis) 块外，独立 try-catch）
      if (teacherResult != null) {
        try {
          final suggestionId = await persistTeacherSuggestion(
            _teacherSuggestionRepo,
            teacherResult,
            sessionId,
            messageId,
            'diagnosis',
            isRapidFire: rapidFire,
          );
          // D6：建议落库成功后，写 teacher_suggestion 卡片消息（症候名称而非代号）
          // 批次1（O1）：升级阀绕过心流窗口时以轻量提示替代独立卡片——建议文本已
          // 并入 assistant 消息（combinedContent），不再重复插卡打断写作心流
          if (suggestionId != null && !flowBypassed) {
            final targetTask = teacherResult.trainingTask;
            String? targetName;
            if (targetTask?.targetSyndromeId != null && diagnosis != null) {
              targetName = diagnosis.syndromes
                  .where((s) => s.syndromeId == targetTask!.targetSyndromeId)
                  .map((s) => s.name)
                  .firstOrNull;
            }
            try {
              await insertTeacherSuggestionCard(
                _sessionRepo,
                sessionId,
                TeacherSuggestionCardPayload(
                  suggestionId: suggestionId,
                  teachingDecision: teacherResult.teachingDecision,
                  naturalLanguage: teacherResult.naturalLanguage,
                  taskType: targetTask?.taskType ?? '',
                  taskDescription: targetTask?.taskDescription ?? '',
                  difficulty: targetTask?.difficulty ?? '',
                  evaluationCriteria:
                      targetTask?.evaluationCriteria ?? const [],
                  targetSyndromeId: targetTask?.targetSyndromeId,
                  targetSyndromeName: targetName,
                  source: 'diagnosis',
                  locationMarks: teacherResult.locationMarks,
                ),
              );
            } catch (e) {
              debugPrint('[SafeRun] 建议卡片插入失败不阻断主流程: $e');
            }
          }
        } catch (e) {
          debugPrint('[SafeRun] Teacher suggestion 落库失败: $e');
        }
      }
  }

  Future<void> _handleTrainingResult({
    required String sessionId,
    required TeachingSubphase? currentSubphase,
    required String displayContent,
    required String? trainingSyndromeId,
    required List<ActiveProblemView> activeProblems,
    required SendMessageCallbacks callbacks,
  }) async {
      // 11. 训练结果解析 + teaching_history 写入
      // 真源：chat-service.ts L767-793
      // 条件：subphase == FEEDBACK 且 parseTrainingResult 命中
      // trainingSyndromeId 来自 focus-resolver（步骤 6.2）
      // 注意：基于 displayContent（不含诊断块），避免误触发
      if (currentSubphase == TeachingSubphase.feedback) {
        // D8 轻量观测：评估顺序（学员自评 → 改前改后对比 → AI 评估）
        // 约束源为 skill 指令（skill_registry.dart 阶段3），非代码强制；
        // 仅 debug 留痕观测回复是否按顺序走全三步，不改变行为。
        _observeEvaluationOrder(displayContent);
        final trainingResult = _diagnosis.parseTrainingResult(displayContent);
        if (trainingResult != null) {
          try {
            if (trainingSyndromeId != null) {
              await _studentModelRepo.appendTeachingHistory(sessionId, {
                'type': 'training',
                'syndromeId': trainingSyndromeId,
                'result': trainingResult.value,
                'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                'sessionId': sessionId,
              });
              // T3 修复：训练记录写入后，用新历史重跑 FSM 并持久化状态
              // 步骤 6.3 在 LLM 调用前评估，此时训练记录尚未写入；
              // 训练完成后需重评估，确保 FSM 状态反映最新训练结果。
              try {
                final problem = activeProblems
                    .where((p) => p.syndromeId == trainingSyndromeId)
                    .firstOrNull;
                if (problem != null) {
                  final reEvalInput = await buildTrainingInputForActiveSyndrome(
                    _studentModelRepo,
                    sessionId,
                    trainingSyndromeId,
                    ActiveProblemMeta(
                      currentSeverity:
                          Severity.fromString(problem.severity) ?? Severity.l2,
                    ),
                    diagnosisRepo: _diagnosisRepo,
                  );
                  if (reEvalInput != null) {
                    final reEvalSummary = buildEvaluationSummary(
                      trainingSyndromeId,
                      reEvalInput,
                    );
                    if (reEvalSummary.teachingState !=
                        reEvalInput.teachingState) {
                      await _diagnosisRepo.updateTeachingState(
                        sessionId,
                        trainingSyndromeId,
                        reEvalSummary.teachingState.value,
                      );
                      if (reEvalSummary.teachingState ==
                          TeachingState.mastered) {
                        try {
                          await _diagnosisRepo.resolveSyndromesBatch(
                            sessionId,
                            [trainingSyndromeId],
                          );
                        } catch (e) {
                          debugPrint('[SafeRun] 重评估resolveSyndromesBatch: $e');
                        }
                        // B1：达标→解锁同时插入阶段总结卡，汇总该症候进展
                        await _insertPhaseSummaryOnMastered(
                          sessionId,
                          trainingSyndromeId,
                          problem.syndromeName,
                          reEvalInput.passRateInput.totalCount,
                        );
                      }
                    }
                  }
                }
              } catch (e) {
                debugPrint('[SafeRun] 重评估失败不阻断主流程: $e');
              }
            }
          } catch (e) {
            debugPrint('[SafeRun] 训练记录写入失败: $e');
          }
          // 批次1（C3）：训练轮终结（反馈已解析命中）→ 重置子阶段，防 feedback 残留
          // 后续含"达标/未达标"字样消息不再误归属旧训练轮
          try {
            await _stateRepo.updateSubphase(sessionId, null);
          } catch (e) {
            debugPrint('[SafeRun] 训练轮终结重置子阶段失败: $e');
          }
          // onTrainingResult 回调：通知 UI 展示训练结果（T3 接线）
          callbacks.onTrainingResult?.call(trainingResult);
        }
      }
  }

}
