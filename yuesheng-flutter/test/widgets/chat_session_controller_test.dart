// ─────────────────────────────────────────────────────────────
// chat_session_controller_test — 会话管理动作控制器**直接**测试
//
// 背景（2026-09-17 批 3 收尾顺带发现）：
//   本控制器在 `test/` **零引用** —— 此前只被 ChatPage 内部实例化，
//   全靠 UI 驱动间接覆盖。于是本批补的两处 `logSilentDegrade`
//   （1b6e4bb，R-028 空 catch 留痕修复）**没有任何断言能证明它生效**。
//
// 覆盖：
//   成功路径：loadSessions / rename / togglePin / deleteSession（非当前）
//   降级路径：本地库不可用 ⇒ 不崩 UI + **真实落 error_logs**（R-028 契约）
//
// 注入方式：`ChatPageHost` 是显式接口 ⇒ 用最小宿主 harness 直测控制器，
//   不经过 ChatPage（避免 UI 断言掩盖控制流）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/chat_store.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/attitude_advisor.dart';
import 'package:writingcoach/services/error_handler.dart';
import 'package:writingcoach/types/coach_persona.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/features/chat/chat_attitude_controller.dart';
import 'package:writingcoach/features/chat/chat_diagnosis_controller.dart';
import 'package:writingcoach/features/chat/chat_input.dart';
import 'package:writingcoach/features/chat/chat_page_host.dart';
import 'package:writingcoach/features/chat/chat_session_controller.dart';
import 'package:writingcoach/features/chat/chat_teaching_controller.dart';

import '../helpers/mock_last_session_storage.dart';

/// 关闭数据库（忽略「已关闭」的二次关闭异常）
Future<void> _closeQuietly(AppDatabase d) async {
  try {
    await d.close();
  } catch (_) {
    // 已在用例内关闭过 ⇒ 忽略
  }
}

/// 轮询等待留痕落库（captureError 内部是 unawaited 异步持久化）
Future<List<ErrorLog>> _waitLogs(AppDatabase logDb, {int atLeast = 1}) async {
  var rows = <ErrorLog>[];
  for (var i = 0; i < 80; i++) {
    rows = await logDb.select(logDb.errorLogs).get();
    if (rows.length >= atLeast) break;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return rows;
}

/// 取某条留痕（按精确 message 匹配）
ErrorLog _logWith(List<ErrorLog> rows, String message) =>
    rows.firstWhere((r) => r.message == message);

void main() {
  late AppDatabase db; // 业务库（用例内可关闭以模拟「本地库不可用」）
  late AppDatabase logDb; // 日志库（独立，承接留痕；业务库关了它照写）

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logDb = AppDatabase.forTesting(NativeDatabase.memory());
    ErrorHandler.instance.resetForTesting();
    ErrorHandler.instance.attachRepository(ErrorLogRepository(logDb));
  });

  tearDown(() async {
    ErrorHandler.instance.resetForTesting();
    await _closeQuietly(db);
    await _closeQuietly(logDb);
  });

  Future<_HostState> pumpHost(
    WidgetTester tester, {
    required AppDatabase database,
  }) async {
    late _HostState state;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          // 批次 50：隔离 flutter_secure_storage 平台通道（testWidgets 下挂起）
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
        ],
        child: MaterialApp(home: _HostHarness(onReady: (s) => state = s)),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  /// 造一个「已激活后关闭」的库：drift 关闭后读写均抛 StateError
  /// （实测 `Can't re-open a database after closing it`）
  Future<AppDatabase> brokenDb() async {
    final d = AppDatabase.forTesting(NativeDatabase.memory());
    await d.select(d.sessions).get(); // 先激活连接
    await d.close();
    return d;
  }

  group('成功路径（本地库可用）', () {
    testWidgets('loadSessions 把 DB 会话列表灌入宿主', (tester) async {
      final id = await SessionRepository(db).createBlankSession(title: '甲');
      final host = await pumpHost(tester, database: db);

      expect(host.sessions, isEmpty, reason: '初始未加载');

      await host.controller.loadSessions();

      expect(host.sessions, hasLength(1));
      expect(host.sessions.single.session.id, id);
      expect(host.sessions.single.session.title, '甲');
    });

    testWidgets('handleRenameSession 写库生效并刷新宿主列表', (tester) async {
      final id = await SessionRepository(db).createBlankSession(title: '旧名');
      final host = await pumpHost(tester, database: db);

      await host.controller.handleRenameSession(id, '新名');

      final list = await SessionRepository(db).listSessions();
      expect(
        list.firstWhere((s) => s.id == id).title,
        '新名',
        reason: 'DB 标题应已更新',
      );
      expect(
        host.sessions.firstWhere((s) => s.session.id == id).session.title,
        '新名',
        reason: '宿主列表应已刷新（成功路径内会调 loadSessions）',
      );
    });

    testWidgets('handleTogglePinSession 读当前值翻转置顶', (tester) async {
      final id = await SessionRepository(db).createBlankSession(title: '甲');
      final host = await pumpHost(tester, database: db);
      await host.controller.loadSessions();
      expect(host.sessions.single.session.pinned, 0, reason: '初始未置顶');

      await host.controller.handleTogglePinSession(id);
      var list = await SessionRepository(db).listSessions();
      expect(list.firstWhere((s) => s.id == id).pinned, 1, reason: '应置顶');

      await host.controller.handleTogglePinSession(id);
      list = await SessionRepository(db).listSessions();
      expect(list.firstWhere((s) => s.id == id).pinned, 0, reason: '应取消置顶');
    });

    testWidgets('handleDeleteSession 删非当前会话：只删不切换', (tester) async {
      final keep = await SessionRepository(db).createBlankSession(title: '保留');
      final drop = await SessionRepository(db).createBlankSession(title: '删除');
      final host = await pumpHost(tester, database: db);
      await host.controller.loadSessions();
      expect(host.sessions.map((s) => s.session.id), containsAll([keep, drop]));

      await host.controller.handleDeleteSession(drop);

      final ids = (await SessionRepository(
        db,
      ).listSessions()).map((s) => s.id).toList();
      expect(ids, isNot(contains(drop)), reason: '目标会话应被删除');
      expect(ids, contains(keep), reason: '其余会话不受影响');
      expect(
        host.sessions.map((s) => s.session.id),
        isNot(contains(drop)),
        reason: '宿主列表应已刷新',
      );
    });

    // FIX-2：resetSessionScopedState 重置主引用标题 + pending 诊断章节（防跨会话串引用/串诊断）
    testWidgets('resetSessionScopedState 清空引用标题与 pending 诊断', (tester) async {
      final host = await pumpHost(tester, database: db);
      host.setPrimaryRefTitle('旧书');
      host.ref.read(pendingDiagnosisChapterProvider.notifier).state = 'ch-old';

      host.controller.resetSessionScopedState();

      expect(host.primaryRefTitle, isNull, reason: '旧书名不得残留到新会话');
      expect(
        host.ref.read(pendingDiagnosisChapterProvider),
        isNull,
        reason: 'pending 诊断章节不得跨会话存活',
      );
    });

    // A4：切/建会话入口必须取消在途流式，并复位流式 UI（防旧会话串台）
    testWidgets('resetSessionScopedState 取消旧流 + 复位流式 UI（A4）', (tester) async {
      final host = await pumpHost(tester, database: db);
      // 模拟「上一会话正在流式」
      host.ref
          .read(chatStoreProvider.notifier)
          .setStreaming(true, stageLabel: '正在思考…');
      host.ref.read(chatStoreProvider.notifier).appendStreamingContent('旧会话残留');
      expect(host.ref.read(chatStoreProvider).isStreaming, isTrue);

      host.controller.resetSessionScopedState();

      expect(
        host.cancelGenerationCalls,
        greaterThanOrEqualTo(1),
        reason: '复位会话状态必须先取消旧流',
      );
      expect(
        host.ref.read(chatStoreProvider).isStreaming,
        isFalse,
        reason: '新会话不在生成中，ThinkingIndicator 不得残留',
      );
      expect(
        host.ref.read(chatStoreProvider).streamingContent,
        '',
        reason: '旧会话流式文本不得串到新会话',
      );
    });

    testWidgets('handleSwitchSession 入口先取消在途流式（A4）', (tester) async {
      final a = await SessionRepository(db).createBlankSession(title: '甲');
      final b = await SessionRepository(db).createBlankSession(title: '乙');
      final host = await pumpHost(tester, database: db);
      // harness 未 watch bootstrap ⇒ 主动 await future 触发其构建（懒加载）
      await host.ref.read(sessionBootstrapProvider.future);
      await tester.pump();

      final current = host.ref.read(sessionBootstrapProvider).value?.sessionId;
      expect(current, isNotNull);
      // 切到「非当前」的那个会话（bootstrap 落点取决于 updated_at 顺序，不取假设）
      final other = current == a ? b : a;

      final before = host.cancelGenerationCalls;
      await host.controller.handleSwitchSession(other);
      await tester.pump();

      expect(
        host.cancelGenerationCalls,
        greaterThan(before),
        reason: '切换会话必须先取消旧流，避免旧会话 chunk/完成/错误污染新会话 UI',
      );
      expect(
        host.ref.read(sessionBootstrapProvider).value?.sessionId,
        other,
        reason: '切换后 bootstrap 应指向目标会话',
      );
    });
  });

  group('降级路径（本地库不可用 ⇒ R-028 留痕契约）', () {
    testWidgets('handleRenameSession 失败：不抛出 + 留痕落 error_logs', (tester) async {
      final broken = await brokenDb();
      final host = await pumpHost(tester, database: broken);

      // 关键：降级不崩 UI ⇒ 不应抛出
      await host.controller.handleRenameSession('s-x', '新名');

      final rows = await _waitLogs(logDb, atLeast: 2);
      final messages = rows.map((r) => r.message).toList();
      expect(
        messages,
        contains('handleRenameSession 降级（失败不阻断）'),
        reason: 'R-028：controller 的降级 catch 必须留痕（本批 1b6e4bb 修复点）',
      );
      expect(
        messages.any((m) => m.contains('renameSession')),
        isTrue,
        reason: '仓储写守卫也应留痕（guardRepoWrite 捕获后 rethrow）',
      );

      final degrade = _logWith(rows, 'handleRenameSession 降级（失败不阻断）');
      expect(degrade.level, 'warn', reason: '降级 = 功能未中断 ⇒ warn 而非 error');
      expect(degrade.category, 'general');
    });

    testWidgets('handleTogglePinSession 失败：不抛出 + 留痕落 error_logs', (
      tester,
    ) async {
      final broken = await brokenDb();
      final host = await pumpHost(tester, database: broken);

      await host.controller.handleTogglePinSession('s-x');

      final rows = await _waitLogs(logDb, atLeast: 2);
      final messages = rows.map((r) => r.message).toList();
      expect(
        messages,
        contains('handleTogglePinSession 降级（失败不阻断）'),
        reason: 'R-028：置顶降级必须留痕（本批 1b6e4bb 修复点）',
      );

      final degrade = _logWith(rows, 'handleTogglePinSession 降级（失败不阻断）');
      expect(degrade.level, 'warn');
      expect(degrade.category, 'general');
    });

    testWidgets('loadSessions 失败：不抛出，保持空列表（有意静默）', (tester) async {
      final broken = await brokenDb();
      final host = await pumpHost(tester, database: broken);

      await host.controller.loadSessions();

      expect(host.sessions, isEmpty, reason: '查询失败保持空列表，不崩 UI');
    });
  });

  // ════════════════════════════════════════════════════════
  // C129：态度档位「设置↔对话」链路（断点 A 刷新打通 + 断点 B 锁定透明化）
  // 直测 ChatAttitudeController.loadAttitude / handleAttitudeChange：
  //   真实内存库 + 真实 chatServiceProvider（loadAttitudeState 全链路跑通）。
  // ════════════════════════════════════════════════════════
  group('C129 态度档位设置↔对话链路', () {
    /// 造一个自定义人格并设为全局激活（attitudeLevel 指定其态度档）。
    Future<void> activateCustomPersona(
      AppDatabase d, {
      required String id,
      required String name,
      required AttitudeLevel level,
    }) async {
      final appState = AppStateRepository(d);
      await appState.saveCustomCoachPersona(
        CoachPersona(
          id: id,
          name: name,
          label: '测',
          isSystem: false,
          attitudeLevel: level,
          systemPromptFragment: '测试语气',
        ),
      );
      await appState.setActiveCoachPersona(id);
    }

    testWidgets('A：未锁定会话随全局教练变更重新 resolve（revision 重载语义）', (tester) async {
      final host = await pumpHost(tester, database: db);
      final sessionId = (await host.ref.read(
        sessionBootstrapProvider.future,
      )).sessionId;

      await activateCustomPersona(
        db,
        id: 'c_a',
        name: '教练甲',
        level: AttitudeLevel.yuesheng,
      );
      await host.attitudeController.loadAttitude(sessionId);
      expect(host.attitude, AttitudeLevel.yuesheng);
      expect(host.isAttitudeLocked, isFalse);

      // 设置页改全局教练为「教练乙（sensei）」→ 对话页收到 revision 信号后
      // 对当前会话重载重 resolve（与 _attitudeController.loadAttitude 同一路径）。
      await activateCustomPersona(
        db,
        id: 'c_b',
        name: '教练乙',
        level: AttitudeLevel.sensei,
      );
      await host.attitudeController.loadAttitude(sessionId);

      expect(host.attitude, AttitudeLevel.sensei, reason: '未锁定会话应反映新全局教练态度');
      expect(host.isAttitudeLocked, isFalse);
    });

    testWidgets('A：锁定会话不受全局教练变更影响', (tester) async {
      final host = await pumpHost(tester, database: db);
      final sessionId = (await host.ref.read(
        sessionBootstrapProvider.future,
      )).sessionId;

      // 先在对话页切档 → 会话锁定 yuesheng（persistAttitude 落库）
      await host.ref
          .read(chatServiceProvider)
          .persistAttitude(sessionId, AttitudeLevel.yuesheng);

      // 设置页把全局教练改为 sensei
      await activateCustomPersona(
        db,
        id: 'c_b',
        name: '教练乙',
        level: AttitudeLevel.sensei,
      );

      await host.attitudeController.loadAttitude(sessionId);

      expect(
        host.attitude,
        AttitudeLevel.yuesheng,
        reason: '锁定会话仍用其锁定态度，不跟全局教练变',
      );
      expect(host.isAttitudeLocked, isTrue);
    });

    testWidgets('A：会话切换重载——锁定会话与新会话各自 resolve 当时状态', (tester) async {
      final host = await pumpHost(tester, database: db);
      await activateCustomPersona(
        db,
        id: 'c_y',
        name: '全局教练',
        level: AttitudeLevel.yuesheng,
      );

      // 会话甲：锁定 sensei
      final s1 = await SessionRepository(db).createBlankSession(title: '甲');
      await host.ref
          .read(chatServiceProvider)
          .persistAttitude(s1, AttitudeLevel.sensei);
      // 会话乙：空白未锁定
      final s2 = await SessionRepository(db).createBlankSession(title: '乙');

      await host.attitudeController.loadAttitude(s1);
      expect(host.attitude, AttitudeLevel.sensei);
      expect(host.isAttitudeLocked, isTrue);

      // 切到会话乙（bootstrap 变更 → _onBootstrapReady → loadAttitude）
      await host.attitudeController.loadAttitude(s2);
      expect(
        host.attitude,
        AttitudeLevel.yuesheng,
        reason: '新会话未锁定 → resolve 全局激活人格态度',
      );
      expect(host.isAttitudeLocked, isFalse);
    });

    testWidgets('B：handleAttitudeChange 成功 → 会话即时锁定', (tester) async {
      final host = await pumpHost(tester, database: db);
      final sessionId = (await host.ref.read(
        sessionBootstrapProvider.future,
      )).sessionId;
      expect(host.isAttitudeLocked, isFalse);

      await host.attitudeController.handleAttitudeChange(AttitudeLevel.sensei);

      expect(host.attitude, AttitudeLevel.sensei);
      expect(host.isAttitudeLocked, isTrue, reason: 'persistAttitude 成功即锁定');
      // DB 侧确证：下次 loadAttitudeState 带锁定标志
      final state = await host.ref
          .read(chatServiceProvider)
          .loadAttitudeState(sessionId);
      expect(state.isAttitudeLocked, isTrue);
    });
  });
}

// ── 最小宿主：用 ConsumerState 拿真实 WidgetRef，实现 ChatPageHost 最小集 ──

class _HostHarness extends ConsumerStatefulWidget {
  const _HostHarness({required this.onReady});

  final void Function(_HostState state) onReady;

  @override
  ConsumerState<_HostHarness> createState() => _HostState();
}

class _HostState extends ConsumerState<_HostHarness> implements ChatPageHost {
  late final ChatSessionController controller = ChatSessionController(this);
  // C129：态度控制器（复用同一宿主 harness 直测 loadAttitude / handleAttitudeChange）
  late final ChatTeachingController _teaching = ChatTeachingController(this);
  late final ChatDiagnosisController _diagnosis = ChatDiagnosisController(
    this,
    _teaching,
  );
  late final ChatAttitudeController attitudeController = ChatAttitudeController(
    this,
    _diagnosis,
  );

  String _inputText = '';
  AttitudeLevel _attitude = AttitudeLevel.doubao;
  TeachingPhase _phase = TeachingPhase.p0Engage;
  // C129：会话态度锁定标志（applyAttitudeState / setAttitudeLocked 写入）
  bool _attitudeLocked = false;
  String? _primaryRefTitle;
  AttitudeSuggestion? _suggestion;
  int? _lastSuggestionTime;
  List<ActiveProblemView> _activeProblems = const [];
  List<SessionWithPhase> _sessions = const [];
  int clearComposerCalls = 0;

  /// A4：记录 cancelActiveGeneration 被调用次数（会话切换入口应取消旧流）
  int cancelGenerationCalls = 0;
  final GlobalKey<ChatInputState> _chatInputKey = GlobalKey<ChatInputState>();

  @override
  TeachingMode get teachingMode => TeachingMode.socratic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady(this);
    });
  }

  // ── ChatPageHost：状态读取 ──
  @override
  String get inputText => _inputText;
  @override
  AttitudeLevel get attitude => _attitude;
  @override
  bool get isAttitudeLocked => _attitudeLocked;
  @override
  String? get activePersonaName => null;
  @override
  TeachingPhase get phase => _phase;
  @override
  String? get primaryRefTitle => _primaryRefTitle;
  @override
  AttitudeSuggestion? get attitudeSuggestion => _suggestion;
  @override
  int? get lastSuggestionTime => _lastSuggestionTime;
  @override
  List<ActiveProblemView> get activeProblems => _activeProblems;
  @override
  List<SessionWithPhase> get sessions => _sessions;
  @override
  GlobalKey<ChatInputState> get chatInputKey => _chatInputKey;

  // ── ChatPageHost：状态写入 ──
  @override
  void setInputText(String value) => _inputText = value;
  @override
  void setAttitude(AttitudeLevel value) => _attitude = value;
  @override
  void applyAttitudeState(
    AttitudeLevel attitude,
    TeachingPhase phase, {
    String? activePersonaName,
    bool isAttitudeLocked = false,
  }) {
    _attitude = attitude;
    _phase = phase;
    _attitudeLocked = isAttitudeLocked;
  }

  @override
  void setAttitudeLocked(bool value) => _attitudeLocked = value;

  @override
  void setPrimaryRefTitle(String? value) => _primaryRefTitle = value;
  @override
  void setAttitudeSuggestion(
    AttitudeSuggestion? suggestion, {
    int? lastSuggestionTime,
  }) {
    _suggestion = suggestion;
    _lastSuggestionTime = lastSuggestionTime;
  }

  @override
  void setActiveProblems(List<ActiveProblemView> value) =>
      _activeProblems = value;
  @override
  void setSessions(List<SessionWithPhase> value) {
    _sessions = value;
  }

  @override
  void clearComposerState() {
    clearComposerCalls++;
  }

  @override
  void cancelActiveGeneration() {
    cancelGenerationCalls++;
  }

  @override
  void scheduleAttitudeCheck() {}

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
