// 故事结构画像（ADR-0006）
//
// 定位：把 `event_fact` 表里的事件序列压缩成 **几百字的结构画像**，注入
// 诊断 prompt，让模型能回答「这个故事整体结构怎么样」——而不用往 prompt
// 塞全文（后者是信息流硬扩，token 线性涨、注意力稀释、模型自己悟结构）。
//
// 事件序列是全文在结构维度上的**显式化压缩**：几百字承载「谁在第几章
// 因为什么做了什么、导致什么」。F07（因果断裂观察）已证明该通道走得通，
// 本文件把同一通道的用途从「找一个断裂」扩到「算整体画像」。
//
// ★ 覆盖度诚实性（C-3，本文件最高优先约束）：
// 事件是**诊断派生的**——只诊断过 3 章，画像就只有 3 章。若不显式写明
// 覆盖度，模型会把「第 3 章的节奏」说成「这个故事的节奏」——这比症候
// 假报更危险（假报骗一次，整体误判骗整个方向）。三条硬规则：
//   H-1 首行强制覆盖度声明（由 [buildStoryStructureProfile] 序列化保证）；
//   H-2 覆盖度低于阈值 ⇒ [buildStoryStructureProfile] 返回 null（不注入）；
//   H-3 verdict 契约层强制复述 coverage（见 diagnosis_parser `_parseOverall`）。
//
// 抽取质量自检（C-5）：模型抽事件丢事件 ⇒ 画像系统性失真。事件数/章节数
// 比例低于经验下界 ⇒ lowConfidence 标记 + 呈现层降权。
//
// 纯函数、无副作用、无外部依赖（输入是调用方从 repo 取好的数据），
// 便于单测。真源形态参照 event_causality_detector.dart。

import 'package:writingcoach/data/database/database.dart' show Chapter;
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';

import 'event_causality_detector.dart' show kCriticalEventTypes;

/// 供 feature 层（merge 链路两调用方）复用的「取数 + 构建」入口。///
/// 与 message_injector 短链路注入点共享同一构建函数（单一真源），
/// 差异仅在取数位置：短链路在 injector 内（已有 repo 句柄），
/// merge 链路调用方（chat_diagnosis_controller / writing_coach_panel_
/// diagnosis_runner）在 feature 层自己取。返回 null 级降级文本或 null
/// （不注入）；异常吞掉返回 null（不阻断诊断主流程）。
Future<String?> buildStoryStructureProfileText({
  required EventFactRepository eventFactRepo,
  required ChapterRepository chapterRepo,
  required DiagnosisRepository diagnosisRepo,
  required String manuscriptId,
}) async {
  try {
    final events = await eventFactRepo.listEvents(manuscriptId);
    if (events.isEmpty) return null;
    final chapters = await chapterRepo.listChapters(manuscriptId);
    if (chapters.isEmpty) return null;
    final rows = await diagnosisRepo.listDiagnosesForManuscript(manuscriptId);
    final chapterIds = rows
        .where((r) => r.targetRefType == 'chapter' && r.targetRefId != null)
        .map((r) => r.targetRefId!)
        .toSet();
    final List<Chapter> diagnosedChapters = chapterIds.isEmpty
        ? const []
        : await chapterRepo.getChaptersByIds(chapterIds.toList());
    final profile = buildStoryStructureProfile(
      events: events
          .map(
            (e) => (
              name: e.name,
              chapter: e.chapter,
              chapterSortOrder: e.chapterSortOrder,
              eventType: e.eventType,
              causeEventId: e.causeEventId,
              stale: e.stale != 0,
            ),
          )
          .toList(),
      diagnosedChapterKeys: diagnosedChapters
          .map((c) => c.sortOrder.toString())
          .toSet(),
      totalChapters: chapters.length,
    );
    return profile.injectable ? profile.text : null;
  } catch (_) {
    // 画像失败绝不阻断诊断主流程（与 F07 同款降级）。
    return null;
  }
}

/// 结构画像的输入事件（与 F07 `EventFactInput` 同型，另加 chapterSortOrder）。
typedef StructureProfileEventInput = ({
  String name,
  int? chapter,
  int? chapterSortOrder,
  String eventType,
  String? causeEventId,
  bool stale,
});

/// 覆盖度低于该比例 ⇒ 不注入画像（H-2：宁缺毋滥）。
const double kProfileMinCoverage = 0.3;

/// 画像块字符数预算闸（C-2）：超出即截断尾部指标行（覆盖度首行不动）。
const int kProfileMaxChars = 800;

/// 抽取质量下界：每已诊断章节少于该事件数 ⇒ 标记 lowConfidence（C-5）。
const double kProfileMinEventsPerChapter = 2.0;

/// 画像构建结果。
class StoryStructureProfile {
  /// 可直接注入的紧凑文本块（含覆盖度首行）；null 级降级不产生文本。
  final String? text;

  /// 已诊断章节数（覆盖度分子）。
  final int diagnosedChapters;

  /// 作品总章节数（覆盖度分母）。
  final int totalChapters;

  /// 覆盖度比例（0-1）。
  final double coverage;

  /// 抽取质量自检是否通过（false ⇒ 呈现层降权，C-5）。
  final bool qualityOk;

  /// 不注入的原因码（null = 可注入）。供日志/测试判读。
  final String? skipReason;

  const StoryStructureProfile({
    required this.text,
    required this.diagnosedChapters,
    required this.totalChapters,
    required this.coverage,
    required this.qualityOk,
    this.skipReason,
  });

  bool get injectable => text != null;
}

/// 构建故事结构画像（H-1/H-2/C-5 三判据的唯一实现点）。///
/// [events] 作品下全部事件（调用方取，通常来自 event_fact_repository）；
/// [diagnosedChapterKeys] 已诊断章节的身份键集合（chapter_sort_order 字符串化，
/// 由调用方从 diagnosis_results 的 targetRefId 反查章节后填充）；
/// [totalChapters] 作品总章节数。
///
/// 降级路径（均不报错、不编造、不注入）：
/// - 事件表为空 ⇒ skipReason='events_empty'；
/// - 覆盖度 < [kProfileMinCoverage] ⇒ skipReason='coverage_low'（H-2）；
/// - 抽取质量不过关（事件数/已诊断章节 < 下界）⇒ 仍注入但 qualityOk=false，
///   文本内标注低置信（C-5）。
StoryStructureProfile buildStoryStructureProfile({
  required List<StructureProfileEventInput> events,
  required Set<String> diagnosedChapterKeys,
  required int totalChapters,
}) {
  final live = events.where((e) => !e.stale).toList();
  if (live.isEmpty) {
    return _skip(
      reason: 'events_empty',
      diagnosed: 0,
      totalChapters: totalChapters,
    );
  }

  final diagnosed = _countDiagnosedChapters(live, diagnosedChapterKeys);
  final coverage = _coverageOf(diagnosed, totalChapters);

  // H-2：覆盖度不足 ⇒ 整块不注入（局部冒充整体比没有画像更糟）。
  if (coverage < kProfileMinCoverage) {
    return _skip(
      reason: 'coverage_low',
      diagnosed: diagnosed,
      totalChapters: totalChapters,
      coverage: coverage,
    );
  }

  // C-5：抽取质量自检（事件数 ÷ 已诊断章节数）。
  final qualityOk =
      diagnosed <= 0 || live.length / diagnosed >= kProfileMinEventsPerChapter;

  return StoryStructureProfile(
    text: _serialize(
      events: live,
      diagnosed: diagnosed,
      totalChapters: totalChapters,
      coverage: coverage,
      qualityOk: qualityOk,
    ),
    diagnosedChapters: diagnosed,
    totalChapters: totalChapters,
    coverage: coverage,
    qualityOk: qualityOk,
  );
}

/// 已诊断章节数 = 事件所在章节身份键与已诊断键集合的交集大小
/// （未诊断章节的事件理论上不存在，取交集防历史脏数据虚高）。
int _countDiagnosedChapters(
  List<StructureProfileEventInput> live,
  Set<String> diagnosedChapterKeys,
) {
  final eventChapterKeys = live
      .map((e) => e.chapterSortOrder?.toString())
      .whereType<String>()
      .toSet();
  return eventChapterKeys.where(diagnosedChapterKeys.contains).length;
}

/// 降级结果构造（text=null 的统一出口，R-019 拆出）。
StoryStructureProfile _skip({
  required String reason,
  required int diagnosed,
  required int totalChapters,
  double coverage = 0,
}) => StoryStructureProfile(
  text: null,
  diagnosedChapters: diagnosed,
  totalChapters: totalChapters,
  coverage: coverage,
  qualityOk: false,
  skipReason: reason,
);

/// 覆盖度比例（分母 0 防除零 ⇒ 0.0）。
double _coverageOf(int diagnosed, int totalChapters) =>
    totalChapters <= 0 ? 0.0 : diagnosed / totalChapters;

/// 序列化为紧凑文本块（H-1：首行强制覆盖度声明）。
///
/// 真分解（R-019）：指标计算拆 _typeDistribution / _causalityLine /
/// _densityLine 三个纯 helper，本函数只做拼接与预算闸。
String _serialize({
  required List<StructureProfileEventInput> events,
  required int diagnosed,
  required int totalChapters,
  required double coverage,
  required bool qualityOk,
}) {
  final pct = (coverage * 100).round();
  final buf = StringBuffer()
    ..writeln(
      '[结构画像] 基于已诊断 $diagnosed/$totalChapters 章（$pct%），'
      '未诊断章节不构成判断依据。以下是已诊断部分的**结构特征**，'
      '不是文学评价，也不替代逐条症候诊断。',
    )
    ..writeln('事件类型分布：${_typeDistribution(events)}');

  final causality = _causalityLine(events);
  if (causality != null) buf.writeln(causality);

  final density = _densityLine(events);
  if (density != null) buf.writeln(density);

  buf.writeln('孤儿关键事件（无前因）：${_orphanCount(events)} 个');

  // ⑤ 质量标注（C-5：抽取不过关 ⇒ 明示低置信，呈现层同降权）。
  if (!qualityOk) {
    buf.writeln('⚠ 事件密度异常偏低，画像可能不完整（低置信）。');
  }

  final out = buf.toString();
  if (out.length <= kProfileMaxChars) return out;
  // 预算闸（C-2）：超长时保留首行（覆盖度声明）与类型分布/因果两行核心指标，
  // 截断密度曲线等尾部细节。宁少勿假——截断必须可预期。
  final lines = out.split('\n');
  final kept = <String>[lines.first];
  for (final line in lines.skip(1)) {
    if (kept.join('\n').length + line.length + 1 > kProfileMaxChars) break;
    kept.add(line);
  }
  return kept.join('\n');
}

/// ① 事件类型分布串（「日常6 / 转折3」，按数量降序）。
String _typeDistribution(List<StructureProfileEventInput> events) {
  final byType = <String, int>{};
  for (final e in events) {
    byType[e.eventType] = (byType[e.eventType] ?? 0) + 1;
  }
  final dist = byType.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return dist.map((e) => '${e.key}${e.value}').join(' / ');
}

/// ② 因果链覆盖率行（关键事件有前因的比例；无关键事件 ⇒ null 不渲染）。
String? _causalityLine(List<StructureProfileEventInput> events) {
  final critical = events
      .where((e) => kCriticalEventTypes.contains(e.eventType))
      .toList();
  if (critical.isEmpty) return null;
  final withCause = critical
      .where((e) => e.causeEventId != null && e.causeEventId!.isNotEmpty)
      .length;
  final ratio = (withCause / critical.length * 100).round();
  return '因果链覆盖：关键事件（决定/转折/突发）$withCause/${critical.length} '
      '有前因（$ratio%）。';
}

/// ③ 章节密度曲线行（用 chapterSortOrder 身份键；无有效章节 ⇒ null）。
String? _densityLine(List<StructureProfileEventInput> events) {
  final byChapter = <int, int>{};
  for (final e in events) {
    final key = e.chapterSortOrder ?? e.chapter ?? -1;
    byChapter[key] = (byChapter[key] ?? 0) + 1;
  }
  final chapters = byChapter.keys.where((k) => k >= 0).toList()..sort();
  if (chapters.isEmpty) return null;
  final curve = chapters.map((c) => '${c + 1}章×${byChapter[c]}').join(' → ');
  return '章节事件密度：$curve';
}

/// ④ 孤儿关键事件数（无前因的关键事件——与 F07 同指标）。
int _orphanCount(List<StructureProfileEventInput> events) => events
    .where(
      (e) =>
          kCriticalEventTypes.contains(e.eventType) &&
          (e.causeEventId == null || e.causeEventId!.isEmpty),
    )
    .length;
