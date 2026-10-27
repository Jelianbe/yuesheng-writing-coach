// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// 常量级 prompt 体积锚点（`buildSystemPromptV2` 计量面之外的三块）
//
// 卡：T-20261025-03 §二（B3b-0 · L0 支撑层 · 零 prompt 正文改动）
//
// ## 这个文件为什么存在
//
// 既有三份锚点（`skill_prompt_anchor.json` / `message_sequence_anchor.json` /
// `l3_entry_anchor.json`）只覆盖 `buildSystemPromptV2` 的产物与消息序列，
// **以下三块常量不在任何一份里**：
//
//   ① `kChunkSystemPrompt`（`progressive_diagnosis.dart:589`）——
//      >4000 字文本走的分块链 system prompt。`test/` 对它的既有断言
//      （`progressive_chunk_syndrome_coverage_test.dart`）全部是
//      **ID 覆盖 / 子串存在性**，**零体积断言** ⇒ 任何增长无拦截。
//   ② `chunkExceptionGuideBlock` —— 上者内嵌的例外指引表（库私有常量
//      `_kChunkExceptionGuide`，`progressive_diagnosis.dart:406`）。
//      下一批 B3b-1 要改的正是它 ⇒ 没有读数面就无从读数、也无从拦超限。
//   ③ `ChatService.kDiagnosisProtocolSuffix`（`chat_service.dart:227`）——
//      拼在诊断轮次 user 消息上的协议文本；`T-20261024-13` 缺口 1 的对象。
//
// ## `chunkExceptionGuideBlock` 怎么取（为什么不是读源码文件）
//
// 该常量是**库私有**，外部 test 不可直接引用。这里**不为它开公开 API**——
// 读数面不该让生产代码永久背一个测试专用导出。改为从**已装配好的**
// `kChunkSystemPrompt` 里按运行时文本切片。
//
// ★ 不读源码文件做正则：那量的是**源码文本**，不是**运行时注入字节**；
//   两者会在生成代码 / 转义 / 字符串拼接变化时分家（量错了还报绿）。
// ★ 切片锚点失效必须响亮失败（`throw`），不许 fallback 到 0 或跳过——
//   「静默量错对象」是本项目反复踩过的坑。
//
// ## 用法
//
//   flutter test test/services/prompt_const_anchor_test.dart
//   UPDATE_SNAPSHOTS=true flutter test test/services/prompt_const_anchor_test.dart
//
// ## ★ 快照缺失语义 = **fail-closed**（对齐 `chat_service_message_sequence_anchor_test.dart`）
//
// 本文件的缺失分支语义**对齐** `test/services/chat_service_message_sequence_anchor_test.dart`
// 的 fail-closed 守卫（同族：`l3_entry_anchor_test.dart` / `student_profile_anchor_test.dart`），
// **不沿用** `test/services/skill_prompt_anchor_test.dart:384` 的旧写法
// `if (updating || !file.existsSync())` —— 那个写法把「显式重建」与「快照缺失」
// 并成一个分支，快照被误删 / 误移 / 未检出时会**静默把当前装配写成新基线并判绿**
// ⇒ 判据面缩小而门禁仍在跑。该类写法登记为 `T-20261024-13` 缺口 2（fail-open），
// 待修；**本文件不得照抄它**。
//
// 三条分支必须互相独立：
//   ① `!exists && !updating` ⇒ `fail`（缺失 = 事故，不重建）
//   ② `updating`            ⇒ 显式重建通路，写盘 + 告警「本次未做任何比对」
//   ③ `exists && !updating` ⇒ 比对，有 diff 就 `fail`
// 且①**前置于任何装配/计算**：否则装配侧抛错会遮住「快照缺失」这个真因。
//
// ## ★★ 重冻 ≠ 获准增长
//
// `UPDATE_SNAPSHOTS=true` 只是**把当前读数写成新基线**，它不构成任何批准。
// 重冻后必须同步做三件事，缺一即视为「用重冻洗掉增量」：
//   ① 把 `tool/check_prompt_volume.py` 的 `CONST_REDLINE` 重钉到**新实测值**；
//   ② 在 `.ai/DECISIONS.md` 登记归因（哪个文件哪一行、方向、授权来源）；
//   ③ 重跑 `python tool/check_prompt_volume.py` 确认它在新值上仍是绿的。
// 只重冻本文件而不重钉红线 ⇒ 两份读数分家，红线变成装饰。
//
// ⚠️ 本文件量的是**体积与字节**，**不量行为**：分块链 >4000 字语料实测 0 条
//   （T-20261025-03 §五 ①）⇒ 「例外表变长了」不等于「模型判得更准了」。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';

const String kAnchorPath = 'test/snapshots/prompt_const_anchor.json';

// ── 切片锚点（取例外表首行 / 输出格式段首行；两者均由源码实测）──
/// 例外表首行（`progressive_diagnosis.dart:406` 常量正文第一行）。
const String kGuideStartMarker = '例外情况指引（以下场景通常不应判定为症候）：';

/// 输出格式段首行（`_kChunkOutputFormat` 正文第一行，装配顺序紧接例外表）。
const String kGuideEndMarker = '请输出JSON格式的笔记';

/// 例外表条目行的唯一形态：`- Pxxx例外…`
final RegExp kExceptionLineRe = RegExp(r'- (P\d{3})例外');

/// 行首形态（用于与上面**独立**量「例外行数」，两路交叉校验）。
final RegExp kExceptionLineHeadRe = RegExp(r'^- P\d{3}例外');

/// FNV-1a 64 位指纹（与 `skill_prompt_anchor_test.dart` 同一实现，
/// 保证四份快照的 fnv 口径可互相印鉴）。
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

/// 从**已装配好的** `kChunkSystemPrompt` 里切出例外指引表。
///
/// 装配形态（`progressive_diagnosis.dart:574-584`）：
/// `…\n\n$_kChunkExceptionGuide\n\n$_kChunkOutputFormat…`
/// ⇒ 从 startMarker 到 endMarker 之间的原文，必然以 `\n\n` 收尾；
/// 去掉这 2 个字符即为常量本体（不含装配分隔符）。
String _sliceChunkExceptionGuide(String prompt) {
  final start = prompt.indexOf(kGuideStartMarker);
  final end = start < 0 ? -1 : prompt.indexOf(kGuideEndMarker, start);
  if (start < 0 || end <= start) {
    throw StateError(
      '例外表切片锚点失效：start=$start end=$end。'
      '装配形态或锚点文案已变，须先核 '
      'progressive_diagnosis.dart:574-584 再改本文件的 kGuide*Marker。',
    );
  }
  final raw = prompt.substring(start, end);
  if (raw.length < 2 || !raw.endsWith('\n\n')) {
    final tail = raw.length > 12 ? raw.substring(raw.length - 12) : raw;
    throw StateError(
      '例外表与输出格式段之间的分隔变了：切片尾部=${jsonEncode(tail)}'
      '（期望以两个换行收尾，即两段之间的空行）。'
      '不许静默放行 —— 分隔符变了说明切片对象可能已不是例外表本体。',
    );
  }
  return raw.substring(0, raw.length - 2);
}

/// 一次取值的结果：三个钉值键 + 切片正文（结构自检复用**同一份**文本，
/// 不重新切片、不重新求值）。
typedef CollectedPromptConsts = ({
  Map<String, Object> anchors,
  String guideText,
});

/// 汇总当前读数。三个值**全部来自同一次** `kChunkSystemPrompt` 取值。
CollectedPromptConsts _buildCurrent() {
  final chunkPrompt = kChunkSystemPrompt; // ★ 单次取值，后续键不得重新求值
  final guide = _sliceChunkExceptionGuide(chunkPrompt);
  final suffix = ChatService.kDiagnosisProtocolSuffix;

  // meta 段**只做归因、不做钉值**：漂移时打出来给人看是哪几条变了，
  // 但不参与判定（判定看 len + fnv）。
  //
  // ★ 两个「条数」口径必须分开命名（写错名字比写错数更糟 —— 后人会按名字去用）：
  //   · exceptionIds        = `- P\d{3}例外` 的**出现次数**（子串匹配）
  //   · exceptionLineCount  = 以 `- Pxxx例外` **行首开头**的行数（逐行匹配）
  //   · guideLineCount      = 例外表**总行数**（含首行标题行与末条兜底行）
  // 三者用两种独立机制量（子串 allMatches vs 逐行 hasMatch）⇒ 结构自检⑤
  // 交叉校验才有牙齿；若同源于一次匹配，那条断言恒真。
  final ids = kExceptionLineRe
      .allMatches(guide)
      .map((m) => m.group(1)!)
      .toList();
  final exceptionLineCount = guide
      .split('\n')
      .where(kExceptionLineHeadRe.hasMatch)
      .length;

  return (
    anchors: {
      'kChunkSystemPrompt': _textAnchor(chunkPrompt),
      'chunkExceptionGuideBlock': _textAnchor(guide),
      'kDiagnosisProtocolSuffix': _textAnchor(suffix),
      'meta': {
        'exceptionIds': ids,
        'exceptionLineCount': exceptionLineCount,
        'guideLineCount': guide.split('\n').length,
        'note':
            'meta 段只做归因、不做钉值；判定看上面三个键的 len + fnv。'
            r'exceptionIds = `- P\d{3}例外` 出现次数；'
            r'exceptionLineCount = 以 `- Pxxx例外` 行首开头的行数；'
            'guideLineCount = 例外表总行数（含首行标题与末条兜底）。',
      },
    },
    guideText: guide,
  );
}

/// 写/比对之前的结构自检（四问）。任一不过 ⇒ `fail`，**不许写脏基线**。
///
/// 依据：本项目已发生过「锚点漂移后静默量到错对象、快照照样生成、门禁照样绿」
/// ⇒ 结构自检必须打在**被测对象本身**上，不能只打在快照上。
void _selfCheck(Map<String, Object> current, String guideText) {
  final chunkLen = (current['kChunkSystemPrompt']! as Map)['len']! as int;
  final guideLen = (current['chunkExceptionGuideBlock']! as Map)['len']! as int;
  final suffixLen =
      (current['kDiagnosisProtocolSuffix']! as Map)['len']! as int;

  // ① 整条分块 system prompt 不可能这么短（症候清单 + 五块常量的下限）
  if (chunkLen <= 3000) {
    fail(
      '结构自检①不过：kChunkSystemPrompt.len=$chunkLen ≤ 3000 '
      '⇒ 疑量到空串 / 别的对象。',
    );
  }
  // ② 例外表实测 2,767 字符；低于 2,000 说明切片错位（少切了条目）
  //    （2026-10-28 刷新：旧值 2,544 停在批一a 之前 —— T-20261026-01 附带项①）
  if (guideLen < 2000) {
    fail(
      '结构自检②不过：chunkExceptionGuideBlock.len=$guideLen < 2000 '
      '⇒ 切片起点/终点错位（实测参考值 2,767）。',
    );
  }
  // ③ 切片体内不得出现 endMarker（防 endMarker 过早命中、只切到半张表）
  if (guideText.contains(kGuideEndMarker)) {
    fail(
      '结构自检③不过：例外表切片内含 endMarker「$kGuideEndMarker」'
      '⇒ endMarker 命中了错误位置。',
    );
  }
  // ④ 协议 suffix 不可能这么短（本批实测 977；协议标记 + 字段表的下限）
  if (suffixLen <= 500) {
    fail(
      '结构自检④不过：ChatService.kDiagnosisProtocolSuffix.len=$suffixLen '
      '≤ 500 ⇒ 疑量到空串 / 常量已被清空。',
    );
  }
  // ⑤ 两个「条数」口径交叉校验。
  //    exceptionIds 走**子串** allMatches，exceptionLineCount 走**逐行** hasMatch
  //    ⇒ 两路独立。二者不等即说明口径已坏（两条例外被并到一行 / 例外行不再以
  //    `- ` 开头 / 正则被改坏）；此时读数名与内容不符，**必须红**而不是静默带着
  //    一个错名进基线（写错名字比写错数更糟 —— 后人会按名字去用）。
  final meta = current['meta']! as Map;
  final ids = meta['exceptionIds']! as List;
  final exLines = meta['exceptionLineCount']! as int;
  final guideLines = meta['guideLineCount']! as int;
  if (ids.length != exLines) {
    fail(
      '结构自检⑤不过：exceptionIds 命中 ${ids.length} 个，但行首例外行为 '
      '$exLines 行 ⇒ 子串匹配与逐行匹配不一致'
      '（疑似两条例外并到一行，或例外行未以 `- ` 开头）。',
    );
  }
  if (guideLines < exLines) {
    fail(
      '结构自检⑤不过：guideLineCount=$guideLines < exceptionLineCount=$exLines '
      '⇒ 总行数不可能少于例外行数，切片对象已不是例外表本体。',
    );
  }
}

/// 递归 diff，返回 `path: before → after`（与既有快照护栏同款）。
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

const List<String> kPinnedKeys = [
  'kChunkSystemPrompt',
  'chunkExceptionGuideBlock',
  'kDiagnosisProtocolSuffix',
];

/// 打印 meta 归因差异（**不判定**——判定只看三个钉值键的 len + fnv）。
void _printMetaDrift(dynamic storedMeta, dynamic currentMeta) {
  if (jsonEncode(storedMeta) == jsonEncode(currentMeta)) return;
  final beforeIds = storedMeta is Map ? storedMeta['exceptionIds'] : null;
  final afterIds = currentMeta is Map ? currentMeta['exceptionIds'] : null;
  final beforeEx = storedMeta is Map ? storedMeta['exceptionLineCount'] : null;
  final afterEx = currentMeta is Map ? currentMeta['exceptionLineCount'] : null;
  final beforeAll = storedMeta is Map ? storedMeta['guideLineCount'] : null;
  final afterAll = currentMeta is Map ? currentMeta['guideLineCount'] : null;
  print(
    '[const-anchor] meta 归因差异（不判定）：'
    '例外条目 ${beforeIds is List ? beforeIds.length : -1}'
    ' → ${afterIds is List ? afterIds.length : -1}；'
    '例外行 $beforeEx → $afterEx；'
    '总行数 $beforeAll → $afterAll',
  );
}

void main() {
  test('常量级 prompt 体积锚点：三块常量字节级不变', () {
    final updating = (Platform.environment['UPDATE_SNAPSHOTS'] ?? '') == 'true';
    final file = File(kAnchorPath);
    final exists = file.existsSync();

    // ── fail-closed 守卫（对齐 chat_service_message_sequence_anchor_test.dart）──
    // 旧写法 `if (updating || !file.existsSync())` 把两件事并成一个分支：
    //   「显式重建」与「快照缺失」⇒ 快照被误删 / 误移 / 未检出时本用例**照样绿**，
    //   并把当前装配静默写成新基线（此刻 lib 侧若有漂移，基线即被替换成漂移后的值
    //   ⇒ 之后再不会红）。该形态登记为 `T-20261024-13` 缺口 2（fail-open）。
    // ★ 守卫**前置于任何装配/计算**：否则切片或装配侧抛错会先红，
    //   「快照缺失」这个真因会被后者的报错遮住（判据落点须指向缺失本身）。
    if (!exists && !updating) {
      fail(
        '[const-anchor] 锚点快照缺失：$kAnchorPath\n'
        '  ★ 快照文件缺失 = 事故，不是常态（该文件本应随仓库一起检出）。\n'
        '  缺失时**不得**自动生成基线 —— 那等于用「当前行为」重写判据，'
        '任何漂移都会被静默转绿。\n'
        '  先查三因：误删 / 误移 / 未检出'
        '（git status --porcelain、git ls-files test/snapshots/）。\n'
        '  确需重建（基线变更须可对账、须经评审）：\n'
        '    UPDATE_SNAPSHOTS=true flutter test '
        'test/services/prompt_const_anchor_test.dart',
      );
    }

    final collected = _buildCurrent();
    final current = collected.anchors;
    _selfCheck(current, collected.guideText);

    // ── ② 显式重建通路（UPDATE_SNAPSHOTS=true）──────────────────────────
    // 允许写，但**必须打告警**：本分支不做任何比对，写出的就是新判据。
    if (updating) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(current)}\n',
        );
      print(
        '[const-anchor][告警] UPDATE_SNAPSHOTS=true ⇒ 基线被强制覆盖：'
        '$kAnchorPath',
      );
      print(
        '[const-anchor][告警] 本次**未做任何比对**，这不是校验通过；'
        '原快照${exists ? '已被丢弃' : '本就不存在（本次为新建）'}。',
      );
      print('[const-anchor][告警] 提交前必须逐条复核 git diff $kAnchorPath。');
      for (final k in kPinnedKeys) {
        final a = current[k]! as Map;
        print('[const-anchor][告警]   $k len=${a['len']} fnv=${a['fnv']}');
      }
      final meta = current['meta']! as Map;
      print(
        '[const-anchor][告警]   meta 例外条目 '
        '${meta['exceptionIds']!.length as int} 条 / '
        '例外行 ${meta['exceptionLineCount']} 行 / '
        '总行数 ${meta['guideLineCount']} 行',
      );
      print(
        '[const-anchor][告警] ⚠️ 重冻 ≠ 获准增长：须同步重钉 '
        'tool/check_prompt_volume.py 的 CONST_REDLINE 并登记 DECISIONS 归因。',
      );

      // 回读校验：写入成功 ≠ 写出的是完整基线（截断 / 空文件同样「存在」）。
      final reread =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final missing = <String>[
        for (final k in [...kPinnedKeys, 'meta'])
          if (!reread.containsKey(k)) k,
      ];
      if (missing.isNotEmpty) {
        fail('[const-anchor] 基线写入不完整，缺 ${missing.length} 个键：$missing');
      }
      expect(file.existsSync(), isTrue);
      return;
    }

    // ── ③ 比对分支（exists && !updating）────────────────────────────────
    final stored = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    final diffs = <String>[];
    for (final k in kPinnedKeys) {
      diffs.addAll(_diff(k, stored[k], current[k]));
    }

    if (diffs.isNotEmpty) {
      // 分布：先看清是哪几个键在动（一个键 2 行 / 多键则分行点名）
      final touched = <String, int>{};
      for (final d in diffs) {
        final key = d.split('.').first;
        touched[key] = (touched[key] ?? 0) + 1;
      }
      print('[const-anchor] 检测到 ${diffs.length} 处字节级漂移');
      print(
        '[const-anchor] 分布：'
        '${touched.entries.map((e) => '${e.key} ${e.value}').join(' / ')}',
      );
      for (final d in diffs) {
        print('  - $d');
      }
      // meta 只做归因：一致/不一致都打出来，但不计入 diff
      _printMetaDrift(stored['meta'], current['meta']);
      print('[const-anchor] 若漂移为预期改动（须舰长确认 + 同步重钉红线），请运行：');
      print(
        '  UPDATE_SNAPSHOTS=true flutter test '
        'test/services/prompt_const_anchor_test.dart',
      );
      fail(
        '常量级 prompt 体积锚点发生字节级漂移（${diffs.length} 处，'
        '涉及 ${touched.keys.join(', ')}），见上方 diff。',
      );
    }

    // meta 归因信息（不判定）
    _printMetaDrift(stored['meta'], current['meta']);

    print('[const-anchor] 比对通过：三块常量与基线字节级一致 ✓');
    for (final k in kPinnedKeys) {
      final a = current[k]! as Map;
      print('[const-anchor]   $k len=${a['len']} fnv=${a['fnv']}');
    }
    expect(diffs, isEmpty);
  });
}
