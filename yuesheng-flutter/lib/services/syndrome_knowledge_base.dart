// ─────────────────────────────────────────────────────────────
// L3 症候知识库 — 复刻 yuesheng-android/src/assets/skills/syndrome-diagnosis.ts
// 内容 100% 逐字保留（2026-08-08 批次 22 步骤② 搬运）
//   kSyndromeIndexContent  → L2 层 syndrome-diagnosis-index 索引
//   kSyndromeManualContent → L3 检索源（按症候 ID 提取完整定义）
// b9 批次28：表格行（索引表/类型速查/技法映射）与头部计数改从注册表派生，
//           渲染输出与手写逐字一致（四库一致性测试兜底）
// ─────────────────────────────────────────────────────────────

import 'syndrome_registry.dart';
import 'technique_knowledge_base.dart'; // techniqueNameOf

// ─── P3 数据分片（数据/逻辑分离；知识文本在 part 文件）───
part 'syndrome_kb_content.dart';
part 'syndrome_kb_content_manual_1.dart';
part 'syndrome_kb_content_manual_2.dart';
part 'syndrome_kb_content_manual_3.dart';
part 'syndrome_kb_content_manual_4.dart';
part 'syndrome_kb_content_manual_5.dart';
part 'syndrome_kb_content_manual_6.dart';

/// 从完整手册中按症候 ID 提取单个症候的完整定义（复刻 RN extractSyndromeSection）
String _extractSyndromeSection(String raw, String id) {
  final pattern = RegExp('### $id ');
  final match = pattern.firstMatch(raw);
  if (match == null) return '';
  final startIdx = match.start;
  // 结束边界：下一个三级段（### P0XX）或二级段（## 章节标题），取更早者。
  // 修复：最后一个症候段（如 P034）之后若只有 `## ` 二级标题，旧逻辑会落到
  // 文件末尾，把手册尾部非症候内容（类型速查/诊断规范/重叠规则）一起吞进 L3 详情。
  final nextH3 = raw.indexOf('\n### ', startIdx + 1);
  final nextH2 = raw.indexOf('\n## ', startIdx + 1);
  var endIdx = raw.length;
  if (nextH3 != -1) endIdx = nextH3;
  if (nextH2 != -1 && nextH2 < endIdx) endIdx = nextH2;
  return raw.substring(startIdx, endIdx).trim();
}

/// L3 检索：获取指定症候的完整详细内容（复刻 RN getSyndromeContent）
String getSyndromeContent(List<String> syndromeIds) {
  final sections = syndromeIds
      .map((id) => _extractSyndromeSection(kSyndromeManualContent, id))
      .where((s) => s.isNotEmpty)
      .toList();
  if (sections.isEmpty) return '';
  const header =
      '## 活跃症候详细定义（系统注入，学员不可见）\n\n以下是你当前锁定诊断的症候的完整定义。请严格参照其中的判断原则、例外情况和诊断锚点进行后续诊断和训练。\n\n---\n\n';
  return header + sections.join('\n\n---\n\n');
}

// ── b9 批次28：症候库表格行渲染（输出与手写逐字一致）──────────

/// 索引表「映射表」行：| ID | 关键词 | 一句话描述 |
String _syndromeIndexRow(SyndromeRecord s) =>
    '| ${s.id} | ${s.keyword} | ${s.oneLine} |';

/// 类型速查表行：| 类型 | ID 症候名(v1ActionName ?? name) | 核心问题 |
String _typeLookupRow(SyndromeRecord s) =>
    '| ${s.type.value} | ${s.id} ${s.v1ActionDisplayName} | ${s.typeLine} |';

/// 类型速查表：按类型分组（枚举声明序），组内按注册表 ID 升序，
/// 与手写表逐字一致（motivation → expressive → structural → commercial）。
/// 前置换行：前接 _syndromeManualBody6 的表头分隔行（无尾换行），
/// 缺此行首行（P009）会与分隔行粘连，导致类型速查行数少 1（测试 #12 曾捕获）。
String _typeLookupTable() {
  final buffer = StringBuffer();
  for (final t in SyndromeType.values) {
    for (final s in kSyndromeRegistry.where((s) => s.retired != true)) {
      if (s.type == t) buffer.writeln(_typeLookupRow(s));
    }
  }
  return '\n' + buffer.toString().trimRight();
}

/// 手册内嵌技法映射表行：| ID 症候名(shortName) | 首选技法 技法名 |
String _techniqueMapRow(SyndromeRecord s) {
  final t = s.techniques.first;
  return '| ${s.id} ${s.shortName} | $t ${techniqueNameOf(t) ?? ''} |';
}
