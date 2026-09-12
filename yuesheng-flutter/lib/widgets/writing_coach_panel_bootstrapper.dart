// ─────────────────────────────────────────────────────────────
// WritingCoachSessionBootstrapper — 会话初始化 / 态度恢复（独立类，无 part）
//
// R-019 真分解：从 _WritingCoachPanelState 抽出的会话引导逻辑——
// 加载章节已有会话（ADR-C81 懒创建：只查不建）+ 恢复评估报告 +
// 从 teaching_state 恢复态度档位。所需能力经构造注入，不隐式依赖 State。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/evaluation_providers.dart';
import '../providers/session_providers.dart';
import '../types/teaching_types.dart';
import 'writing_coach_panel_store.dart' show writingCoachStoreProvider;

/// 会话引导器（初始化已有会话 + 恢复评估报告 + 恢复态度档位）。
class WritingCoachSessionBootstrapper {
  final WidgetRef ref;

  /// 当前章节 id（**动态读取**——widget 复用导致 chapterId 变化时须取最新值）
  final String Function() chapterId;

  /// 会话 id 绑定回调（查到已有会话时写回 State）
  final void Function(String sessionId) onSessionBound;

  /// 态度档位恢复回调（读到后写回 State）
  final void Function(AttitudeLevel attitude) onAttitudeLoaded;

  /// 是否仍挂载（避免 unmounted 时 setState）
  final bool Function() isMounted;

  WritingCoachSessionBootstrapper({
    required this.ref,
    required this.chapterId,
    required this.onSessionBound,
    required this.onAttitudeLoaded,
    required this.isMounted,
  });

  /// 加载章节已有会话（ADR-C81 懒创建：只查不建）。
  ///
  /// 查到 → 绑定 store + 加载消息 + 恢复评估报告 + 恢复态度档；
  /// 查不到 → 不落库任何会话，UI 落空态。
  Future<void> initSession() async {
    final cid = chapterId();
    final db = ref.read(appDatabaseProvider);
    final existing = await SessionRepository(db).findSessionForChapter(cid);
    if (existing == null) return;
    onSessionBound(existing.id);
    await loadAttitude(existing.id);
    ref.read(writingCoachStoreProvider(cid).notifier).setSessionId(existing.id);
    final messages = await SessionRepository(db).listMessages(existing.id);
    ref.read(writingCoachStoreProvider(cid).notifier).setMessages(messages);
    // 批次6 E1：恢复该章节会话的评估报告 + 当前轮次（对齐 chat_page bootstrap）。
    // 注意：不用 resetReports——它会清空 DB 中当前会话报告导致刚训练的数据丢失；
    // restoreForSession 内部会覆盖内存状态并重置 _currentSessionId（防跨会话串写）。
    await ref
        .read(evaluationReportsProvider.notifier)
        .restoreForSession(existing.id);
  }

  /// P1（2026-09-11）：从 teaching_state 恢复本章节会话的态度档位，
  /// 与对话页切换保持同步。加载失败保持默认档，静默。
  Future<void> loadAttitude(String sessionId) async {
    try {
      final state = await ref
          .read(chatServiceProvider)
          .loadAttitudeState(sessionId);
      if (isMounted()) onAttitudeLoaded(state.attitude);
    } catch (_) {
      // 保持默认档，静默（与 chat_page._loadAttitude 一致）
    }
  }
}
