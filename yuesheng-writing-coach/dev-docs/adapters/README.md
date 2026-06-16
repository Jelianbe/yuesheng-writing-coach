# 月笙写作教练 — 适配器层规范

> 本文档蒸馏自 AGENTS.md 的 adapter 层模式。
> 为 ai-teacher 的每个技术层定义「它拥有什么」「它禁止什么」「它如何接线」。

---

## 1. 渲染器适配器 (Renderer / React)

**@ADAPTER:framework/react@@ — 月笙 React 组件规范**

### 它拥有
- 组件树结构、JSX 呈现、hook 编排
- UI 状态：`useState`、`useReducer`、Zustand selector（仅消费）

### 它不拥有
- 业务语义（教学状态切换、训练记录、IPC 调用）
- 组件内不得直接 `getState()` 调用 store action（例外：`useCallback` 包装后作为 prop 传入）
- 不得 import `ipcRenderer` 直接调用 IPC

### 接线方式
- 消费 store 只能用 hook selector（`useXxxStore(s => s.xxx)`）
- 副作用通过 event handler 回调向上传递
- IPC 调用通过 service 层（`src/renderer/services/`）

### 禁止
- ❌ 组件内 `getState()` 调用业务 action
- ❌ 组件内 import `ipcRenderer`
- ❌ 内联 style（CSS Modules + 变量，例外：动态主题色/计算值）
- ❌ 接口 `{}` 空声明（用 `Record<string, never>`）
- ❌ `@ts-ignore`（用 `@ts-expect-error`）

---

## 2. IPC 适配器 (Electron Main↔Renderer)

**@ADAPTER:platform/electron@@ — 月笙 IPC 契约规范**

### 它拥有
- IPC 通道定义（`src/shared/api-contracts/`）
- handler 注册（`src/main/ipc/`）
- request/response 类型契约

### 接线方式
- 通道命名：`domain:action`（如 `session:list`、`training:recommend`）
- handler 签名：`(event, request: T) => Promise<ApiResponse<U>>`
- 所有 handler 在 `ipc-registry.ts` 注册

### 禁止
- ❌ handler 内使用 `any` 作参数/返回类型
- ❌ 通道名常量散落在 handler 文件中（必须在 `src/shared/constants.ts` 的 `IPC_CHANNELS` 中定义）
- ❌ renderer 直接 import handler

---

## 3. Store 适配器 (Zustand)

**@ADAPTER:state/zustand@@ — 月笙状态管理规范**

### 它拥有
- Store 定义（`src/renderer/stores/`）
- State 形状 + action 实现
- 数据持久化（`persist` middleware）

### 接线方式
- UI 通过 `useXxxStore(s => s.field)` 读
- Action 通过组件内 `useCallback` 包装后作为 prop 转发，或 store 自身包装的 `useXxxStore.getState().action()`（仅在 service/hook 层）

### 禁止
- ❌ Store action 内直接调用 IPC（应通过 service 层）
- ❌ Store 之间循环依赖（A store import B store import A store）
- ❌ UI 组件直接调 `useXxxStore.getState()` 执行 action（可接受：test / service）

---

## 4. CSS / 样式适配器

**@ADAPTER:design/css-modules@@ — 月笙样式规范**

### 它拥有
- CSS Modules（`*.module.css`）
- 设计 token（`src/renderer/styles/variables.css`）
- 共享布局类（`src/renderer/styles/panel-shared.module.css`）

### 禁止
- ❌ 内联 `style={{ }}`（例外：动态计算值、第三方组件 props）
- ❌ 硬编码色值（必须用 CSS 变量）
- ❌ 多个 CSS module 声明同一样式（重复 → 共享 module）

### 颜色引用链
```
variables.css (token 定义)
  └── panel-shared.module.css (共享布局/排版)
        └── [component].module.css (组件专属)
```

---

## 5. 测试适配器 (Vitest)

**@ADAPTER:testing/vitest@@ — 月笙测试规范**

### 它拥有
- 测试文件位置：`*.test.ts` / `*.test.tsx` 同级源文件，或 `__tests__/`
- 测试框架：Vitest

### 接线方式
- Store 测试：`act(() => store.getState().action())` 直接调用
- IPC handler 测试：调用 handler 函数直接传 mock 参数
- 组件测试：`@testing-library/react` render + fireEvent

### 禁止
- ❌ 测试内使用 `any` 应使用 `eslint-disable` 而非去除类型安全（已通过 eslint override 允许）
- ❌ 测试不覆盖核心业务路径（诊断合并、训练记录、TeachingState 转换）
