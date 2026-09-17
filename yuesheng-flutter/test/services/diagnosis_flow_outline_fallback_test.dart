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
    Map<String, dynamic>? extraBody,
  }) async {
    if (_fullResponse.isNotEmpty) {
      callback(LlmStreamResponse(content: _fullResponse, isDone: false));
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// 按调用次序回放不同响应的 Fake（S4b #1b 用：第 1 次 = 主链诊断块，
/// 第 2 次 = teacher 建议链返回空——否则 teacher 会把诊断块原文当回复，
/// combinedContent 非空，占位路径不触发）。
class SeqFakeLlmClient extends LlmClient {
  SeqFakeLlmClient(this._responses);

  final List<String> _responses;
  int _cursor = 0;

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    final response = _cursor < _responses.length ? _responses[_cursor++] : '';
    if (response.isNotEmpty) {
      callback(LlmStreamResponse(content: response, isDone: false));
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
    // assistant 消息落库，内容为 S4b 升级占位（实体分型，R6/Q1 甲）
    final messages = await sessionRepo.listMessages(sessionId);
    final assistant = messages
        .where((m) => m.role == 'assistant')
        .map((m) => m.content)
        .toList();
    expect(assistant, isNotEmpty, reason: 'M5: 兜底成立后应写入 assistant 消息');
    expect(assistant.last, contains('大纲实体已保存'), reason: 'S4b: 空响应判真后应写入实体分型占位');
    expect(assistant.last, contains('已保存'), reason: 'S4b 硬约束①: 必须交代「数据已保存」');
    expect(assistant.last, contains('文字点评'), reason: 'S4b 硬约束①: 必须交代「缺文字点评」');
    expect(assistant.last, contains('临时故障'), reason: 'S4b: 交代可能是网络或模型临时故障');
    expect(
      assistant.last,
      isNot(contains('建议保存')),
      reason: 'S4b: 实体已持久化，回执不应误降级',
    );
  });

  test('#1b 空正文 + 有诊断块 → 升级占位（诊断分型：N 条症候），不 abort', () async {
    final errors = <String>[];
    final svc = buildService(
      SeqFakeLlmClient([
        // 第 1 次：主链流式响应 = 纯诊断块（无自然语言后缀）→ combinedContent 空
        // 有意分行的 JSON 拼接（相邻字面量在编译期合并，非漏逗号）
        // ignore: no_adjacent_strings_in_list
        '[YS_DIAGNOSIS]'
            '{"syndromes":[{"syndrome_id":"P003","name":"情绪直白","severity":"L2",'
            '"evidence":["第3段"],"explanation":"情绪描写过于直白"}],'
            '"suggested_actions":[],"confidence":0.8}'
            '[/YS_DIAGNOSIS]',
        // 第 2 次：teacher 建议链返回空（占位路径要求 combinedContent 全空）
        '',
      ]),
      outlineRepo: OutlineRepository(db),
    );
    await svc.sendMessage(sessionId, '帮我诊断', callbacks(errors), options());

    expect(errors, isEmpty, reason: 'S4b: 有诊断块时判真，不触发 onError');
    final messages = await sessionRepo.listMessages(sessionId);
    final assistant = messages
        .where((m) => m.role == 'assistant')
        .map((m) => m.content)
        .toList();
    expect(assistant, isNotEmpty);
    expect(
      assistant.last,
      contains('诊断数据已保存（1 条症候）'),
      reason: 'S4b: 诊断分型占位应带症候计数',
    );
    expect(assistant.last, contains('文字点评'), reason: 'S4b 硬约束①: 两件事齐说');
    expect(
      assistant.last,
      isNot(contains('诊断完成')),
      reason: 'S4b: 病根占位「诊断完成。」应被替换',
    );
  });

  test('#1c 正文非空 → 逐字原样落库，不触占位（R6-AC3）', () async {
    final errors = <String>[];
    final svc = buildService(
      FakeLlmClient('这段的开头张力立住了，但中段节奏偏平，建议压缩铺垫。'),
      outlineRepo: OutlineRepository(db),
    );
    await svc.sendMessage(sessionId, '帮我诊断', callbacks(errors), options());

    expect(errors, isEmpty);
    final messages = await sessionRepo.listMessages(sessionId);
    final assistant = messages
        .where((m) => m.role == 'assistant')
        .map((m) => m.content)
        .toList();
    expect(
      assistant,
      contains('这段的开头张力立住了，但中段节奏偏平，建议压缩铺垫。'),
      reason: 'S4b AC3: 非空正文逐字不变，占位文案不参与',
    );
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
    await chapterRepo.createChapter(manuscriptId, title: '第一章', content: '正文');
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
