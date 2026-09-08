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

    test('#10 死 LAST_SESSION（DB 不存在）→ 回退新建，不采用失效 ID（FK 修复）', () async {
      final lastStorage = _MemoryLastSessionStorage();
      await lastStorage.setLastSessionId('dead-session-id-not-in-db');
      final container = buildContainer(
        overrides: [lastSessionStorageProvider.overrideWithValue(lastStorage)],
      );
      addTearDown(container.dispose);

      // 空 DB + 死 lastId → 必须新建会话，且持久化为新 ID（不得报 FK 错）
      final state = await container.read(sessionBootstrapProvider.future);
      final sessionRepo = SessionRepository(db);
      final sessions = await sessionRepo.listSessions();
      expect(state.sessionId, isNot('dead-session-id-not-in-db'));
      expect(sessions.any((s) => s.id == state.sessionId), isTrue);
      expect(await lastStorage.getLastSessionId(), state.sessionId);
    });

    test('#11 死 LAST_SESSION + DB 有会话 → 回退 updated_at 最新会话', () async {
      final sessionRepo = SessionRepository(db);
      final latestSessionId = await sessionRepo.createBlankSession();
      final lastStorage = _MemoryLastSessionStorage();
      await lastStorage.setLastSessionId('dead-session-id-not-in-db');
      final container = buildContainer(
        overrides: [lastSessionStorageProvider.overrideWithValue(lastStorage)],
      );
      addTearDown(container.dispose);

      final state = await container.read(sessionBootstrapProvider.future);
      expect(state.sessionId, latestSessionId);
    });

    test('#12 死显式目标会话 → 回退最新会话（不采用失效 ID）', () async {
      final sessionRepo = SessionRepository(db);
      final latestSessionId = await sessionRepo.createBlankSession();
      final lastStorage = _MemoryLastSessionStorage();
      final container = buildContainer(
        overrides: [lastSessionStorageProvider.overrideWithValue(lastStorage)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(sessionBootstrapProvider.notifier);
      await notifier.switchTo('dead-target-not-in-db');
      final state = await container.read(sessionBootstrapProvider.future);
      expect(state.sessionId, latestSessionId);
    });
    // ── 以下为第五批审查补充（CR-33） ─────────────────────────
    // SecureStore 走平台通道，keystore 不可用 / 通道未就绪时会抛异常。
    // 「恢复到上次会话」只是体验优化，不应连带打挂整个 bootstrap——
    // 否则 ChatPage 落到「初始化失败，请重试」且无重试入口。

    test('#13 CR-33 回归：LAST_SESSION 写入失败 → 降级，bootstrap 仍成功',
        () async {
      final container = buildContainer(
        overrides: [
          lastSessionStorageProvider.overrideWithValue(
            _ThrowingWriteLastSessionStorage(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(sessionBootstrapProvider.future);

      expect(state.sessionId, isNotEmpty, reason: '写入失败不应阻断启动');
      expect(state.shouldShowOnboarding, isTrue);
    });

    test('#14 CR-33 回归：LAST_SESSION 读取失败 → 回退默认解析', () async {
      final container = buildContainer(
        overrides: [
          lastSessionStorageProvider.overrideWithValue(
            _ThrowingReadLastSessionStorage(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(sessionBootstrapProvider.future);

      expect(state.sessionId, isNotEmpty, reason: '读取失败应回退到新建/最新会话');
    });

    test('#15 CR-33 回归：读写均失败时，会话仍可用于后续刷新', () async {
      final container = buildContainer(
        overrides: [
          lastSessionStorageProvider.overrideWithValue(
            _ThrowingWriteLastSessionStorage(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final first = await container.read(sessionBootstrapProvider.future);
      await container.read(sessionBootstrapProvider.notifier).refresh();
      final second = await container.read(sessionBootstrapProvider.future);

      expect(second.sessionId, first.sessionId, reason: '降级后 refresh 应稳定');
    });
  });
}

/// 写入即抛（模拟 SecureStore 平台通道故障）
class _ThrowingWriteLastSessionStorage implements LastSessionStorage {
  @override
  Future<String?> getLastSessionId() async => null;

  @override
  Future<void> setLastSessionId(String sessionId) async {
    throw Exception('PlatformException: 写入失败');
  }

  @override
  Future<void> clearLastSessionId() async {}
}

/// 读取即抛
class _ThrowingReadLastSessionStorage implements LastSessionStorage {
  @override
  Future<String?> getLastSessionId() async {
    throw Exception('PlatformException: 读取失败');
  }

  @override
  Future<void> setLastSessionId(String sessionId) async {}

  @override
  Future<void> clearLastSessionId() async {}
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

  @override
  Future<void> clearLastSessionId() async {
    _id = null;
  }
}

/// Fake BootstrapService：shouldShowQuestionnaire 总是抛异常
class _ThrowingBootstrapService implements BootstrapService {
  @override
  Future<bool> shouldShowQuestionnaire(String? sessionId) async {
    throw Exception('bootstrap failed');
  }
}
