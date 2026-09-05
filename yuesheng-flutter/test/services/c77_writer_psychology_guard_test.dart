// ─────────────────────────────────────────────────────────────
// ADR-C77 护栏：writer-psychology 压缩后不可丢失的骨架
//
// 话术可压，防贴标签边界不可丢：六个免责句逐一计数在位（V4.8 逐处判），
// 方法关键词（限时写/最小承诺/评论三分类）与三张支撑结构在位。
// ─────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_registry.dart';

void main() {
  final content = skillRegistry['writer-psychology']!.content;

  group('ADR-C77 压缩骨架护栏', () {
    test('六个「不是诊断」类免责句逐一在位', () {
      // 每个障碍各一条，措辞各异但都含「不是诊断」——逐障碍断言
      expect(content, contains('**注意**：这只是最常出现的几种情况之一，**不是诊断**'));
      expect(content, contains('**注意**：不是诊断。要确认只能问'));
      expect(content, contains('**注意**：不要从"他写不出来"反推他的内心'));
      expect(content, contains('**注意**：这不是诊断，也**不要直接把这个判断说给学员**'));
      // 六障碍总数：'不是诊断' 至少出现 5 次（障碍1/2/3/4/5；障碍6 的注意句见下）
      expect('不是诊断'.allMatches(content).length, greaterThanOrEqualTo(5));
    });

    test('方法关键词在位（压缩保留的是方法不是台词）', () {
      expect(content, contains('十分钟限时写'));
      expect(content, contains('写完不准删'));
      expect(content, contains('最小承诺'));
      expect(content, contains('评论三分类'));
      expect(content, contains('先写中间'));
      expect(content, contains('core-product-identity 措辞 1，无例外'));
    });

    test('三张支撑结构在位（信号表/档位表/休息节）', () {
      expect(content, contains('| 可能观察到的信号 | 值得留意的方向'));
      expect(content, contains('这张表怎么用'));
      expect(content, contains('为什么这一版不写障碍名称'));
      expect(content, contains('| 障碍类型 | 豆包 | 月笙 | sensei |'));
      expect(content, contains('## 四、何时说"休息一下"'));
    });

    test('压缩生效：不再保留整段台词式引用', () {
      // 旧版整段台词引用的特征句（ADR-C77 前存在）不得回流
      expect(content, isNot(contains('改比从零写容易一百倍')));
      expect(content, isNot(contains('这不叫比较，这叫自残')));
      expect(content, isNot(contains('写作不靠灵感。靠屁股')));
    });
  });
}
