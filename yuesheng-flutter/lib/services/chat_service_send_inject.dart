// ─────────────────────────────────────────────────────────────
// chat_service_send 步骤块提取：chat_service_send_inject.dart（R-019 ≤300 行）
// 逐字迁移自 chat_service_send.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_service.dart';

extension ChatServiceSendInject on ChatService {
  Future<void> _injectProfileAndIntents({
    required String sessionId,
    required String content,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    // 5.0 学员画像注入（跨会话上下文）
    // 真源：chat-service.ts L218 buildStudentContext
    try {
      final profileResult = await buildStudentContext(
        diagnosisRepo: _diagnosisRepo,
        studentModelRepo: _studentModelRepo,
        sessionRepo: _sessionRepo,
        sessionId: sessionId,
      );
      if (profileResult.text.isNotEmpty) {
        markStage(BudgetStageNames.studentProfile);
        messages.add(ChatMessage(role: 'system', content: profileResult.text));
      }
    } catch (e) {
      debugPrint('[SafeRun] 画像注入失败不阻断主流程: $e');
    }

    // 5.0.0b S2/S3 修复：注入上一轮教学焦点的 focus_reason + next_focus
    // 闭合 teaching_plan 3元组协议的"下一轮注入"承诺
    try {
      final latestDiag = await _diagnosisRepo.getLatestDiagnosis(sessionId);
      if (latestDiag != null) {
        final parts = <String>[];
        if (latestDiag.focusReason != null &&
            latestDiag.focusReason!.isNotEmpty) {
          parts.add('**上一轮教学焦点理由**：${latestDiag.focusReason}');
        }
        if (latestDiag.nextFocus != null && latestDiag.nextFocus!.isNotEmpty) {
          parts.add('**上轮设定的下一步方向**：${latestDiag.nextFocus}');
        }
        if (parts.isNotEmpty) {
          messages.add(
            ChatMessage(
              role: 'system',
              content:
                  '# 上一轮教学计划延续（系统注入）\n\n'
                  '${parts.join('\n\n')}\n\n'
                  '请保持教学连贯性，延续上轮设定的方向。',
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[SafeRun] 教学计划延续注入失败不阻断主流程: $e');
    }

    // 5.0.1 交互意图分类（批次63 B62b，A2 落地）
    // L1 数据模型「意图识别分类器 + 最近3次意图向量」→ 决定 prompt 构造与触发策略
    final intent = classifyUserIntent(content);
    final recentIntents = _recentIntentsBySession.putIfAbsent(
      sessionId,
      () => [],
    );
    recentIntents.add(intent.value);
    if (recentIntents.length > 3) recentIntents.removeAt(0);
    final intentNote = buildIntentInstruction(intent, recentIntents);
    if (intentNote != null) {
      messages.add(ChatMessage(role: 'system', content: intentNote));
    }

    // 5.0.2 回复颗粒度控制：用户请求「长话短说/详细点」时注入（standard 不注入）
    // 落地教学行为对照表 9.2「反馈颗粒度」行（说详细点/简单说说就行 → 调整 detail level）
    final detailNote = buildReplyDetailInstruction(detectReplyDetail(content));
    if (detailNote != null) {
      messages.add(ChatMessage(role: 'system', content: detailNote));
    }
  }

  Future<
    ({
      ReferenceItem? primaryRef,
      bool reviewerPassed,
      bool reviewerNeedsEditor,
      String? chapterContent,
    })
  >
  _injectReferencesAndReviewer({
    required String sessionId,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    // 5.1 引用内容注入（作品/章节/素材文件）
    // 真源：chat-service.ts L230-246 buildReferencesContext
    // 同时记录 primaryRef 供 5.2 附属文件注入使用
    ReferenceItem? primaryRef;
    try {
      final refs = await _referenceRepo.listReferences(sessionId);
      if (refs.isNotEmpty) {
        final referenceItems = refs
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
        // 记录主引用（isPrimary == 1），供 5.2 附属文件注入推导 manuscriptId
        primaryRef = referenceItems.firstWhere(
          (r) => r.isPrimary == 1,
          orElse: () => referenceItems.first,
        );

        final resolvers = ReferenceResolvers(
          fileResolver: (fileId) {
            // 同步包装：buildReferencesContext 是同步函数，需要 sync resolver
            // 由于 drift 是 async，这里用 _cachedAttachedFiles 预加载
            return _cachedAttachedFiles[fileId];
          },
          chapterResolver: (chapterId) {
            return _cachedChapters[chapterId];
          },
          manuscriptResolver: (manuscriptId) {
            return _cachedManuscripts[manuscriptId];
          },
        );
        // 预加载所有引用的详情到缓存
        await _preloadReferenceDetails(refs);
        final referencesContext = buildReferencesContext(
          referenceItems,
          resolvers: resolvers,
        );
        if (referencesContext.isNotEmpty) {
          markStage(BudgetStageNames.references);
          messages.add(ChatMessage(role: 'system', content: referencesContext));
        }
        // 清理缓存
        _cachedAttachedFiles.clear();
        _cachedChapters.clear();
        _cachedManuscripts.clear();
      }
    } catch (e) {
      debugPrint('[SafeRun] 引用内容注入失败不阻断主流程: $e');
    }

    // 5.1.1 Reviewer 门控（P4-007 批 1）
    // 真源：chat-service.ts L256-309
    // 触发条件：ENABLED + 主引用是 chapter + 章节内容 >= MIN_TEXT_LENGTH
    // FAIL → 追加 matched_signals 提示 system message
    // PASS + needs_editor=true → 供后续 Editor 分支使用
    List<String>? reviewerMatchedSignals;
    bool reviewerPassed = false;
    bool reviewerNeedsEditor = false;
    String? chapterContent;
    if (ReviewerGate.enabled && primaryRef?.refType == 'chapter') {
      try {
        final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
        if (chapter != null &&
            chapter.content.length >= ReviewerGate.minTextLength) {
          chapterContent = chapter.content;
          final review = await callReviewer(_llmClient, chapter.content);
          if (review != null) {
            if (review.verdict == ReviewVerdict.fail) {
              reviewerMatchedSignals = review.matchedSignals;
            } else {
              reviewerPassed = true;
              reviewerNeedsEditor = review.needsEditor;
            }
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] Reviewer 失败降级走现有流程: $e');
      }
    }

    // Reviewer FAIL 时追加命中信号提示（不破坏 buildSystemPromptV2 输出）
    if (reviewerMatchedSignals != null && reviewerMatchedSignals.isNotEmpty) {
      messages.add(
        ChatMessage(
          role: 'system',
          content:
              '# 审稿人门控提示\n\n审稿人已判定此文本"存在写作技术问题"（FAIL）。\n'
              '**命中信号**：${reviewerMatchedSignals.join('；')}\n\n'
              '请基于这些信号识别具体写作问题。',
        ),
      );
    }
    return (
      primaryRef: primaryRef,
      reviewerPassed: reviewerPassed,
      reviewerNeedsEditor: reviewerNeedsEditor,
      chapterContent: chapterContent,
    );
  }

  Future<void> _injectOutlineFactsAndFiles({
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    // 5.1.8 大纲实体记忆（批次72 大纲层 + 批次74 协议告知）：
    // 触发时机：用户请求章节诊断且主引用为章节、装配了 outlineRepo
    // 协议说明：无条件注入（零实体也注入）→ AI 从首轮即知晓 [YS_ENTITY] 协议，闭环可启动
    // 实体索引：有实体才注入（供 matched_entity_id/conflict_with 引用，防幻觉）
    if (content.contains(_kDiagnosisRequestMarker) &&
        primaryRef?.refType == 'chapter' &&
        _ensureOutlineService() != null) {
      try {
        final outlineService = _ensureOutlineService()!;
        messages.add(
          ChatMessage(
            role: 'system',
            content: outlineService.buildEntityProtocolContext(),
          ),
        );
        final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
        if (chapter != null) {
          final ctx = await outlineService.buildEntityIndexContext(
            chapter.manuscriptId,
          );
          if (ctx != null) {
            messages.add(ChatMessage(role: 'system', content: ctx));
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] 大纲记忆注入失败不阻断主流程: $e');
      }
    }

    // 5.1.9 A6：时序知识图谱事实提取协议注入
    // 触发条件：章节引用 + 至少一个 fact 仓储已装配
    // 输出顺序：[YS_DIAGNOSIS] → [YS_ENTITY] → [YS_FACT] → 自然语言
    // 批次4（4.10 L4）：移除诊断标记硬约束——训练/评估/自由讨论等非诊断消息
    // 在章节会话中也注入，避免学员练习文本中的事实被漏提
    if (primaryRef?.refType == 'chapter' &&
        (_characterFactRepo != null ||
            _eventFactRepo != null ||
            _subplotFactRepo != null)) {
      messages.add(
        ChatMessage(role: 'system', content: _buildFactProtocolContext()),
      );
    }

    // 5.2 附属文件上下文注入（V3：AI 可读取书籍下所有文件）
    // 真源：chat-service.ts L311-335
    // 从 primaryRef 推 manuscriptId，列书籍下所有附属文件，格式化后注入
    try {
      String? manuscriptId;
      if (primaryRef != null) {
        if (primaryRef.refType == 'manuscript') {
          manuscriptId = primaryRef.refId;
        } else if (primaryRef.refType == 'chapter') {
          final chapter = await _chapterRepo.getChapter(primaryRef.refId);
          manuscriptId = chapter?.manuscriptId;
        }
      }
      if (manuscriptId != null) {
        final files = await _referenceRepo.listAttachedFiles(manuscriptId);
        if (files.isNotEmpty) {
          final fileInfos = files
              .map(
                (f) => AttachedFileInfo(
                  fileName: f.fileName,
                  fileRole: f.fileRole,
                  content: f.content,
                ),
              )
              .toList();
          final fileContext = _material.formatAttachedFiles(fileInfos);
          if (fileContext != null && fileContext.isNotEmpty) {
            markStage(BudgetStageNames.attachedFiles);
            messages.add(ChatMessage(role: 'system', content: fileContext));
          }
        }
      }
    } catch (e) {
      debugPrint('[SafeRun] 附属文件注入失败不阻断主流程: $e');
    }
  }
}
