# 月笙写作教练 — 内部真源索引

> 本文档是真源入口（`@@TRUTH:dev-docs/README.md@@`）。  
> 当源代码、测试、脚本、schema 和运行日志不足以决定时，以此索引指向的文档为准。

## 项目边界

- **产品**：Electron 桌面写作教练（月度会员订阅制），不做 Web 版、不做移动端
- **核心用户**：中学生/大学生 → 提升叙事写作能力
- **已否定方向**：硬编码话术模板、HTTP RESTful 后端拆为独立部署、IDE 编辑器模式（ChapterEditor 保留代码但入口已移除）
- **工作流**：Vibe-coding + 分阶段验收，非全职维护

## 核心文档索引

| 文档 | 路径 | 说明 |
|------|------|------|
| 教学状态机 | `src/shared/constants.ts` | 常量层 — 阶段/子阶段/子阶段名 |
| 前端合同 | `src/shared/types-teaching.ts` | SyndromeResult/EvidenceRecord 等核心类型 |
| 前端合同（训练） | `src/renderer/stores/training.types.ts` | TrainingTask/READING_STEPS/DEFAULT_STEPS |
| 教学路由 | `src/main/domains/teaching/strategy/router.ts` | decideRouting / decideReading |
| 引导状态机 | `src/main/domains/teaching/teaching-state/teaching-state-machine.guide.ts` | GUIDE 子阶段逻辑 |
| 训练库配置 | `resources/config/training-library.json` | 29 条训练条目 schema |
| 阅读库配置 | `resources/config/reading-library.json` | 5 条 preset 示例 |
| 症候类型映射 | `resources/config/syndrome-type-map.json` | discoverable 配置 |
| IPC 通道定义 | `src/shared/constants.ts` | `IPC_CHANNELS` 枚举 |

## 架构决策记录

见 [dev-docs/decisions/](./decisions/) — 所有 ADR 按编号顺序索引。

## 适配器层规范

项目技术栈约定，见 [dev-docs/adapters/](./adapters/)：

| 适配器 | 文件 | 管辖区 |
|--------|------|--------|
| React | `adapters/README.md §1` | 组件模式、hook、JSX 规则 |
| Electron IPC | `adapters/README.md §2` | 通道定义、handler 注册 |
| Zustand | `adapters/README.md §3` | Store 结构、action 边界 |
| CSS Modules | `adapters/README.md §4` | 设计 token、内联 style 禁令 |
| Vitest | `adapters/README.md §5` | 测试位置、mock 规范 |

## 健康/审计报告

| 报告 | 路径 |
|------|------|
| 前端体检报告 2026-06-15 | `docs/reports/daily-health/scan_2026-06-15.json` |
| 反例测试基线 | `output/test-reports/` |

## 门禁

在项目根目录执行以下命令进行验收：

```bash
npm run gate
# 等价于: tsc --noEmit && vitest run && eslint src/ --ext .ts,.tsx --max-warnings 300 && npx tsx scripts/check-a11y-colors.ts
```
