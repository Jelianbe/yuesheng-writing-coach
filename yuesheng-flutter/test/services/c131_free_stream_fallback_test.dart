// ─────────────────────────────────────────────────────────────
// C131 批「顺手清」：离线降级路径（无 Key）补测
//
// 依据：docs/2026-10-01-工作流链条审查报告.md §3.5 可测性表
//   「离线降级路径（无 Key）| 无覆盖 | —」
//
// 目标：llm_client.dart:539-544（streamChat 入口 _loadConfig 返回 null）
//   → _emitFreeTestStream（:634-652）：模拟流式回调，推送 3 段固定免费
//   教学文案分块 + 末尾 isDone=true。本测试如实断言：
//     1. 无 Key（cfg==null）时 streamChat 不发任何 HTTP 请求，走本地模拟
//     2. 3 段 content 分块顺序与文案与 _emitFreeTestStream 硬编码一致
//     3. 末尾恰好一次 isDone=true（content=''）
//     4. 全部分块不含诊断块结构（[YS_DIAGNOSIS]）——免费模式不伪造诊断
//
// 注入方式：LlmClient 第 3 位命名可选参数 _configLoader 直接返回 null，
//   完全绕过 secure_storage / connectivity 平台通道（比 mock channel 更
//   最小，不依赖 TestDefaultBinaryMessenger）。
//
// 边界（R-010）：纯测试层新增，不改任何 lib/ 产品代码。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/llm_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 与 llm_client.dart:639-643 _emitFreeTestStream 的 chunks 逐字对齐。
  const expectedChunks = <String>[
    '（免费测试模式）我现在处于离线示例模式。',
    '配置 API Key 后，我就能为你做真实的写作诊断与编辑观察——',
    '去「设置」中填入即可。',
  ];

  group('streamChat 离线降级（cfg==null → _emitFreeTestStream）', () {
    test('无 Key 时推送固定免费文案 3 分块 + 末尾 isDone，无诊断块', () async {
      // 注入返回 null 的 configLoader ⇒ _loadConfig 立即返回 null，
      // 不触碰 secure_storage / connectivity / Dio。
      final client = LlmClient(null, null, () async => null);

      final received = <LlmStreamResponse>[];
      await client.streamChat(const [
        ChatMessage(role: 'user', content: '帮我看看这段'),
      ], (resp) => received.add(resp));

      // ── 1. 恰好 3 个 content 分块 + 1 个 isDone 收尾 ──
      expect(received.length, 4, reason: '3 段内容 + 1 段 DONE');

      final contentResponses = received
          .where((r) => !r.isDone)
          .toList(growable: false);
      expect(contentResponses.length, 3);

      // ── 2. 3 段文案顺序与硬编码 chunks 逐字一致 ──
      for (var i = 0; i < expectedChunks.length; i++) {
        expect(
          contentResponses[i].content,
          expectedChunks[i],
          reason: '第 $i 段分块应与 _emitFreeTestStream 硬编码文案一致',
        );
        expect(contentResponses[i].isDone, isFalse);
      }

      // ── 3. 末尾恰好一次 isDone=true，content 为空 ──
      final last = received.last;
      expect(last.isDone, isTrue);
      expect(last.content, isEmpty);

      // ── 4. 全部分块不含诊断块结构（免费模式不伪造诊断）──
      final allText = received.map((r) => r.content).join();
      expect(
        allText.contains('[YS_DIAGNOSIS]'),
        isFalse,
        reason: '免费测试模式不得输出诊断协议块',
      );
      expect(allText.contains('[/YS_DIAGNOSIS]'), isFalse);

      // ── 5. 拼接后语义 = 固定免费引导文案 ──
      expect(allText, contains('免费测试模式'));
      expect(allText, contains('配置 API Key'));
    });
  });
}
