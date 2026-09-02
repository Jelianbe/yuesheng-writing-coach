// ADR-C64 护栏：validator 侧可选字段类型漂移（N39 + N40 补完）
//
// 被守护的缺陷（ADR-C64 §1.2 实测）：
//   validateDiagnosisSchema 只校验必填三项，可选字段类型完全不校验。
//   _mapToParsedDiagnosis 对这些字段原为硬 cast（as String?），类型漂移
//   抛 TypeError——而抛错点在 validateDiagnosisOutput 返回之前（:268 早于
//   :273），连带丢掉已算好的 NL 清洗结果，导致 V-03 编号泄漏拦截失效、
//   用户直接看到 P012 这类裸编号。
//
// 本文件的核心断言不是「不崩」，而是「崩了之后 V-03 是否仍然生效」——
// 后者才是这个缺陷对用户可见的后果。

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 正文含裸编号，用于验证 V-03 是否生效
const String _kLeakyText = '这段正文泄漏了内部编号 P012，应当被替换';

/// 顶层可选字段漂移点（ADR-C64 §2.2 #1-6）
const List<String> _kTopLevelDriftFields = [
  'next_focus',
  'root_cause_analysis',
  'feedback_summary',
  'suggested_phase',
  'suggested_beginner_level',
  'teaching_mode',
];

/// teaching_plan 子字段漂移点（ADR-C64 §2.2 #7-8）
const List<String> _kTeachingPlanDriftFields = [
  'current_teaching_focus_id',
  'focus_reason',
];

/// 通过 schema 校验的最小合法 payload
Map<String, dynamic> _baseJson() => {
  'syndromes': [
    {
      'syndrome_id': 'P012',
      'name': '铺垫缺失',
      'severity': 'L2',
      'evidence': ['证据一'],
      'explanation': '说明文字',
    },
  ],
  'suggested_actions': ['动作一'],
  'confidence': 0.8,
};

void main() {
  // ── 组 1：语料自检（置顶，防空集假绿）────────────────────────────
  group('组1 语料自检', () {
    test('漂移字段清单非空', () {
      expect(_kTopLevelDriftFields.length, 6);
      expect(_kTeachingPlanDriftFields.length, 2);
      // 6 顶层 + 2 teaching_plan 子字段 + 1 syndromes[].reader_impact = 9 处
      expect(
        _kTopLevelDriftFields.length + _kTeachingPlanDriftFields.length + 1,
        9,
      );
    });

    test('基线 payload 能通过 schema（否则后续断言全部失去意义）', () {
      final r = validateDiagnosisOutput(_kLeakyText, _baseJson());
      expect(r.jsonValidation.valid, isTrue);
      expect(r.jsonValidation.errors, isEmpty);
      expect(r.diagnosis, isNotNull);
    });

    test('基线正文确实含裸编号（V-03 语料有效）', () {
      expect(_kLeakyText, contains('P012'));
      expect(_kLeakyText, isNot(contains('【症候】')));
    });
  });

  // ── 组 2：9 处漂移均不抛异常、且不丢诊断 ─────────────────────────
  group('组2 九处漂移均不崩溃', () {
    for (final field in _kTopLevelDriftFields) {
      test('顶层 $field 类型漂移 → 不抛异常且诊断不丢', () {
        final j = _baseJson();
        j[field] = 12345;
        late FullValidationResult r;
        expect(() {
          r = validateDiagnosisOutput(_kLeakyText, j);
        }, returnsNormally);
        expect(r.diagnosis, isNotNull, reason: '$field 漂移不应丢弃整块诊断');
        expect(r.jsonValidation.valid, isTrue);
      });
    }

    for (final field in _kTeachingPlanDriftFields) {
      test('teaching_plan.$field 类型漂移 → 不抛异常且诊断不丢', () {
        final j = _baseJson();
        j['teaching_plan'] = {field: 12345};
        late FullValidationResult r;
        expect(() {
          r = validateDiagnosisOutput(_kLeakyText, j);
        }, returnsNormally);
        expect(r.diagnosis, isNotNull);
        expect(r.jsonValidation.valid, isTrue);
      });
    }

    test('syndromes[].reader_impact 类型漂移 → 不抛异常且诊断不丢', () {
      final j = _baseJson();
      (j['syndromes'] as List)[0]['reader_impact'] = {'nested': 1};
      late FullValidationResult r;
      expect(() {
        r = validateDiagnosisOutput(_kLeakyText, j);
      }, returnsNormally);
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.syndromes.first.readerImpact, isNull);
    });

    test('teaching_plan 本身非 Map → 不抛异常（既有守卫，固化为回归）', () {
      final j = _baseJson();
      j['teaching_plan'] = 'not a map';
      late FullValidationResult r;
      expect(() {
        r = validateDiagnosisOutput(_kLeakyText, j);
      }, returnsNormally);
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.currentTeachingFocusId, isNull);
      expect(r.diagnosis!.focusReason, isNull);
    });
  });

  // ── 组 3：V-03 清洗在所有漂移路径上都生效（修复的核心价值）────────
  group('组3 漂移时 V-03 编号泄漏拦截仍生效', () {
    for (final field in _kTopLevelDriftFields) {
      test('$field 漂移时 displayContent 仍被清洗', () {
        final j = _baseJson();
        j[field] = 12345;
        final r = validateDiagnosisOutput(_kLeakyText, j);
        expect(
          r.displayContent,
          contains('【症候】'),
          reason: '$field 漂移不得让 V-03 失效',
        );
        expect(
          r.displayContent,
          isNot(contains('P012')),
          reason: '$field 漂移不得把裸编号泄漏给用户',
        );
      });
    }

    for (final field in _kTeachingPlanDriftFields) {
      test('teaching_plan.$field 漂移时 displayContent 仍被清洗', () {
        final j = _baseJson();
        j['teaching_plan'] = {field: 12345};
        final r = validateDiagnosisOutput(_kLeakyText, j);
        expect(r.displayContent, contains('【症候】'));
        expect(r.displayContent, isNot(contains('P012')));
      });
    }

    test('reader_impact 漂移时 displayContent 仍被清洗', () {
      final j = _baseJson();
      (j['syndromes'] as List)[0]['reader_impact'] = {'nested': 1};
      final r = validateDiagnosisOutput(_kLeakyText, j);
      expect(r.displayContent, contains('【症候】'));
      expect(r.displayContent, isNot(contains('P012')));
    });

    test('无漂移基线：V-03 同样生效（对照组）', () {
      final r = validateDiagnosisOutput(_kLeakyText, _baseJson());
      expect(r.displayContent, contains('【症候】'));
      expect(r.displayContent, isNot(contains('P012')));
    });

    test('语料有效性：V-03 属真拦截，含裸编号时 passed 为 false', () {
      // 这条是语料自检的延伸——确认本文件用的正文确实会触发 V-03 真拦截。
      // 若此条失败，说明语料失效，组 3 其余断言都失去意义。
      final r = validateDiagnosisOutput(_kLeakyText, _baseJson());
      expect(
        r.nlValidation.fixes.any((f) => f.type == 'V-03'),
        isTrue,
        reason: '正文含 P012，必须触发 V-03，否则本组语料失效',
      );
      expect(
        r.passed,
        isFalse,
        reason: 'V-03 是真拦截类型（_kBlockingFixTypes），应判不通过',
      );
    });
  });

  // ── 组 4：漂移必须留痕（不新增静默点）───────────────────────────
  group('组4 漂移留痕', () {
    for (final field in _kTopLevelDriftFields) {
      test('$field 漂移 → warnings 记录该字段', () {
        final j = _baseJson();
        j[field] = 12345;
        final r = validateDiagnosisOutput(_kLeakyText, j);
        expect(
          r.jsonValidation.warnings.any((w) => w.contains(field)),
          isTrue,
          reason: '$field 漂移必须留痕，不得静默丢弃',
        );
      });
    }

    for (final field in _kTeachingPlanDriftFields) {
      test('teaching_plan.$field 漂移 → warnings 记录该字段', () {
        final j = _baseJson();
        j['teaching_plan'] = {field: 12345};
        final r = validateDiagnosisOutput(_kLeakyText, j);
        expect(
          r.jsonValidation.warnings.any(
            (w) => w.contains('teaching_plan.$field'),
          ),
          isTrue,
        );
      });
    }

    test('reader_impact 漂移 → warnings 记录该字段', () {
      final j = _baseJson();
      (j['syndromes'] as List)[0]['reader_impact'] = {'nested': 1};
      final r = validateDiagnosisOutput(_kLeakyText, j);
      expect(
        r.jsonValidation.warnings.any((w) => w.contains('reader_impact')),
        isTrue,
      );
    });

    test('warning 文本含实际类型，便于定位', () {
      final j = _baseJson();
      j['next_focus'] = 12345;
      final r = validateDiagnosisOutput(_kLeakyText, j);
      expect(
        r.jsonValidation.warnings.any((w) => w.contains('int')),
        isTrue,
        reason: 'warning 应带运行时类型，否则仍难定位',
      );
    });
  });

  // ── 组 5：零行为变更（无漂移输入必须逐字段不变）───────────────────
  group('组5 零行为变更', () {
    // 注意：不断言 passed。本文件语料正文故意含 P012，会触发 V-03
    // 真拦截（_kBlockingFixTypes 含 'V-03'），故 passed 恒为 false。
    // passed 的语义断言放在组 3，不在本组。
    test('无漂移 → warnings 为空、valid 为真、诊断不丢', () {
      final r = validateDiagnosisOutput(_kLeakyText, _baseJson());
      expect(r.jsonValidation.warnings, isEmpty);
      expect(r.jsonValidation.valid, isTrue);
      expect(r.diagnosis, isNotNull);
    });

    test('合法 String 值不被误判为漂移', () {
      final j = _baseJson()
        ..['next_focus'] = '下一步'
        ..['root_cause_analysis'] = '根因'
        ..['feedback_summary'] = '摘要'
        ..['suggested_phase'] = 'P2_PRACTICE_LOOP'
        ..['suggested_beginner_level'] = 'N2_SCENE'
        ..['teaching_mode'] = 'socratic'
        // N3-a（ADR-C65）：必须是本轮 syndromes 中的 id（此处 P012）。
        // 原用 'F001'——类型合法但成员越界，加校验后会被置 null，
        // 就测不到「合法 String 不被误判为漂移」了。换合规值保留原意图。
        ..['teaching_plan'] = {
          'current_teaching_focus_id': 'P012',
          'focus_reason': '原因',
        };
      final r = validateDiagnosisOutput(_kLeakyText, j);
      expect(r.jsonValidation.warnings, isEmpty, reason: '合法 String 不得被误报为漂移');

      final d = r.diagnosis!;
      expect(d.nextFocus, '下一步');
      expect(d.rootCauseAnalysis, '根因');
      expect(d.feedbackSummary, '摘要');
      expect(d.suggestedPhase, TeachingPhase.p2PracticeLoop);
      expect(d.suggestedBeginnerLevel, BeginnerLevel.n2Scene);
      expect(d.teachingMode, TeachingMode.socratic);
      expect(d.currentTeachingFocusId, 'P012');
      expect(d.focusReason, '原因');
    });

    test('合法 reader_impact 不被误判为漂移且正常解析', () {
      final j = _baseJson();
      (j['syndromes'] as List)[0]['reader_impact'] = '读者感受';
      final r = validateDiagnosisOutput(_kLeakyText, j);
      expect(r.jsonValidation.warnings, isEmpty);
      expect(r.diagnosis!.syndromes.first.readerImpact, '读者感受');
    });

    test('字段缺失（null）不产生漂移 warning', () {
      final j = _baseJson()..['next_focus'] = null;
      final r = validateDiagnosisOutput(_kLeakyText, j);
      expect(r.jsonValidation.warnings, isEmpty);
      expect(r.diagnosis!.nextFocus, isNull);
    });
  });

  // ── 组 6：漂移字段按缺失处理，语义与缺失一致 ──────────────────────
  group('组6 漂移按缺失处理', () {
    test('suggested_phase 漂移 → 解析为 null（与缺失一致）', () {
      final j = _baseJson()..['suggested_phase'] = 4;
      final r = validateDiagnosisOutput(_kLeakyText, j);
      expect(r.diagnosis!.suggestedPhase, isNull);
    });

    test('teaching_mode 漂移 → 解析为 null', () {
      final j = _baseJson()..['teaching_mode'] = true;
      final r = validateDiagnosisOutput(_kLeakyText, j);
      expect(r.diagnosis!.teachingMode, isNull);
    });

    test('next_focus 漂移 → 回退到 teaching_plan.next_step', () {
      final j = _baseJson()
        ..['next_focus'] = 12345
        ..['teaching_plan'] = {'next_step': '来自教学计划的下一步'};
      final r = validateDiagnosisOutput(_kLeakyText, j);
      expect(
        r.diagnosis!.nextFocus,
        '来自教学计划的下一步',
        reason: '漂移按缺失处理，回退语义须与 next_focus 为 null 时一致',
      );
    });

    test('suggested_beginner_level 漂移 → 解析为 null', () {
      final j = _baseJson()..['suggested_beginner_level'] = [];
      final r = validateDiagnosisOutput(_kLeakyText, j);
      expect(r.diagnosis!.suggestedBeginnerLevel, isNull);
    });
  });

  // ── 组 7：漂移不影响 schema 判定（不放大「输出了但不落库」）─────────
  group('组7 漂移不判为 schema 错误', () {
    for (final field in _kTopLevelDriftFields) {
      test('$field 漂移 → errors 仍为空、诊断不被丢弃', () {
        final baseline = validateDiagnosisOutput(_kLeakyText, _baseJson());
        final j = _baseJson();
        j[field] = 12345;
        final r = validateDiagnosisOutput(_kLeakyText, j);

        expect(r.jsonValidation.errors, isEmpty);
        expect(r.jsonValidation.valid, isTrue);
        expect(r.diagnosis, isNotNull, reason: '漂移不得判为错误，否则整块诊断被丢弃');
        // passed 由 V-03 决定（语料含 P012 → 真拦截 → false），
        // 但漂移与否不得改变它——用基线做对照而非硬编码期望值
        expect(r.passed, baseline.passed, reason: '漂移不得改变整体判定结果');
      });
    }
  });
}
