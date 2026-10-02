// ─────────────────────────────────────────────────────────────
// FeedbackVariantPool — 话术变体池（ADR-C132 §4 三层调度 · 数据层）
//
// 定位：**静态注入资产**（写死标签 + 措辞骨架），与 skills_*.dart 的
// prompt 逻辑解耦。变体池不决定「诊断结论」，只提供「同一结论的不同
// 表达面」，由 persona 层（稳定声线）+ 软风格层（轮换表达）调度消费。
//
// 本文件是变体池的**真源数据层**：
//  - 增删变体 = 在此增删一条 FeedbackVariant（并跑完整性单测）
//  - 试点范围 = 少量高频症候（P018/P005/P021），每症候 ≥3 变体、
//    覆盖不同反馈功能组合（ADR §9 轮2：试点选型按「真实缺口」）
//  - 调度逻辑（选择变体 / 状态资格裁决 / 近轮去重）属批 2 注入链，
//    本文件不含任何调度代码
//
// R-009 边界（研讨报告 §4.3，写死在模板措辞里）：
//  - 直给判断只指根因与方向，禁成句 / 禁打分
//  - 元语言解释禁给可直接粘贴的成品改法
//  - 引导提问必须附方向兜底（Conrad & Goldstein 教训）
//  - 描述观察不隐含价值判决
// ─────────────────────────────────────────────────────────────

/// 反馈功能（主标签，互斥）。
///
/// 验收口径（挑战者 R8 裁决）：主标签互斥 + 次标签可叠加；
/// 放弃「互斥 / 穷尽」假目标，编码员信度 κ≥0.7 为准。
enum FeedbackFunction {
  /// 直给判断：指根因与方向（禁成句、禁打分）。
  directJudgment('direct_judgment'),

  /// 元语言解释：把现象翻译成概念，不替写。
  metalanguage('metalanguage'),

  /// 引导提问：只对中高水平 + 情绪平稳开放（资格门）。
  guidedQuestion('guided_question'),

  /// 描述观察：只描述看到的事实，不隐含价值判决。
  observation('observation');

  final String value;
  const FeedbackFunction(this.value);

  static FeedbackFunction? fromValue(String? v) {
    for (final f in FeedbackFunction.values) {
      if (f.value == v) return f;
    }
    return null;
  }
}

/// 状态资格（资格门）：决定变体允许被用于哪种学员状态。
///
/// 规则（研讨报告 §4）：提问类（guidedQuestion）限「中高水平 + 情绪
/// 平稳」；低水平 / 消沉状态走「直给 + 肯定 + 明确下一步」。资格裁决
/// 在批 2 调度层做，此处仅声明变体的适用资格。
enum FeedbackEligibility {
  /// 所有状态可用（直给 / 元语言 / 描述观察的默认资格）。
  all('all'),

  /// 仅中高水平 + 情绪平稳可用（引导提问的强制资格）。
  highStableOnly('high_stable_only');

  final String value;
  const FeedbackEligibility(this.value);
}

/// 变体池单条变体（措辞骨架 + 标签）。
///
/// [template] 含占位符（{anchor} = 稿件被标记片段，必需；
/// 其余如 {word} 由批 2 调度时按 [placeholders] 注入）。
class FeedbackVariant {
  /// 稳定 ID（变体级，供埋点 / 测试 / 近轮去重引用）。
  final String id;

  /// 症候 ID（软引用 syndrome_registry 的 P0XX）。
  final String syndromeId;

  /// 主标签（互斥）。
  final FeedbackFunction function;

  /// 次标签（可叠加，无 = 空集）。
  final Set<FeedbackFunction> secondaryFunctions;

  /// 状态资格（提问类必须 highStableOnly）。
  final FeedbackEligibility eligibility;

  /// 措辞骨架（含 {anchor} 等占位符）。
  final String template;

  /// 模板所需占位符集合（含 'anchor'）。
  final Set<String> placeholders;

  const FeedbackVariant({
    required this.id,
    required this.syndromeId,
    required this.function,
    this.secondaryFunctions = const {},
    this.eligibility = FeedbackEligibility.all,
    required this.template,
    required this.placeholders,
  });
}

/// 完整性断言（供单测 / 批 2 调度前防御）：
///  - 主标签互斥（函数签名已保证单值）
///  - 提问类必须带 highStableOnly 资格（研讨报告 §4 资格门）
///  - 模板必须含 {anchor} 占位（稿件锚定硬门层）
///  - 声明的占位符必须真的出现在模板里
String? validateVariant(FeedbackVariant v) {
  if (!v.template.contains('{anchor}')) {
    return '${v.id}: 模板必须含 {anchor} 锚定占位符';
  }
  if (v.function == FeedbackFunction.guidedQuestion &&
      v.eligibility != FeedbackEligibility.highStableOnly) {
    return '${v.id}: 引导提问类必须声明 highStableOnly 资格';
  }
  for (final p in v.placeholders) {
    if (!v.template.contains('{$p}')) {
      return '${v.id}: 占位符 {$p} 未出现在模板中';
    }
  }
  return null;
}

/// 试点变体池（首批：P018 重复用词/基础语病 · P005 句式节奏单一 ·
/// P021 画面感缺失；每症候 4 条，覆盖四类反馈功能）。
const List<FeedbackVariant> kFeedbackVariantPool = [
  // ── P018 重复用词 / 基础语病 ──
  FeedbackVariant(
    id: 'P018-direct-1',
    syndromeId: 'P018',
    function: FeedbackFunction.directJudgment,
    template:
        '「{anchor}」里「{word}」反复出现，语感被它拖住了。'
        '这是重复用词在作怪——方向是换词或删减，但具体怎么换，你自己定。',
    placeholders: {'anchor', 'word'},
  ),
  FeedbackVariant(
    id: 'P018-meta-1',
    syndromeId: 'P018',
    function: FeedbackFunction.metalanguage,
    template:
        '你连着在「{anchor}」里用了「{word}」，这在写作里叫重复用词：'
        '同一个词密度过高，读者会下意识跳过它。它不是错，是密度问题——'
        '把间隔拉开，语感就活了。',
    placeholders: {'anchor', 'word'},
  ),
  FeedbackVariant(
    id: 'P018-question-1',
    syndromeId: 'P018',
    function: FeedbackFunction.guidedQuestion,
    eligibility: FeedbackEligibility.highStableOnly,
    template:
        '回看「{anchor}」这一段，如果让你把「{word}」的位置腾出一半，'
        '你会优先留哪几处？留出来的空位，你想放点什么？',
    placeholders: {'anchor', 'word'},
  ),
  FeedbackVariant(
    id: 'P018-observation-1',
    syndromeId: 'P018',
    function: FeedbackFunction.observation,
    template:
        '我注意到「{anchor}」里「{word}」出现了几次，其他段落里它的'
        '密度明显低一些。',
    placeholders: {'anchor', 'word'},
  ),

  // ── P005 句式节奏单一 ──
  FeedbackVariant(
    id: 'P005-direct-1',
    syndromeId: 'P005',
    function: FeedbackFunction.directJudgment,
    template:
        '「{anchor}」这段的句子几乎同一个长度，读起来像匀速直线。'
        '这是句式节奏单一的根子——方向是拉开长短句的落差，具体在哪断，'
        '你来定。',
    placeholders: {'anchor'},
  ),
  FeedbackVariant(
    id: 'P005-meta-1',
    syndromeId: 'P005',
    function: FeedbackFunction.metalanguage,
    template:
        '「{anchor}」这段的句子长度趋同，在写作里叫句式节奏单一：'
        '节奏 = 长短句的落差，落差没了，读者的注意力就平了。'
        '试着让一个短句打破它。',
    placeholders: {'anchor'},
  ),
  FeedbackVariant(
    id: 'P005-question-1',
    syndromeId: 'P005',
    function: FeedbackFunction.guidedQuestion,
    eligibility: FeedbackEligibility.highStableOnly,
    template:
        '「{anchor}」里，哪一句是你最想让它「顿一下」的？如果把它'
        '拆短，你会拆在哪？',
    placeholders: {'anchor'},
  ),
  FeedbackVariant(
    id: 'P005-observation-1',
    syndromeId: 'P005',
    function: FeedbackFunction.observation,
    template: '我数了一下，「{anchor}」里连续几句的长度都在相近的区间。',
    placeholders: {'anchor'},
  ),

  // ── P021 画面感缺失 ──
  FeedbackVariant(
    id: 'P021-direct-1',
    syndromeId: 'P021',
    function: FeedbackFunction.directJudgment,
    template:
        '「{anchor}」只说了发生了什么，没让读者看见画面。这是画面感'
        '缺失——方向是补一个可感的具体细节，选什么细节，由你挑。',
    placeholders: {'anchor'},
  ),
  FeedbackVariant(
    id: 'P021-meta-1',
    syndromeId: 'P021',
    function: FeedbackFunction.metalanguage,
    template:
        '「{anchor}」这段话在写作里叫「概述叙事」：交代了结果，'
        '但缺可感的细节（视觉 / 听觉 / 触觉）。画面感 = 让读者用'
        '自己的感官补完场景。',
    placeholders: {'anchor'},
  ),
  FeedbackVariant(
    id: 'P021-question-1',
    syndromeId: 'P021',
    function: FeedbackFunction.guidedQuestion,
    eligibility: FeedbackEligibility.highStableOnly,
    template:
        '「{anchor}」发生时，房间里最显眼的一样东西是什么？如果让'
        '读者先看见它，再看见人物，你想怎么安排？',
    placeholders: {'anchor'},
  ),
  FeedbackVariant(
    id: 'P021-observation-1',
    syndromeId: 'P021',
    function: FeedbackFunction.observation,
    template:
        '「{anchor}」通篇没有一处具象的物象——视觉、听觉、触觉都'
        '没落地。',
    placeholders: {'anchor'},
  ),
];

/// 全池完整性校验（供单测；返回第一个违规描述，无违规 = null）。
String? validateVariantPool() {
  for (final v in kFeedbackVariantPool) {
    final err = validateVariant(v);
    if (err != null) return err;
  }
  return null;
}

/// 按症候取变体（无 = 空列表；批 2 调度层消费）。
List<FeedbackVariant> variantsForSyndrome(String syndromeId) => [
  for (final v in kFeedbackVariantPool)
    if (v.syndromeId == syndromeId) v,
];
