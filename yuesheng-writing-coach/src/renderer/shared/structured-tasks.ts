/**
 * 结构化训练任务数据（来自 training-tasks.md V2.0）
 *
 * 将 Markdown 中 20 个结构化任务导出为 TypeScript 数据，
 * 供 RecommendationsSection 和 ActiveTrainingView 消费。
 */

// ======================== 类型定义 ========================

/** 结构化训练任务（来自 training-tasks.md V2.0） */
export interface StructuredTrainingTask {
  /** 任务编号，如 T001 */
  id: string;
  /** 适用病症 ID，如 P003 */
  syndromeId: string;
  /** 适用病症名称 */
  syndromeName: string;
  /** 任务内容描述 */
  content: string;
  /** 禁止词列表（如有的话） */
  forbiddenWords?: string[];
  /** 场景设定 */
  scene?: string;
  /** 目标字数 */
  wordCount?: number;
  /** 评估标准列表 */
  criteria?: string[];
  /** 合格示例（可选） */
  example?: string;
  /** 任务模式：reading_task 时流程不同 */
  mode?: 'writing' | 'reading';
}

// ======================== 20 个结构化任务 ========================

export const STRUCTURED_TASKS: StructuredTrainingTask[] = [
  // ===== T001-T002: P003 情绪标签化 =====
  {
    id: 'T001',
    syndromeId: 'P003',
    syndromeName: '情绪标签化',
    content: '请描写一个紧张的人。',
    forbiddenWords: ['紧张', '害怕', '恐惧', '慌张', '焦虑', '不安', '忐忑', '心跳加速', '手心出汗'],
    scene: '考试发卷前，主角坐在教室里。',
    wordCount: 300,
    criteria: ['有具体的身体反应', '有环境互动', '情绪通过行为传达', '出现任何禁止词 → 不合格'],
    example: '他的手指在桌沿上点了三下，又停下来。试卷还没发到，他盯着前排同学的后脑勺，看那人转笔——转了两圈，掉了，那人弯腰去捡，他跟着低头，又立刻抬起来。老师的脚步声近了。',
    mode: 'writing',
  },
  {
    id: 'T002',
    syndromeId: 'P003',
    syndromeName: '情绪标签化',
    content: '请描写一个愤怒的人。',
    forbiddenWords: ['愤怒', '生气', '恼火', '暴怒', '火冒三丈', '气得发抖'],
    scene: '主角和朋友吵架后，独自走在街上。',
    wordCount: 300,
    criteria: ['有具体的身体反应', '有环境互动', '情绪通过行为传达', '出现任何禁止词 → 不合格'],
    mode: 'writing',
  },

  // ===== T003-T004: P002 角色工具人化 =====
  {
    id: 'T003',
    syndromeId: 'P002',
    syndromeName: '角色工具人化',
    content: '写一个配角拒绝主角的场景。\n\n要求：\n- 配角有独立立场，不是为主角服务的\n- 配角的拒绝要有合理理由',
    scene: '主角请求朋友帮忙，朋友拒绝。',
    wordCount: 500,
    criteria: ['配角有明确的拒绝理由', '配角的拒绝符合其性格和处境', '配角的拒绝理由模糊或牵强 → 不合格'],
    example: '"你让我帮你去跟老师说？"许南州把书包往肩上一甩，"你自己去。我上次帮他打掩护，他到现在还记着，我再去就是找死。"',
    mode: 'writing',
  },
  {
    id: 'T004',
    syndromeId: 'P002',
    syndromeName: '角色工具人化',
    content: '写一个NPC角色在特定情境下的真实反应。\n\n要求：\n- 这个角色只出场一次，只有一句话或一个动作\n- 但要符合角色的身份和处境',
    scene: '主角在食堂排队，前面的同学被撞了一下。',
    wordCount: 200,
    criteria: ['NPC的反应符合其身份', 'NPC不是为了"传递信息"而存在', 'NPC的反应过于书面化 → 不合格'],
    mode: 'writing',
  },

  // ===== T005-T006, T015-T016: P004 信息硬塞 =====
  {
    id: 'T005',
    syndromeId: 'P004',
    syndromeName: '信息硬塞',
    content: '写一段对话，需要交代以下设定：\n- 这个世界有"武者"和"普通人"的区别\n- 武者需要测试才能成为\n- 测试在特定地点进行\n\n禁止：\n- 单独成段交代设定\n- 对话中直接说明',
    forbiddenWords: ['单独成段交代设定', '对话中直接说明'],
    wordCount: 400,
    criteria: ['设定通过对话自然流露', '对话符合真人说话习惯', '出现单独成段的设定说明 → 不合格'],
    mode: 'writing',
  },
  {
    id: 'T006',
    syndromeId: 'P004',
    syndromeName: '信息硬塞',
    content: '写一个场景，需要交代以下设定：\n- 主角刚穿越，不知道这个世界\n- 这个世界的地理和原来不同\n\n禁止：\n- 单独成段交代设定\n- 主角突然"知道"设定',
    forbiddenWords: ['单独成段交代设定', '主角突然"知道"设定'],
    wordCount: 500,
    criteria: ['设定通过主角的观察/反应自然流露', '主角有真实的困惑反应', '出现单独成段的设定说明 → 不合格'],
    mode: 'writing',
  },
  {
    id: 'T015',
    syndromeId: 'P004',
    syndromeName: '信息硬塞',
    content: '写一个场景，让读者自己"发现"以下设定（而非直接交代）：\n- 这个世界有超凡力量\n- 使用超凡力量有代价\n\n禁止：\n- 任何直接说明句："这个世界有魔法""超凡力量需要消耗"\n- 角色停下来解释设定',
    forbiddenWords: ['这个世界有魔法', '超凡力量需要消耗', '角色停下来解释设定'],
    scene: '主角第一次看到别人使用超凡力量。',
    wordCount: 400,
    criteria: ['设定通过角色看到的/感受到的展现', '读者能从场景中推断出设定', '出现直接说明句 → 不合格'],
    mode: 'writing',
  },
  {
    id: 'T016',
    syndromeId: 'P004',
    syndromeName: '信息硬塞',
    content: '写一个穿越/新来者视角的场景，通过主角的困惑和探索展现世界观。',
    forbiddenWords: ['这个世界是...', 'XX分为...', '主角突然"知道"设定'],
    scene: '主角刚来到一个陌生的地方，需要找人问路。',
    wordCount: 500,
    criteria: ['设定通过主角的观察和疑问自然流露', '信息通过NPC的对话或行动揭示', '出现旁白直接交代设定 → 不合格'],
    mode: 'writing',
  },

  // ===== T007-T008: P005 视角漂移 =====
  {
    id: 'T007',
    syndromeId: 'P005',
    syndromeName: '视角漂移',
    content: '写一个教室场景。\n\n禁止：\n- "大家都很紧张"\n- "众人心中打气"\n- 任何主角看不到的内心活动',
    forbiddenWords: ['大家都很紧张', '众人心中打气', '主角看不到的内心活动'],
    wordCount: 400,
    criteria: ['全文只写主角视角', '其他人的情绪通过行为传达', '出现全知描写 → 不合格'],
    mode: 'writing',
  },
  {
    id: 'T008',
    syndromeId: 'P005',
    syndromeName: '视角漂移',
    content: '写一段主角和朋友的对话。\n\n禁止：\n- 描写朋友"心中想XX"\n- 任何主角不知道的朋友内心',
    forbiddenWords: ['朋友心中想', '朋友内心', '朋友的想法'],
    wordCount: 300,
    criteria: ['全文只写主角视角', '出现主角知道朋友内心的描写 → 不合格'],
    mode: 'writing',
  },

  // ===== T009-T010: P006 节奏停滞 =====
  {
    id: 'T009',
    syndromeId: 'P006',
    syndromeName: '节奏停滞',
    content: '写一个小说开篇。\n\n禁止：\n- 开篇纯背景介绍\n- 开篇没有事件\n\n要求：\n- 第一段必须有事件发生\n- 事件必须有冲突或张力',
    forbiddenWords: ['开篇纯背景介绍', '开篇没有事件'],
    wordCount: 500,
    criteria: ['第一段有事件', '事件有冲突', '开篇纯背景介绍 → 不合格'],
    example: '"江璃，你又迟到了。"班主任站在门口，盯着他。江璃低头，没说话。后面有人笑了一声。',
    mode: 'writing',
  },
  {
    id: 'T010',
    syndromeId: 'P006',
    syndromeName: '节奏停滞',
    content: '写一个小说开篇，必须有钩子。\n\n钩子类型（选一个）：\n- 悬念钩子\n- 反常钩子\n- 冲突钩子',
    wordCount: 500,
    criteria: ['开篇有明确的钩子', '钩子在前三段内出现', '开篇没有钩子 → 不合格'],
    mode: 'writing',
  },

  // ===== T011-T012: P001 世界观膨胀 =====
  {
    id: 'T011',
    syndromeId: 'P001',
    syndromeName: '世界观膨胀',
    content: '写主角出场的一个场景。\n\n禁止：\n- 交代整个世界观\n- 交代主角的全部背景\n- 超过一个场景',
    forbiddenWords: ['交代整个世界观', '交代主角的全部背景', '超过一个场景'],
    wordCount: 500,
    criteria: ['全文只有一个场景', '没有世界观背景介绍', '出现世界观背景介绍 → 不合格'],
    mode: 'writing',
  },
  {
    id: 'T012',
    syndromeId: 'P001',
    syndromeName: '世界观膨胀',
    content: '写主角的第一章。\n\n禁止：\n- 先写世界观再写主角\n- 主角信息少于世界观信息',
    forbiddenWords: ['先写世界观再写主角', '主角信息少于世界观信息'],
    wordCount: 1000,
    criteria: ['主角信息先于世界观信息', '主角是核心，世界观是背景', '世界观信息超过主角信息 → 不合格'],
    mode: 'writing',
  },

  // ===== T021-T022: P008 世界观说明书症 =====
  {
    id: 'T021',
    syndromeId: 'P008',
    syndromeName: '世界观说明书症',
    content: '写一个角色在某个具有超凡能力的世界中起床、洗漱、出门的日常场景。\n\n要求：\n- 通过角色的行为暗示这个世界有特殊规则\n- 不能出现任何直接说明世界设定的句子\n- 读者读完应该能推断出"这个世界和现实不一样"',
    forbiddenWords: ['这个世界是', '在这个世界里', '众所周知', '设定如下', '体系为', '分为'],
    scene: '一个普通早晨，主角准备出门上班/上学',
    wordCount: 500,
    criteria: ['无任何直接说明世界观的句子', '至少有2处通过行为暗示了世界特殊性', '读者能从场景中推断出世界观特征', '出现任何说明句 → 不合格'],
    mode: 'writing',
  },
  {
    id: 'T022',
    syndromeId: 'P008',
    syndromeName: '世界观说明书症',
    content: '写一段两个角色之间的对话，其中自然地嵌入以下信息：\n- 这个社会有严格的等级制度\n- 等级通过某种可见标记区分\n- 主角属于较低等级\n\n禁止：单独成段交代背景、旁白解说。',
    forbiddenWords: ['等级制度', '分为三等', '众所周知', '在这个社会里', '自古以来', '根据规定'],
    scene: '主角和一个高等级角色在公共场合偶然相遇',
    wordCount: 400,
    criteria: ['等级信息完全通过对话流露', '对话符合真人说话习惯（不生硬）', '无单独成段的背景介绍', '出现任何说明性文字 → 不合格'],
    mode: 'writing',
  },

  // ===== T013-T014: P007 阅读结构单一（reading 模式） =====
  {
    id: 'T013',
    syndromeId: 'P007',
    syndromeName: '阅读结构单一',
    content: '精读以下片段，并回答问题。\n\n精读材料（选一个）：\n- 余华《活着》开篇\n- 鲁迅《朝花夕拾》某篇\n- 奈诃夫短篇小说片段\n\n问题：\n1. 这段文字用了多少个情绪标签词？\n2. 作者如何传达情绪？\n3. 这段文字的视角是什么？\n4. 你从这段文字学到了什么？',
    criteria: ['用户能识别情绪标签词的使用方式', '用户能理解"通过行为传达情绪"', '用户无法回答问题 → 需要进一步引导'],
    mode: 'reading',
  },
  {
    id: 'T014',
    syndromeId: 'P007',
    syndromeName: '阅读结构单一',
    content: '找一本传统文学（如《活着》《围城》或你自己选的），只读前三章。\n\n阅读任务：\n带着一个具体问题去读：**作者是怎么在开场就把主角的性格写出来的？**\n\n完成后回答：\n1. 主角在第三章结束时，你对他有什么印象？\n2. 作者用了哪些方法让你形成这个印象？（对话？行为？环境？）\n3. 你能借鉴其中一个方法吗？',
    criteria: ['用户能说出主角印象', '用户能识别作者的方法', '用户能说出可借鉴的点', '用户只说"读完感觉不错" → 需要进一步引导'],
    mode: 'reading',
  },

  // ===== T017-T018: P009 角色动机缺失 =====
  {
    id: 'T017',
    syndromeId: 'P009',
    syndromeName: '角色动机缺失',
    content: '给一个角色设计一个"想要的东西"和"害怕失去的东西"。\n\n要求：\n- 想要的东西必须具体（不是"变强"，而是"通过下个月的考核"）\n- 害怕失去的东西必须和他过去的经历有关\n\n表单格式：\n角色名：\n想要：______（具体目标）\n因为：______（过去的经历驱动）\n害怕失去：______（一旦失去就完了的东西）',
    criteria: ['目标具体可衡量', '动机与过去经历挂钩', '目标太抽象 → 要求细化'],
    mode: 'writing',
  },
  {
    id: 'T018',
    syndromeId: 'P009',
    syndromeName: '角色动机缺失',
    content: '给角色设置一个两难选择场景。\n\n要求：\n- 两个选项都不能轻易放弃\n- 无论选哪一个，角色都会失去重要的东西\n\n场景（任选一个）：\n- 朋友被害，凶手是救命恩人\n- 完成任务就能救家人，但任务会害死无辜的人\n- 追随梦想＝背叛家族的期望',
    wordCount: 600,
    criteria: ['两个选项都有合理的理由', '角色有内心挣扎的描写', '一个选项明显正确 → 两难不够'],
    mode: 'writing',
  },

  // ===== T019-T020: P010 OC平面化 =====
  {
    id: 'T019',
    syndromeId: 'P010',
    syndromeName: 'OC平面化',
    content: '给角色设计一个内在矛盾。\n\n矛盾类型（选一个）：\n- 外表冷静，内心暴躁\n- 嘴上冷漠，行动上却总在帮助别人\n- 渴望被爱，但习惯性推开所有人\n\n场景：\n写一个能展示这个矛盾的场景，让人物在一次行动中暴露出与平时不符的一面。',
    wordCount: 500,
    criteria: ['矛盾在行动中展现，不是通过说明', '场景中有"反平时行为"的时刻', '直接用文字说明角色矛盾 → 不合格'],
    mode: 'writing',
  },
  {
    id: 'T020',
    syndromeId: 'P010',
    syndromeName: 'OC平面化',
    content: '写一个角色经历事件前后发生变化的场景。\n\n要求：\n- 先写事件前的角色（如何看待某件事）\n- 再写事件本身（对他产生冲击）\n- 最后写事件后的角色（看法和行为发生改变）',
    wordCount: 800,
    criteria: ['事件前的态度明确', '事件对角色有实质冲击', '事件后的变化可感知', '事件前后角色没变化 → 不合格'],
    mode: 'writing',
  },
];

// ======================== 映射表 ========================

/** 症候 ID → 结构化任务 ID 列表映射 */
export const SYNDROME_TO_TASKS_MAP: Record<string, string[]> = {
  P001: ['T011', 'T012'],
  P002: ['T003', 'T004'],
  P003: ['T001', 'T002'],
  P004: ['T005', 'T006', 'T015', 'T016'],
  P005: ['T007', 'T008'],
  P006: ['T009', 'T010'],
  P007: ['T013', 'T014'],
  P008: ['T021', 'T022'],
  P009: ['T017', 'T018'],
  P010: ['T019', 'T020'],
};

/** 按 ID 快速查找结构化任务的 Map（运行时 O(1) 查询） */
export const TASK_BY_ID_MAP: Record<string, StructuredTrainingTask> = Object.fromEntries(
  STRUCTURED_TASKS.map((task) => [task.id, task]),
);

/** Challenge ID（CH-P00x 格式）→ 症候 ID 映射，用于将推荐卡片的 challengeId 关联到结构化任务 */
export const CHALLENGE_ID_TO_SYNDROME_ID: Record<string, string> = {
  'CH-P001': 'P001',
  'CH-P002': 'P002',
  'CH-P003': 'P003',
  'CH-P004': 'P004',
  'CH-P005': 'P005',
  'CH-P006': 'P006',
  'CH-P007': 'P007',
  'CH-P009': 'P009',
  'CH-P010': 'P010',
};

/**
 * 根据推荐卡片的 challengeId 查找对应的结构化任务列表
 *
 * @param challengeId 推荐 TrainingRecommendation 的 challengeId（如 "CH-P003"）
 * @returns 匹配的结构化任务数组（可能为空）
 */
export function getStructuredTasksForChallenge(challengeId: string): StructuredTrainingTask[] {
  const syndromeId = CHALLENGE_ID_TO_SYNDROME_ID[challengeId];
  if (!syndromeId) return [];
  const taskIds = SYNDROME_TO_TASKS_MAP[syndromeId];
  if (!taskIds) return [];
  return taskIds
    .map((id) => TASK_BY_ID_MAP[id])
    .filter(Boolean);
}

/**
 * 根据 activeTraining 的 challengeId 查找第一个匹配的结构化任务
 *
 * @param challengeId ActiveTrainingSession 的 challengeId
 * @returns 匹配的第一个结构化任务（可能为 undefined）
 */
export function getStructuredTaskForActiveTraining(challengeId: string): StructuredTrainingTask | undefined {
  const tasks = getStructuredTasksForChallenge(challengeId);
  return tasks[0];
}
