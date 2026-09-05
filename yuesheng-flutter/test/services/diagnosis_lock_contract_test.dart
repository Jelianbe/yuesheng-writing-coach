// ADR-C65 护栏：诊断落库正确性（N2 成功不落库 / N3-a 焦点越界绕过锁定）
//
// 被守护的缺陷：
//
// **N2**（chat_service.dart 步骤 10）：`treatAsValid` 给 `diagnosis != null`
// 也加了「装配大纲服务 + 章节主引用」两个前置条件——诊断能否落库与有没有
// 装配大纲服务毫无关系。命中时 aborted=true，调用方 :3051 提前 return，
// 步骤 11 的 commitDiagnosisWithHistory 被整个跳过：AI 输出了合法诊断块，
// 用户收到「AI 返回为空」，诊断永久丢失。
//
// **N3-a**（focus id 越界）：prompt 三处明写「current_teaching_focus_id
// 必须从本轮 syndromes 中选取」，但 parser 只验 `is String`、validator 只验
// 类型。越界 id 落库后，下轮 getLatestTeachingFocus 取出它，focus-resolver
// 校验 1「在池中」拦不住（commitDiagnosis 已把本轮症候 UPSERT 进池，
// 落库先于校验），焦点被换走——原锁定症候被绕过。

// ignore_for_file: prefer_initializing_formals, unnecessary_underscores

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
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;

/// Fake LLM 客户端：预设 streamChat 响应（沿用既有夹具）
class FakeLlmClient extends LlmClient {
  final String _fullResponse;
  final int _chunkSize;

  /// K-9 mutation 锚点：streamChat 调用次数（FT-22「只诊断」应恰好 1 次，
  /// Teacher 触发会再走一次 streamChat）
  int chatCalls = 0;

  FakeLlmClient(this._fullResponse, {int chunkSize = 10})
    : _chunkSize = chunkSize;

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    chatCalls++;
    for (int i = 0; i < _fullResponse.length; i += _chunkSize) {
      final end = i + _chunkSize < _fullResponse.length
          ? i + _chunkSize
          : _fullResponse.length;
      callback(
        LlmStreamResponse(
          content: _fullResponse.substring(i, end),
          isDone: false,
        ),
      );
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

// ══════════════ N3-a：纯函数层语料 ══════════════

const String _kInPoolId = 'P012';
const String _kOutOfPoolId = 'P099';

/// 构造诊断块文本。focusId 为 null 时不写该字段
String buildBlock({required String? focusId, String syndromeId = _kInPoolId}) {
  final plan = focusId == null
      ? 'null'
      : '{"current_teaching_focus_id": "$focusId", "focus_reason": "原因"}';
  return '[YS_DIAGNOSIS]\n'
      '{"syndromes":[{"syndrome_id":"$syndromeId","name":"铺垫缺失",'
      '"severity":"L2","evidence":["证据一"],"explanation":"说明"}],'
      '"suggested_actions":["动作一"],"confidence":0.8,'
      '"teaching_plan":$plan}\n'
      '[/YS_DIAGNOSIS]';
}

/// 与 buildBlock 等价的 payload，供 validator 直接消费
Map<String, dynamic> buildPayload({
  required String? focusId,
  String syndromeId = _kInPoolId,
}) => {
  'syndromes': [
    {
      'syndrome_id': syndromeId,
      'name': '铺垫缺失',
      'severity': 'L2',
      'evidence': ['证据一'],
      'explanation': '说明',
    },
  ],
  'suggested_actions': ['动作一'],
  'confidence': 0.8,
  if (focusId != null)
    'teaching_plan': {
      'current_teaching_focus_id': focusId,
      'focus_reason': '原因',
    },
};

void main() {
  // ── 组 1：语料自检（置顶，防空集假绿）────────────────────────────
  group('组1 语料自检', () {
    test('两个 id 必须不同，否则越界用例失去意义', () {
      expect(_kInPoolId, isNot(_kOutOfPoolId));
    });

    test('合规语料：parser 与 validator 都能产出非 null 诊断', () {
      final p = parseDiagnosis(buildBlock(focusId: _kInPoolId));
      expect(p.diagnosis, isNotNull, reason: '语料必须能解析，否则后续断言全废');
      expect(p.diagnosis!.syndromes.single.syndromeId, _kInPoolId);

      final v = validateDiagnosisOutput(
        '正文',
        buildPayload(focusId: _kInPoolId),
      );
      expect(v.diagnosis, isNotNull);
    });
  });

  // ── 组 2：N3-a parser 侧 ────────────────────────────────────────
  group('组2 N3-a parser 焦点越界', () {
    test('合规（∈ syndromes）→ 原样保留', () {
      final d = parseDiagnosis(buildBlock(focusId: _kInPoolId)).diagnosis!;
      expect(d.currentTeachingFocusId, _kInPoolId);
    });

    test('越界（∉ syndromes）→ 置 null', () {
      final d = parseDiagnosis(buildBlock(focusId: _kOutOfPoolId)).diagnosis!;
      expect(
        d.currentTeachingFocusId,
        isNull,
        reason: '越界焦点会绕过诊断锁定，必须拦（ADR-C65 §3.3）',
      );
    });

    test('越界 → notes 留痕 focus_not_in_syndromes', () {
      final r = parseDiagnosis(buildBlock(focusId: _kOutOfPoolId));
      expect(r.notes, contains('focus_not_in_syndromes'));
    });

    test('合规 → notes 不留痕（零行为变更）', () {
      final r = parseDiagnosis(buildBlock(focusId: _kInPoolId));
      expect(r.notes, isNot(contains('focus_not_in_syndromes')));
      expect(r.notes, isEmpty);
    });

    test('越界不丢弃整块诊断（只影响焦点，不放大「输出了但不落库」）', () {
      final r = parseDiagnosis(buildBlock(focusId: _kOutOfPoolId));
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.syndromes, hasLength(1));
      expect(r.rejectReason, isNull);
    });

    test('非 String 焦点 → 置 null（既有行为不变）', () {
      final block = buildBlock(focusId: null).replaceFirst(
        '"teaching_plan":null',
        '"teaching_plan":{"current_teaching_focus_id": 123}',
      );
      final d = parseDiagnosis(block).diagnosis!;
      expect(d.currentTeachingFocusId, isNull);
    });

    test('无 teaching_plan → 置 null（既有行为不变）', () {
      final d = parseDiagnosis(buildBlock(focusId: null)).diagnosis!;
      expect(d.currentTeachingFocusId, isNull);
    });
  });

  // ── 组 3：N3-a validator 侧 ─────────────────────────────────────
  group('组3 N3-a validator 焦点越界', () {
    test('合规（∈ syndromes）→ 原样保留', () {
      final d = validateDiagnosisOutput(
        '正文',
        buildPayload(focusId: _kInPoolId),
      ).diagnosis!;
      expect(d.currentTeachingFocusId, _kInPoolId);
    });

    test('越界（∉ syndromes）→ 置 null', () {
      final d = validateDiagnosisOutput(
        '正文',
        buildPayload(focusId: _kOutOfPoolId),
      ).diagnosis!;
      expect(d.currentTeachingFocusId, isNull);
    });

    test('越界 → warnings 留痕（不得静默）', () {
      final r = validateDiagnosisOutput(
        '正文',
        buildPayload(focusId: _kOutOfPoolId),
      );
      expect(
        r.jsonValidation.warnings.any((w) => w.contains('不在本轮 syndromes 中')),
        isTrue,
      );
    });

    test('合规 → warnings 为空（零行为变更）', () {
      final r = validateDiagnosisOutput(
        '正文',
        buildPayload(focusId: _kInPoolId),
      );
      expect(r.jsonValidation.warnings, isEmpty);
    });

    test('越界不判为 schema 错误（不动 valid，与 N5 裁决一致）', () {
      final r = validateDiagnosisOutput(
        '正文',
        buildPayload(focusId: _kOutOfPoolId),
      );
      expect(r.jsonValidation.errors, isEmpty);
      expect(r.jsonValidation.valid, isTrue);
    });
  });

  // ── 组 4：两条解析路径必须一致（N8 教训）─────────────────────────
  group('组4 两条路径一致性', () {
    for (final focusId in <String?>[_kInPoolId, _kOutOfPoolId, null]) {
      final label = focusId ?? '(无)';
      test('focusId=$label → parser 与 validator 行为一致', () {
        final viaParser = parseDiagnosis(
          buildBlock(focusId: focusId),
        ).diagnosis!;
        final viaValidator = validateDiagnosisOutput(
          '正文',
          buildPayload(focusId: focusId),
        ).diagnosis!;
        expect(
          viaParser.currentTeachingFocusId,
          viaValidator.currentTeachingFocusId,
          reason: '两条路径不一致就会重演 N8（parser 校验、validator 不校验）',
        );
      });
    }
  });

  // ══════════════ N2：端到端（chat_service 集成）══════════════

  group('组5 N2 诊断成功必须落库', () {
    late AppDatabase db;
    late SessionRepository sessionRepo;
    late String sessionId;
    final List<String> errors = <String>[];

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      sessionRepo = SessionRepository(db);
      sessionId = await sessionRepo.createBlankSession();
      errors.clear();
    });

    tearDown(() async => db.close());

    ChatService buildService(LlmClient llm) => ChatService(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      llmClient: llm,
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      editorObservationRepo: EditorObservationRepository(db),
      // 关键：不装配 outlineRepo —— 原实现的两个前置条件之一不成立
      outlineRepo: null,
      // ADR-C74 K-5：诊断提交编排器收紧为 required
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
      ),

      messageInjector: MessageInjector(
        sessionRepo: sessionRepo,

        diagnosisRepo: DiagnosisRepository(db),

        studentModelRepo: StudentModelRepository(db),

        referenceRepo: ReferenceRepository(db),

        chapterRepo: ChapterRepository(db),

        manuscriptRepo: ManuscriptRepository(db),

        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,

          stateRepo: TeachingStateRepository(db),

          diagnosisRepo: DiagnosisRepository(db),

          studentModelRepo: StudentModelRepository(db),

          referenceRepo: ReferenceRepository(db),

          chapterRepo: ChapterRepository(db),
        ),

        material: const MaterialCapabilityImpl(),
      ),
      diagnosisFlowHandler: DiagnosisFlowHandler(
        sessionRepo: SessionRepository(db),
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        teacherSuggestionRepo: TeacherSuggestionRepository(db),
        llmClient: llm,

        messageInjector: MessageInjector(
          sessionRepo: sessionRepo,

          diagnosisRepo: DiagnosisRepository(db),

          studentModelRepo: StudentModelRepository(db),

          referenceRepo: ReferenceRepository(db),

          chapterRepo: ChapterRepository(db),

          manuscriptRepo: ManuscriptRepository(db),

          diagnosisCommitter: DiagnosisCommitter(
            sessionRepo: sessionRepo,

            stateRepo: TeachingStateRepository(db),

            diagnosisRepo: DiagnosisRepository(db),

            studentModelRepo: StudentModelRepository(db),

            referenceRepo: ReferenceRepository(db),

            chapterRepo: ChapterRepository(db),
          ),

          material: const MaterialCapabilityImpl(),
        ),
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
        ),
        diagnosis: const DiagnosisCapabilityImpl(),
        genUi: const GenUiParser(),
      ),
    );

    SendMessageCallbacks callbacks() => SendMessageCallbacks(
      onStream: (_) {},
      onComplete: (_, _) {},
      onError: (e) => errors.add(e),
    );

    SendMessageOptions options() => const SendMessageOptions(
      phase: TeachingPhase.p0Engage,
      attitude: AttitudeLevel.doubao,
    );

    test('只输出诊断块 + 未装配大纲 → 诊断仍落库（原实现会永久丢失）', () async {
      final svc = buildService(FakeLlmClient(buildBlock(focusId: _kInPoolId)));
      await svc.sendMessage(
        sessionId,
        // FT-22：命中「只诊断」边界声明 → 跳过 Teacher stream，
        // 保证 combinedContent 为空（模拟协议块占据首位的场景）
        '只诊断就好，不要给建议',
        callbacks(),
        options(),
      );

      final problems = await DiagnosisRepository(
        db,
      ).listActiveProblems(sessionId);

      expect(problems, isNotEmpty, reason: 'N2：诊断块合法就必须落库，不得因未装配大纲服务而丢弃');
      expect(problems.first.syndromeId, _kInPoolId);
      expect(errors, isEmpty, reason: '诊断成功不该报「AI 返回为空」');
    });

    test('落库同时写入 assistant 消息（用户看得到产出）', () async {
      final svc = buildService(FakeLlmClient(buildBlock(focusId: _kInPoolId)));
      await svc.sendMessage(sessionId, '只诊断就好，不要给建议', callbacks(), options());

      final messages = await sessionRepo.listMessages(sessionId);
      final assistant = messages.where((m) => m.role == 'assistant');
      expect(assistant, isNotEmpty);
      expect(assistant.last.content, isNotEmpty);
    });

    test('FT-22 命中「只诊断」→ Teacher 不触发（streamChat 仅诊断 1 次）', () async {
      final fake = FakeLlmClient(buildBlock(focusId: _kInPoolId));
      final svc = buildService(fake);
      await svc.sendMessage(sessionId, '只诊断就好，不要给建议', callbacks(), options());
      expect(
        fake.chatCalls,
        1,
        reason:
            'FT-22：命中只诊断边界应跳过 Teacher stream，只产生诊断 1 次 chat；'
            '触发 Teacher 会再走一次 streamChat（K-9 _triggerTeacherForDiagnosis）',
      );
    });
    test('对照组：三空齐发（正文空+诊断空+实体空）→ 仍走 onError（RN 原语义）', () async {
      final svc = buildService(FakeLlmClient(''));
      await svc.sendMessage(sessionId, '只诊断就好，不要给建议', callbacks(), options());

      expect(errors, contains('AI 返回为空'), reason: '三空齐发必须维持 RN 原语义，本批不改这条');
      final problems = await DiagnosisRepository(
        db,
      ).listActiveProblems(sessionId);
      expect(problems, isEmpty);
    });
  });
}
