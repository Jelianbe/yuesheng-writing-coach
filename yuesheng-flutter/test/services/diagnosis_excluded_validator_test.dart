// ─────────────────────────────────────────────────────────────
// T-20261024-05 批 2 · excluded 字段全链 —— 判据 3「校验可观测」
//
// 落点（报批稿 ①4）：
//   - diagnosis_validator.dart · validateDiagnosisSchema 内新增三项
//     excluded note（warning 级，循 validateSyndromeMutexWarnings 先例，不阻断落库）：
//       ① excluded ID 格式错（kAnchoredSyndromeIdRe）
//       ② excluded ID 不在候选集 C（从 kSyndromeRegistry 派生的推导值）
//       ③ excluded ID 与 syndromes 重复
//
// 断言纪律：不锁 note 文案措辞（实现细节），只断言「触发了对应 ID 的 note」。
// 基例取 syndromes=[P004]（单边不触发既有互斥 warning，见
// diagnosis_validator_test.dart 既有先例），让本批三条 note 是唯一变量。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';

void main() {
  group('判据 3 · 校验可观测（excluded 三项 note）', () {
    /// 基例：单边 P004 —— 不触发既有互斥 warning（validateSyndromeMutexWarnings
    /// 仅在互斥对双侧同时命中时才记录），本批 note 是 warnings 列表的唯一来源。
    Map<String, dynamic> baseJson({Object? excluded, Object? syndromes}) {
      return <String, dynamic>{
        'syndromes':
            syndromes ??
            [
              {
                'syndrome_id': 'P004',
                'name': '症候P004',
                'severity': 'L2',
                'evidence': ['证据'],
                'explanation': '解释',
              },
            ],
        'suggested_actions': ['动作1'],
        'confidence': 0.8,
        if (excluded != null) 'excluded': excluded,
      };
    }

    /// warnings 里是否有任意一条提及给定 ID（不锁文案措辞）。
    bool mentionsId(List<String> warnings, String id) =>
        warnings.any((w) => w.contains(id));

    test('V1 格式错：excluded ID 不合 kAnchoredSyndromeIdRe → 触发 note，不阻断', () {
      final r = validateDiagnosisSchema(
        baseJson(
          excluded: [
            {'syndrome_id': 'P1', 'reason': '太短'},
          ],
        ),
      );
      expect(r.valid, isTrue, reason: 'note 是 warning 级，不得阻断落库');
      expect(
        mentionsId(r.warnings, 'P1'),
        isTrue,
        reason: '格式非法的 excluded ID 必须进 warnings',
      );
    });

    test('V2 不在候选集：P099（格式合法、注册表未注册）→ 触发 note，不阻断', () {
      final r = validateDiagnosisSchema(
        baseJson(
          excluded: [
            {'syndrome_id': 'P099', 'reason': '编外编号'},
          ],
        ),
      );
      expect(r.valid, isTrue, reason: 'note 是 warning 级，不得阻断落库');
      expect(
        mentionsId(r.warnings, 'P099'),
        isTrue,
        reason: '不在候选集 C 内的 excluded ID 必须进 warnings',
      );
    });

    test('V3 重复：excluded 与 syndromes 重复 → 触发 note，不阻断', () {
      final r = validateDiagnosisSchema(
        baseJson(
          excluded: [
            {'syndrome_id': 'P004', 'reason': '已经报过了'},
          ],
        ),
      );
      expect(r.valid, isTrue, reason: 'note 是 warning 级，不得阻断落库');
      expect(
        mentionsId(r.warnings, 'P004'),
        isTrue,
        reason: '与 syndromes 重复的 excluded ID 必须进 warnings',
      );
    });

    test('V4 无 note 对照组：P017 是 P004 互斥对派生候选 → 不触发任何 excluded note', () {
      // 可预测依据（报批稿 ①4 候选集 C 定义）：
      //   syndromes=[P004] 命中互斥对 P004/P017 ⇒ P017 ∈ C。
      //   P017 格式合法、不与 P004 重复 ⇒ 三项 note 均不应触发。
      //   syndromes=[P004] 单边 ⇒ 既有互斥 warning 也不触发（baseJson 已选此基例）。
      final r = validateDiagnosisSchema(
        baseJson(
          excluded: [
            {'syndrome_id': 'P017', 'reason': '互斥对另一边，候选集内'},
          ],
        ),
      );
      expect(r.valid, isTrue);
      expect(
        r.warnings,
        isEmpty,
        reason:
            'P017 在候选集 C 内（互斥对派生）、格式合法、不与 P004 重复 '
            '⇒ 不应产生任何 excluded note；warnings 必须仍为空',
      );
    });

    test('V5 不影响 error 判定：excluded note 不改变 valid/errors', () {
      // 半面 A：合法输入 + 触发 note → valid=true、errors 为空。
      final withNote = validateDiagnosisSchema(
        baseJson(
          excluded: [
            {'syndrome_id': 'P099', 'reason': '编外'},
          ],
        ),
      );
      expect(withNote.valid, isTrue);
      expect(
        withNote.errors,
        isEmpty,
        reason: '触发 excluded note 不得同时产生 error（warning 与 error 分通道）',
      );

      // 半面 B：非法 syndromes（字符串，类型守卫）+ excluded 正常 → valid=false、
      // errors 非空（excluded 正常不救赎 error；error 通道独立）。
      final badSchema = validateDiagnosisSchema(
        baseJson(
          syndromes: 'P001',
          excluded: [
            {'syndrome_id': 'P017', 'reason': '正常条目'},
          ],
        ),
      );
      expect(badSchema.valid, isFalse);
      expect(
        badSchema.errors,
        isNotEmpty,
        reason: 'excluded 字段正常不得修复 syndromes 的类型错误（error 判定独立）',
      );
    });
  });
}
