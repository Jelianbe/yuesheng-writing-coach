// ─────────────────────────────────────────────────────────────
// formatAttachedFilesContext 单元测试 — 锁定 A-1 token 止血行为
//
// A-1 将「书籍下所有文件完整内容全量注入」改为「标题 + 200 字开头摘要」
// 的清单式注入，避免每轮 token 爆炸。本测试锁定该契约不被回退。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';

void main() {
  group('formatAttachedFilesContext (A-1 止血)', () {
    test('空列表返回 null', () {
      expect(formatAttachedFilesContext([]), isNull);
    });

    test('大文件被截断为 200 字摘要，不再全量注入', () {
      final big = '月笙如歌' * 1000; // 4000 字
      final out = formatAttachedFilesContext([
        AttachedFileInfo(fileName: '大纲.txt', fileRole: 'outline', content: big),
      ]);
      expect(out, isNotNull);
      expect(out, contains('大纲.txt'));
      // 摘要截断提示存在，证明走清单式而非全量
      expect(out, contains('更多内容可通过 @ 引用获取'));
      // 输出远小于原始 4000 字（仅 200 字 + 标题/提示），证明非全量
      expect(out!.length, lessThan(big.length));
      expect(out.length, lessThan(400));
    });

    test('多个文件各自输出标题 + 摘要（清单式）', () {
      final out = formatAttachedFilesContext([
        AttachedFileInfo(
          fileName: 'a.txt',
          fileRole: 'normal',
          content: 'hello world content',
        ),
        AttachedFileInfo(
          fileName: '素材.md',
          fileRole: 'material',
          content: '素材片段内容',
        ),
      ]);
      expect(out, contains('a.txt'));
      expect(out, contains('素材.md'));
      expect(out, contains('hello world content'));
      expect(out, contains('素材片段内容'));
    });
  });
}
