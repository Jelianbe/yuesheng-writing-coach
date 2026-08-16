// ─────────────────────────────────────────────────────────────
// SmartPunctuationFormatter 单元测试（批次85-6 智能标点）
//
// 覆盖路径：
//   1. 左配对符自动补全（「《【（），光标居中
//   2. 已配对中间继续插入左符 → 仍补全
//   3. 右符前输入相同右符 → 跳过不重复，光标移到右符后
//   4. 普通字符 / 删除 / 多字符粘贴 / 有选区 → 原样
//   5. 孤立右符（光标后无相同右符）→ 正常插入
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/smart_punctuation_formatter.dart';

void main() {
  const formatter = SmartPunctuationFormatter();

  TextEditingValue edit(
    String oldText,
    int oldCaret,
    String newText,
    int newCaret,
  ) {
    return formatter.formatEditUpdate(
      TextEditingValue(
        text: oldText,
        selection: TextSelection.collapsed(offset: oldCaret),
      ),
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newCaret),
      ),
    );
  }

  group('批次85-⑥：智能标点 formatter 单测', () {
    test('输入「 → 自动补「」光标居中', () {
      final r = edit('', 0, '「', 1);
      expect(r.text, '「」');
      expect(r.selection.baseOffset, 1);
    });

    test('输入《 / 【 / （ 同样补全', () {
      expect(edit('', 0, '《', 1).text, '《》');
      expect(edit('', 0, '【', 1).text, '【】');
      expect(edit('', 0, '（', 1).text, '（）');
    });

    test('已有文本中间输入「 → 补全且光标仍在中间', () {
      final r = edit('你好世界', 2, '你好「世界', 3);
      expect(r.text, '你好「」世界');
      expect(r.selection.baseOffset, 3);
    });

    test('光标在右符前输入相同右符 → 跳过不重复 + 光标移后', () {
      // 文本「」光标在中间（index 1），输入」→ 不新增，光标跳到 index 2
      final r = edit('「」', 1, '「」」', 2);
      expect(r.text, '「」');
      expect(r.selection.baseOffset, 2);
    });

    test('光标在句中右符前输入相同右符 → 跳过', () {
      // 光标停在「」前（index 2），输入」→ 不新增，光标跳到右符后（index 3）
      final r = edit('你好」世界', 2, '你好」」世界', 3);
      expect(r.text, '你好」世界');
      expect(r.selection.baseOffset, 3);
    });

    test('普通字符 → 原样', () {
      final r = edit('你好', 2, '你好啊', 3);
      expect(r.text, '你好啊');
      expect(r.selection.baseOffset, 3);
    });

    test('删除（文本变短）→ 原样', () {
      final r = edit('你好', 2, '你', 1);
      expect(r.text, '你');
    });

    test('多字符粘贴 → 原样不补全', () {
      final r = edit('', 0, '「你好」', 4);
      expect(r.text, '「你好」');
    });

    test('有选区输入左符 → 原样（不包选区）', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '你好世界',
          selection: TextSelection(baseOffset: 1, extentOffset: 3),
        ),
        const TextEditingValue(
          text: '你「世界',
          selection: TextSelection(baseOffset: 2, extentOffset: 2),
        ),
      );
      expect(result.text, '你「世界');
    });

    test('孤立右符（光标后无相同右符）→ 正常插入', () {
      final r = edit('你说', 2, '你说」', 3);
      expect(r.text, '你说」');
      expect(r.selection.baseOffset, 3);
    });
  });
}
