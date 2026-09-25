// C103 回归：长文（批处理）诊断链路 commitDiagnosisFromContent 补齐
// 原先缺失的 GenUI 卡片 + 教师建议触发（AI-002：长/短链路下游副作用一致）。
//
// 背景：原长文链路只跑 _runDiagnosisCommitSequence（诊断卡 + 阶段迁移 + 风格画像），
// 跳过 GenUI 卡片 / 教师建议；短链路 commitDiagnosisAndSuggestions 跑全套。
// 本文件锁定「长文链路现在也会插入 GenUI 卡、并在 chapterContent 非空时触发
// 教师 LLM」——不回归到「长文不展示 GenUI / 不触发教师」。

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
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/types/teaching_types.dart';

// 仅记录是否被调用（长文链路唯一的 LLM 调用就是教师建议，故命中即证明触发）。
class _RecordingLlmClient extends LlmClient {
  _RecordingLlmClient(this._fullResponse);
  final String _fullResponse;
  int streamChatCalls = 0;

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    streamChatCalls++;
    if (_fullResponse.isNotEmpty) {
      callback(LlmStreamResponse(content: _fullResponse, isDone: false));
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late TeachingStateRepository stateRepo;
  late DiagnosisRepository diagnosisRepo;
  late StudentModelRepository studentModelRepo;
  late TeacherSuggestionRepository teacherSuggestionRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    stateRepo = TeachingStateRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
    teacherSuggestionRepo = TeacherSuggestionRepository(db);
  });

  tearDown(() async => db.close());

  String diagnosisResp() =>
      '诊断完成。\n[YS_DIAGNOSIS]\n{"syndromes":['
      '{"syndrome_id":"s1","name":"叙事含糊","severity":"L2",'
      '"evidence":[],"explanation":"测试"}],"suggested_actions":[],'
      '"confidence":0.8,"suggested_phase":"P1_WORLD"}\n[/YS_DIAGNOSIS]';

  DiagnosisCommitter buildCommitter() => DiagnosisCommitter(
    sessionRepo: sessionRepo,
    stateRepo: stateRepo,
    diagnosisRepo: diagnosisRepo,
    studentModelRepo: studentModelRepo,
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
  );

  DiagnosisFlowHandler buildHandler(_RecordingLlmClient llm) =>
      DiagnosisFlowHandler(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagnosisRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        teacherSuggestionRepo: teacherSuggestionRepo,
        llmClient: llm,
        messageInjector: MessageInjector(
          sessionRepo: sessionRepo,
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
          manuscriptRepo: ManuscriptRepository(db),
          diagnosisCommitter: buildCommitter(),
          material: const MaterialCapabilityImpl(),
        ),
        diagnosisCommitter: buildCommitter(),
        diagnosis: const DiagnosisCapabilityImpl(),
        genUi: const GenUiParser(),
      );

  Future<String> seedSession() async {
    final sid = await sessionRepo.createBlankSession();
    await stateRepo.updatePhase(sid, TeachingPhase.p0Engage.value);
    await stateRepo.updateBeginnerLevel(sid, BeginnerLevel.n3Diagnose.value);
    return sid;
  }

  test('C103-1：长文链路插入 GenUI 卡片（含 [YS_GENUI] 块时）', () async {
    final sid = await seedSession();
    const contentWithGenui =
        '这是反馈\n[YS_GENUI]{"type":"quiz","title":"t",'
        '"items":[{"q":"q1","options":["a","b"],"answer":0}]}[/YS_GENUI]'
        '\n[YS_DIAGNOSIS]\n{"syndromes":['
        '{"syndrome_id":"s1","name":"叙事含糊","severity":"L2",'
        '"evidence":[],"explanation":"测试"}],"suggested_actions":[],'
        '"confidence":0.8,"suggested_phase":"P1_WORLD"}\n[/YS_DIAGNOSIS]';
    await buildHandler(
      _RecordingLlmClient(''),
    ).commitDiagnosisFromContent(sessionId: sid, fullContent: contentWithGenui);
    final msgs = await sessionRepo.listMessages(sid);
    final genuiCards = msgs.where((m) => m.messageType == 'genui').toList();
    expect(genuiCards, hasLength(1), reason: '长文链路须补齐 GenUI 卡片（旧实现完全缺失）');
  });

  test('C103-2：chapterContent 非空时触发教师 LLM', () async {
    final sid = await seedSession();
    final llm = _RecordingLlmClient('');
    await buildHandler(llm).commitDiagnosisFromContent(
      sessionId: sid,
      fullContent: diagnosisResp(),
      chapterContent: '某章节全文',
    );
    expect(
      llm.streamChatCalls,
      greaterThan(0),
      reason: 'chapterContent 非空须触发教师建议 LLM',
    );
  });

  test('C103-3：chapterContent 为 null 时不触发教师 LLM（保持旧默认）', () async {
    final sid = await seedSession();
    final llm = _RecordingLlmClient('');
    await buildHandler(
      llm,
    ).commitDiagnosisFromContent(sessionId: sid, fullContent: diagnosisResp());
    expect(llm.streamChatCalls, 0, reason: 'chapterContent 缺省须跳过教师（无回归）');
  });
}
