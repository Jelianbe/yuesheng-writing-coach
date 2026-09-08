// ─────────────────────────────────────────────────────────────
// realtime_observation_service_test — 批次68 A7 实时通道服务测试
//
// 覆盖：
//   1. observe 成功 → displayContent + observation + messageId，observation 入库
//   2. 流式回调透传 + targetRef 字段入库
//   3. LLM 失败 → observation=null，不抛出，不入库（兜底）
//   4. 轻量约束 system 消息已附加（轻 prompt 语义）
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/realtime_observation_service.dart';

/// 合法 EditorResult JSON（3 条 observation）
const String _validEditorJson = '''{
  "possible_intent": "表达情绪",
  "intent_confidence": "moderate",
  "observations": [
    {
      "dimension": "character_agency",
      "dimension_name": "人物能动性",
      "phenomenon": "主角缺乏主动选择",
      "evidence": ["第3段被动反应"],
      "reader_impact": "读者难以代入",
      "observation_visibility": "pronounced",
      "intent_alignment": "against"
    },
    {
      "dimension": "pacing_control",
      "dimension_name": "节奏控制",
      "phenomenon": "场景推进偏快",
      "evidence": ["第5段跳跃"],
      "reader_impact": "情绪未充分铺垫",
      "observation_visibility": "moderate",
      "intent_alignment": "unclear"
    },
    {
      "dimension": "dialogue_dynamics",
      "dimension_name": "对话动态",
      "phenomenon": "对话信息密度高",
      "evidence": ["对话段落"],
      "reader_impact": "信息过载",
      "observation_visibility": "subtle",
      "intent_alignment": "aligned"
    }
  ],
  "overall_impression": "整体有潜力",
  "strengths": ["意象独特"]
}''';

/// 记录 messages 的 Fake LLM（断言 system 构造 + 注入错误）
class _RecordingLlmClient extends LlmClient {
  final String? fullResponse;
  final Exception? error;
  List<ChatMessage> capturedMessages = [];

  _RecordingLlmClient({this.fullResponse, this.error});

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    capturedMessages = messages;
    if (error != null) throw error!;
    callback(LlmStreamResponse(content: fullResponse ?? '', isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late EditorObservationRepository observationRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    observationRepo = EditorObservationRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  RealtimeObservationService buildService(LlmClient llmClient) {
    return RealtimeObservationService(
      llmClient: llmClient,
      sessionRepo: sessionRepo,
      editorObservationRepo: observationRepo,
    );
  }

  test('#1 observe 成功 → 返回结果 + observation 入库', () async {
    final llm = _RecordingLlmClient(
      fullResponse: '这是给用户的轻量反馈。\n[YS_EDITOR]\n$_validEditorJson\n[/YS_EDITOR]',
    );
    final service = buildService(llm);

    final result = await service.observe(sessionId: sessionId, text: '待观察文本');

    expect(result.displayContent, contains('这是给用户的轻量反馈'));
    expect(result.observation, isNotNull);
    expect(result.observation!.observations.length, 3);
    expect(result.messageId, isNotNull);

    // 入库可查（R1：总是入库）
    final stored = await observationRepo.getObservationByMessage(
      result.messageId!,
    );
    expect(stored, isNotNull);
    expect(stored!.possibleIntent, '表达情绪');
    expect(stored.teacherTriggered, 0);
    expect(stored.pronouncedCount, 1); // 1 条 pronounced
    expect(stored.againstCount, 1); // 1 条 against
  });

  test('#2 流式回调透传 + targetRef 字段入库', () async {
    final llm = _RecordingLlmClient(
      fullResponse: '反馈A\n反馈B\n[YS_EDITOR]\n$_validEditorJson\n[/YS_EDITOR]',
    );
    final service = buildService(llm);

    final deltas = <String>[];
    final result = await service.observe(
      sessionId: sessionId,
      text: '待观察文本',
      targetRefType: 'chapter',
      targetRefId: 'chapter-1',
      onStream: (d) => deltas.add(d),
    );

    // 流式回调收到标记前的自然语言，且不含 [YS_EDITOR] 块
    final streamed = deltas.join('');
    expect(streamed, contains('反馈A'));
    expect(streamed, contains('反馈B'));
    expect(streamed, isNot(contains('[YS_EDITOR]')));

    // targetRef 字段入库
    final stored = await observationRepo.getObservationByMessage(
      result.messageId!,
    );
    expect(stored!.targetRefType, 'chapter');
    expect(stored.targetRefId, 'chapter-1');
  });

  test('#3 LLM 失败 → observation=null，不抛出，不入库（兜底）', () async {
    final llm = _RecordingLlmClient(error: Exception('网络错误'));
    final service = buildService(llm);

    final result = await service.observe(sessionId: sessionId, text: '待观察文本');

    expect(result.observation, isNull);
    // 兜底文案写入会话历史（用户可见「生成编辑观察失败，请稍后重试」）
    expect(result.messageId, isNotNull);
    // 不抛出（已兜底），observation 未入库
    expect(await observationRepo.countObservations(sessionId), 0);
  });

  test('#4 轻量约束 system 消息已附加（轻 prompt 语义）', () async {
    final llm = _RecordingLlmClient(
      fullResponse: '反馈\n[YS_EDITOR]\n$_validEditorJson\n[/YS_EDITOR]',
    );
    final service = buildService(llm);

    await service.observe(sessionId: sessionId, text: '待观察文本');

    final systemContents = llm.capturedMessages
        .where((m) => m.role == 'system')
        .map((m) => m.content)
        .toList();
    // skill + 轻量约束，共 2 条 system
    expect(systemContents.length, 2);
    expect(systemContents.last, contains('轻量观察约束'));
    expect(systemContents.last, contains('一次只观察一个最值得提的点'));
  });
  test('#5 displayContent 为空但解析成功 → 可见摘要 + observation 入库', () async {
    // ADR-C85：DeepSeek 流式对 editor-observation 请求直接输出
    // [YS_EDITOR] JSON 块（marker 前无自然语言导语），displayContent 为空
    // 但 observation 解析成功。修复：生成可见摘要，保证用户有反馈且可入库。
    final llm = _RecordingLlmClient(
      fullResponse: '[YS_EDITOR]\n$_validEditorJson\n[/YS_EDITOR]',
    );
    final service = buildService(llm);

    final result = await service.observe(sessionId: sessionId, text: '待观察文本');

    expect(result.displayContent, isEmpty);
    expect(result.observation, isNotNull);
    // 摘要写入会话 → messageId 非空 → observation 可入库
    expect(result.messageId, isNotNull);
    final stored = await observationRepo.getObservationByMessage(
      result.messageId!,
    );
    expect(stored, isNotNull);
    expect(stored!.possibleIntent, '表达情绪');

    // 会话历史里出现可见摘要（用户能读到反馈）
    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages, isNotEmpty);
    expect(messages.last.content, contains('快速观察完成'));
    expect(messages.last.content, contains('人物能动性'));
  });
  test('#6 displayContent 为空 + observation 为空 → 明确失败提示（杜绝静默）', () async {
    // ADR-C85 兜底：LLM 输出纯 JSON 块但解析/校验失败时，displayContent
    // 与 observation 均为空——若不写消息，用户看到「正在快速观察…」后
    // 直接消失，没有任何反馈。修复：写明确失败提示。
    final llm = _RecordingLlmClient(
      fullResponse: '[YS_EDITOR]\n{\"bad\": json}\n[/YS_EDITOR]',
    );
    final service = buildService(llm);

    final result = await service.observe(sessionId: sessionId, text: '待观察文本');

    expect(result.displayContent, isEmpty);
    expect(result.observation, isNull);
    // 兜底消息已写入 → 用户有反馈
    expect(result.messageId, isNotNull);
    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages.last.content, contains('快速观察未生成有效结果'));
  });
}
