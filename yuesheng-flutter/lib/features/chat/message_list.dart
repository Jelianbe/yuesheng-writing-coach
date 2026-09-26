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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_motion.dart';
import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/manuscript_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/fact_batch_providers.dart';
import '../../providers/practice_providers.dart';
import '../../router/app_routes.dart';
import '../../types/display_types.dart';
import '../../types/teaching_types.dart';
import '../../widgets/fact_batch_card.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/message_card_dispatcher.dart';
import '../../widgets/practice_result_indicator.dart';
import '../../widgets/practice_task_card.dart';
import '../../theme/app_typography.dart';

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
  final void Function(String content, TrainingSelfAssessment? assessment)?
  onSubmitPractice;

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

  /// C78 批次3（FR-10）：messageId → 批次沉淀记录（非空时消息尾部渲染提示卡）。
  /// 由 ChatPage watch factBatchProvider 传入——MessageList 保持 build 期
  /// 无 ref 依赖（对齐 evaluationReports 的参数注入模式，流式测试可裸 pump）。
  final Map<String, FactBatchRecord> factBatches;

  /// T4 评估报告：关闭指定消息的报告
  final void Function(String messageId)? onDismissEvaluationReport;

  /// E1-b②：评估报告「查看成长记录」回调（跳成长详情页；null 时不渲染入口）
  final VoidCallback? onOpenGrowth;

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
    this.factBatches = const {},
    this.onDismissEvaluationReport,
    this.onOpenGrowth,
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
      unawaited(
        context.push(
          '/writing/$refId',
          extra: <String, dynamic>{
            'manuscriptId': chapter.manuscriptId,
            'chapterTitle': chapter.title,
          },
        ),
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
    unawaited(
      context.push(
        AppRoutes.manuscriptDetail,
        extra: <String, dynamic>{'manuscriptId': ms.id, 'title': ms.title},
      ),
    );
  }

  /// 引用对象已失效时的轻提示（不改跳转逻辑，仅拦截落空路径）
  void _showMentionGone(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// C78 批次3（FR-10）：assistant 消息有批次沉淀记录 → 尾部追加系统提示卡
  /// （数据来自 [MessageList.factBatches]；流式虚拟消息 id 不会命中）。
  Widget _withFactBatchCard(Widget child, Message msg) {
    final record = widget.factBatches[msg.id];
    if (record == null || msg.role != 'assistant') return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        child,
        FactBatchCard(record: record),
      ],
    );
  }

  /// 长按消息 → 操作菜单（复制内容 / 删除）。
  /// 复制不依赖 onDelete（任何消息都可用）；删除沿用确认弹窗流程。
  Future<void> _showMessageActions(Message message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.copy_rounded,
                color: context.palette.textPrimary,
              ),
              title: Text('复制内容', style: context.text.body),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            if (widget.onDelete != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: context.palette.danger,
                ),
                title: Text('删除', style: context.text.body),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.content));
      // 此处 context 是 State.context ⇒ 守卫须用 State 的 mounted（同文件 164/183 行同例）。
      // 写成 context.mounted 会被判为「unrelated mounted check」（lint 只看守卫形式，
      // 而 State.context 与 BuildContext.mounted 的配对不是它认可的形式）。
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('内容已复制')));
      }
    } else if (action == 'delete') {
      await _showDeleteConfirm(message);
    }
  }

  /// 长按消息 → 弹出删除确认对话框（E4：统一为标准 showDialog，
  /// 与书架/作品详情的弹窗实现一致，替代自定义覆盖层）
  Future<void> _showDeleteConfirm(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: context.palette.overlay,
      builder: (ctx) => _buildDeleteDialog(ctx),
    );
    if (confirmed == true && widget.onDelete != null) {
      widget.onDelete!(message.id);
    }
  }

  Widget _buildDeleteDialog(BuildContext ctx) {
    return AlertDialog(
      title: Text('确认删除', style: context.text.titleLg),
      content: Text(
        '确定要删除这条消息吗？此操作不可撤销。',
        textAlign: TextAlign.center,
        style: context.text.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: AppButtonStyles.secondary,
          child: Text(
            '取消',
            style: TextStyle(
              color: context.palette.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.danger,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
          ),
          child: Text(
            '删除',
            style: TextStyle(
              color: context.palette.onPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ADR-C84 后续：用户主动发送（新 user 消息上屏）→ 无条件滚到底。
    // 发送是强意图（键盘弹起时 _isAtBottom 会因视口压缩误判，导致
    // 键盘收起后列表停在旧位置、新消息不可见）；B18 的「不劫持」仅
    // 适用于流式 token 追加（用户看历史时不被拉回）。
    final hasNewUserMessage =
        widget.messages.length > oldWidget.messages.length &&
        widget.messages.any(
          (m) =>
              m.role == 'user' &&
              !oldWidget.messages.any((om) => om.id == m.id),
        );
    if (hasNewUserMessage) {
      _scrollToBottom();
    } else if ((oldWidget.messages.length != widget.messages.length ||
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
    final renderItems = _buildRenderItems();
    final hasThinkingIndicator =
        widget.isStreaming &&
        (widget.streamingContent.isEmpty || _isDiagnosisStage());
    final isEmpty = widget.messages.isEmpty && !widget.isStreaming;
    final practiceWidgets = _buildPracticeWidgets();

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              if (isEmpty)
                _buildEmptyState()
              else
                _buildMessageListView(
                  renderItems,
                  hasThinkingIndicator,
                  practiceWidgets,
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isDiagnosisStage() =>
      widget.streamStageLabel?.startsWith('正在诊断') ?? false;

  List<Map<String, dynamic>> _buildRenderItems() {
    final renderItems = <Map<String, dynamic>>[];
    for (final msg in widget.messages) {
      renderItems.add({'type': 'message', 'data': msg});
    }
    final isDiagnosisStage = _isDiagnosisStage();
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
    return renderItems;
  }

  List<Widget> _buildPracticeWidgets() {
    final practiceWidgets = <Widget>[];
    if (widget.activePracticeTask != null) {
      practiceWidgets.add(
        PracticeTaskCard(
          task: widget.activePracticeTask!,
          submitting: widget.isPracticeSubmitting,
          onSubmit: widget.onSubmitPractice ?? (_, _) {},
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
    return practiceWidgets;
  }

  Widget _buildEmptyState() {
    return widget.emptyWidget ??
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 40,
                  color: context.palette.textTertiary,
                ),
                SizedBox(height: 12),
                Text(
                  '有问题尽管问教练',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: context.palette.textSecondary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '写作遇到卡壳、不知道怎么改，直接问就行',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.palette.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
  }

  Widget _buildMessageListView(
    List<Map<String, dynamic>> renderItems,
    bool hasThinkingIndicator,
    List<Widget> practiceWidgets,
  ) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      itemCount:
          renderItems.length +
          (hasThinkingIndicator ? 1 : 0) +
          practiceWidgets.length,
      itemBuilder: (context, index) => _buildMessageItem(
        index,
        renderItems,
        hasThinkingIndicator,
        practiceWidgets,
      ),
    );
  }

  Widget _buildMessageItem(
    int index,
    List<Map<String, dynamic>> renderItems,
    bool hasThinkingIndicator,
    List<Widget> practiceWidgets,
  ) {
    if (hasThinkingIndicator && index == renderItems.length) {
      return _buildThinkingIndicatorItem();
    }
    final practiceIndex =
        index - renderItems.length - (hasThinkingIndicator ? 1 : 0);
    if (practiceIndex >= 0) {
      return _buildPracticeItem(practiceIndex, practiceWidgets);
    }
    final item = renderItems[index];
    final msg = item['data'] as Message;
    final isStreamingBubble = item['type'] == 'streaming';
    final isFailed = widget.failedMessageIds.contains(msg.id);
    final cardItem = _buildCardItem(msg, isStreamingBubble, isFailed);
    if (cardItem != null) return cardItem;
    return _buildBubbleItem(msg, isStreamingBubble, isFailed);
  }

  Widget _buildThinkingIndicatorItem() {
    return RepaintBoundary(
      key: const ValueKey('msg-item-thinking'),
      child: ThinkingIndicator(label: widget.streamStageLabel),
    );
  }

  Widget _buildPracticeItem(int practiceIndex, List<Widget> practiceWidgets) {
    return RepaintBoundary(
      key: ValueKey('msg-item-practice-$practiceIndex'),
      child: practiceWidgets[practiceIndex],
    );
  }

  Widget? _buildCardItem(Message msg, bool isStreamingBubble, bool isFailed) {
    final card = dispatchMessageCard(
      context: context,
      msg: msg,
      isStreamingBubble: isStreamingBubble,
      evaluationReport: widget.evaluationReports[msg.id],
      onTeachPrinciple: widget.onTeachPrinciple,
      onDismissEvaluationReport: widget.onDismissEvaluationReport != null
          ? () => widget.onDismissEvaluationReport!(msg.id)
          : null,
      onOpenGrowth: widget.onOpenGrowth,
      onContinueTraining: widget.onContinueTraining,
      onViewProfile: widget.onViewProfile,
      onBackToChat: widget.onBackToChat,
      onAddContent: widget.onAddContent,
      onContinueChat: widget.onContinueChat,
      onPartialAgreementSubmit: widget.onPartialAgreementSubmit,
      onPartialAgreementSkip: widget.onPartialAgreementSkip,
    );
    if (card == null) return null;
    return RepaintBoundary(
      key: ValueKey('msg-item-${msg.id}'),
      child: _withFactBatchCard(
        GestureDetector(
          onLongPress: () => _showMessageActions(msg),
          child: card,
        ),
        msg,
      ),
    );
  }

  Widget _buildBubbleItem(Message msg, bool isStreamingBubble, bool isFailed) {
    final streamBubble = MessageBubble(
      message: msg,
      isStreaming: isStreamingBubble,
      isFailed: isFailed,
      onRetry: isFailed ? widget.onRetry : null,
      onLongPress: _showMessageActions,
      onSaveToFile: widget.onSaveToFile,
      onMentionTap: _handleMentionTap,
    );
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
                style: context.text.microCaption,
              ),
            ),
            streamBubble,
          ],
        ),
      );
    }
    return RepaintBoundary(
      key: ValueKey('msg-item-${msg.id}'),
      child: _withFactBatchCard(streamBubble, msg),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(label ?? '正在思考…', style: context.text.subBody),
        ],
      ),
    );
  }
}
