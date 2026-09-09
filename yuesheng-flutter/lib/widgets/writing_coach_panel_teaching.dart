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
      builder: (ctx) => _buildDeleteConfirmDialog(ctx),
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

  /// 删除确认对话框（R-019 清偿：_confirmDeleteMessage 拆出）。
  Widget _buildDeleteConfirmDialog(BuildContext dialogCtx) {
    return AlertDialog(
      title: const Text('删除消息', style: AppTextStyles.titleLg),
      content: const Text(
        '确定要删除这条消息吗？此操作不可撤销。',
        textAlign: TextAlign.center,
        style: AppTextStyles.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          style: AppButtonStyles.secondary,
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
          onPressed: () => Navigator.pop(dialogCtx, true),
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
    );
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

    // ADR-C81 懒创建：发送是「产生内容」入口，此处才真正创建会话
    final sid = await _ensureSession();
    if (sid == null) return;

    // ADR-C86：发送即清空输入栏（对齐主流 AI 对话体验——消息已发出，
    // 输入栏立即可编辑下一条，不等 AI 回复）。会话确保成功后才清空，
    // 避免会话创建失败时用户输入丢失。
    _inputController.clear();

    // 2. 接入 ChatService 流式发送（onUserMessagePersisted：用户消息
    //    落库即上屏、真实消息 id——与对话页 ADR-C84 一致，流式中断/
    //    失败也保证消息可见且可管理）
    final store = ref.read(
      writingCoachStoreProvider(widget.chapterId).notifier,
    );
    store.setStreaming(true);
    // ADR-C87：本次发送的取消令牌（供「停止生成」按钮在流式中段中止）
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      await _runSendMessage(
        sid: sid,
        text: text,
        store: store,
        subphase: subphase,
        onTrainingResult: onTrainingResult,
        cancelToken: cancelToken,
      );
    } catch (e) {
      if (mounted) setState(() => _streamStageLabel = null);
      // ADR-C88：快速观察改非流式后，取消（chatCompletion 抛
      // DioExceptionType.cancel）原样上抛至此——优雅复位，不标记失败不弹红错。
      if (e is DioException && e.type == DioExceptionType.cancel) {
        store.cancelStreaming();
        return;
      }
      store.setError(e.toString());
    } finally {
      _cancelToken = null;
    }
  }

  /// ChatService.sendMessage 调用 + 流式回调（R-019 清偿：_handleSend 拆出）。
  Future<void> _runSendMessage({
    required String sid,
    required String text,
    required ChatStore store,
    TeachingSubphase? subphase,
    void Function(TrainingResult)? onTrainingResult,
    required CancelToken cancelToken,
  }) async {
    final chatService = ref.read(chatServiceProvider);
    await chatService.sendMessage(
      sid,
      text,
      SendMessageCallbacks(
        onUserMessagePersisted: (message) {
          store.addMessage(message);
        },
        onStream: (delta) {
          store.appendStreamingContent(delta);
        },
        onComplete: (fullContent, messageId) async {
          final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
          final messages = await sessionRepo.listMessages(sid);
          store.setMessages(messages);
          store.setStreaming(false);
          // 批次49：复位阶段标签
          if (mounted) setState(() => _streamStageLabel = null);
        },
        onError: (error) {
          store.setError(error);
        },
        onCancelled: () {
          // 用户主动停止：优雅复位（不标记失败、不弹红错）
          store.cancelStreaming();
        },
        onTrainingResult: onTrainingResult,
      ),
      SendMessageOptions(
        phase: TeachingPhase.p0Engage,
        attitude: AttitudeLevel.doubao,
        // 批次64（B62g）：透传编辑器活动时间戳，心流判定叠加编辑活跃
        lastEditorEditAtSec: ref.read(editorActivityProvider),
        // ADR-C87：取消令牌——流式中可主动中止
        cancelToken: cancelToken,
      ),
      subphase: subphase,
    );
  }

  /// ADR-C87：主动停止当前生成（「停止生成」按钮回调）。
  /// 取消底层 Dio 请求 → 流被中断 → sendMessage 走 onCancelled 优雅复位；
  /// 快速观察走 callEditorStream 兜底文案（显示失败提示，不崩溃）。
  void _cancelGeneration() {
    _cancelToken?.cancel('用户取消生成');
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
    // ADR-C81 懒创建：快速观察是「产生内容」入口，此处才真正创建会话
    // ADR-C66：门槛取自 UILimits（字数不足时弹提示并返回 null）
    final prepared = await _ensureObserveSession();
    if (prepared == null) return;
    final sid = prepared.sid;
    final content = prepared.content;

    // 批次49：快速观察阶段标签
    if (mounted) setState(() => _streamStageLabel = '正在快速观察…');
    final store = ref.read(
      writingCoachStoreProvider(widget.chapterId).notifier,
    );
    store.setStreaming(true);
    // ADR-C87：本次观察的取消令牌（「停止生成」按钮可中止）
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    try {
      await _runObserve(
        sid: sid,
        content: content,
        store: store,
        cancelToken: cancelToken,
      );
    } catch (e) {
      if (mounted) setState(() => _streamStageLabel = null);
      // ADR-C88：快速观察改非流式后，取消（chatCompletion 抛
      // DioExceptionType.cancel）原样上抛至此——优雅复位，不标记失败不弹红错。
      if (e is DioException && e.type == DioExceptionType.cancel) {
        store.cancelStreaming();
        return;
      }
      store.setError(e.toString());
    } finally {
      _cancelToken = null;
    }
  }

  /// 快速观察前置：会话懒创建 + 字数校验（R-019 清偿拆出：_handleRealtimeObserve）。
  ///
  /// 字数不足（<50 字）时弹提示并返回 null，不发起观察。
  Future<({String sid, String content})?> _ensureObserveSession() async {
    final sid = await _ensureSession();
    if (sid == null) return null;

    // 字数校验：实时观察要求至少 50 字（短文本观察无意义）
    //
    // ADR-C66：门槛取自 UILimits，与诊断门槛同理（避免常量与文案双份维护）。
    final writingState = ref.read(writingStoreProvider(widget.chapterId));
    final content = writingState.localContent;
    if (content.trim().length < UILimits.quickObservationWordThreshold) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '请至少写 ${UILimits.quickObservationWordThreshold} 字后再快速观察',
          ),
        ),
      );
      return null;
    }
    return (sid: sid, content: content);
  }

  /// RealtimeObservationService.observe 调用 + 刷新消息（R-019 清偿拆出）。
  Future<void> _runObserve({
    required String sid,
    required String content,
    required ChatStore store,
    required CancelToken cancelToken,
  }) async {
    await ref
        .read(realtimeObservationServiceProvider)
        .observe(
          sessionId: sid,
          text: content,
          targetRefType: 'chapter',
          targetRefId: widget.chapterId,
          onStream: (delta) {
            store.appendStreamingContent(delta);
          },
          cancelToken: cancelToken,
        );

    // observe 内部已写入 assistant 消息 → 刷新消息列表
    final messages = await SessionRepository(
      ref.read(appDatabaseProvider),
    ).listMessages(sid);
    store.setMessages(messages);
    store.setStreaming(false);
    // 批次49：复位阶段标签，避免残留到下一次流式
    if (mounted) setState(() => _streamStageLabel = null);
  }

  /// 诊断入口：selectedText 非空 → 选段诊断（B3 划词诊断）；否则整章诊断
  ///
  /// 对齐 RN chapter-editor.tsx#L254-L284（整章）与 #L331-L365（选段）：
  ///   1. saveContent：先把编辑器当前内容落库（避免诊断到旧版本，仅整章诊断）
  ///   2. updateChapterDiagnosedAt：写章节最后诊断时间（仅整章诊断）
  ///   3. updatePhase(P1_WORLD)：状态机流转，否则 syndrome-diagnosis-index 不加载
  ///
  /// R-019 清偿：前置（会话/输入解析/整章准备）与链路（分块/单次）拆至子方法。
  Future<void> _handleDiagnoseWithText(String? selectedText) async {
    // ADR-C81 懒创建：诊断（整章/划词）是「产生内容」入口，此处才真正创建会话
    final sid = await _ensureSession();
    if (sid == null) return;

    // D5-A：诊断中置位（驱动「诊断中…」占位 + 按钮禁用态）
    // 批次49：同时设阶段标签（选段/整章区分文案）
    final input = _resolveDiagnosisInput(selectedText);
    if (input == null) return;
    if (mounted) {
      setState(() {
        _isDiagnosing = true;
        _streamStageLabel = input.isSelection ? '正在诊断选段…' : '正在诊断本章…';
      });
    }

    await _prepareChapterDiagnosis(sid, input.isSelection);

    // D2：长度路由 — 内容 > THRESHOLD(4000) 时分块，否则单次
    // 调用方 onContent/onComplete：统一由 sendMessage 流程处理
    final store = ref.read(
      writingCoachStoreProvider(widget.chapterId).notifier,
    );
    store.setStreaming(true);
    // 1. 先把用户消息加到内存 store（即时反馈）
    store.addMessage(_buildDiagnosisUserMessage(sid, input.isSelection));
    // 2. 构造单次诊断 prompt（对齐 RN chat.tsx#L212：显式要求 [YS_DIAGNOSIS] 格式）
    final diagPrompt = _buildDiagnosisPrompt(input.title, input.isSelection);

    await _runDiagnosisChain(
      sid: sid,
      content: input.content,
      title: input.title,
      diagPrompt: diagPrompt,
      isSelection: input.isSelection,
    );
  }

  /// 诊断输入解析：内容来源（选中文本或整章）+ 字数校验（R-019 清偿拆出）。
  ///
  /// 字数不足时弹提示并返回 null（不继续诊断）。
  ({String content, String title, bool isSelection})? _resolveDiagnosisInput(
    String? selectedText,
  ) {
    final isSelection = selectedText != null && selectedText.trim().isNotEmpty;
    final writingState = ref.read(writingStoreProvider(widget.chapterId));
    final content = isSelection
        ? selectedText.trim()
        : writingState.localContent;
    final title = writingState.chapter?.title ?? widget.chapterTitle;

    // 前置 2：字数校验（选段 ≥20 字 / 整章 ≥100 字，对齐 RN）
    //
    // ADR-C66：两档阈值统一取自 UILimits，避免此处硬编码与常量各说一套。
    final minLength = isSelection
        ? UILimits.diagnosisSelectionWordThreshold
        : UILimits.diagnosisWordThreshold;
    if (content.trim().length < minLength) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSelection
                ? '请至少选择 ${UILimits.diagnosisSelectionWordThreshold} 字以上的文本进行诊断'
                : '请至少输入 ${UILimits.diagnosisWordThreshold} 字后再提交诊断',
          ),
        ),
      );
      return null;
    }
    return (content: content, title: title, isSelection: isSelection);
  }

  /// 整章诊断前置：未保存内容落库 + 诊断时间 + P1 阶段迁移（R-019 清偿拆出）。
  Future<void> _prepareChapterDiagnosis(String sid, bool isSelection) async {
    // 前置 3：把未保存内容落库，避免诊断到旧版本（仅整章诊断；选段诊断不落库）
    if (!isSelection) {
      await ref.read(writingStoreProvider(widget.chapterId).notifier).saveNow();
    }

    // 前置 4：更新章节最后诊断时间（仅整章诊断）+ 教学阶段 P1_WORLD
    if (!isSelection) {
      final db = ref.read(appDatabaseProvider);
      await ChapterRepository(db).updateChapterDiagnosedAt(widget.chapterId);
      // 批次6 M1：阶段迁移合法性校验——仅当当前阶段允许 P1（P0 或同阶段）时才写入，
      // 防止已到 P2+ 的学员被整章诊断非法回退到 P1（validatePhaseTransition 拦截降级）。
      try {
        final ts = await TeachingStateRepository(db).getTeachingState(sid);
        final currentPhase =
            TeachingPhase.fromString(ts?.currentPhase) ??
            TeachingPhase.p0Engage;
        if (validatePhaseTransition(currentPhase, TeachingPhase.p1World)) {
          await TeachingStateRepository(
            db,
          ).updatePhase(sid, TeachingPhase.p1World.value);
        }
      } catch (e) {
        // 迁移失败不阻断诊断主流程（保守策略，静默）
      }
    }
  }

  /// 诊断用户消息（R-019 清偿拆出：_handleDiagnoseWithText）。
  Message _buildDiagnosisUserMessage(String sid, bool isSelection) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Message(
      id: now.toString(),
      sessionId: sid,
      role: 'user',
      content: isSelection ? '请诊断以下选中文本' : '请诊断本章内容',
      timestamp: now ~/ 1000,
      messageType: 'chat',
    );
  }

  /// 单次诊断 prompt（对齐 RN chat.tsx#L212：显式要求 [YS_DIAGNOSIS] 格式，
  /// R-019 清偿拆出：_handleDiagnoseWithText）。
  // 批次98：对话历史只展示简洁消息（「已发送章节」），全文由
  // SendMessageOptions.chapterFullText 运行时注入（不落库，AI 仍收到全部内容）。
  String _buildDiagnosisPrompt(String title, bool isSelection) {
    return isSelection ? '请诊断选中文本' : '请诊断本章：《$title》';
  }

  /// 诊断完成：刷新消息 + 复位流式/诊断中 + 完成反馈（R-019 清偿拆出）。
  Future<void> _handleDiagnosisComplete(String sid) async {
    final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
    final messages = await sessionRepo.listMessages(sid);
    final store = ref.read(
      writingCoachStoreProvider(widget.chapterId).notifier,
    );
    store.setMessages(messages);
    store.setStreaming(false);
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

  /// 诊断错误：复位诊断中标志 + 写入 store 错误（R-019 清偿拆出）。
  void _handleDiagnosisError(String error) {
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

  /// 用户主动停止诊断：优雅复位（不标记失败、不弹红错，R-019 清偿拆出）。
  void _handleDiagnosisCancelled() {
    ref
        .read(writingCoachStoreProvider(widget.chapterId).notifier)
        .cancelStreaming();
    if (mounted) {
      setState(() {
        _isDiagnosing = false;
        _streamStageLabel = null;
      });
    }
  }

  /// 诊断链路编排：共用取消令牌 + 分块/单次路由 + 取消/错误处理（R-019 清偿拆出）。
  Future<void> _runDiagnosisChain({
    required String sid,
    required String content,
    required String title,
    required String diagPrompt,
    required bool isSelection,
  }) async {
    // ADR-C87 延伸：诊断全链路（分块+单次）共用取消令牌
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      await _runProgressiveOrSend(
        sid: sid,
        content: content,
        title: title,
        diagPrompt: diagPrompt,
        isSelection: isSelection,
        cancelToken: cancelToken,
      );
    } on ProgressiveDiagnosisCancelled {
      // 用户主动停止分块诊断：优雅复位（不标记失败、不弹红错）
      _handleDiagnosisCancelled();
    } catch (e) {
      _handleDiagnosisError(e.toString());
    } finally {
      _cancelToken = null;
    }
  }

  /// 长度路由执行：先分块链路（长文本），null（≤THRESHOLD）则单次 sendMessage
  /// （R-019 清偿拆出：_runDiagnosisChain）。
  Future<void> _runProgressiveOrSend({
    required String sid,
    required String content,
    required String title,
    required String diagPrompt,
    required bool isSelection,
    required CancelToken cancelToken,
  }) async {
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
      // ADR-C87 延伸：分块诊断中途可取消（每块前/合并前检查）
      cancelToken: cancelToken,
    );

    final store = ref.read(
      writingCoachStoreProvider(widget.chapterId).notifier,
    );
    final chatService = ref.read(chatServiceProvider);
    if (progressive != null) {
      // D4-A：分块链路完成 → 解析+持久化+卡片插入
      await chatService.commitDiagnosisFromContent(
        sessionId: sid,
        fullContent: progressive.fullContent,
      );
      await _handleDiagnosisComplete(sid);
      return;
    }

    // 分块链路返回 null（内容 <= THRESHOLD，不触发分块）
    // → 走 D1 已接通的单次 ChatService.sendMessage 链路
    await _runSingleDiagnosisSend(
      sid: sid,
      diagPrompt: diagPrompt,
      fullText: content,
      store: store,
      chatService: chatService,
      cancelToken: cancelToken,
    );
  }

  /// 单次诊断 sendMessage（D1 链路；R-019 清偿拆出：_runProgressiveOrSend）。
  Future<void> _runSingleDiagnosisSend({
    required String sid,
    required String diagPrompt,
    required String fullText,
    required ChatStore store,
    required dynamic chatService,
    required CancelToken cancelToken,
  }) async {
    await chatService.sendMessage(
      sid,
      diagPrompt,
      SendMessageCallbacks(
        onStream: (delta) {
          store.appendStreamingContent(delta);
        },
        onComplete: (_, _) => _handleDiagnosisComplete(sid),
        onError: _handleDiagnosisError,
        onCancelled: () {
          // 用户主动停止诊断：优雅复位（不标记失败、不弹红错）
          _handleDiagnosisCancelled();
        },
      ),
      SendMessageOptions(
        phase: TeachingPhase.p1World,
        attitude: AttitudeLevel.doubao,
        // 批次64（B62g）：透传编辑器活动时间戳，心流判定叠加编辑活跃
        lastEditorEditAtSec: ref.read(editorActivityProvider),
        // ADR-C87：取消令牌——诊断中可主动中止
        cancelToken: cancelToken,
        // 批次98：诊断全文运行时注入（不落库，对话历史只展示简洁消息）
        chapterFullText: fullText,
      ),
    );
  }
}
