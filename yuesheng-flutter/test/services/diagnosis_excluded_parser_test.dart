// ─────────────────────────────────────────────────────────────
// T-20261024-05 批 2 · excluded 字段全链 —— 判据 2「解析可读」
//
// 落点（报批稿 ①3 / ①5）：
//   - diagnosis_parser.dart · _buildParsedDiagnosis（excluded 可选读，循 readerImpact 先例）
//   - teaching_types.dart · ParsedDiagnosis.excluded（List<ParsedExclusion>，缺省 const []）
//
// 三例成套：
//   E1 正向：含 excluded → ParsedDiagnosis.excluded 正确取值（syndromeId + reason）。
//   E2 边界：类型守卫 —— 非字符串字段归一 ''、非 Map 元素过滤，不抛。
//   E3 防误删（零行为变更）：无 excluded 键 → excluded == const []，其余字段逐值不变。
//   E4 异常：excluded 非数组 → 空列表，不抛（schema 不校验类型的承诺）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('判据 2 · 解析可读（excluded 可选读）', () {
    /// 最小合法诊断 JSON 基底（与 diagnosis_parser_test.dart #3 同形）。
    Map<String, dynamic> baseJson({Object? excluded}) {
      final map = <String, dynamic>{
        'syndromes': [
          {
            'syndrome_id': 'P001',
            'name': '情绪标签化',
            'severity': 'L1',
            'evidence': ['x'],
            'explanation': 'y',
          },
        ],
        'suggested_actions': ['A002'],
        'confidence': 0.75,
      };
      if (excluded != null) map['excluded'] = excluded;
      return map;
    }

    /// 把诊断 JSON 包进 [YS_DIAGNOSIS] 块喂给 parser 公开入口。
    /// （形态照 diagnosis_parser_test.dart:186-189 的 jsonEncode 先例。）
    ParsedDiagnosis? parseOf(Map<String, dynamic> json) {
      final raw = '[YS_DIAGNOSIS]\n${jsonEncode(json)}\n[/YS_DIAGNOSIS]';
      return parseDiagnosis(raw).diagnosis;
    }

    test('E1 正向：含 excluded → excluded 列表正确取值（syndromeId + reason）', () {
      final d = parseOf(
        baseJson(
          excluded: [
            {'syndrome_id': 'P002', 'reason': '与主线视角问题相邻，证据不足'},
            {'syndrome_id': 'P007', 'reason': ''},
          ],
        ),
      );
      expect(d, isNotNull);
      expect(d!.excluded, hasLength(2));
      expect(d.excluded[0].syndromeId, 'P002');
      expect(d.excluded[0].reason, '与主线视角问题相邻，证据不足');
      expect(d.excluded[1].syndromeId, 'P007');
      expect(d.excluded[1].reason, '');
    });

    test('E2 边界：类型守卫 —— 非字符串字段归一 ""，非 Map 元素过滤，不抛', () {
      final d = parseOf(
        baseJson(
          excluded: [
            {'syndrome_id': 123, 'reason': 456},
            '我不是 Map',
            {'syndrome_id': 'P099'},
          ],
        ),
      );
      expect(d, isNotNull);
      // 非 Map 元素被 whereType<Map> 过滤；两项中仅 123 与 P099 两条存活。
      expect(d!.excluded, hasLength(2));
      // 类型守卫：非 String 归一空串（循 readerImpact 先例，schema 不校验类型）。
      expect(d.excluded[0].syndromeId, '');
      expect(d.excluded[0].reason, '');
      // 缺 reason 键 → ''（与缺 syndrome_id 同型安全读取）。
      expect(d.excluded[1].syndromeId, 'P099');
      expect(d.excluded[1].reason, '');
    });

    test('E3 防误删：无 excluded 键 → excluded 为空列表，其余字段逐值不变', () {
      final d = parseOf(baseJson());
      expect(d, isNotNull);
      expect(
        d!.excluded,
        isEmpty,
        reason: '无 excluded 键时必须 const []（零行为变更，与批 1 readerImpact 同型）',
      );
      // 既有字段未因本批受影响（防「靠牺牲既有行为换来新字段」）。
      expect(d.syndromes, hasLength(1));
      expect(d.syndromes.first.syndromeId, 'P001');
      expect(d.suggestedActions, ['A002']);
    });

    test('E4 异常：excluded 非数组（字符串）→ 空列表，不抛', () {
      final d = parseOf(baseJson(excluded: '不是数组'));
      expect(d, isNotNull);
      expect(
        d!.excluded,
        isEmpty,
        reason: 'excluded 不是 List 时必须 const []（安全读取，不得抛 TypeError）',
      );
    });

    test('E5 validator 链覆盖：_mapToParsedDiagnosis 同型补读 excluded（补齐 a）', () {
      // 生产链 flow_handler:581 diagnosis = validation.diagnosis ——
      // validator 结果完全覆盖 parser 结果。若 validator 链不读 excluded，
      // 渲染区块将永远为空（readerImpact 先例即两链都读）。
      final json = baseJson(
        excluded: [
          {'syndrome_id': 'P002', 'reason': '链覆盖必须两路径都读'},
        ],
      );
      final result = validateDiagnosisOutput('自然语言', json);
      expect(result.diagnosis, isNotNull);
      expect(result.diagnosis!.excluded, hasLength(1));
      expect(result.diagnosis!.excluded.single.syndromeId, 'P002');
      expect(result.diagnosis!.excluded.single.reason, '链覆盖必须两路径都读');
    });
  });
}
