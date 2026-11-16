// ─────────────────────────────────────────────────────────────
// diagnosis_syndrome_name_backfill_test — B1(c) · R-027 方案 i
//  诊断输出 name 由注册表按 syndrome_id 精确回填，模型自报降级为 note。
//
// 守的是什么：
//   ① 纯函数四态：一致⇒原值、不一致⇒注册表值+note、未知ID⇒原值、空notes可空；
//   ② parser 链端到端：模型自由 name 被回填、mismatch note 出口可达；
//   ③ validator 落库链端到端：生产最终落库取 validator 结果，其 name 也须回填；
//   ④ 零行为变更：一致时逐字不变（不制造新的 name 漂移）；
//   ⑤ P023 语义代价实测：模型写「设定/信息可信度缺口」⇒ 回填「设定矛盾」。
//
// 纪律：只回填 name + 记 note，不改注册表/ID/文案/埋点/skill（R-027 已报批方案 i）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';
import 'package:writingcoach/services/syndrome_registry.dart';

Map<String, dynamic> _syn(String id, String name) => {
  'syndrome_id': id,
  'name': name,
  'severity': 'L1',
  'evidence': ['e'],
  'explanation': 'y',
};

void main() {
  final p001 = syndromeNameOf('P001')!; // 情绪标签化
  final p023 = syndromeNameOf('P023')!; // 设定矛盾

  group('canonicalSyndromeName 纯函数四态', () {
    test('① 一致⇒原值返回、不记账', () {
      final notes = <String>[];
      final got = canonicalSyndromeName(_syn('P001', p001), notes);
      expect(got, p001);
      expect(notes, isEmpty);
    });

    test('② 不一致⇒注册表值 + syndrome_name_mismatch:<id>', () {
      final notes = <String>[];
      final got = canonicalSyndromeName(_syn('P001', '自由命名'), notes);
      expect(got, p001);
      expect(notes, contains('syndrome_name_mismatch:P001'));
    });

    test('③ 未知 ID⇒保留模型原值、不猜名', () {
      final notes = <String>[];
      final got = canonicalSyndromeName(_syn('P999', '模型自报名'), notes);
      expect(got, '模型自报名');
      expect(notes, isEmpty);
    });

    test('④ notes 可空（validator 链只回填不记账）', () {
      final got = canonicalSyndromeName(_syn('P001', '自由命名'), null);
      expect(got, p001);
    });
  });

  group('parser 链端到端：name 回填 + note 出口', () {
    String block(String name) =>
        '说明\n[YS_DIAGNOSIS]\n'
        '{"syndromes":[{"syndrome_id":"P001","name":"$name","severity":"L1",'
        '"evidence":["e"],"explanation":"y"}],'
        '"suggested_actions":["A002"],"confidence":0.8}\n[/YS_DIAGNOSIS]';

    test('⑤ 模型自由 name ⇒ 回填注册表值 + mismatch note', () {
      final r = parseDiagnosis(block('自由发挥的名字'));
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.syndromes.single.name, p001);
      expect(r.notes, contains('syndrome_name_mismatch:P001'));
    });

    test('⑥ 一致时逐字不变、不产 note（零行为变更）', () {
      final r = parseDiagnosis(block(p001));
      expect(r.diagnosis!.syndromes.single.name, p001);
      expect(r.notes, isNot(contains('syndrome_name_mismatch:P001')));
    });

    test('⑦ 空串 name 也被回填（非法但 String 的情形）', () {
      final r = parseDiagnosis(block(''));
      expect(r.diagnosis!.syndromes.single.name, p001);
    });
  });

  group('validator 落库链端到端：最终落库 name 亦回填', () {
    Map<String, dynamic> payload(String id, String name) => {
      'syndromes': [_syn(id, name)],
      'suggested_actions': ['A002'],
      'confidence': 0.8,
    };

    test('⑧ validator 结果 name = 注册表值（生产落库口径）', () {
      final v = validateDiagnosisOutput('正文', payload('P001', '自由命名'));
      expect(v.diagnosis, isNotNull);
      expect(v.diagnosis!.syndromes.single.name, p001);
    });

    test('⑨ validator 对未知 ID 同样保留原值', () {
      final v = validateDiagnosisOutput('正文', payload('P999', '模型自报名'));
      expect(v.diagnosis!.syndromes.single.name, '模型自报名');
    });
  });

  group('P023 语义代价实测（方案 i 已被登记的已知代价）', () {
    test('⑩ 模型写宽口径「设定/信息可信度缺口」⇒ 回填窄口径「设定矛盾」', () {
      final notes = <String>[];
      final got = canonicalSyndromeName(_syn('P023', '设定/信息可信度缺口'), notes);
      expect(p023, '设定矛盾');
      expect(got, p023);
      expect(notes, contains('syndrome_name_mismatch:P023'));
    });
  });
}
