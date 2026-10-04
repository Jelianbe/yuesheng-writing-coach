// ─────────────────────────────────────────────────────────────
// NoviceModeGuide — 纯新手模式（ADR-C122）
//
// 取代 onboarding 问卷：入口 = 对话页「➕」面板。
// 全部为 UI 层固定常量 + 本地规则解析，**不触注入 prompt**
// （R-027 判定见 ADR-C122 §4：不注入 skills_*.dart / skill_registry /
// few-shot / message_injector，不新增 P/T/A 注册表条目）。
//
// 流程（★ 2026-10-04 依舰长真机反馈重写，见 kNoviceModeFirstMessage 长注）：
//   1. 「➕」→「纯新手模式」→ 固定确认弹窗（kNoviceModeDialog*）
//   2. 确认 → **新建会话** → 插入固定首条消息 kNoviceModeFirstMessage
//      （一句话自我介绍 + 只问「有没有写作基础」）
//   3. 学员回答后**立刻进正题**（分支引导），不再有任何"答完才放行"的闸门；
//      能解析到的字段落库（供学员画像段用），解析不到就整段不注入
//      （student_profile_format.dart:102 是 `if (onboarding == null) return`，
//      缺字段不崩、只是少一段教学约束）。
//
// R-009：引导语只「问 + 引」，不给范文、不评分、不给写作处方。
// 小白引导语**无任何时间压力措辞**（30 秒机制已作废）。
// ─────────────────────────────────────────────────────────────

import '../../types/teaching_types.dart';

/// 解析上限（★ 2026-10-04 归零保留：不再有追问轮次）
///
/// 原为 2，配合chat_page 的 `_noviceRetries`（State 局部变量，页面重建即归零）
/// 会形成复读循环。甲方案下**答不上来直接进正题**，故本常量不再参与流程，
/// 保留定义仅为不破坏既有引用（chat_page 仍 import 本库）。
const int kNoviceMaxRetries = 0;

/// 纯新手模式消息的 messageType 标记（C123）。
///
/// 新手问答（AI 固定引导 + 学员三字段采集回答）落库时打此标记：
/// - **UI 消息列表仍全量显示**（message_card_dispatcher 白名单未命中 → 回退普通气泡）；
/// - **喂 LLM 的诊断上下文在 chat_service._loadSessionContext 处剔除**，
///   避免把采集问答当学员真实写作文本混入后续真实诊断。
/// messageType 为 TEXT 自由取值（无 CHECK 约束），加此值零 schema 迁移。
const String kNoviceMessageType = 'novice_chat';

/// 固定弹窗标题
const String kNoviceModeDialogTitle = '进入纯新手模式';

/// 固定弹窗内容（告知学员 AI 将主动询问；固定 UI 文案）
const String kNoviceModeDialogContent =
    '月笙会先自我介绍，然后主动问你三个问题：\n'
    '① 你现在写作大概是什么水平\n'
    '② 你最想提升哪个方面\n'
    '③ 你平时喜欢怎么学\n\n'
    '回答完，月笙会按你的情况引导你写第一段，或带你去看教学资料。\n'
    '不需要你之前写过任何东西。';

/// 固定首条消息（AI 主动自我介绍 + **只问一句话**）
///
/// ★ 2026-10-04 依舰长真机反馈重写（原版一次问三题 + 强制答完才放行）：
/// 原实现一次抛出三问、且`isNoviceAnswerComplete` 要求「方向或偏好至少命中
/// 一项」才算通过 ⇒ 学员答不全就被追问、被卡住。舰长的原话期待是
/// 「转一句话：你好，我是月笙，我可以从零基础开始叫你写作，你之前有写作基础吗？」
///
/// 本次改动（甲方案，经舰长裁定）：
///  ① 首条消息**只问一句**（有没有写作基础），不再列三问、不再给四句
///     水平对号入座表（那是问卷残留，且「必须挑一句」同样是强制）；
///  ② 学员回答后**立刻进正题**，不再有任何"答完才放行"的闸门；
///  ③ 方向/偏好/目标三字段改为**在后续真实对话里由AI 顺带问**，
///     解析到就落库、解析不到就不落——画像段是「有则注入、无则整段跳过」
///     （student_profile_format.dart:102），缺字段不会崩，只会少一段约束。
///     保留它们是因为 proficiency 决定三档完全不同的教学方式约束
///     （student_profile_format.dart:108-124），直接删会让新手/进阶/高手
///     教学分层永久失效。
///  ④ 追问仍保留（AI 需要知道「没答上来」该怎么办），但**上限降为 1**且
///     不再重复同一段话——原版kNoviceMaxRetries=2 且两条追问几乎同文，
///     叠加 State 变量归零（见 chat_page _noviceRetries）会形成复读循环。
const String kNoviceModeFirstMessage =
    '你好，我是月笙，我可以从零基础开始叫你写作。\n\n'
    '我不替你写句子，也不替你做决定——我的工作是帮你看懂自己的写作、'
    '练对方向。\n\n'
    '你之前有写作基础吗？有的话简单说说写到哪儿了，没有也完全没关系，'
    '我们从零开始。';

/// 固定追问消息（学员回答未能识别出写作基础时插入，**只问一次**）
///
/// ★ 2026-10-04：原版把三问原样重复一遍（:67-72），叠加 chat_page 的
/// `_noviceRetries` 是 State 局部变量（页面重建即归零）⇒ 复读循环。
/// 现改为**不追问**：直接给兜底引导进正题。理由——舰长要的是「转一句话」，
/// 追问本身就是「必须答完」的残留；答不上来不该阻断学习。
/// 保留本常量仅供未来显式复用，当前流程不再引用（见 novice_mode_guide 头注 ④）。
@Deprecated('2026-10-04 起不再追问：答不上来直接进正题，避免复读循环')
const String kNoviceModeFollowUpMessage =
    '没关系，我们先不纠结这些。\n\n'
    '现在直接写几句试试：窗外此刻能看见的三样东西，'
    '或者你脑子里想到的任何画面，想怎么写就怎么写。写完发给我，我帮你看。';

/// 小白分支引导（无时间压力，低门槛写作提示；R-009 不替写）
const String kNoviceModeBeginnerGuide =
    '好，我了解了。\n\n'
    '别急着想太多。先随手写几句：\n'
    '写窗外此刻能看见的三样东西，或者你此刻脑子里想到的任何画面——'
    '想怎么写就怎么写，写多少算多少。\n'
    '写完直接发给我，我帮你看。';

/// 有基础分支引导（引导到资料区 / 直接开写）
const String kNoviceModeAdvancedGuide =
    '好，我知道了。\n\n'
    '你可以直接写一段发给我，我帮你看；\n'
    '也可以先去成长页的「教学资料」看看症候解读——想先看哪边都行。';

/// 解析兜底引导（两次追问仍无法识别 → 按默认值落库后给出）
const String kNoviceModeFallbackGuide =
    '没关系，我们先不纠结这些。\n\n'
    '现在直接写几句试试：窗外此刻能看见的三样东西，或者你脑子里'
    '想到的任何画面，想怎么写就怎么写。写完发给我，我帮你看。';

/// ── 本地规则解析（关键词 → 枚举；纯函数，可单测）──

/// 写作水平解析（未命中任一档 → beginner 兜底）
///
/// ★ 2026-10-04 扩表：首条消息已改成只问「你之前有写作基础吗？」，
/// 学员最可能的回答是「没有 / 没写过 / 零基础」这类**否定式**，
/// 原词表（:99-124）全是肯定式信号（完整作品/长篇/老手…）⇒ 否定回答
/// 会掉到 beginner 兜底——beginner 恰好是对的，但那是**碰巧对**：
/// 若学员答「有点基础但没写过完整小说」，原表会误判 beginner。
/// 故补两组：先判否定（明确零基础），再判肯定。
/// 水平档位 → 触发信号词表（**顺序即优先级**：从上到下第一个命中即返回）。
///
/// ★ 2026-10-04 表驱动化（原为 5 个串联 `if (_containsAny(...))` 分支，
/// 66 行超 R-019 上限 50）。改动等价、但把「档位顺序」这件易错的事
/// 从代码结构变成**数据顺序**——2026-10-04 本批就踩过一次：
/// intermediate 档被新加的 '写过' 抢在前面 ⇒ 该档变死代码。
///
/// **调整档位时只改本表顺序，不要在解析函数里加分支**：
/// 更具体的档位必须排在更宽泛的之前（如 intermediate 早于 elementary）。
const List<(ProficiencyLevel, List<String>)> _kProficiencyCascade = [
  // ① 明确否定 / 零基础 —— 必须最先判：否则「没写过但有点基础」会被
  //    下面的 '有基础' / '写过' 抓走（学员说的是"没写过完整小说"）。
  (
    ProficiencyLevel.beginner,
    [
      '没有基础',
      '没基础',
      '零基础',
      '没写过',
      '没有写过',
      '没写过东西',
      '从零',
      '完全没',
      '一点没',
      '没碰过',
      '没开始',
    ],
  ),
  // ② 已发表/长篇 —— 最具体的一档。
  (
    ProficiencyLevel.advanced,
    ['完整作品', '有作品', '长篇', '老手', '熟练', '能写完整场景', '出版'],
  ),
  // ③ 写到一半 / 中篇 —— 必须早于 ④（'写过' 属 ④ 组，否则此档变死代码）。
  (
    ProficiencyLevel.intermediate,
    ['完整场景', '完整章节', '中篇', '能写场景', '写到一半', '卡在中段'],
  ),
  // ④ 片段级/ 自认勉强。
  (
    ProficiencyLevel.elementary,
    ['写过一些', '写过片段', '片段', '短篇', '勉强', '半懂不懂', '写不出来', '有点基础', '有一些基础', '基础还行'],
  ),
  // ⑤ 有基础但无量化词（回答含糊但确有基础）—— 最宽的一组。
  (ProficiencyLevel.elementary, ['有基础', '写过', '发表过', '投稿过']),
];

/// 写作水平解析：表驱动级联，未命中任一档 → beginner 兜底。
///
/// 词表设计见 [_kProficiencyCascade] 的说明（含两处顺序陷阱）。
ProficiencyLevel parseProficiency(String text) {
  for (final (level, keys) in _kProficiencyCascade) {
    if (_containsAny(text, keys)) return level;
  }
  return ProficiencyLevel.beginner;
}

/// 提升方向解析（多选；命中 kFocusAreaOptions 子集）
List<String> parseFocusAreas(String text) {
  final t = text;
  final areas = <String>[];
  if (_containsAny(t, const ['人物', '角色', '人设'])) {
    areas.add('人物塑造');
  }
  if (_containsAny(t, const ['情节', '剧情', '故事', '冲突', '节奏'])) {
    areas.add('情节设计');
  }
  if (_containsAny(t, const ['文笔', '描写', '修辞', '语言', '细节', '画面'])) {
    areas.add('文笔修辞');
  }
  if (_containsAny(t, const ['世界观', '设定', '背景', '体系'])) {
    areas.add('世界观构建');
  }
  return areas;
}

/// 学习偏好解析（未命中 → mixed 兜底）
CognitiveStyle parseCognitiveStyle(String text) {
  final t = text;
  if (_containsAny(t, const ['多练', '快', '动手', '直接写', '少讲', '实践'])) {
    return CognitiveStyle.intuitive;
  }
  if (_containsAny(t, const ['讲解', '理解', '深度', '道理', '原理', '先学', '看懂'])) {
    return CognitiveStyle.analytical;
  }
  return CognitiveStyle.mixed;
}

/// 回答是否「够用」（决定何时放行学员进正题）
///
/// ★ 2026-10-04 语义变更（甲方案）：原名`isNoviceAnswerComplete`、原语义是
/// 「三字段都识别到才算完成」，判据为「方向或偏好至少命中一项」⇒ 答不全就被
/// 追问、被卡在引导里。这正是舰长说的「被强制了，必须全部答完」。
///
/// 现语义：**只问一句「有没有写作基础」，所以只需识别到基础信号即放行**；
/// 任何非空回答（含「不知道」「跳过」）一律放行 —— 采集是可选的，
/// 阻断学习才是问题。方向/偏好/目标改为后续真实对话里顺带采集（解析到
/// 就落库，解析不到就不注入画像段）。
bool isNoviceAnswerComplete(String text) {
  // 唯一仍算「不够用」的情况：完全空回复（用户还没说话就触发了发送）。
  // 注意**不再**检查「不知道/没想过/随便/跳过」——那些都是有效回答。
  return text.trim().isNotEmpty;
}

/// 组装 OnboardingData（纯新手模式落库；skipped=false，正式采集）
OnboardingData buildNoviceOnboardingData(String text) {
  return OnboardingData(
    proficiency: parseProficiency(text),
    focusAreas: parseFocusAreas(text),
    cognitiveStyle: parseCognitiveStyle(text),
    writingGoal: '',
    completedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    skipped: false,
  );
}

/// 分支判定：小白（N0/N1）→ 低门槛写作引导；有基础（N2/N3）→ 资料区/开写
bool isBeginnerGuide(ProficiencyLevel proficiency) {
  return proficiency == ProficiencyLevel.beginner ||
      proficiency == ProficiencyLevel.elementary;
}

bool _containsAny(String text, List<String> keywords) {
  for (final k in keywords) {
    if (text.contains(k)) return true;
  }
  return false;
}
