// ─────────────────────────────────────────────────────────────
// app_motion_test — 批次69 动效节奏统一
// 断言 AppMotion 令牌档位（时长/曲线真源），防手改漂移。
// 各组件动画已收敛引用本文件常量（analyze 层保证编译期一致性）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_motion.dart';

void main() {
  group('批次69 AppMotion 动效令牌', () {
    test('时长档位收敛（微交互<组件<转场<翻页）', () {
      expect(AppMotion.durationFast, const Duration(milliseconds: 150));
      expect(AppMotion.durationStandard, const Duration(milliseconds: 200));
      expect(AppMotion.durationTransition, const Duration(milliseconds: 220));
      expect(AppMotion.durationLong, const Duration(milliseconds: 250));

      // 档位递增关系：保证层级语义不被误改
      expect(
        AppMotion.durationFast.inMilliseconds <
            AppMotion.durationStandard.inMilliseconds,
        isTrue,
      );
      expect(
        AppMotion.durationStandard.inMilliseconds <
            AppMotion.durationTransition.inMilliseconds,
        isTrue,
      );
      expect(
        AppMotion.durationTransition.inMilliseconds <
            AppMotion.durationLong.inMilliseconds,
        isTrue,
      );
    });

    test('曲线档位（缓出起步快 / 翻页对称）', () {
      expect(AppMotion.curveStandard, Curves.easeOutCubic);
      expect(AppMotion.curveFade, Curves.easeOut);
      expect(AppMotion.curvePage, Curves.easeInOut);
    });
  });
}
