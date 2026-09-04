// ─────────────────────────────────────────────────────────────
// chat_service_intent_injection_test — 批次63 B62b 意图注入测试
//
// 覆盖：
//   1. smalltalk → 注入「闲聊」system 消息 + 最近意图序列
//   2. ask → 注入「询问」消息
//   3. revise → 注入「修改」消息
//   4. compose → 不注入
//   5. 意图向量保留最近 3 条
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
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
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 捕获注入 messages 的 Fake LLM
class _CaptureLlmClient extends LlmClient {
  List<String> systemContents = [];
  List<String> capturedUserContent = [];

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
    callback(const LlmStreamResponse(content: '收到，我们继续。', isDone: false));
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
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
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

  bool hasIntentNote(List<String> systems, String marker) {
    return systems.any((s) => s.contains('## 交互意图') && s.contains(marker));
  }

  test('#1 smalltalk → 注入「闲聊」消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '你好', callbacks(), options());
    await service.sendMessage(sessionId, '在吗', callbacks(), options());

    expect(llm.systemContents, isNotEmpty);
    // 至少一轮注入闲聊意图（第二轮的 systemContents 即本次）
    expect(hasIntentNote(llm.systemContents, '闲聊'), true);
    expect(llm.systemContents.join('\n'), contains('不要发起诊断'));
  });

  test('#2 ask → 注入「询问」消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '这段对话怎么改更好？', callbacks(), options());

    expect(hasIntentNote(llm.systemContents, '询问'), true);
    expect(llm.systemContents.join('\n'), contains('不要展开新的诊断'));
  });

  test('#3 revise → 注入「修改」消息（降诊断强度 + 不替写）', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '把这段对话改成动作描写', callbacks(), options());

    expect(hasIntentNote(llm.systemContents, '修改'), true);
    final joined = llm.systemContents.join('\n');
    expect(joined, contains('只提示最关键的问题'));
    expect(joined, contains('不替学员改写正文'));
  });

  test('#4 compose → 不注入意图消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(
      sessionId,
      '他推开门，风灌了进来，桌上的信纸被吹落在地。',
      callbacks(),
      options(),
    );

    expect(hasIntentNote(llm.systemContents, '创作'), false);
    expect(llm.systemContents.any((s) => s.contains('## 交互意图')), false);
  });

  test('#5 意图向量保留最近 3 条（序列注入）', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    // 连续 4 条：ask → ask → smalltalk → ask；最后一条注入含最近 3 条意图
    await service.sendMessage(sessionId, '怎么提升节奏？', callbacks(), options());
    await service.sendMessage(sessionId, '为什么这段出戏？', callbacks(), options());
    await service.sendMessage(sessionId, '好的', callbacks(), options());
    await service.sendMessage(sessionId, '这段话是什么意思？', callbacks(), options());

    final joined = llm.systemContents.join('\n');
    // 最近 3 条意图 = smalltalk → ask（第一条 ask 已被挤出）
    expect(joined, contains('smalltalk → ask'));
    // 不应包含 4 条意图（只保留 3）
    expect(joined.contains('ask → ask → smalltalk → ask'), false);
  });

  test('#6 「长话短说」→ 注入压缩颗粒度消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '这段怎么改，长话短说', callbacks(), options());

    expect(llm.systemContents.any((s) => s.contains('回复颗粒度：压缩')), true);
    expect(llm.systemContents.join('\n'), contains('一句话结论'));
    expect(llm.systemContents.join('\n'), contains('删除一切铺垫'));
  });

  test('#7 「详细点」→ 注入展开颗粒度消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '再详细讲讲这个技巧', callbacks(), options());

    expect(llm.systemContents.any((s) => s.contains('回复颗粒度：展开')), true);
    expect(llm.systemContents.join('\n'), contains('完整示范'));
  });

  test('#8 无颗粒度信号 → 不注入颗粒度消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '他推开门，风灌了进来', callbacks(), options());

    expect(llm.systemContents.any((s) => s.contains('回复颗粒度')), false);
  });
}
