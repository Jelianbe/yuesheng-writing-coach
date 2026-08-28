/// Skill 三级加载分层配置
///
/// 架构：
///   L1 常驻（~10000 tokens 实测）— 核心规则 + 态度档位，所有场景必加载
///   L2 按需注入（~8000-11000 tokens/组）— 按教学语境切换，每次只加载一组
///   L3 检索触发（~600 tokens/条）— 代码按需检索特定条目后注入
///   注入管线（~200-800 tokens）— 代码引擎计算结果注入 prompt
///
/// 真源：yuesheng-android/src/assets/skills/skill-layers.ts
library;

import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/contracts/teaching_capability.dart'; // 2026-08-19 选项B：L2Mode/SkillLoadContext/L3RetrievalContext 上移至契约层
import 'syndrome_registry.dart'; // kSyndromeIds（b9 真源）

/// 保持旧调用方经 skill_layers 取得教学 DTO（L2Mode / SkillLoadContext /
/// L3RetrievalContext / SystemPromptResult / TeachingCapability）。
/// 2026-08-19 选项B 依赖倒置：这些类型已上移至 contracts/teaching_capability.dart。
export 'package:writingcoach/contracts/teaching_capability.dart';

// ─── L1 常驻层 ───────────────────────────────────────────────

/// L1 层：所有场景均加载的核心 skill（~10000 tokens 实测总计）
const List<String> l1SkillIds = [
  'core-iron-triangle', // ~400 tokens
  'core-product-identity', // ~630 tokens
  'writing-anchors', // ~410 tokens (P4 批 5 新增)
  'teaching-strategy', // ~4400 tokens
  'phase-mapper', // ~100 tokens
  'scenario-rules', // ~560 tokens
  'validation-rules', // ~780 tokens
  'teaching-modes', // ~1600 tokens
  'reply-voice', // ~300 tokens (批次65 教练口语化去 AI 味，提炼 humanizer-zh)
  // + attitude-* (+~1100 tokens) → 总计 ~10280
];

// ─── L2 按需层 ───────────────────────────────────────────────

/// L2 加载模式：决定注入哪组 skill（类型定义已上移至 contracts/teaching_capability.dart）
/// L2 各组 skill 挂载（SkillRef：共享本体单实例 + contextHint 语境适配）
const Map<L2Mode, List<SkillRef>> l2SkillMap = {
  L2Mode.none: [],
  L2Mode.beginner: [
    SkillRef('beginner-path'),
    SkillRef('gap-detector'),
    SkillRef('coaching-rhythm', '新手语境：用「确认→选择→倾听→梳理→循环」节奏扶着走，少评判多给台阶'),
    SkillRef('narrative-design', '新手语境：只推世界观差异与角色第一层，不追深度地层'),
    SkillRef('plot-design', '新手语境：先讲清因果链，不急着铺情节'),
    SkillRef('writer-psychology'), // ~3200 tokens (新手心理支持：完美主义瘫痪、空白页恐惧)
  ],
  L2Mode.diagnosis: [
    SkillRef('syndrome-diagnosis-index'), // 仅症候索引+通用规则 (~1800 tokens)
    SkillRef('coaching-actions', '诊断语境：把症候映射到推荐动作卡'),
    SkillRef('coaching-rhythm', '诊断语境：P1 暴露差距，Layer2 认知桥接，先确认当下卡点'),
    SkillRef('narrative-design', '诊断语境：核对世界观/角色构建是否薄弱，给可操作重建步骤'),
    SkillRef('plot-design', '诊断语境：定位情节断裂/张力缺失，给因果链追问工具'),
    SkillRef('reader-awareness', '诊断语境：审视读者视角漏洞（信息/情绪/认知）'),
    SkillRef('genre-guide'), // ~3500 tokens (体裁感知诊断调整)
    SkillRef('writing-style'), // ~2800 tokens (正向风格识别，与症候诊断互补)
    SkillRef(
      'diagnosis-confirmation',
    ), // ~700 tokens (↓ from 1800, FSM code-fied)
    SkillRef('feedback-cognition'), // ~900 tokens
  ],
  L2Mode.training: [
    SkillRef('technique-library-index'), // 仅技法索引+映射表 (~900 tokens)
    SkillRef('training-loop'), // ~180 tokens
    SkillRef(
      'training-templates',
    ), // V2 时替换为 training-templates-index（~1500 tokens 索引，完整知识走 L3）
    SkillRef('training-evaluation'), // ~80 tokens
    SkillRef('text-surgery'), // ~1250 tokens
    SkillRef('coaching-actions', '训练语境：动作卡直接执行指引'),
    SkillRef('demonstration'), // ~470 tokens
    SkillRef('comparison'), // ~540 tokens
    SkillRef('timed-rewrite'), // ~1600 tokens (2026-08-11 批次17 新训练形态：限时重写)
    SkillRef('model-rewrite'), // ~1800 tokens (2026-08-11 批次17 新训练形态：范文对照改写)
    SkillRef('revision-methodology'), // ~1970 tokens (章级修改/修订方法论)
    SkillRef('reader-awareness', '训练语境：聚焦反馈恐惧与读者视角的刻意练习'),
    SkillRef('writer-psychology'), // ~2690 tokens (训练疲劳、比较焦虑、反馈恐惧)
  ],
  L2Mode.advanced: [
    SkillRef('advanced-phases'), // ~4200 tokens (P3/P4/P5 完整指引)
    SkillRef('training-loop'), // ~3500 tokens (训练执行框架)
    SkillRef('coaching-actions', '进阶语境：P3 专项训练的动作编排'),
    SkillRef('revision-methodology'), // ~2600 tokens (深度修订)
    SkillRef('reader-awareness', '进阶语境：P4 复盘/P5 共读中的读者视角深化'),
    SkillRef('writing-style'), // ~2800 tokens (P3/P4 风格深化)
    SkillRef('genre-guide'), // ~3500 tokens (P3 体裁专项突破)
  ],
  L2Mode.outline: [
    SkillRef('plot-design', '大纲语境：对齐情节结构与因果链，检测引擎是否成立'),
    SkillRef('narrative-design', '大纲语境：把角色/世界观设定与大纲结构对齐，检测交织'),
    SkillRef('outline-diagnosis'), // ~4200 tokens (大纲结构诊断)
    SkillRef('coaching-actions', '大纲语境：动作卡辅助大纲场景处理（A005阶段拆分 / A001缩小范围）'),
    SkillRef('reader-awareness', '大纲语境：大纲层面的读者体验预判'),
  ],
};

// ─── V2 试点开关 ─────────────────────────────────────────────

/// 训练系统 V2 试点开关。
///
/// 当为 true 时，training/diagnosis 模式下与训练相关的 v1 skill 会被替换为 v2 版本：
///   - training-loop        → training-loop-v2
///   - training-templates   → training-templates-index（索引；完整知识由 L3 按焦点检索）
///   - training-evaluation  → training-evaluation-v2
///   - text-surgery         → text-surgery-v2
///   - coaching-actions     → coaching-actions-v2（diagnosis 模式也会替换）
///
/// 真源：skill-layers.ts L100-126
const bool useTrainingV2Pilot = true;

/// V1 → V2 skill ID 映射表
const Map<String, String> v2SkillReplacements = {
  'training-loop': 'training-loop-v2',
  'training-templates': 'training-templates-index',
  'training-evaluation': 'training-evaluation-v2',
  'text-surgery': 'text-surgery-v2',
  'coaching-actions': 'coaching-actions-v2',
};

/// 获取指定 L2 模式下的 skill ID 列表。
///
/// 当 [useTrainingV2Pilot] 为 true 时，将 v1 训练相关 skill 替换为 v2 版本。
/// 这是 skill-dispatcher 获取 L2 skill 列表的唯一入口。
List<SkillRef> getL2SkillIds(L2Mode mode) {
  final baseRefs = l2SkillMap[mode] ?? const <SkillRef>[];
  if (!useTrainingV2Pilot) {
    return List.unmodifiable(baseRefs);
  }
  // V2 替换：保留 contextHint，仅替换 skillId
  return List.unmodifiable(
    baseRefs.map(
      (ref) => SkillRef(
        v2SkillReplacements[ref.skillId] ?? ref.skillId,
        ref.contextHint,
      ),
    ),
  );
}

// ─── L2 决议逻辑 ─────────────────────────────────────────────

/// Skill 加载上下文（类型定义已上移至 contracts/teaching_capability.dart）

/// 根据教学语境决议应加载的 L2 组。
///
/// 规则优先级：
///   1. P0/P1 + 零基础学员 → beginner
///   2. P2+ DIAGNOSIS 子阶段 → diagnosis
///   3. P2+ PRACTICE/FEEDBACK 子阶段 → training
///   4. P3/P4 进阶阶段 → advanced（如果非零基础）
///   5. 无法决议 → none（不加载 L2）
L2Mode resolveL2Mode(SkillLoadContext ctx) {
  final phase = ctx.phase;
  final subphase = ctx.subphase;
  final isBeginner = ctx.isBeginner;
  final isOutlineContext = ctx.isOutlineContext;

  // 规则0：大纲语境优先（在任何阶段都可触发）
  if (isOutlineContext) return L2Mode.outline;

  // 规则1：零基础优先（P0-P2 均可加载 beginner path）
  if (isBeginner &&
      (phase == TeachingPhase.p0Engage ||
          phase == TeachingPhase.p1World ||
          phase == TeachingPhase.p2PracticeLoop)) {
    return L2Mode.beginner;
  }

  // 规则2-3：P2 按子阶段拆分（核心优化点）
  if (phase == TeachingPhase.p2PracticeLoop) {
    if (subphase == null || subphase == TeachingSubphase.diagnosis) {
      return L2Mode.diagnosis;
    }
    if (subphase == TeachingSubphase.practice ||
        subphase == TeachingSubphase.feedback) {
      return L2Mode.training;
    }
  }

  // P1 无子阶段概念，按诊断模式加载
  if (phase == TeachingPhase.p1World) {
    return L2Mode.diagnosis;
  }

  // 规则4：进阶阶段
  if (phase == TeachingPhase.p3Training || phase == TeachingPhase.p4Review) {
    if (isBeginner) return L2Mode.beginner;
    return L2Mode.advanced;
  }

  // P0：不加载 L2
  return L2Mode.none;
}

// ─── L3 检索层 ───────────────────────────────────────────────

/// 症候 ID 列表（b9 真源化：由 syndrome_registry 派生，不再手写；
/// H001/H002 已合并至 P013；批次15 加 P023-P027，批次23-26 加 P028-P031）
final List<String> syndromeIds = kSyndromeIds;

/// L3 检索上下文：驱动按需检索特定症候/技法详细内容（类型定义已上移至 contracts/teaching_capability.dart）

/// L3 检索结果
class L3RetrievalResult {
  /// 症候详情文本（用于追加到 system prompt）
  final String? syndromeDetails;

  /// 技法详情文本
  final String? techniqueDetails;

  const L3RetrievalResult({this.syndromeDetails, this.techniqueDetails});
}
