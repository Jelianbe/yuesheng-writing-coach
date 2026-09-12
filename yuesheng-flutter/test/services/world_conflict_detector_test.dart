// ─────────────────────────────────────────────────────────────
// world_conflict_detector_test — 批次 E1-b 设定层判据（ADR-C93）
//
// 纯判据 detectWorldConflicts：
//   1. 同主题同属性不同值 + 带 evidence + 不同章 → 产出（正向基准）
//   2. 描述格式含章节
//   3. ★ 跨主题不比较（不同 name 同属性不同值 → 不产出）——「层次感」不误报
//   4. 同主题不同属性 → 不产出
//   5. 同值 → 不产出
//   6. ★ 无 evidence → 不产出（D4① 硬门槛）
//   7. ★ 同章豁免（D4③）
//   8. stale 断言 → 不产出（白拿 E1-a）
//   9. rejected 断言 → 不产出（R-009 用户主权）
//  10. 多主题 → 按 (主题名, 属性) 字典序稳定排序
//  11. 空输入 → 空数组
//  12. 无章节信息（chapter 同为 null）→ 不产出（D4③ 的 null 分支）
//  13. ★ 隔离反证：世界观断言走 F05 判据会产出，但走设定层判据才是其归属
//     ——两侧分组键不同，同一批数据结果不同，证明判据确实分立
//
// 适配入口 detectConflictsForWorlds（world_setting.dart）：
//  14. 端到端：upsertWorld 写入 → 入口检出（验证 evidence 经合并逻辑保真）
//
// 注入文本 buildWorldSettingObservationsContext：
//  15. 空 → null（零 token 成本）
//  16. 非空 → 含设定层标题、主题名、「规则与例外」免责句式
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/conflict_detector.dart';
import 'package:writingcoach/services/world_setting.dart';
import 'package:writingcoach/types/character_types.dart';

CharacterAssertion _assertion({
  required String attribute,
  required String value,
  int? chapter,
  required int timestamp,
  // D4① 门槛要求非空，故默认给值；要测「无依据」显式传 null。
  String? evidence = '原文片段',
  String status = 'confirmed',
  bool stale = false,
}) {
  return CharacterAssertion(
    attribute: attribute,
    value: value,
    chapter: chapter,
    timestamp: timestamp,
    status: status,
    evidence: evidence,
    stale: stale,
  );
}

void main() {
  group('detectWorldConflicts（纯判据）', () {
    test('#1 同主题同属性不同值 + 带依据 + 不同章 → 产出', () {
      final result = detectWorldConflicts([
        (
          name: '灵气体系',
          assertions: [
            _assertion(
              attribute: '灵气浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
            ),
            _assertion(
              attribute: '灵气浓度',
              value: '充沛',
              chapter: 20,
              timestamp: 200,
            ),
          ],
        ),
      ]);

      expect(result.length, 1);
      final obs = result.first;
      expect(obs.themeName, '灵气体系');
      expect(obs.attribute, '灵气浓度');
      expect(obs.orderedValues.length, 2);
      expect(obs.excerpt, '原文片段');
    });

    test('#2 描述格式含章节', () {
      final obs = detectWorldConflicts([
        (
          name: '灵气体系',
          assertions: [
            _assertion(
              attribute: '灵气浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
            ),
            _assertion(
              attribute: '灵气浓度',
              value: '充沛',
              chapter: 20,
              timestamp: 200,
            ),
          ],
        ),
      ]).first;

      expect(obs.description, '第3章「稀薄」→ 第20章「充沛」');
    });

    test('#3 ★ 跨主题不比较——规则与例外是层次，不是不一致', () {
      // 「这个世界灵气稀薄」（全域规则）+「青云山灵脉充沛」（局部例外）
      // 落成两个设定主题，判据**只在同一主题内**比较，故零产出。
      final result = detectWorldConflicts([
        (
          name: '东荒灵气',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
            ),
          ],
        ),
        (
          name: '青云山灵脉',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '充沛',
              chapter: 8,
              timestamp: 200,
            ),
          ],
        ),
      ]);

      expect(result, isEmpty, reason: '跨主题的不同取值是层次感，不是设定不一致');
    });

    test('#4 同主题不同属性 → 不产出', () {
      final result = detectWorldConflicts([
        (
          name: '灵气体系',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
            ),
            _assertion(
              attribute: '来源',
              value: '灵脉',
              chapter: 8,
              timestamp: 200,
            ),
          ],
        ),
      ]);

      expect(result, isEmpty);
    });

    test('#5 同值 → 不产出', () {
      final result = detectWorldConflicts([
        (
          name: '灵气体系',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
            ),
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 20,
              timestamp: 200,
            ),
          ],
        ),
      ]);

      expect(result, isEmpty);
    });

    test('#6 ★ 无 evidence → 不产出（D4① 硬门槛）', () {
      final result = detectWorldConflicts([
        (
          name: '灵气体系',
          assertions: [
            // 第一条无原文依据 → 被门槛滤掉，只剩一条 → 不构成不一致
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
              evidence: null,
            ),
            _assertion(
              attribute: '浓度',
              value: '充沛',
              chapter: 20,
              timestamp: 200,
            ),
          ],
        ),
      ]);

      expect(result, isEmpty, reason: '无原文可核对的断言不得参与设定层检测');
    });

    test('#6b 无 evidence 的门槛逐条生效：两侧都无依据 → 不产出', () {
      final result = detectWorldConflicts([
        (
          name: '灵气体系',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
              evidence: null,
            ),
            _assertion(
              attribute: '浓度',
              value: '充沛',
              chapter: 20,
              timestamp: 200,
              evidence: '',
            ),
          ],
        ),
      ]);

      expect(result, isEmpty);
    });

    test('#7 ★ 同章豁免（D4③）', () {
      final result = detectWorldConflicts([
        (
          name: '灵气体系',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
            ),
            _assertion(
              attribute: '浓度',
              value: '充沛',
              chapter: 3,
              timestamp: 200,
            ),
          ],
        ),
      ]);

      expect(result, isEmpty, reason: '同一章内的两种措辞不是时序矛盾');
    });

    test('#12 无章节信息（chapter 同为 null）→ 不产出', () {
      final result = detectWorldConflicts([
        (
          name: '灵气体系',
          assertions: [
            _assertion(attribute: '浓度', value: '稀薄', timestamp: 100),
            _assertion(attribute: '浓度', value: '充沛', timestamp: 200),
          ],
        ),
      ]);

      expect(result, isEmpty, reason: '无章节信息即无法判定为时序差，保守不报');
    });

    test('#8 stale 断言 → 不产出', () {
      final result = detectWorldConflicts([
        (
          name: '灵气体系',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
              stale: true,
            ),
            _assertion(
              attribute: '浓度',
              value: '充沛',
              chapter: 20,
              timestamp: 200,
            ),
          ],
        ),
      ]);

      expect(result, isEmpty);
    });

    test('#9 rejected 断言 → 不产出', () {
      final result = detectWorldConflicts([
        (
          name: '灵气体系',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
              status: 'rejected',
            ),
            _assertion(
              attribute: '浓度',
              value: '充沛',
              chapter: 20,
              timestamp: 200,
            ),
          ],
        ),
      ]);

      expect(result, isEmpty, reason: 'R-009：用户已否决的断言不得复活为检测输入');
    });

    test('#10 多主题 → 按 (主题名, 属性) 字典序稳定排序', () {
      final result = detectWorldConflicts([
        (
          name: '朝廷',
          assertions: [
            _assertion(
              attribute: '国策',
              value: '主战',
              chapter: 1,
              timestamp: 100,
            ),
            _assertion(
              attribute: '国策',
              value: '主和',
              chapter: 9,
              timestamp: 200,
            ),
          ],
        ),
        (
          name: '灵气体系',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
            ),
            _assertion(
              attribute: '浓度',
              value: '充沛',
              chapter: 20,
              timestamp: 200,
            ),
          ],
        ),
      ]);

      expect(result.map((o) => o.themeName).toList(), ['朝廷', '灵气体系']);
    });

    test('#11 空输入 → 空数组', () {
      expect(detectWorldConflicts(const []), isEmpty);
    });

    test('#13 ★ 隔离反证：同批数据走 F05 判据与走设定层判据结果不同', () {
      // 造一批「同一主题内、跨章、不同值」的世界观断言。
      //
      // 走 F05 判据（喂成两个人名）→ 产出 2 条时序矛盾——这正是**误报**的形态：
      // 世界观是规则，跨主题取值不同是层次，此处被拆成两个「人」后必然"矛盾"。
      // 走设定层判据（喂成一个主题）→ 产出 1 条不一致（判据归属正确）。
      //
      // 两侧分组键不同 ⇒ 判据确实分立，世界观数据不会被 F05 通道消化。
      final f05 = detectCharacterConflicts([
        (
          name: '东荒灵气',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
            ),
          ],
        ),
        (
          name: '青云山灵脉',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '充沛',
              chapter: 8,
              timestamp: 200,
            ),
          ],
        ),
      ]);
      final setting = detectWorldConflicts([
        (
          name: '灵气体系',
          assertions: [
            _assertion(
              attribute: '浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
            ),
            _assertion(
              attribute: '浓度',
              value: '充沛',
              chapter: 20,
              timestamp: 200,
            ),
          ],
        ),
      ]);

      expect(f05, isEmpty, reason: 'F05 逐人比较，两人各只有一条 → 无矛盾');
      expect(setting.length, 1, reason: '设定层同主题内两条 → 不一致');
    });
  });

  group('detectConflictsForWorlds（适配入口）', () {
    late AppDatabase db;
    late WorldFactRepository repo;
    late String manuscriptId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = WorldFactRepository(db);
      manuscriptId = await ManuscriptRepository(
        db,
      ).createManuscript(title: '测试稿');
    });

    tearDown(() async => db.close());

    test('#14 端到端：upsertWorld 写入 → 入口检出（evidence 经合并保真）', () async {
      await repo.upsertWorld(
        manuscriptId: manuscriptId,
        name: '灵气体系',
        assertions: [
          _assertion(
            attribute: '浓度',
            value: '稀薄',
            chapter: 3,
            timestamp: 100,
            evidence: '这方天地灵气稀薄',
          ),
          _assertion(
            attribute: '浓度',
            value: '充沛',
            chapter: 20,
            timestamp: 200,
            evidence: '此地灵脉充沛',
          ),
        ],
        chapterHash: 'H3',
        chapterNo: 3,
      );

      final worlds = await repo.listWorlds(manuscriptId);
      final result = detectConflictsForWorlds(worlds);

      expect(result.length, 1);
      expect(result.first.themeName, '灵气体系');
      expect(
        result.first.excerpt,
        isNotEmpty,
        reason: 'mergeAssertions 必须保留 evidence，否则门槛会把全部断言挡在门外',
      );
    });

    test('#14b 单条断言的作品 → 入口零产出', () async {
      await repo.upsertWorld(
        manuscriptId: manuscriptId,
        name: '灵气体系',
        assertions: [
          _assertion(attribute: '浓度', value: '稀薄', chapter: 3, timestamp: 100),
        ],
      );

      final worlds = await repo.listWorlds(manuscriptId);
      expect(detectConflictsForWorlds(worlds), isEmpty);
    });
  });

  group('buildWorldSettingObservationsContext（注入文本）', () {
    test('#15 空 → null（零 token 成本）', () {
      expect(buildWorldSettingObservationsContext(const []), isNull);
    });

    test('#16 非空 → 含设定层标题、主题名与「规则与例外」免责句式', () {
      final ctx = buildWorldSettingObservationsContext([
        WorldConflictObservation(
          themeName: '灵气体系',
          attribute: '灵气浓度',
          orderedValues: [
            _assertion(
              attribute: '灵气浓度',
              value: '稀薄',
              chapter: 3,
              timestamp: 100,
            ),
          ],
          description: '第3章「稀薄」→ 第20章「充沛」',
          excerpt: '这方天地灵气稀薄',
        ),
      ]);

      expect(ctx, isNotNull);
      expect(ctx, contains('设定不一致观察（设定层）'));
      expect(ctx, contains('灵气体系'));
      expect(ctx, contains('规则与例外'), reason: '缺了免责句式等于把机械判定当结论');
      expect(ctx, contains('这方天地灵气稀薄'));
      expect(ctx, isNot(contains('P018')), reason: '设定层不挂 P 编号，注入文本不得引用人物侧症候');
    });
  });
}
