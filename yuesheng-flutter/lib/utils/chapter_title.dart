// ─────────────────────────────────────────────────────────────
// chapter_title — 章节自动命名（批次88-1）
//
// 新建章节时按已有章节标题自动取名「第一章 / 第二章 / …」：
//   - 优先取已有标题中最大的「第X章」序号 +1（兼容中文/阿拉伯数字）
//   - 没有带序号的标题时，按当前章节数量 +1
// 例：已有「第一章：启程」「第三章：重逢」→ 新章「第四章」；
//     已有「引子」「序言」→ 第 3 章（3 章）→ 新章「第四章」。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';

const String _chapterTitlePattern = r'第\s*([零〇一二三四五六七八九十百千\d]+)\s*章';

/// 中文数字字符 → 数值（零/〇/一~九）
int? _chineseDigitToInt(String ch) {
  switch (ch) {
    case '零':
    case '〇':
      return 0;
    case '一':
      return 1;
    case '二':
      return 2;
    case '三':
      return 3;
    case '四':
      return 4;
    case '五':
      return 5;
    case '六':
      return 6;
    case '七':
      return 7;
    case '八':
      return 8;
    case '九':
      return 9;
  }
  return null;
}

/// 中文数字串 → 阿拉伯数（支持到「九千九百九十九」，含阿拉伯数字串）。
/// 解析失败返回 null。
int? chineseNumberToInt(String s) {
  if (s.isEmpty) return null;
  // 纯阿拉伯数字直接转换
  if (RegExp(r'^\d+$').hasMatch(s)) return int.parse(s);
  const units = {'十': 10, '百': 100, '千': 1000, '万': 10000};
  var total = 0;
  var section = 0;
  for (var i = 0; i < s.length; i++) {
    final unit = units[s[i]];
    if (unit != null) {
      total += (section == 0 ? 1 : section) * unit;
      section = 0;
    } else {
      final d = _chineseDigitToInt(s[i]);
      if (d == null) return null;
      section = d;
    }
  }
  return total + section;
}

/// 阿拉伯数 → 中文数字（1 → 一、10 → 十、21 → 二十一、123 → 一百二十三）。
String intToChineseNumber(int n) {
  if (n <= 0) return '零';
  const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  const unitChars = ['', '十', '百', '千'];
  if (n < 10) return digits[n];
  if (n < 20) {
    final rest = n % 10;
    return rest == 0 ? '十' : '十${digits[rest]}';
  }
  var result = '';
  var unitIndex = 0;
  var pendingZero = false;
  var value = n;
  while (value > 0) {
    final digit = value % 10;
    if (digit == 0) {
      if (unitIndex > 0) pendingZero = true;
    } else {
      if (pendingZero && result.isNotEmpty) result = '零$result';
      pendingZero = false;
      result = '${digits[digit]}${unitChars[unitIndex]}$result';
    }
    value ~/= 10;
    unitIndex++;
  }
  return result;
}

/// 计算新建章节的自动标题（「第X章」，X = 最大序号 + 1；无序号则按章节数 + 1）
String nextChapterTitle(List<Chapter> chapters) {
  final re = RegExp(_chapterTitlePattern);
  var maxIndex = 0;
  for (final ch in chapters) {
    final m = re.firstMatch(ch.title);
    if (m == null) continue;
    final n = chineseNumberToInt(m.group(1)!);
    if (n != null && n > maxIndex) maxIndex = n;
  }
  if (maxIndex == 0) maxIndex = chapters.length;
  return '第${intToChineseNumber(maxIndex + 1)}章';
}
