# 后备资料库（Reference / Knowledge Library）

AI 小说创作教学软件的**创作知识底座**。当 AI 教练（03-teaching）需要讲解某个创作原理、
展示好/坏范例、或决定「该怎么引导学员」时，从这里检索结构化知识卡作为补充数据。

> 与项目既有资源的关系：`01-diagnosis`（症候）、`02-prescription`（技法/能力节点）、
> `03-teaching`（教练策略）、`04-validation`（掌握度）、`05-retro`（案例）。本库是它们的
> **知识来源**，让教练的每句话都有出处、成体系、不臆断。

## 目录结构

```
06-reference-library/
├── schema.ts                 # 条目结构 TypeScript 类型（权威定义）
├── library-loader.ts         # 运行时检索 API（被 Teaching Agent 调用）
├── library-index.json        # 索引：分类树 + 症候/场景/关键词倒排（由脚本生成）
├── entries/
│   └── library-entries.json  # 知识卡全集（25 条，覆盖 C1–C7）
├── scripts/
│   ├── build-index.mjs       # 由 entries 重建 library-index.json
│   └── demo.mjs              # 检索路由演示 + 数据自检
├── retrieval-spec.md         # 检索与调用机制说明
└── README.md                 # 本文件
```

## 条目结构（知识卡字段）

| 字段 | 含义 |
|:---|:---|
| `id` | `REF-Cx-xxx` 唯一编号 |
| `title` | 标题 |
| `category` / `categoryLabel` | 一级分类 ID 与中文名（C1–C7） |
| `subcategory` | 二级子分类（可选） |
| `summary` | 一句话核心摘要 |
| `corePoints` | 核心要点（3–6 条） |
| `examples` | 示例片段 [{context, excerpt, analysis}] |
| `teachingTips` | 教学提示（AI 教练如何用这条知识引导，体现教练哲学） |
| `relatedSyndromes` | 关联诊断症候（P001–P012），用于「诊断→资料」路由 |
| `relatedTechniques` | 关联技法（TQ-/TC-），用于「资料→练习」链路 |
| `difficulty` | beginner / intermediate / advanced |
| `retrievalKeywords` | 检索关键词 |
| `scenarios` | 可服务的教学场景 |
| `externalRefs` | 外部参考书（仅书名/作者/框架，不编造原文） |

## 检索 API（`library-loader.ts`）

- `getBySyndrome(syndromeId)` —— 诊断症候路由
- `getByCategory(categoryId)` —— 浏览/扩展阅读
- `getByScenario(scenario)` —— 教学场景路由
- `search(query, opts)` —— 关键词/语义检索（CJK 友好）
- `getForTeachingContext(ctx)` —— **核心 API**：加权合并三路、去重、排序，输出 `InjectableReference[]`

## 常用命令

```bash
# 重建索引（新增/修改条目后必须运行）
node scripts/build-index.mjs

# 路由演示 + 数据自检
node scripts/demo.mjs
```

## 扩写资料库

1. 往 `entries/library-entries.json` 追加条目（遵循 `schema.ts` 字段）。
2. `node scripts/build-index.mjs` 重建索引（症候/场景映射与倒排索引自动派生）。
3. `node scripts/demo.mjs` 自检字段完整性与路由结果。
4. 无需改动 `library-loader.ts` —— 接口与索引自动生效。
