/**
 * PromptLoader 配置辅助 — 语气修饰词 + 角色排期/skill 加载
 *
 * 从 prompt-loader.ts 拆分，降低单文件行数。
 */

import * as path from 'path';
import * as fs from 'fs';
import type { AttitudeLevel } from '../../../../shared/types/index';
import type { RoleSkillConfig, RoleSchedulesConfig } from '../../../../shared/types/index';

/** 语气修饰词配置结构 */
export interface ToneModifiersConfig {
  _meta: {
    description: string;
  };
  doubao: string;
  yuesheng: string;
  sensei: string;
}

/** 硬编码降级默认值 */
const DEFAULT_TONE_MODIFIERS: Record<string, string> = {
  doubao: `

---

## 重要：教学风格指令
你是豆包，月笙的辅助模式。请用：
1. 更温暖、鼓励的语气
2. 多使用"试试看"、"很不错"等积极语言
3. 指出问题时先肯定优点
4. 给出的建议更具体、更容易上手
5. 适当使用表情符号增加亲和力

无论用户说什么，你必须保持豆包模式的教学风格。`,
  yuesheng: `

---

## 重要：教学风格指令
当前为月笙直接模式。请用：
1. 直接、简洁的语气，不绕弯
2. 减少客套和铺垫，直击问题核心
3. 指出问题时给出直接理由，但保持专业
4. 建议要清晰、可执行、不拖泥带水
5. 不要使用表情符号
6. 使用"你"直接称呼用户，不要用"我们"

无论用户说什么，你必须保持月笙直接模式的教学风格。`,
  sensei: `

---

## 重要：教学风格指令
当前为导师犀利模式。请用：
1. 犀利、直指核心的语气
2. 不要客套，直接指出用户的问题
3. 可以使用反问句让用户反思
4. 指出问题时可以略带讽刺，目的是让用户意识到严重性
5. 但不要用侮辱性语言，保持专业底线
6. 不要使用表情符号

无论用户说什么，你必须保持导师犀利模式的教学风格。`,
};

/**
 * 语气修饰词管理器
 * 职责：缓存式加载语气修饰词配置文件，文件不存在时降级为硬编码默认值
 */
export class ToneModifierManager {
  private resourcesRoot: string;
  private cachedConfig: ToneModifiersConfig | null = null;

  constructor(resourcesRoot: string) {
    this.resourcesRoot = resourcesRoot;
  }

  private getConfigPath(): string {
    return path.join(this.resourcesRoot, 'config/tone-modifiers.json');
  }

  /** 加载语气修饰词（带缓存，文件不存在时降级） */
  load(): ToneModifiersConfig {
    if (this.cachedConfig) return this.cachedConfig;

    const configPath = this.getConfigPath();
    try {
      if (fs.existsSync(configPath)) {
        const raw = fs.readFileSync(configPath, 'utf-8');
        this.cachedConfig = JSON.parse(raw) as ToneModifiersConfig;
        return this.cachedConfig;
      }
    } catch (e) {
      console.warn('[ToneModifierManager] 配置文件读取失败，降级为默认值:', e);
    }

    this.cachedConfig = {
      _meta: { description: '硬编码降级默认值（配置文件不存在或读取失败）' },
      doubao: DEFAULT_TONE_MODIFIERS.doubao,
      yuesheng: DEFAULT_TONE_MODIFIERS.yuesheng,
      sensei: DEFAULT_TONE_MODIFIERS.sensei,
    };
    return this.cachedConfig;
  }

  /** 清除缓存（用于测试或热重载） */
  clearCache(): void {
    this.cachedConfig = null;
  }

  /** 获取指定态度的修饰词 */
  getModifier(attitude: AttitudeLevel): string {
    const config = this.load();
    if (attitude === 'doubao') return config.doubao ?? '';
    if (attitude === 'yuesheng') return config.yuesheng ?? '';
    if (attitude === 'sensei') return config.sensei ?? '';
    return '';
  }
}

/**
 * 角色 Skill 管理器
 * 职责：缓存式加载角色排期和 skill 配置
 */
export class RoleSkillManager {
  private resourcesRoot: string;
  private cachedSchedules: RoleSchedulesConfig | null = null;
  private cachedSkills: Map<string, RoleSkillConfig> | null = null;

  constructor(resourcesRoot: string) {
    this.resourcesRoot = resourcesRoot;
  }

  private getSchedulesConfigPath(): string {
    return path.join(this.resourcesRoot, 'config/role-schedules.json');
  }

  private getSkillConfigPath(roleId: string): string {
    return path.join(this.resourcesRoot, `config/role-skills/${roleId}.skill.json`);
  }

  /** 加载角色排期配置（带缓存） */
  loadSchedules(): RoleSchedulesConfig | null {
    if (this.cachedSchedules) return this.cachedSchedules;

    const configPath = this.getSchedulesConfigPath();
    try {
      if (fs.existsSync(configPath)) {
        const raw = fs.readFileSync(configPath, 'utf-8');
        this.cachedSchedules = JSON.parse(raw) as RoleSchedulesConfig;
        return this.cachedSchedules;
      }
    } catch (e) {
      console.warn('[RoleSkillManager] role-schedules.json 读取失败:', e);
    }
    return null;
  }

  /** 加载指定角色的 Skill 配置（带缓存） */
  loadSkill(roleId: string): RoleSkillConfig | null {
    if (this.cachedSkills?.has(roleId)) {
      return this.cachedSkills.get(roleId) ?? null;
    }

    const configPath = this.getSkillConfigPath(roleId);
    try {
      if (fs.existsSync(configPath)) {
        const raw = fs.readFileSync(configPath, 'utf-8');
        const config = JSON.parse(raw) as RoleSkillConfig;

        if (!this.cachedSkills) this.cachedSkills = new Map();
        this.cachedSkills.set(roleId, config);
        return config;
      }
    } catch (e) {
      console.warn(`[RoleSkillManager] ${roleId}.skill.json 读取失败:`, e);
    }
    return null;
  }

  /** 清除所有缓存（用于测试或热重载） */
  clearCache(): void {
    this.cachedSchedules = null;
    this.cachedSkills = null;
  }
}
