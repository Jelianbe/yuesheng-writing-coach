// ─────────────────────────────────────────────────────────────
// chat_service_dialogue_tag_injection_test — 批次71 F02 对话标签注入测试
//
// 覆盖：
//   1. 章节含重复修饰标签 + 诊断请求 → 注入「对话标签观察」
//   2. 章节内容干净（无对话） → 不注入（零 token 成本）
//   3. 非诊断消息 → 即使有重复标签也不注入（触发时机门控）
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
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
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 含重复修饰标签的章节正文（3 处「低声说」）
const String _flawedContent =
    '「我等你很久了。」她低声说。「我也是。」他低声说。「那就好。」她低声说。'
    '他望着窗外的夜色，迟迟没有回答。';

/// 干净章节正文（无对话标签）
const String _cleanContent =
    '他沉默地站在窗前，看着夜色一点一点漫上来。远处传来更夫的打更声，'
    '提醒着这座城已经入睡。他转过身，把桌上的信小心折好，放进了怀中。';

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

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();

    // 建稿 + 章节（含重复标签）+ 会话主引用（章节）
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final refRepo = ReferenceRepository(db);
    manuscriptId = await msRepo.createManuscript(title: '测试稿');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: _flawedContent,
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
  String diagPrompt() => '请对以下章节内容进行写作诊断分析：\n\n【第一章】\n$_flawedContent';

  test('#1 章节含重复修饰标签 + 诊断请求 → 注入「对话标签观察」', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined, contains('对话标签观察'));
    expect(joined, contains('P011'));
    expect(joined, contains('「低声」类对话标签出现 3 次'));
    expect(joined, contains('只定位，不代改正文'));
  });

  test('#2 章节内容干净（无对话）→ 不注入（零 token 成本）', () async {
    // 覆盖章节内容为干净文本
    await (db.update(db.chapters)..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(content: const Value(_cleanContent)),
    );

    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined.contains('对话标签观察'), false);
  });

  test('#3 非诊断消息 → 即使有重复标签也不注入（触发时机门控）', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    // 普通聊天消息（无诊断标记）
    await service.sendMessage(sessionId, '今天写得有点卡', callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined.contains('对话标签观察'), false);
  });
}
