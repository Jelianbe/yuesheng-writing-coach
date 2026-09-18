// setting_assertion_extractor_test — 正文提炼断言解析器测试（创建体验 A2）
//
//   1. 标准 JSON 数组 → 断言（pending/ai/chapterSortOrder）
//   2. ```json 围栏 + 前导文本 → 截取解析
//   3. 非 JSON / 缺字段项 → 容错（跳过 + 空数组）
//   4. 空数组 / 全无效 → 空列表
//   5. `N12-F3c` 章号落点：身份必须进 **chapterSortOrder**，旧列 `chapter` 留空
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/setting_assertion_extractor.dart';

void main() {
  test('#1 标准 JSON 数组 → pending/ai 断言', () {
    final result = parseExtractedAssertions(
      '[{"attribute": "身份", "value": "守夜人"},'
      '{"attribute": "武器", "value": "青铜剑"}]',
      chapterIdentity: 3,
    );
    expect(result.length, 2);
    expect(result[0].attribute, '身份');
    expect(result[0].value, '守夜人');
    expect(result[0].status, 'pending');
    expect(result[0].source, 'ai');
  });

  test('#5 章号落**身份载体** `chapterSortOrder`，旧列 `chapter` 留空（`N12-F3c`）', () {
    // 判别性：身份取 7（一个不可能是「展示号直觉值」的数），旧列必须为 null。
    // 若退回旧写法（把身份写进 `chapter`），本用例前两条断言同时转红。
    final result = parseExtractedAssertions(
      '[{"attribute": "身份", "value": "守夜人"}]',
      chapterIdentity: 7,
    );
    expect(result.single.chapterSortOrder, 7, reason: '身份落新载体');
    expect(
      result.single.chapter,
      isNull,
      reason: '旧列装的是「用户原写的数 / AI 标称号」，提炼协议里没有它 ⇒ 不得占用',
    );
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
