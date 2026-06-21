/**
 * 技法库服务
 *
 * 职责：管理技法库的加载、过滤和注入
 * 从 chat-orchestrator.service.ts 提取，减少主文件职责
 *
 * DI 注册名：'techniquePoolService'
 */

import * as path from 'path';
import * as fs from 'fs';

export interface TechniqueData {
  id: string;
  name: string;
  source: string;
  difficulty: string;
  category: string;
  applicableSyndromes: string[];
  description: string;
  coreId?: string;
}

export interface TechniqueFilter {
  coreId?: string;
  syndromeIds?: string[];
}

export class TechniquePoolService {
  private techniquePoolData: TechniqueData[] | null = null;

  constructor(private resourcesRoot: string) {}

  /**
   * 加载技法数据（延迟加载，只加载一次）
   */
  private loadTechniquePool(): TechniqueData[] {
    if (this.techniquePoolData) return this.techniquePoolData;

    try {
      const techniquePath = path.join(this.resourcesRoot, 'config/technique-library.json');
      const raw = fs.readFileSync(techniquePath, 'utf-8');
      this.techniquePoolData = JSON.parse(raw) as TechniqueData[];
      return this.techniquePoolData;
    } catch (err) {
      console.warn('[TechniquePool] Failed to load technique-library.json:', err);
      return [];
    }
  }

  /**
   * 根据过滤条件获取技法列表
   */
  getFiltered(filter?: TechniqueFilter): TechniqueData[] {
    let filtered = this.loadTechniquePool();

    if (filter?.coreId) {
      filtered = filtered.filter(t => t.coreId === filter.coreId);
    }
    if (filter?.syndromeIds && filter.syndromeIds.length > 0) {
      filtered = filtered.filter(t =>
        t.applicableSyndromes.some(s => filter.syndromeIds!.includes(s)),
      );
    }

    return filtered;
  }

  /**
   * 将技法库注入到提示词中
   */
  injectIntoPrompt(prompt: string, filter?: TechniqueFilter): string {
    if (!prompt.includes('{{technique_pool}}')) return prompt;

    const filtered = this.getFiltered(filter);

    if (this.techniquePoolData === null && filtered.length === 0) {
      // 加载失败的情况
      return prompt.replace('{{technique_pool}}', '（技法库加载失败，请根据症候自行匹配技法）');
    }

    const lines = filtered.map(t =>
      `- ${t.id} ${t.name}（来源：${t.source}，难度：${t.difficulty}，适用症候：${t.applicableSyndromes.join('/')}）：${t.description}`,
    );
    const poolText = lines.join('\n') || '（无匹配技法）';

    return prompt.replace('{{technique_pool}}', poolText);
  }
}
