// ─────────────────────────────────────────────────────────────
// 症候退役档案（**纯文档** · 2026-10-05 层 2 单轨收口批起运行时零消费）
//
// ── 为什么有这个文件 ──
// 0.3.6+10 做过一次纯代码重编号（`e64096db`），**无数据迁移**，留下三张
// 必须手工同步的表：
//   ① `kSyndromeMergeMap`（读路径真源，syndrome_registry.dart）
//   ② `_legacyToCanonical`（v46 迁移平铺表，migration_v46.dart）
//   ③ 护栏的「合法 legacy 编号豁免集合」（3 个测试文件各写一遍）
// 每次内容增减都要三处同步，漏改**不报错**，只会静默串号 —— 本文件是它们的
// 唯一来源，`tool/gen_syndrome_retirement.py` 由本文件生成三份产物。
//
// ★★ **2026-10-05（层 2 单轨收口批）：三份产物全部退役。**
// 项目改为**单轨 ID**（号码一旦分配便永不复用），于是：
//   · ① `kSyndromeMergeMap` + `effectiveSyndromeId` **整张删除**
//     （`syndrome_registry.dart`），归一语义不复存在
//   · ② v46 迁移**退役**（`database.dart` 调用点删除）—— 它那张平铺表
//     **含** recycled 3 条，单轨下执行会把撞文同质化症的历史数据静默
//     改成「对话疲劳症」
//   · ③ 豁免集合改为**空集**（单轨下无「合法legacy 编号」可言）
//
// ⇒ **本文件现在是纯历史文档**：它回答「`P005` 这个字符串历史上是什么」
// （而这正是单轨要**永久禁止**再发生的事）。git 历史里已有一份，
// 保留在代码里是为了让后来者不必考古。
//
// ▸ 若将来要分配新号，**先查本文件**：某个号若出现在 `kSyndromeRetirement`
//   的 `oldId` 里，说明它历史上承载过别的实体 ⇒ **绝不复用**。
//   这是单轨纪律的**唯一**执行入口（无机器强制，靠人查）。
// ─────────────────────────────────────────────────────────────

/// 退役动作类型 —— **决定这条进哪张产物表**。
enum RetirementKind {
  /// 纯改号：旧号与目标号指同一个实体，实体本身还活着（0.3.6 重编号产生）。
  renumber,

  /// 实体合并：0.3.6 把这条记录标 `retired: true`，
  /// 其识别点/技法/动作被并入**另一个**实体 ⇒ 旧名与目标名不同。
  merge,

  /// ghost 号：早于注册表起点，旧名不可考（git 历史里没有这条记录）。
  ghost,

  /// 槽位曾待复用为**新症候**（ADR-0003 阶段一，2026-10-05 已实际复用）。
  /// ⚠️ 这三条是**同号跨代**的活样本，也是单轨收口决定性理由的来源：
  ///   旧 `P035` = 对话注水症（并入 P009）· 现行 `P035` = **撞文同质化症**
  ///   旧 `P036` = 流水账叙述症（并入 P004）· 现行 `P036` = **细节失真症**
  ///   旧 `P037` = 心理内耗症（并入 P026）· 现行 `P037` = **故事核缺失症**
  /// 同一个字符串，程序**无法判别**拿到的是哪一代（§4-136 编码碰撞）。
  /// ⇒ 单轨之后「同号不同代」被永久禁止，见文件头。
  recycled,
}

/// 一条退役档案。
class SyndromeRetirement {
  /// 退役的 ID（历史数据里存的就是它）。
  final String oldId;

  /// 退役时的名字。**可为 null**（ghost 号不可考）。
  final String? oldName;

  /// 并入的目标 ID（必是**现行注册表**里的 ID）。
  final String mergedInto;

  /// 这次退役属于哪一类（决定进哪张产物表）。
  final RetirementKind kind;

  const SyndromeRetirement(
    this.oldId,
    this.oldName,
    this.mergedInto,
    this.kind,
  );

  @override
  String toString() =>
      'S(\'$oldId\', ${oldName ?? 'null'}, \'$mergedInto\', '
      'RetirementKind.${kind.name})';
}

// dart format off
/// ⚠️ **唯一手写真源** —— 下列 50 条是全量（4 ghost + 31 renumber + 12 merge
/// + 3 recycled），由 `tool/gen_syndrome_retirement.py` 生成三份产物。
/// 增删退役记录**只改这里**，不要改产物。
///
/// ⚠️ **`dart format off` 是必需的，不是可选的**（实测踩过）：
///   带括号长名的两条（`P004` / `P009`）行长远超 80 列，format 会把它拆成
///   「每参数一行 + 尾随逗号」的多行形态 ⇒ 生成器的逐条正则匹配不到它们
///   ⇒ **静默丢 2 条**（实测解析数 50 → 48），而产物里它们还在，
///   `--check` 只会报「漂移」，看不出真因。
//   `parse_archive()` 里那道「解析数 == 源码字面条数」的守卫就是为拦截它而加的。
const List<SyndromeRetirement> kSyndromeRetirement = [
  // ── ghost 号（4 条）：早于注册表起点，旧名不可考 ──
  SyndromeRetirement('H001', null, 'P011', RetirementKind.ghost),
  SyndromeRetirement('H002', null, 'P011', RetirementKind.ghost),
  SyndromeRetirement('P001', null, 'P002', RetirementKind.ghost),
  SyndromeRetirement('P002', null, 'P007', RetirementKind.ghost),

  // ── 纯改号（31 条）：旧名与目标名一致，实体未变 ──
  SyndromeRetirement('P003', '情绪标签化', 'P001', RetirementKind.renumber),
  SyndromeRetirement('P004', '信息倾泻症（含原 P001 世界观膨胀子类型）', 'P002', RetirementKind.renumber),
  SyndromeRetirement('P005', '视角漂移', 'P003', RetirementKind.renumber),
  SyndromeRetirement('P006', '节奏停滞', 'P004', RetirementKind.renumber),
  SyndromeRetirement('P007', '句式节奏单一', 'P005', RetirementKind.renumber),
  SyndromeRetirement('P008', '语言堆砌', 'P006', RetirementKind.renumber),
  SyndromeRetirement('P009', '角色空心化（含原 P002 角色工具化症状）', 'P007', RetirementKind.renumber),
  SyndromeRetirement('P010', 'OC 平面化', 'P008', RetirementKind.renumber),
  SyndromeRetirement('P011', '对话疲劳症', 'P009', RetirementKind.renumber),
  SyndromeRetirement('P012', '张力不足症', 'P010', RetirementKind.renumber),
  SyndromeRetirement('P013', '开篇平庸症', 'P011', RetirementKind.renumber),
  SyndromeRetirement('P014', '结尾乏力症', 'P012', RetirementKind.renumber),
  SyndromeRetirement('P015', '高潮疲软症', 'P013', RetirementKind.renumber),
  SyndromeRetirement('P016', '情节巧合过多症', 'P014', RetirementKind.renumber),
  SyndromeRetirement('P018', '人设崩塌症', 'P015', RetirementKind.renumber),
  SyndromeRetirement('P020', '过渡生硬症', 'P016', RetirementKind.renumber),
  SyndromeRetirement('P021', '跳跃叙事/过度概括症', 'P017', RetirementKind.renumber),
  SyndromeRetirement('P022', '重复用词/基础语病', 'P018', RetirementKind.renumber),
  SyndromeRetirement('P026', '章节钩子缺失症', 'P019', RetirementKind.renumber),
  SyndromeRetirement('P027', '追读动力不足症', 'P020', RetirementKind.renumber),
  SyndromeRetirement('P028', '画面感缺失症', 'P021', RetirementKind.renumber),
  SyndromeRetirement('P030', '节奏比例失衡症', 'P022', RetirementKind.renumber),
  SyndromeRetirement('P031', '设定矛盾症', 'P023', RetirementKind.renumber),
  SyndromeRetirement('P032', '金手指失衡症', 'P024', RetirementKind.renumber),
  SyndromeRetirement('P038', '支线涣散症', 'P027', RetirementKind.renumber),
  SyndromeRetirement('P040', '被动主角症', 'P028', RetirementKind.renumber),
  SyndromeRetirement('P041', '降智反派症', 'P029', RetirementKind.renumber),
  SyndromeRetirement('P042', '声线漂移症', 'P030', RetirementKind.renumber),
  SyndromeRetirement('P043', '题材边界感缺失症', 'P031', RetirementKind.renumber),
  SyndromeRetirement('P046', '翻译腔/外来语干扰症', 'P032', RetirementKind.renumber),
  SyndromeRetirement('P049', '冲突未升级/模式重复症', 'P033', RetirementKind.renumber),

  // ── 实体合并（12 条）：0.3.6 标 retired:true，旧名与目标名不同 ──
  SyndromeRetirement('P017', '伏笔失效症', 'P012', RetirementKind.merge),
  SyndromeRetirement('P019', '情感失真症', 'P001', RetirementKind.merge),
  SyndromeRetirement('P023', '爽点乏力症', 'P013', RetirementKind.merge),
  SyndromeRetirement('P024', '期待感断裂症', 'P019', RetirementKind.merge),
  SyndromeRetirement('P025', '黄金三章失效症', 'P011', RetirementKind.merge),
  SyndromeRetirement('P029', '段落失控症', 'P005', RetirementKind.merge),
  SyndromeRetirement('P033', '升级节奏失衡症', 'P024', RetirementKind.merge),
  SyndromeRetirement('P039', '目标模糊症', 'P007', RetirementKind.merge),
  SyndromeRetirement('P044', '切入点选择偏差症', 'P011', RetirementKind.merge),
  SyndromeRetirement('P045', '驱动力套皮缺失症', 'P007', RetirementKind.merge),
  SyndromeRetirement('P047', '空评价词症', 'P001', RetirementKind.merge),
  SyndromeRetirement('P048', '语法层语病症', 'P018', RetirementKind.merge),

  // ── 槽位待复用（3 条）：ADR-0003 阶段一 ──
  // ⚠️ 不进 merge map（否则新槽位会被旧映射改写），但留在 v46 平铺表。
  SyndromeRetirement('P035', '对话注水症', 'P009', RetirementKind.recycled),
  SyndromeRetirement('P036', '流水账叙述症', 'P004', RetirementKind.recycled),
  SyndromeRetirement('P037', '心理内耗症', 'P026', RetirementKind.recycled),
// dart format on
];

/// **全部曾被使用过的 ID**（含 [RetirementKind.recycled]），50 条。
///
/// ★ 2026-10-05（层 2 单轨收口批）语义**已变**：
/// 它原本是护栏的「**合法 legacy 编号豁免集合**」—— 即「这些号虽然退役了，
/// 但在知识库/历史文本里被引用时不该报警」。
/// **单轨下这个概念不复存在**：号码永不复用 ⇒ 引用一个不在注册表里的号
/// 就是**缺陷**，不该豁免（豁免等于把缺陷藏起来）。
/// ⇒ 三个护栏的豁免集合已改为**空集**。
///
/// ▸ 本集合现在的唯一用途 = **单轨纪律的执行入口**（无机器强制，靠人查）：
///   分配新号前先查本集合，若某号在`oldId` 里 ⇒ 它历史上承载过别的实体
///   ⇒ **绝不复用**。
///
/// ⚠️ 特别提醒 `P035` / `P036` / `P037`（kind = `recycled`）：
///   它们**已经**被 ADR-0003 阶段一复用为现行实体（撞文同质化症 / 细节失真症 /
///   故事核缺失症）。这不是「待复用」，是「已复用」——
///   旧 P035（对话注水症）与现行 P035（撞文同质化症）**是两个不同实体**，
///   而程序拿到 `'P035'` 时**无法判别**是哪一个（§4-136 编码碰撞）。
///   v46 迁移的平铺表**至今仍含** `P035→P009` 这三条，
///   这正是它被退役的决定性理由（见 `database.dart` 的「v46 迁移退役说明」）。
Set<String> get kRetiredSyndromeIds => {
  for (final r in kSyndromeRetirement) r.oldId,
};
