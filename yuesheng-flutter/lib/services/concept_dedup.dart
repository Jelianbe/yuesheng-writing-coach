// ─────────────────────────────────────────────────────────────
// concept_dedup — 多轮概念去重（FT-21，多轮协议 + 无状态恢复）
//
// 依据：架构真源 FT-21 — 重复解释问题，学员没理解概念时系统重复
//   同样定义。借鉴：多轮协议 + 无状态恢复。
//   现有 chat_gates.dart 的 hasDuplicateSuggestion 是教学建议去重
//   （防同症候重复推送建议），不是教学内容去重（防同概念重复解释）。
//
// 本模块为概念去重基础设施，不修改现有 chat_service（向后兼容）。
// 未来在上下文构建中注入"已解释概念"标记，让 LLM 知道哪些概念已解释过。
//
// 设计：
//   1. ConceptRegistry 追踪已解释概念（注册 + 查询 + 过期清理）
//   2. detectDuplicateConcepts 纯函数检测即将解释的概念是否已存在
//   3. 时间窗口：概念解释后 N 轮内不重复
// ─────────────────────────────────────────────────────────────

/// 已解释的概念记录
class ExplainedConcept {
  /// 概念标识（如"过渡句"、"情绪标签化"）
  final String conceptId;

  /// 解释时的对话轮次（turn 编号）
  final int explainedAtTurn;

  const ExplainedConcept({
    required this.conceptId,
    required this.explainedAtTurn,
  });
}

/// 概念注册表（追踪已解释概念）
class ConceptRegistry {
  /// 已解释概念列表
  final List<ExplainedConcept> _concepts = [];

  List<ExplainedConcept> get concepts => List.unmodifiable(_concepts);

  /// 去重窗口：概念解释后 N 轮内不重复（默认 5 轮）
  static const int kDedupWindowTurns = 5;

  /// 注册一个已解释概念
  void register(String conceptId, int turn) {
    _concepts.add(
      ExplainedConcept(conceptId: conceptId, explainedAtTurn: turn),
    );
  }

  /// 清理过期概念（超过去重窗口的记录）
  void pruneExpired(int currentTurn, {int window = kDedupWindowTurns}) {
    _concepts.removeWhere((c) => currentTurn - c.explainedAtTurn >= window);
  }

  /// 查询某概念是否在去重窗口内已解释过
  bool isRecentlyExplained(
    String conceptId,
    int currentTurn, {
    int window = kDedupWindowTurns,
  }) {
    return _concepts.any(
      (c) =>
          c.conceptId == conceptId && currentTurn - c.explainedAtTurn < window,
    );
  }

  /// 是否为空
  bool get isEmpty => _concepts.isEmpty;

  /// 已注册概念数
  int get length => _concepts.length;
}

/// 概念去重检测结果
class ConceptDedupResult {
  /// 需要解释的概念（未重复的）
  final List<String> newConcepts;

  /// 已重复的概念（窗口内已解释过的）
  final List<String> duplicateConcepts;

  const ConceptDedupResult({
    required this.newConcepts,
    required this.duplicateConcepts,
  });

  /// 是否有重复
  bool get hasDuplicates => duplicateConcepts.isNotEmpty;
}

/// 检测即将解释的概念是否已重复（纯函数，可单测）
///
/// 输入：即将解释的概念列表 + 当前注册表 + 当前轮次
/// 输出：新概念（需解释）+ 重复概念（已解释过，跳过）
ConceptDedupResult detectDuplicateConcepts({
  required List<String> incomingConcepts,
  required ConceptRegistry registry,
  required int currentTurn,
  int window = ConceptRegistry.kDedupWindowTurns,
}) {
  final newConcepts = <String>[];
  final duplicates = <String>[];

  for (final concept in incomingConcepts) {
    if (registry.isRecentlyExplained(concept, currentTurn, window: window)) {
      duplicates.add(concept);
    } else {
      newConcepts.add(concept);
    }
  }

  return ConceptDedupResult(
    newConcepts: newConcepts,
    duplicateConcepts: duplicates,
  );
}
