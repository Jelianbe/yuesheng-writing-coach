// ─────────────────────────────────────────────────────────────
// 候选区数据面闸牙测（R-027 · T-20261109-01 施工批）。
//
// 对应报批稿 §1.② 能变红判据：
//   B1  锚点滤网：anchor 为空 / 不命中声明域 ⇒ 不得 promoted（淘汰必达）
//   B2  三判据缺一即否决（occurrences<3 / reviewLog<2 / 草案空 / 判重未过）
//   B4  状态机单行道：retired 不得回到 candidate / promoted
//   C4  域内锚定：锚点须为声明域文本逐字子串（纯函数，不触现行门控）
//   计数口径：锚点归一化文本 × 来源文本 去重；同来源重复不计数
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/candidate_zone.dart';

void main() {
  final domainText = '本章正文……弗利西安看向火车的窗外。桦树林染上秋日的黄色。';

  CandidatePromotionRequest fullRequest() => CandidatePromotionRequest(
    declaredDomainText: domainText,
    criteriaDraft: '判据草案：遮名段落可原样搬入他作 ⇒ 判成立（能变红）',
    exceptionDraft: '例外：题材通用套语不计',
    reviewLog: <String>['复核者甲：通过', '复核者乙：通过'],
    duplicateCheckPassed: true,
  );

  group('登记与计数口径（晋升判据①）', () {
    test('新锚点 ⇒ occurrences=1；同来源重复不计数；异来源独立计数', () {
      final zone = CandidateZone();
      final first = zone.registerObservation(
        anchor: '弗利西安看向火车的窗外。',
        hypothesis: '开篇视角锚定',
        sourceTextId: 'chapter-1',
      );
      expect(first.status, CandidateStatus.candidate);
      expect(first.occurrences, 1);

      final sameSource = zone.registerObservation(
        anchor: '弗利西安看向火车的窗外。',
        hypothesis: '开篇视角锚定（同源重复）',
        sourceTextId: 'chapter-1',
      );
      expect(sameSource.occurrences, 1, reason: '同一来源重复不计入跨文本计数');

      final otherSource = zone.registerObservation(
        anchor: '  弗利西安看向火车的窗外。  ',
        hypothesis: '开篇视角锚定',
        sourceTextId: 'chapter-2',
      );
      expect(otherSource.occurrences, 2, reason: '异来源独立计数（锚点归一化后同键）');
    });

    test('空锚点 ⇒ 淘汰态且不入库（schema：空锚点 ⇒ retired）', () {
      final zone = CandidateZone();
      final entry = zone.registerObservation(
        anchor: '   ',
        hypothesis: 'x',
        sourceTextId: 'chapter-1',
      );
      expect(entry.status, CandidateStatus.retired);
      expect(zone.entries(), isEmpty, reason: '淘汰条目不占候选池');
    });

    test('promoted / retired 态不再累积（状态单行道）', () {
      final zone = CandidateZone();
      var entry = zone.registerObservation(
        anchor: '桦树林染上秋日的黄色。',
        hypothesis: 'h',
        sourceTextId: 's1',
      );
      zone.registerObservation(
        anchor: '桦树林染上秋日的黄色。',
        hypothesis: 'h',
        sourceTextId: 's2',
      );
      zone.registerObservation(
        anchor: '桦树林染上秋日的黄色。',
        hypothesis: 'h',
        sourceTextId: 's3',
      );
      entry = zone.registerObservation(
        anchor: '桦树林染上秋日的黄色。',
        hypothesis: 'h',
        sourceTextId: 's3',
      );
      expect(entry.occurrences, 3);

      final outcome = zone.promote(entry, fullRequest());
      expect(outcome, CandidatePromotionOutcome.promoted);

      final after = zone.registerObservation(
        anchor: '桦树林染上秋日的黄色。',
        hypothesis: 'h',
        sourceTextId: 's4',
      );
      expect(after.occurrences, 3, reason: 'promoted 后不再累积');
      expect(after.status, CandidateStatus.promoted);
    });
  });

  group('B1 锚点滤网', () {
    test('锚点不命中声明域 ⇒ rejectedAnchor + retired + 原因登记', () {
      final zone = CandidateZone();
      final entry = zone.registerObservation(
        anchor: '完全不在域内的句子',
        hypothesis: 'h',
        sourceTextId: 's1',
      );
      // 构造跨源三计数，排除 B2 混入（保证红只来自 B1）。
      zone.registerObservation(
        anchor: '完全不在域内的句子',
        hypothesis: 'h',
        sourceTextId: 's2',
      );
      final three = zone.registerObservation(
        anchor: '完全不在域内的句子',
        hypothesis: 'h',
        sourceTextId: 's3',
      );
      expect(three.occurrences, 3);

      final outcome = zone.promote(entry, fullRequest());
      expect(outcome, CandidatePromotionOutcome.rejectedAnchor);
      final stored = zone.entryByAnchor('完全不在域内的句子')!;
      expect(stored.status, CandidateStatus.retired);
      expect(stored.retireReason, 'anchor-not-in-domain');
    });
  });

  group('B2 三判据缺一即否决', () {
    CandidateEntry seedThree(CandidateZone zone) {
      zone.registerObservation(
        anchor: '桦树林染上秋日的黄色',
        hypothesis: 'h',
        sourceTextId: 'a',
      );
      zone.registerObservation(
        anchor: '桦树林染上秋日的黄色',
        hypothesis: 'h',
        sourceTextId: 'b',
      );
      return zone.registerObservation(
        anchor: '桦树林染上秋日的黄色',
        hypothesis: 'h',
        sourceTextId: 'c',
      );
    }

    test('occurrences < 3 ⇒ rejectedCriteria + retired', () {
      final zone = CandidateZone();
      final entry = zone.registerObservation(
        anchor: '桦树林染上秋日的黄色',
        hypothesis: 'h',
        sourceTextId: 'a',
      );
      expect(
        zone.promote(entry, fullRequest()),
        CandidatePromotionOutcome.rejectedCriteria,
      );
      expect(zone.entryByAnchor('桦树林染上秋日的黄色')!.status, CandidateStatus.retired);
    });

    test('reviewLog < 2 ⇒ 否决（分母非空对照：其余判据全满足）', () {
      final zone = CandidateZone();
      final entry = seedThree(zone);
      final request = CandidatePromotionRequest(
        declaredDomainText: domainText,
        criteriaDraft: '草案',
        exceptionDraft: '例外',
        reviewLog: <String>['只有一名复核者'],
        duplicateCheckPassed: true,
      );
      expect(
        zone.promote(entry, request),
        CandidatePromotionOutcome.rejectedCriteria,
      );
    });

    test('判据草案为空 ⇒ 否决（写不出 ⇒ 否决，逐字）', () {
      final zone = CandidateZone();
      final entry = seedThree(zone);
      final request = CandidatePromotionRequest(
        declaredDomainText: domainText,
        criteriaDraft: '   ',
        exceptionDraft: '例外',
        reviewLog: <String>['甲', '乙'],
        duplicateCheckPassed: true,
      );
      expect(
        zone.promote(entry, request),
        CandidatePromotionOutcome.rejectedCriteria,
      );
    });

    test('判重未通过 ⇒ 否决（判据③，离线工具批产出）', () {
      final zone = CandidateZone();
      final entry = seedThree(zone);
      final request = CandidatePromotionRequest(
        declaredDomainText: domainText,
        criteriaDraft: '草案',
        exceptionDraft: '例外',
        reviewLog: <String>['甲', '乙'],
        duplicateCheckPassed: false,
      );
      expect(
        zone.promote(entry, request),
        CandidatePromotionOutcome.rejectedCriteria,
      );
    });

    test('三判据全过 ⇒ promoted 且草案/留痕捆绑携带（一闸两身份）', () {
      final zone = CandidateZone();
      final entry = seedThree(zone);
      final outcome = zone.promote(entry, fullRequest());
      expect(outcome, CandidatePromotionOutcome.promoted);
      final stored = zone.entryByAnchor('桦树林染上秋日的黄色')!;
      expect(stored.status, CandidateStatus.promoted);
      expect(stored.criteriaDraft, isNotNull);
      expect(stored.exceptionDraft, isNotNull);
      expect(stored.reviewLog!.length, 2);
      expect(stored.retireReason, isNull);
    });
  });

  group('B4 状态机单行道', () {
    test('retired 不得回到 candidate / promoted', () {
      final zone = CandidateZone();
      final entry = zone.registerObservation(
        anchor: '不在域内',
        hypothesis: 'h',
        sourceTextId: 's1',
      );
      expect(
        zone.promote(entry, fullRequest()),
        CandidatePromotionOutcome.rejectedAnchor,
      );
      final retired = zone.entryByAnchor('不在域内')!;
      // 再试晋升（即使补齐全部判据）⇒ rejectedState，状态不变。
      expect(
        zone.promote(retired, fullRequest()),
        CandidatePromotionOutcome.rejectedState,
      );
      expect(zone.entryByAnchor('不在域内')!.status, CandidateStatus.retired);
    });
  });

  group('C4 anchorMatchesDomain', () {
    test('归一化后逐字子串命中；空锚点恒不命中', () {
      expect(
        anchorMatchesDomain('弗利西安看向火车的窗外。', domainText),
        isTrue,
        reason: '域文本逐字子串命中',
      );
      expect(
        anchorMatchesDomain('弗利西安  看向火车的窗外。', domainText),
        isFalse,
        reason: '归一化折叠出的单空格与域文本（无空格）不匹配 ⇒ 逐字语义',
      );
      expect(anchorMatchesDomain('窗外没有的句子', domainText), isFalse);
      expect(anchorMatchesDomain('   ', domainText), isFalse);
    });
  });
}
