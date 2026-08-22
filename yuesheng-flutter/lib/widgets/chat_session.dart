// ignore_for_file: invalid_use_of_protected_member
part of 'chat_page.dart';

extension _ChatSession on _ChatPageState {
  /// 重新从 DB 加载消息列表（导入作品建立主引用后刷新上下文）
  Future<void> _reloadMessages() async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;
    final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
    final messages = await sessionRepo.listMessages(bootstrap.sessionId);
    ref.read(chatStoreProvider.notifier).setMessages(messages);
  }

  /// 加载会话列表（SessionDrawer 数据源）
  Future<void> _loadSessions() async {
    try {
      final sessions = await SessionRepository(
        ref.read(appDatabaseProvider),
      ).listSessionsWithPhase();
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (_) {
      // 本地查询失败保持空列表，静默（release 不暴露技术细节）
    }
  }

  /// 切换会话（对齐 RN handleSwitchSession）：
  /// 重置练习/评估报告状态 → bootstrap 切到目标会话 → listen 自动重载消息/态度/引用
  Future<void> _handleSwitchSession(String sessionId) async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || bootstrap.sessionId == sessionId) return;
    _resetSessionScopedState();
    await ref.read(sessionBootstrapProvider.notifier).switchTo(sessionId);
  }

  /// 批次 30：消费待打开会话（清 pending → 切换会话）
  /// 从 build 的 postFrame 回调调用，避免 build 期修改 provider 状态；
  /// shell 重建后 bootstrap 可能仍在加载，先等其就绪再切换，避免丢切换
  Future<void> _consumePendingSession(String sessionId) async {
    final SessionBootstrapState bootstrap;
    final current = ref.read(sessionBootstrapProvider).valueOrNull;
    if (current != null) {
      bootstrap = current;
    } else {
      try {
        bootstrap = await ref.read(sessionBootstrapProvider.future);
      } catch (_) {
        return; // bootstrap 失败则放弃本次切换
      }
    }
    ref.read(pendingOpenSessionProvider.notifier).state = null;
    if (bootstrap.sessionId == sessionId) return;
    await _handleSwitchSession(sessionId);
  }

  /// 新建会话并切换（对齐 RN handleCreateSession）
  Future<void> _handleCreateSession() async {
    _resetSessionScopedState();
    await ref.read(sessionBootstrapProvider.notifier).createNew();
  }

  /// 批次73：删除会话（抽屉长按入口）
  /// 数据删除 → 刷新列表 → 若删的是当前会话则切到剩余最新会话（无剩余则新建）
  Future<void> _handleDeleteSession(String sessionId) async {
    final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    await sessionRepo.deleteSession(sessionId);
    await _loadSessions();
    if (bootstrap == null || bootstrap.sessionId != sessionId) return;
    _resetSessionScopedState();
    final remaining = _sessions
        .where((s) => s.session.id != sessionId)
        .toList();
    if (remaining.isEmpty) {
      await ref.read(sessionBootstrapProvider.notifier).createNew();
    } else {
      await ref
          .read(sessionBootstrapProvider.notifier)
          .switchTo(remaining.first.session.id);
    }
  }

  /// 切换/新建会话时清空上一会话的临时状态（对齐 RN 重置诊断/练习/模态 store）
  void _resetSessionScopedState() {
    ref.read(practiceStoreProvider.notifier).resetPractice();
    ref.read(evaluationReportsProvider.notifier).resetReports();
    setState(() {
      _inputText = '';
      _attitudeSuggestion =
          null; // 对齐 RN reset 模态 store（lastSuggestionTime 为页面级不清）
    });
  }
}
