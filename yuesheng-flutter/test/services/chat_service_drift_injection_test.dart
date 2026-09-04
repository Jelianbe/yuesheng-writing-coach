// ─────────────────────────────────────────────────────────────
// chat_service_drift_injection_test — 批次64 B62f 声线漂移注入测试
//
// 覆盖：
//   1. 无基线（首次诊断）→ 建立基线，不注入漂移提示
//   2. 有基线 + 当前文本句长显著偏离 → 注入「声线漂移检测」system 消息
//   3. 非诊断消息（无诊断标记）→ 即使有偏离也不注入（触发时机门控）
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
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/style_fingerprint.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 章节正文：短句密集（avg ≈ 8 字），与基线（20 字）显著偏离
const String _shortSentenceChapter =
    '他推开门，风灌了进来。\n'
    '她站在窗边，一言不发。\n'
    '他忽然笑了，笑得很难看。\n'
    '她回头看他，眼眶有些红。\n'
    '他们都没有再说话。\n'
    '窗外是沉默的雪。\n'
    '炉火噼啪作响。\n'
    '这一夜特别长。\n'
    '他握紧了拳头。\n'
    '她轻轻叹了口气。';

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

/// 基线指纹：句长 20 字、对话占比 0.3
StyleFingerprint _baseline() {
  return StyleFingerprint(
    avgSentenceLength: 20,
    sentenceLengthVariance: 12,
    shortParaRatio: 0.4,
    mediumParaRatio: 0.4,
    longParaRatio: 0.2,
    dialogueRatio: 0.3,
    narrativeRatio: 0.7,
    simpleSentenceRatio: 0.5,
    metaphorDensity: 0.5,
    rhetoricalQuestionDensity: 0.2,
    ellipsisDensity: 1,
    exclamationDensity: 0.5,
    topWords: const {},
    sentencesCount: 30,
  );
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late String sessionId;
  late String chapterId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();

    // 建稿 + 章节 + 会话主引用（章节）
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final refRepo = ReferenceRepository(db);
    final manuscriptId = await msRepo.createManuscript(title: '测试稿');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: _shortSentenceChapter,
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
      // ADR-C74 K-3：声线漂移提示已迁至 DiagnosisCommitter.buildDriftHintContext
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
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
  String diagPrompt() => '请对以下章节内容进行写作诊断分析：\n\n【第一章】\n$_shortSentenceChapter';

  test('#1 无基线（首次诊断）→ 建立基线，不注入漂移提示', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined.contains('声线漂移检测'), false);

    // 基线已建立
    final stored = await StudentModelRepository(
      db,
    ).getStyleFingerprint(sessionId);
    expect(stored, isNotNull);
    expect(stored!.sentencesCount, greaterThanOrEqualTo(5));
  });

  test('#2 有基线 + 句长显著偏离 → 注入「声线漂移检测」提示', () async {
    // 预置基线（句长 20 字），章节文本 avg ≈ 8 字 → 偏离 ≥40%
    await StudentModelRepository(
      db,
    ).updateStyleFingerprint(sessionId, _baseline());

    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined, contains('声线漂移检测'));
    expect(joined, contains('通常约 20 字'));
    expect(joined, contains('平均只有'));
    expect(joined, contains('是刻意加速'));
  });

  test('#3 非诊断消息 → 即使有偏离也不注入（触发时机门控）', () async {
    await StudentModelRepository(
      db,
    ).updateStyleFingerprint(sessionId, _baseline());

    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    // 普通聊天消息（无诊断标记）
    await service.sendMessage(sessionId, '今天写得有点卡', callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined.contains('声线漂移检测'), false);
  });

  test('#4 章节文本过短 → 指纹为 null，不注入也不落基线', () async {
    // 建一个短章节作为主引用
    final chRepo = ChapterRepository(db);
    final refRepo = ReferenceRepository(db);
    final msRepo = ManuscriptRepository(db);
    final shortMs = await msRepo.createManuscript(title: '短稿');
    final shortCh = await chRepo.createChapter(
      shortMs,
      title: '短章',
      content: '他走了。',
    );
    await refRepo.addReference(sessionId, 'chapter', shortCh, isPrimary: true);

    await StudentModelRepository(
      db,
    ).updateStyleFingerprint(sessionId, _baseline());

    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, diagPrompt(), callbacks(), options());

    final joined = llm.systemContents.join('\n');
    expect(joined.contains('声线漂移检测'), false);
  });
}
