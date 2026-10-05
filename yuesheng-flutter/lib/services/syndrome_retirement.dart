// ─────────────────────────────────────────────────────────────
// 症候退役档案（唯一手写真源 · 转换机层 1）
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
// ── 为什么不直接把 merge map 当真源 ──
// 因为三张表**不是同一种东西**（见 [RetirementKind]）：`merge map` 只装
// 「读路径仍需归一的键」，而 `v46 平铺表` 还必须装**已退役/已腾空**的键
// （它们是存量行里真实存在的旧号，清了就永久漏归一）。二者天然差几条。
// 手写两份就必须靠人记住「哪条进哪张」⇒ 本文件用 [RetirementKind] 显式记下。
//
// ── 四字段档案 ──
//   旧ID + 旧名 + 并入目标 + 动作类型
// ⚠️ `旧名` 可为 null：ghost 号早于注册表起点，git 历史里查不到
//   （实测 `git show e64096db^:…/syndrome_registry.dart` 最早只到 P003）。
//
// ── 分类判据（实测得出，勿凭直觉改）──
//   ghost    = 旧名不可考（P001/P002/H001/H002），4 条
//   merge    = **0.3.6 把它标了 `retired: true`**（查 `e64096db` 的注册表），
//              12 条 + P035/P036（后被 ADR-0003 阶段一腾空 ⇒ 改判 recycled）
//   renumber = 旧名与目标名一致 ⇒ 纯改号，实体未变，31 条
//   recycled = 槽位待复用为新症候（ADR-0003 阶段一），3 条
//
// ⚠️ v1 判据「旧名 != 目标名 ⇒ merge」**误判 2 条**：P004 / P009 的旧名带
//   括号补充说明（「信息倾泻症（含原 P001 世界观膨胀子类型）」），实体未变。
//   权威判据是 `retired: true` 标记，不是名字比较 —— 见 `.ai/DECISIONS.md`。
//
// ── 改动这里之后必须跑 ──
//   python tool/gen_syndrome_retirement.py          # 重生成三份产物
//   python tool/gen_syndrome_retirement.py --check  # 只验产物是否与本文件同步
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

  /// 槽位待复用：ADR-0003 阶段一要把这个号分配给**新症候**。
  /// ⚠️ 这类**绝不能进 merge map** —— 否则新槽位会被旧映射改写
  ///   （回到 M1 要消灭的串号）；但**必须留在 v46 平铺表**里，
  ///   因为存量库里仍有这些旧号的历史行。
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

/// **全部退役 ID**（含 [RetirementKind.recycled]）—— 护栏「合法 legacy 编号」
/// 豁免集合的真源。
///
/// ## 为什么护栏要用它，而不是 `kSyndromeMergeMap.keys`
///
/// merge map 只有 47 条，**缺 3 条 recycled**（P035/P036/P037）—— 那三个槽位
/// 即将被 ADR-0003 阶段一复用为新症候，不能留在读路径映射里。
/// 但它们**仍是合法 legacy 编号**：归一职责已移交 v46 迁移的平铺表，
/// 且知识库/注释里仍有历史提及（实测 `syndrome_kb_content_manual_2.dart:15`
/// 的消歧裁决失效说明、`training_few_shot_library.dart:101` 的
/// 「原 P035 已并入本症候」澄清）。
/// ⇒ 豁免集合的真源必须是「**所有仍可被归一的编号**」，即本集合（50 条）。
Set<String> get kRetiredSyndromeIds => {
  for (final r in kSyndromeRetirement) r.oldId,
};

/// **读路径仍需归一的退役 ID**（排除 [RetirementKind.recycled]）—— 47 条。
///
/// 与 `kSyndromeMergeMap.keys` 逐条相同（由生成器保证），此处供护栏断言用
/// （避免测试 import `database` 层形成反向依赖）。
Set<String> get kMergeMappedSyndromeIds => {
  for (final r in kSyndromeRetirement)
    if (r.kind != RetirementKind.recycled) r.oldId,
};
