# UI 打磨设计稿（月色竹青体系收敛）

> 对应：批次 22（UI/体验打磨）| 2026-08-11
> 背景：E2 界面审查已收敛主色/边框/文字色到 [app_theme.dart](../lib/config/app_theme.dart) 令牌。本批扫描发现 **3 处硬编码色值残留**未走令牌，破坏体系一致性；另评估 2 处体验优化（低风险）。

---

## 一、色值残留清单（硬编码 → 令牌）

### 1.1 AbilityChart 分数/趋势色（[ability_chart.dart](../lib/widgets/ability_chart.dart#L26-L36)）

| 位置 | 现值 | 问题 | 改为 |
|------|------|------|------|
| `scoreColor` score ≥80 | `Color(0xFF2E7D32)`（Material 绿） | 不在月色竹青/矿物色体系 | `AppColors.success`（新增令牌，见 §二） |
| `trendGlyph` improving | `Color(0xFF2E7D32)` | 同上 | `AppColors.success` |

### 1.2 SyndromeHistoryList 已解决色（[syndrome_history_list.dart](../lib/widgets/syndrome_history_list.dart#L140-L202)）

| 位置 | 现值 | 问题 | 改为 |
|------|------|------|------|
| 时间线圆点 `isResolved` | `Color(0xFF2E7D32)` | Material 绿越界 | `AppColors.success` |
| 「解决」徽章 `isResolved` | `Color(0xFF2E7D32)` | 同上 | `AppColors.success` |

### 1.3 路由层（[app_router.dart](../lib/router/app_router.dart)）

| 位置 | 现值 | 问题 | 改为 |
|------|------|------|------|
| 错误页图标 L59 | `Color(0xFFB91C1C)` | 体系外红，应统一矿物红 | `AppColors.danger` |
| 底部导航背景 L246 | `Color(0xFFF7F8F6)` | 硬编码重复 background | `AppColors.background` |
| 底部导航指示器 L247 | `Color(0xFFE8F0EE)` | 硬编码重复 primarySoft | `AppColors.primarySoft` |

---

## 二、新增令牌：success（正向色，体系内补全）

月色竹青体系目前缺「成功/正向」语义色。能力 ≥80 分与症候「已解决」都用 Material 绿 `#2E7D32`，与竹青体系不协调。

**方案**：在 [app_theme.dart](../lib/config/app_theme.dart) 新增：

```dart
// ── 正向色（成功/已解决，矿物色系延伸）──
static const Color success = Color(0xFF3E7C5B); // 正向绿（深青偏绿，与竹青同色调系）
static const Color successBg = Color(0xFFE6F0E9); // 正向淡底（L1 同族）
```

**选择依据**：
- `#3E7C5B` 与竹青 `#2D5A52` 同属青绿系（H 120-160°），保持"月色竹青"整体观感，而非跳入 Material 纯绿
- 对比度：`#3E7C5B` on 白 ≈ 4.9:1（AA 达标）
- 与矿物色 L1 淡青底 `#E8F0EE` 同族，新增 `successBg` 用于未来正向徽章/横幅

**影响面**：仅 3 处硬编码替换 + 2 个新常量，零功能改动。测试不断言颜色（已核验 growth_detail_components_test 仅断言文案），零回归风险。

---

## 三、体验优化评估（可选，默认不做）

扫描中顺带确认的项目当前状态，**无紧急项**：

| 项 | 现状 | 结论 |
|----|------|------|
| prefers-reduced-motion | 批次 6.1 已统一接入 4 处动画 | 已完成 |
| 状态色统一 | danger/warning 已矿物化，废弃 Material 默认红 | 已完成 |
| 主要页面令牌引用 | growth_page/chat_header/attitude_banner 等均走 AppColors | 一致 |

> 不追加额外视觉重设计——功能已饱和，本批收敛色值残留即达成「打磨」。

---

## 四、实施范围与验证

1. **改**：`app_theme.dart`（+success/successBg）、`ability_chart.dart`（2 处）、`syndrome_history_list.dart`（2 处）、`app_router.dart`（3 处）
2. **测试**：补 ability_chart / syndrome_history_list 色值断言（正向色 == AppColors.success）防回归
3. **四闸**：analyze 0 issues + 全量 test 通过
4. **commit**：批次 22，消息带「UI 打磨：月色竹青色值残留收敛」
