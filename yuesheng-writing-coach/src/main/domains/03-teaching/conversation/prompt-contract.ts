/**
 * Prompt Contract — 提示词契约元数据(Sprint 20 增量 3)
 *
 * 设计目标:
 * - 每个 prompt 版本头部声明其依赖的 skills / techniques / tools / events
 * - 启动时(Orchestrator.promptVersion() 返回前)硬校验
 * - 不兼容 → 抛 PromptContractError,阻止服务启动
 *
 * 写在哪里:
 * - 在 resources/prompts/yuesheng-prompt-vX.Y.Z.md 头部插入 YAML 块
 * - 由 parsePromptContract() 解析
 * - 由 validateContract() 校验
 *
 * 依据: dev-docs/tasks/sprint-20-plan.md §增量 3 / D-054 教训
 */

/** 提示词契约:声明本版本 prompt 依赖的外部资源 */
export interface PromptContract {
  /** 本版本要求的会话阶段(与 ConversationPhase 联合) */
  required_phases: Array<
    'trust_building' | 'requirement' | 'diagnosis' | 'training' | 'reflection'
  >;
  /** 本版本要求的 skill ID(skill 库必须提供) */
  required_skills: string[];
  /** 本版本要求引用过的技法 ID(technique-pool 必须提供) */
  required_techniques: string[];
  /** 本版本使用的 IPC tool(IPC 频道必须存在且 preload 白名单已开) */
  required_tools: string[];
  /** 本版本会触发的 event topic(DomainEvent 联合必须包含) */
  emits_events: string[];
}

/** 当前运行环境能提供的资源(由 Orchestrator 启动时构造) */
export interface PromptEnvironment {
  /** 已加载的 skill ID 列表 */
  availableSkills: string[];
  /** 已注册的技法 ID 列表 */
  availableTechniques: string[];
  /** 已注册的 IPC 工具/频道列表 */
  availableTools: string[];
  /** 已知的 event topic 列表 */
  availableEvents: string[];
}

/** 校验错误详情 */
export interface ContractMismatch {
  category: 'skills' | 'techniques' | 'tools' | 'events' | 'phases';
  missing: string[];
}

/** 契约校验失败异常 — 启动时抛,直接拦截服务 */
export class PromptContractError extends Error {
  readonly mismatches: ContractMismatch[];
  readonly contractVersion: string;

  constructor(contractVersion: string, mismatches: ContractMismatch[]) {
    const summary = mismatches
      .map(m => `  [${m.category}] 缺少: ${m.missing.join(', ')}`)
      .join('\n');
    super(
      `Prompt contract v${contractVersion} 校验失败,服务拒绝启动:\n${summary}\n\n` +
      `修复:补充缺失资源,或回滚 prompt 版本。`,
    );
    this.name = 'PromptContractError';
    this.contractVersion = contractVersion;
    this.mismatches = mismatches;
  }
}

/**
 * 校验契约 vs 环境
 * 任何 mismatch 都抛 PromptContractError(硬错,启动拦截)
 */
export function validateContract(
  contract: PromptContract,
  env: PromptEnvironment,
  contractVersion: string,
): void {
  const mismatches: ContractMismatch[] = [];

  const missingSkills = contract.required_skills.filter(s => !env.availableSkills.includes(s));
  if (missingSkills.length > 0) {
    mismatches.push({ category: 'skills', missing: missingSkills });
  }

  const missingTechniques = contract.required_techniques.filter(t => !env.availableTechniques.includes(t));
  if (missingTechniques.length > 0) {
    mismatches.push({ category: 'techniques', missing: missingTechniques });
  }

  const missingTools = contract.required_tools.filter(t => !env.availableTools.includes(t));
  if (missingTools.length > 0) {
    mismatches.push({ category: 'tools', missing: missingTools });
  }

  const missingEvents = contract.emits_events.filter(e => !env.availableEvents.includes(e));
  if (missingEvents.length > 0) {
    mismatches.push({ category: 'events', missing: missingEvents });
  }

  if (mismatches.length > 0) {
    throw new PromptContractError(contractVersion, mismatches);
  }
}

/**
 * 解析 prompt 文件头部的 contract YAML 块
 *
 * 文件格式约定(以 V5.0.0-draft 为例):
 * ```markdown
 * ---
 * contract:
 *   required_phases: [trust_building, requirement, diagnosis, training, reflection]
 *   required_skills: [core-identity, scenario-rules, ...]
 *   required_techniques: [P001, P002, ...]
 *   required_tools: [chapter:read, diagnosis:extract, ...]
 *   emits_events: [chat:token, chat:intent, ...]
 * ---
 * ```
 *
 * 当前实现:简单 YAML 解析(只支持单层数组),避免引入 yaml 依赖
 * 失败 → 抛 ContractParseError
 */
export function parsePromptContract(frontmatter: string): PromptContract {
  const lines = frontmatter.split('\n');
  let inContract = false;
  let currentCategory: keyof PromptContract | null = null;
  const result: Record<string, string[]> = {};

  for (const raw of lines) {
    const line = raw.replace(/\r$/, ''); // CRLF 兼容
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    if (trimmed === 'contract:') {
      inContract = true;
      continue;
    }
    if (!inContract) continue;

    if (trimmed.startsWith('- ')) {
      // 数组项
      const value = trimmed.slice(2).trim();
      if (currentCategory) {
        result[currentCategory] = result[currentCategory] ?? [];
        result[currentCategory].push(value);
      }
      continue;
    }

    // key: [v1, v2, ...] 行内数组
    const inlineMatch = trimmed.match(/^(\w+):\s*\[(.*)\]$/);
    if (inlineMatch) {
      const key = inlineMatch[1] as keyof PromptContract;
      const values = inlineMatch[2]
        .split(',')
        .map(s => s.trim())
        .filter(Boolean);
      result[key] = values;
      currentCategory = key;
      continue;
    }

    // key: 后续
    const keyMatch = trimmed.match(/^(\w+):\s*$/);
    if (keyMatch) {
      currentCategory = keyMatch[1] as keyof PromptContract;
      result[currentCategory] = result[currentCategory] ?? [];
    }
  }

  const required = ['required_phases', 'required_skills', 'required_techniques', 'required_tools', 'emits_events'] as const;
  for (const k of required) {
    if (!result[k] || result[k].length === 0) {
      throw new Error(`Prompt contract parse: missing or empty category "${k}"`);
    }
  }

  return {
    required_phases: result.required_phases as PromptContract['required_phases'],
    required_skills: result.required_skills,
    required_techniques: result.required_techniques,
    required_tools: result.required_tools,
    emits_events: result.emits_events,
  };
}
