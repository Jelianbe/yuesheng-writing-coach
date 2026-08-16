// ─────────────────────────────────────────────────────────────
// time_format — 相对时间格式化（复刻 RN utils/time.ts formatRelativeTime）
//
// 规则：
//   <60s   → 刚刚
//   <60min → N 分钟前
//   <24h   → N 小时前
//   <7d    → N 天前
//   否则   → yyyy-MM-dd
// ─────────────────────────────────────────────────────────────

/// 秒级时间戳 → 相对时间文案
String formatRelativeTime(int timestampSec, {DateTime? now}) {
  final nowLocal = now ?? DateTime.now();
  final time = DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000);
  final diff = nowLocal.difference(time);

  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';

  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '${time.year}-$month-$day';
}
