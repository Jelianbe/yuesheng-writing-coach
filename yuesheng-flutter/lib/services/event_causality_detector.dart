// ─────────────────────────────────────────────────────────────
// event_causality_detector — F07 因果链断裂检测（批次67 B62j / A6 第二迭代）
//
// 规格（V2.0 §3.3 F07）：TKG 事件节点因果边缺失检测。
// 反馈范式：「主角为什么突然决定去那个城市？缺少一个触发事件」
// 观察项挂 P021 跳跃叙事 / P016 情节巧合 补充。
// 纯函数、无 IO，输入输出均为不可变数据，便于单测。
// ─────────────────────────────────────────────────────────────

/// 因果链断裂观察项（挂 P021/P016 补充输入）
class CausalityBreakObservation {
  /// 事件名（如「阿禾决定去金陵」）
  final String name;

  /// 事件发生章节序号（可空）
  final int? chapter;

  /// 事件类型（决定/转折/突发等关键类型）
  final String eventType;

  /// 人类可读描述（例：第5章「阿禾决定去金陵」（决定类）缺触发事件）
  final String description;

  /// 触发原文摘录（O11，批次6 6.5）：正文中事件名的首现片段；
  /// 数据源无正文时由调用方反查填入，不可得为 null（降级安全，不输出）
  final String? excerpt;

  const CausalityBreakObservation({
    required this.name,
    this.chapter,
    required this.eventType,
    required this.description,
    this.excerpt,
  });
}

/// 检测输入：事件名 + 章节 + 事件类型 + 因果边 + 旧版标记
///
/// C78 批次2b（§5.3）：`stale` 写进类型而非在调用点 `.where((e) => !e.stale)` 过滤
/// ——生产侧目前只有 1 个构造点，省事的调用点过滤将来新增时会**静默漏过滤**、
/// 重新长出幽灵 F07。写进 typedef 则**让编译器强制每个构造点表态**。
typedef EventFactInput = ({
  String name,
  int? chapter,
  String eventType,
  String? causeEventId,
  String? effectEventId,
  bool stale,
});

/// 需要因果解释的关键事件类型（决定/转折/突发——「突然…」「为什么…」）
const Set<String> kCriticalEventTypes = {'决定', '转折', '突发'};

/// 关键事件缺前因 → 因果链断裂观察项
///
/// 规则（保守，纯字符串精确比较，不做语义推断）：
///   1. eventType 属于关键事件类型（决定/转折/突发）；
///   2. 因果前驱 causeEventId 为空 → 缺触发事件；
///   3. 非关键事件（冲突/日常等）不检测，避免误报。
/// 输出按 章节（null 排最后）→ 事件名 稳定排序，便于测试与上下文注入。
///
/// C78 批次2b（§5.3）：`stale` 的事件**跳过**——它所属章节已被删除或已改写
/// （D-8），继续报「缺触发事件」是给用户报不存在的断裂（幽灵 F07）。
List<CausalityBreakObservation> detectCausalityBreaks(
  List<EventFactInput> events,
) {
  final observations = <CausalityBreakObservation>[];

  for (final event in events) {
    if (event.stale) continue;
    if (!kCriticalEventTypes.contains(event.eventType)) continue;
    if (event.causeEventId != null && event.causeEventId!.isNotEmpty) {
      continue; // 有前因，因果链完整
    }

    final chapter = event.chapter;
    final chapterText = chapter != null ? '第$chapter章' : '早期';
    observations.add(
      CausalityBreakObservation(
        name: event.name,
        chapter: chapter,
        eventType: event.eventType,
        description: '$chapterText「${event.name}」（${event.eventType}类）缺触发事件',
      ),
    );
  }

  observations.sort((a, b) {
    final ca = a.chapter ?? (1 << 30);
    final cb = b.chapter ?? (1 << 30);
    if (ca != cb) return ca.compareTo(cb);
    return a.name.compareTo(b.name);
  });
  return observations;
}
