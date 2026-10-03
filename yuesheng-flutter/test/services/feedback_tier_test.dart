// ─────────────────────────────────────────────────────────────
// feedback_tier_test — M2→M3 fading 支架渐退（ADR-C134 批2）
//
// 验收判据②：同一症候 prior=N 时注入块递减（指认+示范 → 根因+方向 → 引导提问）。
//
// C146（变体池摘除批）：话术变体池成句模板及其生产注入已按 96-17 反硬编码护栏
// 摘除——本文件随之删除「scheduler 接线 / 近轮去重 / {anchor} 骨架」三组用例；
// 保留 fading 三档行为、资格门安全降级与 R-009 形态审计（教学策略层，非话术）。
//
// N 口径：prior = countConfirmedDiagnosesBySyndrome 在本轮落库前的 confirmed 计数
// （不含本轮）。c=0→N=1（默认路径，不注入）；c=1→N=2（根因+方向）；c≥2→N≥3（提问）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/feedback_tier.dart';

void main() {
  group('tierForPriorCount · 层级映射', () {
    test('c=0 → firstTouch（N=1 默认教学路径）', () {
      expect(tierForPriorCount(0), FeedbackTier.firstTouch);
    });
    test('c=1 → rootCauseOnly（N=2 只指根因+方向）', () {
      expect(tierForPriorCount(1), FeedbackTier.rootCauseOnly);
    });
    test('c=2 → guidedRecall（N≥3 引导自主指认）', () {
      expect(tierForPriorCount(2), FeedbackTier.guidedRecall);
    });
    test('c≥3 仍为 guidedRecall', () {
      expect(tierForPriorCount(5), FeedbackTier.guidedRecall);
    });
  });

  group('buildFadingBlock · 注入块按层级递减', () {
    test('无复发（空表 / 全部 c<1）→ 仍输出三档介入契约块（c=0 指认+受限示范单句可达）', () {
      // ADR-C139（D1 修复）：此前返回 null → c=0 指令不可达（LLM 转引导式追问、
      // 无示范句）。现始终输出契约块，纯首次诊断也能看到「指认根因+受限示范单句」。
      final empty = buildFadingBlock({}, FeedbackEligibility.all);
      expect(empty, isNotNull);
      expect(empty, contains('受限示范单句'));
      expect(empty, contains('首次出现（第 1 次）'));
      expect(empty, contains('只示范一句'));
      // c=0 契约不得替写整段
      expect(empty, contains('不改全段'));
      final zero = buildFadingBlock({'P018': 0}, FeedbackEligibility.all);
      expect(zero, isNotNull);
      expect(zero, isNot(contains('[P018]'))); // c<1 不进复发明细
    });

    test('D1 契约：三档语义齐全且受限（c=0 示范单句 / c=1 根因方向 / c≥2 引导提问）', () {
      final block = buildFadingBlock({
        'P018': 1,
        'P021': 3,
      }, FeedbackEligibility.highStableOnly)!;
      expect(block, contains('首次出现（第 1 次）')); // c=0 契约常驻
      expect(block, contains('受限示范单句')); // c=0 给一句受限示范
      expect(block, contains('只指根因与方向')); // c=1
      expect(block, contains('你发现这一处的问题了吗')); // c≥2
      // 示范受限：不替写整段、不替写成品
      expect(block, contains('不改全段'));
      expect(block, contains('不替写成品段落'));
    });

    test('N=2（c=1）→ 根因+方向块，无引导提问', () {
      final block = buildFadingBlock({'P018': 1}, FeedbackEligibility.all);
      expect(block, isNotNull);
      expect(block, contains('[P018]'));
      // 契约头常驻三档描述（含 c≥2 提问句），故只对「复发明细段」断言层级归属。
      final detail = block!.split('本会话此前已诊断过')[1];
      expect(detail, contains('只指根因与方向'));
      // N=2 的复发行不得出现 N≥3 的引导提问句
      expect(detail, isNot(contains('你发现这一处的问题了吗')));
    });

    test('N≥3（c≥2）+ highStable → 引导提问「你发现了吗」且不提示答案', () {
      final block = buildFadingBlock({
        'P021': 2,
      }, FeedbackEligibility.highStableOnly);
      expect(block, isNotNull);
      expect(block, contains('你发现这一处的问题了吗'));
      expect(block, contains('不要提示答案'));
    });

    test('N≥3 + 低稳定资格 → 安全降级为根因+方向（不用提问类）', () {
      final block = buildFadingBlock(
        {'P021': 3},
        FeedbackEligibility.all, // 低水平/消沉
      );
      expect(block, isNotNull);
      // 契约头常驻三档描述，只对「复发明细段」断言降级归属。
      final detail = block!.split('本会话此前已诊断过')[1];
      expect(detail, isNot(contains('你发现这一处的问题了吗')));
      expect(detail, contains('只指根因与方向'));
    });

    test('多症候混合：c=1 根因 / c≥2 提问 各自成线', () {
      final block = buildFadingBlock({
        'P018': 1,
        'P005': 3,
      }, FeedbackEligibility.highStableOnly);
      expect(block, isNotNull);
      expect(block, contains('[P018]'));
      expect(block, contains('[P005]'));
      expect(block, contains('只指根因与方向')); // P018 c=1
      expect(block, contains('你发现这一处的问题了吗')); // P005 c=3
    });
  });

  group('C146 · 复发行只含层级指令、不注入成句骨架', () {
    test('任意症候复发 → 块保留层级指令、无表达骨架（不注入写死成句）', () {
      // 话术变体池已按 96-17 反硬编码护栏摘除：复发行只输出教学层级指令，
      // 不得再出现「表达骨架」/ 写死成句模板（具体措辞由 AI 现场生成）。
      final block = buildFadingBlock({'P999': 1}, FeedbackEligibility.all)!;
      expect(block, contains('[P999]')); // 层级指令仍在
      expect(block, contains('只指根因与方向'));
      expect(block, isNot(contains('表达骨架'))); // 池摘除 → 无骨架注入
    });
  });

  group('R-009 形态审计 · 注入块文本', () {
    test('块内不打分、提问不提示答案', () {
      final block = buildFadingBlock({
        'P018': 1,
        'P021': 2,
      }, FeedbackEligibility.highStableOnly)!;
      // 无评分词
      expect(block.contains('分'), isFalse, reason: '注入块不得出现评分词');
      // 引导提问必须带「不提示答案」护栏
      expect(block, contains('不要提示答案'));
    });
  });
}
