// ─────────────────────────────────────────────────────────────
// chat_session_controller — 聊天页会话管理动作控制器
//
// 从 chat_session.dart（原 part/extension）真分解而来：
//   reloadMessages / loadSessions / handleSwitchSession
//   / consumePendingSession / handleCreateSession / handleDeleteSession
//   / handleRenameSession / handleTogglePinSession / handleBatchDeleteSessions
//   / resetSessionScopedState
//
// 依赖经 [ChatPageHost] 显式注入。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/evaluation_providers.dart';
import '../providers/practice_providers.dart';
import '../providers/session_providers.dart';
import 'chat_page_host.dart';

/// 聊天页会话管理动作
class ChatSessionController {
  final ChatPageHost host;

  ChatSessionController(this.host);

  /// 重新从 DB 加载消息列表（导入作品建立主引用后刷新上下文）
  Future<void> reloadMessages() async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;
    final sessionRepo = SessionRepository(host.ref.read(appDatabaseProvider));
    final messages = await sessionRepo.listMessages(bootstrap.sessionId);
    host.ref.read(chatStoreProvider.notifier).setMessages(messages);
  }

  /// 加载会话列表（SessionDrawer 数据源）
  Future<void> loadSessions() async {
    try {
      final sessions = await SessionRepository(
        host.ref.read(appDatabaseProvider),
      ).listSessionsWithPhase();
      if (!host.mounted) return;
      host.setSessions(sessions);
    } catch (_) {
      // 本地查询失败保持空列表，静默（release 不暴露技术细节）
    }
  }

  /// 切换会话（对齐 RN handleSwitchSession）：
  /// 重置练习/评估报告状态 → bootstrap 切到目标会话 → listen 自动重载消息/态度/引用
  Future<void> handleSwitchSession(String sessionId) async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || bootstrap.sessionId == sessionId) return;
    resetSessionScopedState();
    await host.ref.read(sessionBootstrapProvider.notifier).switchTo(sessionId);
  }

  /// 批次 30：消费待打开会话（清 pending → 切换会话）。
  /// 从 build 的 postFrame 回调调用，避免 build 期修改 provider 状态；
  /// shell 重建后 bootstrap 可能仍在加载，先等其就绪再切换，避免丢切换
  Future<void> consumePendingSession(String sessionId) async {
    final SessionBootstrapState bootstrap;
    final current = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (current != null) {
      bootstrap = current;
    } else {
      try {
        bootstrap = await host.ref.read(sessionBootstrapProvider.future);
      } catch (_) {
        return; // bootstrap 失败则放弃本次切换
      }
    }
    host.ref.read(pendingOpenSessionProvider.notifier).state = null;
    if (bootstrap.sessionId == sessionId) return;
    await handleSwitchSession(sessionId);
  }

  /// 新建会话并切换（对齐 RN handleCreateSession）
  Future<void> handleCreateSession() async {
    resetSessionScopedState();
    await host.ref.read(sessionBootstrapProvider.notifier).createNew();
  }

  /// 批次73：删除会话（抽屉长按入口）：
  /// 数据删除 → 刷新列表 → 若删的是当前会话则切到剩余最新会话（无剩余则新建）
  Future<void> handleDeleteSession(String sessionId) async {
    final sessionRepo = SessionRepository(host.ref.read(appDatabaseProvider));
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    await sessionRepo.deleteSession(sessionId);
    await loadSessions();
    if (bootstrap == null || bootstrap.sessionId != sessionId) return;
    resetSessionScopedState();
    final remaining = host.sessions
        .where((s) => s.session.id != sessionId)
        .toList();
    if (remaining.isEmpty) {
      await host.ref.read(sessionBootstrapProvider.notifier).createNew();
    } else {
      await host.ref
          .read(sessionBootstrapProvider.notifier)
          .switchTo(remaining.first.session.id);
    }
  }

  /// v30：重命名会话标题
  Future<void> handleRenameSession(String sessionId, String title) async {
    try {
      await SessionRepository(
        host.ref.read(appDatabaseProvider),
      ).renameSession(sessionId, title);
      await loadSessions();
    } catch (_) {}
  }

  /// v30：切换会话置顶（读当前值翻转）
  Future<void> handleTogglePinSession(String sessionId) async {
    try {
      final repo = SessionRepository(host.ref.read(appDatabaseProvider));
      final current = host.sessions
          .where((s) => s.session.id == sessionId)
          .firstOrNull;
      await repo.setPinned(sessionId, current?.session.pinned != 1);
      await loadSessions();
    } catch (_) {}
  }

  /// v30：批量删除会话（逐个复用 deleteSession 链路）
  Future<void> handleBatchDeleteSessions(List<String> ids) async {
    for (final id in ids) {
      await handleDeleteSession(id);
    }
  }

  /// 切换/新建会话时清空上一会话的临时状态（对齐 RN 重置诊断/练习/模态 store）
  void resetSessionScopedState() {
    host.ref.read(practiceStoreProvider.notifier).resetPractice();
    host.ref.read(evaluationReportsProvider.notifier).resetReports();
    host.clearComposerState();
  }
}
