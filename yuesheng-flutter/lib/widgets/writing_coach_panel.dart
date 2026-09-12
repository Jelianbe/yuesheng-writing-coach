// ─────────────────────────────────────────────────────────────
// WritingCoachPanel — 写作页半屏 AI 教练面板
//
// 替换 WritingPage 中的 bottomSheet 占位。每个章节拥有独立会话
// （通过 getOrCreateSessionForChapter 隔离），与 Tab2 聊天互不污染。
//
// 结构（自上而下）：
//   1. 按钮行（快速观察 | 诊断本章 | ✕ 关闭）
//   2. Divider
//   3. 错误横幅（chatState.error != null 时显示）
//   4. 消息列表（Expanded，复用 MessageBubble）
//   5. 输入栏（TextField + 发送按钮）
//
// R-019 真分解（批次 X-025-ARCH 清偿）：
//   本文件曾是「宿主 + 2 个 part/extension」的伪拆分形态。现已拆为多个
//   **独立类**（正常 import，无 part）：WritingCoachMessageList /
//   WritingCoachButtonRow·ErrorBanner·InputBar / WritingCoachTeachingController /
//   WritingCoachSessionController / WritingCoachDeleteDialog 等。
//   State 只保留生命周期 + 会话装配，能力经 WritingCoachPanelHost 显式暴露。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../providers/chat_store.dart';
import '../types/teaching_types.dart';
import 'writing_coach_panel_bootstrapper.dart';
import 'writing_coach_panel_host.dart';
import 'writing_coach_panel_message_list.dart';
import 'writing_coach_panel_session_controller.dart';
import 'writing_coach_panel_store.dart';
import 'writing_coach_panel_teaching.dart';
import 'writing_coach_panel_view.dart';

/// 对外保持旧路径可用：writingCoachStoreProvider 定义在
/// writing_coach_panel_store.dart，此处 re-export（既有 importer 无需改动）。
export 'writing_coach_panel_store.dart' show writingCoachStoreProvider;

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

class _WritingCoachPanelState extends ConsumerState<WritingCoachPanel>
    implements WritingCoachPanelHost {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();

  /// 会话 id（由教学控制器经 Host 接口读写）
  String? _sessionId;

  /// _initSession 的 Future，供删除消息等待会话初始化完成
  late Future<void> _initFuture;

  /// P2-3：会话初始化是否完成（避免先显示空状态再突然出现消息）
  bool _isInitLoading = true;

  /// D5-A：是否正在诊断中（驱动「诊断中…」占位 + 按钮禁用态）
  bool _isDiagnosing = false;

  /// 批次49：流式阶段标签（诊断/评估等场景显示阶段化「思考中」文案）
  String? _streamStageLabel;

  /// B3 划词诊断：已处理的选中文本（防重复触发）
  String? _handledDiagnoseText;

  /// P1（2026-09-11）：本面板态度档位。默认 doubao；会话存在时从
  /// teaching_state 恢复（与对话页切换保持同步，不再硬编码 doubao）。
  AttitudeLevel _attitude = AttitudeLevel.doubao;

  /// ADR-C87：当前流式的取消令牌（发送/快速观察/诊断共用）。
  /// 供「停止生成」按钮在流式中段中止（避免卡死时无出口）；
  /// 面板关闭（dispose）时也取消，防止流式在面板销毁后继续跑。
  CancelToken? _cancelToken;

  /// 诊断 / 教学流程控制器（独立类，经 Host 接口注入能力）。
  late final WritingCoachTeachingController _teacher =
      WritingCoachTeachingController(this);

  /// 发送 / 快速观察 / 练习 / 删除 会话动作控制器（独立类）。
  late final WritingCoachSessionController _session =
      WritingCoachSessionController(this, _teacher.observeGate);

  /// 会话引导器（初始化已有会话 + 恢复评估报告 + 恢复态度档）。
  late final WritingCoachSessionBootstrapper _bootstrap =
      WritingCoachSessionBootstrapper(
        ref: ref,
        chapterId: () => widget.chapterId,
        onSessionBound: (id) => _sessionId = id,
        onAttitudeLoaded: (attitude) {
          if (mounted) setState(() => _attitude = attitude);
        },
        isMounted: () => mounted,
      );

  // ── WritingCoachPanelHost 实现 ──
  // 注：ref / context 由 ConsumerState 直接提供（WidgetRef / BuildContext），
  // 天然满足 Host 接口，无需显式 override。

  @override
  String get chapterId => widget.chapterId;

  @override
  String get manuscriptId => widget.manuscriptId;

  @override
  String get chapterTitle => widget.chapterTitle;

  @override
  TextEditingController get inputController => _inputController;

  @override
  String? get sessionId => _sessionId;

  @override
  set sessionId(String? value) => _sessionId = value;

  @override
  bool get isMounted => mounted;

  @override
  AttitudeLevel get attitude => _attitude;

  @override
  set streamStageLabel(String? value) =>
      setState(() => _streamStageLabel = value);

  @override
  set isDiagnosing(bool value) => setState(() => _isDiagnosing = value);

  @override
  set cancelToken(CancelToken? value) => _cancelToken = value;

  @override
  CancelToken? get cancelToken => _cancelToken;

  @override
  Future<void> loadAttitude(String sessionId) =>
      _bootstrap.loadAttitude(sessionId);

  @override
  Future<void> awaitInit() => _initFuture;

  @override
  void focusInput() => _inputFocusNode.requestFocus();

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
    _teacher.diagnoseWithText(text);
  }

  /// 加载章节已有会话（ADR-C81 懒创建：只查不建）后复位 loading。
  ///
  /// 具体引导逻辑委托给 [WritingCoachSessionBootstrapper]；
  /// 查不到会话 → 不落库任何会话，UI 落空态。
  Future<void> _initSession() async {
    await _bootstrap.initSession();
    if (mounted) setState(() => _isInitLoading = false);
  }

  @override
  void dispose() {
    // ADR-C87：关闭面板时取消进行中的流式（防止流式继续跑浪费额度）
    _cancelToken?.cancel('panel closed');
    _cancelToken = null;
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(writingCoachStoreProvider(widget.chapterId));
    _listenAutoScroll();

    // 批次82 P0-④：教练面板改为右侧可收起侧栏（正文不被覆盖）。
    // 面板填满父容器高度，不再有半屏高度比 + 拖拽手柄（收起交给页面侧开关）。
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        border: Border(left: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Column(
        children: [
          WritingCoachButtonRow(
            isStreaming: chatState.isStreaming,
            onObserve: _session.handleRealtimeObserve,
            onDiagnose: _teacher.diagnoseChapter,
            onClose: widget.onClose,
          ),
          const Divider(height: 1),
          if (chatState.error != null)
            WritingCoachErrorBanner(
              error: chatState.error!,
              onDismiss: () => ref
                  .read(writingCoachStoreProvider(widget.chapterId).notifier)
                  .clearError(),
            ),
          Expanded(child: _buildMessageList(chatState)),
          WritingCoachInputBar(
            chatState: chatState,
            controller: _inputController,
            focusNode: _inputFocusNode,
            onSend: _session.handleSend,
            onStop: _session.cancelGeneration,
          ),
        ],
      ),
    );
  }

  /// 消息列表变化时自动滚动到底部。
  void _listenAutoScroll() {
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
  }

  /// 消息列表：独立 Widget 承载（状态 + 回调显式传入）。
  Widget _buildMessageList(ChatState chatState) {
    return WritingCoachMessageList(
      chatState: chatState,
      isInitLoading: _isInitLoading,
      sessionId: _sessionId,
      streamStageLabel: _streamStageLabel,
      isDiagnosing: _isDiagnosing,
      scrollController: _scrollController,
      onAdopt: widget.onAdopt,
      onTeachPrinciple: _session.handleTeachPrinciple,
      onPartialAgreementSubmit: _session.handlePartialAgreementSubmit,
      onPartialAgreementSkip: _session.handlePartialAgreementSkip,
      onFocusInput: _session.focusInput,
      onDeleteMessage: _session.confirmDeleteMessage,
      onPracticeSubmit: _session.submitPractice,
    );
  }
}
