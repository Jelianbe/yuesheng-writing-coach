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

import '../config/app_theme.dart';
import '../config/shared_constants.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/session_providers.dart';
import '../services/progressive_diagnosis.dart';
import '../services/syndrome_tracker.dart';
import 'chat_page_host.dart';
import 'chat_teaching_controller.dart';

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
  Future<void> handleAutoDiagnose(String chapterId) async {
    // 清空 pending，避免重复触发（对齐 RN diagnosisStartedRef）
    host.ref.read(pendingDiagnosisChapterProvider.notifier).state = null;
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final db = host.ref.read(appDatabaseProvider);
    final chapter = await ChapterRepository(db).getChapter(chapterId);
    if (chapter == null || !host.mounted) return;

    // 对齐 RN：内容过短提示先编辑（Alert 语义落为 SnackBar）
    if (chapter.content.trim().length < UILimits.diagnosisWordThreshold) {
      _showTooShortSnack();
      return;
    }

    // 批次49：自动诊断阶段标签（分块/单次均适用）
    host.ref
        .read(chatStoreProvider.notifier)
        .setStreaming(true, stageLabel: '正在诊断本章…');
    try {
      await _runDiagnosis(chapter, bootstrap);
    } catch (_) {
      // 诊断失败不打断页面，错误由 sendMessage 的 onError / finally 复位处理
    } finally {
      if (host.mounted) await _finalizeDiagnosis(bootstrap.sessionId);
    }
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
    final progressive = await runProgressiveDiagnosis(
      content: chapter.content,
      title: chapter.title,
      llmClient: host.ref.read(llmClientProvider),
      sessionId: bootstrap.sessionId,
      diagnosisContext: historySection,
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
      barrierColor: AppColors.overlay,
      builder: (ctx) => AlertDialog(
        title: const Text('移除问题', style: AppTextStyles.titleLg),
        content: const Text(
          '确定要从练习任务中移除这个问题吗？\n移除后需重新诊断才会再次出现。',
          textAlign: TextAlign.center,
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '取消',
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: const Text(
              '移除',
              style: TextStyle(color: AppColors.onPrimary),
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
