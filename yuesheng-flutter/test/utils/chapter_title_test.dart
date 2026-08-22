// ─────────────────────────────────────────────────────────────
// chapter_title 测试 — 批次88-1 章节自动命名
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/utils/chapter_title.dart';

Chapter _chapter(String title) => Chapter(
  id: 'id-$title',
  manuscriptId: 'ms',
  title: title,
  content: '',
  wordCount: 0,
  sortOrder: 0,
  status: 'draft',
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  group('chineseNumberToInt', () {
    test('个位', () {
      expect(chineseNumberToInt('一'), 1);
      expect(chineseNumberToInt('九'), 9);
      expect(chineseNumberToInt('零'), 0);
    });

    test('十位', () {
      expect(chineseNumberToInt('十'), 10);
      expect(chineseNumberToInt('十一'), 11);
      expect(chineseNumberToInt('十五'), 15);
      expect(chineseNumberToInt('二十'), 20);
      expect(chineseNumberToInt('九十九'), 99);
    });

    test('百位以上', () {
      expect(chineseNumberToInt('一百'), 100);
      expect(chineseNumberToInt('一百零五'), 105);
      expect(chineseNumberToInt('一百二十三'), 123);
      expect(chineseNumberToInt('九百九十九'), 999);
    });

    test('阿拉伯数字串', () {
      expect(chineseNumberToInt('12'), 12);
      expect(chineseNumberToInt('123'), 123);
    });

    test('非法输入返回 null', () {
      expect(chineseNumberToInt(''), null);
      expect(chineseNumberToInt('章节'), null);
    });
  });

  group('intToChineseNumber', () {
    test('个位', () {
      expect(intToChineseNumber(1), '一');
      expect(intToChineseNumber(9), '九');
    });

    test('十位', () {
      expect(intToChineseNumber(10), '十');
      expect(intToChineseNumber(11), '十一');
      expect(intToChineseNumber(20), '二十');
      expect(intToChineseNumber(21), '二十一');
      expect(intToChineseNumber(99), '九十九');
    });

    test('百位以上', () {
      expect(intToChineseNumber(100), '一百');
      expect(intToChineseNumber(105), '一百零五');
      expect(intToChineseNumber(123), '一百二十三');
    });
  });

  group('nextChapterTitle', () {
    test('空作品 → 第一章', () {
      expect(nextChapterTitle([]), '第一章');
    });

    test('已有「第一章」→ 第二章（序号 +1）', () {
      expect(nextChapterTitle([_chapter('第一章：启程')]), '第二章');
    });

    test('取最大序号 +1（存在缺号）', () {
      expect(nextChapterTitle([_chapter('第一章'), _chapter('第三章')]), '第四章');
    });

    test('阿拉伯数字序号兼容', () {
      expect(nextChapterTitle([_chapter('第1章')]), '第二章');
      expect(nextChapterTitle([_chapter('第10章')]), '第十一章');
    });

    test('无序号标题 → 按章节数量 +1', () {
      expect(nextChapterTitle([_chapter('引子'), _chapter('序言')]), '第三章');
    });

    test('混合：带序号取最大，无序号作保底', () {
      expect(nextChapterTitle([_chapter('引子'), _chapter('第二章：夜行')]), '第三章');
    });

    test('第十 → 十一、二十 → 二十一（进位）', () {
      expect(nextChapterTitle([_chapter('第十章')]), '第十一章');
      expect(nextChapterTitle([_chapter('第二十章')]), '第二十一章');
    });
  });
}
