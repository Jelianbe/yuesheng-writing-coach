// ─────────────────────────────────────────────────────────────
// 症候元数据注册表（真源，b9 批次27）
// 设计稿：docs/2026-08-11-b9-syndrome-registry-design.md
//
// 本文件是症候「元数据」的唯一真源：
//   - 增删症候 = 在此增删一条 SyndromeRecord（另需编写手册段 + 训练段）
//   - 各库 markdown 表格行 / 计数 / ID 列表 / 测试断言从此派生
// 内容型段落（手册正文/训练知识/重叠规则）不在此处，保留各库人工编写。
//
// 0.3.6+10：聚类去重后彻底删除被合并的 14 个症候，不再保留退役标记；
// 33 个存活症候按旧 ID 升序连续重编号为 P001–P033。
//
// ★ 2026-10-05（层 2 单轨收口批）：**读路径归一已整张删除**。
// 本项目现在走**单轨 ID**——现行编号 P001–P038。
// ★ ADR-C147（2026-10-11）修正「永不复用」纪律：renumber/merge 腾空的号
//   （P038–P049 内容已并入现行 P001–P037）可复用；只有 ghost 号（H001/H002）永不复用。
// 历史沿革见 `syndrome_retirement.dart`（纯文档，运行时零消费）与 git 历史。
// ─────────────────────────────────────────────────────────────

// ADR-C70：原本 import 的是 syndrome_skill_levels.dart，但那边反过来依赖
// 本文件的 kSyndromeSkillLevelsDerived，形成循环。这里只需要 SkillLevel
// 这个类型，改指向类型层文件即解开——依赖变为 registry → types（单向）。
import 'syndrome_skill_types.dart'; // SkillLevel

// ─── R-019 数据分片（≤300 行）：39 条 kSyndromeRegistry 记录字面量
// ★ 2026-11-15 `T-20261115-10` 拆册：类型层 → `syndrome_record.dart`；
//   记录分四片 → `syndrome_registry_records_p1..p4.dart`（`part of` 本库，
//   私有符号不外泄、零 API 面变化）。宿主只留拼接与派生。
export 'syndrome_record.dart'; // 转发类型：52 个外部 import 路径不变
import 'syndrome_record.dart';

part 'syndrome_registry_records_p1.dart';
part 'syndrome_registry_records_p2.dart';
part 'syndrome_registry_records_p3.dart';
part 'syndrome_registry_records_p4.dart';

/// 注册表（真源）：39 条（P001-P039），按 ID 升序。
/// 增删症候时：
///   - 新增：追加一条记录（ID 连续递增）+ 在症候库/训练库编写手册段与训练段
///   - 删减：删除记录 + 删对应手册段与训练段（勿复用 ID）
/// R-019 拆分：39 条记录字面量分四册（`part of` 本库），此处拼接。
final List<SyndromeRecord> kSyndromeRegistry = List.unmodifiable([
  ..._syndromeRegistryP1,
  ..._syndromeRegistryP2,
  ..._syndromeRegistryP3,
  ..._syndromeRegistryP4,
]);

// ── 派生（各库 / 测试消费）─────────────────────────────────

/// 全部症候 ID 有序列表（替代 skill_layers.syndromeIds 与
/// training_knowledge_base.kTrainingSyndromeIds 的手写列表）
List<String> get kSyndromeIds =>
    List.unmodifiable(kSyndromeRegistry.map((s) => s.id));

/// 「逻辑性弱」因果链成员（ADR-C146 §2.2）。
///
/// 成员：P007 角色空心化（动机缺失）→ P016 过渡生硬 → P017 跳跃叙事/过度概括
/// → P036 细节失真（常识逻辑断裂）。这四条是「作者内容逻辑性弱 → 事件发展
/// 描写显得莫名其妙 → 读起来稀碎」这条因果链的四个环节。
///
/// ⚠️ 这些症候的 [SyndromeRecord.presentationGroup] 仍填**主身份组**
/// （P007→character / P016/P017→plot / P036→description），本常量只表达
/// 「同属一条逻辑链」的交叉语义，供「同源提示」判定（当同一段文本命中
/// ≥2 条本链成员时，在自然说明点出「这几条其实同源」）。见 ADR-C146 §4.2。
const List<String> kLogicChainSyndromeIds = ['P007', 'P016', 'P017', 'P036'];

/// 按症候 ID 反查呈现分组（ADR-C146）。查不到返回 null（调用方自行兜底，
/// 例如历史号 / 未收录号）。这是**静态映射**，模型不输出此字段。
PresentationGroup? presentationGroupOf(String syndromeId) {
  for (final s in kSyndromeRegistry) {
    if (s.id == syndromeId) return s.presentationGroup;
  }
  return null;
}

/// 按症候 ID 反查作用维（T-20261110-12）。查不到返回 null（调用方自行兜底，
/// 例如历史号 / 未收录号 ⇒ 04 空态口径「只显示症候名、不编造 role」）。
/// 静态映射，模型不输出此字段。
String? roleOf(String syndromeId) {
  for (final s in kSyndromeRegistry) {
    if (s.id == syndromeId) return s.role;
  }
  return null;
}

/// 按症候 ID 反查「量」维度标签（诊断维度改进方案 §2.1）。
/// 查不到或该症候无量维度 ⇒ 返回 null（调用方自行兜底）。
/// 静态映射，模型不输出此字段。
QuantityTag? quantityTagOf(String syndromeId) {
  for (final s in kSyndromeRegistry) {
    if (s.id == syndromeId) return s.quantityTag;
  }
  return null;
}

// ★ 2026-10-05（层 2 单轨收口批）：`kSyndromeMergeMap` 与 `effectiveSyndromeId`
// **已整张删除**。本项目现在走单轨 ID —— 号码一旦分配便永不复用，
// 于是「读到历史号时该归一到哪」这个问题不再存在。
//
// 为什么能删（不是「缓解」而是「源头消失」）：
// 映射表存在的原因是 0.3.6 的纯代码重编号（`e64096db`）留下了同号跨代
// 复用 —— 同一个 `P005` 既是旧「视角漂移」又是现行「句式节奏单一」，
// 程序拿到字符串时无从判别年代。50 条档案里 36 条与现行 ID 编号空间重叠。
// 单轨之后：历史号永不复用 ⇒ 新的重叠不会发生 ⇒ 映射表失去存在理由。
//
// ⚠️ 改这段前先读`syndrome_retirement.dart`（退役档案，50 条，纯文档）——
//   它记录了每个旧号原来叫什么、并进了谁。**不再被任何运行时代码消费**，
//   但「P035 这个字符串历史上是别的东西」这条知识不能丢。
//
// ⚠️ 若将来要引入第二个编号段，**必须重新评估**：
//   跨前缀不会撞字符串，但「新号段的号会不会与历史号重复」是另一个问题。
//   （单轨裁定 2026-10-05 / §4-167：当前决定不启用第二个前缀。此处保留的是
//   「若将来真要引入时的复核义务」，不是对它的预告。）

/// 症候 → 技能层级映射（四库一致性测试的权威集合来源）
Map<String, SkillLevel> get kSyndromeSkillLevelsDerived => {
  for (final s in kSyndromeRegistry) s.id: s.level,
};

/// 症候 → 推荐技法映射（替代 technique_knowledge_base.kTechniquesBySyndrome）
Map<String, List<String>> get kTechniquesBySyndromeDerived => {
  for (final s in kSyndromeRegistry) s.id: s.techniques,
};

/// 按 ID 查注册表记录（未知 → null）
SyndromeRecord? syndromeRecordOf(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final s in kSyndromeRegistry) {
    if (s.id == id) return s;
  }
  return null;
}

/// 症候 ID → 显示名（**只精确匹配**；未知 → null）。
///
/// ★ 2026-10-05（层 2 单轨收口批）：legacy 归一回退**已删除**。
/// 理由：回退分支处理的是「LLM 偶发输出历史旧编号」（如 `P048` 语法层语病症
/// → `P018` 重复用词/基础语病）。单轨下**这种输入本身就是缺陷** —— 若模型
/// 吐出一个不在注册表里的号，正确处置是让它**被拒**（`diagnosis_parser`
/// 的 `syndrome_id_format`），而不是猜一个名字回填。
/// 保留回退会掩盖问题：V-03 把越界编号替换成「【症候】」占位符是**底线**
/// （编号不外泄），而回退分支会让越界号看起来像已知号。
///
/// 消费方：diagnosis_validator 的 V-03 编号回填（P0'-3，2026-09-30）。
String? syndromeNameOf(String? id) => syndromeRecordOf(id)?.name;

/// 判据名按 code 取的**共享单一真源查询**（R-027 批，L-TCH/L-INJ 共用）。
///
/// 与 [syndromeNameOf] 同实现（精确匹配，未知 → null）；单独命名以便
/// 「学员话术 / F-block 注入」一律经此入口取判据全名，杜绝手抄判据名
/// （P034「指称歧义 vs 代词指代不清」、P018「带症/不带症」式漂移）。
/// 学员侧/注入侧改名只需改本注册表一处，消费方自动跟随。
String? syndromeNameFor(String? code) => syndromeRecordOf(code)?.name;

/// 判据对象在**创作前提层**（全书题材定位），单章窗口与分块窗口都无位置、
/// 且动作目录里没有同域动作可治的症候 ID ⇒ **退出诊断注入面**（两链都不报）。
/// ⚠️ 不删库常量里的行、不删手册段（`four_libraries_consistency_test #1/行数` 护栏）。
/// 与 [kSingleChapterExcludedSyndromeIds] 的区别：那条只出单章短链、**merge 侧保留**；
/// 本条两链都出，合并出口同样过滤。当前成员仅 P031。
const Set<String> kNonDiagnosableSyndromeIds = {'P031', 'P022'};
