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

  const CharacterAssertion({
    required this.attribute,
    required this.value,
    this.chapter,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'attribute': attribute,
    'value': value,
    'chapter': chapter,
    'timestamp': timestamp,
  };

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
    );
  }
}
