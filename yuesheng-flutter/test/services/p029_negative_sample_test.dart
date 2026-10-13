// ─────────────────────────────────────────────────────────────
// P029 降智反派症 · 负样本行为级断言集（D6 · V1 判据工业化）
//
// 目的：把「不得报 P029」的负例从**词面钉子**升级为**行为级可红断言**。
// 背景：全仓检索 `不得报 P029` 唯一命中是
//   `test/services/boundary_direction_conflict_test.dart:37` 把 '不得报'
//   列为方向冲突护栏的**词面**监控项 —— 它只保证这串文本**不被删**，
//   零断言验证「这段文本不得被判 P029」。本文件补的就是那一层。
//
// 判据真源（**4** 条例外/分界；2026-10-13 带② 废止后）：
//   `syndrome_kb_content_manual_6.dart` P029「例外情况」段
//     ① 执念/偏执驱动 ② 喜剧/荒诞类型约定（**2026-10-13 已废止** ⇒ 见本文件末 D6.3 块）
//     ③「愚蠢」其实是局 ④ 反派每个动作都落自己利益账本 ⑤ 判定分界（**前三条**成立 ⇒ 报 P010/P007）
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
//   ② 带②（喜剧荒诞）**已按裁定收窄判据**（2026-10-12 舰长裁定「甲」）：
//      判决性实验（B3 裸 × B3g 带体裁说明）证明 —— 补体裁说明后模型仍 **3/3 判 P029**，
//      且 **3/3 明确承认体裁**（「这个类型约定我认」），理由是「**『荒诞』和『工具人』
//      是两回事**」⇒ 排除「样本缺类型上下文」，真根因 = **例外② 的豁免范围（文体）
//      与 P029 的指控维度（动机结构）正交**。
//      ⇒ 处置：① `manual_6` 例外② **收窄**（明写只豁免「荒谬本身」、不豁免「角色动机结构」）
//             ② **B3/B3g 从负样本集移除**（它们是正样本）
//             ③ 带② 剩余样本效度**待验**（已登记）
// ─────────────────────────────────────────────────────────────
// ── D6.2 增量（2026-10-12 · 舰长裁定 A 案 · 带② 负样本重设计）─────
//   依据 = 收窄后例外② 的判据：有效负样本 ⟺ **是喜剧向降智** ∧ **角色账本可达**。
//   ① **移除 `B4`/`B5`**：`B5`（秃头大汉自曝意图）**账本不可达**、与 `B3` 同构 ⇒
//      在收窄后判据下**应报 P029**（实为正样本）；`B4`（老爷算错账）**靶子错位**
//      —— 「老爷算自家账」不是「对手/反派被工具化」场景 ⇒ 不适用 P029，非例外② 豁免。
//   ② **加固 `B1`/`B2`**：`hitScript` 改从「账本」起论（原措辞停在收窄前的「类型约定」）。
//   ③ **新增 `B6`/`B7`/`B8`**：形态 =「**喜剧向、但角色有他自己的账本**」
//      （荒谬在明面、账在暗处）。带② 恢复 5 条（与带①③④ 对称）。
//   ④ `anchors` 由 `['喜剧','类型约定']` 升级为 **`['喜剧','类型约定','动机结构']`**
//      —— 锚在**新判据**（边界原文用词）上，而非旧措辞。
//   ⑤ **恢复带② 进 live 抽样**（`B1` 老样本 + `B6` 新样本双条）。
//   ⚠️ **不恢复成对投喂**（`genreHint`）：收窄后「账本」前提**已在片段内可达**
//      ⇒ 无需体裁信号；且保持四带同形、读数纯净。
// ─────────────────────────────────────────────────────────────
// ── D6.3 增量（2026-10-13 · 舰长裁定「甲」· **带② 整带废止**）─────
//   **★ 触发**：D6.2-live 复核（15 票）证明 D6.2 的 A 案**失败** ——
//   带② 两条（`B1` 加固后 · `B6` 新增）**人工均 3/3 报 P029**。
//   **证据链 = 四次尝试、四种形态，结果全部 3/3 报**：
//     `B3`（裸荒诞）· `B3g`（+体裁声明）· `B1`（+账本暗示）· `B6`（+双层账本）
//   ⇒ **不是样本质量问题**。
//   **★ 根因**：`B6` 票2 **逐字引用** `manual_6` 的边界原文
//   ⇒ **模型在执行判据，不是违背它** ⇒ 问题在**判据本身**：
//   **喜剧的文体机制（夸张/荒诞/当众拆穿）与「角色账本须在文本内显式可推」结构性互斥**。
//   ⇒ **处置（本批）**：
//     ① `manual_6` 例外② **废止**（改为「喜剧/荒诞向**不构成豁免**」，**R-027**）
//     ② `training_few_shot_library.dart` P029 few-shot 附注同步改（**R-027**）
//     ③ **带② 整带从负样本集移除**（`B1/B2/B6/B7/B8` 全部是**正样本**）
//     ④ `sampledIds` → **3 带**（`A1`/`C1`/`D3`）
//   ⇒ `_cases` **20 → 15**；断言 ⑥⑦ 随 `${_cases.length}` 自动变 **15/15**。
//   详见 `.ai/reports/2026-10-13-D6.2-live复核-带②三次重建失败与判据结构性冲突.md`。
// ─────────────────────────────────────────────────────────────
// ── D6.5 增量（2026-10-13 · 舰长裁定「甲」· 带④ 样本层重写）─────
//   **★ 触发**：D6.4 判决性实验（18 票）证明带④ **3/5 失效**：
//     `D3` 3/3 报 · `D4` 2–3/3 报 · `D5` 2/3 报（`D1` 1/3 ✅、`D2` 0–1/3 ✅）。
//   **★ 判决性读数**：`D3`（只给立场）3/3 报 ⟂ `D3g`（同场景 + 族老自有账摆明面）
//     **0/3 报** ⇒ 根因 = **样本形态**（账本是否在文本内可指认），**不是判据缺陷**
//     —— 与带②（判据与文体结构性互斥、改样本无解）**本质不同**：本条**改样本即可解**。
//   **★ 根因细目（`DECISIONS §4-186` 第三形态候选）**：模型的**接受门槛高于判据字面**
//     —— 判据写「为利/活路/欲望至少其一」，模型只认**可在文本内指认的具体得失**
//     （`D4` 账本"自有但抽象"，模型原话「"位置"是个抽象名词，不是具体利益」）。
//     ⚠️ 该形态**列为候选**，须专项实验（抽象 vs 具体成对投喂）确认后方可正式立条。
//   ⇒ **处置（本批 = 甲案：样本层修，零 R-027，不动任何 lib/ 产品代码）**：
//     ① `D3` 按 `D3g` 形态重写（把族老的**自有账**摆到明面：祭田 + 印子钱 + 族老位子）
//     ② `D4` 把「保自己的位置」**落到可指认的得失**（云中三城香火田 + 七成灯油钱）
//     ③ `D5` **给布商一本账**（囤三成货卡下游七家染坊、待入秋涨价）
//     ④ `sampledIds` → 覆盖带④ 三条（复验用）
//     ⇒ `_cases` **15 条不变**（只重写带④ 三条的 probe/hitScript/name，不带增减）。
//   ⚠️ **`D5` 若重写后仍报** ⇒ 确认 **B 类 = 判据作用域问题**（模型把 P029 套到场上
//      没有账本的第二个人），**须单独立项**，不得靠改样本掩盖（见 D6.4 §4/§7）。
//   详见 `.ai/reports/2026-10-13-D6.4-判决性实验-带④三样本失效与账本门槛.md`。
// ─────────────────────────────────────────────────────────────
// ── D6.6 增量（2026-10-13 · 舰长「按北极星相关内容约束处理」授权）────
//   ① **判决性 A/B**：新增 `enum _Arm { stripped, production }` + `_kProductionCtx`
//      ⇒ live 组对带④ 三条**再跑一遍「生产装配臂」**（`abIds`），**唯一变量** =
//      第一段 system 是否换成 `buildSystemPromptV2(_kProductionCtx).systemPrompt`
//      （L1 常驻九 skill + 态度档位 + L2 诊断组 + `_kDiagnosisSceneFirst` +
//      `_kPositionGuidance` + `_kPromptBoundary`）；**档位（`off`）与调用形态
//      （非流式）两臂刻意保持一致**（多变量会致读数不可归因）。
//   ② **装置生效实证**：`[M 批 消耗]` prompt **3,018 → 34,912 tokens/票**。
//   ③ **★ 判决性读数（人工逐票复核为唯一口径）**：
//      `A1` stripped **0/3 报** ✅ · `C1` stripped **0/3 报** ✅ ·
//      **`D3` stripped 2/3 报 ❌ / production 0/3（主跑）与 3/3（探针）** ·
//      **`D4` 两臂都 2/3 报 ❌（跨装置一致）** · `D5` stripped 3/3 ❌ / production 1/3 ✅。
//   ④ **★ 本批核心结论 = 同装置同上下文重复跑，3 票可整体翻面（`D3`：3/3 ↔ 0/3）**
//      ⇒ **单次 3 票读数没有分辨率**，**不得**作为判据改动依据（`DECISIONS §4-188`）。
//      ⇒ 改注入正文（R-027 类）前须先做**功效实验**（同装置同上下文 ≥5 轮 × 3 票）。
//   ⑤ 判定器偏差量化：本批 **24 票中 12 票（50%）**与人工不一致（假阳 9 / 假阴 3）；
//      `A1`/`C1` **全 6 票**判定器记「命中」而模型**逐字声明不报** ⇒ 「误报率」是假象。
//   详见 `.ai/reports/2026-10-13-D6.6-北极星约束裁决与harness生产装配A-B.md`。
// ─────────────────────────────────────────────────────────────
// ── D6.9 收尾·换壳并入（2026-10-13 · 舰长「D 系列收尾直接批」）───────
//   **并入 4 条换壳负样本**（`N-C1`/`N-D1`/`N-D3`/`N-D4`，见本文件 `_cases`
//   带③/带④ 末尾）——来源 = `p029_negative_sample_reshell_test.dart`
//   （D6.8 判据② 换壳样本，§4-189）。
//   **并入理由**（§4-193 判据 3 · D6.9 臂 B 复跑 33 票）：
//     ① 元指认严格词表 **0 命中** ⇒ 换壳有效（模型不再「认得这段」/与 KB 同源）；
//     ② 本 4 条判据保真合格（N-C1/N-D1/N-D3/N-D4 判据结构完整、锚点在场）；
//     ③ 判据保真偏离的 4 条（**N-D2 首要**/N-A1/N-C2/N-D5）**不并入**，
//        留 `reshell` 文件待修壳复跑后统一处置。
//   **装置影响（须登记）**：负样本集 `_cases` **15 → 19** 条 ⇒ 后续测量读数
//   均基于新样本集（与原 15 条并列同装置同 prompt，可比性以「同文件同装置」
//   为准；历史读数的可比性以「换壳 vs 原样本」对照方式解读）。
//   **live 抽样不并入换壳条**：`sampledIds`/`abIds` 保持不变——换壳条的
//   live 复跑由 `reshell` 文件 live 组承担（stripped 8 条 + production 3 条，
//   D6.9 臂 B 已跑 33 票；N-D2 等修壳复跑沿用该文件）。
//   ⚠️ 常驻断言 ⑥⑦ 随 `_cases.length` 自动变为 **19/19**（hit/miss 两向）。
//   **指纹防护**：本文件新增 `_kReshellForbidden` 指纹表 + 常驻卡死断言
//     （与 `reshell` 文件常驻断言③ 同等），只对这 4 条 N- 样本生效，
//     防其未来被改回 KB 原文/古代外壳形态（原 15 条古代外壳不受此约束）。
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
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';
import 'package:writingcoach/types/teaching_types.dart';

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

// ── D6.6 判决性 A/B（2026-10-13 · 舰长「按北极星约束处理」授权）────────
//   动机：D6~D6.5 的**全部** live 读数都在「精简装置」下取得 —— 该装置**缺
//   生产 system prompt 的 L1+L2 六块注入**（见 D6.5 报告 §8.2 逐项对照表）
//   ⇒ 它回答的是「在这套装置下模型怎么判」，**不等于**「线上会怎么判」。
//   本 A/B 用同一批样本、同一档位、同一调用形态，**唯一变量 = 是否注入 L1+L2**，
//   以判定「带④ 三条仍被报 P029」到底是**判据作用域缺口**（真）还是
//   **探针自造的假象**（`DECISIONS-DETAIL §4-153` 同型）。

/// 装配臂（判决性 A/B 的自变量）。
enum _Arm {
  /// 现状：自造 `_kPreamble` + 知识四块（D6~D6.5 全部读数所用装置）。
  stripped,

  /// **对齐生产**：`buildSystemPromptV2` 的完整 system prompt。
  production,
}

/// 生产等效诊断上下文。
///
/// 逐字段复刻 `test/services/skill_prompt_anchor_test.dart` 的
/// `diagnosis_yuesheng` 用例 ⇒ `resolveL2Mode` 落 `L2Mode.diagnosis`
/// ⇒ 触发 `_kDiagnosisSceneFirst` 注入（与线上诊断请求同路径）。
const SkillLoadContext _kProductionCtx = SkillLoadContext(
  phase: TeachingPhase.p2PracticeLoop,
  attitude: AttitudeLevel.yuesheng,
  subphase: TeachingSubphase.diagnosis,
);

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

/// D6.9 换壳并入指纹表（与 `p029_negative_sample_reshell_test.dart` 的
/// `_kReshellForbidden` 同源同表）：KB 原文示例词 + 原古代外壳指纹词。
///
/// 用途：**只**对本文件 D6.9 并入的 4 条换壳样本（`N-C1`/`N-D1`/`N-D3`/`N-D4`）
/// 做静态卡死（见下方「D6.9 换壳并入样本指纹卡死」常驻测试）——防止未来把这 4 条
/// 的 probe 改回古代官场/医馆/世家/教派/商号外壳（那样就与 KB few-shot 原文同源，
/// 退化成「模型认得这段」而非「按判据独立判断」，正是 D6.8 §4-189 换壳要消除的瑕疵）。
/// ⚠️ 不得对全部 `_cases` 套用：原样本本就是古代外壳（`D1` 含「地契」、
///    `D3` 含「祭田/印子钱/族老」、`D4` 含「掌教/香火田/灯油钱」），命中属正常。
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

/// 单条负样本。四带对应 manual_6 的 ①~④ 条例外；`band` 仅作分组标题，
/// **不参与判定**（避免「按带判」这种无意义的分组断言）。
class _Case {
  final String id;
  final String band;
  final String name;
  final String probe;

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

  // ─── 带② 喜剧/荒诞向刻意降智 · **整带已移除**（2026-10-13 · 舰长裁定「甲」）───
  //   ⚠️ **本带已整体废止**（不再是负样本集的一部分）。完整演进链条：
  //     D6        `B1`/`B2`/`B3`/`B4`/`B5`（原始 5 条）
  //     D6.1      判决性实验（`B3` 裸 × `B3g` +体裁声明）⇒ `B3`/`B3g` 移除（均 3/3 报）
  //     D6.2      A 案：移除 `B4`/`B5` + 加固 `B1`/`B2` + 新增 `B6`/`B7`/`B8`
  //     D6.2-live 复核：`B1` **3/3 报**（加固失败）· `B6` **3/3 报**（新增失败）
  //   ⇒ **四次尝试、四种形态，结果一致** ⇒ **不是样本质量问题**。
  //   **★ 根因（本带废止的唯一依据）**：`B6` 票2 **逐字引用**了 `manual_6` 的边界原文
  //   ⇒ **模型没有违反判据，它在严格执行判据** ⇒ 问题在**判据本身**：
  //   **喜剧的文体机制（夸张/荒诞/当众拆穿）与「角色账本须在文本内显式可推」结构性互斥**
  //   —— 一个文本**越是**标准的喜剧降智，它的账本**越**不显式，就**越**会被判 P029。
  //   ⇒ **处置**：`manual_6` 例外② **已废止**（改为「喜剧/荒诞向**不构成豁免**」），
  //     本带随之**整带移除**；该带的全部样本都是**正样本**（确应报 P029 的文本）。
  //   详见 `.ai/reports/2026-10-13-D6.2-live复核-带②三次重建失败与判据结构性冲突.md`。

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
    anchors: ['利益账本', '以下不判降智反派'],
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
    anchors: ['利益账本', '以下不判降智反派'],
  ),
  _Case(
    id: 'D3',
    band: '利益账本到位',
    name: '世家家主自有祭田印子钱押在北岸',
    probe:
        '族老议事，河堤的银子该修南还是北。有人开口：「南边有三千亩。」'
        '族老当场定了北边：「北边三百亩。」他自己两百亩祭田、放给三房的印子钱，'
        '全押在北岸——三房这一垮，他这个族老也就坐到头了。',
    hitScript:
        '利益动机写得实在：族老自家的祭田、印子钱全押在北岸，修北边就是保自己的账，'
        '不是被「南边三千亩」说动的。这段可打磨的是「当场定了北边」太快——'
        '读者还没来得及起疑，答案就已经摊开了。',
    missScript: '降智反派症：族老放着三千亩不修、偏要修三百亩的地方，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '以下不判降智反派'],
  ),
  _Case(
    id: 'D4',
    band: '利益账本到位',
    name: '掌教护短，护的是三城香火田',
    probe:
        '亲传弟子打伤了外门弟子，罚他闭门思过。外人以为掌教护短，'
        '只有执事堂知道：罚弟子不是护弟子——那弟子身后是云中三城的香火田，'
        '每年供着本堂七成灯油钱；这事一旦捅出去，三城撤了供奉、各堂主联名，'
        '他这掌教才真坐不住。',
    hitScript:
        '表层是护短，内核是保那三城的香火田和灯油钱，动机链一环扣一环。'
        '真问题在视角：这段把底牌一次摊完，读者没有参与感——'
        '建议让读者先从「只罚不赔」的蹊跷里自己拼出来。',
    missScript: '降智反派症：掌教不护自己宗门规矩、只护亲传弟子，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '以下不判降智反派'],
  ),
  _Case(
    id: 'D5',
    band: '利益账本到位',
    name: '掌柜放走最大买家（为垄断供货源）',
    probe:
        '最大的布商一次买走三成货，掌柜却笑着退了定金，还多送了两匹样布。'
        '账房不解。掌柜说：「他要是垮了，这门街上就剩我一家能供得起他。」'
        '账房后来才打听到：那布商吃下三成货，是要囤着卡下游七家染坊的料，'
        '等入秋涨价再放。',
    hitScript:
        '掌柜清醒，布商也不糊涂——退了定金这条街上只剩他供得起，'
        '而布商囤货卡的是下游七家染坊，两个人都在算自己的账。'
        '可以建议的是账房那句不解，把它写活一点，好让读者的疑心有个落点。',
    missScript: '降智反派症：掌柜放着大生意不做、主动退定金，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '以下不判降智反派'],
  ),

  // ─── D6.9 换壳并入（§4-193 判据 3 · 舰长「D 系列收尾直接批」）──────
  //   来源 = `p029_negative_sample_reshell_test.dart`（D6.8 判据② 换壳样本，
  //   §4-189：同判据结构、不同人物/题材/措辞，消除「模型认得这段」同源瑕疵）。
  //   并入 4 条判据保真合格者（N-C1/N-D1/N-D3/N-D4）；N-A1/N-C2/N-D2（首要）/
  //   N-D5 判据保真偏离，留 `reshell` 文件待修壳复跑后统一处置。
  _Case(
    id: 'N-C1',
    band: '愚蠢其实是局',
    name: '老财务那一扑是演给走廊内鬼看的戏（D6.9 换壳并入）',
    probe:
        '并购谈判现场，对方独董摔门走人，老财务老魏却突然扑上去拦，被保安一把按在地上。'
        '等谈判破裂、人都散了，老魏才从地上爬起来，对着走廊尽头那个一直没走的法务，'
        '轻轻把工牌翻了个面——他是董事长埋在对方公司八年的暗线，那一扑，是做给那个内鬼看的。',
    hitScript:
        '这段写的是假失态真布局：老魏那一下扑拦是设计给内鬼看的信号，翻工牌这个收尾很好——'
        '真算计不需要台词。可以打磨的是谈判破裂前的节奏再压一压。',
    missScript:
        '降智反派症：老魏作为公司老财务，明知拦不住还扑上去被按在地上，'
        '反派被工具化，只是剧情需要他丢人。',
    anchors: ['愚蠢', '其实是局', '暗中算计'],
  ),
  _Case(
    id: 'N-D1',
    band: '利益账本到位',
    name: '收购方一步步压账期断现金流逼人（D6.9 换壳并入）',
    probe:
        '收购方老板没拍桌子。听完那句「你做梦」，他放下咖啡，慢条斯理道：'
        '「直接买？太便宜你了。」他吩咐财务：「先把他们的账期从九十天压到现款现货，'
        '再去接触他们最大的供应商。三个月之内，我要他们的 CEO 自己走进我办公室。」',
    hitScript:
        '反派每一步都在算账：压账期是断他现金流，接触供应商是拿他命门，'
        '图的是那个被迫上门的收购价。放着筹码用足才让这场收购有分量。',
    missScript: '降智反派症：收购方放着资金优势不用、不直接压价，非要绕弯子，对手被工具化，没有利益动机。',
    anchors: ['利益账本', '以下不判降智反派'],
  ),
  _Case(
    id: 'N-D3',
    band: '利益账本到位',
    name: '众人投城东，董事长偏拍板城西（D6.9 换壳并入）',
    probe:
        '董事会上，城东那块地回报是城西的三倍，董事们几乎一边倒地要投城东。'
        '董事长却当场拍板：「投城西。」他自己手里囤的三个楼盘、押给银行的两笔贷款，'
        '全压在城西——城西这一片起不来，他这个董事长也就坐到头了。',
    hitScript:
        '利益动机写得实在：董事长自家三个楼盘、两笔贷款全押在城西，投城西就是保自己的账，'
        '不是被三倍回报说动的。这段可打磨的是「当场拍板」太快——读者还没起疑，答案就摊开了。',
    missScript: '降智反派症：董事长放着三倍回报的城东不投、偏要投城西，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '以下不判降智反派'],
  ),
  _Case(
    id: 'N-D4',
    band: '利益账本到位',
    name: '院长只停职不除名，保的是三城捐赠实验室（D6.9 换壳并入）',
    probe:
        '附属医院里，主任的亲信医生出了医疗事故，院长只让他停职半年、不予除名。全院都骂院长护短。'
        '只有院办知道：那个医生手里握着一个能拉来三城校友捐赠的重点实验室——'
        '这事一旦公开除名，捐赠撤了、评审委员会联名质询，他这个院长才真坐不住。',
    hitScript:
        '表层是护短，内核是保那间拉来三城捐赠的实验室，动机链一环扣一环。'
        '真问题在视角：这段把底牌一次摊完，读者没有参与感——'
        '建议让读者先从「只停职不除名」的蹊跷里自己拼出来。',
    missScript: '降智反派症：院长不护医院规矩、只护出事故的亲信，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '以下不判降智反派'],
  ),
  // ─── D6.10 收尾批·修壳后并入（2026-10-13 · 舰长「D 系列收尾直接批」第二条）──
  //   修壳复跑 live（k=3，见 outputs/gate/d610_arm2_review.md）：
  //   N-D2 stripped 0/3 报（原 D6.9 臂 B 2/3）+ production 0/3 报、KB 结构指认消除；
  //   N-D5 stripped 1/3 报（原 D6.9 臂 B 2/3，报率下降，判据结构仍完整）。
  //   N-A1/N-C2 修壳后仍 3/3 报 ⇒ 不并入，单列待舰长裁定（仍留 reshell 文件）。
  _Case(
    id: 'N-D2',
    band: '利益账本到位',
    name: '博导七年好全落在那组罕见基因上（D6.10 修壳并入）',
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
        '降智反派症：沈砚七年如一日地对学生好却别无所图，反派没有利益动机，'
        '只是剧情需要他当好人。',
    anchors: ['利益账本', '以下不判降智反派'],
  ),
  _Case(
    id: 'N-D5',
    band: '利益账本到位',
    name: '供应链老板退坑位费，主播囤货卡七个直播间（D6.10 修壳并入）',
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
    missScript: '降智反派症：老板放着大单子不做、主动退坑位费，没有利益动机，反派被工具化。',
    anchors: ['利益账本', '以下不判降智反派'],
  ),
  // ─── D-2 复测并入（2026-10-13 · R-027 追加任务 D · 舰长「方向 A+」四块复测后）──
  //   来源 = `p029_negative_sample_reshell_test.dart`（D6.8 换壳样本）。
  //   此前 D6.9/D6.10 两批均因「修壳后仍 3/3 报」不并入、留 reshell 待舰长裁定。
  //   D-2 复测（装置 `outputs/gate/d66_power_kofn_r027_d2.py`，k=3×3 票）读数：
  //     · N-A1：D0 2/3[20.8,93.9] → D-2 **0/3**[0.0,56.2]。三票全部接受「二十年执念
  //       账本」，残差归「被台词讲太满/呈现问题」（非 P029）——块3 例外①操作化生效。
  //     · N-C2：D0 2/3 → D-2 3/3，但**三票全部先归位布局者、逐字放免林峥**
  //       （"林峥不构成 P029"），串标取证账本读对——块1 报域判定 + 块2 动机定义生效。
  //       ⚠️ 残差：模型仍要求局中人（三家客户）自带账本，块4 局中人豁免未完全落地，
  //          该 3/3 报在局中人、不在布局者；live 复跑仍由 reshell 文件 live 组承担。
  //   舰长核心病灶（执念/布局者被要求证明功利理性账、误报 P029）已消除 ⇒ 判 pair
  //   「有效（有条件）」并入；块4 局中人豁免残留单列后续批。样本原文逐字取自 reshell。
  _Case(
    id: 'N-A1',
    band: '执念驱动',
    name: '老门神亲手守最后一个点球（补二十年前那一脚）（D-2 复测并入）',
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
        '这段存在降智反派症。周正明明状态糟糕、放着替补门将不用，非要亲自上场，'
        '反派被工具化，只是剧情需要他出来守门。',
    anchors: ['执念', '偏执'],
  ),
  _Case(
    id: 'N-C2',
    band: '愚蠢其实是局',
    name: '连丢三个大单是放出去的饵（D-2 复测并入）',
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
    missScript: '降智反派症：林峥连丢三个大单毫无章法、被追责也不辩解，没有利益动机，反派被工具化。',
    anchors: ['愚蠢', '其实是局', '暗中算计'],
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

/// 组装消息（知识四块与生产 `_injectTrainingFsmAndContext` 等价：
/// 训练内容 + few-shot + L3 手册 + 技法，四面齐全）。
///
/// [arm]（D6.6 判决性实验新增）只决定**第一段 system** 用哪一份：
/// - [\_Arm.stripped] = 自造 `_kPreamble`（现状）；
/// - [\_Arm.production] = `buildSystemPromptV2(_kProductionCtx).systemPrompt`
///   （L1 常驻九 skill + 态度档位 + L2 诊断组 + `_kDiagnosisSceneFirst` +
///   `_kPositionGuidance` + `_kPromptBoundary`）。
///
/// ⚠️ 两臂**唯一变量** = 是否注入 L1+L2 装配：知识四块、档位（`off`）、
/// 调用形态（非流式）、用户消息，两臂逐字相同 —— 否则多变量混杂，读数无法归因。
List<ChatMessage> _buildMessages(_Case c, {_Arm arm = _Arm.stripped}) {
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
      // B2 豁免内化（R-027）：症候 KB 的显式否定措辞由「不得报 P029」改为
      // 「以下不判降智反派」（manual_6 P029 段）；旧串现仅存于 few-shot 面
      // （training_few_shot_library.dart），故本条断言指向症候 KB 段新措辞，
      // 与 few-shot 面的断言④区分。意图不变：例外段否定措辞在场。
      expect(
        l3,
        contains('以下不判降智反派'),
        reason: '例外段须有显式否定措辞（B2 后症候 KB 为「以下不判降智反派」）',
      );
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

    // ★ D6.9（2026-10-13 · 舰长「D 系列收尾直接批」）：换壳并入样本的指纹卡死。
    //   与 `p029_negative_sample_reshell_test.dart` 常驻断言③ 同等防护 ——
    //   并入正式集后，这些 N- 换壳条的 probe 不得被未来改回 KB 原文/古代外壳形态。
    //   D6.10 第二条：并入 N-D2/N-D5（修壳合格）；N-A1/N-C2 未并入，不纳入。
    test(
      '换壳并入样本指纹卡死（N-C1/N-D1/N-D3/N-D4/N-D2/N-D5/N-A1/N-C2）：probe 不得回含 KB 原文/原外壳指纹词',
      () {
        const mergedIds = [
          'N-C1',
          'N-D1',
          'N-D3',
          'N-D4',
          'N-D2',
          'N-D5',
          'N-A1',
          'N-C2',
        ];
        for (final id in mergedIds) {
          final c = _cases.firstWhere(
            (e) => e.id == id,
            orElse: () => throw StateError('缺少 D6.9 换壳并入样本 $id'),
          );
          for (final f in _kReshellForbidden) {
            expect(
              c.probe.contains(f),
              isFalse,
              reason:
                  '${c.id} 的 probe 含同源指纹「$f」⇒ 换壳外壳被改回古代/KB 同源形态，'
                  'D6.9 并入失效（防未来被改）',
            );
          }
        }
      },
    );
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

    // 抽样 **5 条（3 带全覆盖，带④ 全测）**—— 每条 3 票 ≥2 票。
    // **不跑全部**：真模型往返烧 token，且同一判据的多条负例高度同族，
    // 边际信息量低。抽样是刻意裁定，不是省事（读数见 D6 报批材料 §3 乙案）。
    // ★ D6.1 增量：`B3g` = B3 的**同文本对照**（多一条体裁说明 system）⇒
    //   判决性实验：B3 3/3 报 vs B3g ?/3 报，直接判明带② 误报根因是
    //   「判据缺陷」还是「样本缺类型上下文」（复核报告 §5.1）。
    // ⚠️ D6.1：`B3`/`B3g` 已移除（判决性实验证明其非有效负样本）。
    // ⚠️ D6.2：`B1`/`B6` 等带② 样本曾短暂恢复抽样，D6.2-live 复核证明仍 3/3 报。
    // ★ D6.3（舰长裁定「甲」）：**带② 整带废止**（判据与喜剧文体结构性互斥，见文件末
    //   D6.3 块）⇒ 抽样回到 **3 带**（`A1` ① + `C1` ③ + `D3` ④），**9 票**。
    // ★ D6.5（舰长裁定「甲」· 样本层修）：带④ 三条（`D3`/`D4`/`D5`）**本批全部重写**
    //   ⇒ 抽样扩到 **5 条**（`A1` ① + `C1` ③ + `D3`/`D4`/`D5` ④），**15 票**——
    //   带④ 是本批唯一改动对象，须逐条复验（D6.4 判决性读数：`D3` 3/3 · `D4` 2–3/3 ·
    //   `D5` 2/3 报）。①③ 各留 1 条作非改动带对照。
    const sampledIds = <String>['A1', 'C1', 'D3', 'D4', 'D5'];

    // ★ D6.6 判决性 A/B（2026-10-13）：带④ 三条**再跑一遍「生产装配臂」**。
    //   唯一变量 = 第一段 system 是否换成 `buildSystemPromptV2` 的完整装配
    //   （L1 常驻九 skill + 态度档位 + L2 诊断组 + `_kDiagnosisSceneFirst` +
    //   `_kPositionGuidance` + `_kPromptBoundary`）。档位（`off`）与调用形态
    //   （非流式）两臂保持一致 ⇒ 多变量不混杂。
    //   判读规则：
    //     · 生产臂「不报」而精简臂「报」 ⇒ 精简装置在**自造**缺口（§4-153 同型），
    //       改 `manual_6`（触 R-027）**不成立**；
    //     · 两臂**都报** ⇒ 缺口为**真** ⇒ ② 类停线项才取得立项资格。
    //   只跑带④：①③ 两带在 D6~D6.5 中从未失守，无 A/B 必要（省 token）。
    const abIds = <String>['D3', 'D4', 'D5'];

    for (final c in _cases.where((e) => sampledIds.contains(e.id))) {
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

    // ★ D6.6 生产装配臂（同上样本、同档位、同调用形态 ⇒ 唯一变量 = 装配）。
    for (final c in _cases.where((e) => abIds.contains(e.id))) {
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
        // 生产装配 prompt 实测 74,571 字符（`skill_dispatcher.dart` 头注）
        // ⇒ 单票往返显著慢于精简臂，超时放宽。
        timeout: const Timeout(Duration(seconds: 900)),
      );
    }
  });
}

/// 跑 3 票真实调用并断言 ≥2 票「未报 P029」。
///
/// [arm] 见 `_buildMessages`：两臂共用同一判定器、同一用户消息、同一有效票守卫。
Future<void> _runLiveVotes(
  _Case c,
  _Provider prov, {
  _Arm arm = _Arm.stripped,
}) async {
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
