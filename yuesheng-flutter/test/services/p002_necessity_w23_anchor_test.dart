// ─────────────────────────────────────────────────────────────
// p002_necessity_w23_anchor_test — P002 必要性扩围 + 组合⑤ + W-23 真伪锚点
//
// 【来源】T-20261014-12 §五（2026-10-17 开工，舰长「立吧」= R-027 人工批准
//   判据正文改动）。修法①必要性首筛扩围（单句带过的必要事实）+ 修法②严重度
//   组合⑤（L2+ 双要素）+ 真伪锚点（X01 过敏型 / X22 GT 验证型）入库后的
//   **防回退**静态断言。
//
// 【为什么是静态断言】本轮改动在判据正文（KB 文案），行为验证（检测器对
//   X01 型压至 0 开报 / X22 型保持 L2）需 LLM 重跑 = R-027 另批项，不在本轮。
//   本测试锁死「改动在场」：短语/锚点被删或被改松 ⇒ 立刻红。
//
// 【锚点语料来源】W-23 交叉验证 240 格实测（.ai/research/cross-validation/
//   data/w23/w23_cells.json）：X01|t03|r2（检测器自述「这些信息本身必要」
//   仍开报 = 执行缺口）；X22|t03|r1（GT=P002 真阳性，成段多事实 + 论文式
//   结构）。两个锚点原文逐字入库。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';

void main() {
  final p002 = getSyndromeCriteriaSections(['P002']);

  setUpAll(() {
    expect(
      p002.isNotEmpty,
      true,
      reason: 'P002 段应可从 KB 提取（getSyndromeCriteriaSections）',
    );
  });

  group('P002 修法①：必要性首筛扩围（单句带过的必要事实）', () {
    test('含单句必要事实专条', () {
      expect(p002, contains('单句带过的必要事实专条'));
    });

    test('专条枚举普通人物背景句（W-23 X01 型病灶）', () {
      // 修法①的核心：必要类从「规则类」扩到「单句带过的事实信息」
      expect(p002, contains('人物背景'));
      expect(p002, contains('一句话带过'));
    });

    test('专条含「形态词不是病灶，必要性才是」的判据句', () {
      expect(p002, contains('形态词不是病灶，必要性才是'));
    });

    test('专条引用 W-23 实测反例（为了脱离他妈…找租房型）', () {
      expect(p002, contains('为了脱离他妈，毕业就四处找租房'));
    });
  });

  group('P002 修法②：严重度组合⑤（L2+ 双要素）', () {
    test('含组合⑤条目', () {
      // 断长串不短串：'组合⑤' 是子串，被改成 '组合⑤X' 仍会含 ⇒ 假绿。
      // 锁「组合⑤·L2+ 双要素判据」整句（变异必须破坏整句才红）。
      expect(p002, contains('组合⑤·L2+ 双要素判据'));
    });

    test('要素 a = 成段多事实（≥3 条，非单句带过）', () {
      expect(p002, contains('成段多事实'));
      expect(p002, contains('≥3 条'));
    });

    test('要素 b = 论文式结构或关切打断', () {
      expect(p002, contains('论文式结构或关切打断'));
      expect(p002, contains('原因有二'));
    });

    test('仅要素 b 不构成 L2（防量形式漏功能）', () {
      expect(p002, contains('仅 (b) 一条不构成 L2'));
      expect(p002, contains('量形式漏功能'));
    });

    test('单句带过一律封顶 L1', () {
      expect(p002, contains('单句带过的事实信息一律封顶 L1'));
    });
  });

  group('P002 真伪锚点（W-23 同库对照）', () {
    test('❌ 过敏型锚点：X01|t03|r2 原文逐字 + 不触发判定', () {
      expect(p002, contains('韩佑为了脱离他那个好管事的妈，大学一毕业就四处找租房'));
      expect(p002, contains('W-23 实证锚点 X01|t03|r2'));
      // 该锚点必须判「不触发」——若被改成开报，锚点即失效
      final anchorBlock = p002.substring(p002.indexOf('W-23 实证锚点 X01|t03|r2'));
      expect(anchorBlock, contains('不触发 P002'));
    });

    test('✅ 真阳型锚点：X22|t03|r1 原文逐字 + L2 判定', () {
      expect(p002, contains('全民偶像是一档国内首创的偶像类养成节目'));
      expect(p002, contains('W-23 GT 验证锚点 X22|t03|r1'));
      final anchorBlock = p002.substring(
        p002.indexOf('W-23 GT 验证锚点 X22|t03|r1'),
      );
      expect(anchorBlock, contains('P002 L2'));
    });

    test('两个锚点必须同时在库（同库对照缺一即红）', () {
      expect(p002, contains('W-23 实证锚点 X01|t03|r2'));
      expect(p002, contains('W-23 GT 验证锚点 X22|t03|r1'));
    });
  });

  group('P002 既有原则未被破坏（§4-192 四条 + 原有锚点）', () {
    test('必要性首筛仍在', () {
      expect(p002, contains('必要性首筛'));
    });

    test('生存/世界底层规则专条仍在', () {
      expect(p002, contains('旁白式生存/世界底层规则专条'));
    });

    test('量功能不量形式 + 悬浮≠倾泻 + 展示不必要组合仍在', () {
      expect(p002, contains('量功能不量形式'));
      expect(p002, contains('悬浮 ≠ 倾泻'));
      expect(p002, contains('严重度仅对「展示 + 不必要」组合定级'));
    });

    test('原 L2 命中锚点（天元大陆）与对话释放锚点仍在', () {
      expect(p002, contains('天元大陆有四大帝国'));
      expect(p002, contains('老铁匠把刀放在灯下看了看'));
    });
  });
}
