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

    test('#R8 ★ 单轨：读路径无 ID 变换，注册表即唯一真源', () {
      // ★ 2026-10-05（层 2 单轨收口批）：本用例**整体改写**。
      //
      //   旧形态测的是「legacy 归一映射自洽」：逐条遍历 `kSyndromeMergeMap`，
      //   键 ∈ 现行注册表的断言恒等、键 ∉ 的断言单跳归一，再钉住
      //   「33 个现行键 + 14 个真旧号 = 47」。
      //   ⇒ 归一（`kSyndromeMergeMap` + `effectiveSyndromeId`）已整张删除，
      //      该断言的**对象不存在**了。
      //
      //   单轨下的等价命题（本用例现测的内容）：
      //     ① 注册表即全集：ID 唯一，无重复、无第二编号段；
      //     ② 读路径**没有任何 ID 变换** —— 库里那个 ID 是什么，读出来就是什么；
      //     ③ 未知 ID **不得**被猜成已知（`syndromeNameOf` 去回退后的行为）。
      //
      //   ⚠️ ② 不能写成 `effectiveSyndromeId(id) == id`（旧形态）——
      //      那是 `a == a`，恒真、零鉴别力。也不能新造一个恒等函数来测，
      //      那只是把已删的复杂度换个名字装回来。②的真判据是**结构性的**：
      //      生产代码里不存在 ID 变换函数（由 analyzer 的 unused_import 与
      //      下面的 #S-1 共同保证），不是由某条运行时断言保证。
      final active = kSyndromeIds.toSet();

      // ① 注册表即全集：ID 唯一、无重复
      expect(
        active.length,
        kSyndromeRegistry.length,
        reason: '注册表内 ID 必须唯一（重复即两个实体抢一个号）',
      );

      // ③ 未知 ID 一律查不到名字 —— 单轨下越界编号**本身就是缺陷**，
      //   正确处置是让它被 `diagnosis_parser` 的 `syndrome_id_format` 拒掉，
      //   而不是猜一个名字回填（回退会掩盖越界，且让 V-03 的「编号不外泄」
      //   底线失效）。
      for (final unknown in const [
        'P999',
        'P050',
        '',
        'P01',
        'P0001',
        'X001',
        'ZZZ',
      ]) {
        expect(
          syndromeRecordOf(unknown),
          isNull,
          reason: '$unknown 不在注册表内，必须查不到（未知不能变成已知）',
        );
        expect(
          syndromeNameOf(unknown),
          isNull,
          reason: '$unknown 不得被回退猜出名字 —— legacy 归一回退已删除',
        );
      }

      // ★ 真旧号（14 个：P038–P049 + H001/H002）同样必须查不到。
      //   这 14 个是「曾经用过、已永不复用」的号；单轨纪律的第一条就是
      //   **号码一旦分配便永不复用** ⇒ 它们在读路径上必须是「纯未知」。
      //
      //   ⚠️ 本条是单轨纪律的**执行点**：任何「把 P038 分给新症候」的改动
      //      都会在这里变红。这比在退役档案里查（#R-1 系列）更靠前 ——
      //      档案是「历史上用过什么」，注册表是「现在是什么」，
      //      两者相交即事故。
      const retiiredOldIds = [
        'P038',
        'P039',
        'P040',
        'P041',
        'P042',
        'P043',
        'P044',
        'P045',
        'P046',
        'P047',
        'P048',
        'P049',
        'H001',
        'H002',
      ];
      expect(retiiredOldIds.length, 14, reason: '真旧号清单长度是硬锚（防有人悄悄删项）');
      for (final old in retiiredOldIds) {
        expect(
          active.contains(old),
          isFalse,
          reason:
              '$old 是真旧号，**永不复用** —— 它若出现在注册表里，'
              '说明有人把新症候分到了一个已用过的号上',
        );
        expect(
          syndromeNameOf(old),
          isNull,
          reason: '$old 必须读不出名字（不得回退到它退役时的旧实体）',
        );
      }
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

    test('#A1-C ★★★ 三号撞现行号时，必须指向不同实体（变异点）', () {
      // 【断言方向的三次演进 —— 别退回任何一版】
      //
      //   v0（原始）：`expect(effectiveSyndromeId(id), id)`（自聚）。
      //     变异实测（M1：往 map 里加 `'P035': 'P040'`）发现**该断言恒绿**
      //     ⇒ 形同虚设。
      //   v1（ADR-0003 阶段一）：改成直接断言
      //     `kSyndromeMergeMap.containsKey(id) == false`。
      //     这版能被真实变异打红，但**对象已退役**（归一整张删除）。
      //   v2（单轨，2026-10-05 · 本版）：
      //     归一没了，「映射表里不该有这三个键」这件事**无从谈起**。
      //     单轨下真正要守的是**语义层**判据：
      //
      //       字符串 `P035` 如今是「撞文同质化症」，
      //       而它退役时是「对话注水症」（并入 P009）。
      //     ⇒ 同一个字符串、两个不同实体。若哪天两者的**名字变成一样**，
      //        那才是真事故 —— 任何形式的自动归一都会把新实体的数据
      //        改写到旧实体上，且表面完全正常。
      //
      //   ⚠️ 本版比 v1 更强的原因：v1 只能证明「表里没这个键」，
      //      而「表里没键」与「语义不冲突」**不是一回事** ——
      //      键不在表里，代码仍可能按别的方式（如未来的迁移脚本）
      //      把新实体当旧实体处理。本版直接查名字，堵的是语义本身。
      const slots = {'P035': '撞文同质化症', 'P036': '细节失真症', 'P037': '故事核缺失症'};
      const oldEntities = {'P035': '对话注水症', 'P036': '流水账叙述症', 'P037': '心理内耗症'};
      slots.forEach((id, curName) {
        expect(
          syndromeNameOf(id),
          curName,
          reason: '$id 现为「$curName」，不得回退成旧实体',
        );
        expect(
          syndromeNameOf(id),
          isNot(oldEntities[id]),
          reason:
              '$id 若读出旧实体 ⇒ 任何自动归一都会把新实体的历史数据'
              '静默改写到旧实体上',
        );
      });
    });
  });
}
