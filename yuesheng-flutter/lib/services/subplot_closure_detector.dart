// ─────────────────────────────────────────────────────────────
// subplot_closure_detector — F11 情节闭环检测（批次67 B62j / A6 第二迭代）
//
// 规格（V2.0 §3.3 F11）：子线是否自然收束。
// 反馈范式：「第2卷引出了3条支线，目前只回收了1条」
// 观察项挂 P014 结尾仓促（伏笔不回收）/ P017 伏笔埋设回收问题 补充。
// 纯函数、无 IO，输入输出均为不可变数据，便于单测。
// ─────────────────────────────────────────────────────────────

/// 未回收支线观察项（挂 P014/P017 补充输入）
class UnclosedSubplotObservation {
  /// 支线名（如「钥匙的秘密」）
  final String name;

  /// 引入章节序号（可空，无时间锚点的支线不检测）
  final int? introducedChapter;

  /// 作品当前推进章节
  final int currentChapter;

  /// 人类可读描述（例：第3章引入的支线「钥匙的秘密」至今（第12章）未回收）
  final String description;

  /// 触发原文摘录（O11，批次6 6.5）：正文中支线名的首现片段；
  /// 数据源无正文时由调用方反查填入，不可得为 null（降级安全，不输出）
  final String? excerpt;

  const UnclosedSubplotObservation({
    required this.name,
    required this.introducedChapter,
    required this.currentChapter,
    required this.description,
    this.excerpt,
  });
}

/// 检测输入：支线名 + 引入章节 + 回收章节（null=未回收）+ 引入章**身份键**
///
/// `N12-F3b`（`ADR-C96`）：新增 [introducedSortOrder] 专供**减法判据**用 ——
/// [introducedChapter] 是**一列多源值**（AI 标称号 / 机器身份），与恒为身份的
/// `currentChapter` 相减没有单一基线；存量行无身份 ⇒ 传 null，判据退回原值。
typedef SubplotFactInput = ({
  String name,
  int? introducedChapter,
  int? resolvedChapter,
  int? introducedSortOrder,
});

/// 引入后超过该章节数仍未回收 → 视为「收束滞后」（给作者留回收空间，避免误报）
const int kSubplotGraceChapterCount = 3;

/// 未回收且引入时间久于阈值 → 情节闭环观察项
///
/// 规则（保守，纯规则精确比较）：
///   1. resolvedChapter 为 null（未回收）；
///   2. 引入章节与当前章节均有值，且 当前章节 - 引入章节 >= 阈值（默认 3）；
///   3. 引入章节缺失的支线不检测（无时间锚点，无法判定收束滞后）。
/// 输出按 引入章节升序 稳定排序，便于测试与上下文注入。
List<UnclosedSubplotObservation> detectUnclosedSubplots(
  List<SubplotFactInput> subplots, {
  required int currentChapter,
  int graceChapterCount = kSubplotGraceChapterCount,
}) {
  final observations = <UnclosedSubplotObservation>[];

  for (final subplot in subplots) {
    final introduced = subplot.introducedChapter;
    if (subplot.resolvedChapter != null) continue; // 已回收
    if (introduced == null) continue; // 无时间锚点，保守跳过
    // ★ N12-F3b（`ADR-C96 §2` 消费侧冲突表第 4 行）：**减法判据吃身份** ——
    //   `currentChapter` 恒为身份（`message_injector` 传 `chapter.sortOrder`），
    //   与一列多源的 `introducedChapter` 相减本无单一基线 ⇒ 阈值判据会偏移。
    //   存量行无身份 ⇒ 退回原值，行为逐字不变。
    //   ⚠️ 下方 description 仍用 `introduced`（AI 原值）：它属 ADR 冻结的
    //   **9 处展示渲染**之一，phase 1 不改，切换留 phase 2（被 S1/S2/S3 阻塞）。
    final introducedKey = subplot.introducedSortOrder ?? introduced;
    if (currentChapter - introducedKey < graceChapterCount) continue;

    observations.add(
      UnclosedSubplotObservation(
        name: subplot.name,
        introducedChapter: introduced,
        currentChapter: currentChapter,
        description:
            '第$introduced章引入的支线「${subplot.name}」至今（第$currentChapter章）未回收',
      ),
    );
  }

  observations.sort(
    (a, b) => (a.introducedChapter ?? 0).compareTo(b.introducedChapter ?? 0),
  );
  return observations;
}
