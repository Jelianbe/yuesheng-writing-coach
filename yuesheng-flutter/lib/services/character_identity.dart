// ─────────────────────────────────────────────────────────────
// character_identity — C78 批次2b：人物身份合并 + F05 判据唯一入口
//
// 病根：character_fact 的唯一键是 UNIQUE(manuscript_id, name)，同一人被 AI 用
// 不同称呼抽出时会落成**多行**（主名行「林晚晴」+ 别名行「阿晴」）。而
// detectCharacterConflicts 是「逐角色逐属性、**跨行不合并**」
// （conflict_detector.dart:56-83 实读确认）——直接喂进去，同一人的断言被拆在
// 两个角色里各自内部比较，**跨行矛盾漏检**，D-1 的别名价值在 F05 侧完全落空。
//
// 对策：先按「主名 ∪ 别名」的交集判定同一性，把多行合并成**一行一身份**再交给
// 检测器；对外只暴露判据入口，杜绝调用方漏掉「先合并」这一环。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import '../data/database/database.dart';
import '../data/repositories/character_fact_repository.dart';
import '../types/character_types.dart';
import 'chat_context_builder.dart';
import 'conflict_detector.dart';

/// 按身份合并人物行 → **一行一身份**的扁平输入。
///
/// 同一性判据：两行的「主名 ∪ 别名」有**交集**即同一人。用并查集取传递闭包——
/// 「林晚晴」=「阿晴」、「阿晴」=「晚晴」可推出「林晚晴」=「晚晴」。
///
/// 输出形状与 [detectCharacterConflicts] 的输入**逐字对齐**：`(name, assertions)`
/// 的扁平列表。检测器跨行不合并，故此处必须并成一行，否则跨行矛盾重新漏检。
///
/// 合并后 `name` 取**主名行**（`status == 'active'` 优先，无则取首行）；
/// 别名**不进** `name`——它留在各自行的 `aliases` 里，供 §5.4 按
/// 「主名 ∪ 别名」匹配事件 participants（若并进 name，别名侧反而匹配不到）。
/// 调用方契约：入参应是 `listCharacters(includeMerged: false)` 的结果（§5.4）。
/// 合并后的源行断言已被拷进目标行，若一并喂进来会双重计入——
/// 检测器按值去重，纯重复不会凭空造矛盾，但没有理由依赖这个巧合。
List<CharacterFactInput> groupByIdentity(List<CharacterFact> facts) =>
    _groupRows(facts).map(_mergeGroup).toList();

/// 主名 → 该身份的**全部称呼**（主名 ∪ 别名），供 §5.4 按 participants 匹配事件。
///
/// 别名刻意**不进** [groupByIdentity] 输出的 `name`——那是检测器的输入形状
/// `(name, assertions)`，检测器不认别名；若把别名并进 name，§5.4 按
/// 「主名 ∪ 别名」匹配时别名侧反而命中不到（ADR §5.3 勘误 2）。
/// 故别名上下文在此**单独**暴露，与 [groupByIdentity] 同源于 [_groupRows]，
/// 两者不可能分叉出「检测算一组、关联算另一组」的错位。
Map<String, Set<String>> identityAliases(List<CharacterFact> facts) => {
  for (final group in _groupRows(facts))
    _primaryOf(group).name: {for (final f in group) ..._identityNames(f)},
};

/// 判据入口：身份合并 + F05 检测。**不碰正文**，两个调用方共用，判据不可能分叉。
///
/// 对外**只暴露本函数**（与 [fillConflictExcerpts]），不允许调用方自行组合
/// groupByIdentity + detectCharacterConflicts——一旦漏掉「先合并」这一环，
/// 就退化成按人物名分组、别名行矛盾重新漏检（批次 3 的 UI 侧尤其容易漏）。
List<ConflictObservation> detectConflictsForFacts(List<CharacterFact> facts) =>
    detectCharacterConflicts(groupByIdentity(facts));

/// 摘录：给观察项填 excerpt。**与判据分离**，由调用方各自决定用哪章正文。
///
/// 刻意不并进 [detectConflictsForFacts]：AI 侧喂的是**当前诊断章节**的正文，
/// 而关键词取 `orderedValues.first.value`（**最早**断言值，往往出自前几章）
/// → 恒为 null。把摘录绑进判据接口 = 让 UI 侧一并继承这个既有缺陷（ADR §5.3）。
List<ConflictObservation> fillConflictExcerpts(
  List<ConflictObservation> observations,
  String content,
) => observations
    .map(
      (o) => ConflictObservation(
        characterName: o.characterName,
        attribute: o.attribute,
        orderedValues: o.orderedValues,
        description: o.description,
        excerpt: findKeywordExcerpt(content, o.orderedValues.first.value),
      ),
    )
    .toList();

/// 一行的身份名集合：主名 + 别名（去空）
Set<String> _identityNames(CharacterFact fact) {
  final names = <String>{fact.name};
  names.addAll(_parseAliases(fact.aliases).where((a) => a.isNotEmpty));
  return names;
}

/// 合并一个身份组 → 单个 input。
///
/// 断言**按行序拼接、不去重**——去重是检测器的职责（它按「值」去重、取最早
/// 两个）；此处若先去重，会篡改「最早」的判定，把真矛盾洗成单值。
CharacterFactInput _mergeGroup(List<CharacterFact> group) {
  final assertions = <CharacterAssertion>[];
  for (final f in group) {
    assertions.addAll(CharacterFactRepository.parseAssertions(f.assertions));
  }
  return (name: _primaryOf(group).name, assertions: assertions);
}

/// 主名行：`status == 'active'` 优先（`CharacterFact.status` 仅 active | merged，
/// 见 tables.dart:520）。合并后源行是 merged、目标行是 active，故取到的必是目标行。
///
/// 全组无 active（脏数据 / 合并中途失败）→ 退回首行：**不抛、不返回空**，
/// 这是 R-028 降级而非主流程，静默取首行比让 F05 整块消失代价小。
CharacterFact _primaryOf(List<CharacterFact> group) {
  for (final f in group) {
    if (f.status == 'active') return f;
  }
  return group.first;
}

/// 按身份归组 → 每组的**原始行**（合并上下文，保留 aliases 供 §5.4 事件关联）
List<List<CharacterFact>> _groupRows(List<CharacterFact> facts) {
  final union = _IdentityUnion(facts.length);
  final nameToIndex = <String, int>{};
  for (var i = 0; i < facts.length; i++) {
    for (final name in _identityNames(facts[i])) {
      final first = nameToIndex.putIfAbsent(name, () => i);
      if (first != i) union.union(first, i);
    }
  }
  final groups = <int, List<int>>{};
  for (var i = 0; i < facts.length; i++) {
    groups.putIfAbsent(union.find(i), () => []).add(i);
  }
  return [
    for (final ids in groups.values) [for (final i in ids) facts[i]],
  ];
}

/// 别名 JSON 数组（`TEXT NOT NULL DEFAULT '[]'`，批次 1 加）
List<String> _parseAliases(String raw) {
  if (raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList();
  } catch (_) {
    return const [];
  }
}

/// 并查集：把「主名 ∪ 别名有交集」的行归为同一身份。
///
/// 独立类（**真分解**，非 `part` / `extension` 机械拆分——AGENTS.md 明列后者为伪拆分）。
class _IdentityUnion {
  _IdentityUnion(int size) : _parent = List<int>.generate(size, (i) => i);

  final List<int> _parent;

  int find(int i) {
    var root = i;
    while (_parent[root] != root) {
      root = _parent[root];
    }
    while (_parent[i] != root) {
      final next = _parent[i];
      _parent[i] = root;
      i = next;
    }
    return root;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) _parent[rb] = ra;
  }
}
