// ─────────────────────────────────────────────────────────────
// material_entry_service_test — 资料条目默认不提炼 + on-demand 摘要（ADR-C143 批C）
//
// DoD §5.3：存原文不提炼（默认路径）；关键片段原样截取+锚点；
//           AI 摘要仅 on-demand 按钮触发（断言默认无摘要生成）。
// DoD §5.4：来源 unknown 默认 + 只展示域名 + AI 不评级（无评级字段/方法）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/material_entry_repository.dart';
import 'package:writingcoach/services/material_entry_service.dart';

void main() {
  late AppDatabase db;
  late MaterialEntryService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = MaterialEntryService(db);
  });
  tearDown(() => db.close());

  test('默认存路径：存原文、key_snippet 原样截取、summary=null、来源 unknown', () async {
    final entry = await service.saveOriginal(
      manuscriptId: 'm1',
      url: 'https://blog.example.com/post/1',
      sourceName: 'blog.example.com', // 只展示域名/来源名
      originalText: '这是一段外部资料原文。\n第二行。',
      keySnippet: '这是一段外部资料原文。', // 原样截取，非 AI 摘要句
      anchor: '#:~:text=外部资料',
    );

    expect(entry.originalText, '这是一段外部资料原文。\n第二行。');
    expect(entry.keySnippet, '这是一段外部资料原文。');
    expect(entry.anchor, '#:~:text=外部资料');
    expect(entry.sourceName, 'blog.example.com');
    // ★ 默认路径不生成摘要
    expect(entry.summary, isNull, reason: '默认存原文路径绝不写 summary');
    // ★ 来源可信度恒 unknown，无评级
    expect(entry.sourceCredibility, SourceCredibility.unknown);
  });

  test('on-demand：只有点按钮才生成摘要；默认路径绝不调 LLM', () async {
    final entry = await service.saveOriginal(
      manuscriptId: 'm1',
      originalText: '原文内容较长……',
    );
    expect(entry.summary, isNull);

    // 记录 summarizer 被调用次数：默认保存路径后应仍为 0
    var calls = 0;
    Future<String> fakeSummarizer(String original) async {
      calls++;
      expect(original, '原文内容较长……'); // 摘要器只吃原文，不被喂加工稿
      return '这是一句概括。';
    }

    final summary = await service.requestSummaryOnDemand(
      entryId: entry.id,
      summarize: fakeSummarizer,
    );
    expect(calls, 1, reason: 'on-demand 恰好调用一次摘要器');
    expect(summary, '这是一句概括。');

    final refreshed = await MaterialEntryRepository(db).getById(entry.id);
    expect(refreshed!.summary, '这是一句概括。');
  });

  test('on-demand prompt 文本钉死（最小口径，仅按钮路径可达）', () {
    final prompt = buildMaterialSummaryPrompt('原文XYZ');
    // 钉住：只客观概括、不替作者做设定判断（R-009）
    expect(prompt, contains('原文：\n原文XYZ'));
    expect(prompt, contains('不替作者判断'));
  });
}
