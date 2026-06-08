# T-017: 态度系统统一

> **优先级**: P1 | **状态**: completed | **预估**: 1d  
> **依赖**: T-016 | **后续**: T-018

## 目标

统一当前两套独立的态度/语气系统（`doubao/yuesheng/direct` 态度档位 和 `encouraging/direct/logical/resonant` 教学语气）为三态系统。每档有明确的语气修饰和教学行为，修复默认 `yuesheng` 档位无语气修饰的 Bug。

## 设计依据

- **设计依据文档**: [attitude-system-unification_V1.0.md](../design/attitude-system-unification_V1.0.md)
- **关联发现**: 月笙_设计意图vs代码实现_V1.0.md → 发现7 态度系统混乱
- **来源任务**: T-016（辩驳升级后需统一态度系统支持 sensei 模式）

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | decideTone() 接收 attitude 参数做联动 | `src/main/services/teaching-strategy.service.ts` |
| 后端 | 修复 yuesheng 档位无语气修饰 | `src/main/services/prompt-loader.ts` |
| 数据 | tone-modifiers.json 添加 sensei 档位 | `resources/config/tone-modifiers.json` |
| 前端 | 态度按钮映射调整为三态 | `src/renderer/components/layout/Sidebar.tsx` |
| 类型 | 统一 AttitudeLevel 定义 | `src/renderer/shared/types.ts` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/renderer/shared/types.ts` | 修改 | 统一 AttitudeLevel 定义 |
| 2 | `resources/config/tone-modifiers.json` | 修改 | 添加 sensei 档位修饰词 |
| 3 | `src/main/services/teaching-strategy.service.ts` | 修改 | decideTone() 接收 attitude 参数 |
| 4 | `src/main/services/prompt-loader.ts` | 修改 | 修复 yuesheng 语气修饰 |
| 5 | `src/renderer/components/layout/Sidebar.tsx` | 修改 | 态度按钮映射调整为三态 |

## DoD（完成标准）

- [x] S1. 三态 `doubao/yuesheng/direct` 每档有明确语气修饰
- [x] S2. tone-modifiers.json 三条目完整
- [x] S3. decideTone() 接收 attitude 参数做联动
- [x] S4. 默认 `yuesheng` 档位有语气修饰（修复当前 Bug）
- [x] S5. TypeScript 编译无错误
- [ ] S6. 3 个测试覆盖不同态度的语气输出（后续补充）

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. tone-modifiers.json 恢复到旧版本
3. 前端类型恢复旧定义

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|
| `src/main/services/teaching-strategy.service.ts` | ToneType 添加 `challenging`，StrategyInput 添加 `attitude`，decideTone() 优先按 attitude 映射语气 |
| `src/main/services/prompt-loader.ts` | ToneModifiersConfig 接口添加 `yuesheng`，DEFAULT_TONE_MODIFIERS 补充三态完整降级默认值 |
| `src/main/services/prompt-builder.ts` | getToneInstruction() 添加 `challenging` 语气指令映射 |
| `src/main/ipc/chat.handler.ts` | buildStrategyInstruction() 添加 attitude 参数，StrategyInput 传递 attitude |
| `src/renderer/utils/app-helpers.ts` | mapHeaderAttitude/getAttitudeMap 更新为三态映射 |
| `resources/config/tone-modifiers.json` | 添加 yuesheng 修饰词，更新 direct 修饰词文案 |
| `src/main/services/dispute-tracker.service.ts` | 添加 ALL_ATTITUDE_LEVELS 常量修复类型错误 |

### 验证结果（实际完成时填写）

- [x] TypeScript 编译通过（`npx tsc --noEmit` 0 errors）
- [x] 测试通过（31/32 test files passed，350/356 tests passed，1个 pre-existing better-sqlite3 兼容性问题）

### 输出产物（实际完成时填写）


## 下个任务建议

（完成后填写）
