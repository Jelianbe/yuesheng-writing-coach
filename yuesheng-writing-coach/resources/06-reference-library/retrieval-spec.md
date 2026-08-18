# 后备资料库 · 检索与调用机制（Retrieval & Invocation Spec）

> 配套文件：`library-loader.ts`（运行时 API）、`library-index.json`（索引）、`entries/library-entries.json`（知识卡）。
> 设计目标：让 AI 教学系统在不同场景下，精准、系统地把「创作知识」作为补充数据注入教练上下文。

---

## 1. 资料库在资源管线中的位置

```
01-diagnosis  →  02-prescription  →  03-teaching  →  04-validation  →  05-retro
  (症候 P00x)      (技法 TQ/能力AB)     (教练话术)       (掌握度挑战)       (案例复盘)
        │                │                  ▲
        │                │                  │ 取用
        └────────────────┴──── 06-reference-library（创作知识库）──┘
                                 (知识卡 REF-Cx-xxx)
```

- **01-diagnosis** 回答「哪里错了」（症候）。
- **02-prescription** 回答「练什么」（技法/能力节点）。
- **06-reference-library** 回答「这件事的创作原理是什么、好/坏范例长什么样、教练该怎么讲」——它是前两者的**知识底座**，让教练的每句话都有出处、成体系、不臆断。
- **03-teaching** 在生成话术前，调用本库组装 `availableReferences`，与现有 `availableTechniques` 并列注入。

---

## 2. 检索路由（三条主路径）

| 路由 | 触发条件 | API | 典型场景 |
|:---|:---|:---|:---|
| **症候路由** | 诊断给出 `primarySyndrome`（如 `P009`） | `getBySyndrome(syndromeId)` | 诊断后讲解根因 |
| **场景路由** | 进入某教学场景（如 `onboarding`） | `getByScenario(scenario)` | 新用户引导、训练前铺垫 |
| **查询路由** | 用户自由提问 / 上下文含关键词 | `search(query)` | 对话内即时教练、扩展阅读 |

主 API `getForTeachingContext(ctx)` 将上述三路**加权合并、去重、排序**：

```
权重：症候命中 +10  ＞  场景命中 +5  ＞  自由查询命中 +2
取 Top-N（默认 6）→ 映射为 InjectableReference → 注入 Teaching Agent
```

加权设计保证：**诊断症候命中的资料永远优先**（根因优先于泛讲），场景资料兜底，查询资料补位。

---

## 3. 注入形态（对齐现有契约）

Teaching Agent 的输入 JSON 在 `availableTechniques` 旁新增 `availableReferences`：

```json
{
  "diagnosisResult": { "primarySyndrome": "P009", "syndromeName": "角色动机缺失" },
  "availableTechniques": [ { "id": "TQ-045", "method": "动机外化法", "summary": "…" } ],
  "availableReferences": [
    {
      "id": "REF-C2-002",
      "title": "动机设计：想要 vs 需要 + 谎言/创伤/真相",
      "summary": "驱动人物的不是『目标』一个词，而是…",
      "corePoints": ["想要（外部目标）…", "需要（内在真知）…", "谎言…", "创伤…", "真相…"],
      "examples": [ { "context": "史莱克", "excerpt": "…", "analysis": "…" } ],
      "teachingTips": ["动机缺失时，先问『ta做这个选择是因为想要什么…』", "…"],
      "difficulty": "intermediate"
    }
  ],
  "studentProfile": { "level": "新手", "projectType": "玄幻", "projectStatus": "第一章创作中" }
}
```

Teaching Agent 据此：
- 用 `corePoints` 校准自己讲的知识点是否准确、成体系；
- 用 `examples.excerpt + analysis` 做**对比展示**（好/差范例），而非凭空编造；
- 用 `teachingTips` 约束姿态——**只引导、不代写、不替决定**，并回扣诊断根因；
- 绝不把 `REF-xxx` 编号或内部字段暴露给学员（遵循 teaching-agent 既有纪律）。

---

## 4. 教练哲学护栏（硬性）

1. **不替写、不替决定**：`teachingTips` 字段强制以「引导性提问 / 让学员自己试」为落点，禁止出现「你应该这样写」。
2. **找根因**：资料卡必须能解释「为什么这是问题」，而非只给结论。
3. **引用纪律**：`externalRefs` 只写书名/作者/方法论框架（沿用 `external-resources.json` 规则），**不编造章节、页码、原文**。
4. **可溯源**：每条 `InjectableReference` 携带 `id`，复盘/调试时可反查知识卡原文。

---

## 5. 可演进性

- 当前 `search()` 为关键词/倒排索引召回（轻量、确定、可离线）。**接口不变**的前提下，可平滑替换为向量检索（embedding + ANN），无需改动 Teaching Agent 调用方。
- 新增知识卡：往 `entries/library-entries.json` 追加条目 → 运行 `node scripts/build-index.mjs` 重建索引即可，无需改代码。
- 症候/场景映射由索引自动派生，新增症候只需在条目 `relatedSyndromes` 标注。
