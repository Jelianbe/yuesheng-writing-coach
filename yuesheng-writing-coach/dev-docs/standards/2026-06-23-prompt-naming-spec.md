# 命名规范草案 — 提示词与 Skill 资产

> **Sprint**: 11 资产普查产出
> **状态**: 草案（不执行，仅文档）
> **目标**: 为 Sprint 12 提示词工程统一 + 后续资源归档提供命名基线

---

## 一、范围

本规范适用于：
- `resources/prompts/**` 下的所有 prompt 文件
- `resources/{01-05}/**` 下的 prompt / config / signal 文件
- 5 个 SKILL-*.md 拆分产物
- 项目自有的 `.trae/skills/**` 下的 skill 文件

不适用于：
- `.agents/skills/`、`.claude/skills/`、`.qoder/skills/`（系统级 IDE skills，与项目无关）
- `node_modules/`、`dist/`、`build/`（构建产物）
- `__tests__/`（测试代码）

---

## 二、命名约束

### 2.1 文件名规则

| 类型 | 规则 | 示例 |
|------|------|------|
| **agent prompt** | `{role}-prompt[-v{N}].md` | `teaching-agent-prompt-v2.md` |
| **拆分 skill** | `SKILL-{NAME}.md`（v4 风格） | `SKILL-IDENTITY.md` |
| **配置文件** | `{purpose}.json` | `teaching-rules.json` |
| **映射表** | `{from}-to-{to}-map.json` | `syndrome-action-map.json` |
| **信号/症候** | `signal-weight-matrix.json`、`syndrome-manual.md` | 同上 |
| **临时/草稿** | `{name}-草案.md` 或 `{name}.draft.md`（仅限未发布）| 评估后立即归并或归档 |

### 2.2 大小写

- **小写 + 连字符**（kebab-case）为主
- 例外：`SKILL-*.md` 全大写前缀（v4 风格，承载"模块"语义）
- **禁止**：camelCase、snake_case、PascalCase 混合

### 2.3 版本后缀

- **正式版**：`-v{N}.md`（如 v1、v2、v3）
- **草案**：`-草案.md`（中文）或 `.draft.md`（英文）
- **归档**：`.archive.md` 或归档到 `archive/` 子目录
- **快照**：`@{YYYY-MM-DD}.md`（特定日期快照）

### 2.4 长度限制

- 文件名 ≤ 50 字符（不含扩展名）
- 路径总长 ≤ 200 字符（含目录）

---

## 三、路径约定

### 3.1 单点 vs 多点

| 场景 | 位置 | 理由 |
|------|------|------|
| **项目主 prompt** | `resources/prompts/{name}.md` | 全项目唯一真源 |
| **领域 prompt** | `resources/{domain}/prompts/{name}.md` | 仅供该 domain 使用 |
| **领域 config** | `resources/{domain}/config/{name}.json` | 配置数据 |
| **领域 signal** | `resources/{domain}/signals/{name}.md` | 信号源材料 |

**冲突处理**：当一个文件存在于 `resources/prompts/` 和 `resources/{domain}/prompts/` 两处时：
1. `resources/prompts/` 视为**主位置**（全项目可见）
2. `resources/{domain}/prompts/` 视为**领域特化**（仅该 domain 使用）
3. 两者内容不一致时，主位置优先 + 在领域特化顶部加 `# DEPRECATED: 见 resources/prompts/{name}.md`

### 3.2 拆分产物归档

- 拆分产物（如 v4 的 5 个 SKILL-*.md）应归档到 `resources/archive/prompts/{name-vN}/`
- 不得散落在 `prompts/skills/` 和 `{domain}/prompts/skills/` 多处

### 3.3 IDE skills 副本

- 项目自有 skill 放 `.trae/skills/{name}/SKILL.md`
- 系统级 IDE skill 放 `.agents/skills/`、`.claude/skills/`、`.qoder/skills/`
- 4 个 IDE 目录的相同 skill 应通过 git submodule 或符号链接共享，不重复拷贝

---

## 四、废弃规则

| 后缀 | 含义 | 处置 |
|------|------|------|
| `-v1.md` + 同时存在 `-v2.md` | v1 已废 | 归档到 `archive/prompts/{name}-v1/` |
| `-草案.md` | 草稿 | 评估后 1 周内：合并入正式版 OR 归档 |
| `.bak` | 备份 | 删除（git 历史保留） |
| `.tmp` | 临时 | 立即删除 |
| `@{date}.md` | 快照 | 归档到 `archive/snapshots/{date}/` |

---

## 五、版本控制规则

1. **每次重大更新**必须升级版本号（v1 → v2）
2. **旧版本不删除**，归档到 `archive/prompts/{name}-v{N}/`
3. **commit 信息**引用对应的 ADR（如 `Refs: ADR-003`）
4. **占位符**统一双花 `{{xxx}}`（R-026）

---

## 六、待澄清（草案状态）

- [ ] 是否允许 `resources/{domain}/prompts/{name}.md` 与 `resources/prompts/{name}.md` 内容不同？
- [ ] IDE skills 共享方案（submodule vs symlink vs 复制）的最终选择
- [ ] `core-principles.md`、`teacher-prompt.md`、`clown-prompt.md` 是否独立文件还是合并？
- [ ] `diagnosis-agent-prompt-v2.md` 在 `resources/01-diagnosis/` 与老位置 `resources/prompts/` 的关系

---

## 七、与现有规则的关系

| 规则 | 关系 |
|------|------|
| R-019 代码规范 | 一致（行数、命名风格） |
| R-014 配置外置 | 一致（json 配置 + 命名规范） |
| R-025 Prompt 治理 | 一致（版本控制、归档） |
| R-026 Prompt 工程规范 | 扩展（具体文件命名） |

---

## 八、Sprint 12 应用计划

Sprint 12 提示词工程统一时，将按本规范：
1. 5 个 SKILL-*.md 合并到 `resources/prompts/yuesheng-prompt-v5.md`
2. v3 单体归档到 `resources/archive/prompts/yuesheng-prompt-v3.md`
3. 跨域同名文件去重（按 §3.1 冲突处理）
4. 命名异常清理（§四 废弃规则）

---

## 变更历史

| 版本 | 日期 | 变更 |
|:----:|:----:|------|
| v0.1 | 2026-06-23 | 初版（基于 Sprint 11 普查数据） |
