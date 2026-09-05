// ─────────────────────────────────────────────────────────────
// chat_service_conflict_injection_test — 批次66 B62i 时序矛盾注入测试
//
// 覆盖：
//   1. 有冲突人物数据 + 诊断请求 → 注入「时序矛盾观察」system 消息
//   2. 无人物数据 → 不注入（零 token 成本）
//   3. 非诊断消息 → 即使有冲突数据也不注入（触发时机门控）
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
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
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/types/teaching_types.dart';

import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart'
    show GenUiParser;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
/// 章节正文
const String _chapterContent =
    '第3章里他是独生子。\n'
    '第15章却冒出了一个妹妹。\n'
    '她站在窗前，没有说话。\n'
    '风从窗外吹进来。\n'
    '他低头看着手中的信。\n'
    '这一夜没有人睡好。';

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
    callback(const LlmStreamResponse(content: '收到，开始诊断。', isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late String sessionId;
  late String chapterId;
  late String manuscriptId;
  late CharacterFactRepository factRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();
    factRepo = CharacterFactRepository(db);

    // 建稿 + 章节 + 会话主引用（章节）
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final refRepo = ReferenceRepository(db);
    manuscriptId = await msRepo.createManuscript(title: '测试稿');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: _chapterContent,
    );
    await refRepo.addReference(
      sessionId,
      'chapter',
      chapterId,
      isPrimary: true,
    );
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

        characterFactRepo: factRepo,

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

            stateRepo: TeachingStateRepository(db),

            diagnosisRepo: DiagnosisRepository(db),

            studentModelRepo: StudentModelRepository(db),

            referenceRepo: ReferenceRepository(db),

            chapterRepo: ChapterRepository(db),
          ),

          characterFactRepo: factRepo,

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
      characterFactRepo: factRepo,
    );
  }

  SendMessageCallbacks callbacks() => SendMessageCallbacks(
    onStream: (_) {},
    onComplete: (_, _) {},
    onError: (_) {},
  );

  SendMessageOptions options() => const SendMessageOptions(
    phase: TeachingPhase.p1World,
    attitude: AttitudeLevel.doubao,
  );

  /// 诊断请求消息（含诊断标记）
  String diagPrompt() => '请对以下章节内容进行写作诊断分析：\n\n【第一章】\n$_chapterContent';

  /// 预置冲突人物数据：阿禾「独生子」(第3章) vs「妹妹」(第15章)
  Future<void> seedConflictFacts() async {
    await factRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      firstSeenChapter: 3,
      assertions: [
        CharacterAssertion(
          attribute: '独生子女状态',
          value: '独生子',
          chapter: 3,
          timestamp: 300,
        ),
        CharacterAssertion(
          attribute: '独生子女状态',
          value: '妹妹',
          chapter: 15,
          timestamp: 1500,
        ),
      ],
    );
  }

  test('#1 有冲突人物数据 + 诊断请求 → 注入「时序矛盾观察」', () async {
    await seedConflictFacts();

    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined, contains('时序矛盾观察'));
    expect(joined, contains('阿禾「独生子女状态」'));
    expect(joined, contains('第3章「独生子」→ 第15章「妹妹」'));
    expect(joined, contains('P018'));
  });

  test('#2 无人物数据 → 不注入（零 token 成本）', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined.contains('时序矛盾观察'), false);
  });

  test('#3 非诊断消息 → 即使有冲突数据也不注入（触发时机门控）', () async {
    await seedConflictFacts();

    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    // 普通聊天消息（无诊断标记）
    await service.sendMessage(sessionId, '今天写得有点卡', callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined.contains('时序矛盾观察'), false);
  });
}
