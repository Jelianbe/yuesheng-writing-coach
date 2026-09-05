// ─────────────────────────────────────────────────────────────
// 批次60：chat_service 教学决策层注入测试
// 覆盖：学员技能层级软引导 + 训练介入级别（I do/We do/You do）
// 真源链路：步骤 3 读 beginner_level → 步骤 6.1 focus 层级软优先 →
//           步骤 6.3 介入级别注入 → 步骤 6.4 技能层级软引导注入
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
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
/// 捕获注入 messages 的 Fake LLM
class _CaptureLlmClient extends LlmClient {
  List<String> systemContents = [];

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    systemContents = messages
        .where((m) => m.role == 'system')
        .map((m) => m.content)
        .toList();
    callback(const LlmStreamResponse(content: '收到，我们开始。', isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  ChatService buildChatService(LlmClient llmClient) {
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
        sessionRepo: sessionRepo,
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
  }

  /// 种子：active 症候 P003（L1 基础表达）+ 学员水平 N1（→ L1）
  Future<void> seedActiveProblem({int? trainingCount}) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.activeProblems)
        .insert(
          ActiveProblemsCompanion.insert(
            id: generateUuid(),
            sessionId: sessionId,
            syndromeId: 'P003',
            syndromeName: const Value('情绪标签化'),
            severity: const Value('L2'),
            status: const Value('active'),
            confirmationStatus: const Value('confirmed'),
            createdAt: Value(ts),
          ),
        );
    await TeachingStateRepository(
      db,
    ).updateBeginnerLevel(sessionId, BeginnerLevel.n1Elements.value);

    // 可选：写入 training 历史（验证介入级别随次数进阶）
    if (trainingCount != null && trainingCount > 0) {
      final repo = StudentModelRepository(db);
      for (var i = 0; i < trainingCount; i++) {
        await repo.appendTeachingHistory(sessionId, {
          'type': 'training',
          'syndromeId': 'P003',
          'result': 'passed',
          'timestamp': ts + i,
        });
      }
    }
  }

  String joinedSystem(_CaptureLlmClient llm) => llm.systemContents.join('\n');

  test('#J1 技能层级软引导 + 介入级别注入（N1 + 未训练 → L1 / I do）', () async {
    await seedActiveProblem();
    final llm = _CaptureLlmClient();
    final chatService = buildChatService(llm);

    await chatService.sendMessage(
      sessionId,
      '帮我看看这段',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, _) {},
        onError: (_) {},
      ),
      const SendMessageOptions(
        phase: TeachingPhase.p1World,
        attitude: AttitudeLevel.doubao,
      ),
    );

    final joined = joinedSystem(llm);
    expect(joined, contains('学员技能层级'));
    expect(joined, contains('L1 基础表达'));
    expect(joined, contains('训练介入级别'));
    expect(joined, contains('I do'));
  });

  test('#J2 训练 4 次后介入级别进阶为 You do', () async {
    await seedActiveProblem(trainingCount: 4);
    final llm = _CaptureLlmClient();
    final chatService = buildChatService(llm);

    await chatService.sendMessage(
      sessionId,
      '继续练',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, _) {},
        onError: (_) {},
      ),
      const SendMessageOptions(
        phase: TeachingPhase.p1World,
        attitude: AttitudeLevel.doubao,
      ),
    );

    final joined = joinedSystem(llm);
    expect(joined, contains('训练介入级别'));
    expect(joined, contains('You do'));
    expect(joined, contains('已训练 4 次'));
  });

  test('#J3 无学员水平 → 不注入技能层级软引导（仍注入介入级别）', () async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.activeProblems)
        .insert(
          ActiveProblemsCompanion.insert(
            id: generateUuid(),
            sessionId: sessionId,
            syndromeId: 'P003',
            syndromeName: const Value('情绪标签化'),
            severity: const Value('L2'),
            status: const Value('active'),
            confirmationStatus: const Value('confirmed'),
            createdAt: Value(ts),
          ),
        );
    final llm = _CaptureLlmClient();
    final chatService = buildChatService(llm);

    await chatService.sendMessage(
      sessionId,
      '看看',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, _) {},
        onError: (_) {},
      ),
      const SendMessageOptions(
        phase: TeachingPhase.p1World,
        attitude: AttitudeLevel.doubao,
      ),
    );

    final joined = joinedSystem(llm);
    expect(joined, isNot(contains('学员技能层级')));
    expect(joined, contains('训练介入级别'));
  });

  test('#J4 批次16 表现差（4 次全未达标）→ 介入级别回退 I do + 注入回退原因', () async {
    // 种子：P003 活跃 + N1 学员水平
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.activeProblems)
        .insert(
          ActiveProblemsCompanion.insert(
            id: generateUuid(),
            sessionId: sessionId,
            syndromeId: 'P003',
            syndromeName: const Value('情绪标签化'),
            severity: const Value('L2'),
            status: const Value('active'),
            confirmationStatus: const Value('confirmed'),
            createdAt: Value(ts),
          ),
        );
    await TeachingStateRepository(
      db,
    ).updateBeginnerLevel(sessionId, BeginnerLevel.n1Elements.value);

    // 4 次训练全部 failed → performance_gate G1（连续 ≥3 次未达标 → I do）
    final repo = StudentModelRepository(db);
    for (var i = 0; i < 4; i++) {
      await repo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 'P003',
        'result': 'failed',
        'timestamp': ts + i,
      });
    }

    final llm = _CaptureLlmClient();
    final chatService = buildChatService(llm);

    await chatService.sendMessage(
      sessionId,
      '继续练',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, _) {},
        onError: (_) {},
      ),
      const SendMessageOptions(
        phase: TeachingPhase.p1World,
        attitude: AttitudeLevel.doubao,
      ),
    );

    final joined = joinedSystem(llm);
    expect(joined, contains('训练介入级别'));
    // 4 次未达标 → G1 回退 I do（而非按次数分级到 You do）
    expect(joined, contains('I do'));
    expect(joined, isNot(contains('You do（独立练习）')));
    // 修正原因注入
    expect(joined, contains('连续 4 次未达标'));
  });
}
