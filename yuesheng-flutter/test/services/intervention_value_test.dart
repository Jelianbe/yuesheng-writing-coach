// ─────────────────────────────────────────────────────────────
// W-19-A 回归测试：intervention_value 契约层
//
// 覆盖（对应设计稿 §3.1 + W-19 行验收）：
//   1. normalizeInterventionValue：三档合法 / 越界 / 非字符串 / null
//   2. interventionValueRank：high > medium > low > null
//   3. sortSyndromesForDiagnosisCard：severity 主序 + 同档价值次序 +
//      null 殿后 + 输入不被修改（纯函数契约）
//   4. Syndrome toJson/fromJson：有值往返 / 无值不落 key
//   5. 解析器：合法档位透传；越界值 → 字段 null + notes 留痕（观测不拦截）
//   6. DiagnosisSyndromeCard toJson/fromJson 往返
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/intervention_value.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

Syndrome _s(String id, {Severity severity = Severity.l2, String? value}) =>
    Syndrome(
      syndromeId: id,
      name: 'n-$id',
      severity: severity,
      evidence: const ['e'],
      explanation: 'x',
      interventionValue: value,
    );

void main() {
  group('normalizeInterventionValue', () {
    test('三档合法值原样返回', () {
      expect(normalizeInterventionValue('high'), 'high');
      expect(normalizeInterventionValue('medium'), 'medium');
      expect(normalizeInterventionValue('low'), 'low');
    });
    test('越界字符串 / 非字符串 / null → null', () {
      expect(normalizeInterventionValue('High'), isNull); // 大小写敏感，不纠偏
      expect(normalizeInterventionValue('critical'), isNull);
      expect(normalizeInterventionValue(3), isNull);
      expect(normalizeInterventionValue(null), isNull);
    });
  });

  group('interventionValueRank', () {
    test('high > medium > low > null', () {
      expect(
        interventionValueRank('high'),
        greaterThan(interventionValueRank('medium')),
      );
      expect(
        interventionValueRank('medium'),
        greaterThan(interventionValueRank('low')),
      );
      expect(
        interventionValueRank('low'),
        greaterThan(interventionValueRank(null)),
      );
    });
  });

  group('sortSyndromesForDiagnosisCard', () {
    test('severity 主序：L3 > L2 > L1（既有口径不变）', () {
      final out = sortSyndromesForDiagnosisCard([
        _s('a', severity: Severity.l1),
        _s('b', severity: Severity.l3),
        _s('c', severity: Severity.l2),
      ]);
      expect(out.map((s) => s.syndromeId).toList(), ['b', 'c', 'a']);
    });

    test('同 severity 档内：high > medium > low > null', () {
      final out = sortSyndromesForDiagnosisCard([
        _s('null-v'),
        _s('low-v', value: 'low'),
        _s('high-v', value: 'high'),
        _s('medium-v', value: 'medium'),
      ]);
      expect(out.map((s) => s.syndromeId).toList(), [
        'high-v',
        'medium-v',
        'low-v',
        'null-v',
      ]);
    });

    test('severity 严格优先于干预价值（L1-high 不越过 L2-null）', () {
      final out = sortSyndromesForDiagnosisCard([
        _s('l1-high', severity: Severity.l1, value: 'high'),
        _s('l2-null', severity: Severity.l2),
      ]);
      expect(out.map((s) => s.syndromeId).toList(), ['l2-null', 'l1-high']);
    });

    test('纯函数：输入列表不被修改', () {
      final input = [_s('a', value: 'low'), _s('b', value: 'high')];
      sortSyndromesForDiagnosisCard(input);
      expect(input.map((s) => s.syndromeId).toList(), ['a', 'b']);
    });
  });

  group('Syndrome JSON 往返', () {
    test('有值：intervention_value 落 key 且往返稳定', () {
      final s = _s('P001', value: 'high');
      final back = Syndrome.fromJson(s.toJson());
      expect(back.interventionValue, 'high');
    });
    test('无值：不落 key，fromJson 得 null', () {
      final s = _s('P001');
      expect(s.toJson().containsKey('intervention_value'), isFalse);
      final back = Syndrome.fromJson(s.toJson());
      expect(back.interventionValue, isNull);
    });
    test('fromJson 越界值安全读取为 null（不抛 TypeError）', () {
      final back = Syndrome.fromJson({
        'syndrome_id': 'P001',
        'name': 'n',
        'severity': 'L2',
        'evidence': ['e'],
        'explanation': 'x',
        'intervention_value': 42,
      });
      expect(back.interventionValue, isNull);
    });
  });

  group('解析器接线', () {
    String _wrap(String syndromeJson) =>
        '前导[YS_DIAGNOSIS]\n{"syndromes":[$syndromeJson],'
        '"suggested_actions":["A002"],"confidence":0.75,'
        '"feedback_summary":"ok","root_cause_analysis":"r",'
        '"next_focus":"P001","teaching_plan":{"current_teaching_focus_id":'
        '"P001","focus_reason":"a","next_step":"b"}}\n[/YS_DIAGNOSIS]';

    test('合法档位透传到 Syndrome', () {
      final r = parseDiagnosis(
        _wrap(
          '{"syndrome_id":"P001","name":"情绪标签化","severity":"L1",'
          '"evidence":["x"],"explanation":"y","intervention_value":"high"}',
        ),
      );
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.syndromes.first.interventionValue, 'high');
    });

    test('越界档位：字段 null + notes 留痕（观测不拦截，条目不丢）', () {
      final r = parseDiagnosis(
        _wrap(
          '{"syndrome_id":"P001","name":"情绪标签化","severity":"L1",'
          '"evidence":["x"],"explanation":"y","intervention_value":"满分"}',
        ),
      );
      expect(r.diagnosis, isNotNull); // 条目不丢
      expect(r.diagnosis!.syndromes.first.interventionValue, isNull);
      expect(r.notes, contains('syndrome_intervention_value_invalid'));
    });
  });

  group('DiagnosisSyndromeCard 往返', () {
    test('intervention_value 有值落 key、无值不落 key，往返稳定', () {
      const withValue = DiagnosisSyndromeCard(
        syndromeId: 'P001',
        name: 'n',
        severity: 'L1',
        evidenceCount: 1,
        interventionValue: 'medium',
      );
      final back = DiagnosisSyndromeCard.fromJson(withValue.toJson());
      expect(back.interventionValue, 'medium');

      const withoutValue = DiagnosisSyndromeCard(
        syndromeId: 'P002',
        name: 'n',
        severity: 'L2',
        evidenceCount: 0,
      );
      expect(withoutValue.toJson().containsKey('intervention_value'), isFalse);
      expect(
        DiagnosisSyndromeCard.fromJson(withoutValue.toJson()).interventionValue,
        isNull,
      );
    });
  });
}
