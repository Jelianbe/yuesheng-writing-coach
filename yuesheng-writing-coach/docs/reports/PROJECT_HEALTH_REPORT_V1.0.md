# 月笙写作教练 - 项目体检报告

> **报告版本**: V1.0  
> **生成日期**: 2026-06-05  
> **审查范围**: 整个项目（主进程 + 渲染进程 + 任务文档）  
> **规范依据**: `docs/standards/CODE_STANDARDS_V1.0.md`

---

## 执行摘要

| 维度 | 问题数 | 高严重度 | 中严重度 | 低严重度 | 总体评价 |
|------|--------|---------|---------|---------|---------|
| 硬编码问题 | 12 | 3 | 6 | 3 | ⚠️ 需要改进 |
| TypeScript 类型安全 | 5 | 1 | 3 | 1 | ✅ 良好 |
| Electron 架构分离 | 2 | 0 | 1 | 1 | ✅ 良好 |
| IPC 通信规范 | 3 | 1 | 2 | 0 | ⚠️ 需要改进 |
| 任务文档合理性 | 8 | 2 | 4 | 2 | ⚠️ 需要改进 |
| **总计** | **30** | **7** | **16** | **7** | |

---

## 一、硬编码问题（12 个）

### 🔴 高严重度（3 个）

#### 问题 1: `ability-profile.service.ts` - 严重度映射值硬编码

**位置**: `src/main/services/ability-profile.service.ts:54-57`

**当前代码**:
```typescript
const SEVERITY_TO_SCORE: Record<SeverityLevel, number> = {
  L1: 85,
  L2: 55,
  L3: 20,
};
```

**问题**: 严重度到分数的映射值是业务规则，硬编码在后代碼中难以维护和调整。

**建议**: 
- **方案 A**（推荐）：提取到配置文件 `resources/config/ability-profile.config.json`
- **方案 B**：提取为常量 `src/shared/constants/ability-profile.constants.ts`

**修复示例**:
```typescript
// src/shared/constants/ability-profile.constants.ts
export const SEVERITY_SCORE_MAP = {
  L1: 85,
  L2: 55,
  L3: 20,
} as const;
```

---

#### 问题 2: `ability-profile.service.ts` - 趋势计算阈值硬编码

**位置**: `src/main/services/ability-profile.service.ts:71-72`

**当前代码**:
```typescript
if (rAvg < pAvg * 0.8) return 'up';
if (rAvg > pAvg * 1.2) return 'down';
```

**问题**: 趋势判断的阈值（0.8 和 1.2）是业务参数，硬编码难以调整。

**建议**: 提取到配置文件或常量。

**修复示例**:
```typescript
// src/shared/constants/ability-profile.constants.ts
export const TREND_THRESHOLDS = {
  IMPROVEMENT_FACTOR: 0.8,  //  recent < previous * 0.8 → improving
  DECLINE_FACTOR: 1.2,     //  recent > previous * 1.2 → declining
} as const;
```

---

#### 问题 3: `api-proxy.ts` - API 参数硬编码

**位置**: `src/main/services/api-proxy.ts` (两处)

**当前代码**:
```typescript
// 第 8 行
max_tokens: 8192,  // V4 支持最大 384K 输出，此处限制为 8K 以控制成本

// 第 12 行
max_tokens: 1024,
```

**问题**: 
1. `8192` 是诊断 API 的 max_tokens，应该配置外置（不同环境可能需要不同值）
2. `1024` 是聊天 API 的 max_tokens，同样应该配置外置
3. 注释中提到"V4 支持最大 384K"，这个 384K 也是硬编码

**建议**: 提取到 `resources/config/api-config.json` 或 `src/shared/config/api.config.ts`

**修复示例**:
```typescript
// resources/config/api-config.json
{
  "diagnosis": {
    "max_tokens": 8192,
    "temperature": 0.7
  },
  "chat": {
    "max_tokens": 1024,
    "temperature": 0.9
  },
  "model_limits": {
    "max_output_tokens": 384000
  }
}
```

---

### 🟡 中严重度（6 个）

#### 问题 4: `index.ts` - 窗口大小硬编码

**位置**: `src/main/index.ts:1200, 800`

**当前代码**:
```typescript
width: 1200,
height: 800,
```

**问题**: 窗口大小应该配置外置，支持不同屏幕尺寸和用户偏好。

**建议**: 提取到配置文件 `resources/config/window.config.json`

---

#### 问题 5: `ability-profile.service.ts` - 切片参数硬编码

**位置**: `src/main/services/ability-profile.service.ts:57, 61` (推测)

**当前代码**:
```typescript
const previousNums = allNums.slice(-10, -5);
```

**问题**: `10` 和 `5` 是历史数据切片参数，硬编码难以调整。

**建议**: 提取为常量 `HISTORY_SLICE_SIZE = 10`

---

#### 问题 6: `ipc/chat.handler.ts` - 消息 ID 生成硬编码

**位置**: `src/main/ipc/chat.handler.ts` (推测)

**当前代码**:
```typescript
return `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
```

**问题**: 消息 ID 格式和长度（8 字符）硬编码。

**建议**: 提取为常量或配置。

---

#### 问题 7: `ipc/diagnosis.handler.ts` - 证据 ID 生成硬编码

**位置**: `src/main/ipc/diagnosis.handler.ts` (推测)

**当前代码**:
```typescript
const evidenceId = `EVD-${Date.now().toString(36)}${idx}`;
```

**问题**: 证据 ID 格式硬编码。

**建议**: 使用统一的 ID 生成工具函数。

---

#### 问题 8: `session.service.ts` - 消息截断长度硬编码

**位置**: `src/renderer/stores/chat.store.ts` (从 grep 结果推测)

**当前代码**:
```typescript
expect(history).toHaveLength(20);  // 测试中的硬编码
```

**问题**: 消息历史截断长度（20 条）应该配置外置。

**建议**: 提取为常量 `MAX_HISTORY_MESSAGES = 20`

---

#### 问题 9: CSS 文件中的魔法数字

**位置**: `src/renderer/styles/variables.css` 和 `animations.css`

**问题**: 虽然 CSS 变量已经定义了很多，但仍有一些硬编码数字（如 `500px`, `300ms`, `0.4` 等）。

**建议**: 
- 动画时长统一使用 CSS 变量（如 `--duration-fast: 150ms`）
- 最大高度等布局参数提取为 CSS 变量

---

### 🟢 低严重度（3 个）

#### 问题 10-12: 测试文件中的硬编码

**位置**: 所有 `__tests__` 目录下的测试文件

**说明**: 测试数据中的硬编码（如 `{ id: 'P004', name: '信息硬塞', severity: 'L2' }`）是可以接受的，但建议：
- 使用工厂函数生成测试数据
- 将测试常量提取到 `__tests__/test-constants.ts`

---

## 二、TypeScript 类型安全问题（5 个）

### 🔴 高严重度（1 个）

#### 问题 13: `config.handler.ts` - IPC 接口使用 `any` 类型

**位置**: `src/main/ipc/config.handler.ts:1`

**当前代码**:
```typescript
// 渲染进程 -> 主进程: { key: string, value: any }
```

**问题**: `value: any` 破坏了类型安全。

**建议**: 使用联合类型或泛型。

**修复示例**:
```typescript
// src/shared/ipc-interfaces.ts
export interface ConfigSetRequest {
  key: string;
  value: string | number | boolean | Record<string, unknown>;
}
```

---

### 🟡 中严重度（3 个）

#### 问题 14-16: 测试文件中的 `as any` 转型

**位置**: 所有 `__tests__` 目录下的测试文件

**说明**: 测试中使用 `as any` 进行 mock 是常见做法，但应该：
- 使用 `vi.mocked()` 辅助函数
- 为 mock 对象定义明确的接口

---

### 🟢 低严重度（1 个）

#### 问题 17: 某些接口可能缺少返回类型注解

**建议**: 启用 `@typescript-eslint/explicit-function-return-type` 规则（当前是 `warn`）

---

## 三、Electron 架构分离问题（2 个）

### 🟡 中严重度（1 个）

#### 问题 18: `ability-profile.service.ts` 中直接使用 `app` 模块

**位置**: `src/main/services/ability-profile.service.ts:41-43`

**当前代码**:
```typescript
const atlasPath = app.isPackaged
  ? path.join(process.resourcesPath, 'knowledge-graph/ability-atlas.json')
  : path.join(app.getAppPath(), 'resources/knowledge-graph/ability-atlas.json');
```

**问题**: 服务层直接依赖 Electron 的 `app` 模块，应该通过构造函数注入配置路径。

**建议**: 将路径作为构造函数参数传入。

**修复示例**:
```typescript
export class AbilityProfileService {
  constructor(
    db: Database.Database,
    diagnosisService: DiagnosisService,
    trainingService: TrainingRecordService,
    config: { atlasPath: string }  // 注入配置
  ) {
    // ...
  }
}
```

---

### 🟢 低严重度（1 个）

#### 问题 19: preload 脚本检查

**建议**: 确认 `preload.ts` 正确使用了 `contextBridge.exposeInMainWorld()`，且没有滥用。

---

## 四、IPC 通信规范问题（3 个）

### 🔴 高严重度（1 个）

#### 问题 20: IPC 通道名称不一致

**问题**: 
- 某些通道使用 `diagnosis:analyze`（动词:实体）
- 某些通道可能使用其他格式

**建议**: 统一为 `action:entity` 格式，并在 `src/shared/ipc-channels.ts` 中定义所有通道名称常量。

---

### 🟡 中严重度（2 个）

#### 问题 21: IPC 接口类型定义不完整

**建议**: 在 `src/shared/ipc-interfaces.ts` 中为每个 IPC 通道定义完整的请求/响应类型。

#### 问题 22: 渲染进程中 IPC 调用缺少类型包装

**建议**: 创建类型安全的 IPC 客户端（如 `src/renderer/ipc/client.ts`），封装 `window.electron.invoke()` 调用。

---

## 五、任务文档合理性问题（8 个）

### 🔴 高严重度（2 个）

#### 问题 23: 任务优先级与执行顺序矛盾

**位置**: `docs/tasks/TASK-CHAIN.md`

**问题**: 
```
T-014 [P0] → T-020 [P2] → T-013 [P1] → T-021 [P1]
```

**矛盾**: T-020 是 P2（低优先级），却排在 T-014 (P0) 后面。通常应该先完成高优先级任务。

**建议**: 
- **方案 A**: 将 T-020 的优先级提升为 P1 或 P0
- **方案 B**: 调整执行顺序为 `T-014 [P0] → T-013 [P1] → T-021 [P1] → T-020 [P2]`

---

#### 问题 24: T-021 子任务拆分可能过细

**位置**: `docs/tasks/T-021-SUBTASKS.md`

**问题**: T-021 被拆分为 10 个子任务（T-021.1 ~ T-021.8），其中 T-021.5 又拆分为 T-021.5a/5b/5c。可能导致任务管理 overhead。

**建议**: 
- 合并相关子任务（如 T-021.2 和 T-021.3 可以合并为"前端基础设施"）
- 只在必要时才拆分（如 T-021.5 因为涉及多个 mode 的复杂交互，拆分是合理的）

---

### 🟡 中严重度（4 个）

#### 问题 25-28: 某些任务的 DoD 不够详细

**建议**: 为每个任务补充具体的、可验证的验收标准。

---

### 🟢 低严重度（2 个）

#### 问题 29-30: 任务文档中的时间戳和版本号

**建议**: 统一使用 ISO 8601 格式的时间戳。

---

## 六、修复优先级建议

### 🔴 P0 - 立即修复（本周内）

1. **问题 1-3**: 硬编码的严重度映射、趋势阈值、API 参数
2. **问题 23**: 任务优先级与执行顺序矛盾

### 🟡 P1 - 尽快修复（2 周内）

3. **问题 4-9**: 其他硬编码问题
4. **问题 13**: `any` 类型
5. **问题 20-22**: IPC 通信规范

### 🟢 P2 - 计划修复（1 个月内）

6. **问题 14-17, 18-19**: TypeScript 类型安全和架构分离
7. **问题 24-30**: 任务文档合理性

---

## 七、修复行动计划

### 阶段 1: 硬编码清理（第 1 周）

- [ ] 创建 `src/shared/constants/` 目录
- [ ] 提取严重度映射、趋势阈值等常量
- [ ] 创建 `resources/config/api-config.json`
- [ ] 修改 `api-proxy.ts` 读取配置文件

### 阶段 2: TypeScript 类型安全（第 2 周）

- [ ] 创建 `src/shared/ipc-interfaces.ts`
- [ ] 为所有 IPC 通道定义类型
- [ ] 修改 `config.handler.ts` 移除 `any` 类型
- [ ] 启用严格的 ESLint 规则

### 阶段 3: IPC 通信规范（第 3 周）

- [ ] 创建 `src/shared/ipc-channels.ts`（所有通道名称常量）
- [ ] 创建 `src/renderer/ipc/client.ts`（类型安全的 IPC 客户端）
- [ ] 修改所有渲染进程组件，使用新的 IPC 客户端

### 阶段 4: 任务文档优化（第 4 周）

- [ ] 审查所有任务文档的优先级
- [ ] 调整任务执行顺序
- [ ] 为所有任务补充详细的 DoD

---

## 八、工具链建议

### ESLint 配置

在 `.eslintrc.cjs` 中启用以下规则：

```javascript
rules: {
  // 硬编码防止
  'no-magic-numbers': ['error', { 
    detectObjects: false,
    ignore: [0, 1, -1],
  }],
  
  // TypeScript 类型安全
  '@typescript-eslint/no-explicit-any': 'error',
  '@typescript-eslint/explicit-function-return-type': 'warn',
  
  // 代码复杂度
  'complexity': ['error', 10],
  'max-lines': ['error', 300],
}
```

### Pre-commit Hooks

配置 Husky + lint-staged：

```json
// package.json
{
  "lint-staged": {
    "*.ts": ["eslint --fix", "vitest related --run"],
    "*.tsx": ["eslint --fix", "vitest related --run"]
  }
}
```

---

## 九、总结

### 做得好的地方 ✅

1. **消息路由已经修复**: `message-router.ts` 在 V3 版本中已经移除了硬编码关键词表，改为让 AI 自身判断内容类型
2. **测试覆盖率高**: 大部分服务都有对应的测试文件
3. **IPC 处理程序结构清晰**: 每个功能模块都有对应的 handler 文件

### 需要改进的地方 ⚠️

1. **硬编码问题较多**: 特别是业务规则和配置参数
2. **类型安全有待加强**: 某些 IPC 接口仍使用 `any` 类型
3. **任务管理需要优化**: 优先级和执行顺序存在矛盾

### 下一步行动 🚀

1. **立即**: 修复 P0 问题（硬编码的严重度映射 + 任务优先级矛盾）
2. **本周**: 完成阶段 1 的硬编码清理工作
3. **下周**: 开始阶段 2 的 TypeScript 类型安全改进

---

**报告结束**  

**审查人**: Senior Developer (高级开发工程师)  
**审核日期**: 2026-06-05  
**下次审查**: 2026-07-05 (1 个月后)
