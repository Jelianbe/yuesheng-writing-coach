// ─────────────────────────────────────────────────────────────
// VerificationGate 单测 — 验证层第二模型接入（ADR-0014 · R-027）
//
// 逐组对应 R-027 施工稿 §3.4 六个 group：
//   V-2 三键缺省即禁用（分母 = 8 子集）
//   V-4② 硬超时（C3 定值 15000 · 期望值硬编码，异源）
//   V-5 非法值隔离（分母 = 3 负向样本）
//   V-4③ 异常不外抛（分母 = 4 类故障桩）
//   S-7 上下文不含发现层结论（哨兵串）
//   V-2/V-3 独立实例
//
// 读数口径：本文件断言的是一切「结构态」（四态 / 计数 / 串内容），
// 不产出任何语义读数；E2 红线不因本文件而被触碰。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/discovery_call.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/verification_gate.dart';

/// 出站替身：行为由 handler 决定，记录调用次数与最后一条 messages。
///
/// 与既有测试同构（`extends LlmClient` + override）——`LlmClient` 的位置参数
/// 全可选 ⇒ 隐式 `super()` 合法，不需要改动被继承类。
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

const VerificationKeys _fullKeys = VerificationKeys(
  baseUrl: 'https://verify.example/v1',
  apiKey: 'verify-key',
  model: 'verify-model',
);

const VerificationHypothesis _h1 = VerificationHypothesis(
  id: 'h1',
  syndromeId: 'S-01',
  evidence: ['他把杯子放回桌面，没有说话。'],
);

const VerificationHypothesis _h2 = VerificationHypothesis(
  id: 'h2',
  syndromeId: 'S-02',
  evidence: ['窗外的雨下了一整夜。'],
);

const String _okOneItem = '[{"id":"h1","verdict":"confirmed"}]';

/// 构造一个只带替身 client 的 gate（sink 缺省静默，避免污染测试输出）。
VerificationGate _gate({
  required _SpyClient client,
  VerificationKeys keys = _fullKeys,
  Duration? timeout,
  VerificationSink? sink,
  Future<VerificationKeys> Function()? keysLoader,
}) => VerificationGate(
  keysLoader: keysLoader ?? () async => keys,
  clientFactory: (_) => client,
  sink: sink ?? (_) {},
  debugTimeoutOverride: timeout,
);

void main() {
  group('V-2 三键缺省即禁用（分母 = 8 子集）', () {
    test('8 个子集逐个构造：7 个子集出站 0，全集格出站 1（阳性对照）', () async {
      const sentinel = 'https://verify.example/v1';
      const key = 'verify-key';
      const model = 'verify-model';

      // 分母显式打印：三键的空/非空组合 = 2^3 = 8。
      const subsetCount = 8;
      expect(subsetCount, 8, reason: '分母非空：8 个子集');

      var disabledCount = 0;
      var configuredCount = 0;

      for (var mask = 0; mask < subsetCount; mask++) {
        final keys = VerificationKeys(
          baseUrl: (mask & 1) != 0 ? sentinel : '',
          apiKey: (mask & 2) != 0 ? key : '',
          model: (mask & 4) != 0 ? model : '',
        );
        final client = _SpyClient((_) async => _okOneItem);
        final gate = _gate(client: client, keys: keys);

        final record = await gate.run(hypotheses: const [_h1]);

        if (mask == subsetCount - 1) {
          // 全集格 = 阳性对照：三键齐 ⇒ 真的出站 1 次。
          expect(keys.isComplete, isTrue, reason: 'mask=$mask 应三键齐');
          expect(client.calls, 1, reason: 'mask=$mask 全集格必须出站 1 次');
          expect(record!.outcome, VerificationOutcome.ok);
          configuredCount++;
        } else {
          expect(keys.isComplete, isFalse, reason: 'mask=$mask 应缺键');
          expect(client.calls, 0, reason: 'mask=$mask 缺键必须零出站');
          expect(
            record!.outcome,
            VerificationOutcome.notConfigured,
            reason: 'mask=$mask 缺键必须记 notConfigured',
          );
          disabledCount++;
        }
      }

      expect(disabledCount, 7, reason: '7 个缺键子集');
      expect(configuredCount, 1, reason: '1 个全集格');
    });

    test('空候选 / 显式取消 ⇒ 返回 null（不是四态之一）', () async {
      final client = _SpyClient((_) async => _okOneItem);
      final gate = _gate(client: client);

      expect(await gate.run(hypotheses: const []), isNull);
      expect(await gate.run(hypotheses: const [_h1], cancelled: true), isNull);
      expect(client.calls, 0, reason: '两种情况都不得出站');
    });
  });

  group('V-4② 硬超时（C3 定值 15000）', () {
    test('hardTimeout 期望值硬编码 15000ms（异源：不读常量反推常量）', () {
      // 期望值来自 DECISIONS §4-449 ② 的定值，**不是**从 LlmConfig 反推
      // ⇒ 常量被改即红；若两侧都读同一常量就成了同源自证。
      expect(VerificationGate.hardTimeout, const Duration(milliseconds: 15000));
    });

    test('永不返回的桩 ⇒ 降级 timeout，且耗时有上界', () async {
      // 永不完成的 future：只有硬超时能结束它。
      final client = _SpyClient((_) => Completer<String>().future);
      final gate = _gate(
        client: client,
        timeout: const Duration(milliseconds: 20),
      );

      final stopwatch = Stopwatch()..start();
      final record = await gate.run(hypotheses: const [_h1]);
      stopwatch.stop();

      expect(record!.outcome, VerificationOutcome.timeout);
      expect(client.calls, 1);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1000),
        reason: '硬超时必须真的截断等待（实测 ${stopwatch.elapsedMilliseconds}ms）',
      );
    });
  });

  group('V-5 非法值隔离（分母 = 3 负向样本）', () {
    test('枚举恰 3 值', () {
      expect(VerificationVerdict.values.length, 3);
      expect(kVerdictWire.length, 3, reason: '线上字面量表也恰 3 项');
    });

    test('3 类非法响应逐类 parseFail（各计 1 次读数）', () async {
      // 分母显式打印：3 个负向样本。
      const sampleCount = 3;

      final samples = <String, String>{
        // ① verdict 不在三值内
        'verdict_illegal': '[{"id":"h1","verdict":"maybe"}]',
        // ② 缺 id 字段
        'missing_id': '[{"verdict":"confirmed"}]',
        // ③ 项数少一项（给了 2 条假设，只回 1 项）
        'count_mismatch': _okOneItem,
      };
      final hypothesesBySample = <String, List<VerificationHypothesis>>{
        'verdict_illegal': const [_h1],
        'missing_id': const [_h1],
        'count_mismatch': const [_h1, _h2],
      };

      expect(samples.length, sampleCount, reason: '分母非空：3 个负向样本');

      var parseFailCount = 0;
      for (final entry in samples.entries) {
        final client = _SpyClient((_) async => entry.value);
        final gate = _gate(client: client);
        final record = await gate.run(
          hypotheses: hypothesesBySample[entry.key]!,
        );

        expect(
          record!.outcome,
          VerificationOutcome.parseFail,
          reason: '样本 ${entry.key} 必须整批 parseFail',
        );
        expect(record.verdicts, isEmpty, reason: '样本 ${entry.key} 不得部分采信');
        parseFailCount++;
      }
      expect(parseFailCount, sampleCount);
    });

    test('三值正向：三种合法 verdict 逐个映射（分母 = 3）', () async {
      const wires = {
        'rejected': VerificationVerdict.rejected,
        'confirmed': VerificationVerdict.confirmed,
        'needs_full_text': VerificationVerdict.needsFullText,
      };
      expect(wires.length, 3);

      for (final entry in wires.entries) {
        final client = _SpyClient(
          (_) async => '[{"id":"h1","verdict":"${entry.key}"}]',
        );
        final record = await _gate(client: client).run(hypotheses: const [_h1]);

        expect(record!.outcome, VerificationOutcome.ok);
        expect(record.verdicts['h1'], entry.value);
      }
    });
  });

  group('V-4③ 异常不外抛（分母 = 4 类故障桩）', () {
    test('4 类故障逐类降级 error，无一抛出', () async {
      const sampleCount = 4;
      final failures = <String, Exception>{
        'connection_error': DioException(
          requestOptions: RequestOptions(path: '/chat'),
          type: DioExceptionType.connectionError,
        ),
        // 网络层超时（DioException）≠ gate 自身硬超时（TimeoutException）：
        // 前者是出站故障 ⇒ error；后者走 V-4② 的 timeout 分支。
        'network_timeout': DioException(
          requestOptions: RequestOptions(path: '/chat'),
          type: DioExceptionType.receiveTimeout,
        ),
        'bad_response': DioException(
          requestOptions: RequestOptions(path: '/chat'),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/chat'),
            statusCode: 500,
          ),
        ),
        'decode_error': const FormatException('bad json'),
      };
      expect(failures.length, sampleCount, reason: '分母非空：4 类故障桩');

      var errorCount = 0;
      for (final entry in failures.entries) {
        final client = _SpyClient((_) async => throw entry.value);
        final record = await _gate(client: client).run(hypotheses: const [_h1]);

        expect(
          record!.outcome,
          VerificationOutcome.error,
          reason: '故障 ${entry.key} 必须降级 error 且不外抛',
        );
        errorCount++;
      }
      expect(errorCount, sampleCount);
    });

    test('sink 自身抛异常也不冒泡到调用方', () async {
      final client = _SpyClient((_) async => _okOneItem);
      final gate = _gate(
        client: client,
        sink: (_) => throw StateError('sink 炸了'),
      );

      final record = await gate.run(hypotheses: const [_h1]);
      expect(record!.outcome, VerificationOutcome.ok);
    });
  });

  group('S-7 上下文不含发现层结论', () {
    test('inference 哨兵不出现在实际发出的 user 内容里', () async {
      const sentinel = 'ZZ_DESC_SENTINEL';
      // ★ 哨兵刻意放 `inference`（DiscoveryNote 真有的字段）而不是 `description`
      // （`VerificationHypothesis` 类型层就没有该字段 ⇒ 放那里测不到东西）。
      // 链路走真实解析器，不手工构造 parsed：手工构造时断言的是自己写死的值。
      final raw =
          '{"observations":[{"exit":"promoted",'
          '"anchorQuotes":["他把杯子放回桌面，没有说话。"],'
          '"inference":"$sentinel 这条推测不得进入验证上下文",'
          '"syndromeId":"S-01"}]}';
      final parsed = parseDiscoveryNotes(raw, '他把杯子放回桌面，没有说话。');
      expect(parsed.rawCount, 1, reason: '分母非空：否则下面的断言恒真');

      final hypotheses = toHypotheses(parsed);
      expect(hypotheses.length, 1, reason: '出口一 + 有编号应放行 1 条');

      final client = _SpyClient((_) async => _okOneItem);
      await _gate(client: client).run(hypotheses: hypotheses);

      final userContent = client.lastMessages
          .firstWhere((message) => message.role == 'user')
          .content;

      // 负向：发现层结论不得出现（命中即红）。
      expect(
        userContent.contains(sentinel),
        isFalse,
        reason: '验证上下文含发现层 inference ⇒ S-7 破防',
      );
      // 阳性对照：证据与症候编号必须在（防「发空串也算不含哨兵」）。
      expect(userContent.contains('他把杯子放回桌面'), isTrue);
      expect(userContent.contains('S-01'), isTrue);
      // 系统提示词也检一次（防把结论写进 system）。
      final systemContent = client.lastMessages
          .firstWhere((message) => message.role == 'system')
          .content;
      expect(systemContent.contains(sentinel), isFalse);
    });

    test('三出口：只有 exit=promoted 且有编号者入验证层（分母成对断言）', () {
      final raw =
          '{"observations":['
          '{"exit":"promoted","anchorQuotes":["e1"],"inference":"i1",'
          '"syndromeId":"S-01"},'
          '{"exit":"observation","anchorQuotes":["e2"],"reason":"r2"},'
          '{"exit":"unclassified","anchorQuotes":["e3"],"reason":"r3"}]}';
      final parsed = parseDiscoveryNotes(raw, 'e1 e2 e3');

      final hypotheses = toHypotheses(parsed);

      // 集合断言：出口一且有编号者才进。
      expect(hypotheses.map((item) => item.syndromeId).toList(), ['S-01']);
      expect(hypotheses.single.id, 'h1');
      // ★ 分母断言与集合断言**必须成对**：只断言 length == 1 时，
      // 「把该进的都丢掉」也满足（空集恒绿）。
      expect(parsed.rawCount, 3);
      expect(parsed.promoted, 1);
      expect(parsed.dropped, 0);
    });
  });

  group('V-2/V-3 独立实例', () {
    test('验证三键与主链三键不同键，且三键互不相同', () {
      // 期望值硬编码自主链存储的公开契约（`llm_config_storage.dart:9-11`），
      // 不从本层常量反推 ⇒ 有人把验证键写成主链键即红。
      expect(kVerificationKeyApiKey, isNot('yuesheng_api_key'));
      expect(kVerificationKeyBaseUrl, isNot('yuesheng_api_base_url'));
      expect(kVerificationKeyModel, isNot('yuesheng_api_model'));
      expect(
        {
          kVerificationKeyApiKey,
          kVerificationKeyBaseUrl,
          kVerificationKeyModel,
        }.length,
        3,
      );
    });

    test('同源 model 构造：不告警、不阻断、出站 1 次', () async {
      VerificationKeys? received;
      final client = _SpyClient((_) async => _okOneItem);
      final gate = VerificationGate(
        keysLoader: () async => const VerificationKeys(
          baseUrl: 'https://verify.example/v1',
          apiKey: 'verify-key',
          // 与主链同名模型：V-3 明确不识别、不告警、不拦截。
          model: 'same-as-main-chain',
        ),
        clientFactory: (keys) {
          received = keys;
          return client;
        },
        sink: (_) {},
      );

      final record = await gate.run(hypotheses: const [_h1]);

      expect(received!.model, 'same-as-main-chain');
      // factory 收到的是**验证三键**而非主链键（复核补：原先只断言了常量字符串）。
      expect(received!.apiKey, 'verify-key');
      expect(received!.baseUrl, 'https://verify.example/v1');
      expect(client.calls, 1);
      expect(record!.outcome, VerificationOutcome.ok);
    });

    test('读数形态：全枚举 / 整数，无折算无百分比（V-8）', () async {
      final client = _SpyClient(
        (_) async =>
            '[{"id":"h1","verdict":"confirmed"},{"id":"h2","verdict":"rejected"}]',
      );
      final record = await _gate(
        client: client,
      ).run(hypotheses: const [_h1, _h2]);

      final json = record!.toJson();
      expect(json['evidence'], 'E2');
      expect(json['outcome'], 'ok');
      expect(json['hypothesisCount'], 2);
      expect(json.containsKey('percent'), isFalse);
      expect(json.containsKey('rate'), isFalse);
    });
  });
}
