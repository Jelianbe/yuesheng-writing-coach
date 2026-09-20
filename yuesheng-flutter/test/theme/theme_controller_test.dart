// ─────────────────────────────────────────────────────────────
// theme_controller_test — 多主题注册表控制器
//
// 锁死（每条配一条会因退化实现变红的负例）：
//   ① 默认 light；水合读回已存 dark（否则「切了暗色重启又变亮」）
//   ② select 真落 app_state + 乐观更新；未知/未注册主题被拒
//   ③ 注册表自洽：每个 ThemeId 都有 palette + ThemeData（加主题漏登记即红）
//   ④ themeDataFor/paletteOf 对每个 id 返回非默认（防注册表接错线）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/theme/theme_controller.dart';
import 'package:writingcoach/theme/theme_registry.dart';

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

  ThemeController notifier() =>
      container.read(themeControllerProvider.notifier);
  ThemeId current() => container.read(themeControllerProvider);
  Future<String?> stored() => AppStateRepository(db).getValue(kThemeIdKey);

  group('默认与水合', () {
    test('#1 未水合默认 light', () {
      expect(current(), ThemeId.light);
    });

    test('#2 水合读回已存 dark', () async {
      await AppStateRepository(db).setValue(kThemeIdKey, 'dark');
      await notifier().hydrate();
      expect(current(), ThemeId.dark);
    });

    test('#3 水合读回已存 light ⇒ light（成对，防「恒置 dark」）', () async {
      await AppStateRepository(db).setValue(kThemeIdKey, 'light');
      await notifier().hydrate();
      expect(current(), ThemeId.light);
    });

    test('#4 未知/脏值 ⇒ 保持 light（不落入未注册主题）', () async {
      await AppStateRepository(db).setValue(kThemeIdKey, 'ocean_未上线');
      await notifier().hydrate();
      expect(current(), ThemeId.light);
    });

    test('#5 水合幂等：二次调用不覆盖后改的值', () async {
      await notifier().hydrate();
      await notifier().select(ThemeId.dark);
      await notifier().hydrate();
      expect(current(), ThemeId.dark);
    });
  });

  group('切换与注册表', () {
    test('#6 select dark ⇒ 状态更新 + 落库 + 返回 true', () async {
      final ok = await notifier().select(ThemeId.dark);
      expect(ok, isTrue);
      expect(current(), ThemeId.dark);
      expect(await stored(), 'dark');
    });

    test('#7 select light ⇒ 落库 light（成对）', () async {
      await notifier().select(ThemeId.dark);
      final ok = await notifier().select(ThemeId.light);
      expect(ok, isTrue);
      expect(await stored(), 'light');
    });

    test('#8 注册表自洽：每个 ThemeId 都有 palette + ThemeData', () {
      for (final id in ThemeId.values) {
        expect(paletteRegistry[id], isA<AppPalette>(), reason: '$id 缺 palette');
        expect(themeRegistry[id], isA<ThemeData>(), reason: '$id 缺 ThemeData');
      }
    });

    test('#9 themeDataFor/paletteOf 对 dark 返回暗色实例（防接错线）', () {
      expect(paletteOf(ThemeId.dark), same(AppPalette.dark));
      expect(paletteOf(ThemeId.light), same(AppPalette.light));
      expect(themeIsDark(ThemeId.dark), isTrue);
      expect(themeIsDark(ThemeId.light), isFalse);
    });
  });
}
