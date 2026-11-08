// ─────────────────────────────────────────────────────────────
// VerificationGate 接线级测试 — 走 runProgressiveDiagnosis 真实链路
//
// 对应 R-027 施工稿 §3.4 的第二组：
//   V-1 / V-4(a) 主链返回对象不受验证层影响（分母 = 4 字段）
//   未配置态零出站且不阻塞
//
// 与模块级测试的分工：这里不验四态内部逻辑，只验「接上去之后主链有没有变」。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';
import 'package:writingcoach/services/verification_gate.dart';

/// 主链替身：分块分析走 [chatCompletion]，merge 走 [streamChat]。
///
/// ★ T-20261106-04（S-5 接线）起，**同一个 client 也会收到发现帧**：
/// `runDiscoveryThenVerify` 用主链 `llmClient` 出站（发现层不是第二模型）。
/// 故本桩必须**按 system 帧分派**，否则发现调用会拿到分块笔记的 JSON、
/// 解析出 0 条出口一 ⇒ 验证层输入恒空 ⇒ 「验证层真的出站」变成空转绿。
class _ChainClient extends LlmClient {
  static const String _chatResponse =
      '{"notes":[{"syndromeId":"P001","description":"情绪标签化",'
      '"evidence":["XXXXXXXXXX"],"severity":"L1"}]}';

  /// 发现帧应答：1 条出口一 + 逐字锚点（`XXXXXXXXXX` 是每段原文的子串）。
  static const String _discoveryResponse =
      '{"observations":[{"exit":"promoted","anchorQuotes":["XXXXXXXXXX"],'
      '"inference":"疑似情绪标签化","syndromeId":"P001"}]}';

  static const String _streamResponse = '合并后的诊断结果';

  int chatCalls = 0;
  int discoveryCalls = 0;

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) async {
    chatCalls++;
    // 发现帧独有词 `anchorQuotes`（S-1 帧隔离的可判形态）⇒ 按帧分派。
    final system = messages
        .firstWhere((message) => message.role == 'system')
        .content;
    if (system.contains('anchorQuotes')) {
      discoveryCalls++;
      return _discoveryResponse;
    }
    return _chatResponse;
  }

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    callback(LlmStreamResponse(content: _streamResponse, isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// 验证层出站替身。
class _VerifyClient extends LlmClient {
  final Future<String> Function() handler;
  int calls = 0;

  _VerifyClient(this.handler);

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) {
    calls++;
    return handler();
  }
}

/// >4000 字触发分块的正文（15 段 × 351 字 ≈ 5265 字）。
///
/// evidence 声明为 `XXXXXXXXXX` —— 是每段原文的子串（`_parseChunkNotes` 会
/// 断言「证据是本块原文子串」，非子串会被丢条，导致验证层输入为空而误绿）。
String _longContent() {
  final paragraphs = <String>[];
  for (var i = 0; i < 15; i++) {
    paragraphs.add('${'X' * 350}段落$i');
  }
  return paragraphs.join('\n\n');
}

const VerificationKeys _fullKeys = VerificationKeys(
  baseUrl: 'https://verify.example/v1',
  apiKey: 'verify-key',
  model: 'verify-model',
);

/// 主链返回对象的可比形态（ChunkCoverage 未重写 `==`，逐字段拼串比较）。
List<String> _resultShape(ProgressiveResult result) => [
  result.fullContent,
  '${result.chunkCount}',
  '${result.failedChunks}',
  result.chunkCoverage
      .map((item) => '${item.index}:${item.start}:${item.end}:${item.located}')
      .join(','),
];

void main() {
  group('V-1 / V-4(a) 主链返回对象不受验证层影响', () {
    test('4 个字段逐字段相等（gate = null vs gate = 故障注入）', () async {
      final content = _longContent();

      final baseline = await runProgressiveDiagnosis(
        content: content,
        title: '接线测试',
        onContent: (_) {},
        llmClient: _ChainClient(),
      );

      // 故障注入：验证层出站直接抛异常（会走 error 态）。
      final verifyClient = _VerifyClient(
        () async => throw StateError('验证层故障注入'),
      );
      final gate = VerificationGate(
        keysLoader: () async => _fullKeys,
        clientFactory: (_) => verifyClient,
        sink: (_) {},
      );

      final withGate = await runProgressiveDiagnosis(
        content: content,
        title: '接线测试',
        onContent: (_) {},
        llmClient: _ChainClient(),
        verificationGate: gate,
      );

      expect(baseline, isNotNull);
      expect(withGate, isNotNull);

      final baselineShape = _resultShape(baseline!);
      final withGateShape = _resultShape(withGate!);

      // 分母显式打印：4 个字段。
      expect(baselineShape.length, 4, reason: '分母 = 4 字段');
      for (var i = 0; i < baselineShape.length; i++) {
        expect(
          withGateShape[i],
          baselineShape[i],
          reason: '第 ${i + 1} 个字段被验证层改变了 ⇒ V-4(a) 破防',
        );
      }

      // 阳性对照：验证层确实被调用了（否则上面的相等是空转）。
      expect(verifyClient.calls, 1, reason: '验证层必须真的出站 1 次，否则「主链不变」是空转绿');
    });

    test('四态逐态注入：4 字段逐态不变，且各态都有上界（分母 = 4 态 × 4 字段）', () async {
      final content = _longContent();

      final baseline = await runProgressiveDiagnosis(
        content: content,
        title: '接线测试',
        onContent: (_) {},
        llmClient: _ChainClient(),
      );
      final baselineShape = _resultShape(baseline!);

      const emptyKeys = VerificationKeys(baseUrl: '', apiKey: '', model: '');
      final gates = <String, VerificationGate>{
        // 态①：三键缺省 ⇒ notConfigured（不该发请求，factory 也不该被调）。
        'notConfigured': VerificationGate(
          keysLoader: () async => emptyKeys,
          clientFactory: (_) => _VerifyClient(() async => '[]'),
          sink: (_) {},
        ),
        // 态②：硬超时 ⇒ timeout（永不返回 + 20ms 上限，避免真等 15s）。
        'timeout': VerificationGate(
          keysLoader: () async => _fullKeys,
          clientFactory: (_) => _VerifyClient(() => Completer<String>().future),
          sink: (_) {},
          debugTimeoutOverride: const Duration(milliseconds: 20),
        ),
        // 态③：出站异常 ⇒ error。
        'error': VerificationGate(
          keysLoader: () async => _fullKeys,
          clientFactory: (_) =>
              _VerifyClient(() async => throw StateError('四态注入 error')),
          sink: (_) {},
        ),
        // 态④：解析非法 ⇒ parseFail。
        'parseFail': VerificationGate(
          keysLoader: () async => _fullKeys,
          clientFactory: (_) => _VerifyClient(() async => '这不是 JSON'),
          sink: (_) {},
        ),
      };

      expect(gates.length, 4, reason: '分母 = 4 个降级态');

      for (final entry in gates.entries) {
        final watch = Stopwatch()..start();
        final result = await runProgressiveDiagnosis(
          content: content,
          title: '接线测试',
          onContent: (_) {},
          llmClient: _ChainClient(),
          verificationGate: entry.value,
        );
        watch.stop();

        final shape = _resultShape(result!);
        for (var i = 0; i < baselineShape.length; i++) {
          expect(
            shape[i],
            baselineShape[i],
            reason: '态 ${entry.key} 改变了第 ${i + 1} 个字段 ⇒ V-4(a)/(c) 破防',
          );
        }
        // V-4(b)：四态都必须有上界（正常一轮亚秒级，给 5s 宽限）。
        expect(
          watch.elapsedMilliseconds,
          lessThan(5000),
          reason:
              '态 ${entry.key} 把主链拖住 ${watch.elapsedMilliseconds}ms ⇒ V-4(b) 破防',
        );
      }
    });
  });

  group('未配置态零出站且不阻塞', () {
    test('三键全空 ⇒ 发现层与验证层都零出站、client 都不造、零读数', () async {
      final content = _longContent();

      // 基线耗时（gate = null）。
      final baselineWatch = Stopwatch()..start();
      await runProgressiveDiagnosis(
        content: content,
        title: '接线测试',
        onContent: (_) {},
        llmClient: _ChainClient(),
      );
      baselineWatch.stop();

      var factoryCalls = 0;
      final verifyClient = _VerifyClient(
        () async => '[{"id":"h1","verdict":"confirmed"}]',
      );
      final records = <VerificationRecord>[];
      final gate = VerificationGate(
        keysLoader: () async =>
            const VerificationKeys(baseUrl: '', apiKey: '', model: ''),
        clientFactory: (_) {
          factoryCalls++;
          return verifyClient;
        },
        sink: records.add,
      );

      final watch = Stopwatch()..start();
      final chain = _ChainClient();
      final result = await runProgressiveDiagnosis(
        content: content,
        title: '接线测试',
        onContent: (_) {},
        llmClient: chain,
        verificationGate: gate,
      );
      watch.stop();

      expect(result, isNotNull);
      expect(factoryCalls, 0, reason: '未配置态连 client 都不该造');
      expect(verifyClient.calls, 0, reason: '未配置态必须零出站');
      expect(chain.discoveryCalls, 0, reason: '三键门前置于发现调用（裁点 E）');

      // ★ 改判（T-20261106-04 · S-5 接线）：旧链路里「有候选 + 未配置」会留 1 条
      // notConfigured 读数；新链路里三键门**前置于发现调用** ⇒ 未配置时发现层也
      // 不跑 ⇒ 验证层输入恒空 ⇒ `gate.run` 按既有语义（`hypotheses.isEmpty ⇒
      // return null`）**不留读数**。这不是「零读数更安全」，而是**可观测性下降**，
      // 已登记为本批已知代价（见施工回执 §6）。
      expect(records, isEmpty, reason: '未配置态不再产生 notConfigured 读数');

      // 防空转（保留原用例意图，换判据）：同一条主链，仅把三键填满 ⇒
      // 发现层必须真的出站 1 次 ⇒ 证明上面的零出站来自三键门，
      // **不是「没东西可发」**。
      var fullFactoryCalls = 0;
      final fullVerify = _VerifyClient(
        () async => '[{"id":"h1","verdict":"confirmed"}]',
      );
      final fullGate = VerificationGate(
        keysLoader: () async => _fullKeys,
        clientFactory: (_) {
          fullFactoryCalls++;
          return fullVerify;
        },
        sink: (_) {},
      );
      final fullChain = _ChainClient();
      await runProgressiveDiagnosis(
        content: content,
        title: '接线测试',
        onContent: (_) {},
        llmClient: fullChain,
        verificationGate: fullGate,
      );

      expect(fullChain.discoveryCalls, 1, reason: '三键齐 ⇒ 发现调用恰 1 次');
      expect(fullFactoryCalls, 1, reason: '三键齐 ⇒ 验证 client 造 1 次');
      expect(fullVerify.calls, 1, reason: '三键齐 ⇒ 验证层出站 1 次');

      expect(
        watch.elapsedMilliseconds - baselineWatch.elapsedMilliseconds,
        lessThan(1000),
        reason:
            '未配置态不得阻塞主链（基线 ${baselineWatch.elapsedMilliseconds}ms / '
            '接入后 ${watch.elapsedMilliseconds}ms）',
      );
    });

    test('取消态 ⇒ 不发起验证（返回 null，零读数）', () async {
      final content = _longContent();
      final cancelToken = CancelToken();
      final verifyClient = _VerifyClient(
        () async => '[{"id":"h1","verdict":"confirmed"}]',
      );
      final records = <VerificationRecord>[];
      final gate = VerificationGate(
        keysLoader: () async => _fullKeys,
        clientFactory: (_) => verifyClient,
        sink: records.add,
      );

      // 主链在 merge 前就被取消 ⇒ runProgressiveDiagnosis 抛取消异常，
      // 不会走到验证层。这里断言「取消路径根本不到验证层」。
      cancelToken.cancel();
      await expectLater(
        runProgressiveDiagnosis(
          content: content,
          title: '接线测试',
          onContent: (_) {},
          llmClient: _ChainClient(),
          cancelToken: cancelToken,
          verificationGate: gate,
        ),
        throwsA(isA<ProgressiveDiagnosisCancelled>()),
      );

      expect(verifyClient.calls, 0);
      expect(records, isEmpty);
    });
  });

  group('V-1 ② 调用图断言：装配点唯一 · 两条链都接上', () {
    // 扫 lib/ 全部 dart 文件。★ 分母非空守卫：cwd 不对 / 目录缺失时 files=0，
    // 下面每条「不存在」断言都会退化成恒真空集（本仓已踩过这个坑）。
    ({
      int files,
      List<String> defined,
      List<String> called,
      List<String> legacy,
    })
    scan() {
      var files = 0;
      final defined = <String>[];
      final called = <String>[];
      final legacy = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        files++;
        final rel = e.path.replaceAll('\\', '/'); // Windows 路径归一
        final src = e.readAsStringSync();
        if (src.contains('VerificationGate productionVerificationGate()')) {
          defined.add(rel);
        }
        if (src.contains('productionVerificationGate()')) called.add(rel);
        if (src.contains('VerificationGate.fromStorage')) legacy.add(rel);
      }
      return (files: files, defined: defined, called: called, legacy: legacy);
    }

    test('★#B4-1 装配入口唯一：定义恰 1 处 · 旧 fromStorage 已消失', () {
      final r = scan();
      expect(r.files, greaterThan(100), reason: '扫描分母必须非空，否则本条恒真');
      expect(r.defined, [
        'lib/services/verification_gate.dart',
      ], reason: 'V-1：装配点须唯一落在 lib/services/ 侧；出现第二处即已分叉');
      expect(
        r.legacy,
        isEmpty,
        reason: '旧静态入口 fromStorage 不得复活——V-2「全集 ⇒ 出站恰 = 1」依赖单点装配',
      );
    });

    test('★#B4-2 两条链都以「传参」形态接上（不只是 import）', () {
      final r = scan();
      expect(r.called.length, 3, reason: '1 处定义 + 两条链各 1 处调用');
      for (final f in const [
        'lib/features/chat/chat_diagnosis_controller.dart',
        'lib/features/writing/writing_coach_panel_diagnosis_runner.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(
          src.contains('verificationGate: productionVerificationGate()'),
          isTrue,
          reason: '$f 必须把 gate 作为 runProgressiveDiagnosis 的参数传入',
        );
      }
    });

    test('★#B4-3 装配结果可用，且三键读取是惰性的（构造期不碰 storage）', () {
      // 若 keysLoader 在构造期就执行，test 环境无 platform channel ⇒ 会抛。
      // 能构造出来即证明读取是惰性闭包——这也是「未配置态不崩主链」的前提。
      final gate = productionVerificationGate();
      expect(gate.keysLoader, isNotNull);
      expect(gate.clientFactory, isNotNull);
    });
  });
}
