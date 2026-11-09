// ─────────────────────────────────────────────────────────────
// chat_diagnosis_controller — 聊天页诊断/活跃问题动作控制器
//
// 从 chat_teaching.dart（原 part/extension）真分解而来：
//   handleAutoDiagnose / loadSyndromeHistorySection / loadActiveProblems
//   / handleMarkComplete / handleRemoveProblem
//
// 原 76 行超限方法拆为 handleAutoDiagnose + _showTooShortSnack + _runDiagnosis + _finalizeDiagnosis（R-019）。
//
// 依赖经 [ChatPageHost] 显式注入；回退发送委托 [ChatTeachingController]。
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../config/diagnosis_temperature.dart';
import '../../config/shared_constants.dart';
import '../../data/database/database.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/diagnosis_repository.dart';
import '../../data/repositories/event_fact_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/chat_store.dart';
import '../../providers/session_providers.dart';
import '../../services/chapter_position.dart';
import '../../services/discovery_card_payload.dart';
import '../../services/discovery_chat_pilot.dart';
import '../../services/discovery_note.dart';
import '../../services/progressive_diagnosis.dart';
import '../../services/source_plane_capture.dart';
import '../../services/story_structure_profile.dart';
import '../../services/syndrome_tracker.dart';
import '../../services/verification_gate.dart';
import 'chat_page_host.dart';
import 'chat_teaching_controller.dart';
import '../../theme/app_typography.dart';
import '../../config/app_palette.dart';

/// 聊天页诊断与活跃问题动作
class ChatDiagnosisController {
  final ChatPageHost host;
  final ChatTeachingController teaching;

  ChatDiagnosisController(this.host, this.teaching);

  /// 批次 13 自动诊断（对齐 RN sendDiagnosisMessage）：长文走分块链，短文走单次诊断 prompt。
  Future<void> handleAutoDiagnose(String chapterId) async {
    // 清空 pending，避免重复触发（对齐 RN diagnosisStartedRef）
    host.ref.read(pendingDiagnosisChapterProvider.notifier).state = null;
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final db = host.ref.read(appDatabaseProvider);
    // W-15-B：messenger 在首个 await 前捕获（host.context 跨 async gap 会触发 lint）。
    final messenger = ScaffoldMessenger.of(host.context);
    // 先上屏 loading：等待落盘期间用户看到「正在准备诊断内容…」而非无响应。
    host.ref
        .read(chatStoreProvider.notifier)
        .setStreaming(true, stageLabel: '正在准备诊断内容…');
    try {
      final outcome = await _waitForDiagnosableChapter(db, chapterId);
      if (!host.mounted) return;
      final chapter = outcome.chapter;
      if (chapter == null) {
        // 轮询超时仍不可诊断——上传落盘未完成或正文不足，给明确提示而非静默。
        host.ref.read(chatStoreProvider.notifier).cancelStreaming();
        if (outcome.tooShort) {
          _showTooShortSnack();
        } else {
          _showContentNotReadySnack();
        }
        return;
      }
      // B0c 后半件：诊断发起前留 D2 源面快照（纯仪器，失败不阻断主链）。
      unawaited(
        captureDiagnosisSourcePlane(
          chapterText: chapter.content,
          loader: sessionMessageLoader(db, bootstrap.sessionId),
        ),
      );
      await _runDiagnosis(chapter, bootstrap);
    } on ProgressiveMergeOverBudget catch (e) {
      // W-15-B B1：merge 预算拒发——显式提示（设计稿 §3.1「UI 显式报」），不落入下方通用静默 catch。
      if (host.mounted) {
        host.ref.read(chatStoreProvider.notifier).cancelStreaming();
        messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
      }
    } catch (_) {
      // 诊断失败不打断页面，错误由 sendMessage 的 onError / finally 复位处理
    } finally {
      if (host.mounted) await _finalizeDiagnosis(bootstrap.sessionId);
    }
  }

  /// 轮询等待章节正文落盘可见。上传即诊断时章节行可能刚由导入事务写入，首次
  /// getChapter 可能拿不到或 content 为空。最多等 ~1s（10×100ms）；
  /// 返回 (chapter: 就绪章节 / null, tooShort: 章节已在但正文不足门槛)。
  Future<({Chapter? chapter, bool tooShort})> _waitForDiagnosableChapter(
    AppDatabase db,
    String chapterId,
  ) {
    return waitForDiagnosableChapter(
      fetch: () => ChapterRepository(db).getChapter(chapterId),
    );
  }

  /// 内容尚未就绪（上传落盘未完成）提示。
  void _showContentNotReadySnack() {
    ScaffoldMessenger.of(
      host.context,
    ).showSnackBar(const SnackBar(content: Text('章节内容尚未就绪，请稍候再试一次')));
  }

  /// 章节过短提示（对齐 RN 内容校验分支）。
  void _showTooShortSnack() {
    ScaffoldMessenger.of(host.context).showSnackBar(
      const SnackBar(
        content: Text('章节内容少于 ${UILimits.diagnosisWordThreshold} 字，请先编辑章节'),
      ),
    );
  }

  /// 本书结构画像文本（ADR-0006：覆盖度不足/事件表空/异常 ⇒ 空串）。
  Future<String> _structureProfileText(Chapter chapter) async {
    final db = host.ref.read(appDatabaseProvider);
    final text = await buildStoryStructureProfileText(
      eventFactRepo: EventFactRepository(db),
      chapterRepo: ChapterRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      manuscriptId: chapter.manuscriptId,
    );
    return text ?? '';
  }

  /// W-15-B B1 级序 b：会话活跃症候 ID 集（merge 超预算降级过滤判据；加载失败返空集=级序 b 跳过）。
  Future<Set<String>> _activeSyndromeIds(String sessionId) async {
    try {
      final problems = await DiagnosisRepository(
        host.ref.read(appDatabaseProvider),
      ).listActiveProblems(sessionId);
      return problems.map((p) => p.syndromeId).toSet();
    } catch (_) {
      return const {};
    }
  }

  /// W-18 用户温度档（merge 段；灵活档 ⇒ null ⇒ 请求体逐字节不变）。
  Future<double?> _mergeTemperature() async => mergeTemperatureFor(
    await AppStateRepository(
      host.ref.read(appDatabaseProvider),
    ).getDiagnosisTemperature(),
  );

  Future<void> _runDiagnosis(
    Chapter chapter,
    SessionBootstrapState bootstrap,
  ) async {
    final historySection = await loadSyndromeHistorySection(
      bootstrap.sessionId,
    );
    final diagPrefs = await AppStateRepository(
      host.ref.read(appDatabaseProvider),
    ).getDiagnosisPrefs();
    host.ref.read(chatServiceProvider).disabledSyndromeIds =
        diagPrefs?.effectiveDisabledIds ?? const {};
    final position = await _positionOf(chapter);
    final configured = await discoveryConfigured(); // S3（R-027 已批）：三键齐轮次快照。
    DiscoveryParseResult? discoveryResult;
    final progressive = await runProgressiveDiagnosis(
      content: chapter.content,
      title: chapter.title,
      llmClient: host.ref.read(llmClientProvider),
      sessionId: bootstrap.sessionId,
      diagnosisContext: historySection,
      structureProfile: await _structureProfileText(chapter),
      disabledSyndromeIds: diagPrefs?.effectiveDisabledIds ?? const {},
      chapterOrder: position?.order,
      totalChapters: position?.total,
      mergeTemperature: await _mergeTemperature(),
      activeSyndromeIds: await _activeSyndromeIds(bootstrap.sessionId),
      verificationGate: productionVerificationGate(),
      onDiscovery: (r) => discoveryResult = r,
      onContent: (delta) {
        host.ref.read(chatStoreProvider.notifier).appendStreamingContent(delta);
      },
    );
    if (progressive != null) {
      await _commitChunkedDiagnosis(
        progressive,
        chapter,
        bootstrap.sessionId,
        discoverySectionOf(configured, discoveryResult),
      );
    } else {
      await teaching.handleSend(
        '请诊断本章：《${chapter.title}》',
        stageLabel: '正在诊断本章…',
        chapterFullText: chapter.content,
        chapterPosition: position,
      );
      unawaited(_runDiscoveryPilot(chapter));
    }
  }

  /// 落点乙试点（裁点甲 · R-027 已批 · T-20261109-01）：短链发现调用入候选区。
  Future<void> _runDiscoveryPilot(Chapter chapter) {
    return runChatChainDiscoveryForChapter(
      gate: productionVerificationGate(),
      llmClient: host.ref.read(llmClientProvider),
      chapter: chapter,
    );
  }

  /// 分块链路收尾：解析合并结果 + 持久化 + 卡片插入（R-019 自 `_runDiagnosis` 拆出）。
  Future<void> _commitChunkedDiagnosis(
    ProgressiveResult progressive,
    Chapter chapter,
    String sessionId,
    DiscoverySectionCard? discovery,
  ) async {
    await host.ref
        .read(chatServiceProvider)
        .commitDiagnosisFromContent(
          sessionId: sessionId,
          fullContent: progressive.fullContent,
          chapterContent: chapter.content,
          // S3：出口三折叠条数据随诊断卡落库（null ⇒ 不落 key ⇒ S0）。
          discovery: discovery,
        );
  }

  /// 真实位次的本地入口（仓库构造注入 `resolveChapterPosition`，R-019 计数留白）。
  Future<({int order, int total})?> _positionOf(Chapter chapter) =>
      resolveChapterPosition(
        ChapterRepository(host.ref.read(appDatabaseProvider)),
        chapter,
      );

  /// 诊断收尾：复位流式标志并回读消息列表。
  Future<void> _finalizeDiagnosis(String sessionId) async {
    host.ref.read(chatStoreProvider.notifier).setStreaming(false);
    final messages = await SessionRepository(
      host.ref.read(appDatabaseProvider),
    ).listMessages(sessionId);
    host.ref.read(chatStoreProvider.notifier).setMessages(messages);
  }

  /// B 档：跨轮次症候历史 → 注入文本。加载失败返回空串（不阻断主流程）。
  Future<String> loadSyndromeHistorySection(String sessionId) async {
    try {
      final tracker = SyndromeTracker(
        DiagnosisRepository(host.ref.read(appDatabaseProvider)),
      );
      final tracked = await tracker.loadSyndromeTrends(sessionId);
      return formatSyndromeHistory(tracked);
    } catch (_) {
      return '';
    }
  }

  /// 批次 18 活跃问题面板：加载当前会话活跃问题列表。
  Future<void> loadActiveProblems(String sessionId) async {
    try {
      final problems = await DiagnosisRepository(
        host.ref.read(appDatabaseProvider),
      ).listActiveProblems(sessionId);
      if (host.mounted) host.setActiveProblems(problems);
    } catch (_) {
      // 加载失败保持空列表，静默
    }
  }

  /// 批次 18 活跃问题面板：标记症候已完成（resolveProblem + 重载）。
  Future<void> handleMarkComplete(String syndromeId) async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;
    await DiagnosisRepository(
      host.ref.read(appDatabaseProvider),
    ).resolveProblem(bootstrap.sessionId, syndromeId);
    await loadActiveProblems(bootstrap.sessionId);
  }

  /// 批次75：移除活跃问题条目（物理删行 + 重载）。
  /// 与「完成」区分：完成保留 resolved 历史供成长曲线，移除 = 主观不再追踪。
  Future<void> handleRemoveProblem(String syndromeId) async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;
    final confirmed = await showDialog<bool>(
      context: host.context,
      barrierDismissible: true,
      barrierColor: host.context.palette.overlay,
      builder: (ctx) => AlertDialog(
        title: Text('移除问题', style: ctx.text.titleLg),
        content: Text(
          '确定要从练习任务中移除这个问题吗？\n移除后需重新诊断才会再次出现。',
          textAlign: TextAlign.center,
          style: ctx.text.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '取消',
              style: TextStyle(color: host.context.palette.textPrimary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: host.context.palette.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: Text(
              '移除',
              style: TextStyle(color: host.context.palette.onPrimary),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DiagnosisRepository(
      host.ref.read(appDatabaseProvider),
    ).removeProblem(bootstrap.sessionId, syndromeId);
    await loadActiveProblems(bootstrap.sessionId);
  }
}

/// 轮询等待章节正文落盘可见（可测纯逻辑，不依赖 host）。
///
/// 上传即诊断时，章节行/正文可能刚由导入事务写入，首次读取拿不到或为空。
/// 这里最多轮询 [maxAttempts] 次、每次间隔 [delay]，直到读到正文达到
/// [threshold] 字数的章节；仍不可诊断则返回 (chapter: null, tooShort: …)，
/// 让调用方给可见提示而不是发空诊断。[fetch] 注入便于测试模拟「稍后才落盘」。
Future<({Chapter? chapter, bool tooShort})> waitForDiagnosableChapter({
  required Future<Chapter?> Function() fetch,
  int threshold = UILimits.diagnosisWordThreshold,
  int maxAttempts = 10,
  Duration delay = const Duration(milliseconds: 100),
}) async {
  Chapter? lastSeen;
  for (var i = 0; i < maxAttempts; i++) {
    Chapter? chapter;
    try {
      chapter = await fetch();
    } catch (_) {
      chapter = null;
    }
    if (chapter != null) {
      lastSeen = chapter;
      if (chapter.content.trim().length >= threshold) {
        return (chapter: chapter, tooShort: false);
      }
    }
    await Future<void>.delayed(delay);
  }
  return (chapter: null, tooShort: lastSeen != null);
}
