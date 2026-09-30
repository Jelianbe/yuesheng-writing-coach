// ─────────────────────────────────────────────────────────────
// subplot_closure_detector — F11 情节闭环检测（批次67 B62j / A6 第二迭代）
//
// 规格（V2.0 §3.3 F11）：子线是否自然收束。
// 反馈范式：「第2卷引出了3条支线，目前只回收了1条」
// 观察项挂 P012 结尾仓促/伏笔埋设回收问题补充。
// 纯函数、无 IO，输入输出均为不可变数据，便于单测。
// ─────────────────────────────────────────────────────────────

/// 未回收支线观察项（挂 P012 补充输入）
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

/// A8：前置过滤「引入章已被删除」的幽灵支线。
///
/// 支线行的 `introduced*` 是**历史身份/标称号**，不会因章节被删而级联清空
/// （R1′ + 历史章节可被删/重排）。于是：用户删了支线引入的那章后，它的
/// `introducedSortOrder` 仍指向一个**已不存在**的 sortOrder，
/// `currentChapter - introducedKey` 算出一个超大正数 ⇒ 每次诊断都被误报成
/// 「引入后 N 章未回收」——可该引入章本身都不存在了，无从回收。
///
/// [existingChapterSortOrders] = 该作品现存（非回收站）章节的 `sortOrder` 集合。
/// 丢弃「引入章身份不在此集合内」的支线。引入章为空 ⇒ 保守保留（无锚点本就不检测）。
List<SubplotFactInput> dropGhostIntroducedSubplots(
  List<SubplotFactInput> inputs,
  Set<int> existingChapterSortOrders,
) {
  return [
    for (final s in inputs)
      if (_introducedChapterStillExists(s, existingChapterSortOrders)) s,
  ];
}

bool _introducedChapterStillExists(SubplotFactInput s, Set<int> existing) {
  final introduced = s.introducedSortOrder ?? s.introducedChapter;
  if (introduced == null) return true; // 无锚点 ⇒ 保守保留，不误杀存量
  return existing.contains(introduced);
}
