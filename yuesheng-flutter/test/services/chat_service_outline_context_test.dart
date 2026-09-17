// ─────────────────────────────────────────────────────────────
// P2-8 outline 组激活：会话引用含 outline 附属文件 → isOutlineContext
// 接线进 L2 决议（L2Mode.outline + outline-diagnosis 加载）
//
// 验证点：
//   1. 有 outline 引用 → LLM 输入含「大纲结构诊断」（outline-diagnosis 已加载）
//   2. 无 outline 引用（对照）→ 不含大纲诊断段
//   3. 非 outline 文件引用（general）→ 不触发大纲语境
// ─────────────────────────────────────────────────────────────

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
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;

/// Fake LLM 客户端：记录最近一次请求的完整 messages
class FakeLlmClient extends LlmClient {
  final String _fullResponse;
  List<ChatMessage>? lastMessages;
  int callCount = 0;

  FakeLlmClient(this._fullResponse);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    callCount++;
    lastMessages = messages;
    callback(LlmStreamResponse(content: _fullResponse, isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late ReferenceRepository referenceRepo;
  late ManuscriptRepository manuscriptRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    referenceRepo = ReferenceRepository(db);
    manuscriptRepo = ManuscriptRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  ChatService buildChatService(LlmClient llmClient) {
    return ChatService(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: referenceRepo,
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: manuscriptRepo,
      llmClient: llmClient,
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      editorObservationRepo: EditorObservationRepository(db),
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: referenceRepo,
        chapterRepo: ChapterRepository(db),
      ),
      messageInjector: MessageInjector(
        sessionRepo: sessionRepo,
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: referenceRepo,
        chapterRepo: ChapterRepository(db),
        manuscriptRepo: manuscriptRepo,
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: referenceRepo,
          chapterRepo: ChapterRepository(db),
        ),
        material: const MaterialCapabilityImpl(),
      ),
      diagnosisFlowHandler: DiagnosisFlowHandler(
        sessionRepo: SessionRepository(db),
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: referenceRepo,
        chapterRepo: ChapterRepository(db),
        teacherSuggestionRepo: TeacherSuggestionRepository(db),
        llmClient: llmClient,
        messageInjector: MessageInjector(
          sessionRepo: sessionRepo,
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: referenceRepo,
          chapterRepo: ChapterRepository(db),
          manuscriptRepo: manuscriptRepo,
          diagnosisCommitter: DiagnosisCommitter(
            sessionRepo: sessionRepo,
            stateRepo: TeachingStateRepository(db),
            diagnosisRepo: DiagnosisRepository(db),
            studentModelRepo: StudentModelRepository(db),
            referenceRepo: referenceRepo,
            chapterRepo: ChapterRepository(db),
          ),
          material: const MaterialCapabilityImpl(),
        ),
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: referenceRepo,
          chapterRepo: ChapterRepository(db),
        ),
        diagnosis: const DiagnosisCapabilityImpl(),
        genUi: const GenUiParser(),
      ),
    );
  }

  const defaultOptions = SendMessageOptions(
    phase: TeachingPhase.p0Engage,
    attitude: AttitudeLevel.doubao,
  );

  /// 取最近一次请求里所有 system 消息拼接文本
  String systemPromptOf(FakeLlmClient llm) {
    final systems = llm.lastMessages!
        .where((m) => m.role == 'system')
        .map((m) => m.content)
        .join('\n');
    return systems;
  }

  /// 建一本书（attachedFiles.bookId 外键指向 Manuscripts）
  Future<String> createBook() async {
    return manuscriptRepo.createManuscript(title: '测试书');
  }

  test('#P2-8-1 outline 引用存在 → 大纲语境激活（L2Mode.outline 加载大纲诊断）', () async {
    final bookId = await createBook();
    final file = await referenceRepo.createAttachedFile(
      bookId: bookId,
      fileName: '大纲.md',
      fileRole: 'outline',
      content: '第一卷：…',
    );
    await referenceRepo.addReference(sessionId, 'file', file.id);

    final llm = FakeLlmClient('好的，我们来看大纲。');
    final chatService = buildChatService(llm);
    await chatService.sendMessage(
      sessionId,
      '帮我看一下这个大纲的结构',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      defaultOptions,
    );

    expect(llm.lastMessages, isNotNull);
    expect(systemPromptOf(llm), contains('大纲结构诊断'));
    expect(systemPromptOf(llm), contains('大纲'));
  });

  test('#P2-8-2 无引用（对照）→ 不加载大纲诊断', () async {
    final llm = FakeLlmClient('你好。');
    final chatService = buildChatService(llm);
    await chatService.sendMessage(
      sessionId,
      '你好',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      defaultOptions,
    );

    expect(llm.lastMessages, isNotNull);
    expect(systemPromptOf(llm), isNot(contains('大纲结构诊断')));
  });

  test('#P2-8-3 general 文件引用 → 不触发大纲语境', () async {
    final bookId = await createBook();
    final file = await referenceRepo.createAttachedFile(
      bookId: bookId,
      fileName: '素材.md',
      fileRole: 'general',
      content: '设定资料…',
    );
    await referenceRepo.addReference(sessionId, 'file', file.id);

    final llm = FakeLlmClient('收到。');
    final chatService = buildChatService(llm);
    await chatService.sendMessage(
      sessionId,
      '参考一下素材',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      defaultOptions,
    );

    expect(llm.lastMessages, isNotNull);
    expect(systemPromptOf(llm), isNot(contains('大纲结构诊断')));
  });
}
