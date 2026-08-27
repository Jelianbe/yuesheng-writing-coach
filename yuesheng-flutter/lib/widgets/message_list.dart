// ─────────────────────────────────────────────────────────────
// MessageList — 消息列表（MVP 版本）
// 复刻 yuesheng-android/src/components/chat/MessageList.tsx
//
// 核心职责：
//   1. 用 ListView.builder 渲染 messages 数组
//   2. 流式时把 streamingContent 包装为虚拟消息追加到末尾
//   3. isStreaming && streamingContent 为空时显示 ThinkingIndicator
//   4. 自动滚动到底部（didUpdateWidget 检测变化 → scrollToBottom）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_motion.dart';
import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../providers/app_providers.dart';
import '../providers/practice_providers.dart';
import '../router/app_routes.dart';
import '../types/display_types.dart';
import '../types/teaching_types.dart';
import 'message_bubble.dart';
import 'message_card_dispatcher.dart';
import 'practice_result_indicator.dart';
import 'practice_task_card.dart';

class MessageList extends ConsumerStatefulWidget {
  final List<Message> messages;
  final bool isStreaming;
  final String streamingContent;

  /// 批次49：流式阶段标签（诊断/评估等场景 ThinkingIndicator 与流式气泡
  /// 显示阶段化文案；null = 默认「正在思考…」）
  final String? streamStageLabel;
  final Set<String> failedMessageIds;
  final void Function(String messageId)? onRetry;
  final void Function(String messageId)? onDelete;

  /// T3 训练系统：当前练习任务（非空时在列表底部渲染练习卡）
  final PracticeTask? activePracticeTask;

  /// T3 训练系统：最近一次训练结果（非空时渲染结果指示器）
  final TrainingResult? trainingResult;

  /// T3 训练系统：练习提交中状态
  final bool isPracticeSubmitting;

  /// T3 训练系统：提交作答回调
  final void Function(String content)? onSubmitPractice;

  /// T3 训练系统：跳过练习回调
  final VoidCallback? onSkipPractice;

  /// T3 训练系统：关闭结果回调
  final VoidCallback? onDismissResult;

  /// T3 训练系统：再试一次（未达标时重新打开练习）
  final VoidCallback? onRetryPractice;

  /// 批次61：Teacher 建议卡「教我原理」回调（参数 = 症候名）
  final ValueChanged<String>? onTeachPrinciple;

  /// 批次81 H1：PhaseSummaryCard「继续训练」回调（重开练习任务）
  final VoidCallback? onContinueTraining;

  /// 批次81 H1：PhaseSummaryCard「查看学员画像」回调（跳能力画像页）
  final VoidCallback? onViewProfile;

  /// 批次81 H1/H2：PhaseSummaryCard「返回对话」/ DiagnosisFailedCard
  /// 「继续对话」「补充内容」回调（聚焦输入框继续对话）
  final VoidCallback? onBackToChat;
  final VoidCallback? onAddContent;
  final VoidCallback? onContinueChat;

  /// 批次81 H3：PartialAgreementCard「提交反馈/快速选项」回调
  final void Function(String feedback, String? quickOption)?
  onPartialAgreementSubmit;

  /// 批次81 H3：PartialAgreementCard「跳过此症候」回调
  final VoidCallback? onPartialAgreementSkip;

  /// T4 评估报告：messageId → EvaluationData（非空时渲染评估报告面板）
  final Map<String, EvaluationData> evaluationReports;

  /// T4 评估报告：关闭指定消息的报告
  final void Function(String messageId)? onDismissEvaluationReport;

  /// 空态自定义组件（缺口清单第 5 项：ChatPage 传 ChatWelcome 欢迎态；
  /// 未传时保留默认「有问题尽管问教练」引导）
  final Widget? emptyWidget;

  /// 「保存到文件」：透传给 MessageBubble 操作区（批次 14）
  final void Function(Message message)? onSaveToFile;

  const MessageList({
    super.key,
    required this.messages,
    required this.isStreaming,
    required this.streamingContent,
    this.streamStageLabel,
    this.failedMessageIds = const {},
    this.onRetry,
    this.onDelete,
    this.activePracticeTask,
    this.trainingResult,
    this.isPracticeSubmitting = false,
    this.onSubmitPractice,
    this.onSkipPractice,
    this.onDismissResult,
    this.onRetryPractice,
    this.onTeachPrinciple,
    this.onContinueTraining,
    this.onViewProfile,
    this.onBackToChat,
    this.onAddContent,
    this.onContinueChat,
    this.onPartialAgreementSubmit,
    this.onPartialAgreementSkip,
    this.evaluationReports = const {},
    this.onDismissEvaluationReport,
    this.emptyWidget,
    this.onSaveToFile,
  });

  @override
  ConsumerState<MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<MessageList> {
  final ScrollController _scrollController = ScrollController();

  /// 批次72：点击引用徽章前反查真实性（防改名/删除后跳转落空）
  ///  - chapter：getChapter 存在 → 跳 /writing/:chapterId（改名后按 refId 仍有效）；
  ///    章节已删（getChapter 返回 null）→ SnackBar 提示不跳转
  ///  - manuscript / file：作品存在且非 archived → 跳 /manuscript-detail；
  ///    已删除/已归档 → SnackBar 提示不跳转
  Future<void> _handleMentionTap(
    String refType,
    String refId,
    String? manuscriptId,
  ) async {
    final db = ref.read(appDatabaseProvider);
    if (refType == 'chapter') {
      final chapter = await ChapterRepository(db).getChapter(refId);
      if (!mounted) return;
      if (chapter == null) {
        _showMentionGone('该章节已不存在，无法打开');
        return;
      }
      context.push(
        '/writing/$refId',
        extra: <String, dynamic>{
          'manuscriptId': chapter.manuscriptId,
          'chapterTitle': chapter.title,
        },
      );
      return;
    }
    // manuscript / file：跳所属作品详情（无 manuscriptId 时回退到 refId）
    final msId = manuscriptId ?? refId;
    final ms = await ManuscriptRepository(db).getManuscript(msId);
    if (!mounted) return;
    if (ms == null || ms.status == 'archived') {
      _showMentionGone('该作品已不存在，无法打开');
      return;
    }
    context.push(
      AppRoutes.manuscriptDetail,
      extra: <String, dynamic>{'manuscriptId': ms.id, 'title': ms.title},
    );
  }

  /// 引用对象已失效时的轻提示（不改跳转逻辑，仅拦截落空路径）
  void _showMentionGone(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// 长按消息 → 弹出删除确认对话框（E4：统一为标准 showDialog，
  /// 与书架/作品详情的弹窗实现一致，替代自定义覆盖层）
  Future<void> _showDeleteConfirm(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.overlay,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            '确认删除',
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
              style: AppButtonStyles.secondary,
              child: const Text(
                '取消',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                padding: const EdgeInsets.symmetric(
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
      },
    );
    if (confirmed == true && widget.onDelete != null) {
      widget.onDelete!(message.id);
    }
  }

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 消息数变化或流式内容变化时，仅当用户本就停在底部才自动滚动到底部
    // （B18：防止每收到一个 token 就无条件劫持滚动，用户上滑看历史时被拉回）
    if ((oldWidget.messages.length != widget.messages.length ||
            oldWidget.streamingContent != widget.streamingContent) &&
        _isAtBottom()) {
      _scrollToBottom();
    }
  }

  /// 用户是否停在列表底部（80px 容差）。无 clients 时视为在底部。
  bool _isAtBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.pixels >= pos.maxScrollExtent - 80;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          // 批次6（6.1）：prefers-reduced-motion 时归零动画时长
          // 批次69：动效节奏统一——时长/曲线收敛到 AppMotion 令牌
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.durationStandard,
          curve: AppMotion.curveFade,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 构造渲染列表：真实消息 + 可选的流式虚拟消息
    final renderItems = <Map<String, dynamic>>[];

    for (final msg in widget.messages) {
      renderItems.add({'type': 'message', 'data': msg});
    }

    // 批次51：诊断阶段（阶段标签以「正在诊断」开头）流式中隐藏前导文本——
    // 诊断最终交付物是 DiagnosisCard，流式期间的说明文本（含协议块拦截后的
    // 冻结态）不直接展示，统一走 ThinkingIndicator（spinner + 阶段文案），
    // 避免「先长文本后变卡片」跳变；评估/快速观察等阶段保留流式文本。
    final isDiagnosisStage =
        widget.streamStageLabel?.startsWith('正在诊断') ?? false;

    // 流式中：streamingContent 非空 → 追加虚拟消息（role=assistant, isStreaming=true 渲染半透明）
    if (widget.isStreaming &&
        widget.streamingContent.isNotEmpty &&
        !isDiagnosisStage) {
      renderItems.add({
        'type': 'streaming',
        'data': Message(
          id: '__streaming__',
          sessionId: '',
          role: 'assistant',
          content: widget.streamingContent,
          timestamp: 0,
          messageType: 'chat',
        ),
      });
    }

    // 末尾 ThinkingIndicator 的额外 item（streaming 但内容为空，或诊断阶段收拢文本）
    final hasThinkingIndicator =
        widget.isStreaming &&
        (widget.streamingContent.isEmpty || isDiagnosisStage);

    // P2-2 修复：消息列表为空且不在流式中时，显示引导文案
    final isEmpty = widget.messages.isEmpty && !widget.isStreaming;

    // T3 训练系统：练习任务卡 + 结果指示器（渲染在列表底部，对齐 WritingCoachPanel）
    final practiceWidgets = <Widget>[];
    if (widget.activePracticeTask != null) {
      practiceWidgets.add(
        PracticeTaskCard(
          task: widget.activePracticeTask!,
          submitting: widget.isPracticeSubmitting,
          onSubmit: widget.onSubmitPractice ?? (_) {},
          onSkip: widget.onSkipPractice ?? () {},
        ),
      );
    }
    if (widget.trainingResult != null) {
      practiceWidgets.add(
        PracticeResultIndicator(
          result: widget.trainingResult!,
          onDismiss: widget.onDismissResult,
          onRetry: widget.onRetryPractice,
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              if (isEmpty)
                widget.emptyWidget ??
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 40,
                              color: AppColors.textTertiary,
                            ),
                            SizedBox(height: 12),
                            Text(
                              '有问题尽管问教练',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '写作遇到卡壳、不知道怎么改，直接问就行',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textTertiary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
              else
                ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  itemCount:
                      renderItems.length +
                      (hasThinkingIndicator ? 1 : 0) +
                      practiceWidgets.length,
                  itemBuilder: (context, index) {
                    // 流式中 + streamingContent 空 → 末尾显示 ThinkingIndicator
                    if (hasThinkingIndicator && index == renderItems.length) {
                      return RepaintBoundary(
                        key: const ValueKey('msg-item-thinking'),
                        child: ThinkingIndicator(
                          label: widget.streamStageLabel,
                        ),
                      );
                    }

                    // 练习任务卡 / 结果指示器：列表底部渲染（对齐 RN 训练卡片在列表内）
                    final practiceIndex =
                        index -
                        renderItems.length -
                        (hasThinkingIndicator ? 1 : 0);
                    if (practiceIndex >= 0) {
                      return RepaintBoundary(
                        key: ValueKey('msg-item-practice-$practiceIndex'),
                        child: practiceWidgets[practiceIndex],
                      );
                    }

                    final item = renderItems[index];
                    final msg = item['data'] as Message;
                    final isStreamingBubble = item['type'] == 'streaming';
                    final isFailed = widget.failedMessageIds.contains(msg.id);

                    // 批次5（5.1）：卡片分派统一走 MessageCardDispatcher
                    //（diagnosis_result/teacher_suggestion/outline_confirmation/
                    //  reference_change/phase_upgrade/partial_agreement/phase_summary/
                    //  diagnosis_failed/评估报告 均由其处理；不命中回退 MessageBubble）
                    final card = dispatchMessageCard(
                      msg: msg,
                      isStreamingBubble: isStreamingBubble,
                      evaluationReport: widget.evaluationReports[msg.id],
                      onTeachPrinciple: widget.onTeachPrinciple,
                      onDismissEvaluationReport:
                          widget.onDismissEvaluationReport != null
                          ? () => widget.onDismissEvaluationReport!(msg.id)
                          : null,
                      // 批次81：三卡回调透传（H1-H3）
                      onContinueTraining: widget.onContinueTraining,
                      onViewProfile: widget.onViewProfile,
                      onBackToChat: widget.onBackToChat,
                      onAddContent: widget.onAddContent,
                      onContinueChat: widget.onContinueChat,
                      onPartialAgreementSubmit: widget.onPartialAgreementSubmit,
                      onPartialAgreementSkip: widget.onPartialAgreementSkip,
                    );
                    if (card != null) {
                      // 批次53：RepaintBoundary 隔离——流式期间全列表 rebuild 时
                      // 每消息绘制/动画独立，不扩散到兄弟 item，降低每 token 重绘开销
                      return RepaintBoundary(
                        key: ValueKey('msg-item-${msg.id}'),
                        // 批次74：卡片消息同样支持长按删除（对齐普通气泡心智）
                        child: GestureDetector(
                          onLongPress: widget.onDelete != null
                              ? () => _showDeleteConfirm(msg)
                              : null,
                          child: card,
                        ),
                      );
                    }

                    final streamBubble = MessageBubble(
                      message: msg,
                      isStreaming: isStreamingBubble,
                      isFailed: isFailed,
                      onRetry: isFailed ? widget.onRetry : null,
                      onLongPress: widget.onDelete != null
                          ? _showDeleteConfirm
                          : null,
                      onSaveToFile: widget.onSaveToFile,
                      // 批次71：引用徽章点击跳转
                      onMentionTap: _handleMentionTap,
                    );
                    // 批次49：流式气泡顶部加阶段角标（诊断/评估等，让等待可感知）
                    if (isStreamingBubble && widget.streamStageLabel != null) {
                      return RepaintBoundary(
                        key: ValueKey('msg-item-${msg.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                left: AppSpacing.md,
                                bottom: AppSpacing.xxs,
                              ),
                              child: Text(
                                widget.streamStageLabel!,
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
                      key: ValueKey('msg-item-${msg.id}'),
                      child: streamBubble,
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 思考指示器（流式启动但尚未收到 token 时显示）
///
/// 显示旋转 loading + 阶段化文案（批次49：诊断/评估场景传入 [label]，
/// null = 默认「正在思考…」），位置左对齐，灰调配色。
class ThinkingIndicator extends StatelessWidget {
  final String? label;

  const ThinkingIndicator({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label ?? '正在思考…',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
