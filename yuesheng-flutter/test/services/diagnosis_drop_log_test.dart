// ─────────────────────────────────────────────────────────────
// diagnosis_drop_log_test — `diagnosisDropLog` 迁出后的等价性判据
//
// 背景：该函数原为 `DiagnosisFlowHandler._diagnosisDropLog`（私有方法），
// A2 施工时为满足「文件行数不得变胖」而迁至 `diagnosis_drop_log.dart`。
// **迁移不是重构**——输出必须逐字等价，否则会改变日志内容从而影响排查口径。
//
// 守的是什么：
//   ① 无被拒原因且无丢弃字段 ⇒ 空串（调用方直接拼接不产生多余 ` | `）；
//   ② 只有被拒原因 ⇒ ` | 被拒原因=<code>`；
//   ③ 只有丢弃字段 ⇒ ` | 静默丢弃=a,b`（逗号连接，无空格）；
//   ④ 两者都有 ⇒ 两段用 ` | ` 连接（段内、段间同一分隔符）；
//   ⑤ 反例：`notes` 为空列表（非 null）不得产出空段。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/diagnosis_drop_log.dart';
import 'package:writingcoach/services/diagnosis_parser.dart' show ParseResult;

void main() {
  /// 构造最小 ParseResult：只关心 rejectReason / notes 两字段。
  ParseResult _r({String? rejectReason, List<String> notes = const []}) =>
      ParseResult(displayContent: '', rejectReason: rejectReason, notes: notes);

  group('diagnosisDropLog 输出等价性（迁移不得改口径）', () {
    test('① 无被拒原因且无丢弃字段 ⇒ 空串', () {
      expect(diagnosisDropLog(_r()), '');
    });

    test('② 仅被拒原因 ⇒ ` | 被拒原因=<code>`', () {
      expect(
        diagnosisDropLog(_r(rejectReason: 'missing_block')),
        ' | 被拒原因=missing_block',
      );
    });

    test('③ 仅丢弃字段 ⇒ ` | 静默丢弃=a,b`', () {
      expect(
        diagnosisDropLog(_r(notes: const ['fieldA', 'fieldB'])),
        ' | 静默丢弃=fieldA,fieldB',
      );
    });

    test('④ 两者都有 ⇒ 段间同样用 ` | ` 连接', () {
      expect(
        diagnosisDropLog(
          _r(rejectReason: 'json_invalid', notes: const ['syndromes']),
        ),
        ' | 被拒原因=json_invalid | 静默丢弃=syndromes',
      );
    });

    test('⑤ 反例：notes 为空列表不得产出空段', () {
      final out = diagnosisDropLog(_r(rejectReason: 'x', notes: const []));
      expect(out, ' | 被拒原因=x');
      expect(out.contains('静默丢弃'), isFalse, reason: '空列表不得落成「静默丢弃=」空段');
    });

    test('⑥ 反例：单条 notes 不得多出逗号', () {
      expect(diagnosisDropLog(_r(notes: const ['only'])), ' | 静默丢弃=only');
    });
  });
}
