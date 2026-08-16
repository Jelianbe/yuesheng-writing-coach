// ─────────────────────────────────────────────────────────────
// editor_service_test — callEditorStream 测试
//
// 覆盖路径：
//   1. 成功：display + [YS_EDITOR] JSON → displayContent + observation
//   2. 无 [YS_EDITOR] 标记 → displayContent=原文，observation=null
//   3. [YS_EDITOR] 缺结束标记 → displayContent，observation=null
//   4. schema 校验失败（observations < 3）→ displayContent，observation=null
//   5. 硬限制失败（phenomenon 含判决词）→ displayContent，observation=null
//   6. LLM 抛异常 → 兜底文案，observation=null
//   7. 流式跨 chunk 标记：[YS_ED 在一个 chunk，ITOR] 在下一个
//
// 设计：FakeLlmClient 继承 LlmClient override streamChat，
// 把完整字符串切成 chunks 模拟流式回调。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/editor_service.dart';
import 'package:writingcoach/services/llm_client.dart';

/// Fake LLM 客户端：预设 streamChat 响应
class FakeLlmClient extends LlmClient {
  final String _fullResponse;
  final Exception? _error;
  final int _chunkSize;

  /// [_chunkSize] 模拟流式分块大小，默认 10 字符/chunk
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

    // 把完整响应切成 chunks 模拟流式
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

/// 记录 messages 的 Fake LLM（用于断言 system 消息构造）
class RecordingLlmClient extends LlmClient {
  final String _fullResponse;
  List<ChatMessage> capturedMessages = [];

  RecordingLlmClient(this._fullResponse);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    capturedMessages = messages;
    callback(LlmStreamResponse(content: _fullResponse, isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// 合法 EditorResult JSON（3 条 observation）
const String kValidEditorJson = '''{
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

/// schema 失败 JSON（observations 只有 2 条，需要 >= 3）
const String kSchemaFailJson = '''{
  "possible_intent": "表达情绪",
  "intent_confidence": "moderate",
  "observations": [
    {
      "dimension": "character_agency",
      "dimension_name": "人物能动性",
      "phenomenon": "现象",
      "evidence": ["证据"],
      "reader_impact": "影响",
      "observation_visibility": "pronounced",
      "intent_alignment": "against"
    }
  ],
  "overall_impression": "整体印象",
  "strengths": ["优点"]
}''';

/// 硬限制失败 JSON（phenomenon 含判决词"应该"）
const String kHardLimitFailJson = '''{
  "possible_intent": "表达情绪",
  "intent_confidence": "moderate",
  "observations": [
    {
      "dimension": "character_agency",
      "dimension_name": "人物能动性",
      "phenomenon": "主角应该主动选择",
      "evidence": ["第3段"],
      "reader_impact": "读者难以代入",
      "observation_visibility": "pronounced",
      "intent_alignment": "against"
    },
    {
      "dimension": "pacing_control",
      "dimension_name": "节奏",
      "phenomenon": "节奏偏快",
      "evidence": ["第5段"],
      "reader_impact": "情绪未铺垫",
      "observation_visibility": "moderate",
      "intent_alignment": "unclear"
    },
    {
      "dimension": "dialogue_dynamics",
      "dimension_name": "对话",
      "phenomenon": "对话密度高",
      "evidence": ["对话段"],
      "reader_impact": "信息过载",
      "observation_visibility": "subtle",
      "intent_alignment": "aligned"
    }
  ],
  "overall_impression": "有潜力",
  "strengths": ["意象独特"]
}''';

void main() {
  group('callEditorStream', () {
    test('#1 成功：display + [YS_EDITOR] JSON', () async {
      final raw = '这是给用户的反馈。\n[YS_EDITOR]\n$kValidEditorJson\n[/YS_EDITOR]';
      final llm = FakeLlmClient(raw);

      final deltas = <String>[];
      final result = await callEditorStream(llm, '测试文本', (d) => deltas.add(d));

      expect(result.observation, isNotNull);
      expect(result.observation!.possibleIntent, '表达情绪');
      expect(result.observation!.observations.length, 3);
      // displayContent 应包含标记前的文本
      expect(result.displayContent, contains('这是给用户的反馈'));
      // onStream 应收到标记前的文本
      expect(deltas.join(''), contains('这是给用户的反馈'));
      // [YS_EDITOR] 块不应转发给 onStream
      expect(deltas.join(''), isNot(contains('[YS_EDITOR]')));
      expect(deltas.join(''), isNot(contains('possible_intent')));
    });

    test('#2 无 [YS_EDITOR] 标记 → displayContent=原文，observation=null', () async {
      final raw = '纯文本回复，没有标记';
      final llm = FakeLlmClient(raw);

      final result = await callEditorStream(llm, '测试文本', (_) {});

      expect(result.observation, isNull);
      expect(result.displayContent, '纯文本回复，没有标记');
    });

    test('#3 [YS_EDITOR] 缺结束标记 → displayContent，observation=null', () async {
      final raw = '反馈内容\n[YS_EDITOR]\n$kValidEditorJson';
      final llm = FakeLlmClient(raw);

      final result = await callEditorStream(llm, '测试文本', (_) {});

      expect(result.observation, isNull);
      expect(result.displayContent, contains('反馈内容'));
    });

    test('#4 schema 校验失败（observations < 3）→ observation=null', () async {
      final raw = '[YS_EDITOR]\n$kSchemaFailJson\n[/YS_EDITOR]';
      final llm = FakeLlmClient(raw);

      final result = await callEditorStream(llm, '测试文本', (_) {});

      expect(result.observation, isNull);
    });

    test('#5 硬限制失败（phenomenon 含判决词"应该"）→ observation=null', () async {
      final raw = '[YS_EDITOR]\n$kHardLimitFailJson\n[/YS_EDITOR]';
      final llm = FakeLlmClient(raw);

      final result = await callEditorStream(llm, '测试文本', (_) {});

      expect(result.observation, isNull);
    });

    test('#6 LLM 抛异常 → 兜底文案，observation=null', () async {
      final llm = FakeLlmClient('', error: Exception('网络错误'));

      final result = await callEditorStream(llm, '测试文本', (_) {});

      expect(result.observation, isNull);
      expect(result.displayContent, '审稿通过，但生成编辑观察失败，请稍后重试');
    });

    test('#7 流式跨 chunk 标记：标记被拆分到多个 chunk', () async {
      // 用很小的 chunkSize 强制 [YS_EDITOR] 被拆分到多个 chunk
      final raw = '反馈\n[YS_EDITOR]\n$kValidEditorJson\n[/YS_EDITOR]';
      final llm = FakeLlmClient(raw, chunkSize: 3);

      final deltas = <String>[];
      final result = await callEditorStream(llm, '测试文本', (d) => deltas.add(d));

      expect(result.observation, isNotNull);
      // 即使标记跨 chunk，也不应转发给 onStream
      final combined = deltas.join('');
      expect(combined, isNot(contains('[YS_EDITOR]')));
      expect(combined, isNot(contains('possible_intent')));
      expect(combined, contains('反馈'));
    });

    test('#8 extraSystemMessages → 追加到 system 消息（默认不影响既有调用）', () async {
      final raw = '反馈\n[YS_EDITOR]\n$kValidEditorJson\n[/YS_EDITOR]';
      final llm = RecordingLlmClient(raw);

      final extra = ChatMessage(role: 'system', content: '轻量约束消息');
      final result = await callEditorStream(
        llm,
        '测试文本',
        (_) {},
        extraSystemMessages: [extra],
      );

      expect(result.observation, isNotNull);
      final systemContents = llm.capturedMessages
          .where((m) => m.role == 'system')
          .map((m) => m.content)
          .toList();
      // skill + extra，共 2 条 system
      expect(systemContents.length, 2);
      expect(systemContents.last, '轻量约束消息');
    });
  });
}
