part of 'chat_service.dart';

extension ChatServiceDiagnosis on ChatService {
  /// 批次64（B62f）：声线漂移提示上下文——引导 AI 以提问方式温和指出其中一条
  String _buildDriftHintContext(List<String> hints) {
    return '## 声线漂移检测（L3→L1 实时反馈）\n\n'
        '检测到写作特征与既有风格基线出现明显偏差。\n'
        '若合适，请用**提问的方式**温和地向学员指出**其中一条**'
        '（结合具体数字，如"你的句子长度通常 15-20 字，但这部分平均只有 8 字——'
        '是刻意加速，还是无意识的变化？"），一次只问一个点，不展开成诊断。\n'
        '偏差项：\n- ${hints.join('\n- ')}';
  }

  /// A6：时序知识图谱事实提取协议（诊断章节正文时注入）
  ///
  /// 指导 AI 在诊断回复中附加 [YS_FACT] 块，提取人物/事件/支线三类结构化事实，
  /// 供系统 upsert 到 TKG 三表，驱动时序矛盾/因果链/情节闭环检测。
  /// 与 [YS_DIAGNOSIS]、[YS_ENTITY] 并列独立，输出顺序排在最后。
  String _buildFactProtocolContext() {
    return '## 时序知识图谱事实沉淀（输出顺序约束）\n\n'
        '【输出顺序】若同时输出诊断块、实体块与事实块，**必须严格按此顺序**：\n'
        '  1. [YS_DIAGNOSIS] 症候块（若诊断要求）；\n'
        '  2. [YS_ENTITY] 实体记忆块；\n'
        '  3. [YS_FACT] 事实块（本条）；\n'
        '  4. 之后再写面向学员的自然语言诊断与教学建议。\n\n'
        '若章节正文出现值得长期记住的**结构化事实**（人物属性断言、关键事件、'
        '支线收束），请在回复中附加 [YS_FACT] JSON 块，供系统沉淀为时序知识图谱。'
        '增量更新：仅记录当前章节新增或变化的事实，不重复已沉淀内容。'
        '完全无新事实（无人物属性变化、无关键事件、无支线进展）可不输出该块。\n\n'
        '格式：\n'
        '[YS_FACT]\n'
        '{\n'
        '  "characters": [\n'
        '    {"name":"人物名","assertions":[\n'
        '      {"attribute":"属性名(如独生子女状态/性格/职业/身份)","value":"属性值",'
        '"chapter":3}\n'
        '    ]}\n'
        '  ],\n'
        '  "events": [\n'
        '    {"name":"事件名","event_type":"决定|转折|突发|冲突|日常",'
        '"chapter":5,"participants":["人物名"],"description":"一句话概述",'
        '"cause_event_name":"触发本事件的前因事件名（无前因则省略）"}\n'
        '  ],\n'
        '  "subplots": [\n'
        '    {"name":"支线名","introduced_chapter":3,"resolved_chapter":null,'
        '"description":"支线梗概"}\n'
        '  ]\n'
        '}\n'
        '[/YS_FACT]\n\n'
        '规则：\n'
        '- characters：记录本章新增或变化的人物属性断言。attribute 用规范属性名'
        '（如「独生子女状态」「性格」「职业」「身份」「关系」），value 为原文可验证的具体值，'
        'chapter 为该断言出现的章节序号。同一人物可多条断言。\n'
        '- events：记录关键事件（决定/转折/突发类必记，冲突/日常视重要性）。'
        'event_type 从「决定|转折|突发|冲突|日常」中选一。participants 为参与人物名列表。'
        'description 一句话概述事件（≤30字）。'
        'cause_event_name 填触发本事件的前因事件名（须与既有事件 name 一致），'
        '用于构建因果链；无前因触发（如开篇事件）则省略此字段。\n'
        '- subplots：记录支线引入或回收。introduced_chapter 填首次引入章节，'
        'resolved_chapter 填本章回收章节（未回收填 null）。'
        '若本章回收了既有支线，必须输出该条并填入 resolved_chapter。\n'
        '- **完整性硬约束**：[YS_FACT] 包裹的 JSON 必须语法合法、完整闭合。'
        '如担心篇幅，请压缩自然语言诊断说明以保证事实块完整。';
  }

  /// 批次74：快速读取某章节对应手稿下的实体数（用于 combinedContent 空时判真故障）
  Future<int> _readOutlineEntityCount(String chapterId) async {
    try {
      final outlineService = _ensureOutlineService();
      if (outlineService == null) return 0;
      final chapter = await _chapterRepo.getChapter(chapterId);
      if (chapter == null) return 0;
      // 复用已公开 buildEntityIndexContext 非空推 count
      final ctx = await outlineService.buildEntityIndexContext(
        chapter.manuscriptId,
      );
      if (ctx == null) return 0;
      // 保守估算：每行实体前缀算 1 个
      return '\n$ctx'.split('\n- [').length - 1;
    } catch (e) {
      debugPrint('[SafeRun] 大纲实体检索计数失败: $e');
      return 0;
    }
  }

  /// 处理分块诊断生成的完整 AI 输出（D4-A）
  ///
  /// 当 runProgressiveDiagnosis 返回非 null 时，由 WritingCoachPanel 调用。
  /// 复用 sendMessage 的步骤 9-11（解析 + 持久化 + 卡片），不含 Teacher 触发。
  Future<String> commitDiagnosisFromContent({
    required String sessionId,
    required String fullContent,
  }) async {
    // 步骤 9: 解析诊断
    final rawParse = parseDiagnosis(fullContent);
    String displayContent = rawParse.displayContent;
    ParsedDiagnosis? diagnosis = rawParse.diagnosis;

    if (diagnosis != null) {
      final startIndex = fullContent.indexOf(kDiagnosisStart);
      final endIndex = fullContent.indexOf(
        kDiagnosisEnd,
        startIndex + kDiagnosisStart.length,
      );
      if (startIndex != -1 && endIndex != -1) {
        final jsonStr = fullContent
            .substring(startIndex + kDiagnosisStart.length, endIndex)
            .trim();
        try {
          final rawJson = jsonDecode(jsonStr);
          final validation = validateDiagnosisOutput(
            rawParse.displayContent,
            rawJson,
          );
          displayContent = validation.displayContent;
          diagnosis = validation.diagnosis;
        } catch (e) {
          debugPrint(
            '[SafeRun] commitDiagnosisFromContent JSON 解析失败沿用 rawParse: $e',
          );
        }
      }
    }

    // 批次74 A1：D4-A 渐进诊断也沉淀大纲 + 写确认卡
    // （commitDiagnosisFromContent 不传 primaryRef，内部会从 session 查当前章节主引用；
    //   无装配/无大纲块/非章节 → 静默跳过）
    await _applyOutlineEntitiesFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
    );

    // A6：D4-A 路径也沉淀事实到 TKG 三表
    await _applyFactExtractionFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
    );

    // 批次74：剥离 [YS_ENTITY] 协议块（防原始 JSON 落库）
    displayContent = stripOutlineBlock(displayContent);
    // A6：剥离 [YS_FACT] 协议块
    displayContent = stripFactBlock(displayContent);

    // 步骤 10: 写入 assistant 消息
    if (displayContent.trim().isEmpty) {
      displayContent = '诊断完成';
    }
    final messageId = await _sessionRepo.addMessage(
      sessionId,
      'assistant',
      displayContent,
    );
    debugPrint(
      '[ChatService] commitDiagnosisFromContent: assistant 消息已写入 | messageId=$messageId | contentLen=${displayContent.length}',
    );

    // 步骤 11: 持久化诊断结果 + 卡片
    if (diagnosis != null) {
      // D4 修复：从 session 引用解析 primaryRef，传入 targetRefType/targetRefId
      String? d4TargetRefType;
      String? d4TargetRefId;
      try {
        final refs = await _referenceRepo.listReferencesOfSession(sessionId);
        if (refs.isNotEmpty) {
          final primary = refs.firstWhere(
            (r) => r.isPrimary == 1,
            orElse: () => refs.first,
          );
          d4TargetRefType = primary.refType;
          d4TargetRefId = primary.refId;
        }
      } catch (e) {
        debugPrint('[SafeRun] commitDiagnosisFromContent 引用查询失败: $e');
      }

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
            targetRefType: d4TargetRefType,
            targetRefId: d4TargetRefId,
          ),
        );

        // 批次10（C3）：D4-A 分块诊断同样 = 旧训练轮终结 → 重置子阶段，
        // 与 sendMessage 主路径（L1400-1406）对称，防 feedback 残留
        try {
          await _stateRepo.updateSubphase(sessionId, null);
        } catch (e) {
          debugPrint('[SafeRun] commitDiagnosisFromContent 诊断后重置子阶段失败: $e');
        }

        // S5 修复：D4-A 路径也沉淀 style_profile（与 sendMessage 主路径对齐）
        if (diagnosis.styleProfile != null) {
          try {
            await _studentModelRepo.updateStyleProfile(
              sessionId,
              diagnosis.styleProfile!,
            );
          } catch (e) {
            debugPrint('[SafeRun] commitDiagnosisFromContent 风格画像沉淀失败: $e');
          }
        }

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
          debugPrint('[SafeRun] commitDiagnosisFromContent 卡片插入失败: $e');
        }

        // 批次6 D1：分块诊断路径复用阶段迁移（resolver + M4-A 自动迁移 + M4-C 达标率校验），
        // 与 sendMessage 单次诊断路径行为一致，超长章节诊断完成后也能推进阶段/升级卡片
        await _applyPhaseMigration(sessionId: sessionId, diagnosis: diagnosis);
      } catch (e) {
        debugPrint('[SafeRun] commitDiagnosisFromContent 诊断写入失败: $e');
      }
    }

    // B1：D4-A 分块诊断链路必为诊断；成败记录 → 失败卡阈值门控
    await _recordDiagnosisOutcome(
      sessionId,
      attempted: true,
      success: diagnosis != null,
    );

    return messageId;
  }

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

  /// 大纲实体提取 + 确认卡写入（批次72/73/74 D4-A 共用）
  ///
  /// 失败/未装配/无大纲块/非章节主引用 → 静默跳过不抛。
  /// 优先使用入参传入的 primaryRef（sendMessage 路径）；
  /// 若未传（commitDiagnosisFromContent 路径）则从 session 的当前引用取。
  Future<void> _applyOutlineEntitiesFromContent({
    required String sessionId,
    required String fullContent,
    ReferenceItem? primaryRef,
  }) async {
    if (_ensureOutlineService() == null) return;
    // 若调用方未传入 primaryRef（D4-A 路径），从 session 装配主引用
    ReferenceItem? pRef = primaryRef;
    if (pRef == null) {
      try {
        final refs = await _referenceRepo.listReferencesOfSession(sessionId);
        if (refs.isNotEmpty) {
          final items = refs
              .map(
                (r) => ReferenceItem(
                  refType: r.refType,
                  refId: r.refId,
                  title: r.title,
                  isPrimary: r.isPrimary,
                  manuscriptId: r.manuscriptId,
                  excerptRange: r.excerptRange,
                ),
              )
              .toList();
          pRef = items.firstWhere(
            (r) => r.isPrimary == 1,
            orElse: () => items.first,
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] commitOutlineChangeFromContent 引用查询失败: $e');
        return;
      }
    }
    if (pRef?.refType != 'chapter') return;
    try {
      final outlineExtraction = parseOutlineExtraction(fullContent);
      if (outlineExtraction == null || outlineExtraction.entities.isEmpty) {
        return;
      }
      final chapter = await _chapterRepo.getChapter(pRef!.refId);
      if (chapter == null) return;
      final results = await _ensureOutlineService()!.applyOutlineExtraction(
        manuscriptId: chapter.manuscriptId,
        extraction: outlineExtraction,
        sourceChapterId: chapter.id,
        sourceChapterNo: chapter.sortOrder,
      );
      debugPrint(
        '[ChatService] 大纲提取落库 | 实体数=${outlineExtraction.entities.length}',
      );
      for (final r in results) {
        if (r.impressions.isEmpty) continue;
        await insertOutlineConfirmationCard(
          _sessionRepo,
          sessionId,
          OutlineConfirmationPayload(
            confirmationId: generateUuid(),
            entityId: r.entityId,
            entityType: r.entityType,
            entityKey: r.entityKey,
            isNewEntity: r.isNewEntity,
            impressions: r.impressions
                .map(
                  (im) => OutlineImpressionPayload(
                    id: im.id,
                    text: im.text,
                    conflictWith: im.conflictWith,
                  ),
                )
                .toList(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[SafeRun] commitOutlineChangeFromContent 大纲落库失败: $e');
    }
  }

  /// A6：事实提取落库（时序知识图谱写入路径）
  ///
  /// 从 AI 诊断回复中提取 [YS_FACT] 块，将人物/事件/支线事实
  /// upsert 到 character_fact/event_fact/subplot_fact 三表。
  /// 失败/未装配/无事实块/非章节 → 静默跳过不抛。
  /// 优先使用入参 primaryRef（sendMessage 路径）；
  /// 若未传（commitDiagnosisFromContent 路径）则从 session 引用取。
  Future<void> _applyFactExtractionFromContent({
    required String sessionId,
    required String fullContent,
    ReferenceItem? primaryRef,
  }) async {
    // 三表仓储至少一个未装配 → 跳过
    if (_characterFactRepo == null &&
        _eventFactRepo == null &&
        _subplotFactRepo == null) {
      return;
    }

    // 解析 primaryRef（同 _applyOutlineEntitiesFromContent 模式）
    ReferenceItem? pRef = primaryRef;
    if (pRef == null) {
      try {
        final refs = await _referenceRepo.listReferencesOfSession(sessionId);
        if (refs.isNotEmpty) {
          final items = refs
              .map(
                (r) => ReferenceItem(
                  refType: r.refType,
                  refId: r.refId,
                  title: r.title,
                  isPrimary: r.isPrimary,
                  manuscriptId: r.manuscriptId,
                  excerptRange: r.excerptRange,
                ),
              )
              .toList();
          pRef = items.firstWhere(
            (r) => r.isPrimary == 1,
            orElse: () => items.first,
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] persistTeacherSuggestion 失败: $e');
        return;
      }
    }
    if (pRef?.refType != 'chapter') return;

    try {
      final extraction = parseFactExtraction(fullContent);
      if (extraction == null || extraction.isEmpty) return;

      final chapter = await _chapterRepo.getChapter(pRef!.refId);
      if (chapter == null) return;
      final manuscriptId = chapter.manuscriptId;
      final chapterNo = chapter.sortOrder;
      final now = nowSec();

      // 人物事实 → character_fact
      if (_characterFactRepo != null) {
        for (final c in extraction.characters) {
          await _characterFactRepo.upsertCharacter(
            manuscriptId: manuscriptId,
            name: c.name,
            firstSeenChapter: chapterNo,
            firstSeenAt: now,
            assertions: c.assertions,
          );
        }
      }

      // 事件事实 → event_fact
      // 批次3-D4：两轮写入——先 upsert 全部事件（不带因果边），
      // 再反查 causeEventName 对应 id 填入 cause_event_id
      if (_eventFactRepo != null) {
        // 第一轮：upsert 全部事件
        for (final e in extraction.events) {
          await _eventFactRepo.upsertEvent(
            manuscriptId: manuscriptId,
            name: e.name,
            eventType: e.eventType,
            chapter: e.chapter ?? chapterNo,
            participants: e.participants,
            description: e.description,
          );
        }
        // 第二轮：填因果边（causeEventName → causeEventId）
        for (final e in extraction.events) {
          final causeName = e.causeEventName;
          if (causeName == null) continue;
          final self = await _eventFactRepo.getEvent(manuscriptId, e.name);
          final cause = await _eventFactRepo.getEvent(manuscriptId, causeName);
          if (self != null && cause != null) {
            await _eventFactRepo.updateCauseEventId(self.id, cause.id);
          } else {
            // 批次6（6.11 L5/V10）：因果边反查失败不再静默丢弃——
            // 打日志留痕，便于排查前因名称不一致导致关联未建立
            debugPrint(
              '[FactExtract] 因果边反查失败未关联: 事件="$e.name" '
              '前因="$causeName"（self=${self != null ? '找到' : '缺失'}'
              ' / cause=${cause != null ? '找到' : '缺失'}）',
            );
          }
        }
      }

      // 支线事实 → subplot_fact
      if (_subplotFactRepo != null) {
        for (final s in extraction.subplots) {
          await _subplotFactRepo.upsertSubplot(
            manuscriptId: manuscriptId,
            name: s.name,
            introducedChapter: s.introducedChapter ?? chapterNo,
            resolvedChapter: s.resolvedChapter,
            resolvedAt: s.resolvedChapter != null ? now : null,
            description: s.description,
          );
        }
      }

      debugPrint(
        '[ChatService] A6 事实提取落库 | 人物=${extraction.characters.length} '
        '事件=${extraction.events.length} 支线=${extraction.subplots.length}',
      );
    } catch (e) {
      debugPrint('[SafeRun] 事实提取三表落库失败: $e');
    }
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
