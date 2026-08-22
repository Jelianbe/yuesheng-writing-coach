// ─────────────────────────────────────────────────────────────
// chat_service_diagnosis 方法级拆分：chat_service_diagnosis_support.dart（R-019 ≤300 行）
// 逐字迁移自 chat_service_diagnosis.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_service.dart';

extension ChatServiceDiagnosisSupport on ChatService {
  /// 阶段迁移统一处理（批次6 D1）——AI 驱动 resolver + M4-A 自动迁移 + M4-C 达标率校验
  ///
  /// 供 [sendMessage] 与 [commitDiagnosisFromContent] 复用，保证两条诊断路径行为一致：
  ///   - sendMessage：单次诊断（≤4000 字）
  ///   - commitDiagnosisFromContent：超长分块诊断（>4000 字，progressive 路径）
  ///
  /// 内部职责（均 try/catch 包裹，失败不阻断主流程）：
  ///   1. diagnosis 输出 suggestedPhase/suggestedBeginnerLevel 时 → phase-mapper resolver
  ///   2. effectivePhase → M4-B validatePhaseTransition 校验 → updatePhase + 子阶段重置 + 升级卡片
  ///   3. effectiveBeginnerLevel → updateBeginnerLevel
  ///   4. 所有活跃症候已 resolved → M4-A 自动迁移（M4-C 达标率 ≥ phasePassRate 才放行）
  Future<void> _applyPhaseMigration({
    required String sessionId,
    required ParsedDiagnosis? diagnosis,
  }) async {
    // 批次1（C5/H3）：路径1（AI 驱动）成功迁移后，路径2（M4-A 自动）不得
    // 再无条件继续，防止同轮链式双跳（如 P1→P2→P3）
    var path1Migrated = false;
    // ── 1. AI 驱动路径：phase-mapper resolver ──
    if (diagnosis != null &&
        (diagnosis.suggestedPhase != null ||
            diagnosis.suggestedBeginnerLevel != null)) {
      try {
        final currentState = await _stateRepo.getTeachingState(sessionId);
        final currentBeginnerLevelStr = currentState?.beginnerLevel;
        final currentBeginnerLevel = BeginnerLevel.fromString(
          currentBeginnerLevelStr,
        );

        // 计算连续失败训练次数（仅 N3 触发降级检查时需要）
        int consecutiveFailedTrainings = 0;
        if (currentBeginnerLevel == BeginnerLevel.n3Diagnose) {
          try {
            final allHistory = await _studentModelRepo.getTeachingHistory(
              sessionId,
            );
            final activeProblems = await _diagnosisRepo.listActiveProblems(
              sessionId,
            );
            final focusSyndromeId =
                diagnosis.currentTeachingFocusId ??
                activeProblems.firstOrNull?.syndromeId;
            if (focusSyndromeId != null) {
              final trainingRecords =
                  allHistory
                      .where(
                        (r) =>
                            r['type'] == 'training' &&
                            r['syndromeId'] == focusSyndromeId,
                      )
                      .toList()
                    ..sort((a, b) {
                      final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
                      final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
                      return ta.compareTo(tb);
                    });
              for (int i = trainingRecords.length - 1; i >= 0; i--) {
                if (trainingRecords[i]['result'] == 'failed') {
                  consecutiveFailedTrainings++;
                } else {
                  break;
                }
              }
            }
          } catch (e) {
            debugPrint('[SafeRun] resolver 训练记录读取失败: $e');
          }
        }

        final resolverResult = resolvePhaseMapper(
          PhaseMapperInput(
            currentPhase: TeachingPhase.fromString(currentState?.currentPhase),
            currentBeginnerLevel: currentBeginnerLevel,
            suggestedPhase: diagnosis.suggestedPhase,
            suggestedBeginnerLevel: diagnosis.suggestedBeginnerLevel,
            consecutiveFailedTrainings: consecutiveFailedTrainings,
          ),
        );

        final effectivePhase = resolverResult.effectivePhase;
        if (effectivePhase != null) {
          // M4-B: 阶段迁移合法性校验——拦截非法跳级/回退
          // （如 P2→P0、P3→P1 等），仅放行相邻递进或 P4→P2 回退
          final prevPhaseValue = currentState?.currentPhase;
          final currentPhaseForValidation =
              TeachingPhase.fromString(prevPhaseValue) ??
              TeachingPhase.p0Engage;
          if (validatePhaseTransition(
            currentPhaseForValidation,
            effectivePhase,
          )) {
            await _stateRepo.updatePhase(sessionId, effectivePhase.value);
            // 批次9：阶段真实变化时插入 phase_upgrade 卡片（对齐 RN insertPhaseUpgradeCard）
            if (prevPhaseValue != effectivePhase.value) {
              path1Migrated = true;
              // M4-D: 阶段迁移时重置子阶段，避免上一阶段子阶段残留
              await _stateRepo.updateSubphase(sessionId, null);
              try {
                await insertPhaseUpgradeCard(
                  _sessionRepo,
                  sessionId,
                  PhaseUpgradeCardPayload(
                    from: prevPhaseValue ?? TeachingPhase.p0Engage.value,
                    to: effectivePhase.value,
                  ),
                );
              } catch (e) {
                debugPrint('[SafeRun] 卡片插入失败不影响阶段迁移: $e');
              }
            }
          } else {
            debugPrint(
              '[SafeRun] M4-B: 阶段迁移非法已拦截 '
              '$currentPhaseForValidation → $effectivePhase',
            );
          }
        }
        if (resolverResult.effectiveBeginnerLevel != null) {
          await _stateRepo.updateBeginnerLevel(
            sessionId,
            resolverResult.effectiveBeginnerLevel!.value,
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] resolver 失败不阻断主流程: $e');
      }
    }

    // 批次1（C5/H3）：路径1 已成功迁移 → 直接返回，路径2 仅当路径1 无有效迁移时评估
    if (path1Migrated) return;

    // ── 2. 自动迁移路径：M4-A + M4-C 达标率校验 ──
    // 所有活跃症候已 resolved 时，代码侧主动推进阶段（不依赖 AI suggestedPhase）
    // 守卫：仅在 P2 及以后触发（P0/P1 阶段迁移由 AI suggested_phase 驱动）
    // M4-C: passRate >= phasePassRate(0.7) 才允许迁移，避免手动标记完成跳过训练升阶
    try {
      final remaining = await _diagnosisRepo.listActiveProblems(sessionId);
      if (remaining.isEmpty) {
        final ts = await _stateRepo.getTeachingState(sessionId);
        final currentPhase =
            TeachingPhase.fromString(ts?.currentPhase) ??
            TeachingPhase.p0Engage;
        if (currentPhase != TeachingPhase.p0Engage &&
            currentPhase != TeachingPhase.p1World) {
          final evalService = EvaluationService(
            _diagnosisRepo,
            _studentModelRepo,
          );
          final passRate = await evalService.computePassRateForPhaseMigration(
            sessionId,
          );
          if (passRate >= EvaluationThresholds.phasePassRate) {
            final next = nextPhase(currentPhase);
            // M4-B: nextPhase 已保证相邻递进，validatePhaseTransition 双重校验
            if (next != null && validatePhaseTransition(currentPhase, next)) {
              await _stateRepo.updatePhase(sessionId, next.value);
              await _stateRepo.updateSubphase(sessionId, null);
              try {
                await insertPhaseUpgradeCard(
                  _sessionRepo,
                  sessionId,
                  PhaseUpgradeCardPayload(
                    from: currentPhase.value,
                    to: next.value,
                  ),
                );
              } catch (e) {
                debugPrint('[SafeRun] 自动迁移卡片插入失败: $e');
              }
            }
          } else {
            debugPrint(
              '[SafeRun] M4-C: 达标率 $passRate < '
              '${EvaluationThresholds.phasePassRate}，阶段暂不迁移',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[SafeRun] 自动迁移失败不阻断主流程: $e');
    }
  }

  /// 7.2（批次16）：介入级别修正原因说明。
  ///
  /// D3（复发/L3）或 performance_gate（G1-G5）命中时返回一句说明，
  /// 供介入级别注入消息标注修正原因，帮助 AI 校准教学力度；未命中返回空串。
  /// 规则顺序与 interventionLevelForTrainingCount 完全一致（D3 > G1 > G2 > G3 > 次数 > G4 > G5）。
  String _buildInterventionAdjustmentNote({
    required int trainingCount,
    required Severity currentSeverity,
    required bool relapse,
    required TrainingPerformance? performance,
  }) {
    // D3（批次8）：复发 / L3 无条件回退 I do（最高优先级）
    if (relapse) return '（本轮因复发回退脚手架到 I do）';
    if (currentSeverity == Severity.l3) {
      return '（本轮因严重度 L3 回退脚手架到 I do）';
    }
    if (performance == null) return '';

    // 基础次数档位（与 interventionLevelForTrainingCount 同口径）
    final base = trainingCount >= 4
        ? InterventionLevel.youDo
        : trainingCount >= 2
        ? InterventionLevel.weDo
        : InterventionLevel.iDo;

    // 延迟撤脚手架（保守）
    if (performance.consecutiveFails >= 3) {
      return '（连续 ${performance.consecutiveFails} 次未达标，回退脚手架到 I do）';
    }
    if (performance.passRate < 0.5 && base != InterventionLevel.iDo) {
      final pct = (performance.passRate * 100).round();
      return '（历史达标率 $pct%，回退脚手架一档）';
    }
    if (performance.consecutiveFails >= 2 && base == InterventionLevel.youDo) {
      return '（最近两次未达标，暂不进入独立练习）';
    }

    // 提前撤脚手架（正向）
    if (base == InterventionLevel.iDo &&
        performance.totalCount >= 1 &&
        performance.consecutivePasses == performance.totalCount) {
      return '（首次训练即通过，提前进入引导练习）';
    }
    if (base == InterventionLevel.weDo &&
        performance.totalCount >= 2 &&
        performance.consecutivePasses == performance.totalCount) {
      return '（连续训练全部通过，提前进入独立练习）';
    }

    return '';
  }
}
