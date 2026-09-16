// ─────────────────────────────────────────────────────────────
// SettingLibraryTab — 统一「资料」容器（设定资料库第三批）
//
// 收编拆三处的设定入口 → 详情页「资料」Tab 单入口：
//   角色 → CharacterListView（含 AI 抽取确认卡）
//   大纲 → OutlineEntityListView（AI 沉淀实体清单 + pending 确认）
//   世界观 → WorldFactListView（设计时已预留进 Tab 零重构）
//   其他 → 占位（开放容器为第二批：用户自建类别 + 逐条勾选参与诊断）
//
// 无 Scaffold / 无 AppBar：直接嵌入详情页 TabBarView（R4-10 不产生
// 双层标题栏）。子列表用 IndexedStack 保持状态（切换不重载）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../character/character_list_view.dart';
import '../world/world_fact_list_view.dart';
import 'outline_entity_list_view.dart';

/// 四子列表的段标识
enum _Section { character, outline, world, other }

class SettingLibraryTab extends StatefulWidget {
  final String manuscriptId;

  const SettingLibraryTab({super.key, required this.manuscriptId});

  @override
  State<SettingLibraryTab> createState() => _SettingLibraryTabState();
}

class _SettingLibraryTabState extends State<SettingLibraryTab> {
  _Section _section = _Section.character;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.sm,
            AppSpacing.page,
            AppSpacing.xs,
          ),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_Section>(
              segments: const [
                ButtonSegment(value: _Section.character, label: Text('角色')),
                ButtonSegment(value: _Section.outline, label: Text('大纲')),
                ButtonSegment(value: _Section.world, label: Text('世界观')),
                ButtonSegment(value: _Section.other, label: Text('其他')),
              ],
              selected: {_section},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _section = s.first),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _section.index,
            children: [
              CharacterListView(manuscriptId: widget.manuscriptId),
              OutlineEntityListView(manuscriptId: widget.manuscriptId),
              WorldFactListView(manuscriptId: widget.manuscriptId),
              const _OtherSectionPlaceholder(),
            ],
          ),
        ),
      ],
    );
  }
}

/// 「其他」开放容器占位（第二批实现：用户自建类别标签 + 逐条勾选参与诊断）。
class _OtherSectionPlaceholder extends StatelessWidget {
  const _OtherSectionPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          '「其他」开放容器规划中：\n武器 / 规则怪谈等自定义类别，可逐条勾选参与诊断',
          style: AppTextStyles.body,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
