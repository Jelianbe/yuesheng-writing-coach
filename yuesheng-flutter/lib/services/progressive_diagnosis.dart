// ─────────────────────────────────────────────────────────────
// ProgressiveDiagnosis — 长文本分块诊断
//
// 移植 RN progressive-diagnosis.ts
// 核心职责：
//   1. splitContent：按段落 + overlap 分块（SIZE=3000 / OVERLAP=200 / MIN_LAST_CHUNK=500）
//   2. analyzeChunk：每块用 CHUNK_SYSTEM_PROMPT 识别症候（输出 JSON notes）
//   3. buildMergePrompt：注入 SYNDROME_DIAGNOSIS_SKILL + 前次活跃症候上下文 + 合并规则
//   4. runProgressiveDiagnosis：按 THRESHOLD=4000 路由，超长走分块，否则返回 null
//
// 与 ChatService 的整合（D2 WritingCoachPanel 调用）：
//   - runProgressiveDiagnosis 返回非 null → 走分块链路
//   - 返回 null → 走 ChatService.sendMessage 单次链路（D1 已接通）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/shared_constants.dart';
import 'decode_guard.dart';
import 'error_handler.dart';
import 'llm_call_log_sink.dart';
import 'llm_client.dart';
import 'llm_usage.dart';
import 'syndrome_registry.dart'; // ADR-C69：分块 prompt 的症候清单改由注册表派生
// 治理续批第二批（2026-10-20 · 路 α · R-027 批准）：S3 三判据 + 形态字段段的**唯一定义源**。
// 两宿主（merge 链 / 单次链）各插值引用 ⇒ 跨链判据逐字同一、零复制漂移。
import 'intervention_value.dart'
    show kInterventionValueS3Criteria, kFormFieldCriteria;
import 'token_budget_guard.dart'; // W-15-B B1：merge 预算预检（estimate + 报告同构）
import 'output_whitelist.dart'; // L3：severity 白名单归一化
import '../types/teaching_types.dart';

// ── 常量（对齐 RN shared-constants.ts DIAGNOSIS_CHUNK）──
/// 触发分块诊断的字符阈值
const int kDiagnosisChunkThreshold = 4000;

/// 单块字符大小
const int kDiagnosisChunkSize = 3000;

/// 块间重叠字符数（保证跨块上下文连续）
const int kDiagnosisChunkOverlap = 200;

/// 末块最小字符数（<此值时与前块合并，避免末块只有一两句）
const int kDiagnosisMinLastChunk = 500;

/// TH 九批：诊断链路的埋点上下文（三处调用共用；顶层常量 ⇒ 不占 R-019）。
const _kDiagnosisCallContext = LlmCallContext(
  purpose: LlmCallPurpose.diagnosis,
);

// ── 数据类型（对齐 RN ChunkNote / ChunkAnalysisResult）──

/// 单块识别到的一条症候笔记
class ChunkNote {
  final String syndromeId;
  final String description;
  final List<String> evidence;
  final String severity; // L1 / L2 / L3

  /// ★ 分片阶段**判不了**这条（依赖片段外信息），交由 merge 裁决
  /// （2026-10-21，ADR-C153 §2）。缺省 false。
  ///
  /// 为什么需要它：`_kChunkWindowBoundary` 让模型承认「看不到片段之外」，
  /// 但承认之后必须**有地方放**。若只有文字声明没有结构化字段，merge 阶段读到的
  /// 仍是一堆肯定结论 —— 声明 ≠ 生效（同族：例外写进手册但分块链不加载）。
  ///
  /// 与 merge 侧 `pending_context` 的关系：两者是**同一语义的两端**——
  /// 本字段标「我现在判不了」，`pending_context` 标「我合并后仍判不了」。
  /// 缺了本字段，后者就没有输入源。
  final bool uncertain;

  const ChunkNote({
    required this.syndromeId,
    required this.description,
    required this.evidence,
    required this.severity,
    this.uncertain = false,
  });
}

/// 单块分析结果
class ChunkAnalysisResult {
  final int chunkIndex;
  final List<ChunkNote> notes;
  final bool success;

  /// 失败原因码（success=true 时恒为 null，ADR-C80）：
  /// [kChunkFailureEmptyContent]（重试后 content 仍为空）/
  /// [kChunkFailureException]（调用抛异常）。
  final String? failureReason;

  const ChunkAnalysisResult({
    required this.chunkIndex,
    required this.notes,
    required this.success,
    this.failureReason,
  });
}

/// 单块失败原因码：重试后 content 仍为空——推理型模型把 max_tokens 预算
/// 全部耗在 reasoning 上（ADR-C80 §1.2 探针实证）。
const String kChunkFailureEmptyContent = 'empty_content';

/// 单块失败原因码：调用抛异常（网络 / 超时等）。
const String kChunkFailureException = 'exception';

/// runProgressiveDiagnosis 返回值
class ProgressiveResult {
  final String fullContent;
  final int chunkCount;
  final int failedChunks;

  /// W-15-A：各分块在原文中的覆盖区间（验收②）。空 = 旧调用方未传（兼容）。
  final List<ChunkCoverage> chunkCoverage;

  const ProgressiveResult({
    required this.fullContent,
    required this.chunkCount,
    required this.failedChunks,
    this.chunkCoverage = const [],
  });
}

/// ADR-C87 延伸：分块诊断被用户取消（「停止生成」按钮）。
///
/// 与「返回 null（未触发分块）」必须区分：取消返回 null 会让调用方
/// 误走单次链路（再发一次请求，比不取消更糟），故用专用异常。
class ProgressiveDiagnosisCancelled implements Exception {
  const ProgressiveDiagnosisCancelled();
}

/// W-15-B B1（验收①）：merge 预算预检三态之「拒发」——降级序列穷尽后
/// 估算仍超上限，**不发送**（超限不得静默继续发送）。
///
/// 走既有取消/复位路径：调用方显式 catch 并以 [userMessage] 提示用户；
/// 未捕获时沿异常链上抛（与 [ProgressiveDiagnosisCancelled] 同纪律）。
class ProgressiveMergeOverBudget implements Exception {
  /// 降级穷尽后的最终估算值（tokens）
  final int estimatedTokens;

  /// 预算上限（tokens，真源 [TokenEstimate.maxBudget]）
  final int maxBudget;

  const ProgressiveMergeOverBudget(this.estimatedTokens, this.maxBudget);

  /// UI 显式提示文案（设计稿 §3.1：「估算 N > 上限 M」，不发送）。
  String get userMessage => '本章过长，无法合并诊断（估算 $estimatedTokens > 上限 $maxBudget）';

  @override
  String toString() =>
      'ProgressiveMergeOverBudget(estimated=$estimatedTokens, '
      'maxBudget=$maxBudget)';
}

/// ADR-C87 延伸：检查取消令牌，已取消则抛 [ProgressiveDiagnosisCancelled]。
void _throwIfCancelled(CancelToken? token) {
  if (token != null && token.isCancelled) {
    throw const ProgressiveDiagnosisCancelled();
  }
}

// ── W-15-A：分块覆盖区间（验收②「分块路径记录每块覆盖范围」）──

/// 单块在**原文**中的字符区间 [start, end)。
///
/// overlap 区间 = 相邻两块区间的交集；`located=false` 表示定位失败
/// （防御位：分块文本按构造必是原文子串，理论不可达；失败时区间无意义，
/// 消费方不得用它渲染「覆盖原文」标注）。
class ChunkCoverage {
  final int index;
  final int start;
  final int end;
  final bool located;

  const ChunkCoverage({
    required this.index,
    required this.start,
    required this.end,
    this.located = true,
  });

  bool get isValid => located && end > start;
}

/// 计算各分块在原文中的字符区间。
///
/// 算法：顺序 `indexOf` 定位（分块按构造是原文的**有序**子串，块间
/// overlap 使下一块起点 ≥ 本块起点，故游标只前进不回退）。定位失败时
/// 记 `located=false`（不抛错——覆盖记录是旁路观测，不阻断诊断主链）。
List<ChunkCoverage> computeChunkCoverage(String content, List<String> chunks) {
  final out = <ChunkCoverage>[];
  var cursor = 0;
  for (var i = 0; i < chunks.length; i++) {
    final idx = content.indexOf(chunks[i], cursor);
    if (idx < 0) {
      out.add(
        ChunkCoverage(index: i, start: cursor, end: cursor, located: false),
      );
    } else {
      out.add(ChunkCoverage(index: i, start: idx, end: idx + chunks[i].length));
      cursor = idx; // 下一块从本块起点起搜（overlap 可回退到块内）
    }
  }
  return out;
}

// ── 分块：按段落 + overlap 回溯（对齐 RN splitContent）──

/// 按段落切分文本为若干块，块间保留 overlap 字符的上下文重叠。
///
/// 算法：
///   1. 按 '\n\n' 切段落
///   2. 从 startIndex 累加段落，总长度接近 SIZE 时切块
///   3. overlap 从本块末尾段落向前回溯，累计长度 ≥ OVERLAP 停
///   4. 末块 < MIN_LAST_CHUNK 时合并到前一块（合并时按 overlap 段索引
///      去重，见 [_mergeSmallLastChunk]——T-20261021-03 读数批实锤修复）
///
/// 原子性：单段超长（首段即 ≥ SIZE）时**整段成块**，不再按字符硬切——
/// 段落是分块算法的边界，段内不再切。修复批次 H 侦察的同步死循环缺陷
/// （ADR-C73 §2）。
List<String> splitContent(String content) {
  if (content.length <= kDiagnosisChunkSize) {
    return [content];
  }

  final paragraphs = content.split('\n\n');
  final (chunks, spans) = _chunkParagraphs(paragraphs);
  _mergeSmallLastChunk(chunks, spans, paragraphs.length);
  return chunks;
}

/// 按段落 + overlap 切块，返回 (块文本列表, 每块段索引区间 [start, end))。
///
/// 区间（end 独占）供 [_mergeSmallLastChunk] 的 overlap 去重使用——末块
/// 头部本就是 overlap 设计语义下前块尾部的逐字重复，字符串比对分不开
/// 「设计内 overlap」与「合并后块内重复」，只能靠索引。
///
/// 单段原子性：首段即超阈值时**整段成块并跳过 overlap**——段落是不可再分
/// 的原子单元（按 '\n\n' 分块，段内不再切）。修复批次 H 侦察的同步死循环
/// 缺陷（ADR-C73 §2）：若只推进 endIndex 而不推进 startIndex，overlap
/// 回溯后会让 startIndex 不变 ⇒ while 永真。
(List<String>, List<({int start, int end})>) _chunkParagraphs(
  List<String> paragraphs,
) {
  final chunks = <String>[];
  final spans = <({int start, int end})>[];
  var startIndex = 0;

  while (startIndex < paragraphs.length) {
    var endIndex = startIndex;
    var length = 0;
    var reachedThreshold = false;

    for (var i = startIndex; i < paragraphs.length; i++) {
      final pLen = paragraphs[i].length + 2; // +2 是 '\n\n' 分隔
      if (length + pLen >= kDiagnosisChunkSize) {
        reachedThreshold = true;
        break;
      }
      length += pLen;
      endIndex = i + 1;
    }

    if (!reachedThreshold) {
      chunks.add(paragraphs.sublist(startIndex).join('\n\n'));
      spans.add((start: startIndex, end: paragraphs.length));
      break;
    }

    if (endIndex == startIndex) {
      chunks.add(paragraphs[startIndex]);
      spans.add((start: startIndex, end: startIndex + 1));
      startIndex = startIndex + 1;
      continue;
    }

    final chunk = paragraphs.sublist(startIndex, endIndex).join('\n\n');
    chunks.add(chunk);
    spans.add((start: startIndex, end: endIndex));

    startIndex = _overlapStartIndex(paragraphs, endIndex, startIndex);
  }

  return (chunks, spans);
}

/// overlap 回溯：从 endIndex-1 向前累加，直到长度 ≥ OVERLAP。
///
/// ★ W-15-B 批修复的既有缺陷（e2e 测试实证 34GB 堆耗尽）：回溯失败时
/// （前文段落合计不足 OVERLAP，或单段成块 endIndex==startIndex+1）旧实现
/// 返回 startIndex ⇒ startIndex 不前进 ⇒ while 永真、同一 chunk 无限重复。
/// 触发条件极普通：**任一 1499–2997 字符的段落**（含 2 字分隔）即可命中
/// （pLen×2 ≥ SIZE ⇒ 恰一段成块；回溯窗口内无前文可退）。ADR-C73 当年
/// 只修了 `endIndex == startIndex` 的原子分支，本退化分支漏网。
/// 修复 = 回溯失败改从 endIndex 起（该边界不带 overlap），保证 startIndex
/// 严格前移；代价仅是该边界损失一次 overlap 连续性（块内容覆盖不变）。
int _overlapStartIndex(List<String> paragraphs, int endIndex, int startIndex) {
  var overlapLength = 0;
  var overlapStart = endIndex - 1;
  while (overlapStart > startIndex) {
    overlapLength += paragraphs[overlapStart].length + 2;
    if (overlapLength >= kDiagnosisChunkOverlap) {
      break;
    }
    overlapStart--;
  }
  if (overlapStart > startIndex) return overlapStart;
  return endIndex > startIndex ? endIndex : startIndex + 1;
}

/// 末块过小时合并到前一块（避免单句成块）。
///
/// ★ T-20261021-03 读数批实锤缺陷修复（2026-10-23，报告《分块链读数》§四）：
/// 旧实现原样拼接 `chunks[n-2] + '\n\n' + last`。而末块的头部段落正是
/// overlap 回溯（splitContent 第 3 步）从「前块末尾」带回来的——与倒数第二
/// 块尾部逐字相同。合并后这些段落在**同一块内**二次出现：L03c2 实测
/// 1/18 块命中（段[27]=段[29]、段[28]=段[30] 一字不差），该批唯一 hit
/// （P018 段落重复）即其假症候、已作废。污染诊断质量（重复判症 / token
/// 浪费）与未来任何读数。
///
/// 修复 = 按块间 overlap 的段索引**精确去重**：末块中落在
/// `[lastStart, min(prevEnd, paragraphCount))` 的段落是前块已收内容，
/// 跳过再拼。overlap 语义保留在**块间**，不在块内二次出现。
/// （overlap 兜底分支令 lastStart == prevEnd 时 dupCount ≤ 0，走原样拼接。）
void _mergeSmallLastChunk(
  List<String> chunks,
  List<({int start, int end})> spans,
  int paragraphCount,
) {
  if (chunks.length < 2) return;
  final last = chunks.last;
  if (last.length >= kDiagnosisMinLastChunk) return;

  final lastStart = spans.last.start;
  final prevEnd = spans[spans.length - 2].end;
  final dupCount =
      (prevEnd < paragraphCount ? prevEnd : paragraphCount) - lastStart;
  if (dupCount <= 0) {
    chunks[chunks.length - 2] = '${chunks[chunks.length - 2]}\n\n$last';
  } else {
    final kept = last.split('\n\n').skip(dupCount).join('\n\n');
    chunks[chunks.length - 2] = kept.isEmpty
        ? chunks[chunks.length - 2]
        : '${chunks[chunks.length - 2]}\n\n$kept';
  }
  chunks.removeLast();
}

// ── 单块系统提示词（对齐 RN CHUNK_SYSTEM_PROMPT）──
//
// ADR-C69：症候清单原为硬编码 P001-P017（19 条），而注册表已有 39 条
// （P001-P029），导致分块路径漏掉后段 20 个症候——且 anchor 测试覆盖不到本
// 文件（不在 skill_registry 内），缺陷潜伏至今。现改由注册表派生，扩容自动
// 跟随；一致性由 progressive_chunk_syndrome_coverage_test.dart 兜底。

/// ★ T-20261021-03 读数批（ADR-C155）：分块下系统性退化为 uncertain 的判据集。
///
/// 读数依据（`.ai/reports/2026-10-23-分块链读数.md` §三）：干净名家语料
/// 18 块 × 39 判据 = 701 条判定中，这 6 条 uncertain 率 33%–100%
/// （P022 18/18 全退化 · P020 16/18 · P019 10/18 · P012 8/18 ·
/// P011 7/18 · P033 6/18），其余 33 条 18/18 判定稳定（全 miss）。
/// 形态一致：全部是**跨章/跨片依赖判据**（全文节奏比例 / 跨章长线 /
/// 章末收束 / 章首开篇 / 冲突场次前史）——窗口边界纪律下无法在片内自证。
///
/// 处置（ADR-C155 裁定 = 乙形态 + 丙为先）：
/// - 从分块 prompt 的「判定要点清单」**排除**这 6 条（不注入判定要点）；
/// - 但在「跨章依赖判据」节**显式留痕**（点名 + uncertain 指引）——
///   排除而非静默不选（B4），且是 ADR-C153 窗口边界规则的具体化
///   （规则早已存在，本清单把实测退化者点名，零结构改动）。
///
/// ⚠️ 注册表新增症候时：若其成立依赖片段外信息（跨章比例 / 前史 /
/// 后文解释 / 角色长期状态），须同步加入本常量——否则会自动进入要点
/// 清单（默认假设「片内可判定」），重蹈「注入只会制造噪声」。
const Set<String> kChunkDegradedCriteriaIds = {
  'P011',
  'P012',
  'P019',
  'P020',
  'P022',
  'P033',
};

/// 症候 ID 的连续范围说明，形如 `P001-P029`。
///
/// ADR-C69：merge prompt 原硬编码「P001-P020」，与注册表（P001-P029）不符，
/// 会压制后段症候的输出。改由同一真源派生，杜绝两套范围。
String _syndromeIdRange([Set<String> disabled = const {}]) {
  final ids =
      kSyndromeRegistry
          .where((s) => !disabled.contains(s.id))
          .map((s) => s.id)
          .toList()
        ..sort();
  if (ids.isEmpty) return '（无可用症候）';
  return '${ids.first}-${ids.last}';
}

/// 例外情况指引（RN 移植，逐字保留）。
///
/// 末条为 ADR-C69 新增的兜底：这些例外只覆盖 P001-P017，注册表扩到 P029 后
/// 后段症候没有对应例外，补一句通用兜底避免"零例外"导致的过度诊断。
const String _kChunkExceptionGuide = '''例外情况指引（以下场景通常不应判定为症候）：
- P001例外：隐喻表达（"冰冷的眼神""心头一热"）、有具体动作支撑的情绪词、紧凑叙事中的快速过渡；非人类/非常规思维的角色设定
- P002例外：角色的内心自省（角色在评价自己，非作者补设定）、角色对地点/势力的随口判断
- P003例外：角色对自己所处环境的评价、角色对自身经历的回忆、有明确标记的视角切换；显式叙述者全知插叙提示语（"他不知道的是""原来""其实""而此时""与此同时""而另一边"）——读者能确定是叙述者在交代信息，不构成视角漂移
- P004例外：情绪沉淀段落、氛围描写的节奏变化、关键揭示前的屏息时刻
- P005例外：极简风格的刻意选择（海明威式短句叙事是风格而非缺陷）、信息密集段落中以传递信息为目标的句式趋同、限制视角下反映角色思维重复的心理描写
- P006例外：情感爆发点的浓墨重彩、作者刻意特定风格
- P007例外：悬疑叙事中动机故意模糊、功能性配角
- P009例外：剧本/对白主导文体、法庭剧/审讯场景
- P010例外：日常向/温馨向作品、悬疑铺垫章节
- P011例外：文学性作品的缓慢开场、内心独白本身即冲突载体的第一人称开篇、诗化/氛围型开篇（氛围本身就是钩子）
- P012例外：开放式结局的刻意留白、系列连载的"未完待续"设计
- P013例外：情绪高潮替代动作高潮的文学型叙事
- P014例外：喜剧/荒诞向作品中刻意设计的巧合（前提是风格一致）
- P015例外：角色因重大事件（如创伤、顿悟）导致的刻意转变，且有明确铺垫
- P016例外：蒙太奇/意识流/碎片化叙事手法
- P018例外：刻意排比/刻意节奏下的高频连接词重复、符合口语习惯的高频词、故事层同动作多次发生的事件重复（不判为语言层啰嗦）
- P032例外：学术/法律等本就框式表达的文体（类型约定）、角色人设故意用书面/翻译腔说话（角色声线功能）、有意借用外来语制造异域感（作者主动选择且有中文缓冲）
- P034判界（关键，防误路由）：同一句/相邻小句出现两个以上"他/她/它"而就近可及人物≥2、读者判不出每个指谁（典型如"他骂了他一顿"，两个他分属不同人物），或连续省略主语致就近候选≥2 → **必须报 P034（代词指代不清/零回指过载症）**，即使句中有重复字面。区别于 P018（P018 是同一字无差别紧邻重复/打字连写"他他"、连接词反复，读者不因"指谁"困惑）与 P023（P023 是世界观设定前后矛盾，不是"他指谁"解歧）
- P034例外：有明确话题锚/单一主语链的连续零回指合法——同一小话题下单主角行动链（连续零主语省略、就近候选恒为 1，如"他推开门，走进来，坐下端起碗"）、对话轮内紧邻动作省略说话人、上句刚出现唯一专名且就近候选仅 1 个，不构成指称过载
- P008例外：功能性配角（邮差/保安/路人）扁平本身即合理设计、喜剧中的类型化夸张是类型需要；寓言/讽刺类作品刻意符号化的角色是叙事策略——只有主角式平面化才报
- P017例外：蒙太奇/时间压缩（刻意快速推进且后有场景落地）、快节奏动作序列的快速切场、非关键时间段的过渡性概括（"一路无话，三日后抵达"）、"这是一个关于……的故事"式框架开头。裁决问句：改好这段需**加**内容 ⇒ P017，需**减** ⇒ P002，都不需要 ⇒ 都不报
- P021例外：快速过渡/时间跳跃段（是 P017 而非 P021）；角色内心独白与议论性段落本就无需具象化；语言精炼但信息完整（描写密度不足而叙事完整）属范畴错配
- P023例外：视角限制下的信息差——角色不知道 ≠ 设定矛盾（转 P003）；角色成长带来的合理能力变化（有铺垫）；留白设定——从未明确过的规则不构成前后不一致
- P024例外：金手指有代价/限制且冲突仍在；高阶题材里金手指是后续世界层次揭示前的常规能力铺垫（规则未闭合不先判）；信息差下的能力隐藏（转 P003）
- P025例外：配角日常行为与主线无关但展现性格；一次性功能性角色（跑腿/报信）本就短暂出场；群像场景中配角群有集体辨识度，不要求每个单点立体
- P026例外：独白在推进决策（纠结后给出选择/行动，有收敛）；内心戏本身即看点（心理悬疑/权谋博弈中内心推算就是剧情本体）；少量点睛独白服务人物厚度
- P027例外：支线埋主线伏笔（看似无关实为铺路）；支线丰富核心角色人设；单元剧结构中支线即爽点单元
- P028例外：被推 + 有回应（选择/代价评估/内心挣扎）= 被动中主动，不报；侦探/悬疑题材以观察者身份展开；主角故意隐忍蛰伏（等待时机是主动选择）；群像剧刻意弱化单一主角
- P029例外：先归位——这局没有布局者（反派本人）时本症候**根本不在报域**（症结归 P010/P007）；布局者行为有读者读得到的账（自身目标＋前史因果＋不可让渡的代价＋行为与执念一致）即不报；局中人/被算计者的蠢、连败、不申辩一律不得作为判定依据
- P030例外：多视角叙述刻意切换叙述者声线；角色内心独白故意用角色腔（与叙述声线分开看待）；风格实验/跨题材尝试中声线是变量而非失误
- P031例外：有意做类型融合且内核统一（有明确审美纲领）；文学性实验作品（类型边界本就是讨论对象）；系列化多品类——判定对象为单本而非跨本
- P033例外：刻意的循环/复沓结构（主题需轮回感且有自觉变奏设计）；日常流/治愈系本就低冲突，不靠升级驱动；看似重复实则每轮换维度（上轮外部危机、下轮内部信任崩塌＝升级）
- P038例外：刻意的悬念延迟（先抛结果再揭原因，有明确设计意图）；意识流/蒙太奇（顺序随意识跳，非物理时空顺序）；空间全景式白描（刻意从整体到局部是合法顺序）
- P039例外：留白/停顿/氛围描写不是稀碎——留白是"作者有意不写、让读者填补"且删掉会破坏叙事，稀碎是"写了等于没写"、删掉叙事不受影响；无信息增量链（不揭示新事实、不改变角色状态、不制造张力）才是稀碎
- 上面未列出的症候：例外情况以症候诊断手册为准；判定尺度与上述一致——只在读者体验确实会受损时才算症候''';

/// 单块输出格式（纯静态，与症候清单分离）。
const String _kChunkOutputFormat = '''请输出JSON格式的笔记，不要包含markdown代码块标记，只输出纯JSON对象：
{
  "notes": [
    {
      "syndromeId": "P001",
      "description": "简要描述观察到的问题，在原文中的位置",
      "evidence": ["具体例句1", "具体例句2"],
      "severity": "L1",
      "uncertain": false
    }
  ]
}

uncertain 字段说明：按上面「片段窗口边界」一节，该条判据的成立与否依赖片段外信息时置 true，并在 description 里简述缺哪类信息（缺前文铺垫 / 缺后文解释 / 缺片段外人物关系 / 缺全文节奏比例 / 缺角色长期状态）。缺省 false。''';

/// FIX-1（2026-09-23）：分块合并输出约束——自然语言正文 + 顶层字段格式。
/// 根因：旧 prompt 结尾只要求协议标记，模型可省略自然语言正文且 suggested_actions
/// 无格式约束 → 整块被拒（suggested_actions_invalid）→ 空输出兜底「诊断完成」。
const String _kMergeOutputRequirement = '''输出结构说明（下面两部分缺任一，合并解析会失败）：
1. 先输出面向学员的自然语言诊断正文——直接可读的诊断总结与教学建议（核心结论、最值得先改的一点、鼓励性收尾），不得省略；
2. 再输出 [YS_DIAGNOSIS] 和 [/YS_DIAGNOSIS] 包裹的标准诊断 JSON 块。

[YS_DIAGNOSIS] 块顶层字段要求：
- syndromes (object[]): 症候列表（格式见上），必填
- suggested_actions (string[]): 建议动作编号数组（如 ["A009","A005"]），必填且必须为字符串数组
- confidence (number): 0-1 置信度——★ §1-20：模型自报 confidence 已废除（禁止重新引入）；
  本字段为协议兼容保留（活性审查 D1 / §4-215 裁7②），可省略；解析侧缺省 0.0
- root_cause_analysis / next_focus / feedback_summary: 可选
- overall (object): 整体判定（结构完整度诊断，非文学打分、不给分数），仅当已诊断章节覆盖度足够时输出：
  - verdict (string): 三档之一「结构完整」「基本完整」「存在结构性缺口」
  - reasons (string[]): 1-3 条核心理由，须引用上面的结构画像或已报症候证据
  - keep (string): 最值得保持的一点（1 条）
  - priority (string[]): 建议先改的顺序（1-3 条）
  - coverage (string): 复述覆盖度声明（如「基于已诊断 3/20 章」），必填；缺此项 overall 无效

请输出标准诊断格式，包含 [YS_DIAGNOSIS] 和 [/YS_DIAGNOSIS] 标记。''';

/// ★ 窗口边界声明（2026-10-21，ADR-C153）：分片阶段的**前提**，不是例外清单。
///
/// 为什么不写成例外清单（逐条点名 P0xx「以下不判……」）：那 6 条高风险豁免
/// （P019/P020/P022/P035/P036/P037）的成立条件**都不需要指认任何位置**——
/// 类型自证、意图自证、跨片依赖。任何文本都能套用，列进清单等于给每个分片
/// 发一张免责模板，最坏情况是剧情组真阳性掉一大截，掉的还是「章末无钩子、
/// 长线无牵引」那批最该报的。
///
/// 为什么这么写能覆盖同 6 条 + P012/P037 跨章清单：
/// 「跨片依赖类不可判」是**一条规则**，6 条例外是它的 6 个具体表现。按规则写 =
/// 一次消解；按例外写 = 6 次重复且各有遗漏。规则还顺带覆盖将来新增的同类判据。
///
/// 与 merge 阶段的分工：分片阶段只做**块内可自证**的判定；跨片归并、交叉引用、
/// 因果一律留给 merge（那里能看到全部分片 + 原文覆盖区间）。merge 侧对应机制
/// 是既有的 `pending_context`（W-15-B，已有完整消费链），本块不重复发明，
/// 只补 merge 侧没有的**前半段**：分片阶段不能因为看不到前文就把
/// 「这里像是有问题」写成肯定结论。
const String _kChunkWindowBoundary = '''## 片段窗口边界（判读前提，先读这一节）
你读到的是全章的一个片段，**看不到片段之外的内容**。因此：
- 只依据本片段内可指认的证据判定。看不到前文铺垫、后文解释、片段外人物关系时，
  **既不得据此否定，也不得据此肯定**。
- 若某条判据的成立与否依赖片段外信息（前文伏笔、后文解释、跨片段的人物关系、
  全文节奏比例、角色的长期状态），本片段阶段**无法判定**：不要勉强给结论，
  在该条 note 上标 `"uncertain": true` 并简述缺哪类信息，交由合并阶段裁决。
- 「本片段看不出问题」不等于「本章没问题」，也不等于「本章有问题」。
- 只有一条分片时（片段 1/1），本章即全文，跨片段前提不成立，按常规判定。
''';

/// 「块内可自证」的对照说明 —— 不新增判据，只举例说明上面的规则怎么用。
const String _kChunkSelfContainedProbe =
    '''- 可在片段内指认位置的（局部措辞、局部节奏、局部视角跳变、局部设定堆积）：照常判。
- 可由片段自身自证的（类型通用件的辨识性、类型固有节奏、体裁约定）：照常判。''';

/// 「跨章依赖判据」节：点名 [kChunkDegradedCriteriaIds] + uncertain 指引。
///
/// ADR-C155（T-20261021-03 读数批）：这 6 条在分块形态下 uncertain 率
/// 33%–100%（P022 18/18 全退化），成立与否依赖片段外信息 ⇒ 片内原理上
/// 判不了。**不是豁免**（ADR-C153 已否决例外清单路线），是把窗口边界
/// 规则应用到实测退化者：遇到疑似形态直接标 uncertain 交合并阶段，
/// 勿在片内推测。用户禁用某条时同步剔除（R-009 用户主权）。
String _chunkDegradedCriteriaBlock([Set<String> disabled = const {}]) {
  final rows =
      kSyndromeRegistry
          .where((s) => kChunkDegradedCriteriaIds.contains(s.id))
          .where((s) => !disabled.contains(s.id))
          .map((s) => '- ${s.id} ${s.name}')
          .toList()
        ..sort();
  if (rows.isEmpty) return '';
  return '''跨章依赖判据（片段内不可判定，直接标 uncertain）：
以下症候的成立与否依赖片段之外的信息（全文节奏比例、跨章长线、章末收束、章首开篇、冲突场次前史），在本片段阶段无法自证：
${rows.join('\n')}
遇到以上形态的可疑迹象时，不要勉强给结论：在该条 note 上标 "uncertain": true 并简述缺哪类信息，交由合并阶段裁决。''';
}

/// 分块 prompt 的「判定要点」行：`- <ID> <病名>（<关键词>）：<一句话判定要点>`。
///
/// ADR-C155 裁定 = **乙形态**（原则 + 判据条目，不注入负例 few-shot）：
/// 读数批的判读依据是 39 条判据**原文**（61514 字符）；原文 verbatim
/// （丙形态）按 33 条折算 ≈52000 字符/片，token 成本随片数爆炸 ⇒ 否。
/// 乙形态从注册表现成字段（keyword + oneLine）派生，零新内容维护面。
/// 排除 [kChunkDegradedCriteriaIds]（那些走「跨章依赖判据」节）。
List<String> _activeSyndromeCriteriaLines([Set<String> disabled = const {}]) {
  final rows =
      kSyndromeRegistry
          .where((s) => !disabled.contains(s.id))
          .where((s) => !kChunkDegradedCriteriaIds.contains(s.id))
          .map((s) => '- ${s.id} ${s.name}（${s.keyword}）：${s.oneLine}')
          .toList()
        ..sort();
  return rows;
}

/// 构造单块系统提示词：症候清单由注册表派生（ADR-C69）。
///
/// 每行 4 个，沿用 RN 逐字移植时的紧凑排布，避免 39 条摊成 39 行。
/// [disabled] 为用户永久关闭的症候 ID 集合（空 = 全启用）。
/// 分块链路教学方式指令（与 teaching-mode skill 组语义一致，但分块旁路不走
/// skill_dispatcher，故在此内联注入）。socratic=引导发现；direct=直给结论。
String _kTeachingModeChunkInstruction(TeachingMode mode) => switch (mode) {
  TeachingMode.socratic =>
    '\n\n## 教学风格（疑问式）\n- 指出问题时优先用提问引导学员自己发现，不要一次性倾倒全部结论；'
        '长文更应聚焦最核心的 1-2 个问题让学员先动手。',
  TeachingMode.direct => '\n\n## 教学风格（直接说）\n- 直接给出诊断结论与可操作改法，不绕弯、不铺垫。',
  _ => '',
};

String _buildChunkSystemPrompt([
  Set<String> disabled = const {},
  TeachingMode teachingMode = TeachingMode.socratic,
]) {
  final criteriaLines = _activeSyndromeCriteriaLines(disabled);
  final degradedBlock = _chunkDegradedCriteriaBlock(disabled);
  return '''你是一个专业的写作诊断助手。请阅读以下文本片段，识别其中存在的写作问题。

症候判定要点（逐条核对，不要强行匹配）：
${criteriaLines.join('\n')}

${degradedBlock == '' ? '' : '$degradedBlock\n\n'}$_kChunkWindowBoundary
$_kChunkSelfContainedProbe

$_kChunkExceptionGuide

$_kChunkOutputFormat$_kTeachingModeChunkInstruction(teachingMode)''';
}

/// 单块系统提示词（全启用默认值）：症候清单由注册表派生，调用处无需感知（ADR-C69）。
/// 运行时按用户启用集构造请用 [_buildChunkSystemPrompt]。
final String kChunkSystemPrompt = _buildChunkSystemPrompt();

// ── JSON 提取（对齐 RN extractJson：优先 code block，否则按括号平衡）──

/// 从 LLM 返回的文本中提取第一个顶层 JSON 对象字符串。
/// 返回 '{}' 表示未找到。
String extractJson(String text) {
  // 优先匹配 markdown 代码块内的 JSON
  final codeBlock = RegExp(
    r'```(?:json)?\s*\n?(\{[\s\S]*?\})\s*\n?```',
  ).firstMatch(text);
  if (codeBlock != null && codeBlock.groupCount >= 1) {
    return codeBlock.group(1)!;
  }
  // 按括号平衡匹配第一个顶层 {}
  var depth = 0;
  var start = -1;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '{') {
      if (depth == 0) start = i;
      depth++;
    } else if (text[i] == '}') {
      depth--;
      if (depth == 0 && start != -1) {
        return text.substring(start, i + 1);
      }
    }
  }
  return '{}';
}

// ── Merge prompt：注入 SKILL + 合并规则（对齐 RN buildMergePrompt）──

/// 叙事合理性判定门——merge prompt 的**唯一**质量过滤器。
///
/// P0'-1（2026-09-30，走 **ADR-C67/C68 兼容**的路线 B）：**不动数量规则**
/// （ADR-C67 裁决「症候库侧识别到多少报多少 = 诊断须全量落库」，且
/// syndrome_count_scope_test / diagnosis_output_semantics_test 有反向断言守着），
/// 改为**收紧这道门**：把「不改会更差吗」这种主观自问，升级为
/// 「① 须是读者级实际损害（读不懂/读不下去/被误导）② 须指得出原文具体位置」
/// 的双必要条件，并列出**不算**清单 + 拿不准时默认不输出。
/// 实测依据：旧门过松，同章出 25/16/25/19 条（2026-09-30 取证）。
///
/// 生效性：本常量只被 [buildMergePrompt] 插值 ⇒ 必落在**会被注入**的 merge prompt 内。
/// 对照：`syndrome_kb_content.dart` 里另有一份同名副本，落在手册尾部
/// `## 诊断执行指引`（**按症候 ID 切片注入 ⇒ 该段从不注入**），属防御性同步。
const String _kMergeRelevanceGate = '''叙事合理性判定（最终裁决步骤，从严）：
在输出每条症候之前，必须**证明**它会造成读者级的实际损害，而不是"可以更好"。
逐条回答以下两个问题，**都**为"是"才允许输出这条症候：
1. 不改这段，读者会**读不懂 / 读不下去 / 被误导**吗？（"能更精彩 / 更顺"不算）
2. 你能指着**原文的具体位置**说清读者在哪里、因何受损吗？（指不出具体位置即不算）

以下情形**一律不算**"显著受损"，不得据此输出症候：
- 只是风格或口味差异——作者这样写也成立，只是不合你的偏好；
- 读者仍能顺畅理解文意，只是"还能更好"；
- 需要读者停下来分析才能察觉的局部瑕疵；
- 与本章写作意图 / 主旨无关的细枝末节。

拿不准是否真的损害了读者体验时，一律判为"否"，不输出该条。''';

/// 把分片分析结果组装成 merge prompt 里的「## 分片 N」笔记块列表。
///
/// 抽出为独立函数（职责级）：组装笔记是**纯数据变换**，与 merge prompt
/// 的文本拼装无关；原 buildMergePrompt 64 行里本块21 行，
/// R-019（函数 ≤ 50 行）计的是函数体。
/// 跳过 [ChunkAnalysisResult.success] 为 false 或 notes 为空的分片。
///
/// W-15-A（验收②）：[chunkCoverage] 非空时，块头追加「覆盖原文 [s, e)」
/// ——这是**机械元数据**（代码算出的字符区间），非 skill 话术，不触 R-027。
List<String> _buildChunkNotesBlocks(
  List<ChunkAnalysisResult> chunkResults, {
  List<ChunkCoverage> chunkCoverage = const [],
}) {
  String header(int i) {
    if (i >= chunkCoverage.length) return '## 分片 ${i + 1}';
    final c = chunkCoverage[i];
    if (!c.isValid) return '## 分片 ${i + 1}';
    return '## 分片 ${i + 1}（覆盖原文 [${c.start}, ${c.end})）';
  }

  final allNotesJson = <String>[];

  for (var i = 0; i < chunkResults.length; i++) {
    final r = chunkResults[i];
    if (r.success && r.notes.isNotEmpty) {
      final notes = r.notes
          .map(
            (n) => {
              'syndromeId': n.syndromeId,
              'description': n.description,
              'evidence': n.evidence,
              'severity': n.severity,
              // ★ 必须带进 merge（ADR-C153 §3）：不带则 merge 读到的仍是一堆
              // 肯定结论，分片侧的「我判不了」就在这一步丢失 ⇒ 又一个声明≠生效。
              'uncertain': n.uncertain,
            },
          )
          .toList();
      // 用自研 _encodeJson 序列化分片笔记（对齐 JSON.stringify 语义；
      // 不用 toString()——其对中文/引号/换行会产生非 JSON 输出）。
      final encoded = '{"notes": ${_encodeJson(notes)}}';
      allNotesJson.add('${header(i)}\n```json\n$encoded\n```');
    }
  }
  return allNotesJson;
}

/// merge prompt 的静态指引块：合并注意事项 + 叙事合理性判定门 + 数量原则
/// + 跨片因果提示（W-15-B）+ 干预价值（S3）三判据（W-19-B，2026-10-16 舰长批 R-027）。
///
/// 抽出为顶层常量（纯数据）：本块不依赖 buildMergePrompt 的任何参数，
/// 只有 [_kMergeRelevanceGate] 一个 const 插值，故合并规则与判定门在
/// merge 链路上仍只此一份（与 syndrome_kb_content.dart 尾部那份副本无关，
/// 那份落在按ID 切片注入的手册尾部，从不注入）。
final String _kMergeGuidanceBlock =
    '''
注意事项：
- 同一个症候在不同分片中出现的信号 → 合并为一条诊断，严重度取最高
- 某个症候只在单一分片出现但证据充分 → 保留
- 跨分片一致的信号（如 P003 在开头和结尾都出现）→ 说明这是个系统性问题，提升严重度
- 互相矛盾的信号 → 做权衡判断，只输出合理的结论

$_kMergeRelevanceGate

数量原则（按判据收敛报出）：只有当某症候的成立条件能够逐条满足、且你能为它引用可指认的原文证据时，才报出该症候；判据未满足或证据不足时不报（宁缺勿滥，不凑数）。报出的条目按严重度与证据把握排序；若合格条目超过 5 条，保留排序最前的 5 条，其余在 feedback_summary 中一句话概括。

跨片因果提示：若某条线索的成立与否依赖未包含在任何分片中的信息（如前文伏笔、后文解释、分片外的人物关系），该条须标记 pending_context=true，并把结论写为「暂时无法判断」——不得强行下结论。pending_context 缺省 false。

分片不确定标记的处置：上面每条笔记的 uncertain=true 表示**该分片阶段因看不到片段外信息而无法判定**。处置规则：
- 你现在能看到**全部分片**，对该条重判：能靠跨片信息确认成立 → 输出该条并把 pending_context 置 false；确认不成立 → 丢弃；
- 重判后**仍**需要片段外信息（本批分片之外的前文/后文）→ 输出该条并置 pending_context=true，结论写「暂时无法判断」，**不得**按 L1/L2/L3 给确定严重度；
- 不得把 uncertain=true 的笔记原样当作已确认结论输出。

## 干预价值（S3）三判据

$kInterventionValueS3Criteria

## 形态字段（仅量形式症候评定）

$kFormFieldCriteria
''';

/// 构造跨分片合并的系统 prompt。
///
/// [diagnosisContext] 来自前次活跃症候累积（对齐 RN buildDiagnosisContext）。
/// [structureProfile] ADR-0006：故事结构画像文本块（空 = 不注入；由调用方
/// 经 [buildStoryStructureProfileText] 构建——覆盖度不足/事件表空时返回
/// 空串，此处照常工作，零耦合）。
/// [disabledSyndromeIds] 为用户永久关闭的症候 ID 集合（空 = 全启用）。
///
/// W-15-A：[chunkCoverage] 非空时分片块头带覆盖区间（验收②）。
String buildMergePrompt(
  List<ChunkAnalysisResult> chunkResults, {
  String diagnosisContext = '',
  String structureProfile = '',
  Set<String> disabledSyndromeIds = const {},
  TeachingMode teachingMode = TeachingMode.socratic,
  List<ChunkCoverage> chunkCoverage = const [],
}) {
  final allNotesJson = _buildChunkNotesBlocks(
    chunkResults,
    chunkCoverage: chunkCoverage,
  );

  final contextSection = diagnosisContext.isNotEmpty
      ? '$diagnosisContext\n---\n\n'
      : '';

  // ADR-0006：结构画像置于笔记之前（先给全局形状，再看逐块问题）；
  // 首行覆盖度声明由 buildStoryStructureProfile 保证（H-1）。
  final profileSection = structureProfile.isNotEmpty
      ? '$structureProfile\n\n---\n\n'
      : '';

  return '''$contextSection$profileSection# SKILL: 症候诊断手册
（引用内置 syndrome-diagnosis 技能，请严格按照症候定义与例外规则进行裁决。）

---

以下是同一章节多个分片的诊断笔记。请综合所有笔记，做跨片段的统合分析，输出最终的结构化诊断结果：

${allNotesJson.join('\n\n')}

$_kMergeGuidanceBlock
syndrome 对象格式要求：
- syndrome_id (string): 症候编号 ${_syndromeIdRange(disabledSyndromeIds)}（由注册表派生，ADR-C69）
- name (string): 症候名称
- severity (L1|L2|L3): 严重度
- evidence (string[]): 原文证据片段，每条症候至少 1 条证据
- explanation (string): 诊断解释
- reader_impact (string): 一句话说明"不改这段，读者会有什么体验影响"。须结合本条证据**具体**说明该段文本对读者的影响，**不得照抄示例措辞**。示例（仅示意句式）："这一段把结论直接摆出来，读者没有被说服的过程，情感落点会显得突兀"
- intervention_value (high|medium|low): 按上述「干预价值（S3）三判据」评定的档位，缺省 low
- form_fact_count (int): 可选；仅量形式症候——成段设定/背景事实条数（单句带过=1）
- form_structure (string): 可选；仅量形式症候——expository=论文式/说明书结构 / interruption=读者关切时刻被打断 / narrative=叙事流内
- pending_context (bool): 缺省 false；见「跨片因果提示」

$_kMergeOutputRequirement$_kTeachingModeChunkInstruction(teachingMode)''';
}

/// 简易 JSON 编码器（仅用于合并 prompt 中展示 notes，不做校验）。
String _encodeJson(Object? obj) {
  if (obj is String) return '"${_escapeJsonString(obj)}"';
  if (obj is num || obj is bool) return obj.toString();
  if (obj == null) return 'null';
  if (obj is List) {
    final items = obj.map((e) => _encodeJson(e)).join(', ');
    return '[$items]';
  }
  if (obj is Map) {
    final entries = obj.entries
        .map(
          (e) =>
              '"${_escapeJsonString(e.key.toString())}": ${_encodeJson(e.value)}',
        )
        .join(', ');
    return '{$entries}';
  }
  return '"${_escapeJsonString(obj.toString())}"';
}

String _escapeJsonString(String s) {
  return s
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
}

// ── W-15-B B1：merge 预算预检与三态（验收①「超限不得静默继续发送」）──
//
// 设计稿 docs/designs/2026-10-15-W15-超上下文策略与合并收敛-设计稿v2.md §3.1：
// 原则 = 先预检、能降则降、降不动则拒发——三态显式，绝不静默。
// 上限口径 = [TokenEstimate.maxBudget]（与 chat 单次链路闸门同源，禁手抄第二份）；
// 降级级序（逐级尝试、每级重估）：
//   a. 裁 structureProfile（画像可再生成，非事实数据）
//   b. 裁 diagnosisContext 中非活跃症候部分（只留 active 集合；active 集合
//      未传入时该级跳过——无判据不动刀，宁可落到 c/拒发也不私造语义）
//   c. 分片笔记按块压缩：每块只保留 severity 最高前 3 条（块内代码选，非 LLM）
// 每级落 [BudgetGuardReport] 同构记录（totalBefore/After、droppedStages），
// 供 B3 快照（§3.5 budget_report）复用。

/// 降级级名（进 BudgetGuardReport.droppedStages 与快照 budget_report）。
const String kMergeBudgetStageProfile = 'merge_structure_profile';
const String kMergeBudgetStageContext = 'merge_inactive_context';
const String kMergeBudgetStageNotes = 'merge_chunk_notes_top3';

/// B1 级序 c：每块只保留 severity 最高前 3 条（稳定排序：同severity保原序）。
/// 纯函数：不改输入。无块超 3 条时返回原列表实例（调用方据此跳过该级）。
List<ChunkAnalysisResult> compressChunkNotesBySeverity(
  List<ChunkAnalysisResult> results,
) {
  const keep = 3;
  final changed = results.any((r) => r.notes.length > keep);
  if (!changed) return results;
  int rank(String s) => switch (s) {
    'L3' => 3,
    'L2' => 2,
    'L1' => 1,
    _ => 0,
  };
  return [
    for (final r in results)
      r.notes.length <= keep
          ? r
          : ChunkAnalysisResult(
              chunkIndex: r.chunkIndex,
              success: r.success,
              failureReason: r.failureReason,
              notes:
                  ([...r.notes]..sort(
                        (a, b) => rank(b.severity).compareTo(rank(a.severity)),
                      ))
                      .take(keep)
                      .toList(),
            ),
  ];
}

/// B1 级序 b：把 diagnosisContext（formatSyndromeHistory 产出的 Markdown 段）
//  过滤到活跃症候集合——保留非列表行（标题/引言/收尾），列表行只留
//  首个 token（症候 ID）∈ [activeSyndromeIds] 者。纯文本过滤，不解析语义。
String filterDiagnosisContextToActive(
  String context,
  Set<String> activeSyndromeIds,
) {
  if (context.isEmpty || activeSyndromeIds.isEmpty) return context;
  final lines = context.split('\n');
  final kept = lines.where((line) {
    final t = line.trimLeft();
    if (!t.startsWith('- ')) return true; // 标题/引言/收尾行全保留
    final id = t.substring(2).trim().split(RegExp(r'\s')).first;
    return activeSyndromeIds.contains(id);
  }).toList();
  return kept.join('\n');
}

/// B1 预检结果：最终输入集 + 最终 mergePrompt + 逐级降级报告。
class MergeBudgetPlan {
  /// 降级后的 structureProfile（可能已被置空）
  final String structureProfile;

  /// 降级后的 diagnosisContext（可能已被过滤）
  final String diagnosisContext;

  /// 降级后的分片结果（笔记可能已被压缩）
  final List<ChunkAnalysisResult> chunkResults;

  /// 按最终输入重建的 merge prompt（= 实际发送体，B3 快照与逐字节对账的基准）
  final String mergePrompt;

  /// 最终估算值（tokens，口径 = [TokenBudgetGuard.estimate]）
  final int estimatedTokens;

  /// 逐级降级报告（仅实际发生的级；照发时为空）
  final List<BudgetGuardReport> reports;

  const MergeBudgetPlan({
    required this.structureProfile,
    required this.diagnosisContext,
    required this.chunkResults,
    required this.mergePrompt,
    required this.estimatedTokens,
    required this.reports,
  });
}

/// B1：merge 预算预检三态（照发 / 降级 / 拒发）。
///
/// 纯函数（不发请求）。超 [limit]（缺省 = [TokenEstimate.maxBudget]，与
/// chat 单次链路同源）时按级序 a→b→c 逐级降级、每级重估；穷尽后仍超限
/// 抛 [ProgressiveMergeOverBudget]（**不发送**）。[limit] 参数仅为测试注入
/// 小阈值，生产路径一律走缺省常量，不引第二套口径。
MergeBudgetPlan planMergeBudget({
  required List<ChunkAnalysisResult> chunkResults,
  required List<ChunkCoverage> chunkCoverage,
  required String diagnosisContext,
  required String structureProfile,
  required Set<String> disabledSyndromeIds,
  required TeachingMode teachingMode,
  Set<String> activeSyndromeIds = const {},
  int limit = TokenEstimate.maxBudget,
}) {
  String build(String ctx, String profile, List<ChunkAnalysisResult> results) =>
      buildMergePrompt(
        results,
        diagnosisContext: ctx,
        structureProfile: profile,
        disabledSyndromeIds: disabledSyndromeIds,
        teachingMode: teachingMode,
        chunkCoverage: chunkCoverage,
      );

  var ctx = diagnosisContext;
  var profile = structureProfile;
  var results = chunkResults;
  final reports = <BudgetGuardReport>[];
  var est = TokenBudgetGuard.estimate(build(ctx, profile, results));
  if (est <= limit) {
    return MergeBudgetPlan(
      structureProfile: profile,
      diagnosisContext: ctx,
      chunkResults: results,
      mergePrompt: build(ctx, profile, results),
      estimatedTokens: est,
      reports: reports,
    );
  }

  // 降级序列：逐级尝试、每级重估（级序见本节头注）
  void degrade(String stage, bool Function() apply) {
    if (est <= limit) return;
    final before = est;
    if (!apply()) return; // 该级无可裁内容 → 跳过（不虚报 droppedStages）
    final prompt = build(ctx, profile, results);
    est = TokenBudgetGuard.estimate(prompt);
    reports.add(
      BudgetGuardReport(
        overBudget: est > limit,
        triggered: true,
        overWarning: est > limit * TokenEstimate.warningRatio,
        totalBefore: before,
        totalAfter: est,
        droppedStages: [stage],
        droppedMessageCount: 0,
      ),
    );
  }

  degrade(kMergeBudgetStageProfile, () {
    if (profile.isEmpty) return false;
    profile = '';
    return true;
  });
  degrade(kMergeBudgetStageContext, () {
    if (ctx.isEmpty || activeSyndromeIds.isEmpty) return false;
    final filtered = filterDiagnosisContextToActive(ctx, activeSyndromeIds);
    if (filtered == ctx) return false;
    ctx = filtered;
    return true;
  });
  degrade(kMergeBudgetStageNotes, () {
    final compressed = compressChunkNotesBySeverity(results);
    if (identical(compressed, results)) return false;
    results = compressed;
    return true;
  });

  if (est > limit) {
    throw ProgressiveMergeOverBudget(est, limit);
  }
  return MergeBudgetPlan(
    structureProfile: profile,
    diagnosisContext: ctx,
    chunkResults: results,
    mergePrompt: build(ctx, profile, results),
    estimatedTokens: est,
    reports: reports,
  );
}

// ── W-15-B B3：发送快照落库（验收⑤「最终发送快照与日志可核对」）──
//
// 设计稿 §3.5：merge 调用前把最终 mergePrompt 全文落 error_logs（复用
// LlmCallLogSink 通道纪律：info 级 / category='api' / event='llm_prompt_snapshot'；
// A12 脱敏天然生效）。载荷含 convergence 为设计稿标注的「后补」项——收敛报告
// 在卡片装配点（diagnosis_flow_handler）才产生，本快照发射点（发送前）不可得，
// 本批不接（诚实登记，非缺口：发送体可核对性不依赖它）。
// 旁路纪律：落库失败静默，不阻断主流程、不改返回值。

/// 快照截断阈值（字节）：mergePrompt 超过即截断存哈希 + 头尾。
const int kMergePromptSnapshotMaxBytes = 64 * 1024;

/// 截断时保留的头/尾字节数（各 8 KB）。
const int kMergePromptSnapshotKeepBytes = 8 * 1024;

/// B3：mergePrompt 快照视图。≤64 KB 原文原样；>64 KB 截断存全文哈希
/// （sha256 前 16 位）+ 头尾各 8 KB（按 UTF-8 字节切，边界字符容错解码），
/// 截断事实显式记录。纯函数，不发请求。
({bool truncated, String stored, String? sha256Prefix, int totalBytes})
truncateMergePromptForSnapshot(String prompt) {
  final bytes = utf8.encode(prompt);
  if (bytes.length <= kMergePromptSnapshotMaxBytes) {
    return (
      truncated: false,
      stored: prompt,
      sha256Prefix: null,
      totalBytes: bytes.length,
    );
  }
  final head = utf8.decode(
    bytes.sublist(0, kMergePromptSnapshotKeepBytes),
    allowMalformed: true,
  );
  final tail = utf8.decode(
    bytes.sublist(bytes.length - kMergePromptSnapshotKeepBytes),
    allowMalformed: true,
  );
  final sha = crypto.sha256.convert(bytes).toString();
  final shaPrefix = sha.substring(0, 16);
  return (
    truncated: true,
    stored:
        '$head\n…[截断：全文 ${bytes.length} 字节，sha256 前 16 位=$shaPrefix]…\n$tail',
    sha256Prefix: shaPrefix,
    totalBytes: bytes.length,
  );
}

/// B3：组装快照载荷（event 名 = 查询锚点；budget_report 携带逐级降级记录）。
Map<String, dynamic> buildMergePromptSnapshotPayload({
  required int chunkCount,
  required List<ChunkCoverage> chunkCoverage,
  required String mergePrompt,
  required List<BudgetGuardReport> degradationReports,
  required int estimatedTokens,
  required int budgetLimit,
}) {
  final view = truncateMergePromptForSnapshot(mergePrompt);
  return {
    'event': 'llm_prompt_snapshot',
    'purpose': 'diagnosis_merge',
    'chunk_count': chunkCount,
    'chunk_coverage': [
      for (final c in chunkCoverage)
        {
          'index': c.index,
          'start': c.start,
          'end': c.end,
          'located': c.located,
        },
    ],
    'merge_prompt': view.stored,
    if (view.truncated) ...{
      'merge_prompt_truncated': true,
      'merge_prompt_sha256_16': view.sha256Prefix,
      'merge_prompt_total_bytes': view.totalBytes,
    },
    'budget_report': {
      'levels': [
        for (final r in degradationReports)
          if (r.droppedStages.isNotEmpty)
            {
              'stage': r.droppedStages.first,
              'total_before': r.totalBefore,
              'total_after': r.totalAfter,
            },
      ],
      'final_estimate': estimatedTokens,
      'limit': budgetLimit,
    },
  };
}

// ── 主入口：runProgressiveDiagnosis（对齐 RN，超长时分块，否则 null）──

typedef ProgressCallback = void Function(String phase, int current, int total);

/// 渐进式诊断入口。
///
/// 返回 [ProgressiveResult] 表示成功走了分块链路；返回 null 表示内容 <= THRESHOLD，
/// 应交给外部走单次诊断链路（ChatService.sendMessage，D1 已接通）。
///
/// 调用方提供的 [onContent] 在分块链路的 merge 阶段会收到流式增量文本（对齐
/// RN streamChat）。[onProgress] 可选，用于 UI 进度展示。
///
/// D4-A 真链路：通过注入 [llmClient] 实现完整分块链路——
///   - analyzeChunk（单块分析）走 LlmClient.chatCompletion（非流式）
///   - merge 阶段走 LlmClient.streamChat（流式）
///
/// [mergeTemperature]（W-18 用户温度档，真源 config/diagnosis_temperature.dart）：
/// merge（流式）段请求体温度覆盖。null = 现网默认（不产 extraBody 键，
/// 请求体逐字节不变）；仅作用于 merge 段——单块分析段与教学链路不受影响。
///
/// [activeSyndromeIds]（W-15-B B1 级序 b）：会话当前活跃症候 ID 集合，仅在
/// merge 超预算降级时用于过滤 diagnosisContext；空集 = 无判据，级序 b 跳过。
///
/// [snapshotWriter]（W-15-B B3）：merge prompt 发送快照出口，缺省走
/// error_logs（`emitMergePromptSnapshot`）；测试注入收集器断言载荷。
Future<ProgressiveResult?> runProgressiveDiagnosis({
  required String content,
  required String title,
  required void Function(String content) onContent,
  required LlmClient llmClient,
  ProgressCallback? onProgress,
  String? sessionId,
  String diagnosisContext = '',
  String structureProfile = '',
  CancelToken? cancelToken,
  Set<String> disabledSyndromeIds = const {},
  TeachingMode teachingMode = TeachingMode.socratic,
  double? mergeTemperature,
  Set<String> activeSyndromeIds = const {},
  MergePromptSnapshotWriter? snapshotWriter,
}) async {
  if (content.length <= kDiagnosisChunkThreshold) {
    return null;
  }

  // 1. 分块（W-15-A：同步计算覆盖区间，验收②）
  final chunks = splitContent(content);
  final chunkCoverage = computeChunkCoverage(content, chunks);
  onProgress?.call('分块完成', 0, chunks.length);

  // 2. 逐块分析（非流式 chatCompletion；空内容分级降级见 ADR-C80）
  final chunkResults = <ChunkAnalysisResult>[];
  var failedChunks = 0;

  for (var i = 0; i < chunks.length; i++) {
    // ADR-C87 延伸：每块前检查，用户可在多轮调用中中途停止
    _throwIfCancelled(cancelToken);
    final result = await _analyzeSingleChunk(
      llmClient,
      title: title,
      chunk: chunks[i],
      chunkIndex: i,
      chunkCount: chunks.length,
      onProgress: onProgress,
      disabledSyndromeIds: disabledSyndromeIds,
      teachingMode: teachingMode,
    );
    if (!result.success) failedChunks++;
    chunkResults.add(result);
  }

  // 3. 合并：预算预检三态（B1）→ 发送快照（B3）→ streamChat 流式输出
  // ADR-C87 延伸：合并前检查，取消时不发起最后一次调用
  _throwIfCancelled(cancelToken);
  final fullContent = await _runMergePhase(
    chunkResults: chunkResults,
    chunkCoverage: chunkCoverage,
    diagnosisContext: diagnosisContext,
    structureProfile: structureProfile,
    disabledSyndromeIds: disabledSyndromeIds,
    teachingMode: teachingMode,
    activeSyndromeIds: activeSyndromeIds,
    llmClient: llmClient,
    onContent: onContent,
    cancelToken: cancelToken,
    mergeTemperature: mergeTemperature,
    snapshotWriter: snapshotWriter,
  );

  return ProgressiveResult(
    fullContent: fullContent,
    chunkCount: chunks.length,
    failedChunks: failedChunks,
    chunkCoverage: chunkCoverage,
  );
}

/// W-15-B：merge 段执行（预算预检三态 → 发送快照 → 流式合并）。
///
/// 由 [runProgressiveDiagnosis] 抽出（R-019：主入口不因 B1/B3 继续膨胀）。
/// 拒发路径：[planMergeBudget] 穷尽降级仍超限 ⇒ 抛
/// [ProgressiveMergeOverBudget]，**不发起任何 LLM 调用**。
Future<String> _runMergePhase({
  required List<ChunkAnalysisResult> chunkResults,
  required List<ChunkCoverage> chunkCoverage,
  required String diagnosisContext,
  required String structureProfile,
  required Set<String> disabledSyndromeIds,
  required TeachingMode teachingMode,
  required Set<String> activeSyndromeIds,
  required LlmClient llmClient,
  required void Function(String content) onContent,
  CancelToken? cancelToken,
  double? mergeTemperature,
  MergePromptSnapshotWriter? snapshotWriter,
}) async {
  // B1：merge 预算预检（照发 / 降级 / 拒发——超限不静默发送）
  final plan = planMergeBudget(
    chunkResults: chunkResults,
    chunkCoverage: chunkCoverage,
    diagnosisContext: diagnosisContext,
    structureProfile: structureProfile,
    disabledSyndromeIds: disabledSyndromeIds,
    teachingMode: teachingMode,
    activeSyndromeIds: activeSyndromeIds,
  );
  final mergePrompt = plan.mergePrompt;

  // B3：发送快照（旁路；载荷含最终发送体全文与逐级降级记录）
  emitMergePromptSnapshot(
    buildMergePromptSnapshotPayload(
      chunkCount: chunkResults.length,
      chunkCoverage: chunkCoverage,
      mergePrompt: mergePrompt,
      degradationReports: plan.reports,
      estimatedTokens: plan.estimatedTokens,
      budgetLimit: TokenEstimate.maxBudget,
    ),
    writer: snapshotWriter,
  );

  var fullContent = '';
  try {
    // TH 九批：标注诊断链路（合流轮）。
    llmClient.markCallContext(_kDiagnosisCallContext);
    await llmClient.streamChat(
      [
        const ChatMessage(role: 'system', content: '你是一个专业的写作诊断助手。'),
        ChatMessage(role: 'user', content: mergePrompt),
      ],
      (response) {
        if (response.isDone || response.content.isEmpty) return;
        fullContent += response.content;
        onContent(response.content);
      },
      // P3 观察项收口：merge 阶段透传取消令牌——此前缺传，合并中无法
      // 中途停止；取消统一转 ProgressiveDiagnosisCancelled（调用方已有
      // 优雅复位），不落为「报错」。
      cancelToken: cancelToken,
      // W-18 用户温度档：null 不产键 ⇒ 请求体逐字节不变（灵活档）；
      // 保守档 0.3 经 extraBody 覆盖骨架 temperature（W-18 实验档复现，
      // extraBody 合并在骨架 temperature 之后，可覆盖且不触碰其它键）。
      extraBody: mergeTemperature == null
          ? null
          : {'temperature': mergeTemperature},
    );
  } on LlmRequestCancelledException {
    throw const ProgressiveDiagnosisCancelled();
  }
  return fullContent;
}

/// ★ 解析 `uncertain` 标记（ADR-C153 §2）。
///
/// 为什么不能写 `n['uncertain'] == true`：模型对该字段的类型不稳定 ——
/// 实测常见三种形态 `true`（bool）/ `"true"`（String）/ `1`（num）。
/// `== true` 会把后两种全判成 false ⇒ **窗口边界声明在最常见的两种输出下静默失效**，
/// 而失效方向恰好是「把判不了的当成判得了」——正是要防的那一侧。
///
/// 只认肯定语义（true / "true" / "True" / "1" / 1）；其余一律 false（缺省）。
/// 不抛异常：本函数在 `_parseChunkNotes` 的 try 内，抛异常会连带丢掉整块笔记。
bool _parseUncertainFlag(Object? raw) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    final v = raw.trim().toLowerCase();
    return v == 'true' || v == '1' || v == 'yes';
  }
  return false;
}

/// 解析单块分析返回的 JSON 为 ChunkNote 列表
List<ChunkNote> _parseChunkNotes(String jsonStr) {
  try {
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map<String, dynamic> && decoded['notes'] is List) {
      return (decoded['notes'] as List)
          .whereType<Map<String, dynamic>>()
          .map(
            (n) => ChunkNote(
              syndromeId: n['syndromeId'] as String? ?? '',
              description: n['description'] as String? ?? '',
              evidence:
                  (n['evidence'] as List?)?.map((e) => e.toString()).toList() ??
                  const [],
              severity: n['severity'] as String? ?? 'L1',
              uncertain: _parseUncertainFlag(n['uncertain']),
            ),
          )
          // L3 白名单：severity 越界（非 L1/L2/L3）→ 剔除该条并留痕。
          // 中间产物诚实降级——不伪造严重度进入合并 prompt。
          .where((n) {
            final ok = normalizeSeverity(n.severity) != null;
            if (!ok) {
              debugPrint(
                '[L3] 分块笔记 severity 越界剔除: '
                '${n.syndromeId} ${n.severity}',
              );
            }
            return ok;
          })
          .toList();
    }
  } catch (e, st) {
    // LLM 返回结构不符预期 → 本块诊断结果降级为空（原行为保留）。
    // 此前静默吞掉，用户表现为「诊断结果少了/没有」且无从追溯。
    logDecodeFailure(
      field: 'progressive_diagnosis.chunk_notes',
      error: e,
      stack: st,
      category: 'api',
    );
  }
  return const [];
}

// ── 单块分析：空内容分级降级（ADR-C80）──

/// 单块分析的 messages（尝试 1 与兜底重试共用同一组消息）。
List<ChatMessage> _chunkMessages(
  String title,
  String chunk,
  int chunkIndex,
  int chunkCount, {
  Set<String> disabledSyndromeIds = const {},
  TeachingMode teachingMode = TeachingMode.socratic,
}) {
  return [
    // ADR-C69：kChunkSystemPrompt 改由注册表派生（非 const），此处 const 去掉。
    // 诊断编辑器：按用户启用集运行时构造 prompt（空集 = 全启用默认）。
    ChatMessage(
      role: 'system',
      content:
          disabledSyndromeIds.isEmpty && teachingMode == TeachingMode.socratic
          ? kChunkSystemPrompt
          : _buildChunkSystemPrompt(disabledSyndromeIds, teachingMode),
    ),
    ChatMessage(
      role: 'user',
      content: '章节标题：$title\n\n文本片段 ${chunkIndex + 1}/$chunkCount：\n\n$chunk',
    ),
  ];
}

/// 单块分析（ADR-C80 分级降级）：
///
/// 尝试 1 = 应用现参数（推理开启，质量优先，成功路径零变更）；content 为空
/// → 尝试 2 = 兜底参数（8192 + thinking disabled，推理归零，实测见 ADR §1.2）；
/// 仍空 → 返回 success=false + [kChunkFailureEmptyContent] 并留痕。
/// 异常路径同样置 [kChunkFailureException] 并留痕（此前 catch 静默）。
///
/// 「空」判据是 `content.trim().isEmpty`：合法「零症候」是 notes 为空的
/// 非空 JSON（模型说了「没有」），与本缺陷（模型一个字没说）是两回事。
Future<ChunkAnalysisResult> _analyzeSingleChunk(
  LlmClient llmClient, {
  required String title,
  required String chunk,
  required int chunkIndex,
  required int chunkCount,
  required ProgressCallback? onProgress,
  Set<String> disabledSyndromeIds = const {},
  TeachingMode teachingMode = TeachingMode.socratic,
}) async {
  final messages = _chunkMessages(
    title,
    chunk,
    chunkIndex,
    chunkCount,
    disabledSyndromeIds: disabledSyndromeIds,
    teachingMode: teachingMode,
  );
  try {
    // TH 九批：分块分析（含 fallback 重发）同属诊断链路 —— 每次调用前
    // 重新标注，因为标记是一次性消费的。
    llmClient.markCallContext(_kDiagnosisCallContext);
    var content = await llmClient.chatCompletion(messages);
    if (content.trim().isEmpty) {
      llmClient.markCallContext(_kDiagnosisCallContext);
      content = await llmClient.chatCompletion(
        messages,
        maxTokens: LlmConfig.chunkAnalysisFallbackMaxTokens,
        extraBody: LlmConfig.chunkAnalysisFallbackExtraBody,
      );
    }
    // 空块此前走成功路径会推进度，保持推进；异常块此前不推，保持不推
    onProgress?.call('分析分片', chunkIndex + 1, chunkCount);
    if (content.trim().isEmpty) {
      _logChunkFailure(chunkIndex, kChunkFailureEmptyContent);
      return ChunkAnalysisResult(
        chunkIndex: chunkIndex,
        notes: const [],
        success: false,
        failureReason: kChunkFailureEmptyContent,
      );
    }
    final jsonStr = extractJson(content);
    final notes = _parseChunkNotes(jsonStr);
    return ChunkAnalysisResult(
      chunkIndex: chunkIndex,
      notes: notes,
      success: true,
    );
  } catch (e, st) {
    _logChunkFailure(chunkIndex, kChunkFailureException, error: e, stack: st);
    return ChunkAnalysisResult(
      chunkIndex: chunkIndex,
      notes: const [],
      success: false,
      failureReason: kChunkFailureException,
    );
  }
}

/// 单块失败显式留痕（ADR-C63 范式：降级行为保留，可观测性补上）。
void _logChunkFailure(
  int chunkIndex,
  String reason, {
  Object? error,
  StackTrace? stack,
}) {
  debugPrint(
    '[progressive_diagnosis] 分块 $chunkIndex 失败 reason=$reason'
    '${error != null ? ' error=$error' : ''}',
  );
  ErrorHandler.instance.captureError(
    level: 'warn',
    category: 'api',
    message: '分块诊断失败，已按失败块降级',
    context: {
      'chunkIndex': chunkIndex,
      'reason': reason,
      if (error != null) 'error': '$error',
    },
    stack: stack?.toString(),
  );
}
