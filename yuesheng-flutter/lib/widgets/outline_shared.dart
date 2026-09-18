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
/// ⚠️ 本表覆盖的是**当前类型空间的全集**：AI 侧白名单即
/// `character|setting|plot`（`services/outline_service.dart:68`）。
/// `volume` / `chapter` 虽已进入 `outline_entity` 的取值域（大纲结构化批次），
/// 但**当前无生产写入方**（唯一写入口 `outline_service.dart:210` 的
/// `update.type` 来自上述白名单）⇒ 二者不在本表内、也不被任何大纲 UI 展示。
/// N6「大纲类型体系（volume/chapter）」开工时随实现一并扩展。
const List<({String type, String label})> kOutlineTypeOrder = [
  (type: 'character', label: '人物'),
  (type: 'setting', label: '设定'),
  (type: 'plot', label: '情节'),
];

/// 大纲实体 / 印象**可展示**的状态。
///
/// `rejected`（用户显式否决）、`superseded`（被新印象取代）、`expired`
/// （清理置旧）三者均为**无效态**，一律跳过不展示。
/// 三处消费点（大纲抽屉的实体分组 / 抽屉的印象行 / 资料 Tab 大纲列表）共用本集，
/// 避免出现「一处放宽、另一处不放宽」的口径分叉。
const Set<String> kOutlineVisibleStatuses = {'pending', 'active'};

/// 类型 → 中文展示名；不在 [kOutlineTypeOrder] 内则**原样回退**类型值。
///
/// 回退而非抛错：未知类型（如未来的 `volume` / `chapter`）在 UI 上宁可显示
/// 原值，也不要因为一个类型不认识就丢掉整张卡片。
String outlineTypeLabel(String type) {
  for (final g in kOutlineTypeOrder) {
    if (g.type == type) return g.label;
  }
  return type;
}
