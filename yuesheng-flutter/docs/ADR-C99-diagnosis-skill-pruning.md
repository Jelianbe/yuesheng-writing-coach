# ADR-C99 · narrative-design / plot-design 移出 diagnosis 常驻组（减编批次 2）

- **日期**：2026-09-23
- **性质**：**L2 组配置调整**——减编常驻上下文，不改变诊断核心能力
- **触发**：外部资料入库前上下文容量审计（2026-09-23）→ diagnosis 组 ~12k tokens，需为后续扩展腾空间
- **硬约束**：R-019（函数 ≤50 行）· R-027（Prompt 改动需确认）· AGENTS.md §7（涉核心模块先写 ADR）
- **上游**：
  - `docs/ADR-C98-editor-coordinate-model.md`（ADR 落点与镜像纪律先例）
  - `.ai/materials/2026-09-23-外部资料入库-总台账.md`（减编方案 §四）

---

## §0 一句话结论

**diagnosis 组移出 narrative-design + plot-design 两个 skill（~4000 tokens）**——它们是"从零构建故事"的引导工具，不是诊断工具；诊断场景下学员只是交文本找问题，不需要现场构建世界观/情节。结构性症候（P006/P015 等）的修复指导由 L3 症候详情（getSyndromeContent）承载，不依赖这两个常驻 skill。

---

## §1 证据链

### 1.1 两个 skill 的真实定位

| Skill | 定位（原文注释） | 诊断场景的实际使用率 |
|:--|:--|:--|
| narrative-design | "世界观/角色构建引导——叙事铁三角第一角" | 低——诊断时学员已有文本，不是从零构建 |
| plot-design | "情节/因果链构建引导——叙事铁三角第三角" | 低——同上 |

【事实】来自 `skills_beginner_p1.dart:269` / `skills_beginner_p2.dart:7` 的 meta 注释。

### 1.2 为什么 diagnosis 组加载了它们

【事实】来自 `skill_layers.dart:81-82`：
```dart
SkillRef('narrative-design', '诊断语境：核对世界观/角色构建是否薄弱，给可操作重建步骤'),
SkillRef('plot-design', '诊断语境：定位情节断裂/张力缺失，给因果链追问工具'),
```

加载理由是"诊断发现结构性问题时回退设计层"——但这是**偶发事件**，不是诊断主流程。常驻占 ~4000 tokens 不划算。

### 1.3 移出后诊断能力是否受损

【推断】不会。理由：
1. 结构性症候（P006 节奏停滞 / P015 高潮疲软 / P016 巧合滥用）的完整定义和推荐动作在 L3 知识库（syndrome_knowledge_base.dart）里，诊断锁定时通过 `getSyndromeContent` 按需注入
2. narrative-design/plot-design 提供的是"构建方法论"（怎么从零写），不是"诊断方法论"（怎么找问题）
3. 学员后续真要"回退到设计层"修复时，会进入 outline 或 beginner 模式，那时这两个 skill 在对应组里加载

---

## §2 改动范围

### 2.1 修改文件

- `lib/services/skill_layers.dart`：L2Mode.diagnosis 组去掉 narrative-design + plot-design 两行

### 2.2 不改动

- skill_registry.dart：两个 skill 的注册保留（outline/beginner 组仍用）
- syndrome_knowledge_base.dart：L3 症候详情不变
- 诊断核心逻辑：getSyndromeContent 链路不变

---

## §3 风险与回退

| 风险 | 缓解 |
|:--|:--|
| 诊断时 AI 对结构性问题的建议质量下降 | L3 症候详情已有推荐动作（A005/A009/A013），足够支撑基础建议 |
| 学员要求"怎么改"时 AI 给不出构建层面的指导 | 后续可加动态注入：诊断命中 P006/P015 时再注入这两个 skill 的内容 |
| 锚点测试挂 | UPDATE_SNAPSHOTS 重生成 |

**回退**：git revert 即可。

---

## §4 验收

- 门禁 12/12 全绿
- diagnosis 组常驻 tokens 从 ~12k → ~8k
- 锚点重生成通过

---
*本 ADR 镜像至 `.ai/DECISIONS.md §2`（按 ADR-C96 先例）。*
