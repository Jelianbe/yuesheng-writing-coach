// ─────────────────────────────────────────────────────────────
// 机器回执态（P0，2026-08-18）
//
// 设计来源：福帮手「质量态三档」思想（advisory / machine_receipt_present /
// human_review_pending）。月笙教练遵循「不替写、不替决定」，但 LLM 输出偶尔会
// 自称「已保存 / 已导出 / 已应用 / 已修改」——这些动作教练本回合并未真实执行，
// 属于虚假断言。本工具是纯函数式安全网：凡自称完成某动作但不具备真实机器回执，
// 一律降级为「建议 X」语气，避免对学员产生「我已替你做过」的误导。
//
// 设计约束（R-010 最小范围 / R-021 不替决定）：
//   1. 不改动任何诊断 / 教学 / 引用逻辑，只在「落库前」对文本做一次降级。
//   2. 仅当本回合 service 确实落库了对应动作时，才把该动作加入 receipts，避免误降级。
//   3. 降级是保守的：只匹配「已X」连续写法，不以「为你/帮你」等做主语猜测，避免误伤。
// ───────────────────────── (END)

/// 动作类型：教练本回合可能「自称已完成」的动作。
enum ReceiptAction {
  saved('保存'), // 保存（稿件 / 诊断 / 草稿）
  exported('导出'), // 导出
  applied('应用'), // 把修改应用到正文
  modified('修改') // 修改正文内容
  ;

  /// 命中短语：即「已 + 动作」形式（如「已保存」）。
  final String claimPhrase;
  const ReceiptAction(this.claimPhrase);

  /// 降级后的建议语气短语（如「建议保存」）。
  String get advisoryPhrase => '建议$claimPhrase';
}

/// 回执判定结果。
enum ReceiptStatus {
  receiptOk('receipt_ok'), // 回复中无任何未支撑的「已X」声明
  humanReviewPending('human_review_pending') // 存在未支撑声明，已降级，需人工复核
  ;

  final String value;
  const ReceiptStatus(this.value);

  static ReceiptStatus? fromString(String? s) =>
      ReceiptStatus.values.where((e) => e.value == s).firstOrNull;
}

/// 降级结果与元数据，供上层（日志 / UI / 后续契约测试）消费。
class ReceiptGuardResult {
  final String text; // 降级后的文本
  final ReceiptStatus status;
  final List<ReceiptAction> downgraded; // 被降级的动作清单

  const ReceiptGuardResult({
    required this.text,
    required this.status,
    required this.downgraded,
  });
}

/// 回复回执守护：把没有真实机器回执的动作声明降级为建议语气。
///
/// [text] 为本回合将要落库的 assistant 回复文本。
/// [receipts] 为本回合 service 真实落库的动作（调用方依据实际 DB 写入传入）。
class ReplyReceiptGuard {
  /// 对 [text] 逐动作扫描：若某「已X」声明不在 [receipts] 中，则改写为「建议X」。
  /// 返回降级后的文本与判定状态；纯函数，无副作用。
  static ReceiptGuardResult sanitize(
    String text, {
    required Set<ReceiptAction> receipts,
  }) {
    String result = text;
    final downgraded = <ReceiptAction>[];
    for (final action in ReceiptAction.values) {
      if (receipts.contains(action)) continue; // 有真实回执，声明属实
      final claim = '已${action.claimPhrase}';
      if (result.contains(claim)) {
        result = result.replaceAll(claim, action.advisoryPhrase);
        downgraded.add(action);
      }
    }
    final status = downgraded.isEmpty
        ? ReceiptStatus.receiptOk
        : ReceiptStatus.humanReviewPending;
    return ReceiptGuardResult(
      text: result,
      status: status,
      downgraded: downgraded,
    );
  }

  /// 便捷判断：回复是否包含任意「已X」声明（不论是否有回执）。
  static bool hasAnyClaim(String text) =>
      ReceiptAction.values.any((a) => text.contains('已${a.claimPhrase}'));
}
