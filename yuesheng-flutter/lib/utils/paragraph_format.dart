// ─────────────────────────────────────────────────────────────
// paragraph_format — 段落格式批量处理（批次88-4）
//
// 配合「自动首行缩进 / 段间空行」排版开关，对已有全文执行
// 批量应用 / 清除。输入时的自动补缩进/空行走 TextInputFormatter
// （ParagraphFormatFormatter），本文件只做"存量文本"处理。
// ─────────────────────────────────────────────────────────────

/// 首行缩进单位：两个全角空格（中文排版惯例）
const String paragraphIndent = '\u3000\u3000';

/// 是否为缩进前缀（全角空格或半角空格开头）
bool _isIndented(String segment) =>
    segment.startsWith('\u3000') || segment.startsWith(' ');

/// 为每个非空段首补首行缩进（已缩进/空段跳过）
String indentParagraphs(String text) {
  final parts = text.split('\n');
  for (var i = 0; i < parts.length; i++) {
    final seg = parts[i];
    if (seg.isNotEmpty && !_isIndented(seg)) {
      parts[i] = '$paragraphIndent$seg';
    }
  }
  return parts.join('\n');
}

/// 移除每段开头的缩进（全角/半角空格前缀，至少移除两个全角空格或任意空格）
String removeParagraphIndent(String text) {
  final parts = text.split('\n');
  for (var i = 0; i < parts.length; i++) {
    parts[i] = parts[i].replaceFirst(RegExp(r'^[\u3000 ]+'), '');
  }
  return parts.join('\n');
}

/// 段落间加空行：压缩已有连续换行后，在每个换行后补一个空行
String addBlankLineBetween(String text) {
  final normalized = text.replaceAll(RegExp(r'\n{2,}'), '\n');
  if (normalized.isEmpty) return normalized;
  return normalized.replaceAll('\n', '\n\n');
}

/// 移除段间空行：连续换行压缩为单个换行
String removeBlankLineBetween(String text) {
  return text.replaceAll(RegExp(r'\n{2,}'), '\n');
}
