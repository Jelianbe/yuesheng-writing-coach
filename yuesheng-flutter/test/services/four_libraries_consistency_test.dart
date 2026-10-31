// ─────────────────────────────────────────────────────────────
// 四库一致性静态测试 — 批次3（3.2 O4）扩容前置
//
// 症候 / 技法 / 动作 / 训练四库所有 syndrome_id 双向存在；
// 训练库每症候非空；互斥对引用 ID 存在；内容引用 ID 无悬空。
// 为内容层扩容（P013+）提供防漂移基线。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/config/token_budget_table.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/chunk_prompt.dart';
import 'package:writingcoach/services/conflict_detector.dart';
import 'package:writingcoach/services/dialogue_tag_detector.dart';
import 'package:writingcoach/services/event_causality_detector.dart';
import 'package:writingcoach/services/grammar_lexical_detector.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/services/subplot_closure_detector.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/syndrome_retirement.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  // 权威症候集合（b9 真源化：由 syndrome_registry 派生，替代 kSyndromeSkillLevels.keys）
  final validSyndromes = kSyndromeIds.toSet();

  // 内容引用白名单（b11 派生化）：活跃 ∪ 退役 ∪ 合并映射旧 ID，全部来自注册表，无硬编码
  //
  // ⚠️ 退役部分用 `kRetiredSyndromeIds`（**全量 50 条**，含 recycled），不能只并
  // `kSyndromeMergeMap`（47 条）。两者差的 P035/P036/P037 是 ADR-0003 阶段一
  // 待复用的槽位：已从读路径 merge map 清掉，但**仍是合法 legacy 编号**
  // （归一职责已移交 v46 迁移平铺表）。
  //   只并 merge map 键 ⇒ 这三个 ID 在知识库里的历史提及会被判成「悬空引用」
  //   —— 实测 `syndrome_kb_content_manual_2.dart:15` 与
  //   `training_few_shot_library.dart:101` 均有提及（前者是消歧裁决失效说明，
  //   后者是「原 P035 已并入本症候」的教学澄清）⇒ `#9` 恒红。
  //   ⇒ 豁免集合的真源必须是「**所有仍可被归一的合法编号**」。
  // 真源 = lib/services/syndrome_retirement.dart（退役档案）派生。
  final allowedIds = kSyndromeIds.toSet().union(kRetiredSyndromeIds);

  group('批次3（3.2）症候库基础', () {
    test('#1 权威集合由注册表派生（活跃共 ${kSyndromeIds.length} 个）', () {
      expect(validSyndromes.length, kSyndromeIds.length);
      // ID 连续递增（P001 起逐号递增，ID 永不复用）
      for (int i = 0; i < kSyndromeRegistry.length; i++) {
        expect(
          kSyndromeRegistry[i].id,
          'P${(1 + i).toString().padLeft(3, '0')}',
          reason:
              '症候 ID 应连续递增，第 ${i + 1} 个应为 P${(1 + i).toString().padLeft(3, '0')}',
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
      for (final s in kSyndromeRegistry) {
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
      // 0.3.6+9 聚类去重后：类型速查表只渲染活跃症候（退役记录定义保留但不进渲染）
      expect(typeRows.length, kSyndromeIds.length, reason: '类型速查表行数与活跃注册表不一致');

      final techRows = RegExp(
        r'^\| (P\d{3}) [^|]+ \| T\d{3} ',
        multiLine: true,
      ).allMatches(kSyndromeManualContent).map((m) => m.group(1)!).toList();
      expect(techRows, kSyndromeIds, reason: '技法映射表行数与注册表不一致');

      // 技法库 L2 症候→技法映射表（b9 批次29）
      for (final s in kSyndromeRegistry) {
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
      for (final s in kSyndromeRegistry) {
        expect(
          v2Content,
          contains(
            '| ${s.id} ${s.v2ActionDisplayName} | ${s.actions.first} ${actionNameOf(s.actions.first) ?? ''}',
          ),
          reason: 'v2 动作映射渲染行缺失 ${s.id}',
        );
        // R-027：P018 不再特地带"症"，索引行一律取 registry shortName
        // （真源名「重复用词/基础语病」）。
        final tName = s.shortName;
        expect(
          templatesIndex,
          contains('| ${s.id} | $tName | ${s.trainingLine} |'),
          reason: 'training-templates-index 渲染行缺失 ${s.id}',
        );
      }
      final loopV2 = getSkill('training-loop-v2')?.content ?? '';
      for (final g in MaxAttemptsGroup.values) {
        final ids = kSyndromeRegistry
            .where((s) => s.group == g)
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

    test('#17 件③：九条首选动作逐条落在批准序首位（不用集合断言）', () {
      // 同集合换序 ⇒ 集合断言恒绿，所以这里**逐条字面**钉 `actions.first`
      // （报批稿 §6.1 N6 与坑 1：判据的自述不能强于鉴别力）。
      const preferred = <String, String>{
        'P006': 'A011',
        'P010': 'A003',
        'P012': 'A012',
        'P016': 'A006',
        'P017': 'A005',
        'P020': 'A012',
        'P028': 'A007',
        'P033': 'A003',
        'P037': 'A013',
      };
      final bad = <String>[];
      for (final e in preferred.entries) {
        final rec = kSyndromeRegistry.firstWhere((s) => s.id == e.key);
        if (rec.actions.first != e.value) {
          bad.add(
            '${e.key} 现首位=${rec.actions.first} 期望=${e.value} '
            '全序=${rec.actions.join(',')}',
          );
        }
      }
      expect(bad, isEmpty, reason: '注册表首选动作与批准序不一致:\n${bad.join('\n')}');
    });

    test('#18 件④甲：P036 首选改 A006 且保留 A002 备选', () {
      final p036 = kSyndromeRegistry.firstWhere((s) => s.id == 'P036');
      expect(p036.actions.first, 'A006', reason: '手册首选是 A006，系统侧须一致');
      // A002 备选只存在于注册表侧 —— manual_6.dart:500 的 P036 原文是「首选 A006
      // 感官全开 + A005 动作链」，手册无 A002。本判据只钉注册表首位，不得读成手册也这么说。
      expect(
        p036.actions,
        contains('A002'),
        reason: '甲案保留 A002 作学员退路（乙案删它 = 超范围减法，本批不采）',
      );
      expect(p036.actions, contains('A005'));
    });

    test('#19 手册首选 == 注册表 actions.first（N-Guard · 白名单取空集）', () {
      // 按 ID 抽段比对 —— **直接用 L3 注入面的真源函数** `getSyndromeContent`
      // （不自建段界：自建会在 `### ` / `## ` 边界上与运行期分家，见 §2.9 抽段口径）。
      // 分歧此前只能靠人工脚本发现（报批稿 E1-9）⇒ 本护栏把它变成机器牙。
      // 白名单 = L3 抽段内确实没有「推荐教学动作」行的 ID。
      // ⚠️ 施工实测（2026-10-31）：稿 E1-9 记「P013 手册段无该行」，但按**运行期真源**
      //   `getSyndromeContent(['P013'])` 抽段，该行**在场**且首选 A007 == 注册表首位
      //   ⇒ 白名单取**空集**（P013 不入白名单）。若将来某条真的缺行，此处加成员并在台账归因。
      const noPreferredLineWhitelist = <String>{};
      final preferredRe = RegExp(r'\*\*推荐教学动作\*\*：首选 (A\d{3})');
      final bad = <String>[];
      for (final s in kSyndromeRegistry) {
        final sec = getSyndromeContent([s.id]);
        final all = sec.isEmpty
            ? <RegExpMatch>[]
            : preferredRe.allMatches(sec).toList();
        if (all.isEmpty) {
          if (!noPreferredLineWhitelist.contains(s.id)) {
            bad.add('${s.id} 手册段缺「首选 Axxx」行且不在白名单');
          }
          continue;
        }
        if (noPreferredLineWhitelist.contains(s.id)) {
          bad.add('${s.id} 已在白名单但手册行回来了 ⇒ 白名单陈旧，须删该成员');
          continue;
        }
        final vals = all.map((m) => m.group(1)!).toSet();
        if (vals.length > 1) {
          bad.add(
            '${s.id} 手册段 ${all.length} 条首选行取值不一致(${vals.join('/')}) ⇒ 先定谁权威',
          );
          continue;
        }
        if (vals.single != s.actions.first) {
          bad.add('${s.id} 手册首选=${vals.single} 注册表首位=${s.actions.first} ⇒ 分歧');
        }
      }
      expect(bad, isEmpty, reason: '手册/注册表首选不一致:\n${bad.join('\n')}');
    });
  });

  group('批次3（3.2）互斥对与内容引用', () {
    test('#8 互斥对引用 ID 存在（P004/P017、P013/P010、P007/P015）', () {
      const pairs = [
        ('P004', 'P017'), // 互斥校验（先排除对方）
        ('P013', 'P010'), // 铺垫质量前置（无代价预期优先判 P010）
        ('P007', 'P015'), // 触发信号差异化
        ('P021', 'P001'), // 画面感缺失优先于情绪标签（先建画面再谈情绪词，批次23）
        ('P022', 'P004'), // 节奏比例失衡优先于停滞（比例是根因，批次25）
        ('P023', 'P015'), // 角色可信度先于世界观可信度（先修角色，批次26）
        ('P024', 'P010'), // 金手指过强是冲突失效的根因（P024 优先，批次32）
        ('P025', 'P007'), // 核心角色动机先于配角群像（P007 优先，批次34）
        ('P028', 'P014'), // 先修可见的因果链，再挖角色动机（P014 优先，批次46）
        ('P029', 'P010'), // 对手利益到位，张力自然恢复（P029 优先，批次47）
      ];
      for (final (a, b) in pairs) {
        expect(validSyndromes.contains(a), true, reason: '互斥对引用非法症候 $a');
        expect(validSyndromes.contains(b), true, reason: '互斥对引用非法症候 $b');
      }

      // 互斥关系在症候手册中有据可查（防内容漂移）
      final manual = kSyndromeManualContent;
      expect(manual, contains('排除 P017'), reason: 'P004 互斥校验（排除 P017）缺失');
      expect(manual, contains('排除 P004'), reason: 'P017 互斥校验（排除 P004）缺失');
      expect(manual, contains('P010 张力不足'), reason: 'P013 铺垫质量前置（P010）缺失');
      expect(manual, contains('区分 P015'), reason: 'P007/P015 触发信号差异化缺失');
      expect(manual, contains('P021 优先'), reason: 'P021/P001 重叠优先级（P021 优先）缺失');
      expect(manual, contains('P004 优先'), reason: 'P005/P004 重叠优先级（P004 优先）缺失');
      expect(manual, contains('P022 优先'), reason: 'P022/P004 重叠优先级（P022 优先）缺失');
      expect(
        manual,
        contains('P023 设定矛盾 vs P015 人设崩塌'),
        reason: 'P023/P015 重叠优先级（P015 优先）缺失',
      );
      expect(
        manual,
        contains('P024 金手指失衡 vs P010 张力不足'),
        reason: 'P024/P010 重叠优先级（P024 优先）缺失',
      );
      expect(
        manual,
        contains('P024 金手指失衡 vs P022 节奏比例失衡'),
        reason: 'P024/P022 重叠优先级（P022 优先）缺失',
      );
      expect(
        manual,
        contains('P025 配角工具人 vs P007 角色空心化'),
        reason: 'P025/P007 重叠优先级（P007 优先）缺失',
      );
      expect(
        manual,
        contains('P004 节奏停滞 vs P017 跳跃叙事'),
        reason: 'P004/P017 重叠优先级（P017 优先）缺失',
      );
      expect(
        manual,
        contains('P007 角色空心化 vs P028 被动主角'),
        reason: 'P007/P028 重叠优先级（P007 优先）缺失',
      );
      expect(
        manual,
        contains('P028 被动主角 vs P014 情节巧合过多'),
        reason: 'P028/P014 重叠优先级（P014 优先）缺失',
      );
      expect(
        manual,
        contains('P029 降智反派 vs P010 张力不足'),
        reason: 'P029/P010 重叠优先级（P029 优先）缺失',
      );
    });

    test('#8b 重叠优先级表覆盖 P018/P013/P019（B9 补充）', () {
      final manual = kSyndromeManualContent;
      expect(
        manual,
        contains('P018 重复用词/基础语病 vs P006 语言堆砌'),
        reason: 'P018/P006 重叠优先级缺失',
      );
      expect(
        manual,
        contains('P013 高潮疲软 vs P010 张力不足'),
        reason: 'P013/P010 重叠优先级缺失',
      );
      expect(
        manual,
        contains('P019 章节钩子缺失 vs P012 结尾乏力'),
        reason: 'P019/P012 重叠优先级缺失',
      );
    });

    test('#10 动作↔症候双向一致：coaching-actions-v2 手写「适用」对齐注册表真源（B6）', () {
      final content = getSkill('coaching-actions-v2')?.content ?? '';
      // v2 用「**适用**：<症候名>」格式；症候名 = shortName 去掉尾字「症」
      final nameToId = <String, String>{};
      for (final s in kSyndromeRegistry) {
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
      for (final s in kSyndromeRegistry) {
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

    test('#9 内容引用漂移：全库出现的症候 ID 均合法（防 P013+ 悬空引用）', () {
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

  group('重编号残留护栏（0.3.6 症候去重重编号回归）', () {
    // 全库生效内容（注入路径上的常量，不含文件头注释）
    final allKb = [
      kSyndromeIndexContent,
      kSyndromeManualContent,
      kTechniqueIndexContent,
      kTechniqueLibraryContent,
      kTrainingFullKnowledge,
      kTrainingFewShotLibrary.values.join('\n'),
      getSkill('coaching-actions-v2')?.content ?? '',
    ].join('\n');

    // ───────────────────────────────────────────────────────────
    // ★ T-20261031-14：本判据的抽取式**不得**以「症」结尾作锚。
    //
    // 24-17 把 lib/ 内以「症」结尾的硬编码名字全部去掉了末字，于是「要求名字
    // 以『症』结尾」的抽取式在 allKb 上**零命中** ⇒ `bad` 恒空 ⇒ 断言恒绿。
    // U2 实测（2026-10-31）：严格式 0 命中；去掉「症」锚后 554 命中（覆盖
    // 39/39 个 ID），其中「名字属于另一个 ID」的错配 **0** 条 ⇒ 配对还在，
    // 只是形态变了。⇒ 判据改为**反查**（不再以「症」为锚），三条子判据：
    //
    //   R-A 跨 ID 错配：全库 `P0XX + 中文 token`，token 若恰好是**别的 ID** 的
    //       别名 ⇒ 红（0.3.6 重编号残留的主形态）。
    //   R-B 旧形态残留：token 以「症」结尾 ⇒ 红（旧名一律在白名单外，V3）。
    //   R-C 名字槽位：标题行 `### P0XX 名字` 的名字必须是该 ID 的别名 ⇒ 改名
    //       未同步注册表即红（#15 只查标题存在且唯一，不查名字对不上）。
    //
    // 白名单口径（V3）：`kLegacySyndromeNames`（24-07 过渡件，31 条旧名）已随
    // 24-17 清扫删除（现场核：`grep -rn kLegacySyndromeNames lib/ test/` 无该
    // 符号，只剩退役档案里的注释提到）⇒ 允许集 = **注册表现行字段**
    // （name / shortName / v1·v2 动作显示名，及去「症」形态）。⇒ 任何旧名
    // （含「现行名 + 症」形态）都落在白名单外 ⇒ 必红，不会因白名单被复活。
    //
    // 已知边界（不是缺陷，是取舍）：叙述文本里 157 条 `P0XX + 叙述词`（如
    // 「P001 优先」「P006 是风格问题」）不属任何别名 ⇒ R-A 跳过，不判红。
    // 若强行要求「全库每个 token 都必须是别名」，现行四库立刻误红 157 条；
    // 而按「表格单元格/列表行首」判名字槽又误红 40 条（消歧裁决表 `| P001 优先 |`）。
    // ⇒ 严格性只落在**标题槽位**（78/78 命中现行名，零误红）。
    // ───────────────────────────────────────────────────────────
    test('#13 症候「ID↔名字」一致性：全库 P0XX 后的名字必须匹配注册表', () {
      final nameById = {for (final s in kSyndromeRegistry) s.id: s.name};
      final aliases = <String, Set<String>>{
        for (final s in kSyndromeRegistry)
          s.id: {
            s.name,
            s.shortName,
            s.name.replaceAll(RegExp(r'症$'), ''),
            s.shortName.replaceAll(RegExp(r'症$'), ''),
            // 动作库渲染的是 v1/v2 动作显示名（`v1ActionDisplayName` /
            // `v2ActionDisplayName`），不并入 ⇒ coaching-actions-v2 必假红。
            s.v1ActionDisplayName,
            s.v2ActionDisplayName,
          },
      };
      // 别名 → 拥有它的 ID 集合（反查「这条名字属于谁」）
      final ownerOf = <String, Set<String>>{};
      aliases.forEach((id, set) {
        for (final a in set) {
          ownerOf.putIfAbsent(a, () => <String>{}).add(id);
        }
      });

      // 抽取式：`P0XX + 紧跟的中文 token（2–12 字）+ 边界`。**不再要求以
      // 「症」结尾**（那正是 24-17 消除的形态）。边界前置断言保留，用于跳过
      // 「P018 为基础症候」「P001-P023 全部症候」这类范围/叙述文本。
      final re = RegExp(
        r'(P\d{3})\s*[（(]?\s*([\u4e00-\u9fff][\u4e00-\u9fffA-Za-z0-9/·]{1,11})'
        r'(?=[、，,。；;）)|:：\s]|$)',
        multiLine: true,
      );
      // 旧形态：`P0XX + 以「症」结尾的 token`（清扫批要消灭的形态）
      final legacyRe = RegExp(
        r'(P\d{3})\s*[（(]?\s*([\u4e00-\u9fff][\u4e00-\u9fffA-Za-z0-9/·]{1,11}?症)'
        r'(?=[、，,。；;）)|:：\s]|$)',
        multiLine: true,
      );
      // 名字槽位：标题行 `### P0XX 名字`（症候手册 `###` / 训练库 `##`）
      final headRe = RegExp(
        r'^(#{1,6})[ \t]+(P\d{3})[ \t]+(.*)$',
        multiLine: true,
      );

      // 失败信息里带上下文，直接指认是哪一处
      String snippet(String kb, int start, int end) {
        final a = (start - 14).clamp(0, kb.length);
        final b = (end + 14).clamp(0, kb.length);
        return kb.substring(a, b).replaceAll('\n', '⏎');
      }

      int lineOf(String kb, int offset) {
        var n = 1;
        var i = kb.indexOf('\n');
        while (i >= 0 && i < offset) {
          n++;
          i = kb.indexOf('\n', i + 1);
        }
        return n;
      }

      // ── R-A：跨 ID 错配（token 是别的 ID 的名字 ⇒ 必红）──
      List<String> crossIdBad(String kb) {
        final bad = <String>[];
        for (final m in re.allMatches(kb)) {
          final id = m.group(1)!;
          final tok = m.group(2)!;
          final al = aliases[id];
          if (al == null) continue; // 非法 ID 由 #9 兜底
          if (al.contains(tok)) continue; // 该 ID 自己的别名，合法
          final owners = ownerOf[tok];
          if (owners == null || owners.isEmpty) continue; // 叙述文本，非名字（见上文边界）
          bad.add(
            '第 ${lineOf(kb, m.start)} 行 $id +「$tok」← 该名字属于 '
            '${owners.join("/")}（$id 应为「${nameById[id]}」）…'
            '「${snippet(kb, m.start, m.end)}」',
          );
        }
        return bad;
      }

      // ── R-B：旧形态残留（以「症」结尾 ⇒ 白名单外 ⇒ 必红）──
      List<String> legacyBad(String kb) {
        final bad = <String>[];
        for (final m in legacyRe.allMatches(kb)) {
          bad.add(
            '第 ${lineOf(kb, m.start)} 行 ${m.group(1)} +「${m.group(2)}」'
            '（旧形态末字「症」，应去掉）…「${snippet(kb, m.start, m.end)}」',
          );
        }
        return bad;
      }

      // ── R-C：名字槽位（标题行名字必须是该 ID 的别名）──
      List<String> headingBad(String kb) {
        final bad = <String>[];
        for (final m in headRe.allMatches(kb)) {
          final id = m.group(2)!;
          final rest = m.group(3)!.trim();
          final al = aliases[id];
          if (al == null) continue;
          if (al.contains(rest)) continue;
          bad.add(
            '第 ${lineOf(kb, m.start)} 行 $id 标题名「$rest」不在允许别名集'
            '（应为「${nameById[id]}」）',
          );
        }
        return bad;
      }

      // ── 正向：现行四库零误差（V1）──
      final crossIdList = crossIdBad(allKb);
      expect(
        crossIdList,
        isEmpty,
        reason:
            '症候 ID 与名字不一致（0.3.6 重编号残留）:\n'
            '${crossIdList.join('\n')}',
      );
      final legacyList = legacyBad(allKb);
      expect(
        legacyList,
        isEmpty,
        reason:
            '库内仍带旧形态末字「症」（24-17 清扫回归）:\n'
            '${legacyList.join('\n')}',
      );
      final headingList = headingBad(allKb);
      expect(
        headingList,
        isEmpty,
        reason: '症候段标题名与注册表不一致:\n${headingList.join('\n')}',
      );

      // ── 反空转：抽取面被抽空时上面三条会恒绿，故先钉住「面非空」──
      final hitIds = <String>{
        for (final m in re.allMatches(allKb))
          if (aliases.containsKey(m.group(1))) m.group(1)!,
      };
      expect(
        hitIds.length,
        kSyndromeRegistry.length,
        reason:
            '每个注册表 ID 都必须在全库里至少出现一次「ID + 中文 token」'
            '（实到 ${hitIds.length}/${kSyndromeRegistry.length}）——'
            '少一个就说明抽取面漏了该 ID，上面三条对该 ID 恒绿',
      );
      final headingHitIds = <String>{
        for (final m in headRe.allMatches(allKb))
          if (aliases.containsKey(m.group(2))) m.group(2)!,
      };
      expect(
        headingHitIds.length,
        kSyndromeRegistry.length,
        reason:
            '每个注册表 ID 都必须有段标题（实到 '
            '${headingHitIds.length}/${kSyndromeRegistry.length}）——'
            '标题锚一旦失配，R-C 就空转',
      );

      // ── 负向自测（V2 / U3）：每条子判据各证一次「会红」，并证合法形态不误红 ──
      // 断言不只「非空」，还要求命中的正是这条注入 —— 否则换个原因红了也算通过。
      // N1 跨 ID 错配：把 P010 的名字接到 P001 后面 ⇒ 必须红
      final n1 = crossIdBad('$allKb\n| P001 张力不足 | 注入的错配行 |\n');
      expect(
        n1,
        isNotEmpty,
        reason: '注入「P001 张力不足」（张力不足属 P010）后仍不红 ⇒ R-A 无鉴别力',
      );
      expect(
        n1.first,
        allOf(contains('P001 +「张力不足」'), contains('P010')),
        reason: '红了，但不是因为这条注入（R-A 判红原因对不上）: ${n1.first}',
      );
      // N1b 同一形态的另一种：`P001 信息倾泻`
      //     —— 卡面 §三 把它写成「不误红」的合法形态（理由「P001 的
      //     v2ActionName 就是信息倾泻」），但现场事实是：
      //       · P001 现行名 = 情绪标签化（`syndrome_registry.dart:288-290`）；
      //       · 信息倾泻 = P002 的 name，`v2ActionName: '信息倾泻'` 也在 P002
      //         记录内（`:305-321`，下一条记录 P003 起于 `:323`）；
      //       · 退役档案记 `P004 信息倾泻症（含原 P001 世界观膨胀子类型）→ P002`
      //         （`syndrome_retirement.dart:103`）⇒ 历史上信息倾泻在 P004/P002
      //         一侧，从未属于 P001。
      //     ⇒ `P001 信息倾泻` **是**跨 ID 冒充，必红；卡面那条「不误红」样本
      //       本身即错配形态，若按它放行等于把护栏对主形态免疫。
      final n1b = crossIdBad('$allKb\n- P001 信息倾泻，\n');
      expect(
        n1b,
        isNotEmpty,
        reason: '注入「P001 信息倾泻」（信息倾泻属 P002）后仍不红 ⇒ R-A 无鉴别力',
      );
      expect(
        n1b.first,
        allOf(contains('P001 +「信息倾泻」'), contains('P002')),
        reason: '红了，但不是因为这条注入（R-A 判红原因对不上）: ${n1b.first}',
      );
      // N1c 旧形态：注回末字「症」⇒ 必须红
      final n1c = legacyBad('$allKb\n- P002 信息倾泻症，\n');
      expect(n1c, isNotEmpty, reason: '注入旧形态「P002 信息倾泻症」后仍不红 ⇒ R-B 无鉴别力（恒绿）');
      expect(
        n1c.first,
        contains('P002 +「信息倾泻症」'),
        reason: '红了，但不是因为这条注入（R-B 判红原因对不上）: ${n1c.first}',
      );
      // N1d 名字槽位：标题被改名而未同步注册表 ⇒ 必须红
      final n1d = headingBad('$allKb\n### P001 情绪标签\n');
      expect(n1d, isNotEmpty, reason: '标题改成「情绪标签」后仍不红 ⇒ R-C 无鉴别力');
      expect(
        n1d.first,
        contains('标题名「情绪标签」'),
        reason: '红了，但不是因为这条注入（R-C 判红原因对不上）: ${n1d.first}',
      );
      // N2 合法形态不得误红（这是「不误红」的正确样本，替换卡面那个误标项）：
      //     现行名 / v2 动作显示名（动作库真实渲染形态）/ 表格行内配对。
      //     ⚠️ `OC 平面化` 这类**以拉丁字母起头**的名字，R-A 的抽取式抓不到
      //     （token 首字符类限定为汉字）⇒ 由 R-C 标题槽位覆盖（P008 亦在
      //     上面的 39/39 覆盖里）。此边界不改抽取式：放宽首字符会引入
      //     `P001 A007` 这类动作编号噪声。
      const legit =
          '\n- P002 信息倾泻，\n'
          '- P005 句式单一，\n'
          '- P001 情绪标签化，\n'
          '| P006 语言堆砌 | 合法配对 |\n';
      expect(
        crossIdBad('$allKb$legit'),
        isEmpty,
        reason: '合法配对被误红 ⇒ R-A 过严（每条别名都在白名单内）',
      );
      expect(
        legacyBad('$allKb$legit'),
        isEmpty,
        reason: '合法配对（不含「症」）被误红 ⇒ R-B 过严',
      );
      expect(headingBad('$allKb$legit'), isEmpty, reason: '合法标题被误红 ⇒ R-C 过严');
    });

    test('#14 手写「技法索引」表行内症候 ID 不重复（0.3.6 去重回归）', () {
      // 0.3.6 把 14 个被删症候的旧 ID 重映射到幸存者，使同行
      // 「适用症候」列出现重复 ID（如 P007、P007 / P004、P004）。
      final rowRe = RegExp(
        r'^\|\s*(T\d{3})\s*\|([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|\s*$',
        multiLine: true,
      );
      final bad = <String>[];
      for (final (label, content) in [
        ('technique-index(L2)', kTechniqueIndexContent),
        ('technique-library(L3)', kTechniqueLibraryContent),
      ]) {
        final idx = content.indexOf('## 技法索引');
        expect(idx, isNot(-1), reason: '$label 未找到「## 技法索引」表（判据前提）');
        for (final m in rowRe.allMatches(content.substring(idx))) {
          final ids = RegExp(
            r'P\d{3}',
          ).allMatches(m.group(4)!).map((x) => x.group(0)!).toList();
          if (ids.length != ids.toSet().length) {
            bad.add('$label ${m.group(1)} -> ${ids.join('、')}');
          }
        }
      }
      expect(bad, isEmpty, reason: '技法索引表行内出现重复症候 ID:\n${bad.join('\n')}');
    });

    test('#15 症候段标题唯一：手册 ### / 训练 ## 每个 ID 恰 1 次', () {
      final bad = <String>[];
      for (final (label, content, re) in [
        ('手册', kSyndromeManualContent, RegExp(r'###\s+(P\d{3})\s')),
        ('训练', kTrainingFullKnowledge, RegExp(r'##\s+(P\d{3})\s')),
      ]) {
        final count = <String, int>{};
        for (final m in re.allMatches(content)) {
          count.update(m.group(1)!, (v) => v + 1, ifAbsent: () => 1);
        }
        for (final id in kSyndromeIds) {
          final n = count[id] ?? 0;
          if (n != 1) bad.add('$label $id 段数=$n（应为 1）');
        }
      }
      expect(bad, isEmpty, reason: '症候段标题重复/缺失:\n${bad.join('\n')}');
    });

    test('#16 few-shot 库键均为合法症候 ID（防旧编号键残留）', () {
      final ids = kSyndromeIds.toSet();
      final bad = <String>[
        for (final k in kTrainingFewShotLibrary.keys)
          if (!ids.contains(k)) '非法键 $k',
      ];
      expect(bad, isEmpty, reason: 'few-shot 库存在非注册表键:\n${bad.join('\n')}');
      expect(kTrainingFewShotLibrary, isNotEmpty, reason: 'few-shot 库为空');
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
      // P2-9：新增 reviewSchedule 降级项（deg 3），共 9 项
      expect(order.length, 9);
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

  // ───────────────────────────────────────────────────────────
  // 去症清扫反方向护栏（T-20261024-17 B7）
  //
  // 正方向（现行名不带「症」）由四库一致性 #1–#12 与锚点快照守着；
  // 本组守**反方向**：旧形态（末字带「症」）不得再出现在 6 个派生注入面里。
  //
  // 派生口径（报批稿 §2.6 甲案）：**不新增 A→B 映射表、不把旧名写进任何
  // `lib/` 文件** —— 旧形态在测试内由注册表现行名运行时派生
  // （`现行名 + '症'`）。此派生式与 24-07 别名单的 31 条旧名逐字相等
  // （现场实证 31/31），故覆盖面不窄于报批稿授权面。
  //
  // 每条断言配**负向自测**：把派生旧形态注回面的副本 ⇒ 必须命中。
  // 没有负向自测，「零出现」在派生集变空时会恒绿（V4.15 坑 1）。
  // ───────────────────────────────────────────────────────────
  group('去症清扫反方向护栏（T-20261024-17 B7 · 六面零出现）', () {
    // 派生式：旧形态 = 现行名 + 「症」（24-07 别名单的 31 条逐字等价，现场实证）。
    String legacyFormOf(String name) => '$name症';

    // 派生集：现行名 + 「症」。注册表若将来出现以「症」结尾的现行名，
    // 派生式会退化成「现行名本身」⇒ 必恒红，故先把这个前提钉住。
    final legacyForms = <String>{
      for (final s in kSyndromeRegistry) legacyFormOf(s.name),
    };

    // 边界护栏：命中后紧跟「候」的是「…病症候」这类复合词（症候 = symptom，
    // 不是旧名残留），不算命中；其余一律算。
    String? firstLegacyHit(String face) {
      for (final form in legacyForms) {
        var i = face.indexOf(form);
        while (i >= 0) {
          final after = i + form.length;
          if (after >= face.length || face[after] != '候') return form;
          i = face.indexOf(form, after);
        }
      }
      return null;
    }

    // 切片：锚缺失即 fail（不得跳过）——V4.15 坑 1 的「锚失效要 fail」。
    String sliceBetween(
      String src,
      String startAnchor,
      String endAnchor,
      String label,
    ) {
      final a = src.indexOf(startAnchor);
      final b = src.indexOf(endAnchor, a + 1);
      expect(a, greaterThan(-1), reason: '$label 起锚「$startAnchor」缺失 ⇒ 护栏失明');
      expect(b, greaterThan(a), reason: '$label 止锚「$endAnchor」缺失或倒序 ⇒ 护栏失明');
      return src.substring(a, b);
    }

    // F-block 观察注入面：五个构建器各喂一条最小观察项，拼成被注入的原文。
    String fBlockFaces() {
      final conflict = buildConflictObservationsContext([
        ConflictObservation(
          characterName: '阿禾',
          attribute: '独生子女状态',
          orderedValues: [
            CharacterAssertion(attribute: '独生子女状态', value: '独生子', timestamp: 0),
          ],
          description: '第3章「独生子」→ 第15章「妹妹」',
        ),
      ]);
      final causality = buildCausalityBreakContext([
        const CausalityBreakObservation(
          name: '决定去金陵',
          eventType: '决定',
          description: '第5章「决定去金陵」（决定类）缺触发事件',
        ),
      ]);
      final subplot = buildSubplotClosureContext([
        const UnclosedSubplotObservation(
          name: '钥匙的秘密',
          introducedChapter: 3,
          currentChapter: 12,
          description: '第3章引入的支线「钥匙的秘密」至今（第12章）未回收',
        ),
      ]);
      final grammar = buildGrammarLexicalContext([
        const GrammarLexicalIssue(
          kind: GrammarIssueKind.dupChar,
          evidence: '的了了',
          description: '相邻重复虚词',
        ),
      ]);
      final dialogue = buildDialogueTagContext([
        const DialogueTagIssue(
          kind: DialogueTagIssueKind.tagRepeat,
          evidence: '低声说',
          description: '同一修饰性对话标签重复',
        ),
      ]);
      final faces = [conflict, causality, subplot, grammar, dialogue];
      for (final f in faces) {
        expect(f, isNotNull, reason: 'F-block 构建器返回 null ⇒ 该面未注入，护栏空转');
      }
      return faces.join('\n');
    }

    // 六个派生注入面（与报批稿 §2.6 编号一一对应）。
    final faces = <String, String Function()>{
      '1 症候类型速查表': () => sliceBetween(
        kSyndromeManualContent,
        '## 症候类型速查',
        '## 诊断输出规范',
        '类型速查表',
      ),
      '2 手册内嵌技法映射表': () => sliceBetween(
        kSyndromeManualContent,
        '### 写作技巧提示（技法库）',
        '## 诊断执行指引',
        '技法映射表',
      ),
      '3 training-templates-index': () =>
          skillRegistry['training-templates-index']!.content,
      '4 coaching-actions-v2': () =>
          skillRegistry['coaching-actions-v2']!.content,
      '5 F-block 观察注入': fBlockFaces,
      '6 kChunkSystemPrompt': () => kChunkSystemPrompt,
    };

    test('#13 派生口径前提：注册表无现行名以「症」结尾，旧形态集非空', () {
      expect(
        kSyndromeRegistry.every((s) => !s.name.endsWith('症')),
        true,
        reason: '若有现行名以「症」结尾，派生式退化为现行名本身 ⇒ 反方向断言恒红',
      );
      expect(
        legacyForms.length,
        kSyndromeRegistry.length,
        reason: '派生旧形态必须逐条对应注册表（去重后少一条 = 有两条现行名同名）',
      );
      expect(legacyForms.isNotEmpty, true, reason: '空集会让下面所有零出现断言恒绿');
    });

    for (final entry in faces.entries) {
      final label = entry.key;
      test('#14 $label：旧形态零出现 + 现行名在场', () {
        final face = entry.value();
        expect(face.isEmpty, false, reason: '$label 为空面 ⇒ 零出现断言恒绿');

        // 反方向：派生旧形态在该面内不得出现（「…病症候」除外）。
        expect(
          firstLegacyHit(face),
          isNull,
          reason: '$label 仍带旧形态末字「症」⇒ 24-17 正文清扫回归',
        );

        // 正向：现行名（不带「症」）必须在场 —— 证明该面真的在被检查。
        final presentNames = kSyndromeRegistry
            .map((s) => s.name)
            .where(face.contains)
            .toList();
        expect(
          presentNames.length,
          greaterThanOrEqualTo(1),
          reason: '$label 里一条现行名都没有 ⇒ 面选错或内容被抽空',
        );
      });
    }

    test('#15 负向自测：把派生旧形态注回每个面 ⇒ 必须被检出（断言不恒绿）', () {
      for (final entry in faces.entries) {
        final face = entry.value();
        // 取该面里在场的第一条现行名，注回其旧形态。
        final currentName = kSyndromeRegistry
            .map((s) => s.name)
            .firstWhere((n) => face.contains(n));
        final tampered = '$face\n（人工注入 $currentName症）';
        expect(
          firstLegacyHit(tampered),
          '$currentName症',
          reason: '${entry.key} 注入旧形态后仍检不出 ⇒ 该断言恒绿，无鉴别力',
        );
      }
    });

    test('#16 边界护栏：「…症候」复合词不算旧名残留', () {
      // 护栏自身的鉴别力：既不能把合法复合词判红（否则护栏被当噪声拆掉），
      // 也不能因此放过真旧名。旧形态一律由注册表派生，不写死字符串。
      final n = kSyndromeRegistry.first.name;
      expect(
        firstLegacyHit('${legacyFormOf(n)}候补充说明'),
        isNull,
        reason: '「症候」是复合词（symptom），不是旧名末字 ⇒ 不得判红',
      );
      expect(
        firstLegacyHit('${legacyFormOf(n)}，应报该判据'),
        isNotNull,
        reason: '真正的旧形态（末字「症」后不接「候」）必须命中',
      );
    });
  });
}
