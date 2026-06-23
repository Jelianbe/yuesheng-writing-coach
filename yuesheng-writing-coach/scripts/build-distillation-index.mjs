#!/usr/bin/env node
/**
 * 蒸馏素材索引构建器
 * Sprint 15 T15-A：把 3 个 MD 文件 + 1 个标签索引合并为 distillation-index.json
 *
 * 输入：
 *   1) resources/01-diagnosis/signals/写作蒸馏素材-200条-避雷与教学指导.md
 *      → 批次 001：避雷 100 (B-001~100) + 教学 100 (J-001~100) = 200 条
 *   2) resources/01-diagnosis/signals/写作蒸馏素材-扩展第2批-实战困境与习惯养成200条.md
 *      → 批次 002：困境 100 (K-001~100) + 习惯 100 (X-001~100) = 200 条
 *   3) resources/01-diagnosis/signals/写作蒸馏素材-扩展第3批-情节场景对话补充61条.md
 *      → 批次 003：PL-25 + SC-18 + DG-18 = 61 条
 *   4) resources/01-diagnosis/signals/素材症候标签索引-D03.md
 *      → 400 条已标注定稿（仅覆盖批次 001+002）
 *
 * 输出：
 *   resources/distillation-index.json
 *
 * ID 命名规范（Sprint 15 T15-D）：
 *   DST-{3位批次号}-{3位序号}
 *   DST-001-001 ~ DST-001-200 (批次 001)
 *   DST-002-001 ~ DST-002-200 (批次 002)
 *   DST-003-001 ~ DST-003-061 (批次 003)
 *
 * 决策记录：
 *   - LLM 预标 + 人工校核 10%：批次 001+002 用 D03 索引（已标注），批次 003 暂用启发式占位
 *   - 旧 ID 保留在 legacyId 字段，避免破坏现有引用
 */

import * as fs from 'fs';
import * as path from 'path';

const ROOT = path.resolve(import.meta.dirname, '..');
const SIGNALS = path.join(ROOT, 'resources/01-diagnosis/signals');
const OUT = path.join(ROOT, 'resources/distillation-index.json');

// ===== 工具函数 =====

/** "P001" / "P001_pos" 解析为 { base: "P001", isPos: bool } */
function parseSyndromeId(s) {
  if (!s) return null;
  const t = s.trim();
  if (t === '' || t === '-') return null;
  const isPos = t.endsWith('_pos');
  const base = isPos ? t.slice(0, -4) : t;
  return { base, isPos, original: t };
}

/** 从单行内容里提取【平台】标识，返回 { platform, body } */
function splitPlatform(line) {
  const m = line.match(/^(\d+)\s*\.?\s*【([^】]+)】\s*(.*)$/);
  if (!m) return { platform: null, body: line, num: null };
  return { platform: m[2], body: m[3], num: parseInt(m[1], 10) };
}

// ===== 批次 001 解析器（避雷 100 + 教学 100） =====

/**
 * 解析 "200条-避雷与教学指导.md"
 *
 * 文件结构（混合两种格式）：
 *   第一部分：写作避雷 100 条 — 列表格式 `数字.【平台】描述内容`
 *   第二部分：写作教学指导 100 条 — 表格格式 `| 序号 | 平台 | 标题 | 作者 | 技法 |`
 *
 * 批次 001 范围：仅取避雷 1-100 + 教学 1-100 = 200 条
 * （文件后续 201+ 是"长期坚持方法论"等扩展内容，不纳入本期批次 001）
 *
 * ID 映射：
 *   避雷 序号 n → DST-001-{n}      legacyId=B-{n}
 *   教学 序号 n → DST-001-{100+n}  legacyId=J-{n}
 */
function parseBatch001() {
  const fp = path.join(SIGNALS, '写作蒸馏素材-避雷与教学指导200条-2026-06-20.md');
  const altFp = path.join(SIGNALS, '写作蒸馏素材-200条-避雷与教学指导.md');
  const realFp = fs.existsSync(fp) ? fp : altFp;
  const text = fs.readFileSync(realFp, 'utf-8');
  const lines = text.split(/\r?\n/);

  const entries = [];
  let currentCategory = null;
  let part = 'unknown'; // 'leilei' (避雷) or 'jiaoxue' (教学)
  let inTable = false; // 是否在表格中

  for (const line of lines) {
    // 第二部分标题识别
    if (/^# 第二部分/.test(line)) {
      part = 'jiaoxue';
      inTable = false;
      continue;
    }
    if (/^# 第一部分/.test(line)) {
      part = 'leilei';
      inTable = false;
      continue;
    }

    // 章节标题：## 一、xxx（第 1-20 条）
    const h2Match = line.match(/^##\s*([^（]+)/);
    if (h2Match) {
      currentCategory = h2Match[1].trim();
      continue;
    }

    // 表格表头：| 序号 | 平台 | 标题/主题 | 作者 | 核心技法 |
    if (line.match(/^\|\s*序号\s*\|/)) {
      inTable = true;
      continue;
    }
    // 表格分隔行：|------|------|...
    if (line.match(/^\|[\s-:|]+\|$/)) {
      continue;
    }

    if (part === 'leilei') {
      // 列表格式：数字.【平台】描述
      const itemMatch = line.match(/^(\d+)\s*\.\s*【([^】]+)】\s*(.+)$/);
      if (!itemMatch || !currentCategory) continue;
      const seq = parseInt(itemMatch[1], 10);
      if (seq < 1 || seq > 100) continue; // 只取 1-100

      const platform = itemMatch[2].trim();
      const body = itemMatch[3].trim();
      const newId = `DST-001-${String(seq).padStart(3, '0')}`;
      const legacyId = `B-${String(seq).padStart(3, '0')}`;

      entries.push({
        id: newId,
        legacyId,
        batch: '001',
        batchLabel: '避雷100条',
        category: currentCategory,
        platform,
        summary: body.slice(0, 20),
        content: body,
        syndromes: { primary: null, secondary: [] },
        teachingAction: null,
        keywordTags: [],
        taggedBy: 'heuristic',
        sourceFile: 'resources/01-diagnosis/signals/写作蒸馏素材-200条-避雷与教学指导.md',
      });
    } else if (part === 'jiaoxue' && inTable) {
      // 表格格式：| 序号 | 平台 | 标题 | 作者 | 技法 |
      const cells = line.split('|').map(c => c.trim()).filter(c => c !== '');
      if (cells.length < 4) continue;
      const seq = parseInt(cells[0], 10);
      if (isNaN(seq) || seq < 1 || seq > 100) continue; // 只取 1-100

      const platform = cells[1] || '';
      const title = cells[2] || '';
      const author = cells[3] || '';
      const technique = cells[4] || '';

      const newId = `DST-001-${String(100 + seq).padStart(3, '0')}`;
      const legacyId = `J-${String(seq).padStart(3, '0')}`;

      entries.push({
        id: newId,
        legacyId,
        batch: '001',
        batchLabel: '教学指导100条',
        category: currentCategory,
        platform,
        summary: title.slice(0, 20),
        content: `${title}（作者：${author}）— ${technique}`,
        syndromes: { primary: null, secondary: [] },
        teachingAction: technique,
        keywordTags: [],
        taggedBy: 'heuristic',
        sourceFile: 'resources/01-diagnosis/signals/写作蒸馏素材-200条-避雷与教学指导.md',
      });
    }
  }

  return entries;
}

// ===== 批次 002 解析器（困境 100 + 习惯 100，表格格式） =====

/**
 * 解析 "扩展第2批-实战困境与习惯养成200条.md"
 *
 * 文件结构（两个部分各自独立编号 1-100）：
 *   第一部分：写作实战困境（100条）— 表格列：序号 / 困境描述 / 原因 / 方案 / 来源
 *   第二部分：写作习惯养成（100条）— 表格列：序号 / 问题 / 方法 / 步骤 / 来源
 *
 * 批次 002 范围：第一部分 1-100 + 第二部分 1-100 = 200 条
 *
 * ID 映射：
 *   困境 序号 n → DST-002-{n}     legacyId=K-{n}
 *   习惯 序号 n → DST-002-{100+n} legacyId=X-{n}
 */
function parseBatch002() {
  const fp = path.join(SIGNALS, '写作蒸馏素材-扩展第2批-实战困境与习惯养成200条.md');
  const text = fs.readFileSync(fp, 'utf-8');
  const lines = text.split(/\r?\n/);

  const entries = [];
  let currentCategory = null;
  let part = 'unknown'; // 'kunjing' (困境) or 'xiguan' (习惯)
  let columns = null; // 表格列定义

  for (const line of lines) {
    // 部分识别
    if (/^# 第一部分/.test(line) || /^## 第一部分/.test(line)) {
      part = 'kunjing';
      columns = null;
      continue;
    }
    if (/^# 第二部分/.test(line) || /^## 第二部分/.test(line)) {
      part = 'xiguan';
      columns = null;
      continue;
    }

    // 章节：### 一、xxx（15条）
    const h3Match = line.match(/^###\s*([^（]+)/);
    if (h3Match) {
      currentCategory = h3Match[1].trim();
      continue;
    }

    // 表格表头
    if (line.startsWith('| 序号') || line.match(/^\|\s*序号\s*\|/)) {
      // 解析列名
      const headerCells = line.split('|').map(c => c.trim()).filter(c => c !== '');
      columns = headerCells;
      continue;
    }
    // 表格分隔行
    if (line.match(/^\|[\s-:|]+\|$/)) {
      continue;
    }

    // 表格数据行
    if (!line.startsWith('|') || !columns || !currentCategory || part === 'unknown') continue;
    const cells = line.split('|').map(c => c.trim()).filter(c => c !== '');
    if (cells.length < 3) continue;

    const seq = parseInt(cells[0], 10);
    if (isNaN(seq) || seq < 1 || seq > 100) continue;

    // 按列定义取值
    const get = idx => (idx < cells.length ? cells[idx] : '');

    let legacyId, newId, batchLabel, summary, content;
    if (part === 'kunjing') {
      // 困境：序号 / 困境描述 / 原因 / 方案 / 来源
      legacyId = `K-${String(seq).padStart(3, '0')}`;
      newId = `DST-002-${String(seq).padStart(3, '0')}`;
      batchLabel = '实战困境100条';
      summary = get(1).slice(0, 20);
      content = `${get(1)} | 原因: ${get(2)} | 方案: ${get(3)}`;
    } else {
      // 习惯：序号 / 问题 / 方法 / 步骤 / 来源
      legacyId = `X-${String(seq).padStart(3, '0')}`;
      newId = `DST-002-${String(100 + seq).padStart(3, '0')}`;
      batchLabel = '习惯养成100条';
      summary = get(1).slice(0, 20);
      content = `${get(1)} | 方法: ${get(2)} | 步骤: ${get(3)}`;
    }

    entries.push({
      id: newId,
      legacyId,
      batch: '002',
      batchLabel,
      category: currentCategory,
      platform: get(columns.length - 1), // 最后一列总是来源
      summary,
      content,
      syndromes: { primary: null, secondary: [] },
      teachingAction: get(part === 'kunjing' ? 3 : 2), // 方案 or 方法
      keywordTags: [],
      taggedBy: 'heuristic',
      sourceFile: 'resources/01-diagnosis/signals/写作蒸馏素材-扩展第2批-实战困境与习惯养成200条.md',
    });
  }

  return entries;
}

// ===== 批次 003 解析器（PL-25 + SC-18 + DG-18，表格格式） =====

/**
 * 解析 "扩展第3批-情节场景对话补充61条.md"
 * 表格：| 编号 | 具体问题/技法描述 | 解决方案或核心要点 | 来源平台 |
 * 三个 section：PL-01~25（情节）/ SC-01~18（场景）/ DG-01~18（对话）
 */
function parseBatch003() {
  const fp = path.join(SIGNALS, '写作蒸馏素材-扩展第3批-情节场景对话补充61条.md');
  const text = fs.readFileSync(fp, 'utf-8');
  const lines = text.split(/\r?\n/);

  const entries = [];
  let currentCategory = null;
  let sectionIndex = 0; // 批次 003 内部序号计数器

  for (const line of lines) {
    // 章节：## 第一部分：情节薄弱 额外素材（25条）
    const h2Match = line.match(/^##\s*([^（]+)/);
    if (h2Match) {
      currentCategory = h2Match[1].trim();
      continue;
    }

    // 表格行
    if (!line.startsWith('|') || line.match(/^\|[\s-:|]+\|$/)) continue;
    const cells = line.split('|').map(c => c.trim()).filter(c => c !== '');
    if (cells.length < 3) continue;

    const code = cells[0]; // PL-01 / SC-01 / DG-01
    if (!/^[A-Z]{2}-\d{2}$/.test(code)) continue;

    const problem = cells[1] || '';
    const solution = cells[2] || '';
    const source = cells[3] || '';

    sectionIndex += 1;
    const newId = `DST-003-${String(sectionIndex).padStart(3, '0')}`;

    entries.push({
      id: newId,
      legacyId: code,
      batch: '003',
      batchLabel: code.startsWith('PL') ? '情节薄弱25条' : code.startsWith('SC') ? '场景描写18条' : '对话生硬18条',
      category: currentCategory,
      platform: source,
      summary: problem.slice(0, 20),
      content: `${problem} | 方案: ${solution}`,
      syndromes: { primary: null, secondary: [] },
      teachingAction: solution,
      keywordTags: [],
      taggedBy: 'heuristic',
      sourceFile: 'resources/01-diagnosis/signals/写作蒸馏素材-扩展第3批-情节场景对话补充61条.md',
    });
  }

  return entries;
}

// ===== D03 标签索引合并（400 条已标注） =====

/**
 * 解析 "素材症候标签索引-D03.md"
 * 表格：| 素材编号 | 来源文件 | 原文摘要(≤20字) | 主症候 | 次症候 | 教学动作(如有) |
 *
 * key = 素材编号（如 B-023, J-092, K-039, X-001）
 * 但实际文件 1 的素材 B-023 在 序列 = ?（批次 001 序号）
 * B-023 映射到 DST-001-023（避雷第 23 条 = 序号 23）
 * J-092 映射到 DST-001-192（教学第 92 条 = 序号 100+92=192）
 * K-039 映射到 DST-002-039（困境第 39 条 = 序号 39）
 * X-001 映射到 DST-002-101（习惯第 1 条 = 序号 100+1=101）
 */
function parseD03Index() {
  const fp = path.join(SIGNALS, '素材症候标签索引-D03.md');
  const text = fs.readFileSync(fp, 'utf-8');
  const lines = text.split(/\r?\n/);

  /** @type {Map<string, {primary: string, secondary: string[], teachingAction: string|null}>} */
  const tagMap = new Map();

  for (const line of lines) {
    // 表格数据行
    const m = line.match(/^\|\s*([A-Z]-\d{3})\s*\|\s*([^|]+)\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|\s*$/);
    if (!m) continue;

    const legacyId = m[1];
    const summary = m[3].trim();
    const primaryRaw = m[4].trim();
    const secondaryRaw = m[5].trim();
    const teachingAction = m[6].trim();

    const primary = parseSyndromeId(primaryRaw);
    const secondary = secondaryRaw
      ? secondaryRaw.split(/[，,]/).map(s => parseSyndromeId(s)?.original).filter(Boolean)
      : [];

    tagMap.set(legacyId, {
      summary,
      primary: primary?.original ?? null,
      primaryBase: primary?.base ?? null,
      isPos: primary?.isPos ?? false,
      secondary,
      teachingAction: teachingAction || null,
    });
  }

  return tagMap;
}

/** 把 legacyId (B-001, J-001, K-001, X-001) 映射到 DST-XXX-NNN */
function legacyIdToNewId(legacyId) {
  const m = legacyId.match(/^([A-Z])-(\d{3})$/);
  if (!m) return null;
  const prefix = m[1];
  const innerSeq = parseInt(m[2], 10);

  if (prefix === 'B') return `DST-001-${String(innerSeq).padStart(3, '0')}`;
  if (prefix === 'J') return `DST-001-${String(innerSeq + 100).padStart(3, '0')}`;
  if (prefix === 'K') return `DST-002-${String(innerSeq).padStart(3, '0')}`;
  if (prefix === 'X') return `DST-002-${String(innerSeq + 100).padStart(3, '0')}`;
  return null;
}

// ===== 主流程 =====

function main() {
  console.log('[build-distillation-index] 开始构建...');

  const batch001 = parseBatch001();
  const batch002 = parseBatch002();
  const batch003 = parseBatch003();
  const d03Tags = parseD03Index();

  console.log(`  批次 001: ${batch001.length} 条`);
  console.log(`  批次 002: ${batch002.length} 条`);
  console.log(`  批次 003: ${batch003.length} 条`);
  console.log(`  D03 标签: ${d03Tags.size} 条`);

  // 合并所有
  const all = [...batch001, ...batch002, ...batch003];

  // 应用 D03 标签（仅对批次 001+002）
  let taggedCount = 0;
  for (const entry of all) {
    if (entry.batch === '003') continue; // 第 3 批暂无标注
    const tags = d03Tags.get(entry.legacyId);
    if (!tags) continue;
    entry.syndromes.primary = tags.primary;
    entry.syndromes.secondary = tags.secondary;
    entry.teachingAction = entry.teachingAction || tags.teachingAction;
    entry.summary = tags.summary || entry.summary;
    entry.taggedBy = 'human';
    taggedCount += 1;
  }

  console.log(`  应用 D03 标签: ${taggedCount} 条`);

  // 输出 JSON
  const output = {
    version: '1.0.0',
    generatedAt: new Date().toISOString(),
    description: '蒸馏素材结构化索引（461 条）',
    sources: {
      batch001: 'resources/01-diagnosis/signals/写作蒸馏素材-200条-避雷与教学指导.md',
      batch002: 'resources/01-diagnosis/signals/写作蒸馏素材-扩展第2批-实战困境与习惯养成200条.md',
      batch003: 'resources/01-diagnosis/signals/写作蒸馏素材-扩展第3批-情节场景对话补充61条.md',
      tags: 'resources/01-diagnosis/signals/素材症候标签索引-D03.md',
    },
    statistics: {
      total: all.length,
      batch001: batch001.length,
      batch002: batch002.length,
      batch003: batch003.length,
      taggedByHuman: taggedCount,
      taggedByHeuristic: all.length - taggedCount,
    },
    entries: all,
  };

  fs.writeFileSync(OUT, JSON.stringify(output, null, 2), 'utf-8');
  console.log(`  写入 ${OUT}`);
  console.log(`  共 ${all.length} 条 / 已标注 ${taggedCount} 条 / 待标注 ${all.length - taggedCount} 条`);
  console.log('[build-distillation-index] 完成');
}

main();
