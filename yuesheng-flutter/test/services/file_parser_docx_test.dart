// ─────────────────────────────────────────────────────────────
// file_parser .docx 直读测试（C144 W1）
//
// 覆盖（ADR-C144 §5 DoD #1 / #2）：
//   1. extractDocxText：ZIP→word/document.xml→纯文本（段落换行）
//   2. readFileContent：.docx 走专用提取，parseDocument 复用 txt 切章
//   3. 损坏路径：非 ZIP / 缺 document.xml / 空文件 → 抛异常（不崩，留痕）
//
// fixture：用 archive.ZipEncoder 手工造最小 .docx（ZIP 容器含
// word/document.xml），不依赖任何真实 Word 产物。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/file_parser.dart';

/// 构造最小 .docx 字节：ZIP 容器，内含 word/document.xml。
List<int> _buildDocxBytes(String documentXml) {
  final encoder = ZipEncoder();
  final archive = Archive();
  archive.addFile(
    ArchiveFile.bytes('word/document.xml', utf8.encode(documentXml)),
  );
  return encoder.encode(archive);
}

const _kDocXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
<w:p><w:r><w:t>第一章 开端</w:t></w:r></w:p>
<w:p><w:r><w:t>这是第一章正文。</w:t></w:r></w:p>
<w:p><w:r><w:t>第二章 展开</w:t></w:r></w:p>
<w:p><w:r><w:t>这是第二章正文。</w:t></w:r></w:p>
</w:body>
</w:document>
''';

void main() {
  group('extractDocxText（C144 W1）', () {
    test('#1 ZIP→document.xml→纯文本，段落以换行拼接', () {
      final bytes = _buildDocxBytes(_kDocXml);
      final text = extractDocxText(bytes);

      expect(text, contains('第一章 开端'));
      expect(text, contains('这是第一章正文。'));
      expect(text, contains('第二章 展开'));
      expect(text, contains('这是第二章正文。'));
      // 段落之间换行（切章依赖行结构）
      expect(text, contains('\n'));
    });

    test('#2 提取文本喂 parseDocument → 复用 txt 切章（不改 prompt）', () {
      final bytes = _buildDocxBytes(_kDocXml);
      final text = extractDocxText(bytes);

      final parsed = parseDocument(text, '我的小说.docx');
      expect(parsed.title, '我的小说');
      expect(parsed.chapters.length, 2);
      expect(parsed.chapters[0].title, '第一章 开端');
      expect(parsed.chapters[0].content, contains('这是第一章正文。'));
      expect(parsed.chapters[1].title, '第二章 展开');
      expect(parsed.chapters[1].content, contains('这是第二章正文。'));
    });

    test('#3 readFileContent：.docx 文件走专用提取（端到端落盘读取）', () async {
      final dir = await Directory.systemTemp.createTemp('parser_docx');
      final f = File('${dir.path}/novel.docx');
      await f.writeAsBytes(_buildDocxBytes(_kDocXml));
      try {
        final content = await readFileContent(f.path);
        expect(content, contains('第一章 开端'));
        expect(content, contains('这是第二章正文。'));
        // 入库前再切章，验证与既有章节链打通
        final parsed = parseDocument(
          content,
          f.path.split(Platform.pathSeparator).last,
        );
        expect(parsed.chapters.length, 2);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('extractDocxText 失败路径（DoD #2 · R-028 优雅降级）', () {
    test('#4 非 ZIP 二进制 → 抛异常（不崩）', () async {
      final dir = await Directory.systemTemp.createTemp('parser_docx_bad');
      final f = File('${dir.path}/bad.docx');
      // 随机字节，不是合法 ZIP 本地文件头（PK）
      await f.writeAsBytes([0x00, 0x11, 0x22, 0x33, 0x44, 0x55]);
      try {
        await expectLater(readFileContent(f.path), throwsA(isA<Exception>()));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('#5 合法 ZIP 但缺 word/document.xml → FormatException', () {
      final encoder = ZipEncoder();
      final archive = Archive();
      archive.addFile(ArchiveFile.bytes('other.txt', utf8.encode('hello')));
      final bytes = encoder.encode(archive);

      expect(() => extractDocxText(bytes), throwsA(isA<FormatException>()));
    });

    test('#6 空文件（0 字节）→ 抛异常（不崩）', () async {
      final dir = await Directory.systemTemp.createTemp('parser_docx_empty');
      final f = File('${dir.path}/empty.docx');
      await f.writeAsBytes(const <int>[]);
      try {
        await expectLater(readFileContent(f.path), throwsA(isA<Exception>()));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
