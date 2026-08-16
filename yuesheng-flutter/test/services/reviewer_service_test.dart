// ─────────────────────────────────────────────────────────────
// reviewer_service_test — callReviewer 测试
//
// 覆盖路径：
//   1. 成功 + PASS verdict（matched_signals 必须为空）
//   2. 成功 + FAIL verdict（matched_signals 非空 + needs_editor=true）
//   3. LLM 抛异常 → 返回 null（严格降级）
//   4. 解析失败：raw 中无 [YS_REVIEW] 标记 → null
//   5. 解析失败：[YS_REVIEW] 缺结束标记 → null
//   6. 校验失败：PASS 但 matched_signals 非空 → null（一致性违反）
//   7. 校验失败：FAIL 但 matched_signals 为空 → null
//   8. 校验失败：schema 缺字段 → null
//
// 设计：FakeLlmClient 继承 LlmClient override chatCompletion，
// 不引入 mockito，不触发 FlutterSecureStorage 平台通道。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/reviewer_service.dart';
import 'package:writingcoach/services/reviewer_validator.dart';

/// Fake LLM 客户端：预设 chatCompletion 返回值
class FakeLlmClient extends LlmClient {
  final String _response;
  final Exception? _error;

  FakeLlmClient(this._response, [this._error]);

  @override
  Future<String> chatCompletion(List<ChatMessage> messages) async {
    if (_error != null) throw _error;
    return _response;
  }
}

void main() {
  group('callReviewer', () {
    test('#1 成功 + PASS verdict', () async {
      final raw =
          '审稿通过。\n[YS_REVIEW]\n'
          '{"genre":"都市","verdict":"PASS","matched_signals":[],'
          '"reason":"无明显信号","needs_editor":false}\n[/YS_REVIEW]';
      final llm = FakeLlmClient(raw);

      final result = await callReviewer(llm, '测试文本');

      expect(result, isNotNull);
      expect(result!.verdict, ReviewVerdict.pass);
      expect(result.matchedSignals, isEmpty);
      expect(result.needsEditor, false);
      expect(result.genre, '都市');
    });

    test('#2 成功 + FAIL verdict + needs_editor=true', () async {
      final raw =
          '[YS_REVIEW]\n'
          '{"genre":"悬疑","verdict":"FAIL",'
          '"matched_signals":["信号A","信号B"],'
          '"reason":"命中 2 个信号","needs_editor":true}\n[/YS_REVIEW]';
      final llm = FakeLlmClient(raw);

      final result = await callReviewer(llm, '测试文本');

      expect(result, isNotNull);
      expect(result!.verdict, ReviewVerdict.fail);
      expect(result.matchedSignals, ['信号A', '信号B']);
      expect(result.needsEditor, true);
    });

    test('#3 LLM 抛异常 → 返回 null（严格降级）', () async {
      final llm = FakeLlmClient('', Exception('网络错误'));

      final result = await callReviewer(llm, '测试文本');

      expect(result, isNull);
    });

    test('#4 解析失败：raw 中无 [YS_REVIEW] 标记 → null', () async {
      final llm = FakeLlmClient('这是一段没有标记的回复');

      final result = await callReviewer(llm, '测试文本');

      expect(result, isNull);
    });

    test('#5 解析失败：[YS_REVIEW] 缺结束标记 → null', () async {
      final raw = '[YS_REVIEW]\n{"verdict":"PASS","matched_signals":[]}';
      final llm = FakeLlmClient(raw);

      final result = await callReviewer(llm, '测试文本');

      expect(result, isNull);
    });

    test('#6 校验失败：PASS 但 matched_signals 非空 → null（一致性违反）', () async {
      final raw =
          '[YS_REVIEW]\n'
          '{"genre":"都市","verdict":"PASS",'
          '"matched_signals":["信号A"],"reason":"x","needs_editor":false}\n'
          '[/YS_REVIEW]';
      final llm = FakeLlmClient(raw);

      final result = await callReviewer(llm, '测试文本');

      expect(result, isNull);
    });

    test('#7 校验失败：FAIL 但 matched_signals 为空 → null', () async {
      final raw =
          '[YS_REVIEW]\n'
          '{"genre":"都市","verdict":"FAIL","matched_signals":[],'
          '"reason":"x","needs_editor":true}\n[/YS_REVIEW]';
      final llm = FakeLlmClient(raw);

      final result = await callReviewer(llm, '测试文本');

      expect(result, isNull);
    });

    test('#8 校验失败：schema 缺字段 → null', () async {
      final raw =
          '[YS_REVIEW]\n'
          '{"genre":"都市","verdict":"PASS"}\n[/YS_REVIEW]';
      final llm = FakeLlmClient(raw);

      final result = await callReviewer(llm, '测试文本');

      expect(result, isNull);
    });
  });
}
