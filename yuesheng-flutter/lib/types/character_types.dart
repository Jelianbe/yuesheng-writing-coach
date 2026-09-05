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
class CharacterAssertion {
  /// 属性名（如 '独生子女状态' '性格' '职业'）
  final String attribute;

  /// 属性值（如 '独生子' '冷静' '捕快'）
  final String value;

  /// 断言所在章节序号（sort_order，时间维度；未标注为 null）
  final int? chapter;

  /// 断言时间（unix 秒，时间维度）
  final int timestamp;

  /// C78 D-2：确认状态 confirmed | rejected（无 pending，存量断言默认 confirmed）
  final String status;

  /// C78 D-4：来源 ai | user（用户手动修正的断言为 user，不被 AI 覆写）
  final String source;

  /// C78 D-3：正文原文摘录（非转述、非概括），供用户在角色标签页核对依据
  final String? evidence;

  /// C78 D-6：抽取时该章内容指纹，用于判定断言是否 stale
  final String? chapterHash;

  /// C78 D-6：旧版标记（章节正文已改动 → true）
  final bool stale;

  const CharacterAssertion({
    required this.attribute,
    required this.value,
    this.chapter,
    required this.timestamp,
    this.status = 'confirmed',
    this.source = 'ai',
    this.evidence,
    this.chapterHash,
    this.stale = false,
  });

  Map<String, dynamic> toJson() => {
    'attribute': attribute,
    'value': value,
    'chapter': chapter,
    'timestamp': timestamp,
    'status': status,
    'source': source,
    'evidence': evidence,
    'chapterHash': chapterHash,
    'stale': stale,
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
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? 'confirmed',
      source: (json['source'] as String?) ?? 'ai',
      evidence: json['evidence'] as String?,
      chapterHash: json['chapterHash'] as String?,
      stale: json['stale'] == true,
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
      timestamp: timestamp,
      status: status,
      source: source,
      evidence: evidence,
      chapterHash: chapterHash ?? this.chapterHash,
      stale: stale ?? this.stale,
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
      evidence: json['evidence'] as String?,
    );
  }
}
