// ─────────────────────────────────────────────────────────────
// outline_shared — 大纲 UI 共享面（批次 N12：「大纲 Drawer 解绑」）
//
// ★ 为什么需要这个文件
//   以下三者原本都住在 `outline_drawer.dart`（写作页右侧抽屉）里，却被
//   **非抽屉**的消费方反向 import —— 一个 setting 页为了拿「类型展示序」，
//   竟必须依赖写作页的抽屉文件：
//     · `setting/outline_entity_list_view.dart:20`   （资料 Tab「大纲」子列表）
//     · `setting/outline_entity_detail_page.dart:23` （大纲实体详情页）
//   而 `_visibleStatuses` 与 `_typeLabel` 的查找循环，在上述消费点里
//   **各有一份逐字重复**（两份 `{'pending','active'}`、两份同样的 for 循环）。
//   ⇒ 本文件是这些「大纲 UI 共享面」的唯一落点：**数据层之上、具体承载之下**。
//
// 边界（刻意克制）：
//   · 只放**展示元数据与纯函数** —— 不放 Widget、不碰 DB、不读 Provider；
//   · 承载方式（抽屉 / 页面 / Tab）一律不在此处出现。
// ─────────────────────────────────────────────────────────────

/// 实体类型中文名 + 展示顺序（人物 → 设定 → 情节）。
///
/// ★ 语义（N6 起）：本表是**排序优先表**，**不是白名单**。
///   在表内 = 有专属分组（按其下标排序）；**不在表内不再被丢弃** ——
///   由 [outlineHasOwnGroup] 判定后归入 [kOutlineOtherGroupLabel] 分组。
///   ⇒ 动机见 `docs`/设计稿 §4.3：旧实现把它当白名单用，在「库里有一行、
///     但该类型不在表内」时，分组循环整圈 `continue` ⇒ 抽屉渲染成**一片空白**
///     （既无分组、也无空态文案），且**静默丢弃**了库里的行。
///
/// AI 侧白名单即 `character|setting|plot`（`services/outline_service.dart:68`）；
/// `volume` / `chapter` 虽已进入 `outline_entity` 的取值域（大纲结构化批次），
/// 但**当前无生产写入方**（唯一写入口 `outline_service.dart:210` 的
/// `update.type` 来自上述白名单）⇒ 二者不会出现在专属分组里；
/// 若因历史数据/人工写入而存在，由「其他」分组兜底展示（N6 之前是静默丢弃）。
///
/// ⚠️ `volume`/`chapter` **不进本表**：卷与章的真源是 `volumes` / `chapters`
/// 两张表，大纲视图以**只读投影**形态展示（设计稿 §2 路线 A）。
/// 把卷/章再写成 `outline_entity` 会同时引入**两处真源**、**唯一键撞名**
/// （`uniqueKeys` 是 `{manuscriptId, entityKey}`，不含 type）与 **prompt 改动**。
const List<({String type, String label})> kOutlineTypeOrder = [
  (type: 'character', label: '人物'),
  (type: 'setting', label: '设定'),
  (type: 'plot', label: '情节'),
];

/// 「其他」兜底分组的标签 —— 容纳**没有专属分组**的类型。
///
/// 与 [outlineTypeLabel] 的**原值回退**配套：分组标题固定为「其他」，
/// 而组内每张卡片用 [outlineTypeLabel] 打出该类型**原值**，使「有但认不出」
/// 与「真的没有」在界面上可区分（前者有分组、后者走空态）。
const String kOutlineOtherGroupLabel = '其他';

/// 类型是否有**专属分组**（即是否在 [kOutlineTypeOrder] 内）。
///
/// 返回 false 的类型**不得丢弃** —— 调用方须归入 [kOutlineOtherGroupLabel]。
/// 与「零命中」类教训同族（`DECISIONS §4-48`/`§4-49`）：**静默丢弃与
/// 「本来就没有」在界面上外观完全相同**，必须给出显式出口。
bool outlineHasOwnGroup(String type) {
  for (final g in kOutlineTypeOrder) {
    if (g.type == type) return true;
  }
  return false;
}

/// 大纲实体 / 印象**可展示**的状态。
///
/// `rejected`（用户显式否决）、`superseded`（被新印象取代）、`expired`
/// （清理置旧）三者均为**无效态**，一律跳过不展示。
/// 三处消费点（大纲抽屉的实体分组 / 抽屉的印象行 / 资料 Tab 大纲列表）共用本集，
/// 避免出现「一处放宽、另一处不放宽」的口径分叉。
const Set<String> kOutlineVisibleStatuses = {'pending', 'active'};

/// 类型 → 中文展示名；不在 [kOutlineTypeOrder] 内则**原样回退**类型值。
///
/// 回退而非抛错：未知类型（如 `volume` / `chapter`）在 UI 上宁可显示
/// 原值，也不要因为一个类型不认识就丢掉整张卡片。
/// N6 起该回退在**「其他」分组内的类型标签**上真正被用到（此前只声明未使用）。
String outlineTypeLabel(String type) {
  for (final g in kOutlineTypeOrder) {
    if (g.type == type) return g.label;
  }
  return type;
}
