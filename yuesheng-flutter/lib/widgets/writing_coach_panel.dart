// ─────────────────────────────────────────────────────────────
// WritingCoachPanel — 写作页半屏 AI 教练面板
//
// 替换 WritingPage 中的 bottomSheet 占位。每个章节拥有独立会话
// （通过 getOrCreateSessionForChapter 隔离），与 Tab2 聊天互不污染。
//
// 结构（自上而下）：
//   1. 拖拽手柄（全宽独立行，36x4 圆角灰条）
//   2. 按钮行（诊断本章 | ✕ 关闭）
//   3. Divider
//   4. 错误横幅（chatState.error != null 时显示）
//   5. 消息列表（Expanded，复用 MessageBubble）
//   6. 输入栏（TextField + 发送按钮）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../config/shared_constants.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/teaching_state_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/evaluation_providers.dart';
import '../providers/practice_providers.dart';
import '../providers/session_providers.dart';
import '../providers/writing_providers.dart';
import '../router/app_routes.dart';
import '../services/chat_message_types.dart' show SendMessageCallbacks, SendMessageOptions;
import '../services/progressive_diagnosis.dart';
import '../services/phase_transition.dart';
import '../types/teaching_types.dart';
import 'message_bubble.dart';
import 'message_card_dispatcher.dart';
import 'partial_agreement_card.dart';
import 'practice_result_indicator.dart';
import 'practice_task_card.dart';
import 'writing/thinking_placeholder.dart';

part 'writing_coach_panel_teaching.dart';
part 'writing_coach_panel_builders.dart';

/// WritingCoachPanel 专用 ChatStore（与 Tab2 chatStoreProvider 隔离）
///
/// 按 chapterId 隔离：每个章节拥有独立的 ChatStore 实例，
/// 避免多个 WritingCoachPanel 实例共享同一个 store 导致会话污染。
final writingCoachStoreProvider =
    StateNotifierProvider.family<ChatStore, ChatState, String>((
      ref,
      chapterId,
    ) {
      return ChatStore();
    });

class WritingCoachPanel extends ConsumerStatefulWidget {
  final String chapterId;
  final String manuscriptId;
  final String chapterTitle;
  final VoidCallback onClose;
  final void Function(String suggestion)? onAdopt;

  /// B3 划词诊断：写作页选中文本注入（非空时打开面板即自动对该选段诊断）
  final String? pendingDiagnoseText;

  const WritingCoachPanel({
    super.key,
    required this.chapterId,
    required this.manuscriptId,
    required this.chapterTitle,
    required this.onClose,
    this.onAdopt,
    this.pendingDiagnoseText,
  });

  @override
  ConsumerState<WritingCoachPanel> createState() => _WritingCoachPanelState();
}

class _WritingCoachPanelState extends ConsumerState<WritingCoachPanel> {
  String? _sessionId;
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();

  /// _initSession 的 Future，供 _handleDiagnose 等待会话初始化完成
  late Future<void> _initFuture;

  /// P2-3：会话初始化是否完成（避免先显示空状态再突然出现消息）
  bool _isInitLoading = true;

  /// D5-A：是否正在诊断中（驱动「诊断中…」占位 + 按钮禁用态）
  bool _isDiagnosing = false;

  /// 批次49：流式阶段标签（诊断/评估等场景显示阶段化「思考中」文案）
  String? _streamStageLabel;

  /// B3 划词诊断：已处理的选中文本（防重复触发）
  String? _handledDiagnoseText;

  @override
  void initState() {
    super.initState();
    _initFuture = _initSession();
    // B3：打开面板时若已注入选中文本 → 自动触发选段诊断
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeTriggerSelectionDiagnose();
    });
  }

  @override
  void didUpdateWidget(covariant WritingCoachPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // chapterId 变化时（widget 复用场景），重新初始化会话
    if (oldWidget.chapterId != widget.chapterId) {
      _sessionId = null;
      _initFuture = _initSession();
    }
    // B3：选中文本变化 → 触发选段诊断
    _maybeTriggerSelectionDiagnose();
  }

  /// B3 划词诊断触发检查：pendingDiagnoseText 非空且未处理过 → 对该选段诊断
  void _maybeTriggerSelectionDiagnose() {
    final text = widget.pendingDiagnoseText;
    if (text == null || text.trim().isEmpty) return;
    if (_handledDiagnoseText == text) return;
    _handledDiagnoseText = text;
    _handleDiagnoseWithText(text);
  }

  /// 初始化章节级隔离会话 + 加载已有消息
  Future<void> _initSession() async {
    final db = ref.read(appDatabaseProvider);
    final sessionId = await SessionRepository(
      db,
    ).getOrCreateSessionForChapter(widget.manuscriptId, widget.chapterId);
    _sessionId = sessionId;
    ref
        .read(writingCoachStoreProvider(widget.chapterId).notifier)
        .setSessionId(sessionId);
    final messages = await SessionRepository(db).listMessages(sessionId);
    ref
        .read(writingCoachStoreProvider(widget.chapterId).notifier)
        .setMessages(messages);
    // 批次6 E1：恢复该章节会话的评估报告 + 当前轮次（对齐 chat_page bootstrap）。
    // 注意：不用 resetReports——它会清空 DB 中当前会话报告导致刚训练的数据丢失；
    // restoreForSession 内部会覆盖内存状态并重置 _currentSessionId（防跨会话串写）。
    await ref
        .read(evaluationReportsProvider.notifier)
        .restoreForSession(sessionId);
    if (mounted) setState(() => _isInitLoading = false);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(writingCoachStoreProvider(widget.chapterId));

    // 消息列表变化时自动滚动到底部
    ref.listen<ChatState>(writingCoachStoreProvider(widget.chapterId), (
      previous,
      next,
    ) {
      if (previous?.messages.length != next.messages.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    });

    // 批次82 P0-④：教练面板改为右侧可收起侧栏（正文不被覆盖）。
    // 面板填满父容器高度，不再有半屏高度比 + 拖拽手柄（收起交给页面侧开关）。
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        border: Border(left: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Column(
        children: [
          _buildButtonRow(chatState.isStreaming),
          const Divider(height: 1),
          if (chatState.error != null) _buildErrorBanner(chatState),
          Expanded(child: _buildMessageList(chatState)),
          _buildInputBar(chatState),
        ],
      ),
    );
  }
}

/// D5-A：思考/诊断中占位 — 竹青头像 + 转圈 + 文案
///
/// 流式开始但尚无内容时显示，替代空白空气泡：
///   - 诊断中 → 「诊断中…」
///   - 普通聊天 → 「思考中…」
