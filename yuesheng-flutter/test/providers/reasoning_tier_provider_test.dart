// ─────────────────────────────────────────────────────────────
// reasoning_tier_provider_test — 推理档位的 UI 共享状态
//
// 为什么单独测这一层：档位有**两个改动入口**（设置页 / 聊天页更多菜单）
// 与**一个显示入口**（输入框开关）。若两页各持本地副本，改一处另一处仍
// 显示旧值。本层是 UI 侧唯一可读源，故必须锁死：
//   ① 写操作真落 app_state（不只是内存）
//   ② 开关 ⇄ 档位换算经 notifier，且「上次开启态档位」被记住
//   ③ hydrate 幂等（两页首帧都会调）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/reasoning_tier.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/reasoning_tier_provider.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  ReasoningTierNotifier notifier() =>
      container.read(reasoningTierProvider.notifier);

  String currentTier() => container.read(reasoningTierProvider);

  Future<String?> storedTier() => AppStateRepository(db).getReasoningTier();

  Future<String?> storedLastOn() =>
      AppStateRepository(db).getValue(kReasoningTierLastOnKey);

  group('默认与水合', () {
    test('#1 未水合时默认标准档（不干预请求体，行为最保守）', () {
      expect(currentTier(), reasoningTierStandard);
    });

    test('#2 水合读回已存档位', () async {
      await AppStateRepository(db).setReasoningTier(reasoningTierDeep);

      await notifier().hydrate();

      expect(currentTier(), reasoningTierDeep);
    });

    test('#3 存量未知 key / 无记录 ⇒ 标准档（旧库前向兼容）', () async {
      final repo = AppStateRepository(db);
      await repo.setReasoningTier('未知档位');
      await notifier().hydrate();
      expect(currentTier(), reasoningTierStandard);

      // 另一容器：完全无记录
      final fresh = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(fresh.dispose);
      await fresh.read(reasoningTierProvider.notifier).hydrate();
      expect(fresh.read(reasoningTierProvider), reasoningTierStandard);
    });

    test('#4 水合幂等：二次调用不覆盖后改的值（两页首帧都调）', () async {
      await notifier().hydrate();
      await notifier().setTier(reasoningTierLow);

      await notifier().hydrate(); // 再次调用应直接返回

      expect(currentTier(), reasoningTierLow);
    });
  });

  group('显式选档', () {
    test('#5 选档成功 ⇒ 状态更新 + 落库 + 返回 true', () async {
      final ok = await notifier().setTier(reasoningTierLow);

      expect(ok, isTrue);
      expect(currentTier(), reasoningTierLow);
      expect(await storedTier(), reasoningTierLow);
    });

    test('#6 选开启态档位 ⇒ 同时记住「上次开启态档位」', () async {
      await notifier().setTier(reasoningTierDeep);

      expect(await storedLastOn(), reasoningTierDeep);
    });

    test('#7 选关闭档 ⇒ 不覆盖「上次开启态档位」', () async {
      await notifier().setTier(reasoningTierDeep);
      await notifier().setTier(reasoningTierOff);

      expect(currentTier(), reasoningTierOff);
      expect(await storedTier(), reasoningTierOff);
      expect(await storedLastOn(), reasoningTierDeep);
    });
  });

  group('开关（输入框上方二值入口）', () {
    test('#8 关 ⇒ 关闭思考档；开 ⇒ 恢复上次开启态档位', () async {
      await notifier().setTier(reasoningTierDeep);

      await notifier().setThinkingEnabled(false);
      expect(currentTier(), reasoningTierOff);
      expect(isThinkingEnabled(currentTier()), isFalse);

      await notifier().setThinkingEnabled(true);
      expect(currentTier(), reasoningTierDeep);
      expect(isThinkingEnabled(currentTier()), isTrue);
    });

    test('#9 从未选过档位：关再开 ⇒ 回到标准档（不产生未知值）', () async {
      await notifier().setThinkingEnabled(false);
      await notifier().setThinkingEnabled(true);

      expect(currentTier(), reasoningTierStandard);
      expect(await storedTier(), reasoningTierStandard);
    });

    test('#10 水合到 off + last_on ⇒ 开开关恢复到 last_on（跨会话记忆）', () async {
      final repo = AppStateRepository(db);
      await repo.setReasoningTier(reasoningTierOff);
      await repo.setValue(kReasoningTierLastOnKey, reasoningTierLow);

      await notifier().hydrate();
      expect(currentTier(), reasoningTierOff);

      await notifier().setThinkingEnabled(true);
      expect(currentTier(), reasoningTierLow);
    });

    test('#11 水合到开启态档位 ⇒ 该档位即「上次开启态」（无需读 last_on）', () async {
      await AppStateRepository(db).setReasoningTier(reasoningTierLow);

      await notifier().hydrate();
      await notifier().setThinkingEnabled(false);
      await notifier().setThinkingEnabled(true);

      expect(currentTier(), reasoningTierLow);
    });
  });
}
