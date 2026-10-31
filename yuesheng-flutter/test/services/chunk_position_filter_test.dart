// ─────────────────────────────────────────────────────────────
// T-20261025-06 件2 · position band 过滤（报批稿 §6 P1–P8，本文件覆盖 P1–P6 + P8）
//
// 判据设计成**能变红**：
//   P1 把 `end` 判断挪到 `beginning` 之后 ⇒ 红（三章书末章归错档）
//   P2 任一 band 的允许集写错        ⇒ 红
//   P3–P5 删掉 `.where((s) => allowed.contains(s.position))` ⇒ 红（三方向成对）
//   P6 单章书/无位次「逐字节等价默认」 ⇒ 过滤误伤即红
//   P8 链路未透传 positionBand       ⇒ 红（Fake LLM 捕获第 0 条 system）
//
// P7（位置块 band 映射）在 `test/w45_known_position_test.dart` 同批更新。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/position_semantics.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';

class _FakeLlmClient extends LlmClient {
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
    callback(const LlmStreamResponse(content: '诊断完成', isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// > 4000 字触发分块的正文（15 段 × 351 字）。
String _makeLongContent() {
  final paragraphs = <String>[];
  for (int i = 0; i < 15; i++) {
    paragraphs.add('${'X' * 350}段落$i');
  }
  return paragraphs.join('\n\n');
}

String _promptFor(String? band) =>
    buildChunkMessages('标题', '正文', 0, 3, positionBand: band).first.content;

void main() {
  group('P1 band 映射（含 end 优先）', () {
    test('三章书末章归结尾；前三章归开头；单章归全局', () {
      expect(positionBandOf(1, 1), 'global');
      expect(positionBandOf(2, 3), 'beginning');
      expect(positionBandOf(3, 3), 'end');
      expect(positionBandOf(3, 10), 'beginning');
      expect(positionBandOf(4, 5), 'middle');
      expect(positionBandOf(5, 5), 'end');
      expect(positionBandOf(2, 2), 'end');
      expect(positionBandOf(1, 2), 'beginning');
    });
  });

  group('P2 允许集', () {
    test('middle 不含 beginning/end，含其余五值', () {
      final allowed = allowedPositionsForBand('middle');
      expect(allowed, isNot(contains('beginning')));
      expect(allowed, isNot(contains('end')));
      for (final v in ['middle', 'global', 'chapter', 'local', 'serial']) {
        expect(allowed, contains(v));
      }
    });

    test('null ⇒ 恰七值（现行为不过滤）', () {
      expect(allowedPositionsForBand(null), kPositionSemantics.keys.toSet());
    });

    test('非法半截位次 ⇒ null band', () {
      expect(positionBandOrNull(null, 10), isNull);
      expect(positionBandOrNull(1, null), isNull);
      expect(positionBandOrNull(0, 10), isNull);
      expect(positionBandOrNull(1, 0), isNull);
      expect(positionBandOrNull(-1, 10), isNull);
      expect(positionBandOrNull(5, 10), 'middle');
    });
  });

  group('P3–P5 三个方向的成对过滤', () {
    test('P3 中段块去开篇判据，保留中段与通配/规模轴判据', () {
      final p = _promptFor('middle');
      expect(p, isNot(contains('- P002 ')));
      expect(p, contains('- P004 '));
      expect(p, contains('- P019 '));
      expect(p, contains('- P020 '));
    });

    test('P4 开头块去中段判据，保留开篇判据', () {
      final p = _promptFor('beginning');
      expect(p, isNot(contains('- P004 ')));
      expect(p, isNot(contains('- P013 ')));
      expect(p, contains('- P002 '));
      expect(p, contains('- P011 '));
    });

    test('P5 结尾块去掉两端（开篇 + 中段），保留结尾判据', () {
      final p = _promptFor('end');
      expect(p, isNot(contains('- P002 ')));
      expect(p, isNot(contains('- P004 ')));
      expect(p, isNot(contains('- P013 ')));
      expect(p, contains('- P012 '));
    });

    test('P5b 退化节随 band 同步过滤（P012 只出现在结尾块）', () {
      // P012 同时是「跨章依赖判据」点名项 ⇒ 两条路径都必须按 band 过滤。
      expect(_promptFor('end'), contains('- P012 结尾乏力'));
      expect(_promptFor('beginning'), isNot(contains('- P012 结尾乏力')));
      expect(_promptFor('middle'), isNot(contains('- P012 结尾乏力')));
    });
  });

  group('P6 单章书 / 无位次逐字节等价默认', () {
    test('global 与 null 两种 prompt 逐字节相等且等于 kChunkSystemPrompt', () {
      expect(_promptFor('global'), kChunkSystemPrompt);
      expect(_promptFor(null), kChunkSystemPrompt);
      expect(buildChunkSystemPrompt(), kChunkSystemPrompt);
    });
  });

  group('P8 链路透传（Fake LLM 捕获第 0 条 system）', () {
    test('chapterOrder 5 / total 10 ⇒ 首块 system 按中段过滤', () async {
      final client = _FakeLlmClient();
      await runProgressiveDiagnosis(
        content: _makeLongContent(),
        title: '链路透传',
        onContent: (_) {},
        llmClient: client,
        chapterOrder: 5,
        totalChapters: 10,
      );
      expect(client.chatMessages, isNotEmpty);
      final system = client.chatMessages.first;
      expect(system.role, 'system');
      expect(system.content, isNot(contains('- P002 ')));
      expect(system.content, contains('- P004 '));
    });

    test('不传位次 ⇒ 首块 system 仍逐字节等于默认 prompt', () async {
      final client = _FakeLlmClient();
      await runProgressiveDiagnosis(
        content: _makeLongContent(),
        title: '默认路径',
        onContent: (_) {},
        llmClient: client,
      );
      expect(client.chatMessages.first.content, kChunkSystemPrompt);
    });
  });
}
