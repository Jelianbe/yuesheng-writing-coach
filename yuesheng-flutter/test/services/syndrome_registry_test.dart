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

      // 归一映射：value 均为活跃症候；effectiveSyndromeId 归一正确
      for (final entry in kSyndromeMergeMap.entries) {
        expect(
          active.contains(entry.value),
          true,
          reason: '归一映射 ${entry.key} → ${entry.value} 目标非活跃症候',
        );
        expect(
          effectiveSyndromeId(entry.key),
          entry.value,
          reason: 'effectiveSyndromeId(${entry.key}) 未归一',
        );
      }
      // 未在映射表中的 ID 原样返回
      expect(effectiveSyndromeId('P999'), 'P999', reason: '非映射 ID 应原样返回');
    });
  });
}
