// ─────────────────────────────────────────────────────────────
// schema_head — drift `schemaVersion` 的**测试侧单一钉值**
//
// 为什么存在：每次 bump 都连带改 N 处字面量（本仓已第 6 次）。收敛后只改
// **1 处**（本常量）+ 新增迁移块与它的新测试。裁定见 `.ai/DECISIONS.md §2`
// 「`schemaVersion` 下一次 bump 的落地形状」（2026-09-18，由 `N12-F3b` 触发落地）。
//
// 用法：
//   - 迁移测试断言「升到头」：`expect(..., kSchemaHead)`
//   - `test/widget_test.dart` 里「空库 `user_version == kSchemaHead`」那一例是
//     **唯一的钉值断言** —— 它证明本常量与**库真实开出来的**版本一致。
//     没有它，常量与 `AppDatabase.schemaVersion` 分叉时全仓测试仍会全绿。
//
// ⚠️ 本文件**不 import `lib/`**：避免把生产代码拉进无关测试的依赖面。
//    「与真源一致」由上述那 1 例断言保证，而不是靠 import。
//
// 历史（**只追加，不改写旧行** —— 旧行是「当时 head」的记录，不是待更新的值）：
//   12 → … → 27 → 28 → 29 → 31 → 32 → 33 → 34 → 35 → 36 → 37 → 38 → 39
//   40 → 41（ADR-C121 试点埋点表 pilot_metric_event）
//   41 → 42（C126 diagnosis_results 加 status 列 confirmed/pending/replaced）
//   42 → 43（ADR-C132 批1 写作修改事件表 edit_diff_event）
//   43 → 44（ADR-C143 书籍资料库：记录条目 record_entry / 资料条目 material_entry）
//   44 → 45（C147 记录条目加 target_section 列：作者自选归入位置人设/大纲/世界观）
//   45 → 46（ADR-0003 前置v46：三张表的 legacy 症候 ID 按 merge map 单跳归一）
// ─────────────────────────────────────────────────────────────

/// 当前 drift `schemaVersion`（= `AppDatabase.schemaVersion`）的测试侧镜像。
const int kSchemaHead = 46;
