// ─────────────────────────────────────────────────────────────
// writing_coach_panel 的 part 文件：UI builders
// 覆盖 _buildButtonRow / _buildErrorBanner / _buildMessageList /
// _buildInputBar。以私有 extension on _WritingCoachPanelState 形式提供，
// 直接访问宿主私有成员（_scrollController / _isInitLoading /
// _streamStageLabel / _isDiagnosing / _sessionId / _inputController 等），
// 与教学逻辑 part 同库，可互相调用，行为与原内联实现完全一致。
// ─────────────────────────────────────────────────────────────
// ignore_for_file: invalid_use_of_protected_member
part of 'writing_coach_panel.dart';

extension _WritingCoachPanelBuilders on _WritingCoachPanelState {
  /// 按钮行：快速观察 | 诊断本章（左）| 关闭 ✕（右）
  ///
  /// D5-A：流式/诊断中时禁用按钮，避免重复触发
  /// 批次69（A7 双通道）：「快速观察」= 实时通道（轻 prompt，Editor 观察）
  Widget _buildButtonRow(bool isStreaming) {
    // 批次82 P0-④：侧栏宽度受限 → 收紧按钮内边距，避免窄屏溢出
    final btnStyle = TextButton.styleFrom(
      // X-039-Batch1：8→sm
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Row(
      children: [
        TextButton.icon(
          style: btnStyle,
          onPressed: isStreaming ? null : _handleRealtimeObserve,
          icon: Icon(
            Icons.bolt,
            color: isStreaming ? AppColors.disabledText : AppColors.primary,
          ),
          label: Text(
            '快速观察',
            style: TextStyle(
              fontSize: 13,
              color: isStreaming ? AppColors.disabledText : AppColors.primary,
            ),
          ),
        ),
        TextButton.icon(
          style: btnStyle,
          onPressed: isStreaming ? null : _handleDiagnose,
          icon: Icon(
            Icons.analytics_outlined,
            color: isStreaming ? AppColors.disabledText : AppColors.primary,
          ),
          label: Text(
            '诊断本章',
            style: TextStyle(
              fontSize: 13,
              color: isStreaming ? AppColors.disabledText : AppColors.primary,
            ),
          ),
        ),
        const Spacer(),
        IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose),
      ],
    );
  }

  /// 错误横幅：浅红底 + 错误图标 + 错误文本 + 关闭按钮
  Widget _buildErrorBanner(ChatState chatState) {
    return Container(
      color: AppColors.dangerBg,
      // X-039-Batch1：12→md
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              // release 静默：不向用户展示异常技术细节（对齐 P2-7 铁律）
              kDebugMode ? chatState.error! : '发送失败，请稍后重试',
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: () => ref
                .read(writingCoachStoreProvider(widget.chapterId).notifier)
                .clearError(),
            child: const Icon(Icons.close, size: 16, color: AppColors.danger),
          ),
        ],
      ),
    );
  }

  /// 消息列表：初始化中 loading，空状态居中提示，否则 ListView 复用 MessageBubble
  Widget _buildMessageList(ChatState chatState) {
    // P2-3：初始化未完成时显示 loading，避免先闪空状态再突然出现消息
    if (_isInitLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    // T3：练习任务卡 + 结果指示器（activePracticeTask / trainingResult 非空时渲染在列表底部）
    final practiceState = ref.watch(practiceStoreProvider);
    // T4：评估报告（messageId → EvaluationData）
    final evaluationState = ref.watch(evaluationReportsProvider);
    final practiceWidgets = <Widget>[];
    if (practiceState.activePracticeTask != null) {
      practiceWidgets.add(
        PracticeTaskCard(
          task: practiceState.activePracticeTask!,
          submitting: practiceState.isSubmitting,
          onSubmit: _submitPractice,
          onSkip: () {
            ref.read(practiceStoreProvider.notifier).skipPractice();
          },
        ),
      );
    }
    if (practiceState.trainingResult != null) {
      practiceWidgets.add(
        PracticeResultIndicator(
          result: practiceState.trainingResult!,
          onDismiss: () {
            ref.read(practiceStoreProvider.notifier).setTrainingResult(null);
          },
          onRetry: () {
            ref.read(practiceStoreProvider.notifier).retryPractice();
          },
        ),
      );
    }
    if (chatState.messages.isEmpty && !chatState.isStreaming) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: AppColors.disabledText,
            ),
            SizedBox(height: 8),
            Text('有问题问教练', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            // X-039-Batch1：12→md / 8→sm
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            itemCount:
                chatState.messages.length + (chatState.isStreaming ? 1 : 0),
            itemBuilder: (context, index) {
              // 流式占位气泡（列表末尾，isStreaming 时）
              if (index == chatState.messages.length && chatState.isStreaming) {
                // D5-A：尚无流式内容时显示「思考/诊断中…」占位，而非空气泡
                // 批次51：诊断阶段（阶段标签以「正在诊断」开头）即使已有流式内容
                // 也显示占位——诊断交付物是 DiagnosisCard，隐藏流式前导文本，
                // 避免「先长文本后变卡片」跳变；评估/快速观察等保留流式文本。
                final isDiagnosisStage =
                    _streamStageLabel?.startsWith('正在诊断') ?? false;
                if (chatState.streamingContent.isEmpty || isDiagnosisStage) {
                  return RepaintBoundary(
                    key: const ValueKey('coach-item-thinking'),
                    child: ThinkingPlaceholder(
                      isDiagnosing: _isDiagnosing,
                      label: _streamStageLabel,
                    ),
                  );
                }
                final streamMsg = Message(
                  id: '__streaming__',
                  sessionId: _sessionId ?? '',
                  role: 'assistant',
                  content: chatState.streamingContent,
                  timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  messageType: 'chat',
                );
                final streamBubble = MessageBubble(
                  message: streamMsg,
                  isStreaming: true,
                );
                // 批次49：流式气泡顶部加阶段角标（与 message_list 一致）
                if (_streamStageLabel != null) {
                  return RepaintBoundary(
                    key: const ValueKey('coach-item-__streaming__'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          // X-039-Batch1：12→md / 2→xxs
                          padding: const EdgeInsets.only(
                            left: AppSpacing.md,
                            bottom: AppSpacing.xxs,
                          ),
                          child: Text(
                            _streamStageLabel!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                        streamBubble,
                      ],
                    ),
                  );
                }
                return RepaintBoundary(
                  key: const ValueKey('coach-item-__streaming__'),
                  child: streamBubble,
                );
              }
              final msg = chatState.messages[index];
              // 批次5（5.1）：卡片分派统一走 MessageCardDispatcher
              //（diagnosis_result/teacher_suggestion/outline_confirmation/评估报告/
              //  suggestion 采纳按钮 均由其处理；不命中回退 MessageBubble）
              final card = dispatchMessageCard(
                msg: msg,
                isStreamingBubble: false,
                evaluationReport: evaluationState.reports[msg.id],
                onTeachPrinciple: _handleTeachPrinciple,
                onDismissEvaluationReport: () => ref
                    .read(evaluationReportsProvider.notifier)
                    .dismissEvaluationReport(msg.id),
                onAdoptSuggestion: widget.onAdopt != null
                    ? () => widget.onAdopt!(msg.content)
                    : null,
                // 批次81：三卡回调接线（H1-H3）
                onContinueTraining: () =>
                    ref.read(practiceStoreProvider.notifier).retryPractice(),
                onViewProfile: () => context.push(AppRoutes.growthDetail),
                onBackToChat: _focusInput,
                onAddContent: _focusInput,
                onContinueChat: _focusInput,
                onPartialAgreementSubmit: _handlePartialAgreementSubmit,
                onPartialAgreementSkip: _handlePartialAgreementSkip,
              );
              if (card != null) {
                // 批次53：RepaintBoundary 隔离——流式期间全列表 rebuild 时
                // 每消息绘制/动画独立，不扩散到兄弟 item，降低每 token 重绘开销
                // 批次74：卡片消息同样支持长按删除（对齐对话页长按删除心智）
                return RepaintBoundary(
                  key: ValueKey('coach-item-${msg.id}'),
                  child: GestureDetector(
                    onLongPress: () => _confirmDeleteMessage(msg),
                    child: card,
                  ),
                );
              }
              // 批次74：普通气泡长按删除（对齐对话页长按删除心智）
              return RepaintBoundary(
                key: ValueKey('coach-item-${msg.id}'),
                child: MessageBubble(
                  message: msg,
                  onLongPress: _confirmDeleteMessage,
                ),
              );
            },
          ),
        ),
        // T3：练习任务卡 + 结果指示器（列表底部）
        ...practiceWidgets,
      ],
    );
  }

  /// 输入栏：TextField + 发送按钮，回车发送
  Widget _buildInputBar(ChatState chatState) {
    // P1-7 修复：键盘弹起时输入栏需要加上 viewInsets.bottom 的 padding，
    // 否则输入栏会被键盘完全顶出可视区。
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      // X-039-Batch1：16→lg / 8→sm / +bottomInset（动态值，不令牌）
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm + bottomInset,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              decoration: InputDecoration(
                hintText: '问教练...',
                border: OutlineInputBorder(
                  // X-039-Batch1：24→xl
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  // X-039-Batch1：16→lg / 10→smx
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.smx,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, color: AppColors.primary),
            onPressed: chatState.isStreaming ? null : () => _handleSend(),
          ),
        ],
      ),
    );
  }
}
