// ─────────────────────────────────────────────────────────────
// llm_call_log_sink_test — TH 九批：LLM 调用埋点的落库出口
//
// 覆盖：
//   1. usage + context ⇒ 载荷字段逐项映射（purpose / sessionId / tokens）
//   2. 无 context ⇒ purpose=unknown、sessionId=null（既有调用零标注的形态）
//   3. latency 由 context.withLatency 携带（LlmClient 在 usage 帧处填）
//   4. toJson 的 event 锚点与 miss_tokens 预计算
//   5. writer 抛错 ⇒ 不冒泡（观测是旁路，不得阻断主流程）
//   6. 默认 writer 可构造（不注入 writer 时不抛）
//   7. TH-2：档位由 context.withTier 携带 ⇒ 落 reasoning_tier；
//      且 withLatency **不得丢档位**（真实调用链是先 withTier 后 withLatency）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_call_log_sink.dart';
import 'package:writingcoach/services/llm_usage.dart';

void main() {
  group('LlmCallLogSink — 载荷组装', () {
    test('#1 usage + context ⇒ 字段逐项映射', () {
      final captured = <LlmCallLogEntry>[];
      final sink = LlmCallLogSink(writer: captured.add);

      sink.call(
        const LlmUsage(
          promptTokens: 120,
          completionTokens: 8,
          cachedTokens: 64,
          reasoningTokens: 3,
          model: 'deepseek-flash',
          context: LlmCallContext(
            purpose: LlmCallPurpose.teacher,
            sessionId: 's-1',
          ),
        ),
        LlmUsageKind.stream,
      );

      expect(captured, hasLength(1));
      final e = captured.single;
      expect(e.purpose, LlmCallPurpose.teacher);
      expect(e.sessionId, 's-1');
      expect(e.kind, LlmUsageKind.stream);
      expect(e.promptTokens, 120);
      expect(e.completionTokens, 8);
      expect(e.cachedTokens, 64);
      expect(e.reasoningTokens, 3);
      expect(e.missTokens, 56, reason: 'miss = prompt − cached');
      expect(e.model, 'deepseek-flash');
    });

    test('#2 无 context ⇒ purpose=unknown、sessionId=null', () {
      final captured = <LlmCallLogEntry>[];
      final sink = LlmCallLogSink(writer: captured.add);

      sink.call(
        const LlmUsage(promptTokens: 10, completionTokens: 2),
        LlmUsageKind.chat,
      );

      final e = captured.single;
      expect(e.purpose, LlmCallPurpose.unknown);
      expect(e.sessionId, isNull);
      expect(e.latencyMs, isNull);
    });

    test('#3 latency 由 context 携带（withLatency 链路）', () {
      final captured = <LlmCallLogEntry>[];
      final sink = LlmCallLogSink(writer: captured.add);

      // 模拟 LlmClient 在 usage 帧处的做法：withContext(...withLatency(ms))
      const base = LlmCallContext(purpose: LlmCallPurpose.diagnosis);
      sink.call(
        const LlmUsage(
          promptTokens: 5,
          completionTokens: 1,
        ).withContext(base.withLatency(1234)),
        LlmUsageKind.stream,
      );

      expect(captured.single.latencyMs, 1234);
      expect(captured.single.purpose, LlmCallPurpose.diagnosis);
    });

    test('#4 toJson：event 锚点 + miss_tokens + 字段名口径', () {
      const e = LlmCallLogEntry(
        sessionId: 's-9',
        purpose: LlmCallPurpose.mainChat,
        kind: LlmUsageKind.stream,
        promptTokens: 100,
        completionTokens: 20,
        cachedTokens: 80,
        reasoningTokens: 7,
        latencyMs: 456,
        model: 'deepseek-flash',
      );

      final json = e.toJson();
      expect(json['event'], 'llm_call');
      expect(json['session_id'], 's-9');
      expect(json['purpose'], 'mainChat');
      expect(json['kind'], 'stream');
      expect(json['prompt_tokens'], 100);
      expect(json['completion_tokens'], 20);
      expect(json['cached_tokens'], 80);
      expect(json['reasoning_tokens'], 7);
      expect(json['miss_tokens'], 20);
      expect(json['latency_ms'], 456);
      expect(json['model'], 'deepseek-flash');
    });

    test('#5 missTokens 不为负（cached 异常大于 prompt 时钳零）', () {
      const e = LlmCallLogEntry(
        sessionId: null,
        purpose: LlmCallPurpose.unknown,
        kind: LlmUsageKind.chat,
        promptTokens: 10,
        completionTokens: 1,
        cachedTokens: 99,
        reasoningTokens: 0,
      );
      expect(e.missTokens, 0);
    });

    test('#6 writer 抛错 ⇒ 不冒泡（观测是旁路）', () {
      final sink = LlmCallLogSink(
        writer: (_) => throw StateError('落库通道故障（演练）'),
      );

      // 不放 expect(throwsA)：纪律要求静默吞掉，主流程不受影响
      expect(
        () => sink.call(
          const LlmUsage(promptTokens: 1, completionTokens: 1),
          LlmUsageKind.chat,
        ),
        returnsNormally,
      );
    });

    test('#7 缺省 writer（落 error_logs 通道）可构造且不抛', () {
      // 不 attach 仓储时 ErrorHandler 走内存入队（有界），同样不得抛。
      final sink = LlmCallLogSink();
      expect(
        () => sink.call(
          const LlmUsage(promptTokens: 2, completionTokens: 1),
          LlmUsageKind.chat,
        ),
        returnsNormally,
      );
    });

    // ── TH-2：档位入埋点（可事后回溯） ──
    //
    // 动因：档位此前只活在请求体里 ⇒ 事后从 error_logs 读不回，审计只能靠
    // 「切档 + 重启 + rowid 段」归属（该法已被 `DECISIONS §4-68` 列为不可采信）。

    test('#8 档位由 context.withTier 携带 ⇒ 同时进字段与 toJson', () {
      final captured = <LlmCallLogEntry>[];
      final sink = LlmCallLogSink(writer: captured.add);

      const base = LlmCallContext(purpose: LlmCallPurpose.mainChat);
      sink.call(
        const LlmUsage(
          promptTokens: 10,
          completionTokens: 2,
        ).withContext(base.withTier('deep')),
        LlmUsageKind.stream,
      );

      expect(captured.single.reasoningTier, 'deep');
      expect(captured.single.toJson()['reasoning_tier'], 'deep');
    });

    test('#9 未带档位 ⇒ 键在、值为 null（不编造默认档）', () {
      const e = LlmCallLogEntry(
        sessionId: 's-1',
        purpose: LlmCallPurpose.unknown,
        kind: LlmUsageKind.chat,
        promptTokens: 1,
        completionTokens: 1,
        cachedTokens: 0,
        reasoningTokens: 0,
      );

      final json = e.toJson();
      expect(e.reasoningTier, isNull);
      expect(
        json.containsKey('reasoning_tier'),
        isTrue,
        reason: '键恒在 —— 查询侧不必区分「旧记录没这个键」与「本次没档位」',
      );
      expect(json['reasoning_tier'], isNull);
    });

    test('#10 ★ withLatency 不得丢档位（真实链路顺序 = 先 withTier 后 withLatency）', () {
      const base = LlmCallContext(purpose: LlmCallPurpose.mainChat);

      final chained = base.withTier('low').withLatency(88);

      expect(
        chained.reasoningTier,
        'low',
        reason: 'withLatency 若丢档位，落库载荷会静默变 null —— 而只调 withTier 的用例不会红',
      );
      expect(chained.latencyMs, 88);
    });
  });
}
