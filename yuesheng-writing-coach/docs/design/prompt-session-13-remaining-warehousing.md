# 会话13：剩余蒸馏入库（T-032）

## ⚠️ 项目背景（必读）

月笙写作教练（Electron + React + TypeScript + SQLite），`technique-library.json` 目前已有 107 条技法（TQ-001~TQ-073 + TC-001~TC-015 + TN-001 + TE-001~TE-018）。编号已用到 TE-018。

**你的任务**：将 WinkNovel 和 InkoS 蒸馏产出的教学零件中可归入技法库的部分追加到 `technique-library.json`。

---

## 入库内容

### WinkNovel 教学零件（12 条，全部入库）

基于 [distillation-winknovel_V1.md](file:///D:/ai-teacher/yuesheng-writing-coach/docs/teaching/distillation-winknovel_V1.md) 的 TP-001~TP-012。

每条已有：核心技法、经典案例、刻意练习、评估标准、常见错误。

### InkoS 教学零件（评估后入库）

基于 [ai-tool-distillation/V1.0.md](file:///D:/ai-teacher/yuesheng-writing-coach/docs/research/ai-tool-distillation/V1.0.md) 的 TP-013~TP-024。

**可入库**（约 7 条）：
- TP-015 写作心法十四条 → 拆分为 3-4 条技法（每条提炼 2-3 条原则）
- TP-017 断在上升沿法则 → 节奏类
- TP-018 看点密度自检法 → 节奏类
- TP-019 角色行为推导法 → 角色类
- TP-021 伏笔生命周期管理 → 剧情类
- TP-022 写作前信息整理法 → 表达类
- TP-023 伏笔追踪表 → 剧情类

**不入库**（已由 T-030 处理为系统功能）：
- TP-013 37维度结构化反馈框架 → 系统功能
- TP-014 写作前七问规划法 → 系统功能
- TP-016 AI味四维识别法 → 系统功能
- TP-020 明线暗线设计法 → 系统功能（与 TP-021 合并为伏笔管理）
- TP-024 开篇三章写作指南 → 系统功能

---

## 编号规范

| 来源 | 范围 | 数量 |
|:----|:----:|:----:|
| WinkNovel（TP-001~TP-012） | **AIP-001~AIP-012** | 12 |
| InkoS 可入库（TP-015/017~019/021~023） | **AIP-013~AIP-019** | 7（约） |

**AIP** = AI Prompt (tool) — 区别于 TQ(小说)、TC(网文创作)、TE(外部教学)

---

## 入库格式

必须与 JSON 中已有 TE-018 的格式完全一致：

```json
{
  "id": "AIP-001",
  "name": "世界观五维构建法",
  "source": "WinkNovel 世界观构建体系",
  "sourceAuthor": "WinkNovel",
  "sourceType": "ai_tool",
  "difficulty": "intermediate",
  "category": "世界观",
  "applicableSyndromes": ["P001", "P004"],
  "coreIdea": "一句话概括核心价值（20字内）",
  "description": "降级讲解+核心技法要点（100-200字，用大白话，不写编码内容）",
  "teachingLogic": "WinkNovel 通过 100+ 问题问卷引导用户系统构建世界观，此处提取为可独立执行的技法",
  "example": "经典案例（选 TP 条目中已有的案例，精简到 50-100 字）",
  "exercise": "刻意练习（直接使用 TP 条目中的练习，50字内）",
  "coreId": "分配核心模式标识",
  "coreName": "核心模式名称",
  "difficultyOrder": 1,
  "genreScope": "通用"
}
```

### category 可选值

世界观、角色、节奏、开篇、情绪、场景、对话、视角、剧情、表达、其他

### coreId/coreName 可选值

已有：`show-dont-tell`/展示而非告知, `suspense-engine`/悬念驱动, `pov-control`/视角控制, `structure-innovation`/结构创新, `worldbuilding-embed`/设定融入, `character-depth`/角色立体化, `dialogue-depth`/对话层次, `rhythm-control`/节奏呼吸, `opening-hook`/开篇钩子, `negative-example`/反面教材

世界观类 → `worldbuilding-embed`
节奏类 → `rhythm-control` 或 `suspense-engine`
角色类 → `character-depth`
剧情类 → `suspense-engine`
表达类 → `show-dont-tell`

### difficulty/difficultyOrder

- `beginner` → 1
- `intermediate` → 2  
- `advanced` → 3

难度判断标准：
- **beginner**：直接可操作的清单/模板类（如人物卡、自检表）
- **intermediate**：需要练习才能掌握的方法（如三-五-十节奏骨架）
- **advanced**：需要有写作经验才能理解的高级概念（如叙事线索管理）

---

## 验证

- `npx tsc --noEmit` 通过
- JSON 格式正确

## 休止符条件

- [ ] WinkNovel 12 条（AIP-001~AIP-012）全部入库
- [ ] InkoS ~7 条（AIP-013~AIP-019）评估后入库
- [ ] 入库格式与 TE-018 完全一致
- [ ] TSC 通过
- [ ] index_V1.md 已用追加的条目名称同步

完成后把以下文件带回来：
- `technique-library.json`（追加后的完整文件）
- `index_V1.md`（同步更新）
