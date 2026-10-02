// ─────────────────────────────────────────────────────────────
// ADR-C136 项 2：few-shot P029–P033 引用质量「真实 LLM 回放」验证
//
// 目标：受控候选集「含 vs 不含 few-shot 示例块」的同一文本两问对照。
//   断言：注入 few-shot 示例块时，真实 LLM 输出在「行为级」上引用/贴合
//   对应症候概念——即（a）点到新样本文本的具体位置（引用我种入的专名/物件，
//   证明它真读了我的样本而非复读示例块），且（b） articulating 出该症候的
//   两个概念侧面。剔除词面相似旁路：只复读症候名/关键词、不落到具体位置与
//   概念的输出，判为不命中。
//
// 方法真源：.ai/reports/2026-09-30-14条行为级复验.md
//   （受控候选集 + 吸收方样本对照 + 3 票制 + 探针必须能红能绿）。
//
// 注入点（照生产 message_injector._injectTrainingKnowledge:1957-1965）：
//   含块 arm  = preamble + getTrainingContent([X]) + getTrainingFewShot([X])
//   不含 arm  = preamble + getTrainingContent([X])                 ← 唯一差异
//   （few-shot 生产上紧跟 L3 知识库之后追加；本测试隔离这一条 system 消息。）
//
// 双组结构（仿 live_interface_comparison_test）：
//   1) 常驻自检组（无 tag，门禁全量必跑）：_ScriptedFakeLlmClient 喂「贴合概念」
//      与「仅词面复读」两类脚本输出，跑与 live 组完全相同的判定器，证明判真/
//      剔假都自洽、无 key 可跑；同时断言含/不含两条消息分支确实切换。
//   2) live 组（per-test tags: ['live','external']）：真实 DeepSeek。
//      无 DEEPSEEK_API_KEY 时每个 test 内 markTestSkipped，不破门禁全量。
//
// 费用护栏（ADR §4：few-shot ≤24 次真实调用）：
//   5 症候 ×（含块 3 票 + 不含对照 1 票）= 20 次计划内调用；
//   测试侧硬上限 24，达到立即 fail（瞬时报错内部重试最多 2 次退避，也计数）。
//
// 运行真实回放（key 只经环境变量，严禁写入源码）：
//   $env:DEEPSEEK_API_KEY="sk-xxx"
//   flutter test --tags "live,external" test/live_fewshot_replay_test.dart
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
import 'package:writingcoach/services/training_few_shot_library.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';

const String _kBaseUrl = 'https://api.deepseek.com';
const String _kModel = 'deepseek-v4-flash';

/// 真实调用硬上限（ADR-C136 §4：few-shot 面 ≤24 次）
const int _kMaxRealCalls = 24;

const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 共享教练前置（两 arm 完全一致，唯一变量是 few-shot 消息）。
/// R-009：诊断指向根因、不替写、不替决定。
const String _kCoachPreamble =
    '你是一名写作教练。学员给你看一段他新写的小说文字，请你做诊断，'
    '不要替学员改写句子、不要替他做决定。'
    '请指出这段文字里最核心的一个写作问题：必须点到具体位置（引用原文里的词或句），'
    '并说明这个问题为什么是问题、它伤害了读者的什么阅读体验。一次只聚焦一个最主要的点。';

/// 单症候回放配置。
///
/// [probe]       全新样本文本（吸收方样本）——刻意不与 few-shot 示例块原文重合，
///               用以检验「概念迁移」而非词面复读。
/// [planted]     我在 probe 里种入的专名/物件（示例块中不出现）。输出须命中 ≥1，
///               证明模型真读了我的样本、而非背诵示例块。
/// [conceptA]    症候概念侧面 A（输出须命中 ≥1）。
/// [conceptB]    症候概念侧面 B（输出须命中 ≥1）。
/// [hitScript]   自检用：行为级贴合输出（判定器应判真）。
/// [bypassScript]自检用：仅词面复读输出（判定器应判假）。
class _Case {
  final String id;
  final String name;
  final String probe;
  final List<String> planted;
  final List<String> conceptA;
  final List<String> conceptB;
  final String hitScript;
  final String bypassScript;
  const _Case({
    required this.id,
    required this.name,
    required this.probe,
    required this.planted,
    required this.conceptA,
    required this.conceptB,
    required this.hitScript,
    required this.bypassScript,
  });
}

const List<_Case> _cases = [
  _Case(
    id: 'P029',
    name: '降智反派症',
    probe:
        '漕帮孙舵主在城里经营二十年，手里捏着小伙计陈七欠下的三千两赌据，'
        '陈七的堂兄还在县衙当差。大堂之上，陈七只低着头嘟囔了一句「老泥鳅」。'
        '孙舵主当场翻了脸，一拍桌子站起来：「来人，把这小子给我沉到江里去！」',
    planted: ['孙舵主', '陈七', '老泥鳅', '赌据'],
    conceptA: ['捏着', '手里', '当差', '赌据', '三千两', '慢慢', '拿捏'],
    conceptB: ['一句', '嘟囔', '老泥鳅', '拍', '沉', '翻脸', '亲自', '犯不上'],
    hitScript:
        '这段的问题在孙舵主身上。他明明手里捏着陈七的赌据、堂兄又在县衙当差，'
        '本可以慢慢拿捏，却因为陈七一句嘟囔「老泥鳅」就拍桌叫人把他沉江——'
        '反派放着现成优势不用，被一句轻慢就亲自翻脸下场，动机立不住。',
    bypassScript: '这段存在降智反派问题，反派写得不够聪明，需要改进，整体反派塑造失败。',
  ),
  _Case(
    id: 'P030',
    name: '声线漂移症',
    probe:
        '赵铁衣翻过三丈高墙，刀出鞘时寒芒破空。月色如练，伏尸满地，她刀下从无冤魂。\n'
        '她落地时脚一崴，一屁股坐在巷口，揉着脚踝直吸凉气：'
        '妈呀妈呀，这墙也太高了吧，摔得我屁股都快开花了，早知道就不去追那个飞贼了。',
    planted: ['赵铁衣', '飞贼', '高墙', '屁股'],
    conceptA: ['声线', '腔调', '口吻', '判若两人', '不像同一个', '叙述'],
    conceptB: ['突然', '前文', '后段', '前段', '过渡', '判若', '口语', '碎嘴'],
    hitScript:
        '问题在两段之间的声线：前一段写赵铁衣翻高墙、刀出鞘，用的是四字句冷峻腔；'
        '落地后突然变成「妈呀妈呀」的口语碎嘴——同一个叙述者，腔调前后判若两人，'
        '没有任何过渡，读者辨不出是谁在讲。',
    bypassScript: '这段存在声线漂移问题，文风前后不一致，需要注意。',
  ),
  _Case(
    id: 'P031',
    name: '题材边界感缺失症',
    probe:
        '第一章：银河联邦的战列舰「苍狼号」跃迁到未知星域，舰长老周下令全舰警戒。'
        '镜头一转，紫禁城里雍正爷正在翻牌子，晋贵人的安胎药里被人下了红花。'
        '再一转，高二女生林小满月考后被同桌塞了一张奶茶店优惠券，脸一下子红到耳根。',
    planted: ['苍狼号', '晋贵人', '林小满', '红花'],
    conceptA: ['赛道', '类型', '题材', '读者', '哪一类', '定位', '追的'],
    conceptB: ['拼贴', '杂糅', '一会儿', '一转', '元素', '混乱', '内核', '纲领'],
    hitScript:
        '问题是赛道定位失焦：这一段把星际战舰（苍狼号）、清宫宅斗（晋贵人被下红花）、'
        '校园甜宠（林小满收优惠券）三个完全不同的类型一会儿一转地拼贴在一起，'
        '没有统一的类型内核，读者读不出自己在追哪一类。',
    bypassScript: '这段存在题材边界感问题，元素比较杂，需要统一风格。',
  ),
  _Case(
    id: 'P032',
    name: '翻译腔/外来语干扰症',
    probe:
        '对于那个曾经在三年前冬天被老陈所救下的、如今在镇上当小学老师的姑娘来说，'
        '村口那间被雨水泡塌了一半的老屋，是一个重要的、在她最害怕的时候给过她庇护的存在。'
        '不容忽视的是，这种庇护并不是可以被轻易地估价的。',
    planted: ['老陈', '姑娘', '老屋', '小学老师'],
    conceptA: ['定语', '的字', '修饰语', '太长', '前置', '拆'],
    conceptB: ['对于', '来说', '翻译腔', '机翻', '语序', '抽象', '不像中文'],
    hitScript:
        '问题在句法：「那个被老陈所救下的、如今当小学老师的姑娘」一长串定语全压在主语前面，'
        '加上「对于……来说」「被……所」「这种庇护是可以被估价的」这类框式和抽象名词句首，像机翻。'
        '应该把长定语拆开，顺着时间流后置，让主语落地成人和动作。',
    bypassScript: '这段有翻译腔问题，句子不够通顺，需要修改。',
  ),
  _Case(
    id: 'P033',
    name: '冲突未升级/模式重复症',
    probe:
        '第一场：周小满夜里听见院门响，握紧手电——拉开门，是隔壁阿婆走错了门。虚惊一场。\n'
        '第二场：她起夜看见窗帘后立着个人影，抄起扫帚——拉开窗帘，是挂着的风衣。又是虚惊。\n'
        '第三场：半夜床下传来抓挠声，她壮着胆子掀开床单——是自家那只橘猫。还是虚惊。',
    planted: ['周小满', '阿婆', '橘猫', '风衣'],
    conceptA: ['重复', '雷同', '一样', '套路', '模式', '三场', '结构'],
    conceptB: ['升级', '递进', '量级', '维度', '还是', '只是', '紧张不起来'],
    hitScript:
        '问题是三场戏结构完全重复：周小满听见响动——紧张——拉开一看是阿婆/风衣/橘猫，'
        '连续三场都是「异常→虚惊」同一个套路，威胁量级没有升级、也不换维度，'
        '读者第二次就摸清了，第三次已经紧张不起来。',
    bypassScript: '这段存在冲突未升级问题，情节重复，需要改进。',
  ),
];

/// 判定器：行为级命中 ⇔ 命中 ≥1 个样本专名（真读了我的样本）
///   且 命中 ≥1 个概念侧面 A 且 ≥1 个概念侧面 B。
/// 只复读症候名/关键词、不落到具体位置与概念 → 任一条件不满足即判假（剔除词面旁路）。
bool _isBehavioralHit(String output, _Case c) {
  final sampleRef = c.planted.any(output.contains);
  final facetA = c.conceptA.any(output.contains);
  final facetB = c.conceptB.any(output.contains);
  return sampleRef && facetA && facetB;
}

/// 组装两 arm 的消息。唯一差异：含块 arm 在 L3 知识库之后追加 few-shot 示例块。
List<ChatMessage> _buildMessages(_Case c, {required bool withBlock}) {
  final msgs = <ChatMessage>[
    ChatMessage(role: 'system', content: _kCoachPreamble),
  ];
  final knowledge = getTrainingContent([c.id]);
  if (knowledge.isNotEmpty) {
    msgs.add(ChatMessage(role: 'system', content: knowledge));
  }
  if (withBlock) {
    final few = getTrainingFewShot([c.id]);
    if (few.isNotEmpty) {
      msgs.add(ChatMessage(role: 'system', content: few));
    }
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

/// 脚本化 Fake LLM：覆写 chatCompletionWithMeta 直接返回预置文本。
/// 无 key、无网络、无配置依赖。
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
  }) async {
    return ChatCompletionResult(content: content);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bool hasKey = Platform.environment.containsKey('DEEPSEEK_API_KEY');

  // ── 常驻自检组（无 tag，门禁全量必跑，无 key 可跑）──
  group('few-shot 回放·常驻自检（FakeLlmClient：判定器能红能绿 + 含/不含切换）', () {
    for (final c in _cases) {
      test('[${c.id}] ${c.name}：行为级判真 / 词面复读判假 / 消息分支正确', () async {
        // 含块 arm 必须注入 few-shot 示例块
        final withMsgs = _buildMessages(c, withBlock: true);
        expect(
          getTrainingFewShot([c.id]),
          isNotEmpty,
          reason: '${c.id} few-shot 库应非空',
        );
        expect(
          withMsgs.any((m) => m.content.contains('教学示例参考')),
          isTrue,
          reason: '${c.id} 含块 arm 应注入 few-shot 示例块',
        );
        // 不含块 arm 不得注入
        final withoutMsgs = _buildMessages(c, withBlock: false);
        expect(
          withoutMsgs.any((m) => m.content.contains('教学示例参考')),
          isFalse,
          reason: '${c.id} 不含块 arm 不得注入 few-shot 示例块',
        );
        // 行为级贴合 → 判真
        final hit = await _ScriptedFakeLlmClient(
          c.hitScript,
        ).chatCompletionWithMeta(withMsgs);
        expect(
          _isBehavioralHit(hit.content, c),
          isTrue,
          reason: '${c.id} 判定器应接受「点位置+概念」的行为级输出',
        );
        // 仅词面复读 → 判假
        final bypass = await _ScriptedFakeLlmClient(
          c.bypassScript,
        ).chatCompletionWithMeta(withoutMsgs);
        expect(
          _isBehavioralHit(bypass.content, c),
          isFalse,
          reason: '${c.id} 判定器应剔除「只复读关键词」的词面旁路输出',
        );
      });
    }
  });

  // ── live 组准备（仅在有 key 时恢复真实网络 + mock 平台通道）──
  setUpAll(() {
    if (!hasKey) return;
    HttpOverrides.global = null; // flutter_test 默认把 HttpClient 换成「永远 400」的 mock
    final key = Platform.environment['DEEPSEEK_API_KEY']!;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
    final storage = <String, String>{
      'yuesheng_api_key': key,
      'yuesheng_api_base_url': _kBaseUrl,
      'yuesheng_api_model': _kModel,
    };
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

  // 真实调用计数（费用护栏）。每次真实 HTTP 前自增；达上限即 fail。
  var realCalls = 0;

  Future<ChatCompletionResult> callWithBudget(
    LlmClient client,
    List<ChatMessage> messages,
  ) async {
    Object? lastErr;
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (realCalls >= _kMaxRealCalls) {
        fail('费用预算用尽：已 $realCalls 次真实调用 ≥ 上限 $_kMaxRealCalls，停止。');
      }
      try {
        realCalls++;
        // 首轮实测教训：推理型模型下 maxTokens=600 被 reasoning token 吃满、正文
        // 截断/空输出（finish=length）。修复：①maxTokens 提到 2000；②按生产既有
        // 字段（shared_constants 的 thinking:disabled）经 extraBody 关闭推理，把
        // reasoning_tokens 归零，省 token 且保证正文完整产出。
        return await client.chatCompletionWithMeta(
          messages,
          maxTokens: 2000,
          extraBody: const {
            'thinking': {'type': 'disabled'},
          },
        );
      } catch (e) {
        lastErr = e;
        final msg = e.toString();
        // 鉴权 / 内容类错误立即 fail；仅瞬时错误（网络/5xx/超时）退避重试。
        final fatal = RegExp(
          r'401|403|unauthorized|invalid.*key|鉴权|content.?filter|content_filter',
          caseSensitive: false,
        ).hasMatch(msg);
        if (fatal) {
          print('[护栏] 鉴权/内容类错误，立即停止: $msg');
          rethrow;
        }
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
      }
    }
    throw StateError('真实 LLM 调用重试已耗尽（瞬时错误 3 次均失败）: $lastErr');
  }

  // ── live 组（per-test tags，无 key 自动 skip）──
  group('few-shot 回放·真实 LLM（DeepSeek，@live,external）', () {
    for (final c in _cases) {
      test(
        '[${c.id}] ${c.name}：含示例块 3 票 ≥2 票行为级命中（+ 不含对照 1 票）',
        () async {
          if (!hasKey) {
            markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
            return;
          }
          final key = Platform.environment['DEEPSEEK_API_KEY']!;
          final cfg = LlmConfigValues(
            apiKey: key,
            baseUrl: _kBaseUrl,
            model: _kModel,
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

          // 含示例块：3 票，多数（≥2）判行为级命中才算过
          var hits = 0;
          for (var v = 1; v <= 3; v++) {
            final msgs = _buildMessages(c, withBlock: true);
            final res = await callWithBudget(client, msgs);
            final ok = _isBehavioralHit(res.content, c);
            hits += ok ? 1 : 0;
            print('[${c.id}][含·票$v] hit=$ok finish=${res.finishReason}');
            print('  输出: ${res.content.trim()}');
          }
          expect(
            hits >= 2,
            isTrue,
            reason: '${c.id} 含示例块 3 票需 ≥2 票行为级命中，实际 $hits/3',
          );

          // 不含示例块：1 票对照（仅打印证据，不对其做硬性断言）
          final ctrlMsgs = _buildMessages(c, withBlock: false);
          final ctrl = await callWithBudget(client, ctrlMsgs);
          print('[${c.id}][不含·对照] hit=${_isBehavioralHit(ctrl.content, c)}');
          print('  输出: ${ctrl.content.trim()}');

          print('[${c.id}] 累计用量: ${monitor.totals}');
        },
        tags: const ['live', 'external'],
        timeout: const Timeout(Duration(seconds: 240)),
      );
    }

    test('护栏收尾：真实调用计数留痕（≤ $_kMaxRealCalls）', () async {
      if (!hasKey) {
        markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
        return;
      }
      print('[护栏] 本批真实调用（测试侧计数）: $realCalls / 上限 $_kMaxRealCalls');
      expect(realCalls, lessThanOrEqualTo(_kMaxRealCalls));
    }, tags: const ['live', 'external']);
  });
}
