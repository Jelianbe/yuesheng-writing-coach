// ─────────────────────────────────────────────────────────────
// chat_service 关键路径测试（T8）
//
// 用 FakeLlmClient 覆盖 sendMessage 的核心路径：
//   1. 成功：user 消息写入 + assistant 消息写入 + onComplete 触发
//   2. 流式：onStream 收到 delta
//   3. LLM 异常 → onError 触发
//   4. 空响应 → onError 触发
//   5. 诊断块拦截：displayContent 不含 [YS_DIAGNOSIS] 内容
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
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// Fake LLM 客户端：预设 streamChat 响应
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

  /// 构造 ChatService（注入 FakeLlmClient）
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

  const defaultOptions = SendMessageOptions(
    phase: TeachingPhase.p0Engage,
    attitude: AttitudeLevel.doubao,
  );

  test(
    '#1 sendMessage 成功：user 消息写入 + assistant 消息写入 + onComplete 触发',
    () async {
      final chatService = buildChatService(FakeLlmClient('你好，我是月笙。'));

      String? completeContent;
      String? completeMessageId;

      await chatService.sendMessage(
        sessionId,
        '你好',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (content, messageId) {
            completeContent = content;
            completeMessageId = messageId;
          },
          onError: (_) {},
        ),
        defaultOptions,
      );

      // user 消息应已写入
      final messages = await sessionRepo.listMessages(sessionId);
      expect(messages.length, 2); // user + assistant
      expect(messages[0].role, 'user');
      expect(messages[0].content, '你好');
      expect(messages[1].role, 'assistant');
      expect(messages[1].content, contains('月笙'));

      // onComplete 应被触发
      expect(completeContent, isNotNull);
      expect(completeMessageId, isNotNull);
    },
  );

  test('#2 sendMessage 流式：onStream 收到 delta', () async {
    final chatService = buildChatService(FakeLlmClient('你好，我是月笙。'));

    final deltas = <String>[];

    await chatService.sendMessage(
      sessionId,
      '测试',
      SendMessageCallbacks(
        onStream: (delta) => deltas.add(delta),
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      defaultOptions,
    );

    // 应收到至少一个 delta
    expect(deltas, isNotEmpty);
    // deltas 拼接应包含完整内容
    expect(deltas.join(), contains('月笙'));
  });

  test('#3 sendMessage LLM 异常 → onError 触发', () async {
    final errorService = buildChatService(
      FakeLlmClient('', error: Exception('网络错误')),
    );

    String? errorMsg;

    await errorService.sendMessage(
      sessionId,
      '测试',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (err) => errorMsg = err,
      ),
      defaultOptions,
    );

    expect(errorMsg, isNotNull);
    expect(errorMsg, contains('网络错误'));
  });

  test('#4 sendMessage 空响应 → onError 触发', () async {
    final emptyService = buildChatService(FakeLlmClient(''));

    String? errorMsg;
    bool onCompleteCalled = false;

    await emptyService.sendMessage(
      sessionId,
      '测试',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) => onCompleteCalled = true,
        onError: (err) => errorMsg = err,
      ),
      defaultOptions,
    );

    // 空响应应触发 onError 而非 onComplete
    expect(onCompleteCalled, false);
    expect(errorMsg, isNotNull);
  });

  test('#5 sendMessage 诊断块拦截：displayContent 不含诊断 JSON', () async {
    // 模拟 LLM 返回：正文 + 诊断块
    const llmResponse =
        '你的文本节奏偏快。\n[YS_DIAGNOSIS]\n{"syndromes":[]}\n[/YS_DIAGNOSIS]';

    final diagService = buildChatService(FakeLlmClient(llmResponse));

    final streamedDeltas = <String>[];
    String? completeContent;

    await diagService.sendMessage(
      sessionId,
      '帮我看看',
      SendMessageCallbacks(
        onStream: (delta) => streamedDeltas.add(delta),
        onComplete: (content, _) => completeContent = content,
        onError: (_) {},
      ),
      defaultOptions,
    );

    // 流式 delta 拼接不应包含 [YS_DIAGNOSIS] 标记
    final streamedContent = streamedDeltas.join();
    expect(
      streamedContent.contains('[YS_DIAGNOSIS]'),
      false,
      reason: '诊断块不应通过 onStream 推送到 UI',
    );

    // onComplete 的 content 应是 displayContent（不含诊断块）
    expect(completeContent, isNotNull);
    expect(completeContent!.contains('[YS_DIAGNOSIS]'), false);
    expect(completeContent, contains('节奏偏快'));
  });

  test('#6 sendMessage user 消息在 assistant 之前写入', () async {
    final chatService = buildChatService(FakeLlmClient('收到。'));

    await chatService.sendMessage(
      sessionId,
      '第一条',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      defaultOptions,
    );

    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages.length, 2);
    expect(messages[0].role, 'user');
    expect(messages[0].content, '第一条');
    expect(messages[1].role, 'assistant');
    expect(messages[1].content, '收到。');
  });

  test('#7 sendMessage 多轮对话：历史消息正确累积', () async {
    final chatService = buildChatService(FakeLlmClient('好的。'));

    // 第一轮
    await chatService.sendMessage(
      sessionId,
      '第一轮',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      defaultOptions,
    );

    // 第二轮
    await chatService.sendMessage(
      sessionId,
      '第二轮',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      defaultOptions,
    );

    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages.length, 4); // 2 user + 2 assistant
    expect(messages[0].role, 'user');
    expect(messages[0].content, '第一轮');
    expect(messages[1].role, 'assistant');
    expect(messages[2].role, 'user');
    expect(messages[2].content, '第二轮');
    expect(messages[3].role, 'assistant');
  });

  test(
    '#8 T3 训练闭环：subphase=FEEDBACK + 达标回复 → onTrainingResult 触发（passed）',
    () async {
      // 模拟训练评估：LLM 回复含「达标」关键词
      final chatService = buildChatService(FakeLlmClient('很好，本次练习达标了！'));

      TrainingResult? trainingResult;
      await chatService.sendMessage(
        sessionId,
        '他攥紧拳头，指节发白。',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
          onTrainingResult: (result) => trainingResult = result,
        ),
        defaultOptions,
        subphase: TeachingSubphase.feedback,
      );

      // parseTrainingResult 命中「达标」→ passed
      expect(trainingResult, TrainingResult.passed);
    },
  );

  test('#9 T3 训练闭环：未达标回复 → onTrainingResult 触发（failed）', () async {
    final chatService = buildChatService(FakeLlmClient('本次练习未达标，建议重新理解要求。'));

    TrainingResult? trainingResult;
    await chatService.sendMessage(
      sessionId,
      '他还是直接写了「他很生气」。',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
        onTrainingResult: (result) => trainingResult = result,
      ),
      defaultOptions,
      subphase: TeachingSubphase.feedback,
    );

    expect(trainingResult, TrainingResult.failed);
  });

  // ── 批次1 C3：subphase=feedback 残留 ──
  //
  // 修复前：阶段不变时 subphase 永不重置，后续含「达标/未达标」字样消息
  // 误归属旧训练轮。修复后：训练轮终结（反馈解析命中）与新诊断提交都会
  // 重置子阶段。

  group('C3 subphase=feedback 残留（批次1）', () {
    late TeachingStateRepository stateRepo;
    late StudentModelRepository studentModelRepo;
    late DiagnosisRepository diagnosisRepo;

    setUp(() {
      stateRepo = TeachingStateRepository(db);
      studentModelRepo = StudentModelRepository(db);
      diagnosisRepo = DiagnosisRepository(db);
    });

    /// 种子活跃症候 s1 + 两条诊断历史（FSM 可评估、focus-resolver 有焦点）
    Future<void> seedActiveProblemAndHistory() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'diagnosis',
        'syndromes': ['s1'],
        'maxSeverity': 'L2',
        'timestamp': now - 100,
        'sessionId': sessionId,
      });
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'diagnosis',
        'syndromes': ['s1'],
        'maxSeverity': 'L1',
        'timestamp': now,
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
            {'syndrome_id': 's1', 'name': '叙事含糊', 'severity': 'L1'},
          ],
          suggestedActions: const [],
          confidence: 0.8,
        ),
      );
    }

    test('#S1 训练轮终结（feedback 解析命中）→ 子阶段重置为 null，后续含「达标」消息不再误触发', () async {
      await seedActiveProblemAndHistory();
      // 模拟旧训练轮残留：DB 子阶段 = FEEDBACK
      await stateRepo.updateSubphase(
        sessionId,
        TeachingSubphase.feedback.value,
      );

      final chatService = buildChatService(
        FakeLlmClient('很好，本次练习达标了！'),
      );

      // 第一轮：subphase=feedback 提交练习作答 → 命中训练结果解析
      await chatService.sendMessage(
        sessionId,
        '我改好了',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        defaultOptions,
        subphase: TeachingSubphase.feedback,
      );

      // 训练轮终结 → DB 子阶段被重置为 null
      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts?.currentSubphase, isNull,
          reason: '训练轮终结后应重置子阶段，防止 feedback 残留');

      // 第二轮：普通消息（不带 subphase），AI 回复仍含「达标」→ 不应再写入训练记录
      final before = await studentModelRepo.getTeachingHistory(sessionId);
      final trainingBefore = before
          .where((r) => r['type'] == 'training')
          .length;
      await chatService.sendMessage(
        sessionId,
        '随便聊聊',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        defaultOptions,
      );
      final after = await studentModelRepo.getTeachingHistory(sessionId);
      final trainingAfter = after.where((r) => r['type'] == 'training').length;
      expect(trainingAfter, trainingBefore,
          reason: '子阶段已重置，普通消息不应再被误归属为旧训练轮结果');
    });

    test('#S2 新诊断提交 → 子阶段重置为 null（新诊断=旧训练轮终结）', () async {
      await stateRepo.updateSubphase(
        sessionId,
        TeachingSubphase.feedback.value,
      );

      // 回复正文不含训练关键词（避免 feedback 分支先重置），
      // 只有诊断块 → 仅诊断提交路径（批次1 C3）重置子阶段
      final chatService = buildChatService(
        FakeLlmClient(
          '这段写得不错，注意下节奏。'
          '\n[YS_DIAGNOSIS]'
          '\n{"syndromes":[{"syndrome_id":"s1","name":"叙事含糊","severity":"L2","evidence":[],"explanation":"测试"}],"suggested_actions":[],"confidence":0.8}'
          '\n[/YS_DIAGNOSIS]',
        ),
      );

      await chatService.sendMessage(
        sessionId,
        '这是新章节内容',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        defaultOptions,
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts?.currentSubphase, isNull,
          reason: '新诊断提交 = 旧训练轮终结，应重置子阶段');
    });

    test('#S3 D4-A 分块诊断路径提交新诊断 → 子阶段同样重置为 null', () async {
      await stateRepo.updateSubphase(
        sessionId,
        TeachingSubphase.feedback.value,
      );

      // 模拟超长章节分块诊断（progressive 路径）产出的完整 AI 输出
      final chatService = buildChatService(FakeLlmClient('占位'));

      await chatService.commitDiagnosisFromContent(
        sessionId: sessionId,
        fullContent:
            '诊断说明。\n[YS_DIAGNOSIS]'
            '\n{"syndromes":[{"syndrome_id":"s1","name":"叙事含糊","severity":"L2","evidence":[],"explanation":"测试"}],"suggested_actions":[],"confidence":0.8}'
            '\n[/YS_DIAGNOSIS]',
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts?.currentSubphase, isNull,
          reason: 'D4-A 新诊断提交同样终结旧训练轮，应重置子阶段');
    });
  });

  // ── 批次6（6.7 V4）：流式跨 chunk 确认边界 ──
  //
  // _blockPendingPrefix 已实现：标记跨 chunk 到达时，未完成前缀暂缓转发，
  // 等完整标记出现后由拦截逻辑整体处理。此处补边界测试：
  //   - [YS_DIAGNOSIS]（14 字符）跨 chunk 拆分 → 流式不泄漏半截标记
  //   - [YS_FACT]（9 字符）跨 chunk 拆分 → 流式不泄漏半截标记
  // 断言统一用「onStream 增量不含任何 [YS_ 前缀」，覆盖诊断/大纲/事实三类标记。

  group('V4 流式跨 chunk 确认（批次6 6.7）', () {
    test('#V1 诊断标记跨 chunk 拆分 → onStream 不泄漏半截标记，onComplete 不含诊断块', () async {
      // chunkSize=8：`正文节奏不错。\n`（8 字符）+ `[YS_DIAGN`（8 字符）拆开
      // → [YS_DIAGNOSIS] 的「[YS_DIAGN」先到，末尾为未完成前缀
      const llmResponse =
          '正文节奏不错。\n[YS_DIAGNOSIS]\n{"syndromes":[]}\n[/YS_DIAGNOSIS]';
      final diagService = buildChatService(FakeLlmClient(llmResponse, chunkSize: 8));

      final streamedDeltas = <String>[];
      String? completeContent;

      await diagService.sendMessage(
        sessionId,
        '帮我看看',
        SendMessageCallbacks(
          onStream: (delta) => streamedDeltas.add(delta),
          onComplete: (content, _) => completeContent = content,
          onError: (_) {},
        ),
        defaultOptions,
      );

      final streamedContent = streamedDeltas.join();
      expect(
        streamedContent.contains('[YS_'),
        false,
        reason: '跨 chunk 拆分时半截协议标记也不应通过 onStream 推送',
      );
      expect(streamedContent, contains('正文节奏不错'));

      expect(completeContent, isNotNull);
      expect(completeContent!.contains('[YS_DIAGNOSIS]'), false);
      expect(completeContent, contains('正文节奏不错'));
    });

    test('#V2 事实标记跨 chunk 拆分 → onStream 不泄漏半截标记', () async {
      // chunkSize=4：`正文。\n`（4 字符）+ `[YS_`（4 字符）拆开
      const llmResponse = '正文。\n[YS_FACT]\n{"events":[]}\n[/YS_FACT]';
      final factService = buildChatService(FakeLlmClient(llmResponse, chunkSize: 4));

      final streamedDeltas = <String>[];

      await factService.sendMessage(
        sessionId,
        '帮我看看',
        SendMessageCallbacks(
          onStream: (delta) => streamedDeltas.add(delta),
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        defaultOptions,
      );

      final streamedContent = streamedDeltas.join();
      expect(
        streamedContent.contains('[YS_'),
        false,
        reason: '[YS_FACT] 跨 chunk 拆分时半截标记不应通过 onStream 推送',
      );
      expect(streamedContent, contains('正文。'));
    });

    test('#V3 标记完整在同一 chunk → 拦截行为不回归（同 #5）', () async {
      const llmResponse =
          '你的文本节奏偏快。\n[YS_DIAGNOSIS]\n{"syndromes":[]}\n[/YS_DIAGNOSIS]';
      final diagService = buildChatService(FakeLlmClient(llmResponse));

      final streamedDeltas = <String>[];
      String? completeContent;

      await diagService.sendMessage(
        sessionId,
        '帮我看看',
        SendMessageCallbacks(
          onStream: (delta) => streamedDeltas.add(delta),
          onComplete: (content, _) => completeContent = content,
          onError: (_) {},
        ),
        defaultOptions,
      );

      final streamedContent = streamedDeltas.join();
      expect(streamedContent.contains('[YS_DIAGNOSIS]'), false);
      expect(completeContent, isNotNull);
      expect(completeContent!.contains('[YS_DIAGNOSIS]'), false);
    });
  });
}
