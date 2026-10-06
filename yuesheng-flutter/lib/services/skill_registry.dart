/// Skill 注册表 — 所有 skill 内容的单一来源
///
/// 真源：yuesheng-android/src/assets/skills/*.ts（meta + content 模式）
/// 复刻策略：直接搬运 content 文本，元数据简化为 id + group + promptStyle
/// （体积不再手写：见 `Skill.estimatedTokens`，由 `content` 派生）
///
/// 包含：
///   - L1 常驻层 8 个核心 skill
///   - 3 个态度档位 skill（温柔语气/yuesheng/sensei）
///   - L2 按需层 skill（beginner/diagnosis/training/advanced/outline 各组）
///   - L2 虚拟索引 skill（syndrome-diagnosis-index / technique-library-index，
///     索引内容来自 L3 知识库文件，完整知识由 L3 检索注入）
library;

import 'skill_types.dart'; // B6：本文件自身要用 Skill/SkillMeta/PromptStyle
export 'skill_types.dart'; // B6：并转发给外部消费者（历史 import 路径不变）

import 'skill_phase_slicing.dart';
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
part 'skills_teaching_mode.dart';
part 'skills_beginner.dart';
part 'skills_beginner_p1.dart';
part 'skills_beginner_p2.dart';
part 'skills_beginner_p3.dart';
part 'skills_beginner_p4.dart';
part 'skills_beginner_p5.dart';
part 'skills_beginner_p6.dart';
part 'skills_beginner_p7.dart';
part 'skills_beginner_p8.dart';
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
part 'skills_reply_voice.dart';

// ─── Skill 元数据与实体 ───────────────────────────────
// ★ B6（2026-10-06）：`PromptStyle` / `SkillMeta` / `Skill` 三个类型
//   已抽到 `skill_types.dart`（**本批只做这一步**）。
//   抽出理由 = 消除「类型定义埋在数据分片宿主里」这个结构性耦合：
//   宿主 `skill_registry.dart` 同时承担**类型定义**与**34 个 part 分片的
//   宿主**两项职责，而 part 成员靠共享它的作用域直接用这三个类型
//   ⇒ 类型无处可去、无独立测试面、也无法被非 part 的 library 复用。
//   抽出后宿主与（未来的）独立 library 都可单向 import 它。
// ⚠️ **`part` 消解本身未做，且当前不可做** —— 门禁 11
//   （`scripts/check_a_class_exemption.py`）的 A4 判据要求
//   「任何 A 类文件必须真的是 part 家族成员」，G1 判据要求
//   「分片数不得少于基线 minPartCount=49」。而 B6 的目标正是让
//   `skills_diagnosis*` **不再是** part 成员 ⇒ 两条判据与本批目标
//   **方向相反**（实测：拆 3 个文件 + 删 1 个壳后 A4 报 3 条违规、
//   G1 报「分片数 46 < 49」）。⇒ 属**门禁判据与施工目标的设计冲突**，
//   不是代码缺陷；改判据需独立批准（96-26/96-27 既定设计的成文约束）。
//   **本批保留的收益**：类型解耦已完成，且它是将来任何 part 消解的
//   **必要前置**（不抽类型就拆不动）。
// ⚠️ 宿主自身**也必须 import** skill_types.dart（不只是 export）：
//   export 只把符号**转发给本库的消费者**，不会让本文件自身看到它们。
//   而宿主仍要 `Map<String, Skill> skillRegistry = {...}` ⇒ 必须 import。
//   另：export 指令在 Dart 里**必须位于 part 指令之前**，故它放在文件头
//   import 区（下方），说明注释留在本节。

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
  'attitude-gentle': _attitudeGentle,
  'attitude-yuesheng': _attitudeYuesheng,
  'attitude-sensei': _attitudeSensei,
  // 教学方式（疑问式 / 直接说）—— 与人格档位正交，由 coach_teaching_mode 开关驱动
  'teaching-mode-socratic': _teachingModeSocratic,
  'teaching-mode-direct': _teachingModeDirect,
  // L2 按需层 — beginner 组（2026-08-08 批次 17）
  'beginner-path': _beginnerPath,
  'gap-detector': _gapDetector,
  'coaching-rhythm': _coachingRhythm,
  'narrative-design': _narrativeDesign,
  'plot-design': _plotDesign,
  'writer-psychology': _writerPsychology,
  // L2 按需层 — diagnosis 组（2026-08-08 批次 17）
  'reader-awareness': _readerAwareness,
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
      promptStyle: PromptStyle.strict,
    ),
    content: kSyndromeIndexContent,
  ),
  'technique-library-index': Skill(
    meta: SkillMeta(
      id: 'technique-library-index',
      group: 'training',
      promptStyle: PromptStyle.free,
    ),
    content: kTechniqueIndexContent,
  ),
};

/// 获取指定 ID 的 skill。不存在返回 null。
Skill? getSkill(String id) => skillRegistry[id];

// ── b9 批次30：注册表行渲染（输出与手写逐字一致）────────────────

/// 症候 ID 范围（如 P001-P023），提示文本派生用
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

/// maxAttempts 分组 ID 列表（如 P001/P005/...），组内按注册表 ID 升序
String _maxAttemptsIds(MaxAttemptsGroup group) =>
    kSyndromeRegistry.where((s) => s.group == group).map((s) => s.id).join('/');

/// training-templates-index 行：| ID | 症候名 | 核心本质一句话 |
/// 症候名默认 shortName；P018 现有文本为「重复用词/基础语病症」（带"症"字），特例保留
String _trainingIndexRow(SyndromeRecord s) {
  final name = s.id == 'P018' ? '重复用词/基础语病症' : s.shortName;
  return '| ${s.id} | $name | ${s.trainingLine} |';
}
