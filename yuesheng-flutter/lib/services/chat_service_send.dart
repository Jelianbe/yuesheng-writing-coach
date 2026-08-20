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
      final promptResult = _teaching.buildSystemPrompt(skillCtx);

      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: promptResult.systemPrompt),
      ];

      // 可降级阶段 → 消息索引（运行时 token 预算闸门裁剪依据，2026-08-11）
      // 只记录非保底层；systemPrompt 内嵌的 L2 组与保底阶段不记录、不裁。
      final stageIndexes = <String, List<int>>{};
      void markStage(String stage) {
        (stageIndexes[stage] ??= []).add(messages.length);
      }
      // 5.0-5.2 上下文注入（R-019 三级拆分：步骤块提取至 chat_service_send_*.dart）
      await _injectProfileAndIntents(
        sessionId: sessionId,
        content: content,
        messages: messages,
        markStage: markStage,
      );
      final refCtx = await _injectReferencesAndReviewer(
        sessionId: sessionId,
        messages: messages,
        markStage: markStage,
      );
      final primaryRef = refCtx.primaryRef;
      final reviewerPassed = refCtx.reviewerPassed;
      final reviewerNeedsEditor = refCtx.reviewerNeedsEditor;
      final chapterContent = refCtx.chapterContent;
      await _injectChapterObservations(
        sessionId: sessionId,
        content: content,
        primaryRef: primaryRef,
        messages: messages,
      );
      await _injectOutlineFactsAndFiles(
        content: content,
        primaryRef: primaryRef,
        messages: messages,
        markStage: markStage,
      );
      final trainingSyndromeId = await _injectDiagnosisLock(
        sessionId: sessionId,
        content: content,
        activeProblems: activeProblems,
        currentSubphase: currentSubphase,
        beginnerLevel: beginnerLevel,
        messages: messages,
        markStage: markStage,
      );
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

      // 7.1 Editor 分支（R-019：步骤块提取，返回 true 表示已处理并提前结束）
      if (reviewerPassed && reviewerNeedsEditor && chapterContent != null) {
        final handled = await _runEditorBranch(
          sessionId: sessionId,
          primaryRef: primaryRef,
          reviewerPassed: reviewerPassed,
          reviewerNeedsEditor: reviewerNeedsEditor,
          chapterContent: chapterContent,
          rapidFire: rapidFire,
          callbacks: callbacks,
          options: options,
        );
        if (handled) return;
      }

      // 8. 流式调用 + 拦截诊断块（R-019：提取为 _streamLlm）
      final streamResult = await _streamLlm(
        messages: messages,
        callbacks: callbacks,
        options: options,
      );
      final fullContent = streamResult.fullContent;
      final inDiagnosisBlock = streamResult.inDiagnosisBlock;

      // 9-10. 解析 + 校验 + 落库（R-019：提取为 _parseAndPersist）
      final parsed = await _parseAndPersist(
        sessionId: sessionId,
        fullContent: fullContent,
        inDiagnosisBlock: inDiagnosisBlock,
        primaryRef: primaryRef,
        chapterContent: chapterContent,
        callbacks: callbacks,
        options: options,
      );
      // 步骤 10 空响应提前结束（onError 已触发，等价原 return）
      if (parsed.aborted) return;

      // 11. 诊断提交 + Teacher suggestion + GenUI 卡片（R-019：提取为 _commitDiagnosisAndSuggestions）
      await _commitDiagnosisAndSuggestions(
        sessionId: sessionId,
        diagnosis: parsed.diagnosis,
        messageId: parsed.messageId,
        primaryRef: primaryRef,
        teacherResult: parsed.teacherResult,
        rapidFire: rapidFire,
        flowBypassed: flowBypassed,
        genuiComponents: parsed.genuiComponents,
      );
      // 批次50 临时测量：回复长度观测（决策前置：先量化 standard 档是否真超长）
      // 仅 debug 留痕不干预；批次 52 汇成节奏体检报告后按结论处置。
      _observeReplyLength(
        parsed.displayContent,
        content,
        options.attitude,
        currentSubphase,
      );

      // 11. 训练结果解析 + teaching_history 写入（R-019：提取为 _handleTrainingResult）
      await _handleTrainingResult(
        sessionId: sessionId,
        currentSubphase: currentSubphase,
        displayContent: parsed.displayContent,
        trainingSyndromeId: trainingSyndromeId,
        activeProblems: activeProblems,
        callbacks: callbacks,
      );
      await callbacks.onComplete(parsed.finalContent, parsed.messageId);
      debugPrint('[ChatService] sendMessage 完成 | onComplete 已触发');
    } catch (e) {
      debugPrint('[ChatService] sendMessage 异常: $e');
      // 区分「用户主动取消」与「真实失败」：取消是预期行为，
      // 走 onCancelled 让 UI 优雅复位（不标记消息失败、不弹红错）；
      // 其余异常走 onError。
      final cancelled =
          e is LlmRequestCancelledException ||
          (options.cancelToken?.isCancelled ?? false);
      if (cancelled) {
        callbacks.onCancelled?.call();
      } else {
        callbacks.onError(e is Exception ? e.toString() : '发送失败');
      }
    }
  }
}
