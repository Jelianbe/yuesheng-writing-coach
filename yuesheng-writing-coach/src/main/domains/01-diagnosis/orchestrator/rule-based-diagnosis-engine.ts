/**
 * 规则诊断引擎（本地兜底校验）
 *
 * 当 LLM 诊断 Agent 调用失败/超时/格式异常时，使用规则引擎做本地兜底诊断。
 * 基于信号权重表 + 正则匹配扫描用户文本，计算各症候得分和严重度。
 *
 * PRD V1.0 §2.3 design:
 *   - SYNDROME_SIGNALS: 信号权重表（关键词/正则模式 + 权重值）
 *   - analyzeMessage(): 扫描文本 → 计算总分 → 判断严重度 → 生成建议动作
 *   - 多症候优先级排序: P004 > P006 > P005 > P003 > P001 > P002 > P007
 *
 * DI 注册名: 'ruleBasedDiagnosisEngine'
 */

import type { DiagnosisAnalysis } from '../../../../shared/types/index';

// ===== 信号定义 =====

interface SyndromeSignal {
  /** 匹配模式（正则表达式字符串或关键词） */
  pattern: RegExp;
  /** 权重分值 */
  weight: number;
  /** 信号描述 */
  description: string;
}

/** 症候信号表 */
const SYNDROME_SIGNALS: Record<string, SyndromeSignal[]> = {
  // P001: 世界观膨胀
  P001: [
    { pattern: /世界观|设定集|魔法体系|等级体系|势力分布|大陆地图/, weight: 2, description: '世界观/设定关键词' },
    { pattern: /在我的世界里|这个世界有|我们这个大陆|整个宇宙/, weight: 2, description: '宏观视角陈述' },
    { pattern: /分为.*级|共有.*种|主要有.*类/, weight: 2, description: '分类枚举式设定' },
    { pattern: /第一章.{0,20}(背景|设定|介绍|由来|历史)/, weight: 3, description: '开篇堆设定' },
    { pattern: /然后主角/, weight: 1, description: '主角迟迟未登场' },
    { pattern: /话说|从前|很久很久以前/, weight: 1, description: '说书式开篇' },
  ],
  // P002: 角色工具人化
  P002: [
    { pattern: /他(她)?(便|就|于是|立刻|马上)(去|说|做|拿|走)/, weight: 1, description: '角色行为缺乏动机' },
    { pattern: /为了推动剧情|为了让故事|作者需要/, weight: 2, description: '角色为剧情服务' },
    { pattern: /工具人|路人甲|炮灰|龙套/, weight: 2, description: '角色标签化' },
    { pattern: /他(她)?出现了|他(她)?出场了|这时.*来了/, weight: 1, description: '角色突兀出场' },
    { pattern: /(他|她|主角|反派)需要(做|去|完成)/, weight: 2, description: '行为外部驱动' },
  ],
  // P003: 情绪标签化
  P003: [
    { pattern: /他很(生气|难过|高兴|伤心|愤怒|悲伤|开心|兴奋|沮丧|焦虑)/, weight: 2, description: '直写情绪形容词' },
    { pattern: /她感到|他觉得|心里(很|非常|十分)(难过|开心|痛苦|委屈|害怕)/, weight: 2, description: '内心感受直述' },
    { pattern: /一种.*的(感觉|情绪|心情|感受)涌上心头/, weight: 2, description: '情绪涌上心头句式' },
    { pattern: /(愤怒|悲伤|喜悦|恐惧|绝望|委屈|幸福)充满了/, weight: 2, description: '情绪充塞句式' },
    { pattern: /他(她)?(伤心地|愤怒地|开心地|悲伤地|绝望地|坚定地)(说|看|走|望|转)/, weight: 3, description: '情绪副词修饰动作' },
    { pattern: /(心里|内心|心中)一阵/, weight: 1, description: '内心感受模糊描述' },
  ],
  // P004: 信息硬塞
  P004: [
    { pattern: /众所周知|众所周知的是|需要知道的是|值得一提的是/, weight: 2, description: '旁白式信息引入' },
    { pattern: /原来|事实上|实际上|其实.*(是|有|在)/, weight: 1, description: '事后解释' },
    { pattern: /这里(需要|要|得)说明(一下)?/, weight: 3, description: '作者直接插话' },
    { pattern: /背景(是|设定在|发生)/, weight: 2, description: '背景直述' },
    { pattern: /让我们(来|一起)(了解|看看|介绍)/, weight: 3, description: '作者介入叙述' },
    { pattern: /顺便(一提|说下|说一下)/, weight: 2, description: '附带信息硬塞' },
    { pattern: /他是.*(的人|的角色|的存在)/, weight: 1, description: '静态身份定义' },
  ],
  // P005: 视角漂移
  P005: [
    { pattern: /他(她)?不知道|他(她)?没(有)?看到|他(她)?无法(知道|看到|察觉)/, weight: 3, description: '写了主角不知道的事' },
    { pattern: /与此同时.*(另一边|另一处|远处的)/, weight: 2, description: '切换视角' },
    { pattern: /而在.*(这边|那边|地方|角落|远处|城外|屋内|楼上)/, weight: 2, description: '空间视角切换' },
    { pattern: /(读者|观众)可以(看到|发现|知道)/, weight: 3, description: '跳出角色视角' },
    { pattern: /其实.*(心里|内心|暗自|早已|早就)/, weight: 1, description: '全知视角' },
  ],
  // P006: 节奏停滞
  P006: [
    { pattern: /(描写|描述|描绘|刻画)了.{0,10}(场景|环境|外貌|穿着|长相)/, weight: 2, description: '静态描写堆砌' },
    { pattern: /只见|但见|却见|放眼望去/, weight: 2, description: '观察式停滞' },
    { pattern: /(详细|细致|细细|慢慢|缓缓)(地)?(描写|描述|介绍|讲述)/, weight: 2, description: '过度细致' },
    { pattern: /(.{10,30}(的|地)){3,}/, weight: 1, description: '长修饰语拖沓' },
    { pattern: /(一百字以上段落且无对话)/, weight: 1, description: '无对话长段' },
    { pattern: /这时|这时候|就在这时|突然/, weight: 1, description: '虚假推进' },
  ],
  // P007: 阅读结构单一
  P007: [
    { pattern: /(他|她|它)(们)?(说|道|问|答|叫|喊|骂|吼)/, weight: 1, description: '单一对话模式' },
    { pattern: /(然后|接着|于是|随后)(他|她|它)/, weight: 2, description: '流水账叙事' },
    { pattern: /(.{0,10}了[。，；]){4,}/, weight: 2, description: "连续'了'字句" },
    { pattern: /(只见|就看|听到|闻到|感到)/, weight: 1, description: '单一感官描写' },
    { pattern: /一个.{0,6}(的|地).{0,6}(的|地).{0,6}/, weight: 1, description: '固定句式重复' },
  ],
  // P009: 角色动机缺失
  P009: [
    { pattern: /他(她)?(就|便|于是)(去|做|说|走|来|到)/, weight: 1, description: '行为无动机交代' },
    { pattern: /不知道为什么|说不清为什么|莫名其妙/, weight: 2, description: '行为无缘由' },
    { pattern: /他(她)?(只是|就是要|偏要|非要)(去|做|说)/, weight: 1, description: '任性行为' },
    { pattern: /(为了推动|为了让|便于|以便).*(剧情|故事|情节)/, weight: 3, description: '为剧情服务的行为' },
    { pattern: /然后(他|她)就(这样|这么)(做|说|走|去)/, weight: 1, description: '行为无内在逻辑' },
    { pattern: /(他|她)想要.{0,10}(但|可是|却|不过).{0,10}(不知道|不清楚|没想好)/, weight: 2, description: '欲望模糊' },
  ],
  // P010: OC平面化
  P010: [
    { pattern: /他(她)?是一个.{0,8}(的人|的角色|的存在)/, weight: 2, description: '角色定义标签化' },
    { pattern: /(善良|勇敢|坚强|温柔|冷酷|霸道|腹黑|呆萌)的(主角|男主|女主|人设)/, weight: 3, description: '人设标签堆砌' },
    { pattern: /人设(是|就是|为).*(善良|勇敢|高冷|温柔|傲娇|病娇)/, weight: 3, description: '人设定义直接' },
    { pattern: /他(她)?(永远|总是|从来)(都)?(是|不会|会)/, weight: 1, description: '角色行为单一化' },
    { pattern: /(高冷|霸道|温柔|呆萌|傲娇|病娇)(总裁|王爷|将军|学长|男友)/, weight: 2, description: '类型化角色' },
    { pattern: /(他|她)就是那种.{0,15}(的人)/, weight: 2, description: '角色类型定义' },
  ],
};

/** 症候优先级排序（数字越小优先级越高） */
const PRIORITY_ORDER: Record<string, number> = {
  P004: 0,
  P006: 1,
  P005: 2,
  P003: 3,
  P001: 4,
  P002: 5,
  P007: 6,
  P009: 7,
  P010: 8,
};

/** 症候中文名映射 */
const SYNDROME_NAME_MAP: Record<string, string> = {
  P001: '世界观膨胀',
  P002: '角色工具人化',
  P003: '情绪标签化',
  P004: '信息硬塞',
  P005: '视角漂移',
  P006: '节奏停滞',
  P007: '阅读结构单一',
  P009: '角色动机缺失',
  P010: 'OC平面化',
};

/** 症候 → 默认教学动作映射 */
const SYNDROME_DEFAULT_ACTIONS: Record<string, string[]> = {
  P001: ['A001', 'A005'],
  P002: ['A004', 'A003'],
  P003: ['A004'],
  P004: ['A002', 'A001'],
  P005: ['A002', 'A007'],
  P006: ['A003', 'A005'],
  P007: ['A008'],
  P009: ['A002'],
  P010: ['A006'],
};

// ===== 严重度门槛 =====

/** 各严重度等级的分数门槛（信号权重和） */
const SEVERITY_THRESHOLDS = { L1: 2, L2: 5, L3: 8 };

// ===== 引擎 =====

export interface RuleBasedDiagnosisResult {
  syndromes: Array<{
    id: string;
    name: string;
    severity: string;
    evidence: string[];
    score: number;
    suggestedActions: string[];
  }>;
  confidence: number;
  rawScores: Record<string, number>;
}

/**
 * 扫描文本，执行信号匹配
 * @returns 各症候的匹配得分
 */
function scanSignals(text: string): Record<string, { score: number; matches: string[] }> {
  const results: Record<string, { score: number; matches: string[] }> = {};

  for (const [syndromeId, signals] of Object.entries(SYNDROME_SIGNALS)) {
    let score = 0;
    const matches: string[] = [];

    for (const signal of signals) {
      const found = text.match(signal.pattern);
      if (found) {
        score += signal.weight * found.length;
        matches.push(found[0]);
      }
    }

    if (score > 0) {
      results[syndromeId] = { score, matches };
    }
  }

  return results;
}

/**
 * 根据信号分确定严重度
 */
function determineSeverity(score: number): string {
  if (score >= SEVERITY_THRESHOLDS.L3) return 'L3';
  if (score >= SEVERITY_THRESHOLDS.L2) return 'L2';
  return 'L1';
}

/**
 * 执行规则诊断
 *
 * @param userText 用户输入的文本
 * @param contextLength 文本长度（字符数），用于参考
 * @returns 规则诊断结果，若无匹配则返回 null
 */
export function analyzeByRules(userText: string): RuleBasedDiagnosisResult | null {
  const signalResults = scanSignals(userText);
  const syndromeIds = Object.keys(signalResults);

  if (syndromeIds.length === 0) {
    return null;
  }

  // 按优先级排序
  syndromeIds.sort((a, b) => {
    const pa = PRIORITY_ORDER[a] ?? 99;
    const pb = PRIORITY_ORDER[b] ?? 99;
    return pa - pb;
  });

  // 取证据片段（每个症候取前2个匹配）
  const syndromes = syndromeIds.map((id) => {
    const { score, matches } = signalResults[id];
    return {
      id,
      name: SYNDROME_NAME_MAP[id] ?? id,
      severity: determineSeverity(score),
      evidence: matches.slice(0, 2),
      score,
      suggestedActions: SYNDROME_DEFAULT_ACTIONS[id] ?? [],
    };
  });

  // 置信度 = 匹配症候数 / 总症候数 * 0.6（规则引擎置信度不高）
  const totalSyndromes = Object.keys(SYNDROME_SIGNALS).length;
  const matchedRatio = syndromeIds.length / totalSyndromes;
  const confidence = Math.min(0.6, 0.2 + matchedRatio * 0.4);

  const rawScores: Record<string, number> = {};
  for (const id of syndromeIds) {
    rawScores[id] = signalResults[id].score;
  }

  return {
    syndromes,
    confidence: Math.round(confidence * 100) / 100,
    rawScores,
  };
}

/**
 * 将规则诊断结果转换为 DiagnosisAnalysis 格式
 * （与 LLM 诊断 Agent 输出兼容）
 */
export function ruleResultToAnalysis(
  result: RuleBasedDiagnosisResult,
  _userText: string,
): DiagnosisAnalysis {
  return {
    contentType: 'narrative',
    rootCause: result.syndromes[0]?.name ?? '未知',
    intentPhase: 1,
    syndromeRef: result.syndromes.map(s => s.id),
    techniquePool: [],
    keyPassages: result.syndromes.flatMap(s =>
      s.evidence.map(text => ({
        text: text.slice(0, 50),
        issue: `检测到${s.name}信号`,
        syndromeRef: s.id,
      })),
    ),
    confidence: result.confidence,
  };
}
