const fs = require('fs');
const path = require('path');

const configDir = path.join(__dirname, '..', 'resources', 'config');

// ============================================================
// 1. Transform training-library.json
// ============================================================
const trainingPath = path.join(configDir, 'training-library.json');
const training = JSON.parse(fs.readFileSync(trainingPath, 'utf-8'));

// developmentStage mapping by syndromeId prefix
const stageMap = {
  'P001': 'structure',
  'P002': 'person',
  'P003': 'word',
  'P004': 'structure',
  'P005': 'control',
  'P006': 'structure',
  'P007': 'word',
  'P009': 'person',
  'P010': 'person',
};

// classicalBasis mapping by syndromeId prefix
const basisMap = {
  'P001': [{ principleId: 'CHEKHOV_GUN' }, { principleId: 'LAO_SHE_EVERYTHING_MATTERS' }],
  'P002': [{ principleId: 'LAO_SHE_ACTION' }, { principleId: 'FORSTER_ROUND' }],
  'P003': [{ principleId: 'WANG_ZENG_QI_ACCURACY' }, { principleId: 'CHEKHOV_EMOTION' }],
  'P004': [{ principleId: 'CHEKHOV_GUN' }, { principleId: 'STRUNK_WHITE_CONCISE' }],
  'P005': [{ principleId: 'GARDNER_PSYCHIC_DISTANCE' }, { principleId: 'SHEN_CONGWEN_CLING' }],
  'P006': [{ principleId: 'CHEKHOV_GUN' }, { principleId: 'LAO_SHE_ONE_THING' }],
  'P007': [{ principleId: 'STRUNK_WHITE_CONCISE' }, { principleId: 'LU_XUN_DELETE' }],
  'P009': [{ principleId: 'FORSTER_ROUND' }, { principleId: 'LAO_SHE_MOTIVATION' }],
  'P010': [{ principleId: 'BOOTH_SHOWING' }, { principleId: 'LAO_SHE_LIVING' }],
};

// Add developmentStage and classicalBasis to existing entries
for (const entry of training.entries) {
  const prefix = entry.syndromeId;
  entry.developmentStage = stageMap[prefix];
  entry.classicalBasis = basisMap[prefix];
}

// Modify TRAIN-P005-001: set developmentStage to "control" (overrides the P005 mapping)
// PRAC-CONTROL-001 overlaps with TRAIN-P005-001, so we just update the existing one
const p005001 = training.entries.find(e => e.id === 'TRAIN-P005-001');
if (p005001) {
  p005001.developmentStage = 'control';
}

// New entries to add (7 total; PRAC-CONTROL-001 is NOT added — modifies TRAIN-P005-001 instead)
const newEntries = [
  {
    "id": "PRAC-EYE-001",
    "syndromeId": null,
    "syndromeName": null,
    "title": "看烂书·找茬",
    "difficulty": "easy",
    "mode": "narrow_focus",
    "developmentStage": "eye",
    "tier": "surface",
    "constraint": "打开番茄小说随便找一本评分低的，读2000字第一章，找出3个让你读不下去的地方。每个写30字说明\u2018为什么读不下去\u2019——禁止用\u2018文笔差\u2019\u2018剧情无聊\u2019等笼统判断。",
    "expectedOutcome": "建立\u2018对差的本能反感\u2019，能在阅读中主动识别具体问题段落并给出针对理由",
    "classicalBasis": [{"principleId": "ZHU_GUANG_QIAN_DISCRIMINATION"}, {"principleId": "LU_XUN_DELETE"}],
    "techniques": [],
    "exercises": [
      {"step": 1, "instruction": "随便打开一本番茄小说第一章", "duration": "3min"},
      {"step": 2, "instruction": "边读边在你想跳过的段落旁边打标记（读完全章，不限时）", "duration": "10min"},
      {"step": 3, "instruction": "选出最让你难受的3处，每处写30字以上的\u2018为什么难受\u2019", "duration": "10min"},
      {"step": 4, "instruction": "回头检查——你写的理由有没有出现\u2018无聊\u2019\u2018不好看\u2019等笼统词？有的话重写", "duration": "3min"}
    ]
  },
  {
    "id": "PRAC-EYE-002",
    "syndromeId": null,
    "syndromeName": null,
    "title": "看烂书·归类",
    "difficulty": "easy",
    "mode": "narrow_focus",
    "developmentStage": "eye",
    "tier": "surface",
    "constraint": "再用同一本书的第二章（或换一本），再找3个问题。这次除了写\u2018为什么\u2019，还要把你找出来的问题归个类——归类名称自己定，不需要用术语。3个问题全部有归类，且同一归类标准不自相矛盾。",
    "expectedOutcome": "在\u2018找茬\u2019的基础上训练归类能力，为后续理解P症候体系打感知基础",
    "classicalBasis": [{"principleId": "STRUNK_WHITE_CONCISE"}],
    "techniques": [],
    "exercises": [
      {"step": 1, "instruction": "阅读同一本或新一本的第二章（读完，不限时）", "duration": "不限时"},
      {"step": 2, "instruction": "找3个问题，每个写30字+理由+自定义归类标签", "duration": "12min"},
      {"step": 3, "instruction": "回头看你的3个归类——如果用同一个\u2018归类的逻辑\u2019去判断，它们是一致的吗？", "duration": "3min"}
    ]
  },
  {
    "id": "PRAC-PEN-001",
    "syndromeId": null,
    "syndromeName": null,
    "title": "指定视角阅读/观影协议",
    "difficulty": "medium",
    "mode": "narrow_focus",
    "developmentStage": "pen",
    "tier": "deep",
    "constraint": "选择一部作品，指定一个视角（得与失/准确表达/结构经济/人物塑造），带着这个视角看完并做笔记。输出500字以上分析报告——不准AI、不准错字、逻辑连贯、表达清晰、结构完整。",
    "expectedOutcome": "带着具体诊断任务去阅读/观影，而非泛泛感受",
    "classicalBasis": [{"principleId": "ZHU_GUANG_QIAN_DISCRIMINATION"}, {"principleId": "WANG_ZENG_QI_ACCURACY"}],
    "techniques": [],
    "exercises": [
      {"step": 1, "instruction": "选定作品和视角，在笔记里写下\u2018我要找什么\u2019", "duration": "2min"},
      {"step": 2, "instruction": "观看/阅读全作品，随时记录符合视角观察点的内容", "duration": "不限时"},
      {"step": 3, "instruction": "写500字以上分析报告——开头一句话抛出核心判断，中间逐点引用文本支撑，结尾一句话收束", "duration": "60min"},
      {"step": 4, "instruction": "自检——删掉所有\u2018我觉得\u2019\u2018我感觉\u2019开头的句子，把主观感受改写成可验证的判断", "duration": "5min"}
    ]
  },
  {
    "id": "PRAC-PEN-002",
    "syndromeId": null,
    "syndromeName": null,
    "title": "一人一事",
    "difficulty": "easy",
    "mode": "narrow_focus",
    "developmentStage": "pen",
    "tier": "surface",
    "constraint": "选一个人（可以是自己、认识的某人、虚构的角色），选一件事（有开头发展结尾），写300-500字讲清楚。硬约束：只写这一个人这件事，不许引入第二个人物线，不许写背景，不许写\u2018他想起了以前\u2019。",
    "expectedOutcome": "在进入任何技法训练之前，先确保能讲清楚一个完整的最小叙事单元",
    "classicalBasis": [{"principleId": "LAO_SHE_ONE_THING"}],
    "techniques": [],
    "exercises": [
      {"step": 1, "instruction": "选定人物和事件，用一句话写下来\u2018谁，做了什么\u2019", "duration": "3min"},
      {"step": 2, "instruction": "写出这件事的3个节点：开头\u2192发展\u2192结尾", "duration": "5min"},
      {"step": 3, "instruction": "写300-500字完整叙事", "duration": "20min"},
      {"step": 4, "instruction": "找一个人读，让他回答——\u2460这个人做了什么？\u2461为什么做？\u2462结果如何？", "duration": "5min"}
    ]
  },
  {
    "id": "PRAC-WORD-001",
    "syndromeId": null,
    "syndromeName": null,
    "title": "删可有可无",
    "difficulty": "easy",
    "mode": "word_refine",
    "developmentStage": "word",
    "tier": "surface",
    "constraint": "取你自己写过的一段300-500字文字。第一遍：删词——找出所有\u2018的\u2019\u2018了\u2019\u2018是\u2019\u2018有\u2019\u2018很\u2019\u2018非常\u2019等虚词删到最少。第二遍：删句——找出所有删掉也不影响意思的句子直接删除。第三遍：删段——如果删掉某段后前后文仍然连贯，删除。目标：至少缩减30%。",
    "expectedOutcome": "建立删改的勇气和判断力——删到不能再删为止",
    "classicalBasis": [{"principleId": "LU_XUN_DELETE"}],
    "techniques": [],
    "exercises": [
      {"step": 1, "instruction": "取300-500字自己的文字", "duration": "2min"},
      {"step": 2, "instruction": "逐句删虚词——每删一个停顿问自己\u2018没有它意思变了吗\u2019", "duration": "10min"},
      {"step": 3, "instruction": "删可删句子——每句问\u2018删了它读者会漏掉什么必要信息吗\u2019", "duration": "8min"},
      {"step": 4, "instruction": "删可删段落", "duration": "5min"},
      {"step": 5, "instruction": "计算缩减比例，不足30%继续删", "duration": "5min"}
    ]
  },
  {
    "id": "PRAC-STRUCT-001",
    "syndromeId": null,
    "syndromeName": null,
    "title": "得与失框架应用",
    "difficulty": "medium",
    "mode": "restructure",
    "developmentStage": "structure",
    "tier": "structural",
    "constraint": "选一段自己写过的人物困境场景（300字以内）。列出：角色正在失去什么（具体的、有形的）？曾经得到过什么（与失去形成对比）？害怕失去什么（还没失去但可能失去）？如果有一项空白，补充这一项。",
    "expectedOutcome": "用\u2018得与失\u2019作为简易工具分析任何叙事文本的情感驱动力",
    "classicalBasis": [{"principleId": "ZHU_GUANG_QIAN_DISCRIMINATION"}, {"principleId": "LAO_SHE_EVERYTHING_MATTERS"}],
    "techniques": [],
    "exercises": [
      {"step": 1, "instruction": "选取300字人物困境场景", "duration": "2min"},
      {"step": 2, "instruction": "列出\u2018正在失去\u2019\u2018曾经得到\u2019\u2018害怕失去\u2019三项", "duration": "8min"},
      {"step": 3, "instruction": "找到空白项，补充1-2句植入原文", "duration": "10min"},
      {"step": 4, "instruction": "自检——补充的内容是\u2018展示\u2019出来的还是\u2018告诉\u2019出来的？", "duration": "5min"}
    ]
  },
  {
    "id": "PRAC-TASTE-001",
    "syndromeId": null,
    "syndromeName": null,
    "title": "高阶平淡练习",
    "difficulty": "medium",
    "mode": "word_refine",
    "developmentStage": "taste",
    "tier": "deep",
    "constraint": "取一段自己写过的200-300字场景。先删到150字，再删到100字。在100字版本里确保：a) 仍然有一个具体的动作在进行 b) 仍然有一个具体的物品被看到/使用 c) 仍然有一个情绪被感受到（但不能出现情绪词）",
    "expectedOutcome": "训练\u2018写得少但写得准\u2019的能力——用最少的文字传达最精确的信息",
    "classicalBasis": [{"principleId": "WANG_ZENG_QI_ACCURACY"}],
    "techniques": [],
    "exercises": [
      {"step": 1, "instruction": "取200-300字自己的场景", "duration": "2min"},
      {"step": 2, "instruction": "第一轮删减到150字——删词删句不删结构", "duration": "8min"},
      {"step": 3, "instruction": "第二轮删减到100字——可以动结构重新组织", "duration": "10min"},
      {"step": 4, "instruction": "找人盲读两个版本，问\u2018哪个版本情绪更强烈\u2019", "duration": "5min"}
    ]
  },
  {
    "id": "PRAC-TASTE-002",
    "syndromeId": null,
    "syndromeName": null,
    "title": "趣味自检",
    "difficulty": "medium",
    "mode": "restructure",
    "developmentStage": "taste",
    "tier": "structural",
    "constraint": "取自己最近一周写的文字（累计不少于1000字）。对照朱光潜十大弊病逐条自检：无病呻吟？装腔作势？堆砌典故？油腔滑调？涂脂抹粉？找出自己最高频的1-2条弊病，选一段文字针对性修改。",
    "expectedOutcome": "建立对自己写作趣味的自检能力——识别自己最容易滑入的低级趣味",
    "classicalBasis": [{"principleId": "ZHU_GUANG_QIAN_DISCRIMINATION"}],
    "techniques": [],
    "exercises": [
      {"step": 1, "instruction": "收集自己最近一周的文字，不少于1000字", "duration": "5min"},
      {"step": 2, "instruction": "逐条对照十大弊病，每命中一处做标记", "duration": "15min"},
      {"step": 3, "instruction": "统计标记分布，找出你的\u2018主力弊病\u2019", "duration": "3min"},
      {"step": 4, "instruction": "选一段典型文字针对性修改", "duration": "10min"}
    ]
  }
];

training.entries.push(...newEntries);

fs.writeFileSync(trainingPath, JSON.stringify(training, null, 2), 'utf-8');
console.log('\u2705 training-library.json transformed successfully');

// ============================================================
// 2. Transform technique-library.json (first 30 entries)
// ============================================================
const techniquePath = path.join(configDir, 'technique-library.json');
const techniques = JSON.parse(fs.readFileSync(techniquePath, 'utf-8'));

// classicalBasis mapping by technique ID for the first 30 entries
const techniqueBasis = {};
techniqueBasis['TQ-001'] = [
  { principleId: 'CHEKHOV_GUN', relevance: '\u9012\u8FDB\u5F00\u7BC7\u7684\u6BCF\u4E2A\u8BCD\u90FD\u5E94\u662F\u2018\u67AA\u2019\u2014\u2014\u4E3A\u540E\u7EED\u60C5\u7EEA\u79EF\u7D2F\u52BF\u80FD' },
  { principleId: 'STRUNK_WHITE_CONCISE', relevance: '\u4E09\u8BCD\u9012\u8FDB\u662F\u6781\u81F4\u7B80\u6D01\u7684\u5178\u8303\uFF0C\u6BCF\u4E2A\u8BCD\u90FD\u627F\u8F7D\u4E0D\u53EF\u524A\u51CF\u7684\u91CD\u91CF' }
];

// Let me just construct the whole object properly using a function
function makeBasis(entries) {
  for (const [id, basis] of Object.entries(entries)) {
    techniqueBasis[id] = basis;
  }
}

makeBasis({
  'TQ-001': [
    { principleId: 'CHEKHOV_GUN', relevance: '递进开篇的每个词都应是\u2018枪\u2019——为后续情绪积累势能' },
    { principleId: 'STRUNK_WHITE_CONCISE', relevance: '三词递进是极致简洁的典范，每个词都承载不可削减的重量' }
  ],
  'TQ-002': [
    { principleId: 'CHEKHOV_GUN', relevance: '反常物件就是\u2018枪\u2019——不解释但必然有意义，读者会一直惦记' },
    { principleId: 'SHEN_CONGWEN_CLING', relevance: '让读者的注意力\u2018粘\u2019在反常物件上，用日常与异常的对比制造张力' }
  ],
  'TQ-003': [
    { principleId: 'CHEKHOV_GUN', relevance: '视觉奇观是打响的第一枪——用画面代替讲解启动叙事' },
    { principleId: 'LAO_SHE_EVERYTHING_MATTERS', relevance: '每一个视觉细节都有份量，代替冗长的世界观说明' }
  ],
  'TQ-004': [
    { principleId: 'CHEKHOV_GUN', relevance: '每个证据都是\u2018枪\u2019，读者知道它们终将指向某个真相' },
    { principleId: 'GARDNER_PSYCHIC_DISTANCE', relevance: '让读者站在侦探视角推理，缩短心理距离增强参与感' }
  ],
  'TQ-005': [
    { principleId: 'CRON_BRAIN_SIMULATION', relevance: '三段式情绪设计符合读者大脑对情绪弧线的预期，优化阅读体验' }
  ],
  'TQ-006': [
    { principleId: 'CHEKHOV_GUN', relevance: '主角的决定就是\u2018枪\u2019——读者期待这把枪在下一章打响' }
  ],
  'TQ-007': [
    { principleId: 'LAO_SHE_ONE_THING', relevance: '绝境开局聚焦于\u2018一件事\u2019——让主角的求生成为第一章唯一主线' }
  ],
  'TQ-008': [
    { principleId: 'LAO_SHE_ACTION', relevance: '内心吐槽是角色的内在动作——让性格通过内心动作而非旁白建立' },
    { principleId: 'FORSTER_ROUND', relevance: '吐槽揭示角色复杂面，使扁平角色快速获得圆形维度' }
  ],
  'TQ-009': [
    { principleId: 'CHEKHOV_GUN', relevance: '每条叙事线都是\u2018枪\u2019——两条线交错产生更大的叙事势能' },
    { principleId: 'GARDNER_PSYCHIC_DISTANCE', relevance: '信息差让读者拥有比角色更多的视角，缩短与作者的同盟距离' }
  ],
  'TQ-010': [
    { principleId: 'STRUNK_WHITE_CONCISE', relevance: '反常识推理的核心是\u2018用最简单的常识推翻复杂的共识\u2019——简洁即力量' }
  ],
  'TQ-011': [
    { principleId: 'CRON_BRAIN_SIMULATION', relevance: '倒计时触发读者大脑的紧迫感模拟，生理性地驱动翻页' }
  ],
  'TQ-012': [
    { principleId: 'BOOTH_SHOWING', relevance: '用\u2018转身离开\u2019替代\u2018悲伤\u2019——展示情绪而非告知情绪的最佳范本' },
    { principleId: 'LAO_SHE_ACTION', relevance: '动作本身就是情感——转身/沉默/关上门都是\u2018不说话\u2019的精准动作' }
  ],
  'TQ-013': [
    { principleId: 'BOOTH_SHOWING', relevance: '用3个准备行动展示恐惧——不写情绪只写动作是最强的\u2018展示\u2019' },
    { principleId: 'LAO_SHE_ACTION', relevance: '通过具体行动序列呈现心理状态，让动作本身说话' }
  ],
  'TQ-014': [
    { principleId: 'CHEKHOV_GUN', relevance: '世界碎裂的视觉画面是穿越的\u2018枪\u2019——读者第一眼就知道发生了什么' }
  ],
  'TQ-015': [
    { principleId: 'CHEKHOV_GUN', relevance: '远期预告是挂在第一章末尾的\u2018枪\u2019——读者会一直等待它打响' }
  ],
  'TQ-016': [
    { principleId: 'LAO_SHE_EVERYTHING_MATTERS', relevance: '贫困的每个细节都有份量——两个窝头比一百字\u2018很穷\u2019更有力' }
  ],
  'TQ-017': [
    { principleId: 'CHEKHOV_GUN', relevance: '密闭空间+未知威胁是组合\u2018枪\u2019——读者知道它们必须被解决' }
  ],
  'TQ-018': [
    { principleId: 'STRUNK_WHITE_CONCISE', relevance: '用一个数字矛盾替代整段说明——最简洁的悬念制造方式' }
  ],
  'TQ-019': [
    { principleId: 'CRON_BRAIN_SIMULATION', relevance: '暴力事件瞬间建立读者对世界规则的认知——大脑对威胁的敏感度最高' }
  ],
  'TQ-020': [
    { principleId: 'FORSTER_ROUND', relevance: '身份反转揭示角色的隐藏维度——让读者重新审视对人物的理解' }
  ],
  'TQ-021': [
    { principleId: 'STRUNK_WHITE_CONCISE', relevance: '规则漏洞往往是规则中最简洁的地方——用最少文字制造最大破绽' }
  ],
  'TQ-022': [
    { principleId: 'CHEKHOV_GUN', relevance: '身份与行为的反差是视觉化的\u2018枪\u2019——读者立刻好奇这矛盾意味着什么' }
  ],
  'TQ-023': [
    { principleId: 'FORSTER_ROUND', relevance: '双重身份是角色复杂性的起点——读者不知道哪个身份是\u2018真\u2019的' }
  ],
  'TQ-024': [
    { principleId: 'SHEN_CONGWEN_CLING', relevance: '反复出现的梦境像\u2018粘\u2019在读者心头的线索——每次出现都加深印象' }
  ],
  'TC-001': [
    { principleId: 'LAO_SHE_EVERYTHING_MATTERS', relevance: '日常行为的每个细节都有份量——投一枚铜便士带出货币体系和能源系统' },
    { principleId: 'CHEKHOV_GUN', relevance: '日常物品也是\u2018枪\u2019——煤气灯计费器不仅照亮街道，也照亮世界观' }
  ],
  'TC-002': [
    { principleId: 'LAO_SHE_ACTION', relevance: '重复台词是角色的语言动作——每次重复都在强化人物印记' },
    { principleId: 'FORSTER_ROUND', relevance: '同一句台词在不同语境中的微妙变化，揭示角色的多面性' }
  ],
  'TC-003': [
    { principleId: 'LAO_SHE_ACTION', relevance: '\u2018活下去\u2019是最高密度的语言动作——三个字承载整场告别的重量' },
    { principleId: 'FORSTER_ROUND', relevance: '极简台词为角色留下想象空间——读者用自己的情感填充' }
  ],
  'TC-004': [
    { principleId: 'LAO_SHE_ACTION', relevance: '日常场景中的动作序列是角色性格最自然的展示窗口' },
    { principleId: 'FORSTER_ROUND', relevance: '一个场景同时展现3个特征——让角色在读者心中迅速立体化' }
  ],
  'TC-005': [
    { principleId: 'LAO_SHE_EVERYTHING_MATTERS', relevance: '贫困的具体细节（两个窝头）比抽象标签更有份量——细节即真实' }
  ],
  'TC-006': [
    { principleId: 'FORSTER_ROUND', relevance: '绰号与能力的反差本身就是角色复杂性的开端——读者自然好奇' }
  ]
});

// Process first 30 entries
for (let i = 0; i < Math.min(30, techniques.length); i++) {
  const technique = techniques[i];
  const basis = techniqueBasis[technique.id];
  if (basis) {
    technique.classicalBasis = basis;
  } else {
    console.warn('Warning: No basis mapping found for technique: ' + technique.id + ' (' + technique.name + ')');
  }
}

fs.writeFileSync(techniquePath, JSON.stringify(techniques, null, 2), 'utf-8');
console.log('\u2705 technique-library.json (first 30 entries) transformed successfully');
