// ─────────────────────────────────────────────────────────────
// chat_service_reference_preload_test — A-3 遗留 N+1 消除：批量预加载回归
//
// 锁定 _preloadReferenceDetails 批量版行为：同一会话混合 chapter（主）+
// manuscript（次）+ file（次）三类引用时，一次 sendMessage 即把三类缓存全部
// 填充，使 buildReferencesContext 注入的 system 消息同时含三类内容。
// （原逐条实现亦应通过；本测试守护批量重构不回退该契约。）
// ─────────────────────────────────────────────────────────────

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
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 捕获注入 system 消息的 Fake LLM
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
    callback(const LlmStreamResponse(content: '已就绪。', isDone: false));
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

    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final refRepo = ReferenceRepository(db);

    // 主稿 + 主引用章节（primary）
    final msA = await msRepo.createManuscript(title: '主稿', genre: '小说');
    final chA = await chRepo.createChapter(
      msA,
      title: '第一章 风起',
      content: '风起云涌的独特锚点XYZ',
    );
    await refRepo.addReference(sessionId, 'chapter', chA, isPrimary: true);

    // 主稿上的素材文件（secondary file 引用）
    final file = await refRepo.createAttachedFile(
      bookId: msA,
      fileName: '人物表.txt',
      fileRole: 'outline',
      content: '主角：林某',
    );
    await refRepo.addReference(sessionId, 'file', file.id);

    // 副稿 + 其章节（secondary manuscript 引用）
    final msB = await msRepo.createManuscript(title: '副稿', genre: '短篇');
    await chRepo.createChapter(msB, title: '序章', content: '副稿序章正文');
    await refRepo.addReference(sessionId, 'manuscript', msB);
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

  test('混合三类引用 → 批量预加载一次填充 chapter/manuscript/file 缓存', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '请诊断这一章。', callbacks(), options());

    final joined = llm.systemContents.join('\n');

    // 章节主引用：标题 + 正文（证明 _cachedChapters 填充）
    expect(joined, contains('第一章 风起'));
    expect(joined, contains('风起云涌的独特锚点XYZ'));

    // 素材次要引用：文件名 + 内容（证明 _cachedAttachedFiles 填充）
    expect(joined, contains('【素材文件】人物表.txt'));
    expect(joined, contains('主角：林某'));

    // 作品次要引用：标题 + 目录概览中的章节（证明 _cachedManuscripts 填充，含 chapters）
    expect(joined, contains('作品：副稿'));
    expect(joined, contains('序章'));
  });
}
