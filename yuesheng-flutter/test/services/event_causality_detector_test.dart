// ─────────────────────────────────────────────────────────────
// event_causality_detector_test — 批次67 B62j F07 因果链断裂检测单元测试
//
// 覆盖：
//   1. 空输入 → 空数组
//   2. 关键事件（决定类）缺前因 → 因果链断裂观察项
//   3. 关键事件但有前因 → 不误报
//   4. 非关键事件（日常/冲突）无前因 → 不误报
//   5. 乱序输入 → 按章节升序输出
//   6. 章节 null 排最后
//   7. buildCausalityBreakContext：空 → null
//   8. buildCausalityBreakContext：非空 → 含观察与措辞
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/event_causality_detector.dart';

void main() {
  test('#1 空输入 → 空数组', () {
    expect(detectCausalityBreaks(const []), isEmpty);
  });

  test('#2 关键事件（决定类）缺前因 → 因果链断裂观察项', () {
    final result = detectCausalityBreaks([
      (
        name: '阿禾决定去金陵',
        chapter: 5,
        eventType: '决定',
        causeEventId: null,
        effectEventId: null,
      ),
    ]);

    expect(result.length, 1);
    final obs = result.first;
    expect(obs.name, '阿禾决定去金陵');
    expect(obs.chapter, 5);
    expect(obs.eventType, '决定');
    expect(obs.description, '第5章「阿禾决定去金陵」（决定类）缺触发事件');
  });

  test('#3 关键事件但有前因 → 不误报', () {
    final result = detectCausalityBreaks([
      (
        name: '阿禾决定去金陵',
        chapter: 5,
        eventType: '决定',
        causeEventId: 'event-1',
        effectEventId: null,
      ),
    ]);

    expect(result, isEmpty);
  });

  test('#4 非关键事件（日常/冲突）无前因 → 不误报', () {
    final result = detectCausalityBreaks([
      (
        name: '阿禾在茶楼喝茶',
        chapter: 2,
        eventType: '日常',
        causeEventId: null,
        effectEventId: null,
      ),
      (
        name: '阿禾与捕快争执',
        chapter: 3,
        eventType: '冲突',
        causeEventId: null,
        effectEventId: null,
      ),
    ]);

    expect(result, isEmpty);
  });

  test('#5 乱序输入 → 按章节升序输出', () {
    final result = detectCausalityBreaks([
      (
        name: '阿禾决定去金陵',
        chapter: 9,
        eventType: '决定',
        causeEventId: null,
        effectEventId: null,
      ),
      (
        name: '阿禾突然辞官',
        chapter: 2,
        eventType: '突发',
        causeEventId: null,
        effectEventId: null,
      ),
    ]);

    expect(result.length, 2);
    expect(result.first.name, '阿禾突然辞官');
    expect(result.first.description, '第2章「阿禾突然辞官」（突发类）缺触发事件');
    expect(result.last.name, '阿禾决定去金陵');
  });

  test('#6 章节 null 排最后', () {
    final result = detectCausalityBreaks([
      (
        name: '无章节事件',
        chapter: null,
        eventType: '转折',
        causeEventId: null,
        effectEventId: null,
      ),
      (
        name: '有章节事件',
        chapter: 1,
        eventType: '转折',
        causeEventId: null,
        effectEventId: null,
      ),
    ]);

    expect(result.first.name, '有章节事件');
    expect(result.first.description, '第1章「有章节事件」（转折类）缺触发事件');
    expect(result.last.name, '无章节事件');
    expect(result.last.description, '早期「无章节事件」（转折类）缺触发事件');
  });

  test('#7 buildCausalityBreakContext 空 → null', () {
    expect(buildCausalityBreakContext(const []), isNull);
  });

  test('#8 buildCausalityBreakContext 非空 → 含观察与措辞', () {
    final observations = detectCausalityBreaks([
      (
        name: '阿禾决定去金陵',
        chapter: 5,
        eventType: '决定',
        causeEventId: null,
        effectEventId: null,
      ),
    ]);

    final ctx = buildCausalityBreakContext(observations);
    expect(ctx, isNotNull);
    expect(ctx, contains('因果链断裂观察'));
    expect(ctx, contains('第5章「阿禾决定去金陵」（决定类）缺触发事件'));
    expect(ctx, contains('P021'));
  });
}
