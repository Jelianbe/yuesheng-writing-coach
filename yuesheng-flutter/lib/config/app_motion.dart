// ─────────────────────────────────────────────────────────────
// app_motion — 动画/转场令牌（批次67-69 统一真源）
//
// 背景：批次67 页面转场收敛——Flutter 默认 PredictiveBack/FadeForwards
// 模拟 Android U Expressive 动画（450ms），体感偏长；本文件提供统一
// 轻量转场（fade + 轻微上滑，220ms，easeOutCubic），并借
// PageTransitionsBuilder.transitionDuration 全局收敛所有页面路由时长。
// 批次69 将各组件动画时长/曲线收敛到本文件常量。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';

/// 月色竹青动效令牌（时长 + 曲线真源）
abstract final class AppMotion {
  /// 微交互（进度点/角标等轻量反馈）
  static const Duration durationFast = Duration(milliseconds: 150);

  /// 组件级动画（卡片展开/面板高度切换/滚动跟随等）
  static const Duration durationStandard = Duration(milliseconds: 200);

  /// 页面转场（路由切换）
  static const Duration durationTransition = Duration(milliseconds: 220);

  /// 翻页滑动（PageView 等横向整页滚动）
  static const Duration durationLong = Duration(milliseconds: 250);

  /// 标准缓出曲线（起步快、收尾缓，切换/弹出「快」的感知来源）
  static const Curve curveStandard = Curves.easeOutCubic;

  /// 淡入/缓出曲线（展开、滚动等单向反馈，无过冲）
  static const Curve curveFade = Curves.easeOut;

  /// 翻页曲线（进出双向对称，横滑顺滑）
  static const Curve curvePage = Curves.easeInOut;

  /// 转场时新页面上滑起始位移（轻微，防生硬）
  static const Offset _slideBegin = Offset(0, 0.03);
}

/// 月笙轻量页面转场（批次67）
///
/// fade + 轻微上滑，220ms easeOutCubic——比 PredictiveBack/FadeForwards
/// （450ms）与 Zoom（缩放感）都更轻快。route 时长自动采用
/// [transitionDuration]（MaterialRouteTransitionMixin 从 builder 读取）。
/// prefers-reduced-motion 时直接渲染 child（无过渡，即时切换）。
class YueFadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const YueFadeSlidePageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.durationTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.curveStandard,
      reverseCurve: AppMotion.curveStandard,
    );
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: AppMotion.curveFade),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: AppMotion._slideBegin,
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
