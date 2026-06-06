---
name: 月笙代码审查
description: 专为月笙写作教练项目设计的代码审查工具。检查 TypeScript 类型安全、Electron IPC 规范、Zustand Store 规范、诊断引擎特殊检查及项目规则合规性。适用于代码审查、PR 合并前、功能开发完成后。
---

# 月笙代码审查

## 触发场景
- 用户要求审查代码时
- 功能开发完成后
- PR 合并前
- 重构完成后

## 审查范围

### 1. TypeScript 类型安全

| 检查项 | 规则 | 严重度 |
|--------|------|--------|
| 类型定义 | 禁止使用 `any`，使用具体类型 | Error |
| 接口定义 | 接口使用 PascalCase | Warning |
| 枚举使用 | 优先使用 `as const` 而非枚举 | Info |
| 空值处理 | 使用可选链 `?.` 和空值合并 `??` | Warning |

### 2. Electron IPC 规范

| 检查项 | 规则 | 严重度 |
|--------|------|--------|
| 通道命名 | 使用 `domain:action` 格式（如 `chat:send`） | Error |
| 类型定义 | IPC 通道必须在 `shared/types.ts` 中定义 | Error |
| 错误处理 | 所有 IPC handler 必须有 try-catch | Error |
| preload 暴露 | 只暴露必要的 API，不暴露整个 ipcRenderer | Error |

### 3. Zustand Store 规范

| 检查项 | 规则 | 严重度 |
|--------|------|--------|
| 状态切片 | 每个 store 只管理一个领域状态 | Warning |
| 选择器 | 使用 `useStore(selector)` 避免不必要的重渲染 | Warning |
| persist | 配置需要持久化的状态，不持久化临时状态 | Error |
| 命名 | store 文件以 `.store.ts` 结尾 | Error |

### 4. 诊断引擎特殊检查

| 检查项 | 规则 | 严重度 |
|--------|------|--------|
| 信号权重 | 不能硬编码，必须从配置读取 | Error |
| 病症规则 | 新增病症必须更新 syndrome-manual | Error |
| 动作映射 | 新增动作必须更新 action-library | Error |

### 5. 项目规则合规

| 检查项 | 对应规则 | 严重度 |
|--------|---------|--------|
| 代码原子化 | R-001 | Warning |
| 最小化范围 | R-010 | Warning |
| 逻辑解释 | R-005 | Warning |
| 配置外置 | R-014 | Error |
| 文档同步 | R-008 | Info |

## 审查输出格式

```markdown
## 代码审查报告

### 总评
- 文件数：N
- 问题数：X Error, Y Warning, Z Info

### Error（必须修复）
| 位置 | 问题 | 规则 | 建议 |

### Warning（建议修复）
| 位置 | 问题 | 规则 | 建议 |

### Info（可选改进）
| 位置 | 问题 | 规则 | 建议 |
```

## 注意事项
- 优先关注业务逻辑正确性
- 遵循月笙核心原则的代码实现
- 诊断引擎代码需要更严格的审查
