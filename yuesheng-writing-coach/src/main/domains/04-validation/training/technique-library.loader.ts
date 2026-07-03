/**
 * technique-library.loader.ts — 技法库加载器(main 端)
 *
 * 职责:从 resources/config/technique-library.json 读取技法数据,
 *      替代 service 中 `import xxx from '*.json'` 的反模式(违反 R-014)。
 *      供 TrainingFlowService 在生成 TrainingFlow 时查询技法详情。
 *
 * 缓存:模块级单例,process lifetime 内只读一次。
 *
 * 依据:BL-01 R-014 配置外置重构
 */

import techniqueLibraryJson from '../../../../../resources/config/technique-library.json';

export interface TechniqueEntry {
  id: string;
  name: string;
  source: string;
  difficulty: string;
  category: string;
  discoverable?: boolean;
  applicableSyndromes: string[];
  description: string;
  example?: string;
  exercise?: string;
  coreId?: string;
  coreName?: string;
  difficultyOrder?: number;
}

const techniques = techniqueLibraryJson as unknown as TechniqueEntry[];

if (!Array.isArray(techniques) || techniques.length === 0) {
  throw new Error(
    '[technique-library.loader] technique-library.json 必须为非空数组',
  );
}

const techniquesById = new Map<string, TechniqueEntry>();
const techniquesByName = new Map<string, TechniqueEntry>();
for (const t of techniques) {
  if (!t.id || !t.name) {
    throw new Error(
      `[technique-library.loader] 技法缺少 id/name:${JSON.stringify(t).slice(0, 80)}`,
    );
  }
  if (techniquesById.has(t.id)) {
    throw new Error(
      `[technique-library.loader] 技法 id 重复:${t.id}`,
    );
  }
  techniquesById.set(t.id, t);
  techniquesByName.set(t.name, t);
}

/** 获取所有技法(只读快照) */
export function getAllTechniques(): readonly TechniqueEntry[] {
  return techniques;
}

/** 按 id 或 name 查找技法 */
export function findTechnique(nameOrId: string): TechniqueEntry | undefined {
  return techniquesById.get(nameOrId) ?? techniquesByName.get(nameOrId);
}

/** 获取所有分类(去重) */
export function getTechniqueCategories(): string[] {
  return [...new Set(techniques.map((t) => t.category).filter(Boolean))];
}
