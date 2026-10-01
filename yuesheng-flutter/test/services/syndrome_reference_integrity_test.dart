// ─────────────────────────────────────────────────────────────
// 症候「引用完整性」全域校验（2026-09-30 · 舰长裁定「现在开工」）
//
// 由来：0.3.6「聚类去重 + 全仓重编号」在 208 个文件里留下一批
// 「新 ID + 已死旧名」残留（如 `**适用症候**：P012 伏笔失效症`）。
// P0-A 修掉其中 14 处，并在 four_libraries_consistency_test.dart 补了
// #13/#14/#15/#16 —— 但那四条只跑在 **7 个内容常量** 上
//   kSyndromeIndexContent / kSyndromeManualContent / kTechniqueIndexContent /
//   kTechniqueLibraryContent / kTrainingFullKnowledge / kTrainingFewShotLibrary /
//   coaching-actions-v2
// 而症候 ID 实测分布在 lib/ 的 **37 个文件 / 869 处**（全库共 445 个 .dart）。
//
// 本文件把两条判据**全域化**到 lib/**/*.dart，并补上既有护栏缺的三件事：
//   R1 全域「ID↔名字」一致性
//   R2 全域「ID 存在性」（悬空 ID 为零）
//   R3 载体矩阵：每个活跃 ID 在各载体「要么齐、要么按声明一致地无」
//   R4 阳性对照：三条扫描器必须**真命中**（防正则静默失效 ⇒ 零命中假绿）
//
// 三条实测依据（详见 `.ai/reports/2026-09-30-积木化与症状开关-评估.md` §4①）：
//
// ① 全域语料：lib/ 共 **445** 个 .dart（其中 37 个携带症候 ID、20 个携带「ID+名」）。
//    现状基线（2026-09-30 实测；**两套独立实现逐字一致** —— 见 `.ai/reports/2026-09-30-引用完整性-交叉验证.py`）：
//      • R1「ID+名」命中 **321 处**，错配 **0**  ⇒ 内容层当前是干净的，
//        本护栏守的是**将来**（下一次整合漏一处即红）。
//      • R2 ID 出现 **869 处**（去重 51 个），悬空 **0**。
//
// ② #13 的正则要求名字**以「症」结尾**，但注册表 33 条里有 **8 个名字不含「症」**：
//    P001 情绪标签化 / P003 视角漂移 / P004 节奏停滞 / P005 句式节奏单一 /
//    P006 语言堆砌 / P007 角色空心化 / P008 OC 平面化 / P018 重复用词/基础语病
//    ⇒ 全域口径下该规则只命中 **144** 处，而并集命中 **321** 处（**漏 177 处 = 55%**）。
//    本文件取**双规则并集**：
//      A（ID + 以「症」结尾的名字）—— 抓「新 ID + **已死旧名**」
//      B（ID + 注册表别名字面量）—— 抓「新 ID + **错的活名**」
//    两者**互补**，实测微验证（见 `.ai/reports/2026-09-30-引用完整性-交叉验证.py`）：
//      `P012 伏笔失效症`（已删名）⇒ A 命中、B 不命中（B 的别名宇宙不含已删名）
//      `P024 情绪标签化`（错的活名）⇒ B 命中、A 不命中（不含「症」，A 够不着）
//    变异 M1/M2 分别实证两条都真的在拦（见下「已验证」）。
//
// ③ `honest_affordance_guard_test.dart` 的「行首是 // 或 * 即豁免」在**内容型文件**上
//    会**误豁免**：lib/ 实测有 **12 处**命中落在 markdown 粗体行
//    （`**适用症候**：P002 信息倾泻症`），首字符恰是 `*` —— 而其中一处
//    （`technique_kb_content_lib_3.dart:100`）正是 0.3.6 的真实残留点。
//    ⇒ 本文件改用**逐字符词法剥离**（注释 / 字符串 / 代码），不用行首启发式。
//    （反向也成立：不做剥离则注释里的历史留痕会误报，实测 3 处 ——
//     `manual_2.dart:15`「P035 对话注水症 已并入 P009」等，都是**合法留痕**。）
//
// 已验证（2026-09-30，`.ai/reports/2026-09-30-引用完整性-变异验证.py` · 六轮实跑）：
//   基线绿 → M1 新ID+已死旧名 ⇒ R1 红 → M2 新ID+错的活名 ⇒ R1 红
//   → M3 插入 P099 ⇒ R2 红 → M4 注释里的旧名 ⇒ **绿**（豁免生效）→ 还原后复绿。
//
// 已知边界（诚实声明，勿当全知）：
//   • 只扫 `lib/`。test/ 是**自证**的（名字写错即该用例红），且实测只有 24 处。
//   • 不覆盖「既不以症结尾、又不是任何注册表名字」的自造名 —— 与普通中文无法区分。
//   • 只做**静态文本**判据，不验语义（「这条症候该不该存在」是另一层问题）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';

// ═══ 一、词法剥离：注释 vs 字符串 ═══════════════════════════════

enum _Zone { code, line, block, str }

/// 与 [s] 等长的区域掩码（逐字符标注）。
List<_Zone> _zoneMask(String s) {
  final m = List<_Zone>.filled(s.length, _Zone.code);
  var i = 0;
  while (i < s.length) {
    i = _advance(s, i, m);
  }
  return m;
}

/// 从 i 起识别一个「注释 / 字符串」起始；标注区域后返回新下标（无命中则 i+1）。
int _advance(String s, int i, List<_Zone> m) {
  final n = s.length;
  if (s[i] == '/' && i + 1 < n && s[i + 1] == '/') {
    var j = i;
    while (j < n && s[j] != '\n') {
      m[j] = _Zone.line;
      j++;
    }
    return j;
  }
  if (s[i] == '/' && i + 1 < n && s[i + 1] == '*') {
    var j = i;
    while (j < n && !(s[j] == '*' && j + 1 < n && s[j + 1] == '/')) {
      m[j] = _Zone.block;
      j++;
    }
    final end = j + 2 > n ? n : j + 2;
    for (var k = j; k < end; k++) {
      m[k] = _Zone.block;
    }
    return end;
  }
  return _markStringAt(s, i, m) ?? i + 1;
}

/// 若 i 处是字符串起始（含 r 前缀、三引号），标注整段并返回其结束下标；否则 null。
int? _markStringAt(String s, int i, List<_Zone> m) {
  final n = s.length;
  var k = i;
  var raw = false;
  if (s[k] == 'r' && k + 1 < n && (s[k + 1] == "'" || s[k + 1] == '"')) {
    raw = true;
    k++;
  }
  if (k >= n || (s[k] != "'" && s[k] != '"')) return null;
  final q = s[k];
  final triple = k + 3 <= n && s.substring(k, k + 3) == q * 3;
  final end = _skipString(s, k, q, raw, triple);
  for (var x = i; x < end; x++) {
    m[x] = _Zone.str;
  }
  return end;
}

/// 返回字符串字面量的结束下标（开引号在 k）。
int _skipString(String s, int k, String q, bool raw, bool triple) {
  final n = s.length;
  final pat = triple ? q * 3 : q;
  var j = k + pat.length;
  while (j < n) {
    if (!raw && s[j] == r'\') {
      j += 2;
      continue;
    }
    if (s.startsWith(pat, j)) return j + pat.length > n ? n : j + pat.length;
    if (!triple && s[j] == '\n') return j; // 未闭合的单行串
    j++;
  }
  return n;
}

// ═══ 二、扫描基建 ═══════════════════════════════════════════════

/// 包根定位：从 cwd 向上回溯，直到同时存在 lib/ 与 test/。
Directory _findPackageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (Directory('${dir.path}/lib').existsSync() &&
        Directory('${dir.path}/test').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError('找不到包根目录（cwd=${Directory.current.path}）');
}

final Directory _root = _findPackageRoot();

/// lib/ 下所有 .dart（排除 .g.dart），按路径排序保证可复现。
List<File> _libDartFiles() {
  final out = <File>[];
  for (final e in Directory('${_root.path}/lib').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart') && !e.path.endsWith('.g.dart')) {
      out.add(e);
    }
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

List<int> _lineStarts(String s) {
  final out = <int>[0];
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '\n') out.add(i + 1);
  }
  return out;
}

/// 二分：idx 落在第几行（1 起）。
int _lineAt(List<int> starts, int idx) {
  var lo = 0;
  var hi = starts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= idx) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo + 1;
}

class _Hit {
  final String file;
  final int line;
  final String id;
  final String name;
  const _Hit(this.file, this.line, this.id, this.name);

  @override
  String toString() => '$file:$line  $id「$name」';
}

/// 注册表某条记录的全部合法写法（name / shortName 及其去尾「症」变体）。
Set<String> _aliasesOf(SyndromeRecord s) {
  final out = <String>{s.name, s.shortName};
  for (final v in [s.name, s.shortName]) {
    if (v.endsWith('症')) out.add(v.substring(0, v.length - 1));
  }
  return out;
}

/// 在一个文件里扫「ID+名」，跳过注释区。同一处被两条规则同时命中时只记一次。
List<_Hit> _scanPairs(String rel, String src, List<RegExp> res) {
  final mask = _zoneMask(src);
  final starts = _lineStarts(src);
  final seen = <String>{};
  final out = <_Hit>[];
  for (final re in res) {
    for (final m in re.allMatches(src)) {
      final z = mask[m.start];
      if (z == _Zone.line || z == _Zone.block) continue; // 注释豁免
      final key = '${m.start}:${m.group(1)}:${m.group(2)}';
      if (!seen.add(key)) continue;
      out.add(_Hit(rel, _lineAt(starts, m.start), m.group(1)!, m.group(2)!));
    }
  }
  return out;
}

/// 在一个文件里扫全部 ID（注释区跳过）。
List<String> _scanIds(String src, RegExp re) {
  final mask = _zoneMask(src);
  final out = <String>[];
  for (final m in re.allMatches(src)) {
    final z = mask[m.start];
    if (z == _Zone.line || z == _Zone.block) continue;
    out.add(m.group(0)!);
  }
  return out;
}

// ═══ 三、语料一次性构建 ═══════════════════════════════════════

class _Scan {
  final int filesScanned;
  final List<_Hit> pairHits; // 双规则并集（注释外）
  final List<String> idTokens; // 全部 ID（注释外）
  const _Scan({
    required this.filesScanned,
    required this.pairHits,
    required this.idTokens,
  });
}

/// 规则 A：ID + 以「症」结尾的名字（= #13 口径，抓「已死旧名」）。
final RegExp _reSuffix = RegExp(
  r'(P\d{3})\s*[（(]?\s*([\u4e00-\u9fff][\u4e00-\u9fffA-Za-z0-9/·]{1,11}?症)'
  r'(?=[、，,。；;）)|:：\s（(]|$)',
  multiLine: true,
);

/// 规则 B：ID + 任何「注册表名字」字面量（抓「错的活名」，含 8 个不带「症」的名字）。
final RegExp _reAlias = _buildAliasRe();

RegExp _buildAliasRe() {
  final universe = <String>{};
  for (final s in kSyndromeRegistry) {
    universe.addAll(_aliasesOf(s));
  }
  final alts = universe.toList()..sort((a, b) => b.length - a.length);
  final body = alts.map(RegExp.escape).join('|');
  return RegExp(
    '(P\\d{3})\\s*[（(]?\\s*($body)(?=[、，,。;；）)|:：\\s（(]|\$)',
    multiLine: true,
  );
}

/// 任何 ID（含历史 ghost H0XX 与已删编号 —— 合法性由 allowedIds 判）。
final RegExp _reAnyId = RegExp(r'\b(?:P|H)0\d{2}\b');

_Scan _buildScan() {
  var files = 0;
  final pairs = <_Hit>[];
  final ids = <String>[];
  for (final f in _libDartFiles()) {
    final rel = f.path.replaceAll(r'\', '/').replaceFirst('${_root.path}/', '');
    final src = f.readAsStringSync();
    files++;
    pairs.addAll(_scanPairs(rel, src, [_reSuffix, _reAlias]));
    ids.addAll(_scanIds(src, _reAnyId));
  }
  return _Scan(filesScanned: files, pairHits: pairs, idTokens: ids);
}

// ═══ 四、判据 ═══════════════════════════════════════════════════

/// 活跃 ∪ mergeMap 键（= four_libraries_consistency_test.dart #9 的 allowedIds 口径）。
Set<String> _allowedIds() =>
    kSyndromeIds.toSet().union(kSyndromeMergeMap.keys.toSet());

void _r1IdNameConsistency(_Scan scan) {
  final alias = <String, Set<String>>{
    for (final s in kSyndromeRegistry) s.id: _aliasesOf(s),
  };
  final bad = <String>[];
  for (final h in scan.pairHits) {
    final al = alias[h.id];
    if (al == null) continue; // 非法 ID 由 R2 兜底
    if (!al.contains(h.name)) {
      bad.add('$h（应为「${syndromeNameOf(h.id) ?? '?'}」）');
    }
  }
  expect(
    bad,
    isEmpty,
    reason:
        '症候「ID↔名字」不一致 ${bad.length} 处（0.3.6 重编号残留同族）:\n'
        '${bad.join('\n')}',
  );
}

void _r2NoDanglingIds(_Scan scan) {
  final allowed = _allowedIds();
  final bad = <String>{};
  for (final id in scan.idTokens) {
    if (!allowed.contains(id)) bad.add(id);
  }
  expect(
    bad,
    isEmpty,
    reason:
        'lib/ 出现注册表外的症候 ID（悬空引用）: ${bad.toList()..sort()}\n'
        '（注：P001–P049 全部是合法 legacy 编号，见 kSyndromeMergeMap）',
  );
}

/// 刻意**无** few-shot 示例的症候 —— 须与 training_few_shot_library.dart
/// 文件头「覆盖范围：注册表 P001–P023」一致；补了示例即须改本行（否则红）。
const Set<String> _fewShotIntentionallyMissing = {
  'P024',
  'P025',
  'P026',
  'P027',
  'P028',
  'P029',
  'P030',
  'P031',
  'P032',
  'P033',
  // P034 已于 C123 批（2026-10-02）补正反例对，移出「刻意缺口」。
};

Map<String, int> _countBy(String content, RegExp re) {
  final count = <String, int>{};
  for (final m in re.allMatches(content)) {
    count.update(m.group(1)!, (v) => v + 1, ifAbsent: () => 1);
  }
  return count;
}

/// R3 载体矩阵：每个活跃 ID 在各载体上「要么齐、要么按声明一致地无」。
void _r3CarrierMatrix() {
  final manual = _countBy(kSyndromeManualContent, RegExp(r'###\s+(P\d{3})\s'));
  final training = _countBy(kTrainingFullKnowledge, RegExp(r'##\s+(P\d{3})\s'));
  final index = _countBy(
    kSyndromeIndexContent,
    RegExp(r'^\|\s*(P\d{3})\s*\|', multiLine: true),
  );
  final bad = <String>[];
  for (final s in kSyndromeRegistry) {
    final id = s.id;
    if ((manual[id] ?? 0) != 1) bad.add('手册段 $id = ${manual[id] ?? 0}（应恰 1）');
    if ((training[id] ?? 0) != 1) {
      bad.add('训练段 $id = ${training[id] ?? 0}（应恰 1）');
    }
    if ((index[id] ?? 0) != 1) bad.add('L2索引行 $id = ${index[id] ?? 0}（应恰 1）');
  }
  expect(bad, isEmpty, reason: '载体矩阵缺项/多项:\n${bad.join('\n')}');

  final fewShot = kTrainingFewShotLibrary.keys.toSet();
  expect(
    fewShot.difference(kSyndromeIds.toSet()),
    isEmpty,
    reason: 'few-shot 库存在非注册表键',
  );
  expect(
    kSyndromeIds.toSet().difference(fewShot),
    _fewShotIntentionallyMissing,
    reason: 'few-shot「刻意覆盖缺口」与声明不符（新增/删除示例须同步本文件常量）',
  );
}

/// R4 阳性对照：扫描器必须真命中，否则「零发现」与「没跑起来」外观相同。
void _r4PositiveControls(_Scan scan) {
  expect(
    scan.filesScanned,
    greaterThanOrEqualTo(300),
    reason: '扫描面过窄（实测 445 个 .dart）—— 疑似只扫到部分目录',
  );
  expect(
    scan.pairHits,
    isNotEmpty,
    reason: '「ID+名」扫描零命中 —— 正则疑似静默失效（实测应 321 处）',
  );
  expect(
    scan.pairHits.length,
    greaterThanOrEqualTo(150),
    reason: '「ID+名」命中数骤降（实测 321）—— 疑似正则/剥离逻辑退化',
  );
  expect(
    scan.idTokens.length,
    greaterThanOrEqualTo(400),
    reason: 'ID 命中数骤降（实测 869）—— 疑似扫描面退化',
  );
  expect(
    scan.idTokens.toSet().length,
    greaterThanOrEqualTo(30),
    reason: '命中 ID 种类过少（实测 51）—— 疑似只扫到部分文件',
  );
}

void main() {
  final scan = _buildScan();

  group('症候引用完整性（全域 · 2026-09-30）', () {
    test('#R1 全域「ID↔名字」一致（实测 ${scan.pairHits.length} 处）', () {
      _r1IdNameConsistency(scan);
    });

    test('#R2 全域无悬空 ID（实测 ${scan.idTokens.length} 处）', () {
      _r2NoDanglingIds(scan);
    });

    test('#R3 载体矩阵：手册/训练/索引 齐·缺一致 + few-shot 缺口显式', () {
      _r3CarrierMatrix();
    });

    test('#R4 阳性对照：扫描器必须真命中（检出 ${scan.pairHits.length} 对 / '
        '${scan.idTokens.length} ID / ${scan.filesScanned} 文件）', () {
      _r4PositiveControls(scan);
    });
  });
}
