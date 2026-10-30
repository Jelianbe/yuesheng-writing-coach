// ─────────────────────────────────────────────────────────────
// T-20261024-06 · merge 链 excluded 传播（形态甲）—— 判据 1/2/3 + 教学判据 1/2
//
// 落点（设计批 §6，全在 progressive_diagnosis.dart）：
//   ①1 _kChunkOutputFormat 分片模板加 excluded 字段说明
//   ①2 ChunkNote 加 excluded 字段（复用批 2 ParsedExclusion，缺省 const []）
//   ①3 _parseChunkNotes 反序列化 excluded（循 _parseUncertainFlag 先例）
//   ①4 _buildChunkNotesBlocks notes map 加 excluded 透传
//   ①5 _kMergeOutputRequirement 顶层加 excluded 说明（透传不重判）
//
// 观测面（批 2 纪律：私有函数不直测）：
//   序列化面 = buildMergePrompt 公开产物（先例 progressive_diagnosis_test.dart #W-3）
//   反序列化面 = runProgressiveDiagnosis 端到端（先例 #8-1 抓 streamMessages.last）
//
// 假绿纪律（flutter-widget-test-false-green）：
//   期望侧钉死字面量理由（不调生产 helper 生成）；阳性对照用 contains/RegExp 实测命中；
//   用例数静态对账（本文件 8 例）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 分片级样本长正文（15 段 × 350 字 ≈ 5265 字 > 4000 触发分块，
/// 对位 progressive_diagnosis_test.dart makeLongContent 先例）。
String makeLongContent() {
  final paragraphs = <String>[];
  for (int i = 0; i < 15; i++) {
    paragraphs.add('${'X' * 350}段落$i');
  }
  return paragraphs.join('\n\n');
}

/// 简版 Fake LLM（照抄既有 _FakeLlmClient 形态，只留本批所需：
/// 分片 chatCompletion 队列响应 + merge streamMessages 抓取）。
class _FakeLlm extends LlmClient {
  final List<String> _chunkResponses;
  int _chunkCall = 0;
  final List<List<ChatMessage>> streamMessages = [];

  _FakeLlm(List<String> chunkResponses) : _chunkResponses = chunkResponses;

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) async {
    if (_chunkCall >= _chunkResponses.length) return '{"notes":[]}';
    return _chunkResponses[_chunkCall++];
  }

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    streamMessages.add(messages);
    callback(const LlmStreamResponse(content: '诊断完成。', isDone: true));
  }
}

void main() {
  group(
    '判据 1 · ChunkNote excluded 序列化进 merge prompt（buildMergePrompt 公开面）',
    () {
      test('T1-1 正向：带 excluded → prompt 含 excluded 键且两条理由逐字保留（教学判据 1）', () {
        final prompt = buildMergePrompt([
          const ChunkAnalysisResult(
            chunkIndex: 0,
            notes: [
              ChunkNote(
                syndromeId: 'P001',
                description: '情绪标签化',
                evidence: ['她很愤怒'],
                severity: 'L1',
                excluded: [
                  ParsedExclusion(syndromeId: 'P017', reason: '与主线视角问题相邻，证据不足'),
                  ParsedExclusion(syndromeId: 'P021', reason: '此窗口内未触发'),
                ],
              ),
            ],
            success: true,
          ),
        ], diagnosisContext: '');

        // 阳性对照：notes 块整体在（防 buildMergePrompt 被改成空转后子串空过）。
        expect(prompt, contains('"syndromeId": "P001"'));
        // excluded 键必须进 notes JSON（①4 透传）。
        expect(
          prompt,
          contains('"excluded"'),
          reason: 'ChunkNote.excluded 必须序列化进 merge prompt（透传不丢主判据）',
        );
        // 理由保留逐字一致（教学判据 1：≤1 次点击读到原始理由，不截断不改写）。
        expect(
          prompt,
          contains('与主线视角问题相邻，证据不足'),
          reason: 'excluded reason 必须逐字进 merge prompt（理由≠ID 替身）',
        );
        expect(
          prompt,
          contains('此窗口内未触发'),
          reason: '第二条 excluded reason 必须逐字保留',
        );
        expect(prompt, contains('P017'));
        expect(prompt, contains('P021'));
      });

      test('T1-2 缺省：excluded 缺省 → 显式落空数组（循 uncertain 先例，区分「没标」与「标了空」）', () {
        // 先例 #W-4：uncertain 缺省 false 也须显式落键——merge 侧要能区分
        //「没标」与「标了不成立」；excluded 循同例（设计批 §6#3 循 uncertain 先例）。
        final prompt = buildMergePrompt([
          const ChunkAnalysisResult(
            chunkIndex: 0,
            notes: [
              ChunkNote(
                syndromeId: 'P001',
                description: '情绪标签化',
                evidence: ['她很愤怒'],
                severity: 'L1',
              ),
            ],
            success: true,
          ),
        ], diagnosisContext: '');
        expect(
          RegExp(r'"excluded"\s*:\s*\[\]').hasMatch(prompt),
          isTrue,
          reason: '缺省 excluded 必须显式落空数组（不省略键，同 uncertain 先例）',
        );
      });
    },
  );

  group('判据 2 · 传播不丢（端到端 runProgressiveDiagnosis：分片解析 → merge prompt）', () {
    test('T2-1 分片 JSON 带 excluded → merge prompt 逐字携带（传播主判据）', () async {
      // 分片模型输出（notes 报出字段 camelCase 经 _parseChunkNotes；
      // excluded 元素 snake_case 经 _parseChunkExcludedList :1337-1348 读 syndrome_id）。
      const chunkNotes =
          '{"notes":[{"syndromeId":"P001","description":"情绪标签化",'
          '"evidence":["她很愤怒"],"severity":"L1",'
          '"excluded":[{"syndrome_id":"P017","reason":"分片窗口排除理由"}]}]}';
      final fake = _FakeLlm(const [chunkNotes, '{"notes":[]}']);
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '传播测试',
        llmClient: fake,
        onContent: (_) {},
      );
      expect(result, isNotNull);
      // 阳性对照：merge 阶段确实发起（streamMessages 非空）。
      expect(fake.streamMessages, isNotEmpty);
      final mergeText = fake.streamMessages.last
          .map((m) => m.content)
          .join('\n');
      // 传播不丢：分片排除理由逐字到达 merge prompt（删 ①3 解析或 ①4 序列化即红）。
      expect(
        mergeText,
        contains('分片窗口排除理由'),
        reason: '分片 excluded 理由必须逐字透传到 merge prompt（不丢主判据）',
      );
      expect(mergeText, contains('P017'));
    });

    test('T2-2 反序列化容错：excluded 脏值不崩、干净值仍透传（安全读先例）', () async {
      const chunkNotes =
          '{"notes":[{"syndromeId":"P001","description":"情绪标签化",'
          '"evidence":["她很愤怒"],"severity":"L1",'
          '"excluded":"不是数组",'
          '"extra":[{"syndromeId":"P021","reason":"脏夹塞"}]}]}';
      final fake = _FakeLlm(const [chunkNotes, '{"notes":[]}']);
      final result = await runProgressiveDiagnosis(
        content: makeLongContent(),
        title: '容错测试',
        llmClient: fake,
        onContent: (_) {},
      );
      expect(result, isNotNull, reason: 'excluded 脏值（字符串/缺键）不得让整块解析崩（安全读）');
      final mergeText = fake.streamMessages.last
          .map((m) => m.content)
          .join('\n');
      // 报出 note 仍在（容错不连带吞掉既有字段）。
      expect(mergeText, contains('P001'));
    });
  });

  group('判据 3 · 模板面（R-027 两处 prompt 说明段）', () {
    test('T3-1 kChunkSystemPrompt：分片输出协议含 excluded 字段说明段', () {
      // ①1 落点：分片模板教模型产出 excluded（对齐 uncertain 字段说明先例）。
      expect(
        kChunkSystemPrompt,
        contains('excluded'),
        reason: '分片输出协议必须含 excluded 字段说明（①1 R-027 面）',
      );
    });

    test('T3-2 merge 输出要求：透传各片排除记录、不重判的说明存在', () {
      // ①5 落点：merge 输出要求说明 excluded 为可选透传记录（不重判 = 不伪造）。
      final prompt = buildMergePrompt([
        const ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P001',
              description: 'd',
              evidence: ['e'],
              severity: 'L1',
            ),
          ],
          success: true,
        ),
      ], diagnosisContext: '');
      expect(
        prompt,
        contains('excluded'),
        reason: 'merge 输出要求必须含 excluded 说明段（①5 R-027 面）',
      );
    });
  });

  group('教学判据 2 · 轮次绑定不串轮（双片样本）', () {
    test('T4 轮1排 P017/R1、轮2排 P021/R2 → 理由各挂对应分片块，不串轮', () {
      final prompt = buildMergePrompt([
        const ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P001',
              description: 'd1',
              evidence: ['e1'],
              severity: 'L1',
              excluded: [
                ParsedExclusion(syndromeId: 'P017', reason: '轮一理由：本段节奏未展开'),
              ],
            ),
          ],
          success: true,
        ),
        const ChunkAnalysisResult(
          chunkIndex: 1,
          notes: [
            ChunkNote(
              syndromeId: 'P002',
              description: 'd2',
              evidence: ['e2'],
              severity: 'L2',
              excluded: [
                ParsedExclusion(syndromeId: 'P021', reason: '轮二理由：跨章关系未成立'),
              ],
            ),
          ],
          success: true,
        ),
      ], diagnosisContext: '');

      // 阳性对照：两片 header 都在（位置断言的前提）。
      expect(prompt, contains('分片 1'));
      expect(prompt, contains('分片 2'));
      // 轮一理由只落在分片 1 块内（分片 1 之后、分片 2 之前）。
      final idx1 = prompt.indexOf('分片 1');
      final idx2 = prompt.indexOf('分片 2');
      final idxR1 = prompt.indexOf('轮一理由：本段节奏未展开');
      final idxR2 = prompt.indexOf('轮二理由：跨章关系未成立');
      expect(idx1, lessThan(idx2), reason: '两片块顺序应先 1 后 2');
      expect(idxR1, greaterThan(idx1), reason: '轮一理由必须挂在分片 1 块内');
      expect(idxR1, lessThan(idx2), reason: '轮一理由不得串到分片 2 块（轮次绑定不串轮）');
      expect(idxR2, greaterThan(idx2), reason: '轮二理由必须挂在分片 2 块内（不串轮、不张冠李戴）');
    });
  });

  group('判据 3 · merge 输出 excluded 透传（parseDiagnosis 公开面，批 2 已支持）', () {
    test('T5 merge 输出 JSON 带 excluded → ParsedDiagnosis.excluded 逐条读出', () {
      // merge 输出经 diagnosis_flow_handler:382 parseDiagnosis（设计批 §2.1#3）。
      // 批 2 parser 已安全读，本条锚 merge 形态 fixture（形态照批 2
      // diagnosis_excluded_parser_test.dart:46：[YS_DIAGNOSIS]\n jsonEncode \n[/YS_DIAGNOSIS]）。
      final map = <String, dynamic>{
        'syndromes': [
          {
            'syndrome_id': 'P004',
            'name': '情绪标签化',
            'severity': 'L1',
            'evidence': ['x'],
            'explanation': 'y',
          },
        ],
        'suggested_actions': ['试一段对话'],
        'confidence': 0.8,
        'excluded': [
          {'syndrome_id': 'P017', 'reason': '合并视图保留片1排除记录'},
        ],
      };
      final raw = '[YS_DIAGNOSIS]\n${jsonEncode(map)}\n[/YS_DIAGNOSIS]';
      final parsed = parseDiagnosis(raw);
      expect(parsed.diagnosis, isNotNull);
      final excluded = parsed.diagnosis!.excluded;
      expect(
        excluded,
        hasLength(1),
        reason: 'merge 输出 excluded 必须 1:1 透传为 ParsedDiagnosis.excluded',
      );
      expect(excluded.single.syndromeId, 'P017');
      expect(
        excluded.single.reason,
        '合并视图保留片1排除记录',
        reason: 'merge 理由逐字保留（教学判据 1 的输出侧）',
      );
    });
  });
}
