// ─────────────────────────────────────────────────────────────
// W-45 窄改②③ 判据：P002 密度上限 + P002/P017 互斥规则
//
// 背景：`.ai/reports/2026-10-20-W45-抽核回执与位置维度调查.md` §四 实测
// 「P002 与 P017 抢同一个词」—— P017 的排除说明（manual_6.dart:521）自称
// 覆盖「信息倾泻」，而互斥表全表 grep 无 P002-vs-P017 裁决规则。
// X31 就落在这条缝上：判据报 P002（设定以旁白告知），舰长读成 P017（概括过多）。
//
// 本测试的判据全部能变红：
//   · 删掉 manual_1 的密度上限段   ⇒ D1–D3 变红
//   · 删掉 manual_3 的互斥校验段   ⇒ E1–E3 变红
//   · 把 manual_6 的错误措辞改回   ⇒ F1 变红
//   · 若 P002 段落从首轮注入面掉出来 ⇒ G1 变红（防止改了个不生效的地方）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';

String _p002() => getSyndromeCriteriaSections(const ['P002']);
String _p017() => getSyndromeCriteriaSections(const ['P017']);

void main() {
  group('W-45 窄改② · P002 密度上限（只管信息过量）', () {
    test('D1 P002 判据含密度上限段且标明方向相反的两种病灶', () {
      final s = _p002();
      expect(s, contains('密度上限'));
      expect(s, contains('方向相反'));
      // 两种病灶必须都被点名为，否则「划死」无从谈起。
      expect(s, contains('信息过量'));
      expect(s, contains('叙事被压缩'));
    });

    test('D2 三条裁决问句按序给出，且「归 P017 不是 P002」是明写的', () {
      final s = _p002();
      expect(s, contains('删掉这段，后续看不懂吗'));
      expect(s, contains('读者会被拉出故事吗'));
      expect(s, contains('三分之一篇幅重述'));
      // 承重句：这是让 X31 类归因不再错投的那一句。
      expect(s, contains('归 P017，不是 P002'));
      expect(s, contains('此时报 P002 属归因错误'));
    });

    test('D3 禁用形态词/长度词两种偷懒判法（判据必须能约束判据）', () {
      final s = _p002();
      expect(s, contains('那是形态词'));
      expect(s, contains('那是长度词'));
      expect(s, contains('指不出具体位置即不算'));
    });

    test('D4 与 P017 的分工一句话可被检索到（水太多 vs 该给水没给）', () {
      expect(_p002(), contains('P002 = 水太多（信息倒给）；P017 = 该给水的地方没给（叙事跳过）'));
    });

    test('D5 既有判据未被窄改②破坏（三条存量专条仍在）', () {
      final s = _p002();
      expect(s, contains('必要性首筛'));
      expect(s, contains('单句带过的必要事实专条'));
      expect(s, contains('量功能不量形式'));
      expect(s, contains('悬浮 ≠ 倾泻'));
      expect(s, contains('组合⑤'));
    });

    test('D6 position_sensitivity: beginning 未被改动', () {
      expect(_p002(), contains('position_sensitivity**: beginning'));
    });
  });

  group('W-45 窄改③ · P002 vs P017 互斥规则', () {
    test('E1 P017 判据含互斥校验段并点名 P002', () {
      final s = _p017();
      expect(s, contains('互斥校验（P002 vs P017'));
      expect(s, contains('水太多'));
      expect(s, contains('该给水的地方没给'));
    });

    test('E2 裁决问句是「加内容还是减内容」（可执行，非同义反复）', () {
      final s = _p017();
      expect(s, contains('需要**加** ⇒ P017；需要**减** ⇒ P002'));
      expect(s, contains('两者皆不需要 ⇒ 都不报'));
    });

    test('E3 允许同段双报但要求分别定位（防止用一条盖掉另一条）', () {
      final s = _p017();
      expect(s, contains('各报一条并分别定位'));
      expect(s, contains('不得只取其一'));
    });

    test('E4 P017 既有判据未被窄改③破坏', () {
      final s = _p017();
      expect(s, contains('先排除 P004 场景'));
      expect(s, contains('有功能的压缩不报'));
      expect(s, contains('position_sensitivity**: global'));
    });

    test('E5 双向对称：P002 侧也写了让位给 P017 的规则', () {
      // 单侧互斥 = 半条规则：P002 若不知道要让位，仍会继续抢。
      expect(_p002(), contains('P017'));
      expect(_p017(), contains('P002'));
    });
  });

  group('W-45 窄改③ · 抢边界的错误措辞已订正', () {
    test('F1 P037 划界表不再把「信息倾泻」算作 P017 的覆盖范围', () {
      // 该句在 manual_6 的 P037 段落；用全文检索锁定修订后的表述。
      final s = getSyndromeCriteriaSections(const ['P037']);
      expect(s, isNotEmpty);
      // 修订后保留「段落层」划界，但不再自称覆盖「信息倾泻」。
      expect(s, contains('单场内该展开的叙事被概括跳过'));
      expect(s, isNot(contains('铺陈失控/信息倾泻')));
    });

    test('F2 订正处带原因说明（防止后人「顺手改回去」）', () {
      final s = getSyndromeCriteriaSections(const ['P037']);
      expect(s, contains('措辞有误'));
      expect(s, contains('共用同一措辞会让 P017 越界抢报'));
    });
  });

  group('W-45 窄改②③ · 改动确实在注入面上（防空改）', () {
    test('G1 P002 属首轮注入集三巨头 ⇒ 密度上限随首轮就生效', () {
      expect(kFirstRoundCriteriaIds, contains('P002'));
      final block = buildFirstRoundCriteriaBlock();
      expect(block, contains('密度上限'));
    });

    test('G2 用户关闭该症候时首轮块不含密度上限（R-009 用户主权）', () {
      final block = buildFirstRoundCriteriaBlock(
        disabledSyndromeIds: const {'P002'},
      );
      expect(block, isNot(contains('密度上限')));
    });
  });
}
