// ─────────────────────────────────────────────────────────────
// P031 前提层承接入口（T-20261110-13 · 甲裁定实现 · 2026-11-11 舰长批）
//
// 报批稿：.ai/reports/2026-11-11-报批稿-P031前提层承接入口.md（strict rc=0）
// 交互设计：.ai/reports/2026-11-11-交互设计-P031前提层承接入口-简知微.md
//
// 背景：P031（题材边界感缺失）已裁退出诊断面（kNonDiagnosableSyndromeIds），
// 但判据对象在创作前提层（全书题材定位），单章窗口无它的位置 ⇒ 三段教学
// 内容全部不可达。本文件提供**非诊断触发**的教学入口：学员在对话里谈
// 题材/赛道/定位时，注入教学上下文（手册精简段 + 训练KB + 边界句）。
//
// 硬约束（报批稿 N1/N2/N3）：
//   · 不产生诊断记录、不碰 kNonDiagnosableSyndromeIds 语义；
//   · 教学姿态 = 引导学员自己想清，不替学员选题材/赛道/读者；
//   · 静态锚零漂移（条件注入不入 kChunkSystemPrompt 计量面）。
// ─────────────────────────────────────────────────────────────

import 'intent_classifier.dart';
import 'llm_client.dart';
import 'training_knowledge_base.dart'; // kTrainingFullKnowledge（公开 const，part 分片拼接）

/// 题材定位关键词集 K（报批稿 ④-5 终稿草案 · U3 签核 2026-11-11 维持 11 词；
/// 形态参照 chat_gates.dart kHelpSeekingKeywords。误报采样挂 prompt-behavior-sampling）
const List<String> kPremiseTopicKeywords = [
  '题材',
  '赛道',
  '定位',
  '什么类型',
  '什么书',
  '写给谁',
  '读者画像',
  '混搭',
  '类型融合',
  '网文方向',
  '写什么题材',
];

/// 触发头注（报批稿 ④-1 逐字）
const String _kPremiseHeader =
    '学员正在讨论作品定位、题材或赛道选择。这是前提层教学对话，不是文本诊断：'
    '不要报任何症候编号，不要判定严重度，不要输出诊断结论。对话历史里已教过的'
    '内容不必重复，按学员本轮的新问题推进。';

/// P031 手册精简段（报批稿 ④-2 逐字；old = syndrome_kb_content_manual_6.dart
/// P031 节。U3 签核裁点落地：删「严重度判断」段 + 「诊断锚点示例」段 +
/// position_sensitivity 行（诊断口吻，注入诱导模型判级违反 N2）；
/// 核心问题段 P011 编号引用改为自然语言）
const String _kPremiseManualSection =
    '**核心问题**：写作者不清楚自己写的是哪个题材赛道、目标读者是谁，题材内部'
    '混搭失焦（言情里硬塞科幻设定、历史里硬塞系统文），读者找不到类型预期，'
    '平台也推不动。这不是开篇节奏问题（黄金三章），而是更前置的**赛道定位**'
    '问题——连"写给谁看"都没想清。\n\n'
    '**触发信号**：开篇大段世界观铺陈却不说清楚类型；同一本书里言情、悬疑、'
    '科幻元素随机混搭；作者自己说不清"这本书像哪一类畅销书"；题材随热点飘移，'
    '上一本赘婿下一本无限流毫无积累。\n\n'
    '**判断原则**（基于上下文，非硬性标准）：\n'
    '- 读者能不能用一句话说出"这是本什么书"？\n'
    '- 题材混搭是否有统一的内核（类型约定）支撑，还是单纯蹭元素？\n'
    '- 目标读者画像是否清晰（给谁爽、给谁哭）？\n'
    '- **以下不判题材边界缺失**（原例外内化）：①有意做类型融合且内核统一'
    '（如蒸汽朋克=工业+魔法，有明确审美纲领）；②文学性实验作品——类型边界本'
    '就是讨论对象；③系列化多品类——作者明确是多线品牌策略，判定对象为单本'
    '而非跨本。\n\n'
    '**推荐教学动作**：首选 A007 一句话冲突，备选 A003 五问法\n\n'
    '**外部佐证（商业网文向标注）**：本症候为"商业网文向"题材定位专项——面向'
    '以网文商业逻辑写作的学员；非商业/纯文学向学员若题材融合有纲领则不触发。';

/// 教练边界句（报批稿 ④-4 逐字）
const String _kPremiseBoundary =
    '教学姿态：用提问引导学员自己想清定位。一句话测试、五问法、读者画像都由学员'
    '自己回答；不替学员选题材、选赛道、定读者。';

/// G2：键入文本是否命中题材定位关键词集 K（只判调用方传入的键入文本——
/// 引用附件 / mention 内容由调用方排除，不计入，报批稿 R6）
bool premiseTopicHit(String typedText) =>
    kPremiseTopicKeywords.any(typedText.contains);

/// 从训练知识库提取单症候节（与 training_knowledge_base.dart
/// _extractTrainingSection 同构；单一真源零复制——KB 文本不落地本文件，
/// 漂移由源文件唯一化消除）
String _extractKbSection(String id) {
  final pattern = RegExp('^## $id ', multiLine: true);
  final match = pattern.firstMatch(kTrainingFullKnowledge);
  if (match == null) return '';
  final startIdx = match.start;
  final nextSection = kTrainingFullKnowledge.indexOf('\n## ', startIdx + 1);
  final endIdx = nextSection != -1
      ? nextSection
      : kTrainingFullKnowledge.length;
  return kTrainingFullKnowledge.substring(startIdx, endIdx).trim();
}

/// 注入判据（G1 诊断优先 + G2 键入命中）。
///
/// 返回 null = 本轮不注入；非 null = 注入文本（含 P031 段标记 = R1 断言锚）。
/// 注入不设冷却（G3——每命中轮注入，教练凭 KB 回应当轮新问题）。
/// G1：诊断链路意图（compose，ADR-0005 意图硬门语义）优先，抑制前提层注入
/// ——显式诊断请求走诊断链是既有契约，前提层入口服务「聊」形态（ask/revise/
/// smalltalk）。
String? buildPremiseTeachingInjection({
  required UserIntent intent,
  required String typedText,
}) {
  if (intent == UserIntent.compose) return null;
  if (!premiseTopicHit(typedText)) return null;
  final kb = _extractKbSection('P031');
  if (kb.isEmpty) return null; // 防御：知识库异常时不注入残缺教学
  return '$_kPremiseHeader\n\n'
      '## 题材定位教学参考（前提层 · 非诊断）\n\n'
      '$_kPremiseManualSection\n\n'
      '$kb\n\n'
      '$_kPremiseBoundary';
}

/// 一段式接线入口（message_injector.injectTrailingHints 调用；
/// 逻辑全部在本文件——宿主文件只加一行，R-019 等行数纪律）
void maybeInjectPremiseTeaching({
  required String content,
  required List<ChatMessage> messages,
}) {
  final note = buildPremiseTeachingInjection(
    intent: classifyUserIntent(content),
    typedText: content,
  );
  if (note != null) {
    messages.add(ChatMessage(role: 'system', content: note));
  }
}
