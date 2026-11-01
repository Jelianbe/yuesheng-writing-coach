// ─────────────────────────────────────────────────────────────
// SyndromeRedirectTable — 撤销改道登记表（T-20261031-12 · R-027 已批）
//
// 33 条改道逐字登记。**文案唯一真源** = `.ai/reports/2026-11-01-温知新-31-12教学层签与33条文案.md`
// §二 33 条终稿表 —— 本文件只抄录：一个字不改、不新造术语、不新造训练出口。
// 文案漂移由 `test/services/syndrome_redirect_test.dart` 的遍历断言守住。
//
// 分家说明：本文件只放「数据」，派生与校验 API 在 `syndrome_redirect.dart`
// （R-019 文件级 300 行硬上限：33 条逐字登记 + 派生函数同文件实测 367 行 ⇒ 超限）。
// 两文件合起来 = 报批稿 §2.3 的「33 条登记 + 派生函数」。偏差已回执。
// ─────────────────────────────────────────────────────────────

/// 一条改道登记。
class SyndromeRedirect {
  /// 类型记号：'S' = 转另一症候的训练 · 'A' = 转同域动作训练 · 'T' = 无出口。
  final String type;

  /// 主指向 id（终稿表「机器指向（主 · 备）」列的首个 id）；T 行为 null。
  final String? primary;

  /// 该行**允许发出**的 id 集（= 该行文案里出现的 Pxxx/Axxx 集）。
  final Set<String> allowed;

  /// 学员面一句话（逐字取自终稿表 §二，不新造术语）。
  final String text;

  const SyndromeRedirect({
    required this.type,
    required this.primary,
    required this.allowed,
    required this.text,
  });

  /// 是否进模型面：S/A 进；**T 不进**（无出口可指，注入负向句只会耗 token
  /// 且有被复述进 reason 的风险 ⇒ T 文案只作客户端兜底渲染）。
  bool get inModelFace => type != 'T';
}

/// 33 条改道登记（逐字取自温知新终稿表 §二）。
///
/// `allowed` = 该行文案里出现的 id 集（协议「不得超出该行登记的指向集合」）。
/// `primary` = 终稿表机器指向列的首个 id。
/// ★ P028 的 `allowed` = {P007, P014}：终稿表该行机器指向列只写 P007，
///   但同表学员面文案含「转 P014」⇒ 按「文案里出现的 id 才是允许发出的 id」
///   （报批稿 §2.3 遍历断言口径）登记两支，primary 仍为 P007。偏差已回执。
const Map<String, SyndromeRedirect> kSyndromeRedirects = {
  'P001': SyndromeRedirect(
    type: 'S',
    primary: 'P009',
    allowed: {'P009', 'P021', 'P003'},
    text:
        '情绪标签化不成立而情绪问题仍在时，多半归属他条：对话段落里先修对话结构（P009）、通篇缺画面先建画面（P021）、视角漂移在先先统一视角（P003）。',
  ),
  'P003': SyndromeRedirect(
    type: 'T',
    primary: null,
    allowed: {},
    text: '本条撤销后没有点名可转向的其他症候训练；视角是否仍有问题，由你按下一次诊断判断。',
  ),
  'P004': SyndromeRedirect(
    type: 'S',
    primary: 'P010',
    allowed: {'P010', 'P011', 'P012', 'P017'},
    text:
        '节奏停滞不成立而问题仍在时，先看归属：缺冲突分量转 P010、开篇冷启动转 P011、结尾收束无力转 P012、关键事件被概括带过转 P017 的训练。',
  ),
  'P005': SyndromeRedirect(
    type: 'S',
    primary: 'P004',
    allowed: {'P004'},
    text: '句式单一不成立而「读者读这段读不下去」仍在时，那是节奏维度的问题——转 P004 的训练。',
  ),
  'P006': SyndromeRedirect(
    type: 'A',
    primary: 'A011',
    allowed: {'A011'},
    text: '语言堆砌不成立而文字仍显繁复时，同域的练法是场景裁剪（A011）——是否使用由你决定。',
  ),
  'P007': SyndromeRedirect(
    type: 'S',
    primary: 'P015',
    allowed: {'P015', 'P014'},
    text: '角色空心化不成立时：动机本已立住而行为前后矛盾，转 P015 的训练；动机立住而情节靠巧合推进，先修因果链，转 P014。',
  ),
  'P008': SyndromeRedirect(
    type: 'S',
    primary: 'P007',
    allowed: {'P007'},
    text: 'OC 平面化不成立而角色仍立不住时，动机缺失是更深层的问题——转 P007 的训练。',
  ),
  'P009': SyndromeRedirect(
    type: 'S',
    primary: 'P002',
    allowed: {'P002'},
    text: '对话疲劳不成立而对话仍在硬灌设定时，叙述层是根因——转 P002 的训练。',
  ),
  'P010': SyndromeRedirect(
    type: 'A',
    primary: 'A003',
    allowed: {'A003', 'P024', 'P029'},
    text:
        '张力不足不成立时先看根因：金手指过强则转 P024、对手无利益动机则转 P029；若张力感仍缺，同域练法是五问法（A003）——是否使用由你决定。',
  ),
  'P011': SyndromeRedirect(
    type: 'T',
    primary: null,
    allowed: {},
    text: '开篇平庸要看前三章整体，本条撤销后没有点名可转向的其他症候训练——开篇是否调整，由你决定。',
  ),
  'P012': SyndromeRedirect(
    type: 'A',
    primary: 'A012',
    allowed: {'A012'},
    text: '结尾乏力不成立而收束感仍缺时，同域练法是伏笔追踪（A012）——是否使用由你决定。',
  ),
  'P013': SyndromeRedirect(
    type: 'S',
    primary: 'P010',
    allowed: {'P010'},
    text: '高潮疲软不成立而冲突仍无分量时，张力是根因——先修冲突分量，转 P010 的训练。',
  ),
  'P014': SyndromeRedirect(
    type: 'T',
    primary: null,
    allowed: {},
    text: '本条撤销后没有点名可转向的其他症候训练；事件是否缺少前置原因，按本条判据由你复核。',
  ),
  'P015': SyndromeRedirect(
    type: 'S',
    primary: 'P007',
    allowed: {'P007'},
    text: '人设崩塌不成立时：若角色从一开始就缺乏动机，那不是崩塌而是空心——转 P007 的训练。',
  ),
  'P016': SyndromeRedirect(
    type: 'S',
    primary: 'P003',
    allowed: {'P003'},
    text: '过渡生硬不成立而视角漂移在先时，转 P003 的训练——视角统一后过渡自然改善。',
  ),
  'P017': SyndromeRedirect(
    type: 'A',
    primary: 'A005',
    allowed: {'A005'},
    text: '跳跃叙事不成立而关键情节点仍被带过时，同域练法是动作链展开（A005）——是否展开由你决定。',
  ),
  'P018': SyndromeRedirect(
    type: 'S',
    primary: 'P006',
    allowed: {'P006'},
    text: '重复用词不成立而读者仍费力抓不住核心时，那是句级修饰密度的问题——转 P006 的训练。',
  ),
  'P019': SyndromeRedirect(
    type: 'S',
    primary: 'P012',
    allowed: {'P012'},
    text: '章节钩子不成立而收束无力发生在全文尾时，那是结尾维度的问题——转 P012 的训练。',
  ),
  'P020': SyndromeRedirect(
    type: 'A',
    primary: 'A012',
    allowed: {'A012'},
    text: '追读动力不足不成立而长线留存仍弱时，同域练法是伏笔追踪（A012）——是否使用由你决定。',
  ),
  'P025': SyndromeRedirect(
    type: 'S',
    primary: 'P007',
    allowed: {'P007', 'P008'},
    text: '配角工具人不成立时：核心角色动机缺失更深，先修 P007；核心角色缺辨识度则先修 P008，配角群像后修。',
  ),
  'P026': SyndromeRedirect(
    type: 'S',
    primary: 'P001',
    allowed: {'P001', 'P006'},
    text: '心理内耗不成立时：内心戏在直接告知情绪，先修 P001；修饰词堆砌则先修词藻，转 P006 的训练。',
  ),
  'P027': SyndromeRedirect(
    type: 'S',
    primary: 'P020',
    allowed: {'P020', 'P025', 'P004'},
    text: '支线涣散不成立时：长线留存弱先修留存结构（P020）、配角无性格先修配角（P025）、支线段局部停滞先救事件推进（P004）。',
  ),
  'P028': SyndromeRedirect(
    type: 'S',
    primary: 'P007',
    allowed: {'P007', 'P014'},
    text: '被动主角不成立时：动机整体缺失更深，先修 P007；情节靠巧合推进则先修因果链，转 P014。',
  ),
  'P030': SyndromeRedirect(
    type: 'T',
    primary: null,
    allowed: {},
    text: '本条撤销后没有点名可转向的其他症候训练；声线是否仍漂移，由你对照前文判断。',
  ),
  'P031': SyndromeRedirect(
    type: 'T',
    primary: null,
    allowed: {},
    text: '题材边界属创作前提层（写什么题材、给谁看），本条撤销后没有同域的场景层动作——赛道定位由你决定。',
  ),
  'P032': SyndromeRedirect(
    type: 'T',
    primary: null,
    allowed: {},
    text: '本条判据对象在句法-语感层，撤销后没有作用于此层的训练动作——是否调整由你决定。',
  ),
  'P033': SyndromeRedirect(
    type: 'A',
    primary: 'A003',
    allowed: {'A003'},
    text: '冲突未升级不成立而冲突模式仍原地重复时，同域练法是五问法（A003）——是否使用由你决定。',
  ),
  'P034': SyndromeRedirect(
    type: 'T',
    primary: null,
    allowed: {},
    text: '本条治的是「谁被指」而非「谁在看」，撤销后没有治指代的训练动作——指代是否清楚，按本条判据（就近能否确定指谁）由你复核。',
  ),
  'P035': SyndromeRedirect(
    type: 'T',
    primary: null,
    allowed: {},
    text: '撞文同质化不成立时没有点名可转向的训练——场景是否仍可与任意同类作品互换，按本条判据由你复核。',
  ),
  'P036': SyndromeRedirect(
    type: 'T',
    primary: null,
    allowed: {},
    text: '本条撤销后暂不指认训练动作；细节是否失真，按本条判据由你复核。',
  ),
  'P037': SyndromeRedirect(
    type: 'A',
    primary: 'A013',
    allowed: {'A013'},
    text: '故事核缺失不成立而主干仍立不住时，同域练法是情节复盘（A013）——是否使用由你决定。',
  ),
  'P038': SyndromeRedirect(
    type: 'T',
    primary: null,
    allowed: {},
    text: '治本条的办法是按感知到达顺序或因果发生顺序重排（由你自己重排），但当前没有与此对应的训练动作——是否重排由你决定。',
  ),
  'P039': SyndromeRedirect(
    type: 'T',
    primary: null,
    allowed: {},
    text: '本条撤销后没有点名可转向的其他症候训练；信息密度是否仍是问题，由你按下一次诊断判断。',
  ),
};
