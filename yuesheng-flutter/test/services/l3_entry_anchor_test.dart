// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// L3 知识库「词条级」行为锚点（字节级）— 补 P3 覆盖缺口
//
// 背景（docs/research/2026-09-13-injection-refinement-guardrail-gaps.md §G-2）：
//   test/snapshots/skill_prompt_anchor.json 的 l3Inject 只覆盖 4 个注入组合
//   （P001 / T001+T008 / P001+P005+T001 / 空），L3 **逐词条正文**无字节级保护。
//   本测试为三类 L3 检索源建立**逐词条**指纹快照（len + FNV-1a 64），
//   任一词条被删/改都会在 diff 里被指名。
//
// 覆盖（检索口径 = 单条 ID 的注入输出，与生产 L3 注入同函数）：
//   syndrome  → getSyndromeContent([id])   （症候词条；kSyndromeIds）
//   technique → getTechniqueContent([id])  （技法词条；kTechniqueShortNames.keys）
//   training  → getTrainingContent([id])   （训练词条；kTrainingSyndromeIds）
//   * 空内容词条（如索引/无对应段）以 len=0 记录，内容新增亦会被捕获。
//
// 快照：test/snapshots/l3_entry_anchor.json（**独立文件**，
//       绝不动 skill_prompt_anchor.json 的现有值）。
// 算法：与 test/services/skill_prompt_anchor_test.dart:196-203 同款
//       （UTF-16 code units 的 FNV-1a 64 位）。
//
// 用法：
//   flutter test test/services/l3_entry_anchor_test.dart
//   UPDATE_SNAPSHOTS=true flutter test test/services/l3_entry_anchor_test.dart
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';

import '../helpers/anchor_content_floor.dart';

const String kL3AnchorPath = 'test/snapshots/l3_entry_anchor.json';

/// FNV-1a 64 位指纹（与 skill_prompt_anchor_test.dart 同款）。
int _fnv1a64(String s) {
  // FNV-1a 64 位偏移基数（14695981039346656037）。项目仅发布 Android、不编译 JS，
  // VM 上 int 即 64 位；改用 BigInt 会改变哈希值 ⇒ 锚点快照全量失配，故保留字面量。
  // ignore: avoid_js_rounded_ints
  var h = 0xcbf29ce484222325;
  for (final cu in s.codeUnits) {
    h ^= cu;
    h *= 0x100000001b3;
  }
  return h & 0x7fffffffffffffff;
}

Map<String, Object> _textAnchor(String s) => {
  'len': s.length,
  'fnv': _fnv1a64(s).toRadixString(16),
};

/// 症候词条 ID（活跃，注册表派生）。
List<String> get _syndromeEntryIds => kSyndromeIds;

/// 技法词条 ID（技法名真源 31 条，排序保证键序稳定）。
List<String> get _techniqueEntryIds =>
    kTechniqueShortNames.keys.toList()..sort();

/// 训练词条 ID（与症候真源同源）。
List<String> get _trainingEntryIds => kTrainingSyndromeIds;

/// 汇总当前全部 L3 词条锚点。
Map<String, Object> _buildCurrent() {
  final syndrome = <String, Object>{};
  for (final id in _syndromeEntryIds) {
    syndrome[id] = _textAnchor(getSyndromeContent([id]));
  }
  final technique = <String, Object>{};
  for (final id in _techniqueEntryIds) {
    technique[id] = _textAnchor(getTechniqueContent([id]));
  }
  final training = <String, Object>{};
  for (final id in _trainingEntryIds) {
    training[id] = _textAnchor(getTrainingContent([id]));
  }
  return {
    'meta': {
      'note': 'L3 知识库词条级行为锚点（字节级：长度 + FNV-1a 指纹）',
      'syndromeCount': syndrome.length,
      'techniqueCount': technique.length,
      'trainingCount': training.length,
    },
    'syndrome': syndrome,
    'technique': technique,
    'training': training,
  };
}

/// 递归 diff（与既有锚点护栏同款）。
List<String> _diff(String path, dynamic a, dynamic b) {
  final out = <String>[];
  if (a is Map && b is Map) {
    final keys = <String>{...a.keys.cast<String>(), ...b.keys.cast<String>()};
    for (final k in keys) {
      out.addAll(_diff('$path.$k', a[k], b[k]));
    }
  } else if (a != b) {
    out.add('$path: ${a ?? '∅'} → ${b ?? '∅'}');
  }
  return out;
}

// ─────────────────────────────────────────────────────────────
// 重建下限判据（T-20261024-15 · L4 支撑层）
//
// 由来：本文件的回读校验只有「每个分节是**非空对象**」（下方
//   `got is! Map || got.isEmpty`）—— 那是 F1 的一半（条数 ≥ 1），
//   **没有 F2（条目叶值非空）也没有 F3（总数 ≥ 旧基线 50%）**：
//   每个词条 `len` 全归 0、只留 39 个键，同样算「非空对象」⇒ 塌陷照样过关。
//
// 口径（`DECISIONS §4-260⑤` 舰长 2026-10-24 23:31 已裁，不得改）：
//   ① 每例**非空** + 总数 ≥ 旧基线 **50%**；② 越限 = **fail**。
//
// 落点只在**重建分支**：比对分支的判据面是「与基线逐条字节级一致」，塌陷基线
//   在那里表现为「当前 ≠ 基线」⇒ 本来就会红。
// ★ 新增的两条判据都在**写盘之前**；既有 F1 回读校验仍在写盘之后（不改它，
//   避免顺手重构）。「分节塌成空对象」这种极端塌陷会先被 F3 的比率下限拦下。
// ─────────────────────────────────────────────────────────────

/// 本快照的三个判据面（分节）。
const List<String> _kSections = ['syndrome', 'technique', 'training'];

/// F2：叶值非空 —— 每条目的 `fnv` 不得为空串。
///
/// ★ F1（每分节条数 ≥ 1）由既有回读校验承担（见本文件重建分支里的
///   `got is! Map || got.isEmpty`），**不在这里重复**。
/// ⚠️ 诚实边界：本文件**不对单个词条的 `len == 0` 报红** —— 文件头注释已声明
///   「空内容词条（如索引 / 无对应段）以 len=0 记录」，那是设计。真正接住
///   「所有词条一起塌陷」的是 F3（体积腰斩）。
void _assertPerEntryNonEmpty(Map<String, Object> current) {
  final emptyFnv = <String>[];
  for (final section in _kSections) {
    final got = current[section]! as Map<String, Object>;
    for (final e in got.entries) {
      final anchor = e.value as Map<String, Object>;
      if ((anchor['fnv']! as String).isEmpty) {
        emptyFnv.add('$section.${e.key}');
      }
    }
  }
  if (emptyFnv.isEmpty) return;
  fail(
    '[l3-anchor] 重建下限不过（F2 叶值非空），**已拒绝写盘**：\n'
    '  F2 空指纹 ${emptyFnv.length} 条：${emptyFnv.take(12).toList()}'
    '${emptyFnv.length > 12 ? ' …' : ''}\n'
    '  ★ 指纹为空串 = 写入侧被改坏（截断 / 换了载体），不是「词条变了」。\n'
    '  排查真因后确需重写基线：UPDATE_SNAPSHOTS=true。',
  );
}

/// 读旧基线的三个分节；返回 `null` = 无可比基线。
///
/// 「不可解析」（非 JSON / 顶层非对象 / 缺分节）一律**默认 fail**（除非显式豁免）：
/// `旧快照损坏 + UPDATE_SNAPSHOTS=true` 是**洗白基线最省力的入口**。
Map<String, dynamic>? _loadBaselineSections(File file, {required bool exists}) {
  if (!exists) return null; // 首次生成：F3 不生效（调用处打告警）
  final raw = file.readAsStringSync();
  String? why;
  // ★ 失败形态标签：多种「基线不可用」共用同一出口，靠它区分。
  var kind = '不可解析';
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    why = '${e.message}（偏移 ${e.offset}）';
  }
  if (why == null) {
    if (decoded is! Map<String, dynamic>) {
      why = '顶层应为 JSON 对象，实际为 ${decoded.runtimeType}';
    } else {
      final missing = <String>[
        for (final s in _kSections)
          if (decoded[s] is! Map) s,
      ];
      if (missing.isNotEmpty) {
        kind = decoded.keys.where((k) => k != 'meta').isEmpty
            ? '顶层只有 meta、缺全部分节'
            : '缺分节';
        why = '缺分节 $missing';
      } else {
        final sections = <String, dynamic>{
          for (final s in _kSections) s: decoded[s],
        };
        if (anchorMeasureVolume(sections).content == 0) {
          // ★ 最隐蔽的一种：分节齐备、但所有 `len` 都是 0 且 `fnv` 为空串。
          //   体积 0 ⇒ 下限 `ceil(0/2) == 0` ⇒ 任何内容都 `≥ 0` ⇒ F3 恒绿（fail-open）。
          //   与「不可解析」同类失效，必须走同一条 fail 通路，**不另造出口**。
          kind = '分节齐备但全零长度';
          why =
              '分节齐备，但内容体积（单调代理）为 0'
              '（所有 `len` 均为 0，且无叶字符串）';
        } else {
          final hollows = findHollowLenFnvFamilies(sections);
          if (hollows.isNotEmpty) {
            kind = '族内全零长度但 fnv 非空';
            why =
                '${hollows.length} 个 len+fnv 节点族族内 len 全 0、fnv 非空'
                '（空壳基线，与「体积为 0」同罪）：${hollows.take(3).join(' / ')}';
          } else {
            return sections;
          }
        }
      }
    }
  }
  final waived =
      (Platform.environment['ALLOW_FLOORLESS_REBUILD'] ?? '') == 'true';
  if (!waived) {
    fail(
      '[l3-anchor] 旧基线不可解析 ⇒ 比率下限无法生效（或：可解析但不可用）：'
      '$kL3AnchorPath\n'
      '  本次形态：$kind\n'
      '  判定依据：$why\n'
      '  ★ 可解析但不可用 = ① 缺分节 ② 顶层只有 `meta` ③ **分节齐备但所有 `len` 均为 0**'
      ' ④ **族内 len 全 0 但 fnv 非空**。\n'
      '    前三者让下限退化为 0、④ 让下限来自非内容量 ⇒ F3 对任何内容恒绿（fail-open），与「文件损坏」同罪。\n'
      '  两条出口：\n'
      '    ① 恢复基线：git checkout -- $kL3AnchorPath\n'
      '    ② 确认要丢弃旧基线：ALLOW_FLOORLESS_REBUILD=true'
      '（会打双重告警，且本次不设任何下限）',
    );
  }
  print(
    '[l3-anchor][告警] 已放弃比率下限：旧基线不可解析或不可用（$kind：$why）'
    '⇒ 本次未做任何比对，这不是校验通过。',
  );
  print('[l3-anchor][告警] 路径：$kL3AnchorPath；本次为「无下限重建」，须人工复核体量。');
  return null;
}

/// F3：总数（**内容体积（单调代理）**）≥ 旧基线 50%。不过即 `fail`（**不写盘**）。
///
/// 口径见 `test/helpers/anchor_content_floor.dart`：叶字符串长度 + 仅 `len` /
/// `length` 键的整数值（本文件的 `len`）；其余整数（`meta` 的各类 `*Count`、
/// 未来可能的 ID）单列 `nonContentInt`，**不计体积**。
/// ⚠️ 该指标**不得当作字节数 / token 成本引用**。
void _assertVolumeFloor(
  Map<String, Object> current, {
  required File file,
  required bool exists,
}) {
  final body = <String, Object>{for (final s in _kSections) s: current[s]!};
  final newMeasure = anchorMeasureVolume(body);
  final newVolume = newMeasure.content;
  final baseline = _loadBaselineSections(file, exists: exists);
  if (baseline == null) {
    if (!exists) {
      print(
        '[l3-anchor][告警] 本次为首次生成，比率下限未生效：$kL3AnchorPath\n'
        '  ★ 首次生成是合法通路，故不拦；但**不静默** —— 否则「删掉旧快照再重冻」'
        '就成了绕过下限的最短路径。\n'
        '  提交前请人工复核该基线的体量是否合理'
        '（本次内容体积（单调代理）$newVolume；'
        '非长度整数（不计体积）${newMeasure.nonContentInt}）。',
      );
    }
    return;
  }
  final baselineMeasure = anchorMeasureVolume(baseline);
  final baselineVolume = baselineMeasure.content;
  final floor = (baselineVolume / 2).ceil();
  if (newVolume < floor) {
    fail(
      '[l3-anchor] 重建内容体积（单调代理）低于比率下限，**已拒绝写盘**：\n'
      '  实际：$newVolume\n'
      '  下限：$floor（旧基线 $baselineVolume 的 50%）\n'
      '  非长度整数（不计体积）：${newMeasure.nonContentInt}'
      '（旧基线 ${baselineMeasure.nonContentInt}）\n'
      '  ★ 键齐但内容腰斩 = 装配塌陷的典型形态（知识库读空 / 检索异常被吞）。\n'
      '  ★ 该指标是「内容体积（单调代理）」，**不得当作字节数 / token 成本引用**。\n'
      '  确为有意的语料缩减须经评审并在 .ai/DECISIONS.md 登记；'
      '确认不设下限时：ALLOW_FLOORLESS_REBUILD=true。',
    );
  }
  print(
    '[l3-anchor] 重建下限通过：内容体积（单调代理）$newVolume ≥ 下限 $floor'
    '（旧基线 $baselineVolume 的 50%）；'
    '非长度整数（不计体积）${newMeasure.nonContentInt}。',
  );
}

// ─────────────────────────────────────────────────────────────
// P003 手册面文本牙（T-20261029-05 · 短链 FID 同形误伤收窄批 · R-027 舰长已批）
//
// 字节级锚点只证「P003 段变了/没变」，不证「变成了什么」：
//   收窄被写回裸禁令、后果句被删、收紧侧被吃掉，len/fnv 同样会变 ⇒ 锚点拦不住方向。
// 本牙打在 getSyndromeContent(['P003']) 切片上，钉住收窄后口径的关键句：
//   牙1 收窄在位 · 牙2 后果句接豁免方向 · 牙3 收紧侧（R-009：放宽不得吃掉真缺陷）·
//   牙4 :242 定义连带收窄 · 牙5 :251 示例理由对齐 · 牙6 裸禁令不得复活（J1 反向面）。
// ★ 只加牙、不新增用例；牙面逐字量见 .ai/reports/2026-10-30-29-05-短链FID同形误伤-报批稿.md §6.1。
// ─────────────────────────────────────────────────────────────
void _p003ManualTeeth() {
  final s = getSyndromeContent(['P003']);
  const mustContain = [
    '不含叙述者代述的他人内心', // 牙1：条件句已收窄（反向写回裸禁令 ⇒ 牙1+牙6 双红）
    '推断归属人物、可错⇒不构成漂移', // 牙2：后果句接到豁免方向
    '叙述者以断定口吻陈述超出感知者认知的事实⇒仍判漂移', // 牙3：收紧侧未被吃掉
    '叙述者代述的他人内心活动', // 牙4：:242 L1 越界点定义连带收窄（J2 第二条）
    '叙述者直接代述他人内心', // 牙5：:251 示例理由连带对齐（J2 第三条）
  ];
  const mustNotContain = [
    '只要不包含他人内心、', // 牙6：裸禁令不得复活（J1 反向面）
  ];
  final missing = [
    for (final t in mustContain)
      if (!s.contains(t)) t,
  ];
  final revived = [
    for (final t in mustNotContain)
      if (s.contains(t)) t,
  ];
  if (missing.isNotEmpty || revived.isNotEmpty) {
    fail(
      '[l3-anchor] P003 手册面文本牙未通过：\n'
      '  缺：${missing.isEmpty ? '∅' : missing.join(' / ')}\n'
      '  裸口径复活：${revived.isEmpty ? '∅' : revived.join(' / ')}\n'
      '  ★ 收窄被写回裸禁令 / 后果句被删 / 收紧侧被吃掉 / :242/:251 残留裸口径。',
    );
  }
}

void main() {
  test('L3 词条级锚点：syndrome / technique / training 逐条字节级不变', () {
    final updating = (Platform.environment['UPDATE_SNAPSHOTS'] ?? '') == 'true';
    final file = File(kL3AnchorPath);
    final exists = file.existsSync();

    // ── fail-closed 守卫（T-20261024-14 B 块；与 -13 B 块同形）────────────
    // 旧写法 `if (updating || !file.existsSync())` 把两件事并成一个分支：
    //   「显式重生成」与「快照缺失」⇒ 快照被误删 / 误移 / 未检出时本用例**照样绿**，
    //   并把当前装配静默写成新基线（此刻 lib 侧若有漂移，基线即被替换成漂移后的值
    //   ⇒ 之后再不会红）。本文件**门禁侧无兜底**（`scripts/` `tool/` `.ai/tools/`
    //   全量 grep 无任何脚本读该快照）⇒ 测试侧是唯一一道。
    // ★ 守卫前置于 _buildCurrent()：否则词条检索里任一环节抛错会先红，
    //   「快照缺失」这个真因会被后者的报错遮住（判据落点须指向缺失本身）。
    if (!exists && !updating) {
      fail(
        '[l3-anchor] 锚点快照缺失：$kL3AnchorPath\n'
        '  ★ 快照文件缺失 = 事故，不是常态（该文件本应随仓库一起检出）。\n'
        '  缺失时**不得**自动生成基线 —— 那等于用「当前行为」重写判据，'
        '任何漂移都会被静默转绿。\n'
        '  先查三因：误删 / 误移 / 未检出'
        '（git status --porcelain、git ls-files test/snapshots/）。\n'
        '  确需重建（基线变更须可对账、须经评审）：\n'
        '    UPDATE_SNAPSHOTS=true flutter test '
        'test/services/l3_entry_anchor_test.dart',
      );
    }

    // 组装确定性自检：同一词条连跑两遍，输出必须一致。
    final probeId = _syndromeEntryIds.first;
    final first = getSyndromeContent([probeId]);
    final second = getSyndromeContent([probeId]);
    expect(first, second, reason: 'L3 检索非确定性');

    final current = _buildCurrent();

    // P003 手册面文本牙（收窄口径在位校验；重冻分支也先过牙 ⇒ 坏文本进不了基线）。
    _p003ManualTeeth();

    if (updating) {
      // ── 基线非退化判据（T-20261024-15 · 重建分支专属）──────────────
      // 顺序：F2（纯内存）→ F3（要读旧基线，含 IO 与「不可解析」分支）。
      // 两者都在 `writeAsStringSync` **之前**；既有 F1 回读校验在写盘之后。
      _assertPerEntryNonEmpty(current);
      _assertVolumeFloor(current, file: file, exists: exists);

      // ── 显式重建通路（UPDATE_SNAPSHOTS=true）──────────────────────────
      // 允许写，但**必须打告警**：本分支不做任何比对，写出的就是新判据。
      // 旧措辞「基线已生成」与正常日志无法区分 ⇒ 重建被误读成「校验通过」。
      final hadSnapshot = exists;
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(current)}\n',
        );
      print(
        '[l3-anchor][告警] UPDATE_SNAPSHOTS=true ⇒ 基线被强制覆盖：'
        '$kL3AnchorPath（syndrome ${_syndromeEntryIds.length} / '
        'technique ${_techniqueEntryIds.length} / '
        'training ${_trainingEntryIds.length} 条）',
      );
      print(
        '[l3-anchor][告警] 本次**未做任何比对**，这不是校验通过；'
        '原快照${hadSnapshot ? '已被丢弃' : '本就不存在（本次为新建）'}。',
      );
      print('[l3-anchor][告警] 提交前必须逐条复核 git diff $kL3AnchorPath。');

      // 回读校验：写入成功 ≠ 写出的是完整基线（截断 / 空文件同样「存在」）。
      final reread = jsonDecode(file.readAsStringSync());
      final written = reread is Map<String, dynamic>
          ? reread
          : const <String, dynamic>{};
      for (final section in const ['syndrome', 'technique', 'training']) {
        final got = written[section];
        if (got is! Map || got.isEmpty) {
          fail(
            '[l3-anchor] 基线写入不完整：section `$section` '
            '${got == null ? '缺失' : '为空或类型错误（${got.runtimeType}）'}',
          );
        }
      }
      expect(file.existsSync(), isTrue);
      return;
    }

    final stored = jsonDecode(file.readAsStringSync());
    final diffs = <String>[
      ..._diff('syndrome', stored['syndrome'], current['syndrome']),
      ..._diff('technique', stored['technique'], current['technique']),
      ..._diff('training', stored['training'], current['training']),
    ];

    if (diffs.isNotEmpty) {
      print('[l3-anchor] 检测到 ${diffs.length} 处 L3 词条字节级漂移：');
      for (final d in diffs.take(40)) {
        print('  - $d');
      }
      if (diffs.length > 40) {
        print('  ... 其余 ${diffs.length - 40} 处省略');
      }
      fail('L3 词条级锚点发生字节级漂移（${diffs.length} 处），见上方 diff。');
    }

    print('[l3-anchor] 比对通过：L3 全部词条与基线字节级一致 ✓');
    expect(diffs, isEmpty);
  });
}
