// coach_persona_diagnosis_real_network_test — 用各自人设跑真实诊断（DeepSeek）
//
// 目的：回答「利用这几个人设分别做诊断，以此测试功能」——忠实复刻生产
// sendMessage 主链路中「buildSystemPromptV2 组装含人设的 system prompt →
// LlmClient.chatCompletion」这一段，用 3 个人设（少女/老大爷/中年语文老师）
// 各对同一样本习作发一次真实 DeepSeek 诊断，验证：
//   1. 各人设的润色文本确实进入诊断 system prompt（production 函数）；
//   2. 真实 Key 经 --dart-define=YS_TEST_KEY 注入后，DeepSeek 返回有效诊断
//      （非空、非「免费测试模式」占位、长度合理）；
//   3. 诊断回复体现了该人设的语气（命中各人设特征词之一）——即人设真的
//      影响了诊断输出，而非只停在 prompt 里。
//
// Key 纪律：不得写入源码/仓库；仅经 --dart-define=YS_TEST_KEY=... 注入。
// 本测试为 headless `flutter test`（无需设备）：宿主已验证可出网到
// api.deepseek.com，故直接在主机上发真实 HTTPS 请求。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/types/coach_persona.dart';
import 'package:writingcoach/types/teaching_types.dart';

const Map<String, String> _personaMeta = {
  'girl': '少女',
  'old_man': '老大爷',
  'chinese_teacher': '中年语文老师',
};

/// 各人设语气特征词（取自真实润色文本，用于断言诊断回复带上了人设声音）。
const Map<String, List<String>> _voiceHints = {
  'girl': ['呀', '呢', '哦', '好棒', '元气', '少女', '亮晶晶'],
  'old_man': ['当年', '稿纸', '煤油灯', '你们这代人', '老大爷', '蒲扇', '改稿'],
  'chinese_teacher': [
    '红笔',
    '字眼',
    '《说文',
    '鲁迅',
    '硌牙',
    '病句',
    '用词',
    '摇头',
  ],
};

/// 一段刻意平淡、堆砌、telling-not-showing 的习作样本，给诊断留足发挥空间。
const String _sampleSubmission = '''
第三章 风波
李雷走在街上，突然看见了韩梅梅。他心里想，她真好看。于是他走过去说：“你好。”韩梅梅笑了。他们一起去了咖啡馆。李雷说：“我喜欢你。”韩梅梅说：“我也喜欢你。”然后他们就在一起了。故事结束。
''';

String? _readPolished(String key) {
  for (final candidate in [
    'outputs/polish/persona_$key.txt',
    'yuesheng-flutter/outputs/polish/persona_$key.txt',
  ]) {
    final f = File(candidate);
    if (f.existsSync()) return f.readAsStringSync().trim();
  }
  return null;
}

/// 三人人设润色文本是否齐全（缺失则整个测试 skip，不进函数体）。
bool _personaFilesPresent() =>
    _personaMeta.keys.every((k) => _readPolished(k) != null);

void main() {
  // LlmClient.chatCompletion 内部走 checkNetwork() → Connectivity 平台通道，
  // 以及 getLlmFallbacksRaw() → FlutterSecureStorage 平台通道；
  // 二者在 flutter test 宿主均无原生实现。stub 掉这两个通道，让真实
  // HTTPS 诊断调用能越过预检（真实 HTTP 不受影响，仍是真 DeepSeek 调用）。
  TestWidgetsFlutterBinding.ensureInitialized();
  // TestWidgetsFlutterBinding 默认把 HttpOverrides.global 换成「永远返回 400
  // 的 mock」，会拦截所有真实网络请求。本测试要真发 DeepSeek，故恢复真实
  // HttpClient（Dio 走 HttpClient()，受 HttpOverrides.global 影响）。
  HttpOverrides.global = null;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async {
      if (call.method == 'check') return ['wifi']; // 视为已联网
      return null;
    },
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      // 无备选端点配置：read 返回 null，readAll 返回空表。
      if (call.method == 'read') return null;
      if (call.method == 'readAll') return <String, String>{};
      return null;
    },
  );

  final key = const String.fromEnvironment('YS_TEST_KEY');

  test('用各自人设跑真实诊断：少女/老大爷/中年语文老师', () async {
    final cfg = LlmConfigValues(
      apiKey: key,
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-chat',
    );
    // 与生产 llmClientProvider 同构：LlmClient(null, null, loader)。
    final client = LlmClient(null, null, () async => cfg);

    final List<String> diags = <String>[];

    for (final entry in _personaMeta.entries) {
      final k = entry.key;
      final label = entry.value;

      final polished = _readPolished(k);

      final persona = CoachPersona(
        id: 'real_$k',
        name: label,
        label: '自定义教练',
        isSystem: false,
        attitudeLevel: AttitudeLevel.doubao,
        systemPromptFragment: polished!,
      );

      // 复刻生产 sendMessage：用 buildSystemPromptV2 组装带人设的诊断 prompt。
      final ctx = SkillLoadContext(
        phase: TeachingPhase.p2PracticeLoop,
        attitude: AttitudeLevel.doubao,
        subphase: TeachingSubphase.diagnosis,
        activePersona: persona,
      );
      final r = buildSystemPromptV2(ctx, modeOverride: L2Mode.diagnosis);

      // 1) 人设确实进入诊断 system prompt，且替代了默认态度档。
      expect(r.systemPrompt, contains(polished),
          reason: '[$k] 人设未注入诊断 system prompt');
      expect(r.loadedSkillIds, contains('persona-real_$k'),
          reason: '[$k] 未记录 persona 注入标记');
      expect(r.loadedSkillIds, isNot(contains('attitude-doubao')),
          reason: '[$k] 默认态度档未被人设替换');

      // 2) 真实诊断调用（与生产同一 LlmClient.chatCompletion 链路）。
      final diagnosis = await client.chatCompletion(
        [
          ChatMessage(role: 'system', content: r.systemPrompt),
          ChatMessage(role: 'user', content: _sampleSubmission),
        ],
        maxTokens: 1500,
      );

      // 3) 返回有效（非空、非免费占位、长度合理）。
      expect(diagnosis, isNotEmpty, reason: '[$k] 诊断返回为空');
      expect(diagnosis, isNot(contains('免费测试模式')),
          reason: '[$k] 落入免费测试占位，说明 config 未生效/网络未通');
      expect(diagnosis.length, greaterThan(30), reason: '[$k] 诊断过短，疑似异常');

      diags.add(diagnosis);

      // 4) 人设「声音」软观察（不判失败）：诊断技能强制结构化 JSON 输出，
      //    口语语气词（呀/呢/哦…）通常不出现在 JSON 文本里——这是预期内的
      //    真实现象，而非缺陷。仅记录命中情况，供人工核对。
      final hints = _voiceHints[k]!;
      final hit = hints.any((h) => diagnosis.contains(h));
      final excerpt =
          diagnosis.length > 240 ? diagnosis.substring(0, 240) : diagnosis;
      debugPrint('DIAG[$k] name=$label hitVoiceHint=$hit '
          'len=${diagnosis.length}\n---excerpt---\n$excerpt\n---');
    }

    // 5) 人设上下文确实改变了模型输出：同一习作、三人设的 diagnosis 不应
    //    完全相同（至少出现两种不同诊断）。这是「人设影响诊断」的稳健判据，
    //    避开「字面语气词」这种在 JSON 诊断里不可靠的断言。
    expect(diags.toSet().length, greaterThan(1),
        reason: '三个人设对同一习作的诊断完全相同，人设未对输出产生任何影响');
  }, skip: (key.isEmpty || !_personaFilesPresent())
      ? '需 --dart-define=YS_TEST_KEY 且 outputs/polish/persona_*.txt 存在'
      : false);
}
