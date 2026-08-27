// ─────────────────────────────────────────────────────────────
// compression_protocol — 显式压缩协议（FT-23，标准/高级模式压缩）
//
// 依据：架构真源 FT-23 — 过度压缩高级响应。高级学员请求压缩诊断，
//   结果只给"结构有问题"无细节。借鉴：标准/高级模式压缩。
//   现有有 standard/concise/detailed 颗粒度但缺显式压缩协议——
//   压缩时保留什么/裁剪什么的明确规则。
//
// 本模块为显式压缩协议基础设施，不修改现有 chat_service（向后兼容）。
// 未来在 prompt 注入中按级别追加压缩规则，让 LLM 知道压缩时保留什么。
//
// 三档压缩级别：
//   1. concise（压缩）：保留三要素（问题点+改善方向+证据），裁剪铺垫/重复
//   2. standard（标准）：保留三要素 + 简短铺垫
//   3. detailed（详细）：全量输出
//
// 核心原则：压缩不可裁剪三要素——问题点、改善方向、证据
// ─────────────────────────────────────────────────────────────

/// 压缩级别（对应现有 standard/concise/detailed 颗粒度）
enum CompressionLevel {
  /// 压缩：保留三要素，裁剪铺垫/重复
  concise('concise'),

  /// 标准：保留三要素 + 简短铺垫
  standard('standard'),

  /// 详细：全量输出
  detailed('detailed');

  final String value;
  const CompressionLevel(this.value);

  /// 从字符串解析（防御性：未知值降级为 standard）
  static CompressionLevel fromString(String? value) {
    switch (value) {
      case 'concise':
        return CompressionLevel.concise;
      case 'detailed':
        return CompressionLevel.detailed;
      default:
        return CompressionLevel.standard;
    }
  }
}

/// 压缩规则（保留要素 + 可裁剪要素）
class CompressionRule {
  /// 必须保留的要素（压缩不可裁剪的核心信息）
  final List<String> retainElements;

  /// 可以裁剪的要素（压缩时可省略的内容）
  final List<String> droppableElements;

  /// 铺垫允许的最大行数（concise=0 / standard=2 / detailed=不限制）
  final int? maxPreambleLines;

  const CompressionRule({
    required this.retainElements,
    required this.droppableElements,
    this.maxPreambleLines,
  });

  /// 三要素（所有级别都必须保留）
  static const List<String> kCoreElements = [
    '问题点', // 具体什么问题
    '改善方向', // 怎么改
    '证据', // 原文片段/定位
  ];

  /// 可裁剪要素（仅 concise 级别裁剪）
  static const List<String> kDroppableElements = ['铺垫/寒暄', '重复解释', '详细理论背景'];
}

/// 根据压缩级别返回压缩规则（纯函数，可单测）
///
/// 三档级别对应不同规则：
///   concise：保留三要素 + 裁剪铺垫/重复/理论背景 + 铺垫 0 行
///   standard：保留三要素 + 简短铺垫（≤2 行）
///   detailed：全量输出（不裁剪）
CompressionRule getCompressionRule(CompressionLevel level) {
  switch (level) {
    case CompressionLevel.concise:
      return const CompressionRule(
        retainElements: CompressionRule.kCoreElements,
        droppableElements: CompressionRule.kDroppableElements,
        maxPreambleLines: 0,
      );
    case CompressionLevel.standard:
      return const CompressionRule(
        retainElements: CompressionRule.kCoreElements,
        droppableElements: [], // standard 不裁剪
        maxPreambleLines: 2,
      );
    case CompressionLevel.detailed:
      return const CompressionRule(
        retainElements: CompressionRule.kCoreElements,
        droppableElements: [], // detailed 不裁剪
        maxPreambleLines: null, // 不限制
      );
  }
}

/// 生成压缩协议指令文本（用于 prompt 注入）
///
/// 让 LLM 知道当前压缩级别下保留什么、裁剪什么
String buildCompressionDirective(CompressionLevel level) {
  final rule = getCompressionRule(level);
  final buffer = StringBuffer();

  buffer.writeln('--- 压缩协议（${level.value}）---');

  if (level == CompressionLevel.detailed) {
    buffer.writeln('当前为详细模式：全量输出，不裁剪。');
    return buffer.toString();
  }

  buffer.writeln('必须保留（不可裁剪）：');
  for (final element in rule.retainElements) {
    buffer.writeln('- $element');
  }

  if (rule.droppableElements.isNotEmpty) {
    buffer.writeln('可以裁剪（压缩时省略）：');
    for (final element in rule.droppableElements) {
      buffer.writeln('- $element');
    }
  }

  if (rule.maxPreambleLines != null) {
    buffer.writeln('铺垫/寒暄允许行数：≤${rule.maxPreambleLines}');
    if (rule.maxPreambleLines == 0) {
      buffer.writeln('（concise 模式：零铺垫，直接给三要素）');
    }
  }

  return buffer.toString();
}
