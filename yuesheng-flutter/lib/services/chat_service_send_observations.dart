// ─────────────────────────────────────────────────────────────
// chat_service_send 步骤块提取：chat_service_send_observations.dart（R-019 ≤300 行）
// 逐字迁移自 chat_service_send.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_service.dart';

extension ChatServiceSendObservations on ChatService {
  Future<void> _injectChapterObservations({
    required String sessionId,
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) async {
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
  }

}
