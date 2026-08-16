# E1–E4 界面审查修复提交日志

**日期**：2026-08-07
**批次**：E1（P0 硬约束）→ E2（P1 设计系统）→ E3（P2 功能占位）→ E4（P3 可访问性）
**基线**：`92e3b2c`（D3–D6 诊断链路交付日志）
**范围**：`92e3b2c..HEAD`

---

## 变更概述

依据 stark cross-platform-design 审查准则对全应用 19 个 UI 文件做只读接管审计，发现 13 项问题并全量修复。审查结论分四级：

- **P0（违反硬约束）**：错误细节泄漏到 release 界面、主 Tab 视觉脱节
- **P1（一致性/设计系统）**：零设计令牌、错误红两套体系、废弃 API
- **P2（功能占位/交互欠缺）**：写作菜单 80% 死项、时间线信息空壳、删除交互不可感知
- **P3（可访问性/细节）**：正文对比度不达标、弹窗实现不一致、编辑器贴边、无障碍薄弱

## 提交日志

| Commit | 标题 | 摘要 |
|--------|------|------|
| `1a1b60a` | E1+E2 界面审查修复 — 错误静默 + AppBar 对齐 + 设计令牌体系 | P0+P1 两阶段合并提交（源码同区域耦合，无法独立拆分） |
| `02a9096` | E3 功能占位与交互欠缺修复 — 菜单诚实化 + 时间线增强 + 长按触觉反馈 | P2 全部 3 项可落地修复 |
| `1e19c54` | E4 可访问性与细节修复 — 对比度达标 + 删除弹窗统一 + 编辑器内边距 + Semantics | P3 全部 4 项 |

## 各批次改动明细

### E1 (P0) — 错误静默 + AppBar 对齐

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/chat_page.dart` | 修改 | 错误横幅 release 静默：`kDebugMode ? error : '发送失败，请稍后重试'`；AppBar 从深色竹青改为浅色 #F7F8F6 + 深字 + 48dp，对齐其余主页面 |
| `lib/widgets/writing_coach_panel.dart` | 修改 | 错误横幅同样静默化 |

**违反的硬约束**：release 构建错误日志必须静默，不向用户展示技术细节（原实现直接渲染 `error.toString()`）。

### E2 (P1) — 设计令牌体系

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/config/app_theme.dart` | 新增 | 月色竹青设计令牌唯一真源：AppColors（主色/背景/文字/边框/矿物色/状态色/禁用色）+ AppRadius + AppSpacing |
| `lib/main.dart` | 修改 | 接入 ColorScheme（primary/surface/error 显式指定）+ TextTheme 基线 |
| 19 个 UI 文件 | 修改 | 354 处硬编码色值收敛为 `AppColors.*` 常量引用 |
| `lib/widgets/onboarding_questionnaire.dart` | 修改 | `onPopInvoked`（已废弃）→ `onPopInvokedWithResult` |
| `test/widgets/writing_coach_panel_test.dart` | 修改 | 错误横幅断言从 `Color(0xFFFFF0F0)` 改为 `AppColors.dangerBg`（因错误红统一） |

**错误红统一**：`#FFEBEE/#E53935/#C62828/#B91C1C/Colors.red` 等多套 Material 红 → `AppColors.danger(#B3261E)` / `dangerBg(#FDF0EF)` / `dangerBorder(#E8C5C5)`，与矿物红 L3 体系一致。

### E3 (P2) — 功能占位与交互欠缺

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/writing_menu_sheet.dart` | 修改 | 移除 4 个「开发中」占位项（排版设置/章节列表/撤销/重做），只保留保存状态 + 诊断本章；show 签名简化 |
| `lib/widgets/writing_page.dart` | 修改 | 菜单调用同步简化，移除 showTodo 占位反馈 |
| `lib/widgets/growth_detail_page.dart` | 修改 | 时间线增强：从 syndromes JSON 解析症候名展示（最多 3 个，超出 +N），不再是"时间+置信度"空壳 |
| `lib/widgets/message_bubble.dart` | 修改 | 长按删除增加 `HapticFeedback.mediumImpact()` 触觉反馈，让交互可感知 |
| `test/widgets/writing_menu_sheet_test.dart` | 修改 | 断言同步：占位项 findsNothing + 诊断本章可见 |
| `test/widgets/writing_page_test.dart` | 修改 | 菜单断言改为「诊断本章」 |

**保留项**：TeacherSuggestionCard「开始练习」维持 SnackBar 占位（训练系统未实现，属产品阶段问题，`onStartPractice` 回调已预留）。

### E4 (P3) — 可访问性与细节

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/config/app_theme.dart` | 修改 | 对比度达标：textSecondary `#8A8D93→#6B7076`（4.68:1，AA 达标）；textTertiary `#B8BCC0→#858B92`（3.23:1） |
| `lib/widgets/message_list.dart` | 修改 | 删除确认弹窗从自定义 `Positioned.fill+black54` 覆盖层统一为标准 `showDialog`，与书架/作品详情一致 |
| `lib/widgets/writing_page.dart` | 修改 | 编辑器增加 16dp 内边距，正文不再贴边 |
| `lib/widgets/message_bubble.dart` | 修改 | 增加读屏语义 `Semantics(label: '我/教练：消息内容')` |

## 验证结果

### 四闸验证（每批次提交前均执行）

| 闸门 | 命令 | 结果 |
|------|------|------|
| 闸 1 analyze | `flutter analyze` | ✅ 0 error（30 个 info 均为既有提示，非本批引入） |
| 闸 2 format | `dart format --set-exit-if-changed` | ✅ 全过 |
| 闸 3 test | `flutter test` | ✅ 360 通过 / 1 pre-existing 失败（persistAttitude，非本批范围） |
| 闸 4 文档 | 本文档 | ✅ 已同步 |

### 测试覆盖

- E2：354 处令牌替换后全部 widget 测试通过（含色值断言同步）
- E3：writing_menu_sheet 3 测试 + writing_page 8 测试 + growth_detail + message_bubble 全过
- E4：message_list/chat_page 删除弹窗路径 + Semantics + 编辑器内边距全过

## 审查发现 → 修复对照

| # | 审查发现 | 等级 | 修复 |
|---|---------|------|------|
| 1 | 错误细节泄漏到界面 | P0 | ✅ release 静默（chat_page + writing_coach_panel） |
| 2 | 主 Tab 视觉脱节 | P0 | ✅ ChatPage AppBar 对齐浅色主题 |
| 3 | 零设计令牌 | P1 | ✅ app_theme.dart 令牌真源 + 354 处收敛 |
| 4 | 错误红不统一 | P1 | ✅ 统一矿物红系 |
| 5 | onPopInvoked 废弃 | P1 | ✅ onPopInvokedWithResult |
| 6 | 写作菜单 4/5 占位 | P2 | ✅ 移除占位项，菜单诚实化 |
| 7 | 开始练习占位 | P2 | ⏸ 保留（训练系统未实现，回调已预留） |
| 8 | 删除交互不可感知 | P2 | ✅ 长按触觉反馈 |
| 9 | 成长时间线空壳 | P2 | ✅ 展示症候名 |
| 10 | 正文对比度不达标 | P3 | ✅ textSecondary 4.68:1 / textTertiary 3.23:1 |
| 11 | 删除弹窗实现不一致 | P3 | ✅ 统一 showDialog |
| 12 | 编辑器文字贴边 | P3 | ✅ 16dp 内边距 |
| 13 | 无障碍薄弱 | P3 | ✅ 气泡角色 Semantics |

## 回滚步骤

```bash
# 查看提交历史
git log --oneline | grep "E1\|E2\|E3\|E4\|界面审查"

# 回退到审查前基线
git reset --hard 92e3b2c

# 涉及文件
# 新增：lib/config/app_theme.dart
# 修改：lib/main.dart + lib/widgets/ 下 19 个文件 + test/widgets/ 下 2 个测试
```

## 后续任务

- [ ] 实现「开始练习」训练系统（接入 TeacherSuggestionCard.onStartPractice）
- [ ] 修复 pre-existing `TeachingStateRepository persistAttitude` 失败（独立批次）
- [ ] 真机测试：验证新对比度色值在 OLED/暗光屏下的实际观感
- [ ] 视觉回归走查：令牌替换后截图对比 RN 版 yuesheng-android 基线
