// ─────────────────────────────────────────────────────────────
// 真实文段诊断链路验证 · **双厂商对照**（智谱 glm-4.7-flash / DeepSeek v4-flash）
//
// 目标（用户 2026-10-05 裁定）：回答「模型能不能真给出可用诊断」，
//   而非「能不能调通」。管道通不通由前置体检单独负责。
//
// ★★ 为什么是双厂商（2026-10-05 晚补）：舰长指出「我们这次改了提示词」。
//   实测核实成立：**ADR-0003 阶段一 A1**（`c36021fe`，10-05 10:55 已合主线）
//   改了诊断注入面 —— 注册表 34→37 · few-shot 库 34→37 · 三条新 L3 手册/训练段。
//   而本测试的智谱跑测发生在其**之后** ⇒ 单跑智谱无法区分
//   「模型能力如此」与「注入面变了导致如此」。
//   ⇒ 同一套样本 / 同一套判据 / 同一段 prompt，**两个厂商各跑一遍**：
//     同条件对照下，差异只能归到「模型」这一个变量上。
//   ⚠️ 注意：若某厂商 key 未设，该厂商用例自动 skip（不破门禁），
//     此时「双厂商对照」实际退化为单厂商 —— 读结论时须看护栏计数。
//
// ★ 现状（2026-10-05 实测）：**只有智谱 key**（舰长提供）。
//   DeepSeek key 未设 ⇒ DS 用例 skip。DS 预设本身是齐的
//   （`api_config_page.dart:62-64` baseUrl `https://api.deepseek.com`
//   · model `deepseek-v4-flash`）。
//
// 设计要点 —— **单变量对照**（样本层）：
//   样本 A（有症状）与样本 B（干净文本）**共用同一个 focusSyndromeId、
//   同一知识库、同一 prompt**，唯一差异是投喂的文本本身。
//   ⇒ 若 A 报出症状而 B 不报，才能归因到「模型真在读文本」；
//     若两者输出形态一致，则说明它在复读知识库 / 无差别套模板。
//
// 注入点（照生产 message_injector._injectTrainingKnowledge:1956-1963）：
//   preamble + getTrainingContent([id]) + getTrainingFewShot([id]) + user 文本
//
// 双组结构（仿 live_fewshot_replay_test）：
//   1) 常驻自检组（无 tag，门禁全量必跑）：_ScriptedFakeLlmClient 喂
//      「行为级贴合」与「词面复读 / 编造引文」两类脚本输出，跑与 live 组
//      完全相同的判定器，证明判真/剔假自洽、无 key 可跑。
//   2) live 组（per-test tags: ['live','external']）：逐厂商真实调用。
//      无该厂商 key 时每个 test 内 markTestSkipped，不破门禁全量。
//
// 判据（行为级，非词面）—— **与厂商无关**，两厂商共用同一套：
//   ① 引用性  —— 输出须命中**本样本自己**的 planted 专名中**至少一个**
//      （证明读了文本，不是凭知识库模板编的）。注意是 ≥1 而非全部：
//      诊断答复不必逐个复述人名，要求全部出现会让判据比被测对象更严，
//      测出来的是措辞偏好而非模型质量（初版即栽在这，见 _judge 注释）。
//   ② 无幻觉  —— 输出中**声称引自原文**的引号内容（≥2 字）须逐字出现在本
//      样本 probe 里；编造即教练指着不存在的字说话，是教学系统的致命伤。
//      ⚠️ 只校验「声称引原文」的引号（带引述标记或位于引用块）。
//      中文里引号还用于**术语命名**（`这是典型的「降智反派」`）与强调；
//      混进判据会系统性误判——实测一条真实输出被误报 8 项幻觉。
//      而「用语料比对来放行」也不成立：模型会自造术语（实测
//      `剧情工具人`、`高手博弈` 均不在知识库内），语料比对无法区分
//      自造与编造 ⇒ 改判「是否声称引原文」这个可观察属性。
//   ③ 症候两面（A 专有）—— 须 articulating 出该症候的两个概念侧面，
//      只复读症候名不算命中。
//   B 不要求「必须说好话」—— 干净文本给通用建议是合理的；B 的门只有
//      ①②（读过 + 不编造）。这是有意放开的边界：把「敢不敢报问题」
//      交给教练人设去管，本测试只管「报得准不准、编不编」。
//
// 费用护栏：**每厂商** 2 样本 × 3 票 = 6 次计划内调用；测试侧硬上限 16
//   （含瞬时错误退避重试，重试同样计数 —— 服务方容量抖动会消耗预算）。
//   对照断言**复用**这 6 次的采样结果，不额外发调用（见 live 组 sampled）。
//
// ★ 服务方差异（2026-10-05 实测，必须逐厂商处理，照抄会全数失败）：
//   智谱 glm-4.7-flash：首调 HTTP 429 / code 1305「该模型当前访问量过大」，
//     退避中夹杂 code 500，第 3 次才 200；且短时间连发 6 次即触发限流
//     （实测第二轮 6 次调用**全部**被拒：429 / 60s 超时）。
//   ⇒ 退避窗口统一放宽到 5s/15s/30s（`live_fewshot_replay` 的 2s/4s 对此不够）；
//     429/1305/500 一律按**瞬时**处理（鉴权失败才是 401/403）。
//
// 运行真实回放（key 只经环境变量，严禁写入源码）：
//   $env:ZHIPU_API_KEY="xxx.yyy"       # 智谱
//   $env:DEEPSEEK_API_KEY="sk-xxx"# DeepSeek
//   flutter test --tags "live,external" test/live_zhipu_diagnosis_test.dart
// ─────────────────────────────────────────────────────────────

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_retry.dart';
import 'package:writingcoach/services/llm_usage_monitor.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';

/// 一个可跑真实链路的厂商。
///
/// ★ 两厂商**共用**样本 / 判据 / prompt / focus 症状，
///   唯一差异是这三个字段（端点 + 模型名 + key 来自哪个环境变量）
///   ⇒ 差异只能归到「模型」这一个变量上（这才是对照的意义）。
class _Provider {
  final String label;
  final String baseUrl;
  final String model;

  /// key 的环境变量名（R-029：仅经环境变量注入，严禁写入源码）。
  final String envKey;
  const _Provider({
    required this.label,
    required this.baseUrl,
    required this.model,
    required this.envKey,
  });
}

/// 厂商清单。DeepSeek 的 baseUrl/model 取生产预设
/// （`api_config_page.dart:62-64`，与 `_llmPresets` 逐字一致 ⇒ BYOK 走同一条路）。
const List<_Provider> _providers = [
  _Provider(
    label: '智谱',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4.7-flash',
    envKey: 'ZHIPU_API_KEY',
  ),
  _Provider(
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-v4-flash',
    envKey: 'DEEPSEEK_API_KEY',
  ),
];

/// A / B 共用的 focusSyndromeId —— 单变量对照的前提：知识库完全相同。
const String _kFocusSyndromeId = 'P029';

/// **每厂商**真实调用硬上限（含退避重试的消耗）。
/// 计划内 6 次（2 样本 × 3 票；对照复用同批票，不额外发调用）。
/// 上限 16 是为退避留的余量 —— 实测服务方抖动常吃掉 2–3 次重试
/// （智谱实测第二轮 6 次全被拒，退避 3 轮仍耗尽）。
const int _kMaxRealCallsPerProvider = 16;

const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 教练前置。R-009：诊断指向根因、不替写、不替决定。
const String _kCoachPreamble =
    '你是一名写作教练。学员给你看一段他新写的小说文字，请你做诊断，'
    '不要替学员改写句子、不要替他做决定。'
    '请指出这段文字里最核心的一个写作问题：必须点到具体位置（引用原文里的词或句），'
    '并说明这个问题为什么是问题、它伤害了读者的什么阅读体验。一次只聚焦一个最主要的点。';

/// 单样本配置。
class _Case {
  final String id;
  final String name;
  final String probe;

  /// 我在 probe 里种入的专名（示例块与知识库中均不出现）。
  /// 输出须命中 ≥1，证明模型真读了我的样本而非背诵知识库。
  final List<String> planted;

  /// 症候概念侧面 A / B（仅样本 A 要求；A 需两侧各命中 ≥1）。
  final List<String> facetA;
  final List<String> facetB;

  /// 自检用脚本：行为级贴合（判定器应判真）。
  final String hitScript;

  /// 自检用脚本：仅词面复读 + 编造引文（判定器应判假）。
  final String bypassScript;
  const _Case({
    required this.id,
    required this.name,
    required this.probe,
    required this.planted,
    this.facetA = const [],
    this.facetB = const [],
    required this.hitScript,
    required this.bypassScript,
  });
}

const List<_Case> _cases = [
  _Case(
    id: 'A',
    name: '有症状样本（降智反派）',
    probe:
        '漕帮孙舵主在城里经营二十年，手里捏着小伙计陈七欠下的三千两赌据，'
        '陈七的堂兄还在县衙当差。大堂之上，陈七只低着头嘟囔了一句「老泥鳅」。'
        '孙舵主当场翻了脸，一拍桌子站起来：「来人，把这小子给我沉到江里去！」',
    planted: ['孙舵主', '陈七', '老泥鳅', '赌据', '堂兄'],
    // ★ facet 必须是 P029 的**概念侧面**，不是 A 样本的词汇。
    //   ⚠️ 初版误用 A 的具体用词（`嘟囔/老泥鳅/拍/翻脸/犯不上`）⇒ 模型在
    //   B 样本上改用同义表达（`收起赌据/扔了筹码/放过/工具人`）时，
    //   `facetB` 恒 false ⇒ `isHit` 恒 false ⇒ B「看起来不报症状」
    //   ⇒ 单变量对照假绿（2026-10-05 实测踩中：rc=0 而 B 三票原文
    //   全部明确写着「P029」「工具化」）。
    //   词表来源 = few-shot 库 P029 原文的两个面（`training_few_shot_library.dart:493-499`）：
    //   面①「手握资源却放弃优势」·面②「被一句轻慢激怒 / 亲自动手 / 对手被工具化」。
    facetA: [
      '优势',
      '资源',
      '筹码',
      '把柄',
      '靠山',
      '手握',
      '捏着',
      '赌据',
      '三千两',
      '当差',
      '放弃',
      '不利用',
      '没用',
      '白白',
      '浪费',
      '收起',
      '放走',
      '放过',
    ],
    facetB: [
      '降智',
      '工具人',
      '工具化',
      '剧情需要',
      '剧情推进',
      '亲自',
      '下场',
      '翻脸',
      '拍案',
      '一句',
      '骂',
      '冲动',
      '为坏而坏',
      '无脑',
      '莽夫',
      '蠢',
      '送人头',
      '不计',
      '不计利',
    ],
    hitScript:
        '问题在孙舵主身上。他明明手里捏着陈七的赌据、堂兄又在县衙当差，'
        '本可以慢慢拿捏，却因为陈七一句嘟囔「老泥鳅」就拍桌叫人把他沉江——'
        '放着现成优势不用，被一句轻慢就亲自翻脸下场，动机立不住。',
    bypassScript:
        '这段存在降智反派问题。反派孙舵主写得不够聪明，需要改进，'
        '建议加强人物智力描写，整体人物塑造失败。另外「沉到江里去」'
        '这句台词过于直白，可以更有张力。',
  ),
  _Case(
    id: 'B',
    name: '干净样本（无降智反派症状，含同名元素作对照）',
    // 刻意保留「人物 / 对话 / 压迫感」这些**表层相似**元素，
    // 但孙舵主全程在用优势、从未被一句话激怒 ⇒ 判 A 那种症状即属编造。
    probe:
        '漕帮孙舵主在城里经营二十年，手里捏着小伙计陈七欠下的三千两赌据，'
        '陈七的堂兄还在县衙当差。大堂之上，孙舵主先是不动声色，'
        '把陈七欠赌据的年月一笔笔念完，才抬头问：'
        '「你堂兄在县衙当差，你倒好意思拿我三千两去赌？'
        '陈七听完全身发凉，跪下去只说了一句「小的再不敢了」。'
        '孙舵主把赌据折起来收进袖子，挥手让他起来。',
    // ⚠️ planted 必须**逐条存在于本样本自己的 probe 里**。初版误抄了 A 的
    //   `老泥鳅`（B 的 probe 中根本没有这个物件）⇒ B 的正确答案反被判成
    //   「未读过样本」。判据没错，是数据抄串了。
    planted: ['孙舵主', '陈七', '赌据', '堂兄', '年月'],
    // ★ facet 与样本**无关** ⇒ B 必须带与 A **完全相同**的一份。
    //   少了这一段，B 的 `facetA && facetB` 会因空列表恒为 false，
    //   使「单变量对照」那条 live 断言**永不可能失败**（假绿）。
    //   ⚠️ 另一层（2026-10-05 实测）：facet 必须是「**概念**侧面」而非
    //   A 样本的**词汇**。用 A 的具体用词（`嘟囔/老泥鳅/拍/翻脸`）时，
    //   模型在 B 上改用同义表达即 `facetB` 恒 false ⇒ B 假性「不报症状」
    //   ⇒ rc=0 却是假绿。故此处与 A 共用上面那份**概念级**词表。
    //   语义：B 若也报出「手握优势却放弃 + 被一句轻慢激怒 / 工具化」两面
    //        ⇒ 属无差别套模板。
    facetA: [
      '优势',
      '资源',
      '筹码',
      '把柄',
      '靠山',
      '手握',
      '捏着',
      '赌据',
      '三千两',
      '当差',
      '放弃',
      '不利用',
      '没用',
      '白白',
      '浪费',
      '收起',
      '放走',
      '放过',
    ],
    facetB: [
      '降智',
      '工具人',
      '工具化',
      '剧情需要',
      '剧情推进',
      '亲自',
      '下场',
      '翻脸',
      '拍案',
      '一句',
      '骂',
      '冲动',
      '为坏而坏',
      '无脑',
      '莽夫',
      '蠢',
      '送人头',
      '不计',
      '不计利',
    ],
    hitScript:
        '这段的力量在孙舵主「把陈七欠赌据的年月一笔笔念完」这一处：'
        '压迫感来自程序感而不是发作，他全程没抬高过声音，'
        '读者却跟着陈七「听完全身发凉」一起紧张起来。',
    // 旁路 = 复读 A 的症状（降智反派）+ **声称引自原文却引用 A 独有的物件**。
    // ⇒ 同时踩中 ① 未命中 B 专名（此脚本刻意不含 B 的任何专名）与
    //    ② 编造原文（「原文中的这句」是引述标记，判据②会校验其逐字性）。
    bypassScript:
        '这段存在降智反派问题。反派被小伙计一句「老泥鳅」就激得翻脸下命令，'
        '原文中的这句：「他当场翻脸，一拍桌子站起来」，'
        '放着现成的靠山不用，动机立不住，建议加强人物智力描写。',
  ),
];

/// 判定一个引号是否处在「**声称引自原文**」的上下文里。
///
/// ★ 中文写作用引号有三种用途，只 punishing 其中一种会系统性误判：
///   (a) 引原文  —— `原文中的这句：「陈七听完全身凉…」` / 引用块 `> 「…」`
///   (b) 术语命名 —— `这是典型的「降智反派」` / `变成了「剧情工具人」`
///   (c) 强调
///   初版按「引号内容是否在语料内」判定，实测一条输出误报 8 项，
///   因为模型会**自造术语**（实测 `剧情工具人`、`高手博弈` 均不在知识库内
///   —— 用「是否在语料内」根本区分不了自造与编造）。
///   ⇒ 改判「**它是否声称在引原文**」：(a) 类才校验逐字一致，(b)(c) 不管。
///
/// 判定线索：引号**前** 40 字窗口内出现引述标记（原文/原句/这句/台词/
/// 写着…），或引号位于引用块行（行首 `>`）。
/// 取 40 字窗口是实测定的：真实模型把标记与引号之间的换行、加粗、
/// 引导语都算进来，超短窗口会漏检。
const List<String> _kAttributionCues = [
  '原文',
  '原句',
  '原话',
  '这句',
  '这段',
  '台词',
  '写着',
  '写道',
  '念',
  '喊',
  '指着',
  '例如',
  '比如',
  '引用',
  '出自',
  '出自于',
  '说过',
];

/// 抽出所有「声称引自原文」的引号内容（≥2 字）。
///
/// 只认中文弯引号「」与直角引号『』；英文半角引号与单引号会大量误命中
///（撇号、代词缩写），故不纳入。
List<String> _extractQuotes(String s) {
  final out = <String>[];
  final pair = RegExp('[「『]([^」』]{2,})[」』]');
  for (final m in pair.allMatches(s)) {
    final head = s.substring(0, m.start);
    final inQuoteBlock = RegExp(
      r'^\s*>\s*\**\s*$',
    ).hasMatch(head.substring(head.lastIndexOf('\n') + 1));
    final cued = _kAttributionCues.any(
      head.substring(head.length < 40 ? 0 : head.length - 40).contains,
    );
    if (inQuoteBlock || cued) out.add(m.group(1)!);
  }
  return out;
}

/// 引文**呈现形态**归一化：换形态，不动内容。
///
/// 为什么需要（两层，均为 2026-10-05 智谱实测）：
///   ① 引号层级：中文排版里嵌套引号正确写法是外层「」+ 内层『』，
///      但模型按自己习惯**整体换一级**。probe 写
///      `站起来：「来人，把这小子给我沉到江里去！」`，模型引作
///      `站起来：『来人，把这小子给我沉到江里去！』`——逐字一致。
///   ② Markdown 装饰：模型常把引文加粗 ⇒ `「**来人…**」`，
///      而 probe 里没有 `**`。
///   两者都是**呈现层**，不是内容改写。而 `probe.contains(quote)` 不认
///   这两类装饰 ⇒ 被判成「编造引文」。
///
/// 性质判定：这是**判据缺陷**（比较维度选错），不是模型幻觉。
///   不修则每次都在测我的措辞偏好而非模型质量（反向假 FAIL，§4-177 第 1 条）。
///
/// 纪律：归一化**只动形态、不动一个字** ⇒ 真编造仍判红（测试内有正对照：
///   `沉到江里去` → `沉到江底去` 必须仍然判红）。
String _normalizeQuotes(String s) => s
    .replaceAll('『', '「')
    .replaceAll('』', '」')
    // Markdown 强调标记：`**` / `__` / 单个 `*` / `_`。
    // 中文正文里这四个字符不承担语义 ⇒ 删掉不影响逐字比对。
    .replaceAll('**', '')
    .replaceAll('__', '')
    .replaceAll('*', '')
    .replaceAll('_', '');

/// 判定器：单样本的行为级判据。返回各项明细，供 expect 逐项归因。
class _Verdict {
  final bool referenced; // ① 引用性
  final List<String> missingRefs; // ① 反向明细（应为空）
  final List<String> fakeQuotes; // ② 编造引文明细（应为空）
  final bool facetA;
  final bool facetB;

  _Verdict({
    required this.referenced,
    required this.missingRefs,
    required this.fakeQuotes,
    required this.facetA,
    required this.facetB,
  });

  /// 样本 A：① + ② + ③ 全中。
  bool get isHit => referenced && fakeQuotes.isEmpty && facetA && facetB;

  /// 样本 B：只要 ① + ②（不要求说好话，见文件头「判据」节）。
  bool get isClean => referenced && fakeQuotes.isEmpty;

  String get detail =>
      'referenced=$referenced miss=${missingRefs.join("/")} '
      'fakeQuotes=${fakeQuotes.join("/")} facetA=$facetA facetB=$facetB';
}

_Verdict _judge(String output, _Case c) {
  final missing = c.planted.where((p) => !output.contains(p)).toList();
  // 判据②：声称引自原文的引号内容，必须逐字出现在本样本 probe 里。
  // （不再与知识库比对 —— 模型会自造术语，实测「剧情工具人」「高手博弈」
  //  均不在知识库内，用语料比对根本区分不了「自造」与「编造」。）
  final fake = _extractQuotes(output)
      .where((q) => !_normalizeQuotes(c.probe).contains(_normalizeQuotes(q)))
      .toList();
  return _Verdict(
    // ⚠️ 口径：**命中 ≥1 即算读过样本**（对齐 live_fewshot_replay 的 `.any`）。
    //初版写成 `missing.isEmpty`（要求**全部** planted 都出现）⇒ 一条
    //  只引了 3/5 个人名的正确答案被判成「没读过样本」。
    //  在真实链路上这是**反向假 FAIL**：诊断答复本就不必逐个复述人名，
    //  判据会比被测对象更严格 ⇒ 测的就不再是模型质量而是我的措辞偏好。
    //  missing 保留为**诊断明细**（报告哪几个没被引用），不作判据。
    referenced: c.planted.any(output.contains),
    missingRefs: missing,
    fakeQuotes: fake,
    facetA: c.facetA.any(output.contains),
    facetB: c.facetB.any(output.contains),
  );
}

/// 组装消息。唯一变量是 probe 文本 —— 知识库 / few-shot / preamble 全同。
List<ChatMessage> _buildMessages(_Case c) {
  final msgs = <ChatMessage>[
    ChatMessage(role: 'system', content: _kCoachPreamble),
  ];
  final knowledge = getTrainingContent([_kFocusSyndromeId]);
  if (knowledge.isNotEmpty) {
    msgs.add(ChatMessage(role: 'system', content: knowledge));
  }
  final few = getTrainingFewShot([_kFocusSyndromeId]);
  if (few.isNotEmpty) {
    msgs.add(ChatMessage(role: 'system', content: few));
  }
  msgs.add(
    ChatMessage(
      role: 'user',
      content:
          '这是我新写的一段：\n\n${c.probe}\n\n'
          '请诊断这段文字最核心的写作问题——必须点到具体位置（引用原文的词或句），'
          '并说明它为什么是问题。不要替我改写。',
    ),
  );
  return msgs;
}

/// 脚本化 Fake LLM：覆写 chatCompletionWithMeta 直接返回预置文本。
/// 无 key、无网络、无配置依赖。
class _ScriptedFakeLlmClient extends LlmClient {
  final String content;
  _ScriptedFakeLlmClient(this.content);

  @override
  Future<ChatCompletionResult> chatCompletionWithMeta(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
    LlmRetryPolicy retryPolicy = LlmRetryPolicy.standard,
  }) async {
    return ChatCompletionResult(content: content);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── 常驻自检组（无 tag，门禁全量必跑，无 key 可跑）──
  //
  // ⚠️ 本组**与厂商无关**：判定器是厂商中立的，所以零 key 也能跑、也必须跑。
  //   若哪天把它挪进 tag 里，它就退化成装饰（门禁再也不会验证判定器有牙齿）。
  group('诊断判定器·常驻自检（FakeLlmClient：判定器能红能绿）', () {
    test('知识库 / few-shot 注入面非空且消息装配正确', () {
      expect(
        getTrainingContent([_kFocusSyndromeId]),
        isNotEmpty,
        reason: '$_kFocusSyndromeId 知识库应非空',
      );
      expect(
        getTrainingFewShot([_kFocusSyndromeId]),
        isNotEmpty,
        reason: '$_kFocusSyndromeId few-shot 库应非空',
      );
      final msgs = _buildMessages(_cases.first);
      expect(msgs.length, greaterThanOrEqualTo(3));
      expect(msgs.first.role, 'system');
      expect(msgs.last.role, 'user');
      expect(msgs.last.content, contains(_cases.first.probe));
    });

    for (final c in _cases) {
      test('[${c.id}] ${c.name}：行为级判真 / 旁路与编造判假', () async {
        final msgs = _buildMessages(c);
        // 行为级贴合 → 判真
        final hit = await _ScriptedFakeLlmClient(
          c.hitScript,
        ).chatCompletionWithMeta(msgs);
        expect(
          _judge(hit.content, c).isHit || _judge(hit.content, c).isClean,
          isTrue,
          reason:
              '${c.id} 判定器应接受「读过样本 + 无编造」的行为级输出，'
              '实得 ${_judge(hit.content, c).detail}',
        );
        // 仅词面复读 / 编造引文 → 判假
        final bypass = await _ScriptedFakeLlmClient(
          c.bypassScript,
        ).chatCompletionWithMeta(msgs);
        final v = _judge(bypass.content, c);
        expect(
          v.isHit && v.isClean,
          isFalse,
          reason: '${c.id} 判定器必须剔除旁路输出，实得 ${v.detail}',
        );
      });
    }

    // 判据自身有牙齿：B 样本的旁路脚本 = 复述 A 症状 + 编造引文。
    // ⚠️ 必须同时给**正对照**：否则这条测试只是复述「我写的脚本恰好不含
    //   B 的专名」，证明不了判据①真在起作用（假绿的一种）。
    //   正对照 = 把同一个 bypassScript 里的专名换成 B 的真实专名 ⇒
    //   ① 应转绿（读过样本了）、② 仍红（引文仍是 A 的「老泥鳅」）。
    //   这就证明 ① 与 ② 是两条**独立**判据，而非同一条判两次。
    test('判据有牙齿：B 旁路（复读 A 症状）违反①②，换成本样本专名后①转绿', () {
      final b = _cases[1];
      final v = _judge(b.bypassScript, b);
      expect(v.referenced, isFalse, reason: '应因未命中 B 样本专名而违反①');
      expect(v.fakeQuotes, isNotEmpty, reason: '应因编造引文而违反②');

      // 正对照：把「小伙计」换成 B 里真实存在的「陈七」。
      final patched = b.bypassScript.replaceAll('小伙计', '陈七');
      final v2 = _judge(patched, b);
      expect(v2.referenced, isTrue, reason: '① 应因命中本样本专名而转绿');
      expect(
        v2.fakeQuotes,
        isNotEmpty,
        reason: '② 应仍红 —— 引文「老泥鳅」不属于 B 样本，与① 相互独立',
      );
    });

    // ⚠️ 判据②改成「只校验声称引原文的引号」后必须复验它**仍有牙齿**：
    //   放宽的正当性只能来自「同一批真编造样本仍然被抓」。
    //   正对照四项，覆盖三种引号用法 + 一个真编造。
    test('判据②有牙齿：放行术语命名/真引文，仍抓声称引原文的编造', () {
      final a = _cases[0];
      // (b) 术语命名 —— 逐字取自真实模型输出（含模型自造术语「剧情工具人」）
      expect(
        _judge('这是典型的「降智反派」写法，反派变成了「剧情工具人」。', a).fakeQuotes,
        isEmpty,
        reason: '术语命名不应判幻觉（含知识库外的自造术语）',
      );
      // (a) 真引文：带引述标记 + 内容逐字在 probe 内 ⇒ 抽出但放行
      //（若这条写成无引述标记的「他嘟囔了一句「老泥鳅」」，则它压根不会被
      //  抽出、判据②没被触达 ⇒ 验证的是空集合而非校验逻辑。实测踩过。）
      expect(_extractQuotes('原文中的这句：「老泥鳅」'), ['老泥鳅'], reason: '真引文应被抽出并接受逐字校验');
      expect(
        _judge('原文中的这句：「老泥鳅」，他听了就翻脸。', a).fakeQuotes,
        isEmpty,
        reason: '真引文不应判幻觉',
      );
      // (c) 强调用法：无引述标记、无引用块 ⇒ 不校验
      expect(
        _judge('他「停顿」了很久，才开口。', a).fakeQuotes,
        isEmpty,
        reason: '无引述标记的引号不应纳入判据②',
      );
      // (a) 真编造：带引述标记 + 内容不在原文 ⇒ 必须判红
      final red = _judge('原文中的这句：「他抄了父亲的遗书永世不得翻身」，还砸了祠堂。', a);
      expect(
        red.fakeQuotes,
        contains('他抄了父亲的遗书永世不得翻身'),
        reason: '声称引原文却不逐字存在 ⇒ 判据②必须抓住，否则该判据已成装饰',
      );
      // 引用块同样纳入（模型常用 `> 「…」` 而不加引述标记）
      expect(
        _judge('问题在这句：\n> 「他抄了父亲的遗书永世不得翻身」', a).fakeQuotes,
        contains('他抄了父亲的遗书永世不得翻身'),
        reason: '引用块内的编造也必须被抓',
      );
    });

    // ⚠️ 判据②**必须先做呈现形态归一化**（2026-10-05 智谱实测修，两层）。
    //   现象①：probe 写「来人，把这小子给我沉到江里去！」，模型引作
    //     『来人，把这小子给我沉到江里去！』—— 逐字一致、仅引号层级不同，
    //     未归一化时被 `probe.contains(quote)` 判成**编造引文**。
    //   现象②：模型把引文加粗 ⇒ `「**来人…！**」`，而 probe 里没有 `**`。
    //   两者都是**呈现层装饰**，不是内容改写。
    //   性质 = 判据缺陷（比较维度选错），不是模型幻觉 ⇒ 不修则
    //     每次都在测我的措辞偏好（反向假 FAIL，§4-177 第 1 条）。
    //   正对照三项：换引号层级 → 放行；加 Markdown 粗 → 放行；
    //     换一个字 → 仍判红 ⇒ 证明归一化只动形态、不动内容。
    test('呈现形态归一：仅换引号层级/Markdown 粗必须放行，换一字仍判红', () {
      final a = _cases[0];
      // 取 probe 里真实存在的嵌套引号原句（逐字来自 a.probe）
      final real = '孙舵主当场翻了脸，一拍桌子站起来：「来人，把这小子给我沉到江里去！」';
      expect(a.probe.contains(real), isTrue, reason: '正样本必须真的在 probe 内');

      // ① 形态①：引号层级不同（『』↔「」）、内容逐字一致 ⇒ 必须放行
      final reshaped = real.replaceAll('「', '『').replaceAll('」', '』');
      expect(reshaped, isNot(equals(real)), reason: '形态确实变了，否则本条是空跑');
      expect(
        _judge('原文中的这句：$reshaped', a).fakeQuotes,
        isEmpty,
        reason: '仅引号层级不同不得判幻觉',
      );
      expect(
        _normalizeQuotes(reshaped),
        _normalizeQuotes(real),
        reason: '归一化后应逐字相等',
      );

      // ② 形态②：Markdown 加粗包装（智谱实测 A 票1 原样：`「**来人…！**」`）
      final bolded = real.replaceAll('「', '「**').replaceAll('」', '**」');
      expect(
        _judge('原文中的这句：$bolded', a).fakeQuotes,
        isEmpty,
        reason: '仅 Markdown 加粗装饰不得判幻觉',
      );

      // ③ 内容真的换了一个字 ⇒ 必须判红（证明归一化没把判据放松成装饰）
      final tampered = real.replaceFirst('沉到江里去', '沉到江底去');
      expect(
        _judge('原文中的这句：$tampered', a).fakeQuotes,
        isNotEmpty,
        reason: '内容被改写仍必须判红 —— 否则判据②已成装饰',
      );
    });

    // ★★ 护栏：facet 必须是「**概念**侧面」，不得是 A 样本的**词汇**。
    //   这条防的是 2026-10-05 实测踩中的假绿：facet 当时用的是 A 的具体
    //   用词（`嘟囔/老泥鳅/拍/翻脸/犯不上`），而真实模型在 B 样本上改用
    //   同义表达（`收起赌据 / 随手扔了筹码 / 工具人`）⇒ `facetB` 恒 false
    //   ⇒ `isHit` 恒 false ⇒ 单变量对照 `rc=0`，**而 B 三票原文全部
    //   明确写着「P029」「工具化」**。外观与「真改善」完全一致。
    //   判法：用一段**刻意避开 A 全部具体用词、只用概念词**的 B 症状复述，
    //   它必须被判为 isHit —— 否则说明 facet 仍绑在 A 的词汇上。
    test('facet 是概念侧面而非 A 的词汇：同义表达也必须命中 isHit', () {
      final b = _cases[1];
      // 这段刻意不含 A 的具体用词（无「嘟囔/老泥鳅/拍桌/翻脸/犯不上」），
      // 只用 P029 定义层面的概念词 —— 真实模型在 B 上就是这个说法。
      const synonymous =
          '这段的反派被工具化了：明明手握赌据这张牌、'
          '堂兄又在衙门当差，他却放弃勒索改用情绪化指责，'
          '正是为了剧情需要让他赢一次，属降智反派。';
      for (final w in ['嘟囔', '老泥鳅', '拍桌', '翻脸', '犯不上']) {
        expect(synonymous.contains(w), isFalse, reason: '正样本不应含A 用词「$w」');
      }
      final v = _judge(synonymous, b);
      expect(
        v.facetA && v.facetB,
        isTrue,
        reason: '概念级同义表达必须命中两侧 facet，实得 ${v.detail}',
      );
      // 反向：facet 仍绑在 A 词汇上时这条会红，而它**在 live 组之前**就会红
      // ⇒ 不再依赖真实网络与额度就能拦住这类假绿。
    });

    // ⚠️ 本条随判据②语义更新重写（初版断言「凡成对引号都抽出」，那是旧语义）。
    //   新语义 = 只抽「声称引自原文」的引号，故逐条分开验：
    //   带引述标记 → 抽；仅术语/强调 → 不抽；形态过滤规则不变。
    test('引文抽取：只抽声称引原文者 + 形态过滤规则', () {
      expect(_extractQuotes('原文里的这句：「老泥鳅」，他听了就翻脸'), [
        '老泥鳅',
      ], reason: '带引述标记应抽出');
      expect(_extractQuotes('问题在这句：\n> 「老泥鳅」'), [
        '老泥鳅',
      ], reason: '引用块内应抽出（模型常不加引述标记）');
      expect(
        _extractQuotes('他嘟囔了一句「老泥鳅」'),
        isEmpty,
        reason: '无引述标记、无引用块 ⇒ 术语/强调用法，不纳入判据②',
      );
      expect(_extractQuotes('他说"老泥鳅"'), isEmpty, reason: '半角引号不纳入');
      expect(_extractQuotes('原文中的这句：「好」'), isEmpty, reason: '1 字不入抽取');
      expect(_extractQuotes('没有引号的输出'), isEmpty);
    });
  });

  // ── live 组准备（仅在**任一厂商**有 key 时恢复真实网络 + mock 平台通道）──
  //
  // ⚠️ secure storage 的 mock 是**全局单例键名**（`yuesheng_api_key` 等），
  //   故每次调用现场改写为当前厂商的值 —— LlmClient 每次都从 provider 现取，
  //   而厂商客户端由 [callWithBudget] 现场构造，故此写法生效。
  //   （若将来改成启动时读一次，此写法会退化为「只认第一个厂商」——
  //   改Provider 时务必同步这里。）
  bool anyKey() =>
      _providers.any((p) => Platform.environment.containsKey(p.envKey));

  setUpAll(() {
    if (!anyKey()) return;
    HttpOverrides.global = null; // flutter_test 默认把 HttpClient 换成「永远 400」的 mock
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
    final storage = <String, String>{};
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          return storage[args['key']];
        case 'write':
          storage[args['key'] as String] = args['value'] as String;
          return true;
        case 'delete':
          storage.remove(args['key']);
          return true;
      }
      return null;
    });
  });

  tearDownAll(() {
    if (!anyKey()) return;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, null);
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, null);
  });

  // ── live 组（逐厂商；每厂商独立费用护栏与采样表）──
  //
  // 跨厂商共享登记簿：厂商名 → 该厂商 A/B 的采样结果。
  // 用于末尾的「双厂商都跑过」断言 —— 局部 [sampled] 在循环外不可见。
  final Map<String, Map<String, List<_Verdict>>> sampledByLabel =
      <String, Map<String, List<_Verdict>>>{};

  for (final prov in _providers) {
    final bool hasKey = Platform.environment.containsKey(prov.envKey);

    // 该厂商的真实调用计数（费用护栏）。每次真实 HTTP 前自增；达上限即 fail。
    // ★ 必须**逐厂商独立**：共用一个计数器会让先跑的厂商吃掉后跑的预算。
    var realCalls = 0;

    Future<ChatCompletionResult> callWithBudget(
      LlmClient client,
      List<ChatMessage> messages,
    ) async {
      Object? lastErr;
      // ★ 退避窗口 5s/15s/30s（实测服务方容量抖动；照抄别处的 2s/4s 会全数失败）。
      const backoff = [5, 15, 30];
      for (var attempt = 1; attempt <= backoff.length; attempt++) {
        if (realCalls >= _kMaxRealCallsPerProvider) {
          fail(
            '[$prov.label] 费用预算用尽：已 $realCalls 次真实调用 ≥ 上限 '
            '$_kMaxRealCallsPerProvider，停止。',
          );
        }
        try {
          realCalls++;
          return await client.chatCompletionWithMeta(
            messages,
            maxTokens: 2000,
            extraBody: const {
              'thinking': {'type': 'disabled'},
            },
          );
        } catch (e) {
          lastErr = e;
          final msg = e.toString();
          // 鉴权 / 内容类错误立即 fail；其余（含 429/1305/500 容量抖动）退避重试。
          final fatal = RegExp(
            r'401|403|unauthorized|invalid.*key|鉴权|content.?filter|content_filter',
            caseSensitive: false,
          ).hasMatch(msg);
          if (fatal) {
            print('[$prov.label][护栏] 鉴权/内容类错误，立即停止: $msg');
            rethrow;
          }
          print(
            '[$prov.label}][护栏] 第 $attempt 次瞬时错误，'
            '退避 ${backoff[attempt - 1]}s: ${msg.split('\n').first}',
          );
          if (attempt < backoff.length) {
            await Future<void>.delayed(Duration(seconds: backoff[attempt - 1]));
          }
        }
      }
      throw StateError('[$prov.label] 真实 LLM 调用重试已耗尽（瞬时错误 3 次均失败）: $lastErr');
    }

    // 采样留存：供「单变量对照」复用。
    //
    // ★ 不为对照单独发一轮调用（实测 429 会把独立那一轮全打掉 ⇒ 对照结论
    //   整段丢失，而 A/B 的票白烧）。对照直接读这 3 票的结果 ⇒
    //   对照结论与采样结论同生共死，不会各说各话。
    final Map<String, List<_Verdict>> sampled = <String, List<_Verdict>>{};

    group('${prov.label}诊断·真实 LLM（${prov.model}，@live,external）', () {
      for (final c in _cases) {
        test(
          '[${c.id}] ${c.name}：3 票 ≥2 票行为级通过',
          () async {
            if (!hasKey) {
              markTestSkipped('未设置 ${prov.envKey}，跳过 ${prov.label} 真实链路');
              return;
            }
            final key = Platform.environment[prov.envKey]!;
            final cfg = LlmConfigValues(
              apiKey: key,
              baseUrl: prov.baseUrl,
              model: prov.model,
            );
            final monitor = LlmUsageMonitor();
            final client = LlmClient(
              null,
              null,
              () async => cfg,
              null,
              LlmConcurrencyGate(),
              monitor.sink,
            );

            var hits = 0;
            final vds = <_Verdict>[];
            for (var v = 1; v <= 3; v++) {
              final msgs = _buildMessages(c);
              final res = await callWithBudget(client, msgs);
              final vd = _judge(res.content, c);
              vds.add(vd);
              final ok = c.id == 'A' ? vd.isHit : vd.isClean;
              hits += ok ? 1 : 0;
              print(
                '[${prov.label}][${c.id}][票$v] ok=$ok '
                'finish=${res.finishReason} len=${res.content.length} '
                '${vd.detail}',
              );
              print('  输出: ${res.content.trim()}');
            }
            sampled[c.id] = vds;
            sampledByLabel[prov.label] = sampled;
            expect(
              hits >= 2,
              isTrue,
              reason: '[${prov.label}] ${c.id} 3 票需 ≥2 票行为级通过，实际 $hits/3',
            );

            print('[${prov.label}][${c.id}] 累计用量: ${monitor.totals}');
          },
          tags: const ['live', 'external'],
          timeout: const Timeout(Duration(seconds: 300)),
        );
      }

      test('单变量对照：A 多数票报出症状 / B 多数票不报（防无差别套模板）', () {
        if (!hasKey) {
          markTestSkipped('未设置 ${prov.envKey}，跳过 ${prov.label} 真实链路');
          return;
        }
        final a = sampled['A'];
        final b = sampled['B'];
        // ⚠️ 上游因服务方限流（429）失败时，本条不得报「A 采样结果缺失」——
        //   那会把真实原因（限流）掩盖成一条看似代码有 bug 的失败。
        if (a == null || b == null) {
          markTestSkipped(
            '[${prov.label}] A/B 采样未完成（上游 live 测试失败，常见于'
            '服务方限流），本条对照无法判定 —— 不把上游失败伪装成本条失败',
          );
          return;
        }

        // A：≥2/3 票报出该症候且两面俱到。
        final aHits = a.where((v) => v.isHit).length;
        expect(
          aHits >= 2,
          isTrue,
          reason:
              '[${prov.label}] 样本 A（有症状）须 ≥2 票报出该症候'
              '且两面俱到，实得 $aHits/3',
        );
        // B：≤1/3 票报出该症候两面 —— 报出即无差别套模板。
        final bOvers = b.where((v) => v.facetA && v.facetB).length;
        print(
          '[${prov.label}][单变量] A 报出 $aHits/3 票；'
          'B 报出 $bOvers/3 票',
        );
        expect(
          bOvers <= 1,
          isTrue,
          reason:
              '[${prov.label}] 样本 B（干净）多数票报出了该症候的两面 '
              '⇒ 模型在无差别套模板，实得 $bOvers/3',
        );
      }, tags: const ['live', 'external']);

      test(
        '护栏收尾：真实调用计数留痕（≤ $_kMaxRealCallsPerProvider）',
        () async {
          if (!hasKey) {
            markTestSkipped('未设置 ${prov.envKey}，跳过 ${prov.label} 真实链路');
            return;
          }
          print(
            '[${prov.label}][护栏] 本厂商真实调用（测试侧计数）: '
            '$realCalls / 上限 $_kMaxRealCallsPerProvider',
          );
          expect(realCalls, lessThanOrEqualTo(_kMaxRealCallsPerProvider));
        },
        tags: const ['live', 'external'],
      );
    });
  }

  // ── 跨厂商对照：把两厂商的采样结论并列，供人工/报告读取 ──
  //
  // ★ 这条**只做断言形态的呈现，不做跨厂商判定**：
  //   两家结论可能不一致（一家报偏误、一家不报），而「谁更对」需要人判
  //   （涉及症候判定边界是否偏宽这一未解问题）⇒ 强行自动化会把
  //   「边界争议」伪装成「测试结论」。
  //   故本条只断言一件可判的事：**两个厂商都跑过**（各厂商采样非空），
  //   否则「双厂商对照」其实退化成单厂商 —— 而那正是本条要防的。
  test('跨厂商对照：至少两个厂商均已采样（否则对照名不副实）', () {
    final done = _providers
        .where((p) => Platform.environment.containsKey(p.envKey))
        .where((p) => sampledByLabel[p.label] != null)
        .map((p) => p.label)
        .toList();
    print('[跨厂商] 已完成采样的厂商: $done');
    // ⚠️ 只配了**一个**厂商 key 时必须 skip 而不是 FAIL ——
    //   否则「双厂商对照」这一条会在单厂商环境下恒红，而它本意是
    //   「防止我把单厂商结果当双厂商结论读」，不是「要求必须配齐两家」。
    if (done.length < 2) {
      final only = done.isEmpty ? '（无）' : done.join('/');
      markTestSkipped(
        '仅「$only」完成采样（需两家 key 才构成对照）⇒ 本条不判定；'
        '⚠️ 此时读结论须注意：只有这一家的数据，**不能**当作双厂商对照',
      );
      return;
    }
    expect(
      done.length,
      greaterThanOrEqualTo(2),
      reason: '双厂商对照需两家都跑过；实际仅 $done',
    );
  }, tags: const ['live', 'external']);
}
