// §4-215 裁7②：confidence 解析降级护栏（活性审查 D1）
//   - 缺失 ⇒ 缺省 0.0，不拒（废除字段不再卡诊断）
//   - 越界（<0 / >1）/ 非数字 ⇒ 仍拒（坏值不放过）
//   - 旧格式（带合法 confidence）⇒ 照常过（兼容性方向=只放宽缺失）
// 依据：§1-20（模型自报 confidence 已废除，禁止重新引入）+ §4-214 裁7 + §4-215 批文。

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';

/// 单症候 JSON 字面量（与 diagnosis_parser_test 同款形态）。
const String _kSyn =
    '{"syndrome_id":"P001","name":"情绪标签化",'
    '"severity":"L1","evidence":["x"],"explanation":"y","reader_impact":"z"}';

/// 包一层协议块。
String _diag(String body) => '[YS_DIAGNOSIS]\n$body\n[/YS_DIAGNOSIS]';

/// 完整合法 JSON（confidence 由参数注入；null = 不带该键）。
String _json(String? confValue) {
  final conf = confValue == null ? '' : ',"confidence":$confValue';
  return '{"syndromes":[$_kSyn],"suggested_actions":["A002"]$conf,'
      '"feedback_summary":"ok"}';
}

void main() {
  group('§4-215 裁7② · confidence 降级可选', () {
    test('① 缺失 confidence ⇒ 不拒，缺省 0.0（废除字段不再卡诊断）', () {
      final r = parseDiagnosis(_diag(_json(null)));
      expect(r.diagnosis, isNotNull, reason: '缺 confidence 不得再拒整块诊断');
      expect(r.rejectReason, isNull);
      expect(r.diagnosis!.confidence, 0.0);
    });

    test('② 越界 >1 ⇒ 仍拒（confidence_invalid，坏值不放过）', () {
      final r = parseDiagnosis(_diag(_json('1.5')));
      expect(r.diagnosis, isNull);
      expect(r.rejectReason, 'confidence_invalid');
    });

    test('③ 越界 <0 ⇒ 仍拒', () {
      final r = parseDiagnosis(_diag(_json('-0.1')));
      expect(r.diagnosis, isNull);
      expect(r.rejectReason, 'confidence_invalid');
    });

    test('④ 非数字（字符串）⇒ 仍拒', () {
      final r = parseDiagnosis(_diag(_json('"high"')));
      expect(r.diagnosis, isNull);
      expect(r.rejectReason, 'confidence_invalid');
    });

    test('⑤ 旧格式（合法 0.75）⇒ 照常过且保值（兼容不破坏）', () {
      final r = parseDiagnosis(_diag(_json('0.75')));
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.confidence, 0.75);
    });

    test('⑥ 边界值 0.0 / 1.0 ⇒ 合法（闭区间）', () {
      for (final v in const ['0.0', '1.0']) {
        final r = parseDiagnosis(_diag(_json(v)));
        expect(r.diagnosis, isNotNull, reason: 'confidence=$v 应合法');
      }
    });
  });
}
