// setting_assertion_extractor_test — 正文提炼断言解析器测试（创建体验 A2）
//
//   1. 标准 JSON 数组 → 断言（pending/ai/chapter）
//   2. ```json 围栏 + 前导文本 → 截取解析
//   3. 非 JSON / 缺字段项 → 容错（跳过 + 空数组）
//   4. 空数组 / 全无效 → 空列表
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/setting_assertion_extractor.dart';

void main() {
  test('#1 标准 JSON 数组 → pending/ai 断言', () {
    final result = parseExtractedAssertions(
      '[{"attribute": "身份", "value": "守夜人"},'
      '{"attribute": "武器", "value": "青铜剑"}]',
      chapter: 3,
    );
    expect(result.length, 2);
    expect(result[0].attribute, '身份');
    expect(result[0].value, '守夜人');
    expect(result[0].chapter, 3);
    expect(result[0].status, 'pending');
    expect(result[0].source, 'ai');
  });

  test('#2 围栏 + 前导文本容错', () {
    final result = parseExtractedAssertions(
      '好的，以下是提炼结果：\n```json\n'
      '[{"attribute": "外貌", "value": "银发"}]'
      '\n```',
    );
    expect(result.length, 1);
    expect(result.single.attribute, '外貌');
  });

  test('#3 缺字段项跳过 + 非 JSON 返回空', () {
    expect(
      parseExtractedAssertions('[{"attribute": "身份"}]'),
      isEmpty,
      reason: '缺 value 跳过',
    );
    expect(parseExtractedAssertions('这不是 JSON'), isEmpty);
    expect(parseExtractedAssertions('[]'), isEmpty);
  });

  test('#4 截断 JSON 容错（不抛）', () {
    expect(
      parseExtractedAssertions('[{"attribute": "身份", "value": "守夜人"}'),
      isEmpty,
      reason: '无闭合括号 → 截取失败',
    );
  });
}
