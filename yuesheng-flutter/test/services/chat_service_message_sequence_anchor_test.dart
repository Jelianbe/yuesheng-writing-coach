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
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
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
  const _Case(
    this.name,
    this.phase,
    this.attitude,
    this.subphase,
    this.isBeginner,
  );
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
    studentModelRepo: StudentModelRepository(db),
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
    manuscriptRepo: ManuscriptRepository(db),
    llmClient: llmClient,
    teacherSuggestionRepo: TeacherSuggestionRepository(db),
    editorObservationRepo: EditorObservationRepository(db),
    diagnosisCommitter: committer(),
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
      _kContent,
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, _) {},
        onError: (_) {},
      ),
      SendMessageOptions(phase: c.phase, attitude: c.attitude),
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

    final current = <String, Object>{
      'meta': {'note': 'chat_service 边界消息序列结构锚点'},
    };
    for (final c in _kCases) {
      current[c.name] = await _captureOne(c);
    }

    final file = File(kMsgSeqAnchorPath);
    if (updating || !file.existsSync()) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(current)}\n',
        );
      print('[msg-seq] 基线已生成: $kMsgSeqAnchorPath（${_kCases.length} 例）');
      expect(file.existsSync(), isTrue);
      return;
    }

    final stored = jsonDecode(file.readAsStringSync());
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
