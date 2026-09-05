// ─────────────────────────────────────────────────────────────
// character_identity_test — C78 批次2b「人物身份合并」单元测试
//
// 病根：character_fact 唯一键是 UNIQUE(manuscript_id, name)，同一人被 AI 用
// 不同称呼抽出时落成**多行**（主名行「林晚晴」+ 别名行「阿晴」）。而
// detectCharacterConflicts 是「逐角色逐属性、跨行不合并」
// （conflict_detector.dart:56-83）——直接喂进去，同一人的断言被拆在两个角色
// 里各自内部比较，**跨行矛盾漏检**，D-1 的别名价值在 F05 侧完全落空。
//
// 本文件的核心是 #2：它同时跑「不合并」与「合并」两条路径做**对拍**，
// 证明漏检真实存在、且 groupByIdentity 确实把它补上了。只验合并后能检出
// 是不够的——那验不到「本函数存在的理由」。
//
// 覆盖：
//   1. 空输入 → 三个入口都空
//   2. 主名行 + 别名行的跨行矛盾能检出（对照组：不合并 → 漏检）
//   3. 两个无关人物不误合并
//   4. 合并后 name 用主名行（status='active' 优先，非首行优先）
//   5. 防御分支：全组无 active → 取首行，不抛不空（脏数据降级）
//   6. 传递闭包：林晚晴=阿晴、阿晴=晚晴 ⇒ 林晚晴=晚晴
//   7. 别名进合并上下文（identityAliases），但**不进**检测器的 name
//   8. 合并不得绕过 F05 判据（stale 断言合并后仍被过滤）
//   9. fillConflictExcerpts：命中填摘录 / 不命中 null
//  10. detectConflictsForFacts 判据入口：空输入 → 空
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

// 不 import drift：drift 导出 isNull / isNotNull 与 matcher 撞名（实测：
// 撞名来自 **drift 那条 import**，database.dart 并不再导出它们——单独 import
// database.dart + flutter_test 用 isNull 编译通过，已探针验证）。
// 本文件只需 CharacterFact，无谓地引 drift 等于自找命名冲突。
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/services/character_identity.dart';
import 'package:writingcoach/services/conflict_detector.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  CharacterAssertion a(
    String attribute,
    String value, {
    int? chapter,
    int timestamp = 1000,
    String status = 'confirmed',
    bool stale = false,
  }) {
    return CharacterAssertion(
      attribute: attribute,
      value: value,
      chapter: chapter,
      timestamp: timestamp,
      status: status,
      stale: stale,
    );
  }

  /// 构造 character_fact 行。
  ///
  /// 走**直接构造**而非内存库：`groupByIdentity` / `identityAliases` 是纯函数，
  /// 不碰 IO，起一个 NativeDatabase 只会让用例变慢且掩盖「纯函数」这一性质。
  /// 断言走 `jsonEncode` 是为了让被测代码真的过一遍 `parseAssertions`——
  /// 那才是生产路径（DB 里存的就是 JSON 字符串）。
  CharacterFact fact(
    String name, {
    List<CharacterAssertion> assertions = const [],
    List<String> aliases = const [],
    String status = 'active',
  }) {
    return CharacterFact(
      id: 'cf_$name',
      manuscriptId: 'ms_1',
      name: name,
      assertions: jsonEncode(
        assertions.map((x) => x.toJson()).toList(growable: false),
      ),
      aliases: jsonEncode(aliases),
      status: status,
      createdAt: 1000,
      updatedAt: 1000,
    );
  }

  test('#1 空输入 → 三个入口都空', () {
    expect(groupByIdentity(const []), isEmpty);
    expect(identityAliases(const []), isEmpty);
    expect(detectConflictsForFacts(const []), isEmpty);
  });

  test('#2 主名行 + 别名行的跨行矛盾能检出（对照组：不合并则漏检）', () {
    final a0 = a('独生子女状态', '独生子', chapter: 3, timestamp: 100);
    final a1 = a('独生子女状态', '有妹妹', chapter: 15, timestamp: 200);
    final facts = [
      fact('林晚晴', aliases: const ['阿晴'], assertions: [a0]),
      fact('阿晴', assertions: [a1]),
    ];

    // 对照组：直接喂给检测器（**不先合并**）→ 每个角色名下只有一个值，
    // 检测器跨行不比较 → 零观察项。这条断言就是 groupByIdentity 存在的理由。
    final unmerged = detectCharacterConflicts([
      (name: facts[0].name, assertions: [a0]),
      (name: facts[1].name, assertions: [a1]),
    ]);
    expect(unmerged, isEmpty, reason: '不合并 = 漏检，D-1 的别名在 F05 侧落空');

    final grouped = groupByIdentity(facts);
    expect(grouped.length, 1, reason: '「林晚晴」的别名含「阿晴」→ 同一身份');
    expect(grouped.single.assertions.length, 2);

    final result = detectConflictsForFacts(facts);
    expect(result.length, 1);
    expect(result.single.characterName, '林晚晴');
    expect(result.single.description, '第3章「独生子」→ 第15章「有妹妹」');
  });

  test('#3 两个无关人物不误合并', () {
    final facts = [
      fact('林晚晴', aliases: const ['阿晴']),
      fact('沈砚', aliases: const ['沈先生']),
    ];

    final grouped = groupByIdentity(facts);
    expect(grouped.length, 2);
    expect(grouped.map((g) => g.name).toSet(), {'林晚晴', '沈砚'});
    expect(identityAliases(facts).length, 2);
  });

  test('#4 合并后 name 用主名行（active 优先，非首行优先）', () {
    // 行序刻意让「非主名行」排在前：若实现退化成「取首行」，本例会红。
    final facts = [
      fact('阿晴', status: 'merged'),
      fact('林晚晴', status: 'active', aliases: const ['阿晴']),
    ];

    expect(groupByIdentity(facts).single.name, '林晚晴');
    expect(identityAliases(facts).keys.single, '林晚晴');
  });

  test('#5 防御分支：全组无 active → 取首行，不抛不空', () {
    // 脏数据 / 合并中途失败的行态（tables.dart:520 status 仅 active|merged）。
    // R-028 降级路径：静默取首行比让 F05 整块消失代价小。
    final facts = [
      fact('阿晴', status: 'merged'),
      fact('林晚晴', status: 'merged', aliases: const ['阿晴']),
    ];

    expect(groupByIdentity(facts).single.name, '阿晴');
  });

  test('#6 传递闭包：林晚晴=阿晴、阿晴=晚晴 ⇒ 三者一组', () {
    final facts = [
      fact('林晚晴', aliases: const ['阿晴']),
      fact('阿晴', aliases: const ['晚晴']),
      fact('晚晴'),
    ];

    // 「林晚晴」与「晚晴」**没有直接交集**，只能靠并查集的传递闭包并起来。
    final grouped = groupByIdentity(facts);
    expect(grouped.length, 1);
    expect(grouped.single.name, '林晚晴');
    expect(identityAliases(facts).values.single, {'林晚晴', '阿晴', '晚晴'});
  });

  test('#7 别名进合并上下文（identityAliases），但不进检测器的 name', () {
    final facts = [
      fact('林晚晴', aliases: const ['阿晴', '晚晴']),
      fact('沈砚', aliases: const ['沈先生']),
    ];

    final index = identityAliases(facts);
    expect(index['林晚晴'], {'林晚晴', '阿晴', '晚晴'});
    expect(index['沈砚'], {'沈砚', '沈先生'});

    // 若把别名并进 name，§5.4 按「主名 ∪ 别名」匹配 participants 时
    // 别名侧反而命中不到——故检测器的输入里只能有主名（ADR §5.3 勘误 2）。
    expect(groupByIdentity(facts).map((g) => g.name).toList(), ['林晚晴', '沈砚']);
  });

  test('#8 合并不得绕过 F05 判据（stale 断言合并后仍被过滤）', () {
    final facts = [
      fact(
        '林晚晴',
        aliases: const ['阿晴'],
        assertions: [
          a('独生子女状态', '独生子', chapter: 3, timestamp: 100, stale: true),
        ],
      ),
      fact('阿晴', assertions: [a('独生子女状态', '有妹妹', chapter: 15, timestamp: 200)]),
    ];

    expect(
      detectConflictsForFacts(facts),
      isEmpty,
      reason: '合并是为了不漏检真矛盾，不是把幽灵矛盾放进来（D-6）',
    );
  });

  test('#9 fillConflictExcerpts：命中填摘录 / 不命中 null', () {
    final values = [
      a('独生子女状态', '独生子', chapter: 3),
      a('独生子女状态', '有妹妹', chapter: 15),
    ];
    final observation = ConflictObservation(
      characterName: '林晚晴',
      attribute: '独生子女状态',
      orderedValues: values,
      description: '第3章「独生子」→ 第15章「有妹妹」',
    );

    final hit = fillConflictExcerpts([observation], '前文铺垫……独生子……后续');
    expect(hit.single.excerpt, isNotNull);
    expect(hit.single.excerpt, contains('独生子'));

    // 找不到就诚实为 null，不伪造定位（ADR §6「未定位到原文」同一条纪律）
    final miss = fillConflictExcerpts([observation], '毫不相干的正文');
    expect(miss.single.excerpt, isNull);
  });

  test('#10 判据入口输出 = 手写「已合并单角色」输入的输出', () {
    final a0 = a('性格', '冷静', chapter: 1, timestamp: 100);
    final a1 = a('性格', '暴烈', chapter: 8, timestamp: 200);
    final facts = [
      fact('林晚晴', aliases: const ['阿晴'], assertions: [a0]),
      fact('阿晴', assertions: [a1]),
    ];

    // 手写「合并后应有的样子」——把 groupByIdentity 的输出形状钉死：
    // 一行一身份、name 是主名、断言按行序拼接。
    final handMerged = detectCharacterConflicts([
      (name: '林晚晴', assertions: [a0, a1]),
    ]);

    final viaEntry = detectConflictsForFacts(facts);
    expect(viaEntry.length, 1);
    expect(viaEntry.single.characterName, '林晚晴');
    expect(viaEntry.single.orderedValues.map((v) => v.value).toList(), [
      '冷静',
      '暴烈',
    ]);
    expect(
      viaEntry.map((o) => '${o.characterName}|${o.description}').toList(),
      handMerged.map((o) => '${o.characterName}|${o.description}').toList(),
      reason: '对外只暴露判据入口，就是要让「漏掉先合并」这件事无从发生',
    );
  });
}
