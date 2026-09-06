// ─────────────────────────────────────────────────────────────
// ProgressiveDiagnosis 单测 — 长文本分块诊断
//
// 对应 RN progressive-diagnosis.ts
// 覆盖：
//   #1 splitContent 短文本不分块（<= CHUNK_SIZE 返单块）
//   #2 splitContent 按段落拆分，块间含 overlap 回溯
//   #3 splitContent 末块过小时与前块合并
//   #4 buildMergePrompt 注入 SYNDROME_DIAGNOSIS_SKILL 引用 + 跨片段合并规则
//   #5 runProgressiveDiagnosis 短文本走 null（走单次链路）
//   #8 ADR-C80 空内容分级降级（换参重试 / 仍空显式失败 / 合法零症候不误伤）
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';

/// Fake LLM 客户端：预设 chatCompletion 和 streamChat 响应
class _FakeLlmClient extends LlmClient {
  final String _chatResponse;
  final String _streamResponse;

  /// 逐次返回的 chatCompletion 响应队列（空则恒返 [_chatResponse]）；
  /// 同时记录每次调用的透传参数，供 ADR-C80 兜底参数断言用。
  final List<String> _chatResponses;
  final List<ChatMessage> chatMessages = [];
  final List<int?> chatMaxTokens = [];
  final List<Map<String, dynamic>?> chatExtraBodies = [];
  final Object? _chatError;

  /// streamChat 收到的 messages（merge 阶段），供端到端断言 notes 进入合并。
  final List<List<ChatMessage>> streamMessages = [];

  _FakeLlmClient({
    String chatResponse = '{"notes":[]}',
    String streamResponse = '',
    List<String>? chatResponses,
    Object? chatError,
  }) : _chatResponse = chatResponse,
       _streamResponse = streamResponse,
       _chatResponses = chatResponses ?? const [],
       _chatError = chatError;

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
  }) async {
    chatMessages.addAll(messages);
    chatMaxTokens.add(maxTokens);
    chatExtraBodies.add(extraBody);
    if (_chatError != null) throw _chatError!;
    if (_chatResponses.isEmpty) return _chatResponse;
    return _chatResponses.length == 1
        ? _chatResponses.first
        : _chatResponses.removeAt(0);
  }

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    streamMessages.add(messages);
    if (_streamResponse.isEmpty) {
      callback(const LlmStreamResponse(content: '', isDone: true));
      return;
    }
    callback(LlmStreamResponse(content: _streamResponse, isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  group('splitContent', () {
    test('#1 短文本不分块（<= CHUNK_SIZE 返回单块）', () {
      final short = '这是一段短文本，长度不足以触发分块。';
      final chunks = splitContent(short);
      expect(chunks.length, 1);
      expect(chunks[0], short);
    });

    test('#2 按段落拆分，块间含 overlap 回溯', () {
      // 用短但多的段落构造：每个段落 350 字符，累计 >3000
      final paragraphs = <String>[];
      for (int i = 0; i < 12; i++) {
        // 每段 350 字符：'XXXX...' + 结尾 marker
        final marker = 'P${i}MARK';
        final fill = 'X' * (350 - marker.length);
        paragraphs.add('$fill$marker');
      }
      final content = paragraphs.join('\n\n');
      final chunks = splitContent(content);

      // 应至少 2 块
      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(chunks.first.length, lessThan(content.length));

      // overlap 校验：第一块的最后几个 marker 应该在第二块开头出现
      // 取第一块末尾所有 marker 的匹配
      final markersInChunk1 = RegExp(
        r'P\d+MARK',
      ).allMatches(chunks.first).map((m) => m.group(0)!).toList();
      if (markersInChunk1.isNotEmpty) {
        final lastMarkers = markersInChunk1
            .skip(markersInChunk1.length - 3)
            .toList(); // 最后 3 个 marker
        final chunk2Start = chunks[1].substring(0, 600);
        final overlapHit = lastMarkers.any((m) => chunk2Start.contains(m));
        // CHUNK_OVERLAP=200，每个 marker(PiMARK)=6 字符，fill=344 字符，每段 350。
        // 从末尾段起向前，每段 352（含 '\n\n'）字符，直到长度 ≥ 200。
        // 约等于回溯 1 段就够 200 个字符 overlap，所以至少 1 个 marker 应该出现。
        expect(
          overlapHit,
          isTrue,
          reason:
              'chunk1 末尾 marker 至少有一个在 chunk2 开头 ${chunk2Start.length} 字符内出现（保证跨块上下文连续）',
        );
      }
    });

    test('#3 末块过小时与前块合并（MIN_LAST_CHUNK=500）', () {
      // 构造刚好触发切块的短内容：前 9 段 340 字 ≈ 3060（含分隔符共 ~3078）> SIZE 3000
      // 然后追加第 10 段只有 40 字 < MIN_LAST_CHUNK=500，应该被合并回末块
      final paragraphs = <String>[];
      for (int i = 0; i < 9; i++) {
        paragraphs.add('Y' * 340 + 'S${i}END'); // 346 字符 / 段
      }
      // 第 10 段：只有 <500 字符，末块如果只有它应触发合并
      final tail = '短尾段落T，长度约 40 个字符用来触发合并';
      paragraphs.add(tail);
      final content = paragraphs.join('\n\n');
      final chunks = splitContent(content);

      // 最后一块必须包含 tail
      expect(chunks.last, contains('短尾段落T'));
      // 末块长度不应小于 MIN_LAST_CHUNK（否则就已被正确合并到前一块，此时 chunks 数 < 段落数-0
      // 预期：要么 chunks.length=1（全部合并），要么 chunks.last >=500（已合并或单块够长）
      if (chunks.length > 1) {
        expect(
          chunks.last.length,
          greaterThanOrEqualTo(500),
          reason: '若 chunks>=2，末块 >=500（MIN_LAST_CHUNK），说明 tail 已正确合并到前一块',
        );
      }
    });

    test('#4 空字符串返回单块', () {
      expect(splitContent(''), ['']);
    });

    test('#5 长度恰等于 kDiagnosisChunkSize → 单块（<= 边界）', () {
      // 摸底判据：`content.length <= SIZE` 的 `=` 侧此前无锚
      // （#1 用例名写 "<=" 但文本远短于阈值）。
      // 注：单段 > SIZE 的超长文本存在死循环缺陷（批次 H 侦察实锤，
      // 已登记待办），本用例只锚 `=` 边界，不触达该路径。
      final exact = 'X' * kDiagnosisChunkSize; // 3000，无 \n\n
      final chunks = splitContent(exact);
      expect(chunks, hasLength(1));
      expect(chunks.single, exact);
    });

    test('#6 单段超长（>= SIZE 且无 \\n\\n）不挂死，整段成块', () {
      // 死循环判据（ADR-C73 §2）：批次 H 实锤，单段 ≥3000 + 总长 >3000
      // 会让 while(startIndex < paragraphs.length) 永真（endIndex=startIndex
      // → overlapStart ≤ startIndex → startIndex 不变）。
      // 修复后：首段即超阈值时强制 endIndex = startIndex + 1，整段成块。
      // 用例必须秒过（>60s 即变异命中，挂死型拦截由 _verify_batch_h_coverage
      // 兜底）。
      final longSingle = 'X' * 4000; // 单段 4000 字符，无段落边界
      final chunks = splitContent(longSingle);
      expect(chunks, isNotEmpty);
      expect(chunks.single, longSingle); // 整段成块
    });

    test('#7 字符串中间夹杂 \\n\\n 但首段即 ≥ SIZE → 首段成块 + 后续正常切', () {
      // 边界组合：首段超长触发修复路径，第二段短且合并到末块。
      // 验证修复不影响后续段落的常规分块。
      final first = 'A' * 4000; // 单段超长
      final tail1 = 'B' * 350 + 'T1END'; // 短段落
      final tail2 = 'C' * 350 + 'T2END'; // 短段落
      final content = '$first\n\n$tail1\n\n$tail2';
      final chunks = splitContent(content);
      // 至少 2 块：第一块含首段（整段或部分），后续按段落合并
      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(chunks.first, contains(first)); // 首段必在前块
    });
  });

  group('buildMergePrompt', () {
    test('#4-1 注入 SYNDROME_DIAGNOSIS_SKILL 引用 + 跨片段合并规则', () {
      final chunkResults = <ChunkAnalysisResult>[
        ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P003',
              description: '情绪标签化出现在开头',
              evidence: ['她非常愤怒'],
              severity: 'L1',
            ),
          ],
          success: true,
        ),
        ChunkAnalysisResult(
          chunkIndex: 1,
          notes: [
            ChunkNote(
              syndromeId: 'P003',
              description: '情绪标签化出现在结尾',
              evidence: ['他很激动'],
              severity: 'L2',
            ),
          ],
          success: true,
        ),
      ];
      final prompt = buildMergePrompt(chunkResults, diagnosisContext: '');

      // 必含 SKILL 锚点（对齐 RN merge prompt 顶部 # SKILL: 症候诊断手册）
      expect(prompt, contains('症候诊断手册'));
      // 必含跨片段合并规则
      expect(prompt, contains('同一个症候在不同分片中出现的信号'));
      expect(prompt, contains('严重度取最高'));
      expect(prompt, contains('不限制输出问题数量'));
      expect(prompt, contains('[YS_DIAGNOSIS]'));
      expect(prompt, contains('[/YS_DIAGNOSIS]'));
      // 两个分片的分析结果都包含在 prompt 里
      expect(prompt, contains('分片 1'));
      expect(prompt, contains('分片 2'));
      expect(prompt, contains('P003'));
    });

    test('#4-2 注入前次诊断上下文（diagnosisContext 非空时出现在 prompt 顶部）', () {
      final chunkResults = <ChunkAnalysisResult>[
        ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P004',
              description: '',
              evidence: [],
              severity: 'L1',
            ),
          ],
          success: true,
        ),
      ];
      const ctx = '## 前次诊断上下文\n\n- P003 情绪标签化（当前严重度: L2）';
      final prompt = buildMergePrompt(chunkResults, diagnosisContext: ctx);

      // 上下文应出现在 SKILL 锚点之前
      final idxCtx = prompt.indexOf('前次诊断上下文');
      final idxSkill = prompt.indexOf('症候诊断手册');
      expect(idxCtx, lessThan(idxSkill), reason: '诊断上下文应位于 SKILL 之前');
      expect(prompt, contains('P003 情绪标签化'));
    });
  });

  group('runProgressiveDiagnosis', () {
    test('#5 短文本（<= THRESHOLD=4000）走 null（走单次链路）', () async {
      const short = '这是一段不足 4000 字的文本，应该直接返回 null，由外部走单次诊断。';
      final result = await runProgressiveDiagnosis(
        content: short,
        title: '短文本',
        llmClient: _FakeLlmClient(),
        onContent: (_) {},
      );
      expect(result, isNull);
    });

    test('#6 长文本（> THRESHOLD=4000）走分块链路 → 返回 ProgressiveResult', () async {
      // 构造 > 4000 字的长文本
      final paragraphs = <String>[];
      for (int i = 0; i < 15; i++) {
        paragraphs.add('X' * 350 + '段落$i');
      }
      final content = paragraphs.join('\n\n');

      final streamResponse =
          '诊断完成。[YS_DIAGNOSIS]{"syndromes":[],"suggested_actions":[],"confidence":0.8}[/YS_DIAGNOSIS]';
      var receivedContent = '';

      final result = await runProgressiveDiagnosis(
        content: content,
        title: '长文本测试',
        llmClient: _FakeLlmClient(streamResponse: streamResponse),
        onContent: (delta) {
          receivedContent += delta;
        },
      );

      expect(result, isNotNull);
      expect(result!.chunkCount, greaterThanOrEqualTo(2));
      expect(result.failedChunks, 0);
      expect(result.fullContent, isNotEmpty);
      expect(receivedContent, isNotEmpty);
      expect(result.fullContent, contains('[YS_DIAGNOSIS]'));
    });
  });

  group('runProgressiveDiagnosis · ADR-C80 空内容分级降级', () {
    // >4000 字触发分块（与 #6 同款构造，切成 2 块）
    String makeLongContent() {
      final paragraphs = <String>[];
      for (int i = 0; i < 15; i++) {
        paragraphs.add('X' * 350 + '段落$i');
      }
      return paragraphs.join('\n\n');
    }

    const validNotes =
        '{"notes":[{"syndromeId":"P003","description":"情绪标签化","evidence":["她很愤怒"],"severity":"L1"}]}';

    test('#8-1 尝试 1 空 → 换兜底参数重试一次（消息不变）→ 救回', () async {
      final fake = _FakeLlmClient(chatResponses: ['', validNotes]);
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '降级测试',
        llmClient: fake,
        onContent: (_) {},
      );

      expect(result, isNotNull);
      expect(result!.failedChunks, 0);

      // 2 块：chunk0 两次调用（尝试 1 + 兜底），chunk1 队列耗尽走默认响应一次
      expect(fake.chatMaxTokens.length, 3);
      // 尝试 1：不传覆盖参数（应用现参数原样）；尝试 2：兜底参数
      expect(fake.chatMaxTokens[0], isNull);
      expect(fake.chatMaxTokens[1], LlmConfig.chunkAnalysisFallbackMaxTokens);
      expect(LlmConfig.chunkAnalysisFallbackMaxTokens, 8192);
      expect(fake.chatExtraBodies[0], isNull);
      expect(fake.chatExtraBodies[1], LlmConfig.chunkAnalysisFallbackExtraBody);
      expect(fake.chatExtraBodies[1]!['thinking'], {'type': 'disabled'});

      // 重试是换参数，不是换消息：chunk0 两次调用的 messages 逐条一致
      expect(fake.chatMessages.length, 6);
      for (var i = 0; i < 2; i++) {
        expect(fake.chatMessages[i].role, fake.chatMessages[i + 2].role);
        expect(fake.chatMessages[i].content, fake.chatMessages[i + 2].content);
      }

      // 救回的 notes 真正进入 merge 阶段（端到端：P003 出现在合并 prompt）
      expect(fake.streamMessages, hasLength(1));
      expect(
        fake.streamMessages.last.map((m) => m.content).join('\n'),
        contains('P003'),
      );
    });

    test('#8-2 重试后仍空 → 显式失败（empty_content），不再静默计成功', () async {
      final fake = _FakeLlmClient(chatResponse: ''); // 所有调用都返回空
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '降级测试',
        llmClient: fake,
        onContent: (_) {},
      );

      expect(result, isNotNull);
      expect(result!.failedChunks, result!.chunkCount);
      // 每块两次调用（尝试 1 + 兜底重试）
      expect(fake.chatMaxTokens.length, result!.chunkCount * 2);
      for (var i = 0; i < fake.chatMaxTokens.length; i += 2) {
        expect(fake.chatMaxTokens[i], isNull);
        expect(
          fake.chatMaxTokens[i + 1],
          LlmConfig.chunkAnalysisFallbackMaxTokens,
        );
      }
    });

    test('#8-3 合法零症候（非空 JSON、notes 空）不误伤为失败', () async {
      final fake = _FakeLlmClient(); // 默认 '{"notes":[]}'
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '降级测试',
        llmClient: fake,
        onContent: (_) {},
      );

      expect(result, isNotNull);
      expect(result!.failedChunks, 0);
      expect(fake.chatMaxTokens.length, result!.chunkCount); // 无重试
      expect(fake.chatMaxTokens[0], isNull);
      expect(fake.chatExtraBodies[0], isNull);
    });

    test('#8-4 调用异常 → 显式失败（exception）且计入 failedChunks', () async {
      final fake = _FakeLlmClient(chatError: Exception('网络不可用'));
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '降级测试',
        llmClient: fake,
        onContent: (_) {},
      );

      expect(result, isNotNull);
      expect(result!.failedChunks, result!.chunkCount);
      // 异常路径只调用一次（无兜底重试——异常不是空 content）
      expect(fake.chatMaxTokens.length, result!.chunkCount);
    });
  });
}
