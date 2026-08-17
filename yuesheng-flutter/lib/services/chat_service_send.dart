// ignore_for_file: invalid_use_of_protected_member
part of 'chat_service.dart';

/// sendMessage 主流程实现（批次96-25 从宿主逐字迁出，行为零变更）。
/// 命名为 _sendMessageCore 以避免遮蔽宿主保留的薄实例方法 sendMessage，
/// 从而维持子类 override / 测试替身（_FakeChatService）的派发语义。
extension ChatServiceSend on ChatService {
  Future<void> _sendMessageCore(
    String sessionId,
    String content,
    SendMessageCallbacks callbacks,
    SendMessageOptions options, {
    TeachingSubphase? subphase,
  }) async {
    debugPrint(
      '[ChatService] sendMessage 开始 | session=$sessionId | content="${content.length > 50 ? '${content.substring(0, 50)}...' : content}" | phase=${options.phase} | attitude=${options.attitude}',
    );
    // 批次59/64：心流判定（Just-in-Time 触发三问第 3 问）
    // 批次64（B62g）：叠加编辑器活跃——距上一条消息 < 60s 或最近 120s 内有编辑
    // 批次1（O1）：Teacher 升级阀——某症候严重度/诊断次数达阈值时绕过心流窗口
    //（判定放在步骤 4 加载活跃症候之后，见下方 _shouldBypassFlowWindow）
    final nowAtSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    try {
      // 1. 写入用户消息
      // 批次71：@ 引用快照随 user 消息落库（气泡底部引用徽章展示 + 点击跳转）
      await _sessionRepo.addMessage(
        sessionId,
        'user',
        content,
        referencesJson: options.referencesJson,
      );
      debugPrint('[ChatService] 步骤1: user 消息已写入');

      // 2. 获取历史消息（已含 user）
      final history = await _sessionRepo.listMessages(sessionId);
      debugPrint('[ChatService] 步骤2: 历史消息 ${history.length} 条');

      // 3. 读取 teaching state
      TeachingSubphase? currentSubphase = subphase;
      bool isBeginner = false;
      BeginnerLevel? beginnerLevel; // 批次60：技能层级软引导用
      // 批次6 M2：阶段上下文优先取 DB 持久化 currentPhase。
      // options.phase 由 UI 层硬编码（chat_page 恒为 p0Engage），可能与学员真实阶段
      // 不一致——已到 P2/P3 的学员在聊天页发消息，AI 仍按 P0 语境响应。DB 为准。
      var effectivePhase = options.phase;
      try {
        final ts = await _stateRepo.getTeachingState(sessionId);
        if (ts != null) {
          currentSubphase =
              subphase ?? TeachingSubphase.fromString(ts.currentSubphase);
          final level = ts.beginnerLevel;
          beginnerLevel = BeginnerLevel.fromString(level);
          isBeginner =
              level != null &&
              level != BeginnerLevel.n4Independent.value &&
              level != BeginnerLevel.n3Diagnose.value;
          final dbPhase = TeachingPhase.fromString(ts.currentPhase);
          if (dbPhase != null) effectivePhase = dbPhase;
        }
      } catch (e) {
        debugPrint('[SafeRun] getTeachingState+解析失败: $e');
        currentSubphase = subphase;
      }

      // 4. 加载活跃症候
      final activeProblems = await _diagnosisRepo.listActiveProblems(sessionId);
      debugPrint('[ChatService] 步骤4: 活跃症候 ${activeProblems.length} 个');

      // 批次1（O1）：Teacher 升级阀——慢性/重度症候绕过心流窗口，让建议出得来
      final flowBypassed = await _shouldBypassFlowWindow(
        sessionId,
        activeProblems,
      );
      final rapidFire = isInFlow(
        lastSendAtSec: _lastUserSendAtSec[sessionId],
        lastEditorEditAtSec: options.lastEditorEditAtSec,
        nowAtSec: nowAtSec,
        bypassFlowWindow: flowBypassed,
        // 批次6（6.8 M4）：求助关键词（不会/怎么/卡住了/没思路）命中
        // → 绕过心流抑制，主动求助及时反馈
        helpSignal: content,
      );
      _lastUserSendAtSec[sessionId] = nowAtSec;

      // 5. 拼接 system prompt（L1 + L2）
      final skillCtx = SkillLoadContext(
        phase: effectivePhase,
        attitude: options.attitude,
        subphase: currentSubphase,
        isBeginner: isBeginner,
      );
      final promptResult = buildSystemPromptV2(skillCtx);

      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: promptResult.systemPrompt),
      ];

      // 可降级阶段 → 消息索引（运行时 token 预算闸门裁剪依据，2026-08-11）
      // 只记录非保底层；systemPrompt 内嵌的 L2 组与保底阶段不记录、不裁。
      final stageIndexes = <String, List<int>>{};
      void markStage(String stage) {
        (stageIndexes[stage] ??= []).add(messages.length);
      }

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
          messages.add(
            ChatMessage(role: 'system', content: profileResult.text),
          );
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
          if (latestDiag.nextFocus != null &&
              latestDiag.nextFocus!.isNotEmpty) {
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
      final detailNote = buildReplyDetailInstruction(
        detectReplyDetail(content),
      );
      if (detailNote != null) {
        messages.add(ChatMessage(role: 'system', content: detailNote));
      }

      // 5.1 引用内容注入（作品/章节/素材文件）
      // 真源：chat-service.ts L230-246 buildReferencesContext
      // 同时记录 primaryRef 供 5.2 附属文件注入使用
      ReferenceItem? primaryRef;
      try {
        final refs = await _referenceRepo.listReferencesOfSession(sessionId);
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
            messages.add(
              ChatMessage(role: 'system', content: referencesContext),
            );
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

      // 5.1.2 声线漂移检测（批次64 B62f，F10 实时化）：
      // L3 定量指纹（style_fingerprint）→ L1 实时提示
      // 触发时机：用户请求章节诊断（content 含诊断标记）且主引用为章节
      // 基线策略：首次建立；无漂移时随最新文本滑动重锚（合法演化不误报）
      // 漂移命中 → 注入本轮 prompt，AI 以提问式语言温和指出（软引导非硬拦截）
      if (content.contains(_kDiagnosisRequestMarker) &&
          primaryRef?.refType == 'chapter') {
        try {
          final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
          if (chapter != null) {
            final current = extractStyleFingerprint(chapter.content);
            if (current != null) {
              final baseline = await _studentModelRepo.getStyleFingerprint(
                sessionId,
              );
              final hints = (baseline == null || baseline.sentencesCount == 0)
                  ? const <String>[]
                  : detectVoiceDrift(baseline, current);
              if (hints.isEmpty) {
                await _studentModelRepo.updateStyleFingerprint(
                  sessionId,
                  current,
                );
              } else {
                messages.add(
                  ChatMessage(
                    role: 'system',
                    content: _buildDriftHintContext(hints),
                  ),
                );
              }
            }
          }
        } catch (e) {
          debugPrint('[SafeRun] 漂移检测失败不阻断主流程: $e');
        }
      }

      // 5.1.3 时序矛盾冲突观察（批次66 B62i，A6 首步，挂 F05/P018 补充）：
      // 触发时机：用户请求章节诊断且主引用为章节；人物知识仓储已装配
      // 数据源：character_fact（作品级人物断言，断言带章节/时间维度）
      // 无人物断言数据 → 无观察项 → 不注入（零 token 成本）
      if (content.contains(_kDiagnosisRequestMarker) &&
          primaryRef?.refType == 'chapter' &&
          _characterFactRepo != null) {
        try {
          final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
          if (chapter != null) {
            final facts = await _characterFactRepo.listCharacters(
              chapter.manuscriptId,
            );
            if (facts.isNotEmpty) {
              final inputs = facts
                  .map(
                    (f) => (
                      name: f.name,
                      assertions: CharacterFactRepository.parseAssertions(
                        f.assertions,
                      ),
                    ),
                  )
                  .toList();
              final raw = detectCharacterConflicts(inputs);
              // O11（批次6 6.5）：正文反查最早断言值的首现片段作触发原文摘录；
              // 正文不含关键词时 excerpt 为 null，上下文降级不输出摘录
              final observations = raw
                  .map(
                    (o) => ConflictObservation(
                      characterName: o.characterName,
                      attribute: o.attribute,
                      orderedValues: o.orderedValues,
                      description: o.description,
                      excerpt: findKeywordExcerpt(
                        chapter.content,
                        o.orderedValues.first.value,
                      ),
                    ),
                  )
                  .toList();
              final ctx = buildConflictObservationsContext(observations);
              if (ctx != null) {
                messages.add(ChatMessage(role: 'system', content: ctx));
              }
            }
          }
        } catch (e) {
          debugPrint('[SafeRun] 冲突检测失败不阻断主流程: $e');
        }
      }

      // 5.1.4 因果链断裂观察（批次67 B62j，A6 第二迭代 F07，挂 P021/P016 补充）：
      // 触发时机：用户请求章节诊断且主引用为章节；事件知识仓储已装配
      // 数据源：event_fact（作品级事件节点，带章节 + 因果边）
      // 无事件数据 → 无观察项 → 不注入（零 token 成本）
      if (content.contains(_kDiagnosisRequestMarker) &&
          primaryRef?.refType == 'chapter' &&
          _eventFactRepo != null) {
        try {
          final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
          if (chapter != null) {
            final events = await _eventFactRepo.listEvents(
              chapter.manuscriptId,
            );
            if (events.isNotEmpty) {
              final inputs = events
                  .map(
                    (e) => (
                      name: e.name,
                      chapter: e.chapter,
                      eventType: e.eventType,
                      causeEventId: e.causeEventId,
                      effectEventId: e.effectEventId,
                    ),
                  )
                  .toList();
              final raw = detectCausalityBreaks(inputs);
              // O11（批次6 6.5）：正文反查事件名首现片段作触发原文摘录；
              // 正文不含事件名时 excerpt 为 null，上下文降级不输出摘录
              final observations = raw
                  .map(
                    (o) => CausalityBreakObservation(
                      name: o.name,
                      chapter: o.chapter,
                      eventType: o.eventType,
                      description: o.description,
                      excerpt: findKeywordExcerpt(chapter.content, o.name),
                    ),
                  )
                  .toList();
              final ctx = buildCausalityBreakContext(observations);
              if (ctx != null) {
                messages.add(ChatMessage(role: 'system', content: ctx));
              }
            }
          }
        } catch (e) {
          debugPrint('[SafeRun] 因果链检测失败不阻断主流程: $e');
        }
      }

      // 5.1.5 情节闭环观察（批次67 B62j，A6 第二迭代 F11，挂 P014/P017 补充）：
      // 触发时机：用户请求章节诊断且主引用为章节；支线知识仓储已装配
      // 数据源：subplot_fact（作品级支线节点，带引入/回收章节）
      // 当前章节 = 主引用章节 sortOrder；无支线数据 → 不注入（零 token 成本）
      if (content.contains(_kDiagnosisRequestMarker) &&
          primaryRef?.refType == 'chapter' &&
          _subplotFactRepo != null) {
        try {
          final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
          if (chapter != null) {
            final subplots = await _subplotFactRepo.listSubplots(
              chapter.manuscriptId,
            );
            if (subplots.isNotEmpty) {
              final inputs = subplots
                  .map(
                    (s) => (
                      name: s.name,
                      introducedChapter: s.introducedChapter,
                      resolvedChapter: s.resolvedChapter,
                    ),
                  )
                  .toList();
              final raw = detectUnclosedSubplots(
                inputs,
                currentChapter: chapter.sortOrder,
              );
              // O11（批次6 6.5）：正文反查支线名首现片段作触发原文摘录；
              // 正文不含支线名时 excerpt 为 null，上下文降级不输出摘录
              final observations = raw
                  .map(
                    (o) => UnclosedSubplotObservation(
                      name: o.name,
                      introducedChapter: o.introducedChapter,
                      currentChapter: o.currentChapter,
                      description: o.description,
                      excerpt: findKeywordExcerpt(chapter.content, o.name),
                    ),
                  )
                  .toList();
              final ctx = buildSubplotClosureContext(observations);
              if (ctx != null) {
                messages.add(ChatMessage(role: 'system', content: ctx));
              }
            }
          }
        } catch (e) {
          debugPrint('[SafeRun] 情节闭环检测失败不阻断主流程: $e');
        }
      }

      // 5.1.6 基础文法观察（批次70 F12，挂 P022 重复用词/基础语病 补充）：
      // 触发时机：用户请求章节诊断且主引用为章节
      // 数据源：章节正文（纯规则文本检测，无仓储依赖）
      // 无检出问题 → 不注入（零 token 成本）
      if (content.contains(_kDiagnosisRequestMarker) &&
          primaryRef?.refType == 'chapter') {
        try {
          final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
          if (chapter != null) {
            final issues = detectGrammarLexicalIssues(chapter.content);
            final ctx = buildGrammarLexicalContext(issues);
            if (ctx != null) {
              messages.add(ChatMessage(role: 'system', content: ctx));
            }
          }
        } catch (e) {
          debugPrint('[SafeRun] 基础文法检测失败不阻断主流程: $e');
        }
      }

      // 5.1.7 对话标签观察（批次71 F02，挂 P011 对话疲劳症 增强补充）：
      // 触发时机：用户请求章节诊断且主引用为章节
      // 数据源：章节正文（纯规则文本检测，无仓储依赖）
      // 无检出问题 → 不注入（零 token 成本）
      if (content.contains(_kDiagnosisRequestMarker) &&
          primaryRef?.refType == 'chapter') {
        try {
          final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
          if (chapter != null) {
            final issues = detectDialogueTagIssues(chapter.content);
            final ctx = buildDialogueTagContext(issues);
            if (ctx != null) {
              messages.add(ChatMessage(role: 'system', content: ctx));
            }
          }
        } catch (e) {
          debugPrint('[SafeRun] 对话标签检测失败不阻断主流程: $e');
        }
      }

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
            final fileContext = formatAttachedFilesContext(fileInfos);
            if (fileContext != null && fileContext.isNotEmpty) {
              markStage(BudgetStageNames.attachedFiles);
              messages.add(ChatMessage(role: 'system', content: fileContext));
            }
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] 附属文件注入失败不阻断主流程: $e');
      }

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
              relapse = await _diagnosisRepo.hasResolvedHistory(
                focusSyndromeId,
              );
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
                  ChatMessage(
                    role: 'system',
                    content: summary.contextInjection,
                  ),
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

        final structuredContext = buildStructuredSyndromeContext(
          activeSyndromeViews,
          activeFocus: ActiveFocusContext(
            focusId: focusResult.activatedFocusId,
            source: _mapFocusSource(focusResult.source),
            reason: focusResult.reason,
          ),
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

      // 6.5 临场输出约束：在所有教学内容注入后、历史对话前追加
      // 真源：RN e8c46bb（表达密度提交）——利用 LLM recency bias
      // 确保表达密度规则不被后面的详细教学内容覆盖
      //（Flutter 曾缺失：三档态度 skill 表达密度小节 + 本约束，批次 41 补齐）
      // 示范规则以当前态度档位为准：doubao/yuesheng 最小示范，sensei 零示范（只给方向）
      messages.add(
        ChatMessage(
          role: 'system',
          content: kLiveOutputConstraints,
        ),
      );

      // 7. 追加历史消息
      for (final m in history) {
        markStage(BudgetStageNames.history);
        messages.add(ChatMessage(role: m.role, content: m.content));
      }

      // 批次4（4.3）：临场输出约束双保险——历史消息后再追加极简提醒。
      // 主约束在历史之前（利用 recency bias），此处兜底防止长历史稀释其优先级；
      // 只重复最核心的一条，不重复整段约束。
      messages.add(
        ChatMessage(
          role: 'system',
          content: '# 回复纪律（最后提醒）\n\n本次回复：一次只抛一个点，删掉铺垫，示范按态度档位执行。',
        ),
      );

      // 7.0 运行时 token 预算闸门（2026-08-11 体检落地）
      // 总估算超 maxBudget 时按 TokenBudgetTable.planDegradation() 顺序
      // 整段裁掉已标记的可降级阶段；超 warning 线不裁仅提示。
      final guardReport = TokenBudgetGuard.apply(
        messages,
        stageIndexes: stageIndexes,
      );
      if (guardReport.triggered) {
        debugPrint(
          '[ChatService] 预算闸门触发降级: 裁 ${guardReport.droppedMessageCount} 条'
          '（${guardReport.droppedStages.join('、')}）'
          ' | ${guardReport.totalBefore}→${guardReport.totalAfter} tokens',
        );
      } else if (guardReport.overWarning) {
        debugPrint(
          '[ChatService] 预算超警告线未裁剪: ~${guardReport.totalBefore}'
          ' > ${(TokenEstimate.maxBudget * TokenEstimate.warningRatio).round()}',
        );
      }
      debugPrint(
        '[ChatService] 步骤7: 发送到 LLM 的 messages 数量=${messages.length}（含 system + history）',
      );

      // 7.1 Editor 分支（Reviewer PASS + needs_editor=true）
      // 真源：chat-service.ts L464-562
      // R1：Editor observation 总是入库（即使 Teacher 未触发），便于审计阈值校准
      // R6：Teacher suggestion 写入抽到 chat_gates.dart，消除两分支重复
      if (reviewerPassed && reviewerNeedsEditor && chapterContent != null) {
        final editorResult = await callEditorStream(
          _llmClient,
          chapterContent,
          callbacks.onStream,
          cancelToken: options.cancelToken,
        );

        // R1：计算 Teacher 触发判断中间状态（pronounced/against 计数 + 触发标志）
        bool teacherTriggered = false;
        int pronouncedCount = 0;
        int againstCount = 0;
        if (editorResult.observation != null) {
          pronouncedCount = editorResult.observation!.observations
              .where((o) => o.observationVisibility == 'pronounced')
              .length;
          againstCount = editorResult.observation!.observations
              .where((o) => o.intentAlignment == 'against')
              .length;
          teacherTriggered = shouldTriggerTeacherForEditor(
            editorResult.observation!,
          );
        }

        // Editor → Teacher 条件触发（追加教学反馈）
        String teacherDisplayContent = '';
        TeacherResult? teacherResult;
        if (teacherTriggered && editorResult.observation != null) {
          try {
            final teacherStream = await callTeacherStream(
              _llmClient,
              TeacherEditorInput(
                editorResult: editorResult.observation!,
                chapterContent: chapterContent,
              ),
              callbacks.onStream,
              cancelToken: options.cancelToken,
            );
            teacherDisplayContent = teacherStream.displayContent;
            teacherResult = teacherStream.teacher;
          } catch (e) {
            debugPrint('[SafeRun] Teacher 失败不影响 Editor 已有输出: $e');
          }
        }

        // 合并 Editor + Teacher 输出
        final combinedContent =
            editorResult.displayContent +
            (teacherDisplayContent.isNotEmpty
                ? '\n\n$teacherDisplayContent'
                : '');

        if (combinedContent.trim().isEmpty) {
          callbacks.onError('AI 返回为空');
          return;
        }

        final messageId = await _sessionRepo.addMessage(
          sessionId,
          'assistant',
          combinedContent,
        );

        // R1：Editor observation 持久化（总是写入，便于审计阈值）
        if (editorResult.observation != null) {
          try {
            await _editorObservationRepo.insertEditorObservation(
              InsertEditorObservationParams(
                sessionId: sessionId,
                messageId: messageId,
                editorResult: editorResult.observation!,
                teacherTriggered: teacherTriggered,
                pronouncedCount: pronouncedCount,
                againstCount: againstCount,
                targetRefType: primaryRef?.refType,
                targetRefId: primaryRef?.refId,
              ),
            );
          } catch (e) {
            debugPrint('[SafeRun] DB 写入失败不影响 Editor/Teacher 已有输出: $e');
          }
        }

        // R6：Teacher suggestion 写入（两分支复用 persistTeacherSuggestion）
        if (teacherResult != null) {
          await persistTeacherSuggestion(
            _teacherSuggestionRepo,
            teacherResult,
            sessionId,
            messageId,
            'editor',
            isRapidFire: rapidFire,
          );
        }

        await callbacks.onComplete(combinedContent, messageId);
        return; // Editor 分支提前结束，不走主流 Diagnosis streamChat
      }

      // 8. 流式调用 + 拦截诊断块
      String fullContent = '';
      bool inDiagnosisBlock = false;
      int displayLength = 0;
      int streamChunkCount = 0;

      debugPrint('[ChatService] 步骤8: 开始 streamChat 调用...');
      await _llmClient.streamChat(messages, (response) {
        if (response.isDone) {
          debugPrint('[ChatService] 步骤8: streamChat 收到 [DONE]');
          return;
        }
        if (response.content.isEmpty) return;

        streamChunkCount++;
        fullContent += response.content;
        // 批次6（6.10）：内存上限截断——超限丢弃头部，displayLength 同步左移
        //（已转发内容不受影响，仅服务端解析缓冲降载）
        if (fullContent.length > ChatService._kFullContentMaxLen) {
          final overflow = fullContent.length - ChatService._kFullContentMaxLen;
          fullContent = fullContent.substring(overflow);
          displayLength = (displayLength - overflow).clamp(
            0,
            fullContent.length,
          );
          debugPrint(
            '[ChatService] 步骤8: fullContent 超上限截断头部 $overflow 字符（上限 $ChatService._kFullContentMaxLen）',
          );
        }
        if (streamChunkCount <= 3 || streamChunkCount % 10 == 0) {
          debugPrint(
            '[ChatService] 步骤8: chunk#$streamChunkCount | delta="${response.content.length > 30 ? '${response.content.substring(0, 30)}...' : response.content}" | fullLen=${fullContent.length}',
          );
        }

        if (inDiagnosisBlock) return;

        // 拦截诊断块、大纲记忆块（[YS_ENTITY]）、事实块（[YS_FACT]）：
        // 任一标记出现即从该处起不再转发，避免原始协议 JSON 泄漏到流式展示
        // 批次6（6.3）：O(n²) → O(n)——安全区已转发到 displayLength，标记只可能
        // 出现在末尾 ≤ 最大标记长的窗口内（含跨 chunk 拼接），从窗口起点起搜，
        // 避免每 chunk 对全量 fullContent 做三次 indexOf 扫描。
        final scanStart = displayLength > ChatService._kMaxStreamMarkerLen
            ? displayLength - ChatService._kMaxStreamMarkerLen + 1
            : 0;
        final diagMarkerIndex = fullContent.indexOf(kDiagnosisStart, scanStart);
        final outlineMarkerIndex = fullContent.indexOf(
          kOutlineStart,
          scanStart,
        );
        final factMarkerIndex = fullContent.indexOf(kFactStart, scanStart);
        final markerIndex = ChatService._earliestMarkerIndex(
          ChatService._earliestMarkerIndex(diagMarkerIndex, outlineMarkerIndex),
          factMarkerIndex,
        );
        if (markerIndex != -1) {
          final newDisplay = fullContent.substring(displayLength, markerIndex);
          if (newDisplay.isNotEmpty) callbacks.onStream(newDisplay);
          displayLength = markerIndex;
          inDiagnosisBlock = true;
          debugPrint(
            '[ChatService] 步骤8: 检测到协议块标记，切换到拦截模式 | displayLength=$displayLength',
          );
          return;
        }

        final pendingLen = ChatService._blockPendingPrefix(fullContent);
        final safeEnd = pendingLen > 0
            ? fullContent.length - pendingLen
            : fullContent.length;
        if (safeEnd > displayLength) {
          final newDisplay = fullContent.substring(displayLength, safeEnd);
          if (newDisplay.isNotEmpty) callbacks.onStream(newDisplay);
          displayLength = safeEnd;
        }
      }, cancelToken: options.cancelToken);
      debugPrint(
        '[ChatService] 步骤8: streamChat 完成 | 总 chunk=$streamChunkCount | fullContent 长度=${fullContent.length} | inDiagnosisBlock=$inDiagnosisBlock',
      );

      // 9. 解析 + 第二层后置校验
      final rawParse = parseDiagnosis(fullContent);
      debugPrint(
        '[ChatService] 步骤9: parseDiagnosis | displayContent 长度=${rawParse.displayContent.length} | diagnosis=${rawParse.diagnosis != null ? "有(${rawParse.diagnosis!.syndromes.length} 症候)" : "无"}',
      );

      String displayContent = rawParse.displayContent;
      ParsedDiagnosis? diagnosis = rawParse.diagnosis;

      // 步骤 9.1：大纲提取落库（批次72，独立 OUTLINE 块，失败/未装配不阻断）
      // 批次73：落库后为含 pending 印象的实体写入确认卡片
      await _applyOutlineEntitiesFromContent(
        sessionId: sessionId,
        fullContent: fullContent,
        primaryRef: primaryRef,
      );

      // 步骤 9.2：A6 事实提取落库（时序知识图谱写入路径，失败不阻断）
      await _applyFactExtractionFromContent(
        sessionId: sessionId,
        fullContent: fullContent,
        primaryRef: primaryRef,
      );

      if (diagnosis != null) {
        // 提取诊断块原始 JSON 供 validator 用
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
              attitude: options.attitude,
            );
            displayContent = validation.displayContent;
            diagnosis = validation.diagnosis;
          } catch (e) {
            debugPrint('[SafeRun] JSON 解析失败沿用 rawParse: $e');
          }
        }
      }

      // 批次74：剥离 [YS_ENTITY] 协议块（诊断缺块时 displayContent 会含原始 JSON，
      // 校验回填也可能重新引入），确保展示/落库内容不含协议原文
      displayContent = stripOutlineBlock(displayContent);
      // A6：剥离 [YS_FACT] 协议块（事实提取块，与实体块并列独立）
      displayContent = stripFactBlock(displayContent);

      // B1：诊断成败记录 → 连续失败达阈值插诊断失败卡。
      // attempted 仅当 AI 确实输出了 [YS_DIAGNOSIS] 块（inDiagnosisBlock），
      // 普通聊天解析为 null 不计入，避免误触发「诊断失败」卡。
      await _recordDiagnosisOutcome(
        sessionId,
        attempted: inDiagnosisBlock,
        success: diagnosis != null,
      );

      // Diagnosis → Teacher 条件触发（C3）
      // 真源：chat-service.ts L626-655
      String teacherDisplayContent = '';
      TeacherResult? teacherResult;
      if (diagnosis != null &&
          shouldTriggerTeacherForDiagnosis(diagnosis.syndromes)) {
        try {
          final teacherStream = await callTeacherStream(
            _llmClient,
            TeacherDiagnosisInput(
              diagnosis: diagnosis,
              chapterContent: chapterContent ?? '',
            ),
            callbacks.onStream,
            cancelToken: options.cancelToken,
          );
          teacherDisplayContent = teacherStream.displayContent;
          teacherResult = teacherStream.teacher;
        } catch (e) {
          debugPrint('[SafeRun] Teacher 失败不影响 Diagnosis 已有输出: $e');
        }
      }

      // 合并 Diagnosis + Teacher 输出（RN L657-660）
      // 注意：不修改 displayContent，保留原始值供 parseTrainingResult 使用（RN L767 注释）
      final combinedContent =
          displayContent +
          (teacherDisplayContent.isNotEmpty
              ? '\n\n$teacherDisplayContent'
              : '');

      // 10. 写入 assistant 消息
      // 批次74：仅大纲装配的章节诊断才放宽空判断：
      //   - diagnosis 解析成功 或 已落库实体 → 说明可能被协议块（YS_DIAGNOSIS/YS_ENTITY）
      //     占据首位，拦截器 displayLength=0 导致 combinedContent 空 → 给默认文案「诊断完成。」继续。
      //   - 无大纲装配 或 三空齐发（说明空+诊断空+实体空）→ 维持 RN 原语义，onError。
      bool treatAsValid = false;
      if (combinedContent.trim().isEmpty &&
          _ensureOutlineService() != null &&
          primaryRef?.refType == 'chapter') {
        if (diagnosis != null) {
          treatAsValid = true;
        } else {
          final c = await _readOutlineEntityCount(primaryRef!.refId);
          if (c > 0) treatAsValid = true;
        }
      }
      if (combinedContent.trim().isEmpty && !treatAsValid) {
        debugPrint('[ChatService] 步骤10: combinedContent 为空，触发 onError');
        callbacks.onError('AI 返回为空');
        return;
      }
      final finalContent = combinedContent.trim().isEmpty
          ? '诊断完成。'
          : combinedContent;

      final messageId = await _sessionRepo.addMessage(
        sessionId,
        'assistant',
        finalContent,
      );
      debugPrint(
        '[ChatService] 步骤10: assistant 消息已写入 | messageId=$messageId | contentLen=${finalContent.length}',
      );

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

      // 批次50 临时测量：回复长度观测（决策前置：先量化 standard 档是否真超长）
      // 仅 debug 留痕不干预；批次 52 汇成节奏体检报告后按结论处置。
      _observeReplyLength(
        displayContent,
        content,
        options.attitude,
        currentSubphase,
      );

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
        final trainingResult = parseTrainingResult(displayContent);
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

      await callbacks.onComplete(finalContent, messageId);
      debugPrint('[ChatService] sendMessage 完成 | onComplete 已触发');
    } catch (e) {
      debugPrint('[ChatService] sendMessage 异常: $e');
      callbacks.onError(e is Exception ? e.toString() : '发送失败');
    }
  }
}
