// ─────────────────────────────────────────────────────────────
// writing_coach_panel 的 part 文件：教学逻辑 handlers
// 覆盖 _handleSend / _submitPractice / 诊断（整章+选段）/ 快速观察 /
// 部分认同 / 教原理 / 删除消息 等教学链路方法。
// 以私有 extension on _WritingCoachPanelState 形式提供，直接访问宿主
// 私有成员（_inputController / _sessionId / _isDiagnosing 等），
// 行为与原内联实现完全一致，仅做物理拆分。
// ─────────────────────────────────────────────────────────────
// ignore_for_file: invalid_use_of_protected_member
part of 'writing_coach_panel.dart';

extension _WritingCoachPanelTeaching on _WritingCoachPanelState {
  /// 批次81：聚焦输入栏（三卡「返回对话/继续对话/补充内容」复用）
  void _focusInput() {
    _inputFocusNode.requestFocus();
  }

  /// 批次81 H3：部分认同提交反馈 / 快速选项 → 填入输入栏并发送（复用发送链路）
  void _handlePartialAgreementSubmit(String feedback, String? quickOption) {
    if (ref.read(writingCoachStoreProvider(widget.chapterId)).isStreaming) {
      return;
    }
    final detail = quickOption != null
        ? quickOptionLabel(quickOption)
        : feedback;
    if (detail.trim().isEmpty) return;
    _inputController.text = '我对刚才的诊断结果有不同看法：$detail。请根据我的反馈调整诊断。';
    _handleSend();
  }

  /// 批次81 H3：部分认同跳过此症候 → 填入输入栏并发送（请求重新诊断）
  void _handlePartialAgreementSkip() {
    if (ref.read(writingCoachStoreProvider(widget.chapterId)).isStreaming) {
      return;
    }
    _inputController.text = '请跳过这个症候，重新给出诊断结果。';
    _handleSend();
  }

  /// 发送消息（P1-2 修复：接入 ChatService 流式回复）
  /// 批次61：Teacher 建议卡「教我原理」→ 填入输入框并发送（复用 _handleSend 链路）
  void _handleTeachPrinciple(String syndromeName) {
    _inputController.text =
        '我想了解「$syndromeName」的原理。请用简单的话给我讲清楚：'
        '它是什么、怎么判断、怎么避免。一次只讲一个点。';
    _handleSend();
  }

  /// 批次74：长按删除教练面板消息（对齐对话页长按删除心智）
  Future<void> _confirmDeleteMessage(Message msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.overlay,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '删除消息',
          style: AppTextStyles.titleLg,
        ),
        content: const Text(
          '确定要删除这条消息吗？此操作不可撤销。',
          textAlign: TextAlign.center,
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              padding: const EdgeInsets.symmetric(
                // X-039-Batch1：16→lg / 12→md
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
            ),
            child: const Text(
              '取消',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              padding: const EdgeInsets.symmetric(
                // X-039-Batch1：16→lg / 12→md
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
            ),
            child: const Text(
              '删除',
              style: TextStyle(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _initFuture;
    final sid = _sessionId;
    if (sid == null) return;
    final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
    await sessionRepo.deleteMessage(sid, msg.id);
    final messages = await sessionRepo.listMessages(sid);
    if (!mounted) return;
    ref
        .read(writingCoachStoreProvider(widget.chapterId).notifier)
        .setMessages(messages);
  }

  ///
  /// [subphase] 非空时强制指定子阶段（练习提交 → FEEDBACK，触发训练结果解析落库）
  /// [onTrainingResult] 训练结果回调（subphase=FEEDBACK 时由 chat_service 触发）
  Future<void> _handleSend({
    TeachingSubphase? subphase,
    void Function(TrainingResult)? onTrainingResult,
  }) async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();

    // 等待会话初始化完成
    await _initFuture;
    final sid = _sessionId;
    if (sid == null) return;

    // 1. 先把用户消息加到内存 store（即时反馈）
    final now = DateTime.now().millisecondsSinceEpoch;
    final userMsg = Message(
      id: now.toString(),
      sessionId: sid,
      role: 'user',
      content: text,
      timestamp: now ~/ 1000,
      messageType: 'chat',
    );
    ref
        .read(writingCoachStoreProvider(widget.chapterId).notifier)
        .addMessage(userMsg);

    // 2. 接入 ChatService 流式发送
    final store = ref.read(
      writingCoachStoreProvider(widget.chapterId).notifier,
    );
    store.setStreaming(true);
    final chatService = ref.read(chatServiceProvider);
    try {
      await chatService.sendMessage(
        sid,
        text,
        SendMessageCallbacks(
          onStream: (delta) {
            ref
                .read(writingCoachStoreProvider(widget.chapterId).notifier)
                .appendStreamingContent(delta);
          },
          onComplete: (fullContent, messageId) async {
            final sessionRepo = SessionRepository(
              ref.read(appDatabaseProvider),
            );
            final messages = await sessionRepo.listMessages(sid);
            ref
                .read(writingCoachStoreProvider(widget.chapterId).notifier)
                .setMessages(messages);
            ref
                .read(writingCoachStoreProvider(widget.chapterId).notifier)
                .setStreaming(false);
            // 批次49：复位阶段标签
            if (mounted) setState(() => _streamStageLabel = null);
          },
          onError: (error) {
            ref
                .read(writingCoachStoreProvider(widget.chapterId).notifier)
                .setError(error);
          },
          onTrainingResult: onTrainingResult,
        ),
        SendMessageOptions(
          phase: TeachingPhase.p0Engage,
          attitude: AttitudeLevel.doubao,
          // 批次64（B62g）：透传编辑器活动时间戳，心流判定叠加编辑活跃
          lastEditorEditAtSec: ref.read(editorActivityProvider),
        ),
        subphase: subphase,
      );
    } catch (e) {
      if (mounted) setState(() => _streamStageLabel = null);
      store.setError(e.toString());
    }
  }

  /// 提交练习作答（T3：练习任务闭环）
  ///
  /// 复用 _handleSend 链路，强制 subphase=FEEDBACK，
  /// 使 chat_service 步骤 11 的 parseTrainingResult + teaching_history 落库生效，
  /// 并把结果回写到 practiceStore 驱动 PracticeResultIndicator。
  Future<void> _submitPractice(String content) async {
    final practiceStore = ref.read(practiceStoreProvider.notifier);
    practiceStore.setSubmitting(true);
    _inputController.text = content;
    // 批次49：训练评估阶段标签
    if (mounted) setState(() => _streamStageLabel = '正在评估你的改写…');
    await _handleSend(
      subphase: TeachingSubphase.feedback,
      onTrainingResult: (result) {
        practiceStore.setTrainingResult(result);
        _buildEvaluationReportForLastMessage();
      },
    );
    practiceStore.setSubmitting(false);
    practiceStore.submitPractice();
  }

  /// T4 评估报告：训练反馈落库后，为最后一条 assistant 消息构建评估报告
  Future<void> _buildEvaluationReportForLastMessage() async {
    final sid = _sessionId;
    if (sid == null) return;
    final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
    final messages = await sessionRepo.listMessages(sid);
    final lastAssistant = messages
        .where((m) => m.role == 'assistant')
        .lastOrNull;
    if (lastAssistant != null) {
      await ref
          .read(evaluationReportsProvider.notifier)
          .buildEvaluationReport(sid, lastAssistant.id);
    }
  }

  /// 诊断本章（D1：接通 chat_service 真链路，对齐 RN handleConfirmDiagnose）
  Future<void> _handleDiagnose() => _handleDiagnoseWithText(null);

  /// 快速观察（批次69 A7 双通道·实时通道 UI 入口）
  ///
  /// 轻 prompt：只跑 RealtimeObservationService.observe（Editor 观察 + 轻量约束），
  /// 低延迟反馈，不进入全量诊断链路。观察结果写会话 + 入库（R1）。
  /// 与「诊断本章」（复盘通道·全量）形成 A7 双通道分工。
  Future<void> _handleRealtimeObserve() async {
    await _initFuture;
    final sid = _sessionId;
    if (sid == null) return;

    // 字数校验：实时观察要求至少 50 字（短文本观察无意义）
    final writingState = ref.read(writingStoreProvider(widget.chapterId));
    final content = writingState.localContent;
    if (content.trim().length < 50) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少写 50 字后再快速观察')));
      return;
    }

    // 批次49：快速观察阶段标签
    if (mounted) setState(() => _streamStageLabel = '正在快速观察…');
    final store = ref.read(
      writingCoachStoreProvider(widget.chapterId).notifier,
    );
    store.setStreaming(true);

    try {
      await ref
          .read(realtimeObservationServiceProvider)
          .observe(
            sessionId: sid,
            text: content,
            targetRefType: 'chapter',
            targetRefId: widget.chapterId,
            onStream: (delta) {
              ref
                  .read(writingCoachStoreProvider(widget.chapterId).notifier)
                  .appendStreamingContent(delta);
            },
          );

      // observe 内部已写入 assistant 消息 → 刷新消息列表
      final messages = await SessionRepository(
        ref.read(appDatabaseProvider),
      ).listMessages(sid);
      ref
          .read(writingCoachStoreProvider(widget.chapterId).notifier)
          .setMessages(messages);
      ref
          .read(writingCoachStoreProvider(widget.chapterId).notifier)
          .setStreaming(false);
      // 批次49：复位阶段标签，避免残留到下一次流式
      if (mounted) setState(() => _streamStageLabel = null);
    } catch (e) {
      if (mounted) setState(() => _streamStageLabel = null);
      store.setError(e.toString());
    }
  }

  /// 诊断入口：selectedText 非空 → 选段诊断（B3 划词诊断）；否则整章诊断
  ///
  /// 对齐 RN chapter-editor.tsx#L254-L284（整章）与 #L331-L365（选段）：
  ///   1. saveContent：先把编辑器当前内容落库（避免诊断到旧版本，仅整章诊断）
  ///   2. updateChapterDiagnosedAt：写章节最后诊断时间（仅整章诊断）
  ///   3. updatePhase(P1_WORLD)：状态机流转，否则 syndrome-diagnosis-index 不加载
  ///   4. 调 ChatService.sendMessage（phase=P1_WORLD），让 LLM 真正做诊断
  Future<void> _handleDiagnoseWithText(String? selectedText) async {
    // 等待会话初始化完成
    await _initFuture;
    final sid = _sessionId;
    if (sid == null) return;
    final db = ref.read(appDatabaseProvider);

    // D5-A：诊断中置位（驱动「诊断中…」占位 + 按钮禁用态）
    // 批次49：同时设阶段标签（选段/整章区分文案）
    final isSelection = selectedText != null && selectedText.trim().isNotEmpty;
    if (mounted) {
      setState(() {
        _isDiagnosing = true;
        _streamStageLabel = isSelection ? '正在诊断选段…' : '正在诊断本章…';
      });
    }

    // 前置 1：内容来源（选中文本 或 整章）+ 字数校验
    final writingState = ref.read(writingStoreProvider(widget.chapterId));
    final content = isSelection
        ? selectedText.trim()
        : writingState.localContent;
    final title = writingState.chapter?.title ?? widget.chapterTitle;

    // 前置 2：字数校验（选段 ≥20 字 / 整章 ≥100 字，对齐 RN）
    final minLength = isSelection ? 20 : 100;
    if (content.trim().length < minLength) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSelection ? '请至少选择 20 字以上的文本进行诊断' : '请至少输入 100 字后再提交诊断',
          ),
        ),
      );
      return;
    }

    // 前置 3：把未保存内容落库，避免诊断到旧版本（仅整章诊断；选段诊断不落库）
    if (!isSelection) {
      await ref.read(writingStoreProvider(widget.chapterId).notifier).saveNow();
    }

    // 前置 4：更新章节最后诊断时间（仅整章诊断）+ 教学阶段 P1_WORLD
    if (!isSelection) {
      await ChapterRepository(db).updateChapterDiagnosedAt(widget.chapterId);
    }
    // 批次6 M1：阶段迁移合法性校验——仅当当前阶段允许 P1（P0 或同阶段）时才写入，
    // 防止已到 P2+ 的学员被整章诊断非法回退到 P1（validatePhaseTransition 拦截降级）。
    try {
      final ts = await TeachingStateRepository(db).getTeachingState(sid);
      final currentPhase =
          TeachingPhase.fromString(ts?.currentPhase) ?? TeachingPhase.p0Engage;
      if (validatePhaseTransition(currentPhase, TeachingPhase.p1World)) {
        await TeachingStateRepository(
          db,
        ).updatePhase(sid, TeachingPhase.p1World.value);
      }
    } catch (e) {
      // 迁移失败不阻断诊断主流程（保守策略，静默）
    }

    // D2：长度路由 — 内容 > THRESHOLD(4000) 时分块，否则单次
    // 调用方 onContent/onComplete：统一由 sendMessage 流程处理
    final store = ref.read(
      writingCoachStoreProvider(widget.chapterId).notifier,
    );
    store.setStreaming(true);

    // 1. 先把用户消息加到内存 store（即时反馈）
    final now = DateTime.now().millisecondsSinceEpoch;
    final userMsg = Message(
      id: now.toString(),
      sessionId: sid,
      role: 'user',
      content: isSelection ? '请诊断以下选中文本' : '请诊断本章内容',
      timestamp: now ~/ 1000,
      messageType: 'chat',
    );
    ref
        .read(writingCoachStoreProvider(widget.chapterId).notifier)
        .addMessage(userMsg);

    // 2. 构造单次诊断 prompt（对齐 RN chat.tsx#L212：显式要求 [YS_DIAGNOSIS] 格式）
    final diagPrompt = isSelection
        ? '请对以下选中文本进行写作诊断分析：\n\n'
              '【选段】\n'
              '$content\n\n'
              '---\n'
              '重要：诊断说明后必须输出 [YS_DIAGNOSIS]...[/YS_DIAGNOSIS] 包裹的 JSON 块，'
              '含 syndromes 数组（每条含 syndrome_id/name/severity/evidence/explanation）、'
              'suggested_actions（数组）、confidence（0-1）。'
              '此结构化数据用于驱动后续教学流程，不可缺少。'
        : '请对以下章节内容进行写作诊断分析：\n\n'
              '【$title】\n\n'
              '$content\n\n'
              '---\n'
              '重要：诊断说明后必须输出 [YS_DIAGNOSIS]...[/YS_DIAGNOSIS] 包裹的 JSON 块，'
              '含 syndromes 数组（每条含 syndrome_id/name/severity/evidence/explanation）、'
              'suggested_actions（数组）、confidence（0-1）。'
              '此结构化数据用于驱动后续教学流程，不可缺少。';

    // 统一的完成/错误回调，分块/单次都复用
    Future<void> handleDiagnosisComplete() async {
      final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
      final messages = await sessionRepo.listMessages(sid);
      ref
          .read(writingCoachStoreProvider(widget.chapterId).notifier)
          .setMessages(messages);
      ref
          .read(writingCoachStoreProvider(widget.chapterId).notifier)
          .setStreaming(false);
      // D5-A：复位诊断中标志 + 完成反馈（短时 SnackBar，不遮挡后续操作）
      if (mounted) {
        setState(() {
          _isDiagnosing = false;
          _streamStageLabel = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('诊断完成'),
            duration: const Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    handleDiagnosisError(String error) {
      if (mounted) {
        setState(() {
          _isDiagnosing = false;
          _streamStageLabel = null;
        });
      }
      ref
          .read(writingCoachStoreProvider(widget.chapterId).notifier)
          .setError(error);
    }

    try {
      // D2：长度路由 — 先尝试分块链路（长文本）
      final progressive = await runProgressiveDiagnosis(
        content: content,
        title: title,
        llmClient: ref.read(llmClientProvider),
        sessionId: sid,
        onContent: (delta) {
          ref
              .read(writingCoachStoreProvider(widget.chapterId).notifier)
              .appendStreamingContent(delta);
        },
      );

      if (progressive != null) {
        // D4-A：分块链路完成 → 解析+持久化+卡片插入
        final chatService = ref.read(chatServiceProvider);
        await chatService.commitDiagnosisFromContent(
          sessionId: sid,
          fullContent: progressive.fullContent,
        );
        await handleDiagnosisComplete();
        return;
      }

      // 分块链路返回 null（内容 <= THRESHOLD，不触发分块）
      // → 走 D1 已接通的单次 ChatService.sendMessage 链路
      final chatService = ref.read(chatServiceProvider);
      await chatService.sendMessage(
        sid,
        diagPrompt,
        SendMessageCallbacks(
          onStream: (delta) {
            ref
                .read(writingCoachStoreProvider(widget.chapterId).notifier)
                .appendStreamingContent(delta);
          },
          onComplete: (_, _) => handleDiagnosisComplete(),
          onError: handleDiagnosisError,
        ),
        SendMessageOptions(
          phase: TeachingPhase.p1World,
          attitude: AttitudeLevel.doubao,
          // 批次64（B62g）：透传编辑器活动时间戳，心流判定叠加编辑活跃
          lastEditorEditAtSec: ref.read(editorActivityProvider),
        ),
      );
    } catch (e) {
      handleDiagnosisError(e.toString());
    }
  }
}
