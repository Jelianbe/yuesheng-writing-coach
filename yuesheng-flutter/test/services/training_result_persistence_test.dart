// ─────────────────────────────────────────────────────────────
// ADR-C105 A10 — `training_results` 落库端到端
//
// 立项依据（实测）：本批之前 `git grep -c "trainingResultRepo" -- test` = **0**
// ⇒ 测试态 `_trainingResultRepo` **恒为 null** ⇒ `_persistTrainingResult`
// **永不执行**。生产/测试行为分叉：接线若断，生产静默跳过落库，
// 而**没有任何测试会变红**。
//
// 本文件补四件（正 + 反 + 反 + 回退）：
//   1. 正向：装配仓储 ⇒ feedback 子阶段落库 1 行，`result` 与**协议判定**一致
//   2. 反证：**不**装配仓储 ⇒ 不落库（锁定 X-041c「可选依赖」语义）
//   3. 反证：非 feedback 子阶段 ⇒ 早退，不落库
//   4. 回退：`trainingResult == null` ⇒ 走 displayContent 关键词表（Tier 2）
//      + 无关键词 ⇒ 不落库（null 语义 = 不计通过）
//
// 说明：判定值刻意用 `parseTrainingProtocol(...)!.result` 取——
// 与生产 `_parseAndValidate:730` 同一取值方式，锁定「协议判定 → 落库」整条链。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals, unnecessary_underscores

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
import 'package:writingcoach/data/repositories/training_result_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks;
import 'package:writingcoach/services/chat_training_parser.dart'
    show parseTrainingProtocol;
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 训练反馈路径不应触达 LLM；一旦触达即 fail（而非静默发真实请求）。
class _UnusedLlmClient extends LlmClient {
  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    fail('handleTrainingResult 不应发起 LLM 调用');
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late TrainingResultRepository trainingRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    trainingRepo = TrainingResultRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  /// 手工组装 DiagnosisFlowHandler（仅训练反馈路径所需依赖）。
  DiagnosisFlowHandler buildHandler({required bool withTrainingResultRepo}) {
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

    return DiagnosisFlowHandler(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      llmClient: _UnusedLlmClient(),
      diagnosisCommitter: committer(),
      messageInjector: injector(),
      diagnosis: const DiagnosisCapabilityImpl(),
      genUi: const GenUiParser(),
      // A10 的被测开关：装配与否决定落库分支是否可达
      trainingResultRepo: withTrainingResultRepo ? trainingRepo : null,
    );
  }

  /// 模型原始回复：正文 + `[YS_TRAINING]` 协议块（prompt 要求的输出形态）
  const rawWithProtocol =
      '这次改得还是太急。\n[YS_TRAINING]\n'
      '{"result":"partial","reason":"方向对了，细节还要打磨"}\n'
      '[/YS_TRAINING]';

  SendMessageCallbacks cb({void Function(TrainingResult)? onResult}) =>
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
        onTrainingResult: onResult,
      );

  test(
    '★#1 装配仓储 + feedback ⇒ training_results 落库 1 行，result 与协议判定一致',
    () async {
      final handler = buildHandler(withTrainingResultRepo: true);
      TrainingResult? callbackResult;

      // 与生产 _parseAndValidate:730 同一取值方式（协议优先）
      final resolved = parseTrainingProtocol(rawWithProtocol)!.result;
      expect(resolved, TrainingResult.partial, reason: '前置：协议块能被解析出来');

      await handler.handleTrainingResult(
        sessionId: sessionId,
        currentSubphase: TeachingSubphase.feedback,
        displayContent: '这次改得还是太急。',
        userContent: '他攥紧拳头，指节发白。',
        trainingSyndromeId: 'P001',
        activeProblems: const [],
        callbacks: cb(onResult: (r) => callbackResult = r),
        trainingResult: resolved,
      );

      final rows = await trainingRepo.queryBySession(sessionId);
      expect(rows.length, 1, reason: '装配了仓储就必须落库——这正是此前无守护的接缝');
      expect(rows.single.result, 'partial');
      expect(rows.single.syndromeId, 'P001');
      expect(rows.single.userContent, '他攥紧拳头，指节发白。');
      expect(rows.single.taskType, 'rewrite', reason: '无建议追溯时回落默认任务类型');
      expect(callbackResult, TrainingResult.partial);
    },
  );

  test('反证 #2 未装配仓储 ⇒ 不落库且不抛错（X-041c 可选依赖语义）', () async {
    final handler = buildHandler(withTrainingResultRepo: false);

    await handler.handleTrainingResult(
      sessionId: sessionId,
      currentSubphase: TeachingSubphase.feedback,
      displayContent: '这次改得还是太急。',
      userContent: '他攥紧拳头，指节发白。',
      trainingSyndromeId: 'P001',
      activeProblems: const [],
      callbacks: cb(),
      trainingResult: TrainingResult.partial,
    );

    expect(
      await trainingRepo.queryBySession(sessionId),
      isEmpty,
      reason: '可选依赖未装配 ⇒ 跳过落库（而非报错）',
    );
  });

  test('反证 #3 非 feedback 子阶段 ⇒ 早退，不落库', () async {
    final handler = buildHandler(withTrainingResultRepo: true);

    await handler.handleTrainingResult(
      sessionId: sessionId,
      currentSubphase: null,
      displayContent: '这次改得还是太急。',
      userContent: '他攥紧拳头，指节发白。',
      trainingSyndromeId: 'P001',
      activeProblems: const [],
      callbacks: cb(),
      trainingResult: TrainingResult.partial,
    );

    expect(await trainingRepo.queryBySession(sessionId), isEmpty);
  });

  test('#4 trainingResult 为 null ⇒ 回退 displayContent 关键词表（Tier 2）', () async {
    final handler = buildHandler(withTrainingResultRepo: true);

    await handler.handleTrainingResult(
      sessionId: sessionId,
      currentSubphase: TeachingSubphase.feedback,
      displayContent: '本次练习未达标，请重写第二段。',
      userContent: '他很生气。',
      trainingSyndromeId: 'P001',
      activeProblems: const [],
      callbacks: cb(),
      trainingResult: null,
    );

    final rows = await trainingRepo.queryBySession(sessionId);
    expect(rows.length, 1);
    expect(rows.single.result, 'failed', reason: '协议缺失时回退关键词表，行为不变');
  });

  test('#5 trainingResult 为 null 且正文无关键词 ⇒ 不落库（null = 不计通过）', () async {
    final handler = buildHandler(withTrainingResultRepo: true);

    await handler.handleTrainingResult(
      sessionId: sessionId,
      currentSubphase: TeachingSubphase.feedback,
      displayContent: '我们接着聊聊下一段怎么改。',
      userContent: '他很生气。',
      trainingSyndromeId: 'P001',
      activeProblems: const [],
      callbacks: cb(),
      trainingResult: null,
    );

    expect(
      await trainingRepo.queryBySession(sessionId),
      isEmpty,
      reason: '无命中 ⇒ null ⇒ 不写 history、不落 training_results（ADR-C100 既有语义）',
    );
  });
}
