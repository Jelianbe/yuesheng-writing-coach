// ─────────────────────────────────────────────────────────────
// 症候类型层（`SyndromeRecord` 及其枚举）
//
// ★ 2026-11-15 `T-20261115-10`：自 `syndrome_registry.dart` **逐字迁出**，零行为变更。
//   迁出动因 = registry 拆记录册后仍 >300 行（类型段 179 行占大头）；
//   结构同构于 `skill_types.dart` ↔ `skill_registry.dart` 的既有分层。
//   `syndrome_registry.dart` 以 `export` 转发 ⇒ 外部 import 路径不变。
// ─────────────────────────────────────────────────────────────
import 'syndrome_skill_types.dart'; // SkillLevel

/// 症候类型（症候库「症候类型速查」表使用；skill_registry 类型分组表
/// 的「语言表达类」由渲染函数按 P006/P018 特例映射，见批次30）
enum SyndromeType {
  motivationDeficit('motivation_deficit'),
  expressiveDeficit('expressive_deficit'),
  structuralDisorder('structural_disorder'),
  commercialAppeal('commercial_appeal');

  final String value;
  const SyndromeType(this.value);
}

/// maxAttempts 分组（skill_registry「轮次上限」：表达≤3 / 结构≤5 / 深层≤5）
enum MaxAttemptsGroup {
  expression('表达类'),
  structure('结构类'),
  deep('深层类');

  final String label;
  const MaxAttemptsGroup(this.label);
}

/// 诊断呈现分组（ADR-C146 · 2026-10-11 新增）。
///
/// 与 [SyndromeType]（诊断性质）/ [MaxAttemptsGroup]（训练轮次）**正交**：
/// 本枚举只管「诊断卡按哪一组展示」，是**纯呈现层**分组，不影响诊断判据、
/// JSON 契约、训练动作。模型**不输出**此字段 —— 由 `syndrome_id` 静态反查得出。
///
/// 四组语义（归组见 ADR-C146 §2.2，归组草案
/// `2026-10-11-37条症候归组草案.md`）：
/// - [description] 描写：文字表达层（措辞/句式/语病/画面/声线）
/// - [plot] 剧情：结构/节奏/商业层
/// - [character] 角色：人物层
/// - [logic] 逻辑：★「逻辑性弱」因果链的横切标记（P007 动机→P016 过渡→
///   P017 概括→P036 常识逻辑）。成员症候**主身份各归各自组**，本值只标记
///   「这几条同属一条因果链」，供「同源提示」判定 —— 见 ADR-C146 §2.2。
enum PresentationGroup {
  description('描写'),
  plot('剧情'),
  character('角色'),
  logic('逻辑');

  final String label;
  const PresentationGroup(this.label);
}

/// 「量」维度标签（诊断维度改进方案 §2.1，正交于 [SyndromeType] 与 [SkillLevel]）。
///
/// 不是「性质」（那是 [SyndromeType]），也不是「层级」（那是 [SkillLevel]），
/// 而是**第三条切法**：这段文字的问题出在「写多了 / 写少了 / 词没用对」。
/// 供诊断卡作分组/筛选键，由注册表静态映射，模型不输出此字段。
///
/// - [underwritten] 少写：关键处没写够 / 该展开的没展开（情绪标签化、OC 平面化…）
/// - [overwritten] 多写：冗余 / 堆砌 / 重复（信息倾泻、语言堆砌、心理内耗…）
/// - [wordChoice] 用词：词本身没用对（基础语病、翻译腔…）
///
/// ⚠️ 非每条症候都有量维度（如 P003 视角漂移、P038 描写顺序失序是「顺序/视角」问题，
///   不是量的问题）⇒ 字段可空，[quantityTagOf] 查不到返回 null。
enum QuantityTag {
  underwritten('少写'),
  overwritten('多写'),
  wordChoice('用词');

  final String label;
  const QuantityTag(this.label);
}

/// 症候元数据（增删症候的唯一入口）
class SyndromeRecord {
  /// 症候 ID（`P0XX`，连续编号，**永不复用**）。
  final String id;

  /// 全名（手册标题 / 训练段标题 / 索引关键词可用时）
  final String name;

  /// 精简名（training-templates-index / 技法 L3 表用）
  final String shortName;

  /// 索引表「问题类型关键词」列（独立字段，非名称）
  final String keyword;

  /// 一句话描述（索引表一句话 / 类型速查核心问题共用）
  final String oneLine;

  /// 类型速查「核心问题」短句（症候库「症候类型速查」列，与 oneLine 不同源）
  final String typeLine;

  /// training-templates-index「核心本质一句话」（skill_registry 教学知识索引，
  /// 与 oneLine / typeLine 均不同源）
  final String trainingLine;

  /// 症候类型（症候库类型速查表）
  final SyndromeType type;

  /// 技能层级（L1-L5，复用 syndrome_skill_levels 的 SkillLevel）
  final SkillLevel level;

  /// maxAttempts 分组（训练轮次上限）
  final MaxAttemptsGroup group;

  /// 诊断呈现分组（ADR-C146，纯呈现层，见 [PresentationGroup]）
  final PresentationGroup presentationGroup;

  /// 「量」维度标签（诊断维度改进方案 §2.1，见 [QuantityTag]）。
  /// 可空：非每条症候都有量维度（顺序/视角/逻辑类不填）。
  final QuantityTag? quantityTag;

  /// position_sensitivity：取值见 kPositionSemantics（position_semantics.dart）
  final String position;

  /// 判定本症候是否需要以「另一部作品」为参照系（P035 遮名测试）。
  /// 与 position 正交：position 表达「看多大」，本字段表达「跟什么比」。
  final bool needsCrossWorkReference;

  /// 推荐技法 ID 列表（首选在首位，可含备选；与 kTechniquesBySyndrome 一致）
  final List<String> techniques;

  /// 推荐教学动作 ID 列表（首选在首位，可含备选；与 v1 动作映射一致）
  final List<String> actions;

  /// v1 动作映射（coaching-actions）专用名：与 name 不同时设置
  final String? v1ActionName;

  /// v2 动作映射（coaching-actions-v2）专用名：与 shortName 不同时设置
  final String? v2ActionName;

  /// 作用维（四值白名单见 [kSyndromeRoleValues]；T-20261110-12 · U4 双签 · R0 裁乙）
  final String role;

  /// 分块链专属举证条款（可选；null ⇒ 不追加，拼装结果与改动前**逐字相同**）。
  ///
  /// 试点 `T-20261113-04`：仅 P035 填值。手册里 P035 有 5 项「原例外内化」的豁免
  /// （`syndrome_kb_content_manual_6.dart:433`），但分块链注入面**一个字都看不到**
  /// （`b1_two_chain_contract_audit.py` 现测：例外表 30 条无 P035）。
  ///
  /// 本字段把这个缺口转成**举证门槛**，不是豁免清单 —— ADR-C153 否决的是清单形态
  /// （「任何文本都能套用 ⇒ 每个分片发一张免责模板」，`chunk_prompt.dart:92-118`）：
  /// 先要求「指认可无损移植之处」，指不出即不报；豁免只放**最保守的一项**
  /// （①通用件），且命中必须在 `excluded` 记名。
  ///
  /// ⚠️ 措辞为**否定式**（「仅因结构通用、可被替换，不判本条」）。这是盲判证据逼出来的：
  /// 手册原文「类型通用件**本身即辨识来源**」被独立判读者读成**报因**（两段武动乾坤
  /// 都判「报」且理由正是「通用件」），照抄则加了也翻不动。见
  /// `.ai/reports/2026-11-13-P035盲判结果与三道核查.md` §七。
  ///
  /// ⚠️ 短链**不读**本字段（`oneLine` 的消费面 `syndrome_knowledge_base.dart:149`
  /// 不受影响）⇒ 单侧改动，回滚 = 置 null。
  final String? chunkEvidenceClause;

  const SyndromeRecord({
    required this.id,
    required this.name,
    required this.shortName,
    required this.keyword,
    required this.oneLine,
    required this.typeLine,
    required this.trainingLine,
    required this.type,
    required this.level,
    required this.group,
    required this.presentationGroup,
    this.quantityTag,
    required this.position,
    this.needsCrossWorkReference = false,
    required this.techniques,
    required this.actions,
    this.v1ActionName,
    this.v2ActionName,
    required this.role,
    this.chunkEvidenceClause,
  });

  /// v1 动作映射显示名（coaching-actions）
  String get v1ActionDisplayName => v1ActionName ?? name;

  /// v2 动作映射显示名（coaching-actions-v2）
  String get v2ActionDisplayName => v2ActionName ?? shortName;
}

/// 作用维四值白名单（T-20261110-12 · R0 裁乙 · U4 双签 39/0 · 报批稿A §2.3）
const Set<String> kSyndromeRoleValues = {'内容', '结构', '情感', '读者'};
