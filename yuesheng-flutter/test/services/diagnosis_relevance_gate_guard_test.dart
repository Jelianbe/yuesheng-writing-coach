// ─────────────────────────────────────────────────────────────
// 诊断「叙事合理性判定门」收紧护栏（P0'-1，2026-09-30）
//
// 背景：over-diagnosis（同章实测出 25/16/25/19 条）。唯一的质量过滤器是这道
//   自问门。原门只有一句主观自问「不改会更差吗」，形同虚设。
//
// 本批**没有**给数量加硬上限——ADR-C67/C68 已裁决「症候库侧识别到多少报多少
//   = 诊断须全量落库」，并有两条反向断言测试盯着（syndrome_count_scope_test
//   判据④ / diagnosis_output_semantics_test 组④）。本批走的是**兼容路线 B**：
//   一个字不动数量规则，只把这道门收紧。
//
// 本护栏守三条不变量（都能变红）：
//   ① 收紧标记在两个宿主里都在——生效侧 progressive_diagnosis.dart（merge prompt，
//      会被注入）+ 防御侧 syndrome_kb_content.dart（手册尾部，按 ID 切片 ⇒ 从不注入）
//   ② 旧宽松措辞已消失（只加不减会留下更宽松的旧门，等于没修）
//   ③ 数量规则**逐字未动**——若有人改用「最多 N 个」来"修"P0'-1，③ 必红，
//      逼其先写 ADR 推翻 C67，而不是偷偷改规则
//
// 变异验证：
//   A 把门改回旧措辞（删「从严」等）→ ① 失败
//   B 只加新门、保留旧句 → ② 失败
//   C 给数量规则加「最多 3 个」→ ③ 失败
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _findPackageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (Directory('${dir.path}/lib').existsSync() &&
        Directory('${dir.path}/test').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError('找不到包根目录（cwd=${Directory.current.path}）');
}

final Directory _root = _findPackageRoot();

String _readSrc(String relPath) {
  final f = File('${_root.path}/$relPath');
  if (!f.existsSync()) {
    throw StateError('源文件不存在：$relPath（root=${_root.path}）');
  }
  return f.readAsStringSync();
}

int _count(String src, String needle) => needle.allMatches(src).length;

/// 生效侧：merge prompt 宿主（会被注入）
const String kEffectiveHost = 'lib/services/progressive_diagnosis.dart';

/// 防御侧：手册尾部副本（`## 诊断执行指引`，按症候 ID 切片注入 ⇒ 从不注入）
const String kDefensiveHost = 'lib/services/syndrome_kb_content.dart';

const List<String> kHosts = [kEffectiveHost, kDefensiveHost];

/// 收紧后必须出现的标记（两个宿主都要有）
const List<String> kTightMarkers = ['最终裁决步骤，从严', '一律不算', '拿不准'];

/// 收紧时必须消失的旧宽松措辞
const String kLooseGate = '只有当答案是';

/// 数量规则原文（merge prompt 侧）——路线 B 的核心：**一个字不动**
const String kNumberRuleInMergePrompt = '数量原则：不限制输出问题数量——识别到多少就报多少';

void main() {
  group('① 收紧标记存在（生效侧 + 防御侧）', () {
    for (final host in kHosts) {
      test(host, () {
        final src = _readSrc(host);
        for (final marker in kTightMarkers) {
          expect(
            _count(src, marker),
            greaterThanOrEqualTo(1),
            reason:
                '$host 缺少收紧标记「$marker」。\n'
                '（P0\'-1：叙事合理性判定门必须收紧为"读者级实际损害 + 指得出原文位置"）',
          );
        }
      });
    }
  });

  group('② 旧宽松措辞已消失（只加不减 = 没修）', () {
    for (final host in kHosts) {
      test(host, () {
        expect(
          _count(_readSrc(host), kLooseGate),
          0,
          reason:
              '$host 仍残留旧宽松门「$kLooseGate」——\n'
              '只补新门、保留旧门，模型仍可按更宽的那句放行，等于没修（P0\'-1）',
        );
      });
    }
  });

  group('③ 数量规则逐字未动（ADR-C67/C68 兼容）', () {
    test('merge prompt 数量规则原文仍在且唯一', () {
      final src = _readSrc(kEffectiveHost);
      expect(
        _count(src, kNumberRuleInMergePrompt),
        1,
        reason:
            '$kEffectiveHost 中「$kNumberRuleInMergePrompt」应恰好 1 次。\n'
            '（本批走路线 B：不改数量规则。若改成「最多 N 个」，请先写 ADR 推翻\n'
            ' ADR-C67 的"诊断须全量落库"，而不是在这里偷改）',
      );
    });
  });

  group('④ 生效性：收紧门落在 merge prompt 的 return 串内（在数量规则之前）', () {
    test('门的标记早于数量规则原文', () {
      final src = _readSrc(kEffectiveHost);
      final iGate = src.indexOf('最终裁决步骤，从严');
      final iNumber = src.indexOf(kNumberRuleInMergePrompt);
      expect(iGate, isNot(-1), reason: '找不到收紧门');
      expect(iNumber, isNot(-1), reason: '找不到数量规则原文');
      expect(
        iGate,
        lessThan(iNumber),
        reason: '收紧门必须出现在数量规则之前的同一段 prompt 里（否则可能落到了别处）',
      );
    });
  });

  group('⑤ 判据自身有效（变异回归）', () {
    test('旧措辞会被 ② 判红、新标记会被 ① 判绿', () {
      expect(_count('只有当答案是"是"时，这条症候才进入最终输出。', kLooseGate), 1);
      expect(_count('叙事合理性判定（最终裁决步骤，从严）：', '最终裁决步骤，从严'), 1);
      expect(_count('数量原则：不限制输出问题数量——识别到多少就报多少', kNumberRuleInMergePrompt), 1);
      expect(_count('数量原则：最多 3 个问题', kNumberRuleInMergePrompt), 0);
    });
  });
}
