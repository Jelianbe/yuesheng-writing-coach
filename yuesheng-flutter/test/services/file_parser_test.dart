// ─────────────────────────────────────────────────────────────
// file_parser 单元测试 — 文件解析（纯逻辑，对齐 RN file-parser.ts）
//
// 覆盖路径：
//   1. parseTxtFile：中文「第X章」切章
//   2. parseTxtFile：英文 Chapter N 切章
//   3. parseTxtFile：无章节标记 → 兜底「第一章」
//   4. parseTxtFile：标题过长（≥50 字）不作为章节标记
//   5. parseMdFile：按 `# ` 一级标题切章
//   6. parseMdFile：无 `# ` → 兜底
//   7. parseDocument：.md → md 解析；.txt → txt 解析
//   8. 文件名去扩展名 → title；空名 → 「未命名作品」
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/file_parser.dart';

void main() {
  group('parseTxtFile', () {
    test('#1 中文「第X章」切章', () {
      const content = '第一章 开端\n这是第一章的内容。\n第二章 发展\n这是第二章的内容。\n第三章 结局\n结尾内容。';

      final result = parseTxtFile(content, '我的小说.txt');

      expect(result.title, '我的小说');
      expect(result.genre, '未知');
      expect(result.chapters.length, 3);
      expect(result.chapters[0].title, '第一章 开端');
      expect(result.chapters[0].content, contains('这是第一章的内容'));
      expect(result.chapters[2].title, '第三章 结局');
    });

    test('#2 英文 Chapter N 切章', () {
      const content =
          'Chapter 1\nFirst chapter body.\nChapter 2\nSecond chapter body.';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 2);
      expect(result.chapters[0].title, 'Chapter 1');
      expect(result.chapters[0].content, contains('First chapter body'));
      expect(result.chapters[1].title, 'Chapter 2');
    });

    test('#3 无章节标记 → 兜底「第一章」', () {
      const content = '这是一段没有章节标记的连续文本。';

      final result = parseTxtFile(content, 'notes.txt');

      expect(result.chapters.length, 1);
      expect(result.chapters[0].title, '第一章');
      expect(result.chapters[0].content, contains('没有章节标记'));
    });

    test('#4 标题过长（≥50 字）不作为章节标记', () {
      final longTitle = '第${'一' * 60}章${'长' * 10}';
      final content = '$longTitle\n这是内容。';

      final result = parseTxtFile(content, 'long.txt');

      // 过长标题不触发切章 → 整篇兜底第一章，标题仍为默认
      expect(result.chapters.length, 1);
      expect(result.chapters[0].title, '第一章');
      expect(result.chapters[0].content, contains(longTitle));
    });
  });

  group('parseMdFile', () {
    test('#5 md 层级：`# ` 一级章，`## ` 二级卷，`### ` 三级章', () {
      const content = '# 序章\n序章内容。\n# 正文\n正文内容。\n## 第二卷\n卷内内容。';

      final result = parseMdFile(content, 'book.md');

      expect(result.title, 'book');
      expect(result.chapters.length, 2);
      expect(result.chapters[0].title, '序章');
      expect(result.chapters[0].content, contains('序章内容'));
      expect(result.chapters[0].volumeTitle, isNull);
      expect(result.chapters[1].title, '正文');
      expect(result.chapters[1].content, contains('正文内容'));
      // `## ` 二级标题开启新卷，其后内容归属当前章但带卷标记
      expect(result.chapters[1].content, contains('卷内内容'));
      expect(result.chapters[1].volumeTitle, '第二卷');
    });

    test('#6 无 `# ` → 兜底', () {
      const content = '没有任何标题的 markdown 内容。';

      final result = parseMdFile(content, 'plain.md');

      expect(result.chapters.length, 1);
      expect(result.chapters[0].title, '第一章');
    });
  });

  group('parseDocument', () {
    test('#7 .md 走 md 解析，.txt 走 txt 解析', () {
      const mdContent = '# 第一章\n内容A';
      final mdResult = parseDocument(mdContent, 'book.md');
      expect(mdResult.chapters.first.title, '第一章');

      const txtContent = '第一章\n内容B';
      final txtResult = parseDocument(txtContent, 'book.txt');
      expect(txtResult.chapters.first.title, '第一章');

      const markdownContent = '## 标题\n不切';
      final markdownResult = parseDocument(markdownContent, 'book.markdown');
      expect(markdownResult.chapters.first.title, '第一章');
    });

    test('#8 无扩展名 → 「未命名作品」', () {
      final result = parseTxtFile('内容', 'novel');

      expect(result.title, '未命名作品');
    });
  });

  // ════════════════════════════════════════════════════════════
  // FIX-3 变体测试矩阵（对应 .ai/logs/2026-09-23.md §2.1 七例 + 扩展）
  // ════════════════════════════════════════════════════════════
  group('FIX-3 txt 变体切章', () {
    test('B: txt 内容带 `# 第一章`（md 风格）→ 仍按章切', () {
      const content = '# 第一章\n第一段\n# 第二章\n第二段';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 2);
      expect(result.chapters[0].title, '第一章');
      expect(result.chapters[0].content, contains('第一段'));
      expect(result.chapters[1].title, '第二章');
    });

    test('C: 括号变体【第一章】→ 切章且标题去括号', () {
      const content = '【第一章】\n第一段\n【第二章】\n第二段';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 2);
      expect(result.chapters[0].title, '第一章');
      expect(result.chapters[1].title, '第二章');
    });

    test('C2: 中文括号（第一章）→ 切章且标题去括号', () {
      const content = '（第一章）\n第一段\n（第二章）\n第二段';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 2);
      expect(result.chapters[0].title, '第一章');
      expect(result.chapters[1].title, '第二章');
    });

    test('D: 空格变体「第 1 章」→ 切章', () {
      const content = '第 1 章\n第一段\n第 2 章\n第二段';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 2);
      expect(result.chapters[0].title, '第 1 章');
      expect(result.chapters[1].title, '第 2 章');
    });

    test('E: 「序章」开头 → 独立成章，不吞进兜底', () {
      const content = '序章\n序章内容。\n第一章\n正文内容。';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 2);
      expect(result.chapters[0].title, '序章');
      expect(result.chapters[0].content, contains('序章内容'));
      expect(result.chapters[1].title, '第一章');
    });

    test('数字变体：第壹章 / 全角第１章 → 切章', () {
      const content = '第壹章\n壹段\n第１章\n全角段\n第十二章\n十二段';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 3);
      expect(result.chapters[0].title, '第壹章');
      expect(result.chapters[1].title, '第１章');
      expect(result.chapters[2].title, '第十二章');
    });

    test('七后缀：第X节/回/幕/篇/集 → 切章', () {
      const content = '第一节\n内容一\n第二回\n内容二\n第三幕\n内容三';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 3);
      expect(result.chapters[0].title, '第一节');
      expect(result.chapters[1].title, '第二回');
      expect(result.chapters[2].title, '第三幕');
    });

    test('卷识别：第X卷/第一部 → 章节带 volumeTitle', () {
      const content =
          '第一卷 风起\n第一章 少年\n少年内容。\n第二章 远行\n远行内容。\n第二卷 云涌\n第三章 归途\n归途内容。';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 3);
      expect(result.chapters[0].volumeTitle, '第一卷 风起');
      expect(result.chapters[1].volumeTitle, '第一卷 风起');
      expect(result.chapters[2].volumeTitle, '第二卷 云涌');
      // 卷标记本身不产生章节
      expect(result.chapters.map((c) => c.title).toList(), [
        '第一章 少年',
        '第二章 远行',
        '第三章 归途',
      ]);
    });

    test('英文 Part 1 卷标记 → volumeTitle', () {
      const content = 'Part 1\nChapter 1\nBody one.\nChapter 2\nBody two.';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 2);
      expect(result.chapters[0].volumeTitle, 'Part 1');
      expect(result.chapters[0].title, 'Chapter 1');
      expect(result.chapters[1].volumeTitle, 'Part 1');
    });

    test('卷标记后无章标记 → 卷标记不产生空章', () {
      const content = '第一卷 起\n只有内容，没有章节标记。';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 1);
      expect(result.chapters[0].title, '第一章');
      expect(result.chapters[0].volumeTitle, '第一卷 起');
      expect(result.chapters[0].content, contains('只有内容'));
    });
  });

  group('FIX-3 md 层级', () {
    test('F: md 文件用 txt 风格「第一章」→ 切章', () {
      const content = '第一章\n第一段\n第二章\n第二段';

      final result = parseMdFile(content, 'book.md');

      expect(result.chapters.length, 2);
      expect(result.chapters[0].title, '第一章');
      expect(result.chapters[1].title, '第二章');
    });

    test('Kindle 层级：## 卷 + ### 章 → 卷章分级', () {
      const content =
          '## 第一卷\n### 第一章\n内容一。\n### 第二章\n内容二。\n## 第二卷\n### 第三章\n内容三。';

      final result = parseMdFile(content, 'book.md');

      expect(result.chapters.length, 3);
      expect(result.chapters[0].title, '第一章');
      expect(result.chapters[0].volumeTitle, '第一卷');
      expect(result.chapters[1].title, '第二章');
      expect(result.chapters[1].volumeTitle, '第一卷');
      expect(result.chapters[2].title, '第三章');
      expect(result.chapters[2].volumeTitle, '第二卷');
    });

    test('G: 全角空格缩进标题（trim 已处理）', () {
      const content = '　第一章\n第一段\n　第二章\n第二段';

      final result = parseTxtFile(content, 'novel.txt');

      expect(result.chapters.length, 2);
      expect(result.chapters[0].title, '第一章');
    });
  });

  group('FIX-3 编码回退', () {
    test('readFileContent: UTF-8 正常读取', () async {
      final dir = await Directory.systemTemp.createTemp('parser_utf8');
      final f = File('${dir.path}/utf8.txt');
      await f.writeAsBytes(utf8.encode('第一章\n正文内容'));
      try {
        final content = await readFileContent(f.path);
        expect(content, contains('第一章'));
        expect(content, contains('正文内容'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('readFileContent: GBK 文件回退成功', () async {
      final dir = await Directory.systemTemp.createTemp('parser_gbk');
      final f = File('${dir.path}/gbk.txt');
      await f.writeAsBytes(gbk.encode('第一章\n简体中文内容。'));
      try {
        final content = await readFileContent(f.path);
        expect(content, contains('第一章'));
        expect(content, contains('简体中文内容'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('readFileContent: 非 UTF-8/GBK 二进制 → 抛异常（留痕）', () async {
      final dir = await Directory.systemTemp.createTemp('parser_bin');
      final f = File('${dir.path}/bin.txt');
      await f.writeAsBytes([0xFF, 0xFE, 0x00, 0x81, 0xE0]);
      try {
        await expectLater(readFileContent(f.path), throwsA(isA<Exception>()));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
