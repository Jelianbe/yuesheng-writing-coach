// ─────────────────────────────────────────────────────────────
// session_providers_test — session bootstrap Provider 测试
//
// 覆盖路径：
//   1. 新用户：空 DB → 新建 session + shouldShow=true
//   2. 老用户：questionnaire_completed=true → shouldShow=false
//   3. 复用已有 session（不新建）
//   4. bootstrapService 抛异常 → AsyncError
//   5. refresh() 后重新执行 bootstrap（模拟 onboarding 完成后刷新）
//   6. bootstrapServiceProvider 可被 override（注入 throwingService）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/bootstrap_service.dart';
import 'package:writingcoach/services/last_session_storage.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  /// 构造 ProviderContainer，override appDatabaseProvider 用内存 DB
  /// 默认注入内存 LastSessionStorage（批次 50：避免触碰 flutter_secure_storage 平台通道）
  ProviderContainer buildContainer({List<Override>? overrides}) {
    return ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        lastSessionStorageProvider.overrideWithValue(
          _MemoryLastSessionStorage(),
        ),
        ...?overrides,
      ],
    );
  }

  group('sessionBootstrapProvider', () {
    test('#1 新用户：空 DB → 新建 session + shouldShow=true', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      // 等待 AsyncNotifier build 完成
      final state = await container.read(sessionBootstrapProvider.future);

      // 应新建 session
      final sessionRepo = SessionRepository(db);
      final sessions = await sessionRepo.listSessions();
      expect(sessions.length, 1);
      expect(state.sessionId, sessions.first.id);

      // 新用户应弹问卷
      expect(state.shouldShowOnboarding, true);
    });

    test('#2 老用户：questionnaire_completed=true → shouldShow=false', () async {
      // 预置：标记已完成
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      final container = buildContainer();
      addTearDown(container.dispose);

      final state = await container.read(sessionBootstrapProvider.future);

      expect(state.shouldShowOnboarding, false);
    });

    test('#3 复用已有 session（不新建）', () async {
      // 预置：DB 已存在 session
      final sessionRepo = SessionRepository(db);
      final presetSessionId = await sessionRepo.createBlankSession();

      final container = buildContainer();
      addTearDown(container.dispose);

      final state = await container.read(sessionBootstrapProvider.future);

      // 应复用预置 session，不新建
      final sessions = await sessionRepo.listSessions();
      expect(sessions.length, 1);
      expect(state.sessionId, presetSessionId);
    });

    test('#4 bootstrapService 抛异常 → AsyncError', () async {
      // 注入会抛错的 fake BootstrapService
      final throwingService = _ThrowingBootstrapService();

      final container = buildContainer(
        overrides: [
          bootstrapServiceProvider.overrideWithValue(throwingService),
        ],
      );
      addTearDown(container.dispose);

      // 先 await future 让 build 执行完（应抛异常）
      try {
        await container.read(sessionBootstrapProvider.future);
        fail('应抛异常');
      } catch (_) {}

      // 等待 future 完成后，状态应为 AsyncError（而非 AsyncLoading）
      final asyncState = container.read(sessionBootstrapProvider);
      expect(asyncState, isA<AsyncError<SessionBootstrapState>>());
    });

    test('#5 refresh() 后重新执行 bootstrap（模拟 onboarding 完成后刷新）', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      // 第一次：新用户，shouldShow=true
      final state1 = await container.read(sessionBootstrapProvider.future);
      expect(state1.shouldShowOnboarding, true);

      // 模拟 onboarding 完成：写入 questionnaire_completed
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      // refresh：重新执行 bootstrap
      final notifier = container.read(sessionBootstrapProvider.notifier);
      await notifier.refresh();

      // 应变为 shouldShow=false
      final state2 = await container.read(sessionBootstrapProvider.future);
      expect(state2.shouldShowOnboarding, false);
      // sessionId 应保持一致（复用已有 session）
      expect(state2.sessionId, state1.sessionId);
    });

    test('#6 bootstrapServiceProvider 默认依赖 appDatabaseProvider', () async {
      // 不 override bootstrapServiceProvider，验证它用默认实现
      final container = buildContainer();
      addTearDown(container.dispose);

      final service = container.read(bootstrapServiceProvider);
      expect(service, isA<BootstrapService>());

      // 默认 BootstrapService 应能正常工作
      final state = await container.read(sessionBootstrapProvider.future);
      expect(state.sessionId, isNotEmpty);
    });

    test('#7 恢复 LAST_SESSION：优先于 updated_at 最新会话（批次50）', () async {
      // 预置：两个会话（A 先建、B 后建 = updated_at 最新）
      final sessionRepo = SessionRepository(db);
      final oldSessionId = await sessionRepo.createBlankSession();
      final latestSessionId = await sessionRepo.createBlankSession();
      expect(latestSessionId, isNot(oldSessionId));

      // 预置：LAST_SESSION_KEY 指向旧会话 A
      final lastStorage = _MemoryLastSessionStorage();
      await lastStorage.setLastSessionId(oldSessionId);

      final container = buildContainer(
        overrides: [lastSessionStorageProvider.overrideWithValue(lastStorage)],
      );
      addTearDown(container.dispose);

      // 应恢复上次会话 A，而非 updated_at 最新的 B
      final state = await container.read(sessionBootstrapProvider.future);
      expect(state.sessionId, oldSessionId);
    });

    test('#8 选定会话后持久化 LAST_SESSION_KEY（批次50）', () async {
      final lastStorage = _MemoryLastSessionStorage();
      final container = buildContainer(
        overrides: [lastSessionStorageProvider.overrideWithValue(lastStorage)],
      );
      addTearDown(container.dispose);

      final state = await container.read(sessionBootstrapProvider.future);

      // bootstrap 选定后应写入 LAST_SESSION（对齐 RN initSession L79）
      expect(await lastStorage.getLastSessionId(), state.sessionId);
    });

    test('#9 createNew 新建会话后 LAST_SESSION 更新（批次50）', () async {
      final lastStorage = _MemoryLastSessionStorage();
      final container = buildContainer(
        overrides: [lastSessionStorageProvider.overrideWithValue(lastStorage)],
      );
      addTearDown(container.dispose);

      // 首次 bootstrap：新用户空 DB → 新建会话
      final state1 = await container.read(sessionBootstrapProvider.future);
      expect(await lastStorage.getLastSessionId(), state1.sessionId);

      // 新建会话并切换
      final notifier = container.read(sessionBootstrapProvider.notifier);
      await notifier.createNew();

      // 会话切换，LAST_SESSION 跟随新会话
      final state2 = await container.read(sessionBootstrapProvider.future);
      expect(state2.sessionId, isNot(state1.sessionId));
      expect(await lastStorage.getLastSessionId(), state2.sessionId);
    });
  });
}

/// 内存版 LastSessionStorage（批次50：测试隔离平台通道）
class _MemoryLastSessionStorage implements LastSessionStorage {
  String? _id;

  @override
  Future<String?> getLastSessionId() async => _id;

  @override
  Future<void> setLastSessionId(String sessionId) async {
    _id = sessionId;
  }
}

/// Fake BootstrapService：shouldShowQuestionnaire 总是抛异常
class _ThrowingBootstrapService implements BootstrapService {
  @override
  Future<bool> shouldShowQuestionnaire(String? sessionId) async {
    throw Exception('bootstrap failed');
  }
}
