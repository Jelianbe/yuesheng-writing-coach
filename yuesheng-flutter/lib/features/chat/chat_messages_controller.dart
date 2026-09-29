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

import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/chat_store.dart';
import '../../providers/practice_providers.dart';
import '../../providers/session_providers.dart';
import '../../router/app_routes.dart';
import '../../types/teaching_types.dart';
import 'chat_page_host.dart';
import 'chat_teaching_controller.dart';
import 'partial_agreement_card.dart';
import '../../widgets/privacy_notice_dialog.dart';

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

  /// E1-b②：评估报告面板「查看成长记录」→ 成长详情页
  /// （同跳 [AppRoutes.growthDetail]，复用批次78 修复的 push 入口）
  void handleOpenGrowth() => handleOpenProfile();

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

    // 先取出失败消息内容（删除旧行后还能凭它重发）
    final chatState = host.ref.read(chatStoreProvider);
    final failedMsg = chatState.messages
        .where((m) => m.id == failedMessageId)
        .firstOrNull;
    if (failedMsg == null) return;

    // A5：重试前先删掉该轮失败的 user 消息（DB 行 + 内存气泡）。
    // 否则 handleSend 会再走一遍 _writeUserMessage → insert 一条同内容新 user 行，
    // 每点一次重试就多一条重复 user 气泡，且这些重复问句会被 listMessages
    // 喂回上下文污染对话历史。删除后重发只产生一条 user 气泡。
    final sessionRepo = SessionRepository(host.ref.read(appDatabaseProvider));
    try {
      await sessionRepo.deleteMessage(bootstrap.sessionId, failedMessageId);
    } catch (_) {
      // 删除失败不阻断重试：新 user 行仍会写入，onComplete 整表回读时
      // 旧失败行即便残留也由后续清理入口处理，保证用户能把消息发出去。
    }
    host.ref
        .read(chatStoreProvider.notifier)
      ..removeMessage(failedMessageId)
      ..clearMessageFailed(failedMessageId);

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
