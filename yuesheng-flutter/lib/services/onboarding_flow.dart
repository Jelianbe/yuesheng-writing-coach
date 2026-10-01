// ─────────────────────────────────────────────────────────────
// OnboardingFlow — 问卷文本示例 + 等级映射
// 复刻 yuesheng-android/src/services/onboarding-flow.ts（RN 真源规划中的文件）
//
// 设计意图（批次1-8 波6）：
//   - Q1 用 4 级文本示例替代 3 级自评，让学员"对号入座"而非主观判断
//   - 文本示例按 N0→N3 递进，每级体现典型写作特征
//   - Q4（写作目标）因与 Q2（提升方向）重叠，已移除
//   - 3 题制：Q1 等级 / Q2 提升方向（多选）/ Q3 学习偏好
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';

/// 文本示例选项（Q1 用）
class ProficiencyExample {
  final ProficiencyLevel proficiency;
  final BeginnerLevel beginnerLevel;
  final String label;
  final String sample;

  const ProficiencyExample({
    required this.proficiency,
    required this.beginnerLevel,
    required this.label,
    required this.sample,
  });
}

/// Q1：4 级文本示例（N0→N3 递进）
/// 学员选择最接近自己写作水平的示例
const List<ProficiencyExample> kProficiencyExamples = [
  ProficiencyExample(
    proficiency: ProficiencyLevel.beginner,
    beginnerLevel: BeginnerLevel.n0Engage,
    label: '刚开始写作',
    sample: '天黑了，她很害怕，就走回家了。',
  ),
  ProficiencyExample(
    proficiency: ProficiencyLevel.elementary,
    beginnerLevel: BeginnerLevel.n1Elements,
    label: '写过一些片段',
    sample: '夜色渐浓，她加快脚步，心里有些发慌，街道空荡荡的。',
  ),
  ProficiencyExample(
    proficiency: ProficiencyLevel.intermediate,
    beginnerLevel: BeginnerLevel.n2Scene,
    label: '能写完整场景',
    sample: '路灯在她身后一盏盏暗下去，影子拉得老长。她攥紧书包带，脚步声在空巷里回响，每一下都像有人在跟。',
  ),
  ProficiencyExample(
    proficiency: ProficiencyLevel.advanced,
    beginnerLevel: BeginnerLevel.n3Diagnose,
    label: '有完整作品',
    sample:
        '巷子深处传来猫叫，她停下脚步，发现是只花猫从墙头跳下，惊起几片落叶。她笑了，俯身去摸，猫却窜进了黑暗。她直起身，发现身后多了一个影子。',
  ),
];

/// Q2：提升方向（多选）
const List<String> kFocusAreaOptions = ['人物塑造', '情节设计', '文笔修辞', '世界观构建'];

/// Q3：学习偏好
class CognitiveStyleOption {
  final CognitiveStyle value;
  final String label;

  const CognitiveStyleOption({required this.value, required this.label});
}

const List<CognitiveStyleOption> kCognitiveStyleOptions = [
  CognitiveStyleOption(value: CognitiveStyle.intuitive, label: '快速迭代，多练少讲'),
  CognitiveStyleOption(value: CognitiveStyle.analytical, label: '深度讲解，先理解再练'),
  CognitiveStyleOption(value: CognitiveStyle.mixed, label: '边练边讲'),
];

/// 问卷总题数
const int kOnboardingQuestionCount = 3;

/// 根据 ProficiencyLevel 查找对应的 BeginnerLevel
/// 用于 submitOnboarding 时写入 teaching_state.beginner_level
BeginnerLevel proficiencyToBeginnerLevel(ProficiencyLevel proficiency) {
  for (final ex in kProficiencyExamples) {
    if (ex.proficiency == proficiency) return ex.beginnerLevel;
  }
  return BeginnerLevel.n0Engage;
}

// ═══════════════════════════════════════════════════════════
// 小白冷启动试点（ADR-C121）· 30 秒微任务卡片
//
// 资产底：仓内 N0 三激发活动（skills_beginner_p5.dart）——叙述/对话/描写，
// 完成标志 ≥50 字（L88-89）。本文件是**学员侧 UI 新文案**（数据层），
// 不触注入 prompt（skills_*.dart / skill_registry.dart 零改动）。
//
// 任务设计 = Hillocks 结构化写作（给约束不教作文）+ Bereiter-Scardamalia
// 小钩子（末句强制句式，逼出「选择」而非流水账）。
// R-009：卡片只给**任务约束**（范围/字数/句式），不替写句子、不给范文、
// 不给写作处方——学员产出是本人第一份可诊断文本。
// ═══════════════════════════════════════════════════════════

/// 微任务字数门槛（可诊断标准 ≥50 字，与 N0 完成标志一致）
const int kMicroTaskMinChars = 50;

/// 微任务建议上限（软提示；超出不硬禁，诊断链路支持长文本）
const int kMicroTaskSuggestMaxChars = 200;

/// 卡片墙副标题（学员侧文案）
const String kMicroTaskWallSubtitle = '选一个 30 秒任务，写满 50 字，教练立刻给你诊断';

/// 素材练习声明（R-009 边界话术：不是代写成品）
const String kMicroTaskDisclaimer =
    '这是 30 秒素材练习，不是你的第一章——写得越烂越好，'
    '教练要的就是你现在的真实水平。提交即授权教练读这段素材并给诊断。';

/// 微任务卡片（30 秒微任务→立刻诊断的最小闭环素材）
class MicroTaskCard {
  /// 稳定 id（埋点 payload 用）
  final String id;

  /// 卡片标题（行动型，学员一眼知道要做什么）
  final String title;

  /// 主任务指令
  final String prompt;

  /// 结构化约束（Hillocks：给形状，不给内容）
  final String constraint;

  /// 小钩子（末句强制句式，逼出选择/悬念）
  final String hook;

  /// 「换一个」变体池（每卡 ≥2，避免学员被卡死在一个题目上）
  final List<String> variants;

  const MicroTaskCard({
    required this.id,
    required this.title,
    required this.prompt,
    required this.constraint,
    required this.hook,
    required this.variants,
  });
}

/// 三张微任务卡（对齐 N0 三激发：叙述 / 对话 / 描写）
const List<MicroTaskCard> kMicroTaskCards = [
  MicroTaskCard(
    id: 'narrate_morning',
    title: '一个 30 秒的早晨',
    prompt: '写你今早从睁眼到出门前的一件事。只写这一个片段，50–200 字。',
    constraint: '时间线要顺：从睁眼看到的第一样东西写起，写到离开那一刻为止，中间不许跳。',
    hook: '最后一句必须以「然后他／她……」开头，给这件事留一个悬念。',
    variants: ['写你昨晚睡前最后做的一件事。', '写你通勤路上第一眼注意到的东西。'],
  ),
  MicroTaskCard(
    id: 'dialogue_disagree',
    title: '两个人的一句话',
    prompt: '写一段两个人因为一件小事起了分歧的对话，50–200 字。',
    constraint: '每个人只说 2–4 句话，谁都不让步；不用旁白解释谁对谁错。',
    hook: '对话的最后，必须有一句「没有接话」的静默。',
    variants: ['写一段关于「晚饭吃什么」谁都不服谁的对话。', '写一场关于「到底要不要关空调」的分歧。'],
  ),
  MicroTaskCard(
    id: 'describe_three',
    title: '窗外三样东西',
    prompt: '从你眼前（或想象中）的场景里挑三样东西来写，50–200 字。',
    constraint: '用动作、光影或声音写它们，不许用「很」「非常」「特别」这类程度词。',
    hook: '三样东西里，必须有一件是在动的。',
    variants: ['从你书桌或办公桌的角落挑三样。', '从一个雨天的公交站挑三样。'],
  ),
];

/// 按 id 取卡片（无则返回第一张兜底）
MicroTaskCard microTaskCardById(String id) {
  for (final c in kMicroTaskCards) {
    if (c.id == id) return c;
  }
  return kMicroTaskCards.first;
}
