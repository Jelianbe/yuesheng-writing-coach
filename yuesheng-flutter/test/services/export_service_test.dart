// ─────────────────────────────────────────────────────────────
// export_service_test — 导出服务纯函数测试（批次94-1）
// 覆盖：单章 TXT/MD / 单卷 / 整书（卷分组+未分卷+无卷平铺+空书）/ 文件名清洗
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/services/export_service.dart';

Chapter _chapter(
  String title,
  String content, {
  String? volumeId,
  int sortOrder = 0,
}) {
  return Chapter(
    id: 'c-$title',
    manuscriptId: 'm1',
    volumeId: volumeId,
    title: title,
    content: content,
    wordCount: content.length,
    sortOrder: sortOrder,
    status: 'draft',
    createdAt: 0,
    updatedAt: 0,
  );
}

Volume _volume(String id, String title, {int sortOrder = 0}) {
  return Volume(
    id: id,
    manuscriptId: 'm1',
    title: title,
    sortOrder: sortOrder,
    createdAt: 0,
    updatedAt: 0,
  );
}

Manuscript _manuscript(String title) {
  return Manuscript(
    id: 'm1',
    title: title,
    description: '',
    genre: '',
    tags: '[]',
    language: '中文',
    status: 'active',
    sortOrder: 0,
    createdAt: 0,
    updatedAt: 0,
  );
}

void main() {
  group('buildChapterExportText', () {
    test('TXT 格式：标题行 + 分隔线 + 正文', () {
      final text = buildChapterExportText(
        _chapter('第一章', '正文内容'),
        format: ExportFormat.txt,
        chapterNo: 1,
      );
      expect(text, '第1章 第一章\n──────\n正文内容');
    });

    test('Markdown 格式：### 标题 + 正文', () {
      final text = buildChapterExportText(
        _chapter('第一章', '正文内容'),
        format: ExportFormat.markdown,
      );
      expect(text, '### 第一章\n\n正文内容');
    });

    test('空正文章节给出占位提示（不丢失标题）', () {
      final txt = buildChapterExportText(
        _chapter('空章', ''),
        format: ExportFormat.txt,
      );
      expect(txt, contains('空章'));
      expect(txt, contains('（本章暂无正文）'));
    });

    test('空标题回退「未命名章节」', () {
      final text = buildChapterExportText(
        _chapter('', '内容'),
        format: ExportFormat.txt,
      );
      expect(text, startsWith('未命名章节'));
    });
  });

  group('buildVolumeExportText', () {
    test('卷内章节按 sortOrder 排序拼接', () {
      final text = buildVolumeExportText(
        _volume('v1', '第一卷'),
        [
          _chapter('第二章', 'B', volumeId: 'v1', sortOrder: 1),
          _chapter('第一章', 'A', volumeId: 'v1', sortOrder: 0),
        ],
        format: ExportFormat.txt,
      );
      expect(text, contains('《第一卷》'));
      expect(text.indexOf('第一章'), lessThan(text.indexOf('第二章')));
    });

    test('Markdown 卷标题为 ##', () {
      final text = buildVolumeExportText(
        _volume('v1', '第一卷'),
        [_chapter('第一章', 'A', volumeId: 'v1')],
        format: ExportFormat.markdown,
      );
      expect(text, startsWith('## 第一卷'));
    });
  });

  group('buildManuscriptExportText', () {
    test('有卷：书名 + 卷分组 + 未分卷置末', () {
      final text = buildManuscriptExportText(
        _manuscript('山月记'),
        [
          _volume('v1', '第一卷'),
          _volume('v2', '第二卷'),
        ],
        [
          _chapter('散章', '未分卷内容', sortOrder: 5),
          _chapter('第一章', '卷一内容', volumeId: 'v1', sortOrder: 0),
          _chapter('第二章', '卷二内容', volumeId: 'v2', sortOrder: 0),
        ],
        format: ExportFormat.txt,
      );
      expect(text, startsWith('《山月记》'));
      // 卷标题与未分卷内容都出现，未分卷排在卷之后
      expect(text, contains('《第一卷》'));
      expect(text, contains('《第二卷》'));
      expect(text, contains('未分卷内容'));
      expect(text.indexOf('未分卷内容'), greaterThan(text.indexOf('《第二卷》')));
    });

    test('无卷：章节按顺序平铺（不出现《卷名》）', () {
      final text = buildManuscriptExportText(
        _manuscript('山月记'),
        const [],
        [
          _chapter('第二章', 'B', sortOrder: 1),
          _chapter('第一章', 'A', sortOrder: 0),
        ],
        format: ExportFormat.txt,
      );
      expect(text.indexOf('第一章'), lessThan(text.indexOf('第二章')));
      expect(text, isNot(contains('《第一卷》')));
    });

    test('空书：整书占位提示', () {
      final text = buildManuscriptExportText(
        _manuscript('山月记'),
        const [],
        const [],
        format: ExportFormat.txt,
      );
      expect(text, contains('（暂无章节）'));
    });

    test('Markdown 整书以 # 书名开头', () {
      final text = buildManuscriptExportText(
        _manuscript('山月记'),
        const [],
        [_chapter('第一章', 'A')],
        format: ExportFormat.markdown,
      );
      expect(text, startsWith('# 山月记'));
    });
  });

  group('exportFileName', () {
    test('清洗 Windows/Unix 非法字符', () {
      expect(
        exportFileName('山/月\\记:*?"<>|', ExportFormat.txt),
        '山月记.txt',
      );
    });
    test('全非法字符回退「导出」', () {
      expect(exportFileName('///\\\\', ExportFormat.markdown), '导出.md');
    });
    test('扩展名跟随格式', () {
      expect(exportFileName('测试', ExportFormat.txt), '测试.txt');
      expect(exportFileName('测试', ExportFormat.markdown), '测试.md');
    });
  });

  group('ExportFormat', () {
    test('txt/markdown 扩展名', () {
      expect(ExportFormat.txt.extension, 'txt');
      expect(ExportFormat.markdown.extension, 'md');
    });
  });
}
