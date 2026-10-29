// ─────────────────────────────────────────────────────────────
// 分块 / 合并 prompt 的「教学风格」注入回归（C155 闭包插值缺陷的钉子）
//
// 缺陷形态（2026-10-24 坐实）：
//   `$_kTeachingModeChunkInstruction(teachingMode)` 写在字符串插值上下文里
//   ⇒ Dart 只取标识符的**值**（顶层函数的 tear-off 对象），字面 `(teachingMode)`
//   跟在后面 ⇒ 生产 prompt 尾部渲染出：
//     `Closure: (TeachingMode) => String from Function
//      '_kTeachingModeChunkInstruction@...': static.(teachingMode)`
//
// 后果：
//   ① socratic / direct 两种教学风格指令**从未真正注入**任何 prompt；
//   ② 每次分块 / 合并诊断都往模型的 system prompt 里塞了一段无意义闭包串。
//
// 本文件的钉子（断言行为，不断言实现细节）：
//   ① 常量 prompt 里不含闭包表示 / 函数名 / 字面 `(teachingMode)`；
//   ② socratic 模式含「教学风格（疑问式）」与「引导」；
//   ③ direct 模式含「教学风格（直接说）」；
//   ④ 两种模式的 prompt **不相等**（证明模式真的进了 prompt，而非常量没变）。
//
// 入口说明（为什么不用私有函数）：
//   `_buildChunkSystemPrompt` 为私有（`_` 前缀），`test/` 不在同一库 ⇒ 不可直接
//   引用。分块 messages 装配器已于 `T-20261027-01` **H8**（2026-10-29 批八）公开为
//   `buildChunkMessages`（`@visibleForTesting`），但本文件**不改走直调** ——
//   继续走**真实公开入口**取 direct 模式的分块 system prompt：
//   `runProgressiveDiagnosis(teachingMode: TeachingMode.direct)`
//   → Fake LlmClient 捕获实际发出的 system message。
//   ★ H8 后分块链有**两条** system（主提示词 + 窗口元信息）：本文件取的是
//   `firstWhere(role == 'system')` = 第 0 条 = 主提示词本体，语义不变。
//   （该路径已被既有测试 progressive_diagnosis_test.dart #14 验证可在
//     测试环境跑通 —— 本文件复用同一模式，不新增测试基础设施。）
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 捕获实际发出的 chat 请求（含 system message）的 Fake。
class _CapturingLlmClient extends LlmClient {
  final List<ChatMessage> chatMessages = [];

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) async {
    chatMessages.addAll(messages);
    return '{"notes":[]}';
  }

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// >4000 字触发分块的正文（15 段 × 351 字 ≈ 5265 字）。
String _longContent() {
  final paragraphs = <String>[];
  for (int i = 0; i < 15; i++) {
    paragraphs.add('${'X' * 350}段落$i');
  }
  return paragraphs.join('\n\n');
}

/// 取该模式**实际发出**的分块 system prompt。
Future<String> _capturedChunkSystemPrompt(TeachingMode mode) async {
  final fake = _CapturingLlmClient();
  await runProgressiveDiagnosis(
    content: _longContent(),
    title: '教学风格注入',
    llmClient: fake,
    onContent: (_) {},
    teachingMode: mode,
  );
  return fake.chatMessages.firstWhere((m) => m.role == 'system').content;
}

/// 旧写法残留的三个特征串。任一命中 ⇒ 闭包插值回来了。
const List<String> _kClosureArtifacts = [
  'Closure',
  '_kTeachingModeChunkInstruction',
  '(teachingMode)',
];

void main() {
  group('① 分块 prompt 常量（socratic 路径）', () {
    test('不含闭包表示 / 函数名 / 字面 (teachingMode)', () {
      for (final artifact in _kClosureArtifacts) {
        expect(
          kChunkSystemPrompt.contains(artifact),
          isFalse,
          reason:
              'kChunkSystemPrompt 含「$artifact」——字符串插值把函数 tear-off '
              '当值插进去了（教学风格指令从未真正注入）。',
        );
      }
    });

    test('含教学风格实际文本（疑问式 + 引导）', () {
      expect(kChunkSystemPrompt, contains('教学风格（疑问式）'));
      expect(kChunkSystemPrompt, contains('引导'));
    });
  });

  group('② 分块 prompt 实际发出内容（direct 路径）', () {
    test('direct 模式含「教学风格（直接说）」且无闭包残留', () async {
      final prompt = await _capturedChunkSystemPrompt(TeachingMode.direct);
      expect(prompt, contains('教学风格（直接说）'));
      expect(prompt, isNot(contains('教学风格（疑问式）')));
      for (final artifact in _kClosureArtifacts) {
        expect(
          prompt.contains(artifact),
          isFalse,
          reason: 'direct 模式的分块 prompt 含「$artifact」',
        );
      }
    });

    test('direct 与 socratic 的分块 prompt 不相等（模式真的进了 prompt）', () async {
      final socratic = await _capturedChunkSystemPrompt(TeachingMode.socratic);
      final direct = await _capturedChunkSystemPrompt(TeachingMode.direct);
      expect(direct, isNot(equals(socratic)));
      expect(socratic, contains('教学风格（疑问式）'));
      expect(direct, contains('教学风格（直接说）'));
    });
  });

  group('③ 合并 prompt（buildMergePrompt 公开入口）', () {
    test('两种模式各自含对应教学风格，且无闭包残留', () {
      final socratic = buildMergePrompt(const []);
      final direct = buildMergePrompt(
        const [],
        teachingMode: TeachingMode.direct,
      );
      expect(socratic, contains('教学风格（疑问式）'));
      expect(direct, contains('教学风格（直接说）'));
      expect(direct, isNot(contains('教学风格（疑问式）')));
      for (final artifact in _kClosureArtifacts) {
        expect(
          socratic.contains(artifact),
          isFalse,
          reason: 'socratic 含「$artifact」',
        );
        expect(
          direct.contains(artifact),
          isFalse,
          reason: 'direct 含「$artifact」',
        );
      }
    });

    test('direct 与 socratic 的合并 prompt 不相等', () {
      final socratic = buildMergePrompt(const []);
      final direct = buildMergePrompt(
        const [],
        teachingMode: TeachingMode.direct,
      );
      expect(direct, isNot(equals(socratic)));
    });
  });
}
