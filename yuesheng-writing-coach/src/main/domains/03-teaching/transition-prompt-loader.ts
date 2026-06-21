/**
 * 过渡邀请话术加载器
 * 负责：从外部配置文件加载话术模板，支持变量替换和多版本轮询
 *
 * 遵循 R-014 配置外置规范，禁止硬编码业务映射表。
 */

import fs from 'fs';
import path from 'path';


/** 单条话术变体 */
export interface PromptVariant {
  id: string;
  template: string;
  tone: string;
}

/** 话术配置结构 */
export interface TransitionPromptConfig {
  _meta: {
    description: string;
    templateVariables: Record<string, string>;
    selectionStrategy: 'round-robin' | 'random';
  };
  worldbuilding: { variants: PromptVariant[] };
  character: { variants: PromptVariant[] };
}

/** 运行时状态：记录每个 focusArea 下一次该用哪个变体 */
const variantIndices: Record<string, number> = {
  worldbuilding: 0,
  character: 0,
};

/** 由 index.ts 注入的资源根路径（替代直接依赖 app 模块） */
let _resourcesRoot = '';

/** 设置资源根路径（启动时由 index.ts 调用一次） */
export function setResourcesRoot(root: string): void {
  _resourcesRoot = root;
}

let cachedConfig: TransitionPromptConfig | null = null;

/**
 * 获取配置文件路径
 */
function getConfigPath(): string {
  return path.join(_resourcesRoot, 'config/transition-prompts.json');
}

/**
 * 加载话术配置
 * 首次调用时读取文件并缓存，后续直接返回缓存
 */
export function loadTransitionPromptConfig(): TransitionPromptConfig {
  if (cachedConfig) {
    return cachedConfig;
  }

  const configPath = getConfigPath();
  if (!fs.existsSync(configPath)) {
    throw new Error(`[TransitionPrompt] 配置文件未找到: ${configPath}`);
  }

  const raw = fs.readFileSync(configPath, 'utf-8');
  cachedConfig = JSON.parse(raw) as TransitionPromptConfig;
  return cachedConfig;
}

/**
 * 清除配置缓存（用于热重载或测试）
 */
export function clearPromptCache(): void {
  cachedConfig = null;
}

/**
 * 选择下一个话术变体
 * 根据 selectionStrategy 决定轮询或随机
 */
function selectVariant(variants: PromptVariant[], focusArea: string): PromptVariant {
  const config = loadTransitionPromptConfig();
  const strategy = config._meta.selectionStrategy;

  if (strategy === 'random') {
    return variants[Math.floor(Math.random() * variants.length)];
  }

  // 默认轮询
  const idx = variantIndices[focusArea] ?? 0;
  const selected = variants[idx % variants.length];
  variantIndices[focusArea] = (idx + 1) % variants.length;
  return selected;
}

/**
 * 渲染模板，替换变量
 * @param template 模板字符串
 * @param variables 变量映射表
 */
function renderTemplate(
  template: string,
  variables: Record<string, string>,
): string {
  return template.replace(/\{\{(\w+)\}\}/g, (match, key) => {
    return variables[key] ?? match;
  });
}

/**
 * 获取过渡邀请话术
 * @param focusArea 聚焦方向
 * @param variables 模板变量（如 worldSummary, characterName）
 * @returns 渲染后的话术文本，如果 focusArea 不支持则返回 null
 */
export function getTransitionPrompt(
  focusArea: string,
  variables: Record<string, string> = {},
): string | null {
  const config = loadTransitionPromptConfig();

  const areaConfig =
    config[focusArea as keyof Omit<TransitionPromptConfig, '_meta'>];
  if (!areaConfig || areaConfig.variants.length === 0) {
    return null;
  }

  const variant = selectVariant(areaConfig.variants, focusArea);
  return renderTemplate(variant.template, variables);
}

/**
 * 获取所有可用的模板变量说明
 * 用于调试或文档生成
 */
export function getTemplateVariables(): Record<string, string> {
  const config = loadTransitionPromptConfig();
  return config._meta.templateVariables;
}
