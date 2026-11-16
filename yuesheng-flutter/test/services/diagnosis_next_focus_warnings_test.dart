// ─────────────────────────────────────────────────────────────
// diagnosis_next_focus_warnings_test — C1「nextFocus 无护栏」的只观测护栏
//
// 守的是什么：
//   ① 纯函数三态：零症候 + 自报焦点 ⇒ 1 码；有症候 / 无焦点 ⇒ 空；
//   ② 端到端：`parseDiagnosis` 的 `ParseResult.notes` 真带该码（出口可达）；
//   ③ 反例：有症候时同输入不得产码（不误报）；
//   ④ 零行为变更：`nextFocus` 取值在「有码 / 无码」两态下逐字不变——
//      护栏只观测，不改模型自报字段、不改 null 回退语义（R-009）。
// 纪律：只加 note 码，不拦截、不改 prompt / 文案 / schema（零 R-027）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  Syndrome _s(String id) => Syndrome(
    syndromeId: id,
    name: '症候',
    severity: Severity.l1,
    evidence: const ['e'],
    explanation: 'x',
  );

  group('validateNextFocusWarnings 纯函数三态', () {
    test('① 零症候 + 自报焦点 ⇒ next_focus_without_syndromes', () {
      expect(validateNextFocusWarnings(const [], '苏玉不选按住沈青的理由'), const [
        'next_focus_without_syndromes',
      ]);
    });

    test('② 有症候 + 自报焦点 ⇒ 空（不误报）', () {
      expect(validateNextFocusWarnings([_s('P001')], '下步焦点'), isEmpty);
    });

    test('③ 零症候 + 无焦点 ⇒ 空', () {
      expect(validateNextFocusWarnings(const [], null), isEmpty);
    });
  });

  group('parseDiagnosis 端到端：notes 出口可达', () {
    const code = 'next_focus_without_syndromes';

    String block({required bool withSyndrome, String? nextFocus}) {
      final syn = withSyndrome
          ? '[{"syndrome_id":"P001","name":"情绪标签化","severity":"L1",'
                '"evidence":["e"],"explanation":"y"}]'
          : '[]';
      final nf = nextFocus == null ? '' : '"next_focus":"$nextFocus",';
      return '说明\n[YS_DIAGNOSIS]\n'
          '{"syndromes":$syn,${nf}"suggested_actions":["A002"],'
          '"confidence":0.8}\n[/YS_DIAGNOSIS]';
    }

    test('④ syndromeCount=0 + next_focus ⇒ notes 含码', () {
      final r = parseDiagnosis(
        block(withSyndrome: false, nextFocus: '苏玉不说的理由'),
      );
      expect(r.diagnosis, isNotNull);
      expect(r.notes, contains(code));
    });

    test('⑤ 有症候 + 同焦点 ⇒ notes 不含码（反例）', () {
      final r = parseDiagnosis(block(withSyndrome: true, nextFocus: '苏玉不说的理由'));
      expect(r.diagnosis, isNotNull);
      expect(r.notes, isNot(contains(code)));
    });

    test('⑥ 零行为变更：有无该 note 时 nextFocus 取值逐字相同', () {
      final zero = parseDiagnosis(
        block(withSyndrome: false, nextFocus: '同一焦点'),
      );
      final withSyn = parseDiagnosis(
        block(withSyndrome: true, nextFocus: '同一焦点'),
      );
      expect(zero.diagnosis!.nextFocus, withSyn.diagnosis!.nextFocus);
      expect(zero.diagnosis!.nextFocus, '同一焦点');
    });

    test('⑦ 零症候 + 无 next_focus ⇒ 不产码（缺字段不误报）', () {
      final r = parseDiagnosis(block(withSyndrome: false, nextFocus: null));
      expect(r.notes, isNot(contains(code)));
    });
  });
}
