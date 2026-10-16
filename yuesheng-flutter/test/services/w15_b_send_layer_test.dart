// ─────────────────────────────────────────────────────────────
// W-15-B 发送层施工护栏测试
//
// 对应任务书 docs/designs/2026-10-16-W15-B-发送层施工任务书.md：
//   B1（验收①）merge 预算预检三态：照发 / 降级 / 拒发
//     - 三态各至少一例；拒发时零 streamChat 调用；级序可指认；
//       拒发异常消息含估算值与上限
//   B2（验收③）pending_context：schema 往返 + 解析透传 + 收敛层排尾部
//     - 引导自标字段（prompt 指令在场），不得代码侧自动推断
//   B3（验收⑤）发送快照：载荷 merge_prompt 与实际发送体逐字节一致；
//     >64KB 截断（哈希 + 头尾 + 截断标记）；落库失败不炸主流程
//
// 基线回归（任务书 §五.2）：syndrome_count_scope / diagnosis_output_semantics
// / merge_convergence 既有测试不本文件重复；ADR-C67 全量落库语义由彼处守。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/llm_call_log_sink.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/merge_convergence.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';
import 'package:writingcoach/services/token_budget_guard.dart';
import 'package:writingcoach/types/teaching_types.dart';

// ── 夹具 ──

/// Fake LLM 客户端（形态对齐 progressive_diagnosis_test.dart 的同名 Fake；
/// 该类为库私有不能跨文件 import，故本地重声明——只保留本文件用到的面）。
class _FakeLlmClient extends LlmClient {
  final String _chatResponse;
  final String _streamResponse;
  final List<List<ChatMessage>> streamMessages = [];

  _FakeLlmClient({
    String chatResponse = '{"notes":[]}',
    String streamResponse = '',
  }) : _chatResponse = chatResponse,
       _streamResponse = streamResponse;

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) async {
    return _chatResponse;
  }

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
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

/// 空 prompt 骨架的估算值（guidance + 格式段 + 输出要求等基线）。
/// 各用例的 limit 以 `base + Δ` 表达，避免对基线字数做脆弱假设。
int _baseEstimate() {
  final p = buildMergePrompt(const []);
  return TokenBudgetGuard.estimate(p);
}

ChunkNote _note(String id, String severity, {int descLen = 80}) => ChunkNote(
  syndromeId: id,
  description: 'D' * descLen,
  evidence: ['E' * 40],
  severity: severity,
);

ChunkAnalysisResult _chunk(int index, List<ChunkNote> notes) =>
    ChunkAnalysisResult(chunkIndex: index, notes: notes, success: true);

/// 症候历史注入段（formatSyndromeHistory 的形态：标题 + 列表行 + 收尾）。
/// 非活跃行带 100 字符填充，保证「过滤前超限、过滤后回限」的数学余量。
String _historySection() {
  final filler = 'F' * 100;
  return [
    '### 症候历史追踪（跨轮次）',
    '以下为该学员近期诊断中相关症候的出现历史，供你在本次诊断时如实引用：',
    '- P001 情绪标签化：出现 3 次，当前 L2，趋势 稳定',
    '- P002 视角漂移：出现 2 次，当前 L1，趋势 好转，$filler',
    '- P003 叙事节奏拖沓：出现 1 次，当前 L1，趋势 稳定，$filler',
    '- P005 句式节奏单一：出现 2 次，当前 L1，趋势 稳定，$filler',
    '可引用形式：「该症候已是第 N 次出现」——仅当历史确实支持时使用。',
  ].join('\n');
}

void main() {
  // ───────────────────────────────────────────────
  // 回归 · splitContent 死循环修复（W-15-B 批实证的既有缺陷）
  // ───────────────────────────────────────────────
  group('回归 · splitContent overlap 回溯死循环（OOM 实证）', () {
    test('单段 1499–2997 字符 ⇒ 旧实现死循环，现正常终止且全量覆盖', () {
      final paragraph = '正文。' * 750; // 2250 字符 ⇒ pLen×2 ≥ SIZE 的恰一段成块
      final content = List.filled(44, paragraph).join('\n\n');
      final chunks = splitContent(content);
      expect(chunks, isNotEmpty);
      // 终止性已由本行执行到证明；内容无重复、无丢失
      final rejoined = chunks.map((c) => c.length).reduce((a, b) => a + b);
      expect(rejoined, lessThanOrEqualTo(content.length + chunks.length * 4));
      expect(chunks.first, paragraph);
    });

    test('回溯窗口内前文段落合计不足 OVERLAP ⇒ 同样必须终止', () {
      final big = '长' * 2500;
      final tiny = '短';
      // 大段（>1499 触发单段块）之间只夹一个 1 字符小段 ⇒ 回溯合计 < 200
      final content = List.filled(10, '$big\n\n$tiny').join('\n\n');
      final chunks = splitContent(content);
      expect(chunks, isNotEmpty);
      expect(chunks.first, startsWith(big), reason: '首块从大段开头起');
    });
  });

  // ───────────────────────────────────────────────
  // B1 · planMergeBudget 三态
  // ───────────────────────────────────────────────
  group('W-15-B B1 · planMergeBudget 三态', () {
    test('照发：估算 ≤ 上限 → 逐字节原样，无降级报告', () {
      final plan = planMergeBudget(
        chunkResults: const [],
        chunkCoverage: const [],
        diagnosisContext: '',
        structureProfile: '',
        disabledSyndromeIds: const {},
        teachingMode: TeachingMode.socratic,
      );
      expect(plan.reports, isEmpty);
      expect(plan.structureProfile, '');
      expect(plan.mergePrompt, buildMergePrompt(const []));
    });

    test('级序 a：仅画像可裁 → 置空 structureProfile，报告可指认', () {
      final base = _baseEstimate();
      final plan = planMergeBudget(
        chunkResults: const [],
        chunkCoverage: const [],
        diagnosisContext: '',
        structureProfile: 'P' * 6000,
        disabledSyndromeIds: const {},
        teachingMode: TeachingMode.socratic,
        limit: base + 100,
      );
      expect(plan.structureProfile, '');
      expect(plan.reports, hasLength(1));
      expect(plan.reports.single.droppedStages, [kMergeBudgetStageProfile]);
      // 注入 prompt 带 「\n\n---\n\n」 分隔（+7 字符），故用区间断言不逐字
      expect(plan.reports.single.totalBefore, greaterThan(base + 6000));
      expect(plan.estimatedTokens, lessThanOrEqualTo(base + 100));
    });

    test('级序 b：context 过滤到活跃集（非活跃行剔除、标题收尾保留）', () {
      final base = _baseEstimate();
      final plan = planMergeBudget(
        chunkResults: const [],
        chunkCoverage: const [],
        diagnosisContext: _historySection(),
        structureProfile: '',
        disabledSyndromeIds: const {},
        teachingMode: TeachingMode.socratic,
        activeSyndromeIds: const {'P001'},
        // 空骨架 + 全量历史段必超；过滤后剩标题 + P001 行 + 收尾 ≤ base+250
        limit: base + 250,
      );
      expect(plan.reports, hasLength(1));
      expect(plan.reports.single.droppedStages, [kMergeBudgetStageContext]);
      expect(plan.diagnosisContext, contains('- P001 情绪标签化'));
      expect(plan.diagnosisContext, isNot(contains('- P002 视角漂移')));
      expect(plan.diagnosisContext, contains('### 症候历史追踪（跨轮次）'));
      expect(plan.diagnosisContext, contains('可引用形式'));
    });

    test('级序 b：activeSyndromeIds 为空集 → 该级跳过（无判据不动刀）', () {
      final base = _baseEstimate();
      expect(
        () => planMergeBudget(
          chunkResults: const [],
          chunkCoverage: const [],
          diagnosisContext: _historySection(),
          structureProfile: '',
          disabledSyndromeIds: const {},
          teachingMode: TeachingMode.socratic,
          limit: base + 100,
        ),
        throwsA(isA<ProgressiveMergeOverBudget>()),
      );
    });

    test('级序 c：每块只留 severity 最高前 3 条（块内代码选）', () {
      final base = _baseEstimate();
      final results = [
        _chunk(0, [
          _note('P001', 'L1'),
          _note('P002', 'L3'),
          _note('P003', 'L1'),
          _note('P004', 'L3'),
          _note('P005', 'L1'),
          _note('P006', 'L3'),
        ]),
      ];
      final plan = planMergeBudget(
        chunkResults: results,
        chunkCoverage: const [],
        diagnosisContext: '',
        structureProfile: '',
        disabledSyndromeIds: const {},
        teachingMode: TeachingMode.socratic,
        limit: base + 800,
      );
      expect(plan.reports, hasLength(1));
      expect(plan.reports.single.droppedStages, [kMergeBudgetStageNotes]);
      // 保留的 3 条恰为 L3 三条（severity 最高；块内代码选择，非 LLM）
      final kept = plan.chunkResults.single.notes;
      expect(kept, hasLength(3));
      expect(kept.every((n) => n.severity == 'L3'), isTrue);
    });

    test('级序全穷尽仍超限 → 抛 ProgressiveMergeOverBudget（不发送）', () {
      final base = _baseEstimate();
      // 画像 5000 + 单条笔记：a 级裁掉画像后仍超（笔记块 > Δ200）
      expect(
        () => planMergeBudget(
          chunkResults: [
            _chunk(0, [_note('P001', 'L1')]),
          ],
          chunkCoverage: const [],
          diagnosisContext: '',
          structureProfile: 'P' * 5000,
          disabledSyndromeIds: const {},
          teachingMode: TeachingMode.socratic,
          limit: base + 200,
        ),
        throwsA(
          isA<ProgressiveMergeOverBudget>().having(
            (e) => e.maxBudget,
            'maxBudget',
            base + 200,
          ),
        ),
      );
    });

    test('拒发异常消息含估算值与上限（任务书 B1 测试④）', () {
      final base = _baseEstimate();
      final limit = base + 200;
      try {
        planMergeBudget(
          chunkResults: [
            _chunk(0, [_note('P001', 'L1')]),
          ],
          chunkCoverage: const [],
          diagnosisContext: '',
          structureProfile: 'P' * 5000,
          disabledSyndromeIds: const {},
          teachingMode: TeachingMode.socratic,
          limit: limit,
        );
        fail('应抛 ProgressiveMergeOverBudget');
      } on ProgressiveMergeOverBudget catch (e) {
        expect(e.userMessage, contains('本章过长，无法合并诊断'));
        expect(e.userMessage, contains('${e.estimatedTokens}'));
        expect(e.userMessage, contains('$limit'));
        expect(e.estimatedTokens, greaterThan(limit));
      }
    });

    test('上限缺省 = TokenEstimate.maxBudget（与 chat 单次链路同源，不手抄）', () {
      // 空输入在缺省上限下必照发 ⇒ 间接锁定缺省常量与 guard 同源
      final plan = planMergeBudget(
        chunkResults: const [],
        chunkCoverage: const [],
        diagnosisContext: '',
        structureProfile: '',
        disabledSyndromeIds: const {},
        teachingMode: TeachingMode.socratic,
      );
      expect(plan.estimatedTokens, lessThanOrEqualTo(TokenEstimate.maxBudget));
    });
  });

  // ───────────────────────────────────────────────
  // B1 · 公开入口端到端（拒发零 streamChat）
  // ───────────────────────────────────────────────
  group('W-15-B B1 · runProgressiveDiagnosis 端到端', () {
    // 每块返回一条带长 description 的笔记 ⇒ merge prompt 估算 > maxBudget
    // ⇒ 拒发；断言 streamChat 一次都没被调（「超限不得静默继续发送」）。
    test('拒发：抛 ProgressiveMergeOverBudget 且零 streamChat 调用', () async {
      final desc = '长' * 4000;
      final fake = _FakeLlmClient(
        chatResponse:
            '{"notes":[{"syndromeId":"P001","description":"$desc",'
            '"evidence":["证据"],"severity":"L1"}]}',
      );
      // 无 '\n\n' 的整段会成单块（原子性）⇒ 必须按段落构造多块
      final paragraph = '正文。' * 750; // ≈3000 字符/段
      final content = List.filled(44, paragraph).join('\n\n');
      expect(content.length, greaterThan(kDiagnosisChunkThreshold));
      await expectLater(
        runProgressiveDiagnosis(
          content: content,
          title: '预算拒发',
          onContent: (_) {},
          llmClient: fake,
        ),
        throwsA(isA<ProgressiveMergeOverBudget>()),
      );
      expect(fake.streamMessages, isEmpty, reason: '拒发 = 不发起合并调用');
    });

    test('照发 + 快照：载荷 merge_prompt 与实际发送体逐字节一致', () async {
      final fake = _FakeLlmClient(
        chatResponse:
            '{"notes":[{"syndromeId":"P001","description":"测试描述",'
            '"evidence":["证据一"],"severity":"L1"}]}',
        streamResponse: '诊断正文',
      );
      final captured = <Map<String, dynamic>>[];
      final content = '正文段落。' * 1500; // ≈7.5k 字符 ⇒ 触发分块、远低于上限
      final result = await runProgressiveDiagnosis(
        content: content,
        title: '快照对账',
        onContent: (_) {},
        llmClient: fake,
        snapshotWriter: captured.add,
      );
      expect(result, isNotNull);
      expect(captured, hasLength(1));
      final payload = captured.single;
      expect(payload['event'], 'llm_prompt_snapshot');
      expect(payload['purpose'], 'diagnosis_merge');
      final sentUserMessage = fake.streamMessages.single.last.content;
      expect(payload['merge_prompt'], sentUserMessage, reason: '逐字节一致');
      expect(payload['chunk_count'], splitContent(content).length);
      final report = payload['budget_report'] as Map<String, dynamic>;
      expect(report['levels'], isEmpty);
      expect(report['final_estimate'], sentUserMessage.length);
      expect(report['limit'], TokenEstimate.maxBudget);
    });

    test('快照写入方抛错 → 旁路纪律：主流程不受影响', () async {
      final fake = _FakeLlmClient(
        chatResponse: '{"notes":[]}',
        streamResponse: '诊断正文',
      );
      final content = '正文段落。' * 1500;
      final result = await runProgressiveDiagnosis(
        content: content,
        title: '旁路纪律',
        onContent: (_) {},
        llmClient: fake,
        snapshotWriter: (_) => throw StateError('落库失败'),
      );
      expect(result, isNotNull, reason: '落库失败静默，不改返回值');
    });
  });

  // ───────────────────────────────────────────────
  // B3 · 截断视图与发射通道
  // ───────────────────────────────────────────────
  group('W-15-B B3 · truncateMergePromptForSnapshot', () {
    test('≤64KB：原文原样、无哈希', () {
      final r = truncateMergePromptForSnapshot('abc正文');
      expect(r.truncated, isFalse);
      expect(r.stored, 'abc正文');
      expect(r.sha256Prefix, isNull);
      expect(r.totalBytes, utf8.encode('abc正文').length);
    });

    test('>64KB：截断标记 + 头尾 8KB + sha256 前 16 位', () {
      final prompt = '中' * 40000; // 120,000 字节 > 65,536
      final r = truncateMergePromptForSnapshot(prompt);
      expect(r.truncated, isTrue);
      expect(r.totalBytes, 120000);
      final expectSha = crypto.sha256.convert(utf8.encode(prompt)).toString();
      expect(r.sha256Prefix, expectSha.substring(0, 16));
      expect(r.stored, contains('截断'));
      expect(r.stored, contains(r.sha256Prefix));
      // 头尾各 8 KB（按字节切，UTF-8 每个中文字符 3 字节 ⇒ 完整字符约 2730 个）
      expect(r.stored.startsWith('中' * 2700), isTrue);
      expect(r.stored.endsWith('中' * 2700), isTrue);
    });
  });

  group('W-15-B B3 · emitMergePromptSnapshot 旁路纪律', () {
    test('缺省通道注入收集器透传；写入方抛错被吞', () {
      final captured = <Map<String, dynamic>>[];
      emitMergePromptSnapshot(const {
        'event': 'llm_prompt_snapshot',
      }, writer: captured.add);
      expect(captured, hasLength(1));
      expect(
        () => emitMergePromptSnapshot(const {
          'event': 'llm_prompt_snapshot',
        }, writer: (_) => throw StateError('DB 不可用')),
        returnsNormally,
      );
    });
  });

  // ───────────────────────────────────────────────
  // B2 · pending_context（schema / 解析 / 收敛层）
  // ───────────────────────────────────────────────
  group('W-15-B B2 · prompt 指令在场（引导 LLM 自标）', () {
    test('merge prompt 含「跨片因果提示」段与格式字段行（已过审文案）', () {
      final prompt = buildMergePrompt(const []);
      expect(prompt, contains('跨片因果提示：若某条线索的成立与否依赖未包含在任何分片中的信息'));
      expect(prompt, contains('该条须标记 pending_context=true，并把结论写为「暂时无法判断」'));
      expect(prompt, contains('- pending_context (bool): 缺省 false；见「跨片因果提示」'));
    });
  });

  group('W-15-B B2 · Syndrome schema 往返', () {
    test('normalizePendingContext：bool 透传，非 bool 归 null', () {
      expect(normalizePendingContext(true), isTrue);
      expect(normalizePendingContext(false), isFalse);
      expect(normalizePendingContext('true'), isNull);
      expect(normalizePendingContext(1), isNull);
      expect(normalizePendingContext(null), isNull);
    });

    test('toJson：true/false 落 key，null 不落 key（往返稳定）', () {
      Syndrome s(bool? pending) => Syndrome(
        syndromeId: 'P001',
        name: '情绪标签化',
        severity: Severity.l2,
        evidence: const ['证据'],
        explanation: '说明',
        pendingContext: pending,
      );
      expect(s(true).toJson()['pending_context'], true);
      expect(s(false).toJson()['pending_context'], false);
      expect(s(null).toJson().containsKey('pending_context'), isFalse);
      // 往返：toJson → fromJson 保真
      expect(Syndrome.fromJson(s(true).toJson()).pendingContext, isTrue);
      expect(Syndrome.fromJson(s(false).toJson()).pendingContext, isFalse);
      expect(Syndrome.fromJson(s(null).toJson()).pendingContext, isNull);
    });

    test('fromJson：非 bool 值按缺失处理（不抛 TypeError）', () {
      final s = Syndrome.fromJson({
        'syndrome_id': 'P001',
        'name': '情绪标签化',
        'severity': 'L2',
        'evidence': ['证据'],
        'explanation': '说明',
        'pending_context': 'yes',
      });
      expect(s.pendingContext, isNull);
    });

    test('解析透传：YS_DIAGNOSIS 块内 pending_context=true 进 Syndrome', () {
      final raw =
          '诊断正文。\n'
          '[YS_DIAGNOSIS]\n'
          '{"syndromes":[{"syndrome_id":"P001","name":"情绪标签化","severity":"L2",'
          '"evidence":["证据"],"explanation":"说明","pending_context":true}],'
          '"suggested_actions":["A003"],"confidence":0.9}\n'
          '[/YS_DIAGNOSIS]';
      final result = parseDiagnosis(raw);
      expect(result.diagnosis, isNotNull);
      expect(result.diagnosis!.syndromes.single.pendingContext, isTrue);
    });
  });

  group('W-15-B B2 · 收敛层：pending 条目单独排尾部', () {
    Syndrome makeS(String id, Severity sev, {bool? pending}) => Syndrome(
      syndromeId: id,
      name: '症候$id',
      severity: sev,
      evidence: ['证据$id'],
      explanation: '说明$id',
      pendingContext: pending,
    );

    test('pending 条目不挤占展示位：5 条可判断 + 1 条 pending ⇒ pending 进溢出', () {
      final input = [
        makeS('P001', Severity.l1),
        makeS('P002', Severity.l2),
        makeS('P003', Severity.l3),
        makeS('P004', Severity.l2),
        makeS('P005', Severity.l1),
        makeS('P006', Severity.l3, pending: true),
      ];
      final (:displayed, :report) = mergeOutputConvergence(input);
      expect(displayed, hasLength(kMergeDisplayCap));
      expect(displayed.any((s) => s.pendingContext == true), isFalse);
      expect(report.overflow.map((s) => s.syndromeId), ['P006']);
    });

    test('条目不足上限：pending 排尾部（不参与严重度主序）', () {
      final input = [
        makeS('P001', Severity.l1),
        makeS('P002', Severity.l2),
        makeS('P003', Severity.l3, pending: true),
      ];
      final (:displayed, :report) = mergeOutputConvergence(input);
      expect(report.rawCount, 3);
      expect(displayed, hasLength(3));
      expect(displayed.last.syndromeId, 'P003', reason: 'pending 单独排尾部');
      expect(displayed.first.syndromeId, 'P002', reason: '非 pending 走主序');
    });

    test('同 id 高重叠合并：任一份 pending ⇒ 合并条目保留 pending（缺口不因合并抹掉）', () {
      final evidence = ['同一处原文证据，足够长以触发 Jaccard 阈值判定逻辑'];
      final input = [
        Syndrome(
          syndromeId: 'P001',
          name: '情绪标签化',
          severity: Severity.l2,
          evidence: evidence,
          explanation: '说明',
        ),
        Syndrome(
          syndromeId: 'P001',
          name: '情绪标签化',
          severity: Severity.l2,
          evidence: evidence,
          explanation: '说明',
          pendingContext: true,
        ),
      ];
      final (:displayed, :report) = mergeOutputConvergence(input);
      expect(report.dedupedCount, 1, reason: '同 id 且证据 Jaccard=1 ⇒ 合并');
      expect(displayed.single.pendingContext, isTrue);
    });
  });
}
