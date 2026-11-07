// ─────────────────────────────────────────────────────────────
// 发现层接线单测（R-027 · T-20261106-04 批）。
//
// 逐组对应报批稿 §7 的七条牙（J1–J7）+ §2.4 的五条硬约束：
//   J1  S-1 · 发现帧不含症候库判据正文（分母非空）
//   J2  S-1 · 帧隔离（kChunkSystemPrompt 零漂移 + 无协议独有词）
//   J3  S-5 · 只有出口一且有编号者进验证层
//   J4  S-5 · 全出口二时集合空**但分母非零**（防空集恒绿）
//   J5  锚点必须是逐字子串
//   J6  协议违规三形态一律 dropped
//   J7  S-7 · 映射产物不含 inference / reason
//   门控：三键门 / 长度门 / 取消门 / 失败不外抛 / 禁用症候剔除
//
// ★ J3 与 J4 是**成对**的：只有 J3 会漏掉「把该进的都丢掉」；
//   只有 J4 会漏掉「出口二/三 也进来了」。二者缺一，S-5 的牙不成立。
//
// 读数口径：本文件只断言结构态，不产出语义读数（检出增量挂 U4，E3 未验）。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/discovery_call.dart';
import 'package:writingcoach/services/discovery_prompt.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/verification_gate.dart';

/// 出站替身：记录调用次数与最后一条 messages（与 `verification_gate_test.dart` 同构）。
class _SpyClient extends LlmClient {
  final Future<String> Function(List<ChatMessage> messages) handler;

  int calls = 0;
  List<ChatMessage> lastMessages = const [];

  _SpyClient(this.handler);

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) {
    calls++;
    lastMessages = messages;
    return handler(messages);
  }
}

const VerificationKeys _completeKeys = VerificationKeys(
  baseUrl: 'https://verify.invalid/v1',
  apiKey: 'k',
  model: 'm',
);

VerificationGate _gate({VerificationKeys keys = _completeKeys}) =>
    VerificationGate(
      keysLoader: () async => keys,
      clientFactory: (_) => _SpyClient((_) async => '{"observations":[]}'),
      sink: (_) {},
    );

/// 一条合法 promoted note 的 JSON 片段。
String _promoted({
  String quotes = '["E1"]',
  String inference = '"推测"',
  String syndromeId = '"S-01"',
}) =>
    '{"exit":"promoted","anchorQuotes":$quotes,"inference":$inference,'
    '"syndromeId":$syndromeId}';

String _observation({
  String quotes = '["E2"]',
  String reason = '"r2"',
  String syndromeId = '""',
}) =>
    '{"exit":"observation","anchorQuotes":$quotes,"reason":$reason,'
    '"syndromeId":$syndromeId}';

/// 手册里最长的一行正文（非 `###` 标题）。单样本足够：整段 `contains` 会因
/// 换行/缩进必然为 false，那是恒真断言，没有牙。
String _longestManualLine() {
  final lines = kSyndromeManualContent
      .split('\n')
      .where(
        (String line) => line.trim().isNotEmpty && !line.startsWith('###'),
      );
  var longest = '';
  for (final line in lines) {
    if (line.length > longest.length) longest = line;
  }
  return longest.trim();
}

void main() {
  group('J1 S-1 · 发现帧不含症候库判据正文', () {
    test('oneLine 全文与手册判据行都不出现（分母非空）', () {
      final prompt = buildDiscoverySystemPrompt();

      // 分母：取最长的 3 条 oneLine。取不到 3 条或样本过短 ⇒ 下面断言恒真。
      final oneLines = kSyndromeRegistry.map((r) => r.oneLine).toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      final samples = oneLines.take(3).toList();
      expect(samples.length, 3, reason: '分母非空：样本不足则断言无意义');

      for (final sample in samples) {
        expect(
          sample.length,
          greaterThan(10),
          reason: '样本过短会与通用措辞巧合重合，产生假红/假绿',
        );
        expect(
          prompt.contains(sample),
          isFalse,
          reason: '发现帧含症候判据正文 ⇒ S-1 破防：$sample',
        );
      }

      final manualLine = _longestManualLine();
      expect(manualLine.length, greaterThan(30), reason: '手册判据行样本过短 ⇒ 断言无牙');
      expect(prompt.contains(manualLine), isFalse, reason: '发现帧含手册判据正文');
    });
  });

  group('J2 S-1 · 帧隔离', () {
    test('kChunkSystemPrompt 长度不变且不含发现协议独有词', () {
      // 硬编码 8716（与锚点快照同源读数）：本批若误把协议拼进分块帧，
      // 只会漂移一个键 ⇒ 这里先红，比等锚点 diff 更快定位。
      expect(kChunkSystemPrompt.length, 8716);
      expect(kChunkSystemPrompt.contains('observations'), isFalse);
      expect(kChunkSystemPrompt.contains('anchorQuotes'), isFalse);
      // 反向对照：发现帧自己必须有这些词（防「两边都不含」时上面恒真）。
      final discovery = buildDiscoverySystemPrompt();
      expect(discovery.contains('observations'), isTrue);
      expect(discovery.contains('anchorQuotes'), isTrue);
    });
  });

  group('J3/J4 S-5 · 谓词与分母成对', () {
    test('J3 只有 exit=promoted 且有编号者进验证层', () {
      // ★ 非 promoted 的两条**故意带症候编号**：否则它们会因「编号为空」被顺带
      // 滤掉，「去掉 exit 判断」这个变异就抓不到（J3 会假绿）。
      final raw =
          '{"observations":[${_promoted()},'
          '${_observation(syndromeId: '"S-02"')},'
          '{"exit":"unclassified","anchorQuotes":["E3"],"reason":"r3",'
          '"syndromeId":"S-03"}]}';
      final parsed = parseDiscoveryNotes(raw, 'E1 E2 E3');
      final hypotheses = toHypotheses(parsed);

      expect(hypotheses.length, 1);
      expect(hypotheses.single.id, 'h1');
      expect(hypotheses.single.syndromeId, 'S-01');
      expect(hypotheses.single.evidence, ['E1']);
      expect(parsed.rawCount, 3, reason: '分母与集合断言必须成对');
      expect(parsed.promoted, 1);
      expect(parsed.dropped, 0);
    });

    test('J4 三出口全为 observation ⇒ 集合空但分母非零（防空集恒绿）', () {
      final raw =
          '{"observations":[${_observation(quotes: '["E1"]', syndromeId: '"S-01"')},'
          '${_observation()},'
          '{"exit":"observation","anchorQuotes":["E3"],"reason":"r3",'
          '"syndromeId":"S-03"}]}';
      final parsed = parseDiscoveryNotes(raw, 'E1 E2 E3');
      final hypotheses = toHypotheses(parsed);

      expect(hypotheses, isEmpty);
      // ★ 这三条才是牙：删掉它们，「把该进的都丢掉」也能满足上面那条 isEmpty。
      expect(parsed.rawCount, 3);
      expect(parsed.promoted, 0);
      expect(parsed.dropped, 0);
    });

    test('出口一无编号 ⇒ 计入 promoted 分母但不进验证层（裁点 B 甲）', () {
      final raw = '{"observations":[${_promoted(syndromeId: '""')}]}';
      final parsed = parseDiscoveryNotes(raw, 'E1');
      final hypotheses = toHypotheses(parsed);

      expect(hypotheses, isEmpty);
      expect(parsed.promoted, 1, reason: '无编号的出口一仍计入分母');
      // 这个差就是 §8-1 的可观测口径。
      expect(parsed.promoted - hypotheses.length, 1);
    });
  });

  group('J5 · 锚点必须是逐字子串', () {
    test('全部引句都不是子串 ⇒ 整条作废', () {
      final raw = '{"observations":[${_promoted(quotes: '["改写过的一句"]')}]}';
      final parsed = parseDiscoveryNotes(raw, '他推开门，雨声灌进来。');

      expect(toHypotheses(parsed), isEmpty);
      expect(parsed.dropped, 1);
      expect(parsed.rawCount, 1);
    });

    test('部分引句通过 ⇒ 只保留通过者（未通过的绝不进证据）', () {
      final raw = '{"observations":[${_promoted(quotes: '["E1","伪造的一句"]')}]}';
      final parsed = parseDiscoveryNotes(raw, 'E1 E2');
      final hypotheses = toHypotheses(parsed);

      expect(hypotheses.single.evidence, ['E1']);
      expect(hypotheses.single.evidence.join().contains('伪造'), isFalse);
      expect(parsed.dropped, 0);
    });
  });

  group('J6 · 协议违规', () {
    test('缺 exit / exit 为数组 / 非法值 三形态一律 dropped', () {
      final raw =
          '{"observations":['
          '{"anchorQuotes":["E1"],"inference":"i"},'
          '{"exit":["promoted"],"anchorQuotes":["E2"],"inference":"i"},'
          '{"exit":"maybe","anchorQuotes":["E3"],"inference":"i"}]}';
      final parsed = parseDiscoveryNotes(raw, 'E1 E2 E3');

      expect(toHypotheses(parsed), isEmpty);
      expect(parsed.dropped, 3);
      expect(parsed.promoted, 0);
      expect(parsed.rawCount, 3);
    });

    test('promoted 缺 inference / observation 缺 reason 也 dropped', () {
      final raw =
          '{"observations":[${_promoted(inference: '""')},'
          '${_observation(reason: '""')}]}';
      final parsed = parseDiscoveryNotes(raw, 'E1 E2');

      expect(parsed.dropped, 2);
      expect(parsed.promoted, 0);
      expect(toHypotheses(parsed), isEmpty);
    });

    test('顶层非 JSON / observations 非数组 ⇒ empty', () {
      expect(parseDiscoveryNotes('不是 JSON', 'x').rawCount, 0);
      expect(parseDiscoveryNotes('{"observations":{}}', 'x').rawCount, 0);
      expect(parseDiscoveryNotes('{"items":[]}', 'x').rawCount, 0);
    });

    test('exit 大小写不敏感（"Promoted" 不丢条）', () {
      // ★ 报批稿 §2.4 判定要点 = 「trim + toLowerCase 后仍不中 ⇒ dropped」，
      //   而 §7 J6 表格写「"Promoted" 应 dropped」—— 两处冲突。本批按逐字
      //   授权面 §2.4 执行（宽容），并用本用例把该语义钉死，防后人按表格改回严格。
      final raw =
          '{"observations":[{"exit":"Promoted","anchorQuotes":["E1"],'
          '"inference":"i","syndromeId":"S-01"}]}';
      final parsed = parseDiscoveryNotes(raw, 'E1');

      expect(parsed.dropped, 0);
      expect(parsed.promoted, 1);
      expect(toHypotheses(parsed).single.syndromeId, 'S-01');
    });

    test('JSON 重复键不可用作「双出口」样本（jsonDecode 后者覆盖）', () {
      // 记录这一事实：重复键在解析阶段就已被覆盖，解析器**看不到**两个值。
      // ⇒ 「双出口」的可判形态只有「exit 是数组」（上一用例已覆盖）。
      final raw =
          '{"observations":[{"exit":"promoted","exit":"observation",'
          '"anchorQuotes":["E1"],"inference":"i","syndromeId":"S-01"}]}';
      final parsed = parseDiscoveryNotes(raw, 'E1');

      // 后值胜 ⇒ 实际 exit=observation，缺 reason ⇒ 被作废。
      expect(parsed.dropped, 1, reason: '若解析器真看到 promoted，本断言会红');
      expect(parsed.promoted, 0);
    });
  });

  group('J7 S-7 · 映射产物不含发现层结论', () {
    test('inference / reason 串不出现在任何字段里', () {
      const inference = 'ZZ_INFERENCE_SENTINEL';
      const reason = 'ZZ_REASON_SENTINEL';
      final raw =
          '{"observations":[{"exit":"promoted","anchorQuotes":["E1"],'
          '"inference":"$inference","reason":"$reason","syndromeId":"S-01"}]}';
      final parsed = parseDiscoveryNotes(raw, 'E1');
      final hypotheses = toHypotheses(parsed);

      final flat = [
        hypotheses.single.id,
        hypotheses.single.syndromeId,
        ...hypotheses.single.evidence,
      ].join('|');

      expect(flat.contains(inference), isFalse);
      expect(flat.contains(reason), isFalse);
      // 阳性对照：映射确实产出了东西（防空集恒绿）。
      expect(hypotheses.single.syndromeId, 'S-01');
      expect(hypotheses.single.evidence, ['E1']);
    });
  });

  group('门控 · 五条硬约束', () {
    test('三键不全 ⇒ 零出站', () async {
      final client = _SpyClient((_) async => '{"observations":[]}');
      final parsed = await runDiscoveryThenVerify(
        gate: _gate(
          keys: const VerificationKeys(baseUrl: '', apiKey: 'k', model: 'm'),
        ),
        llmClient: client,
        content: 'E1',
        disabledSyndromeIds: const {},
        cancelled: false,
      );

      expect(client.calls, 0, reason: '三键不全仍出站 ⇒ 违反裁点 E');
      expect(parsed.rawCount, 0);
    });

    test('超长正文 ⇒ 零出站（不逐块回退）', () async {
      final client = _SpyClient((_) async => '{"observations":[]}');
      final long = List.filled(kDiscoveryContentLimit + 1, 'a').join();
      final parsed = await runDiscoveryThenVerify(
        gate: _gate(),
        llmClient: client,
        content: long,
        disabledSyndromeIds: const {},
        cancelled: false,
      );

      expect(client.calls, 0);
      expect(parsed.rawCount, 0);
    });

    test('已取消 ⇒ 零出站', () async {
      final client = _SpyClient((_) async => '{"observations":[]}');
      await runDiscoveryThenVerify(
        gate: _gate(),
        llmClient: client,
        content: 'E1',
        disabledSyndromeIds: const {},
        cancelled: true,
      );

      expect(client.calls, 0);
    });

    test('三键齐 ⇒ 恰 1 次出站，system 帧 = buildDiscoverySystemPrompt()', () async {
      final client = _SpyClient(
        (_) async => '{"observations":[${_promoted()}]}',
      );
      final parsed = await runDiscoveryThenVerify(
        gate: _gate(),
        llmClient: client,
        content: 'E1 正文',
        disabledSyndromeIds: const {},
        cancelled: false,
      );

      expect(client.calls, 1);
      expect(client.lastMessages.length, 2);
      expect(client.lastMessages.first.role, 'system');
      expect(
        client.lastMessages.first.content,
        buildDiscoverySystemPrompt(),
        reason: '发现帧必须逐字等于装配函数产物（防临时拼串）',
      );
      expect(client.lastMessages.last.content, 'E1 正文');
      expect(parsed.promoted, 1);
      expect(toHypotheses(parsed).length, 1);
    });

    test('出站抛异常 ⇒ 返回 empty 且不外抛', () async {
      final client = _SpyClient((_) async => throw StateError('boom'));
      final parsed = await runDiscoveryThenVerify(
        gate: _gate(),
        llmClient: client,
        content: 'E1',
        disabledSyndromeIds: const {},
        cancelled: false,
      );

      expect(client.calls, 1, reason: '应尝试过一次（不重试）');
      expect(parsed.rawCount, 0);
    });

    test('禁用的症候被剔除，且 promoted 分母同步下调', () async {
      final client = _SpyClient(
        (_) async => '{"observations":[${_promoted()}]}',
      );
      final parsed = await runDiscoveryThenVerify(
        gate: _gate(),
        llmClient: client,
        content: 'E1',
        disabledSyndromeIds: const {'S-01'},
        cancelled: false,
      );

      expect(toHypotheses(parsed), isEmpty);
      expect(parsed.promoted, 0, reason: '分母下调，保证 promoted - h.length 只反映无编号');
    });
  });
}
