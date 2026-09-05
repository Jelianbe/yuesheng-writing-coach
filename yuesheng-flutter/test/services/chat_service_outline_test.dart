// ─────────────────────────────────────────────────────────────
// chat_service_outline_test — 批次72 大纲层端到端注入/落库测试
//
// 覆盖：
//   1. 诊断 + 章节 + 装配 outlineRepo → AI 返回 OUTLINE 块 → 落库（pending）
//   2. 已有实体时诊断 → 注入「大纲实体索引」上下文
//   3. 未装配 outlineRepo → 不注入索引、OUTLINE 块不落库
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
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
const String _chapterContent = '王建国站在巷口，夜色沉沉。他想起母亲说过的话，攥紧了拳头。';

/// 捕获注入 messages + 固定回 OUTLINE 块的 Fake LLM
class _OutlineLlmClient extends LlmClient {
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
    var content = '王建国这个人物塑造得很扎实。';
    content +=
        '\n[YS_ENTITY]{"entities":[{"type":"character","key":"王建国",'
        '"aliases":["建国"],"impressions":[{"text":"巷口沉默，攥拳"},'
        '{"text":"记得母亲的话"}]}]}[/YS_ENTITY]';
    callback(LlmStreamResponse(content: content, isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late OutlineRepository outlineRepo;
  late String sessionId;
  late String chapterId;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    outlineRepo = OutlineRepository(db);
    sessionId = await sessionRepo.createBlankSession();

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

  ChatService buildChatService(LlmClient llm, {bool withOutline = true}) {
    return ChatService(
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
      outlineRepo: withOutline ? outlineRepo : null,
      // ADR-C74 K-4：实体/事实落库辅助需要 DiagnosisCommitter
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        outlineRepo: withOutline ? outlineRepo : null,
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

          outlineRepo: withOutline ? outlineRepo : null,
        ),

        characterFactRepo: null,
        eventFactRepo: null,
        subplotFactRepo: null,
        outlineRepo: withOutline ? outlineRepo : null,
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

            outlineRepo: withOutline ? outlineRepo : null,
          ),

          characterFactRepo: null,
          eventFactRepo: null,
          subplotFactRepo: null,
          outlineRepo: withOutline ? outlineRepo : null,
          material: const MaterialCapabilityImpl(),
        ),
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
          outlineRepo: withOutline ? outlineRepo : null,
        ),
        diagnosis: const DiagnosisCapabilityImpl(),
        genUi: const GenUiParser(),
      ),
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

  String diagPrompt() => '请对以下章节内容进行写作诊断分析：\n\n【第一章】\n$_chapterContent';

  test('#1 诊断 + 章节 + 装配 outlineRepo → OUTLINE 块落库（pending）', () async {
    final llm = _OutlineLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final entities = await outlineRepo.listEntities(manuscriptId);
    expect(entities.length, 1);
    expect(entities.single.entityKey, '王建国');
    expect(entities.single.status, 'pending');
    expect(OutlineRepository.parseAliases(entities.single.aliases), ['建国']);

    final impressions = await outlineRepo.listImpressions(entities.single.id);
    expect(impressions.length, 2);
    expect(impressions.every((i) => i.status == 'pending'), true);
    expect(impressions.every((i) => i.sourceChapterId == chapterId), true);

    // 批次73：确认卡片消息已写入
    final messages = await sessionRepo.listMessages(sessionId);
    final cards = messages
        .where((m) => m.messageType == 'outline_confirmation')
        .toList();
    expect(cards.length, 1, reason: '应为该实体写 1 张确认卡');
    expect(cards.single.content, contains('王建国'));
    expect(cards.single.content, contains('巷口沉默，攥拳'));

    // 批次74：落库的 assistant 消息不含原始协议 JSON（剥离展示）
    final assistant = messages.singleWhere((m) => m.role == 'assistant');
    expect(assistant.content, contains('王建国这个人物塑造得很扎实。'));
    expect(assistant.content.contains('YS_ENTITY'), false);
    expect(assistant.content.contains('巷口沉默，攥拳'), false);
  });

  test('#2 已有实体时诊断 → 注入「大纲实体索引」+ 协议说明', () async {
    // 预置实体
    await outlineRepo.insertEntity(
      manuscriptId: manuscriptId,
      entityType: 'character',
      entityKey: '王建国',
      aliases: const ['建国'],
    );

    final llm = _OutlineLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined, contains('大纲实体索引'));
    expect(joined, contains('王建国'));
    // 批次74：协议说明已注入（零实体时也应注入，闭环可启动）
    expect(joined, contains('大纲实体记忆沉淀'));
    expect(joined, contains('[YS_ENTITY]'));
  });

  test('#3 未装配 outlineRepo → 不注入协议/索引、OUTLINE 块不落库', () async {
    final llm = _OutlineLlmClient();
    final service = buildChatService(llm, withOutline: false);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined.contains('大纲实体索引'), false);
    expect(joined.contains('大纲实体记忆沉淀'), false);
    expect(await outlineRepo.listEntities(manuscriptId), isEmpty);
  });

  test('#4 D4-A commitDiagnosisFromContent 也沉淀大纲实体 + 确认卡', () async {
    final llm = _OutlineLlmClient();
    final service = buildChatService(llm);

    // 构造含 [YS_ENTITY] + [YS_DIAGNOSIS] 的 AI 原始输出（模拟渐进诊断分块拼接）
    final aiFullOutput =
        '王建国这个人物塑造得很扎实。\n'
        '[YS_ENTITY]{"entities":[{"type":"character","key":"王叔","aliases":["王师傅"],'
        '"impressions":[{"text":"守在巷口三十年"},{"text":"左眼有一道刀疤"}]}]}[/YS_ENTITY]\n'
        '[YS_DIAGNOSIS]{"syndromes":[{"syndrome_id":"P001","name":"情绪直白","severity":"medium",'
        '"evidence":["心里一紧"],"explanation":"e"}],"suggested_actions":["动作化"],"confidence":0.9}[/YS_DIAGNOSIS]\n'
        '试试把情绪换成动作。';

    await service.commitDiagnosisFromContent(
      sessionId: sessionId,
      fullContent: aiFullOutput,
    );

    // 实体落库（sendMessage 未调用，应仅来自 commitDiagnosisFromContent）
    final entities = await outlineRepo.listEntities(manuscriptId);
    expect(
      entities.length,
      1,
      reason: 'D4-A 也应走 applyOutlineExtraction 落库 1 个实体',
    );
    expect(entities.single.entityKey, '王叔');
    expect(entities.single.status, 'pending');
    expect(OutlineRepository.parseAliases(entities.single.aliases), ['王师傅']);

    final impressions = await outlineRepo.listImpressions(entities.single.id);
    expect(impressions.length, 2);
    expect(impressions.every((i) => i.status == 'pending'), true);
    expect(impressions.every((i) => i.sourceChapterId == chapterId), true);

    // 确认卡
    final messages = await sessionRepo.listMessages(sessionId);
    final cards = messages
        .where((m) => m.messageType == 'outline_confirmation')
        .toList();
    expect(cards.length, 1, reason: 'D4-A 也应写 1 张大纲确认卡');
    expect(cards.single.content, contains('王叔'));
    expect(cards.single.content, contains('守在巷口三十年'));

    // assistant 消息剥离协议
    final assistant = messages.singleWhere((m) => m.role == 'assistant');
    expect(assistant.content, contains('王建国这个人物塑造得很扎实'));
    expect(assistant.content, contains('试试把情绪换成动作。'));
    expect(assistant.content.contains('YS_ENTITY'), false);
    expect(assistant.content.contains('守在巷口三十年'), false);
  });

  test('#5 D4-A commitDiagnosisFromContent 无章节主引用 → 静默跳过大纲落库', () async {
    final llm = _OutlineLlmClient();
    final service = buildChatService(llm);

    // 创建一个新 session，不绑定章节主引用
    final noRefSessionId = await sessionRepo.createBlankSession();
    final aiFullOutput =
        '诊断文本\n[YS_ENTITY]{"entities":[{"type":"character","key":"林小芸",'
        '"impressions":[{"text":"握着手枪"}]}]}[/YS_ENTITY]';

    await service.commitDiagnosisFromContent(
      sessionId: noRefSessionId,
      fullContent: aiFullOutput,
    );

    // 无装配主引用时，应静默跳过（不落库实体）
    expect(await outlineRepo.listEntities(manuscriptId), isEmpty);
  });
}
