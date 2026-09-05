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
//
// C78 批次2b 追加（§5.3 F07 过滤判据 `if (event.stale) continue;`，一个判据一条）：
//   9. 正向基准：stale=false 的关键事件缺前因 → 照常检出
//   10. stale=true（章节已删/已改写）→ 跳过（幽灵 F07，D-8）
//   11. 混排：stale 逐条生效，只保留非 stale 的观察项
//
// 注：本文件 9 个 record 字面量已全部补 `stale: false`——typedef 加字段后
// 无类型标注的字面量全部编译失败，这是刻意的（编译器强制每个构造点表态）。
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
        stale: false,
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
        stale: false,
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
        stale: false,
      ),
      (
        name: '阿禾与捕快争执',
        chapter: 3,
        eventType: '冲突',
        causeEventId: null,
        effectEventId: null,
        stale: false,
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
        stale: false,
      ),
      (
        name: '阿禾突然辞官',
        chapter: 2,
        eventType: '突发',
        causeEventId: null,
        effectEventId: null,
        stale: false,
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
        stale: false,
      ),
      (
        name: '有章节事件',
        chapter: 1,
        eventType: '转折',
        causeEventId: null,
        effectEventId: null,
        stale: false,
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
        stale: false,
      ),
    ]);

    final ctx = buildCausalityBreakContext(observations);
    expect(ctx, isNotNull);
    expect(ctx, contains('因果链断裂观察'));
    expect(ctx, contains('第5章「阿禾决定去金陵」（决定类）缺触发事件'));
    expect(ctx, contains('P021'));
  });

  // ── C78 批次2b（§5.3）─────────────────────────────────────────
  // F07 过滤判据 `if (event.stale) continue;`——stale 写进 EventFactInput
  // typedef 而非在调用点 `.where()` 过滤，正是为了让编译器强制每个构造点
  // 表态（本文件 9 个字面量全部因此编译报错而不得不补 `stale`，ADR 已预判）。
  group('F07 过滤判据（stale 跳过）', () {
    test('#9 正向基准：stale=false 的关键事件缺前因 → 照常检出', () {
      final result = detectCausalityBreaks([
        (
          name: '阿禾决定去金陵',
          chapter: 5,
          eventType: '决定',
          causeEventId: null,
          effectEventId: null,
          stale: false,
        ),
      ]);

      expect(result.length, 1);
    });

    test('#10 stale=true（章节已删/已改写）→ 跳过', () {
      // D-8：事件所属章节都不在了，报「缺触发事件」是给用户报不存在的断裂。
      final result = detectCausalityBreaks([
        (
          name: '阿禾决定去金陵',
          chapter: 5,
          eventType: '决定',
          causeEventId: null,
          effectEventId: null,
          stale: true,
        ),
      ]);

      expect(result, isEmpty, reason: '幽灵 F07 不得报出');
    });

    test('#11 混排：stale 逐条生效，只保留非 stale 的观察项', () {
      final result = detectCausalityBreaks([
        (
          name: '旧事件（已删章）',
          chapter: 3,
          eventType: '决定',
          causeEventId: null,
          effectEventId: null,
          stale: true,
        ),
        (
          name: '当前事件',
          chapter: 8,
          eventType: '突发',
          causeEventId: null,
          effectEventId: null,
          stale: false,
        ),
      ]);

      expect(result.length, 1);
      expect(result.first.name, '当前事件', reason: 'stale 那条被跳过，不得连带吃掉同批的合法观察项');
    });
  });
}
