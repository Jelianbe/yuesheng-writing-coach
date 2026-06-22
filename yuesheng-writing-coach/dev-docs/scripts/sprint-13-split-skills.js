// Sprint 13 Phase 1: 拆分 yuesheng-prompt-v5.md 为 6 个 SKILL 文件
// 用 Node.js (UTF-8) 写文件，避免 PowerShell 5.1 中文编码问题
// 内容逐字逐段从 v5.md 复制（行范围已审计）

const fs = require('fs');
const path = require('path');

const V5_PATH = 'resources/prompts/yuesheng-prompt-v5.md';
const SKILLS_DIR = 'resources/prompts/skills';

// 行范围（0-indexed, [start, end] inclusive, 用于 slice(start, end+1)）
// 来源：审计 v5.md 的 `## ` 标题位置
const slices = [
  {
    file: 'core-identity.md',
    start: 20,  // line 21: ## 一、铁三角（核心层，必须遵守）
    end: 83,    // line 84: 2.6 底线清单最后一行
    id: 'core-identity',
    title: '身份与底线',
    estimatedTokens: 1500,
    phases: ['P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    source: 'yuesheng-prompt-v5.md §一+§二+§2.6',
    loadWhenDesc: '所有 phase 必加载（身份是基础层）',
  },
  {
    file: 'teaching-strategy.md',
    start: 93,  // line 94: ## 三、教学策略铁律
    end: 262,   // line 263: 6.3 核心约束最后一行
    id: 'teaching-strategy',
    title: '教学策略',
    estimatedTokens: 3200,
    phases: ['P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    source: 'yuesheng-prompt-v5.md §三+§四+§五+§六',
    loadWhenDesc: '所有 phase 必加载（教学策略贯穿全流程）',
  },
  {
    file: 'reference-drawer.md',
    start: 265,  // line 266: ## 九、参考抽屉（按需调用）
    end: 308,    // line 309: 10.2 能力边界声明最后一行
    id: 'reference-drawer',
    title: '参考抽屉',
    estimatedTokens: 800,
    phases: ['P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    source: 'yuesheng-prompt-v5.md §九+§十',
    loadWhenDesc: '仅在 P2/P3/P4 加载（参考和信念属于进阶使用）',
  },
  {
    file: 'validation-rules.md',
    start: 318,  // line 319: ## 八、输出验证（回复完成后逐项检查）
    end: 378,    // line 379: V-09 检测标准最后一行
    id: 'validation-rules',
    title: '输出验证',
    estimatedTokens: 1700,
    phases: ['P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    source: 'yuesheng-prompt-v5.md §八',
    loadWhenDesc: '所有 phase 必加载（合规校验是硬约束）',
  },
  {
    file: 'feedback-cognition.md',
    start: 388,  // line 389: ## 七、认知反馈层（训练透明化）
    end: 444,    // line 445: 7.5 同侪感最后一行
    id: 'feedback-cognition',
    title: '认知反馈',
    estimatedTokens: 900,
    phases: ['P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    source: 'yuesheng-prompt-v5.md §七',
    loadWhenDesc: '仅在 P2/P3/P4 加载（认知反馈是训练后环节）',
  },
  {
    file: 'scenario-rules.md',
    start: 454,  // line 455: > 以下为特定场景下的强制话术和策略...
    end: 509,    // line 510: **场景6（要求改写）**...最后一行
    id: 'scenario-rules',
    title: '场景规则扩展',
    estimatedTokens: 1100,
    phases: ['P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    source: 'yuesheng-prompt-v5.md §十一',
    loadWhenDesc: '所有 phase 必加载（场景规则是触发式硬约束）',
  },
];

// 验证 v5.md 存在
if (!fs.existsSync(V5_PATH)) {
  console.error('FATAL: v5.md not found at ' + V5_PATH);
  process.exit(1);
}

// 读取 v5.md（按 \n 分割，不用 \r\n，避免 Windows CRLF 问题）
const rawContent = fs.readFileSync(V5_PATH, 'utf-8');
const lines = rawContent.split(/\r?\n/);
console.log('v5.md total lines:', lines.length);
console.log('v5.md total bytes:', Buffer.byteLength(rawContent, 'utf-8'));

// 确保 skills 目录存在
if (!fs.existsSync(SKILLS_DIR)) {
  fs.mkdirSync(SKILLS_DIR, { recursive: true });
  console.log('Created directory:', SKILLS_DIR);
}

// 写入每个 SKILL 文件
let totalContentBytes = 0;
for (const s of slices) {
  const contentLines = lines.slice(s.start, s.end + 1);
  const content = contentLines.join('\n');
  const contentBytes = Buffer.byteLength(content, 'utf-8');
  totalContentBytes += contentBytes;

  // YAML frontmatter + 标题 + 来源/loadWhen + 内容
  const yaml = [
    '---',
    'id: ' + s.id,
    'estimatedTokens: ' + s.estimatedTokens,
    'loadWhen:',
    '  phases: [' + s.phases.join(', ') + ']',
    '  attitudes: [doubao, yuesheng, sensei]',
    '---',
    '',
    '# SKILL: ' + s.title,
    '',
    '> **来源**: ' + s.source,
    '> **loadWhen**: ' + s.loadWhenDesc,
    '',
    content,
  ].join('\n');

  const outPath = path.join(SKILLS_DIR, s.file);
  // 用 UTF-8 写入，不带 BOM
  fs.writeFileSync(outPath, yaml, { encoding: 'utf-8' });

  const outBytes = Buffer.byteLength(yaml, 'utf-8');
  console.log(
    'Wrote ' + outPath + ': ' + outBytes + ' bytes (content ' + contentBytes + ' bytes, ' + contentLines.length + ' lines)'
  );
}

console.log('---');
console.log('Total content bytes (sum of 6 files, sans frontmatter):', totalContentBytes);
console.log('v5.md total bytes:', Buffer.byteLength(rawContent, 'utf-8'));
console.log('v5.md header/wrapper overhead:', Buffer.byteLength(rawContent, 'utf-8') - totalContentBytes);
