/// Skill 注册表 — 所有 skill 内容的单一来源
///
/// 真源：yuesheng-android/src/assets/skills/*.ts（meta + content 模式）
/// 复刻策略：直接搬运 content 文本，元数据简化为 id + estimatedTokens
///
/// 包含：
///   - L1 常驻层 8 个核心 skill
///   - 3 个态度档位 skill（doubao/yuesheng/sensei）
///   - L2 按需层 skill（beginner/diagnosis/training/advanced/outline 各组）
///   - L2 虚拟索引 skill（syndrome-diagnosis-index / technique-library-index，
///     索引内容来自 L3 知识库文件，完整知识由 L3 检索注入）
library;

import 'package:writingcoach/types/teaching_types.dart';

import 'syndrome_knowledge_base.dart';
import 'syndrome_registry.dart';
import 'technique_knowledge_base.dart';

// ─── P3 数据分片（数据/逻辑分离；Skill 常量在各 skills_*.dart part 文件）──
// 二级拆分（R-019 ≤300 行）：超限分片的 Skill 对象字面量进一步拆至 skills_*_pN.dart
part 'skills_l1_core.dart';
part 'skills_l1_core_p1.dart';
part 'skills_l1_core_p2.dart';
part 'skills_l1_core_p3.dart';
part 'skills_l1_core_p4.dart';
part 'skills_attitude.dart';
part 'skills_beginner.dart';
part 'skills_beginner_p1.dart';
part 'skills_beginner_p2.dart';
part 'skills_beginner_p3.dart';
part 'skills_beginner_p4.dart';
part 'skills_beginner_p5.dart';
part 'skills_beginner_p6.dart';
part 'skills_beginner_p7.dart';
part 'skills_beginner_p8.dart';
part 'skills_beginner_p9.dart';
part 'skills_diagnosis.dart';
part 'skills_diagnosis_p1.dart';
part 'skills_diagnosis_p2.dart';
part 'skills_diagnosis_p3.dart';
part 'skills_training.dart';
part 'skills_training_p1.dart';
part 'skills_training_p2.dart';
part 'skills_training_p3.dart';
part 'skills_training_p4.dart';
part 'skills_training_p5.dart';
part 'skills_advanced_outline.dart';
part 'skills_advanced_outline_p1.dart';
part 'skills_advanced_outline_p2.dart';
part 'skills_advanced_outline_p3.dart';
part 'skills_advanced_outline_p4.dart';
part 'skills_advanced_outline_p5.dart';
part 'skills_advanced_outline_p6.dart';
part 'skills_advanced_outline_p7.dart';
part 'skills_reply_voice.dart';

// ─── Skill 元数据与实体 ───────────────────────────────────────

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
class SkillMeta {
  final String id;
  final String
  group; // core | attitude | coaching | diagnosis | training | etc.
  final int estimatedTokens;

  /// 正文表述风格（E.8）。必填——新增 skill 时强制显式声明档位，
  /// 不给默认值：默认值会让漏标静默滑过，与 N19 的教训同源。
  final PromptStyle promptStyle;

  const SkillMeta({
    required this.id,
    required this.group,
    required this.estimatedTokens,
    required this.promptStyle,
  });
}

/// Skill 实体
class Skill {
  final SkillMeta meta;
  final String content;

  /// 按教学阶段裁剪内容的钩子（Phase 3 A 组：状态驱动裁剪）。
  ///
  /// 为 null 时退化为完整 [content]（与历史行为一致）。
  /// 切片必须返回 [content] 的原文子串，确保零编辑漂移。
  final String Function(TeachingPhase phase)? contentForPhase;

  const Skill({
    required this.meta,
    required this.content,
    this.contentForPhase,
  });
}

// ─── Skill 注册表 ─────────────────────────────────────────────

/// 所有已注册的 skill（L1 核心 + 3 态度 + L2 按需层）
///
/// L2 按需层 skill 分五组：beginner/diagnosis/training/advanced/outline。
/// 2026-08-08 批次 17 起按组搬运（真源：yuesheng-android/src/assets/skills/*.ts）。
final Map<String, Skill> skillRegistry = {
  // L1 常驻层
  'core-iron-triangle': _coreIronTriangle,
  'core-product-identity': _coreProductIdentity,
  'writing-anchors': _writingAnchors,
  'teaching-strategy': _teachingStrategy,
  'phase-mapper': _phaseMapper,
  'scenario-rules': _scenarioRules,
  'validation-rules': _validationRules,
  'teaching-modes': _teachingModes,
  // 批次65：回复语气（教练口语化去 AI 味，提炼 humanizer-zh）
  'reply-voice': _replyVoice,
  // 态度档位
  'attitude-doubao': _attitudeDoubao,
  'attitude-yuesheng': _attitudeYuesheng,
  'attitude-sensei': _attitudeSensei,
  // L2 按需层 — beginner 组（2026-08-08 批次 17）
  'beginner-path': _beginnerPath,
  'gap-detector': _gapDetector,
  'coaching-rhythm': _coachingRhythm,
  'narrative-design': _narrativeDesign,
  'plot-design': _plotDesign,
  'writer-psychology': _writerPsychology,
  // L2 按需层 — diagnosis 组（2026-08-08 批次 17）
  'reader-awareness': _readerAwareness,
  'genre-guide': _genreGuide,
  'writing-style': _writingStyle,
  'diagnosis-confirmation': _diagnosisConfirmation,
  'feedback-cognition': _feedbackCognition,
  // L2 按需层 — training 组（2026-08-08 批次 17）
  'training-loop-v2': _trainingLoopV2,
  'training-templates-index': _trainingTemplatesIndex,
  'training-evaluation-v2': _trainingEvaluationV2,
  'text-surgery-v2': _textSurgeryV2,
  'coaching-actions-v2': _coachingActionsV2,
  'demonstration': _demonstration,
  'comparison': _comparison,
  // 新训练形态（2026-08-11 批次 17：限时重写/范文对照改写）
  'timed-rewrite': _timedRewrite,
  'model-rewrite': _modelRewrite,
  'revision-methodology': _revisionMethodology,
  // L2 按需层 — advanced 组（2026-08-08 批次 17）
  'advanced-phases': _advancedPhases,
  // L2 按需层 — outline 组（2026-08-08 批次 17）
  'outline-diagnosis': _outlineDiagnosis,
  // L2 虚拟索引 skill（2026-08-08 批次 22 步骤②：索引内容注册，完整知识走 L3 检索）
  'syndrome-diagnosis-index': Skill(
    meta: SkillMeta(
      id: 'syndrome-diagnosis-index',
      group: 'diagnosis',
      estimatedTokens: 1800,
      promptStyle: PromptStyle.strict,
    ),
    content: kSyndromeIndexContent,
  ),
  'technique-library-index': Skill(
    meta: SkillMeta(
      id: 'technique-library-index',
      group: 'training',
      estimatedTokens: 900,
      promptStyle: PromptStyle.free,
    ),
    content: kTechniqueIndexContent,
  ),
};

/// 获取指定 ID 的 skill。不存在返回 null。
Skill? getSkill(String id) => skillRegistry[id];

// ── b9 批次30：注册表行渲染（输出与手写逐字一致）────────────────

/// 症候 ID 范围（如 P003-P031），提示文本派生用
String get _syndromeIdRange => '${kSyndromeIds.first}-${kSyndromeIds.last}';

/// 动作精简名真源（A001-A016，动作名稳定；动作映射表渲染取用）
const Map<String, String> kActionShortNames = {
  'A001': '缩小范围',
  'A002': '回归主角',
  'A003': '五问法',
  'A004': '现实锚点',
  'A005': '动作链',
  'A006': '感官全开',
  'A007': '一句话冲突',
  'A008': '对话瘦身',
  'A009': '节奏变速',
  'A010': '角色盲写',
  'A011': '场景裁剪',
  'A012': '伏笔追踪',
  'A013': '情节复盘',
  'A014': '情感校准',
  'A015': '人设审查',
  'A016': '高频词清扫',
};

/// 动作精简名查询（真源：kActionShortNames）。未知 ID 返回 null。
String? actionNameOf(String? id) => id == null ? null : kActionShortNames[id];

/// 动作映射表行（v1/v2 共用格式）：
///   | 症候 | 推荐动作 | 可选动作 |
///   无备选 → '—'；多备选 → 'A005 动作链 / A009 节奏变速'
String _actionRow(SyndromeRecord s, String displayName) {
  final acts = s.actions;
  final primary = '${acts.first} ${actionNameOf(acts.first) ?? ''}';
  final alt = acts.length <= 1
      ? '—'
      : acts.sublist(1).map((a) => '$a ${actionNameOf(a) ?? ''}').join(' / ');
  return '| ${s.id} $displayName | $primary | $alt |';
}

/// v2 动作映射（coaching-actions-v2）行：症候列用 v2ActionName ?? shortName
String _v2ActionRow(SyndromeRecord s) => _actionRow(s, s.v2ActionDisplayName);

/// maxAttempts 分组 ID 列表（如 P003/P007/...），组内按注册表 ID 升序
String _maxAttemptsIds(MaxAttemptsGroup group) => kSyndromeRegistry
    .where((s) => s.group == group && s.retired != true)
    .map((s) => s.id)
    .join('/');

/// training-templates-index 行：| ID | 症候名 | 核心本质一句话 |
/// 症候名默认 shortName；P022 现有文本为「重复用词/基础语病症」（带"症"字），特例保留
String _trainingIndexRow(SyndromeRecord s) {
  final name = s.id == 'P022' ? '重复用词/基础语病症' : s.shortName;
  return '| ${s.id} | $name | ${s.trainingLine} |';
}
