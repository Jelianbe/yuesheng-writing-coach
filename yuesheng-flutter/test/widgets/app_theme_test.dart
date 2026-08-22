// ─────────────────────────────────────────────────────────────
// app_theme_test — 批次67 页面转场收敛
// 断言 buildAppTheme() 的 pageTransitionsTheme 配置：
//   - Android/桌面平台用 YueFadeSlidePageTransitionsBuilder（轻量过渡）
//   - iOS/macOS 保留 CupertinoPageTransitionsBuilder（滑动返回手势）
//   - 过渡时长收敛为 AppMotion.durationTransition（220ms）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_motion.dart';
import 'package:writingcoach/main.dart';

void main() {
  group('批次67 页面转场收敛', () {
    test('Android 用 YueFadeSlide 轻量过渡（替代 450ms 默认长过渡）', () {
      final theme = buildAppTheme();
      final builders = theme.pageTransitionsTheme.builders;
      expect(
        builders[TargetPlatform.android],
        isA<YueFadeSlidePageTransitionsBuilder>(),
      );
    });

    test('其余平台（fuchsia/linux/windows）同样走轻量过渡', () {
      final theme = buildAppTheme();
      final builders = theme.pageTransitionsTheme.builders;
      for (final p in [
        TargetPlatform.fuchsia,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(
          builders[p],
          isA<YueFadeSlidePageTransitionsBuilder>(),
          reason: '$p 应配置 YueFadeSlidePageTransitionsBuilder',
        );
      }
    });

    test('iOS/macOS 保留 Cupertino（滑动返回手势）', () {
      final theme = buildAppTheme();
      final builders = theme.pageTransitionsTheme.builders;
      expect(
        builders[TargetPlatform.iOS],
        isA<CupertinoPageTransitionsBuilder>(),
      );
      expect(
        builders[TargetPlatform.macOS],
        isA<CupertinoPageTransitionsBuilder>(),
      );
    });

    test('轻量转场时长收敛为 220ms（route 时长随 builder 全局生效）', () {
      const builder = YueFadeSlidePageTransitionsBuilder();
      expect(builder.transitionDuration, AppMotion.durationTransition);
      expect(builder.transitionDuration, const Duration(milliseconds: 220));
    });
  });
}
