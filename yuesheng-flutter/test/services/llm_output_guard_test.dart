import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_output_guard.dart';

void main() {
  group('assessLlmOutput 三判据', () {
    test('空输出 / 全空白 → isBlank', () {
      expect(assessLlmOutput('').isBlank, isTrue);
      expect(assessLlmOutput('   \n  ').isBlank, isTrue);
      expect(assessLlmOutput('你好').isBlank, isFalse);
    });

    test('正常内容 → 无问题', () {
      final a = assessLlmOutput('第一章 清晨\n他推开门，看见晨光。');
      expect(a.isProblematic, isFalse);
    });

    test('重复 loop：连续相同行 ≥5 → hasRepetition', () {
      final content = List.filled(6, '这是一句重复的话。').join('\n');
      final a = assessLlmOutput(content);
      expect(a.hasRepetition, isTrue);
      expect(a.detail, contains('repetition'));
    });

    test('重复不足 5 行不误报', () {
      final content = List.filled(4, '重复的话').join('\n');
      expect(assessLlmOutput(content).hasRepetition, isFalse);
    });

    test('不同行不误报（正常写作）', () {
      final content = '第一行\n第二行\n第一行\n第二行\n第一行\n第二行';
      expect(assessLlmOutput(content).hasRepetition, isFalse);
    });

    test('元文本：模型身份声明 → hasMetaText', () {
      const samples = [
        '我是一个AI，无法完成这个任务',
        '好的，我作为语言模型来回答',
        '作为一个AI，我不能直接',
      ];
      for (final s in samples) {
        expect(assessLlmOutput(s).hasMetaText, isTrue, reason: s);
        expect(assessLlmOutput(s).detail, contains('meta'));
      }
    });

    test('正常写作含「我是」不误报', () {
      expect(assessLlmOutput('我是主角，走进房间。').hasMetaText, isFalse);
    });
  });

  group('extractJsonObject 容错', () {
    test('裸 JSON 对象', () {
      expect(extractJsonObject('{"a":1}'), '{"a":1}');
    });

    test('带 ```json 围栏', () {
      const raw = '好的，结果如下：\n```json\n{"a":1,"b":2}\n```\n完';
      expect(extractJsonObject(raw), '{"a":1,"b":2}');
    });

    test('围栏含语言标签', () {
      const raw = '```js\n{"x": [1,2]}\n```';
      expect(extractJsonObject(raw), '{"x": [1,2]}');
    });

    test('嵌套对象：字符串内括号不计', () {
      const raw = '{"a":{"b":"包含}括号"},"c":2}';
      expect(extractJsonObject(raw), '{"a":{"b":"包含}括号"},"c":2}');
    });

    test('顶层数组', () {
      expect(extractJsonObject('[1,2,3]'), '[1,2,3]');
    });

    test('元文本 + 对象混合', () {
      const raw = '好的，以下是结果：{"a":1} 希望对你有帮助';
      expect(extractJsonObject(raw), '{"a":1}');
    });

    test('尾逗号清理', () {
      expect(extractJsonObject('{"a":1,"b":2,}'), '{"a":1,"b":2}');
    });

    test('无 JSON → null', () {
      expect(extractJsonObject('没有 JSON 内容'), isNull);
      expect(extractJsonObject(''), isNull);
    });
  });
}
