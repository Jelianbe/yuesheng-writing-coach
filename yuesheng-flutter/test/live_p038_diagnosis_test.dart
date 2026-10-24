// ─────────────────────────────────────────────────────────────
// P038 描写顺序失序 · 真实 LLM 判据验证
//
// 目标：回答「模型能不能真识别 P038（因果倒置 / 空间跳接），
//   且对合法的先整体后局部顺序不误报」。
//
// 设计（单变量对照，仿 live_llm_diagnosis_test）：
//   样本 A（有症状）与样本 B（干净）共用同一 focusSyndromeId=P038、
//   同一知识库、同一 prompt，唯一差异是投喂文本。
//   ⇒ A 须报出顺序问题；B 不得报 P038。
//
// 判据（P038 专属，比 P029 简单——顺序错乱可直接观察）：
//   样本 A（因果倒置）：输出须 articulating「果在前、因在后」或「顺序反了」
//     这一概念侧面（不要求词面命中 P038 编号）。
//   样本 B（先整体后局部）：输出不得声称这是「顺序/因果错乱」类问题
//     （允许给通用建议，但不得报 P038）。
//
// 运行（key 只经环境变量，R-029）：
//   $env:DEEPSEEK_API_KEY="sk-xxx"
//   flutter test --tags "live,external" test/live_p038_diagnosis_test.dart
// ─────────────────────────────────────────────────────────────

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_retry.dart';
import 'package:writingcoach/services/llm_usage_monitor.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';

const String _kFocusId = 'P038';

const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 教练前置（与生产 message_injector 等价）。
const String _kPreamble =
    '你是一名写作教练。学员给你看一段他新写的小说文字，请你做诊断，'
    '不要替学员改写句子、不要替他做决定。'
    '请指出这段文字里最核心的一个写作问题：必须点到具体位置（引用原文里的词或句），'
    '并说明这个问题为什么是问题、它伤害了读者的什么阅读体验。一次只聚焦一个最主要的点。';

/// P038 概念侧面（面①：因果倒置；面②：空间跳接无动线）。
/// 来源：syndrome_kb_content_manual_6.dart P038 段 + few-shot。
/// ⚠️ 只收「**问题信号**」词，不收中性词（如「顺序」「空间」）——
///   后者在合法描述（「空间顺序清晰」）里也出现，会系统性误报。
const List<String> _kFacetCausal = [
  '反了',
  '倒了',
  '颠倒',
  '倒置',
  '结果在前',
  '原因在后',
  '先后',
  '前因后果',
  '先因后果',
];

const List<String> _kFacetSpatial = ['跳接', '没有过渡', '缺过渡', '无过渡', '动线', '远近'];

/// 单样本配置。
class _Case {
  final String id;
  final String name;
  final String probe;
  final List<String> planted;
  final List<String> facetA;
  final List<String> facetB;
  final String hitScript;
  final String missScript;
  const _Case({
    required this.id,
    required this.name,
    required this.probe,
    required this.planted,
    required this.facetA,
    required this.facetB,
    required this.hitScript,
    required this.missScript,
  });
}

final List<_Case> _cases = [
  _Case(
    id: 'A',
    name: '因果倒置样本（果在前、因在后）',
    probe:
        '林晚摔下了楼梯。她踩到了第三阶上那块松动的木板，'
        '木板翘起来的时候她正低头看手机，整个人失去了重心。',
    planted: ['林晚', '楼梯', '木板', '手机'],
    facetA: _kFacetCausal,
    facetB: _kFacetSpatial,
    // 行为级贴合：点出「摔下」在前、「踩到木板」在后，因果顺序反了。
    hitScript:
        '问题在因果顺序上。「林晚摔下了楼梯」是结果，却放在了最前面，'
        '原因「踩到松动的木板」到第二句才出现——先后颠倒了，'
        '读者先看到摔下去，再回头找为什么摔，得回看一遍才能拼出「先踩木板、后摔下去」。'
        '应该把踩到木板的动作放到摔下去之前。',
    // 旁路：只喊编号 + 词面复读，不 articulating 因果倒置的概念。
    missScript: '这段有问题，建议修改，加强逻辑。',
  ),
  _Case(
    id: 'B',
    name: '干净样本（先整体后局部的合法空间顺序）',
    probe:
        '雨后的小镇湿漉漉的。青石板路泛着水光，巷口那棵老槐树的叶子上还挂着水珠，'
        '水珠顺着叶尖滑落，滴进沈砚脚边的水洼里。',
    planted: ['小镇', '青石板', '老槐树', '沈砚', '水洼'],
    facetA: _kFacetCausal,
    facetB: _kFacetSpatial,
    // 行为级贴合：不报 P038（水珠从叶尖到水洼形成连续视线桥，无空间跳接）。
    hitScript:
        '这段的推进是清晰的：从雨后小镇的全景，到青石板路、老槐树的细节，'
        '再顺着水珠从叶尖滑落落到水洼——镜头是逐步收窄的，读者的视线跟着水珠移动。'
        '如果要再打磨，可以在水珠落进水洼后加一点涟漪的描写。',
    // 旁路：误报顺序错乱（把合法推进当成 P038）。
    missScript: '这段存在描写顺序失序，空间描写从远到近没有过渡，属于跳接。',
  ),
];

/// 判定输出是否命中 P038 的概念侧面。
bool _hitsFacet(String output, _Case c) =>
    c.facetA.any(output.contains) || c.facetB.any(output.contains);

/// 组装消息（与生产 _buildFocusSyndromeSection 等价）。
List<ChatMessage> _buildMessages(_Case c) {
  final msgs = <ChatMessage>[ChatMessage(role: 'system', content: _kPreamble)];
  final knowledge = getTrainingContent([_kFocusId]);
  if (knowledge.isNotEmpty) {
    msgs.add(ChatMessage(role: 'system', content: knowledge));
  }
  final few = getTrainingFewShot([_kFocusId]);
  if (few.isNotEmpty) {
    msgs.add(ChatMessage(role: 'system', content: few));
  }
  final l3 = getSyndromeContent([_kFocusId]);
  if (l3.isNotEmpty) {
    msgs.add(ChatMessage(role: 'system', content: l3));
  }
  final tech = getTechniquesBySyndrome([_kFocusId]);
  if (tech.isNotEmpty) {
    msgs.add(ChatMessage(role: 'system', content: tech));
  }
  msgs.add(
    ChatMessage(
      role: 'user',
      content:
          '这是我新写的一段：\n\n${c.probe}\n\n'
          '请诊断这段文字最核心的写作问题——必须点到具体位置（引用原文的词或句），'
          '并说明它为什么是问题。不要替我改写。',
    ),
  );
  return msgs;
}

/// 脚本化 Fake LLM：直接返回预置文本，无 key 无网络。
class _ScriptedFakeLlmClient extends LlmClient {
  final String content;
  _ScriptedFakeLlmClient(this.content);

  @override
  Future<ChatCompletionResult> chatCompletionWithMeta(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
    LlmRetryPolicy retryPolicy = LlmRetryPolicy.standard,
  }) async => ChatCompletionResult(content: content);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P038 判定器·常驻自检（无 key，FakeLlmClient）', () {
    test('注入面非空', () {
      expect(getTrainingContent([_kFocusId]), isNotEmpty);
      expect(getTrainingFewShot([_kFocusId]), isNotEmpty);
      expect(getSyndromeContent([_kFocusId]), isNotEmpty);
    });

    test('A：行为级贴合判真 / 词面复读判假', () async {
      final c = _cases.firstWhere((e) => e.id == 'A');
      final msgs = _buildMessages(c);
      final hit = await _ScriptedFakeLlmClient(
        c.hitScript,
      ).chatCompletionWithMeta(msgs);
      expect(
        _hitsFacet(hit.content, c),
        isTrue,
        reason: 'A 的 hitScript 应命中 P038 概念侧面',
      );
      final miss = await _ScriptedFakeLlmClient(
        c.missScript,
      ).chatCompletionWithMeta(msgs);
      expect(
        _hitsFacet(miss.content, c),
        isFalse,
        reason: 'A 的 missScript（只喊编号）不应命中概念侧面',
      );
    });

    test('B：不报 P038 判真 / 误报判假', () async {
      final c = _cases.firstWhere((e) => e.id == 'B');
      final msgs = _buildMessages(c);
      final hit = await _ScriptedFakeLlmClient(
        c.hitScript,
      ).chatCompletionWithMeta(msgs);
      // B 的 hitScript 不声称顺序错乱 ⇒ 不应命中 P038 侧面
      expect(
        _hitsFacet(hit.content, c),
        isFalse,
        reason: 'B 的 hitScript（合法推进）不应命中 P038 概念侧面',
      );
      final miss = await _ScriptedFakeLlmClient(
        c.missScript,
      ).chatCompletionWithMeta(msgs);
      expect(
        _hitsFacet(miss.content, c),
        isTrue,
        reason: 'B 的 missScript（误报顺序错乱）应命中 P038 侧面',
      );
    });
  });

  group('P038 真实 LLM 验证（DeepSeek，@live,external）', () {
    const prov = _Provider(
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-v4-flash',
      envKey: 'DEEPSEEK_API_KEY',
    );
    final hasKey = Platform.environment[prov.envKey]?.isNotEmpty ?? false;

    setUpAll(() {
      if (!hasKey) return;
      HttpOverrides.global =
          null; // flutter_test 默认把 HttpClient 换成「永远 400」的 mock
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
        if (call.method == 'check') return <String>['wifi'];
        return null;
      });
      final storage = <String, String>{};
      messenger.setMockMethodCallHandler(_kSecureStorageChannel, (call) async {
        final args = (call.arguments as Map?) ?? const {};
        switch (call.method) {
          case 'read':
            return storage[args['key']];
          case 'write':
            storage[args['key'] as String] = args['value'] as String;
            return true;
          case 'delete':
            storage.remove(args['key']);
            return true;
        }
        return null;
      });
    });

    tearDownAll(() {
      if (!hasKey) return;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_kConnectivityChannel, null);
      messenger.setMockMethodCallHandler(_kSecureStorageChannel, null);
    });

    for (final c in _cases) {
      test(
        '[${c.id}] ${c.name}：3 票 ≥2 票行为级通过',
        () async {
          if (!hasKey) {
            markTestSkipped('未设置 ${prov.envKey}，跳过真实链路');
            return;
          }
          await _runLiveVotes(c, prov);
        },
        tags: const ['live', 'external'],
        timeout: const Timeout(Duration(seconds: 300)),
      );
    }
  });
}

/// 跑 3 票真实调用并断言 ≥2 票行为级通过。
Future<void> _runLiveVotes(_Case c, _Provider prov) async {
  final key = Platform.environment[prov.envKey]!;
  final cfg = LlmConfigValues(
    apiKey: key,
    baseUrl: prov.baseUrl,
    model: prov.model,
  );
  final monitor = LlmUsageMonitor();
  final client = LlmClient(
    null,
    null,
    () async => cfg,
    null,
    LlmConcurrencyGate(),
    monitor.sink,
  );

  var passes = 0;
  for (var v = 1; v <= 3; v++) {
    final msgs = _buildMessages(c);
    final res = await client.chatCompletionWithMeta(msgs);
    final hit = _hitsFacet(res.content, c);
    final ok = c.id == 'A' ? hit : !hit;
    passes += ok ? 1 : 0;
    print(
      '[${c.id}][票$v] ok=$ok hit=$hit '
      'finish=${res.finishReason} len=${res.content.length}',
    );
    print('  输出: ${res.content.trim()}');
  }
  print('[${c.id}] 累计用量: ${monitor.totals}');
  expect(passes >= 2, isTrue, reason: '${c.id} 3 票需 ≥2 票行为级通过，实际 $passes/3');
}

class _Provider {
  final String label;
  final String baseUrl;
  final String model;
  final String envKey;
  const _Provider({
    required this.label,
    required this.baseUrl,
    required this.model,
    required this.envKey,
  });
}
