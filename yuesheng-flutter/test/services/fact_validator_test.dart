// ─────────────────────────────────────────────────────────────
// D4 批次9：fact_validator 独立校验层测试
// 覆盖：人物/事件/支线三类 schema + 宽松策略（非法条目逐条跳过）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/fact_validator.dart';

void main() {
  group('validateFactSchema（宽松：非法条目逐条跳过）', () {
    test('#F1 三类合法 → valid + data 完整', () {
      final result = validateFactSchema({
        'characters': [
          {
            'name': '林晚',
            'assertions': [
              {'attribute': '性格', 'value': '冷静', 'chapter': 1, 'timestamp': 100},
            ],
          },
        ],
        'events': [
          {
            'name': '林家遇袭',
            'event_type': 'conflict',
            'chapter': 3,
            'participants': ['林晚', '黑衣人'],
            'description': '深夜林家被袭',
            'cause_event_name': '林父失踪',
          },
        ],
        'subplots': [
          {
            'name': '家产争夺',
            'introduced_chapter': 2,
            'resolved_chapter': 10,
            'description': '主线暗线',
          },
        ],
      });
      expect(result.valid, isTrue);
      final data = result.data!;
      expect(data.characters.length, 1);
      expect(data.characters.first.name, '林晚');
      expect(data.characters.first.assertions.single.attribute, '性格');
      expect(data.events.length, 1);
      expect(data.events.first.eventType, 'conflict');
      expect(data.events.first.causeEventName, '林父失踪');
      expect(data.subplots.length, 1);
      expect(data.subplots.first.introducedChapter, 2);
      expect(data.subplots.first.resolvedChapter, 10);
    });

    test('#F2 单类存在即可 → valid', () {
      final onlyEvents = validateFactSchema({
        'events': [
          {'name': '开篇', 'event_type': 'opening'},
        ],
      });
      expect(onlyEvents.valid, isTrue);
      expect(onlyEvents.data!.events.length, 1);
      expect(onlyEvents.data!.characters, isEmpty);
    });

    test('#F3 非法条目被跳过，合法条目保留（逐条隔离）', () {
      final result = validateFactSchema({
        'characters': [
          {'name': '', 'assertions': []}, // 非法：空 name
          {
            'name': '林晚',
            'assertions': [
              {'attribute': '职业', 'value': '捕快'},
            ],
          },
          'not-a-map', // 非法：非对象
        ],
        'events': [
          {'name': '事件', 'event_type': 42}, // 非法：event_type 非字符串
          {'name': '合法事件', 'event_type': 'conflict'},
        ],
      });
      expect(result.valid, isTrue); // 仍有合法条目
      expect(result.data!.characters.length, 1);
      expect(result.data!.characters.first.name, '林晚');
      expect(result.data!.events.length, 1);
      expect(result.data!.events.first.name, '合法事件');
      expect(result.errors, isNotEmpty); // 跳过的条目有观测记录
    });

    test('#F4 三类全空/全非法 → invalid + data null', () {
      expect(validateFactSchema({'characters': []}).valid, isFalse);
      final onlyBad = validateFactSchema({
        'characters': [
          {'name': '', 'assertions': []},
        ],
      });
      expect(onlyBad.valid, isFalse);
      expect(onlyBad.data, isNull);
    });

    test('#F5 根对象非 Map → invalid', () {
      expect(validateFactSchema('not-an-object').valid, isFalse);
      expect(validateFactSchema(null).valid, isFalse);
    });

    test('#F6 event_type/eventType 双键 + 空 cause → null', () {
      final camel = validateFactSchema({
        'events': [
          {
            'name': '聚会',
            'eventType': 'social',
            'causeEventName': '',
          },
        ],
      });
      expect(camel.valid, isTrue);
      expect(camel.data!.events.first.eventType, 'social');
      expect(camel.data!.events.first.causeEventName, isNull); // 空 → null
    });

    test('#F7 subplot snake/camel 双键章节 + description 缺省空串', () {
      final result = validateFactSchema({
        'subplots': [
          {
            'name': '副线',
            'introducedChapter': 5,
            'resolvedChapter': 8,
          },
        ],
      });
      expect(result.valid, isTrue);
      expect(result.data!.subplots.first.introducedChapter, 5);
      expect(result.data!.subplots.first.resolvedChapter, 8);
      expect(result.data!.subplots.first.description, '');
    });

    test('#F8 断言全非法 → 该人物被丢弃', () {
      final result = validateFactSchema({
        'characters': [
          {
            'name': '林晚',
            'assertions': [
              {'attribute': '', 'value': ''}, // tryFromJson 返回 null
            ],
          },
        ],
      });
      expect(result.valid, isFalse); // 无任何合法人物
      expect(result.data, isNull);
    });

    test('#F9 participants 过滤非字符串/空串', () {
      final result = validateFactSchema({
        'events': [
          {
            'name': '事件',
            'event_type': 'conflict',
            'participants': ['林晚', 42, ''],
          },
        ],
      });
      expect(result.valid, isTrue);
      expect(result.data!.events.first.participants, ['林晚']);
    });
  });
}
