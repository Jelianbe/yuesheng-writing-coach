// ─────────────────────────────────────────────────────────────
// diagnosis_ghost_guard — V-01 R-009 代写段守卫（真降级：改写 cleaned）
//
// 【为什么从 DiagnosisValidator 迁出】
//   `diagnosis_validator.dart` 是 776 行的存量超限文件，门禁 5 的文件级判据
//   （≤300 行，基线模式**变胖容差 0 行**）下，A1 的相邻去重逻辑一旦内联就要红。
//   本块是**纯函数 + 三个私有常量**（零 IO、零副作用、唯一的公共依赖是
//   `NlFix` / `DiagnosisLimits`），整体迁出即净减，且判据可继续被外部单测覆盖。
//
// 【判据：同时满足才拦，宁漏勿伤】
//   1. 段落 > [_kRewriteThreshold] 字（80）；
//   2. 无引号（"「『）—— 引用学员原文/例句不算代写；
//   3. 无教练元话语（[_kCoachMetaMarkers]）—— 长段点评学员文本不算代写。
//   命中即把整段替换为 [_kV01Downgrade]，并产出 V-01 fix 供观测。
//
// 【A1（2026-11-16）：相邻降级块去重】
//   改造前 `split('\n').map(...).join()` 对每个命中行各自替换、**无相邻去重** ⇒
//   模型连续输出两段长代写（导出 `740d27bf` 实测 4 次、`a54e43a9` 2 次）时，
//   用户会看到两个**一字不差**的占位符块紧挨着，像是系统坏了。
//   去重规则（只压输出，不动观测）：连续命中的多行 → 只保留**第一个**
//   [_kV01Downgrade] 块，其余命中的行整行丢弃；`fixes` 仍**逐条全记**
//   （观测口径不变 —— 抹掉 fix 会让「模型代写了几段」这个读数失真）。
//   段之间只要夹了一个非命中行就不算相邻，各自保留。
//
// 【零文案改动】
//   [_kV01Downgrade] 常量**一字未动**（含全角括号与标点）⇒ 不触 R-027，
//   历史按该常量字符串计数的受控组读数保持可比。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/config/shared_constants.dart' show DiagnosisLimits;
import 'package:writingcoach/contracts/diagnosis_capability.dart' show NlFix;

/// V-01 触发阈值：段落长度 > 该值才考虑降级（80 字）。
const int _kRewriteThreshold = 80;

/// V-01 教练元话语标记：段落命中即说明在「点评学员文本」而非「替学员成文」→ 不拦。
///
/// 指示词用明确复合形式（这句/这段/这里…），**不裸匹配「这一」**——否则
/// 叙述里的「这一次/这一刻」会被误判成点评（C123 实测 P1 误伤）。
final RegExp _kCoachMetaMarkers = RegExp(
  r'这里|这[一]?句|这[一]?段|这[一]?章|上文|原文|你的|你写的|'
  r'问题(?:在于|是)|因为|所以|对比|建议|可以(?:再|试着|多|少)|'
  r'为什么|节奏|动机|镜头感|比喻|铺垫|转折',
);

/// V-01 降级文案（R-009 合规）：不替学员落笔、不贴标签，改为邀请其自己写。
///
/// ★ R-027 受控：**逐字不可改**（含全角括号与句末句号）。
const String kV01Downgrade = '（这段我不替你落笔：这一段请你自己先写一稿，写完我们一起逐句回看。）';

/// V-01 代写段守卫：命中段落整段替换为 [kV01Downgrade]，连续命中只输出一块。
///
/// [cleaned] 是已过 V-02 等前置清洗的展示文本。
/// 返回改写后的文本 + 逐条 fix（fix 的条数 = 命中段数，**不因去重而减少**）。
({String text, List<NlFix> fixes}) applyGhostRewriteGuard(String cleaned) {
  final fixes = <NlFix>[];
  final outLines = <String>[];
  // 上一个**输出行**是否是降级块 —— 用它判相邻（而不是判上一个输入行）。
  var prevWasDowngrade = false;
  for (final line in cleaned.split('\n')) {
    final para = line.trim();
    final hit =
        para.length > _kRewriteThreshold &&
        !para.contains('"') &&
        !para.contains('「') &&
        !para.contains('『') &&
        !_kCoachMetaMarkers.hasMatch(para);
    if (!hit) {
      outLines.add(line);
      prevWasDowngrade = false;
      continue;
    }
    // 观测不丢：命中一次记一条 fix（与改造前逐行记的行为一致）。
    fixes.add(
      NlFix(
        type: 'V-01',
        original: para.length > DiagnosisLimits.rewritePreviewLength
            ? '${para.substring(0, DiagnosisLimits.rewritePreviewLength)}...'
            : para,
        replacement: kV01Downgrade,
      ),
    );
    if (prevWasDowngrade) continue; // 相邻重复块：不再输出第二个
    outLines.add(kV01Downgrade);
    prevWasDowngrade = true;
  }
  return (text: outLines.join('\n'), fixes: fixes);
}
