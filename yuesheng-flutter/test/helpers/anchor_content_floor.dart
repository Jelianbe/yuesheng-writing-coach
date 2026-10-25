// ─────────────────────────────────────────────────────────────
// 锚点重建下限 · 共用度量（T-20261024-15 · L4 支撑层）
//
// ★ 本文件只放**一件**通用工具：JSON 子树「内容体积（单调代理）」遍历 + 累加。
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
