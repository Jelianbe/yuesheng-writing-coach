// ─────────────────────────────────────────────────────────────
// diagnosis_temperature_test — 诊断温度档位真源（W-18 用户可选）
// 断言「档位 → merge 段温度」映射。重点锁死**灵活档返回 null**：
// 它保证未设置档位（含旧库）时 merge 请求体与改造前逐字节相同，
// 既有诊断链路测试零影响。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/diagnosis_temperature.dart';

void main() {
  group('诊断温度档位 → merge 段温度', () {
    test('灵活档 ⇒ null（不产 extraBody 键，请求体零变更护栏）', () {
      expect(mergeTemperatureFor(diagnosisTempFlexible), isNull);
      expect(mergeTemperatureFor(null), isNull);
      expect(mergeTemperatureFor('不存在的档位'), isNull);
    });

    test('保守档 ⇒ 0.3（W-18 实验档完整复现）', () {
      expect(mergeTemperatureFor(diagnosisTempSteady), 0.3);
    });

    test('预设值与裁定口径一致（0.7 现网 / 0.3 实验档）', () {
      expect(diagnosisTemperatureOf(diagnosisTempFlexible).value, 0.7);
      expect(diagnosisTemperatureOf(diagnosisTempSteady).value, 0.3);
    });
  });

  group('诊断温度档位列表约束', () {
    test('兜底档 = 列表首项（界面默认与逻辑默认同源）', () {
      expect(
        diagnosisTemperatureOf(null).key,
        diagnosisTemperaturePresets.first.key,
      );
      expect(diagnosisTemperaturePresets.first.key, diagnosisTempFlexible);
    });

    test('key 唯一、非空，且不与存储键同名', () {
      final keys = diagnosisTemperaturePresets.map((p) => p.key).toList();
      expect(keys.toSet().length, keys.length);
      expect(keys.every((k) => k.isNotEmpty), isTrue);
      expect(keys.contains(kDiagnosisTemperatureKey), isFalse);
      expect(kDiagnosisTemperatureKey, 'diagnosis_temperature');
    });

    test('每个档位都有面向用户的 label / hint', () {
      for (final p in diagnosisTemperaturePresets) {
        expect(p.label, isNotEmpty);
        expect(p.hint, isNotEmpty);
      }
    });

    test('存储键为 app_state 合法 key（字符串、非空）', () {
      expect(kDiagnosisTemperatureKey, isNotEmpty);
    });
  });
}
