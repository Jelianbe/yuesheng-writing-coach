# Changelog

> 月笙写作教练变更日志。版本号遵循语义化版本（semver）。

## [Unreleased]

## [1.1.0] - 2026-06-23

### Sprint 16 — 五步通用训练流贯通 (2026-06-22)

#### Added
- **训练流映射配置** `resources/config/training-flow-mapping.json`：6 类挑战 → 5 步流程模板
- **训练流加载器** `src/renderer/flow/training.flow.ts`：根据 challengeId 查 mapping，返回 5 步内容
- **五步训练流 UI**：
  - `FiveStepFlow` 主容器 + 进度条 + 导航
  - 5 个步骤面板：`StepExplain` / `StepExample` / `StepConfirm` / `StepTry` / `StepFeedback`
  - 步进指示器 `FlowStepIndicator`
- **填模板工具** `fillTechniqueTemplate()`：从 `technique-library.json` 动态取数据替换占位符
- **复制 resources 脚本** `scripts/copy-resources.cjs`：解决 tsc 后 dist/resources/ 缺失
- **22 个单元测试**（loader 13 + UI 3 + orchestrator 3 + 其他 3）

#### Changed
- **技法消费层过滤**：diagnosis-orchestrator 现在按 `activeSyndromeIds` 过滤技法池（BL-02）
- **训练流类型扩展** `types-training.ts`：新增 `flowType: 'flow5' | 'legacy'`
- **ActiveTrainingView** 支持 `flowType` 分支：5 步流 vs 旧 3 步流并存
- **workspaces-index.ts** 修正 import 路径：原本错误的 `./registry/...` → 正确的 `../components/right/workspaces/...`
- **RightPanel** 加 mount-once useEffect：补齐 `defaultOpen` 同步

#### Fixed
- **preload 白名单缺失** `src/preload/index.ts`：补回 4 个频道（`prescription:getAllStages` / `prescription:getStageProgress` / `prescription:getStageById` / `training:generateFlow`），原"Disallowed IPC channel" 错误
- **goNext 闭包陷阱**：`useState` 函数式 set 修复
- **业务字段名错**：`trainingFlow.content` → `trainingFlow.instruction`
- **setUserDraft 命名错**：`setUserDraft` → `updateDraft`
- **评估/submit UI 阻塞**：用 `queueMicrotask` 包裹不阻塞切换

#### Tech Debt (Sprint 17+ 候选)
- **BL-22: better-sqlite3 双版本** — npm rebuild 单一目标，dev/electron 二选一，配置缺失
- **BL-23: preload 共享白名单** — 硬编码与 `shared/constants.ts` 同步靠人
- **BL-19: 7 个 stub workspace 待实组件化**（Sprint 18 排期）

#### 门禁
- typecheck: 0 errors
- test: 42 files, 629 passed (4 skipped, Sprint 19 补)
- lint: 0 errors, 253 warnings (pre-existing)
