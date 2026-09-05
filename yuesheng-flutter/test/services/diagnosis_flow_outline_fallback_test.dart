// ─────────────────────────────────────────────────────────────
// DiagnosisFlowHandler 空响应 outline 兜底分支测试 — ADR-C74 K-9 收尾 §6.2（M5 盲区补测）
//
// 背景：K-9 mutation M5 暴露 `_resolveFinalAssistantContent` 的 outline 兜底分支
//   （combinedContent 空 + 无诊断 + outlineRepo 已装配 + primaryRef.refType=='chapter'
//    + 该 chapter 的 manuscript 有 outline 实体 → treatAsValid=true 不 abort）
//   在现有测试中零触达——没有任何测试给 DiagnosisFlowHandler 装配 outlineRepo。
//   本文件补 3 例，把该分支钉在判据上（M5 变异 `c > 0` → `c < 0` 应被拦截）。
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
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/types/teaching_types.dart';

class FakeLlmClient extends LlmClient {
  FakeLlmClient(this._fullResponse);

  final String _fullResponse;

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    if (_fullResponse.isNotEmpty) {
      callback(LlmStreamResponse(content: _fullResponse, isDone: false));
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late TeachingStateRepository stateRepo;
  late DiagnosisRepository diagnosisRepo;
  late StudentModelRepository studentModelRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    stateRepo = TeachingStateRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  /// 完整装配 ChatService（DiagnosisFlowHandler 按需装配 outlineRepo）。
  ///
  /// M5 兜底分支依赖 DiagnosisFlowHandler 自身持有 outlineRepo
  /// （`_ensureOutlineService()`），仅装配到 DiagnosisCommitter 不够——
  /// 这正是旧测试（phase_migration #12）从未触达该分支的原因。
  ChatService buildService(
    LlmClient llm, {
    required OutlineRepository? outlineRepo,
  }) {
    return ChatService(
      sessionRepo: sessionRepo,
      stateRepo: stateRepo,
      diagnosisRepo: diagnosisRepo,
      studentModelRepo: studentModelRepo,
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      llmClient: llm,
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      editorObservationRepo: EditorObservationRepository(db),
      outlineRepo: outlineRepo,
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagnosisRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        outlineRepo: outlineRepo,
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
          stateRepo: stateRepo,
          diagnosisRepo: diagnosisRepo,
          studentModelRepo: studentModelRepo,
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
          outlineRepo: outlineRepo,
        ),
        material: const MaterialCapabilityImpl(),
      ),
      diagnosisFlowHandler: DiagnosisFlowHandler(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagnosisRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        teacherSuggestionRepo: TeacherSuggestionRepository(db),
        llmClient: llm,
        outlineRepo: outlineRepo,
        messageInjector: MessageInjector(
          sessionRepo: sessionRepo,
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
          manuscriptRepo: ManuscriptRepository(db),
          diagnosisCommitter: DiagnosisCommitter(
            sessionRepo: sessionRepo,
            stateRepo: stateRepo,
            diagnosisRepo: diagnosisRepo,
            studentModelRepo: studentModelRepo,
            referenceRepo: ReferenceRepository(db),
            chapterRepo: ChapterRepository(db),
            outlineRepo: outlineRepo,
          ),
          material: const MaterialCapabilityImpl(),
        ),
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: stateRepo,
          diagnosisRepo: diagnosisRepo,
          studentModelRepo: studentModelRepo,
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
          outlineRepo: outlineRepo,
        ),
        diagnosis: const DiagnosisCapabilityImpl(),
        genUi: const GenUiParser(),
      ),
    );
  }

  SendMessageCallbacks callbacks(List<String> errors) => SendMessageCallbacks(
    onStream: (_) {},
    onComplete: (_, _) {},
    onError: (e) => errors.add(e),
  );

  SendMessageOptions options() => const SendMessageOptions(
    phase: TeachingPhase.p1World,
    attitude: AttitudeLevel.doubao,
  );

  test('#1 空响应 + 无诊断 + chapter 有 outline 实体 → 兜底判真，不 abort', () async {
    final outlineRepo = OutlineRepository(db);
    final chapterRepo = ChapterRepository(db);
    final msRepo = ManuscriptRepository(db);
    final refRepo = ReferenceRepository(db);

    final manuscriptId = await msRepo.createManuscript(title: 'M5 盲区手稿');
    final chapterId = await chapterRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: '正文',
    );
    // chapter 主引用（M5 兜底前置条件 primaryRef.refType == 'chapter'）
    await refRepo.addReference(
      sessionId,
      'chapter',
      chapterId,
      isPrimary: true,
    );
    // 该 manuscript 至少一个 outline 实体 → buildEntityIndexContext 非 null
    await outlineRepo.insertEntity(
      manuscriptId: manuscriptId,
      entityType: 'character',
      entityKey: '王建国',
    );

    final errors = <String>[];
    final svc = buildService(
      FakeLlmClient(''), // 空响应：无内容、无诊断块
      outlineRepo: outlineRepo,
    );
    await svc.sendMessage(sessionId, '帮我诊断', callbacks(errors), options());

    // 兜底成立 → 不触发 onError('AI 返回为空')
    expect(errors, isEmpty, reason: 'M5: 有 outline 实体时应判真，不 abort');
    // assistant 消息落库，内容为兜底占位「诊断完成。」
    final messages = await sessionRepo.listMessages(sessionId);
    final assistant = messages
        .where((m) => m.role == 'assistant')
        .map((m) => m.content)
        .toList();
    expect(assistant, isNotEmpty, reason: 'M5: 兜底成立后应写入 assistant 消息');
    expect(assistant.last, contains('诊断完成'), reason: 'M5: 空响应判真后应写入「诊断完成。」占位');
  });

  test('#2 空响应 + 无诊断 + chapter 无 outline 实体 → 仍 abort', () async {
    final outlineRepo = OutlineRepository(db);
    final chapterRepo = ChapterRepository(db);
    final msRepo = ManuscriptRepository(db);
    final refRepo = ReferenceRepository(db);

    final manuscriptId = await msRepo.createManuscript(title: 'M5 对照手稿');
    final chapterId = await chapterRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: '正文',
    );
    await refRepo.addReference(
      sessionId,
      'chapter',
      chapterId,
      isPrimary: true,
    );
    // 关键：不插任何实体 → buildEntityIndexContext 返回 null → c == 0

    final errors = <String>[];
    final svc = buildService(FakeLlmClient(''), outlineRepo: outlineRepo);
    await svc.sendMessage(sessionId, '帮我诊断', callbacks(errors), options());

    expect(
      errors,
      contains('AI 返回为空'),
      reason: 'M5: 无实体时兜底不成立，应 abort 触发 onError',
    );
  });

  test('#3 空响应 + 无诊断 + outline 实体存在但主引用非 chapter → 仍 abort', () async {
    final outlineRepo = OutlineRepository(db);
    final chapterRepo = ChapterRepository(db);
    final msRepo = ManuscriptRepository(db);
    final refRepo = ReferenceRepository(db);

    final manuscriptId = await msRepo.createManuscript(title: 'M5 对照手稿 2');
    final chapterId = await chapterRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: '正文',
    );
    // 主引用类型为 manuscript（非 chapter）→ `primaryRef?.refType == 'chapter'` 不成立
    await refRepo.addReference(
      sessionId,
      'manuscript',
      manuscriptId,
      isPrimary: true,
    );
    await outlineRepo.insertEntity(
      manuscriptId: manuscriptId,
      entityType: 'character',
      entityKey: '王建国',
    );

    final errors = <String>[];
    final svc = buildService(FakeLlmClient(''), outlineRepo: outlineRepo);
    await svc.sendMessage(sessionId, '帮我诊断', callbacks(errors), options());

    expect(
      errors,
      contains('AI 返回为空'),
      reason: 'M5: 主引用非 chapter 时兜底不成立，应 abort',
    );
  });
}
