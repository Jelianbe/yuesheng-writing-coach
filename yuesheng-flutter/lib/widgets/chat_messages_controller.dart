// ─────────────────────────────────────────────────────────────
// chat_messages_controller — 聊天页消息/引导/画像动作控制器
//
// 从 chat_messages.dart（原 part/extension）真分解而来：
//   handleOpenProfile / handleContinueTraining / handleViewProfile
//   / handleFocusChatInput / handlePartialAgreementSubmit
//   / handlePartialAgreementSkip / handleRetry / handleDelete
//   / handleOnboardingComplete / handleOnboardingSkip / maybeShowPrivacyNotice
//
// 依赖经 [ChatPageHost] 显式注入；发送委托 [ChatTeachingController]。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/app_state_repository.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/practice_providers.dart';
import '../providers/session_providers.dart';
import '../router/app_routes.dart';
import '../types/teaching_types.dart';
import 'chat_page_host.dart';
import 'chat_teaching_controller.dart';
import 'partial_agreement_card.dart';
import 'privacy_notice_dialog.dart';

/// 聊天页消息与画像相关动作
class ChatMessagesController {
  final ChatPageHost host;
  final ChatTeachingController teaching;

  ChatMessagesController(this.host, this.teaching);

  /// 更多菜单「画像」：跳转能力画像页（对齐 RN onOpenProfile）。
  /// 批次78：pushNamed 误用（go_router 路由不注册 Navigator 命名表，点击必失败）→ push
  void handleOpenProfile() {
    if (!host.mounted) return;
    host.context.push(AppRoutes.growthDetail);
  }

  /// H1 PhaseSummaryCard「继续训练」→ 重开上次练习任务（再练一轮，T3 训练系统）
  void handleContinueTraining() {
    host.ref.read(practiceStoreProvider.notifier).retryPractice();
  }

  /// H1 PhaseSummaryCard「查看学员画像」→ 能力画像页（复用批次78修复入口）
  void handleViewProfile() => handleOpenProfile();

  /// H1「返回对话」/ H2「补充内容」「继续对话」→ 聚焦输入框继续对话
  void handleFocusChatInput() {
    host.chatInputKey.currentState?.focusInput();
  }

  /// H3 PartialAgreementCard 提交反馈 / 快速选项 →
  /// 以用户消息发给教练并请求调整诊断（杜绝静默清空：反馈已真实落库为消息）
  void handlePartialAgreementSubmit(String feedback, String? quickOption) {
    if (host.ref.read(chatStoreProvider).isStreaming) return;
    final detail = quickOption != null
        ? quickOptionLabel(quickOption)
        : feedback;
    if (detail.trim().isEmpty) return;
    teaching.handleSend('我对刚才的诊断结果有不同看法：$detail。请根据我的反馈调整诊断。');
  }

  /// H3 PartialAgreementCard 跳过此症候 → 以用户消息请求重新诊断
  void handlePartialAgreementSkip() {
    if (host.ref.read(chatStoreProvider).isStreaming) return;
    teaching.handleSend('请跳过这个症候，重新给出诊断结果。');
  }

  /// 重试上次失败的消息
  Future<void> handleRetry(String failedMessageId) async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    // 从失败集合中移除
    host.ref
        .read(chatStoreProvider.notifier)
        .clearMessageFailed(failedMessageId);

    // 找到失败消息的内容，重新发送
    final chatState = host.ref.read(chatStoreProvider);
    final failedMsg = chatState.messages
        .where((m) => m.id == failedMessageId)
        .firstOrNull;
    if (failedMsg == null) return;

    await teaching.handleSend(failedMsg.content);
  }

  /// 删除消息：从 DB 删除 + 从内存列表移除
  Future<void> handleDelete(String messageId) async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) {
      debugPrint('[ChatPage] 删除失败：bootstrap 为空');
      if (host.mounted) {
        ScaffoldMessenger.of(
          host.context,
        ).showSnackBar(const SnackBar(content: Text('当前不可用，请稍后再试')));
      }
      return;
    }

    debugPrint(
      '[ChatPage] 开始删除消息 sessionId=${bootstrap.sessionId} messageId=$messageId',
    );
    final sessionRepo = SessionRepository(host.ref.read(appDatabaseProvider));
    try {
      await sessionRepo.deleteMessage(bootstrap.sessionId, messageId);
      debugPrint('[ChatPage] DB 删除成功 messageId=$messageId');
    } catch (e) {
      debugPrint('[ChatPage] DB 删除失败 messageId=$messageId error=$e');
      // P0-3 修复：不要 rethrow 让页面炸，给用户明确失败反馈
      if (host.context.mounted) {
        ScaffoldMessenger.of(
          host.context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后再试')));
      }
      return;
    }
    host.ref.read(chatStoreProvider.notifier).removeMessage(messageId);
    debugPrint('[ChatPage] 内存列表移除完成 messageId=$messageId');
  }

  Future<void> handleOnboardingComplete(OnboardingData data) async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final onboardingService = host.ref.read(onboardingServiceProvider);
    await onboardingService.submitOnboarding(bootstrap.sessionId, data);
    await host.ref.read(sessionBootstrapProvider.notifier).refresh();
    await maybeShowPrivacyNotice();
  }

  Future<void> handleOnboardingSkip() async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final onboardingService = host.ref.read(onboardingServiceProvider);
    await onboardingService.skipOnboarding(bootstrap.sessionId);
    await host.ref.read(sessionBootstrapProvider.notifier).refresh();
    await maybeShowPrivacyNotice();
  }

  /// v0.1 发布批：首启流程（完成/跳过）结束后一次性隐私与费用告知。
  /// 跳过问卷的用户同样告知——他们接下来就会直接发送文本，属应告知范围。
  Future<void> maybeShowPrivacyNotice() async {
    if (!host.mounted) return;
    final appState = AppStateRepository(host.ref.read(appDatabaseProvider));
    await maybeShowPrivacyNoticeOnce(host.context, appState);
  }
}
