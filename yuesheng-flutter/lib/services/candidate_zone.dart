// ─────────────────────────────────────────────────────────────
// 候选区数据面闸（S-3 唯一去向 · S-5 晋升闸 · R-027 · T-20261109-01 施工批）。
//
// 逐字授权面 = `.ai/reports/2026-11-09-报批稿-落点乙-发现方向集与晋升闸与锚定域.md`
// §1.②（字段 schema + 晋升判据逐字），舰长 2026-11-09「都批」。
//
// ★ 零新增模型调用（S-9）：本文件纯数据面——状态机 + 字段 + 计数口径，
//   不发起、不装配、不消费任何 LLM 调用（B5 牙回归面）。
// ★ 持久化边界（登记）：本批为进程内存储；跨启动持久化通路随呈现/消费
//   子批另立（报批稿未把 DB 落库划入三段同批范围）。
// ★ 判据③判重 = 离线工具批（裁点己：不挡本批）⇒ [CandidatePromotionRequest]
//   的 `duplicateCheckPassed` 由工具批产出；本批无工具，生产路径晋升不可达。
// ─────────────────────────────────────────────────────────────

/// 候选区条目状态：candidate / promoted / retired（退役留痕不删）。
enum CandidateStatus { candidate, promoted, retired }

/// 候选区条目（S-3 唯一去向 · S-5 晋升闸 · R-027 报批件 · 2026-11-09 待批）。
/// 必含五字段逐字对齐研究报告 §9.4；新增字段仅三个，见注释。
class CandidateEntry {
  /// 原文摘录锚点：必填。空或不命中声明域 ⇒ 淘汰（retired）
  final String anchor;

  /// AI 归因假设：发现层的推测，不是结论
  final String hypothesis;

  /// 出现次数：跨文本独立计数（口径见晋升判据①）
  final int occurrences;

  /// 首次发现时间
  final DateTime firstSeen;

  /// 状态：candidate / promoted / retired（退役留痕不删）
  final CandidateStatus status;

  // —— 晋升时追加（三判据②的产物与留痕；candidate 态必须为空）——

  /// 能变红的判据草案（双审后填写）
  final String? criteriaDraft;

  /// 例外条款草案（双审后填写）
  final String? exceptionDraft;

  /// 双审留痕：两名复核者的结论记录
  final List<String>? reviewLog;

  /// 淘汰/否决原因（B1/B2/B4 触发时登记；「淘汰原因随条目登记」）
  final String? retireReason;

  const CandidateEntry({
    required this.anchor,
    required this.hypothesis,
    required this.occurrences,
    required this.firstSeen,
    required this.status,
    this.criteriaDraft,
    this.exceptionDraft,
    this.reviewLog,
    this.retireReason,
  });
}

/// 锚点归一化（晋升判据①计数口径的「锚点归一化文本」）：
/// trim + 内部连续空白折叠为单空格。归一化后为空 ⇒ 无效锚点。
String normalizeAnchor(String anchor) =>
    anchor.trim().replaceAll(RegExp(r'\s+'), ' ');

/// 锚定域命中判定（C4/B1 · 报批稿 §1.③）：锚点须为声明域文本的逐字子串。
/// 纯函数；**不复用、不触碰**现行门控函数（那是 L0-① 批的物）。
bool anchorMatchesDomain(String anchor, String declaredDomainText) {
  final normalized = normalizeAnchor(anchor);
  return normalized.isNotEmpty && declaredDomainText.contains(normalized);
}

/// 晋升裁定结果（状态机单行道：只有 candidate 态可出结果，其余原样退回）。
enum CandidatePromotionOutcome {
  promoted,
  rejectedAnchor,
  rejectedCriteria,
  rejectedState,
}

/// 晋升闸：候选 → 晋升假设（三判据全过才晋升，缺一即否决）：
///
/// ① 重复出现：≥3 个不同文本独立出现。
///    计数口径：按（锚点归一化文本 × 来源文本）去重计数；
///    同一用户的重复只升置信度，不计入跨文本计数。
///    （此条由系统计数，代码可判。）
///
/// ② 人工复核：内容层双审通过，且双审后能写出能变红的判据草案
///    与例外条款草案。写不出 ⇒ 否决。
///    （此条人工执行，review_log 留痕。）
///
/// ③ 判重通过：与最相近的现有条目跑鉴别力采样，采样通过。
///    （此条为离线工具批，不进生产调用链。）
///
/// 否决去向：retired（留痕不删）。淘汰原因随条目登记。
class CandidatePromotionRequest {
  final String declaredDomainText;
  final String criteriaDraft;
  final String exceptionDraft;
  final List<String> reviewLog;
  final bool duplicateCheckPassed;

  const CandidatePromotionRequest({
    required this.declaredDomainText,
    required this.criteriaDraft,
    required this.exceptionDraft,
    required this.reviewLog,
    required this.duplicateCheckPassed,
  });
}

/// 候选区存储：登记（跨文本去重计数）+ 晋升闸（B1/B2/B4 牙）。
class CandidateZone {
  CandidateZone({DateTime Function()? now})
    : _now = now ?? (() => DateTime.now());

  final DateTime Function() _now;
  final Map<String, CandidateEntry> _entries = <String, CandidateEntry>{};
  final Map<String, Set<String>> _sourceTexts = <String, Set<String>>{};

  /// 全量条目快照（含 retired，留痕不删）。
  List<CandidateEntry> entries() => List.unmodifiable(_entries.values);

  CandidateEntry? entryByAnchor(String anchor) =>
      _entries[normalizeAnchor(anchor)];

  /// 登记一条库外发现（S-3 去向）。
  ///
  /// 计数口径（晋升判据①）：按（锚点归一化文本 × 来源文本）去重——同一来源
  /// 文本重复登记不计数；不同来源文本独立计数。同一用户的重复（同来源）
  /// 只更新假设文本、不计入。
  ///
  /// 空/归一化后为空的锚点不登记（schema：空锚点 ⇒ 淘汰态，无登记价值）；
  /// promoted / retired 态条目不再累积（留痕不删 ⇒ 状态单行道）。
  CandidateEntry registerObservation({
    required String anchor,
    required String hypothesis,
    required String sourceTextId,
  }) {
    final key = normalizeAnchor(anchor);
    if (key.isEmpty) {
      return CandidateEntry(
        anchor: anchor,
        hypothesis: hypothesis,
        occurrences: 0,
        firstSeen: _now(),
        status: CandidateStatus.retired,
        retireReason: 'anchor-empty',
      );
    }
    final existing = _entries[key];
    if (existing != null && existing.status != CandidateStatus.candidate) {
      return existing;
    }
    final seen = _sourceTexts.putIfAbsent(key, () => <String>{});
    final isNewSource = seen.add(sourceTextId);
    if (existing == null) return _createEntry(key, hypothesis);
    return _mergeExisting(existing, hypothesis, isNewSource);
  }

  CandidateEntry _createEntry(String key, String hypothesis) {
    final entry = CandidateEntry(
      anchor: key,
      hypothesis: hypothesis,
      occurrences: 1,
      firstSeen: _now(),
      status: CandidateStatus.candidate,
    );
    _entries[key] = entry;
    return entry;
  }

  /// 同来源重复：只升假设文本（取更长者为信息量更大者），不计数。
  CandidateEntry _mergeExisting(
    CandidateEntry existing,
    String hypothesis,
    bool isNewSource,
  ) {
    if (!isNewSource) {
      if (hypothesis.length <= existing.hypothesis.length) return existing;
      final updated = CandidateEntry(
        anchor: existing.anchor,
        hypothesis: hypothesis,
        occurrences: existing.occurrences,
        firstSeen: existing.firstSeen,
        status: existing.status,
      );
      _entries[existing.anchor] = updated;
      return updated;
    }
    final updated = CandidateEntry(
      anchor: existing.anchor,
      hypothesis: hypothesis,
      occurrences: existing.occurrences + 1,
      firstSeen: existing.firstSeen,
      status: CandidateStatus.candidate,
    );
    _entries[existing.anchor] = updated;
    return updated;
  }

  /// 晋升闸（三判据缺一即否决；否决去向 retired，留痕不删）。
  ///
  /// - B1 锚点滤网：anchor 为空 / 不命中声明域 ⇒ retired（§9.4 缺锚点直接淘汰）；
  /// - B2 三判据：occurrences < 3 或 reviewLog < 2 条或判据/例外草案为空
  ///   或判重未通过 ⇒ retired；
  /// - B4 状态机单行道：非 candidate 态一律拒绝且状态不变。
  CandidatePromotionOutcome promote(
    CandidateEntry entry,
    CandidatePromotionRequest request,
  ) {
    if (entry.status != CandidateStatus.candidate) {
      return CandidatePromotionOutcome.rejectedState;
    }
    if (!anchorMatchesDomain(entry.anchor, request.declaredDomainText)) {
      _retire(entry, 'anchor-not-in-domain');
      return CandidatePromotionOutcome.rejectedAnchor;
    }
    final criteriaOk =
        request.criteriaDraft.trim().isNotEmpty &&
        request.exceptionDraft.trim().isNotEmpty &&
        request.reviewLog.length >= 2 &&
        request.duplicateCheckPassed;
    if (entry.occurrences < 3 || !criteriaOk) {
      _retire(entry, 'criteria-unmet');
      return CandidatePromotionOutcome.rejectedCriteria;
    }
    _entries[entry.anchor] = CandidateEntry(
      anchor: entry.anchor,
      hypothesis: entry.hypothesis,
      occurrences: entry.occurrences,
      firstSeen: entry.firstSeen,
      status: CandidateStatus.promoted,
      criteriaDraft: request.criteriaDraft,
      exceptionDraft: request.exceptionDraft,
      reviewLog: List.unmodifiable(request.reviewLog),
    );
    return CandidatePromotionOutcome.promoted;
  }

  void _retire(CandidateEntry entry, String reason) {
    _entries[entry.anchor] = CandidateEntry(
      anchor: entry.anchor,
      hypothesis: entry.hypothesis,
      occurrences: entry.occurrences,
      firstSeen: entry.firstSeen,
      status: CandidateStatus.retired,
      retireReason: reason,
    );
  }
}
