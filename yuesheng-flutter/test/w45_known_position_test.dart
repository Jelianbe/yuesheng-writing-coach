// ─────────────────────────────────────────────────────────────
// W-45 窄改①判据：真实章节位次进诊断上下文
//
// 背景：`.ai/reports/2026-10-20-W45-抽核回执与位置维度调查.md` §三 实测
// 240 格，P002 命中率 `<1000` 字组 **39.2%** vs `≥1000` 字组 **93.6%**。
// 差 54pp 来自位置块的一句「内容过短（< 1000 字）难以判断 ⇒ 判【全局】」
// —— 位置是**猜**的，不是**读**的。本批把真实位次传进去。
//
// 本测试的判据全部设计成**能变红**：
//   · 删掉追加分支 ⇒ C1/C2/C3 变红（不是「写了就绿」的同义反复）
//   · 把覆盖句删掉   ⇒ C4 变红（保证「覆盖过短兜底」这句话真的在正文里）
//   · 把映射改错     ⇒ C5–C7 变红（三档 + 单章特例）
//
// 零位次 ⇒ 逐字节不变，是本批锚点零漂移的依据（C8 逐字节比对，非长度近似）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 组一条最小可用的 ctx（与 skill_prompt_anchor_test 同源形状）。
SkillLoadContext _ctx({int? order, int? total}) => SkillLoadContext(
  phase: TeachingPhase.p1World,
  attitude: AttitudeLevel.yuesheng,
  chapterOrder: order,
  totalChapters: total,
);

String _prompt({int? order, int? total}) =>
    buildSystemPromptV2(_ctx(order: order, total: total)).systemPrompt;

void main() {
  group('W-45 窄改① · 零位次时逐字节不变（锚点零漂移依据）', () {
    test('C8a 未传位次 ⇒ prompt 不含任何「已知位置」痕迹', () {
      final p = _prompt();
      expect(p, isNot(contains('本次诊断对象的真实位置')));
      expect(p, contains(kPositionGuidanceConstSection));
    });

    test('C8b 只传一半（order 有 / total 无）⇒ 按未传处理，不注入', () {
      // 半截信息无法定位（不知道总章数就判不了结尾），必须 fail-closed 到「不注入」，
      // 而不是拿 order 单值硬猜。若将来改成允许单值注入，此条应变红。
      final p = _prompt(order: 3);
      expect(p, isNot(contains('本次诊断对象的真实位置')));
    });

    test('C8c 只传一半（total 有 / order 无）⇒ 不注入', () {
      final p = _prompt(total: 10);
      expect(p, isNot(contains('本次诊断对象的真实位置')));
    });

    test('C8d 非法值（order=0 / total=0）⇒ 不注入', () {
      // 位次是 1 基索引，0 与负数都是脏数据；不得据此构造「第 0 章」这种提示。
      expect(_prompt(order: 0, total: 10), isNot(contains('本次诊断对象的真实位置')));
      expect(_prompt(order: 1, total: 0), isNot(contains('本次诊断对象的真实位置')));
      expect(_prompt(order: -1, total: 10), isNot(contains('本次诊断对象的真实位置')));
    });

    test('C8e 零位次与改造前基线逐字节一致（仅含位置块、无覆盖块）', () {
      final p = _prompt();
      expect(p.contains(kPositionGuidanceConstSection), isTrue);
      expect(p.indexOf('本次诊断对象的真实位置'), -1);
    });
  });

  group('W-45 窄改① · 有位次时注入覆盖块', () {
    test('C1 第 1 章 / 共 10 章 ⇒ 注入且判开头', () {
      final p = _prompt(order: 1, total: 10);
      expect(p, contains('本次诊断对象的真实位置'));
      expect(p, contains('第 **1** 章'));
      expect(p, contains('共 **10** 章'));
      expect(p, contains('位置 = **开头**'));
    });

    test('C2 中间章 / 共 10 章 ⇒ 判中段', () {
      expect(_prompt(order: 5, total: 10), contains('位置 = **中段**'));
    });

    test('C3 末章 / 共 10 章 ⇒ 判结尾', () {
      expect(_prompt(order: 10, total: 10), contains('位置 = **结尾**'));
    });

    test('C4 ★ 覆盖「过短 ⇒ 判全局」兜底（短文本才是本次改动的主体）', () {
      // 无这句，短文本仍退回【全局】⇒ `<1000` 字那 130 格完全不受本次改动影响，
      // 也就是整个窄改①白做。此句是判据的承重部分。
      final p = _prompt(order: 2, total: 8);
      expect(p, contains('内容过短（< 1000 字）难以判断 ⇒ 判全局'));
      expect(p, contains('直接采用它'));
      expect(p, contains('文本长度不是位置证据'));
    });

    test('C5 单章书（order==total==1）⇒ 判全局而非开头', () {
      final p = _prompt(order: 1, total: 1);
      expect(p, contains('全书仅此一章'));
      expect(p, isNot(contains('位置 = **开头**')));
      expect(p, isNot(contains('位置 = **结尾**')));
    });

    test('C6 两章书：第 1 章⇒开头，第 2 章⇒结尾（两档都不可退化）', () {
      expect(_prompt(order: 1, total: 2), contains('位置 = **开头**'));
      expect(_prompt(order: 2, total: 2), contains('位置 = **结尾**'));
    });

    test('C7 保留唯一例外通道（段级形态可细化章级位次，但须写明理由）', () {
      // 完全禁止例外会把「全书第 2 章里写了全书高潮」这类真实文本也压死；
      // 完全放开则本批等于没做（模型随时可以改判回它猜的位置）。
      final p = _prompt(order: 4, total: 9);
      expect(p, contains('内容形态'));
      expect(p, contains('故改判为'));
      expect(p, contains('无此形态证据时不得改判'));
    });
  });

  group('W-45 窄改① · 映射逻辑单元判据（buildKnownPositionBlock 直测）', () {
    test('三档边界：首/末/中，含 total==1 特例', () {
      // T-20261025-06 Q2 乙（2026-10-31 舰长批）：开头覆盖前三章 ⇒ (2,3)、(3,3)
      // 中 (3,3) 因 end 优先归结尾；(2,3) 由旧期望「中段」改为「开头」。
      expect(buildKnownPositionBlock(1, 3), contains('位置 = **开头**'));
      expect(buildKnownPositionBlock(2, 3), contains('位置 = **开头**'));
      expect(buildKnownPositionBlock(3, 3), contains('位置 = **结尾**'));
      expect(buildKnownPositionBlock(4, 5), contains('位置 = **中段**'));
      expect(buildKnownPositionBlock(1, 1), contains('全书仅此一章'));
    });

    test('覆盖块恒含「已知位置」小节标题（便于分节级指纹归因）', () {
      expect(
        buildKnownPositionBlock(2, 5),
        contains('## 本次诊断对象的真实位置（系统已核对，优先于上文推测）'),
      );
    });
  });

  group('W-45 窄改① · 位置块在 prompt 中的相对次序', () {
    test('覆盖块在位置引导块之后（后写覆盖先写）', () {
      final p = _prompt(order: 3, total: 12);
      final iGuidance = p.indexOf(kPositionGuidanceConstSection);
      final iKnown = p.indexOf('本次诊断对象的真实位置');
      expect(iGuidance, greaterThanOrEqualTo(0));
      expect(iKnown, greaterThan(iGuidance));
    });

    test('覆盖块在边界声明之前（边界声明始终是最后一段）', () {
      final p = _prompt(order: 3, total: 12);
      expect(p.indexOf('本次诊断对象的真实位置'), lessThan(p.indexOf('【边界声明】')));
    });
  });
}
