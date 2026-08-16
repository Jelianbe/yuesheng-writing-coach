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
    test('#5 按 `# ` 一级标题切章', () {
      const content = '# 序章\n序章内容。\n# 正文\n正文内容。\n## 二级标题\n不切分。';

      final result = parseMdFile(content, 'book.md');

      expect(result.title, 'book');
      expect(result.chapters.length, 2);
      expect(result.chapters[0].title, '序章');
      expect(result.chapters[0].content, contains('序章内容'));
      expect(result.chapters[1].title, '正文');
      // 二级标题不切分，归入正文章节
      expect(result.chapters[1].content, contains('二级标题'));
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
}
