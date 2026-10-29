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
//   ① `kChunkSystemPrompt`（`progressive_diagnosis.dart:617`）——
//      >4000 字文本走的分块链 system prompt。`test/` 对它的既有断言
//      （`progressive_chunk_syndrome_coverage_test.dart`）全部是
//      **ID 覆盖 / 子串存在性**，**零体积断言** ⇒ 任何增长无拦截。
//   ② `chunkExceptionGuideBlock` —— 上者内嵌的例外指引表（库私有常量
//      `_kChunkExceptionGuide`，`progressive_diagnosis.dart:436`）。
//      下一批 B3b-1 要改的正是它 ⇒ 没有读数面就无从读数、也无从拦超限。
//   ③ `ChatService.kDiagnosisProtocolSuffix`（`chat_service.dart:227`）——
//      拼在诊断轮次 user 消息上的协议文本；`T-20261024-13` 缺口 1 的对象。
//
// ★ 2026-10-28 追加第 ④ 键（`T-20261027-01` **H9**）：分块链**窗口元信息**串
//   （固定入参样张）。它此前零锚点 ⇒ 标签措辞（
//   「章节标题：」把记录标题当成块内章节归属）可被任意改动而无人拦。
//   本键与前三块同口径（len + fnv），并配内容牙 `_payloadCheck()`（P1–P4）。
//   ★ 2026-10-29 **H8**（`T-20261027-01` 批八）：该串不再与正文拼在同一条 user
//   消息里 ⇒ 键名随对象改名 `chunkUserMessageSample → chunkWindowMetaSample`，
//   并另加形状牙 **H1–H4**（角色序列 / 正文纯净 / 块序不重复 / 主 system 不动）。

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
/// 例外表首行（`progressive_diagnosis.dart:436` 常量正文第一行）。
const String kGuideStartMarker = '例外情况指引（以下场景通常不应判定为症候）：';

/// 输出格式段首行（`_kChunkOutputFormat` 正文第一行，装配顺序紧接例外表）。
const String kGuideEndMarker = '请输出JSON格式的笔记';

/// 窗口边界节的首/尾锚点（`T-20261028-01` §7-P3 用它切出该节本体）：
/// 首 = `_kChunkWindowBoundary` 正文第一行（`progressive_diagnosis.dart:526`）；
/// 尾 = 紧随其后的「块内可自证」对照段首行（`_kChunkSelfContainedProbe`，`:539`）。
/// ⇒ 切片 = 该节**全部正文**，不含相邻段。
const String kBoundaryStartMarker = '## 片段窗口边界（判读前提，先读这一节）';
const String kBoundaryEndMarker = '- 可在片段内指认位置的';

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
/// 装配形态（`progressive_diagnosis.dart:610-612`）：
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
      'progressive_diagnosis.dart:610-612 再改本文件的 kGuide*Marker。',
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
  String chunkPrompt,
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
      // H9：分块链「窗口元信息」串（固定入参的样张）。量的是**装配产物**，
      // 与上面三块同口径（len + fnv）⇒ 措辞/分隔符一改即红。
      // H8：该串现单独成一条 system 消息，正文那条不再含它（键名随之改）。
      'chunkWindowMetaSample': _textAnchor(
        buildChunkWindowMeta(
          recordTitle: kPayloadSampleTitle,
          chunkIndex: kPayloadSampleIndex,
          chunkCount: kPayloadSampleCount,
        ),
      ),
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
    chunkPrompt: chunkPrompt,
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
  // ② 例外表实测 2,944 字符；低于 2,000 说明切片错位（少切了条目）
  //    （2026-10-28 刷新：旧值 2,544 停在批一a 之前 —— T-20261026-01 附带项①）
  if (guideLen < 2000) {
    fail(
      '结构自检②不过：chunkExceptionGuideBlock.len=$guideLen < 2000 '
      '⇒ 切片起点/终点错位（实测参考值 2,944）。',
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
  'chunkWindowMetaSample',
];

// ── H9 payload 样张入参（固定值 ⇒ 样张可逐字节比对）──
const String kPayloadSampleTitle = '第三章 雨夜';
const int kPayloadSampleIndex = 0;
const int kPayloadSampleCount = 3;
const String kPayloadSampleBody = '他推开门，雨声灌进来。';

/// 内容牙 P1–P4（`T-20261027-01` H9）+ 形状牙 H1–H4（同卡 **H8** · 批八）
/// + 透传牙 T1（**复核后增补**，钉「第二条消息内容 = 元信息构造器产物」）。
///
/// **P 组**：分块链**不得再断言**「这段内容属于某一章」。打在元信息串的
/// **产物**上，与快照样张互补：样张拦「改了字」，本节拦「改回了错误形态」
/// （两者都可能被一次重冻同时洗掉，但本节还额外证明**空标题分支**）。
///
/// **H 组**（H8）：注入**形状**本身 —— 标签单独成条、正文那条只装正文、
/// 块序不重复注入、主 system 仍是那个常量本体。
/// ⚠️ 本文件用例是 **fail-fast**（第一条不过即 `fail`），所以「哪一条红」
/// 需由离线变异探针逐位归因，不指望一次跑全部报出。
void _payloadCheck() {
  final meta = buildChunkWindowMeta(
    recordTitle: kPayloadSampleTitle,
    chunkIndex: kPayloadSampleIndex,
    chunkCount: kPayloadSampleCount,
  );
  final msgs = buildChunkMessages(
    kPayloadSampleTitle,
    kPayloadSampleBody,
    kPayloadSampleIndex,
    kPayloadSampleCount,
  );
  final bodyMsg = msgs.last;
  // P1 旧形态不得复活：`章节标题：` = 把记录标题当块内章节归属（H9 缺陷本体）。
  // ★ H8 后覆盖面**扩到元信息 + 正文两条**（标签搬到哪条都不能复活）。
  final metaPlusBody = '$meta\n$bodyMsg';
  if (metaPlusBody.contains('章节标题：')) {
    fail('内容牙 P1 不过：分块注入仍出现 `章节标题：`（H9 已撤的假断言）。');
  }
  // P2 必须只声明知道的事：来源记录 + 块序号
  for (final must in const ['来源记录：$kPayloadSampleTitle', '文本片段 1/3：']) {
    if (!meta.contains(must)) {
      fail('内容牙 P2 不过：窗口元信息缺 `$must`。');
    }
  }
  // P2b 必须带「可能含多章」这一句 —— 否则标签仍在暗示整段同一章
  if (!meta.contains('本片段可能含多章')) {
    fail('内容牙 P2 不过：窗口元信息缺「本片段可能含多章」（假断言未被撤干净）。');
  }
  // P3′ 正文那条**逐字节等于片段本体**（H8 取代旧 P3 的 `endsWith`：
  // 现在不只是「结尾是正文」，而是「整条就是正文」—— 更强的判据）。
  if (bodyMsg.content != kPayloadSampleBody) {
    fail(
      '内容牙 P3 不过：user 消息不是片段本体'
      '（实 len=${bodyMsg.content.length}，期望 len=${kPayloadSampleBody.length}）。',
    );
  }
  // P4 空标题分支：`chapters.title` 默认空串（不是异常态）⇒ 不得留下「来源记录：」空壳
  final noTitle = buildChunkWindowMeta(
    recordTitle: '',
    chunkIndex: 1,
    chunkCount: 2,
  );
  if (noTitle.contains('来源记录：')) {
    fail('内容牙 P4 不过：标题为空时元信息仍输出「来源记录：」空壳行。');
  }
  if (!noTitle.startsWith('文本片段 2/2：')) {
    fail(
      '内容牙 P4 不过：标题为空时块序号行形态变了（实际开头：'
      '${noTitle.length > 16 ? noTitle.substring(0, 16) : noTitle}）。',
    );
  }
  // ── H 组：注入形状（H8 本体）──
  // H1 角色序列必须恰为 system,system,user（回退成两条 ⇒ 红；
  //    拆成两条 user ⇒ 也红：那不是本包批准的落法）
  final roles = msgs.map((m) => m.role).join(',');
  if (roles != 'system,system,user') {
    fail('形状牙 H1 不过：分块链角色序列是 `$roles`，期望 `system,system,user`。');
  }
  // T1 透传（★ 三链观测点黑洞由用例有效性评审方 2026-10-29 抓出）：
  //   H1 只判第二条的**角色**，P2/P4/H3 打的是**直调构造器**的串 —— 从来没有人读过
  //   `msgs[1].content`。于是「第二条消息内容写成空串 / 正文 / 把 chunkIndex 写死」
  //   在本批三链里全绿。T1 把「那条消息 == 构造器产物」钉住，并用**第二组入参**
  //   （空标题 + 1/2）再钉一次 ⇒ 装配处漏传参数也会红。
  if (msgs[1].content != meta) {
    fail(
      '透传牙 T1 不过：第二条消息内容与 buildChunkWindowMeta(样张入参) 不等'
      '（实 len=${msgs[1].content.length}，期望 len=${meta.length}）。',
    );
  }
  final msgs2 = buildChunkMessages('', kPayloadSampleBody, 1, 2);
  if (msgs2[1].content != noTitle) {
    final got = msgs2[1].content;
    fail(
      '透传牙 T1 不过：换一组入参（空标题 · 片段 2/2）后第二条不再是该组的元信息'
      '（实 `${got.length > 24 ? got.substring(0, 24) : got}`）⇒ 装配处把标题/块序写死了。',
    );
  }
  // H2 纯净：正文那条不得再含任何标签字面量（缺陷本体：标签混进被观察文本）
  for (final banned in const ['来源记录：', '文本片段 ', '本片段可能含多章']) {
    if (bodyMsg.content.contains(banned)) {
      fail('形状牙 H2 不过：正文消息重新混入标签 `$banned`（H8 缺陷回归）。');
    }
  }
  // H3 反重复：块序号在「元信息 + 正文」两条里**恰出现一次**
  //    （两处都写 ⇒ 模型看到两遍块序，比混排更糟）
  final ordinals = RegExp('文本片段 ').allMatches(metaPlusBody).length;
  if (ordinals != 1) {
    fail('形状牙 H3 不过：块序号出现 $ordinals 次（期望恰 1 次，重复注入）。');
  }
  // H4 主 system 仍是常量本体 —— 本包「CONST_REDLINE 零漂移」承诺的守卫。
  //    （若有人改用丙案把标签并进主 system，len/fnv 锚点会红，但这条先指出**是谁**）
  if (msgs.first.content != kChunkSystemPrompt) {
    fail('形状牙 H4 不过：第一条消息不是 kChunkSystemPrompt 本体（主 system 被动了）。');
  }
}

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

/// 内容牙 L1–L4（`T-20261027-01` H5 · 2026-10-28 舰长批准 · 报批稿 §6.2）。
///
/// 打在**运行时切片**上（见文件头部：量注入字节，不量源码文本）。
/// ★ 这四条**不是语义牙**：拦「定义没写 / 没排除项 / 没接后果 / 废词复活」，
///   拦不住「定义写得像、模型照旧乱判」——后者须对照稿 + 真实采样（本批无 key）。
void _contentLint(String guideText) {
  final p003 = guideText
      .split('\n')
      .firstWhere((l) => l.startsWith('- P003例外'), orElse: () => '');
  if (p003.isEmpty) {
    fail('内容牙 L1 不过：例外表内找不到 `- P003例外` 行 ⇒ 行首形态或切片对象已变。');
  }

  // L1 两项定义都要在（形态牙："＝"定义标记）
  for (final term in const ['"感知者"＝', '"感知来源句"＝']) {
    if (!p003.contains(term)) {
      fail('内容牙 L1 不过：P003 行缺定义标记 `$term`（H5 两项内联定义）。');
    }
  }

  // L2 定义必须带排除项 —— 无排除项的定义 = 无鉴别力
  if (!p003.contains('纯环境句不算')) {
    fail(
      '内容牙 L2 不过：感知来源句定义缺排除项 `纯环境句不算`'
      '（无排除项 ⇒ 任意含人名的陈述句都能充数）。',
    );
  }

  // L3 两项都要接在后果句上（只定义、不改变任一判定方向的项 = 死条）
  if (!p003.contains('各自的感知者，二者不同')) {
    fail('内容牙 L3 不过：感知者未接到 ③ 的换锁句 `二者不同`。');
  }
  if (!p003.contains('感知来源句') || !p003.contains('即不构成漂移')) {
    fail('内容牙 L3 不过：感知来源句未接到后果句 `不构成漂移`。');
  }

  // L4 废词牙：`感知中心` 2026-10-27 撤出（§4-343 E3），不得复活
  if (guideText.contains('感知中心')) {
    fail('内容牙 L4 不过：例外表内出现废词 `感知中心`（复裁见 2026-10-28 报批稿 §1）。');
  }
}

/// 判据 P1 / P3（`T-20261028-01` · 2026-10-29 舰长批准 · 报批稿 §7）。
///
/// **P1 文本级**：P003 的失败路径不得再无条件落到「按正文判定」——
///   缺的是**片段外**的句子（切换前一条被上一块截走）时必须先降级为 `uncertain`。
/// **P3 一致性**：同一段 prompt 里 P003 行与 `_kChunkWindowBoundary` 对
///   「证据在窗外」这一场景不得给相反指令 —— 断言**切出边界节本体**后三要素仍在
///   （依赖片段外信息 / 不要勉强给结论 / `uncertain`），即「方向」而非「字还在」。
///
/// ★ 这不是行为牙：拦「分支没写 / 只写一半 / 旧形态复活」，
///   拦不住「模型照旧硬判」—— 后者须离线对照稿（F1/F2）+ 真实采样。
/// ★ 判据编号沿用报批稿 §7（写作 `§7-P1` / `§7-P3`），与本文件上方
///   `_payloadCheck` 的「内容牙 P1–P4」（H9）**不是同一套编号**，勿混读。
void _p003WindowBranchCheck(String chunkPrompt, String guideText) {
  final p003 = guideText
      .split('\n')
      .firstWhere((l) => l.startsWith('- P003例外'), orElse: () => '');
  if (p003.isEmpty) {
    fail('§7-P1 不过：例外表内找不到 `- P003例外` 行。');
  }
  // P1-① 窗外分支逐字在（触发条件 + 标的 + 缺哪类信息）
  const windowBranch = [
    '指不出依据时，若缺的是片段外的句子（切换前一条被上一片段截走）',
    '⇒标 `"uncertain": true`（缺前文），交合并阶段裁决',
  ];
  for (final m in windowBranch) {
    if (!p003.contains(m)) fail('§7-P1 不过：P003 行缺窗外分支片段「$m」。');
  }
  // P1-② 兜底必须被限定为「其余」—— 否则旧的无条件方向仍在
  if (!p003.contains('其余指不出依据⇒例外不成立，按正文判定')) {
    fail('§7-P1 不过：兜底句未限定为「其余」⇒ 仍是无条件按正文判定。');
  }
  // P1-③ 旧形态不得复活（「只摘引一条…」直接接兜底 = 窗外分支被抹掉）
  if (p003.contains('只摘引一条即视为指不出依据。指不出依据⇒')) {
    fail('§7-P1 不过：旧形态复活 —— 「只摘引一条…」后直接是无条件兜底。');
  }
  // P3 同向：**切出窗口边界节本体**再断言方向。
  // ★ 不用整条 chunkPrompt.contains —— 那样只能说明「句中某个字还在」：
  //   该节被改成硬判时句子仍在、方向已反，判据会假绿（2026-10-29 独立复核指出，
  //   初版就是这么写的）。且「不要勉强给结论」在跨章依赖节里也有一份同形句，
  //   整条 contains 会被另一节掩盖 ⇒ 必须限定在切片内。
  final bStart = chunkPrompt.indexOf(kBoundaryStartMarker);
  final bEnd = bStart < 0
      ? -1
      : chunkPrompt.indexOf(kBoundaryEndMarker, bStart);
  if (bStart < 0 || bEnd <= bStart) {
    fail(
      '§7-P3 不过：窗口边界节切片锚点失效（start=$bStart end=$bEnd）'
      '⇒ 节标题或其后「块内可自证」对照段已变，须先核 '
      'progressive_diagnosis.dart:526/539 再改 kBoundary*Marker。',
    );
  }
  final boundary = chunkPrompt.substring(bStart, bEnd);
  // 方向三要素：触发条件（依赖片段外信息）+ 禁令（不要勉强给结论）+ 出口（uncertain）
  const boundaryForward = ['依赖片段外信息', '不要勉强给结论', '`"uncertain": true`'];
  for (final m in boundaryForward) {
    if (!boundary.contains(m)) {
      fail(
        '§7-P3 不过：窗口边界节内缺「$m」'
        '⇒ 该节可能已被改成硬判（方向与 P003 相反）。',
      );
    }
  }
  if (!p003.contains('片段外的句子') || !p003.contains('`"uncertain": true`')) {
    fail(
      '§7-P3 不过：P003 行未与窗口边界节同向 —— '
      '缺「片段外的句子」或 `"uncertain": true`。',
    );
  }
}

/// 判据 **§6-牙1…牙5**（`T-20261027-01` H2 · 舰长 2026-10-29「授权 H2 和 H8」·
/// 报批稿 `2026-10-29-报批稿-H2-自由间接引语可错推断判据.md` §6.1）。
///
/// 拦的是自由间接引语（FID）误伤的**判据文本本身**：
///   牙1 ②补 子句在位 · 牙2 可错推断接到后果句 · 牙3 权威断言侧未被放宽侧吃掉
///   牙4 标记词后门堵句在位 · 牙5 ② 的裸禁令不得复活（丙案把「不含他人内心」
///   收窄为「不含叙述者代述的他人内心」，与 ②补 的「所述可以是他人」不再打架）
///   （离线探针另加 **牙6** 推测词列举六词 / **牙7** 定句主口径 —— 只在探针侧，
///    本用例不重复，避免同一串字面量两处各写一份而分家。
///    ★ 牙6 只钉「六词逐字在位」：真源六词后带「等」= **开放列举**，探针不声称闭合。）
///
/// ★ 五条都打在 `_contentLint` 同一条 `p003` **运行时切片行**上：若插入带来换行，
///   `split('\n')` 只取到前半物理行 ⇒ 切片本身即不成立，无需另建行数断言
///   （快照 `meta` 段只做归因、不钉值，见 `prompt_const_anchor.json` 的 `meta.note`）。
/// ★ 本用例是 **fail-fast**：第一条缺串即 `fail`，且同一 `test()` 里更早的
///   `_p003WindowBranchCheck` 会先红 ⇒ 「一起红」在本机读数里观测不到。
///   逐位归因（哪条牙测的是本包新增的东西）由离线变异探针做：
///   `.ai/reports/2026-10-29-H2-负向自检.py`（内存切片变异，不动 `lib/`）。
/// ★ 这**不是行为牙**：拦「判据没写 / 只写一半 / 矛盾复活」，
///   拦不住「模型照旧把 FID 判成漂移」—— 后者须真实链路采样（本机无 key
///   ⇒ 挂 `T-20261024-19`；**本批不得自宣「误伤下降」**）。
void _p003FidBranchCheck(String guideText) {
  final p003 = guideText
      .split('\n')
      .firstWhere((l) => l.startsWith('- P003例外'), orElse: () => '');
  if (p003.isEmpty) {
    fail('§6-牙1 不过：例外表内找不到 `- P003例外` 行 ⇒ 行首形态或切片对象已变。');
  }
  const teeth = <String, String>{
    '牙1（②补 子句在位）': '②补：',
    '牙2（可错推断接到后果句）': '作人物可错推断，即不构成漂移',
    '牙3（权威断言侧仍在 · R-009 侧）': '叙述者以断定口吻陈述超出感知者认知的事实⇒仍判',
    '牙4（标记词不得单独作豁免凭据）': '不得单独作豁免凭据',
  };
  for (final e in teeth.entries) {
    if (!p003.contains(e.value)) {
      fail(
        '${e.key} 不过：P003 行缺「${e.value}」'
        '⇒ ②补 未落地 / 只写一半 / 方向句丢失。',
      );
    }
  }
  // 牙5 反向牙：② 的裸禁令一旦复活 = 与 ②补 的字面矛盾回来了（误伤源原地不动）。
  if (p003.contains('须指认不含他人内心')) {
    fail(
      '§6-牙5 不过：② 支的裸禁令「须指认不含他人内心」复活 —— '
      '与 ②补 的「所述可以是他人」构成字面矛盾，自由间接引语仍会被硬判'
      '（见 2026-10-29 H2 报批稿 §3 裁点① 丙案）。',
    );
  }
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
    _contentLint(collected.guideText);
    _p003WindowBranchCheck(collected.chunkPrompt, collected.guideText);
    _p003FidBranchCheck(collected.guideText);
    _payloadCheck();

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

    print('[const-anchor] 比对通过：三块常量 + 分块 payload 模板与基线字节级一致 ✓');
    for (final k in kPinnedKeys) {
      final a = current[k]! as Map;
      print('[const-anchor]   $k len=${a['len']} fnv=${a['fnv']}');
    }
    expect(diffs, isEmpty);
  });
}
