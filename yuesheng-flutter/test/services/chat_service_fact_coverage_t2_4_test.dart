// ─────────────────────────────────────────────────────────────
// chat_service 事实提取覆盖率补测（T2-4 续）
//
// 缺口：_applyFactExtractionFromContent（L793-912，约 100 行）当前完全未被
// 任何测试触达——因为默认夹具不装配 Character/Event/Subplot 三个 fact 仓储。
// 本文件装配三表仓储 + 章节主引用，用 commitDiagnosisFromContent 喂 [YS_FACT]
// 块，触发人物/事件/支线三表 upsert 落库路径，补齐这部分覆盖率。
// 零行为变更，沿用 in-memory DB + FakeLlmClient 夹具。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals, unnecessary_underscores

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/subplot_fact_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

class FakeLlmClient extends LlmClient {
  final String _fullResponse;
  FakeLlmClient(this._fullResponse);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    callback(LlmStreamResponse(content: _fullResponse, isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late CharacterFactRepository characterFactRepo;
  late EventFactRepository eventFactRepo;
  late SubplotFactRepository subplotFactRepo;
  late String sessionId;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    characterFactRepo = CharacterFactRepository(db);
    eventFactRepo = EventFactRepository(db);
    subplotFactRepo = SubplotFactRepository(db);
    sessionId = await sessionRepo.createBlankSession();

    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final refRepo = ReferenceRepository(db);
    manuscriptId = await msRepo.createManuscript(title: '测试稿', genre: '小说');
    final ch = await chRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: '王建国站在巷口，夜色沉沉。',
    );
    await refRepo.addReference(sessionId, 'chapter', ch, isPrimary: true);
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
        // ADR-C74 K-4：fact 仓储必须传进 DiagnosisCommitter，否则 applyFactExtraction 静默跳过
        characterFactRepo: characterFactRepo,
        eventFactRepo: eventFactRepo,
        subplotFactRepo: subplotFactRepo,
      ),
      characterFactRepo: characterFactRepo,
      eventFactRepo: eventFactRepo,
      subplotFactRepo: subplotFactRepo,
    );
  }

  const String _factBlock = '''
[YS_FACT]
{
  "characters":[{"name":"王建国","assertions":[{"attribute":"性格","value":"沉默寡言","chapter":1}]}],
  "events":[{"name":"巷口冲突","event_type":"冲突","chapter":1,"participants":["王建国"],"description":"一句概述","cause_event_name":"开篇事件"}],
  "subplots":[{"name":"身世线","introduced_chapter":1,"resolved_chapter":null,"description":"支线梗概"}]
}
[/YS_FACT]
''';

  test('F1 装配 fact 仓储 + [YS_FACT] 块 → 人物/事件/支线三表落库', () async {
    final chatService = buildChatService(FakeLlmClient('占位'));

    await chatService.commitDiagnosisFromContent(
      sessionId: sessionId,
      fullContent: _factBlock,
    );

    final characters = await characterFactRepo.listCharacters(manuscriptId);
    final events = await eventFactRepo.listEvents(manuscriptId);
    final subplots = await subplotFactRepo.listSubplots(manuscriptId);

    expect(characters, isNotEmpty, reason: '人物事实应落库');
    expect(events, isNotEmpty, reason: '事件事实应落库');
    expect(subplots, isNotEmpty, reason: '支线事实应落库');
    expect(characters.first.name, '王建国');
  });

  test('F2 诊断 + 事实混合块 → 诊断落库与事实三表落库并行', () async {
    final chatService = buildChatService(FakeLlmClient('占位'));

    final fullContent =
        '诊断说明。\n'
        '$_factBlock'
        '[YS_DIAGNOSIS]'
        '{"syndromes":[{"syndrome_id":"s1","name":"叙事含糊","severity":"L2","evidence":[],"explanation":"测试"}],"suggested_actions":[],"confidence":0.8}'
        '[/YS_DIAGNOSIS]';

    final messageId = await chatService.commitDiagnosisFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
    );

    expect(messageId, isNotEmpty);
    // 事实三表 + 诊断历史均落库
    expect(await characterFactRepo.listCharacters(manuscriptId), isNotEmpty);
    expect(await eventFactRepo.listEvents(manuscriptId), isNotEmpty);
    expect(await subplotFactRepo.listSubplots(manuscriptId), isNotEmpty);
    final history = await DiagnosisRepository(db).listDiagnosisHistory(sessionId);
    expect(history, isNotEmpty);
  });

  test('F3 仅 [YS_FACT] 无诊断块 → 事实落库且 assistant 消息正常写入不抛错', () async {
    final chatService = buildChatService(FakeLlmClient('占位'));

    await chatService.commitDiagnosisFromContent(
      sessionId: sessionId,
      fullContent: _factBlock,
    );

    final messages = await sessionRepo.listMessages(sessionId);
    expect(
      messages.any((m) => m.role == 'assistant'),
      isTrue,
      reason: '无诊断块时仍应写入 assistant 消息',
    );
    expect(await eventFactRepo.listEvents(manuscriptId), isNotEmpty);
  });
}
