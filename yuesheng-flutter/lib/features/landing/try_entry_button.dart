// ─────────────────────────────────────────────────────────────
// try_entry_button.dart — 书架 header 上的「试用」入口（web-only）
//
// 舰长 2026-11-11 22:24 定形态：**在 header 加一个试用按键切界面**（`§4-499`）。
//
// 【为什么做成独立组件、而不是在 `bookshelf_page` 里内联 `if (kIsWeb)`】
//   `kIsWeb` 在 VM 测试恒 `false` ⇒ 内联写法下「非 web 不渲染」这一支**永远测不到**，
//   而「web 渲染」这一支**永远走不到** —— 两个方向都不可断言（`PRACTICES A3c`）。
//   抽成组件 + 可注入 `isWeb` 后，两个分支都能在测试里被钉住：
//   负向 = `isWeb: true` 必须找到「试用」；正对照 = `isWeb: false` 必须 `findsNothing`。
//
// 【非 web 为什么返回 `SizedBox.shrink()` 而不是让调用方不挂】
//   AppBar 的 `actions` 是列表，挂一个 0×0 的占位对布局零影响；换来的是
//   **调用处只有一行、且不需要在 `bookshelf_page` 里做平台判断**（那里再加一个
//   `kIsWeb` 分支，就又多了一个「判定散落」的点）。判定集中在 `isWebSurface`。
//
// 【为什么用 `Navigator.push` 而不加一条 go_router 路由】
//   `app_router.dart` 在 R-019 **文件级基线**里记 428 行、容差 0 ⇒ 加路由必然触发
//   基线重生成。而本入口不需要深链（`/try` 没有分享语义），全屏 push 即可，
//   返回栈天然正确。同型先例：`chat_page_body.dart` 的 IA-4 用 `Navigator.push`
//   推 `CoachSettingsPage`。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_palette.dart';
import 'landing_gate.dart';
import 'web_landing_page.dart';

/// 书架 header 的「试用」文字键。非 web 端面渲染为 0×0 占位。
class TryEntryButton extends StatelessWidget {
  const TryEntryButton({super.key, this.isWeb});

  /// 仅供测试覆写；生产不传，取 [isWebSurface]。
  final bool? isWeb;

  @override
  Widget build(BuildContext context) {
    if (!isWebSurface(isWeb: isWeb)) return const SizedBox.shrink();
    return TextButton(
      onPressed: () => _openIntro(context),
      style: TextButton.styleFrom(
        foregroundColor: context.palette.primary,
        // 紧贴 AppBar：去掉默认水平 padding，靠 48 的 toolbar 高度保证触控达标。
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(44, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: const Text('试用'),
    );
  }

  /// 推入介绍页（入口态：有返回键，CTA 为「知道了，去试试」）。
  ///
  /// `onStart` 与 `onBack` 都出栈 —— 用户此刻**已在主壳内**，介绍页的用途是
  /// 「告诉他怎么试」，看完就该回去自己动手；留在这里反而挡住了书架。
  void _openIntro(BuildContext context) {
    final nav = Navigator.of(context);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WebLandingPage(onStart: () => nav.pop(), onBack: () => nav.pop()),
      ),
    );
  }
}
