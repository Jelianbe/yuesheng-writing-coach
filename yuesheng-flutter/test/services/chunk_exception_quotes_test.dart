// ─────────────────────────────────────────────────────────────
// T-20261025-10 · 第四态 not_applicable 与例外指认 exception_quotes
// 报批稿 §6 Q1–Q6（Q7/Q8 在 Python 侧，见回执）
//
// 判据设计成**能变红**：
//   Q1 删掉示例行或字段说明段      ⇒ 红
//   Q2 merge 不透传 quotes         ⇒ 红（键缺失）
//   Q3 空 quotes 也带键            ⇒ 红（不应出现该键）
//   Q4 子串校验失效（引文被吞）    ⇒ 红（merge 不含引文）
//   Q5 校验过严（丢整条 note）     ⇒ 红（note 消失 / 无留痕句）
//   Q6 类型宽容退化（抛异常）      ⇒ 红（整块笔记为空）
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chunk_prompt.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 返回固定分片 JSON 的假 LLM；merge 段消息收集到 [mergeMessages]。
class _FakeLlmClient extends LlmClient {
  _FakeLlmClient(this.chunkJson);

  final String chunkJson;
  final List<List<ChatMessage>> chunkCalls = [];
  final List<ChatMessage> mergeMessages = [];

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) async {
    chunkCalls.add(messages);
    return chunkJson;
  }

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    mergeMessages.addAll(messages);
    callback(const LlmStreamResponse(content: '诊断完成', isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// > 4000 字触发分块；同一句反复出现 ⇒ 两个分片都含该串。
String _content() {
  const para = '她推开门，雨声灌进来。她把伞靠在墙角，水滴顺着伞骨往下淌。';
  return List.generate(130, (i) => '$para段$i').join('\n\n');
}

String _noteJson({required String quotes}) =>
    '{"notes":[{"syndromeId":"P003","description":"视角切换无过渡",'
    '"evidence":["她推开门，雨声灌进来。"],"severity":"L2",'
    '"exception_quotes":$quotes}]}';

Future<String> _mergePromptFor(String chunkJson) async {
  final fake = _FakeLlmClient(chunkJson);
  final result = await runProgressiveDiagnosis(
    content: _content(),
    title: '测试章',
    onContent: (_) {},
    llmClient: fake,
    teachingMode: TeachingMode.socratic,
  );
  expect(result, isNotNull, reason: '长文必须走分块链路，否则本用例测不到解析侧');
  return fake.mergeMessages.map((m) => m.content).join('\n');
}

void main() {
  group('Q1 协议：字段行 + 说明段进 kChunkSystemPrompt', () {
    test('Q1a 示例行与说明段都在', () {
      expect(kChunkSystemPrompt, contains('"exception_quotes": ['));
      expect(kChunkSystemPrompt, contains('exception_quotes 字段说明：'));
    });

    test('Q1b 三态字段说明原样未动（本次只增不改）', () {
      expect(kChunkSystemPrompt, contains('uncertain 字段说明：'));
      expect(kChunkSystemPrompt, contains('excluded 字段说明：'));
    });

    test('Q1c Q1 甲：runtime prompt 不得出现 not_applicable（只进评测协议）', () {
      expect(kChunkSystemPrompt, isNot(contains('not_applicable')));
    });
  });

  group('Q2 / Q3 merge 透传', () {
    test('Q2 非空引文 ⇒ merge 含键与逐字引文', () {
      final prompt = buildMergePrompt([
        const ChunkAnalysisResult(
          chunkIndex: 0,
          success: true,
          notes: [
            ChunkNote(
              syndromeId: 'P003',
              description: '视角切换无过渡',
              evidence: ['甲句'],
              severity: 'L2',
              exceptionQuotes: ['切换前一句', '切换后一句'],
            ),
          ],
        ),
      ]);
      expect(prompt, contains('"exception_quotes"'));
      expect(prompt, contains('切换前一句'));
      expect(prompt, contains('切换后一句'));
    });

    test('Q3 空引文 ⇒ merge 不带该键（省略与 [] 同义）', () {
      final prompt = buildMergePrompt([
        const ChunkAnalysisResult(
          chunkIndex: 0,
          success: true,
          notes: [
            ChunkNote(
              syndromeId: 'P003',
              description: '视角切换无过渡',
              evidence: ['甲句'],
              severity: 'L2',
            ),
          ],
        ),
      ]);
      expect(prompt, isNot(contains('exception_quotes')));
    });
  });

  group('Q4 / Q5 子串校验（成对）', () {
    test('Q4 引文在块内 ⇒ 保住引文并进 merge', () async {
      final prompt = await _mergePromptFor(
        _noteJson(quotes: '["她推开门，雨声灌进来。"]'),
      );
      expect(prompt, contains('"exception_quotes"'));
      expect(prompt, contains('她推开门，雨声灌进来。'));
      expect(prompt, isNot(contains('例外引文未在本片原文找到')));
    });

    test('Q5 引文不在块内 ⇒ note 仍在，只丢引文并留痕', () async {
      final prompt = await _mergePromptFor(_noteJson(quotes: '["这句根本不在原文里。"]'));
      // note 主体仍在（不是「这条没报」）
      expect(prompt, contains('P003'));
      expect(prompt, contains('视角切换无过渡'));
      // 引文被剔除 + 留痕
      expect(prompt, contains('例外引文未在本片原文找到，已剔除 1 条'));
      expect(prompt, isNot(contains('这句根本不在原文里。')));
      // 空集 ⇒ 不带键
      expect(prompt, isNot(contains('"exception_quotes"')));
    });
  });

  group('Q6 类型宽容（不抛异常、结果空集）', () {
    test('Q6a 字符串形态', () async {
      final prompt = await _mergePromptFor(_noteJson(quotes: '"她推开门，雨声灌进来。"'));
      expect(prompt, contains('P003'));
      expect(prompt, isNot(contains('"exception_quotes"')));
      expect(prompt, isNot(contains('例外引文未在本片原文找到')));
    });

    test('Q6b 混型数组 [1, null, "  "] ⇒ 空集', () async {
      final prompt = await _mergePromptFor(
        _noteJson(quotes: '[1, null, "  "]'),
      );
      expect(prompt, contains('P003'));
      expect(prompt, isNot(contains('"exception_quotes"')));
      expect(prompt, isNot(contains('例外引文未在本片原文找到')));
    });
  });
}
