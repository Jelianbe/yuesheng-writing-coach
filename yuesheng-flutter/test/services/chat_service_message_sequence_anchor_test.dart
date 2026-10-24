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
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/types/teaching_types.dart';

const String kMsgSeqAnchorPath = 'test/snapshots/message_sequence_anchor.json';

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

Future<List<Map<String, Object>>> _captureOne(_Case c) async {
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
    return _sequence(llm.captured);
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
      current[c.name] = await _captureOne(c);
    }

    if (updating) {
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
}
