// ─────────────────────────────────────────────────────────────
// outline_parser_test — 批次72 大纲提取块解析单元测试
//
// 覆盖：
//   1. 无标记 → null
//   2. 标记不完整（缺结束）但 JSON 完整 → S6 容错解析成功
//   3. 合法 JSON（新实体） → 解析成功
//   4. 非法 JSON（非截断） → null
//   5. 字段校验失败（type 非法 / key 空 / impressions 非列表） → null
//   6. 带 matched_entity_id + conflict_with → 字段保留
//   7-9. stripOutlineBlock 行为
//   10-12. S6 截断容错：实体截断 / 字符串内截断 / 无法恢复
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/outline_parser.dart';

void main() {
  test('#1 无标记 → null', () {
    expect(parseOutlineExtraction('今天写得不错。'), isNull);
  });

  test('#2 标记不完整（缺结束标记）但 JSON 完整 → S6 容错解析成功', () {
    final result = parseOutlineExtraction('[YS_ENTITY]{"entities":[]}');
    expect(result, isNotNull);
    expect(result!.entities, isEmpty);
  });

  test('#3 合法 JSON（新实体）→ 解析成功', () {
    const raw =
        '[YS_ENTITY]{"entities":[{"type":"character","key":"王建国",'
        '"aliases":["王叔"],"impressions":[{"text":"冷酷的杀手，左眼有疤"}]}]}'
        '[/YS_ENTITY]';
    final result = parseOutlineExtraction(raw);
    expect(result, isNotNull);
    expect(result!.entities.length, 1);
    final e = result.entities.first;
    expect(e.type, 'character');
    expect(e.key, '王建国');
    expect(e.aliases, ['王叔']);
    expect(e.matchedEntityId, isNull);
    expect(e.impressions.single.text, '冷酷的杀手，左眼有疤');
    expect(e.impressions.single.conflictWith, isNull);
  });

  test('#4 非法 JSON（非截断性语法错误）→ null', () {
    expect(parseOutlineExtraction('[YS_ENTITY]{not-json}[/YS_ENTITY]'), isNull);
  });

  test('#5 字段校验失败 → null', () {
    // type 非法
    expect(
      parseOutlineExtraction(
        '[YS_ENTITY]{"entities":[{"type":"place","key":"城","impressions":[]}]}'
        '[/YS_ENTITY]',
      ),
      isNull,
    );
    // key 为空
    expect(
      parseOutlineExtraction(
        '[YS_ENTITY]{"entities":[{"type":"character","key":"  ","impressions":[]}]}'
        '[/YS_ENTITY]',
      ),
      isNull,
    );
    // impressions 非列表
    expect(
      parseOutlineExtraction(
        '[YS_ENTITY]{"entities":[{"type":"character","key":"王建国","impressions":"x"}]}'
        '[/YS_ENTITY]',
      ),
      isNull,
    );
    // 无 entities 字段
    expect(parseOutlineExtraction('[YS_ENTITY]{"foo":1}[/YS_ENTITY]'), isNull);
  });

  test('#6 带 matched_entity_id + conflict_with → 字段保留', () {
    const raw =
        '[YS_ENTITY]{"entities":[{"type":"character","key":"王建国",'
        '"matched_entity_id":"abc-123","impressions":[{"text":"温柔的丈夫",'
        '"conflict_with":"imp-999"}]}]}[/YS_ENTITY]';
    final result = parseOutlineExtraction(raw);
    expect(result, isNotNull);
    final e = result!.entities.single;
    expect(e.matchedEntityId, 'abc-123');
    expect(e.impressions.single.conflictWith, 'imp-999');
  });

  test('#7 stripOutlineBlock：完整块整块移除（批次74）', () {
    final stripped = stripOutlineBlock(
      '王建国这个人物塑造得很扎实。\n'
      '[YS_ENTITY]{"entities":[{"type":"character","key":"王建国"}]}'
      '[/YS_ENTITY]',
    );
    expect(stripped, '王建国这个人物塑造得很扎实。');
    expect(stripped.contains('YS_ENTITY'), false);
  });

  test('#8 stripOutlineBlock：无标记原样返回', () {
    const raw = '今天写得不错。';
    expect(stripOutlineBlock(raw), raw);
  });

  test('#9 stripOutlineBlock：有起始无结束 → 自标记起截断', () {
    final stripped = stripOutlineBlock(
      '前面正文[YS_ENTITY]{"entities":[{"type":"character",',
    );
    expect(stripped, '前面正文');
  });

  // ─── S6 截断容错测试 ───

  test('#10 S6 容错：实体 JSON 截断（缺结束标记 + 缺闭合符号）→ 补全解析', () {
    // 截断在 impressions 数组中间，缺少 ]}}
    final result = parseOutlineExtraction(
      '[YS_ENTITY]{"entities":[{"type":"character","key":"王建国",'
      '"aliases":["王叔"],"impressions":[{"text":"冷酷的杀手',
    );
    expect(result, isNotNull);
    expect(result!.entities.length, 1);
    final e = result.entities.first;
    expect(e.type, 'character');
    expect(e.key, '王建国');
    expect(e.aliases, ['王叔']);
    expect(e.impressions.single.text, '冷酷的杀手');
  });

  test('#11 S6 容错：截断在字符串值中间 → 补全引号 + 闭合符号', () {
    // 截断在 impressions text 值中间，字符串未闭合
    final result = parseOutlineExtraction(
      '[YS_ENTITY]{"entities":[{"type":"character","key":"王建国",'
      '"impressions":[{"text":"冷酷',
    );
    expect(result, isNotNull);
    expect(result!.entities.length, 1);
    expect(result.entities.first.key, '王建国');
    expect(result.entities.first.impressions.single.text, '冷酷');
  });

  test('#12 S6 容错：完整标记但 JSON 截断 → 补全解析', () {
    // 有结束标记但 JSON 内部截断（impressions 对象已闭合但数组未闭合）
    final result = parseOutlineExtraction(
      '[YS_ENTITY]{"entities":[{"type":"setting","key":"长安城",'
      '"impressions":[{"text":"古城"}[/YS_ENTITY]',
    );
    // impression 对象已闭合，但缺 ]}} → 补全后解析
    expect(result, isNotNull);
    expect(result!.entities.first.type, 'setting');
    expect(result.entities.first.key, '长安城');
    expect(result.entities.first.impressions.single.text, '古城');
  });

  test('#13 S6 容错：字符串内含花括号不误判', () {
    // 字符串内的 {} 不影响括号计数
    const raw =
        '[YS_ENTITY]{"entities":[{"type":"plot","key":"事件{1}",'
        '"impressions":[{"text":"描述{test}内容"}]}]}[/YS_ENTITY]';
    final result = parseOutlineExtraction(raw);
    expect(result, isNotNull);
    expect(result!.entities.first.key, '事件{1}');
    expect(result.entities.first.impressions.single.text, '描述{test}内容');
  });
}
