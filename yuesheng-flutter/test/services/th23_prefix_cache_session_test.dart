// ─────────────────────────────────────────────────────────────
// TH-2③ 会话内重复诊断 · 前缀缓存采样装置（T-20261016-02 · N=5 两臂 + 恢复探测）
//
// 背景：TH-2 批实测「会话内重复诊断 cached=0」仅 n=1（LEDGER :673 明文
//   「n=1 不作结论」）。本装置多次采样确证 + 机制归因。
//
// 设计（三段，全部生产装配形态，模型/档位与 p029 live 组同源）：
//   臂 A · 字节恒定臂（N=5）：同一份 messages 对象连发 5 次 ——
//         唯一测量「供应商侧前缀缓存」对逐字节相同前缀的行为（上界基线）。
//   臂 B · 画像段漂移臂（N=5）：每轮在 system 首段**尾部**追加一行画像
//         增量（模拟 §4-78 学员画像段跨轮单调增长的已知形态）——
//         前缀**首段**字节漂移 ⇒ 预期整前缀缓存失效（cached≈0）。
//   臂 C · 恢复探测（1 次）：与臂 B 第 5 轮**逐字节相同**再发一次 ——
//         若缓存命中 ⇒ 恢复形态 =「前缀稳定后即刻恢复」。
//
// 判定口径（对应验收三选一）：
//   · 臂 A 命中 + 臂 B 全脱 ⇒「打破」成立且机制 = system 首段漂移；
//   · 臂 A 不命中 ⇒ 供应商缓存本身不可依赖（与装置无关）；
//   · 臂 B 命中 ⇒ TH-2 的 cached=0 另有他因（登记待查）。
//
// 性质：**测量器，不是阈值门**（与 reshell live 组同纪律，判读以报告为准）。
// 纪律：Key 只经环境变量 DEEPSEEK_API_KEY（R-029）；纯测试层零 lib/ 改动（R-010）；
//       控制台不打印 key；usage 观测经自定义 sink（record 永不抛，旁路纪律）。
//
// 运行：
//   DEEPSEEK_API_KEY=sk-xxx flutter test test/services/th23_prefix_cache_session_test.dart \
//     --tags live,external
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/reasoning_tier.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_usage.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';
import 'package:writingcoach/types/teaching_types.dart';

import '../../integration_test/d5_sample_texts.dart';

const String _kFocusId = 'P001';
const int _kRounds = 5;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 默认把 HttpClient 换成「永远 400」（p029 live 组同款处置）
  // ⇒ 清掉它，真实 HTTP 才能出网。
  HttpOverrides.global = null;
  // connectivity_plus 通道 mock（p029 live 组同款：llm_config_storage 首查网络态）。
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? <String>['wifi'] : null,
      );
  // flutter_secure_storage 通道 mock（p029 live 组同款：内存字典替身）。
  final storage = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          final args = (call.arguments as Map?) ?? const <String, String>{};
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
        },
      );

  test(
    'TH-2③ 会话内重复诊断前缀缓存采样（臂A恒定×5 + 臂B画像漂移×5 + 臂C恢复×1）',
    () async {
      final key = Platform.environment['DEEPSEEK_API_KEY'];
      if (key == null || key.isEmpty) {
        markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
        return;
      }

      final content = kD5Samples.firstWhere((D5Sample s) => s.id == 'X11').text;
      final cfg = LlmConfigValues(
        apiKey: key,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        // 档位 off：与 p029 live 组同源（诊断任务零退化实测背书，见其头注）。
        reasoningTier: reasoningTierOff,
      );

      // ── 逐调用 usage 捕获（顺序 = 发起顺序；record 永不抛）──
      final usageLog = <LlmUsage>[];
      void sink(LlmUsage usage, LlmUsageKind kind) {
        usageLog.add(usage);
      }

      final client = LlmClient(
        null,
        null,
        () async => cfg,
        null,
        LlmConcurrencyGate(),
        sink,
      );

      String bodyHash(List<ChatMessage> msgs) => crypto.md5
          .convert(
            utf8.encode(
              msgs.map((m) => '${m.role}:${m.content}').join('\u0001'),
            ),
          )
          .toString();

      // 臂 A：字节恒定（同一对象连发）
      final armA = _buildMessages(content);
      final hashA = bodyHash(armA);
      // ignore: avoid_print
      print('[臂A] system len=${armA.first.content.length} md5=$hashA');
      for (var i = 1; i <= _kRounds; i++) {
        final before = usageLog.length;
        final res = await client.chatCompletionWithMeta(armA);
        final u = usageLog.length > before ? usageLog.last : null;
        // ignore: avoid_print
        print(
          '[臂A][轮$i] valid=${res.content.trim().isNotEmpty} '
          'prompt=${u?.promptTokens} cached=${u?.cachedTokens} '
          'miss=${u == null ? '?' : u.promptTokens - u.cachedTokens} '
          'hitRate=${u == null || u.promptTokens == 0 ? '?' : (100 * u.cachedTokens / u.promptTokens).toStringAsFixed(1)}%',
        );
      }

      // 臂 B：画像段漂移（首段尾部每轮追加一行增量）
      for (var i = 1; i <= _kRounds; i++) {
        final msgs = _buildMessages(
          content,
          profileDrift: '学员画像增量（第$i轮）：本章写作时长 ${40 + i} 分钟，修改 2 处。',
        );
        final hash = bodyHash(msgs);
        final before = usageLog.length;
        final res = await client.chatCompletionWithMeta(msgs);
        final u = usageLog.length > before ? usageLog.last : null;
        // ignore: avoid_print
        print(
          '[臂B][轮$i] md5=$hash valid=${res.content.trim().isNotEmpty} '
          'prompt=${u?.promptTokens} cached=${u?.cachedTokens} '
          'miss=${u == null ? '?' : u.promptTokens - u.cachedTokens} '
          'hitRate=${u == null || u.promptTokens == 0 ? '?' : (100 * u.cachedTokens / u.promptTokens).toStringAsFixed(1)}%',
        );
      }

      // 臂 C：恢复探测（与臂 B 第 5 轮逐字节相同）
      final armC = _buildMessages(
        content,
        profileDrift: '学员画像增量（第$_kRounds轮）：本章写作时长 ${40 + _kRounds} 分钟，修改 2 处。',
      );
      // ignore: avoid_print
      print('[臂C] md5=${bodyHash(armC)}（应与臂B轮5相同）');
      final beforeC = usageLog.length;
      final resC = await client.chatCompletionWithMeta(armC);
      final uC = usageLog.length > beforeC ? usageLog.last : null;
      // ignore: avoid_print
      print(
        '[臂C] valid=${resC.content.trim().isNotEmpty} '
        'prompt=${uC?.promptTokens} cached=${uC?.cachedTokens} '
        'miss=${uC == null ? '?' : uC.promptTokens - uC.cachedTokens} '
        'hitRate=${uC == null || uC.promptTokens == 0 ? '?' : (100 * uC.cachedTokens / uC.promptTokens).toStringAsFixed(1)}%',
      );
    },
    tags: const ['live', 'external'],
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

/// 生产装配形态消息（与 p029 负样本 live 组 `_buildMessages` production 臂同构：
/// buildSystemPromptV2 完整装配 + 知识四块 + 用户消息；focus 换 P001）。
///
/// [profileDrift] 非空时追加到 system 首段**尾部**（模拟 §4-78 画像段跨轮增长）。
List<ChatMessage> _buildMessages(String content, {String? profileDrift}) {
  final system = buildSystemPromptV2(
    const SkillLoadContext(
      phase: TeachingPhase.p2PracticeLoop,
      attitude: AttitudeLevel.yuesheng,
      subphase: TeachingSubphase.diagnosis,
    ),
  ).systemPrompt;
  final msgs = <ChatMessage>[
    ChatMessage(
      role: 'system',
      content: profileDrift == null ? system : '$system\n$profileDrift',
    ),
  ];
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
      content: '以下是本章正文，请按诊断协议输出 JSON 诊断结果：\n\n$content',
    ),
  );
  return msgs;
}
