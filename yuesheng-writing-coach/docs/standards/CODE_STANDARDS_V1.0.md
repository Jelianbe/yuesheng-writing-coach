# 月笙写作教练 - 代码规范 V1.0

> **目标**: 建立统一的代码质量标准，防止硬编码、提升可维护性、确保类型安全

## 目录

1. [TypeScript 基础规范](#1-typescript-基础规范)
2. [Electron 架构规范](#2-electron-架构规范)
3. [硬编码防止指南](#3-硬编码防止指南)
4. [代码质量检查清单](#4-代码质量检查清单)
5. [ESLint 配置推荐](#5-eslint-配置推荐)
6. [AI 代码审查提示词模板](#6-ai-代码审查提示词模板)

---

## 1. TypeScript 基础规范

### 1.1 类型安全

**✅ 必须遵循**:

```typescript
// ❌ 禁止：any 类型
function processData(data: any) { ... }

// ✅ 推荐：明确类型
interface ProcessDataInput {
  id: string;
  content: string;
  metadata?: Record<string, unknown>;
}
function processData(data: ProcessDataInput) { ... }
```

```typescript
// ❌ 禁止：隐式 any
const items = [];  // 类型推断为 any[]

// ✅ 推荐：显式类型
const items: Item[] = [];
```

**规则**:
- 禁止使用 `any`，使用 `unknown` 或具体类型替代
- 禁止使用 `@ts-ignore`，必须处理类型错误
- 优先使用 `interface` 定义对象结构，`type` 用于联合类型/交叉类型

### 1.2 命名规范

| 元素 | 规范 | 示例 |
|------|------|------|
| 变量/函数 | camelCase | `getDiagnosis`, `userId` |
| 常量 | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| 类/接口 | PascalCase | `DiagnosisService`, `IDiagnosisEntry` |
| 类型参数 | PascalCase (单字母或描述性名称) | `TData`, `TResponse` |
| 枚举 | PascalCase (成员也用 PascalCase) | `enum Color { Red, Blue }` |
| 文件 | kebab-case | `diagnosis.service.ts`, `use-diagnosis-flow.ts` |

**接口命名**:
```typescript
// ✅ 推荐：接口不加 I 前缀（TypeScript 社区约定）
interface DiagnosisEntry { ... }
interface UserService { ... }

// ❌ 不推荐
interface IDiagnosisEntry { ... }
```

### 1.3 代码组织

**导入顺序**:
```typescript
// 1. 外部库
import { electron } from 'electron';
import { injectable } from 'tsyringe';

// 2. 内部模块（绝对路径）
import { DiagnosisService } from '@/main/services/diagnosis.service';
import { useDiagnosisFlow } from '@/renderer/hooks/use-diagnosis-flow';

// 3. 相对路径导入
import { helper } from './helper';
import type { Props } from './types';

// 4. 样式导入
import './DiagnosisCard.css';
```

**导出规范**:
```typescript
// ✅ 推荐：明确导出
export class DiagnosisService { ... }
export interface DiagnosisEntry { ... }

// ❌ 禁止：export default（难以重构和类型推断）
export default class DiagnosisService { ... }
```

---

## 2. Electron 架构规范

### 2.1 进程分离

**主进程 (Main Process)**:
```typescript
// ✅ 正确：主进程只处理系统级操作
// src/main/services/diagnosis.service.ts
@injectable()
export class DiagnosisService {
  async diagnose(text: string): Promise<DiagnosisResult> {
    // 调用 DeepSeek API
    // 解析诊断结果
    // 存储到数据库
  }
}
```

**渲染进程 (Renderer Process)**:
```typescript
// ✅ 正确：渲染进程只处理 UI 和状态
// src/renderer/hooks/use-diagnosis-flow.ts
export function useDiagnosisFlow() {
  const [state, setState] = useState<DiagnosisFlowState>(...);
  
  const submitRewrite = useCallback(async (text: string) => {
    // 通过 IPC 调用主进程
    const result = await window.electron.invoke('diagnosis:submitRewrite', text);
    setState(...);
  }, []);
}
```

**禁止**:
- ❌ 渲染进程中直接访问数据库
- ❌ 渲染进程中直接调用 DeepSeek API
- ❌ 主进程中直接操作 DOM

### 2.2 IPC 通信规范

**IPC 通道命名**:
```typescript
// ✅ 推荐：action:entity 格式
'diagnosis:analyze'      // 诊断分析
'training:assign'        // 分配训练
'training:complete'      // 完成训练
'config:get'             // 获取配置
'config:update'          // 更新配置
```

**IPC 接口定义**:
```typescript
// src/shared/ipc-interfaces.ts
export interface IPCChannels {
  'diagnosis:analyze': {
    request: { text: string; options?: AnalysisOptions };
    response: DiagnosisResult | { error: string };
  };
  'training:assign': {
    request: { syndromeId: string; templateId: string };
    response: TrainingRecord | { error: string };
  };
}
```

**渲染进程中类型安全的 IPC 调用**:
```typescript
// src/renderer/ipc/ipc-client.ts
import type { IPCChannels } from '@/shared/ipc-interfaces';

export function createIPCClient() {
  return {
    invoke<K extends keyof IPCChannels>(
      channel: K,
      request: IPCChannels[K]['request']
    ): Promise<IPCChannels[K]['response']> {
      return window.electron.invoke(channel, request);
    }
  };
}
```

### 2.3 安全规范

**Context Isolation**:
```typescript
// ✅ 正确：通过 contextBridge 暴露 API
// preload.ts
contextBridge.exposeInMainWorld('electron', {
  invoke: (channel: string, ...args: unknown[]) =>
    ipcRenderer.invoke(channel, ...args),
});
```

**禁止**:
- ❌ 在渲染进程中直接使用 `ipcRenderer`（必须通过 preload）
- ❌ 启用 `nodeIntegration: true`
- ❌ 在 webPreferences 中禁用 `contextIsolation`

---

## 3. 硬编码防止指南

### 3.1 魔法数字

**❌ 禁止**:
```typescript
// 魔法数字
if (text.length > 100) { ... }  // 100 是什么？
setTimeout(callback, 3000);     // 3000 是什么？
const retryCount = 3;            // 3 是什么？
```

**✅ 推荐**:
```typescript
// 常量提取到配置文件或常量文件
// src/shared/constants.ts
export const DIAGNOSIS = {
  MIN_TEXT_LENGTH: 100,
  MAX_TEXT_LENGTH: 10000,
  RETRY_COUNT: 3,
  TIMEOUT_MS: 3000,
} as const;

// 使用
if (text.length > DIAGNOSIS.MIN_TEXT_LENGTH) { ... }
setTimeout(callback, DIAGNOSIS.TIMEOUT_MS);
```

### 3.2 硬编码字符串

**❌ 禁止**:
```typescript
// 硬编码字符串
if (userRole === 'admin') { ... }
router.push('/diagnosis-result');
showToast('诊断完成');
```

**✅ 推荐**:
```typescript
// src/shared/constants.ts
export const USER_ROLES = {
  ADMIN: 'admin',
  USER: 'user',
  GUEST: 'guest',
} as const;

export const ROUTES = {
  DIAGNOSIS_RESULT: '/diagnosis-result',
  TRAINING_WORKSHOP: '/training-workshop',
} as const;

// src/shared/i18n/zh-CN.ts
export const MESSAGES = {
  DIAGNOSIS_COMPLETE: '诊断完成',
  TRAINING_ASSIGNED: '已分配训练任务',
} as const;

// 使用
if (userRole === USER_ROLES.ADMIN) { ... }
router.push(ROUTES.DIAGNOSIS_RESULT);
showToast(MESSAGES.DIAGNOSIS_COMPLETE);
```

### 3.3 配置外置

**❌ 禁止**:
```typescript
// 硬编码配置
const apiUrl = 'https://api.deepseek.com/v1';
const timeout = 30000;
const maxRetries = 3;
```

**✅ 推荐**:
```typescript
// src/shared/config/config.schema.ts
export interface AppConfig {
  api: {
    deepSeek: {
      baseURL: string;
      timeout: number;
      maxRetries: number;
    };
  };
  diagnosis: {
    minTextLength: number;
    maxTextLength: number;
  };
}

// config/development.yaml
api:
  deepSeek:
    baseURL: 'https://api.deepseek.com/v1'
    timeout: 30000
    maxRetries: 3

// src/main/config/config.service.ts
@injectable()
export class ConfigService {
  private config: AppConfig;
  
  load(configPath: string): AppConfig {
    this.config = loadYAML(configPath);
    return this.config;
  }
  
  get<K extends keyof AppConfig>(key: K): AppConfig[K] {
    return this.config[key];
  }
}
```

### 3.4 枚举替代硬编码字符串

**❌ 禁止**:
```typescript
type Severity = 'fatal' | 'structural' | 'surface';  // 散落在代码各处
if (severity === 'fatal') { ... }
```

**✅ 推荐**:
```typescript
// src/shared/enums/severity.enum.ts
export enum Severity {
  FATAL = 'fatal',
  STRUCTURAL = 'structural',
  SURFACE = 'surface',
}

// 使用
if (severity === Severity.FATAL) { ... }
```

---

## 4. 代码质量检查清单

### 4.1 提交前检查 (Pre-commit)

**必须通过的检查**:

- [ ] TypeScript 编译无错误 (`tsc --noEmit`)
- [ ] ESLint 无错误 (`eslint . --ext .ts,.tsx`)
- [ ] 单元测试通过 (`vitest run`)
- [ ] 无 `any` 类型
- [ ] 无 `@ts-ignore`
- [ ] 无硬编码魔法数字/字符串
- [ ] 无 console.log（生产代码）
- [ ] 无 debugger 语句

### 4.2 代码审查清单

**架构**:
- [ ] 主进程和渲染进程职责分离正确
- [ ] IPC 通信使用类型安全的接口
- [ ] 依赖注入正确使用（`tsyringe`）

**类型安全**:
- [ ] 无 `any` 类型
- [ ] 无隐式类型转换
- [ ] 接口定义完整（无可选字段滥用）

**硬编码**:
- [ ] 所有魔法数字已提取为常量
- [ ] 所有硬编码字符串已提取为常量或 i18n
- [ ] 配置已外置到配置文件

**可维护性**:
- [ ] 函数长度 ≤ 50 行
- [ ] 文件长度 ≤ 300 行
- [ ] 循环复杂度 ≤ 10
- [ ] 无重复代码（DRY 原则）

**错误处理**:
- [ ] 所有异步操作有错误处理
- [ ] 所有 IPC 调用有错误返回
- [ ] 用户界面有加载状态和错误状态

---

## 5. ESLint 配置推荐

### 5.1 基础配置

```javascript
// .eslintrc.cjs
module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  plugins: ['@typescript-eslint', 'no-magic-numbers', 'no-hardcoded-strings'],
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:@typescript-eslint/recommended-requiring-type-checking',
  ],
  parserOptions: {
    project: './tsconfig.json',
    tsconfigRootDir: __dirname,
  },
  rules: {
    // TypeScript 规则
    '@typescript-eslint/no-explicit-any': 'error',
    '@typescript-eslint/no-unused-vars': 'error',
    '@typescript-eslint/explicit-function-return-type': 'warn',
    '@typescript-eslint/no-floating-promises': 'error',
    
    // 硬编码防止规则
    'no-magic-numbers': ['error', { 
      detectObjects: false,
      ignore: [0, 1, -1],
    }],
    'no-hardcoded-strings/no-hardcoded-strings': ['error', {
      ignore: ['/', '.', '-'],
      ignorePatterns: [/^[\w\s]+$/],  // 允许 i18n 键
    }],
    
    // 代码质量规则
    'complexity': ['error', 10],
    'max-lines': ['error', 300],
    'max-lines-per-function': ['error', 50],
  },
};
```

### 5.2 自定义规则（硬编码检测）

```javascript
// eslint-plugin-no-hardcoded-strings/rules/no-hardcoded-strings.js
module.exports = {
  meta: {
    type: 'suggestion',
    docs: {
      description: '禁止硬编码字符串',
      category: 'Best Practices',
    },
    schema: [
      {
        type: 'object',
        properties: {
          ignore: { type: 'array', items: { type: 'string' } },
          ignorePatterns: { type: 'array', items: { instanceof: 'RegExp' } },
        },
      },
    ],
  },
  
  create(context) {
    return {
      Literal(node) {
        if (typeof node.value === 'string' && node.value.length > 3) {
          // 检查是否是硬编码字符串
          const isIgnored = context.options[0]?.ignore?.includes(node.value);
          const isPatternIgnored = context.options[0]?.ignorePatterns?.some(pattern => 
            pattern.test(node.value)
          );
          
          if (!isIgnored && !isPatternIgnored) {
            context.report({
              node,
              message: '禁止硬编码字符串，请使用常量或 i18n',
            });
          }
        }
      },
    };
  },
};
```

---

## 6. AI 代码审查提示词模板

### 6.1 通用代码审查提示词

```
你是一位资深 TypeScript/Electron 代码审查专家。请审查以下代码，重点关注：

## 审查清单

### 1. 类型安全
- [ ] 是否存在 `any` 类型？如有，建议具体类型
- [ ] 是否存在隐式类型转换？
- [ ] 接口定义是否完整？

### 2. 硬编码检测
- [ ] 是否存在魔法数字？如有，建议提取为常量
- [ ] 是否存在硬编码字符串？如有，建议提取为常量或 i18n
- [ ] 配置是否外置？

### 3. Electron 架构
- [ ] 主进程和渲染进程职责是否分离正确？
- [ ] IPC 通信是否类型安全？
- [ ] 是否存在安全漏洞（如 nodeIntegration 启用）？

### 4. 代码质量
- [ ] 函数是否过长（> 50 行）？
- [ ] 文件是否过大（> 300 行）？
- [ ] 循环复杂度是否过高（> 10）？
- [ ] 是否存在重复代码？

### 5. 错误处理
- [ ] 所有异步操作是否有错误处理？
- [ ] 所有 IPC 调用是否有错误返回？
- [ ] 用户界面是否有加载状态和错误状态？

## 输出格式

请按以下格式输出审查结果：

### 问题 1: [问题标题]
- **位置**: `文件路径:行号`
- **严重度**: 高/中/低
- **问题**: 详细描述
- **建议**: 如何修复
- **示例代码**:
  ```typescript
  // ❌ 当前代码
  // ✅ 推荐代码
  ```

### 总结
- 发现问题总数: X
- 高严重度: X
- 中严重度: X
- 低严重度: X
```

### 6.2 硬编码专项审查提示词

```
你是一位代码质量专家，专注于检测硬编码问题。请审查以下代码，找出所有硬编码问题：

## 硬编码检测清单

### 1. 魔法数字
- 数字字面量（除了 0, 1, -1）
- 数字出现在条件判断、循环、超时设置等场景

### 2. 硬编码字符串
- 字符串字面量（除了 '', '/', '.', '-'）
- 字符串出现在路由、角色判断、消息提示等场景

### 3. 配置硬编码
- API URL
- 超时时间
- 重试次数
- 特性开关

### 4. 枚举值硬编码
- 字符串枚举值直接比较
- 应该使用枚举的地方使用了字符串

## 输出格式

### 硬编码问题 1: [问题标题]
- **位置**: `文件路径:行号`
- **类型**: 魔法数字/硬编码字符串/配置硬编码/枚举值硬编码
- **当前值**: 具体的值
- **问题**: 为什么这是问题
- **建议**: 如何修复（常量名、配置文件位置等）
- **示例代码**:
  ```typescript
  // ❌ 当前代码
  const timeout = 30000;
  
  // ✅ 推荐代码
  import { CONFIG } from '@/shared/config';
  const timeout = CONFIG.api.timeout;
  ```
```

---

## 7. 实施计划

### 阶段 1: 基础规范建立（第 1 周）

- [ ] 创建 `.eslintrc.cjs` 并启用基础规则
- [ ] 创建 `tsconfig.json` 并严格配置
- [ ] 整理现有代码中的硬编码问题（优先级：高）
- [ ] 建立 `src/shared/constants.ts` 和配置文件结构

### 阶段 2: 工具链集成（第 2 周）

- [ ] 配置 Husky pre-commit hooks
- [ ] 配置 lint-staged
- [ ] 配置 GitHub Actions / CI 流水线
- [ ] 编写自定义 ESLint 规则（针对项目特定问题）

### 阶段 3: AI 审查集成（第 3 周）

- [ ] 选择合适的 AI 代码审查工具（如 Coderabbit, GitHub Copilot Chat）
- [ ] 配置 AI 审查提示词模板
- [ ] 建立 AI 审查工作流（PR 自动审查）
- [ ] 培训团队如何使用 AI 审查反馈

### 阶段 4: 持续改进（第 4 周及以后）

- [ ] 定期审查 ESLint 规则有效性
- [ ] 根据团队反馈调整规范
- [ ] 分享最佳实践案例
- [ ] 定期重构硬编码问题

---

## 8. 参考资源

- [Airbnb JavaScript Style Guide](https://github.com/airbnb/javascript)
- [Google TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html)
- [Electron Security Guidelines](https://www.electronjs.org/docs/latest/tutorial/security)
- [TypeScript Best Practices](https://typescript.tv/best-practices/)
- [ESLint Rules](https://eslint.org/docs/latest/rules/)

---

**文档版本**: V1.0  
**创建日期**: 2026-06-05  
**负责人**: 月笙如歌  
**审查周期**: 每季度审查一次
