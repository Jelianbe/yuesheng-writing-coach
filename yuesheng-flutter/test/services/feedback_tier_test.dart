// ─────────────────────────────────────────────────────────────
// feedback_tier_test — M2→M3 fading 支架渐退（ADR-C134 批2）
//
// 验收判据②：同一症候 prior=N 时注入块递减（指认+示范 → 根因+方向 → 引导提问）；
// scheduler 生产接线 selectVariantForRecurrence 的资格过滤 / 功能偏好 / 试点外回退。
//
// N 口径：prior = countConfirmedDiagnosesBySyndrome 在本轮落库前的 confirmed 计数
// （不含本轮）。c=0→N=1（默认路径，不注入）；c=1→N=2（根因+方向）；c≥2→N≥3（提问）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/feedback_tier.dart';
import 'package:writingcoach/services/feedback_variant_pool.dart';
import 'package:writingcoach/services/feedback_variant_scheduler.dart';

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

  group('scheduler 生产接线 · selectVariantForRecurrence', () {
    test('prior=1 → 直给判断类（指根因方向，非提问）', () {
      final v = selectVariantForRecurrence('P018', 1, FeedbackEligibility.all);
      expect(v, isNotNull);
      expect(v!.function, FeedbackFunction.directJudgment);
    });

    test('prior≥2 + highStable → 引导提问类', () {
      final v = selectVariantForRecurrence(
        'P018',
        2,
        FeedbackEligibility.highStableOnly,
      );
      expect(v, isNotNull);
      expect(v!.function, FeedbackFunction.guidedQuestion);
    });

    test('prior≥2 + 低稳定 → 降级直给（不越权选提问）', () {
      final v = selectVariantForRecurrence('P018', 2, FeedbackEligibility.all);
      expect(v, isNotNull);
      expect(v!.function, isNot(FeedbackFunction.guidedQuestion));
    });

    test('试点外症候（无池内变体）→ null（回退纯层级指令）', () {
      expect(
        selectVariantForRecurrence(
          'P999',
          2,
          FeedbackEligibility.highStableOnly,
        ),
        isNull,
      );
    });

    test('prior=1 + excludeIds 排除直给变体 → 换一条（近轮去重串联 fading 路径）', () {
      // ADR-C138 项①：selectVariantForRecurrence 必须透传 excludeIds。
      final first = selectVariantForRecurrence(
        'P018',
        1,
        FeedbackEligibility.all,
      );
      expect(first!.id, 'P018-direct-1'); // N=2 偏好直给，池内唯一直给
      final second = selectVariantForRecurrence(
        'P018',
        1,
        FeedbackEligibility.all,
        excludeIds: {first.id},
      );
      expect(second, isNotNull);
      expect(second!.id, isNot(first.id)); // 近轮已用 → 不再复用
    });
  });

  group('ADR-C138 项① · buildFadingBlock 串联近轮去重', () {
    test('excludeIdsBySyndrome 排除首条骨架 → 注入块换用另一变体文本', () {
      // 无排除：N=2 偏好直给 → P018-direct-1（含「语感被它拖住了」）。
      final base = buildFadingBlock({'P018': 1}, FeedbackEligibility.all)!;
      expect(base, contains('语感被它拖住了'));
      // 排除 P018-direct-1：直给候选空 → 安全回退 broader 集首条 = meta-1
      // （含「读者会下意识跳过它」），证明 excludeIds 经 buildFadingBlock 串联生效。
      final dedup = buildFadingBlock(
        {'P018': 1},
        FeedbackEligibility.all,
        excludeIdsBySyndrome: {
          'P018': {'P018-direct-1'},
        },
      )!;
      expect(dedup, isNot(contains('语感被它拖住了')));
      expect(dedup, contains('读者会下意识跳过它'));
    });

    test('默认不传 excludeIdsBySyndrome → 行为与既有一致（零漂移）', () {
      // 可选参数默认空：生产调用方 chat_service 不传时逐字节不变。
      final block = buildFadingBlock({'P018': 1}, FeedbackEligibility.all)!;
      expect(block, contains('语感被它拖住了'));
    });
  });

  group('ADR-C138 项③ · 试点外症候优雅降级（块级）', () {
    test('试点外症候 → 块保留层级指令、但无表达骨架（不注入措辞骨架）', () {
      // selectVariantForRecurrence(P999) → null → _lineFor skeleton=''。
      final block = buildFadingBlock({'P999': 1}, FeedbackEligibility.all)!;
      expect(block, contains('[P999]')); // 层级指令仍在
      expect(block, contains('只指根因与方向'));
      expect(block, isNot(contains('表达骨架'))); // 无池内变体 → 不注入骨架
    });
  });

  group('ADR-C138 项④ · {anchor} 由 LLM 落地（代码侧确认）', () {
    test('注入块保留 {anchor} 原文 + 附替换指令（不在注入时填充）', () {
      // C134 批2 现场裁定#1：注入发生在 LLM 诊断前，被标记原句未产生 →
      // 占位符保留 + 明示替换规则，由 LLM 落地真实片段（伪造即触 R-009）。
      final block = buildFadingBlock({'P018': 1}, FeedbackEligibility.all)!;
      expect(block, contains('{anchor}')); // 占位符未被预填
      expect(block, contains('替换后使用')); // 附替换指令交 LLM 落地
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
