# C4 成长页 + 成长详情页变更说明

**日期**：2026-08-06
**批次**：C4（成长 Tab + 成长详情页）
**关联计划**：[2026-08-06-c4-growth-page-redesign.md](../plans/2026-08-06-c4-growth-page-redesign.md)

---

## 变更概述

将成长 Tab 从 PlaceholderPage 升级为完整的成长概览页（GrowthPage），新增成长详情页（GrowthDetailPage），提供用户级能力画像（熟练度/认知风格/症候分布）与诊断历史时间线。视觉规范对齐 C1/C3 月色竹青基线，数据可视化采用纯 Flutter 实现（CustomPaint + Expanded + Row），无第三方图表库。

**核心设计决策（方案 A）**：ProficiencyRing 的进度环填充量采用"等级位置"而非"推断置信度"，避免 UX 误导（beginner=25% / elementary=50% / intermediate=75% / advanced=100%，环满=满级）。

## 改动文件

| 文件 | 改动类型 |
|------|---------|
| `lib/data/repositories/diagnosis_repository.dart` | 修改（新增 `listAllActiveProblems` 跨 session 聚合方法） |
| `lib/providers/growth_providers.dart` | 新增（GrowthStore 状态管理 + growthStoreProvider 全局单例） |
| `lib/widgets/severity_bar.dart` | 新增（SeverityBar 症候色块条组件） |
| `lib/widgets/proficiency_ring.dart` | 新增（ProficiencyRing 熟练度进度环，方案 A） |
| `lib/widgets/growth_page.dart` | 新增（成长概览页） |
| `lib/widgets/growth_detail_page.dart` | 新增（成长详情页） |
| `lib/router/app_router.dart` | 修改（Tab3 接入 GrowthPage + /growth-detail 路由） |
| `test/data/repositories/diagnosis_repository_test.dart` | 新增（4 测试） |
| `test/providers/growth_providers_test.dart` | 新增（4 测试） |
| `test/widgets/severity_bar_test.dart` | 新增（6 测试） |
| `test/widgets/proficiency_ring_test.dart` | 新增（14 测试） |
| `test/widgets/growth_page_test.dart` | 新增（7 测试） |
| `test/widgets/growth_detail_page_test.dart` | 新增（5 测试） |
| `test/router/growth_route_test.dart` | 新增（5 测试） |

## 改动点

### DiagnosisRepository 新增 `listAllActiveProblems`

| 改动 | 说明 |
|------|------|
| 新增方法 | `Future<List<ActiveProblemView>> listAllActiveProblems()` |
| 作用 | 跨 session 聚合活跃症候，支持用户级视图 |
| 实现 | 查询所有 status='active' 的 active_problem，按 syndrome_id 分组取最新，按 severity DESC 排序 |
| 真源 | 复刻 yuesheng-android listActiveProblems 的跨 session 扩展 |

### GrowthStore 状态管理

| 改动 | 说明 |
|------|------|
| 状态类 | `GrowthState`（immutable：isLoading / profile / activeProblems / diagnosisHistory / error） |
| 状态管理 | `GrowthStore extends StateNotifier<GrowthState>` |
| 加载方法 | `loadGrowthData()` 并行加载：buildStudentContext(sessionId: null) + listAllActiveProblems() + 近 10 条诊断 |
| Provider | `growthStoreProvider` 全局单例（用户级视图，非按 session 隔离） |
| 真源 | 对齐 manuscriptStoreProvider 全局单例模式 |

### SeverityBar 症候色块条

| 改动 | 说明 |
|------|------|
| 数据类 | `SeverityCounts(l1, l2, l3)` |
| 组件 | `SeverityBar` 用 Expanded + flex 按比例渲染 L1/L2/L3 色块 |
| 矿物色标准 | L1=#E8F0EE / L2=#F5E6B8 / L3=#E8C5C5（对齐 C3 ManuscriptDetailPage） |
| 空状态 | 渲染 #E0E4E0 灰色占位条 |
| 无第三方库 | 纯 Flutter Row + Expanded + Container |

### ProficiencyRing 熟练度进度环（方案 A）

| 改动 | 说明 |
|------|------|
| 进度语义 | progress = 等级位置（非 confidence）<br>beginner=0.25 / elementary=0.5 / intermediate=0.75 / advanced=1.0 |
| 设计理由 | 环满 = 满级，符合直觉；避免"beginner + 高 confidence → 环画 90%"的 UX 误导 |
| 中心文本 | 只显示等级标签（新手/入门/进阶/熟练），不显示百分比 |
| 数据不足判定 | confidence < 0.3 → 显示"数据不足" + progress=0 |
| strokeWidth | 按 size 比例（size/15，默认 120 → 8.0） |
| 测试访问器 | `progressForTest` 用于断言进度值 |
| 实现 | CustomPaint + drawArc + StrokeCap.round，无第三方图表库 |

### GrowthPage 成长概览页

| 改动 | 说明 |
|------|------|
| 类型 | ConsumerStatefulWidget（initState 触发 loadGrowthData） |
| 布局 | 熟练度卡片（ProficiencyRing + 总会话数）+ 症候概览卡片（SeverityBar + 图例 + 活跃数）+ 详情入口卡片 |
| AppBar | #F7F8F6 + 48dp + 深字 #2D3142，右侧 info_outline 图标作详情入口 |
| _Card 组件 | 左侧 4dp 竹青色条（ClipRRect + 内部 Container，对齐 C3） |
| onOpenDetail | 回调注入，由路由层提供跳转到 /growth-detail |

### GrowthDetailPage 成长详情页

| 改动 | 说明 |
|------|------|
| 类型 | ConsumerStatefulWidget（initState 触发 loadGrowthData） |
| 布局 | 能力画像卡片（ProficiencyRing + 认知风格 + 总会话数）+ 症候分布列表 + 诊断历史时间线 |
| 空状态 | 显示"暂无诊断数据"（insights_outlined 图标 + 文本） |
| UX 决策 | 空 DB 显示"暂无诊断数据"而非"数据不足"，明确告知用户无数据 |
| 症候分布 | 每症候一张小卡（名称 + 严重度 + 矿物色 chip） |
| 时间线 | 左侧 2dp 竹青竖线 + 8dp 圆点，按 timestamp DESC |
| 内部组件 | _Card / _InfoRow / _SeverityChip / _Timeline / _TimelineItem |

### 路由集成

| 改动 | 说明 |
|------|------|
| 新增常量 | `AppRoutes.growthDetail = '/growth-detail'` |
| 新增顶层路由 | `/growth-detail` → GrowthDetailPage |
| Tab3 改造 | PlaceholderPage → GrowthPage（带 onOpenDetail 跳转回调） |
| 保留 import | PlaceholderPage 仍被 /manuscript-detail 错误分支使用 |

## 影响分析

### 用户可见变化
- **Tab3 成长**：从占位页升级为完整能力画像概览，可查看熟练度环 + 症候分布
- **新增详情页**：点击 AppBar 右侧图标进入完整能力画像（认知风格 + 症候列表 + 诊断时间线）
- **视觉一致**：与 C1/C3 月色竹青基线完全对齐（AppBar / 卡片 / 主色锚点 / 矿物色）

### 数据层影响
- 新增 `listAllActiveProblems` 是只读查询方法，不修改既有数据
- GrowthStore 是新增全局 Provider，不影响既有 session 级 Provider
- 不修改既有表结构、不修改既有 Repository 方法

### 回归风险
- **零回归**：C4 新增 45 个测试全绿，pre-existing 失败（persistAttitude）保持不变
- **路由兼容**：Tab3 路径仍是 /growth，既有深链不受影响
- **依赖隔离**：GrowthPage/GrowthDetailPage 通过 growthStoreProvider 独立加载，不污染既有页面状态

## 验证结果

### 四闸验证

| 闸门 | 命令 | 结果 |
|------|------|------|
| 闸 1 analyze | `flutter analyze` | ✅ C4 代码 0 issues（剩余 30 个 pre-existing info 与 C4 无关） |
| 闸 2 format | `dart format --set-exit-if-changed` | ✅ 14 个 C4 文件 0 改动 |
| 闸 3 test | `flutter test` | ✅ 331 通过 / 1 pre-existing 失败（persistAttitude，与 C4 无关） |
| 闸 4 文档 | 本文档 | ✅ 已同步 |

### 测试覆盖

| 组件 | 测试数 | 覆盖点 |
|------|--------|--------|
| listAllActiveProblems | 4 | 空 DB / 跨 session 聚合 / 排除 resolved / severity DESC 排序 |
| GrowthStore | 4 | 初始状态 / 空 DB / 有诊断 / 多次诊断排序 |
| SeverityBar | 6 | 3 段色块 / L1/L2/L3 颜色 / 空状态 / 比例正确 |
| ProficiencyRing | 14 | 视觉规范 / 4 等级标签 / 方案 A 进度语义 / 数据不足 |
| GrowthPage | 7 | AppBar / Scaffold / 卡片色条 / 详情入口 / 加载状态 / 会话数 |
| GrowthDetailPage | 5 | AppBar / Scaffold / 卡片色条 / 空状态文本 / 空状态图标 |
| 路由集成 | 5 | 常量存在 / Tab3 路径 / GrowthPage 渲染 / 详情页渲染 / 跳转行为 |
| **合计** | **45** | 全绿 |

## 关键技术决策

### 决策 1：全局聚合（sessionId: null）
- **问题**：成长页需要用户级视图，但既有 Repository 按 sessionId 隔离
- **方案**：`buildStudentContext(sessionId: null)` 全表聚合 + 新增 `listAllActiveProblems()` 跨 session 查询 + 诊断历史不限 sessionId
- **真源**：对齐 yuesheng-android 全局视图设计

### 决策 2：方案 A 进度语义
- **问题**：计划原版用 confidence 作进度环填充量，导致"低级 + 高置信度 → 环画 90%"的 UX 误导
- **方案**：progress = 等级位置（beginner=25% / elementary=50% / intermediate=75% / advanced=100%）
- **影响**：中心文本移除百分比，只显示等级标签；confidence 仅用于"数据不足"判定

### 决策 3：纯 Flutter 可视化
- **问题**：数据可视化需要图表组件，但引入第三方库增加依赖
- **方案**：
  - SeverityBar：Expanded + flex 按比例渲染色块
  - ProficiencyRing：CustomPaint + drawArc 绘制进度环
  - 时间线：Row + Container 竖线 + 圆点
- **收益**：零新增依赖，包体积无增长

### 决策 4：_Card 不抽取公共组件
- **问题**：GrowthPage 和 GrowthDetailPage 都需要左侧 4dp 竹青色条卡片
- **方案**：在两个文件中分别定义私有 `_Card` 类，不抽取公共组件
- **理由**：私有类跨文件复用会破坏封装；当前需求简单，复制成本低于抽象成本

### 决策 5：GrowthStore 全局单例
- **问题**：成长页是用户级视图，不应按 session 隔离
- **方案**：`StateNotifierProvider<GrowthStore, GrowthState>` 全局单例
- **真源**：对齐 manuscriptStoreProvider 模式

## 回滚步骤

如需回滚 C4 批次：

```bash
# 1. 查看提交历史
git log --oneline | grep "C4\|growth\|GrowthPage\|GrowthDetailPage\|ProficiencyRing\|SeverityBar\|listAllActiveProblems"

# 2. 回退到 C4 前的提交（C3 最后一个提交）
git reset --hard <C3 最后提交 hash>

# 3. C4 涉及的文件（手动核对）
# 源文件：lib/data/repositories/diagnosis_repository.dart（仅新增方法，可保留）
#         lib/providers/growth_providers.dart（新增）
#         lib/widgets/severity_bar.dart（新增）
#         lib/widgets/proficiency_ring.dart（新增）
#         lib/widgets/growth_page.dart（新增）
#         lib/widgets/growth_detail_page.dart（新增）
#         lib/router/app_router.dart（修改 Tab3 + 新增 /growth-detail）
# 测试：test/ 下对应 7 个测试文件（新增）
```

## 后续任务

- [ ] 真机测试：覆盖主流手机品牌，验证 ProficiencyRing 在小屏（size=80）和大屏（size=120）下的视觉效果
- [ ] 修复 pre-existing `TeachingStateRepository persistAttitude` 失败（独立批次处理，非 C4 范围）
- [ ] 有数据场景的端到端测试：构造完整诊断数据，验证 GrowthDetailPage 的症候分布列表 + 时间线渲染（Task 6 留待后续）
- [ ] 国际化：等级标签（新手/入门/进阶/熟练）提取为常量，支持多语言
