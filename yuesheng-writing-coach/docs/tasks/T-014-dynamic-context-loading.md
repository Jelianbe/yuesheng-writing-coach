# T-014: 动态上下文装载

> **优先级**: P0 | **状态**: completed | **预估**: 3d  
> **依赖**: 无 | **后续**: T-020

## 目标

实现"参考抽屉"的按需装载机制，将 System Prompt 从全量拼接改为 `核心 + 按需 + 上下文` 三段式组装。根据当前教学阶段和活跃症候，只装载相关的知识片段，减少 Prompt 长度，降低 LLM 认知负担和 API 成本。

## 设计依据

- **设计依据文档**: [dynamic-context-service_V1.0.md](../design/dynamic-context-service_V1.0.md)
- **关联发现**: 月笙_设计意图vs代码实现_V1.0.md → 发现10 参考抽屉实现走偏
- **来源任务**: 无（P0 新架构基础任务）

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | 新增 DynamicContextService，按阶段装载知识 | `src/main/services/dynamic-context.service.ts` |
| 后端 | 改造 PromptLoader 调用新服务 | `src/main/services/prompt-loader.ts` |
| 后端 | 注册服务到主进程 | `src/main/index.ts` |
| 数据 | 知识文件增加片段标记 | `resources/prompts/syndrome-manual.md`, `action-library.md` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/main/services/dynamic-context.service.ts` | 新增 | 核心服务：按教学阶段装载知识 |
| 2 | `src/main/services/prompt-loader.ts` | 修改 | loadSystemPrompt() 改为三段式组装 |
| 3 | `resources/prompts/syndrome-manual.md` | 修改 | 增加 SYNDROME:X 片段标记 |
| 4 | `resources/prompts/action-library.md` | 修改 | 增加 ACTION:X 片段标记 |
| 5 | `src/main/index.ts` | 修改 | 注册 DynamicContextService |

## DoD（完成标准）

- [ ] S1. DynamicContextService 正确按教学阶段和活跃症候装载知识片段
- [ ] S2. prompt-loader.ts 改用三段式组装（核心+按需+上下文）替代全量拼接
- [ ] S3. 知识文件具有可解析的片段标记（`<!-- SYNDROME:P001 -->` 格式）
- [ ] S4. TypeScript 编译无错误
- [ ] S5. 至少 3 个单元测试覆盖不同阶段的装载逻辑

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. prompt-loader.ts 恢复为直接读取全量 Prompt
3. 知识文件标记不影响读取（无标记时回退到全量读取）

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|
| `src/main/services/dynamic-context.service.ts` | 新增 DynamicContextService，实现 loadContext、formatReferenceDrawer、clearCache 等方法 |
| `src/main/services/prompt-loader.ts` | 新增 setDynamicContextService() 方法，改造 loadSystemPrompt() 为三段式组装 |
| `src/main/index.ts` | 注册 DynamicContextService 实例，注入到 PromptLoader |
| `resources/prompts/syndrome-manual.md` | 为 P001-P010 症候添加 `<!-- SYNDROME:PXXX -->` / `<!-- END:SYNDROME:PXXX -->` 片段标记 |
| `resources/prompts/action-library.md` | 为 A001-A012 动作添加 `<!-- ACTION:A0XX -->` / `<!-- END:ACTION:A0XX -->` 片段标记 |
| `src/main/services/__tests__/dynamic-context.service.test.ts` | 新增 14 个单元测试用例 |

### 验证结果（实际完成时填写）

- [x] TypeScript 编译通过（`npx tsc --noEmit`）
- [x] 测试通过（14/14 用例通过，`npx vitest run dynamic-context.service.test.ts`）
- [x] 知识文件片段标记验证（syndrome-manual.md: 9 个症候标记；action-library.md: 12 个动作标记）

### 输出产物（实际完成时填写）

| 产物 | 说明 |
|------|------|
| DynamicContextService | 核心服务，实现知识片段按需装载 |
| 知识片段标记规范 | SYNDROME/ACTION/CASE 三种标记格式，支持按 ID 精确提取 |
| 三段式 Prompt 组装 | 核心层 + 按需层（症候+动作）+ 上下文层（学生状态） |
| 单元测试 14 个 | 覆盖片段提取、动作关联、核心 Prompt 装载、参考抽屉格式化、缓存清除等 |


## 下个任务建议

（完成后填写）
