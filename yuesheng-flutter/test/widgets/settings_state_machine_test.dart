// ─────────────────────────────────────────────────────────────
// settings_state_machine_test — 设置页状态机契约
//
// 真源：`T-20261111-01` U1 设计稿 §ST-2 / §ST-3（舰长 2026-11-11 批）
//
// ST-2 三分状态（原文判据）：
//   加载中（不渲染警告）/ 确认未配置（渲染警告）/ **读取失败（不渲染警告，
//   且不谎称「已配置」）**。改动前 `catch (_)` 静默 + `finally` 无条件置
//   `_configLoaded = true` ⇒ 读失败被渲染成「尚未配置 API」。
//
// ST-3 幽灵间距：`_buildUsageSection()` 读不到时自己返回 `shrink`，但它后面
//   那个 `SizedBox(height: 12)` 仍无条件占位 ⇒ 前后两块之间多出 12dp。
//   ★ 设计稿把症状写成「列表顶部 28dp 空白」，实测**位置不对**（用量区块
//     不是首块，`_progressSummary` 才是）；真实症状是「API 卡与外观卡之间
//     +12dp」。判据按实测重写：断两块 SectionCard 的间距。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/features/app_settings/settings_page.dart';
import 'package:writingcoach/features/app_settings/widgets/settings_cards.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/llm_config_storage.dart';

import '../helpers/mock_last_session_storage.dart';

/// 正常存储：无旧单键
class _EmptyConfigStorage extends LlmConfigStorage {
  @override
  Future<LlmConfigValues?> getLlmConfig() async => null;

  @override
  Future<void> saveLlmConfig(LlmConfigValues config) async {}

  @override
  Future<void> clearLlmConfig() async {}
}

/// 故障存储：读旧单键直接抛 ⇒ 走 ST-2 的「读取失败」分支
class _ThrowingConfigStorage extends LlmConfigStorage {
  @override
  Future<LlmConfigValues?> getLlmConfig() async =>
      throw StateError('secure storage 不可用（测试注入）');

  @override
  Future<void> saveLlmConfig(LlmConfigValues config) async {}

  @override
  Future<void> clearLlmConfig() async {}
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildSettings({required LlmConfigStorage storage}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        lastSessionStorageProvider.overrideWithValue(
          MemoryLastSessionStorage(),
        ),
      ],
      child: MaterialApp(home: SettingsPage(configStorage: storage)),
    );
  }

  /// 真实手机视口。
  ///
  /// ★ 刻意**不用**加高视口：360×1600 会把「关于」区块也铺出来，而
  /// `_AboutRow`（`settings_page.dart:1034`）在 360dp 下有**既有的**
  /// 横向溢出 62px（与本卡无关，改动前就在，已登记待裁）。本文件要测的是
  /// 状态机与间距，不该被那笔既有债拖红 —— 用 740 高让列表只铺首屏。
  Future<void> usePhone(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  // ══════════════════════════════════════════════════════════
  // ST-2：读取失败不得显示成「尚未配置」
  // ══════════════════════════════════════════════════════════
  group('ST-2 读失败 ≠ 未配置', () {
    testWidgets('读配置抛异常 → 不出现「尚未配置」警告', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(buildSettings(storage: _ThrowingConfigStorage()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('尚未配置'),
        findsNothing,
        reason: '「不知道」不能被渲染成「没有」—— 原实现会弹这条红色警告',
      );
      // 负对照：区块本身必须在（否则「警告不见了」可能只是整页没渲染）
      expect(find.text('API 配置'), findsOneWidget);
    });

    testWidgets('正对照：确认未配置（无账号 + 无旧键）→ 警告照常出现', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(buildSettings(storage: _EmptyConfigStorage()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('尚未配置'),
        findsOneWidget,
        reason: '真·未配置必须仍然提示，否则 ST-2 会把提示整条改没',
      );
    });
  });

  // ══════════════════════════════════════════════════════════
  // ST-3：用量读不到 → 不留幽灵间距
  // ══════════════════════════════════════════════════════════
  group('ST-3 用量缺失不留幽灵间距', () {
    testWidgets('用量不可用 → API 卡与外观卡间距 == 12（不是 24）', (tester) async {
      await usePhone(tester);
      // 关库：`loadWeekLlmUsage` 抛 ⇒ `_usageReport` 保持 null（区块不渲染）
      await db.close();

      await tester.pumpWidget(buildSettings(storage: _EmptyConfigStorage()));
      await tester.pumpAndSettle();

      final cards = find.byType(SectionCard);
      expect(
        cards.evaluate().length,
        greaterThanOrEqualTo(2),
        reason: '至少应有「API 配置」与「外观」两张卡',
      );

      final apiRect = tester.getRect(cards.at(0));
      final appearanceRect = tester.getRect(
        find.ancestor(of: find.text('外观'), matching: find.byType(SectionCard)),
      );
      final gap = appearanceRect.top - apiRect.bottom;
      expect(gap, 12, reason: '用量区块不渲染时，它后面那个 SizedBox(12) 也必须一起消失');
      // 负对照：确认用量区块真的没渲染（否则这条测的是「间距本来就 12」）
      expect(find.text('本周调用统计'), findsNothing);
    });
  });
}
