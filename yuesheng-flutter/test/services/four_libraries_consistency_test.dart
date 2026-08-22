// ─────────────────────────────────────────────────────────────
// 四库一致性静态测试 — 批次3（3.2 O4）扩容前置
//
// 症候 / 技法 / 动作 / 训练四库所有 syndrome_id 双向存在；
// 训练库每症候非空；互斥对引用 ID 存在；内容引用 ID 无悬空。
// 为内容层扩容（P023+）提供防漂移基线。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/config/token_budget_table.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';

void main() {
  // 权威症候集合（b9 真源化：由 syndrome_registry 派生，替代 kSyndromeSkillLevels.keys）
  final validSyndromes = kSyndromeIds.toSet();

  // 内容引用白名单（b11 派生化）：活跃 ∪ 退役 ∪ 合并映射旧 ID，全部来自注册表，无硬编码
  final allowedIds = kAllSyndromeIds.toSet().union(
    kSyndromeMergeMap.keys.toSet(),
  );

  group('批次3（3.2）症候库基础', () {
    test('#1 权威集合由注册表派生（活跃共 ${kSyndromeIds.length} 个）', () {
      expect(validSyndromes.length, kSyndromeIds.length);
      // ID 连续递增（按注册表原始顺序检查，退役记录保留原位，ID 永不复用）
      for (int i = 0; i < kSyndromeRegistry.length; i++) {
        expect(
          kSyndromeRegistry[i].id,
          'P${(3 + i).toString().padLeft(3, '0')}',
          reason:
              '症候 ID 应连续递增，第 ${i + 1} 个应为 P${(3 + i).toString().padLeft(3, '0')}',
        );
      }
    });

    test('#2 症候库自洽：索引表/手册有条目，L3 检索非空', () {
      for (final id in validSyndromes) {
        expect(kSyndromeIndexContent, contains('| $id '), reason: '症候索引表缺 $id');
        expect(
          kSyndromeManualContent,
          contains('### $id '),
          reason: '症候手册缺 $id',
        );
        expect(getSyndromeContent([id]), isNotEmpty, reason: 'L3 检索 $id 为空');
      }
    });

    test('#12 症候库表格行由注册表渲染（双向逐字一致，b9 批次28）', () {
      // 正向：注册表（活跃） → 内容（渲染行必须逐字出现在对应库中）
      for (final s in kSyndromeRegistry.where((s) => s.retired != true)) {
        final indexRow = '| ${s.id} | ${s.keyword} | ${s.oneLine} |';
        expect(
          kSyndromeIndexContent,
          contains(indexRow),
          reason: '索引表渲染行缺失 ${s.id}: $indexRow',
        );

        final typeRow =
            '| ${s.type.value} | ${s.id} ${s.v1ActionDisplayName} | ${s.typeLine} |';
        expect(
          kSyndromeManualContent,
          contains(typeRow),
          reason: '类型速查渲染行缺失 ${s.id}: $typeRow',
        );

        final t = s.techniques.first;
        final techRow =
            '| ${s.id} ${s.shortName} | $t ${techniqueNameOf(t) ?? ''} |';
        expect(
          kSyndromeManualContent,
          contains(techRow),
          reason: '技法映射渲染行缺失 ${s.id}: $techRow',
        );
      }

      // 反向：内容 → 注册表（表格行数与注册表一致，防多余/重复行）
      final indexRows = RegExp(
        r'^\| (P\d{3}) \| ',
        multiLine: true,
      ).allMatches(kSyndromeIndexContent).map((m) => m.group(1)!).toList();
      expect(indexRows, kSyndromeIds, reason: '索引表行数与注册表不一致');

      final typeRows = RegExp(
        r'^\| [a-z_]+ \| (P\d{3}) ',
        multiLine: true,
      ).allMatches(kSyndromeManualContent).map((m) => m.group(1)!).toList();
      expect(
        typeRows.length,
        kSyndromeRegistry.length,
        reason: '类型速查表行数与注册表不一致',
      );

      final techRows = RegExp(
        r'^\| (P\d{3}) [^|]+ \| T\d{3} ',
        multiLine: true,
      ).allMatches(kSyndromeManualContent).map((m) => m.group(1)!).toList();
      expect(techRows, kSyndromeIds, reason: '技法映射表行数与注册表不一致');

      // 技法库 L2 症候→技法映射表（b9 批次29）
      for (final s in kSyndromeRegistry.where((s) => s.retired != true)) {
        final t = s.techniques.first;
        expect(
          kTechniqueIndexContent,
          contains('| ${s.id} | $t ${techniqueNameOf(t) ?? ''}'),
          reason: 'L2 技法映射表渲染行缺失 ${s.id}',
        );
      }
      final l2Rows = RegExp(
        r'^\| (P\d{3}) \| T\d{3} ',
        multiLine: true,
      ).allMatches(kTechniqueIndexContent).map((m) => m.group(1)!).toList();
      expect(l2Rows, kSyndromeIds, reason: 'L2 技法映射表行数与注册表不一致');

      // 注册表动作映射 / maxAttempts / training-templates-index（b9 批次30）
      final v2Content = getSkill('coaching-actions-v2')?.content ?? '';
      final templatesIndex =
          getSkill('training-templates-index')?.content ?? '';
      expect(v2Content, isNotEmpty);
      expect(templatesIndex, isNotEmpty);
      for (final s in kSyndromeRegistry.where((s) => s.retired != true)) {
        expect(
          v2Content,
          contains(
            '| ${s.id} ${s.v2ActionDisplayName} | ${s.actions.first} ${actionNameOf(s.actions.first) ?? ''}',
          ),
          reason: 'v2 动作映射渲染行缺失 ${s.id}',
        );
        final tName = s.id == 'P022' ? '重复用词/基础语病症' : s.shortName;
        expect(
          templatesIndex,
          contains('| ${s.id} | $tName | ${s.trainingLine} |'),
          reason: 'training-templates-index 渲染行缺失 ${s.id}',
        );
      }
      final loopV2 = getSkill('training-loop-v2')?.content ?? '';
      for (final g in MaxAttemptsGroup.values) {
        final ids = kSyndromeRegistry
            .where((s) => s.group == g && s.retired != true)
            .map((s) => s.id)
            .join('/');
        expect(
          loopV2,
          contains('（$ids）'),
          reason: 'maxAttempts ${g.label} 组缺失 $ids',
        );
      }
      final v2Rows = RegExp(
        r'^\| (P\d{3}) ',
        multiLine: true,
      ).allMatches(v2Content).map((m) => m.group(1)!).toList();
      expect(v2Rows, kSyndromeIds, reason: 'v2 动作映射行数与注册表不一致');
      final tIndexRows = RegExp(
        r'^\| (P\d{3}) \| ',
        multiLine: true,
      ).allMatches(templatesIndex).map((m) => m.group(1)!).toList();
      expect(
        tIndexRows,
        kSyndromeIds,
        reason: 'training-templates-index 行数与注册表不一致',
      );
    });
  });

  group('批次3（3.2）训练库一致性', () {
    test('#3 训练库每症候非空（活跃 ${kSyndromeIds.length}）', () {
      for (final id in validSyndromes) {
        expect(
          kTrainingFullKnowledge,
          contains('## $id '),
          reason: '训练知识缺 $id',
        );
        expect(getTrainingContent([id]), isNotEmpty, reason: '训练检索 $id 为空');
      }
    });
  });

  group('批次3（3.2）技法库双向存在', () {
    test('#4 映射键均为合法症候，技法 ID 在技法库有完整条目', () {
      for (final entry in kTechniquesBySyndrome.entries) {
        expect(
          validSyndromes.contains(entry.key),
          true,
          reason: '技法映射引用非法症候 ${entry.key}',
        );
        expect(entry.value, isNotEmpty, reason: '${entry.key} 无推荐技法');
        for (final t in entry.value) {
          expect(
            kTechniqueLibraryContent,
            contains('### $t '),
            reason: '技法 $t 在技法库无完整条目',
          );
        }
      }
    });

    test('#5 技法库覆盖全部 ${kSyndromeRegistry.length} 症候（双向存在）', () {
      for (final id in validSyndromes) {
        expect(
          kTechniquesBySyndrome.containsKey(id),
          true,
          reason: '症候 $id 在技法映射中缺失',
        );
      }
    });

    test('#6 技法索引表引用的技法 ID 在完整库存在', () {
      final indexTechniques = RegExp(
        r'\| T(\d{3}) ',
      ).allMatches(kTechniqueIndexContent).map((m) => 'T${m.group(1)}').toSet();
      expect(indexTechniques, isNotEmpty);
      for (final t in indexTechniques) {
        expect(
          kTechniqueLibraryContent,
          contains('### $t '),
          reason: '索引表技法 $t 无完整条目',
        );
      }
    });

    test('#7 技法库无孤儿技法：每个定义技法至少被一个症候引用（B7 回归）', () {
      final definedTech = RegExp(
        r'### (T\d{3})',
      ).allMatches(kTechniqueLibraryContent).map((m) => m.group(1)!).toSet();
      expect(definedTech, isNotEmpty, reason: '技法库未解析到任何技法 ID');
      final referenced = <String>{
        for (final s in kSyndromeRegistry) ...s.techniques,
      };
      for (final t in definedTech) {
        expect(
          referenced.contains(t),
          true,
          reason: '孤儿技法 $t 未被任何症候 techniques 引用（B7 回归）',
        );
      }
    });
  });

  group('批次3（3.2）动作库一致性', () {
    test('#7 动作映射表首列症候合法，动作编号均有条目', () {
      for (final skillId in ['coaching-actions-v2']) {
        final content = getSkill(skillId)?.content ?? '';
        expect(content, isNotEmpty, reason: '$skillId skill 缺失');

        // 映射表首列症候 ID
        final syndromeRefs = RegExp(
          r'^\| (P\d{3}) ',
          multiLine: true,
        ).allMatches(content).map((m) => m.group(1)!).toSet();
        expect(syndromeRefs, isNotEmpty, reason: '$skillId 无症候映射表');
        for (final id in syndromeRefs) {
          expect(
            allowedIds.contains(id),
            true,
            reason: '$skillId 映射表引用非法/退役症候 $id',
          );
        }

        // 动作编号条目标题均存在
        final actionIds = RegExp(
          r'^### (A\d{3}) ',
          multiLine: true,
        ).allMatches(content).map((m) => m.group(1)!).toSet();
        expect(actionIds, isNotEmpty, reason: '$skillId 无动作条目');

        // 映射表中引用的动作编号均有条目（防悬空引用）
        final actionRefs = RegExp(
          r'\bA\d{3}\b',
        ).allMatches(content).map((m) => m.group(0)!).toSet();
        for (final a in actionRefs) {
          expect(actionIds.contains(a), true, reason: '$skillId 引用未定义动作 $a');
        }
      }
    });
  });

  group('批次3（3.2）互斥对与内容引用', () {
    test('#8 互斥对引用 ID 存在（P006/P021、P015/P012、P009/P018）', () {
      const pairs = [
        ('P006', 'P021'), // 互斥校验（先排除对方）
        ('P015', 'P012'), // 铺垫质量前置（无代价预期优先判 P012）
        ('P009', 'P018'), // 触发信号差异化
        ('P028', 'P003'), // 画面感缺失优先于情绪标签（先建画面再谈情绪词，批次23）
        ('P029', 'P006'), // 段落长且无推进时，停滞是根因（先修 P006，批次24）
        ('P030', 'P006'), // 节奏比例失衡优先于停滞（比例是根因，批次25）
        ('P031', 'P018'), // 角色可信度先于世界观可信度（先修角色，批次26）
        ('P032', 'P012'), // 金手指过强是冲突失效的根因（P032 优先，批次32）
        ('P033', 'P030'), // 宏观段落比例先于升级节奏（P030 优先，批次33）
        ('P034', 'P009'), // 核心角色动机先于配角群像（P009 优先，批次34）
        ('P035', 'P011'), // 表现力是对话质量基础，先修 P011（P011 优先，批次40）
        ('P036', 'P006'), // 无推进（停滞）是更根本的问题，先修 P006（P006 优先，批次41）
        ('P036', 'P021'), // 概括导致信息丢失更严重，先修 P021（P021 优先，批次41）
        ('P039', 'P040'), // 同族互斥——目标立住后主动性自然提升，先修 P039（P039 优先，批次46）
        ('P040', 'P016'), // 先修可见的因果链，再挖角色动机（P016 优先，批次46）
        ('P041', 'P012'), // 对手利益到位，张力自然恢复（P041 优先，批次47）
      ];
      for (final (a, b) in pairs) {
        expect(validSyndromes.contains(a), true, reason: '互斥对引用非法症候 $a');
        expect(validSyndromes.contains(b), true, reason: '互斥对引用非法症候 $b');
      }

      // 互斥关系在症候手册中有据可查（防内容漂移）
      final manual = kSyndromeManualContent;
      expect(manual, contains('排除 P021'), reason: 'P006 互斥校验（排除 P021）缺失');
      expect(manual, contains('排除 P006'), reason: 'P021 互斥校验（排除 P006）缺失');
      expect(manual, contains('P012 张力不足'), reason: 'P015 铺垫质量前置（P012）缺失');
      expect(manual, contains('区分 P018'), reason: 'P009/P018 触发信号差异化缺失');
      expect(manual, contains('P028 优先'), reason: 'P028/P003 重叠优先级（P028 优先）缺失');
      expect(manual, contains('P006 优先'), reason: 'P029/P006 重叠优先级（P006 优先）缺失');
      expect(manual, contains('P030 优先'), reason: 'P030/P006 重叠优先级（P030 优先）缺失');
      expect(
        manual,
        contains('P031 设定矛盾 vs P018 人设崩塌'),
        reason: 'P031/P018 重叠优先级（P018 优先）缺失',
      );
      expect(
        manual,
        contains('P032 金手指失衡 vs P012 张力不足'),
        reason: 'P032/P012 重叠优先级（P032 优先）缺失',
      );
      expect(
        manual,
        contains('P033 升级节奏失衡 vs P030 节奏比例失衡'),
        reason: 'P033/P030 重叠优先级（P030 优先）缺失',
      );
      expect(
        manual,
        contains('P034 配角工具人 vs P009 角色空心化'),
        reason: 'P034/P009 重叠优先级（P009 优先）缺失',
      );
      expect(
        manual,
        contains('P035 对话注水 vs P011 对话疲劳'),
        reason: 'P035/P011 重叠优先级（P011 优先）缺失',
      );
      expect(
        manual,
        contains('P036 流水账叙述 vs P006 节奏停滞'),
        reason: 'P036/P006 重叠优先级（P006 优先）缺失',
      );
      expect(
        manual,
        contains('P036 流水账叙述 vs P021 跳跃叙事'),
        reason: 'P036/P021 重叠优先级（P021 优先）缺失',
      );
      expect(
        manual,
        contains('P039 目标模糊 vs P040 被动主角'),
        reason: 'P039/P040 重叠优先级（P039 优先）缺失',
      );
      expect(
        manual,
        contains('P040 被动主角 vs P016 情节巧合过多'),
        reason: 'P040/P016 重叠优先级（P016 优先）缺失',
      );
      expect(
        manual,
        contains('P041 降智反派 vs P012 张力不足'),
        reason: 'P041/P012 重叠优先级（P041 优先）缺失',
      );
    });

    test('#8b 重叠优先级表覆盖 P022/P023/P024/P026（B9 补充）', () {
      final manual = kSyndromeManualContent;
      expect(
        manual,
        contains('P022 重复用词/基础语病 vs P008 语言堆砌'),
        reason: 'P022/P008 重叠优先级缺失',
      );
      expect(
        manual,
        contains('P023 爽点乏力 vs P012 张力不足'),
        reason: 'P023/P012 重叠优先级缺失',
      );
      expect(
        manual,
        contains('P024 期待感断裂 vs P026 章节钩子缺失'),
        reason: 'P024/P026 重叠优先级缺失',
      );
      expect(
        manual,
        contains('P026 章节钩子缺失 vs P014 结尾乏力'),
        reason: 'P026/P014 重叠优先级缺失',
      );
    });

    test('#10 动作↔症候双向一致：coaching-actions-v2 手写「适用」对齐注册表真源（B6）', () {
      final content = getSkill('coaching-actions-v2')?.content ?? '';
      // v2 用「**适用**：<症候名>」格式；症候名 = shortName 去掉尾字「症」
      final nameToId = <String, String>{};
      for (final s in kSyndromeRegistry.where((s) => s.retired != true)) {
        for (final key in [
          s.shortName,
          s.shortName.replaceAll(RegExp(r'症$'), ''),
          s.name,
          s.name.replaceAll(RegExp(r'症$'), ''),
          if (s.v2ActionName != null) s.v2ActionName!,
          if (s.v2ActionName != null)
            s.v2ActionName!.replaceAll(RegExp(r'症$'), ''),
        ]) {
          nameToId[key] = s.id;
        }
      }
      final re = RegExp(r'### (A0\d\d)[\s\S]*?\*\*适用\*\*：([^\n]*)');
      final matches = re.allMatches(content);
      final expected = <String, Set<String>>{};
      for (final s in kSyndromeRegistry.where((s) => s.retired != true)) {
        for (final a in s.actions) {
          expected.putIfAbsent(a, () => <String>{}).add(s.id);
        }
      }
      final mismatches = <String>[];
      for (final m in matches) {
        final actionId = m.group(1)!;
        final line = m.group(2)!;
        final ids = line
            .split(RegExp(r'[、,，]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .map((n) => nameToId[n])
            .whereType<String>()
            .toSet();
        final exp = expected[actionId] ?? const <String>{};
        // 注意：Dart Set.== 是引用相等，必须用对称差判断集合内容相等
        final equal =
            ids.difference(exp).isEmpty && exp.difference(ids).isEmpty;
        if (!equal) {
          mismatches.add('$actionId  解析=$ids  期望=$exp  行文本=「$line」');
        }
      }
      expect(
        mismatches,
        isEmpty,
        reason: 'coaching-actions-v2 适用症候与注册表不一致:\n${mismatches.join('\n')}',
      );
      expect(
        matches.length,
        greaterThanOrEqualTo(expected.length),
        reason:
            'coaching-actions-v2 动作覆盖数(${matches.length}) < 注册表动作数(${expected.length})',
      );
    });

    test('#9 内容引用漂移：全库出现的症候 ID 均合法（防 P023+ 悬空引用）', () {
      final allContent = [
        kSyndromeIndexContent,
        kSyndromeManualContent,
        kTechniqueIndexContent,
        kTechniqueLibraryContent,
        getSkill('coaching-actions-v2')?.content ?? '',
        getSkill('coaching-actions-v2')?.content ?? '',
        kTrainingFullKnowledge,
      ].join('\n');

      final foundIds = RegExp(
        r'\bP0(0\d|1\d|2\d|3\d|4\d)\b',
      ).allMatches(allContent).map((m) => m.group(0)!).toSet();
      final illegal = foundIds.difference(allowedIds);
      expect(illegal, isEmpty, reason: '内容引用非法/悬空症候 ID: $illegal');
    });
  });

  group('批次3（3.1）token 预算静态表', () {
    test('#10 最坏情形合计超模型上下文（需降级），warning 线也超', () {
      final total = TokenBudgetTable.worstCaseTotal;
      final warning = (TokenEstimate.maxBudget * TokenEstimate.warningRatio)
          .round();
      expect(
        total,
        greaterThan(warning),
        reason: '最坏情形 $total 应超过 warning 线 $warning（说明必须启用降级）',
      );
      expect(
        total,
        greaterThan(TokenEstimate.maxBudget),
        reason: '最坏情形 $total 应超过 maxBudget ${TokenEstimate.maxBudget}',
      );
    });

    test('#11 溢出降级顺序：L2 组 → L3 非 focus → 检测器 → … → 历史最后', () {
      final order = TokenBudgetTable.planDegradation()
          .map((s) => s.name)
          .toList();
      expect(order.length, 8);
      expect(order[0], contains('L2 按需组'), reason: '最先裁 L2 组数');
      expect(order[1], contains('L3 结构化'), reason: '其次裁 L3 非 focus 概览');
      expect(order[2], contains('规则观察检测器'), reason: '再次裁检测器注入');
      expect(order.last, contains('历史消息'), reason: '历史消息最后裁（保底前的最后手段）');
    });

    test('#12 临场输出约束与协议块为保底层（永不裁）', () {
      final bottom = TokenBudgetTable.bottomLineStages;
      expect(
        bottom.any((s) => s.contains('临场输出约束')),
        true,
        reason: '临场输出约束必须保底',
      );
      expect(
        bottom.any((s) => s.contains('[YS_ENTITY]')),
        true,
        reason: '协议块说明必须保底（不注入 AI 就不输出）',
      );
      expect(
        bottom.any((s) => s.contains('L1 核心 skill')),
        true,
        reason: 'L1 核心 skill 必须保底',
      );
    });
  });
}
