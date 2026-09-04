// ─────────────────────────────────────────────────────────────
// chat_service_plot_injection_test — 批次67 B62j 因果链/情节闭环注入测试
//
// 覆盖：
//   1. F07 有事件数据（决定类缺前因）+ 诊断请求 → 注入「因果链断裂观察」
//   2. F11 有支线数据（引入多章未回收）+ 诊断请求 → 注入「情节闭环观察」
//   3. 无事件/支线数据 → 不注入（零 token 成本）
//   4. 非诊断消息 → 即使有数据也不注入（触发时机门控）
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/subplot_fact_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 章节正文（含「决定去金陵」类转折事件，供 F07/F11 检测数据关联）
/// 注：事件名/支线名须与正文关键词精确匹配，供 6.5 原文摘录反查命中
const String _chapterContent =
    '第5章，阿禾决定去金陵。\n'
    '第3章，他在城门口捡到一把钥匙。\n'
    '如今已到第12章，钥匙的秘密仍没有下文。\n'
    '她站在窗前，没有说话。\n'
    '风从窗外吹进来。\n'
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
  late EventFactRepository eventRepo;
  late SubplotFactRepository subplotRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();
    eventRepo = EventFactRepository(db);
    subplotRepo = SubplotFactRepository(db);

    // 建稿 + 章节（sortOrder=12，当前推进到第12章）+ 会话主引用（章节）
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final refRepo = ReferenceRepository(db);
    manuscriptId = await msRepo.createManuscript(title: '测试稿');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第十二章',
      content: _chapterContent,
    );
    // 将章节 sortOrder 调整为 12（F11 当前章节判定用）
    await (db.update(db.chapters)..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(sortOrder: const Value(12)),
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
      eventFactRepo: eventRepo,
      subplotFactRepo: subplotRepo,
      // ADR-C74 K-5：诊断提交编排器收紧为 required
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        eventFactRepo: eventRepo,
        subplotFactRepo: subplotRepo,
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

  /// 诊断请求消息（含诊断标记）
  String diagPrompt() => '请对以下章节内容进行写作诊断分析：\n\n【第十二章】\n$_chapterContent';

  /// 预置 F07 数据：决定类事件缺前因
  Future<void> seedCausalityBreaks() async {
    await eventRepo.upsertEvent(
      manuscriptId: manuscriptId,
      name: '阿禾决定去金陵',
      eventType: '决定',
      chapter: 5,
    );
  }

  /// 预置 F11 数据：第3章引入的支线未回收（当前12章，已超阈值）
  Future<void> seedUnclosedSubplot() async {
    await subplotRepo.upsertSubplot(
      manuscriptId: manuscriptId,
      name: '钥匙的秘密',
      introducedChapter: 3,
    );
  }

  test('#1 F07 有事件数据 + 诊断请求 → 注入「因果链断裂观察」', () async {
    await seedCausalityBreaks();

    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined, contains('因果链断裂观察'));
    expect(joined, contains('第5章「阿禾决定去金陵」（决定类）缺触发事件'));
    expect(joined, contains('P021'));
    // 6.5 O11：正文反查事件名首现片段作触发原文摘录
    expect(joined, contains('（原文：「第5章，阿禾决定去金陵」）'));
  });

  test('#2 F11 有支线数据 + 诊断请求 → 注入「情节闭环观察」', () async {
    await seedUnclosedSubplot();

    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined, contains('情节闭环观察'));
    expect(joined, contains('第3章引入的支线「钥匙的秘密」至今（第12章）未回收'));
    expect(joined, contains('P014'));
    // 6.5 O11：正文反查支线名首现片段作触发原文摘录
    //（摘录以关键词为锚截断，可能含前文上下文，断言关键词所在句片段即可）
    expect(joined, contains('原文：「'));
    expect(joined, contains('钥匙的秘密仍没有下文'));
  });

  test('#3 无事件/支线数据 → 不注入（零 token 成本）', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined.contains('因果链断裂观察'), false);
    expect(joined.contains('情节闭环观察'), false);
  });

  test('#4 非诊断消息 → 即使有数据也不注入（触发时机门控）', () async {
    await seedCausalityBreaks();
    await seedUnclosedSubplot();

    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    // 普通聊天消息（无诊断标记）
    await service.sendMessage(sessionId, '今天写得有点卡', callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined.contains('因果链断裂观察'), false);
    expect(joined.contains('情节闭环观察'), false);
  });
}
