import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/reply_receipt_guard.dart';

void main() {
  group('ReplyReceiptGuard.sanitize', () {
    test('无回执时把「已X」降级为「建议X」', () {
      const input = '我已经帮你把这段润色好了，已保存到你的作品里。';
      final r = ReplyReceiptGuard.sanitize(
        input,
        receipts: const {},
      );
      expect(r.text, '我已经帮你把这段润色好了，建议保存到你的作品里。');
      expect(r.status, ReceiptStatus.humanReviewPending);
      expect(r.downgraded, contains(ReceiptAction.saved));
    });

    test('有回执时不降级对应声明', () {
      const input = '诊断已保存，结论如下。';
      final r = ReplyReceiptGuard.sanitize(
        input,
        receipts: {ReceiptAction.saved},
      );
      expect(r.text, '诊断已保存，结论如下。');
      expect(r.status, ReceiptStatus.receiptOk);
      expect(r.downgraded, isEmpty);
    });

    test('「已应用 / 已修改」永远降级（教练不替正文改动）', () {
      const input = '我已应用到全文，并已修改了三个段落。';
      final r = ReplyReceiptGuard.sanitize(
        input,
        receipts: const {ReceiptAction.saved},
      );
      // ADR-P0：降级规则为「已X」→「建议X」，不做主语改写（保守优先）；
      // 「已应用/已修改」属替正文改动的动作，永不进 receipts，即使有其它回执也降级。
      expect(r.text, '我建议应用到全文，并建议修改了三个段落。');
      expect(r.downgraded, containsAll([ReceiptAction.applied, ReceiptAction.modified]));
    });

    test('多动作混合：仅降级无回执者', () {
      const input = '已导出，已应用，已修改。';
      final r = ReplyReceiptGuard.sanitize(
        input,
        receipts: {ReceiptAction.exported},
      );
      expect(r.text, '已导出，建议应用，建议修改。');
      expect(r.downgraded, containsAll([ReceiptAction.applied, ReceiptAction.modified]));
      expect(r.downgraded, isNot(contains(ReceiptAction.exported)));
    });

    test('空输入与无声明输入安全返回', () {
      final r1 = ReplyReceiptGuard.sanitize('', receipts: const {});
      expect(r1.text, '');
      expect(r1.status, ReceiptStatus.receiptOk);

      final r2 = ReplyReceiptGuard.sanitize('请参考上面的建议自行调整。', receipts: const {});
      expect(r2.text, '请参考上面的建议自行调整。');
      expect(r2.status, ReceiptStatus.receiptOk);
    });

    test('hasAnyClaim 识别声明', () {
      expect(ReplyReceiptGuard.hasAnyClaim('已保存'), isTrue);
      expect(ReplyReceiptGuard.hasAnyClaim('建议你保存'), isFalse);
      expect(ReplyReceiptGuard.hasAnyClaim('普通文本'), isFalse);
    });
  });
}
