/**
 * 后备资料库 —— 运行时检索与调用（Loader）
 *
 * 被 Teaching Agent（03-teaching）在生成教练话术前调用，按「诊断症候 / 教学场景 /
 * 自由查询」组合出应注入的参考资料（availableReferences），形态对齐现有
 * availableTechniques。资料库只提供创作知识，不替用户写、不替用户决定。
 *
 * 数据来源（见 schema.ts）：
 *  - entries/library-entries.json  知识卡全集
 *  - library-index.json            分类树 + 倒排索引（由 scripts/build-index.mjs 生成）
 */

import rawEntries from './entries/library-entries.json';
import rawIndex from './library-index.json';
import type {
  ReferenceEntry,
  LibraryIndex,
  TeachingContext,
  InjectableReference,
  TeachingScenario,
} from './schema';

const ENTRIES = rawEntries as ReferenceEntry[];
const INDEX = rawIndex as LibraryIndex;

const byId = new Map<string, ReferenceEntry>(ENTRIES.map((e) => [e.id, e]));

/**
 * 缓存对账（cache reconciliation）：
 * library-entries.json 是知识卡的唯一事实源，library-index.json 是派生缓存。
 * 若二者因未及时重新运行 build-index.mjs 而漂移（例如新增卡未进索引），
 * 此处兜底把 entries 中缺失于索引的条目补入各倒排表，保证检索永不遗漏新卡。
 * 幂等：已存在的映射不会重复添加。
 */
function reconcileIndex(): void {
  const addUnique = (arr: string[], id: string): void => {
    if (!arr.includes(id)) arr.push(id);
  };
  for (const e of ENTRIES) {
    for (const s of e.relatedSyndromes || []) addUnique(INDEX.syndromeMap[s] ||= [], e.id);
    for (const sc of e.scenarios || []) addUnique(INDEX.scenarioMap[sc] ||= [], e.id);
    const tokens = new Set<string>([
      ...(e.retrievalKeywords || []),
      ...(e.title || '').split(/\s+/),
      e.categoryLabel ?? '',
    ]);
    for (const raw of tokens) {
      const k = raw.toLowerCase().trim();
      if (!k) continue;
      addUnique(INDEX.keywordIndex[k] ||= [], e.id);
    }
  }
}
reconcileIndex();

function toInjectable(e: ReferenceEntry): InjectableReference {
  return {
    id: e.id,
    title: e.title,
    summary: e.summary,
    corePoints: e.corePoints,
    examples: e.examples,
    teachingTips: e.teachingTips,
    difficulty: e.difficulty,
  };
}

/** 按诊断症候取条目（最精准的「诊断→资料」路由） */
export function getBySyndrome(syndromeId: string, limit = 8): ReferenceEntry[] {
  const ids = INDEX.syndromeMap[syndromeId] ?? [];
  return ids.map((id) => byId.get(id)).filter(Boolean).slice(0, limit) as ReferenceEntry[];
}

/** 按一级/二级分类取条目（浏览/扩展阅读） */
export function getByCategory(categoryId: string, limit = 12): ReferenceEntry[] {
  return ENTRIES.filter(
    (e) => e.category === categoryId || e.subcategory === categoryId
  ).slice(0, limit);
}

/** 按教学场景取条目 */
export function getByScenario(scenario: TeachingScenario, limit = 8): ReferenceEntry[] {
  const ids = INDEX.scenarioMap[scenario] ?? [];
  return ids.map((id) => byId.get(id)).filter(Boolean).slice(0, Math.max(limit, ids.length)) as ReferenceEntry[];
}

function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[\s,，。、；;:：！!？?（）()""''《》<>/]+/)
    .map((t) => t.trim())
    .filter(Boolean);
}

/**
 * 关键词/语义检索：在倒排索引上做召回，再用标题与核心要点打分排序。
 * 轻量、可预测，适合端侧/主进程直接运行；后续可替换为向量检索而不改接口。
 *
 * 兼容性：中文查询通常无空格，故除分词召回外，额外对「条目关键词是否为查询子串」
 * 做匹配（CJK 友好），避免整句查询漏召。
 */
export function search(
  query: string,
  opts: { difficulty?: ReferenceEntry['difficulty']; limit?: number } = {}
): ReferenceEntry[] {
  const limit = opts.limit ?? 8;
  const qTokens = tokenize(query);
  const qLower = query.toLowerCase();
  const scored = new Map<string, number>();

  for (const t of qTokens) {
    for (const id of INDEX.keywordIndex[t] ?? []) {
      scored.set(id, (scored.get(id) ?? 0) + 3); // 关键词索引命中权重高
    }
  }
  for (const e of ENTRIES) {
    let kwHit = false;
    for (const kw of e.retrievalKeywords) {
      if (kw && qLower.includes(kw.toLowerCase())) {
        scored.set(e.id, (scored.get(e.id) ?? 0) + 3); // 关键词子串命中（CJK 友好）
        kwHit = true;
      }
    }
    if (kwHit) continue;
    // 标题与核心要点二次打分（覆盖索引未收录的措辞）
    const hay = (e.title + ' ' + e.corePoints.join(' ')).toLowerCase();
    for (const t of qTokens) {
      if (t.length >= 2 && hay.includes(t)) {
        scored.set(e.id, (scored.get(e.id) ?? 0) + 1);
      }
    }
  }

  return [...scored.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([id]) => byId.get(id))
    .filter((e): e is ReferenceEntry => Boolean(e))
    .filter((e) => (opts.difficulty ? e.difficulty === opts.difficulty : true))
    .slice(0, limit);
}

/**
 * 核心 API：根据教学上下文组合应注入的参考资料。
 * 路由优先级：诊断症候命中 > 场景命中 > 自由查询命中；结果去重并按相关度排序。
 */
export function getForTeachingContext(ctx: TeachingContext): InjectableReference[] {
  const limit = ctx.limit ?? 6;
  const ranked = new Map<string, number>();

  if (ctx.syndrome) {
    for (const e of getBySyndrome(ctx.syndrome)) {
      ranked.set(e.id, (ranked.get(e.id) ?? 0) + 10);
    }
  }
  for (const e of getByScenario(ctx.scenario)) {
    ranked.set(e.id, (ranked.get(e.id) ?? 0) + 5);
  }
  if (ctx.query) {
    for (const e of search(ctx.query, { limit: limit * 2 })) {
      ranked.set(e.id, (ranked.get(e.id) ?? 0) + 2);
    }
  }

  return [...ranked.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([id]) => byId.get(id))
    .filter((e): e is ReferenceEntry => Boolean(e))
    .map(toInjectable);
}

/** 取分类树（供 UI 呈现 / Onboarding 引导） */
export function getTaxonomy() {
  return INDEX.taxonomy;
}

/** 统计信息（调试/自检用） */
export function stats() {
  return {
    totalEntries: ENTRIES.length,
    categories: INDEX.taxonomy.length,
    syndromesCovered: Object.keys(INDEX.syndromeMap).length,
    keywordTokens: Object.keys(INDEX.keywordIndex).length,
  };
}
