// ─────────────────────────────────────────────────────────────
// NoviceModeGuide — 纯新手模式（ADR-C122）
//
// 取代 onboarding 问卷：入口 = 对话页「➕」面板。
// 全部为 UI 层固定常量 + 本地规则解析，**不触注入 prompt**
// （R-027 判定见 ADR-C122 §4：不注入 skills_*.dart / skill_registry /
// few-shot / message_injector，不新增 P/T/A 注册表条目）。
//
// 流程：
//   1. 「➕」→「纯新手模式」→ 固定确认弹窗（kNoviceModeDialog*）
//   2. 确认 → 会话内插入固定首条消息 kNoviceModeFirstMessage
//      （AI 主动自我介绍 + 主动询问三字段，覆盖原问卷全部采集字段）
//   3. 学员自由文本回答 → 本地解析（parse*）：
//      - 三字段可识别 → 组装 OnboardingData 落库（复用 onboarding_service
//        三步迁移）→ 插入固定分支引导消息（小白/有基础）
//      - 不可识别 → 插入固定追问消息（最多 kNoviceMaxRetries 轮，
//        仍失败则按默认值 beginner/mixed 落库并给出兜底引导）
//
// R-009：引导语只「问 + 引」，不给范文、不评分、不给写作处方；
// 水平自评示例是原问卷 Q1 的对号入座锚点（不是写作范文）。
// 小白引导语**无任何时间压力措辞**（30 秒机制已作废）。
// ─────────────────────────────────────────────────────────────

import '../../types/teaching_types.dart';

/// 解析最多轮数（学员两次都答不出可识别内容 → 默认值兜底）
const int kNoviceMaxRetries = 2;

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

/// 固定首条消息（AI 主动自我介绍 + 主动询问；UI 层常量，由宿主插入
/// assistant 消息落库并渲染，不经过 LLM 生成）
const String kNoviceModeFirstMessage =
    '你好，我是月笙，你的专属写作教练。\n\n'
    '先说清楚我的工作方式：我不替你写句子，也不替你做决定——'
    '我的工作是帮你看懂自己的写作、练对方向。\n\n'
    '开始之前，先问你三个问题，让我了解你现在的情况：\n'
    '① 你现在的写作大概是什么水平？可以对照下面这几句对号入座：\n'
    '　·「天黑了，她很害怕，就走回家了」——刚开始写\n'
    '　·「夜色渐浓，她加快脚步，心里有些发慌」——写过一些片段\n'
    '　·「路灯在她身后一盏盏暗下去，影子拉得老长」——能写完整场景\n'
    '　·「巷子深处传来猫叫，她停下脚步」——有完整作品\n'
    '② 你最想提升哪个方面？人物塑造 / 情节设计 / 文笔修辞 / 世界观构建，可以多选\n'
    '③ 你平时喜欢怎么学？多练少讲 / 先理解再练 / 边练边讲\n\n'
    '可以一句句答，也可以一次全说。';

/// 固定追问消息（学员回答未能识别出三字段时插入）
const String kNoviceModeFollowUpMessage =
    '刚才的三个问题还差一点没看全，麻烦补一下：\n'
    '① 写作水平（对照上面那四句，最接近哪一句？）\n'
    '② 想提升的方向（人物 / 情节 / 文笔 / 世界观，可以多选）\n'
    '③ 学习偏好（多练少讲 / 先理解再练 / 边练边讲）\n\n'
    '随便用你自己的话说就行。';

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
ProficiencyLevel parseProficiency(String text) {
  final t = text;
  if (_containsAny(t, const [
    '完整作品',
    '有作品',
    '长篇',
    '老手',
    '熟练',
    '能写完整场景',
    '出版',
  ])) {
    return ProficiencyLevel.advanced;
  }
  if (_containsAny(t, const ['完整场景', '完整章节', '中篇', '能写场景', '写到一半', '卡在中段'])) {
    return ProficiencyLevel.intermediate;
  }
  if (_containsAny(t, const [
    '写过一些',
    '写过片段',
    '片段',
    '短篇',
    '勉强',
    '半懂不懂',
    '写不出来',
  ])) {
    return ProficiencyLevel.elementary;
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

/// 三字段是否已可识别（proficiency 恒有兜底值，故以「方向或偏好至少
/// 命中一项」为完成判据——保证学员不是只回了「不知道」就被放行）
bool isNoviceAnswerComplete(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  final hasProficiencySignal = !_containsAny(t, const [
    '不知道',
    '没想过',
    '随便',
    '跳过',
  ]);
  return hasProficiencySignal &&
      (parseFocusAreas(t).isNotEmpty ||
          parseCognitiveStyle(t) != CognitiveStyle.mixed);
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
