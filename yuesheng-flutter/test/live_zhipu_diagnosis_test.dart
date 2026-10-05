// ─────────────────────────────────────────────────────────────
// 智谱免费档（glm-4.7-flash）· 真实文段诊断链路验证
//
// 目标（用户 2026-10-05 裁定）：回答「免费模型能不能真给出可用诊断」，
//   而非「免费模型能不能调通」。管道通不通由前置体检单独负责。
//
// 设计要点 —— **单变量对照**：
//   样本 A（有症状）与样本 B（干净文本）**共用同一个 focusSyndromeId、
//   同一知识库、同一 prompt、同一个模型**，唯一差异是投喂的文本本身。
//   ⇒ 若 A 报出症状而 B 不报，才能归因到「模型真在读文本」；
//     若两者输出形态一致，则说明它在复读知识库 / 无差别套模板，本批判失败。
//
// 注入点（照生产 message_injector._injectTrainingKnowledge:1956-1963）：
//   preamble + getTrainingContent([id]) + getTrainingFewShot([id]) + user 文本
//
// 双组结构（仿 live_fewshot_replay_test）：
//   1) 常驻自检组（无 tag，门禁全量必跑）：_ScriptedFakeLlmClient 喂
//      「行为级贴合」与「词面复读 / 编造引文」两类脚本输出，跑与 live 组
//      完全相同的判定器，证明判真/剔假自洽、无 key 可跑。
//   2) live 组（per-test tags: ['live','external']）：真实智谱 glm-4.7-flash。
//      无 ZHIPU_API_KEY 时每个 test 内 markTestSkipped，不破门禁全量。
//
// 判据（行为级，非词面）：
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
// 费用护栏：2 样本 × 3 票 = 6 次计划内调用；测试侧硬上限 16
//   （含瞬时错误退避重试，重试同样计数 —— 服务方容量抖动会消耗预算）。
//   对照断言**复用**这 6 次的采样结果，不额外发调用（见 live 组 sampled）。
//
// ★ 服务方容量适配（2026-10-05 实测）：首调返回 HTTP 429 /
//   code 1305「该模型当前访问量过大」，退避后出现 code 500，第 3 次才 200。
//   ⇒ 智谱侧 429/1305/500 一律按**瞬时**处理（鉴权失败才是 401/403），
//     退避窗口放宽到 5s/15s/30s（DeepSeek 版是 2s/4s，照抄会全数失败）。
//
// 运行真实回放（key 只经环境变量，严禁写入源码）：
//   $env:ZHIPU_API_KEY="xxx.yyy"
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

const String _kBaseUrl = 'https://open.bigmodel.cn/api/paas/v4';
const String _kModel = 'glm-4.7-flash';

/// A / B 共用的 focusSyndromeId —— 单变量对照的前提：知识库完全相同。
const String _kFocusSyndromeId = 'P029';

/// 真实调用硬上限（含退避重试的消耗）。
/// 计划内 6 次（2 样本 × 3 票；对照复用同批票，不额外发调用）。
/// 上限 16 是为退避留的余量 —— 实测服务方抖动常吃掉 2–3 次重试。
const int _kMaxRealCalls = 16;

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
    facetA: ['捏着', '手里', '当差', '赌据', '三千两', '慢慢', '拿捏'],
    facetB: ['一句', '嘟囔', '老泥鳅', '拍', '沉', '翻脸', '亲自', '犯不上'],
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
    // ★ facet 是「**症候**的概念侧面」，与样本无关 ⇒ B 必须带与 A **完全相同**
    //   的 facet。少了这一段，B 的 `facetA && facetB` 会因空列表恒为 false，
    //   使「单变量对照」那条 live 断言**永不可能失败**（假绿）。
    //   语义：B 若也报出「捏着优势 + 被一句轻慢激怒」两面 ⇒ 属无差别套模板。
    facetA: ['捏着', '手里', '当差', '赌据', '三千两', '慢慢', '拿捏'],
    facetB: ['一句', '嘟囔', '老泥鳅', '拍', '沉', '翻脸', '亲自', '犯不上'],
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
  final fake = _extractQuotes(
    output,
  ).where((q) => !c.probe.contains(q)).toList();
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

  final bool hasKey = Platform.environment.containsKey('ZHIPU_API_KEY');

  // ── 常驻自检组（无 tag，门禁全量必跑，无 key 可跑）──
  group('智谱诊断·常驻自检（FakeLlmClient：判定器能红能绿）', () {
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

  // ── live 组准备（仅在有 key 时恢复真实网络 + mock 平台通道）──
  setUpAll(() {
    if (!hasKey) return;
    HttpOverrides.global = null; // flutter_test 默认把 HttpClient 换成「永远 400」的 mock
    final key = Platform.environment['ZHIPU_API_KEY']!;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
    final storage = <String, String>{
      'yuesheng_api_key': key,
      'yuesheng_api_base_url': _kBaseUrl,
      'yuesheng_api_model': _kModel,
    };
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
    if (!hasKey) return;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, null);
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, null);
  });

  // 真实调用计数（费用护栏）。每次真实 HTTP 前自增；达上限即 fail。
  var realCalls = 0;

  Future<ChatCompletionResult> callWithBudget(
    LlmClient client,
    List<ChatMessage> messages,
  ) async {
    Object? lastErr;
    // ★ 退避窗口 5s/15s/30s（对齐实测的服务方容量抖动；DeepSeek 版 2s/4s 会全数失败）。
    const backoff = [5, 15, 30];
    for (var attempt = 1; attempt <= backoff.length; attempt++) {
      if (realCalls >= _kMaxRealCalls) {
        fail('费用预算用尽：已 $realCalls 次真实调用 ≥ 上限 $_kMaxRealCalls，停止。');
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
        // 鉴权 / 内容类错误立即 fail；其余（含 429/1305/500 服务方容量抖动）退避重试。
        final fatal = RegExp(
          r'401|403|unauthorized|invalid.*key|鉴权|content.?filter|content_filter',
          caseSensitive: false,
        ).hasMatch(msg);
        if (fatal) {
          print('[护栏] 鉴权/内容类错误，立即停止: $msg');
          rethrow;
        }
        print(
          '[护栏] 第 $attempt 次瞬时错误，退避 ${backoff[attempt - 1]}s: '
          '${msg.split('\n').first}',
        );
        if (attempt < backoff.length) {
          await Future<void>.delayed(Duration(seconds: backoff[attempt - 1]));
        }
      }
    }
    throw StateError('真实 LLM 调用重试已耗尽（瞬时错误 3 次均失败）: $lastErr');
  }

  // 采样留存：供「单变量对照」复用。
  //
  // ★ 不再为对照单独发一轮调用（实测 429 会把独立那一轮全打掉 ⇒ 对照结论
  //   整段丢失，而 A/B 的票白烧）。改为对照直接读上面 3 票的结果 ——
  //   对照结论与采样结论从此同生共死，不会各说各话。
  final Map<String, List<_Verdict>> sampled = <String, List<_Verdict>>{};

  // ── live 组（per-test tags，无 key 自动 skip）──
  group('智谱诊断·真实 LLM（glm-4.7-flash，@live,external）', () {
    for (final c in _cases) {
      test(
        '[${c.id}] ${c.name}：3 票 ≥2 票行为级通过',
        () async {
          if (!hasKey) {
            markTestSkipped('未设置 ZHIPU_API_KEY，跳过真实链路');
            return;
          }
          final key = Platform.environment['ZHIPU_API_KEY']!;
          final cfg = LlmConfigValues(
            apiKey: key,
            baseUrl: _kBaseUrl,
            model: _kModel,
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
              '[${c.id}][票$v] ok=$ok finish=${res.finishReason} '
              'len=${res.content.length} ${vd.detail}',
            );
            print('  输出: ${res.content.trim()}');
          }
          sampled[c.id] = vds;
          expect(
            hits >= 2,
            isTrue,
            reason: '${c.id} 3 票需 ≥2 票行为级通过，实际 $hits/3',
          );

          print('[${c.id}] 累计用量: ${monitor.totals}');
        },
        tags: const ['live', 'external'],
        timeout: const Timeout(Duration(seconds: 300)),
      );
    }

    test('单变量对照：A 多数票报出症状 / B 多数票不报（防无差别套模板）', () {
      if (!hasKey) {
        markTestSkipped('未设置 ZHIPU_API_KEY，跳过真实链路');
        return;
      }
      final a = sampled['A'];
      final b = sampled['B'];
      // ⚠️ 上游因服务方限流（429）失败时，本条不得报「A 采样结果缺失」——
      //   那会把真实原因（限流）掩盖成一条看似代码有 bug 的失败。
      //   对照的输入缺失 ⇒ 跳过本条，让上游错误自己说话。
      if (a == null || b == null) {
        markTestSkipped(
          'A/B 采样未完成（上游 live 测试失败，常见于服务方限流），'
          '本条对照无法判定 —— 不把上游失败伪装成本条失败',
        );
        return;
      }

      // A：≥2/3 票报出该症候且两面俱到。
      final aHits = a.where((v) => v.isHit).length;
      expect(
        aHits >= 2,
        isTrue,
        reason: '样本 A（有症状）须 ≥2 票报出该症候且两面俱到，实得 $aHits/3',
      );
      // B：≤1/3 票报出该症候两面 —— 报出即无差别套模板。
      final bOvers = b.where((v) => v.facetA && v.facetB).length;
      print('[单变量] A 报出 $aHits/3 票；B 报出 $bOvers/3 票');
      expect(
        bOvers <= 1,
        isTrue,
        reason:
            '样本 B（干净）多数票报出了该症候的两面 ⇒ 模型在无差别套'
            '模板，实得 $bOvers/3',
      );
    }, tags: const ['live', 'external']);

    test('护栏收尾：真实调用计数留痕（≤ $_kMaxRealCalls）', () async {
      if (!hasKey) {
        markTestSkipped('未设置 ZHIPU_API_KEY，跳过真实链路');
        return;
      }
      print('[护栏] 本批真实调用（测试侧计数）: $realCalls / 上限 $_kMaxRealCalls');
      expect(realCalls, lessThanOrEqualTo(_kMaxRealCalls));
    }, tags: const ['live', 'external']);
  });
}
