// ─────────────────────────────────────────────────────────────
// fact_parser_test — A6 时序知识图谱事实提取块解析单元测试
//
// 覆盖：
//   1. 无标记 → null
//   2. 标记不完整（缺结束）但 JSON 完整 → S6 容错解析成功
//   3. 合法 JSON（三类事实齐全）→ 解析成功
//   4. 非法 JSON → null
//   5. 字段校验失败（name 空 / assertions 非列表）→ 跳过非法条目
//   6. 仅人物事实（事件/支线为空数组）→ 解析成功
//   7. 仅事件事实
//   8. 仅支线事实
//   9-11. stripFactBlock 行为
//   12. S6 截断容错：JSON 中途截断
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/fact_parser.dart';

void main() {
  group('parseFactExtraction', () {
    test('#1 无标记 → null', () {
      expect(parseFactExtraction('今天写得不错。'), isNull);
    });

    test('#2 标记不完整（缺结束标记）但 JSON 完整 → S6 容错解析成功', () {
      final result = parseFactExtraction(
        '[YS_FACT]{"characters":[],"events":[],"subplots":[]}',
      );
      // 三类全空 → 返回 null（isEmpty 优化）
      expect(result, isNull);
    });

    test('#3 合法 JSON（三类事实齐全）→ 解析成功', () {
      const raw =
          '[YS_FACT]\n'
          '{"characters":[{"name":"阿禾","assertions":['
          '{"attribute":"独生子女状态","value":"独生子","chapter":3}]}],'
          '"events":[{"name":"阿禾决定去金陵","event_type":"决定","chapter":5,'
          '"participants":["阿禾"],"description":"离家寻亲"}],'
          '"subplots":[{"name":"钥匙的秘密","introduced_chapter":3,'
          '"resolved_chapter":null,"description":"神秘钥匙"}]}\n'
          '[/YS_FACT]';
      final result = parseFactExtraction(raw);
      expect(result, isNotNull);
      expect(result!.characters.length, 1);
      expect(result.events.length, 1);
      expect(result.subplots.length, 1);

      final c = result.characters.first;
      expect(c.name, '阿禾');
      expect(c.assertions.length, 1);
      expect(c.assertions.first.attribute, '独生子女状态');
      expect(c.assertions.first.value, '独生子');
      expect(c.assertions.first.chapter, 3);

      final e = result.events.first;
      expect(e.name, '阿禾决定去金陵');
      expect(e.eventType, '决定');
      expect(e.chapter, 5);
      expect(e.participants, ['阿禾']);
      expect(e.description, '离家寻亲');

      final s = result.subplots.first;
      expect(s.name, '钥匙的秘密');
      expect(s.introducedChapter, 3);
      expect(s.resolvedChapter, isNull);
      expect(s.description, '神秘钥匙');
    });

    test('#3b 事件 cause_event_name 解析（批次3-D4）', () {
      const raw =
          '[YS_FACT]\n'
          '{"events":['
          '{"name":"阿禾决定去金陵","event_type":"决定","chapter":5,'
          '"participants":["阿禾"],"description":"离家寻亲",'
          '"cause_event_name":"父亲病重"},'
          '{"name":"父亲病重","event_type":"突发","chapter":3,'
          '"participants":["父亲"],"description":"突发疾病"}'
          ']}\n'
          '[/YS_FACT]';
      final result = parseFactExtraction(raw);
      expect(result, isNotNull);
      expect(result!.events.length, 2);
      final decision = result.events.firstWhere((e) => e.name == '阿禾决定去金陵');
      expect(decision.causeEventName, '父亲病重');
      final trigger = result.events.firstWhere((e) => e.name == '父亲病重');
      expect(trigger.causeEventName, isNull, reason: '开篇事件无前因');
    });

    test('#3c cause_event_name 空字符串 → null（批次3-D4）', () {
      const raw =
          '[YS_FACT]\n'
          '{"events":['
          '{"name":"开篇事件","event_type":"日常","chapter":1,'
          '"participants":[],"description":"开篇","cause_event_name":""}'
          ']}\n'
          '[/YS_FACT]';
      final result = parseFactExtraction(raw);
      expect(result, isNotNull);
      expect(result!.events.single.causeEventName, isNull, reason: '空字符串视为无前因');
    });

    test('#4 非法 JSON → null', () {
      expect(parseFactExtraction('[YS_FACT]{not-json}[/YS_FACT]'), isNull);
    });

    test('#5 字段校验失败 → 跳过非法条目保留合法条目', () {
      // name 空 → 跳过；assertions 非列表 → 跳过；保留合法条目
      const raw =
          '[YS_FACT]\n'
          '{"characters":['
          '{"name":"","assertions":[{"attribute":"x","value":"y","chapter":1}]},'
          '{"name":"合法人物","assertions":"not-a-list"},'
          '{"name":"阿禾","assertions":[{"attribute":"职业","value":"捕快","chapter":3}]}'
          ']}\n'
          '[/YS_FACT]';
      final result = parseFactExtraction(raw);
      expect(result, isNotNull);
      expect(result!.characters.length, 1);
      expect(result.characters.first.name, '阿禾');
    });

    test('#6 仅人物事实（事件/支线缺字段）→ 解析成功', () {
      const raw =
          '[YS_FACT]\n'
          '{"characters":[{"name":"王建国","assertions":['
          '{"attribute":"性格","value":"冷酷","chapter":1}]}]}\n'
          '[/YS_FACT]';
      final result = parseFactExtraction(raw);
      expect(result, isNotNull);
      expect(result!.characters.length, 1);
      expect(result.events, isEmpty);
      expect(result.subplots, isEmpty);
    });

    test('#7 仅事件事实 → 解析成功', () {
      const raw =
          '[YS_FACT]\n'
          '{"events":[{"name":"城门冲突","event_type":"冲突","chapter":7,'
          '"participants":[],"description":"两派争斗"}]}\n'
          '[/YS_FACT]';
      final result = parseFactExtraction(raw);
      expect(result, isNotNull);
      expect(result!.events.length, 1);
      expect(result.characters, isEmpty);
      expect(result.subplots, isEmpty);
    });

    test('#8 仅支线事实（含回收）→ 解析成功', () {
      const raw =
          '[YS_FACT]\n'
          '{"subplots":[{"name":"复仇线","introduced_chapter":2,'
          '"resolved_chapter":15,"description":"大仇得报"}]}\n'
          '[/YS_FACT]';
      final result = parseFactExtraction(raw);
      expect(result, isNotNull);
      expect(result!.subplots.length, 1);
      final s = result.subplots.first;
      expect(s.resolvedChapter, 15);
    });

    test('#9 事件字段兼容 camelCase（eventType / introducedChapter）', () {
      const raw =
          '[YS_FACT]\n'
          '{"events":[{"name":"转折点","eventType":"转折","chapter":8,'
          '"participants":[],"description":"x"}],'
          '"subplots":[{"name":"支线A","introducedChapter":1,'
          '"resolvedChapter":5,"description":"y"}]}\n'
          '[/YS_FACT]';
      final result = parseFactExtraction(raw);
      expect(result, isNotNull);
      expect(result!.events.first.eventType, '转折');
      expect(result.subplots.first.introducedChapter, 1);
      expect(result.subplots.first.resolvedChapter, 5);
    });
  });

  group('stripFactBlock', () {
    test('#10 无标记 → 原样返回', () {
      expect(stripFactBlock('诊断完成，继续努力。'), '诊断完成，继续努力。');
    });

    test('#11 完整块 → 整块移除，前后文本拼接', () {
      const raw = '诊断完成。\n[YS_FACT]{"characters":[]}\n[/YS_FACT]\n明天继续。';
      expect(stripFactBlock(raw), '诊断完成。\n明天继续。');
    });

    test('#12 有起始无结束 → 自标记起截断（防泄漏）', () {
      const raw = '诊断完成。\n[YS_FACT]{"characters":';
      expect(stripFactBlock(raw), '诊断完成。');
    });

    test('#13 块在开头 → 移除后返回尾部', () {
      const raw = '[YS_FACT]{"events":[]}[/YS_FACT]\n这是诊断。';
      expect(stripFactBlock(raw), '这是诊断。');
    });
  });

  group('S6 截断容错', () {
    test('#14 JSON 中途截断（缺闭合括号）→ 容错补全后解析成功', () {
      // 模拟流式输出截断：JSON 未闭合
      const raw =
          '[YS_FACT]\n'
          '{"characters":[{"name":"阿禾","assertions":['
          '{"attribute":"身份","value":"书生","chapter":2}]}';
      // 无结束标记 + JSON 截断 → tryParseJsonWithRecovery 补全
      final result = parseFactExtraction(raw);
      expect(result, isNotNull);
      expect(result!.characters.length, 1);
      expect(result.characters.first.name, '阿禾');
    });
  });
}
