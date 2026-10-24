// ─────────────────────────────────────────────────────────────
// P029 降智反派 · 负样本「场景外壳改写」集（D6.8 · §4-189 判据②）
//
// ★ 为什么有这个文件（D6.6 实测触发）：
//   D6.6 在 A1 票2 命中一句逐字声明——模型说这段「恰好是我教学素材库里
//   一个标准的"正常写法"示例」。换言之，现有 `p029_negative_sample_test.dart`
//   的负样本与注入知识库（KB）原文**同源**：模型测的是「认得这段」，
//   不是「按判据独立判断这段」。两臂（stripped / production）都有此瑕疵，
//   换装置不可消除 ⇒ 削弱整套样本集效度。
//
// §4-189 判据② 的处置 = **同判据结构、不同人物/题材/措辞（场景外壳改写）**：
//   每条新样本保持原样本要测的**结构性属性**（见各 case `structureNote`），
//   但题材从「古代官场/医馆/世家/教派/商号」整体换到现代
//   （体育 / 商战 / 销售竞标 / 资本并购 / 科研医学 / 地产董事会 / 大学医院 / 电商直播），
//   且**不逐字复用 KB few-shot 原文示例**（墨大夫夺舍 / 一城之主单挑送人头 /
//   七反派打脸送人头）。
//
// 判读口径真源：`outputs/gate/d66_power_review.md` §一（唯一口径）：
//   · 模型明确否认 P029（「不构成 / 我不报 / 账本在、症结在呈现」）⇒ 不报；
//   · 把「对手被工具化 / 无账本 / 剧情驱动 / 降智」当症结 ⇒ 报。
//
// 本文件性质：**纯测试层夹具 + 常驻自检**（R-010：零 lib/ 改动）。
//   · 常驻组（无 key 恒跑）：四面注入在场 + 锚点在场 + 判定器两向有牙齿
//     （hitScript 不误报 / missScript 必报）+ **换壳纪律静态断言**（probe 不得
//     含 KB 原文示例与原样本外壳指纹词）+ 覆盖完整性。
//   · live 组（`tags: ['live','external']`）：D6.8 本批**零 API key、不跑 live**，
//     仅留标签占位，供后续批在有 key 时复跑。
//
// 运行（本批）：
//   flutter test test/services/p029_negative_sample_reshell_test.dart
//     （不带 --tags live ⇒ live 组自动 skip，常驻组恒跑 rc=0）
//
// ⚠️ 不得修改/删除现有 `p029_negative_sample_test.dart`（本文件与之并存）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/reasoning_tier.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_usage_monitor.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';
import 'package:writingcoach/types/teaching_types.dart';

const String _kFocusId = 'P029';

// ── D6.9 臂 B：live 复跑装配（与 `p029_negative_sample_test.dart` 逐字同源）──
//   唯一可改动文件 = 本 reshell 文件；装置（preamble/知识四块/用户消息/档位 off/
//   非流式/有效票守卫/三态口径注释/判定器打印）与原文件逐字一致 ⇒ 同装置可比。

const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 教练前置（与生产 message_injector 等价；与原文件逐字一致）。
const String _kPreamble =
    '你是一名写作教练。学员给你看一段他新写的小说文字，请你做诊断，'
    '不要替学员改写句子、不要替他做决定。'
    '请指出这段文字里最核心的一个写作问题：必须点到具体位置（引用原文里的词或句），'
    '并说明这个问题为什么是问题、它伤害了读者的什么阅读体验。一次只聚焦一个最主要的点。';

/// 装配臂（与原文件 `_Arm` 逐字一致）。
enum _Arm {
  /// 现状：自造 `_kPreamble` + 知识四块。
  stripped,

  /// 对齐生产：`buildSystemPromptV2` 的完整 system prompt。
  production,
}

/// 生产等效诊断上下文（与原文件逐字一致）。
const SkillLoadContext _kProductionCtx = SkillLoadContext(
  phase: TeachingPhase.p2PracticeLoop,
  attitude: AttitudeLevel.yuesheng,
  subphase: TeachingSubphase.diagnosis,
);

// ── 判定器（与 `p029_negative_sample_test.dart` 逐字同源，仅作常驻自检辅助）──
//   ⚠️ 定位不变：**辅助筛查器，不是判真器**。正式读数以人工逐票复核为准。
//   这里只用来保证「新写的 hitScript/missScript 在判定器两向都有牙齿」，
//   避免交付一份「恒绿、无鉴别力」的夹具。

/// P029 概念侧面：**只收「问题信号」词，不收中性词**（与原文件同纪律）。
const List<String> _kFacetToolization = [
  '工具化',
  '没有利益动机',
  '无利益动机',
  '没有利益支撑',
  '无利益支撑',
  '为坏而坏',
  '智商不在线',
  '降智反派',
  '工具人',
  '送人头',
  '剧情需要他',
  '当剧情需要',
];

const List<String> _kNegationMarkers = [
  '不是',
  '并非',
  '不构成',
  '不属于',
  '谈不上',
  '不叫',
  '而非',
  '不报',
  '不判',
  '不认定',
  '不该报',
  '不用报',
  '未报',
  '不算',
  '不作为',
  '非降智',
];

const int _kNegationWindow = 16;

bool _hitsFacet(String output) {
  for (final facet in _kFacetToolization) {
    var idx = output.indexOf(facet);
    while (idx != -1) {
      final left = idx <= _kNegationWindow
          ? output.substring(0, idx)
          : output.substring(idx - _kNegationWindow, idx);
      final negated = _kNegationMarkers.any(left.contains);
      if (!negated) return true;
      idx = output.indexOf(facet, idx + 1);
    }
  }
  return false;
}

/// 组装消息（与原文件 `_buildMessages` 逐字同源；仅样本类型换为 `_ReshellCase`）。
///
/// [arm] 只决定第一段 system 用哪一份：stripped = 自造 `_kPreamble`；
/// production = `buildSystemPromptV2(_kProductionCtx).systemPrompt`。
/// 知识四块、档位（off）、调用形态（非流式）、用户消息两臂逐字相同。
List<ChatMessage> _buildMessages(_ReshellCase c, {_Arm arm = _Arm.stripped}) {
  final msgs = <ChatMessage>[
    ChatMessage(
      role: 'system',
      content: arm == _Arm.production
          ? buildSystemPromptV2(_kProductionCtx).systemPrompt
          : _kPreamble,
    ),
  ];
  final knowledge = getTrainingContent([_kFocusId]);
  if (knowledge.isNotEmpty) {
    msgs.add(ChatMessage(role: 'system', content: knowledge));
  }
  final few = getTrainingFewShot([_kFocusId]);
  if (few.isNotEmpty) {
    msgs.add(ChatMessage(role: 'system', content: few));
  }
  final l3 = getSyndromeContent([_kFocusId]);
  if (l3.isNotEmpty) {
    msgs.add(ChatMessage(role: 'system', content: l3));
  }
  final tech = getTechniquesBySyndrome([_kFocusId]);
  if (tech.isNotEmpty) {
    msgs.add(ChatMessage(role: 'system', content: tech));
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

/// 单条换壳负样本。
class _ReshellCase {
  /// 与原样本对齐的 id（N- 前缀 = reshell）。
  final String id;

  /// 原样本 id（同源对照）。
  final String sourceId;
  final String band;
  final String name;

  /// 投喂文本（新外壳）。
  final String probe;

  /// 合法输出：教练正确地指出别的真问题（或明确不判 P029）⇒ 不应命中。
  final String hitScript;

  /// 误报路径：把该段判成「降智反派 / 对手被工具化」⇒ 应命中。
  final String missScript;

  /// 豁免所依据的判据原文片段（钉「断言真的在读判据」）。
  final List<String> anchors;

  /// 本样本要测的**结构性属性**（与 sourceId 同判据结构）。
  final String structureNote;

  const _ReshellCase({
    required this.id,
    required this.sourceId,
    required this.band,
    required this.name,
    required this.probe,
    required this.hitScript,
    required this.missScript,
    required this.anchors,
    required this.structureNote,
  });
}

final List<_ReshellCase> _cases = [
  // ─── 带① 执念/偏执驱动（动机极端但不失内在逻辑）────────────────
  _ReshellCase(
    id: 'N-A1',
    sourceId: 'A1',
    band: '执念驱动',
    name: '老门神亲手守最后一个点球（补二十年前那一脚）',
    probe:
        '点球大战前，本方教练攥着替补名单，劝老门神周正下去休息——他本赛季已经丢了十二个球，'
        '替补门将的扑点率比他高出近三成。周正只是摘下手套，又戴回去：'
        '「二十年前，是我站在门线上，让那一脚从我们队手里漏走了冠军。'
        '我师傅临走前攥着我的手说，这一天你得自己站回来。我等了二十年——'
        '这一脚，换谁来守，我这二十年都不算数。」',
    hitScript:
        '这段写的是执念，不是降智。周正的动机极端（补二十年前那一脚）但内在逻辑完整——'
        '他不亲自站上去，这二十年就没个了结，硬要交给替补反而失真。'
        '真要说问题，是这场点球大战的分量还没在前面垫够。',
    missScript:
        '这段存在降智反派。周正明明状态糟糕、放着替补门将不用，非要亲自上场，'
        '反派被工具化，只是剧情需要他出来守门。',
    anchors: ['执念', '偏执'],
    structureNote:
        '对手方明明有更省力选择（换数据更好的替补），却偏要亲自守最后点球；'
        '表面像「放着资源不用、无脑死磕」，实质是二十年执念的内在账本。'
        '对应例外①：动机极端但不失内在逻辑，不得报 P029。',
  ),

  // ─── 带③「愚蠢」其实是局（表面降智、暗中算计）────────────────
  _ReshellCase(
    id: 'N-C1',
    sourceId: 'C1',
    band: '愚蠢其实是局',
    name: '老财务那一扑是演给走廊内鬼看的戏',
    probe:
        '并购谈判现场，对方独董摔门走人，老财务老魏却突然扑上去拦，被保安一把按在地上。'
        '等谈判破裂、人都散了，老魏才从地上爬起来，对着走廊尽头那个一直没走的法务，'
        '轻轻把工牌翻了个面——他是董事长埋在对方公司八年的暗线，那一扑，是做给那个内鬼看的。',
    hitScript:
        '这段写的是假失态真布局：老魏那一下扑拦是设计给内鬼看的信号，翻工牌这个收尾很好——'
        '真算计不需要台词。可以打磨的是谈判破裂前的节奏再压一压。',
    missScript:
        '降智反派：老魏作为公司老财务，明知拦不住还扑上去被按在地上，'
        '反派被工具化，只是剧情需要他丢人。',
    anchors: ['愚蠢', '其实是局', '暗中算计'],
    structureNote:
        '表面「明知拦不住还扑上去被按倒」= 送人头/被工具化；收尾揭示这是演给走廊内鬼看的局，'
        '翻工牌=真算计不需要台词。对应例外③：表面降智、暗中算计。',
  ),
  _ReshellCase(
    id: 'N-C2',
    sourceId: 'C2',
    band: '愚蠢其实是局',
    name: '连丢三个大单是放出去的饵',
    probe:
        '这个季度，销售总监林峥连丢三个大单，总部发函追责，问他还想不想干。'
        '他一句不辩，只让助理把同一份亲笔签字的保密协议，分别寄给了那三个丢单的客户。'
        '一周后总部再召他回去——那三家客户在行业展会上，各自掏出了同一份带他签字的协议。'
        '林峥这才把三份协议的编号并到桌上：这三家各自背着董事会的季度降本指标，'
        '谁拿到这份「内部底价」，谁就能向董事会交差。他连丢三单，是故意放话让他们以为独得了底价——'
        '三家怕被同行抢先，抢着签了这份保密协议。三份一模一样的协议一撞，'
        '就等于他们亲笔认了背地里共用一套底价、联手压上游。他要的从来不是这三单，'
        '是把这三家串标的证据，钉死在自己手里。',
    hitScript:
        '这是诱敌的经典形态：连丢三单是主动送出去的饵，那份重复寄出的保密协议才是真信息。'
        '真正能写的是总部追责时他那句不辩的沉默——他在等一个必须由更高层来问出口的问题。',
    missScript: '降智反派：林峥连丢三个大单毫无章法、被追责也不辩解，没有利益动机，反派被工具化。',
    anchors: ['愚蠢', '其实是局', '暗中算计'],
    structureNote:
        '表面「连丢三单、被骂怯战也不辩」= 无章法/无动机；实则连丢=放饵，重复的保密协议=真信息，'
        '不申辩=在等一个必须由上位者来问的问题。对应例外③（诱敌形态）。',
  ),

  // ─── 带④ 利益账本到位的普通反派（非例外，仅易误报）──────────
  _ReshellCase(
    id: 'N-D1',
    sourceId: 'D1',
    band: '利益账本到位',
    name: '收购方一步步压账期断现金流逼人',
    probe:
        '收购方老板没拍桌子。听完那句「你做梦」，他放下咖啡，慢条斯理道：'
        '「直接买？太便宜你了。」他吩咐财务：「先把他们的账期从九十天压到现款现货，'
        '再去接触他们最大的供应商。三个月之内，我要他们的 CEO 自己走进我办公室。」',
    hitScript:
        '反派每一步都在算账：压账期是断他现金流，接触供应商是拿他命门，'
        '图的是那个被迫上门的收购价。放着筹码用足才让这场收购有分量。',
    missScript: '降智反派：收购方放着资金优势不用、不直接压价，非要绕弯子，对手被工具化，没有利益动机。',
    anchors: ['利益账本', '以下不判降智反派'],
    structureNote:
        '反派不直接撕脸，而是冷静一步步断对方活路（压账期=断现金流、接触供应商=拿命门），'
        '目的明确（逼对方自己上门谈）。对应例外④：每个动作落自己利益账本。',
  ),
  _ReshellCase(
    id: 'N-D2',
    sourceId: 'D2',
    band: '利益账本到位',
    name: '博导七年好全落在那组罕见基因上',
    probe:
        '博导沈砚组里有个学生，他格外上心了七年。别人看是大方：'
        '累人的家系采样活都派给这个学生，一作署名说让就让，'
        '还总替他挡掉转临床的机会。同行都说，这导师难得肯为学生铺路。'
        '只有他自己清楚：这个学生携带的那组罕见突变基因，'
        '是他攻了二十年那个病、够到终身教职的最后一块钥匙。'
        '那些让出去的一作、挡下来的转组，换回来的是学生每一年按时采的血样，'
        '和那张谁也查不到的家系样本独家授权——他这七年的好，从来都是明码标价的。',
    hitScript:
        '这类铺垫极干净：七年的好全有落点。真值得说的是最后那句「只有他自己清楚」——'
        '读者在揭底前需要一点更早的异样感，现在只有一个直接的悬念。',
    missScript:
        '降智反派：沈砚七年如一日地对学生好却别无所图，反派没有利益动机，'
        '只是剧情需要他当好人。',
    anchors: ['利益账本', '以下不判降智反派'],
    structureNote:
        '七年温柔/资源倾斜全有落点——学生的罕见基因=自己二十年课题+终身教职的唯一钥匙，'
        '账本具体可指认，藏在「只有他自己清楚」里。对应例外④（原 D2 与 KB 墨大夫示例同源，此条彻底换壳）。',
  ),
  _ReshellCase(
    id: 'N-D3',
    sourceId: 'D3',
    band: '利益账本到位',
    name: '众人投城东，董事长偏拍板城西',
    probe:
        '董事会上，城东那块地回报是城西的三倍，董事们几乎一边倒地要投城东。'
        '董事长却当场拍板：「投城西。」他自己手里囤的三个楼盘、押给银行的两笔贷款，'
        '全压在城西——城西这一片起不来，他这个董事长也就坐到头了。',
    hitScript:
        '利益动机写得实在：董事长自家三个楼盘、两笔贷款全押在城西，投城西就是保自己的账，'
        '不是被三倍回报说动的。这段可打磨的是「当场拍板」太快——读者还没起疑，答案就摊开了。',
    missScript: '降智反派：董事长放着三倍回报的城东不投、偏要投城西，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '以下不判降智反派'],
    structureNote:
        '众人主张城东（大利益），他当场定城西——自己三楼盘+两笔贷款全押城西，'
        '投城西=保自己的账，账本在文本内可指认；易误读为「放着大利益不取」。对应例外④（账本摆明面形态）。',
  ),
  _ReshellCase(
    id: 'N-D4',
    sourceId: 'D4',
    band: '利益账本到位',
    name: '院长只停职不除名，保的是三城捐赠实验室',
    probe:
        '附属医院里，主任的亲信医生出了医疗事故，院长只让他停职半年、不予除名。全院都骂院长护短。'
        '只有院办知道：那个医生手里握着一个能拉来三城校友捐赠的重点实验室——'
        '这事一旦公开除名，捐赠撤了、评审委员会联名质询，他这个院长才真坐不住。',
    hitScript:
        '表层是护短，内核是保那间拉来三城捐赠的实验室，动机链一环扣一环。'
        '真问题在视角：这段把底牌一次摊完，读者没有参与感——'
        '建议让读者先从「只停职不除名」的蹊跷里自己拼出来。',
    missScript: '降智反派：院长不护医院规矩、只护出事故的亲信，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '以下不判降智反派'],
    structureNote:
        '表层=护短，内核=保那间拉三城捐赠的实验室（捐赠+评审联名，账本具体可指认、半隐藏），'
        '易误报为「不护规矩只护人」。对应例外④。',
  ),
  _ReshellCase(
    id: 'N-D5',
    sourceId: 'D5',
    band: '利益账本到位',
    name: '供应链老板退坑位费，主播囤货卡七个直播间',
    probe:
        '最大的主播一次吃下三成坑位，供应链老板却笑着退了坑位费，还多寄了两车样品。运营不解。'
        '老板说：「他要是垮了，这个类目就剩我一家供得起他。」'
        '那头主播挂了电话就跟团队交底：三成货照单全收，但不是自己播——'
        '下游七个小直播间都在抢这个爆品，他把货囤进仓、掐住现货，'
        '等大促前谁断货谁就得求他分货，到那时分货价由他来开。'
        '退坑位费？那是老板在赌他撑不住，他偏要借这一步，让两边都替自己抬轿。',
    hitScript:
        '老板清醒，主播也不糊涂——退了坑位费这个类目只剩他供得起，'
        '而主播囤货卡的是下游七个直播间，两个人都在算自己的账。'
        '可以建议的是运营那句不解，把它写活一点，好让读者的疑心有个落点。',
    missScript: '降智反派：老板放着大单子不做、主动退坑位费，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '以下不判降智反派'],
    structureNote:
        '两个角色都在算自己的账：退坑位费=垄断该类目供货，主播囤货卡七个小直播间；'
        '对手侧（主播）也有账本。对应例外④（双方均有账本）。',
  ),
];

/// 换壳纪律指纹：probe **不得**命中下列任一指纹词。
///
/// 来源两类：
///   ① KB few-shot 原文示例（命中 ⇒ 测「识别」而非「判断」，正是本批要消除的同源）：
///     墨大夫/韩立/夺舍/元寿（KB ❌未命中示例）· 千军万马/送人头/恼羞成怒（KB ✅命中示例）；
///   ② 原负样本外壳（古代官场/医馆/世家/教派/商号）：祭田/印子钱/族老/掌教/
///     香火田/灯油钱/染坊/地契/黑旗/死士/碗沿/魔教/崖边/知府/师爷/布商/账房。
const List<String> _kReshellForbidden = [
  '墨大夫',
  '韩立',
  '夺舍',
  '元寿',
  '千军万马',
  '送人头',
  '恼羞成怒',
  '祭田',
  '印子钱',
  '族老',
  '掌教',
  '香火田',
  '灯油钱',
  '染坊',
  '地契',
  '黑旗',
  '死士',
  '碗沿',
  '魔教',
  '崖边',
  '知府',
  '师爷',
  '布商',
  '账房',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P029 换壳负样本 · 注入面与锚点在场（无 key，恒跑）', () {
    test('① 四面注入非空（训练内容 / few-shot / L3 手册 / 技法）', () {
      expect(getTrainingContent([_kFocusId]), isNotEmpty);
      expect(getTrainingFewShot([_kFocusId]), isNotEmpty);
      expect(getSyndromeContent([_kFocusId]), isNotEmpty);
      expect(getTechniquesBySyndrome([_kFocusId]), isNotEmpty);
    });

    test('② 每条换壳样本的锚点片段都能在知识库语料里找到（锚在判据，不在虚空）', () {
      final corpus =
          '${getSyndromeContent([_kFocusId])}\n${getTrainingContent([_kFocusId])}';
      for (final c in _cases) {
        for (final a in c.anchors) {
          expect(corpus, contains(a), reason: '${c.id} 的判据锚点「$a」未在知识库中找到');
        }
      }
    });

    test('③ ★换壳纪律：每条 probe 不得含 KB 原文示例 / 原外壳指纹词', () {
      for (final c in _cases) {
        for (final f in _kReshellForbidden) {
          expect(
            c.probe.contains(f),
            isFalse,
            reason: '${c.id} 的 probe 含同源指纹「$f」⇒ 与 KB/原样本同源，换壳失败',
          );
        }
      }
    });

    test('④ 覆盖完整性：A1/C1/C2/D1–D5 至少各 1 条换壳（≥8 条）', () {
      const required = [
        'N-A1',
        'N-C1',
        'N-C2',
        'N-D1',
        'N-D2',
        'N-D3',
        'N-D4',
        'N-D5',
      ];
      expect(_cases.length, greaterThanOrEqualTo(8));
      for (final id in required) {
        expect(_cases.any((c) => c.id == id), isTrue, reason: '缺少必覆盖样本 $id');
      }
    });

    test('⑤ 换壳样本互不相同：probe 两两不同、id 唯一', () {
      final probes = _cases.map((c) => c.probe).toSet();
      expect(probes.length, _cases.length, reason: '存在 probe 重复的换壳样本');
      final ids = _cases.map((c) => c.id).toSet();
      expect(ids.length, _cases.length, reason: '存在 id 重复');
    });
  });

  group('P029 换壳负样本 · 判定器两向有牙齿（Fake 脚本，无 key 恒跑）', () {
    test(
      '⑥ 合法输出（hitScript）一律不命中 P029 侧面——${_cases.length}/${_cases.length}',
      () {
        for (final c in _cases) {
          expect(
            _hitsFacet(c.hitScript),
            isFalse,
            reason: '${c.id} 的合法输出被误判为 P029：\n${c.hitScript}',
          );
        }
      },
    );

    test(
      '⑦ 误报路径（missScript）一律命中 P029 侧面——${_cases.length}/${_cases.length}',
      () {
        for (final c in _cases) {
          expect(
            _hitsFacet(c.missScript),
            isTrue,
            reason: '${c.id} 的误报路径未被抓住，判定器无牙齿：\n${c.missScript}',
          );
        }
      },
    );
  });

  group('P029 换壳负样本 · 真实 LLM live 复跑（DeepSeek，@live,external，D6.9 臂 B）', () {
    const prov = _Provider(
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-v4-flash',
      envKey: 'DEEPSEEK_API_KEY',
    );
    final hasKey = Platform.environment[prov.envKey]?.isNotEmpty ?? false;

    setUpAll(() {
      if (!hasKey) return;
      HttpOverrides.global = null; // flutter_test 默认把 HttpClient 换成「永远 400」
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
        if (call.method == 'check') return <String>['wifi'];
        return null;
      });
      final storage = <String, String>{};
      messenger.setMockMethodCallHandler(_kSecureStorageChannel, (call) async {
        final args = (call.arguments as Map?) ?? const <String, String>{};
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

    // ★ D6.9 臂 B PLAN（写死）：
    //   stripped 8 条（N-A1/N-C1/N-C2/N-D1/N-D2/N-D3/N-D4/N-D5）× 1 轮（3 票）；
    //   production 只对 N-A1/N-D2/N-D5 三条 × 1 轮（3 票）。
    //   = 11 测试 × 3 票 = 33 票。
    const strippedIds = <String>[
      'N-A1',
      'N-C1',
      'N-C2',
      'N-D1',
      'N-D2',
      'N-D3',
      'N-D4',
      'N-D5',
    ];
    const productionIds = <String>['N-A1', 'N-D2', 'N-D5'];

    for (final c in _cases.where((e) => strippedIds.contains(e.id))) {
      test(
        '[stripped][${c.id}] ${c.name}：3 票 ≥2 票不报 P029',
        () async {
          if (!hasKey) {
            markTestSkipped('未设置 ${prov.envKey}，跳过真实链路');
            return;
          }
          await _runLiveVotes(c, prov);
        },
        tags: const ['live', 'external'],
        timeout: const Timeout(Duration(seconds: 300)),
      );
    }

    for (final c in _cases.where((e) => productionIds.contains(e.id))) {
      test(
        '[production][${c.id}] ${c.name}：3 票 ≥2 票不报 P029（生产装配臂）',
        () async {
          if (!hasKey) {
            markTestSkipped('未设置 ${prov.envKey}，跳过真实链路');
            return;
          }
          await _runLiveVotes(c, prov, arm: _Arm.production);
        },
        tags: const ['live', 'external'],
        // 生产装配 prompt ≈ 34,912 tokens/票 ⇒ 单票往返显著慢，超时放宽。
        timeout: const Timeout(Duration(seconds: 900)),
      );
    }
  });
}

/// 跑 3 票真实调用并打印读数（与原文件 `_runLiveVotes` 逐字同源；
/// 仅样本类型换为 `_ReshellCase`）。本组是测量器，不是阈值门：判读以人工为准。
Future<void> _runLiveVotes(
  _ReshellCase c,
  _Provider prov, {
  _Arm arm = _Arm.stripped,
}) async {
  final key = Platform.environment[prov.envKey]!;
  final cfg = LlmConfigValues(
    apiKey: key,
    baseUrl: prov.baseUrl,
    model: prov.model,
    // 等效性修复：非流式 chatCompletionWithMeta 的 content 只取 message.content
    // ⇒ reasoning 烧满 chatMaxTokens(4096) 时返回 finish=length + content 空串。
    // 诊断任务用 reasoningTierOff（实测背书），避免 reasoning 吃光预算。
    reasoningTier: reasoningTierOff,
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

  // 有效票守卫：有效票 = content 非空 且 finishReason != 'length'（!isTruncated）；
  // 空响应既不计通过、也不计入有效票分母。
  var valid = 0;
  var passes = 0;
  for (var v = 1; v <= 3; v++) {
    final msgs = _buildMessages(c, arm: arm);
    final res = await client.chatCompletionWithMeta(msgs);
    final isValid = res.content.trim().isNotEmpty && !res.isTruncated;
    final hit = _hitsFacet(res.content);
    if (isValid) {
      valid++;
      passes += hit ? 0 : 1;
    }
    // ignore: avoid_print
    print(
      '[${arm.name}][${c.id}][票$v] 有效=$isValid 未报P029=${!hit} hit=$hit '
      'finish=${res.finishReason} len=${res.content.length}',
    );
    // ignore: avoid_print
    print('  输出: ${res.content.trim()}');
  }
  // ignore: avoid_print
  print(
    '[${arm.name}][${c.id}] 累计用量: ${monitor.totals}（有效票 $valid/3，未报 $passes/3）',
  );

  // 唯一硬断言：读数必须有效。不足即报「无法判定」，不得记为通过。
  expect(
    valid >= 2,
    isTrue,
    reason:
        '${c.id} 有效票仅 $valid/3（其余为 finish=length 的空响应）⇒ '
        '本样本本轮**无法判定**，不得记为「通过」',
  );

  // 三态口径：报 / 明确不报 / 未提及；「未提及」不计入未通过。
  // 判定器分不出 ②与③ ⇒ 正式读数须人工逐票复核。
  final hits = valid - passes;
  final falseRate = valid == 0 ? 0.0 : hits / valid;
  // ignore: avoid_print
  print(
    '[${arm.name}][${c.id}] ★读数：命中(误报)=$hits/$valid 假报率 '
    '${(falseRate * 100).toStringAsFixed(1)}%  '
    '｜未报(正确)=$passes/$valid '
    '正确率 ${(100 - falseRate * 100).toStringAsFixed(1)}%'
    '${falseRate > 0.5 ? '  ← 判据在该带仍系统性误报（R-027 待批）' : ''}',
  );
}

class _Provider {
  final String label;
  final String baseUrl;
  final String model;
  final String envKey;
  const _Provider({
    required this.label,
    required this.baseUrl,
    required this.model,
    required this.envKey,
  });
}
