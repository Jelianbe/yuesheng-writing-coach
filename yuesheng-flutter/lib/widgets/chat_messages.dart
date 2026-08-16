// ignore_for_file: invalid_use_of_protected_member
part of 'chat_page.dart';

extension _ChatMessages on _ChatPageState {

  /// 更多菜单「画像」：跳转能力画像页（对齐 RN onOpenProfile → StudentProfilePanel）
  /// 批次78：pushNamed 误用（go_router 路由不注册 Navigator 命名表，点击必失败）→ context.push
  void _handleOpenProfile() {
    if (!mounted) return;
    context.push(AppRoutes.growthDetail);
  }

  /// H1 PhaseSummaryCard「继续训练」→ 重开上次练习任务（再练一轮，T3 训练系统）
  void _handleContinueTraining() {
    ref.read(practiceStoreProvider.notifier).retryPractice();
  }

  /// H1 PhaseSummaryCard「查看学员画像」→ 能力画像页（复用批次78修复入口）
  void _handleViewProfile() => _handleOpenProfile();

  /// H1「返回对话」/ H2「补充内容」「继续对话」→ 聚焦输入框继续对话
  void _handleFocusChatInput() {
    _chatInputKey.currentState?.focusInput();
  }

  /// H3 PartialAgreementCard 提交反馈 / 快速选项 →
  /// 以用户消息发给教练并请求调整诊断（杜绝静默清空：反馈已真实落库为消息）
  void _handlePartialAgreementSubmit(String feedback, String? quickOption) {
    if (ref.read(chatStoreProvider).isStreaming) return;
    final detail = quickOption != null ? quickOptionLabel(quickOption) : feedback;
    if (detail.trim().isEmpty) return;
    _handleSend('我对刚才的诊断结果有不同看法：$detail。请根据我的反馈调整诊断。');
  }

  /// H3 PartialAgreementCard 跳过此症候 → 以用户消息请求重新诊断
  void _handlePartialAgreementSkip() {
    if (ref.read(chatStoreProvider).isStreaming) return;
    _handleSend('请跳过这个症候，重新给出诊断结果。');
  }

  /// 重试上次失败的消息
  Future<void> _handleRetry(String failedMessageId) async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    // 从失败集合中移除
    ref.read(chatStoreProvider.notifier).clearMessageFailed(failedMessageId);

    // 找到失败消息的内容，重新发送
    final chatState = ref.read(chatStoreProvider);
    final failedMsg = chatState.messages
        .where((m) => m.id == failedMessageId)
        .firstOrNull;
    if (failedMsg == null) return;

    await _handleSend(failedMsg.content);
  }

  /// 删除消息：从 DB 删除 + 从内存列表移除
  Future<void> _handleDelete(String messageId) async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) {
      debugPrint('[ChatPage] 删除失败：bootstrap 为空');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前不可用，请稍后再试')));
      }
      return;
    }

    debugPrint(
      '[ChatPage] 开始删除消息 sessionId=${bootstrap.sessionId} messageId=$messageId',
    );
    final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
    try {
      await sessionRepo.deleteMessage(bootstrap.sessionId, messageId);
      debugPrint('[ChatPage] DB 删除成功 messageId=$messageId');
    } catch (e) {
      debugPrint('[ChatPage] DB 删除失败 messageId=$messageId error=$e');
      // P0-3 修复：不要 rethrow 让页面炸，给用户明确失败反馈
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后再试')));
      }
      return;
    }
    ref.read(chatStoreProvider.notifier).removeMessage(messageId);
    debugPrint('[ChatPage] 内存列表移除完成 messageId=$messageId');
  }

  Future<void> _handleOnboardingComplete(OnboardingData data) async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final onboardingService = ref.read(onboardingServiceProvider);
    await onboardingService.submitOnboarding(bootstrap.sessionId, data);
    await ref.read(sessionBootstrapProvider.notifier).refresh();
  }

  Future<void> _handleOnboardingSkip() async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final onboardingService = ref.read(onboardingServiceProvider);
    await onboardingService.skipOnboarding(bootstrap.sessionId);
    await ref.read(sessionBootstrapProvider.notifier).refresh();
  }
}
