# C3 书架页 + 作品详情页再设计变更说明

**日期**：2026-08-06
**批次**：C3（书架页 + 作品详情页再设计）
**关联计划**：[2026-08-05-writing-page-redesign.md](../plans/2026-08-05-writing-page-redesign.md)

---

## 变更概述

将 BookshelfPage 与 ManuscriptDetailPage 的视觉规范对齐 C1 WritingPage 已确立的月色竹青 + 百灵极简基线：AppBar 统一浅化（#F7F8F6 + 48dp + 深字 #2D3142）、卡片加 4dp 竹青左边框作为主色锚点、作品/章节序号色块统一竹青、删除冗余 FAB、章节卡片去阴影扁平化、状态标签矿物色定型。

## 改动文件

| 文件 | 改动类型 |
|------|---------|
| `lib/widgets/bookshelf_page.dart` | 修改（视觉规范对齐） |
| `lib/widgets/manuscript_detail_page.dart` | 修改（视觉规范对齐） |
| `test/widgets/bookshelf_page_test.dart` | 修改（追加 6 个视觉断言 V1-V6） |
| `test/widgets/manuscript_detail_page_test.dart` | 修改（追加 8 个视觉断言 V1-V8 + drift import） |

## 改动点

### BookshelfPage

| 改动 | 改造前 | 改造后 |
|------|--------|--------|
| AppBar | 深色 #2D5A52 + 白字 + 默认 56dp | 浅色 #F7F8F6 + 深字 #2D3142 + 48dp |
| Scaffold 背景 | 默认白色 | 冷青灰白 #F7F8F6 |
| 作品卡片 | #F2F4F2 + Border.all 浅灰 | #F2F4F2 + 左侧 4dp 竹青色条（ClipRRect + 内部 Container） |
| 图标色块 | 3 色轮换（竹青/松石/赭石） | 统一竹青 #2D5A52 |
| FAB | AppBar + FAB（列表非空时显示） | 移除（百灵极简：仅 AppBar + 入口） |

### ManuscriptDetailPage

| 改动 | 改造前 | 改造后 |
|------|--------|--------|
| AppBar | 深色 #2D5A52 + 白字 + 默认 56dp | 浅色 #F7F8F6 + 深字 #2D3142 + 48dp |
| Scaffold 背景 | 默认白色 | 冷青灰白 #F7F8F6 |
| 作品信息卡 | #F2F4F2 + Border.all 浅灰 | #F7F8F6 + 左侧 4dp 竹青色条（ClipRRect + 内部 Container） |
| 信息胶囊 | 白底 + 浅灰边框 + 松石绿字 | 浅竹青 #E8F0EE 底 + 竹青 #2D5A52 字 |
| 章节卡片 | 白底 + boxShadow（重） | 白底 + 浅灰边框（无阴影，百灵扁平风） |
| 章节序号色块 | 4 色轮换（竹青/松石/赭石/灰） | 统一竹青 #2D5A52 |
| 状态标签 - 草稿 | #F2F4F2 底 + #5B7565 字 | #E0E4E0 底 + #5B7565 字（矿物色定型） |
| 状态标签 - 修改中 | #FFF4E5 底 + #B45309 字 | 不变（已对齐矿物色） |
| 状态标签 - 完成 | #E8F0EE 底 + #2D5A52 字 | 不变（已对齐矿物色） |

## 关键技术决策

### 1. ClipRRect + 内部色条替代非均匀 Border

**问题**：Flutter 的 `Border` 在配 `borderRadius` 时强制要求所有 BorderSide 颜色一致，否则抛 `A borderRadius can only be given on borders with uniform colors`。

**方案**：左侧 4dp 竹青色条改为 `Container(width: 4, color: 竹青)` 嵌入 `IntrinsicHeight + Row(crossAxisAlignment: stretch)`，外层用 `ClipRRect` 包裹带圆角的 Container。

**测试断言**：用 `find.byWidgetPredicate` 检查 `w.constraints?.maxWidth == 4 && w.color == 竹青`（Container 的 width 参数会通过 `BoxConstraints.tightFor` 转化为 constraints 属性）。

### 2. 测试断言用 minWidth / 圆角精确匹配

为避免把卡片底色 Container 误匹配为图标色块，#V4 谓词加入 `borderRadius.topLeft.x == 8.0` 精确匹配图标色块的圆角 8（卡片本身圆角 12 被排除）。

## 影响分析

### 用户视角
- **视觉统一**：C1 WritingPage / C3 Bookshelf / C3 ManuscriptDetail 三个页面的 AppBar 与背景色完全一致
- **主色锚点强化**：每张卡片左侧 4dp 竹青色条强化品牌记忆
- **百灵极简**：删除 BookshelfPage 冗余 FAB，与"功能全收菜单"理念一致

### 开发者视角
- **不涉及数据层**：ManuscriptStore / ChapterStore / Repository 全部未改
- **不涉及路由**：app_router.dart 未改
- **测试可读性**：视觉断言独立 group，与功能测试分离，便于维护

## 验证结果

### 四闸
| 闸 | 命令 | 结果 |
|---|------|------|
| 闸 1 | `flutter analyze` 4 文件 | ✅ No issues found |
| 闸 2 | `dart format --set-exit-if-changed` 4 文件 | ✅ 已落盘（3 文件漂移已修复） |
| 闸 3 | `flutter test` 全量 | ✅ 286 通过 / 1 pre-existing `persistAttitude` 失败（按铁律勿修） |
| 闸 4 | 文档同步 | ✅ 本日志 |

### 新增测试清单（共 14 个视觉断言）

**BookshelfPage（6 个）**：
- V1 AppBar 浅色 #F7F8F6 + 48dp + 深字 #2D3142
- V2 Scaffold 背景 #F7F8F6
- V3 作品卡片左侧 4dp 竹青色条
- V4 作品图标色块统一竹青 #2D5A52
- V5 列表非空时无 FAB
- V6 空状态时也无 FAB

**ManuscriptDetailPage（8 个）**：
- V1 AppBar 浅色 #F7F8F6 + 48dp + 深字 #2D3142
- V2 Scaffold 背景 #F7F8F6
- V3 作品信息卡左侧 4dp 竹青色条
- V4 信息胶囊背景 #E8F0EE
- V5 章节卡片无阴影
- V6 章节序号色块统一竹青 #2D5A52
- V7 状态标签矿物色：草稿 #E0E4E0
- V8 状态标签矿物色：完成 #E8F0EE

## 回滚步骤

```bash
cd d:/teacher/yuesheng-flutter
git revert <commit-sha>
```

或手动恢复 4 个文件到上一提交状态。

## 已知遗留（非本批次范围）

- 全项目无 `darkTheme`：所有色值硬编码浅色，深色模式适配作为独立批次统一推进
- pre-existing `dao_repository_test.dart persistAttitude` 测试失败：student_model 表相关，与本批次改动无关
- 书架页未显示作品总字数：Manuscript 表无总字数字段，需 ChapterStore 提供聚合，作为后续批次补
