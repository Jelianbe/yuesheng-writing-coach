// 资料库索引构建脚本
// 读取 entries/library-entries.json，生成 library-index.json（分类树 + 倒排索引）。
// 用法：node scripts/build-index.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');
const entries = JSON.parse(
  readFileSync(join(root, 'entries', 'library-entries.json'), 'utf8')
);

// ---- 分类树（与 schema.ts 的 CategoryNode 对应）----
const taxonomy = [
  {
    id: 'C1', label: '故事结构', description: '组织叙事的骨架与节拍，决定故事的形与节奏。',
    children: [
      { id: 'C1.1', label: '三幕式', description: '建置—对抗—结局的底层骨架。' },
      { id: 'C1.2', label: '英雄之旅', description: '坎贝尔/沃格勒的十二阶段心理蜕变图谱。' },
      { id: 'C1.3', label: '救猫咪节拍表', description: '斯奈德 15 节拍，控制商业节奏。' },
      { id: 'C1.4', label: '故事圆环/起承转结', description: '更轻量的结构变体。' },
      { id: 'C1.5', label: '结构选择指南', description: '按类型与主题选结构。' }
    ]
  },
  {
    id: 'C2', label: '人物塑造', description: '让角色可信、有棱角、能成长。',
    children: [
      { id: 'C2.1', label: '人物弧光', description: '正向/负向/平弧三种契约。' },
      { id: 'C2.2', label: '动机设计', description: '想要vs需要、谎言/创伤/真相、GMC。' },
      { id: 'C2.3', label: '立体人物', description: '可共鸣+出众+真实缺陷。' },
      { id: 'C2.4', label: '配角与反派', description: '独立 GMC，避免工具人。' }
    ]
  },
  {
    id: 'C3', label: '世界观构建', description: '多层级设定系统与信息释放纪律。',
    children: [
      { id: 'C3.1', label: '设定层级', description: '物理/社会/文化/历史同心圆。' },
      { id: 'C3.2', label: '力量/魔法体系', description: '硬软魔法与桑德森三定律。' },
      { id: 'C3.3', label: '信息释放', description: '滴灌而非倾倒。' },
      { id: 'C3.4', label: '世界一致性', description: '规则自洽，避免降神。' }
    ]
  },
  {
    id: 'C4', label: '情节与冲突', description: '驱动故事前进的引擎。',
    children: [
      { id: 'C4.1', label: '冲突类型', description: '内外双线如何咬合。' },
      { id: 'C4.2', label: '悬念与张力', description: '让读者想翻页。' },
      { id: 'C4.3', label: '场景结构', description: '目标—冲突—转折单元。' },
      { id: 'C4.4', label: '节奏', description: '呼吸感与升级。' }
    ]
  },
  {
    id: 'C5', label: '叙事视角与文风', description: '读者借谁的眼睛看、离角色多近。',
    children: [
      { id: 'C5.1', label: '视角类型', description: '第一/第二/第三人称及变体。' },
      { id: 'C5.2', label: '视角距离', description: '叙事距离谱与头跳。' },
      { id: 'C5.3', label: '展示与告知', description: '让读者感受而非被告知。' },
      { id: 'C5.4', label: '文风节制', description: '描写经济与紫废话规避。' }
    ]
  },
  {
    id: 'C6', label: '对话写作', description: '用对话塑人、推进、埋线、制造潜台词。',
    children: [
      { id: 'C6.1', label: '对话功能', description: '不止传递信息。' },
      { id: 'C6.2', label: '潜台词', description: '说的与想的不一样。' },
      { id: 'C6.3', label: '语音个性化', description: '每个角色有自己的说话方式。' },
      { id: 'C6.4', label: '节奏与标签', description: 'beats 与 said-book。' }
    ]
  },
  {
    id: 'C7', label: '常见创作误区', description: '新手高频踩坑与规避。',
    children: [
      { id: 'C7.1', label: '信息倾泻', description: 'info dump。' },
      { id: 'C7.2', label: '玛丽苏/工具人', description: '完美主角与功能配角。' },
      { id: 'C7.3', label: '机械降神', description: 'deus ex machina。' },
      { id: 'C7.4', label: '开头乏力/节奏失控', description: '钩子与呼吸感。' },
      { id: 'C7.5', label: '视角混乱/杂项', description: '头跳、被动语态、紫废话等。' }
    ]
  }
];

// ---- 倒排索引 ----
const syndromeMap = {};
const scenarioMap = {
  onboarding: [], 'post-diagnosis': [], 'in-flow-coaching': [],
  'pre-training': [], 'contrast-demo': [], browse: [], review: []
};
const keywordIndex = {};

for (const e of entries) {
  for (const s of e.relatedSyndromes || []) {
    (syndromeMap[s] ||= []).push(e.id);
  }
  for (const sc of e.scenarios || []) {
    (scenarioMap[sc] ||= []).push(e.id);
  }
  const tokens = new Set([
    ...(e.retrievalKeywords || []),
    ...(e.title || '').split(/\s+/),
    e.categoryLabel
  ]);
  for (const raw of tokens) {
    const k = raw.toLowerCase().trim();
    if (!k) continue;
    (keywordIndex[k] ||= []).push(e.id);
  }
}

const index = {
  version: '1.0',
  updatedAt: new Date().toISOString().slice(0, 10),
  description: '后备资料库索引：分类树 + 症候映射 + 场景映射 + 关键词倒排索引。由 scripts/build-index.mjs 生成。',
  taxonomy,
  syndromeMap,
  scenarioMap,
  keywordIndex
};

writeFileSync(join(root, 'library-index.json'), JSON.stringify(index, null, 2), 'utf8');
console.log(`build-index: wrote library-index.json with ${entries.length} entries, ${Object.keys(keywordIndex).length} keyword tokens.`);
