// ─────────────────────────────────────────────────────────────
// D4 批次9：outline_validator 独立校验层测试
// 覆盖：schema 白名单（type/key/aliases/matched_entity_id/impressions）
//       + 严格策略（任一实体非法 → 整体 invalid，防错关联）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/outline_validator.dart';

void main() {
  group('validateOutlineSchema（严格：任一非法整体 invalid）', () {
    Map<String, dynamic> validEntity({
      String type = 'character',
      String key = '林晚',
      Object? aliases = const ['阿晚'],
      Object? matchedEntityId,
      Object? impressions = const [
        {'text': '初登场时是个爱笑的小姑娘', 'conflict_with': null},
      ],
    }) {
      return {
        'type': type,
        'key': key,
        'aliases': aliases,
        'matched_entity_id': matchedEntityId,
        'impressions': impressions,
      };
    }

    test('#O1 合法实体 → valid + data 完整', () {
      final result = validateOutlineSchema({
        'entities': [validEntity()],
      });
      expect(result.valid, isTrue);
      expect(result.errors, isEmpty);
      final data = result.data;
      expect(data, isNotNull);
      expect(data!.entities.length, 1);
      expect(data.entities.first.type, 'character');
      expect(data.entities.first.key, '林晚');
      expect(data.entities.first.aliases, ['阿晚']);
      expect(data.entities.first.impressions.single.text, '初登场时是个爱笑的小姑娘');
    });

    test('#O2 三类类型白名单（character/setting/plot）→ valid', () {
      final result = validateOutlineSchema({
        'entities': [
          validEntity(type: 'setting', key: '青州府', impressions: const []),
          validEntity(type: 'plot', key: '主线', impressions: const []),
        ],
      });
      expect(result.valid, isTrue);
      expect(result.data!.entities.map((e) => e.type), ['setting', 'plot']);
    });

    test('#O3 空 entities 数组 → valid（空提取）', () {
      final result = validateOutlineSchema({
        'entities': <dynamic>[],
      });
      expect(result.valid, isTrue);
      expect(result.data!.entities, isEmpty);
    });

    test('#O4 非法 type → invalid，且数据不产出（严格整体丢弃）', () {
      final result = validateOutlineSchema({
        'entities': [
          validEntity(type: 'theme', key: '林晚'),
        ],
      });
      expect(result.valid, isFalse);
      expect(result.data, isNull);
      expect(
        result.errors.any((e) => e.field == 'entities[0].type'),
        isTrue,
      );
    });

    test('#O5 空 key → invalid', () {
      final result = validateOutlineSchema({
        'entities': [
          validEntity(key: '   '),
        ],
      });
      expect(result.valid, isFalse);
      expect(result.data, isNull);
    });

    test('#O6 matched_entity_id 非字符串（数字）→ invalid', () {
      final result = validateOutlineSchema({
        'entities': [
          validEntity(matchedEntityId: 123),
        ],
      });
      expect(result.valid, isFalse);
    });

    test('#O7 impressions 非数组 → invalid', () {
      final result = validateOutlineSchema({
        'entities': [
          validEntity(impressions: '不是数组'),
        ],
      });
      expect(result.valid, isFalse);
    });

    test('#O8 印象 text 为空 → invalid', () {
      final result = validateOutlineSchema({
        'entities': [
          validEntity(impressions: [
            {'text': '', 'conflict_with': null},
          ]),
        ],
      });
      expect(result.valid, isFalse);
    });

    test('#O9 conflict_with 非字符串 → invalid', () {
      final result = validateOutlineSchema({
        'entities': [
          validEntity(impressions: [
            {'text': '印象', 'conflict_with': 42},
          ]),
        ],
      });
      expect(result.valid, isFalse);
    });

    test('#O10 根对象非 Map / entities 非数组 → invalid', () {
      expect(validateOutlineSchema('not-an-object').valid, isFalse);
      expect(validateOutlineSchema(null).valid, isFalse);
      final noList = validateOutlineSchema({'entities': 'not-a-list'});
      expect(noList.valid, isFalse);
    });

    test('#O11 多条非法 → errors 全量收集（granular 便于观测）', () {
      final result = validateOutlineSchema({
        'entities': [
          validEntity(type: 'theme'),
          validEntity(key: ''),
          validEntity(impressions: 1),
        ],
      });
      expect(result.valid, isFalse);
      expect(result.errors.length, 3);
    });

    test('#O12 aliases 非字符串条目被过滤，合法保留', () {
      final result = validateOutlineSchema({
        'entities': [
          validEntity(aliases: ['阿晚', 42, '小晚']),
        ],
      });
      expect(result.valid, isTrue);
      expect(result.data!.entities.first.aliases, ['阿晚', '小晚']);
    });
  });
}
