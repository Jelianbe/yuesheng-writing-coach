// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// chat_service 边界「消息序列结构」锚点（字节级）
//
// 背景（docs/research/2026-09-13-injection-refinement-anchor-coverage.md §2）：
//   既有 7 个 chat_service_*_injection_test 的断言是
//   `messages.where(role=='system')..join('\n') + contains(...)` —— **只测子串存在**，
//   无条数/顺序/逐条指纹 ⇒ 「messages[0] 拆成 L1+L2 两条」（B2）、
//   「装配层条件化」（B3）**完全不被拦**。
//
// 本测试补「结构维度」：对代表性 (phase, attitude, subphase, isBeginner)，
// 在 **chat_service 边界**捕获**全部** messages，断言：
//   ① 条数  ② 有序逐条 (role, content.len, FNV-1a64(content))
// 从而「拆消息 / 改顺序 / 增删段 / 换装配」都会现形。
//
// 快照：test/snapshots/message_sequence_anchor.json（独立文件；不复用
//       skill_prompt_anchor.json，也不改其任何值）。
// 算法：UTF-16 code units 的 FNV-1a 64 位（同 skill_prompt_anchor_test.dart:196-203）。
//
// 用法：
//   flutter test test/services/chat_service_message_sequence_anchor_test.dart
//   UPDATE_SNAPSHOTS=true flutter test test/services/chat_service_message_sequence_anchor_test.dart
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_injection_service.dart'
    show InjectionSegments;
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/types/teaching_types.dart';

import '../helpers/anchor_content_floor.dart';

const String kMsgSeqAnchorPath = 'test/snapshots/message_sequence_anchor.json';

/// 五段读数的**独立**快照（ADR-0009 · T-20261024-13 A 块）。
///
/// ★ 为什么不塞进 [kMsgSeqAnchorPath]：旧快照的顶层键集合受「双向键集合判据」
///   看守（`T-20261024-14` A 块），新增一个顶层键要同时改两处排除清单 ——
///   那是在**动 fail-closed 判据**。分段是新读数面 ⇒ 独立文件零改动旧判据。
const String kSegmentsAnchorPath =
    'test/snapshots/injection_segments_anchor.json';

/// 中性正文（compose 意图：不触发诊断协议 / 意图注入 / 颗粒度注入）。
const String _kContent = '他推开门，风灌了进来，桌上的信纸被吹落在地。';

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

/// 捕获 chat_service 边界**全部** messages 的 Fake LLM。
class _CaptureLlmClient extends LlmClient {
  List<ChatMessage> captured = <ChatMessage>[];

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    captured = List<ChatMessage>.from(messages);
    callback(const LlmStreamResponse(content: '收到，我们开始。', isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// 一个代表性装配语境。
class _Case {
  final String name;
  final TeachingPhase phase;
  final AttitudeLevel attitude;
  final TeachingSubphase? subphase;
  final bool isBeginner;

  /// 用户消息正文；默认中性 compose 正文（不触发诊断）。
  final String content;

  /// 待诊断全文；默认 null（不触发诊断协议注入）。
  final String? chapterFullText;
  const _Case(
    this.name,
    this.phase,
    this.attitude,
    this.subphase,
    this.isBeginner, {
    this.content = _kContent,
    this.chapterFullText,
  });
}

/// 覆盖 5 个可达 L2Mode（none/beginner/diagnosis/training/advanced）
/// + attitude 变体 + isBeginner 变体。
const List<_Case> _kCases = [
  _Case(
    'p0_yuesheng_none',
    TeachingPhase.p0Engage,
    AttitudeLevel.yuesheng,
    null,
    false,
  ),
  _Case(
    'p0_yuesheng_beginner',
    TeachingPhase.p0Engage,
    AttitudeLevel.yuesheng,
    null,
    true,
  ),
  _Case(
    'p1_yuesheng_diagnosis',
    TeachingPhase.p1World,
    AttitudeLevel.yuesheng,
    null,
    false,
  ),
  _Case(
    'p2_yuesheng_diagnosis',
    TeachingPhase.p2PracticeLoop,
    AttitudeLevel.yuesheng,
    TeachingSubphase.diagnosis,
    false,
  ),
  _Case(
    'p2_yuesheng_training',
    TeachingPhase.p2PracticeLoop,
    AttitudeLevel.yuesheng,
    TeachingSubphase.practice,
    false,
  ),
  // P0-2：user 侧诊断注入（协议后缀 + 全貌呈现）此前不在任何锚点网内——
  // 用例带 chapterFullText 非空 + 诊断强信号措辞，把 user 侧注入纳入有序指纹。
  _Case(
    'p2_yuesheng_diagnosis_fulltext',
    TeachingPhase.p2PracticeLoop,
    AttitudeLevel.yuesheng,
    TeachingSubphase.diagnosis,
    false,
    content: '请诊断我这段文字',
    chapterFullText:
        '少年推开门，风灌了进来。桌上的信纸被吹落在地，他捡起来读了一遍。'
        '窗外的雨越下越大，他决定今天就出发。',
  ),
  _Case(
    'p3_yuesheng_advanced',
    TeachingPhase.p3Training,
    AttitudeLevel.yuesheng,
    null,
    false,
  ),
  _Case(
    'p3_sensei_advanced',
    TeachingPhase.p3Training,
    AttitudeLevel.sensei,
    null,
    false,
  ),
  _Case(
    'p4_yuesheng_beginner',
    TeachingPhase.p4Review,
    AttitudeLevel.yuesheng,
    null,
    true,
  ),
];

ChatService _buildChatService(AppDatabase db, LlmClient llmClient) {
  final sessionRepo = SessionRepository(db);
  DiagnosisCommitter committer() => DiagnosisCommitter(
    sessionRepo: sessionRepo,
    stateRepo: TeachingStateRepository(db),
    diagnosisRepo: DiagnosisRepository(db),
    studentModelRepo: StudentModelRepository(db),
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
  );
  MessageInjector injector() => MessageInjector(
    sessionRepo: sessionRepo,
    diagnosisRepo: DiagnosisRepository(db),
    studentModelRepo: StudentModelRepository(db),
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
    manuscriptRepo: ManuscriptRepository(db),
    diagnosisCommitter: committer(),
    material: const MaterialCapabilityImpl(),
  );
  return ChatService(
    sessionRepo: sessionRepo,
    stateRepo: TeachingStateRepository(db),
    diagnosisRepo: DiagnosisRepository(db),
    referenceRepo: ReferenceRepository(db),
    llmClient: llmClient,
    messageInjector: injector(),
    diagnosisFlowHandler: DiagnosisFlowHandler(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      llmClient: llmClient,
      messageInjector: injector(),
      diagnosisCommitter: committer(),
      diagnosis: const DiagnosisCapabilityImpl(),
      genUi: const GenUiParser(),
    ),
  );
}

/// 逐条序列指纹：`[{role, len, fnv}, ...]`（有序）。
List<Map<String, Object>> _sequence(List<ChatMessage> messages) => messages
    .map(
      (m) => <String, Object>{
        'role': m.role,
        'len': m.content.length,
        'fnv': _fnv1a64(m.content).toRadixString(16),
      },
    )
    .toList();

/// 单例捕获结果：消息序列 + （若发生了注入）五段读数（ADR-0009）。
typedef _Capture = ({List<Map<String, Object>> seq, Map<String, Object>? segs});

/// 五段读数：`{段名: {len, fnv}}`（ADR-0009 · T-20261024-13 A 块）。
///
/// ★ 段名与顺序**取自 `InjectionSegments.names` / `byIndex`**（生产侧唯一真源），
///   测试侧不另抄一份 —— 抄一份就是第二真源，段顺序一改两边静默分叉。
Map<String, Object> _segmentsOf(InjectionSegments seg) {
  final parts = seg.byIndex;
  return <String, Object>{
    for (var i = 0; i < InjectionSegments.names.length; i++)
      InjectionSegments.names[i]: <String, Object>{
        'len': parts[i].length,
        'fnv': _fnv1a64(parts[i]).toRadixString(16),
      },
  };
}

Future<_Capture> _captureOne(_Case c) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  try {
    final sessionRepo = SessionRepository(db);
    final sessionId = await sessionRepo.createBlankSession();
    // 阶段必须写 DB：_prepareTeachingState 以 DB currentPhase 优先于
    // options.phase（chat_service.dart:693-694），不写 DB 则所有用例都停在
    // createBlankSession 默认的 P0_ENGAGE，装配维度会退化。
    final stateRepo = TeachingStateRepository(db);
    await stateRepo.updatePhase(sessionId, c.phase.value);
    if (c.isBeginner) {
      await stateRepo.updateBeginnerLevel(
        sessionId,
        BeginnerLevel.n1Elements.value,
      );
    }
    final llm = _CaptureLlmClient();
    final service = _buildChatService(db, llm);
    await service.sendMessage(
      sessionId,
      c.content,
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, _) {},
        onError: (_) {},
      ),
      SendMessageOptions(
        phase: c.phase,
        attitude: c.attitude,
        chapterFullText: c.chapterFullText,
      ),
      subphase: c.subphase,
    );
    final seg = service.lastInjectionSegments;
    return (
      seq: _sequence(llm.captured),
      segs: seg == null ? null : _segmentsOf(seg),
    );
  } finally {
    await db.close();
  }
}

List<String> _diff(String path, dynamic a, dynamic b) {
  final out = <String>[];
  if (a is Map && b is Map) {
    final keys = <String>{...a.keys.cast<String>(), ...b.keys.cast<String>()};
    for (final k in keys) {
      out.addAll(_diff('$path.$k', a[k], b[k]));
    }
  } else if (a is List && b is List) {
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      out.addAll(
        _diff(
          '$path[$i]',
          i < a.length ? a[i] : null,
          i < b.length ? b[i] : null,
        ),
      );
    }
    if (a.length != b.length) {
      out.add('$path.length: ${a.length} → ${b.length}');
    }
  } else if (a != b) {
    out.add('$path: ${a ?? '∅'} → ${b ?? '∅'}');
  }
  return out;
}

// ─────────────────────────────────────────────────────────────
// 重建下限判据（T-20261024-15 · L4 支撑层）
//
// 由来：`T-20261024-14` A 块在重建分支只做**双向键集合**（`missingKeys` /
//   `extraKeys`）——「写完整没有」，**没有下限**。每例都捕获成空序列同样
//   「键齐」，于是写出的基线与「装配全塌」的产物一致，此后长期绿。
//
// 口径（`DECISIONS §4-260⑤` 舰长 2026-10-24 23:31 已裁，不得改）：
//   ① 每例**非空** + 总数 ≥ 旧基线 **50%**；② 越限 = **fail**。
//
// 落点只在**重建分支**：比对分支的判据面是「与基线逐条目一致」，塌陷基线在
//   那里表现为「当前 ≠ 基线」⇒ 本来就会红。
// ★ 判据在**写盘之前**：失败必须**不写**，否则「红了但文件已脏」。
// ─────────────────────────────────────────────────────────────

/// F1 + F2：每例非空。不过即 `fail`（**不写盘**）。
///
/// F1 = 每例消息条数 ≥ 1（空序列 = 装配塌陷最直接的表现）；
/// F2 = 该例内不得出现**空消息**（`len < 1` 或 `role` 为空串）。
/// ★ 只查 F1 不够：塌陷的另一种形态是「条数没变、每条 content 清空」——
///   39 条 `len=0` 的消息在 F1 下全部算「非空」，塌陷照样过关。
void _assertPerCaseNonEmpty(Map<String, Object> current) {
  final emptyCases = <String>[];
  final emptyMessages = <String>[];
  for (final c in _kCases) {
    final seq = (current[c.name]! as List).cast<Map<String, Object>>();
    if (seq.isEmpty) {
      emptyCases.add(c.name);
      continue;
    }
    for (var i = 0; i < seq.length; i++) {
      final len = seq[i]['len'] as int;
      final role = seq[i]['role'] as String;
      if (len < 1 || role.isEmpty) {
        emptyMessages.add('${c.name}[$i](role=$role,len=$len)');
      }
    }
  }
  if (emptyCases.isEmpty && emptyMessages.isEmpty) return;
  fail(
    '[msg-seq] 重建下限不过（F1 每例条数 / F2 空消息），**已拒绝写盘**：\n'
    '  F1 整例空序列 ${emptyCases.length} 例：$emptyCases\n'
    '  F2 空消息 ${emptyMessages.length} 条：'
    '${emptyMessages.take(12).toList()}'
    '${emptyMessages.length > 12 ? ' …' : ''}\n'
    '  ★ 这多半是装配塌陷（DB fixture 失效 / 注入装配异常被吞 / '
    'capture 到的 messages 为空），**不是**「消息变少了」。\n'
    '  空壳基线一旦落盘，此后长期绿：判据在跑，比的是空对空。\n'
    '  排查真因后确需重写基线：UPDATE_SNAPSHOTS=true。',
  );
}

/// 读旧基线的用例子树（去掉 `meta`）；返回 `null` = 无可比基线。
///
/// 「不可解析」（非 JSON / 顶层非对象）一律**默认 fail**（除非显式豁免）：
/// `旧快照损坏 + UPDATE_SNAPSHOTS=true` 是**洗白基线最省力的入口**
/// （比装配塌陷更容易发生）。留开关是为了快照真坏时还能修。
Map<String, dynamic>? _loadBaselineCases(File file, {required bool exists}) {
  if (!exists) return null; // 首次生成：F3 不生效（调用处打告警）
  final raw = file.readAsStringSync();
  String? why;
  // ★ 失败形态标签：四种「基线不可用」共用同一出口，靠它区分（否则下次又分不清）。
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
      final body = <String, dynamic>{
        for (final e in decoded.entries)
          if (e.key != 'meta') e.key: e.value,
      };
      // ★ 「体积为 0」的旧基线**不算有基线**：体积 0 ⇒ 比率下限退化为
      //   `ceil(0/2) == 0` ⇒ 任何内容都 `≥ 0` ⇒ **F3 对任何内容恒绿**。
      //   它与「不可解析」是同一类失效（下限无法生效），必须走同一条 fail 通路，
      //   **不另造出口**。三种形态分开报，否则下次又分不清是哪种：
      //     ① 空对象 `{}`（一眼看得出）
      //     ② 只有 `meta`、无用例键
      //     ③ **键齐、但所有 `len` / `length` 都是 0**（最隐蔽：键集合判据全过）
      if (body.isEmpty) {
        kind = decoded.isEmpty ? '空对象 {}' : '只有 meta';
        why = decoded.isEmpty ? '顶层是空对象 `{}`，没有任何键' : '顶层只有 `meta`，没有任何用例键';
      } else {
        final baselineVolume = anchorMeasureVolume(body).content;
        if (baselineVolume == 0) {
          kind = '键齐但全零长度';
          why =
              '用例键齐备，但内容体积（单调代理）为 0'
              '（所有 `len` / `length` 均为 0，且无叶字符串）';
        } else {
          return body;
        }
      }
    }
  }
  final waived =
      (Platform.environment['ALLOW_FLOORLESS_REBUILD'] ?? '') == 'true';
  if (!waived) {
    fail(
      '[msg-seq] 旧基线不可解析 ⇒ 比率下限无法生效（或：可解析但不可用）：'
      '$kMsgSeqAnchorPath\n'
      '  本次形态：$kind\n'
      '  判定依据：$why\n'
      '  ★ 可解析但不可用 = ① 空对象 `{}` ② 只有 `meta` 无用例键 '
      '③ **键齐但所有 `len` / `length` 均为 0**。\n'
      '    三者都让下限退化为 0 ⇒ F3 对任何内容恒绿（fail-open），与「文件损坏」同罪。\n'
      '  两条出口：\n'
      '    ① 恢复基线：git checkout -- $kMsgSeqAnchorPath\n'
      '    ② 确认要丢弃旧基线：ALLOW_FLOORLESS_REBUILD=true'
      '（会打双重告警，且本次不设任何下限）',
    );
  }
  print(
    '[msg-seq][告警] 已放弃比率下限：旧基线不可解析或不可用（$kind：$why）'
    '⇒ 本次未做任何比对，这不是校验通过。',
  );
  print('[msg-seq][告警] 路径：$kMsgSeqAnchorPath；本次为「无下限重建」，须人工复核体量。');
  return null;
}

/// F3：总数（**内容体积（单调代理）**）≥ 旧基线 50%。不过即 `fail`（**不写盘**）。
///
/// 口径见 `test/helpers/anchor_content_floor.dart`：叶字符串长度 + 仅 `len` /
/// `length` 键的整数值；其余整数单列 `nonContentInt`，**不计体积**。
/// ⚠️ 该指标**不得当作字节数 / token 成本引用**（同一段原文经 `len` 被算了两次）。
void _assertVolumeFloor(
  Map<String, Object> current, {
  required File file,
  required bool exists,
}) {
  Map<String, Object> body() => <String, Object>{
    for (final e in current.entries)
      if (e.key != 'meta') e.key: e.value,
  };

  final newMeasure = anchorMeasureVolume(body());
  final newVolume = newMeasure.content;
  final baseline = _loadBaselineCases(file, exists: exists);
  if (baseline == null) {
    if (!exists) {
      print(
        '[msg-seq][告警] 本次为首次生成，比率下限未生效：$kMsgSeqAnchorPath\n'
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
      '[msg-seq] 重建内容体积（单调代理）低于比率下限，**已拒绝写盘**：\n'
      '  实际：$newVolume\n'
      '  下限：$floor（旧基线 $baselineVolume 的 50%）\n'
      '  非长度整数（不计体积）：${newMeasure.nonContentInt}'
      '（旧基线 ${baselineMeasure.nonContentInt}）\n'
      '  ★ 键齐但内容腰斩 = 装配塌陷的典型形态（DB fixture 失效 / 注入异常被吞）。\n'
      '  ★ 该指标是「内容体积（单调代理）」，**不得当作字节数 / token 成本引用**。\n'
      '  确为有意的语料缩减须经评审并在 .ai/DECISIONS.md 登记；'
      '确认不设下限时：ALLOW_FLOORLESS_REBUILD=true。',
    );
  }
  print(
    '[msg-seq] 重建下限通过：内容体积（单调代理）$newVolume ≥ 下限 $floor'
    '（旧基线 $baselineVolume 的 50%）；'
    '非长度整数（不计体积）${newMeasure.nonContentInt}。',
  );
}

void main() {
  test('chat_service 消息序列结构锚点：有序 (role,len,fnv) 逐条不变', () async {
    final updating = (Platform.environment['UPDATE_SNAPSHOTS'] ?? '') == 'true';
    final file = File(kMsgSeqAnchorPath);
    final exists = file.existsSync();

    // ── fail-closed 守卫（T-20261024-13 B 块）────────────────────────────
    // 旧写法 `if (updating || !file.existsSync())` 把两件事并成一个分支：
    //   「显式重生成」与「快照缺失」⇒ 快照被误删 / 误移 / 未检出时本用例**照样绿**，
    //   并把当前装配静默写成新基线（此刻 lib 侧若有漂移，基线即被替换成漂移后的值
    //   ⇒ 之后再不会红）。
    // 语义对齐门禁 18（scripts/gate.sh:769-772 缺失分支 + :958-960 汇总判定）：
    //   skill_prompt_anchor.json 缺失 ⇒ RC=SKIP ⇒ DEGRADED ⇒ rc≠0。
    //   同一对快照不应有两种相反的失效语义。
    // ★ 守卫前置于 capture：否则 9 次 DB 装配中任一环节抛错会先红，
    //   「快照缺失」这个真因会被后者的报错遮住（判据落点须指向缺失本身）。
    if (!exists && !updating) {
      fail(
        '[msg-seq] 锚点快照缺失：$kMsgSeqAnchorPath\n'
        '  ★ 快照文件缺失 = 事故，不是常态（该文件本应随仓库一起检出）。\n'
        '  缺失时**不得**自动生成基线 —— 那等于用「当前行为」重写判据，'
        '任何漂移都会被静默转绿。\n'
        '  先查三因：误删 / 误移 / 未检出'
        '（git status --porcelain、git ls-files test/snapshots/）。\n'
        '  确需重建（基线变更须可对账、须经评审）：\n'
        '    UPDATE_SNAPSHOTS=true flutter test '
        'test/services/chat_service_message_sequence_anchor_test.dart',
      );
    }

    final current = <String, Object>{
      'meta': {'note': 'chat_service 边界消息序列结构锚点'},
    };
    for (final c in _kCases) {
      final cap = await _captureOne(c);
      current[c.name] = cap.seq;
    }

    if (updating) {
      // ── 基线非退化判据（T-20261024-15 · 重建分支专属）──────────────
      // 顺序：F1/F2（纯内存，先拦最明显的塌陷）→ F3（要读旧基线，含 IO 与
      // 「不可解析」分支）。两者都在 `writeAsStringSync` **之前**。
      _assertPerCaseNonEmpty(current);
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
        '[msg-seq][告警] UPDATE_SNAPSHOTS=true ⇒ 基线被强制覆盖：'
        '$kMsgSeqAnchorPath（${_kCases.length} 例）',
      );
      print(
        '[msg-seq][告警] 本次**未做任何比对**，这不是校验通过；'
        '原快照${hadSnapshot ? '已被丢弃' : '本就不存在（本次为新建）'}。',
      );
      print('[msg-seq][告警] 提交前必须逐条复核 git diff $kMsgSeqAnchorPath。');

      // 回读校验：写入成功 ≠ 写出的是完整基线（截断 / 空文件同样「存在」）。
      final reread = jsonDecode(file.readAsStringSync());
      final written = reread is Map<String, dynamic>
          ? reread
          : const <String, dynamic>{};
      final missingKeys = <String>[
        for (final c in _kCases)
          if (!written.containsKey(c.name)) c.name,
      ];
      // 回读校验的第二半：**多余键**（T-20261024-14 A 块同族判据）。
      // 双向键集合判据在「比对分支」只作用于已有基线；重建分支若把已删用例的旧键
      // 一起写回（合并式写入 / 半截覆盖），同样会让判据面里混入不存在的对象。
      // ⚠️ 诚实边界：本判据在当前写法下**近乎恒绿** —— 写入源就是 `current`，
      //    其键集由 `_kCases` 直接生成，除非写出侧被改坏（截断 / 追加旧键）才会命中。
      //    它是防御性检查，**不构成「双向判据有效」的证据**；证据在比对分支的 A1。
      final extraKeys = <String>[
        for (final k in written.keys)
          if (k != 'meta' && !_kCases.any((c) => c.name == k)) k,
      ];
      if (extraKeys.isNotEmpty) {
        fail(
          '[msg-seq] 基线写入出现多余用例键 ${extraKeys.length} 个：$extraKeys\n'
          '  ★ 重建分支只应写出 _kCases 里的 ${_kCases.length} 个用例键 + meta。',
        );
      }
      if (missingKeys.isNotEmpty) {
        fail(
          '[msg-seq] 基线写入不完整，缺 ${missingKeys.length} 个用例键：'
          '$missingKeys',
        );
      }
      expect(file.existsSync(), isTrue);
      return;
    }

    // ── 结构守卫（T-20261024-14 C 块）──────────────────────────────────
    // 旧行为：快照 0 字节 ⇒ `FormatException: Unexpected end of input`；
    //         顶层是数组 `[]` ⇒ `type 'String' is not a subtype of type 'int' of 'index'`。
    // 两者都红得对，但**指向错**：报错像是「比对逻辑有 bug」，真因是快照文件结构非法
    // ⇒ 后来的人会去改比对代码，而不会去看快照文件。
    // 判据（C1 / C2）：失败信息必须含「快照结构非法」+ 文件路径 + 实际类型，
    // 且不得出现 `FormatException` / `subtype of type 'int' of 'index'`。
    final rawSnapshot = file.readAsStringSync();
    if (rawSnapshot.trim().isEmpty) {
      fail(
        '[msg-seq] 快照结构非法：$kMsgSeqAnchorPath 为 0 字节（或仅空白）\n'
        '  ★ 真因是快照文件被截断/清空，不是比对逻辑出错。\n'
        '  先查：git status --porcelain $kMsgSeqAnchorPath ；'
        '需要可用基线时 git checkout -- $kMsgSeqAnchorPath 。',
      );
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(rawSnapshot);
    } on FormatException catch (e) {
      // 兜住「非 JSON」这一大类（截断 / 编码坏 / 手改成 YAML 等）。
      fail(
        '[msg-seq] 快照结构非法：$kMsgSeqAnchorPath 不是合法 JSON\n'
        '  解析器原文：${e.message}（偏移 ${e.offset}）\n'
        '  ★ 真因是快照文件损坏，不是比对逻辑出错。',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      fail(
        '[msg-seq] 快照结构非法：$kMsgSeqAnchorPath 顶层应为 JSON 对象，'
        '实际类型为 ${decoded.runtimeType}\n'
        '  ★ 真因是快照结构被写错（顶层写成了数组/标量），不是比对逻辑出错。',
      );
    }
    final Map<String, dynamic> stored = decoded;

    // ── 双向键集合判据（T-20261024-14 A 块）────────────────────────────
    // 旧 `_diff` 只按 `_kCases` **单向**迭代 ⇒ `stored` 里**多出来的顶层键永远不会被读到**
    // ⇒ 基线里留着一个已删/已改名用例的键，测试照样绿。
    // 这与「快照缺失即自动生成并通过」是同一族失效：**判据面静默缩小，门禁还在跑**。
    // 判据取**集合相等**（不是包含）：少一个键 = 覆盖缩水；多一个键 = 判据面里混着
    // 已不存在的对象。两个方向都必须红。
    final expectedNames = <String>{for (final c in _kCases) c.name};
    final storedNames = stored.keys.toSet()..remove('meta');
    final missingNames = expectedNames.difference(storedNames).toList()..sort();
    final extraNames = storedNames.difference(expectedNames).toList()..sort();
    if (missingNames.isNotEmpty || extraNames.isNotEmpty) {
      fail(
        '[msg-seq] 基线用例键集合与 _kCases 不相等（双向判据）：\n'
        '  基线缺少 ${missingNames.length} 个键：$missingNames\n'
        '  基线多出 ${extraNames.length} 个键：$extraNames\n'
        '  ★ 多余键多为已删/已改名用例的残留 ⇒ 判据面已静默缩小，'
        '**不是**「无影响的旧数据」，必须清理或在 _kCases 里说明其来历。\n'
        '  ★ 缺少键 ⇒ 基线未覆盖该用例（覆盖缩水）。\n'
        '  确需重建（基线变更须可对账、须经评审）：\n'
        '    UPDATE_SNAPSHOTS=true flutter test '
        'test/services/chat_service_message_sequence_anchor_test.dart',
      );
    }

    final diffs = <String>[];
    for (final c in _kCases) {
      diffs.addAll(_diff(c.name, stored[c.name], current[c.name]));
    }

    if (diffs.isNotEmpty) {
      print('[msg-seq] 检测到 ${diffs.length} 处消息序列结构漂移：');
      for (final d in diffs.take(40)) {
        print('  - $d');
      }
      if (diffs.length > 40) {
        print('  ... 其余 ${diffs.length - 40} 处省略');
      }
      fail('chat_service 消息序列结构漂移（${diffs.length} 处），见上方 diff。');
    }

    print('[msg-seq] 比对通过：消息序列结构与基线一致 ✓');
    expect(diffs, isEmpty);
  });

  // ─────────────────────────────────────────────────────────────
  // 诊断注入五段读数锚点（ADR-0009 · T-20261024-13 A 块）
  //
  // 为什么按段量：整条 1583 里 1511 是系统注入（suffix 977 + directExplain 349
  //   + fadingBlock 185），红线却主要由**学员正文变长**触发 ⇒ 两个方向互相掩盖：
  //   正文变长顶红（假红）、支架膨胀被正文缩短抵消（假绿）。
  // 段 = 拼接边界（`InjectionSegments`），不是空行 —— 空行段数随用户输入变化。
  // ─────────────────────────────────────────────────────────────
  test('诊断注入五段读数锚点：逐段 (len,fnv) 不变（ADR-0009）', () async {
    final updating = (Platform.environment['UPDATE_SNAPSHOTS'] ?? '') == 'true';
    final file = File(kSegmentsAnchorPath);
    final exists = file.existsSync();

    if (!exists && !updating) {
      fail(
        '[seg-anchor] 分段快照缺失：$kSegmentsAnchorPath\n'
        '  ★ 缺失 = 事故，不是常态（不自动重建 —— 那等于用当前行为重写判据）。\n'
        '  重建：UPDATE_SNAPSHOTS=true flutter test '
        'test/services/chat_service_message_sequence_anchor_test.dart',
      );
    }

    final current = <String, Object>{
      'meta': {'note': '诊断注入五段读数锚点（ADR-0009）'},
    };
    var injected = 0;
    for (final c in _kCases) {
      final cap = await _captureOne(c);
      final segs = cap.segs;
      if (segs == null) continue;
      injected++;
      if (segs.length != InjectionSegments.segmentCount) {
        fail(
          '[seg-anchor] ${c.name} 分段数 ${segs.length} ≠ '
          '${InjectionSegments.segmentCount}（缺段 = 没量到，不许只判前 N 段）',
        );
      }
      current[c.name] = segs;
    }
    // 空扫不是通过：9 例里零例注入 ⇒ 判据面为空
    if (injected == 0) {
      fail('[seg-anchor] 9 例里零例发生注入 ⇒ 分段判据面为空（空扫不是通过）');
    }

    if (updating) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(current)}\n',
        );
      final reread = jsonDecode(file.readAsStringSync());
      final written = reread is Map<String, dynamic>
          ? reread
          : const <String, dynamic>{};
      expect(
        written.keys.where((k) => k != 'meta').length,
        injected,
        reason: '回读键数必须等于本次注入例数（写到一半 = 半截基线）',
      );
      print(
        '[seg-anchor][告警] UPDATE_SNAPSHOTS=true ⇒ 已重写 $kSegmentsAnchorPath'
        '（$injected 例注入；本次**未做比对**，这不是校验通过）',
      );
      return;
    }

    final decoded = jsonDecode(file.readAsStringSync());
    final stored = decoded is Map<String, dynamic>
        ? decoded
        : const <String, dynamic>{};
    final diffs = <String>[];
    for (final c in _kCases) {
      if (!current.containsKey(c.name)) continue;
      diffs.addAll(_diff(c.name, stored[c.name], current[c.name]));
    }
    if (diffs.isNotEmpty) {
      print('[seg-anchor] 检测到 ${diffs.length} 处分段漂移：');
      for (final d in diffs.take(40)) {
        print('  - $d');
      }
      fail('诊断注入五段读数漂移（${diffs.length} 处），见上方 diff。');
    }
    print('[seg-anchor] 比对通过：五段读数与基线一致 ✓');
    expect(diffs, isEmpty);
  });
}
