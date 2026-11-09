// ─────────────────────────────────────────────────────────────
// chat 链试点发现调用（裁点甲 · R-027 · T-20261109-01 施工批）。
//
// 逐字授权面 = `.ai/reports/2026-11-09-报批稿-落点乙-发现方向集与晋升闸与锚定域.md`
// （方向段 + 域声明 + 装配规则，舰长 2026-11-09「都批」）+
// 11-03 批已批逐字资产复用（kCandidatePromotionGate / kDiscoveryOutputFormat）。
//
// 硬约束（与分块链发现调用同款五条）：
// 1. 三键门（复用 `discoveryGateAllows`，不新增配置面）；
// 2. 长度门（`kDiscoveryContentLimit`）；
// 3. 取消门：`cancelled` 为真 ⇒ 不发起；
// 4. 失败不外抛：异常留痕并返回 empty，不重试；
// 5. ★ S-9：本调用**不触发**任何验证层调用——出口一有编号者在 chat 链的
//    验证消费挂 U3（登记：与分块链不同，本批 chat 链验证消费不接线）。
//
// 登记边界（本批如实口径，见施工报告）：
// - 方向选择策略 = 确定性轮转（系统指定、无自由生成路径，A2 牙）；
//   「按章节位置与能力画像」的画像选择挂 U4 后批（当前无画像数据源）。
// - 域内锚定（C4）校验面 = 本章正文（D2 的子集）：解析器已保证锚点 ⊆ 正文；
//   会话上下文文本的校验通路随呈现子批接。
// - 产物去向 = 候选区数据面（出口三未归类 + 出口一无编号）；UI 折叠条呈现
//   随呈现子批（报批稿 §3.8：UI 通道随呈现子批）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import '../../data/database/database.dart';
import 'candidate_zone.dart';
import 'discovery_call.dart';
import 'discovery_note.dart';
import 'discovery_prompt.dart';
import 'llm_client.dart';
import 'llm_usage.dart';
import 'verification_gate.dart';

/// 埋点上下文：与 `discovery_call.dart` 同 purpose（§8-9 同款缺口：埋点上
/// 与主链诊断调用不可区分；不新增枚举值）。物理重声明理由同源。
const LlmCallContext _kChatDiscoveryCallContext = LlmCallContext(
  purpose: LlmCallPurpose.diagnosis,
);

/// 主方向轮转序号（确定性系统指定；无自由生成路径）。测试可经
/// `ordinal` 参数注入，绕开进程内计数器。
int _chatDiscoveryOrdinal = 0;

/// 方向选择（A2 牙落点）：主方向在前五值中按序号确定性轮转；
/// 兜底方向「通用观察」永不轮空（报批稿 §1.①：兜底永不缺席）。
String resolveChatDiscoveryDirection({int? ordinal}) {
  final mainCount = kDiscoveryDirections.length - 1;
  final n = ordinal ?? _chatDiscoveryOrdinal++;
  return kDiscoveryDirections[n % mainCount];
}

/// chat 链试点发现调用：装配新帧（方向段 + D2 域声明）→ 出站 → 解析
/// → 库外发现登记候选区。失败 / 未配置 / 超长 / 取消一律返回 empty，**不抛**。
Future<DiscoveryParseResult> runChatChainDiscovery({
  required VerificationGate gate,
  required LlmClient llmClient,
  required String content,
  required CandidateZone zone,
  required String sourceTextId,
  bool cancelled = false,
  int? ordinal,
}) async {
  if (cancelled) return DiscoveryParseResult.empty;
  if (!await discoveryGateAllows(gate, content)) {
    return DiscoveryParseResult.empty;
  }

  final direction = resolveChatDiscoveryDirection(ordinal: ordinal);
  String raw;
  try {
    llmClient.markCallContext(_kChatDiscoveryCallContext);
    raw = await llmClient.chatCompletion([
      ChatMessage(
        role: 'system',
        content: buildChatDiscoverySystemPrompt(direction: direction),
      ),
      ChatMessage(role: 'user', content: content),
    ]);
  } catch (error) {
    debugPrint('[discovery_chat] 试点发现调用失败，按零条处理: $error');
    return DiscoveryParseResult.empty;
  }

  final parsed = parseDiscoveryNotes(raw, content);
  final registered = registerCandidates(
    zone,
    parsed,
    domainText: content,
    sourceTextId: sourceTextId,
  );
  debugPrint(
    '[discovery_chat] direction=$direction rawCount=${parsed.rawCount} '
    'promoted=${parsed.promoted} dropped=${parsed.dropped} '
    'candidatesRegistered=$registered',
  );
  return parsed;
}

/// S-3 去向登记：出口三（未归类）与出口一无编号（暂无合适症候）进候选区；
/// 出口二（观察记录，无假设）与出口一有编号（验证层管辖区）不登记。
/// C4 前置：锚点须命中声明域文本（解析器已保证 ⊆ 正文，此处对声明域复验）。
int registerCandidates(
  CandidateZone zone,
  DiscoveryParseResult parsed, {
  required String domainText,
  required String sourceTextId,
}) {
  var registered = 0;
  for (final note in parsed.notes) {
    final isUnnamedHypothesis =
        note.exit == DiscoveryExit.promoted && note.syndromeId.isEmpty;
    final isUnclassified = note.exit == DiscoveryExit.unclassified;
    if (!isUnnamedHypothesis && !isUnclassified) continue;
    if (note.anchorQuotes.isEmpty) continue;
    final anchor = note.anchorQuotes.first;
    if (!anchorMatchesDomain(anchor, domainText)) continue;
    zone.registerObservation(
      anchor: anchor,
      hypothesis: isUnnamedHypothesis ? note.inference : note.reason,
      sourceTextId: sourceTextId,
    );
    registered++;
  }
  return registered;
}

/// 全局候选区（进程内单例；持久化边界见文件头登记）。
final CandidateZone globalCandidateZone = CandidateZone();

/// chat 链接线壳（T-20261109-01 · controller 短链诊断收尾后调用）：
/// 域内校验面 = 本章正文（D2 子集，见文件头登记）；来源标识 = 章节 id。
Future<void> runChatChainDiscoveryForChapter({
  required VerificationGate gate,
  required LlmClient llmClient,
  required Chapter chapter,
}) async {
  await runChatChainDiscovery(
    gate: gate,
    llmClient: llmClient,
    content: chapter.content,
    zone: globalCandidateZone,
    sourceTextId: 'chapter-${chapter.id}',
  );
}
