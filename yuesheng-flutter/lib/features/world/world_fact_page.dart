// ─────────────────────────────────────────────────────────────
// WorldFactPage — 世界观设定页（薄壳，批次 W1）
//
// 同构参照 character_page.dart：本文件为**薄壳** —— 只保留 Scaffold + AppBar
// 与生命周期壳；列表主体（搜索 / 排序 / 归档开关 / 列表 / 空态 +
// A1「＋ 新建设定主题」）已抽为可嵌入组件 WorldFactListView（无 Scaffold /
// AppBar）。
//
// 落地路由：AppRoutes.worlds（/worlds），由 app_router.dart 注册。
// 入口：写作页 ⋮ 菜单「世界观」（openWorlds → context.push）。
//
// R4-11 教训（架构 §7-11）：薄壳 setState **不会**重建子 State ⇒ AppBar
// 「＋ 新建」创建成功后必须经 GlobalKey 显式调子列表 refresh()。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import 'world_fact_list_view.dart';

/// 世界观设定页（独立路由 /worlds 落地页）。
class WorldFactPage extends ConsumerStatefulWidget {
  final String manuscriptId;

  /// 作品标题（预留；可空）—— 与 CharacterPage 签名同构。
  final String? manuscriptTitle;

  const WorldFactPage({
    super.key,
    required this.manuscriptId,
    this.manuscriptTitle,
  });

  @override
  ConsumerState<WorldFactPage> createState() => _WorldFactPageState();
}

class _WorldFactPageState extends ConsumerState<WorldFactPage> {
  /// 列表子组件的 State 句柄 —— 供 AppBar「＋ 新建」创建成功后触发刷新。
  final GlobalKey<WorldFactListViewState> _listKey =
      GlobalKey<WorldFactListViewState>();

  /// 列表上报的行数（过滤 + 排序后），用于 AppBar 标题「世界观 (N)」。
  /// 初值 -1 表示列表尚未上报，占位避免显示误导性的 0。
  int _count = -1;

  /// AppBar「＋ 新建」：与列表头按钮共用 showAndCreateWorldTheme（禁止分叉）。
  Future<void> _create() async {
    final ok = await showAndCreateWorldTheme(context, ref, widget.manuscriptId);
    // 创建成功后显式刷新子列表（GlobalKey）—— 薄壳 setState 不重建子 State。
    if (ok) await _listKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: Text(_count >= 0 ? '世界观 ($_count)' : '世界观'),
        actions: [TextButton(onPressed: _create, child: const Text('+ 新建'))],
      ),
      body: WorldFactListView(
        key: _listKey,
        manuscriptId: widget.manuscriptId,
        onCountChanged: (n) {
          if (!mounted || n == _count) return;
          setState(() => _count = n);
        },
      ),
    );
  }
}
