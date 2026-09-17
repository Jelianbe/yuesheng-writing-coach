// setting_tag_overview_test — 全稿标签聚合纯逻辑测试（标签批次后续）
//
//   1. 跨实体聚合：同一标签跨角色/世界观/其他分组
//   2. 标签按字典序；组内按类型（角色→世界观→其他）再按名称排序
//   3. 名称映射缺失（目标已删）跳过
//   4. 空输入 → 空列表
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/services/setting_tag_overview.dart';

void main() {
  SettingTag tag({
    required String kind,
    required String entityId,
    required String tag,
  }) => SettingTag(
    id: '$kind-$entityId-$tag',
    manuscriptId: 'm1',
    entityKind: kind,
    entityId: entityId,
    tag: tag,
    createdAt: 0,
  );

  test('#1 跨实体聚合：同一标签跨三类实体分组', () {
    final groups = buildTagGroups(
      tags: [
        tag(kind: 'character', entityId: 'c1', tag: '主角团'),
        tag(kind: 'world', entityId: 'w1', tag: '主角团'),
        tag(kind: 'setting', entityId: 's1', tag: '主角团'),
      ],
      characterNames: {'c1': '林晚'},
      worldNames: {'w1': '雾都'},
      settingNames: {'s1': '血月刃'},
    );
    expect(groups.length, 1);
    expect(groups.single.tag, '主角团');
    expect(groups.single.items.length, 3);
    // 类型序：角色 → 世界观 → 其他
    expect(groups.single.items.map((i) => i.name).toList(), [
      '林晚',
      '雾都',
      '血月刃',
    ]);
  });

  test('#2 标签字典序 + 组内按名称排序', () {
    final groups = buildTagGroups(
      tags: [
        tag(kind: 'world', entityId: 'w2', tag: '悬疑'),
        tag(kind: 'world', entityId: 'w1', tag: '雾都'),
        tag(kind: 'character', entityId: 'c1', tag: '雾都'),
      ],
      characterNames: {'c1': '林晚'},
      worldNames: {'w1': '雾都', 'w2': '怪谈'},
      settingNames: const {},
    );
    expect([for (final g in groups) g.tag], ['悬疑', '雾都']);
    // 「悬疑」组只有 world「怪谈」
    expect(groups[0].items.map((i) => i.name).toList(), ['怪谈']);
    // 「雾都」组：角色（index 0）先于世界观（index 1）
    expect(groups[1].items.map((i) => i.name).toList(), ['林晚', '雾都']);
  });

  test('#3 名称映射缺失（目标已删）跳过', () {
    final groups = buildTagGroups(
      tags: [
        tag(kind: 'character', entityId: 'gone', tag: '孤儿标签'),
        tag(kind: 'character', entityId: 'c1', tag: '主角团'),
      ],
      characterNames: {'c1': '林晚'},
      worldNames: const {},
      settingNames: const {},
    );
    expect(groups.length, 1);
    expect(groups.single.tag, '主角团');
  });

  test('#4 空输入 → 空列表', () {
    expect(
      buildTagGroups(
        tags: const [],
        characterNames: const {},
        worldNames: const {},
        settingNames: const {},
      ),
      isEmpty,
    );
  });
}
