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
