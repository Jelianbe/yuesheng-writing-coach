// ─────────────────────────────────────────────────────────────
// chat_context_builder 主题分组拆分：chat_context_builder_observation.dart（R-019 ≤300 行）
// 五类规则观察上下文：buildConflictObservationsContext/buildCausalityBreakContext/buildSubplotClosureContext/buildGrammarLexicalContext/buildDialogueTagContext。逐字迁移自 chat_context_builder.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_context_builder.dart';
/// 时序矛盾观察上下文（批次66 B62i，A6 首步，挂 F05/P018 补充）
///
/// 输入 conflict_detector 输出的观察项（同属性不同值，带章节/时间维度）。
/// 无观察项 → 返回 null（调用方不注入，零 token 成本）。
/// 注入措辞遵循 A1 约束：只定位不代改、温和提问、软引导非硬拦截。
String? buildConflictObservationsContext(
  List<ConflictObservation> observations,
) {
  if (observations.isEmpty) return null;

  final lines = observations
      .map(
        (o) =>
            '- ${o.characterName}「${o.attribute}」：${o.description}'
            '${_excerptSuffix(o.excerpt)}',
      )
      .join('\n');

  return '## 时序矛盾观察（F05 补充）\n\n'
      '以下是作品中已记录的人物属性前后不一致（同属性不同值，按出现章节标注）。'
      '若这些矛盾确属事实性错误（而非角色刻意隐瞒或剧情转折），请结合 P018 人设崩塌症'
      '的判断原则提示学员，温和指出矛盾位置与前后差异（只定位，不代改正文）。\n\n'
      '$lines';
}

/// 因果链断裂观察上下文（批次67 B62j，A6 第二迭代 F07，挂 P021/P016 补充）
///
/// 输入 event_causality_detector 输出的观察项（关键事件缺前因，带章节维度）。
/// 无观察项 → 返回 null（调用方不注入，零 token 成本）。
/// 注入措辞遵循 A1 约束：只定位不代改、温和提问、软引导非硬拦截。
String? buildCausalityBreakContext(
  List<CausalityBreakObservation> observations,
) {
  if (observations.isEmpty) return null;

  final lines = observations
      .map((o) => '- ${o.description}${_excerptSuffix(o.excerpt)}')
      .join('\n');

  return '## 因果链断裂观察（F07 补充）\n\n'
      '以下是作品中已记录的关键事件（决定/转折/突发类）缺少触发事件（因果前驱缺失）。'
      '若确属「突然发生」而读者无法理解动机（而非有意留白或后续章节揭示），请结合 P021 跳跃叙事'
      '/ P016 情节巧合的判断原则提示学员，温和指出事件位置与缺位的前因（只定位，不代改正文）。\n\n'
      '$lines';
}

/// 情节闭环观察上下文（批次67 B62j，A6 第二迭代 F11，挂 P014/P017 补充）
///
/// 输入 subplot_closure_detector 输出的观察项（引入多章未回收的支线）。
/// 无观察项 → 返回 null（调用方不注入，零 token 成本）。
/// 注入措辞遵循 A1 约束：只定位不代改、温和提问、软引导非硬拦截。
String? buildSubplotClosureContext(
  List<UnclosedSubplotObservation> observations,
) {
  if (observations.isEmpty) return null;

  final lines = observations
      .map((o) => '- ${o.description}${_excerptSuffix(o.excerpt)}')
      .join('\n');
  final summary = observations.length >= 2
      ? '\n\n共 ${observations.length} 条支线收束滞后。'
      : '';

  return '## 情节闭环观察（F11 补充）\n\n'
      '以下是作品中已引入多章但至今未回收的支线。若这些支线并非有意留待后续收束，'
      '请结合 P014 结尾仓促 / P017 伏笔埋设回收问题的判断原则提示学员，'
      '温和指出各支线的引入位置与未回收现状（只定位，不代改正文）。\n\n'
      '$lines$summary';
}

/// 基础文法观察上下文（批次70 F12，挂 P022 重复用词/基础语病 补充）
///
/// 输入 grammar_lexical_detector 输出的观察项（相邻重复字/连续标点/
/// 句首重复/高频词密度，带原文证据）。
/// 无观察项 → 返回 null（调用方不注入，零 token 成本）。
/// 注入措辞遵循 A1 约束：只定位不代改、温和提问、软引导非硬拦截。
String? buildGrammarLexicalContext(List<GrammarLexicalIssue> issues) {
  if (issues.isEmpty) return null;

  final lines = issues
      .map((o) => '- ${o.description}：「${o.evidence}」')
      .join('\n');

  return '## 基础文法观察（F12 补充）\n\n'
      '以下是文本中检出的重复用词 / 基础文法问题（纯规则精确匹配，可能包含刻意修辞，'
      '请结合 P022 重复用词/基础语病的判断原则甄别）。'
      '若确属语病（而非刻意排比/口语习惯），温和指出位置与原文片段（只定位，不代改正文）。\n\n'
      '$lines';
}

/// 对话标签观察上下文（批次71 F02，挂 P011 对话疲劳症 增强补充）
///
/// 输入 dialogue_tag_detector 输出的观察项（同一修饰性对话标签重复，
/// 带原文证据）。无观察项 → 返回 null（调用方不注入，零 token 成本）。
/// 注入措辞遵循 A1 约束：只定位不代改、温和提问、软引导非硬拦截。
String? buildDialogueTagContext(List<DialogueTagIssue> issues) {
  if (issues.isEmpty) return null;

  final lines = issues
      .map((o) => '- ${o.description}：「${o.evidence}」')
      .join('\n');

  return '## 对话标签观察（F02 补充）\n\n'
      '以下是文本中重复出现的修饰性对话标签（纯规则精确匹配，'
      '可能属于刻意修辞或人物特征，请结合 P011 对话疲劳症的判断原则甄别）。'
      '若确属标签过度（而非低声密语场景的功能性需要 / 人物固定的口头式说话方式），'
      '温和指出位置与原文片段，提示可尝试用动作/表情替代标签（只定位，不代改正文）。\n\n'
      '$lines';
}

