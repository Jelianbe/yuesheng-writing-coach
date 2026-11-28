// ─────────────────────────────────────────────────────────────
// WritingMenuSheet — 写作页 ⋮ 菜单入口 + 可拖拽容器（百灵极简：纯文字项，无图标）
//
// ★ P1 重裁（T-20261126-04 · R-027 批号「2026-11-26 四项全批 A」）
//   原形态：单列 14 可点项 + 3 组头 + 1 保存行，内容 741dp vs 容器 351.6dp
//   ⇒ 首屏可见率 47.4%、余量仅 0.6dp（全文搜索底 599.4 vs 视口底 600.0）。
//   改后：三 tab 分组，**组头不再渲染**（分组信息由 tab 栏承担，标签复用原
//   组头字面、零新增文案）：
//     ① 写作工具（默认）章节列表·全文搜索·查找替换·快捷短语·回收板 = 5
//     ② 教学 当前文风·写作统计·打开教练面板·世界观·角色·大纲        = 6
//     ③ 设置 排版设置·版本时光机                                    = 2
//   固定区（跨 tab 恒在）：保存状态行（上）+ 取消（下）。
//
// ★ 2026-11-28 戊方案（DECISIONS §4-610/§4-611，舰长「丁按你推荐走」→「按你推荐走」）：
//   ① → ② 移入：角色 + 大纲（大纲依据 U1 翻案：`OutlineRepository` 同表同仓储、
//   同参与 `message_injector.dart:1102 _injectEntityIndex` 诊断注入）；
//   ② → ① 移出：快捷短语（光标插入常用语 = 写作动作）⇒ 分布 6/5/2 → **5/6/2**。
//   0.55 档实测：① `maxScroll 0.00`、取消文字 `791.35–811.35`（完整）；
//                 ② `maxScroll 34.35`、取消文字 `839.35–859.35`（部分可见 + 滚动可达）。
//   ★ 为什么不是 `4/7/2`（只移前两项）：教学 7 项时取消行 top = `887.35 > 851`
//     ⇒ **完全不可见**，破 `批次96-5`「跨 tab 恒在的关闭入口至少露出顶边」。实测红过。
//   ⚠️ 本节下方「改后容量实测 6/6·5/5·2/2」是 **`-26-04` 当时**（分布 6/5/2）的读数，
//      已随本方案过期，**留作历史对照，勿再引为现值**。
//
// ★ 改后容量实测（G6，E1）：真机逻辑尺寸 393×851（1080×2340@2.75）容器
//   489.65dp ⇒ 6/6·5/5·2/2；窄屏 360×800 容器 461.60dp ⇒ 同样 6/6·5/5·2/2。
//
// ★ 容量闭式解（393×851，E1 · 探针 43 例逐位验证，取代旧注释的估算）：
//     sheet_h   = 803f + 48          // f = initialChildSize；48 = 拖拽把手
//     sheet_top = 851 − sheet_h
//     viewport  = 803f − 48          // ★ R5 后 TabBar 在滚动区**外**
//     content   = 140 + 48n          // n = 该 tab 功能项数（不含「取消」）
//     maxScroll = max(0, content − viewport)
//     viewport_top = sheet_top + 96  // 96 = 拖拽把手 48 + TabBar 48
//     第 i 项行 top = viewport_top + 60 + 48(i−1)   // 60 = 上 pad 12 + 保存行 48
//     取消行 top    = viewport_top + 60 + 48n + 20  // 20 = Divider
//     取消 rowOver  = 176 + 48n − 803f              // 176 = 96 + 60 + 20
//     文字 rect = 行 rect 上下各内缩 14             // (48 − 20) / 2
//   三档回归锚点：sheet_h 730.55 / 489.65 / 288.90 · viewport 634.55 / 393.65 / 192.90
//   `140` 的构成 = 12 上 pad + 48 保存行 + 20 分隔线 + 48 取消 + 12 下 pad。
//   ⚠️ 旧注释写的 `188` **不是算错，是过期**（2026-11-28 订正）：
//      `188 = 12+48+48+20+48+12` 六项各出现一次、误差 0，在它自己的时代（R5 前）完全正确。
//      两条 12 是**上、下各一道** padding（两个不同的 12，不是同一个被算两遍）。
//      R5 把 TabBar 48 移出滚动区后，滚动内容固定区 = **140**，恒等：`188 = 140 + 48`。
//      ⇒ 唯一变化项是 TabBar 搬家。**别读成「-26-04 当时算错了」——它算对了，漏的是 R5 之后那一步。**
//
// ★ 三个「余量」必须分开命名，本仓曾长期混用同一个词（E1）：
//     viewport（滚动内容可用高）= 803f − 48
//     maxScrollExtent（溢出量 / 需滚动量）= max(0, content − viewport)   ← **不是余量**
//     行/文字离容器底的余量 = 851 − row.bottom（行口径与文字口径差 14dp）
//   ⇒ 例：0.55 档 n=6 时 maxScroll = 34.35，这是**要滚 34.35**，不是「还剩 34.35」。
//
// ★ 陷阱（高价值，勿删）：旧树（TabBar 在滚动区内）与当前树（TabBar 已移出）
//   在 n=6 时 **maxScroll 都是 34.35** —— 因为 viewport 与 content 各减同一个 48，差值恒等。
//   ⇒ 拿旧树的 34.35 在当前树上一验「对得上」，就会误信旧树整套分解式
//     （viewport 441.65 / 固定区 188dp）没过期。**数字对得上，模型是错的。**
//
// ★ 800×600（Flutter 默认测试视口，**不是手机尺寸**）实测（E1）：
//     容器高 sheet_h    = (600−48)×0.55 + 48 = 351.60
//     滚动内容可用高 viewport = (600−48)×0.55 − 48 = 255.60   （差 96 = 把手 48 + TabBar 48）
//   ⚠️ 早期曾写「扣约 188dp 后只剩 ≈3.4 项」，该数**作废**，它同时犯两错：
//     ① 拿**容器高 351.6** 当**滚动内容可用高**用（应 255.60）
//     ② 扣的 188dp 含分隔线 20 与取消 48（那是「零滚动装项」口径），商却当「首屏可见项数」报
//   ⇒ 原式 (351.6 − 188)/48 = 3.4083 **既不是首屏可见项数，也不是零滚动装项数**。
//   正确两个口径（实测）：
//     首屏可见项数 = (255.60 − 60)/48 = 4.075 ⇒ **4 项**
//     零滚动装项数 = (255.60 − 140)/48 = 2.408 ⇒ **2 项**
//   逐项实测（vp_top = 344.40）：
//     第1 404.40..452.40 (rowOver −147.60, IN)   第2 452.40..500.40 ( −99.60, IN)
//     第3 500.40..548.40 ( −51.60, IN)           第4 548.40..596.40 ( −3.60, IN ← 勉强)
//     第5 596.40..644.40 (+44.40, OUT)           第6 644.40..692.40 (+92.40, OUT)
//     content(n=6) = 428.00 · maxScroll = 428.00 − 255.60 = **172.40**
//   ⇒ 该视口只作阴性质检：第 5 项「查找替换」起确实出界（非恒真）。
//
// ★ 行高恒 48dp 不随字号变（E1，textScaler 1.0/1.3/2.0 三档实测均 48.00，
//   文字高 20/26/40）；文字裁切随字号加重，但无 RenderFlex 溢出。
//
// ★ 既有契约（§4-569 约束 1）：`章节列表/大纲/角色/全文搜索` 四条直点路径
//   全在默认 tab 前 4 项 ⇒ 两处直点测试无需改为滚动。
//
// ★ 依赖方向（单向）：本文件 ──→ `writing_menu_body.dart`，**不反向**。
//   菜单内容渲染（三组构建 / MenuItem / SaveStatusRow / WritingMenuItems）
//   全在 body 文件；本文件只剩入口与可拖拽容器。此边界由门禁 3 守住 ——
//   本批首版曾把组构建留在本文件，实测报循环依赖一圈，已按此方向修正。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../widgets/yue_sheet.dart';
import 'writing_menu_body.dart';

class WritingMenuSheet {
  const WritingMenuSheet._();

  static void show(
    BuildContext context, {
    required DateTime? lastSavedAt,
    required VoidCallback onDiagnose,
    double initialHeight = 0.55,
    ValueChanged<double>? onHeightChanged,
    VoidCallback? onOpenChapterTree,
    VoidCallback? onOpenOutline,
    VoidCallback? onOpenCharacters,
    VoidCallback? onOpenWorlds,
    VoidCallback? onOpenFullTextSearch,
    VoidCallback? onOpenFindReplace,
    VoidCallback? onOpenRecycleBin,
    VoidCallback? onOpenQuickPhrases,
    VoidCallback? onOpenStyleProfile,
    VoidCallback? onOpenWritingStats,
    VoidCallback? onOpenSettings,
    VoidCallback? onOpenVersions,
  }) {
    final initial = initialHeight.clamp(0.30, 0.85);
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _buildSheet(ctx, initial, onHeightChanged, (
        lastSavedAt: lastSavedAt,
        onDiagnose: onDiagnose,
        onOpenChapterTree: onOpenChapterTree,
        onOpenOutline: onOpenOutline,
        onOpenCharacters: onOpenCharacters,
        onOpenWorlds: onOpenWorlds,
        onOpenFullTextSearch: onOpenFullTextSearch,
        onOpenFindReplace: onOpenFindReplace,
        onOpenRecycleBin: onOpenRecycleBin,
        onOpenQuickPhrases: onOpenQuickPhrases,
        onOpenStyleProfile: onOpenStyleProfile,
        onOpenWritingStats: onOpenWritingStats,
        onOpenSettings: onOpenSettings,
        onOpenVersions: onOpenVersions,
      )),
    );
  }

  static Widget _buildSheet(
    BuildContext context,
    double initial,
    ValueChanged<double>? onHeightChanged,
    WritingMenuItems c,
  ) {
    // 拖拽/吸附动画会持续发出 notification——仅当 extent 变化超过阈值才上报，
    // 避免动画中间值反复落库（最后一次上报即最终吸附档位）
    var lastReported = initial;
    return DraggableScrollableSheet(
      initialChildSize: initial,
      minChildSize: 0.30,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.30, 0.55, 0.85],
      expand: false,
      builder: (ctx, scrollController) =>
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              if ((n.extent - lastReported).abs() >= 0.005) {
                lastReported = n.extent;
                onHeightChanged?.call(n.extent);
              }
              return false;
            },
            child: WritingMenuBody(scrollController: scrollController, c: c),
          ),
    );
  }
}
