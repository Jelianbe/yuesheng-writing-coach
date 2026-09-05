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
//
// C78 批次2b 追加（§5.3 F05 过滤判据 `confirmed && !stale`，一个判据一条）：
//   10. 正向基准：confirmed + 非 stale → 参与
//   11. rejected（用户已否决）→ 不参与（R-009）
//   12. stale（章节已删/已改写）→ 不参与（幽灵矛盾，D-6）
//   13. rejected + stale 同时成立 → 不参与（两条件独立生效）
//   14. 过滤逐条生效：被过滤的断言不参与「最早两个值」的选取
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
  // C78 批次2b：status / stale 默认取「参与检测」的值——既有 9 个用例
  // 全部落在这个默认上，故本批过滤改造对它们零影响（已实测零回归）。
  String status = 'confirmed',
  bool stale = false,
}) {
  return CharacterAssertion(
    attribute: attribute,
    value: value,
    chapter: chapter,
    timestamp: timestamp,
    status: status,
    stale: stale,
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

  // ── C78 批次2b（§5.3）─────────────────────────────────────────
  // F05 过滤判据 `status == 'confirmed' && !stale`（判据定义在
  // conflict_detector.isActiveAssertion，检测与 UI 灰显共用同一份）。
  // 一个判据一条用例：两条件各不满足一次、同时不满足一次，加正向基准，
  // 最后一条验证过滤是「逐条生效」而非「整体跳过」。
  group('F05 过滤判据（confirmed 且非 stale）', () {
    test('#10 正向基准：confirmed + 非 stale → 参与检测', () {
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
    });

    test('#11 rejected（用户已否决）→ 不参与检测', () {
      // R-009 用户主权：否决了还拿来做矛盾检测，等于替用户撤回决定。
      final result = detectCharacterConflicts([
        (
          name: '阿禾',
          assertions: [
            _assertion(
              attribute: '独生子女状态',
              value: '独生子',
              chapter: 3,
              timestamp: 100,
              status: 'rejected',
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

      expect(result, isEmpty, reason: '被否决的断言不参与，剩单值不成矛盾');
    });

    test('#12 stale（章节已删/已改写）→ 不参与检测', () {
      // D-6：原文都不在了，它参与比较得出的矛盾是**幽灵矛盾**——本批病根。
      final result = detectCharacterConflicts([
        (
          name: '阿禾',
          assertions: [
            _assertion(
              attribute: '独生子女状态',
              value: '独生子',
              chapter: 3,
              timestamp: 100,
              stale: true,
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

      expect(result, isEmpty, reason: 'stale 断言不参与，剩单值不成矛盾');
    });

    test('#13 rejected + stale 同时成立 → 同样不参与（两条件独立生效）', () {
      final result = detectCharacterConflicts([
        (
          name: '阿禾',
          assertions: [
            _assertion(
              attribute: '独生子女状态',
              value: '独生子',
              chapter: 3,
              timestamp: 100,
              status: 'rejected',
              stale: true,
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

      expect(result, isEmpty);
    });

    test('#14 过滤逐条生效：被过滤的断言不参与「最早两个值」的选取', () {
      // 防「过滤写成整体跳过」：两条合法断言的矛盾仍须报出，且取的
      // 是**未被过滤**的两个值——被过滤那条虽最早，也不得进 orderedValues。
      final result = detectCharacterConflicts([
        (
          name: '阿禾',
          assertions: [
            _assertion(
              attribute: '独生子女状态',
              value: '独生子',
              chapter: 3,
              timestamp: 100,
              stale: true, // ← 最早，但被过滤
            ),
            _assertion(
              attribute: '独生子女状态',
              value: '有妹妹',
              chapter: 9,
              timestamp: 150,
            ),
            _assertion(
              attribute: '独生子女状态',
              value: '独生子',
              chapter: 15,
              timestamp: 200,
            ),
          ],
        ),
      ]);

      expect(result.length, 1);
      expect(
        result.first.orderedValues.map((a) => a.value).toList(),
        ['有妹妹', '独生子'],
        reason: 'stale 的「独生子」(第3章) 被过滤，最早合法值应为第9章那条',
      );
    });
  });
}
