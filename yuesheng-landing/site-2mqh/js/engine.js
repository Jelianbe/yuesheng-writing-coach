// engine.js — 月笙 web 诊断页教学引擎（v1 最小闭环）
// 状态机与组装逻辑复刻自 yuesheng-flutter/lib/services/{phase_transition,skill_layers,skill_dispatcher,prompt_assembly_service}.dart
// 语料来自 corpus.js（真源机械提取，38/38 锚点对账一致）。简化项见施工卡登记。
'use strict';

// ─── 教学阶段 FSM（复刻 phase_transition.dart 逐条规则）──────────
const PHASE_ORDER = ['P0', 'P1', 'P2', 'P3', 'P4'];
const PHASE_LABELS = {
  P0: '破冰', P1: '建世界', P2: '练习循环', P3: '专项训练', P4: '复盘',
};
const SUBPHASES = ['DIAGNOSIS', 'PRACTICE', 'FEEDBACK'];
const SUBPHASE_LABELS = { DIAGNOSIS: '诊断', PRACTICE: '练习', FEEDBACK: '反馈' };

function phaseIndex(p) { return PHASE_ORDER.indexOf(p); }

// phase_transition.dart L33-46
function validatePhaseTransition(current, suggested) {
  if (current === suggested) return true;
  const ci = phaseIndex(current), si = phaseIndex(suggested);
  if (ci === -1 || si === -1) return false;
  if (si === ci + 1) return true;           // 正常递进
  if (current === 'P4' && suggested === 'P2') return true; // P4→P2 回退（下一训练周期）
  return false;
}

// phase_transition.dart L21-25
function nextPhase(current) {
  const i = phaseIndex(current);
  if (i === -1 || i >= PHASE_ORDER.length - 1) return null;
  return PHASE_ORDER[i + 1];
}

// phase_transition.dart L61-71（C-1 早期恰好跨一格降级）
function clampEarlyPhaseSkip(current, suggested) {
  const c = phaseIndex(current), s = phaseIndex(suggested);
  if (c < 0 || s < 0) return null;
  if (c > 1) return null;        // 仅 P0/P1
  if (s !== c + 2) return null;  // 仅恰好跨一格
  return PHASE_ORDER[c + 1];
}

// 应用阶段建议（模型 suggested_phase + 校验 + 降级），返回 {phase, changed, note}
function applyPhaseSuggestion(current, suggested) {
  if (!suggested || !PHASE_ORDER.includes(suggested) || suggested === current) {
    return { phase: current, changed: false, note: null };
  }
  if (validatePhaseTransition(current, suggested)) {
    return { phase: suggested, changed: true, note: null };
  }
  const clamped = clampEarlyPhaseSkip(current, suggested);
  if (clamped) {
    return { phase: clamped, changed: true, note: `早期跨格建议 ${current}→${suggested} 降级为 ${clamped}（C-1）` };
  }
  return { phase: current, changed: false, note: `非法迁移 ${current}→${suggested} 已拦截` };
}

// ─── L2 组决议（复刻 skill_layers.dart resolveL2Mode，web 无 beginner/outline 轨）──
// 简化登记：v1 不含 N 系零基础轨道与大纲语境（见施工卡「显式不做」）。
function resolveL2Mode(phase, subphase) {
  if (phase === 'P2') {
    if (!subphase || subphase === 'DIAGNOSIS') return 'diagnosis';
    if (subphase === 'PRACTICE' || subphase === 'FEEDBACK') return 'training';
  }
  if (phase === 'P1') return 'diagnosis';
  if (phase === 'P3' || phase === 'P4') return 'advanced';
  return 'none'; // P0
}

// skill_layers.dart L62-126（v2 替换已内化；contextHint 逐字保留）
const L2_MAP = {
  diagnosis: [
    ['coaching-actions-v2', '诊断语境：把症候映射到推荐动作卡'],
    ['syndrome-diagnosis-index', null],
    ['reader-awareness', '诊断语境：审视读者视角漏洞（信息/情绪/认知）'],
    ['writing-style', null],
    ['diagnosis-confirmation', null],
    ['feedback-cognition', null],
    ['coaching-rhythm', '诊断语境：P1 暴露差距，Layer2 认知桥接，先确认当下卡点'],
  ],
  training: [
    ['coaching-actions-v2', '训练语境：动作卡直接执行指引'],
    ['technique-library-index', null],
    ['training-loop-v2', null],
    ['training-templates-index', null],
    ['training-evaluation-v2', null],
    ['text-surgery-v2', null],
    ['demonstration', null],
    ['comparison', null],
    ['timed-rewrite', null],
    ['model-rewrite', null],
    ['revision-methodology', null],
    ['reader-awareness', '训练语境：聚焦反馈恐惧与读者视角的刻意练习'],
    ['writer-psychology', null],
  ],
  advanced: [
    ['advanced-phases', null],
    ['training-loop-v2', null],
    ['coaching-actions-v2', '进阶语境：P3 专项训练的动作编排'],
    ['revision-methodology', null],
    ['reader-awareness', '进阶语境：P4 复盘中的读者视角深化'],
    ['writing-style', null],
  ],
};

const L1_IDS = [
  'core-iron-triangle', 'core-product-identity', 'writing-anchors',
  'teaching-strategy', 'phase-mapper', 'scenario-rules', 'validation-rules',
  'teaching-modes', 'reply-voice',
];

const SKILL_SEPARATOR = '\n\n---\n\n';

// syndrome_knowledge_base.dart L51-64（注入面剔除，行形态判据）
function excludeNonDiagnosable(content) {
  const nd = CORPUS.syndromes.nonDiagnosable;
  if (!nd.length) return content;
  const re = /^\| (P\d{3}) [^|]+ \| A\d{3} /;
  return content.split('\n')
    .filter(line => { const m = line.match(re); return !(m && nd.includes(m[1])); })
    .join('\n');
}

// 注入点剔除（skill_dispatcher.dart L385-389）：索引按排除集重建行
// （buildSyndromeIndexContent({...disabled, ...kShortChainExcluded})，v1 disabled=∅）
function buildSyndromeIndexForInjection() {
  const nd = CORPUS.syndromes.nonDiagnosable;
  if (!nd.length) return CORPUS.syndromeIndex;
  return CORPUS.syndromeIndex.split('\n')
    .filter(line => { const m = line.match(/^\| (P\d{3}) \|/); return !(m && nd.includes(m[1])); })
    .join('\n');
}

// skill_dispatcher.dart buildSystemPromptV2 主链（v1 简化：无人格自定义/无已知位次块）
function buildSystemPrompt(ctx) {
  const { phase, subphase, attitude = 'yuesheng', teachingMode = 'socratic',
          forceSceneFirst = false } = ctx;
  const chunks = [];
  // 1. L1 九件套（顺序即缓存契约，勿改）
  for (const id of L1_IDS) {
    if (CORPUS.skills[id]) chunks.push(CORPUS.skills[id].content);
  }
  // 2. 态度档（L1 pinned block：紧跟九件套、在全部 L2 之前）
  const att = CORPUS.skills[`attitude-${attitude}`];
  if (att) chunks.push(att.content);
  // 3. 教学方式块（与人格档正交）
  const tm = CORPUS.skills[`teaching-mode-${teachingMode}`];
  if (tm) chunks.push(tm.content);
  // 4. L2 按需层
  const mode = resolveL2Mode(phase, subphase);
  for (const [id, hint] of (L2_MAP[mode] || [])) {
    if (id === 'syndrome-diagnosis-index') {
      chunks.push(buildSyndromeIndexForInjection());
    } else if (CORPUS.skills[id]) {
      chunks.push(excludeNonDiagnosable(CORPUS.skills[id].content));
    }
    if (hint) chunks.push(hint);
  }
  // 5. 诊断前置（diagnosis 模式或措辞强制）
  if (mode === 'diagnosis' || forceSceneFirst) {
    chunks.push(CORPUS.consts.diagnosisSceneFirst);
  }
  // 6. 位置判断引导（始终注入）
  chunks.push(CORPUS.consts.positionGuidance);
  // 7. 边界声明（始终注入末尾）
  chunks.push(CORPUS.consts.promptBoundary);
  return { systemPrompt: chunks.join(SKILL_SEPARATOR), l2Mode: mode };
}

// ─── L3 检索（复刻 syndrome_knowledge_base.dart / technique_knowledge_base.dart）──
function extractSection(raw, id) {
  const pat = `### ${id} `;
  const start = raw.indexOf(pat);
  if (start === -1) return '';
  const nextH3 = raw.indexOf('\n### ', start + 1);
  const nextH2 = raw.indexOf('\n## ', start + 1);
  let end = raw.length;
  if (nextH3 !== -1) end = nextH3;
  if (nextH2 !== -1 && nextH2 < end) end = nextH2;
  return raw.substring(start, end).trim();
}

function getSyndromeContent(syndromeIds) {
  const sections = syndromeIds.map(id => extractSection(CORPUS.syndromeManual, id)).filter(Boolean);
  if (!sections.length) return '';
  return CORPUS.consts.syndromeL3Header + sections.join('\n\n---\n\n');
}

function getSyndromeCriteriaSections(syndromeIds) {
  return syndromeIds.map(id => extractSection(CORPUS.syndromeManual, id)).filter(Boolean)
    .join('\n\n---\n\n');
}

function getTechniqueContent(techniqueIds) {
  const sections = techniqueIds.map(id => extractSection(CORPUS.techniqueLibrary, id)).filter(Boolean);
  if (!sections.length) return '';
  return CORPUS.consts.techniqueL3Header + sections.join('\n\n---\n\n');
}

// 注册表派生：症候 → 首选+第一备选技法
// ⚠️ 行尾用 \|[\s]* 而非 \| [空格]：映射行以 | 结尾无尾随空格，
//    旧正则因必配尾空格对全部 39 行失配 → 技法 L3 静默丢失（2026-11-12 实测修复）。
function getTechniquesBySyndrome(syndromeIds) {
  const set = new Set();
  for (const sid of syndromeIds) {
    const m = CORPUS.syndromeManual.match(new RegExp(`\\| ${sid} [^|]+ \\| (T\\d{3})[^|]*\\|[\\s]*(T\\d{3})?`));
    if (m) { set.add(m[1]); if (m[2]) set.add(m[2]); }
  }
  return getTechniqueContent([...set]);
}

// prompt_assembly_service.dart _firstRoundCriteriaMessages（W-17 首轮判据）
function buildFirstRoundCriteriaBlock() {
  const ids = CORPUS.syndromes.firstRoundCriteriaIds;
  const header = CORPUS.consts.firstRoundHeader;
  const sections = getSyndromeCriteriaSections(ids);
  const exemptions = '\n\n' + CORPUS.consts.firstRoundP034Exemptions;
  return `${header}\n\n${sections}${exemptions}`;
}

// ─── 消息序列组装（v1 简化：无画像注入/无引用/无预算闸门/无迟滞）──────────
// 纪律重申（prompt_assembly_service.dart _appendDisciplineReminder，L1 尾巴逐字）
function disciplineReminder() {
  return ['# 回复纪律（最后提醒）\n\n',
    '长历史易稀释前置约束，此处重申 L1 核心纪律，回复时严格遵守：\n\n',
    '1. 不得替学员写句子/段落/大纲（R-009 用户主权，示范档例外按态度档执行）；\n',
    '2. 一次只讲一个焦点（铁三角）；\n',
    '3. 示范按当前态度档执行；\n',
    '4. 诊断结论必须基于用户实际文本，不假定被裁掉的素材内容；\n',
    '5. 回复去 AI 味，不用"让我来帮你"等套话；\n',
    '6. 诊断块按 [YS_DIAGNOSIS]...[/YS_DIAGNOSIS] 标记输出（用户请求诊断时），卡片块用对应标签，不裸露 JSON。',
  ].join('');
}

// 组装一次发送的完整消息序列
function assembleMessages(state, userContent) {
  const ctx = {
    phase: state.phase, subphase: state.subphase,
    attitude: state.attitude, teachingMode: state.teachingMode,
    forceSceneFirst: state.forceSceneFirst || false,
  };
  const { systemPrompt, l2Mode } = buildSystemPrompt(ctx);
  const messages = [{ role: 'system', content: systemPrompt }];

  const isDiagnosisLike = l2Mode === 'diagnosis' || ctx.forceSceneFirst;
  if (isDiagnosisLike && (!state.activeSyndromes || state.activeSyndromes.length === 0)) {
    messages.push({ role: 'system', content: buildFirstRoundCriteriaBlock() });
  }
  // L3：诊断模式带活跃症候 → 详情；训练模式带焦点 → 症候+技法
  if (l2Mode === 'diagnosis' && state.activeSyndromes && state.activeSyndromes.length) {
    const l3 = getSyndromeContent(state.activeSyndromes);
    if (l3) messages.push({ role: 'system', content: l3 });
  }
  if (l2Mode === 'training' && state.focusId) {
    const l3 = getSyndromeContent([state.focusId]) + '\n\n---\n\n' + getTechniquesBySyndrome([state.focusId]);
    if (l3.trim()) messages.push({ role: 'system', content: l3 });
  }
  // 历史（页面私有标记 __ 开头的 assistant 项不入模型上下文）
  for (const m of state.history) {
    if (m.role === 'assistant' && typeof m.content === 'string' && m.content.indexOf('__') === 0) continue;
    messages.push({ role: m.role, content: m.content });
  }
  // 本轮 user 消息（诊断模式追加协议后缀）
  let content = userContent;
  if (isDiagnosisLike) {
    content += CORPUS.consts.diagnosisProtocolSuffix;
  }
  messages.push({ role: 'user', content });
  // 纪律重申（末尾 system）
  messages.push({ role: 'system', content: disciplineReminder() });
  return { messages, l2Mode };
}

// ─── 回复解析（[YS_DIAGNOSIS] 块，宽松 JSON）──────────────────────
function parseReply(text) {
  const out = { prose: text, diagnosis: null, rawBlock: null };
  const m = text.match(/\[YS_DIAGNOSIS\]([\s\S]*?)(?:\[\/YS_DIAGNOSIS\]|$)/);
  if (!m) return out;
  out.rawBlock = m[1].trim();
  out.prose = (text.slice(0, m.index) + text.slice(m.index + m[0].length)).trim();
  // 宽松解析：剥 ``` 围栏、截取最外层 {...}
  let js = out.rawBlock.replace(/```(?:json)?/g, '').trim();
  const s = js.indexOf('{'), e = js.lastIndexOf('}');
  if (s !== -1 && e > s) {
    try { out.diagnosis = JSON.parse(js.slice(s, e + 1)); } catch (_) { /* lenient: 不中断会话 */ }
  }
  return out;
}

// ─── 会话状态 ────────────────────────────────────────────────────
function initialState() {
  return {
    phase: 'P0', subphase: null,
    attitude: 'yuesheng', teachingMode: 'socratic',
    activeSyndromes: [], focusId: null,
    forceSceneFirst: false,
    history: [],           // [{role, content}] 已发送轮次（不含 system）
  };
}

const STATE_KEY = 'yuesheng_web_trial_state_v1';
function saveState(state) { try { localStorage.setItem(STATE_KEY, JSON.stringify(state)); } catch (_) {} }
function loadState() {
  try {
    const raw = localStorage.getItem(STATE_KEY);
    if (raw) { const s = JSON.parse(raw); if (s && s.phase) return s; }
  } catch (_) {}
  return initialState();
}
