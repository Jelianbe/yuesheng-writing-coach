// ─────────────────────────────────────────────────────────────
// writing_coach_panel 的诊断 / 教学流程控制器（独立类，依赖注入，无 part）
//
// R-019 真分解（批次 X-025-ARCH 清偿）：本文件曾以
//   `extension _WritingCoachPanelTeaching on _WritingCoachPanelState`
// 的形式机械拆分（伪拆分）。现改为**独立类**：
//   - WritingCoachPanelHost          宿主能力注入接口
//   - WritingCoachTeachingController 诊断（整章 + 选段）/ 门槛校验 / 诊断链路
// 发送 / 快速观察 / 练习 / 删除等会话动作归 writing_coach_panel_session_controller.dart。
// 不再使用 part / extension。
//
// ⚠️ 本文件路径被 `test/widgets/diagnosis_word_threshold_test.dart`
//    （ADR-C66 门槛护栏，锚定 4 个文件路径）引用，**文件名必须保持不变**；
//    两档诊断门槛 + 快速观察门槛的常量插值文案均保留于此。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/shared_constants.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/teaching_state_repository.dart';
import '../providers/app_providers.dart';
import '../providers/evaluation_providers.dart';
import '../providers/writing_providers.dart';
import '../services/phase_transition.dart';
import '../types/teaching_types.dart';
import 'writing_coach_panel_store.dart' show writingCoachStoreProvider;
import 'writing_coach_panel_diagnosis_runner.dart';
import 'writing_coach_panel_host.dart';
import 'writing_coach_panel_interactions.dart';

/// 教学控制器访问宿主（State）能力的注入接口。
///
/// 宿主只需实现本接口即可把能力交给控制器，控制器不直接触碰 State 私有成员。
///
/// 注：接口定义已移至 `writing_coach_panel_host.dart`（避免循环依赖）。

/// 诊断流程控制器（独立类，依赖经构造注入）。
class WritingCoachTeachingController {
  final WritingCoachPanelHost _host;

  /// 诊断链路执行器（分块/单次 + 流式 + 取消/错误复位）。
  late final WritingCoachDiagnosisRunner _runner = WritingCoachDiagnosisRunner(
    _host,
  );

  WritingCoachTeachingController(this._host);

  /// 便捷读取宿主 ref
  WidgetRef get _ref => _host.ref;

  /// 便捷读取章节 id
  String get _chapterId => _host.chapterId;

  /// 快速观察前置校验（供 session controller 经回调调用，门槛常量留驻本文件）。
  Future<({String sid, String content})?> observeGate() =>
      _ensureObserveSession();

  // ───────────────────────── 诊断（整章 + 选段）─────────────────────────

  /// 诊断本章（D1：接通 chat_service 真链路，对齐 RN handleConfirmDiagnose）
  Future<void> diagnoseChapter() => diagnoseWithText(null);

  /// 诊断入口：selectedText 非空 → 选段诊断（B3 划词诊断）；否则整章诊断
  ///
  /// 对齐 RN chapter-editor.tsx#L254-L284（整章）与 #L331-L365（选段）：
  ///   1. saveContent：先把编辑器当前内容落库（避免诊断到旧版本，仅整章诊断）
  ///   2. updateChapterDiagnosedAt：写章节最后诊断时间（仅整章诊断）
  ///   3. updatePhase(P1_WORLD)：状态机流转，否则 syndrome-diagnosis-index 不加载
  Future<void> diagnoseWithText(String? selectedText) async {
    // ADR-C81 懒创建：诊断（整章/划词）是「产生内容」入口，此处才真正创建会话
    final sid = await ensureSession();
    if (sid == null) return;

    // D5-A：诊断中置位（驱动「诊断中…」占位 + 按钮禁用态）
    // 批次49：同时设阶段标签（选段/整章区分文案）
    final input = _resolveDiagnosisInput(selectedText);
    if (input == null) return;
    if (_host.isMounted) {
      _host.isDiagnosing = true;
      _host.streamStageLabel = input.isSelection ? '正在诊断选段…' : '正在诊断本章…';
    }

    await _prepareChapterDiagnosis(sid, input.isSelection);

    // D2：长度路由 — 内容 > THRESHOLD(4000) 时分块，否则单次
    final store = _ref.read(writingCoachStoreProvider(_chapterId).notifier);
    store.setStreaming(true);
    // 1. 先把用户消息加到内存 store（即时反馈）
    store.addMessage(_buildDiagnosisUserMessage(sid, input.isSelection));
    // 2. 构造单次诊断 prompt（对齐 RN chat.tsx#L212：显式要求 [YS_DIAGNOSIS] 格式）
    final diagPrompt = buildDiagnosisPrompt(input.title, input.isSelection);

    await _runDiagnosisChain(
      sid: sid,
      content: input.content,
      title: input.title,
      diagPrompt: diagPrompt,
      isSelection: input.isSelection,
    );
  }

  /// 确保章节会话存在（ADR-C81 懒创建的创建点，幂等）。
  Future<String?> ensureSession() async {
    final existing = _host.sessionId;
    if (existing != null) return existing;
    final sessionId = await SessionRepository(
      _ref.read(appDatabaseProvider),
    ).getOrCreateSessionForChapter(_host.manuscriptId, _chapterId);
    _host.sessionId = sessionId;
    await _host.loadAttitude(sessionId);
    _ref
        .read(writingCoachStoreProvider(_chapterId).notifier)
        .setSessionId(sessionId);
    await _ref
        .read(evaluationReportsProvider.notifier)
        .restoreForSession(sessionId);
    return sessionId;
  }

  /// 诊断输入解析：内容来源（选中文本或整章）+ 字数校验（R-019 清偿拆出）。
  ///
  /// 字数不足时弹提示并返回 null（不继续诊断）。
  ({String content, String title, bool isSelection})? _resolveDiagnosisInput(
    String? selectedText,
  ) {
    final isSelection = selectedText != null && selectedText.trim().isNotEmpty;
    final writingState = _ref.read(writingStoreProvider(_chapterId));
    final content = isSelection
        ? selectedText.trim()
        : writingState.localContent;
    final title = writingState.chapter?.title ?? _host.chapterTitle;

    // 前置 2：字数校验（选段 ≥20 字 / 整章 ≥100 字，对齐 RN）
    //
    // ADR-C66：两档阈值统一取自 UILimits，避免此处硬编码与常量各说一套。
    final minLength = isSelection
        ? UILimits.diagnosisSelectionWordThreshold
        : UILimits.diagnosisWordThreshold;
    if (content.trim().length < minLength) {
      if (!_host.isMounted) return null;
      _showSnack(
        isSelection
            ? '请至少选择 ${UILimits.diagnosisSelectionWordThreshold} 字以上的文本进行诊断'
            : '请至少输入 ${UILimits.diagnosisWordThreshold} 字后再提交诊断',
      );
      return null;
    }
    return (content: content, title: title, isSelection: isSelection);
  }

  /// 整章诊断前置：未保存内容落库 + 诊断时间 + P1 阶段迁移（R-019 清偿拆出）。
  Future<void> _prepareChapterDiagnosis(String sid, bool isSelection) async {
    // 前置 3：把未保存内容落库，避免诊断到旧版本（仅整章诊断；选段诊断不落库）
    if (!isSelection) {
      await _ref.read(writingStoreProvider(_chapterId).notifier).saveNow();
    }

    // 前置 4：更新章节最后诊断时间（仅整章诊断）+ 教学阶段 P1_WORLD
    if (isSelection) return;
    final db = _ref.read(appDatabaseProvider);
    await ChapterRepository(db).updateChapterDiagnosedAt(_chapterId);
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
    } catch (_) {
      // 迁移失败不阻断诊断主流程（保守策略，静默）
    }
  }

  /// 诊断用户消息（R-019 清偿拆出）。
  Message _buildDiagnosisUserMessage(String sid, bool isSelection) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Message(
      id: now.toString(),
      sessionId: sid,
      role: 'user',
      content: buildDiagnosisUserMessageContent(isSelection),
      timestamp: now ~/ 1000,
      messageType: 'chat',
    );
  }

  /// 诊断链路编排（委托检测器：分块/单次路由 + 取消/错误复位）。
  Future<void> _runDiagnosisChain({
    required String sid,
    required String content,
    required String title,
    required String diagPrompt,
    required bool isSelection,
  }) async {
    await _runner.runChain(
      sid: sid,
      content: content,
      title: title,
      diagPrompt: diagPrompt,
      isSelection: isSelection,
    );
  }

  // ───────────────────────── 快速观察前置（门槛留驻本文件）─────────────────────────

  /// 快速观察前置：会话懒创建 + 字数校验（R-019 清偿拆出）。
  ///
  /// 字数不足（<50 字）时弹提示并返回 null，不发起观察。
  Future<({String sid, String content})?> _ensureObserveSession() async {
    final sid = await ensureSession();
    if (sid == null) return null;

    // 字数校验：实时观察要求至少 50 字（短文本观察无意义）
    //
    // ADR-C66：门槛取自 UILimits，与诊断门槛同理（避免常量与文案双份维护）。
    final writingState = _ref.read(writingStoreProvider(_chapterId));
    final content = writingState.localContent;
    if (content.trim().length < UILimits.quickObservationWordThreshold) {
      if (!_host.isMounted) return null;
      _showSnack('请至少写 ${UILimits.quickObservationWordThreshold} 字后再快速观察');
      return null;
    }
    return (sid: sid, content: content);
  }

  /// 统一 SnackBar 提示（复用宿主 context）。
  void _showSnack(String message, {int? durationMs, bool floating = false}) {
    ScaffoldMessenger.of(_host.context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: durationMs == null
            ? const Duration(milliseconds: 4000)
            : Duration(milliseconds: durationMs),
        behavior: floating ? SnackBarBehavior.floating : SnackBarBehavior.fixed,
      ),
    );
  }
}
