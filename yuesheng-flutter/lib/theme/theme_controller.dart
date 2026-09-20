// ─────────────────────────────────────────────────────────────
// theme_controller — 多主题注册表 + 运行期切换（持久化到 app_state）
//
// 为什么是「注册表」而非「ThemeMode.light/dark」：
//   舰长要求「为后续更多主题配色做准备、逻辑可复用」。若把主题写死成 light/dark 两套
//   分支（旧 main.dart 的做法），加第三套配色就得再改分支、再逐处判断 —— 不可复用。
//   注册表把「主题」抽象成一个 key：加一套主题 = 新增一份 AppPalette + 一个 ThemeData
//   工厂 + 注册表加一行；widget 与组件主题**零改动**（它们只认 Theme.of(context)）。
//
// 单一真源：主题选择经本 controller 读写 app_state，MaterialApp watch 它。
// 样板同 reasoning_tier_provider / 旧 theme_mode_provider（本文件取代后者）。
//
// ⚠️ 只支持手动选择（不跟随系统深色）：ColorOS 强制深色改写像素 + 自绘 splash，
//   系统路径不可控（见 reports/2026-09-20-手动暗色开关与三态债收敛.md §一）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_palette.dart';
import '../data/repositories/app_state_repository.dart';
import '../providers/app_providers.dart';
import 'app_theme.dart';
import 'theme_registry.dart';

/// app_state 存储键（值为 [ThemeId.wireName]）。
const String kThemeIdKey = 'theme_id';

/// 主题控制器：持有当前 [ThemeId]，水合自 app_state，写操作乐观更新 + 落库。
class ThemeController extends Notifier<ThemeId> {
  bool _hydrated = false;

  @override
  ThemeId build() => ThemeId.light;

  /// 从 app_state 水合（幂等；读失败 / 未知 key ⇒ 回落 light）。
  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      final stored = await repo.getValue(kThemeIdKey);
      final id = ThemeId.fromWire(stored);
      // 只接受注册表里真实存在的主题（防止脏值 / 已下线主题）
      if (id != null && themeRegistry.containsKey(id)) state = id;
    } catch (_) {
      // 读失败保持 light（最保守）
    }
  }

  /// 切换主题：乐观更新 → 落库 → 失败回滚。
  Future<bool> select(ThemeId id) async {
    if (!themeRegistry.containsKey(id)) return false;
    final prev = state;
    state = id;
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      await repo.setValue(kThemeIdKey, id.wireName);
      return true;
    } catch (_) {
      state = prev;
      return false;
    }
  }
}

/// 当前主题 id（默认 light；首帧后由 [ThemeController.hydrate] 校正）。
final themeControllerProvider = NotifierProvider<ThemeController, ThemeId>(
  ThemeController.new,
);

/// 便捷：某主题 id 是否暗色（供设置页开关用）。走注册表的 brightness，不写死枚举。
bool themeIsDark(ThemeId id) => id.brightness == Brightness.dark;

/// 取某主题 id 对应的 ThemeData（MaterialApp 用）。
ThemeData themeDataFor(ThemeId id) => themeRegistry[id] ?? buildAppTheme();

/// 取某主题 id 对应的调色板（组件主题 / 测试对账用）。
AppPalette paletteOf(ThemeId id) => paletteRegistry[id] ?? AppPalette.light;
