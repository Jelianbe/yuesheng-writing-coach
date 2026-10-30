// ─────────────────────────────────────────────────────────────
// 锚点重建下限 · 共用度量（T-20261024-15 · L4 支撑层）
//
// ★ 本文件放**两件**通用工具：
//   ① JSON 子树「内容体积（单调代理）」遍历 + 累加（`anchorMeasureVolume`）；
//   ② 空壳 len+fnv 族扫描（`findHollowLenFnvFamilies`，T-20261030-05）。
//   三条判据（F1 每例条数 / F2 叶值非空 / F3 比率下限）**留在各自锚点测试文件里**
//   —— 四份快照的 schema 互不相同（消息序列 / 长度+指纹分节 / 结构化决策树 /
//   长度+指纹词条），把它们统一成一套判据 = 伪抽象：下一份新快照接入时会被
//   「看起来已覆盖」骗过去。
//
// ## ★ 这不是字节数，也不是 token 数（命名纪律 · 主理人 2026-10-25 裁）
//
// 本指标叫「**内容体积（单调代理）**」：它唯一保证的性质是**内容塌陷时单调下降**，
// 用途只有一个 —— 给「重建出的基线是不是空壳」提供一个可比的量。
//
// **不得当作字节数 / token 成本引用。** 两条实测理由：
//   ① 它把「叶字符串长度」与 `len` / `length` 的整数值相加，而后者本身就是某段
//      原文的字符数（原文不在快照里，`len` 是它的替身）⇒ 同一个 prompt 被算两遍。
//   ② `skill_prompt_anchor.json` 里 **14 个节点同时含 `len` 与 `tokens`，且 14/14
//      恒等**（`estimatedTokens => content.length`，`DECISIONS §4-265⑦`）
//      ⇒ `tokens` **一个字都不计**（计了就是三计）。
//   ⇒ 要引用成本，请用 `tool/check_prompt_volume.py` 的读数，不用本函数。
//
// ## 为什么要量「体积」而不是「键数」
//
// 双向键集合判据（T-20261024-14 A 块）已经管住「键齐 / 键多 / 键少」；塌陷基线的
// 形态是 **键齐但内容为空**（每例返回空序列 / DB fixture 失效 / 注入装配异常被
// catch 吞掉）⇒ 只有量内容体量才看得见。
//
// ## ★ 为什么叶字符串与 `len` 都要计（对主理人 3.1 原口径的修正，已获采纳）
//
// 三份快照是「长度 + 指纹」schema（`{len, fnv}` / `{length, hash}`），**不存原文**。
// 只累加叶字符串时，量到的是 role / fnv 这类**定长附属字段**：
//
//   实测（`test/snapshots/message_sequence_anchor.json`，2026-10-25）：
//     9 例 / 39 条消息，叶字符串合计 **820 字符**（role + fnv；**排除 `meta`**；
//     含 `meta.note` 则为 **843**，差 23 = note 长度）。
//     「条数不变、每条 content 清空」时这 820 字符**一个字节都不变**
//     ⇒ 纯字符串口径的比率恒 100%，**永远绿**（对该形态零鉴别力）。
//     把 `len` 一并计入后，同一场景从 **530,774** 掉到 **820**（≈0.15%）⇒ 能红。
//
// ## ★ 只认 `len` / `length` 两个键名（防「大常数稀释」，主理人 2026-10-25 要求）
//
// 不是「任何叶整数都算体积」：将来谁往快照里加一个时间戳 / 自增 ID，总体积立刻被
// 它撑大 ⇒ 塌陷时比率仍 > 50% ⇒ **判据静默失效**，而且很难想到是这个原因。
// ⇒ 只有键名为 `len` / `length` 的整数计入 `content`；其余整数（`tokens`、
//   `violationCount`、`syndromeCount`、未来的时间戳…）一律进 `nonContentInt`，
//   **不计体积**，但**打印出来给人看**（读数可见，不静默丢弃）。
// ⇒ `tokens` 明确不计：它与 `len` 恒等（见上 ②），计入即双计。若某快照将来只有
//   `tokens` 没有 `len`，读数会掉一半 —— 由各文件自己的结构自检兜住
//   （`skill_prompt_anchor_test.dart` 有「`len` 与 `tokens` 必须相等」的恒等断言，
//   口径变动时会先红）。
// ─────────────────────────────────────────────────────────────

/// 计入「内容体积」的整数键名（**唯一白名单**，别按需扩张）。
const Set<String> kContentLengthKeys = {'len', 'length'};

/// 内容体积（单调代理）读数。
///
/// - `content`：叶字符串长度 + 键名为 `len` / `length` 的整数值。
///   **只用于「塌陷前后是否单调下降」，不得当作字节数 / token 成本。**
/// - `nonContentInt`：其余叶整数之和（`tokens` / `violationCount` / 时间戳…）。
///   **不计入** `content`，只把它显示在读数里，避免「静默丢弃」。
typedef AnchorVolume = ({int content, int nonContentInt});

/// 递归累加一个 JSON 子树的内容体积（单调代理）。
///
/// 入参可以是 `jsonDecode` 的结果（`Map` / `List` / `String` / `int` /
/// `double` / `bool` / `null`），也可以是测试里刚构造的同形 `Map`。
/// 键名本身不计（键名长度与内容塌陷无关，收进来只会稀释比率）。
AnchorVolume anchorMeasureVolume(Object? node) {
  final acc = _VolumeAcc();
  _walkVolume(node, acc, null);
  return (content: acc.content, nonContentInt: acc.nonContentInt);
}

class _VolumeAcc {
  int content = 0;
  int nonContentInt = 0;
}

void _walkVolume(Object? node, _VolumeAcc acc, String? key) {
  if (node is String) {
    acc.content += node.length;
    return;
  }
  if (node is int) {
    // ★ 只有「语义上是长度」的键才计体积；其余整数单独记账，不进 content。
    if (key != null && kContentLengthKeys.contains(key)) {
      acc.content += node;
    } else {
      acc.nonContentInt += node;
    }
    return;
  }
  if (node is Map) {
    for (final e in node.entries) {
      final k = e.key;
      _walkVolume(e.value, acc, k is String ? k : null);
    }
    return;
  }
  if (node is List) {
    for (final v in node) {
      _walkVolume(v, acc, key);
    }
    return;
  }
  // null / bool / double（`confidence` 一类的比率量）：不随内容塌陷变化，不计体积。
}

// ─────────────────────────────────────────────────────────────
// 空壳 len+fnv 族扫描（T-20261030-05 · 与 python 侧 T-20261025-07
// `_check_hollow_families` 同判据族，异层：python 读落盘快照，dart 在重冻路径上
// 先于写盘拦）。
//
// ## 判据
//
// 族 = 容器（Map / List）中 **≥2 个孩子**是 `{len:int, fnv:String}` 形节点。
// 族内**所有 `len == 0` 且存在非空 `fnv`** ⇒ 空壳基线（与「体积为 0」同罪）：
// 此时体积仍 > 0（`role` / `fnv` 叶串贡献，message_sequence 实测 820）⇒
// `floor = ceil(820/2) = 410` ⇒ 内容全空也 `820 ≥ 410` ⇒ F3 恒绿（fail-open）。
//
// ## 覆盖边界（2026-10-30 主理人审查实测补登 · E1）
//
// 本网接线在 **5 个读取方**，但**判别力只有 3 个** —— 另 2 份快照的 schema 里
// 根本没有 `{len:int, fnv:String}` 形节点，调用恒返回空 = 那里的牙**永不红**：
//
// | 快照 | len+fnv 形节点 | 本网 |
// |:--|--:|:--|
// | `skill_prompt_anchor.json` | 59 | ✅ 有牙（V7 实测：len 全置 0 ⇒ `root.prompt` 等 4 族红）|
// | `l3_entry_anchor.json` | 110 | ✅ 有牙 |
// | `message_sequence_anchor.json` | 44 | ✅ 有牙 |
// | `injection_segments_anchor.json` | 10 | ✅ 有牙 |
// | `prompt_const_anchor.json` | 4 | ✅ 有牙 |
// | `student_profile_anchor.json` | **0**（是 3 个 `{hash, length}`） | ⚪ 恒不红 —— 已登记另卡裁定（T-20261030-05 完成标记）|
// | `teaching_loop_snapshot.json` | **0**（47 例结构化决策树，无长度/指纹形节点） | ⚪ 恒不红 —— **本行是本次审查新增登记**（原卡只写了 student_profile）|
//
// ⇒ 「5 读取方」是**接线数**，不是**看守面**。前一份快照由 `length`/`hash` 形空壳
// 塌陷时，本网看不见；那两份的 F3 由 F1（每例条数）+ F2（叶值非空）兜，**不是**由本网兜。
// 判据出处：`.ai/reports/2026-10-30-审查-F3空壳族负向验证.dart` 的 V7 组读数
// （正臂 R1 = 7 份真实快照全不红；反臂 V7 = 把 len 全置 0 后逐份应有红）。
//
// ## 合法例外（防误红，与 python 侧逐字对齐）
//
// **单节点** len=0 + fnv 非空是合法空串形态（`l3Inject.empty` /
// `injection_segments` nofulltext.fullTextBlock，fnv=`4bf29ce484222325`
// = 空串 FNV 指纹）——族需 ≥2 个形孩子，单节点不成族；族内另有 len>0 兄弟
// ⇒ 不构成「全零」。
// ─────────────────────────────────────────────────────────────

/// 扫描 `root` 子树，返回**违规族**的可读路径列表（空 = 无空壳族）。
///
/// 违规族 = 族内所有 `len == 0` 且至少一个 `fnv` 非空。
List<String> findHollowLenFnvFamilies(Object? root) {
  final families = <_ShapedFamily>[];
  _collectShapedFamilies(root, 'root', families);
  final violators = <String>[];
  for (final f in families) {
    final lens = f.members.map((m) => m['len'] as int).toList();
    final fnvs = f.members.map((m) => m['fnv'] as String).toList();
    if (lens.every((l) => l == 0) && fnvs.any((f) => f.isNotEmpty)) {
      violators.add('${f.path}（${f.members.length} 节点族）');
    }
  }
  return violators;
}

class _ShapedFamily {
  final String path;
  final List<Map<String, dynamic>> members;
  const _ShapedFamily(this.path, this.members);
}

void _collectShapedFamilies(
  Object? node,
  String path,
  List<_ShapedFamily> out,
) {
  if (node is Map) {
    final shaped = <Map<String, dynamic>>[];
    final others = <MapEntry<Object?, Object?>>[];
    for (final e in node.entries) {
      final v = e.value;
      if (v is Map && v['len'] is int && v['fnv'] is String) {
        shaped.add(Map<String, dynamic>.from(v));
      } else {
        others.add(e);
      }
    }
    if (shaped.length >= 2) out.add(_ShapedFamily(path, shaped));
    for (final e in others) {
      final k = e.key;
      _collectShapedFamilies(e.value, '$path.$k', out);
    }
  } else if (node is List) {
    final shaped = <Map<String, dynamic>>[];
    for (var i = 0; i < node.length; i++) {
      final v = node[i];
      if (v is Map && v['len'] is int && v['fnv'] is String) {
        shaped.add(Map<String, dynamic>.from(v));
      } else {
        _collectShapedFamilies(v, '$path[$i]', out);
      }
    }
    if (shaped.length >= 2) out.add(_ShapedFamily(path, shaped));
  }
}
