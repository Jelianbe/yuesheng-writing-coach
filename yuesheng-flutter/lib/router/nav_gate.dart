// ─────────────────────────────────────────────────────────────
// nav_gate.dart — web 首发底部导航的**单一判定点**（NAV-1）
//
// `T-20261111-01` · 舰长 2026-11-11 19:27 裁 · `DECISIONS §4-491 ②`：
// web 首发**不渲染** `NavigationBar`，由 `AppBar` 承载唯一目的地；
// Android 侧行为零变化。
//
// 【为什么不写成 `app_router.dart` 里的内联三元】
//   `kIsWeb` 在 **VM 测试里恒为 `false`** ⇒ 内联写法在 `flutter test`
//   永远走不到「隐藏」这一支，等于**写了一条不可能变红的判据**
//   （本仓反复吃过「判据恒真」的亏，见 `.ai/PRACTICES.md A3c`）。
//   抽成带 `isWeb` 覆写参数的纯函数后，两个分支都能被断言：
//   负向 = `isWeb: true` 必须 `false`；正对照 = `isWeb: false` 必须 `true`
//   （正对照防「函数恒返回 false」这种最省事的假绿）。
//
// 【为什么单独一个文件而不是塞进 `app_router.dart`】
//   `app_router.dart` 已在 R-019 文件级基线登记值上（456 行），
//   容差 0 ⇒ 在该文件里加任何一行都要动基线。抽成独立判定点后
//   `app_router.dart` **净 0 行**（换掉 1 条 import + 1 行表达式）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart' show kIsWeb;

/// 是否渲染底部导航栏。
///
/// `isWeb` 仅供测试覆写；生产调用一律**不传**，取编译期常量 [kIsWeb]。
bool shouldRenderBottomNav({bool? isWeb}) => !(isWeb ?? kIsWeb);
