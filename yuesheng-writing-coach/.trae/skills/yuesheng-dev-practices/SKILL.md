---
name: "yuesheng-dev-practices"
description: "Aggregates all project coding conventions into one actionable checklist: code standards (R-019), IPC patterns (R-028), state management (R-007), scope control (R-010), security (R-029), config externalization (R-014), circular dependency ban (R-020). Invoke when writing or reviewing any code in yuesheng-writing-coach project."
---

# Yuesheng Dev Practices (月笙开发规范聚合)

## Purpose

将月笙写作教练项目的 8 条核心开发规则聚合为一个**编码时即用的操作指南**。不是替代原文档，而是提取精华要点为可执行检查清单。

## When to Invoke

- **编写任何代码前** — 快速确认当前任务的约束条件
- **代码审查时** — 逐项检查 PR 是否违反规范
- **重构决策时** — 判断改动范围是否合理

## Quick Reference Checklist

### Phase 1: 编码前（Before Coding）

- [ ] **确认任务边界** (R-010): 这次只解决一个问题？不碰无关文件？
- [ ] **检查任务文档** (R-018): 有对应的 task/spec 文档作为依据吗？
- [ ] **确认目标文件** (R-019): 要改的文件当前行数？改完会超 300 行吗？
- [ ] **安全检查** (R-029): 会涉及 API Key / 密码 / Token 吗？用占位符？

### Phase 2: 编码中 (While Coding)

#### A. 类型安全 (R-019)

```typescript
// ✅ 正确
type ChapterRef = { chapterId: string; chapterTitle: string; raw: string };
const ref: ChapterRef = parsed[0];

// ❌ 禁止
const ref: any = parsed[0];                          // any 禁止
const id = (data as someType).id!;                   // 非空断言谨慎使用
// @ts-ignore                                         // 绝对禁止
```

**硬上限**:
| 维度 | 上限 |
|------|:----:|
| 单文件 | ≤ 300 行（⚠️ 300-500 警告 / 🔴 >500 错误）|
| 单函数 | ≤ 50 行 |

#### B. 命名规范 (R-19 + AGENTS.md)

| 类别 | 格式 | 示例 |
|------|------|------|
| 变量/函数 | camelCase | `sendMessage`, `parseChapterReferences` |
| 常量 | UPPER_SNAKE_CASE | `MAX_CHAPTER_REF_LENGTH`, `IPC_TIMEOUT_MS` |
| 类/接口/类型 | PascalCase | `ChatHandlerDeps`, `ValidationResult` |
| IPC channel | domain:verb | `chat:send`, `diagnosis:analyze`, `training:start` |
| 文件名 | kebab-case | `chat-handler.ts`, `validate-payload.ts` |

**禁止**:
- `export default` → 用具名导出
- 内联样式 → 用 CSS 变量 / CSS Modules / Tailwind
- 中文变量名 → 用英文

#### C. IPC Handler 模板 (R-028)

每个 handler 必须遵循四步结构：

```typescript
ipcMain.handle('domain:verb', async (_event, payload) => {
  // Step 1: 入参校验
  const validated = validatePayload<PayloadType>(payload);
  if (!validated.success) {
    return { success: false, error: 'INVALID_PAYLOAD', message: validated.error };
  }

  try {
    // Step 2: 业务逻辑
    const result = doSomething(validated.data);

    // Step 3: 出参返回
    return { success: true, data: result };
  } catch (err) {
    // Step 4: 错误分类
    return { success: false, error: classifyError(err), message: err.message };
  }
});
```

**错误码格式**: `{ success: false, error: 'ERROR_CODE', message: '...' }`

#### D. 状态管理 (R-007 + Zustand)

```typescript
// Store 定义
interface ChatState {
  messages: Message[];
  isStreaming: boolean;
  sendMessage: (text: string) => Promise<void>;
  stopStreaming: () => void;
}

export const useChatStore = create<ChatState>()((set, get) => ({
  // ...
}));
```

**关键约定**:
- Store 文件位于 `src/renderer/stores/`
- 状态变更通过 IPC 同步到 main process
- 禁止循环依赖（Store ↔ Store 直接 import）

#### E. 安全与隐私 (R-029)

```typescript
// ✅ 正确: 占位符 + 运行时注入
const API_KEY = process.env.DEEPSEEK_API_KEY ?? '';

// ❌ 禁止: 硬编码
const API_KEY = 'sk-abc123xyz456...';
```

**必查项**:
- [ ] `.env` 在 `.gitignore` 中？
- [ ] Prompt 中无真实 Key？（用 `{{API_KEY}}` 占位符）
- [ ] 密钥只在 main process 使用？（不传给 renderer）

#### F. 配置外置 (R-014)

```typescript
// ❌ 禁止: 静态映射表
const SYNDROME_NAMES: Record<string, string> = {
  P001: '说明书症候',
  P002: '大纲恐惧症',
  // ... 每次新增都要改这里
};

// ✅ 正确: 外置配置
const syndromeConfig = loadSyndromeConfig(); // 从 JSON/YAML 加载
```

### Phase 3: 编码后 (After Coding)

- [ ] **tsc 检查**: `npx tsc --noEmit` → 0 errors?
- [ ] **测试运行**: `npx vitest run` → passed?
- [ ] **构建验证**: `npm run build:main` → success?
- [ ] **文件大小**: 改动文件超 300 行了吗？需要拆分吗？
- [ ] **循环依赖**: 新增 import 是否产生环？(`npm run check:circular`)
- [ ] **console.log**: 有敏感信息吗？有调试日志残留吗？

## Command Cheat Sheet

| 命令 | 用途 |
|------|------|
| `npx tsc --noEmit` | 类型检查（0 error 才能过）|
| `npx vitest run` | 运行全部测试 |
| `npm run build:main` | 编译 main process → dist/main/ |
| `npm run check:size` | 检测超长文件（R-19a）|
| `npm run check:circular` | 检测循环依赖（R-20）|
| `npm run dev` | 启动 dev 环境（tsc -w + vite + electron 并行）|

## Anti-Patterns Quick Reference

| 反模式 | 正确做法 |
|--------|---------|
| 改 A 时顺手修 B | 只改任务范围内的文件（R-010）|
| 先写代码再补文档 | 先有 task doc 再写代码（R-018 前置规则）|
| `console.log(data)` 调试 | 用 `writeDebugLog()` 写入文件日志 |
| `import * as fs from 'fs'` 重复导入 | 用 `require('fs')` 在函数内动态引入 |
| `transition: all 0.3s ease` | 用显式属性列表优化性能 |
| innerHTML 拼接 HTML | 用 createElement + 安全赋值 |
