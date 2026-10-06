// ─────────────────────────────────────────────────────────────
// skill_types — Skill 元数据类型（PromptStyle / SkillMeta / Skill）
//
// ★ B6（2026-10-06）：从 skill_registry.dart 抽出，零行为变更。
//
// 抽出动机（消除「类型定义埋在数据分片宿主里」的结构性耦合）：
//   宿主 `skill_registry.dart` 同时是**类型定义处**与**34 个 part 分片的
//   宿主**，而 part 成员靠共享它的作用域直接用 `Skill` / `SkillMeta` /
//   `PromptStyle` ⇒ 类型无处可去、无独立测试面、也无法被非 part 的
//   library 复用。抽出后宿主与未来的独立 library 都能单向 import 本文件。
//
//   本文件是**将来任何 `part` 消解的必要前置**：不先把三类型抽出来，
//   拆出的 library 就得 import 宿主拿类型、而宿主又要 import 它们
//   ⇒ 双向 import 即循环依赖，门禁 3（`check_circular.py`，失败关闭）
//   会直接变红。
//
//   ⚠️ **`part` 消解本身当前不可做**（详见宿主同处的说明注释）：
//   门禁 11 的 A4 判据要求「A 类文件必须真的是 part 家族成员」、
//   G1 要求「分片数不得少于 minPartCount=49」，与本批目标方向相反。
//
// 内容/逻辑分离（沿用 P3 批次既有约定）：本文件只放**类型定义**，
// 不含任何 Skill 实例常量（那些仍在 skills_*.dart 分片里）。
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';

/// Skill 正文的表述风格标签（E.8）
///
/// 决定 skill 正文里的示例 / 话术应当被当作「格式照做」还是「参考自组织」。
/// 服务于 E.3 元规则第 6 条——让「示例不是格式」可被机器识别，
/// 供 E.6 Prompt Lint 与「内容增减规范」消费。
///
/// 判据（改动档位前先对照）：
/// - strict：正文含输出契约（格式模板 / JSON 字段说明 / 协议）
///   或铁律级硬约束清单，须逐条执行。示例若存在，仅用于说明格式。
/// - guided：正文含示例话术或示例文本，且示例为参考——
///   说法由教练自行组织。文本内通常已自述「不是句式模板 / 不是台词 /
///   说法自定 / 不照念 / 由你自己组织」。
/// - free：只有原则、底线或索引，无输出契约、无可照搬的示例。
///
/// 两条使用约定（E.8(a) 落地时实测得出，改动档位前先看）：
///
/// 1. **档位是整体定性，不是逐条判决。** 一个 skill 完全可以「约束是硬的、
///    示例是软的」——典型如 validation-rules：明写「10 条是硬性约束，违反
///    任何一条都必须重写回复」，同时又写「❌/✅ 都是示例，不是必须套用的
///    句式」。此时按主体约束强度定为 strict，示例的软性由正文自述保证。
/// 2. **正文的局部自述优先级高于档位。** 若正文某处已明说「以下是示例，不是
///    模板」（advanced-phases / feedback-cognition / gap-detector 等都有），
///    以正文为准——档位供机器粗筛，局部自述供模型精判。
enum PromptStyle {
  /// 硬约束：输出契约或铁律，须逐条执行。
  strict,

  /// 参考示例：示例不是格式，说法自行组织。
  guided,

  /// 纯原则：无契约、无示例。
  free,
}

/// Skill 元数据
///
/// Step 1（2026-09-14）：删除手写 `estimatedTokens` 字段。原字段在 `lib/`、
/// `test/`、`tool/`、`scripts/` 中**零读取**（只写不读的死数据），且 37 处
/// 手写值长期失真（多处自承「台账失真」）。体积口径改为由
/// `Skill.estimatedTokens` 从 `content` 派生，与 dispatcher 同源。
class SkillMeta {
  final String id;
  final String
  group; // core | attitude | coaching | diagnosis | training | etc.

  /// 正文表述风格（E.8）。必填——新增 skill 时强制显式声明档位，
  /// 不给默认值：默认值会让漏标静默滑过，与 N19 的教训同源。
  final PromptStyle promptStyle;

  const SkillMeta({
    required this.id,
    required this.group,
    required this.promptStyle,
  });
}

/// Skill 实体
class Skill {
  final SkillMeta meta;
  final String content;

  /// 本 skill 正文的估算 token 数（Step 1：由 [content] 派生，不再手写）。
  ///
  /// 口径 = `content.length`（UTF-16 码元数）× `TokenEstimate.charToTokenRatio`
  /// （= 1.0，B26 中文口径），与 `skill_dispatcher` 的 `_estimateTokens` 同源。
  /// 派生值可用锚点快照 `test/snapshots/skill_prompt_anchor.json` 的
  /// `skillContent[id].len` 逐 id 对账。
  int get estimatedTokens => content.length;

  /// 按教学阶段裁剪内容的钩子（Phase 3 A 组：状态驱动裁剪）。
  ///
  /// 为 null 时退化为完整 [content]（与历史行为一致）。
  /// 切片必须返回 [content] 的原文子串，确保零编辑漂移。
  /// 按教学阶段裁剪内容。签名 `(phase, content)`——[content] 即本 Skill 的
  /// 完整原文，由 dispatcher 传入；这样裁剪逻辑可与其他 library 解耦
  /// （P3-R3：part 私有的正文常量跨库不可见，只能由调用方把原文送来）。
  final String Function(TeachingPhase phase, String content)? contentForPhase;

  const Skill({
    required this.meta,
    required this.content,
    this.contentForPhase,
  });
}
