/// Skill 三级加载调度器（编排版）
///
/// 架构：
///   L1 常驻（~12000 tokens）— 核心规则 + 态度档位，所有场景必加载
///   L2 按需注入（~14000 tokens/组）— 按教学子阶段切换，每次只加载一组
///   L3 检索触发（~600 tokens/条）— 代码按需检索症候/技法详情后追加
///   注入管线 — 代码引擎（训练评估）结果注入到 prompt
///
/// 真源：yuesheng-android/src/services/skill-dispatcher.ts
/// 复刻范围：buildSystemPromptV2 主链路 + L3 注入函数
library;

import 'package:writingcoach/services/skill_layers.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/config/shared_constants.dart';

export 'package:writingcoach/contracts/teaching_capability.dart';

/// 教学能力实现（选项 B 依赖倒置）
///
/// 委托到既有纯函数 buildSystemPromptV2 / resolveL2Mode，自身无状态；
/// UI 经 TeachingCapability 消费，不直接依赖 skill 注册表内部。

/// 顶层实现别名：供 TeachingCapabilityImpl 委托，避免同名实例方法自递归
///（Dart 方法体内同名标识符优先解析为实例成员）。见 2026-08-19 修复。
L2Mode _resolveL2ModeImpl(SkillLoadContext ctx) => resolveL2Mode(ctx);

class TeachingCapabilityImpl implements TeachingCapability {
  const TeachingCapabilityImpl();

  @override
  SystemPromptResult buildSystemPrompt(SkillLoadContext ctx) =>
      buildSystemPromptV2(ctx);

  @override
  L2Mode resolveL2Mode(SkillLoadContext ctx) => _resolveL2ModeImpl(ctx);
}

// ─── 常量 ─────────────────────────────────────────────────────

const String _kSkillSeparator = '\n\n---\n\n';

const String _kPositionGuidance = '''## 内容位置判断（必读）

在对用户提供的写作内容进行诊断前，请先判断其位置（开头/中段/结尾），然后选择适用的诊断维度。

**位置判断标准**：
- 【开头】内容包含"主角首次出场、场景建立、冲突引入"等特征
- 【中段】内容包含"冲突发展、情节推进、对话推进"等特征
- 【结尾】内容包含"高潮、收束、悬念释放/埋设"等特征
- 【全局】内容过短（< 1000 字）难以判断，或用户明确要求全篇检测

**Few-shot 示例**：

示例 1（开头）：
> 萧炎盘腿坐在床上，双手结出修炼的印结，呼吸间，一缕淡白色气流从空气中抽离而出
 【位置判断】开头（主角首次出场，进入修炼状态）

示例 2（中段）：
> "纳兰小姐，请问你此次前来，究竟有何贵干？"萧炎的声音平静，但眼中闪过一丝复杂
 【位置判断】中段（对话推进情节，冲突正在发展）

示例 3（结尾）：
> 望着那道远去的背影，萧炎紧握的拳头缓缓松开，嘴角勾起一抹苦涩的弧度
 【位置判断】结尾（情绪收束，悬念埋设）

**关键要求**：
1. 在诊断输出中首先明确写出【位置判断：XXX】
2. 仅对 position_sensitivity 匹配当前位置的症候进行诊断
3. 全局敏感（position_sensitivity: global）的症候在所有位置都适用
4. 不要对不适用于当前位置的症候进行诊断（如不要在中段诊断"开篇钩子"）''';

// ─── 接口 ─────────────────────────────────────────────────────

// ─── V2 三级加载引擎（无状态）────────────────────────────────

/// 构建三级分层 system prompt。
///
/// 加载顺序：
/// 1. L1 常驻层：8 个核心 skill（按 [l1SkillIds] 顺序）
/// 2. 态度档位 skill：根据 [SkillLoadContext.attitude] 加载一个
/// 3. L2 按需层：根据 [resolveL2Mode] 决议的 mode 加载一组 skill
/// 4. 位置判断引导语（始终注入末尾）
///
/// L3 检索函数通过返回值的 [SystemPromptResult.injectL3] 字段延迟调用。
///
/// 注意：L2 五组 skill 内容已于 2026-08-08 批次 22 全部搬运到 [skillRegistry]
///（注册表 39 项，含虚拟索引）。缺失的 skill 仍会被跳过（不报错），作为防御性兜底保留。
SystemPromptResult buildSystemPromptV2(SkillLoadContext ctx) {
  final chunks = <String>[];
  final loadedIds = <String>[];

  // ═══════════════════════════════════════════════════════════
  // L1: 常驻层 — 核心规则（所有场景必加载）
  // ═══════════════════════════════════════════════════════════
  for (final skillId in l1SkillIds) {
    final skill = getSkill(skillId);
    if (skill != null) {
      chunks.add(skill.content);
      loadedIds.add(skillId);
    }
  }

  // 态度档位 skill（L1 — 根据当前 attitude 加载一个）
  final attitudeKey = 'attitude-${ctx.attitude.value}';
  final attitudeSkill = getSkill(attitudeKey);
  if (attitudeSkill != null) {
    chunks.add(attitudeSkill.content);
    loadedIds.add(attitudeKey);
  }

  // ═══════════════════════════════════════════════════════════
  // L2: 按需层 — 根据教学语境选择一组 skill
  // ═══════════════════════════════════════════════════════════
  final l2Mode = resolveL2Mode(ctx);
  final l2SkillIds = getL2SkillIds(l2Mode);

  for (final skillId in l2SkillIds) {
    final skill = getSkill(skillId);
    if (skill != null) {
      chunks.add(skill.content);
      loadedIds.add(skillId);
    }
    // 未注册的 skill 静默跳过（后续补齐后自动生效）
  }

  // 位置判断引导语（L1 末尾，始终注入）
  chunks.add(_kPositionGuidance);

  // 拼接
  final systemPrompt = chunks.join(_kSkillSeparator);
  final estimatedTokens = _estimateTokens(systemPrompt);

  // ═══════════════════════════════════════════════════════════
  // L3: 检索函数（返回后由调用方按需调用）
  // ═══════════════════════════════════════════════════════════
  String injectL3(L3RetrievalContext l3Ctx) {
    final parts = <String>[];

    // 症候详情（诊断/训练模式都需要）
    // 2026-08-08 批次 22 步骤②：已接入 syndrome-diagnosis 知识库
    //（syndrome_knowledge_base.dart，getSyndromeContent 检索完整定义）
    if (l3Ctx.activeSyndromeIds != null &&
        l3Ctx.activeSyndromeIds!.isNotEmpty) {
      final syndromeDetail = _getSyndromeContent(l3Ctx.activeSyndromeIds!);
      if (syndromeDetail != null && syndromeDetail.isNotEmpty) {
        parts.add(syndromeDetail);
      }
    }

    // 技法详情
    if (l3Ctx.focusedTechniqueIds != null &&
        l3Ctx.focusedTechniqueIds!.isNotEmpty) {
      final techniqueDetail = _getTechniqueContent(l3Ctx.focusedTechniqueIds!);
      if (techniqueDetail != null && techniqueDetail.isNotEmpty) {
        parts.add(techniqueDetail);
      }
    }

    return parts.isNotEmpty ? '\n\n${parts.join('\n\n---\n\n')}' : '';
  }

  return SystemPromptResult(
    systemPrompt: systemPrompt,
    l2Mode: l2Mode,
    loadedSkillIds: List.unmodifiable(loadedIds),
    estimatedTokens: estimatedTokens,
    injectL3: injectL3,
  );
}

// ─── 辅助函数 ─────────────────────────────────────────────────

/// 估算文本的 token 数（中文约 1.0 token/char，B26 由英文口径 0.4 校正）
int _estimateTokens(String text) {
  return (text.length * TokenEstimate.charToTokenRatio).round();
}

/// 获取症候详情文本（L3 检索）
///
/// 真源：yuesheng-android/src/assets/skills/syndrome-diagnosis.ts getSyndromeContent
/// 2026-08-08 批次 22 步骤②：接入症候知识库
String? _getSyndromeContent(List<String> syndromeIds) {
  final content = getSyndromeContent(syndromeIds);
  return content.isEmpty ? null : content;
}

/// 获取技法详情文本（L3 检索）
///
/// 真源：yuesheng-android/src/assets/skills/technique-library.ts getTechniqueContent
/// 入参为技法 ID 列表（如 ['T001', 'T008']）。
/// 2026-08-08 批次 22 步骤②：接入技法知识库
String? _getTechniqueContent(List<String> techniqueIds) {
  final content = getTechniqueContent(techniqueIds);
  return content.isEmpty ? null : content;
}

// ─── 验证工具 ─────────────────────────────────────────────────

/// 验证 system prompt 的基本完整性
PromptValidationResult validatePrompt(String prompt) {
  final errors = <String>[];
  final warnings = <String>[];

  if (prompt.isEmpty) {
    errors.add('system prompt 为空');
    return PromptValidationResult(
      valid: false,
      errors: errors,
      warnings: warnings,
    );
  }

  final tokenEstimate = _estimateTokens(prompt);
  final maxBudget = TokenEstimate.maxBudget;
  if (tokenEstimate > maxBudget) {
    errors.add('Token 估算超限: ~$tokenEstimate/$maxBudget');
  } else if (tokenEstimate > maxBudget * TokenEstimate.warningRatio) {
    warnings.add('Token 预算紧张: ~$tokenEstimate/$maxBudget');
  }

  // 检查必要段是否存在
  if (!prompt.contains('铁三角')) {
    warnings.add('缺少"核心铁三角"规则段');
  }
  if (!prompt.contains('位置判断')) {
    warnings.add('缺少"位置判断"引导语');
  }

  return PromptValidationResult(
    valid: errors.isEmpty,
    errors: errors,
    warnings: warnings,
  );
}

/// 验证结果
class PromptValidationResult {
  final bool valid;
  final List<String> errors;
  final List<String> warnings;

  const PromptValidationResult({
    required this.valid,
    required this.errors,
    required this.warnings,
  });
}
