// ─────────────────────────────────────────────────────────────
// ADR-C76 护栏：genre-guide 体裁技法矩阵「注入边界」自含
//
// 防 C57 同族复发：矩阵推荐技法（与 L3 注入零交集）必须自带未注入时的
// 合法行为与禁止行为，不得指向不存在的「完整技法库」。
// ─────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_registry.dart';

void main() {
  final content = skillRegistry['genre-guide']!.content;

  group('ADR-C76 注入边界护栏', () {
    test('边界段存在且声明有意分层', () {
      expect(content, contains('**注入边界**'));
      expect(content, contains('**有意分层**（ADR-C76）'));
    });

    test('未注入时的合法行为与禁止行为在位', () {
      expect(content, contains('按技法名的字面方法教学'));
      expect(content, contains('退回该症候默认映射中已注入的技法'));
      expect(content, contains('不要虚构技法的详细步骤'));
      expect(content, contains('不要向学员提及"完整技法库"'));
    });

    test('矩阵本体与选择原则未被波及', () {
      expect(content, contains('**选择原则**：选择与该体裁"读者合同"一致的技法'));
      expect(content, contains('T003 感官特写'));
      expect(content, contains('T019 倒计时法'));
    });
  });
}
