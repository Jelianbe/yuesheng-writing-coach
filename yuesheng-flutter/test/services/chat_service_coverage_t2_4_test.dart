// ─────────────────────────────────────────────────────────────
// chat_service 覆盖率补测（T2-4）
//
// 目标：把 lib/services/chat_service.dart 行覆盖率从 75.24% 上提到 ≥85%。
// 策略：直接调用公开方法 + 走活跃症候主链路（_injectDiagnosisLock）+ 走
// commitDiagnosisFromContent 主路径（含章节引用）+ 章节引用注入 / 观察路径。
// 全部零行为变更，沿用既有 in-memory DB + FakeLlmClient 夹具。
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
import 'package:writingcoach/services/genui_parser.dart'
    show GenUiParser;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
/// Fake LLM 客户端：预设 streamChat 响应（不触发诊断/训练分支）
class FakeLlmClient extends LlmClient {
  final String _fullResponse;
  final Exception? _error;
  final int _chunkSize;

  FakeLlmClient(this._fullResponse, {Exception? error, int chunkSize = 10})
    : _error = error,
      _chunkSize = chunkSize;

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    if (_error != null) throw _error;
    for (int i = 0; i < _fullResponse.length; i += _chunkSize) {
      final end = i + _chunkSize < _fullResponse.length
          ? i + _chunkSize
          : _fullResponse.length;
      callback(
        LlmStreamResponse(
          content: _fullResponse.substring(i, end),
          isDone: false,
        ),
      );
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// 捕获发给 LLM 的 messages（含注入的 system 消息），便于断言引用/观察注入
class _CaptureLlmClient extends LlmClient {
  final List<ChatMessage> _sink;
  final String _fullResponse;

  _CaptureLlmClient(this._fullResponse, this._sink);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    _sink
      ..clear()
      ..addAll(messages);
    callback(LlmStreamResponse(content: _fullResponse, isDone: false));
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
        ),

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
        llmClient: llmClient,

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
          ),

          material: const MaterialCapabilityImpl(),
        ),
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: ReferenceRepository(db),
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

  /// 种子一个活跃症候 s1（severity L2），让 sendMessage 进入 _injectDiagnosisLock
  Future<void> seedActiveProblem() async {
    final diagnosisRepo = DiagnosisRepository(db);
    final studentModelRepo = StudentModelRepository(db);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'diagnosis',
      'syndromes': ['s1'],
      'maxSeverity': 'L2',
      'timestamp': now - 100,
      'sessionId': sessionId,
    });
    final msgId = await sessionRepo.addMessage(
      sessionId,
      'assistant',
      '诊断内容',
      messageType: 'diagnosis_result',
    );
    await diagnosisRepo.commitDiagnosis(
      DiagnosisInput(
        sessionId: sessionId,
        messageId: msgId,
        syndromes: [
          {'syndrome_id': 's1', 'name': '叙事含糊', 'severity': 'L2'},
        ],
        suggestedActions: const [],
        confidence: 0.8,
      ),
    );
  }

  /// 创建主稿 + 主引用章节，返回章节 id
  Future<String> seedChapterReference() async {
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final refRepo = ReferenceRepository(db);
    final ms = await msRepo.createManuscript(title: '主稿', genre: '小说');
    final ch = await chRepo.createChapter(
      ms,
      title: '第一章 风起',
      content: '风起云涌的独特锚点XYZ，这一段写得很用心。',
    );
    await refRepo.addReference(sessionId, 'chapter', ch, isPrimary: true);
    return ch;
  }

  // ───────────────────────── A 组：公开方法直接调用 ─────────────────────────

  test('A1 initSession 无会话 → 新建空白会话并返回 id', () async {
    final chatService = buildChatService(FakeLlmClient('ok'));
    final id = await chatService.initSession();
    expect(id, isNotEmpty);
    final sessions = await sessionRepo.listSessions();
    expect(sessions.length, 1);
  });

  test('A2 initSession 已有会话 → 复用既有会话（不新建）', () async {
    final chatService = buildChatService(FakeLlmClient('ok'));
    final before = (await sessionRepo.listSessions()).length; // setUp 已建 1 个
    final id = await chatService.initSession();
    final after = (await sessionRepo.listSessions()).length;
    expect(after, before, reason: '已有会话时不应新建空白会话');
    expect(id, sessionId, reason: '应复用首个既有会话');
  });

  test('A3 loadAttitudeState 无状态 → 默认 doubao / p0Engage', () async {
    final chatService = buildChatService(FakeLlmClient('ok'));
    final state = await chatService.loadAttitudeState(sessionId);
    expect(state.attitude, AttitudeLevel.doubao);
    expect(state.phase, TeachingPhase.p0Engage);
  });

  test('A4 persistAttitude + loadAttitudeState 往返一致', () async {
    final chatService = buildChatService(FakeLlmClient('ok'));
    await chatService.persistAttitude(sessionId, AttitudeLevel.sensei);
    final state = await chatService.loadAttitudeState(sessionId);
    expect(state.attitude, AttitudeLevel.sensei);
  });

  test('A5 loadMessages 写入后可读取', () async {
    final chatService = buildChatService(FakeLlmClient('你好。'));
    await chatService.sendMessage(
      sessionId,
      '在吗',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      defaultOptions,
    );
    final messages = await chatService.loadMessages(sessionId);
    expect(messages.length, greaterThanOrEqualTo(2));
  });

  test('A6 loadSubphase 无状态 → null', () async {
    final chatService = buildChatService(FakeLlmClient('ok'));
    final sub = await chatService.loadSubphase(sessionId);
    expect(sub, isNull);
  });

  test('A7 setSubphase + loadSubphase 往返一致', () async {
    final chatService = buildChatService(FakeLlmClient('ok'));
    await chatService.setSubphase(sessionId, TeachingSubphase.feedback);
    final sub = await chatService.loadSubphase(sessionId);
    expect(sub, TeachingSubphase.feedback);
  });

  test('A8 loadAttitudeState 读取已持久化的阶段（非空 fallback 分支）', () async {
    final chatService = buildChatService(FakeLlmClient('ok'));
    final stateRepo = TeachingStateRepository(db);
    await stateRepo.persistAttitude(sessionId, AttitudeLevel.sensei.value);
    await stateRepo.updatePhase(sessionId, TeachingPhase.p1World.value);
    final state = await chatService.loadAttitudeState(sessionId);
    expect(state.attitude, AttitudeLevel.sensei);
    expect(state.phase, TeachingPhase.p1World);
  });

  // ───────────── B 组：活跃症候主链路（_injectDiagnosisLock） ─────────────

  test('B1 活跃症候 + 普通消息 → 进入 focus 锁定注入且不抛错', () async {
    await seedActiveProblem();
    final chatService = buildChatService(FakeLlmClient('这一段写得不错。'));

    String? completeContent;
    await chatService.sendMessage(
      sessionId,
      '随便聊聊今天写的部分',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (content, _) => completeContent = content,
        onError: (_) {},
      ),
      defaultOptions,
    );

    // 主链路正常完成，assistant 消息落库
    expect(completeContent, isNotNull);
    final messages = await sessionRepo.listMessages(sessionId);
    expect(
      messages.any((m) => m.role == 'assistant'),
      isTrue,
      reason: '活跃症候主链路应正常产出 assistant 回复',
    );
  });

  // ───────────── C 组：commitDiagnosisFromContent 主路径 ─────────────

  test('C1 带章节引用 + 诊断块 → 解析/落库/引用查询全跑通', () async {
    await seedChapterReference();
    final chatService = buildChatService(FakeLlmClient('占位'));

    final fullContent =
        '诊断说明。\n[YS_DIAGNOSIS]'
        '\n{"syndromes":[{"syndrome_id":"s1","name":"叙事含糊","severity":"L2","evidence":[],"explanation":"测试"}],"suggested_actions":[],"confidence":0.8}'
        '\n[/YS_DIAGNOSIS]';

    final messageId = await chatService.commitDiagnosisFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
    );

    expect(messageId, isNotEmpty);
    // 诊断应已落库
    final history = await DiagnosisRepository(
      db,
    ).listDiagnosisHistory(sessionId);
    expect(history, isNotEmpty);
  });

  test('C2 无诊断块重复提交 → 跨失败阈值触发诊断失败卡（不抛错）', () async {
    final chatService = buildChatService(FakeLlmClient('占位'));
    // 连续多次提交不含诊断块的内容，推动连续失败计数越过阈值
    for (int i = 0; i < 4; i++) {
      await chatService.commitDiagnosisFromContent(
        sessionId: sessionId,
        fullContent: '这一段只是普通讨论，没有诊断块。',
      );
    }
    // 不抛错即通过（覆盖 _recordDiagnosisOutcome 失败卡分支）
    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages, isNotEmpty);
  });

  // ───────────── D 组：章节引用注入 / 观察路径 ─────────────

  test('D1 章节主引用 + 普通消息 → 引用内容注入 system 消息', () async {
    await seedChapterReference();
    final captured = <ChatMessage>[];
    final chatService = buildChatService(_CaptureLlmClient('已读。', captured));

    await chatService.sendMessage(
      sessionId,
      '请看看这一章',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      defaultOptions,
    );

    // 引用章节标题应出现在发给 LLM 的 system 消息中（证明 _injectReferencesAndReviewer 执行）
    final systemJoined = captured
        .where((m) => m.role == 'system')
        .map((m) => m.content)
        .join('\n');
    expect(systemJoined, contains('第一章 风起'));
  });

  test('D2 章节引用 + 诊断标记消息 → 进入观察/漂移检测路径不抛错', () async {
    await seedChapterReference();
    final chatService = buildChatService(FakeLlmClient('收到分析。'));

    await chatService.sendMessage(
      sessionId,
      '写作诊断分析：这一章节奏如何？',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      defaultOptions,
    );

    // 走通引用注入 + 漂移检测分支（fact/conflict/causality 仓储未装配则静默跳过）
    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages.any((m) => m.role == 'assistant'), isTrue);
  });
}
