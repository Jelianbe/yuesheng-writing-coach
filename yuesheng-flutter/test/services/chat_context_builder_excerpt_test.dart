// ─────────────────────────────────────────────────────────────
// chat_context_builder_excerpt_test — 批次5（5.5）选段引用上下文
// + 批次6（6.5）O11 原文摘录（findKeywordExcerpt / F05/F07/F11 渲染）
//
// 覆盖：
//   1. parseParagraphAnchor：合法/非法/边界 JSON（段落锚点）
//   2. extractParagraphWindow：按段落锚点截取窗口
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
  group('parseParagraphAnchor（A-3）', () {
    test('合法 JSON → 解析 chapterId/startPara/endPara', () {
      final r = parseParagraphAnchor(
        '{"chapterId":"ch-1","startPara":2,"endPara":5}',
      );
      expect(r, isNotNull);
      expect(r!.chapterId, 'ch-1');
      expect(r.startPara, 2);
      expect(r.endPara, 5);
    });

    test('null / 空串 → null', () {
      expect(parseParagraphAnchor(null), isNull);
      expect(parseParagraphAnchor(''), isNull);
    });

    test('非法 JSON / 缺字段 / start>end / 负数 → null', () {
      expect(parseParagraphAnchor('not-json'), isNull);
      expect(parseParagraphAnchor('{"chapterId":"x"}'), isNull);
      expect(
        parseParagraphAnchor('{"chapterId":"x","startPara":5,"endPara":2}'),
        isNull,
      );
      expect(
        parseParagraphAnchor('{"chapterId":"x","startPara":-1,"endPara":10}'),
        isNull,
      );
      // 旧版字符偏移格式 {"start","end"} 已废弃 → null
      expect(parseParagraphAnchor('{"start":100,"end":320}'), isNull);
    });
  });

  group('extractParagraphWindow（A-3）', () {
    const content = 'p0\np1\np2\np3';

    test('中间段落 → 返回 [start,end] 段落并用 \n 连接', () {
      final r = extractParagraphWindow(content, 1, 2);
      expect(r, 'p1\np2');
    });

    test('单段落 → 返回该段落', () {
      final r = extractParagraphWindow(content, 0, 0);
      expect(r, 'p0');
    });

    test('结尾越界 → 截断到末段落', () {
      final r = extractParagraphWindow(content, 3, 5);
      expect(r, 'p3');
    });

    test('startPara 超出段落数 → 回退整段内容（不越界）', () {
      final r = extractParagraphWindow(content, 10, 20);
      expect(r, content);
    });

    test('单行内容超出 → 返回整段', () {
      final single = 'D' * 30;
      final r = extractParagraphWindow(single, 100, 120);
      expect(r, single);
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
      final ctx = buildReferencesContext([
        ReferenceItem(
          refType: 'chapter',
          refId: 'ch-1',
          title: '第一章',
          isPrimary: 1,
          manuscriptId: 'ms-1',
          excerptRange: '{"chapterId":"ch-1","startPara":0,"endPara":1}',
        ),
      ], resolvers: resolvers());
      expect(ctx, contains('【选段诊断】'));
      expect(ctx, contains('选中片段'));
      expect(
        ctx,
        isNot(contains('【位置提示】请根据内容判断这是原文章节的开头/中段/结尾')),
        reason: '带选段范围时不再走整章位置提示',
      );
    });

    test('主引用 chapter 无 excerptRange → 回退整章路径', () {
      final ctx = buildReferencesContext([
        ReferenceItem(
          refType: 'chapter',
          refId: 'ch-1',
          title: '第一章',
          isPrimary: 1,
          manuscriptId: 'ms-1',
        ),
      ], resolvers: resolvers());
      expect(ctx, contains('【位置提示】请根据内容判断这是原文章节的开头/中段/结尾'));
      expect(ctx, isNot(contains('【选段诊断】')));
    });

    test('主引用 chapter + anchor.chapterId ≠ refId → 不展开选段（回退整章）', () {
      final ctx = buildReferencesContext([
        ReferenceItem(
          refType: 'chapter',
          refId: 'ch-9',
          title: '第九章',
          isPrimary: 1,
          manuscriptId: 'ms-1',
          excerptRange: '{"chapterId":"ch-1","startPara":0,"endPara":1}',
        ),
      ], resolvers: resolvers());
      expect(ctx, isNot(contains('【选段诊断】')), reason: '锚点 chapterId 与引用 id 不匹配');
      expect(ctx, contains('【位置提示】请根据内容判断这是原文章节的开头/中段/结尾'));
    });

    test('次要引用 chapter 带 excerptRange → 不展开选段（仅主引用优先）', () {
      final ctx = buildReferencesContext([
        ReferenceItem(
          refType: 'chapter',
          refId: 'ch-1',
          title: '第一章',
          isPrimary: 0,
          manuscriptId: 'ms-1',
          excerptRange: '{"chapterId":"ch-1","startPara":0,"endPara":1}',
        ),
      ], resolvers: resolvers());
      expect(ctx, isNot(contains('【选段诊断】')), reason: '选段展开仅限主引用');
    });

    test('manuscript 空简介 → 不输出「简介：」行（降级安全）', () {
      final resolversWithMs = ReferenceResolvers(
        fileResolver: (_) => null,
        chapterResolver: (id) => _chapter(content: '原文开头正文，' * 50),
        manuscriptResolver: (id) => ManuscriptDetail(
          genre: '长篇小说',
          description: '',
          chapters: [
            ChapterBrief(
              id: 'ch-1',
              title: '第一章',
              wordCount: 1000,
              sortOrder: 1,
              content: '正文',
            ),
          ],
        ),
      );
      final ctx = buildReferencesContext([
        ReferenceItem(
          refType: 'manuscript',
          refId: 'ms-1',
          title: '作品名',
          isPrimary: 1,
        ),
      ], resolvers: resolversWithMs);
      expect(ctx, contains('### 【主引用】 作品：作品名'));
      expect(ctx, contains('- 类型：长篇小说'));
      expect(ctx, isNot(contains('- 简介：')), reason: '空简介不输出简介行');
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

    test('多段落正文 → 只返回关键词所在段落（不含其它段落）', () {
      final r = findKeywordExcerpt('第一段包含目标词。\n第二段没有。\n第三段也没有。', '目标词');
      expect(r, isNotNull);
      expect(r, contains('目标词'));
      expect(r, isNot(contains('第二段')));
      expect(r, isNot(contains('第三段')));
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
