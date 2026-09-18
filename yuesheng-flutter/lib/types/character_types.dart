// ─────────────────────────────────────────────────────────────
// character_types — A6 人物知识结构数据类（批次66 B62i）
//
// 对齐 V2.0 §1.2 DOME + §3.2 L2 轻量知识结构（TKG）：
// 人物断言必须带「章节 / 时间」双维度——这是 TKG 区别于 KV 存储的根本，
// 也是「同属性不同值 → 时序矛盾」检测的数据基础。
// ─────────────────────────────────────────────────────────────

/// 人物属性断言（TKG 时间维度节点）
///
/// 例：{ attribute: '独生子女状态', value: '独生子', chapter: 3, timestamp: ... }
///     { attribute: '独生子女状态', value: '妹妹', chapter: 15, timestamp: ... }
///
/// ★ **本类没有 `copyWith`，只有逐字段手写重建** ⇒ 新增字段极易被静默丢掉。
///   `N12-F3b`（新增 [chapterSortOrder]）时全仓重建点共 **8 个**，逐点定性如下
///   （取证见 `.ai/reports/2026-09-18-N12-F3b-侦察.md §6`）：
///
///   | # | 位置 | 定性 |
///   |:--:|:--|:--|
///   | 1 | [fromDbJson] | **保真**（DB 往返，丢即一次读写后失忆） |
///   | 2 | [withStaleMark] | **保真** |
///   | 3 | [withStatus] | **保真** |
///   | 4 | [withNegative] | **保真** |
///   | 5 | [tryFromJson] | **有意不读**（AI 协议无此字段，裁定 5 不动协议） |
///   | 6 | `CharacterEditorService._appendUserAssertion` | 新建 ⇒ 填身份 |
///   | 7 | `CharacterEditorService._withStatus` | **保真**（原缺 `negative`，本批一并补） |
///   | 8 | `DiagnosisCommitter._asAiPending` | **有意重建**（置 pending），身份随填 |
///
///   ⇒ **再新增字段时，先 `grep -rn 'CharacterAssertion('` 把 8 点（含世界侧
///   3 处新建）过一遍**，逐点决定「保真 / 有意重置」并留注释。漏一点就重演
///   `fromDbJson` 注释里写的批次 1 潜伏缺陷。
class CharacterAssertion {
  /// 属性名（如 '独生子女状态' '性格' '职业'）
  final String attribute;

  /// 属性值（如 '独生子' '冷静' '捕快'）
  final String value;

  /// 断言所在章节序号 —— ★ **语义未定，勿当身份用**（`ADR-C96 §1`）：
  /// 机器链路写 `sort_order`（**身份**）、AI 抽取写**标称号**（抄自章标题）、
  /// 用户弹层写**他自己填的数** ⇒ **一列多源、读时无法分辨**。
  /// **R1′：此值原样保留、永不篡改**（用户手填输入是 R-009 的保护对象）。
  ///
  /// ⇒ 「读作身份」的地方一律改走 [chapterIdentity]。
  /// ★ **展示侧已不再读本字段**（`N12-F3b` phase 2，2026-09-18）：用户可见的章标
  /// 一律由身份载体经 `chapterLabel` 渲染，**无身份 ⇒ 不渲染**（存量行方案 `S1`）。
  /// 本字段此后只承担两件事：① **原样保留** AI/用户写入的原值（R1′ / R-009）；
  /// ② 作存量行的 [chapterIdentity] **回退源**。
  /// ⚠️ 仍有**未切换**的同族展示点（另行批次，**勿**据此认为全仓已切换）：
  /// `services/progression_builder.dart:38/43` → `widgets/setting/
  /// setting_progressions_section.dart:79`（章节演进时间轴，角色/世界观共用，站名被
  /// 侦察清单漏收）· `widgets/world/world_fact_detail_page.dart:302`（世界观断言瓦片；
  /// 实测真机 `world_fact` 断言 `chapter` 全空 ⇒ 当前无可见缺陷、亦无身份写入方）。
  final int? chapter;

  /// 断言所属章节的**身份键**（`chapters.sort_order`，0 基）—— `ADR-C96` 裁定 1。
  ///
  /// 由写入侧用 `resolveChapterIdentity` 从 [chapter] 解析后**另存**，与 [chapter]
  /// 物理分开 ⇒ 「身份」从此**可判定**。存量行为 null（AI 标称号的归属**不可能
  /// 可靠回溯**）⇒ 读取侧一律走 [chapterIdentity] 的兼容回退。
  final int? chapterSortOrder;

  /// 断言时间（unix 秒，时间维度）
  final int timestamp;

  /// C78 D-2（2026-09-16 修订 · 设定资料库第一批）：确认状态四态
  /// \pending | confirmed | rejected | superseded\。
  /// - \pending\：AI 新抽取待用户裁决（AI 协议写入默认；不参与检测/注入）
  /// - \confirmed\：用户已确认 / 存量断言（默认值，isActiveAssertion 仅认它）
  /// - ejected\：用户已否决（拒绝记忆本体；不参与检测/注入）
  /// - \superseded\：合并裁决中被取代（留库不进列表；不参与检测/注入）
  final String status;

  /// C78 D-4：来源 ai | user（用户手动修正的断言为 user，不被 AI 覆写）
  final String source;

  /// C78 D-3：正文原文摘录（非转述、非概括），供用户在角色标签页核对依据
  final String? evidence;

  /// C78 D-6：抽取时该章内容指纹，用于判定断言是否 stale
  final String? chapterHash;

  /// C78 D-6：旧版标记（章节正文已改动 → true）
  final bool stale;

  /// C78 D-7：拒绝理由（可选 chips：抽取错误/章节已改写/重复/其他；
  /// 仅 status == rejected 时可能有值，批次3 UI 写入，AI 协议不上报）
  final String? rejectReason;

  /// 设定资料库第二批：拒绝即负断言（「这扇门不能开」）。
  /// 仅 status == rejected 时可能有值（默认 false）；用户勾选后该拒绝断言
  /// 以「负断言」形态注入诊断上下文做防矛盾——垃圾处理升级为教学资产。
  /// UI 写入，AI 协议不上报（tryFromJson 不读）。
  final bool negative;

  const CharacterAssertion({
    required this.attribute,
    required this.value,
    this.chapter,
    this.chapterSortOrder,
    required this.timestamp,
    this.status = 'confirmed',
    this.source = 'ai',
    this.evidence,
    this.chapterHash,
    this.stale = false,
    this.rejectReason,
    this.negative = false,
  });

  /// 「读作身份」的**唯一入口**：优先新载体，存量行退回 [chapter]。
  ///
  /// **为什么不直接返回 null**：存量行里**机器写入的那些**，[chapter] 装的本就是
  /// 身份（`diagnosis_committer` 的 `?? chapterNo`）；若一律 null，删章钩子/重诊
  /// 判据将不再命中它们 ⇒ **凭空引入**「幽灵事实回归」这个新缺陷。
  /// 退回 ⇒ 对存量行**行为逐字不变**，对新行**口径正确**（新行必有新载体）。
  int? get chapterIdentity => chapterSortOrder ?? chapter;

  Map<String, dynamic> toJson() => {
    'attribute': attribute,
    'value': value,
    'chapter': chapter,
    'chapterSortOrder': chapterSortOrder,
    'timestamp': timestamp,
    'status': status,
    'source': source,
    'evidence': evidence,
    'chapterHash': chapterHash,
    'stale': stale,
    'rejectReason': rejectReason,
    'negative': negative,
  };

  /// DB 回读入口（C78 批次2a）——与 [tryFromJson] **严格分工，勿混用**
  ///
  /// [tryFromJson] 解析 **AI 协议 JSON**，刻意只读 evidence；本方法解析
  /// **自己写进去的 DB JSON**，必须原样还原全部字段，否则 stale 标记与
  /// 用户裁决会在一次读写往返中丢失（批次1 遗留的潜伏缺陷）。
  static CharacterAssertion fromDbJson(Map<String, dynamic> json) {
    return CharacterAssertion(
      attribute: (json['attribute'] as String?) ?? '',
      value: (json['value'] as String?) ?? '',
      chapter: (json['chapter'] as num?)?.toInt(),
      // N12-F3b 保真 #1：DB 往返必须带上身份，否则身份在一次读写后即失忆。
      chapterSortOrder: (json['chapterSortOrder'] as num?)?.toInt(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? 'confirmed',
      source: (json['source'] as String?) ?? 'ai',
      evidence: json['evidence'] as String?,
      chapterHash: json['chapterHash'] as String?,
      stale: json['stale'] == true,
      rejectReason: json['rejectReason'] as String?,
      negative: json['negative'] == true,
    );
  }

  /// C78 D-6：仅覆盖 stale / chapterHash 两个「写入路径字段」
  ///
  /// 不写全量 copyWith：[chapter] 可空，全量 copyWith 需要哨兵值来区分
  /// 「不传」与「传 null」，本批只需要改这两个字段。
  CharacterAssertion withStaleMark({String? chapterHash, bool? stale}) {
    return CharacterAssertion(
      attribute: attribute,
      value: value,
      chapter: chapter,
      chapterSortOrder: chapterSortOrder, // 保真 #2
      timestamp: timestamp,
      status: status,
      source: source,
      evidence: evidence,
      chapterHash: chapterHash ?? this.chapterHash,
      stale: stale ?? this.stale,
      rejectReason: rejectReason,
      negative: negative,
    );
  }

  /// 2026-09-16 设定资料库第一批：用户裁决写回（status + 可选拒绝理由）。
  /// 仿 [withStaleMark]：只改裁决字段，其余原样保留（R-019）。
  CharacterAssertion withStatus(String status, {String? rejectReason}) {
    return CharacterAssertion(
      attribute: attribute,
      value: value,
      chapter: chapter,
      chapterSortOrder: chapterSortOrder, // 保真 #3
      timestamp: timestamp,
      status: status,
      source: source,
      evidence: evidence,
      chapterHash: chapterHash,
      stale: stale,
      rejectReason: rejectReason ?? this.rejectReason,
      negative: negative,
    );
  }

  /// 设定资料库第二批：负断言开关写回（仿 [withStatus]，只改 negative）。
  CharacterAssertion withNegative(bool negative) {
    return CharacterAssertion(
      attribute: attribute,
      value: value,
      chapter: chapter,
      chapterSortOrder: chapterSortOrder, // 保真 #4
      timestamp: timestamp,
      status: status,
      source: source,
      evidence: evidence,
      chapterHash: chapterHash,
      stale: stale,
      rejectReason: rejectReason,
      negative: negative,
    );
  }

  /// N12-F3b：只改身份载体（仿 [withStaleMark]，其余字段原样保留）。
  CharacterAssertion withChapterSortOrder(int? chapterSortOrder) {
    return CharacterAssertion(
      attribute: attribute,
      value: value,
      chapter: chapter,
      chapterSortOrder: chapterSortOrder,
      timestamp: timestamp,
      status: status,
      source: source,
      evidence: evidence,
      chapterHash: chapterHash,
      stale: stale,
      rejectReason: rejectReason,
      negative: negative,
    );
  }

  /// 宽松解析：属性名/值缺失或为空 → 跳过该条（保守，不抛出）
  static CharacterAssertion? tryFromJson(Map<String, dynamic> json) {
    final attribute = json['attribute'];
    final value = json['value'];
    if (attribute is! String || attribute.isEmpty) return null;
    if (value is! String || value.isEmpty) return null;
    return CharacterAssertion(
      attribute: attribute,
      value: value,
      chapter: (json['chapter'] as num?)?.toInt(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      // C78 D-3：仅 evidence 从协议 JSON 读取（AI 唯一上报的新字段）；
      // status/source/chapterHash/stale 由写入路径填值，此处不读，靠默认值兜底。
      // N12-F3b 有意不读 #5：协议里**没有**身份字段（`ADR-C96` 裁定 5「本期不动协议」）
      // ⇒ 身份由 `DiagnosisCommitter` 在落库前解析填入，不从这里来。
      evidence: json['evidence'] as String?,
    );
  }
}
