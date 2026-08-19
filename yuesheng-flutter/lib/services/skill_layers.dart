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
/// L2 各组 skill ID 映射
const Map<L2Mode, List<String>> l2SkillMap = {
  L2Mode.none: [],
  L2Mode.beginner: [
    'beginner-path',
    'gap-detector',
    'coaching-rhythm', // ~3500 tokens (P0会话节奏 + 从零构建引导)
    'narrative-design', // ~4200 tokens (世界观 + 角色构建方法论 + 卡片系统连接)
    'plot-design', // ~3400 tokens (情节与结构设计方法论)
    'writer-psychology', // ~3200 tokens (新手心理支持：完美主义瘫痪、空白页恐惧)
  ],
  L2Mode.diagnosis: [
    'syndrome-diagnosis-index', // 仅症候索引+通用规则 (~1800 tokens)
    'coaching-actions', // ~2200 tokens
    'coaching-rhythm', // ~3500 tokens (P1暴露问题 + Layer 2认知桥接)
    'narrative-design', // ~3800 tokens (P1世界/角色构建深化)
    'plot-design', // ~3400 tokens (P1情节/结构设计深化)
    'reader-awareness', // ~2200 tokens (读者意识/受众视角)
    'genre-guide', // ~3500 tokens (体裁感知诊断调整)
    'writing-style', // ~2800 tokens (正向风格识别，与症候诊断互补)
    'diagnosis-confirmation', // ~700 tokens (↓ from 1800, FSM code-fied)
    'feedback-cognition', // ~900 tokens
  ],
  L2Mode.training: [
    'technique-library-index', // 仅技法索引+映射表 (~900 tokens)
    'training-loop', // ~180 tokens
    'training-templates', // V2 时替换为 training-templates-index（~1500 tokens 索引，完整知识走 L3）
    'training-evaluation', // ~80 tokens
    'text-surgery', // ~1250 tokens
    'coaching-actions', // ~1400 tokens (V2: 教学动作方法目录，诊断侧 suggested_actions 的执行指引)
    'demonstration', // ~470 tokens
    'comparison', // ~540 tokens
    'timed-rewrite', // ~1600 tokens (2026-08-11 批次17 新训练形态：限时重写)
    'model-rewrite', // ~1800 tokens (2026-08-11 批次17 新训练形态：范文对照改写)
    'revision-methodology', // ~1970 tokens (章级修改/修订方法论)
    'reader-awareness', // ~1930 tokens (训练中的读者视角)
    'writer-psychology', // ~2690 tokens (训练疲劳、比较焦虑、反馈恐惧)
  ],
  L2Mode.advanced: [
    'advanced-phases', // ~4200 tokens (P3/P4/P5 完整指引)
    'training-loop', // ~3500 tokens (训练执行框架)
    'coaching-actions', // ~3900 tokens (教学动作 → P3 专项训练)
    'revision-methodology', // ~2600 tokens (深度修订)
    'reader-awareness', // ~2200 tokens (P4复盘/P5共读中的读者视角)
    'writing-style', // ~2800 tokens (P3/P4 风格深化)
    'genre-guide', // ~3500 tokens (P3 体裁专项突破)
  ],
  L2Mode.outline: [
    'plot-design', // ~3400 tokens (情节与结构设计方法论)
    'narrative-design', // ~3800 tokens (世界观 + 角色构建方法论)
    'outline-diagnosis', // ~4200 tokens (大纲结构诊断)
    'coaching-actions', // ~2200 tokens (A005阶段拆分 / A001缩小范围)
    'reader-awareness', // ~2200 tokens (读者视角)
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
List<String> getL2SkillIds(L2Mode mode) {
  final baseIds = l2SkillMap[mode] ?? const [];
  if (!useTrainingV2Pilot) {
    return List.unmodifiable(baseIds);
  }
  return List.unmodifiable(baseIds.map((id) => v2SkillReplacements[id] ?? id));
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
