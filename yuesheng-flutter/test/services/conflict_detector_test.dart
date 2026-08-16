// ─────────────────────────────────────────────────────────────
// conflict_detector_test — 批次66 B62i 时序矛盾检测单元测试
//
// 覆盖：
//   1. 空输入 → 空数组
//   2. 同属性不同值 → 时序矛盾观察项（描述含章节）
//   3. 同值不误报
//   4. 乱序输入 → 按章节时间序输出
//   5. 章节 null 排最后
//   6. 多人物/多属性 → 字典序稳定排序
//   7. 多个不同值 → 取最早出现的两个
//   8. buildConflictObservationsContext：空 → null
//   9. buildConflictObservationsContext：非空 → 含观察与措辞
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/conflict_detector.dart';
import 'package:writingcoach/types/character_types.dart';

CharacterAssertion _assertion({
  required String attribute,
  required String value,
  int? chapter,
  required int timestamp,
}) {
  return CharacterAssertion(
    attribute: attribute,
    value: value,
    chapter: chapter,
    timestamp: timestamp,
  );
}

void main() {
  test('#1 空输入 → 空数组', () {
    expect(detectCharacterConflicts(const []), isEmpty);
  });

  test('#2 同属性不同值 → 时序矛盾观察项（描述含章节）', () {
    final result = detectCharacterConflicts([
      (
        name: '阿禾',
        assertions: [
          _assertion(
            attribute: '独生子女状态',
            value: '独生子',
            chapter: 3,
            timestamp: 100,
          ),
          _assertion(
            attribute: '独生子女状态',
            value: '妹妹',
            chapter: 15,
            timestamp: 200,
          ),
        ],
      ),
    ]);

    expect(result.length, 1);
    final obs = result.first;
    expect(obs.characterName, '阿禾');
    expect(obs.attribute, '独生子女状态');
    expect(obs.orderedValues.length, 2);
    expect(obs.orderedValues.first.value, '独生子');
    expect(obs.orderedValues.last.value, '妹妹');
    expect(obs.description, '第3章「独生子」→ 第15章「妹妹」');
  });

  test('#3 同值不误报', () {
    final result = detectCharacterConflicts([
      (
        name: '阿禾',
        assertions: [
          _assertion(attribute: '性格', value: '冷静', chapter: 1, timestamp: 100),
          _assertion(attribute: '性格', value: '冷静', chapter: 20, timestamp: 200),
        ],
      ),
    ]);

    expect(result, isEmpty);
  });

  test('#4 乱序输入 → 按章节时间序输出', () {
    final result = detectCharacterConflicts([
      (
        name: '阿禾',
        assertions: [
          _assertion(attribute: '职业', value: '郎中', chapter: 9, timestamp: 200),
          _assertion(attribute: '职业', value: '捕快', chapter: 2, timestamp: 100),
        ],
      ),
    ]);

    final obs = result.first;
    expect(obs.orderedValues.first.value, '捕快');
    expect(obs.orderedValues.last.value, '郎中');
    expect(obs.description, '第2章「捕快」→ 第9章「郎中」');
  });

  test('#5 章节 null 排最后', () {
    final result = detectCharacterConflicts([
      (
        name: '阿禾',
        assertions: [
          _assertion(attribute: '外貌', value: '黑发', timestamp: 200),
          _assertion(attribute: '外貌', value: '银发', chapter: 5, timestamp: 100),
        ],
      ),
    ]);

    final obs = result.first;
    expect(obs.orderedValues.first.value, '银发');
    expect(obs.orderedValues.last.value, '黑发');
    expect(obs.description, '第5章「银发」→ 早期「黑发」');
  });

  test('#6 多人物/多属性 → 字典序稳定排序', () {
    final result = detectCharacterConflicts([
      (
        name: '阿禾',
        assertions: [
          _assertion(attribute: '性格', value: '冷静', chapter: 1, timestamp: 100),
          _assertion(attribute: '性格', value: '暴烈', chapter: 8, timestamp: 200),
        ],
      ),
      (
        name: '阿青',
        assertions: [
          _assertion(
            attribute: '独生子女状态',
            value: '独生女',
            chapter: 2,
            timestamp: 100,
          ),
          _assertion(
            attribute: '独生子女状态',
            value: '有姐姐',
            chapter: 10,
            timestamp: 200,
          ),
        ],
      ),
    ]);

    // 按 (人物名, 属性) 字典序：阿禾(性格) < 阿青(独生子女状态)
    expect(result.length, 2);
    expect(result.first.characterName, '阿禾');
    expect(result.first.attribute, '性格');
    expect(result.last.characterName, '阿青');
  });

  test('#7 多个不同值 → 取最早出现的两个', () {
    final result = detectCharacterConflicts([
      (
        name: '阿禾',
        assertions: [
          _assertion(attribute: '武器', value: '剑', chapter: 1, timestamp: 100),
          _assertion(attribute: '武器', value: '刀', chapter: 5, timestamp: 200),
          _assertion(attribute: '武器', value: '弓', chapter: 9, timestamp: 300),
        ],
      ),
    ]);

    final obs = result.first;
    expect(obs.orderedValues.length, 2);
    expect(obs.orderedValues.first.value, '剑');
    expect(obs.orderedValues.last.value, '刀');
    expect(obs.description, '第1章「剑」→ 第5章「刀」');
  });

  test('#8 buildConflictObservationsContext 空 → null', () {
    expect(buildConflictObservationsContext(const []), isNull);
  });

  test('#9 buildConflictObservationsContext 非空 → 含观察与措辞', () {
    final observations = detectCharacterConflicts([
      (
        name: '阿禾',
        assertions: [
          _assertion(
            attribute: '独生子女状态',
            value: '独生子',
            chapter: 3,
            timestamp: 100,
          ),
          _assertion(
            attribute: '独生子女状态',
            value: '妹妹',
            chapter: 15,
            timestamp: 200,
          ),
        ],
      ),
    ]);

    final ctx = buildConflictObservationsContext(observations);
    expect(ctx, isNotNull);
    expect(ctx, contains('时序矛盾观察'));
    expect(ctx, contains('阿禾「独生子女状态」'));
    expect(ctx, contains('第3章「独生子」→ 第15章「妹妹」'));
    expect(ctx, contains('P018'));
  });
}
