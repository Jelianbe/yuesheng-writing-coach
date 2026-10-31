// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// v2_action_table_filter_test — T-20261031-17（F9）
//
// 目的：钉住「**不可诊断症候的 v2 动作映射表行在注入点被剔除、库常量逐字节不动**」
//       这一条不变式（N1–N5）。配套改动见报批稿
//       `.ai/reports/2026-10-31-报批稿-31-17-F9-P031退出v2映射表.md` §2.0。
//
// ★★ 为什么本文件**不含任何 `test(...)` 用例**（例集指纹锁 · 实测）
//
//   门禁 2 的例集指纹 = 全量 `testStart` 用例名**排序去重**后的 sha256 前 16 位
//   （`scripts/lib_gate_evidence.sh` 的 `_ev_suite_fingerprint`）。
//   新增**任何一个新用例名** ⇒ 指纹变 ⇒ 门禁 2 直接红：
//     "[FAIL] P2 例集：指纹 <新> ≠ 基线 5d08bb1f550babaa ⇒ 例集变了"。
//   本批明令「**不重钉** `tool/test_count_baseline.json`（5466）」⇒ 只能零新用例名。
//   ⇒ 断言写在 `main()` 里直接执行：**无 `test()` ⇒ 无新用例名 ⇒ 指纹输入不变**。
//
//   ★ 为何不用 `expect()`：`expect` 在**测试体外**会抛 `OutsideTestException`
//     （本机实测：连**通过**的 `expect(1, 1)` 也抛，报告形如
//     "Failed to load … : Instance of 'OutsideTestException'"）
//     ⇒ 本文件改用本地 `_require(bool, String)`，不通过即抛 `StateError`。
//
//   ★ 失败形态：任一断言不通过 ⇒ 本文件**加载失败** ⇒ `flutter test` rc=1
//     （门禁 2 红）。通过时本文件 0 用例，报告如实显示 "no tests" ——
//     同仓先例 `test/services/syndrome_merge_map_test.dart`（刻意 0 用例，
//     不放 `expect(true, isTrue)` 之类假绿占位）。
//
// ── 判据分工（与卡 §四 / 报批稿 §6.1 对齐）─────────────────────────
//
//   N1 断言层（正向 · 有牙）：7 个渲染面各**切片**出「动作-症候参考映射」表体，
//      断言切片内 `P031` 逐字为零。**必须切片**：实测（E1）`training_yuesheng` /
//      `advanced_sensei` / `advanced_p4_yuesheng` / `p3_yuesheng_advanced`
//      四个面的**整条** prompt 仍含 `P031`（来自别处），整条数 ID 会恒红不可绿。
//   N2 负对照（硬判据 · 优先于正向）：注册表不删 / 库常量不删行 /
//      force 组逐字节不变 / 快照里的库常量等值钉。
//   N3 明示例外：症名「题材边界感缺失」留在 A003/A007 两条 `**适用**：` 行内，
//      库常量内**恰 3 次**（1 次 v2 表行 + 2 次适用行）—— `#10` 对称差的结构性强制。
//   N4 连通性（源码文本断言 · 形态：签名存在性 + 缺席断言）：
//      `skill_dispatcher.dart` 的 `_buildL2Chunks` 内
//      `chunks.add(excludeNonDiagnosableActionRows(content));`（两要素同现）
//      且裸形态 `chunks.add(content);` **0 处**。
//   N5 落点合规：排除逻辑**不得**漏进库常量生成处
//      （`skills_training_p4.dart` / `skill_registry.dart` 内不得出现
//      `kNonDiagnosableSyndromeIds`，且 v2 表生成表达式逐字未改）。
//      ★ 报批稿 §6.1 的 N5 原文是「落地提交的 `git diff --stat` 判据」——
//        **提交态**的判据无法写成常驻测试（提交后 `git diff` 恒空 ⇒ 恒红）。
//        故测试内以**行为等价**的三条承担：库常量仍含 P031 行（N2②）+
//        注入面已剔除（N1）+ 库常量生成处无排除逻辑（本判据）；
//        `git diff --stat` 判据在**施工期**以命令留痕（见施工报告 §2）。
//
// ── 本文件不做的事 ─────────────────────────────────────────────────
//   · 不新增用例名（见上）⇒ 不改 `tool/test_count_baseline.json`。
//   · 不改 `four_libraries_consistency_test.dart` 的任何期望集合。
//   · 不声称「P031 已不报」—— 行为层未采样（无 API key），本文件只管注入面。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// v2 动作映射表小节锚（`skills_training_p4.dart:253`，小节位于该 skill 正文**末尾**）。
const String _kSectionAnchor = '## 动作-症候参考映射（非强制）';

/// chunk 之间的分隔符（`skill_dispatcher.dart` 的 `_kSkillSeparator`）。
/// 小节止于本 skill chunk 末尾 ⇒ 切片终点 = 下一个分隔符。
const String _kChunkSeparator = '\n\n---\n\n';

/// P031 的 v2 表行（逐字，40 字符；由 `_actionRow` 渲染）。
const String _kP031Row = '| P031 题材边界感缺失 | A007 一句话冲突 | A003 五问法 |';

/// P031 症名（留在 A003/A007 两条 `**适用**：` 行内，N3 的明示例外）。
const String _kP031Name = '题材边界感缺失';

/// force 组红线（负对照：该组 `loadedSkillIds` 不含 `coaching-actions-v2`）。
const int _kForceLen = 66306;
const String _kForceFnv = '37644edbf2af71a8';

/// 库常量等值钉（N2④；值来源 = 重冻后的 `skill_prompt_anchor.json`）。
const int _kV2ConstLen = 3847;
const String _kV2ConstFnv = '46dec3e2b4b76fd';

/// 剔除后表体应剩的行数（注册表 39 条 − P031 1 条）。
const int _kExpectedRowCount = 38;

/// 一个渲染面（ctx → 装配后的 system prompt）。
class _Surface {
  final String name;
  final SkillLoadContext ctx;
  const _Surface(this.name, this.ctx);
}

/// 7 个携带 `coaching-actions-v2` 的渲染面。
///
/// 前 6 个 = `skill_prompt_anchor.json` 的 6 个 `prompt` 键；
/// 第 7 个 = `message_sequence_anchor.json` 的 `p3_yuesheng_advanced`
/// （严丝合 `06` 稿 Q4 发现：不在 14 个 prompt 键里，但在消息序列快照里）。
const List<_Surface> _kSurfaces = [
  _Surface(
    'diagnosis_p1_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p1World,
      attitude: AttitudeLevel.yuesheng,
    ),
  ),
  _Surface(
    'diagnosis_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p2PracticeLoop,
      attitude: AttitudeLevel.yuesheng,
      subphase: TeachingSubphase.diagnosis,
    ),
  ),
  _Surface(
    'training_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p2PracticeLoop,
      attitude: AttitudeLevel.yuesheng,
      subphase: TeachingSubphase.practice,
    ),
  ),
  _Surface(
    'advanced_sensei',
    SkillLoadContext(
      phase: TeachingPhase.p3Training,
      attitude: AttitudeLevel.sensei,
    ),
  ),
  _Surface(
    'advanced_p4_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p4Review,
      attitude: AttitudeLevel.yuesheng,
    ),
  ),
  _Surface(
    'outline_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p2PracticeLoop,
      attitude: AttitudeLevel.yuesheng,
      isOutlineContext: true,
    ),
  ),
  _Surface(
    'p3_yuesheng_advanced',
    SkillLoadContext(
      phase: TeachingPhase.p3Training,
      attitude: AttitudeLevel.yuesheng,
    ),
  ),
];

/// 负对照面：force=true 的 beginner 组（`loadedSkillIds` 不含 `coaching-actions-v2`）。
const SkillLoadContext _kForceCtx = SkillLoadContext(
  phase: TeachingPhase.p3Training,
  attitude: AttitudeLevel.yuesheng,
  isBeginner: true,
  forceDiagnosisSceneFirst: true,
);

/// 断言失败即抛 `StateError`（`expect` 在测试体外不可用，见文件头）。
void _require(bool ok, String message) {
  if (!ok) {
    throw StateError('[31-17] $message');
  }
}

/// FNV-1a 64 位（与锚点测试同口径：UTF-16 码元 + 64 位回绕 + 末位 `& 0x7fff…`）。
int _fnv1a64(String s) {
  // ignore: avoid_js_rounded_ints
  var h = 0xcbf29ce484222325;
  for (final cu in s.codeUnits) {
    h ^= cu;
    h *= 0x100000001b3;
  }
  return h & 0x7fffffffffffffff;
}

/// 切出「动作-症候参考映射」表体（起锚 = 小节标题，止锚 = 下一个 chunk 分隔符）。
String _sliceV2Section(String prompt, String surfaceName) {
  final start = prompt.indexOf(_kSectionAnchor);
  _require(
    start >= 0,
    '$surfaceName: 注入面里找不到「$_kSectionAnchor」小节 ⇒ 切片失配（不是「已剔除」）',
  );
  final end = prompt.indexOf(_kChunkSeparator, start);
  final slice = prompt.substring(start, end < 0 ? prompt.length : end);
  _require(
    slice.length >= 200,
    '$surfaceName: 切片长度 ${slice.length} < 200 ⇒ 锚点失配下的空切片假绿',
  );
  return slice;
}

/// N1（正向 · 有牙）：7 个渲染面的 v2 表体内 `P031` 逐字为零。
void _checkN1() {
  for (final s in _kSurfaces) {
    final prompt = buildSystemPromptV2(s.ctx).systemPrompt;
    final slice = _sliceV2Section(prompt, s.name);
    _require(!slice.contains('P031'), '${s.name}: v2 映射表切片内仍出现 P031 ⇒ 剔除未生效');
    _require(
      !slice.contains('| P031 '),
      '${s.name}: v2 映射表切片内仍出现「| P031 |」行形态',
    );
    // 表体完整性（防「整表被删空」式假绿）：应恰剩 38 条映射行。
    final rows = RegExp(
      r'^\| P\d{3} ',
      multiLine: true,
    ).allMatches(slice).length;
    _require(
      rows == _kExpectedRowCount,
      '${s.name}: 表体映射行数 $rows ≠ $_kExpectedRowCount ⇒ 表被整段删空或行集合异常',
    );
  }
}

/// N2（负对照 · 防越界）：注册表不删 / 库常量不删行 / force 组逐字节不变 / 库常量等值钉。
void _checkN2() {
  // ① 注册表真源不动（P031 仍带首选动作 A007 / 备选 A003）。
  final record = syndromeRecordOf('P031');
  _require(record != null, 'N2① 注册表里 P031 消失 ⇒ 越界（改了真源）');
  _require(
    record!.actions.join(',') == 'A007,A003',
    'N2① P031.actions 被改成 ${record.actions} ⇒ 越界',
  );

  // ② 库常量不删行：v2 skill 正文仍含 P031 行；L2 索引常量仍含 P031。
  final v2Const = skillRegistry['coaching-actions-v2']!.content;
  _require(
    v2Const.contains(_kP031Row),
    'N2② 库常量 coaching-actions-v2 里 P031 行消失 ⇒ 过滤落到了常量生成处（撞 R-027 铁律 5）',
  );
  _require(
    kSyndromeIndexContent.contains('P031'),
    'N2② 库常量 kSyndromeIndexContent 里 P031 消失 ⇒ 库常量被删行',
  );

  // ③ force 组逐字节不变（该组不携带 coaching-actions-v2 ⇒ 天然负对照）。
  final force = buildSystemPromptV2(_kForceCtx).systemPrompt;
  _require(
    force.length == _kForceLen,
    'N2③ force 组 len = ${force.length} ≠ $_kForceLen ⇒ 过滤打到了不该碰的面',
  );
  final forceFnv = _fnv1a64(force).toRadixString(16);
  _require(
    forceFnv == _kForceFnv,
    'N2③ force 组 fnv = $forceFnv ≠ $_kForceFnv ⇒ 过滤打到了不该碰的面',
  );

  // ④ 库常量为常量：快照里的 `skillContent['coaching-actions-v2']` 等值钉。
  final snapshot =
      jsonDecode(
            File('test/snapshots/skill_prompt_anchor.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final skillContent = snapshot['skillContent'] as Map<String, dynamic>;
  final v2Entry = skillContent['coaching-actions-v2'] as Map<String, dynamic>;
  _require(
    v2Entry['len'] == _kV2ConstLen && v2Entry['fnv'] == _kV2ConstFnv,
    'N2④ 库常量快照漂移：$v2Entry（应 $_kV2ConstLen / $_kV2ConstFnv）',
  );
}

/// N3（明示例外）：症名留在两条 `**适用**：` 行内，库常量内恰 3 次。
void _checkN3() {
  final v2Const = skillRegistry['coaching-actions-v2']!.content;
  final hits = RegExp(RegExp.escape(_kP031Name)).allMatches(v2Const).length;
  _require(
    hits == 3,
    'N3 库常量内「$_kP031Name」实为 $hits 次（应恰 3 次 = 1 次 v2 表行 + 2 次适用行）',
  );
}

/// N4（连通性 · 源码文本断言）：注入点接上了剔除函数，且裸形态 0 处。
void _checkN4() {
  final src = File('lib/services/skill_dispatcher.dart').readAsStringSync();
  final start = src.indexOf('void _buildL2Chunks(');
  _require(start >= 0, 'N4：找不到 _buildL2Chunks');
  // 结束锚用独立闭括号行（`\n}\n`），不用 `\n}`（会在参数表/嵌套处提前截断）。
  final end = src.indexOf('\n}\n', start);
  final region = src.substring(start, end < 0 ? src.length : end + 2);
  _require(
    region.contains('chunks.add(excludeNonDiagnosableActionRows(content));'),
    'N4：_buildL2Chunks 内未见 `chunks.add(excludeNonDiagnosableActionRows(content));`'
    '（实参未接上剔除函数）',
  );
  _require(
    !region.contains('chunks.add(content);'),
    'N4：_buildL2Chunks 内仍存在裸形态 `chunks.add(content);`',
  );
}

/// N5（落点合规）：排除逻辑不得漏进库常量生成处。
void _checkN5() {
  final p4 = File('lib/services/skills_training_p4.dart').readAsStringSync();
  _require(
    !p4.contains('kNonDiagnosableSyndromeIds'),
    'N5：排除逻辑漏进了库常量生成处 skills_training_p4.dart ⇒ 变相改库常量',
  );
  _require(
    p4.contains(r"kSyndromeRegistry.map(_v2ActionRow).join('\n')"),
    'N5：v2 表生成表达式被改（skills_training_p4.dart）⇒ 库常量不再是全表',
  );
  final registry = File('lib/services/skill_registry.dart').readAsStringSync();
  _require(
    !registry.contains('kNonDiagnosableSyndromeIds'),
    'N5：排除逻辑漏进了 skill_registry.dart ⇒ 变相改库常量',
  );
}

void main() {
  _checkN1();
  _checkN2();
  _checkN3();
  _checkN4();
  _checkN5();
  print(
    '[31-17] v2 动作映射表过滤判据全绿：7 个渲染面切片内 P031 逐字为零 · '
    '库常量 3847/$_kV2ConstFnv 不动 · force 组 $_kForceLen/$_kForceFnv 不动 · '
    '症名保留 $_kP031Name ×3',
  );
}
