// ─────────────────────────────────────────────────────────────
// 症候注册表（SyndromeRegistry）合法性测试 — b9 批次27 基础设施
//
// 注册表是症候元数据唯一真源。本测试校验其自身合法性：
//   - ID 升序连续（P001 起，逐号递增，ID 永不复用）
//   - 字段非空 / 枚举合法 / 技法与动作 ID 在对应库存在
// 各库与注册表的渲染一致性断言见 four_libraries_consistency_test。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';

void main() {
  group('批次27（b9）注册表合法性', () {
    test('#R1 注册表非空且 ID 升序连续（P001 起逐号递增）', () {
      expect(kSyndromeRegistry, isNotEmpty);
      // 连续性不变量：注册表数组本身 P001..P033 逐号递增、ID 不复用。
      final ids = kSyndromeRegistry.map((s) => s.id).toList();
      expect(ids.length, kSyndromeRegistry.length);
      for (int i = 0; i < ids.length; i++) {
        expect(
          ids[i],
          'P${(1 + i).toString().padLeft(3, '0')}',
          reason:
              '注册表症候 ID 应连续递增，第 ${i + 1} 个应为 P${(1 + i).toString().padLeft(3, '0')}',
        );
      }
    });

    test('#R2 每条记录字段完整（name/shortName/keyword/oneLine 非空）', () {
      for (final s in kSyndromeRegistry) {
        expect(s.name.trim(), isNotEmpty, reason: '${s.id} name 为空');
        expect(s.shortName.trim(), isNotEmpty, reason: '${s.id} shortName 为空');
        expect(s.keyword.trim(), isNotEmpty, reason: '${s.id} keyword 为空');
        expect(s.oneLine.trim(), isNotEmpty, reason: '${s.id} oneLine 为空');
        expect(s.position.trim(), isNotEmpty, reason: '${s.id} position 为空');
      }
    });

    test('#R3 层级 / 分组 / position 合法', () {
      const validPositions = {
        'chapter',
        'serial',
        'global',
        'beginning',
        'middle',
        'end',
        'local',
      };
      for (final s in kSyndromeRegistry) {
        expect(
          SkillLevel.values.contains(s.level),
          true,
          reason: '${s.id} 非法层级',
        );
        expect(
          MaxAttemptsGroup.values.contains(s.group),
          true,
          reason: '${s.id} 非法 maxAttempts 分组',
        );
        expect(
          validPositions.contains(s.position),
          true,
          reason: '${s.id} 非法 position: ${s.position}',
        );
      }
    });

    test('#R4 推荐技法 ID 在技法库有完整条目（防悬空）', () {
      for (final s in kSyndromeRegistry) {
        expect(s.techniques, isNotEmpty, reason: '${s.id} 无推荐技法');
        for (final t in s.techniques) {
          expect(
            kTechniqueLibraryContent,
            contains('### $t '),
            reason: '${s.id} 引用技法 $t 无完整条目',
          );
        }
      }
    });

    test('#R5 推荐动作 ID 合法（A001-A016）且非空', () {
      for (final s in kSyndromeRegistry) {
        expect(s.actions, isNotEmpty, reason: '${s.id} 无推荐动作');
        for (final a in s.actions) {
          expect(
            RegExp(r'^A0(0\d|1[0-6])$').hasMatch(a),
            true,
            reason: '${s.id} 引用非法动作 $a（应为 A001-A016）',
          );
        }
      }
    });

    test('#R6 派生映射与手写 API 一致（kSyndromeSkillLevels 兼容）', () {
      final derived = kSyndromeSkillLevelsDerived;
      expect(
        derived.keys.toSet(),
        kSyndromeIds.toSet(),
        reason: '派生层级键集应与注册表 ID 集一致',
      );
      // 与既有 API 双写一致（kSyndromeSkillLevels 现由注册表派生）
      expect(kSyndromeSkillLevels, derived);
      // skillLevelOf 逐个命中
      for (final s in kSyndromeRegistry) {
        expect(
          skillLevelOf(s.id),
          s.level,
          reason: 'skillLevelOf(${s.id}) 与注册表不一致',
        );
      }
    });

    test('#R7 syndromeRecordOf 精确查找（未知返回 null）', () {
      for (final s in kSyndromeRegistry) {
        expect(syndromeRecordOf(s.id)?.id, s.id);
      }
      expect(syndromeRecordOf('P999'), isNull);
      expect(syndromeRecordOf(''), isNull);
      expect(syndromeRecordOf(null), isNull);
    });

    test('#R8 legacy 归一映射自洽（彻底删除后无退役标记）', () {
      final active = kSyndromeIds.toSet();
      // 彻底删除后注册表无退役记录：注册表即活跃集合
      expect(active.length, kSyndromeRegistry.length);

      // 归一映射：value 均为活跃症候
      for (final entry in kSyndromeMergeMap.entries) {
        expect(
          active.contains(entry.value),
          true,
          reason: '归一映射 ${entry.key} → ${entry.value} 目标非活跃症候',
        );
      }

      // ★ M1（B1 批）后归一断言**按键的类型分两类**，不再一刀切。
      //
      //   背景：merge map 有 **33 个键同时是现行活跃 ID**（P001–P033），
      //   而「旧 P005」与「现行 P005」是**同一个字符串** ⇒ 程序无从区分。
      //   M1 语义 = 现行 ID 恒等 + 真旧号单跳，故：
      //
      //   · 键 ∈ 现行注册表（33 个）⇒ **原样返回**（不得被改写）
      //   · 键 ∉ 现行注册表（14 个：P038–P049 + H001/H002）⇒ 归一到 value
      //
      //   ⚠️ 本断言原先写的是「所有键都应归一到 value」，那是**旧语义**
      //   （`map[id] ?? id`）的写照，会把 33 个现行 ID 拖进别的实体
      //   ⇒ 实测 18 对现行 ID 因此互撞（详见 syndrome_merge_map_test #M1-4）。
      var legacyChecked = 0;
      var activeChecked = 0;
      for (final entry in kSyndromeMergeMap.entries) {
        if (active.contains(entry.key)) {
          // 现行 ID：恒等，不得被 merge map 改写
          expect(
            effectiveSyndromeId(entry.key),
            entry.key,
            reason:
                '现行 ID ${entry.key}（${syndromeRecordOf(entry.key)?.name}）'
                '必须恒等——它同时是某个旧号的映射目标，'
                '但 M1 语义下现行实体优先，不得被拉去别处',
          );
          activeChecked++;
        } else {
          // 真旧号：单跳归一到 value
          expect(
            effectiveSyndromeId(entry.key),
            entry.value,
            reason: '真旧号 ${entry.key} 应归一到 ${entry.value}',
          );
          legacyChecked++;
        }
      }
      // 实测读数（2026-10-05，A2 批清 P035/P036/P037 后）：33 个现行键 + 14 个真旧号 = 47
      expect(activeChecked, 33, reason: '撞现行 ID 的键实测 33 个');
      expect(legacyChecked, 14, reason: '真旧号实测 14 个（P038–P049 + H001/H002）');

      // 未在映射表中的 ID 原样返回
      expect(effectiveSyndromeId('P999'), 'P999', reason: '非映射 ID 应原样返回');
    });
  });

  // ── ADR-0003 阶段一（A1 批 · 2026-10-05）──────────────────────────
  // ⚠️ 本组的作用是**给注册表条数与新号身份钉上「非派生」的硬锚**。
  //
  // 【为什么必须硬编码】上方 #R1 的连续性断言写的是 `P001..P{ids.length}`
  // —— 它是**派生的**：删掉 P037 后 `length` 同步变 36，断言自动退化成
  // `P001..P036` 并**照样通过**。同理 `four_libraries_consistency_test`
  // 全用 `kSyndromeIds.length` 派生 ⇒「删一条注册 + 同步删一份载体」
  // 这类改动会**全链路静默通过**。本组用三条断言堵住这个洞。
  group('ADR-0003 阶段一（34 → 37 条 · 新号身份锁）', () {
    test('#A1-A 注册表条数硬锚 = 37（非派生）', () {
      expect(
        kSyndromeRegistry.length,
        37,
        reason:
            '注册表应为 37 条（34 + P035/P036/P037）。'
            '若你确实要增减条目，必须同步更新本断言并说明理由——'
            '否则 #R1 的派生连续性会让「少一条」静默通过。',
      );
      expect(kSyndromeIds.length, 37, reason: 'kSyndromeIds 应与注册表同长');
    });

    test('#A1-B P035/P036/P037 三号在册且名字与本批锁定值一致', () {
      const expectNames = {'P035': '撞文同质化症', 'P036': '细节失真症', 'P037': '故事核缺失症'};
      expectNames.forEach((id, name) {
        final rec = syndromeRecordOf(id);
        expect(rec, isNotNull, reason: '$id 应在注册表内');
        expect(rec!.name, name, reason: '$id 名字应锁定为 $name');
      });
    });

    test('#A1-C 三号的旧 legacy 别名键不得残留在映射表中（变异点）', () {
      // 【断言方向的修正记录 · 2026-10-05】
      // 初版写的是 `expect(effectiveSyndromeId(id), id)`（自聚）。
      // 变异实测（M1：往 map 里加 `'P035': 'P040'`）发现**该断言恒绿**——
      // 因为 M1 语义（`syndrome_registry.dart`「归一后的有效症候 ID」）规定
      // 「ID ∈ 现行注册表 ⇒ 原样返回，**不查 merge map**」。
      // ⇒ 加回 legacy 键根本走不到归一逻辑，断言形同虚设。
      // 变异实测真正变红的是 `syndrome_registry_test#R8`（退役标记自洽）。
      //
      // 现改为**直接断言映射表里没有这三个键**——这是能被真实变异打红的形态。
      for (final id in const ['P035', 'P036', 'P037']) {
        expect(
          kSyndromeMergeMap.containsKey(id),
          isFalse,
          reason:
              '$id 的旧 legacy 别名键不得残留在 kSyndromeMergeMap。'
              '残留会让 v46 迁移把存量行的现行实体错误改写'
              '（旧实体：对话注水症 / 流水账叙述症 / 心理内耗症）。',
        );
      }
    });
  });
}
