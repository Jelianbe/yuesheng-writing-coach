// ─────────────────────────────────────────────────────────────
// 教学闭环数据流验证（批次 96-15）
//
// 目标：用「真实组件」驱动 问→写→诊→教→练→评 全链路，断言每个 handoff
// 的数据对象正确流转、正确落库：
//   - 真实 drift 内存库（AppDatabase.forTesting + NativeDatabase.memory）
//   - 真实 ChatService + 真实 parsers/validators（复刻 app 真实代码路径）
//   - FakeLlmClient 喂「子代理模拟 LLM」产出的语料 fixture（含 [YS_DIAGNOSIS]
//     + [YS_TEACHER] 协议块）——fixture 的 natural_language 仅为样本输入，
//       话术由 AI 现场生成，本测试绝不将其作为期望文案断言
//
// 关键设计：app 主链路在解析出诊断后会**再次调用 LLM** 取教学决策
// （callTeacherStream，chat_service.dart:1374），故用 SequenceFakeLlmClient
// 第 1 次返回「诊断响应」（正文+[YS_DIAGNOSIS]），第 2 次返回「教学响应」
// （[YS_TEACHER] 块），真实复刻双轮调用而不泄漏协议标记到展示内容。
//
// 验证点：
//   诊：diagnosis 落库 → listActiveProblems 命中期望症候、主症排第一、无凭空症候
//   教：teacher_suggestion 落库 → decision=train、training_task 锁定主症、
//       natural_language 仅经一致性校验（无判决词/无 P0xx 泄漏，非文案期望）
//   评：subphase=feedback + 达标回复 → onTrainingResult(passed) 触发、
//       训练历史落库（关联活跃症候）、子阶段重置为 null（防 feedback 残留）
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals, avoid_print, unnecessary_underscores

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
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart'
    show GenUiParser;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
/// 顺序 Fake LLM：每次 streamChat 返回 responses 中下一条，真实复刻
/// 诊断→教学 的双轮 LLM 调用。所有响应发完后循环复用最后一条。
class SequenceFakeLlmClient extends LlmClient {
  final List<String> _responses;
  int _callIndex = 0;

  SequenceFakeLlmClient(this._responses);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    final r = _responses[_callIndex % _responses.length];
    _callIndex++;
    for (int i = 0; i < r.length; i += 12) {
      final end = i + 12 < r.length ? i + 12 : r.length;
      callback(LlmStreamResponse(content: r.substring(i, end), isDone: false));
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// 单响应 Fake LLM（用于 feedback 轮：无诊断块、仅达标/未达标判定）
class SingleFakeLlmClient extends LlmClient {
  final String _fullResponse;
  SingleFakeLlmClient(this._fullResponse);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    for (int i = 0; i < _fullResponse.length; i += 12) {
      final end = i + 12 < _fullResponse.length ? i + 12 : _fullResponse.length;
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

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late DiagnosisRepository diagRepo;
  late TeacherSuggestionRepository teacherSuggestionRepo;
  late StudentModelRepository studentModelRepo;
  late TeachingStateRepository stateRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    diagRepo = DiagnosisRepository(db);
    teacherSuggestionRepo = TeacherSuggestionRepository(db);
    studentModelRepo = StudentModelRepository(db);
    stateRepo = TeachingStateRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() => db.close());

  ChatService build(LlmClient llmClient) => ChatService(
    sessionRepo: sessionRepo,
    stateRepo: stateRepo,
    diagnosisRepo: diagRepo,
    studentModelRepo: studentModelRepo,
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
    manuscriptRepo: ManuscriptRepository(db),
    llmClient: llmClient,
    teacherSuggestionRepo: teacherSuggestionRepo,
    editorObservationRepo: EditorObservationRepository(db),
    // ADR-C74 K-5：诊断提交编排器收紧为 required
    diagnosisCommitter: DiagnosisCommitter(
      sessionRepo: sessionRepo,
      stateRepo: stateRepo,
      diagnosisRepo: diagRepo,
      studentModelRepo: studentModelRepo,
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

        stateRepo: stateRepo,

        diagnosisRepo: diagRepo,

        studentModelRepo: studentModelRepo,

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
      llmClient: llmClient,

      messageInjector: MessageInjector(
        sessionRepo: sessionRepo,

        diagnosisRepo: DiagnosisRepository(db),

        studentModelRepo: StudentModelRepository(db),

        referenceRepo: ReferenceRepository(db),

        chapterRepo: ChapterRepository(db),

        manuscriptRepo: ManuscriptRepository(db),

        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,

          stateRepo: stateRepo,

          diagnosisRepo: diagRepo,

          studentModelRepo: studentModelRepo,

          referenceRepo: ReferenceRepository(db),

          chapterRepo: ChapterRepository(db),
        ),

        material: const MaterialCapabilityImpl(),
      ),
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
      ),
      diagnosis: const DiagnosisCapabilityImpl(),
      genUi: const GenUiParser(),
    ),
  );

  /// 将 corpus fixture 按 [YS_TEACHER] 切分为「诊断响应」+「教学响应」两段，
  /// 分别喂给真实链路的第 1 / 第 2 次 LLM 调用。
  (String, String) splitFixture(String fileName) {
    final raw = File('test/fixtures/$fileName').readAsStringSync();
    final idx = raw.indexOf('[YS_TEACHER]');
    assert(idx != -1, '$fileName 缺少 [YS_TEACHER] 块');
    return (raw.substring(0, idx), raw.substring(idx));
  }

  const defaultOptions = SendMessageOptions(
    phase: TeachingPhase.p0Engage,
    attitude: AttitudeLevel.doubao,
  );

  group('教学闭环·数据流（真实 ChatService + 内存库 + 模拟 LLM 语料）', () {
    test('主路径（P041/P012 冲突）：问→写→诊→教→练→评 全链路数据正确流转', () async {
      // ── 第 1 轮：问 + 写 + 诊 + 教 ──
      final (diagResp, teacherResp) = splitFixture('corpus_B6_p041_p012.txt');
      final service = build(SequenceFakeLlmClient([diagResp, teacherResp]));

      String? assistantContent;
      await service.sendMessage(
        sessionId,
        '决战那一刻，反派放下能一剑杀主角的机会，开始长篇独白讲述身世。',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (content, _) => assistantContent = content,
          onError: (e) => fail('诊断轮 onError: $e'),
        ),
        defaultOptions,
      );

      // ── 诊：诊断落库，主症 P041 排第一，无凭空症候 ──
      final active = await diagRepo.listActiveProblems(sessionId);
      final hitIds = active.map((p) => p.syndromeId).toList();
      print('[诊] 活跃症候: ${hitIds.join(", ")}');
      expect(hitIds, contains('P041'), reason: '应命中主症 P041');
      expect(hitIds, contains('P012'), reason: '应命中次症 P012');
      expect(
        hitIds.first,
        equals('P041'),
        reason: 'P041 应排 syndromes[0]（冲突优先级裁决）',
      );
      expect(hitIds.length, 2, reason: '不应凭空造症候（误诊/误报）');

      // 用户可见内容不得泄漏协议标记与症候编号
      expect(assistantContent, isNotNull);
      expect(
        assistantContent!,
        isNot(contains('[YS_DIAGNOSIS]')),
        reason: '诊断块标记泄漏到用户可见内容',
      );
      expect(
        assistantContent!,
        isNot(contains('[YS_TEACHER]')),
        reason: '教学块标记泄漏到用户可见内容',
      );
      expect(
        RegExp(r'P0\d{2}').hasMatch(assistantContent!),
        isFalse,
        reason: '自然语言泄漏症候编号',
      );

      // ── 教：教学建议落库，decision=train 且 training_task 锁定主症 ──
      final suggestions = await teacherSuggestionRepo.getActiveSuggestions(
        sessionId,
      );
      expect(suggestions, hasLength(1), reason: '应落库 1 条教学建议');
      final sug = suggestions.first;
      print(
        '[教] decision=${sug.teachingDecision} '
        'target=${sug.targetSyndromeId} taskType=${sug.taskType}',
      );
      expect(sug.teachingDecision, equals('train'), reason: 'L2 症候应决策为 train');
      expect(
        sug.targetSyndromeId,
        equals('P041'),
        reason: 'training_task 应锁定主症 P041（非次症 P012）',
      );
      expect(sug.taskType, equals('rewrite'), reason: 'B6 训练任务应为 rewrite');
      expect(sug.difficulty, equals('medium'));

      // 诊断轮应写入 teaching_history（type=diagnosis）
      final diagHistory = (await studentModelRepo.getTeachingHistory(
        sessionId,
      )).where((r) => r['type'] == 'diagnosis').toList();
      expect(diagHistory, isNotEmpty, reason: '诊断应写入教学历史');

      // ── 第 2 轮：练 + 评（subphase=feedback，学员提交改写 + 达标）──
      final feedbackService = build(SingleFakeLlmClient('很好，本次练习达标了！'));
      TrainingResult? trainingResult;
      await feedbackService.sendMessage(
        sessionId,
        '他攥紧拳头，指节发白，牙关绷紧——这是他三年来第一次离仇人这么近。',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (e) => fail('反馈轮 onError: $e'),
          onTrainingResult: (r) => trainingResult = r,
        ),
        defaultOptions,
        subphase: TeachingSubphase.feedback,
      );

      // ── 评：onTrainingResult 触发且为 passed ──
      expect(
        trainingResult,
        equals(TrainingResult.passed),
        reason: '达标回复应触发 onTrainingResult(passed)',
      );

      // 训练历史落库，关联活跃症候，结果=passed
      final trainingHistory = (await studentModelRepo.getTeachingHistory(
        sessionId,
      )).where((r) => r['type'] == 'training').toList();
      expect(trainingHistory, isNotEmpty, reason: '训练结果应写入教学历史');
      final trainEntry = trainingHistory.last;
      print(
        '[评] 训练历史: syndromeId=${trainEntry['syndromeId']} '
        'result=${trainEntry['result']}',
      );
      expect(trainEntry['result'], equals('passed'));
      expect(
        ['P041', 'P012'].contains(trainEntry['syndromeId']),
        isTrue,
        reason: '训练应关联本会话活跃症候之一',
      );

      // 训练轮终结 → 子阶段重置为 null（防 feedback 残留）
      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts?.currentSubphase, isNull, reason: '训练轮终结后子阶段应重置，防 feedback 残留');
    });

    test(
      '未达标分支（P003 单症候）：反馈轮未达标 → onTrainingResult(failed) 且历史 result=failed',
      () async {
        final (diagResp, teacherResp) = splitFixture('corpus_A1_p003.txt');
        final service = build(SequenceFakeLlmClient([diagResp, teacherResp]));

        await service.sendMessage(
          sessionId,
          '小明早上起床，刷牙洗脸，吃了早饭，然后出门去上班。他很累。他很无聊。',
          SendMessageCallbacks(
            onStream: (_) {},
            onComplete: (_, __) {},
            onError: (e) => fail('诊断轮 onError: $e'),
          ),
          defaultOptions,
        );

        // 诊：P003 命中
        final active = await diagRepo.listActiveProblems(sessionId);
        expect(active.map((p) => p.syndromeId).toList(), contains('P003'));
        // 教：train 锁定 P003
        final sug = (await teacherSuggestionRepo.getActiveSuggestions(
          sessionId,
        )).first;
        expect(sug.targetSyndromeId, equals('P003'));

        // 反馈轮：未达标
        final feedbackService = build(
          SingleFakeLlmClient('本次练习未达标，建议重新理解「行为化呈现情绪」的要求。'),
        );
        TrainingResult? trainingResult;
        await feedbackService.sendMessage(
          sessionId,
          '他觉得很累，很无聊，很没意思。',
          SendMessageCallbacks(
            onStream: (_) {},
            onComplete: (_, __) {},
            onError: (e) => fail('反馈轮 onError: $e'),
            onTrainingResult: (r) => trainingResult = r,
          ),
          defaultOptions,
          subphase: TeachingSubphase.feedback,
        );

        expect(
          trainingResult,
          equals(TrainingResult.failed),
          reason: '未达标回复应触发 onTrainingResult(failed)',
        );
        final trainingHistory = (await studentModelRepo.getTeachingHistory(
          sessionId,
        )).where((r) => r['type'] == 'training').toList();
        expect(trainingHistory, isNotEmpty);
        expect(trainingHistory.last['result'], equals('failed'));

        final ts = await stateRepo.getTeachingState(sessionId);
        expect(ts?.currentSubphase, isNull, reason: '训练轮终结后子阶段应重置');
      },
    );
  });
}
