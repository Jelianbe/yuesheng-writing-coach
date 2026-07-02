# Sprint 18 技术债清单

> 创建：2026-07-02
> 来源：Sprint 18 完工 Reflect (D-050)
> 范围：8 项新债务（D-DEBT-30 ~ D-DEBT-37）

---

## 总览

| 编号 | 描述 | 优先级 | Sprint 19 候选 | 状态 |
|:----:|------|:------:|:--------------:|:----:|
| D-DEBT-30 | ChatPage 历史消息分页 | P2 | - | Open |
| D-DEBT-31 | ProjectSpacePage 雷达图数据源 | P2 | - | Open |
| **D-DEBT-32** | **4 子页 Store 实装** | **P1** | **✅ 候选** | Open |
| D-DEBT-33 | ProjectSpacePage 维度数据整合 | P2 | - | Open |
| **D-DEBT-34** | **typedInvoke 全量覆盖审计** | **P1** | **✅ 候选** | Open |
| D-DEBT-35 | a11y moderate/minor 级别未处理 | P3 | - | Open |
| D-DEBT-36 | 视觉基线重建流程未文档化 | P3 | - | Open |
| D-DEBT-37 | Electron 端到端烟测未集成门禁 | P2 | - | Open |

---

## P1 债务详情

### D-DEBT-32 · 4 子页 Store 实装

**问题描述**：

Sprint 18 创建了 4 个新 Store 占位（ability/growth/prescription/retro），
但子页面（成长报告/训练计划/技法库/素材库）显示"数据加载中…"，
Store action 已就位但 SQLite 查询未实装。

**当前 Store 接口**：
- `useGrowthStore.fetchGlobalTrends()` — 拉全局成长趋势
- `useAbilityStore.fetchRadar(userId)` — 拉能力雷达
- `usePrescriptionStore.fetchList(userId)` — 拉训练处方列表
- `useRetroStore.fetchList(userId)` — 拉复盘记录列表

**修复目标**：
1. 各 Store 对应的 SQLite 表已存在（来自 migration 0XX 系列）
2. 实现 `service.XxxRepository.findAll/findByUserId` 域服务
3. 实现 IPC handler：`growth:getTrends`、`ability:getRadar` 等
4. 4 子页接入真实数据，替换"数据加载中…"占位

**预估工作量**：1.5 - 2 天
**依赖**：无（后端已就位）
**业务价值**：⭐⭐⭐⭐⭐（完成移动端 V1 数据流闭环）

---

### D-DEBT-34 · typedInvoke 全量覆盖审计

**问题描述**：

Sprint 18 升级的 3 个 Store（manuscript/session/project）已切到 typedInvoke，
但仍有 0 个直接 IPC 调用点散落在 renderer 组件中（4 子页硬编码"加载中…"
即是证据）。需要审计所有 `window.electronAPI.invoke` 直接调用点。

**修复目标**：
1. Grep `electronAPI.invoke` 找到所有直接调用点
2. 评估是否需要：(a) 走 typedInvoke (b) 走 Store (c) 删除（未使用）
3. 替换或删除，写入 1 个 PR
4. 设置 ESLint rule `no-restricted-syntax` 禁止新增直接调用

**预估工作量**：1 - 1.5 天
**依赖**：无
**业务价值**：⭐⭐⭐⭐（代码质量 + 类型安全 + IPC 白名单一致性）

---

## P2/P3 债务（简述）

### P2
- **D-DEBT-30**：ChatPage 加载全部历史消息，无分页，大数据量会卡
- **D-DEBT-31**：ProjectSpacePage 雷达图用 mock 数据，能力维度不真实
- **D-DEBT-33**：ProjectSpacePage 4 个 ID 维度（manuscriptId/projectId/trainingId/abilityId）未做统一收敛
- **D-DEBT-37**：Electron 端到端烟测未集成到门禁（Vite-only 跑通 ≠ Electron 跑通）

### P3
- **D-DEBT-35**：axe-core moderate/minor 级别违规未修复（critical/serious 已修）
- **D-DEBT-36**：设计 token 变更后视觉基线重建流程未文档化

---

## Sprint 19 推荐入口

按 R-004 优先级排序：

1. **D-DEBT-32**（P1）— 移动端 V1 数据流闭环
2. **D-DEBT-34**（P1）— 代码质量基础
3. **D-DEBT-30**（P2）— 性能基础
4. **D-DEBT-37**（P2）— 测试门禁完善
5. ...

Sprint 19 启动后，Phase B（IPC 管道优化）和 Phase C（交互设计）作为
后续候选排期。

---

*记录人：AI 复盘官*
*2026-07-02*
