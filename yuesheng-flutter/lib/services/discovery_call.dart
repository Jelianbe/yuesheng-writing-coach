// ─────────────────────────────────────────────────────────────
// 发现调用 + 解析 + → 验证层映射（R-027 · T-20261106-04 接线批新增）。
//
// 逐字授权面 = `.ai/reports/2026-11-07-报批稿-发现层接线与S5落牙.md` §2.4。
// 本文件是 **S-5「发现层与验证层之间唯一装配点」** 的实现：
//   独立帧（S-1）出站 → 解析出三出口 → 只把「出口一 + 逐字锚点」交给验证层。
//
// ★ 不 import `progressive_diagnosis.dart`（否则成环：后者 import 本文件）；
//   因此签名不收 `chunkResults`，也不引用 `_kDiagnosisCallContext`。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'discovery_note.dart';
import 'discovery_prompt.dart';
import 'llm_client.dart';
import 'llm_usage.dart';
import 'verification_gate.dart';

/// 发现调用正文长度上限（字符）。E3 推算：`maxBudget = 123904` × 比值 1.0
/// 再留出发现帧 1538 的余量 ⇒ 12.29 万。超限**不发起**、只留痕，不做逐块回退。
const int kDiscoveryContentLimit = 122900;

/// 埋点上下文。★ §8-9：**不新增** `LlmCallPurpose` 值（新增枚举值可能连带
/// `enum_consistency_test.dart`，未验证）⇒ 与主链 `_kDiagnosisCallContext` 同
/// purpose。物理上不能 import 该常量（`progressive_diagnosis.dart` 反向依赖本文件），
/// 故此处按同值重声明。**已知缺口**：埋点上发现调用与分块调用不可区分。
const _kDiscoveryCallContext = LlmCallContext(
  purpose: LlmCallPurpose.diagnosis,
);

/// 解析发现调用输出。纯函数、无 IO、可单测。
///
/// 失败一律 fail-closed（返回 `empty` 或缩小 notes），**绝不**假设成出口一：
/// - 整体非 JSON / 顶层非 Map / `observations` 非 List ⇒ empty
/// - 元素非 Map ⇒ 丢该元素，dropped+1
/// - `exit` 缺失 / 非字符串（如给了数组）/ 非法值（trim + toLowerCase 后仍不中）
///   ⇒ 丢该条，dropped+1。★ JSON **重复键**（`"exit":"a","exit":"b"`）在
///   `jsonDecode` 阶段被后者覆盖，解析器看不到两个值 ⇒ 「双出口」的可判形态
///   只有「`exit` 是数组」，不能用重复键做样本。
/// - `anchorQuotes` 非 List / 空 / **全部不是 `content` 的逐字子串** ⇒ 丢该条
/// - `promoted` 但 `inference` 空 ⇒ 丢该条；`observation`/`unclassified` 但
///   `reason` 空 ⇒ 丢该条
/// `rawCount` = 顶层 `observations` 的元素个数（**动任何过滤之前**取）。
DiscoveryParseResult parseDiscoveryNotes(String raw, String content) {
  final observations = _decodeObservations(raw);
  if (observations == null) return DiscoveryParseResult.empty;

  final rawCount = observations.length;
  var promoted = 0;
  var dropped = 0;
  final notes = <DiscoveryNote>[];

  for (final item in observations) {
    if (item is! Map) {
      dropped++;
      continue;
    }
    final exit = _parseExit(item['exit']);
    final quotes = _parseQuotes(item['anchorQuotes'], content);
    if (exit == null || quotes == null) {
      dropped++;
      continue;
    }
    final inference = _asString(item['inference']);
    final reason = _asString(item['reason']);
    final required = exit == DiscoveryExit.promoted ? inference : reason;
    if (required.isEmpty) {
      dropped++;
      continue;
    }
    notes.add(
      DiscoveryNote(
        exit: exit,
        anchorQuotes: List<String>.unmodifiable(quotes),
        inference: inference,
        reason: reason,
        syndromeId: _asString(item['syndromeId']),
      ),
    );
    if (exit == DiscoveryExit.promoted) promoted++;
  }

  return DiscoveryParseResult(
    rawCount: rawCount,
    promoted: promoted,
    dropped: dropped,
    notes: List<DiscoveryNote>.unmodifiable(notes),
  );
}

/// 发现层 → 验证层的**唯一**映射点。丢弃 inference / reason（S-7）。
///
/// 只收 `exit == promoted` **且** `syndromeId` 非空的条（裁点 B 甲案）；
/// 无编号的出口一仍计入 `promoted` 分母，但不进返回值 ⇒
/// `promoted - toHypotheses().length` 就是「无编号出口一」的可观测差（§8-1）。
List<VerificationHypothesis> toHypotheses(DiscoveryParseResult result) {
  final hypotheses = <VerificationHypothesis>[];
  var sequence = 0;
  for (final note in result.notes) {
    if (note.exit != DiscoveryExit.promoted) continue;
    if (note.syndromeId.isEmpty) continue;
    sequence++;
    hypotheses.add(
      VerificationHypothesis(
        id: 'h$sequence',
        syndromeId: note.syndromeId,
        evidence: List<String>.unmodifiable(note.anchorQuotes),
      ),
    );
  }
  return hypotheses;
}

/// 发现调用 + 装配。**排在分块循环与 merge 之后**（否则
/// `progressive_teaching_mode_prompt_test.dart:83` 的 `firstWhere(system)` 会取到发现帧）。
///
/// 返回解析结果（含分母三数）。失败 / 未配置 / 超长 / 取消一律返回 `empty`，**不抛**。
///
/// 五条硬约束（逐条落，缺一变即违授权）：
/// 1. **三键门**：`gate.keysLoader()` 不全 ⇒ 直接 return，**零出站**（复用验证
///    三键，不新增配置面 —— 裁点 E）。发现层的唯一消费者就是验证层，验证层
///    关闭时发现结果无人消费。
/// 2. **长度门**：`content.length > kDiscoveryContentLimit` ⇒ 不发起 + 留痕，
///    **不做逐块回退**。
/// 3. **取消门**：`cancelled` 为真 ⇒ 不发起。
/// 4. **失败不外抛**：异常只留痕并返回 `empty`；**不重试**（避免 2 倍噪声与成本）。
/// 5. **不 import `progressive_diagnosis.dart`**，签名不收 `chunkResults`。
///
/// ★ 已知缺口（登记，不在本批处置）：无独立硬超时 ⇒ 发现调用会延长
/// `runProgressiveDiagnosis` 的 Future 完成时刻（merge 已流式交付正文，
/// 但调用方需等本函数返回）。超时口径属判据变更，须另走 R-027。
Future<DiscoveryParseResult> runDiscoveryThenVerify({
  required VerificationGate gate,
  required LlmClient llmClient,
  required String content,
  required Set<String> disabledSyndromeIds,
  required bool cancelled,
}) async {
  if (cancelled) return DiscoveryParseResult.empty;
  if (!await discoveryGateAllows(gate, content)) {
    return DiscoveryParseResult.empty;
  }

  String raw;
  try {
    llmClient.markCallContext(_kDiscoveryCallContext);
    raw = await llmClient.chatCompletion([
      ChatMessage(role: 'system', content: buildDiscoverySystemPrompt()),
      ChatMessage(role: 'user', content: content),
    ]);
  } catch (error) {
    debugPrint('[discovery_call] 发现调用失败，按零条处理: $error');
    return DiscoveryParseResult.empty;
  }

  final parsed = parseDiscoveryNotes(raw, content);
  final gated = _dropDisabled(parsed, disabledSyndromeIds);
  // 分母三数留痕（裁点 F 乙案：不进 VerificationRecord —— 该文件 300 行零余量）。
  debugPrint(
    '[discovery_call] rawCount=${gated.rawCount} promoted=${gated.promoted} '
    'dropped=${gated.dropped} disabledPromoted=${parsed.promoted - gated.promoted}',
  );
  return gated;
}

/// 硬约束 1+2：三键门 → 长度门。`true` = 允许出站。
/// （T-20261109-01：改公开——chat 链试点发现调用复用同款门，保证两帧门控一致。）
Future<bool> discoveryGateAllows(VerificationGate gate, String content) async {
  try {
    final keys = await gate.keysLoader();
    if (!keys.isComplete) return false;
  } catch (error) {
    debugPrint('[discovery_call] 三键读取失败，跳过发现调用: $error');
    return false;
  }
  if (content.length > kDiscoveryContentLimit) {
    debugPrint(
      '[discovery_call] 正文 ${content.length} 字符 > $kDiscoveryContentLimit，跳过（不逐块回退）',
    );
    return false;
  }
  return true;
}

/// 剔除用户禁用的症候对应的出口一条目，并同步下调 `promoted` 分母。
///
/// 下调的理由：`promoted - toHypotheses().length` 必须**只**反映「无编号出口一」
/// （§8-1 的可观测差）；若被禁用条仍计入分母，这个差就混入配置因素而不可解释。
DiscoveryParseResult _dropDisabled(
  DiscoveryParseResult result,
  Set<String> disabledSyndromeIds,
) {
  if (disabledSyndromeIds.isEmpty) return result;
  final kept = <DiscoveryNote>[];
  var promoted = 0;
  var disabledPromoted = 0;
  for (final note in result.notes) {
    final isPromoted = note.exit == DiscoveryExit.promoted;
    if (isPromoted &&
        note.syndromeId.isNotEmpty &&
        disabledSyndromeIds.contains(note.syndromeId)) {
      disabledPromoted++;
      continue;
    }
    kept.add(note);
    if (isPromoted) promoted++;
  }
  if (disabledPromoted == 0) return result;
  return DiscoveryParseResult(
    rawCount: result.rawCount,
    promoted: promoted,
    dropped: result.dropped,
    notes: List<DiscoveryNote>.unmodifiable(kept),
  );
}

/// 取首个 `{` 到末个 `}`（模型常包代码围栏或加一句前言）。
/// 抽不出 ⇒ null。**不做「猜哪段像 JSON」的启发式**。
List<Object?>? _decodeObservations(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(raw.substring(start, end + 1));
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final observations = decoded['observations'];
  return observations is List ? observations : null;
}

/// wire 值 → 枚举。`trim` + `toLowerCase` 后仍不中 ⇒ null（裁点 D 甲：一律 dropped，
/// 不猜、不取数组首项）。
DiscoveryExit? _parseExit(Object? value) {
  if (value is! String) return null;
  switch (value.trim().toLowerCase()) {
    case 'promoted':
      return DiscoveryExit.promoted;
    case 'observation':
      return DiscoveryExit.observation;
    case 'unclassified':
      return DiscoveryExit.unclassified;
  }
  return null;
}

/// 只留**逐字子串**通过 `content.contains` 的引句；一条都不通过 ⇒ null（整条作废）。
/// 部分通过 ⇒ 只保留通过者（未通过的引句绝不进验证层证据）。
List<String>? _parseQuotes(Object? value, String content) {
  if (value is! List) return null;
  final quotes = <String>[];
  for (final item in value) {
    if (item is! String) continue;
    final quote = item.trim();
    if (quote.isEmpty || !content.contains(quote)) continue;
    quotes.add(quote);
  }
  return quotes.isEmpty ? null : quotes;
}

String _asString(Object? value) => value is String ? value.trim() : '';
