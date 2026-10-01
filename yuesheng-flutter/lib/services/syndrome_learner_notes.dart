// ─────────────────────────────────────────────────────────────
// SyndromeLearnerNotes — 诊断资料区 · 症候学员解读库（ADR-C122）
//
// 一期：34 条症候（P001–P034）的学员化转写，纯展示数据。
//
// ★ 边界声明（ADR-C122 §4 判定）：
//   本文件是**独立展示数据文件**，不进注入链（不注入 skills_*.dart /
//   skill_registry.dart / few-shot / message_injector，不新增注册表条目），
//   故本批不触发 R-027 停线。若未来被诊断卡/对话引用（进入注入链），
//   须按 R-027 停线回传批准。
//
// 转写口径：基于 syndrome_registry.dart 的 oneLine/trainingLine 提炼为
// 学员可读语言（「这是什么 / 为什么是问题 / 常见表现 / 对应训练动作」）。
// 编号 + 名称并用（幽灵键消歧纪律：不裸用编号）。
// ─────────────────────────────────────────────────────────────

/// 症候学员解读条目（诊断资料区列表/详情共用）
class SyndromeLearnerNote {
  /// 症候编号（P001–P034，与 syndrome_registry 一致）
  final String id;

  /// 症候名称（与 registry name 一致，编号+名称并用）
  final String name;

  /// 这是什么（学员语言一句话）
  final String what;

  /// 为什么是问题（对读者的影响）
  final String why;

  /// 常见表现（1–2 条，具体可对照）
  final List<String> signs;

  /// 对应训练动作（来自 registry actions，编号引用）
  final List<String> actionRefs;

  const SyndromeLearnerNote({
    required this.id,
    required this.name,
    required this.what,
    required this.why,
    required this.signs,
    required this.actionRefs,
  });
}

/// 诊断资料区列表（34 条，按编号序）
const List<SyndromeLearnerNote> kSyndromeLearnerNotes = [
  SyndromeLearnerNote(
    id: 'P001',
    name: '情绪标签化',
    what: '直接告诉读者「他生气了」「她很美」，而不是让读者从描写里自己感受到。',
    why: '读者看到的是结论不是画面，情绪像开关一样被切换，感受不到，也就不被打动。',
    signs: ['满屏「愤怒/悲伤/害怕」等情绪词', '用「很美/太棒了」盖章式评价代替具体描写'],
    actionRefs: ['A004', 'A006', 'A016', 'A014'],
  ),
  SyndromeLearnerNote(
    id: 'P002',
    name: '信息倾泻症',
    what: '把世界观、背景设定像说明书一样直接倒给读者。',
    why: '设定堆在场景外，读者没进入故事就被灌信息，容易划走。',
    signs: ['开头大段交代历史/规则', '设定靠旁白直说而不是靠情节自然带出'],
    actionRefs: ['A002', 'A008'],
  ),
  SyndromeLearnerNote(
    id: 'P003',
    name: '视角漂移',
    what: '没有提示就跳出当前叙述视角，读者突然不知道「谁在看」。',
    why: '读者失去锚点，读着读着出戏，需要倒回去确认是谁的视角。',
    signs: ['限制视角下突然写「他不知道的是…」', '无标记插入另一角色的内心'],
    actionRefs: ['A002'],
  ),
  SyndromeLearnerNote(
    id: 'P004',
    name: '节奏停滞',
    what: '连续多段没有新事件、新冲突，或把事件按时间平铺，没有详略。',
    why: '故事在原地打转，读者觉得「没有进展」，追读动力流失。',
    signs: ['几段都在描写同一状态的反复', '事件一件接一件罗列，轻重不分'],
    actionRefs: ['A003', 'A005', 'A009', 'A011'],
  ),
  SyndromeLearnerNote(
    id: 'P005',
    name: '句式节奏单一',
    what: '连续多句用同一个句式，或一段过长没有呼吸感、一段过碎像碎片。',
    why: '阅读节奏失衡，读者容易疲劳，也显不出重点。',
    signs: ['每句都是「谁做了什么」的等长句式', '大段无分段，或一句话一个段'],
    actionRefs: ['A009', 'A003', 'A011'],
  ),
  SyndromeLearnerNote(
    id: 'P006',
    name: '语言堆砌',
    what: '修饰词堆太多，一句话里塞满形容词和成语。',
    why: '有效信息被稀释，读者要费力从词海里捞核心。',
    signs: ['「极其非常特别」叠用', '一个画面用三四个比喻'],
    actionRefs: ['A006', 'A011', 'A016'],
  ),
  SyndromeLearnerNote(
    id: 'P007',
    name: '角色空心化',
    what: '角色做事没有动机，欲望只停在「想变强」这类标签上，目标没有数量、期限、代价。',
    why: '换个人物故事照样成立，读者记不住角色，也不关心他下一步。',
    signs: ['「我要变强」但说不清强到什么程度', '行动没有代价和后果'],
    actionRefs: ['A003', 'A007'],
  ),
  SyndromeLearnerNote(
    id: 'P008',
    name: 'OC 平面化',
    what: '角色缺少独特特征，对话和行为换到另一个人身上也成立。',
    why: '人物不立体，读者分不清谁是谁，记忆点缺失。',
    signs: ['所有人说话腔调一样', '角色没有标志性的习惯或口头禅'],
    actionRefs: ['A003', 'A010'],
  ),
  SyndromeLearnerNote(
    id: 'P009',
    name: '对话疲劳症',
    what: '对话占太多篇幅，没有潜台词、没有动作支撑，全是客套和重复确认。',
    why: '看似在推进，其实在灌水，读者跳过对话也不损失信息。',
    signs: ['「你吃了没」「吃了」式寒暄', '对话里没有暗含的意图和冲突'],
    actionRefs: ['A008', 'A006', 'A009'],
  ),
  SyndromeLearnerNote(
    id: 'P010',
    name: '张力不足症',
    what: '主角不会输、没有代价、没有后果，读者从头到尾不紧张。',
    why: '没有失去的可能就没有悬念，紧张感是「可能失去」带来的。',
    signs: ['主角一路碾压从不遇挫', '重要选择没有取舍和代价'],
    actionRefs: ['A007', 'A003'],
  ),
  SyndromeLearnerNote(
    id: 'P011',
    name: '开篇平庸症',
    what: '前几百字没有冲突、悬念或反常，或从最无聊的地方绕大圈写起。',
    why: '开头几秒决定读者留不留，铺垫太长等于把读者送走。',
    signs: ['从主角起床洗漱写起', '前三章还在交代背景没进入故事'],
    actionRefs: ['A007', 'A001'],
  ),
  SyndromeLearnerNote(
    id: 'P012',
    name: '结尾乏力症',
    what: '收尾没有满足感，靠机械降神解决，或伏笔裸露、烂尾、解释式回收。',
    why: '读者憋了一路的期待落空，合上书的印象是「就这？」',
    signs: ['最后一章突然出现救兵/金手指', '关键伏笔一句「其实早就…」带过'],
    actionRefs: ['A007', 'A003', 'A012'],
  ),
  SyndromeLearnerNote(
    id: 'P013',
    name: '高潮疲软症',
    what: '铺垫都做好了，但高潮段落没有冲击力，关键胜利没有情绪回报。',
    why: '读者等了很久的「爽点」没被兑现，越写越没劲。',
    signs: ['大战一章写完主角却无情绪起伏', '胜利来得太容易没有过程'],
    actionRefs: ['A007', 'A009', 'A005', 'A013'],
  ),
  SyndromeLearnerNote(
    id: 'P014',
    name: '情节巧合过多症',
    what: '剧情推进靠偶然事件，而不是角色主动做选择。',
    why: '巧合多了读者觉得「作者硬编」，代入感崩塌。',
    signs: ['关键转折都是「恰好遇到」', '角色从不主动争取只等运气'],
    actionRefs: ['A013', 'A003'],
  ),
  SyndromeLearnerNote(
    id: 'P015',
    name: '人设崩塌症',
    what: '连载中角色的行为偏离前期建立起来的性格模式。',
    why: '读者信任崩塌——前面记住的人突然变了一个人。',
    signs: ['冷静人设突然无理由暴躁', '为剧情需要强行让角色做违背本性的选择'],
    actionRefs: ['A015', 'A010'],
  ),
  SyndromeLearnerNote(
    id: 'P016',
    name: '过渡生硬症',
    what: '场景切换靠「镜头一转」，没有感官或情绪上的连接。',
    why: '读者被硬拽到下一个场景，时空感混乱。',
    signs: ['「与此同时」「画面一转」生硬转场', '场景间没有时间/地点/情绪的线索'],
    actionRefs: ['A009', 'A006'],
  ),
  SyndromeLearnerNote(
    id: 'P017',
    name: '跳跃叙事/过度概括症',
    what: '重要时刻被一两句话带过，读者还没来得及感受就跳到结果。',
    why: '该展开的没展开，情绪刚起来就被掐断。',
    signs: ['「一夜过去，他们成了朋友」', '关键战斗只写输赢不写过程'],
    actionRefs: ['A009', 'A005'],
  ),
  SyndromeLearnerNote(
    id: 'P018',
    name: '重复用词/基础语病',
    what: '相邻字重复、连续标点、高频词反复，或主谓搭配、指代、成分残缺等基础文法问题。',
    why: '基础错误打断阅读，显得不专业，读者信任度下降。',
    signs: ['「他说他说」式重复', '一句话里「的」出现四五次'],
    actionRefs: ['A016', 'A011'],
  ),
  SyndromeLearnerNote(
    id: 'P019',
    name: '章节钩子缺失症',
    what: '章末没有悬念、反转或冲击，读者没有翻页的动力；或钩子不兑现、提前剧透。',
    why: '章末钩子是追读的引擎，没有它读者随时可以停。',
    signs: ['章末停在「他回到了家」', '章末抛出的悬念下章一句带过'],
    actionRefs: ['A012', 'A009', 'A003'],
  ),
  SyndromeLearnerNote(
    id: 'P020',
    name: '追读动力不足症',
    what: '长线悬念、情感绑定、主线牵引太弱，读者看完一章没有「必须看下一章」的理由。',
    why: '单章写得好但串不成线，读者热情维持不了几章。',
    signs: ['每章独立成篇没有持续悬念', '主角目标模糊，读者不知道要等什么'],
    actionRefs: ['A013', 'A012'],
  ),
  SyndromeLearnerNote(
    id: 'P021',
    name: '画面感缺失症',
    what: '通篇抽象概述，没有场景化的呈现，读者脑内无法成像。',
    why: '读者「看不见」故事，等于在看梗概而不是在看小说。',
    signs: ['「他们发生了争执」不写现场', '描写只有情绪词没有感官细节'],
    actionRefs: ['A006', 'A004'],
  ),
  SyndromeLearnerNote(
    id: 'P022',
    name: '节奏比例失衡症',
    what: '铺垫、高潮、收束的比例不对，该快的慢、该慢的快。',
    why: '节奏错配让读者在无聊处煎熬、在关键处被赶着走。',
    signs: ['铺垫占八成高潮一笔带过', '该停留的情绪场景匆匆收场'],
    actionRefs: ['A009', 'A013'],
  ),
  SyndromeLearnerNote(
    id: 'P023',
    name: '设定矛盾症',
    what: '世界观设定前后冲突，规则、时间线、能力不自洽。',
    why: '设定是读者信任的地基，地基裂了故事就塌了。',
    signs: ['前后两章能力规则不一致', '时间线对不上读者去回翻'],
    actionRefs: ['A013', 'A012'],
  ),
  SyndromeLearnerNote(
    id: 'P024',
    name: '金手指失衡症',
    what: '金手指亮相时机、强度上限、规则一致性出问题：升级过快力量通胀，或过慢失去期待。',
    why: '金手指是网文的引擎，失衡会让爽点失灵或让冲突消失。',
    signs: ['金手指一出冲突全灭', '升级慢到读者等不到第一次爽'],
    actionRefs: ['A013', 'A009'],
  ),
  SyndromeLearnerNote(
    id: 'P025',
    name: '配角工具人症',
    what: '配角没有独立性格、动机和记忆点，只负责传话、推剧情、喊口号。',
    why: '配角是世界的可信度来源，全是工具人会让主角的世界显得假。',
    signs: ['配角出场只为给主角送情报', '多个配角说话方式完全一样'],
    actionRefs: ['A010', 'A003'],
  ),
  SyndromeLearnerNote(
    id: 'P026',
    name: '心理内耗症',
    what: '角色内心反复纠结、自我怀疑、复盘过往，大段独白没有进展。',
    why: '内心戏不推进剧情，篇幅长了节奏被拖垮。',
    signs: ['一章里大半是内心独白', '同一个纠结点翻来覆去写'],
    actionRefs: ['A011', 'A004'],
  ),
  SyndromeLearnerNote(
    id: 'P027',
    name: '支线涣散症',
    what: '支线剧情不服务主线、人设或爽点，写着写着主线被搁置。',
    why: '读者等主线等不到，支线再多也是流失的加速器。',
    signs: ['支线写半章主角忘了正事', '几条支线互不相干各写各的'],
    actionRefs: ['A013', 'A002'],
  ),
  SyndromeLearnerNote(
    id: 'P028',
    name: '被动主角症',
    what: '主角被剧情拖着走，没有主动决策、权衡和反制。',
    why: '剧情需要主角去哪他就去哪，读者一眼出戏，主角光环变主角木偶。',
    signs: ['每个转折都是别人推着主角走', '主角从不主动争取或拒绝'],
    actionRefs: ['A002', 'A007', 'A003'],
  ),
  SyndromeLearnerNote(
    id: 'P029',
    name: '降智反派症',
    what: '反派为坏而坏、降智送人头，没有利益动机。',
    why: '对手变蠢，冲突失真，赢的爽感也打折——赢了傻子不算赢。',
    signs: ['反派放着资源不用硬送', '反派行动没有利益逻辑'],
    actionRefs: ['A003', 'A007'],
  ),
  SyndromeLearnerNote(
    id: 'P030',
    name: '声线漂移症',
    what: '文风随段落漂移，前后声线不统一，读者辨不出这是谁写的。',
    why: '声线是你的辨识度，漂移等于读者每次都要重新认识你。',
    signs: ['情绪一来文风突变', '模仿腔和本色腔混着用'],
    actionRefs: ['A009', 'A016'],
  ),
  SyndromeLearnerNote(
    id: 'P031',
    name: '题材边界感缺失症',
    what: '不清楚自己写的是什么题材、给谁看，或题材内部混搭失焦。',
    why: '读者找不到类型预期就划走，混搭还容易两头不讨好。',
    signs: ['言情里硬塞系统设定', '写之前没想过目标读者是谁'],
    actionRefs: ['A007', 'A003'],
  ),
  SyndromeLearnerNote(
    id: 'P032',
    name: '翻译腔/外来语干扰症',
    what: '句子带着翻译腔（长定语、名词化、被动堆砌），或被外来语、音译词打断语流。',
    why: '读起来像机翻不像人写，中文语感被破坏，代入感打折。',
    signs: ['「他是一个…的人」式长定语', '生硬音译词打断句子'],
    actionRefs: ['A006', 'A011'],
  ),
  SyndromeLearnerNote(
    id: 'P033',
    name: '冲突未升级/模式重复症',
    what: '同一模式反复出现但强度没有递增，读者第二次就摸清规律。',
    why: '第三次只是把音量调大，没有新信息，紧张感失效。',
    signs: ['每章都是「异常→紧张→虚惊一场」', '威胁、信息量、情绪都没有递增'],
    actionRefs: ['A007', 'A003', 'A009'],
  ),
  SyndromeLearnerNote(
    id: 'P034',
    name: '指称歧义/零回指过载症',
    what: '连续多个小句省略主语或宾语，读者要回看上段才确认「他/她/它」指谁。',
    why: '解歧负担转嫁给读者，阅读被卡顿打断。',
    signs: ['一段里连续省略主语', '「他说」之后接「她笑了」读者分不清谁'],
    actionRefs: ['A002'],
  ),
];

/// 按编号取条目（无则返回 null；调用方自行兜底）
SyndromeLearnerNote? syndromeLearnerNoteById(String id) {
  for (final note in kSyndromeLearnerNotes) {
    if (note.id == id) return note;
  }
  return null;
}
