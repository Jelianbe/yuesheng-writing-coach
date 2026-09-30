// coach_polish_real_network_test — 模拟器真机网络验证（AI 润色）
//
// 目的：在真机/模拟器上，用 app 真实的 LlmClient（与生产 _polish 同一调用
// chatCompletion([system, user], maxTokens:300)）打真实 DeepSeek，验证：
//   1. app 在 Android 包内（已声明 INTERNET 权限）能出网；
//   2. 真实 Key 经 --dart-define=YS_TEST_KEY=... 注入后，DeepSeek 返回有效
//      润色文本；
//   3. 不落入「免费测试模式」占位（即 config 真的解析成功、网络真通）。
//
// Key 纪律：不得写入源码/仓库；仅经 --dart-define=YS_TEST_KEY=... 注入。
// 复刻 coach_selector_card.dart 的 _kCoachPolishSystemPrompt（必须逐字一致）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';

// 必须与 lib/features/app_settings/coach_selector_card.dart 的
// _kCoachPolishSystemPrompt 逐字一致（2026-09-28 引入）。
const String _kCoachPolishSystemPrompt = '''
你正在帮一位写作者配置「自定义写作教练」的语气设定。
用户会给你：教练的名字（可能为空），以及他随手写的几句语气想法（可能为空）。
请据此生成一段精炼、生动、可直接用作「教练语气设定」的中文描述（1-3 句）。
要求：
- 只描述「这位教练该怎么说话、带什么腔调」，不要写教学动作或诊断流程；
- 口语化、有画面感，避免「专业」「优秀」「有耐心」这类空泛词；
- 只输出描述本身，不要引号、不要前缀、不要解释。
''';

String _buildUser(String name, String tone) => [
  '教练名字：${name.isEmpty ? '（未填写）' : name}',
  '用户当前填写的语气想法：${tone.isEmpty ? '（未填写）' : tone}',
].join('\n');

void main() {
  final key = const String.fromEnvironment('YS_TEST_KEY');

  testWidgets('on-device AI polish: real DeepSeek call for 3 personas', (
    tester,
  ) async {
    expect(key, isNotEmpty, reason: '必须传 --dart-define=YS_TEST_KEY=<真实Key>');

    final cfg = LlmConfigValues(
      apiKey: key,
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-chat',
    );

    // 与生产 llmClientProvider 同构：LlmClient(null, null, loader, ...)。
    // 不传 usageSink ⇒ 走默认 kSharedLlmUsageMonitor（其落库失败被 _reportUsage
    // 静默吞掉，不影响本次断言）。
    final client = LlmClient(null, null, () async => cfg);

    final cases = <String, (String, String)>{
      'girl': ('小桃', '可爱活泼，像二次元少女'),
      'old_man': ('老周头', '胡同里唠嗑的大爷，爱讲当年手写稿的苦'),
      'chinese_teacher': ('王老师', '严谨的语文老师，爱抠字眼'),
    };

    for (final entry in cases.entries) {
      final (name, tone) = entry.value;
      final result = await client.chatCompletion([
        const ChatMessage(role: 'system', content: _kCoachPolishSystemPrompt),
        ChatMessage(role: 'user', content: _buildUser(name, tone)),
      ], maxTokens: 300);

      debugPrint('POLISH[${entry.key}] name=$name => $result');

      expect(result, isNotEmpty, reason: '${entry.key} 润色返回为空');
      expect(
        result,
        isNot(contains('免费测试模式')),
        reason: '${entry.key} 落入免费测试占位，说明 config 未生效',
      );
      expect(result.length, greaterThan(10), reason: '${entry.key} 返回过短，疑似异常');
    }
  });
}
