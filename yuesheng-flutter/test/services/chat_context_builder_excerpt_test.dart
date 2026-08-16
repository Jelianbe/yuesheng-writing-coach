// ─────────────────────────────────────────────────────────────
// chat_context_builder_excerpt_test — 批次5（5.5）选段引用上下文
// + 批次6（6.5）O11 原文摘录（findKeywordExcerpt / F05/F07/F11 渲染）
//
// 覆盖：
//   1. parseExcerptRange：合法/非法/边界 JSON
//   2. extractExcerpt：选段±50 字符上下文
//   3. buildReferencesContext：主引用 chapter + excerptRange →
//      注入选段上下文（替代整章）；无范围 → 回退整章
//   4. findKeywordExcerpt：关键词首现片段摘录（命中/未命中/空/clamp）
//   5. F05/F07/F11 上下文带 excerpt 渲染、null 降级不输出
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/conflict_detector.dart';
import 'package:writingcoach/services/event_causality_detector.dart';
import 'package:writingcoach/services/subplot_closure_detector.dart';
import 'package:writingcoach/types/character_types.dart';

ChapterBrief _chapter({String? content}) {
  final body = content ?? '第一章：雪夜。北风呼啸穿过空旷的原野，远山沉默如铁。';
  return ChapterBrief(
    id: 'ch-1',
    title: '第一章 雪夜',
    wordCount: body.length,
    sortOrder: 1,
    content: body,
  );
}

void main() {
  group('parseExcerptRange（5.5）', () {
    test('合法 JSON → 解析 start/end', () {
      final r = parseExcerptRange('{"start":100,"end":320}');
      expect(r, isNotNull);
      expect(r!.start, 100);
      expect(r.end, 320);
    });

    test('null / 空串 → null', () {
      expect(parseExcerptRange(null), isNull);
      expect(parseExcerptRange(''), isNull);
    });

    test('非法 JSON / 缺字段 / start>end → null', () {
      expect(parseExcerptRange('not-json'), isNull);
      expect(parseExcerptRange('{"start":100}'), isNull);
      expect(parseExcerptRange('{"start":320,"end":100}'), isNull);
      expect(parseExcerptRange('{"start":-1,"end":10}'), isNull);
    });
  });

  group('extractExcerpt（5.5）', () {
    test('中间选段 → 前后各补 50 字符上下文', () {
      final content = 'A' * 200;
      final r = extractExcerpt(content, (start: 100, end: 120));
      expect(r.length, 120 - 50 + 50); // start-50 到 end+50
      expect(r, startsWith('A' * 50));
      expect(r, endsWith('A' * 70));
    });

    test('选段贴近开头 → 上下文从 0 开始', () {
      final content = 'B' * 200;
      final r = extractExcerpt(content, (start: 10, end: 40));
      expect(r.length, 40 + 50);
      expect(r, startsWith('B'));
    });

    test('选段贴近结尾 → 上下文截断到内容末尾', () {
      final content = 'C' * 200;
      final r = extractExcerpt(content, (start: 170, end: 190));
      expect(r.length, 200 - 120); // start-50=120 到 end
      expect(r, endsWith('C'));
    });

    test('范围超出内容 → 不越界', () {
      final content = 'D' * 30;
      final r = extractExcerpt(content, (start: 100, end: 120));
      expect(r, content);
    });
  });

  group('buildReferencesContext 选段注入（5.5）', () {
    ReferenceResolvers resolvers() {
      return ReferenceResolvers(
        fileResolver: (_) => null,
        chapterResolver: (id) => _chapter(content: '原文开头正文，' * 50),
        manuscriptResolver: (_) => null,
      );
    }

    test('主引用 chapter + excerptRange → 输出选段诊断提示（不含整章）', () {
      final ctx = buildReferencesContext(
        [
          ReferenceItem(
            refType: 'chapter',
            refId: 'ch-1',
            title: '第一章',
            isPrimary: 1,
            manuscriptId: 'ms-1',
            excerptRange: '{"start":10,"end":60}',
          ),
        ],
        resolvers: resolvers(),
      );
      expect(ctx, contains('【选段诊断】'));
      expect(ctx, contains('选中片段'));
      expect(ctx, isNot(contains('【位置提示】请根据内容判断这是原文章节的开头/中段/结尾')),
          reason: '带选段范围时不再走整章位置提示');
    });

    test('主引用 chapter 无 excerptRange → 回退整章路径', () {
      final ctx = buildReferencesContext(
        [
          ReferenceItem(
            refType: 'chapter',
            refId: 'ch-1',
            title: '第一章',
            isPrimary: 1,
            manuscriptId: 'ms-1',
          ),
        ],
        resolvers: resolvers(),
      );
      expect(ctx, contains('【位置提示】请根据内容判断这是原文章节的开头/中段/结尾'));
      expect(ctx, isNot(contains('【选段诊断】')));
    });

    test('次要引用 chapter 带 excerptRange → 不展开选段（仅主引用优先）', () {
      final ctx = buildReferencesContext(
        [
          ReferenceItem(
            refType: 'chapter',
            refId: 'ch-1',
            title: '第一章',
            isPrimary: 0,
            manuscriptId: 'ms-1',
            excerptRange: '{"start":10,"end":60}',
          ),
        ],
        resolvers: resolvers(),
      );
      expect(ctx, isNot(contains('【选段诊断】')),
          reason: '选段展开仅限主引用');
    });
  });

  group('findKeywordExcerpt（6.5）', () {
    test('关键词命中 → 返回含前后上下文的单行片段', () {
      final content = '第5章，阿禾决定去金陵。之后他踏上旅途。';
      final r = findKeywordExcerpt(content, '阿禾决定去金陵');
      expect(r, isNotNull);
      expect(r, contains('阿禾决定去金陵'));
      expect(r, contains('第5章'));
    });

    test('关键词未命中 → null', () {
      expect(findKeywordExcerpt('没有该关键词的正文', '不存在的词'), isNull);
    });

    test('空关键词 / 空正文 → null（降级安全）', () {
      expect(findKeywordExcerpt('正文', ''), isNull);
      expect(findKeywordExcerpt('', '关键词'), isNull);
    });

    test('关键词贴近开头 → clamp 不越界', () {
      final r = findKeywordExcerpt('开头关键词结尾', '关键词');
      expect(r, isNotNull);
      expect(r, startsWith('开'));
    });

    test('多句正文 → 只取首句截断为一行', () {
      final r = findKeywordExcerpt('第一句，命中目标词。第二句，继续。', '命中目标词');
      expect(r, isNotNull);
      expect(r, contains('命中目标词'));
      expect(r, isNot(contains('第二句')));
    });
  });

  group('F05/F07/F11 原文摘录渲染（6.5）', () {
    test('F05 带 excerpt → 输出原文摘录', () {
      final ctx = buildConflictObservationsContext([
        ConflictObservation(
          characterName: '阿禾',
          attribute: '独生子女状态',
          orderedValues: [
            CharacterAssertion(
              attribute: '独生子女状态',
              value: '独生子',
              chapter: 3,
              timestamp: 1,
            ),
            CharacterAssertion(
              attribute: '独生子女状态',
              value: '妹妹',
              chapter: 15,
              timestamp: 2,
            ),
          ],
          description: '第3章「独生子」→ 第15章「妹妹」',
          excerpt: '他是家中的独生子，父亲常年在远方',
        ),
      ]);
      expect(ctx, contains('他是家中的独生子'));
      expect(ctx, contains('（原文：「他是家中的独生子'));
    });

    test('F05 excerpt 为 null → 不输出摘录（降级安全）', () {
      final ctx = buildConflictObservationsContext([
        ConflictObservation(
          characterName: '阿禾',
          attribute: '独生子女状态',
          orderedValues: [
            CharacterAssertion(
              attribute: '独生子女状态',
              value: '独生子',
              chapter: 3,
              timestamp: 1,
            ),
            CharacterAssertion(
              attribute: '独生子女状态',
              value: '妹妹',
              chapter: 15,
              timestamp: 2,
            ),
          ],
          description: '第3章「独生子」→ 第15章「妹妹」',
        ),
      ]);
      expect(ctx, contains('第3章「独生子」→ 第15章「妹妹」'));
      expect(ctx, isNot(contains('原文：')));
    });

    test('F07 带 excerpt → 输出原文摘录', () {
      final ctx = buildCausalityBreakContext([
        CausalityBreakObservation(
          name: '阿禾决定去金陵',
          chapter: 5,
          eventType: '决定',
          description: '第5章「阿禾决定去金陵」（决定类）缺触发事件',
          excerpt: '第5章，阿禾决定去金陵',
        ),
      ]);
      expect(ctx, contains('（原文：「第5章，阿禾决定去金陵」）'));
    });

    test('F11 带 excerpt → 输出原文摘录；null → 不输出', () {
      final withExcerpt = buildSubplotClosureContext([
        UnclosedSubplotObservation(
          name: '钥匙的秘密',
          introducedChapter: 3,
          currentChapter: 12,
          description: '第3章引入的支线「钥匙的秘密」至今（第12章）未回收',
          excerpt: '钥匙的秘密始终没有下文',
        ),
      ]);
      expect(withExcerpt, contains('（原文：「钥匙的秘密始终没有下文」）'));

      final withoutExcerpt = buildSubplotClosureContext([
        UnclosedSubplotObservation(
          name: '钥匙的秘密',
          introducedChapter: 3,
          currentChapter: 12,
          description: '第3章引入的支线「钥匙的秘密」至今（第12章）未回收',
        ),
      ]);
      expect(withoutExcerpt, isNot(contains('原文：')));
    });
  });
}
