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
    final rawParse = _diagnosis.parseDiagnosis(fullContent);
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
          final validation = _diagnosis.validateDiagnosisOutput(
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
        final refs = await _referenceRepo.listReferences(sessionId);
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

}
