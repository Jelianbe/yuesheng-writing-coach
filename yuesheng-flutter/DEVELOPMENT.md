# 月笙写作教练 · 开发文档

## 技术栈

| 层 | 技术 |
|:---|:-----|
| 框架 | Flutter + Dart |
| 状态管理 | Riverpod |
| 持久化 | drift（SQLite） |
| 样式 | 设计令牌体系（竹青 `#2D5A52` 色系，`lib/config/app_theme.dart`） |
| 测试 | Flutter test，2600+ 用例（255 个测试文件） |

## 项目结构

```
lib/
├── config/          # 主题/配色/动效常量
├── data/
│   ├── database/    # drift 表定义 + DAO
│   └── repositories/# 数据仓库层
├── services/        # 核心业务逻辑
│   ├── skill_registry.dart      # 症候 skill 注册表（L1/L2/L3 分层）
│   ├── syndrome_registry.dart   # 症候定义（41 条，P001-P041）
│   ├── chat_service.dart        # 对话主流程
│   └── diagnosis_service.dart    # 诊断引擎
├── widgets/         # UI 组件
└── types/          # 类型定义
```

## 快速开始

### 前置依赖

- Flutter SDK（稳定版）
- Android SDK（目标平台：Android 竖屏）

### 运行

```bash
flutter pub get
flutter run
```

### 测试

```bash
# 全量测试
flutter test

# 只跑某个测试文件
flutter test test/services/skill_prompt_anchor_test.dart

# 更新快照（改了 prompt 之后）
UPDATE_SNAPSHOTS=true flutter test test/services/skill_prompt_anchor_test.dart
```

## 质量门禁

六道门禁，`bash scripts/gate.sh` 一键全跑：

1. 代码格式（dart format）
2. 静态分析（flutter analyze）
3. 全量测试（2600+ 用例）
4. 循环依赖检查
5. 安全 / 密钥扫描
6. R-019 函数行数硬上限（≤50 行/函数）

工程纪律：最小必要范围改动、函数行数硬上限、密钥零硬编码、ADR 决策记录。

## 核心架构概念

- **五阶段教学状态机**：P0 初始 → P1 教学 → P2 训练 → P3 评估 → P4 复盘
- **症候驱动**：41 条写作症候，每条有独立的诊断逻辑 + 训练方法
- **Skill 分层**：L1 常驻（系统提示词）/ L2 按需加载 / L3 知识库佐证
- **态度档三档**：温和 / 锐利 / 严格，差异化语气和教学方式
- **学生画像**：基于诊断历史的自动推断 + 初始问卷补充

## 快照测试

| 快照 | 作用 |
|---|---|
| `skill_prompt_anchor_test.dart` | L1+L2+态度档 prompt 字节级基线 |
| `student_profile_anchor_test.dart` | 画像段 prompt 字节级基线 |
| `chat_service_message_sequence_anchor_test.dart` | 消息序列锚点 |

改 prompt 之后，先跑快照测试，确认变化是预期的。


---

## 批量操作注意事项

### ⚠️ PowerShell 处理 UTF-8 有坑

**事故记录**：2026-09-24，用 PowerShell 批量替换 import 路径，把所有 dart 文件的 UTF-8 编码搞坏了（GBK 误读 + 错误写回）。

**正确姿势**：
1. 批量改文件**不要用 PowerShell**——用 Python 脚本或 IDE 的全局替换
2. Python 处理 UTF-8 更可靠：`open(path, 'r', encoding='utf-8')` + `open(path, 'w', encoding='utf-8')`
3. 用 IDE（Android Studio）的 rename/refactor 功能——对 Dart 的 import 迁移是安全的
4. 大重构一定要小步提交：一个目录一个目录改，每步跑测试，别一次性全量替换
5. 改完先 `git diff --stat` 检查文件数和行数是否异常——编码坏了 git diff 会立刻显形

**教训**：工具事故 ≠ 架构风险。不要因为一次操作失误就放弃合理的重构。
