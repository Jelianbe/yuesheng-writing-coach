// ─────────────────────────────────────────────────────────────
// diagnosis_validator_v01_dedup_test — A1「连续 V-01 降级块」修复
//
// 任务来源：`.ai/reports/2026-11-16-SCREENING-REPORT.md` A1 节
//   + `.ai/reports/2026-11-16-A1-R027报批稿.md` 方案 A（已获批准）
//
// 验收判据（报批稿 §四 判据表，逐条落成 test）：
//   1. 两段 >80 字、无引号、无 coach 元话语 ⇒ `_kV01Downgrade` 连续出现次数 ≤ 1
//   2. 每个降级块仍产出 `NlFix`（观测不丢；方案 A 未撤销本条）
//   3. `_kV01Downgrade` 常量字节与 HEAD 逐字相等（**零文案改动**）
//   4. 导出回放等价：4 条 chat 共 8 次命中的形态，修复后连续块数为 0
//
// ★ 本文件为**新增**，不修改任何既有测试断言（任务书 §0.1-4）。
// ★ 每条正例都配反例：段间夹非命中行时**必须各自保留**（防「一刀切全去重」）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';

/// 被测常量（逐字）——与 `diagnosis_validator.dart:84` 必须完全一致。
const String _kDowngrade = '（这段我不替你落笔：这一段请你自己先写一稿，写完我们一起逐句回看。）';

/// 构造一段「必被判定为代写」的长段：>80 字、无引号、无教练元话语。
///
/// 逐字注意：不得出现 `_kCoachMetaMarkers` 里的任一词（这里/这句/上文/原文/
/// 你的/问题/因为/所以/建议/可以/为什么/节奏/动机/镜头感/比喻/铺垫/转折…），
/// 也不得含 `"` `「` `『`。用纯场景描写堆字。
String _ghostPara([String seed = '甲']) {
  final buf = StringBuffer();
  for (var i = 0; i < 12; i++) {
    buf.write('$seed${_kScene[i % _kScene.length]}');
  }
  final s = buf.toString();
  assert(s.length > 80, '构造段长度 ${s.length} 必须 >80');
  return s;
}

const List<String> _kScene = [
  '夜风穿过空荡的长廊，他缓缓抬起头，指节因用力而泛白，',
  '眼中闪过一丝不易察觉的决绝，往事如潮水般涌上心头，',
  '他知道再也没有回头的余地，脚下的青砖在月光下泛着光。',
  '尘土在斜射的光柱里飞舞，老宅仿佛重新活了过来，',
];

void main() {
  group('A1 判据 1：连续命中去重', () {
    test('两个相邻代写段 ⇒ 降级块只出现 1 次', () {
      final r = validateNaturalLanguage(
        '${_ghostPara('甲')}\n${_ghostPara('乙')}',
      );
      expect(
        _kDowngrade.allMatches(r.cleaned).length,
        1,
        reason: '连续两个占位符块正是本任务要修的缺陷（改造前会得 2）',
      );
    });

    test('五个相邻代写段 ⇒ 降级块仍只出现 1 次（不只压两段）', () {
      final input = List.generate(
        5,
        (i) => _ghostPara(String.fromCharCode(65 + i)),
      ).join('\n');
      final r = validateNaturalLanguage(input);
      expect(_kDowngrade.allMatches(r.cleaned).length, 1);
    });

    test('★ 反例：段间夹一个非命中行 ⇒ 必须各自保留（不得一刀切）', () {
      final r = validateNaturalLanguage(
        '${_ghostPara('甲')}\n这一句可以再收一收。\n${_ghostPara('乙')}',
      );
      expect(
        _kDowngrade.allMatches(r.cleaned).length,
        2,
        reason: '中间隔着教练反馈 ⇒ 两块不相邻，各自保留才是对的',
      );
    });

    test('★ 反例：单个代写段 ⇒ 仍降级 1 次（去重不得吞掉唯一那块）', () {
      final r = validateNaturalLanguage(_ghostPara());
      expect(_kDowngrade.allMatches(r.cleaned).length, 1);
    });

    test('正常教练反馈（短句 + 带元话语长句）⇒ 零降级块', () {
      final r = validateNaturalLanguage(
        '这句的镜头感不错。\n'
        '这一段的人物动机可以再明确一点，读者目前还看不出他为什么会生气，'
        '因为他的反应来得太突兀，情绪转变缺少铺垫，需要补一个内心动摇的细节。',
      );
      expect(_kDowngrade.allMatches(r.cleaned).length, 0);
      expect(r.fixes.any((f) => f.type == 'V-01'), isFalse);
    });
  });

  group('A1 判据 2：观测不丢（fixes 仍逐条记）', () {
    test('两个相邻命中 ⇒ fixes 仍是 2 条（输出压成 1 块，观测不压）', () {
      final r = validateNaturalLanguage(
        '${_ghostPara('甲')}\n${_ghostPara('乙')}',
      );
      final v01 = r.fixes.where((f) => f.type == 'V-01').toList();
      expect(v01, hasLength(2), reason: '抹掉 fix 会让「模型代写了几段」这个读数失真（方案 A 未撤销本条）');
      expect(
        _kDowngrade.allMatches(r.cleaned).length,
        1,
        reason: '同一调用内同时断言输出侧已去重 —— 两件事必须分开计',
      );
    });

    test('fix 的 original 保留各段预览（不是同一段的重复）', () {
      final r = validateNaturalLanguage(
        '${_ghostPara('甲')}\n${_ghostPara('乙')}',
      );
      final v01 = r.fixes.where((f) => f.type == 'V-01').toList();
      expect(v01[0].original, isNot(equals(v01[1].original)));
      expect(v01.every((f) => f.replacement == _kDowngrade), isTrue);
    });

    test('fixes 条数与命中的输入段数相等（不因去重而减少）', () {
      for (final n in [1, 2, 3, 5]) {
        final input = List.generate(
          n,
          (i) => _ghostPara(String.fromCharCode(65 + i)),
        ).join('\n');
        final r = validateNaturalLanguage(input);
        expect(
          r.fixes.where((f) => f.type == 'V-01').length,
          n,
          reason: '$n 段命中应记 $n 条 V-01 fix',
        );
      }
    });
  });

  group('A1 判据 3：零文案改动（不触 R-027）', () {
    test('V-01 降级文案在源码中逐字未改', () {
      // A1 真分解后常量迁至 diagnosis_ghost_guard.dart（行数硬约束逼迫净减），
      // 但**文案本身必须逐字不变** —— 这才是本判据守的东西，不是文件位置。
      final src = File(
        'lib/services/diagnosis_ghost_guard.dart',
      ).readAsStringSync();
      // 断言「常量声明 + 文案字面量」同时出现即可 —— 不绑定换行缩进，
      // 否则 reformat 会误伤（判据要守文案，不是守排版）。
      expect(
        src.contains("const String kV01Downgrade"),
        isTrue,
        reason: '常量必须仍以 kV01Downgrade 为名',
      );
      expect(
        src.contains(_kDowngrade),
        isTrue,
        reason: '方案 A 承诺「不动任何用户可见文案」；文案一变即触 R-027',
      );
      // 反例：旧文件里不得再留一份（两处表述必然漂移）。
      final legacy = File(
        'lib/services/diagnosis_validator.dart',
      ).readAsStringSync();
      expect(
        legacy.contains(_kDowngrade),
        isFalse,
        reason: '文案只许一处表述，validator 内不得残留副本',
      );
    });

    test('两个文件都不存在方案 B/C 的新增文案', () {
      final src =
          File('lib/services/diagnosis_ghost_guard.dart').readAsStringSync() +
          File('lib/services/diagnosis_validator.dart').readAsStringSync();
      for (final forbidden in <String>['这一段我先不代笔', '本段未附具体发现', '本轮诊断未完成']) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason: '检测到方案 B/C 文案「$forbidden」——方案 A 不该包含它',
        );
      }
    });
  });

  group('A1 判据 4：导出回放等价形态', () {
    test('4 处 chat 的命中形态（4/2/1/1 次）修复后连续块数均为 0', () {
      // 导出实测：740d27bf 4 次、a54e43a9 2 次、bc4cf188 1 次、e5b12f6d 1 次。
      // 这里按「连续命中」的最坏形态复现（全部相邻），断言连续块数 = 0。
      for (final hits in <int>[4, 2, 1, 1]) {
        final input = List.generate(
          hits,
          (i) => _ghostPara(String.fromCharCode(65 + i)),
        ).join('\n');
        final r = validateNaturalLanguage(input);
        final blocks = _kDowngrade.allMatches(r.cleaned).length;
        // 「连续块数」= 相邻成对的降级块个数。
        final consecutive = blocks > 1 ? blocks - 1 : 0;
        expect(consecutive, 0, reason: '$hits 连击形态修复后不得再有相邻重复块（实测块数 $blocks）');
      }
    });

    test('空输入 / 单空白行 ⇒ 不崩、不产生降级块', () {
      for (final input in <String>['', ' ', '\n', '\n\n']) {
        final r = validateNaturalLanguage(input);
        expect(_kDowngrade.allMatches(r.cleaned).length, 0);
        expect(r.fixes.any((f) => f.type == 'V-01'), isFalse);
      }
    });
  });
}
