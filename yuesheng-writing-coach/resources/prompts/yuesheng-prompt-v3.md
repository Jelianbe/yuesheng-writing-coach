<!--
Version: v4.0.0
Date: 2026-06-15
Change: Skill 工程化 — 拆分为 5 个独立 Skill + 动态组装逻辑
Trigger: V4-SKILL-3 Skill切分方案设计
Rollback: git checkout prompt/v3.9.0 -- resources/prompts/yuesheng-prompt-v3.md
-->
# 月笙 MVP Prompt V4.0

> 核心设计：Skill 工程化 — 5 个独立 Skill + 动态组装
> V4.0：从单体 Prompt 拆分为模块化 Skill 架构

---

## 架构概览

本 Prompt 已拆分为 5 个独立 Skill，按条件动态加载：

| Skill | 加载条件 | 预估字数 |
|-------|---------|----------|
| **SKILL-IDENTITY** | ALWAYS（始终加载） | ~800字 |
| **SKILL-TEACHING** | ALWAYS（始终加载） | ~1200字 |
| **SKILL-VALIDATION** | ALWAYS（始终加载） | ~800字 |
| **SKILL-FEEDBACK** | CONDITIONAL（训练阶段） | ~600字 |
| **SKILL-SCENARIO** | CONDITIONAL（触发关键词） | ~1100字 |

---

## 动态组装逻辑

```typescript
// 伪代码：Skill 路由
function buildPrompt(studentContext: StudentContext, conversationPhase: Phase): string {
  const coreSkills = [
    SKILL_IDENTITY,      // 始终加载
    SKILL_TEACHING,      // 始终加载
    SKILL_VALIDATION     // 始终加载
  ];
  
  const conditionalSkills = [];
  
  // 条件加载：训练阶段
  if (conversationPhase === 'TRAINING' || conversationPhase === 'FEEDBACK') {
    conditionalSkills.push(SKILL_FEEDBACK);
  }
  
  // 条件加载：场景触发
  if (hasTriggerKeywords(userInput, ['帮我写', '续写', '润色', '合作', '发平台'])) {
    conditionalSkills.push(SKILL_SCENARIO);
  }
  
  return [
    L3_STUDENT_CONTEXT,  // 动态注入
    ...coreSkills,
    ...conditionalSkills
  ].join('\n\n');
}
```

---

## Skill 文件位置

```
resources/prompts/
├── skills/
│   ├── SKILL-IDENTITY.md      # 身份与底线
│   ├── SKILL-TEACHING.md      # 教学策略
│   ├── SKILL-VALIDATION.md    # 输出验证
│   ├── SKILL-FEEDBACK.md      # 认知反馈
│   └── SKILL-SCENARIO.md      # 场景规则
└── yuesheng-prompt-v3.md      # 本文件（组装说明）
```

---

## 触发关键词映射

| Skill | 触发条件 | 关键词/状态 |
|-------|----------|-------------|
| SKILL-FEEDBACK | 教学阶段 = TRAINING/FEEDBACK | `teachingState.phase === 'TRAINING'` |
| SKILL-SCENARIO | 用户输入包含代笔请求 | `帮我写\|续写\|润色\|合作\|发平台` |

---

## 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| Skill 间依赖冲突 | 教学策略与输出验证可能矛盾 | 明确优先级：IDENTITY > VALIDATION > TEACHING |
| 动态加载延迟 | 首次触发场景规则时可能遗漏 | 预加载关键词检测，提前 1 轮注入 |
| Token 节省不达预期 | 始终加载的 3 个 Skill 已占 ~2800字 | 后续可进一步精简 SKILL-TEACHING |

---

**版本**：V4.0
**字数**：~4500字（拆分为 5 个 Skill，主文件仅保留组装说明）

**变更**：
- V3.5：应用 PE-005 约束三明治
- V3.6：输出验证段扩展（V-01~V-08）
- V3.7：三处 Prompt 断裂修复
- V3.8：防御点落地（教学法反例库 v2.3）
- V3.9：基线评估改进
- **V4.0：Skill 工程化 — 拆分为 5 个独立 Skill + 动态组装逻辑**
