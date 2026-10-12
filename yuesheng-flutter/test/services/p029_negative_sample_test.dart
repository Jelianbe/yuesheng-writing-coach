// ─────────────────────────────────────────────────────────────
// P029 降智反派症 · 负样本行为级断言集（D6 · V1 判据工业化）
//
// 目的：把「不得报 P029」的负例从**词面钉子**升级为**行为级可红断言**。
// 背景：全仓检索 `不得报 P029` 唯一命中是
//   `test/services/boundary_direction_conflict_test.dart:37` 把 '不得报'
//   列为方向冲突护栏的**词面**监控项 —— 它只保证这串文本**不被删**，
//   零断言验证「这段文本不得被判 P029」。本文件补的就是那一层。
//
// 判据真源（5 条例外/分界，本批 D6 刚落地）：
//   `syndrome_kb_content_manual_6.dart` P029「例外情况」段
//     ① 执念/偏执驱动 ② 喜剧/荒诞类型约定 ③「愚蠢」其实是局
//     ④ 反派每个动作都落自己利益账本 ⑤ 判定分界（前四条成立 ⇒ 报 P010/P007）
//   `training_kb_content_4.dart` P029「常见误区」段（三条均不构成 P029）
//   `training_few_shot_library.dart` P029 两条「✅正常写法·不得报 P029」
//
// 设计（仿 `test/live_p038_diagnosis_test.dart`，同构）：
//   ① 单变量：所有样本共用同一 focusSyndromeId=P029 + 同一知识库 + 同一
//      prompt，唯一差异 = 投喂文本与判读方向。
//   ② 双侧脚本：每条负样本带 `hitScript`（合法输出**不应**命中 P029
//      概念侧面）+ `missScript`（误报路径**应**命中）⇒ 判定器两向都有牙齿。
//      **只测「不报」会得到一个恒绿的弱断言**（§4-158 同型教训）。
//   ③ 概念侧面词表**只收问题信号词、不收中性词** —— 中性词（冲突/张力/动机/
//      反派/利益）在合法文本里也出现，会系统性误报（P038 头注明文警告）。
//   ④ 常驻自检组（FakeLlmClient，无 key 无网络恒跑）+ @live 组
//      （`tags: ['live','external']`，无 key 时 markTestSkipped，不破门禁）。
//   ⑤ Key 只经环境变量 DEEPSEEK_API_KEY，**严禁写入源码**（R-029）。
//
// 运行：
//   flutter test test/services/p029_negative_sample_test.dart
//   $env:DEEPSEEK_API_KEY="sk-xxx"
//   flutter test --tags "live,external" test/services/p029_negative_sample_test.dart
//
// 边界（R-010）：纯测试层新增，不改任何 lib/ 产品代码。
//
// ── D6.1 增量（2026-10-12 · 舰长裁定 ①②③ 三项）────────────────
//   ① 判定器**降级为辅助筛查器**（见 `_hitsFacet` 上方注释）：正式读数
//      一律以**人工逐票复核**为准；判定器只用于常驻组自检 + live 命中辅助定位。
//   ③ 人工复核采**三态口径**：「报 / 明确不报 / 未提及」；**「未提及」不计入
//      未通过**（负样本约束是「不得报」，沉默不构成误报）——见 `_runLiveVotes` 内注释。
//   ② 带②（喜剧荒诞）**暂不收紧判据**：复核报告 §5.1 指出其 3/3 读数
//      **无法区分**「判据缺陷」与「样本缺类型上下文」，而 `manual_6` 例外② 的
//      适用前提是「**喜剧/荒诞向作品**」（作品级）⇒ 裸片段投喂下**不可达**。
//      故先加 **B3g 对照样本**（同文本 + 体裁说明）做判决性实验，据结果再定是否
//      需要改知识源正文（= 新 R-027 触点）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/reasoning_tier.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_retry.dart';
import 'package:writingcoach/services/llm_usage_monitor.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';

const String _kFocusId = 'P029';

const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 教练前置（与生产 message_injector 等价）。
const String _kPreamble =
    '你是一名写作教练。学员给你看一段他新写的小说文字，请你做诊断，'
    '不要替学员改写句子、不要替他做决定。'
    '请指出这段文字里最核心的一个写作问题：必须点到具体位置（引用原文里的词或句），'
    '并说明这个问题为什么是问题、它伤害了读者的什么阅读体验。一次只聚焦一个最主要的点。';

/// P029 概念侧面：**只收「问题信号」词，不收中性词**。
///
/// ⚠️ 收窄纪律（P038 同款，此处更关键）：P029 的中性词密度极高
/// ——「动机」「利益」「反派」「冲突」「张力」在**合法样本里必然出现**
/// （合法反派本来就有利益动机！）。若把它们收进词表，判真/判假两侧都会命中，
/// 判定器立刻退化为恒绿。
/// 故此处只收「工具化 / 无支撑 / 为剧情需要出场」这类**只在误报路径出现**的信号。
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

/// 单条负样本。四带对应 manual_6 的 ①~④ 条例外；`band` 仅作分组标题，
/// **不参与判定**（避免「按带判」这种无意义的分组断言）。
class _Case {
  final String id;
  final String band;
  final String name;
  final String probe;

  /// 体裁/意图提示（**可选**）。非空时作为**独立 system 消息**注入，模拟
  /// 「学员提交时说明了作品体裁」这一生产场景。
  ///
  /// 动因（2026-10-12 D6.1）：`manual_6` 例外② 的原文是「**喜剧/荒诞向作品**
  /// 刻意用降智制造笑点：类型约定」——其适用前提是**作品级体裁判断**。
  /// 而裸片段投喂下该前提**不可达**（模型无从知道这是不是一部喜剧）⇒ B3 的
  /// 3/3 误报**无法区分**「判据缺陷」与「样本信息不足」（复核报告 §5.1）。
  /// 与 N3 批「`'m0'` 不可达」同型：**不可达条款 = 措辞而非约束**。
  /// ⇒ 设 B3（裸，无 hint）× B3g（带 hint）**对照**，以判决性实验判明根因。
  final String? genreHint;

  /// 合法输出：教练正确地指出别的真问题（或明确不判 P029）⇒ 不应命中。
  final String hitScript;

  /// 误报路径：把该段判成「降智反派 / 对手被工具化」⇒ 应命中。
  final String missScript;

  /// 该样本豁免所依据的判据原文片段（钉「断言真的在读判据」）。
  final List<String> anchors;

  const _Case({
    required this.id,
    required this.band,
    required this.name,
    required this.probe,
    this.genreHint,
    required this.hitScript,
    required this.missScript,
    required this.anchors,
  });
}

final List<_Case> _cases = [
  // ─── 带① 执念/偏执驱动（动机极端但不失内在逻辑）───────────────
  _Case(
    id: 'A1',
    band: '执念驱动',
    name: '教主亲守崖边等三十年（为子复仇的偏执）',
    probe:
        '魔教教主明知林远武功远不及自己，却偏偏不派手下，亲自守在崖边等他。'
        '手下不解，他笑了笑：「这一天，我等了三十年。我要亲手把他的血，滴在我儿子的牌位前。」',
    hitScript:
        '这段写的是偏执，不是降智。教主的动机极端（为子复仇）但内在逻辑完整——'
        '他不亲自来，这口气三十年放不下，硬要了结在别人手里反而失真。'
        '真要说问题，是林远此刻该不该来：明知是陷阱还走进来，动机略薄。',
    missScript:
        '这段存在降智反派症。教主明知武功远不及，却放着几十个手下不用、亲自上场，'
        '反派被工具化，只是剧情需要他出来死。',
    anchors: ['执念', '偏执'],
  ),
  _Case(
    id: 'A2',
    band: '执念驱动',
    name: '仇人必须亲手了结（多年血债的执念）',
    probe:
        '老城主守着城门整整十二年，不为别的，就为等当年屠城的那个男人回来。'
        '部下劝他设埋伏、用药，他都摇头：「我要看着他死。」',
    hitScript:
        '动机链是清楚的：十二年只等一个人，这是仇，不是蠢。'
        '放着手下用确实像降智，但那是执念的代价，不是反派被工具化——'
        '他有自己的账要算。真问题在老城主的守法太单薄，十二年只守一门。',
    missScript:
        '降智反派症成立。老城主手握全城兵权却十二年只守一门，还拒不听劝，'
        '对手被工具化，冲突毫无分量。',
    anchors: ['执念', '偏执'],
  ),
  _Case(
    id: 'A3',
    band: '执念驱动',
    name: '为一句羞辱放弃逃生（名誉执念）',
    probe:
        '少爷被当众踩了一脚，手下已经抽刀护主，他却拦住刀，自己走回厅里，'
        '把茶盏砸在那人脸上：「今日之辱，不亲手讨回来，我沈家三辈人的脸往哪搁。」',
    hitScript:
        '这是名誉执念，不是无脑送死。他有退路也未必没有，但「三辈人的脸」'
        '是他的账，动机具体到名誉利益。你要能商量的其实是「能不能更划算地讨回面子」，'
        '不是「他为什么要亲自上」。',
    missScript:
        '这段典型降智反派：明明有刀在手、明明可以事后算账，却非要自己冲上去，'
        '反派被工具化，为剧情需要他挨打。',
    anchors: ['执念', '偏执'],
  ),
  _Case(
    id: 'A4',
    band: '执念驱动',
    name: '断腿也要亲手了断（执念已成本能）',
    probe:
        '老瞎子只剩一条腿，硬要爬着上城楼。弟子要背他，他吐了一口血在地上，'
        '把剑往前挪了三寸：「我这条命就是留着取他项上那颗头的。让开。」',
    hitScript:
        '执念已经成本能，逻辑虽极端但自洽。值得说的是这一段的感官——血、挪剑、'
        '三寸，距离感很好，读者能看见他快到极限。',
    missScript: '降智反派症：老瞎子断了腿还不用弟子背，自己爬上去送死，对手被工具化。',
    anchors: ['执念', '偏执'],
  ),
  _Case(
    id: 'A5',
    band: '执念驱动',
    name: '反复回到同一地点（创伤驱动的固执）',
    probe:
        '她第七次走进这间茶馆。第七次坐在同一个位置，点同一壶茶，看着同一个方向。'
        '掌柜已经不再招呼她——三年前她在这里签下卖身契，把弟弟换了回去。',
    hitScript:
        '这不是反派降智，是创伤驱动的重复行为，动机链完整（愧疚、纪念、逃避三者掺在一起）。'
        '真正可以写的是第七次与第一次之间她袖子里多了什么——细节在替她说话。',
    missScript:
        '这段存在降智反派症：反派反复回到让她失去一切的地方，没有利益动机支撑，'
        '只是剧情需要她出现。',
    anchors: ['执念', '偏执'],
  ),

  // ─── 带② 喜剧/荒诞向刻意降智（类型约定）─────────────────────
  _Case(
    id: 'B1',
    band: '喜剧荒诞',
    name: '为活命主动求饶还硬说自己不怕（喜剧向）',
    probe:
        '「你、你再过来我就、我就咬舌自尽！」壮汉一边喊一边往后缩，'
        '膝盖抖得裤腿直晃。旁边有人小声提醒他台词说错了，他压着嗓子骂：「闭嘴！」',
    hitScript:
        '喜剧向的刻意降智，类型约定，不是真缺陷。真正有趣的是「台词说错了」那个小回扣——'
        '人物在表演自己的英雄台词，这层套层写得好。',
    missScript: '降智反派症成立：反派明显怕死却硬撑，为剧情需要他出丑，对手被工具化。',
    anchors: ['喜剧', '类型约定'],
  ),
  _Case(
    id: 'B2',
    band: '喜剧荒诞',
    name: '蠢到用计谋的蠢（大智若愚的反向写法）',
    probe:
        '胖子一顿饭吃了六碗，然后抹着嘴说：「我这记性太差了，昨天教你的那套话，全忘了。」'
        '旁边的人互相对视了一眼——全城都知道他背得出整本账。',
    hitScript:
        '这是荒诞喜剧的「装傻」结构，不是降智反派。他的蠢是有功能的：'
        '扮猪吃虎让对手放松。值得写的是旁边那一眼，读者比角色先知道真相。',
    missScript: '降智反派症：胖子明明背得出账却装作记性差，反派没有利益动机，被工具化。',
    anchors: ['喜剧', '类型约定'],
  ),
  _Case(
    id: 'B3',
    band: '喜剧荒诞',
    name: '反派坚持一个明显荒谬的执论（喜剧性固执）',
    probe:
        '县令拍着惊堂木：「本官判你充军三千里——理由？你长得太碍眼。」'
        '师爷在下面小声提醒律例没有这一条，他一拍桌子：「本官今天就是律例！」',
    hitScript:
        '荒诞喜剧的经典结构，县令的蠢是权力本身的一部分，读者笑点在这儿。'
        '真要建议的是师爷那一句提醒可以再快半拍，笑点会更响。',
    missScript: '降智反派症：县令毫无利益动机，随意判充军，反派被工具化，冲突失真。',
    anchors: ['喜剧', '类型约定'],
  ),
  _Case(
    id: 'B4',
    band: '喜剧荒诞',
    name: '当着全家面算错账（刻意的丑化）',
    probe:
        '老爷要算这道账，账房先生拨了两回算盘，最后抬头报了个数。'
        '老爷点头：「好，记上。」夫人从屏风后探头：「老爷，那笔银子是去年修桥的。」',
    hitScript:
        '这段的笑点是「他自己知道错」——所以点头那一声才成立。'
        '荒诞向的丑化被控制在人物性格内，没有破坏读者对世界的信任。',
    missScript: '降智反派症：老爷连自己家的账都算不清，反派无利益动机支撑，被工具化。',
    anchors: ['喜剧', '类型约定'],
  ),
  _Case(
    id: 'B5',
    band: '喜剧荒诞',
    name: '反派自曝意图后还大摇大摆（荒诞式降智）',
    probe:
        '「我要灭了你的满门。」秃头大汉站在人家门口，指着自己的脑袋。'
        '主人很客气地请他进来喝茶，说：「你先进来，我让人去把门关上。」',
    hitScript:
        '荒诞喜剧的节奏：反派自曝，主角接得比反派更狠。笑点在两句话的落差，'
        '不在反派为什么来。',
    missScript: '降智反派症成立：反派上门自曝意图还要对手提醒关门，没有利益动机，纯为剧情需要。',
    anchors: ['喜剧', '类型约定'],
  ),
  // ★ B3g = B3 的**同文本对照**，唯一差异 = 多一条体裁说明 system。
  //   判决性实验（D6.1）：B3 3/3 报 vs B3g ?/3 报 ⇒ 直接判明带② 误报根因是
  //   「判据缺陷」（需改 manual_6 例外②，R-027）还是「样本缺类型上下文」（无需改）。
  //   ⚠️ 它**不是**「把答案喂给模型」——例外② 的适用前提本就是「作品属喜剧/荒诞向」，
  //      提供体裁信息是在**使前提可达**，而不是在给结论。
  _Case(
    id: 'B3g',
    band: '喜剧荒诞',
    name: '【对照·带体裁说明】县令荒谬判词（同 B3 文本 + 体裁提示）',
    genreHint:
        '补充说明：这是一部荒诞喜剧，作者刻意用夸张的官腔与不合逻辑的判词制造笑点，'
        '读者预期就是看个热闹，不要求现实可信度。',
    probe:
        '县令拍着惊堂木：「本官判你充军三千里——理由？你长得太碍眼。」'
        '师爷在下面小声提醒律例没有这一条，他一拍桌子：「本官今天就是律例！」',
    hitScript:
        '荒诞喜剧的经典结构，县令的蠢是权力本身的一部分，读者笑点在这儿。'
        '真要建议的是师爷那一句提醒可以再快半拍，笑点会更响。',
    missScript: '降智反派症：县令毫无利益动机，随意判充军，反派被工具化，冲突失真。',
    anchors: ['喜剧', '类型约定'],
  ),

  // ─── 带③「愚蠢」其实是局（表面降智、暗中算计）───────────────
  _Case(
    id: 'C1',
    band: '愚蠢其实是局',
    name: '死士挨刀是演给内鬼看的戏',
    probe:
        '城主府议事厅，主角独闯进来，满堂侍卫都按兵不动，家仆老周却突然扑上去挡刀，'
        '当场被打晕。等主角被押走，老周才睁眼，对着房梁上那个蒙面人轻轻敲了三下碗沿——'
        '他是城主安插在府里二十年的死士，挨那一刀是演给内鬼看的戏。',
    hitScript:
        '这段写的是「假降智真布局」：老周的蠢是设计给内鬼看的信号，'
        '敲三下碗沿这个收尾很好——真算计不需要台词。',
    missScript:
        '降智反派症：老周作为城主心腹，明知不敌还要扑上去挡刀，反派被工具化，'
        '只是剧情需要他挨打。',
    anchors: ['愚蠢', '其实是局', '暗中算计'],
  ),
  _Case(
    id: 'C2',
    band: '愚蠢其实是局',
    name: '主动送上一座空城（引君入瓮）',
    probe:
        '守将大开城门，弃城南逃，一路丢了三座城。朝廷骂他怯战，他一概不回话，'
        '只让人把每一处城门都插满新换的黑旗。',
    hitScript:
        '这是诱敌的经典形态：弃城是主动送出的诱饵，黑旗才是真正的信息。'
        '真正能写的是朝廷骂他时他不回话的那段沉默——他在等一个必须由皇帝来问的问题。',
    missScript: '降智反派症：守将连输三城毫无章法，弃城逃跑没有利益动机，反派被工具化。',
    anchors: ['愚蠢', '其实是局', '暗中算计'],
  ),
  _Case(
    id: 'C3',
    band: '愚蠢其实是局',
    name: '当众承认贪财（钓鱼执法）',
    probe:
        '御史当众索贿，收下了银票，还故意多要了一份。回府后他称了称：'
        '「两份都收，才显得我贪。两份里必有一份是别人塞来攀我的。」',
    hitScript:
        '表面是贪，反面是查。这一段有意思的地方在于他多要那一份的动机——'
        '反向钓鱼，且他自己算得清账。可以建议把「称」这个动作再慢一点。',
    missScript: '降智反派症：御史当众索贿毫无顾忌，为剧情需要他贪，反派被工具化。',
    anchors: ['愚蠢', '其实是局', '暗中算计'],
  ),
  _Case(
    id: 'C4',
    band: '愚蠢其实是局',
    name: '反复输给同一对手（引对方入局）',
    probe:
        '这已经是薛第三次输给江了。军中都在传薛不堪一击。第四次交手前，'
        '江把军中所有将领的家乡籍贯抄了一份，锁进了书房。',
    hitScript:
        '连续输三次是要读者跟着一起松懈的，真正的落点在江那份籍贯抄本。'
        '问题在「军中都在传」这句太快，读者还没跟着松懈，江就已经赢了——顺序可以倒过来。',
    missScript: '降智反派症：薛三次败给同一对手毫无章法，没有利益动机，反派被工具化。',
    anchors: ['愚蠢', '其实是局', '暗中算计'],
  ),
  _Case(
    id: 'C5',
    band: '愚蠢其实是局',
    name: '醉着应下不可能的赌约（装醉脱身）',
    probe:
        '「赌就赌！」他拍着桌子站不稳，满座都笑了。三天后，有人去他府上送礼，'
        '门房回话说：老爷在等你们三十天前送来的那批货。',
    hitScript:
        '醉是设计好的，三十天的期限才是真话。这一段的节奏好——先给读者的嘲笑，'
        '再把嘲笑收回去。可以打磨的是「拍着桌子站不稳」的动作细节。',
    missScript: '降智反派症：反派明明可以不应赌，却为了剧情需要他上套，没有利益动机。',
    anchors: ['愚蠢', '其实是局', '暗中算计'],
  ),

  // ─── 带④ 利益账本到位的普通反派（非例外，仅易误报）───────────
  _Case(
    id: 'D1',
    band: '利益账本到位',
    name: '知府冻地契骗证据（现有 few-shot 改善版同族）',
    probe:
        '知府没拍案。他听完那句「狗官」，端起茶盏抿了一口，才慢悠悠道：'
        '「乱刀砍死？太便宜他了。」他吩咐师爷：「先把他那间客栈的地契冻了，'
        '再去查他妹妹在谁家做活。三天之内，我要他自己跪上来。」',
    hitScript:
        '反派每一步都在算账：冻地契是断他活路，查人是拿人质，骗的是那份密折。'
        '放着资源用足才让死磕有分量。',
    missScript: '降智反派症：知府放着兵马不用、不先断人活路，非要直接动手，对手被工具化。',
    anchors: ['利益账本', '不得报 P029'],
  ),
  _Case(
    id: 'D2',
    band: '利益账本到位',
    name: '墨大夫夺舍续命（现有 ❌未命中锚点同族）',
    probe:
        '墨大夫悉心栽培韩立，传道授业，十年间从不摆架子，弟子们都说他是好人。'
        '只有他自己知道：韩立的体质能容人，他的元寿只剩三年。',
    hitScript:
        '这类铺垫极干净：十年的温柔全有落点。真值得说的是最后那句「只有他自己知道」——'
        '读者在揭底前需要一点更早的异样感，现在只有一个直接的悬念。',
    missScript:
        '降智反派症：墨大夫十年如一日地对弟子好却别无所图，反派没有利益动机，'
        '只是剧情需要他当好人。',
    anchors: ['利益账本', '不得报 P029'],
  ),
  _Case(
    id: 'D3',
    band: '利益账本到位',
    name: '世家家主只为自己族人算账',
    probe:
        '族老议事，河堤的银子该修南还是北。有人开口：「南边有三千亩。」'
        '族老当场定了北边：「北边三百亩，但族里三房都在北岸。」',
    hitScript:
        '利益动机写得极实（三百亩换三房安稳），这段反而值得提醒一句：'
        '三千亩这个数字太像反派配置，建议给它一个具体的用途，否则读者会怀疑。',
    missScript: '降智反派症：族老放着三千亩不修、偏要修三百亩的地方，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '不得报 P029'],
  ),
  _Case(
    id: 'D4',
    band: '利益账本到位',
    name: '掌教护短但护的是自己的位置',
    probe:
        '亲传弟子打伤了外门弟子，罚他闭门思过。外人以为掌教护短，'
        '只有执事堂知道：罚弟子不是护弟子，是保掌教自己的位置——'
        '若此事传出去，各堂主联名，他这位置就坐不稳了。',
    hitScript:
        '表层是护短，内核是自保，动机链完整。真问题在视角：这段把底牌一次摊完，'
        '读者没有参与感——建议让读者先从「只罚不赔」的蹊跷里自己拼出来。',
    missScript: '降智反派症：掌教不护自己宗门规矩、只护亲传弟子，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '不得报 P029'],
  ),
  _Case(
    id: 'D5',
    band: '利益账本到位',
    name: '掌柜放走最大买家（为垄断供货源）',
    probe:
        '最大的布商一次买走三成货，掌柜却笑着退了定金，还多送了两匹样布。'
        '账房不解。掌柜说：「他要是垮了，这门街上就剩我一家能供得起他。」',
    hitScript:
        '这一段把「反派」写得比多数主角都清醒。可以建议的是账房那句不解——'
        '它是唯一让读者进入掌柜视角的缝，这里正好可以把账房写活一点。',
    missScript: '降智反派症：掌柜放着大生意不做、主动退定金，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '不得报 P029'],
  ),
];

/// 判定输出是否命中 P029 的概念侧面。
/// 左侧否定域标记。
///
/// 必要性（2026-10-12 D6 实测教训）：真实教练在判对时**会引用标签名再否定它**
/// ——「这段写的是偏执，不是降智」「不是反派被工具化」。裸 `contains` 判定会把这
/// 类**正确输出**判成命中 ⇒ 判定器在最容易出错的方向（该不报时没报）反而失灵。
/// 故命中判定须先回看信号词左侧窗口，命中否定标记则不计该次命中。
/// ⚠️ 词表来源纪律（2026-10-12 D6 第二轮实测教训）：
///   **不得凭直觉列否定词表** —— 必须按真实模型输出语料补。首版只列了书面语
///   常见的七项（不是/并非/不构成/不属于/谈不上/不叫/而非），实测漏掉
///   模型判对时的**首选句式**：
///     「这段文字，我不报 P029（降智反派症）」——「我不报」不在词表内，
///     ⇒ 一句明确的正确判读被计成误报（首轮 A1 两票全由此误判）。
///   模型与人类书面语的第一否定句式不同，凭直觉列词表必然漏。
const List<String> _kNegationMarkers = [
  '不是',
  '并非',
  '不构成',
  '不属于',
  '谈不上',
  '不叫',
  '而非',
  // ── 以下为 2026-10-12 实测补入（来源=live3.log 真实模型输出）──
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

/// 信号词左侧窗口长度（字符）。**16 是实测校准值**，不是拍脑袋：
///   真实模型句式「我先说结论：**这段文字，我不报 P029（」在「降智反派」之前
///   有 13 个字符（「我先说结论：**这段文字，我不报 P029（」），12 字窗口
///   **够不到**「不报」⇒ 必然漏判。16 覆盖该形态并留余量。
const int _kNegationWindow = 16;

/// ⚠️ 判定器定位（2026-10-12 D6.1 裁定 · 甲案）：**辅助筛查器，不是判真器**。
///
/// 依据 = D6 live 复核实测 **4 处偏差**（3 假阳性 + 1 假阴性），归四类：
/// 「对象错位」（信号词修饰的是配角不是反派）·「提及 ≠ 判定」（引用/转述标签名）·
/// 「表述漂移」（同义异形，词表追不上语言多样性）·「正向词表缺口」。
/// **前三类原理上词表治不了** —— 它没有语义层，看不出「谁被工具化」、
/// 分不出「说这个词」与「判这个症」。⇒ 结构性上限，不是补两个词能修的
/// （§4-153 探针缺陷伪装成被测对象问题 · §4-162 rc≠0 不等于断言生效 的镜像）。
///
/// 故用途**仅限**两条：
///   ① 常驻组 ⑥~⑪ 用 FakeLlmClient 验证**判定器自身**有牙齿（该组不依赖真模型）；
///   ② 跑 live 时打印命中详情，**辅助**人工定位可疑票。
/// **不得**把本判定器的 `rc` / 读数当作「模型假报率」结论 ——
/// **正式读数一律以人工逐票复核为准**（15 票约 20 分钟，成本可控）。
/// 详见 `.ai/reports/2026-10-12-D6-live读数复核-判定器缺陷与带级结论.md` §3 / §6。
///
/// 判定输出是否命中 P029 的概念侧面（含左侧否定域守卫）。
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

/// 组装消息（与生产 `_injectTrainingFsmAndContext` 等价：
/// 训练内容 + few-shot + L3 手册 + 技法，四面齐全）。
List<ChatMessage> _buildMessages(_Case c) {
  final msgs = <ChatMessage>[ChatMessage(role: 'system', content: _kPreamble)];
  final hint = c.genreHint;
  if (hint != null) {
    msgs.add(ChatMessage(role: 'system', content: hint));
  }
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

/// 脚本化 Fake LLM：直接返回预置文本，无 key 无网络。
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
  }) async => ChatCompletionResult(content: content);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P029 负样本 · 注入面与判据在场（无 key，恒跑）', () {
    test('① 四面注入非空（训练内容 / few-shot / L3 手册 / 技法）', () {
      expect(getTrainingContent([_kFocusId]), isNotEmpty);
      expect(getTrainingFewShot([_kFocusId]), isNotEmpty);
      expect(getSyndromeContent([_kFocusId]), isNotEmpty);
      expect(
        getTechniquesBySyndrome([_kFocusId]),
        isNotEmpty,
        reason: '技法面缺失会让判定器失去参照面（不入 prompt 但影响断言完备性）',
      );
    });

    test('② 手册段 5 条例外/分界判据逐条在场（D6 本批落地面）', () {
      final l3 = getSyndromeContent([_kFocusId]);
      expect(l3, contains('不得报 P029'), reason: '例外段须有显式否定措辞');
      expect(l3, contains('利益账本'), reason: '第 4 条（利益账本到位）须在场');
      expect(l3, contains('P010'), reason: '第 5 条判定分界须指向正确归口 P010');
      expect(l3, contains('P007'), reason: '第 5 条判定分界须指向正确归口 P007');
    });

    test('③ 训练段三条常见误区均声明「不构成 P029」（D6 本批落地面）', () {
      final t = getTrainingContent([_kFocusId]);
      expect(t, contains('均不构成 P029'));
    });

    test('④ few-shot 两条「正常写法·不得报 P029」（含本批新增「局」带）', () {
      final f = getTrainingFewShot([_kFocusId]);
      final occurrences = '不得报 P029'.allMatches(f).length;
      expect(
        occurrences,
        greaterThanOrEqualTo(2),
        reason:
            'D6 前 few-shot 只有 1 条（执念+喜剧带），'
            '本批补「愚蠢其实是局」带后应 ≥2',
      );
      expect(f, contains('死士'), reason: '新增负例应带「局」的标志物');
    });

    test('⑤ 每条负样本的锚点片段都能在四面注入里找到（锚点不是空壳）', () {
      final corpus =
          '${getSyndromeContent([_kFocusId])}\n${getTrainingContent([_kFocusId])}';
      for (final c in _cases) {
        for (final a in c.anchors) {
          expect(
            corpus,
            contains(a),
            reason: '${c.id} 的判据锚点「$a」未在知识库中找到 ⇒ 该样本可能锚在虚空',
          );
        }
      }
    });
  });

  group('P029 负样本 · 判定器自身有牙齿（FakeLlmClient，无 key 恒跑）', () {
    test(
      '⑥ 合法输出（hitScript）判定为「不报 P029」——${_cases.length}/${_cases.length}',
      () {
        for (final c in _cases) {
          expect(
            _hitsFacet(c.hitScript),
            isFalse,
            reason: '${c.id}（${c.band}）的合法输出被误判为 P029：\n${c.hitScript}',
          );
        }
      },
    );

    test(
      '⑦ 误报路径（missScript）判定为「报 P029」——${_cases.length}/${_cases.length}',
      () {
        for (final c in _cases) {
          expect(
            _hitsFacet(c.missScript),
            isTrue,
            reason:
                '${c.id}（${c.band}）的误报路径未被抓住，判定器无牙齿：\n'
                '${c.missScript}',
          );
        }
      },
    );

    test('⑧ 走完整装配链仍两向可判（不是只判裸字符串）', () async {
      final c = _cases.firstWhere((e) => e.id == 'C1');
      final msgs = _buildMessages(c);
      expect(msgs.length, greaterThanOrEqualTo(5), reason: '四面 + 前置 + 用户消息');
      final hit = await _ScriptedFakeLlmClient(
        c.hitScript,
      ).chatCompletionWithMeta(msgs);
      expect(_hitsFacet(hit.content), isFalse);
      final miss = await _ScriptedFakeLlmClient(
        c.missScript,
      ).chatCompletionWithMeta(msgs);
      expect(_hitsFacet(miss.content), isTrue);
    });

    test('⑨ 词表收窄纪律：中性词一律不命中（防止退化为恒绿）', () {
      // 这几条在**合法样本里必然出现**，若词表收进来判定器立刻失去鉴别力。
      const neutralOutputs = [
        '这个反派有自己的利益动机，冲突建立在真实的利益对抗上，张力够了。',
        '主角的动机不足，他进这座城不是为了报仇，是为了拿回地契——是主角的问题。',
        '反派的算计有铺垫，他的每一步都落在自己的账上。',
      ];
      for (final out in neutralOutputs) {
        expect(_hitsFacet(out), isFalse, reason: '中性词被收进词表 ⇒ 合法输出也会命中：\n$out');
      }
    });

    test('⑩ 左侧否定域守卫两向有效（D6 实测缺陷固化护栏）', () {
      // 正向：引用标签但否定它 ⇒ 正确教练的标准回应 ⇒ 不得命中
      const negatedQuotes = [
        '这段写的是偏执，不是降智。',
        '他不是反派被工具化，是动机极端但不失内在逻辑。',
        '这不构成降智反派，只是表面看着反常。',
        '并非为坏而坏，而是三十年执念驱动。',
        '谈不上工具化，他每一步都在算自己的账。',
      ];
      for (final out in negatedQuotes) {
        expect(
          _hitsFacet(out),
          isFalse,
          reason: '否定式引用被误判为 P029 命中（守卫失效）：\n$out',
        );
      }
      //负向：肯定断言 ⇒ 必须命中（守卫不得把真命中也吃掉）
      const assertedQuotes = [
        '这段成立降智反派症，他放着资源不用。',
        '对手被工具化，只是剧情需要他出场。',
        '反派为坏而坏，没有任何利益支撑。',
        '他智商不在线，被怼两句就亲自送人头。',
      ];
      for (final out in assertedQuotes) {
        expect(_hitsFacet(out), isTrue, reason: '肯定断言未被命中（守卫把真命中也吃掉了）：\n$out');
      }
      // 混排：先否定后肯定 ⇒ 应以**最后一次**出现的语境为准
      expect(
        _hitsFacet('这不是降智反派，但上一版确实是反派被工具化。'),
        isTrue,
        reason: '同段内先否定后肯定，判定器须能识别出存在肯定语境',
      );
    });

    test('⑪ 真实模型否定句式（我不报/不判/未报 P029）不得计成误报（live3 语料固化）', () {
      // 语料来源：`live3.log` 真实 DeepSeek 输出——模型判对时的**首选句式**。
      // 首版词表只有书面语七项（不是/并非/不构成/…）⇒ 下列句式一条都拦不住，
      // 实测 A1 两票被计成误报、整体读数翻向（见 §4-153 同型教训）。
      // ⚠️ 每条样本**必含 `_kFacetToolization` 信号词**：否则其「不命中」只是
      //   因为句子里压根没有信号词 ⇒ 恒绿无牙齿（§4-158 同型）。
      const realNegations = [
        '我先说结论：这段文字，我不报 P029（降智反派症）。',
        '我不报「反派被工具化」这一条——他每一步都在算自己的账。',
        '我不报 P029——他并非为坏而坏，而是三十年执念。',
        '这段我不判 P029，尽管反派有工具化痕迹。',
        '本次未报 P029（工具化）。',
        '此处不该报 P029：反派没有利益支撑这一说不成立。',
      ];
      for (final out in realNegations) {
        expect(
          _hitsFacet(out),
          isFalse,
          reason: '真实否定句式被计成误报（新补否定词未生效）：\n$out',
        );
      }
      // 负向（牙齿）：同句式去掉否定词 ⇒ 必须命中，
      // 证明上面不是「因为句子里没有信号词」而绿。
      const assertAfterStrip = ['我报 P029（降智反派）。', '反派被工具化，他放着资源不用。'];
      for (final out in assertAfterStrip) {
        expect(_hitsFacet(out), isTrue, reason: '去掉否定词后应命中（反证信号词确实在场）：\n$out');
      }
    });
  });

  group('P029 负样本 · 真实 LLM 验证（DeepSeek，@live,external）', () {
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

    // 抽样 5 条（4 带全覆盖 + 「局」带 2 条）—— 每条 3 票 ≥2 票。
    // **不跑 20 条**：真模型往返烧 token，且同一判据的多条负例高度同族，
    // 边际信息量低。抽样是刻意裁定，不是省事（读数见 D6 报批材料 §3 乙案）。
    // ★ D6.1 增量：`B3g` = B3 的**同文本对照**（多一条体裁说明 system）⇒
    //   判决性实验：B3 3/3 报 vs B3g ?/3 报，直接判明带② 误报根因是
    //   「判据缺陷」还是「样本缺类型上下文」（复核报告 §5.1）。
    const sampledIds = <String>['A1', 'B3', 'B3g', 'C1', 'C2', 'D3'];

    for (final c in _cases.where((e) => sampledIds.contains(e.id))) {
      test(
        '[${c.id}] ${c.name}：3 票 ≥2 票不报 P029',
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
  });
}

/// 跑 3 票真实调用并断言 ≥2 票「未报 P029」。
Future<void> _runLiveVotes(_Case c, _Provider prov) async {
  final key = Platform.environment[prov.envKey]!;
  final cfg = LlmConfigValues(
    apiKey: key,
    baseUrl: prov.baseUrl,
    model: prov.model,
    // ★ 等效性修复（2026-10-12 D6 实测）：非流式 `chatCompletionWithMeta` 的
    // content 只取 `message.content`（llm_client.dart:558，不含 reasoning_content）
    // ⇒ 推理烧满 chatMaxTokens(4096) 时返回 finish=length + content 空串。
    // 首轮实测 C1/C2/D3 各 3 票全为此形态（累计 completion 12290/12288/12288
    // ≈ 3×4096）⇒ 空串不命中词表 ⇒ 判定器给满分而模型一字未出（假绿）。
    //
    // 选 `off` 而非 `low` 的依据：reasoning_tier.dart 头注实测「关思考的效果随
    // 场景翻转——**诊断零退化**，教学场景 6/6 任务失败」⇒ 本测试是诊断任务，
    // `off` 有实测背书；`low` 仅降 31% 输出，不足以避免 reasoning 吃光预算。
    //
    // ⚠️ 等效性代价（须在台账登记）：本 live 组测的是「关闭思考档下的判据表现」，
    // 与生产默认档（standard）**不完全等效**。生产主链走 streamChat 且带
    // ADR-C94 分级降级（llm_client.dart:705-722），本 harness 绕过该降级。
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

  // ★ 有效票守卫（2026-10-12 D6 实测教训，§4-162 同型）：
  //   首轮 C1/C2/D3 各 3 票全部返回 `finish=length` + content 空串
  //   （累计 completion 12290/12288/12288 ≈ 3 × LlmConfig.chatMaxTokens 4096
  //   ⇒ reasoning 吃光预算、content 一字未出）。空串必然不命中词表
  //   ⇒ 判定器会给满分，而模型其实什么都没说——「断言通过 ≠ 断言生效」。
  //   故：有效票 = content 非空 **且** finishReason != 'length'；
  //       空响应**既不计通过、也不计入有效票分母**。
  var valid = 0;
  var passes = 0;
  for (var v = 1; v <= 3; v++) {
    final msgs = _buildMessages(c);
    final res = await client.chatCompletionWithMeta(msgs);
    final isValid = res.content.trim().isNotEmpty && !res.isTruncated;
    final hit = _hitsFacet(res.content);
    if (isValid) {
      valid++;
      passes += hit ? 0 : 1;
    }
    // ignore: avoid_print
    print(
      '[${c.id}][票$v] 有效=$isValid 未报P029=${!hit} hit=$hit '
      'finish=${res.finishReason} len=${res.content.length}',
    );
    // ignore: avoid_print
    print('  输出: ${res.content.trim()}');
  }
  // ignore: avoid_print
  print('[${c.id}] 累计用量: ${monitor.totals}（有效票 $valid/3，未报 $passes/3）');

  // 唯一硬断言：读数必须**有效**。不足即报「无法判定」，不得记为通过。
  expect(
    valid >= 2,
    isTrue,
    reason:
        '${c.id} 有效票仅 $valid/3（其余为 finish=length 的空响应）⇒ '
        '本样本本轮**无法判定**，不得记为「通过」',
  );

  // ★ 三态口径（2026-10-12 D6.1 裁定 · 丙案）：
  //   人工复核时输出应分**三态** ——
  //     ①「报 P029」（= 误报，计入分子）
  //     ②「明确不报 P029」（= 完成负样本要求的识别）
  //     ③「未提及 P029」（答了别的真问题，既未报、也未排除）
  //   口径裁定：**「未提及」不计入「未通过」**。理由 = 本负样本集的约束是
  //   「**不得报** P029」，沉默不构成误报；要求模型主动否定 = 更高的
  //   「显式拒绝率」标准，应单列、不混入误报分母。
  //   ⇒ 正确识别率 =（有效票 − 命中票）/ 有效票（即 明确不报 + 未提及）。
  //   ⚠️ 判定器**分不出** ② 与 ③（两者都是「未命中」）⇒ 这正是「读数须人工复核」
  //      的直接原因；本打印只能给「是否命中」，三态归属须人工标注。
  //
  // ★ 本组是**测量器**，不是阈值门（2026-10-12 D6 裁定）：
  //   假报率是真实产品缺陷信号，不是「测试该断言的东西」。若写成硬阈值就必须
  //   现在决定「可接受误报率是多少」——而该数无依据（首轮读数见 D6 报告）。
  //   故此处只保证读数**有效**，判读交由人 + 台账。
  // ★ 口径订正（2026-10-12 D6 第二轮）：`passes` 统计的是「**未报** P029」
  //   的票数 = **正确**票数，故 `passes/valid` 是**正确率**。
  //   首轮我把它当「假报率」打印 ⇒ 读数整体反了，且下面的告警条件
  //   （`rate > 0.5`）读的是正确率 ⇒ **永远不触发**（正确率低）。
  //   两处必须同源：分子一律取 `valid - passes`（命中票），分母取 `valid`。
  final hits = valid - passes;
  final falseRate = valid == 0 ? 0.0 : hits / valid;
  // ignore: avoid_print
  print(
    '[${c.id}] ★读数：命中(误报)=$hits/$valid 假报率 '
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
