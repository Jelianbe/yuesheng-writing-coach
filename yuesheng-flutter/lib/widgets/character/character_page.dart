// ─────────────────────────────────────────────────────────────
// CharacterPage — 角色列表页（C78 批次3，FR-1/FR-7/FR-10）
//
// 入口：写作页 AppBar ⋮ 菜单（ADR-C78 §3.0，独立路由页非 Sheet）；
// 对话页 FR-10 提示卡经 go_router 携 sinceTimestamp 深链（最近批次过滤视图）。
//
// 架构（R-019 真分解）：本文件为**薄壳** —— 只保留 Scaffold + AppBar
// 与生命周期壳，列表主体（搜索 / 排序 / 列表 / 空态 + A1「＋ 新建角色」）
// 已抽为可嵌入组件 CharacterListView（无 Scaffold / AppBar），供：
//   - 本页 body（独立路由 /characters 落地页，架构 §3.3.4 链路①）
//   - 作品详情页 Tab1「角色」内嵌（架构 §2.1）
//
// ⚠️ 公开构造器签名（manuscriptId / manuscriptTitle / sinceTimestamp）
// 必须原样保留 —— character_page_test.dart:71 直接构造本页，
// app_router.dart:217 与 writing_page_menu_actions.dart:75 亦依赖该签名
// （架构 §3.3.3 关键约束 1）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import 'character_list_view.dart';

/// 角色列表页（独立路由 /characters 落地页）。
class CharacterPage extends ConsumerStatefulWidget {
  final String manuscriptId;

  /// 作品标题（AppBar 副标；可空）
  final String? manuscriptTitle;

  /// FR-10：最近批次过滤起点（unix 秒）。null = 全部。
  final int? sinceTimestamp;

  const CharacterPage({
    super.key,
    required this.manuscriptId,
    this.manuscriptTitle,
    this.sinceTimestamp,
  });

  @override
  ConsumerState<CharacterPage> createState() => _CharacterPageState();
}

class _CharacterPageState extends ConsumerState<CharacterPage> {
  /// 列表子组件的 State 句柄 —— 供 AppBar「+ 新建」创建成功后触发刷新。
  final GlobalKey<CharacterListViewState> _listKey =
      GlobalKey<CharacterListViewState>();

  /// 列表上报的行数（过滤 + 排序后），用于 AppBar 标题「角色 (N)」。
  /// 初值 -1 表示列表尚未上报，占位避免显示误导性的 0。
  int _count = -1;

  /// AppBar「+ 新建」（A1）：与列表头按钮共用 showAndCreateCharacter。
  Future<void> _create() async {
    final ok = await showAndCreateCharacter(context, ref, widget.manuscriptId);
    // 创建成功后显式刷新子列表（GlobalKey）—— 薄壳 setState 不会重建子 State。
    if (ok) await _listKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: Text(_count >= 0 ? '角色 ($_count)' : '角色'),
        actions: [
          // ⚠️ 不得删除：character_page_test.dart:251 依赖 find.text('+ 新建')。
          TextButton(onPressed: _create, child: const Text('+ 新建')),
        ],
      ),
      body: CharacterListView(
        key: _listKey,
        manuscriptId: widget.manuscriptId,
        sinceTimestamp: widget.sinceTimestamp,
        onCountChanged: (n) {
          if (!mounted || n == _count) return;
          setState(() => _count = n);
        },
      ),
    );
  }
}
