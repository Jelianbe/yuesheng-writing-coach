// ─────────────────────────────────────────────────────────────
// chat_diagnosis_controller — 聊天页诊断/活跃问题动作控制器
//
// 从 chat_teaching.dart（原 part/extension）真分解而来：
//   handleAutoDiagnose / loadSyndromeHistorySection / loadActiveProblems
//   / handleMarkComplete / handleRemoveProblem
//
// 原 76 行 `_handleAutoDiagnose` 超限方法拆为 handleAutoDiagnose（薄编排）
//   + _showTooShortSnack + _runDiagnosis + _finalizeDiagnosis，满足 R-019。
//
// 依赖经 [ChatPageHost] 显式注入；回退发送委托 [ChatTeachingController]。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../config/shared_constants.dart';
import '../../data/database/database.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/diagnosis_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/chat_store.dart';
import '../../providers/session_providers.dart';
import '../../services/progressive_diagnosis.dart';
import '../../services/syndrome_tracker.dart';
import 'chat_page_host.dart';
import 'chat_teaching_controller.dart';
import '../../theme/app_typography.dart';
import '../../config/app_palette.dart';

/// 聊天页诊断与活跃问题动作
class ChatDiagnosisController {
  final ChatPageHost host;
  final ChatTeachingController teaching;

  ChatDiagnosisController(this.host, this.teaching);

  /// 批次 13 自动诊断：成长页「写作诊断」选章后进入对话页触发。
  ///
  /// 对齐 RN sendDiagnosisMessage：读章节 → 长度校验 → 超长走分块
  /// （runProgressiveDiagnosis + commitDiagnosisFromContent），否则回退
  /// 单次诊断 prompt（显式要求 [YS_DIAGNOSIS] 格式）。
  ///
  /// 上传即诊断修复：+号上传文本点「立即诊断」时，章节行/正文可能尚未对
  /// 当前读连接可见（导入事务刚提交、provider 监听同步触发）。旧实现只读
  /// 一次 getChapter，拿不到就静默 return → 用户看到「无内容返回」。现改为：
  /// 先显示 loading，短暂轮询等待正文落盘可见；就绪才发诊断；超时给明确
  /// 失败提示而不是静默吞掉。
  Future<void> handleAutoDiagnose(String chapterId) async {
    // 清空 pending，避免重复触发（对齐 RN diagnosisStartedRef）
    host.ref.read(pendingDiagnosisChapterProvider.notifier).state = null;
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final db = host.ref.read(appDatabaseProvider);
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
      await _runDiagnosis(chapter, bootstrap);
    } catch (_) {
      // 诊断失败不打断页面，错误由 sendMessage 的 onError / finally 复位处理
    } finally {
      if (host.mounted) await _finalizeDiagnosis(bootstrap.sessionId);
    }
  }

  /// 轮询等待章节正文落盘可见。上传即诊断时章节行可能刚由导入事务写入，
  /// 首次 getChapter 可能拿不到或 content 为空。最多等 ~1s（10×100ms）。
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

  /// 执行诊断：超长分块优先，失败回退单次诊断 prompt。
  Future<void> _runDiagnosis(
    Chapter chapter,
    SessionBootstrapState bootstrap,
  ) async {
    // B 档：加载跨轮次症候历史（出现次数/趋势）→ 分块合并 prompt 注入
    final historySection = await loadSyndromeHistorySection(
      bootstrap.sessionId,
    );
    // 1. 超长分块（>4000 字）优先，质量更好（对齐 RN T-011）
    // 诊断编辑器：读用户全局启用集，关闭的症候不进分块 prompt
    final diagPrefs = await AppStateRepository(
      host.ref.read(appDatabaseProvider),
    ).getDiagnosisPrefs();
    // 诊断编辑器：短文本链路（单次 sendMessage）也用同一启用集
    host.ref.read(chatServiceProvider).disabledSyndromeIds =
        diagPrefs?.effectiveDisabledIds ?? const {};
    final progressive = await runProgressiveDiagnosis(
      content: chapter.content,
      title: chapter.title,
      llmClient: host.ref.read(llmClientProvider),
      sessionId: bootstrap.sessionId,
      diagnosisContext: historySection,
      disabledSyndromeIds: diagPrefs?.effectiveDisabledIds ?? const {},
      onContent: (delta) {
        host.ref.read(chatStoreProvider.notifier).appendStreamingContent(delta);
      },
    );
    if (progressive != null) {
      // 分块链路：解析 + 持久化 + 卡片插入
      await host.ref
          .read(chatServiceProvider)
          .commitDiagnosisFromContent(
            sessionId: bootstrap.sessionId,
            fullContent: progressive.fullContent,
            chapterContent: chapter.content,
          );
    } else {
      // 2. 回退：单次诊断 prompt。对话历史只展示简洁消息（「已发送章节」），
      // 全文由 chapterFullText 运行时注入（不落库，AI 仍收到全部内容）。
      await teaching.handleSend(
        '请诊断本章：《${chapter.title}》',
        stageLabel: '正在诊断本章…',
        chapterFullText: chapter.content,
      );
    }
  }

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
