# Sprint 11 Plan — 资产普查

> **Sprint**: 11
> **Stage**: GStack Plan
> **Issue**: #16
> **Design**: 005 — 提示词逆转 + 教育链路重整
> **状态**: 待批准

---

## 一、Plan 目标

为 Sprint 12 提示词工程统一提供**完整、准确、可信**的资产盘点基线，避免盲目动手。

Sprint 11 是**只读 + 文档**任务，无代码改动。

---

## 二、任务拆分（执行顺序）

### T11-1 扫描脚本（临时工具）
- **产物**: `scripts/audit-prompt-assets.mjs`（一次性脚本，commit 后可保留）
- **输入**: `resources/prompts/**`, `resources/01-05/**`, `.trae/.agents/.claude/.qoder/skills/**`
- **输出**: stdout JSON，含 path/size/version/last_modified/hash
- **行数**: ≤100 行（Node.js fs 遍历）
- **依赖**: 0（纯 Node.js）

### T11-2 资产清单
- **产物**: `dev-docs/audits/2026-06-23-prompt-asset-inventory.md`
- **内容**:
  - 表 1：所有 prompt 文件清单（path/size/version/last_modified/hash）
  - 表 2：所有 skill 文件清单（同上）
  - 表 3：所有 config 文件清单（user-type-matrix.json 等）
- **格式**: Markdown 表格
- **来源**: T11-1 输出

### T11-3 重复文件标记
- **产物**: T11-2 文件内嵌章节 "重复文件"
- **判定规则**:
  - SHA-256 hash 一致 → 完全重复
  - 内容 diff 相似度 > 95% → 近似重复
- **输出**: 表格（hash/group/file_a/file_b/action）

### T11-4 命名规范 PR 草案
- **产物**: `dev-docs/standards/2026-06-23-prompt-naming-spec.md`
- **内容**:
  - 命名约束（小写 + 连字符 + 无缩写歧义 + 版本号后缀）
  - 路径约定（`prompts/` vs `prompts/{domain}/` 何时用哪个）
  - 废弃规则（v1/v2/draft/bak 何时归档）
  - PR 草案状态：仅文档，不执行
- **行数**: ≤150 行

### T11-5 决策日志更新
- **产物**: `decision-log.md`（项目根或 dev-docs）
- **新条目**: "2026-06-23 — 为什么先做资产普查再动手"
- **内容**: 4 段（决策/原因/范围/风险/验证/回退）

### T11-6 门禁验证
- **产物**: 命令输出（typecheck + test + lint）
- **期望**: 全绿（无代码改动也应绿）

---

## 三、关键决策点（需用户确认）

| # | 决策 | 默认 | 备选 |
|:-:|------|:----:|------|
| 1 | 扫描脚本语言 | Node.js (.mjs) | PowerShell / Python |
| 2 | 扫描范围 | 3 棵（resources/01-05/、resources/prompts/、.trae/.agents/.claude/.qoder/skills/） | 1 棵（只 resources/prompts/） |
| 3 | 重复判定阈值 | hash 完全一致 + 95% 相似度 | 仅 hash 一致 |
| 4 | 命名规范 | 草案状态（不执行） | 草案 + 立即执行 |
| 5 | 决策日志位置 | dev-docs/decision-log.md | 项目根 decision-log.md |
| 6 | 扫描脚本 commit | 保留作为 dev tool | 用完即删 |

---

## 四、文件清单

**新建**:
- `scripts/audit-prompt-assets.mjs`
- `dev-docs/audits/2026-06-23-prompt-asset-inventory.md`
- `dev-docs/standards/2026-06-23-prompt-naming-spec.md`

**更新**:
- `dev-docs/decision-log.md`（追加条目）

**未触碰**:
- 任何 src/ 代码
- 任何 resources/ 文件
- 任何 .trae/ IDE 配置

---

## 五、执行顺序

```
T11-1 扫描脚本 ─┬─→ T11-2 资产清单 ─→ T11-3 重复标记 ─┐
                │                                       ├─→ T11-5 决策日志
                └─→ T11-4 命名规范草案 ──────────────────┘
                                                        ↓
                                              T11-6 门禁验证
```

---

## 六、DoD 验证（对应 Issue #16 DoD）

| Issue DoD | 验证方式 | 期望产物 |
|-----------|----------|----------|
| D0-1 100% 资产清单 | T11-1 + T11-2 | inventory.md 含 3 表 + 计数 ≥ 真实文件数 |
| D0-2 重复文件列表 | T11-3 | inventory.md 内嵌重复章节 ≥ 1 组（按 hash） |
| D0-3 命名规范 PR 草案 | T11-4 | naming-spec.md ≤ 150 行 |
| D0-4 决策日志 | T11-5 | decision-log.md 含 "2026-06-23" 条目 |
| D0-5 门禁全绿 | T11-6 | typecheck && test && lint 零 error |

---

## 七、风险与缓解

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| 扫描脚本漏文件 | 低 | 列出扫描根 + 递归 glob 验证 |
| 扫描脚本误报重复 | 低 | diff 二次确认 + 人工 spot check |
| 命名规范争议 | 低 | 仅草案，不执行 |
| 决策日志未找到文件 | 中 | 找不到则在 T11-5 时新建 |
| 门禁失败（无代码改动） | 低 | Sprint 9 已知全绿，理论上 Sprint 11 也应绿 |

---

## 八、回退路径

Sprint 11 只新增文档和扫描脚本，不修改任何 src/ 或 resources/。

回退 = `git revert <sprint-11-merge-commit>`，无副作用。

---

## 九、时间盒

- 估时: **S**（半天内可完成）
- 不承诺具体时间，按"门禁全绿 + DoD 满足"判断完成

---

## 十、检查清单（声称完成前必跑）

```
□ scripts/audit-prompt-assets.mjs 运行无错误？
□ dev-docs/audits/2026-06-23-prompt-asset-inventory.md 含 3 表 + 重复章节？
□ dev-docs/standards/2026-06-23-prompt-naming-spec.md ≤ 150 行？
□ decision-log.md 含 "2026-06-23" 条目？
□ npm run typecheck && npm test && npm run lint 全绿？
□ 4 个新建文件 commit（按 R-016 拆 commit）？
```

---

## 十一、Plan 批准门

Plan doc 已就绪。**请确认后开始 Build**：
- 接受 → 我说"开始 Sprint 11 Build"或"开始执行 Sprint 11"
- 调整 → 你说哪里改
