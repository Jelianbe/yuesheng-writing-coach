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
//   7. 用户取消（DioExceptionType.cancel）→ 原样上抛（不写兜底文案）
//
// 设计（ADR-C88）：callEditorStream 改非流式（chatCompletionWithMeta），
// FakeLlmClient 继承 LlmClient override chatCompletionWithMeta 返回完整串
// （含 finish_reason，供截断用例注入 'length'）。
// onStream 不再回调（非流式无增量），displayContent 断言走返回值。
//
// ADR-C88 观测增强：新增失败留痕用例——F1/F2/F4 落 error_logs 且 stage 可区分，
// F3（用户取消）不落。error_logs 走真实 ErrorLogRepository（in-memory drift）。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/services/editor_service.dart';
import 'package:writingcoach/services/error_handler.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_retry.dart';

/// Fake LLM 客户端：预设非流式响应（ADR-C88 非流式 + finish_reason 可注入）
class FakeLlmClient extends LlmClient {
  final String _fullResponse;
  final Exception? _error;
  final String? _finishReason;

  FakeLlmClient(
    this._fullResponse, {
    Exception? error,
    String? finishReason,
  }) : _error = error,
       _finishReason = finishReason;

  @override
  Future<ChatCompletionResult> chatCompletionWithMeta(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
    LlmRetryPolicy retryPolicy = LlmRetryPolicy.standard,
  }) async {
    if (_error != null) throw _error;
    return ChatCompletionResult(
      content: _fullResponse,
      finishReason: _finishReason,
    );
  }
}

/// 记录 messages 的 Fake LLM（用于断言 system 消息构造）
class RecordingLlmClient extends LlmClient {
  final String _fullResponse;
  List<ChatMessage> capturedMessages = [];

  RecordingLlmClient(this._fullResponse);

  @override
  Future<ChatCompletionResult> chatCompletionWithMeta(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
    LlmRetryPolicy retryPolicy = LlmRetryPolicy.standard,
  }) async {
    capturedMessages = messages;
    return ChatCompletionResult(content: _fullResponse, finishReason: 'stop');
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

/// 等待 captureError 的异步落库完成（内部 unawaited 写库，需轮询）。
Future<List<ErrorLogEntry>> waitForLogs(
  ErrorLogRepository repo,
  int minCount,
) async {
  for (var i = 0; i < 50; i++) {
    final logs = await repo.queryErrorLogs();
    if (logs.length >= minCount) return logs;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return repo.queryErrorLogs();
}

void main() {
  late AppDatabase db;
  late ErrorLogRepository errorLogRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    errorLogRepo = ErrorLogRepository(db);
    ErrorHandler.instance.resetForTesting();
    ErrorHandler.instance.attachRepository(errorLogRepo);
  });

  tearDown(() async {
    ErrorHandler.instance.resetForTesting();
    await db.close();
  });

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
      // ADR-C88 非流式：onStream 不再回调（无增量）
      expect(deltas, isEmpty);
      // [YS_EDITOR] 块不进入展示内容
      expect(result.displayContent, isNot(contains('[YS_EDITOR]')));
      expect(result.displayContent, isNot(contains('possible_intent')));
    });

    test('#2 无 [YS_EDITOR] 标记 → displayContent=原文，observation=null', () async {
      final raw = '纯文本回复，没有标记';
      final llm = FakeLlmClient(raw);

      final result = await callEditorStream(llm, '测试文本', (_) {});

      expect(result.observation, isNull);
      expect(result.displayContent, '纯文本回复，没有标记');
    });

    test('#3 [YS_EDITOR] 缺结束标记 → 抢救解析 + truncated=true（P1-1）', () async {
      // ADR-C88 观测增强（P1-1）：有头无尾不再直接判死，截取到末尾再解析。
      // 本例 JSON 本身完整（只是丢了 [/YS_EDITOR]），故 observation 抢救成功，
      // 但内容完整性不可确认 → 标 truncated=true 供上层上报。
      final raw = '反馈内容\n[YS_EDITOR]\n$kValidEditorJson';
      final llm = FakeLlmClient(raw);

      final result = await callEditorStream(llm, '测试文本', (_) {});

      expect(result.observation, isNotNull);
      expect(result.truncated, isTrue);
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

    test('#7 用户取消（DioExceptionType.cancel）→ 原样上抛，不写兜底文案', () async {
      // ADR-C88：取消不得被 catch (_) 吞成「审稿通过…失败」误导文案，
      // 必须原样上抛让调用方优雅复位。
      final llm = FakeLlmClient(
        '',
        error: DioException(
          requestOptions: RequestOptions(path: '/chat/completions'),
          type: DioExceptionType.cancel,
        ),
      );

      expect(
        () => callEditorStream(llm, '测试文本', (_) {}),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
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

  group('ADR-C88 观测增强：失败留痕与截断检测', () {
    test('#9 F1 API 失败 → error_logs stage=api（原静默）', () async {
      final llm = FakeLlmClient('', error: Exception('网络错误'));

      final result = await callEditorStream(llm, '测试文本', (_) {});

      expect(result.displayContent, '审稿通过，但生成编辑观察失败，请稍后重试');
      final logs = await waitForLogs(errorLogRepo, 1);
      expect(logs.length, 1);
      expect(logs.last.context?['stage'], 'api');
      expect(logs.last.context?['reason'], 'unexpected_error');
      expect(logs.last.context?['error'], contains('网络错误'));
    });

    test('#10 F2 取不出 observation → stage=parse + head160 归因', () async {
      final raw = '[YS_EDITOR]\n{"bad": json}\n[/YS_EDITOR]';

      await callEditorStream(FakeLlmClient(raw), '测试文本', (_) {});

      final logs = await waitForLogs(errorLogRepo, 1);
      expect(logs.last.context?['stage'], 'parse');
      expect(logs.last.context?['reason'], 'json_invalid');
      expect(logs.last.context?['contentLength'], raw.length);
      expect(logs.last.context?['head160'], contains('[YS_EDITOR]'));
    });

    test('#11 F4 硬限制拦截 → stage=hardlimit + violations', () async {
      final raw = '[YS_EDITOR]\n$kHardLimitFailJson\n[/YS_EDITOR]';

      await callEditorStream(FakeLlmClient(raw), '测试文本', (_) {});

      final logs = await waitForLogs(errorLogRepo, 1);
      expect(logs.last.context?['stage'], 'hardlimit');
      expect(logs.last.context?['reason'], 'verdict_words');
      expect(logs.last.category, 'validation');
      final violations = logs.last.context?['violations'] as List<dynamic>;
      expect(violations.first, contains('character_agency.phenomenon'));
    });

    test('#12 F3 用户取消 → 不落 error_logs（预期行为不污染）', () async {
      final llm = FakeLlmClient(
        '',
        error: DioException(
          requestOptions: RequestOptions(path: '/chat/completions'),
          type: DioExceptionType.cancel,
        ),
      );

      await expectLater(
        () => callEditorStream(llm, '测试文本', (_) {}),
        throwsA(isA<DioException>()),
      );
      // 留一点时间：若误接留痕，此处的轮询能抓到
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await errorLogRepo.queryErrorLogs(), isEmpty);
    });

    test('#13 截断（finish_reason=length + 缺结束标记）→ 与「没生成」区分', () async {
      // 尾部被 max_tokens 截断：JSON 缺右半段，抢救失败，但 truncated=true
      // 使 error_logs 能明确归因为「内容被截断」而非「模型没输出」。
      final cut = kValidEditorJson.substring(0, kValidEditorJson.length - 40);
      final llm = FakeLlmClient('[YS_EDITOR]\n$cut', finishReason: 'length');

      final result = await callEditorStream(llm, '测试文本', (_) {});

      expect(result.observation, isNull);
      expect(result.truncated, isTrue);
      final logs = await waitForLogs(errorLogRepo, 1);
      expect(logs.last.context?['stage'], 'parse');
      expect(logs.last.context?['truncated'], true);
      expect(logs.last.context?['finishReason'], 'length');
    });

    test('#14 缺结束标记但 JSON 完整 → 抢救成功 + 标 truncated_recovered', () async {
      final llm = FakeLlmClient('[YS_EDITOR]\n$kValidEditorJson');

      final result = await callEditorStream(llm, '测试文本', (_) {});

      expect(result.observation, isNotNull);
      expect(result.truncated, isTrue);
      final logs = await waitForLogs(errorLogRepo, 1);
      expect(logs.last.context?['reason'], 'truncated_recovered');
    });
  });
}
