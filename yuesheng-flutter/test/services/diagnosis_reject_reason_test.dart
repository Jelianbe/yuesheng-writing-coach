// ─────────────────────────────────────────────────────────────
// 诊断块解析原因码护栏（ADR-C63 / N1 / N26 / N5 / N8 / N40）
//
// 本文件存在的唯一理由：
//   「AI 输出了诊断块但没落库」此前**全程无报错、查不到根因**。
//   12 处整块丢弃 + 3 处字段静默丢弃全部是裸 `return null`，
//   是 C53 类问题「查不到根因」的直接成因，也是 N26 说的
//   「模型以为有反馈回路，实际没有 → 每一轮都静默失败」的放大器。
//
// 四层结构：
//   1. 语料自检（置顶，防空集假绿）
//   2. 12 个整块被拒原因码逐一可触发
//   3. 4 个非阻断观测码（N26-B 组字段静默丢弃 / N5 格式只观测不拦截）
//   4. 零行为变更验证 + N8 两条路径等价性 + N40 崩溃回归
//
// ⚠️ 新增静默点时必须同步：
//   ① 在 diagnosis_parser.dart 的 kDiagnosisRejectReasons /
//      kDiagnosisParseNotes 登记 ② 在本文件补触发用例。
//   少任何一样，本文件第 1 层的「码 ↔ 用例」双向断言会失败。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';
import 'package:writingcoach/types/teaching_types.dart';

const String kStart = '[YS_DIAGNOSIS]';
const String kEnd = '[/YS_DIAGNOSIS]';

/// 单个合法症候条目。各字段用 [Object?] 以便注入非法值触发拒绝码。
Map<String, Object?> _oneSyndrome({
  Object? id = 'P003',
  Object? name = '情绪标签化',
  Object? severity = 'L1',
  Object? evidence = const ['e1'],
  Object? explanation = 'exp',
  Object? readerImpact,
}) => <String, Object?>{
  'syndrome_id': id,
  'name': name,
  'severity': severity,
  'evidence': evidence,
  'explanation': explanation,
  'reader_impact': ?readerImpact,
};

/// 基线合法诊断对象。可选字段默认**不写入**，用于验证「缺失」与「非法」不混淆。
Map<String, Object?> _validDiagnosis({
  Object? syndromes,
  Object? suggestedActions = const ['A002'],
  Object? confidence = 0.7,
  Object? suggestedPhase,
  Object? beginnerLevel,
  Object? teachingMode,
}) => <String, Object?>{
  'syndromes': syndromes ?? <Object?>[_oneSyndrome()],
  'suggested_actions': suggestedActions,
  'confidence': confidence,
  'suggested_phase': ?suggestedPhase,
  'suggested_beginner_level': ?beginnerLevel,
  'teaching_mode': ?teachingMode,
};

String _block(Object json) => '$kStart${jsonEncode(json)}$kEnd';

/// 12 个整块被拒原因码的触发语料。
///
/// 顺序与 `kDiagnosisRejectReasons` 一致，与解析器的校验顺序
/// （标记 → JSON → 根 → syndromes → actions → confidence）也一致。
final List<(String, String)> _rejectCases = [
  ('marker_end_missing', '$kStart${jsonEncode(_validDiagnosis())}'),
  ('json_decode_failed', '$kStart这不是 JSON$kEnd'),
  ('root_not_object', '$kStart[1,2,3]$kEnd'),
  ('syndromes_not_list', _block(_validDiagnosis(syndromes: 'notalist'))),
  ('syndrome_item_not_object', _block(_validDiagnosis(syndromes: ['plain']))),
  (
    'syndrome_id_not_string',
    _block(_validDiagnosis(syndromes: [_oneSyndrome(id: 123)])),
  ),
  (
    'syndrome_name_not_string',
    _block(_validDiagnosis(syndromes: [_oneSyndrome(name: 456)])),
  ),
  (
    'syndrome_severity_invalid',
    _block(_validDiagnosis(syndromes: [_oneSyndrome(severity: 'L9')])),
  ),
  (
    'syndrome_evidence_invalid',
    _block(
      _validDiagnosis(
        syndromes: [
          _oneSyndrome(evidence: [1, 2]),
        ],
      ),
    ),
  ),
  (
    'syndrome_explanation_not_string',
    _block(
      _validDiagnosis(
        syndromes: [
          _oneSyndrome(explanation: {'a': 1}),
        ],
      ),
    ),
  ),
  (
    'suggested_actions_invalid',
    _block(_validDiagnosis(suggestedActions: [1, 2])),
  ),
  ('confidence_invalid', _block(_validDiagnosis(confidence: 1.5))),
];

void main() {
  // ── 1. 语料自检（置顶：空集会伪装成全绿）────────────────────
  group('语料自检', () {
    test('原因码清单非空且无重复', () {
      expect(kDiagnosisRejectReasons, isNotEmpty);
      expect(
        kDiagnosisRejectReasons.toSet(),
        hasLength(kDiagnosisRejectReasons.length),
      );
      expect(
        kDiagnosisParseNotes.toSet(),
        hasLength(kDiagnosisParseNotes.length),
      );
    });

    test('每个声明的原因码都有触发用例（双向，防新增静默点漏测）', () {
      final covered = _rejectCases.map((c) => c.$1).toSet();
      expect(
        covered,
        kDiagnosisRejectReasons.toSet(),
        reason:
            'kDiagnosisRejectReasons 与本文件的触发用例必须双向相等。\n'
            '仅在解析器里新增 return 而不补用例 → 静默点会重新出现而无人知晓，'
            '这正是 N26 的成因。',
      );
    });
  });

  // ── 2. 12 个整块被拒原因码逐一可触发 ────────────────────────
  group('整块被拒原因码', () {
    for (final c in _rejectCases) {
      test('${c.$1} → diagnosis=null 且 rejectReason 命中', () {
        final r = parseDiagnosis(c.$2);
        expect(r.diagnosis, isNull, reason: '${c.$1} 应导致整块被拒');
        expect(r.rejectReason, c.$1);
      });
    }
  });

  // ── 3. 非阻断观测码 ─────────────────────────────────────────
  group('非阻断观测码（整块仍通过，但字段被静默丢弃）', () {
    test('phase_dropped：模型自造 P5_COMPANION → 整块通过但阶段迁移不发生', () {
      // N22 实测：模型在无 P5 字面枚举时会自己造出 P5_COMPANION / P5_ACCOMPANY。
      // 这是 N13「该轮零迁移」的确切机制——诊断照常显示、UI 毫无异样。
      final r = parseDiagnosis(
        _block(_validDiagnosis(suggestedPhase: 'P5_COMPANION')),
      );
      expect(r.diagnosis, isNotNull, reason: '整块仍应通过（这是它隐蔽的原因）');
      expect(r.rejectReason, isNull);
      expect(r.notes, contains('phase_dropped'));
      expect(r.diagnosis!.suggestedPhase, isNull);
    });

    test('beginner_level_dropped：非法零基础等级被静默置 null', () {
      final r = parseDiagnosis(_block(_validDiagnosis(beginnerLevel: 'N9_X')));
      expect(r.diagnosis, isNotNull);
      expect(r.notes, contains('beginner_level_dropped'));
      expect(r.diagnosis!.suggestedBeginnerLevel, isNull);
    });

    test('teaching_mode_dropped：非法教学模式被静默置 null', () {
      final r = parseDiagnosis(_block(_validDiagnosis(teachingMode: 'zen')));
      expect(r.diagnosis, isNotNull);
      expect(r.notes, contains('teaching_mode_dropped'));
      expect(r.diagnosis!.teachingMode, isNull);
    });

    test('syndrome_id_format：非 P0xx 格式只观测不拦截（N5 / ADR-C63 §3.2）', () {
      // 模型把 syndrome_id 填成中文名是真实危害（后续按 id 查找会静默失配），
      // 但**拦截会让整块诊断被丢弃**，反而放大「输出了但不落库」。
      // 因此只记 note，先测量发生率。
      final r = parseDiagnosis(
        _block(_validDiagnosis(syndromes: [_oneSyndrome(id: '情绪标签化')])),
      );
      expect(r.diagnosis, isNotNull, reason: 'N5 明确定位为「不拦截」');
      expect(r.diagnosis!.syndromes.first.syndromeId, '情绪标签化');
      expect(r.notes, contains('syndrome_id_format'));
    });

    test('N5 锚定：非锚定匹配不算合法（防 "XP003" 蒙混过关）', () {
      // validator 的 kSyndromeCodeRe 是非锚定的（为「正文里找泄漏编号」设计），
      // 直接拿来做字段校验会让 "XP003" 命中 → 等于没校验。
      final r = parseDiagnosis(
        _block(_validDiagnosis(syndromes: [_oneSyndrome(id: 'XP003')])),
      );
      expect(r.notes, contains('syndrome_id_format'));
    });
  });

  // ── 4. 零行为变更验证 ───────────────────────────────────────
  group('零行为变更', () {
    test('全字段合法 → rejectReason=null 且 notes 为空', () {
      final r = parseDiagnosis(
        _block(
          _validDiagnosis(
            suggestedPhase: 'P2_PRACTICE_LOOP',
            beginnerLevel: 'N2_SCENE',
            teachingMode: 'socratic',
          ),
        ),
      );
      expect(r.diagnosis, isNotNull);
      expect(r.rejectReason, isNull);
      expect(r.notes, isEmpty);
      expect(r.diagnosis!.suggestedPhase, TeachingPhase.p2PracticeLoop);
      expect(r.diagnosis!.suggestedBeginnerLevel, BeginnerLevel.n2Scene);
      expect(r.diagnosis!.teachingMode, isNotNull);
    });

    test('无诊断块 → rejectReason=null（「没输出块」与「块被拒」不可混淆）', () {
      // 这是本 ADR 最关键的判别式：
      //   无块 + rejectReason=null     → prompt 没生效，去查 prompt
      //   有块 + rejectReason 有值      → schema 契约问题，去查字段定义
      // 混淆二者会把问题引向错误方向。
      final r = parseDiagnosis('你好，直接说点什么');
      expect(r.diagnosis, isNull);
      expect(r.rejectReason, isNull);
      expect(r.notes, isEmpty);
    });

    test('可选字段缺失 → 不产生 note（缺失 ≠ 非法）', () {
      final r = parseDiagnosis(_block(_validDiagnosis()));
      expect(r.diagnosis, isNotNull);
      expect(r.notes, isEmpty, reason: '字段没填不该被当成「静默丢弃」');
    });
  });

  // ── 5. N8：两条 suggested_phase 解析路径语义等价 ─────────────
  group('N8 两条路径等价性护栏', () {
    test('parser 白名单与 TeachingPhase.fromString 判定一致', () {
      // N8 原描述：parser 走 kValidPhases 白名单、validator 走 fromString，
      // 「形式不一致但语义等价」——这个等价性此前从未被断言，属隐性假设。
      for (final p in kValidPhases) {
        expect(TeachingPhase.fromString(p), isNotNull, reason: '$p 应合法');
      }
      for (final bad in <String>[
        'P5_COMPANION', // N22 实测自造值
        'P5_ACCOMPANY', // N22 实测自造值
        'P1', // 前缀而非全等
        'p0_engage', // 大小写漂移
        '',
      ]) {
        expect(TeachingPhase.fromString(bad), isNull, reason: '$bad 应非法');
        expect(kValidPhases.contains(bad), isFalse);
      }
    });

    test('三个可选枚举的所有合法值都能被 parser 接受（行为侧验证）', () {
      for (final p in TeachingPhase.values) {
        final r = parseDiagnosis(
          _block(_validDiagnosis(suggestedPhase: p.value)),
        );
        expect(r.diagnosis!.suggestedPhase, p, reason: '${p.value} 应被接受');
        expect(r.notes, isEmpty);
      }
      for (final b in BeginnerLevel.values) {
        final r = parseDiagnosis(
          _block(_validDiagnosis(beginnerLevel: b.value)),
        );
        expect(r.diagnosis!.suggestedBeginnerLevel, b);
        expect(r.notes, isEmpty);
      }
      for (final m in TeachingMode.values) {
        final r = parseDiagnosis(
          _block(_validDiagnosis(teachingMode: m.value)),
        );
        expect(r.diagnosis!.teachingMode, m);
        expect(r.notes, isEmpty);
      }
    });

    test('kValidPhases 与 TeachingPhase 枚举双向相等（N19 同源）', () {
      final enumValues = TeachingPhase.values.map((e) => e.value).toSet();
      expect(kValidPhases.toSet(), enumValues);
      final lvlValues = BeginnerLevel.values.map((e) => e.value).toSet();
      expect(kValidBeginnerLevels.toSet(), lvlValues);
    });
  });

  // ── 6. N40 回归：reader_impact 非字符串不得崩溃 ──────────────
  group('N40 硬 cast 崩溃回归', () {
    test('reader_impact 为数字时不抛异常，按缺失处理', () {
      // 原实现 `s['reader_impact'] as String?` 是硬 cast，
      // 模型填非字符串即抛 TypeError。parseDiagnosis 声明「不 throw」，
      // 这条回归守住该声明。
      expect(
        () => parseDiagnosis(
          _block(_validDiagnosis(syndromes: [_oneSyndrome(readerImpact: 123)])),
        ),
        returnsNormally,
      );
      final r = parseDiagnosis(
        _block(_validDiagnosis(syndromes: [_oneSyndrome(readerImpact: 123)])),
      );
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.syndromes.first.readerImpact, isNull);
    });

    test('reader_impact 为字符串时正常保留（不得误伤正常路径）', () {
      final r = parseDiagnosis(
        _block(
          _validDiagnosis(syndromes: [_oneSyndrome(readerImpact: '读者会出戏')]),
        ),
      );
      expect(r.diagnosis!.syndromes.first.readerImpact, '读者会出戏');
    });
  });

  // ── 7. 纯函数契约 ───────────────────────────────────────────
  group('纯函数契约', () {
    test('kSyndromeCodeRe 仍是 validator 侧的非锚定原义（未被本次改动污染）', () {
      // 本批只复用它的模式串，不复用实例（ADR-C63 §3.2）。
      // 守它的原义：正文中嵌入的编号要能被替换掉。
      expect(kSyndromeCodeRe.hasMatch('这里提到 P003 和 P021'), isTrue);
      final cleaned = validateNaturalLanguage('这里提到 P003').cleaned;
      expect(cleaned, isNot(contains('P003')));
    });

    test('同一输入重复解析结果稳定（无隐藏状态）', () {
      const raw = '$kStart{"syndromes":[]}$kEnd';
      expect(
        parseDiagnosis(raw).rejectReason,
        parseDiagnosis(raw).rejectReason,
      );
    });
  });
}
