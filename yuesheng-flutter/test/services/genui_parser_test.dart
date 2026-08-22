// ─────────────────────────────────────────────────────────────
// GenUI 协议层单测（B-1 GenUI v1）
//
// 覆盖：parser 提取/剥离/容错 + validator 白名单/spec guard + payload 往返。
// 纯逻辑，无 DB 依赖，跑得快。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/genui_parser.dart';
import 'package:writingcoach/services/genui_validator.dart';
import 'package:writingcoach/services/message_card_service.dart';

void main() {
  group('parseGenuiBlock', () {
    test('无标记 → null', () {
      expect(parseGenuiBlock('普通回复没有协议块'), isNull);
    });

    test('单个 quiz 组件解析', () {
      const text =
          '这是反馈\n[YS_GENUI]{"type":"quiz","title":"t",'
          '"items":[{"q":"q1","options":["a","b"],"answer":0}]}[/YS_GENUI]';
      final comps = parseGenuiBlock(text);
      expect(comps, isNotNull);
      expect(comps!.length, 1);
      expect(comps.first.type, 'quiz');
      expect(comps.first.data['title'], 't');
    });

    test('components 数组信封', () {
      const text =
          '[YS_GENUI]{"components":['
          '{"type":"diff","before":"x","after":"y"},'
          '{"type":"quiz","items":[{"q":"q","options":["a","b"],"answer":1}]}'
          ']}[/YS_GENUI]';
      final comps = parseGenuiBlock(text);
      expect(comps, isNotNull);
      expect(comps!.length, 2);
      expect(comps[0].type, 'diff');
      expect(comps[1].type, 'quiz');
    });

    test('坏 JSON → 该块跳过，不抛', () {
      const text = '[YS_GENUI]{这不是合法json[/YS_GENUI]尾部';
      expect(parseGenuiBlock(text), isNull);
    });

    test('白名单外类型 → 丢弃', () {
      const text = '[YS_GENUI]{"type":"secret_panel","x":1}[/YS_GENUI]';
      expect(parseGenuiBlock(text), isNull);
    });

    test('diff 缺 before/after → 丢弃', () {
      const text = '[YS_GENUI]{"type":"diff","before":"x"}[/YS_GENUI]';
      expect(parseGenuiBlock(text), isNull);
    });

    test('quiz 缺 answer → 丢弃', () {
      const text =
          '[YS_GENUI]{"type":"quiz",'
          '"items":[{"q":"q","options":["a","b"]}]}[/YS_GENUI]';
      expect(parseGenuiBlock(text), isNull);
    });

    test('无结束标记的残块 → 容错取到末尾，不抛', () {
      const text = '前缀[YS_GENUI]{"type":"diff","before":"a","after":"b"}';
      final comps = parseGenuiBlock(text);
      expect(comps, isNotNull);
      expect(comps!.first.type, 'diff');
    });
  });

  group('stripGenuiBlock', () {
    test('移除完整块并拼接前后文本', () {
      const text =
          '前面内容\n[YS_GENUI]{"type":"diff","before":"a","after":"b"}'
          '[/YS_GENUI]\n后面内容';
      final stripped = stripGenuiBlock(text);
      expect(stripped.contains('[YS_GENUI]'), isFalse);
      expect(stripped.contains('前面内容'), isTrue);
      expect(stripped.contains('后面内容'), isTrue);
    });

    test('无标记 → 原样返回', () {
      const text = '纯文本';
      expect(stripGenuiBlock(text), '纯文本');
    });
  });

  group('validateGenuiComponent', () {
    test('合法 quiz → 通过', () {
      final c = validateGenuiComponent({
        'type': 'quiz',
        'items': [
          {
            'q': 'q',
            'options': ['a', 'b'],
            'answer': 0,
          },
        ],
      });
      expect(c, isNotNull);
      expect(c!.type, 'quiz');
    });

    test('options 不足 2 → 丢弃', () {
      final c = validateGenuiComponent({
        'type': 'quiz',
        'items': [
          {
            'q': 'q',
            'options': ['a'],
            'answer': 0,
          },
        ],
      });
      expect(c, isNull);
    });

    test('合法 stat → 通过', () {
      final c = validateGenuiComponent({
        'type': 'stat',
        'items': [
          {'label': '画面感', 'value': 75, 'max': 100},
        ],
      });
      expect(c, isNotNull);
      expect(c!.type, 'stat');
    });

    test('stat 缺 value → 丢弃', () {
      final c = validateGenuiComponent({
        'type': 'stat',
        'items': [
          {'label': '画面感', 'max': 100},
        ],
      });
      expect(c, isNull);
    });

    test('合法 progress → 通过', () {
      final c = validateGenuiComponent({
        'type': 'progress',
        'steps': [
          {'label': '诊断', 'status': 'done'},
          {'label': '教学', 'status': 'current'},
        ],
      });
      expect(c, isNotNull);
      expect(c!.type, 'progress');
    });

    test('progress 缺 status → 丢弃', () {
      final c = validateGenuiComponent({
        'type': 'progress',
        'steps': [
          {'label': '诊断'},
        ],
      });
      expect(c, isNull);
    });

    test('合法 timeline → 通过', () {
      final c = validateGenuiComponent({
        'type': 'timeline',
        'events': [
          {'date': '2026-08-01', 'title': '首次诊断'},
        ],
      });
      expect(c, isNotNull);
      expect(c!.type, 'timeline');
    });

    test('timeline 缺 title → 丢弃', () {
      final c = validateGenuiComponent({
        'type': 'timeline',
        'events': [
          {'date': '2026-08-01'},
        ],
      });
      expect(c, isNull);
    });
  });

  group('GenuiCardPayload 往返', () {
    test('toJson → fromJson 保持组件', () {
      final payload = GenuiCardPayload(
        components: [
          GenUiComponent(type: 'diff', data: {'before': 'a', 'after': 'b'}),
          GenUiComponent(
            type: 'quiz',
            data: {
              'title': 't',
              'items': [
                {
                  'q': 'q',
                  'options': ['a', 'b'],
                  'answer': 1,
                },
              ],
            },
          ),
        ],
      );
      final json = payload.toJson();
      final restored = GenuiCardPayload.fromJson(json);
      expect(restored.components.length, 2);
      expect(restored.components[0].type, 'diff');
      expect(restored.components[1].data['title'], 't');
    });
  });
}
