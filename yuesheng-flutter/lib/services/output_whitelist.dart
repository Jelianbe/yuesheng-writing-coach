// ─────────────────────────────────────────────────────────────
// output_whitelist — 输出侧关键参数白名单校验（L3 档）
//
// 背景（R-027 人工确认）：LLM 结构化输出的枚举参数（severity 等）
// 可能越界（"L4"、"high"、"严重"），污染下游判定与持久化。
// 本文件提供通用白名单归一化：
//   - 命中白名单（大小写不敏感、容忍首尾空白）→ 归一化为白名单项
//   - 未命中 → 返回 null（由调用方决定降级：丢弃该条/回退默认值）
//
// 与诊断主链 validateDiagnosisOutput（只观测不拦截哲学）互补：
// 本文件服务中间产物（如分块诊断 notes）——越界即剔除，诚实不伪造。
// ─────────────────────────────────────────────────────────────

/// 通用白名单归一化：raw 命中 [allowed] 之一（不区分大小写、
/// 容忍首尾空白）→ 返回白名单中的规范形态；否则返回 null。
String? whitelistNormalize(Object? raw, List<String> allowed) {
  if (raw == null) return null;
  final text = raw.toString().trim().toLowerCase();
  if (text.isEmpty) return null;
  for (final a in allowed) {
    if (text == a.toLowerCase()) return a;
  }
  return null;
}

/// 严重度白名单（L1/L2/L3）。
const List<String> _severityAllowed = ['L1', 'L2', 'L3'];

/// 严重度归一化：`L1|L2|L3`（大小写不敏感）→ 大写规范形态；
/// 越界（"L4"、"high"、"严重"）→ null。
String? normalizeSeverity(Object? raw) =>
    whitelistNormalize(raw, _severityAllowed);

/// 症候 ID 格式白名单：`P` + 至少 1 位数字（如 P003/P21）。
/// 格式不符（注入形 ID、空串）→ null。
String? normalizeSyndromeId(Object? raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  if (!RegExp(r'^P\d+$', caseSensitive: false).hasMatch(text)) return null;
  return text.toUpperCase();
}

/// 布尔参数白名单归一化：true/false/1/0/yes/no → bool。
/// 无法识别 → null。
bool? normalizeBooleanFlag(Object? raw) {
  if (raw == null) return null;
  switch (raw.toString().trim().toLowerCase()) {
    case 'true' || '1' || 'yes' || 'y':
      return true;
    case 'false' || '0' || 'no' || 'n':
      return false;
    default:
      return null;
  }
}
