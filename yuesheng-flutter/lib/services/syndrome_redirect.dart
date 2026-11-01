// ─────────────────────────────────────────────────────────────
// SyndromeRedirect — 撤销改道派生载体（T-20261031-12 · R-027 已批）
//
// 用途：模型撤销一条诊断（excluded）时给学习者一个「改做哪件事」的出口，
// 而不是空洞的「本次未发现显著问题」（判语研究 §4.3 机制层根因）。
//
// 组成（= 报批稿 §2.3 的「33 条登记 + 派生函数」）：
// - `syndrome_redirect_table.dart`：33 条逐字登记表（数据面）；
// - 本文件：派生（分支切分 / 净化 / 展示句回落）。
//
// 零 import 纪律：本文件**不 import** skill_registry / teaching_types
// （skill_registry → skill_types → teaching_types → 本文件 ⇒ 成环）⇒
// 「真源集合」不在本文件硬编，改由「该行 allowed ⊆ 真源」这条**测试侧断言**
// 兜底（报批稿 §2.3 遍历断言），运行时只做「∈ 本行 allowed」。
//
// 文案唯一真源 = `.ai/reports/2026-11-01-温知新-31-12教学层签与33条文案.md`
// §二 33 条终稿表（逐字，零新术语、零新训练出口）——本文件不新造文案。
// ─────────────────────────────────────────────────────────────

import 'syndrome_redirect_table.dart';

export 'syndrome_redirect_table.dart';

/// 一支改道：指向 id + 该支逐字句。
typedef RedirectBranch = ({String id, String clause});

/// 净化后的改道字段（三者皆空 = 未指认）。
typedef RedirectFields = ({
  String? syndromeId,
  String? actionId,
  String? text,
  List<String> traces,
});

/// 查一行改道登记（未登记 ⇒ null）。
SyndromeRedirect? redirectOf(String syndromeId) =>
    kSyndromeRedirects[syndromeId];

/// 把一行文案切成「每支恰含一个 allowed id」的分支列表。
///
/// 切分点固定为「、」与「；」：终稿表 8 条多分支行与 14 条单分支行均满足
/// 「每支恰含一个 allowed id」（S/A 共 22 条 = 8 多 + 14 单），由遍历断言守住。
List<RedirectBranch> redirectBranchesOf(SyndromeRedirect row) {
  final out = <RedirectBranch>[];
  for (final part in row.text.split(RegExp('[、；]'))) {
    final clause = part.trim();
    if (clause.isEmpty) continue;
    final hit = row.allowed.where((id) => clause.contains(id)).toList();
    if (hit.length != 1) continue;
    out.add((id: hit.first, clause: clause));
  }
  return out;
}

/// 该行中指向 [id] 的那一支的逐字句（无此支 ⇒ null）。
String? redirectClauseOf(SyndromeRedirect row, String id) {
  for (final b in redirectBranchesOf(row)) {
    if (b.id == id) return b.clause;
  }
  return null;
}

/// 从模型给出的 redirect 对象净化出三字段（**失配即丢该字段，不丢整条 note**）。
///
/// 处置口径（报批稿 §2.4，对齐 25-10 丙裁「只丢字段并留痕、不丢整条 note」）：
/// - `syndrome_id` / `action_id`：须 ∈ 该行 `allowed` 集（allowed ⊆ 真源，由
///   遍历断言保证）且前缀正确（P → syndrome_id / A → action_id），否则丢该字段并留痕；
/// - 两个指向同时给出：协议要求**择一** ⇒ 按该行 `primary` 留一支、丢另一支并留痕；
/// - `text`：须**逐字取自**该行文案中对应的那一支（且不得含第二个 allowed id
///   ⇒「学习者每次只见一支」在协议层守住），否则丢该字段并留痕。
RedirectFields sanitizeRedirect(
  Object? raw, {
  required String ownerSyndromeId,
}) {
  if (raw == null) return _emptyFields(const <String>[]);
  if (raw is! Map) {
    return _emptyFields(['$ownerSyndromeId redirect 结构非法']);
  }
  final row = kSyndromeRedirects[ownerSyndromeId];
  if (row == null) {
    return _emptyFields(['$ownerSyndromeId 无改道登记，redirect 已丢弃']);
  }
  final traces = <String>[];
  final sid = _readRedirectId(
    raw,
    'syndrome_id',
    'P',
    row,
    ownerSyndromeId,
    traces,
  );
  final aid = _readRedirectId(
    raw,
    'action_id',
    'A',
    row,
    ownerSyndromeId,
    traces,
  );
  final one = _pickOneDirection(sid, aid, row, ownerSyndromeId, traces);
  final text = _readRedirectText(
    raw,
    row,
    one.syndromeId ?? one.actionId,
    ownerSyndromeId,
    traces,
  );
  return (
    syndromeId: one.syndromeId,
    actionId: one.actionId,
    text: text,
    traces: traces,
  );
}

/// 全空字段（未指认）——可带留痕。
RedirectFields _emptyFields(List<String> traces) =>
    (syndromeId: null, actionId: null, text: null, traces: traces);

/// 读一个指向字段：非 String / 空串 / 前缀不符 / 不在该行 `allowed` 集
/// ⇒ **丢该字段并留痕**（不丢整条记录）。
String? _readRedirectId(
  Map<Object?, Object?> raw,
  String key,
  String prefix,
  SyndromeRedirect row,
  String ownerId,
  List<String> traces,
) {
  final v = raw[key];
  if (v == null) return null;
  if (v is String && v.startsWith(prefix) && row.allowed.contains(v)) return v;
  traces.add('$ownerId redirect.$key 失配已丢弃');
  return null;
}

/// 两个指向同时给出时按该行 `primary` **择一**（协议要求择一）⇒ 丢一支并留痕。
({String? syndromeId, String? actionId}) _pickOneDirection(
  String? sid,
  String? aid,
  SyndromeRedirect row,
  String ownerId,
  List<String> traces,
) {
  if (sid == null || aid == null) return (syndromeId: sid, actionId: aid);
  traces.add('$ownerId redirect 同时给了两个指向，已按择一丢弃其一');
  if (row.primary == aid && row.primary != sid) {
    return (syndromeId: null, actionId: aid);
  }
  return (syndromeId: sid, actionId: null);
}

/// 读 text 字段：须**逐字取自**该行文案中对应的那一支（且不得含第二个
/// allowed id ⇒「学习者每次只见一支」在协议层守住），否则丢字段并留痕。
String? _readRedirectText(
  Map<Object?, Object?> raw,
  SyndromeRedirect row,
  String? keptId,
  String ownerId,
  List<String> traces,
) {
  final v = raw['text'];
  if (v == null) return null;
  if (v is String && v.trim().isNotEmpty) {
    final t = v.trim();
    final hit = redirectBranchesOf(row)
        .where((b) => b.id == keptId && (t == b.clause || b.clause.contains(t)))
        .toList();
    if (hit.length == 1) return t;
  }
  traces.add('$ownerId redirect.text 失配已丢弃');
  return null;
}

/// 学员面展示句：优先用模型发出的逐字 text；缺失/失配 ⇒ 回落到登记表的该支逐字句。
///
/// 回落是必要的：净化时 `text` 失配会被丢字段，但指向 id 仍在 ⇒ 渲染仍要有
/// 一句逐字的学员面指路（否则撤销行退回空洞）。
String? redirectDisplayText(
  SyndromeRedirect row,
  String? id,
  String? modelText,
) {
  if (id == null) return null;
  final m = modelText?.trim();
  if (m != null && m.isNotEmpty) return m;
  return redirectClauseOf(row, id);
}

/// T 行的诚实句（客户端兜底：撤销该症候且模型未给 redirect 时显示）。
///
/// T 行不进模型面（无出口可指）⇒ 这句只在客户端出现；措辞中性，不得渲染成
/// 报错或「无能为力」（温知新签 §一 风险「话术伤人」）。
String? redirectHonestText(String syndromeId) {
  final row = kSyndromeRedirects[syndromeId];
  if (row == null || row.inModelFace) return null;
  return row.text;
}
