# T-011: 能力画像文字化

> **优先级**: P1  
> **状态**: ready  
> **预估工时**: 2d  
> **依赖**: T-008（学生模型桥接）✅、T-009（Strategy Service）✅、T-010（PromptBuilder 改造）✅  
> **前端组件**: 需要（学生画像展示优化）

---

## 一、任务目标

将学生模型中的能力等级、认知风格、症候画像等结构化数据，翻译为可读的自然语言描述，用于：
1. 前端展示学生画像时使用文字化描述（而非枚举值）
2. System Prompt 注入时使用文字化描述（AI 更容易理解）

---

## 二、变更溯源

### 依据链
- **设计哲学**：`teaching-knowledge-bridge_V1.0.md` §八 Phase E
- **技术规格**：`student-model-redesign_V1.0.md` §3.2 toPromptText()
- **前置任务**：T-008（StudentModelService 已创建）、T-009（策略服务）、T-010（PromptBuilder 改造）

### 问题陈述
当前学生模型返回的是枚举值（`beginner`/`analytical`/`P001`），前端展示和 System Prompt 都缺少可读的自然语言描述。文字化的好处：
1. 前端用户能直观理解自己的学习状态
2. AI 更容易理解自然语言（"新手期，经常犯致命错误" vs `proficiency: beginner`）
3. 为后续"一句话成长记录"功能提供基础

---

## 三、涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/main/services/student-model.service.ts` | 修改 | 新增 `describeProficiency()`、`describeCognitiveStyle()`、`describeSyndromeProfile()` 方法 |
| `src/main/services/student-model.service.ts` | 修改 | `toPromptText()` 使用新方法增强描述 |
| `src/main/ipc/student-model.handler.ts` | 新增 | IPC 处理器，暴露学生画像查询接口 |
| `src/renderer/src/pages/ChatPage.tsx` 或相关组件 | 修改 | 学生画像展示使用文字化描述 |
| `src/main/services/__tests__/student-model.service.test.ts` | 新增 | StudentModelService 文字化方法测试 |

---

## 四、DoD（完成标准）

### 标准 1：文字化方法实现
- [ ] `describeProficiency()` 返回可读描述（如"你正处于模仿期，偶尔能写出不错的段落，但有时还会出现较严重的问题"）
- [ ] `describeCognitiveStyle()` 返回可读描述
- [ ] `describeSyndromeProfile()` 返回症候画像的总结性文字（而非结构化数据）
- [ ] 文字描述从 JSON 配置读取，不在代码里硬编码（配置外置规范）

### 标准 2：前后端集成
- [ ] `toPromptText()` 使用文字化描述增强输出
- [ ] `toRendererView()` 返回文字化版本
- [ ] 新增 IPC 通道暴露学生画像查询
- [ ] TypeScript 编译无错误（`tsc --noEmit`）

### 标准 3：测试覆盖
- [ ] 新增至少 6 个单元测试覆盖文字化方法
- [ ] 测试覆盖：不同能力等级、不同认知风格、有/无症状象
- [ ] 所有测试通过（`npm test`）

---

## 五、实现方案

### 5.1 新增配置：`student-profile-descriptions.json`

```json
{
  "$source": "teaching-knowledge-bridge_V1.0.md §八 Phase E",
  "proficiency": {
    "beginner": "你正处于模仿期，偶尔能写出不错的段落，但有时还会出现较严重的问题。",
    "intermediate": "你已有一定基础，能识别大多数问题，但在某些复杂场景下仍需指导。",
    "advanced": "你已具备成熟的写作能力，现在适合挑战更高难度的创作技巧。"
  },
  "cognitiveStyle": {
    "analytical": "你更擅长从逻辑和结构角度理解问题，喜欢系统化的分析方法。",
    "emotional": "你更擅长从感受和情感共鸣中学习，通过案例体验效果更好。",
    "mixed": "你兼具逻辑分析和情感体验两种学习方式，可以根据情况灵活切换。"
  }
}
```

### 5.2 StudentModelService 新增方法

```typescript
describeProficiency(level: ProficiencyLevel): string {
  const config = this.loadDescriptionsConfig();
  return config.proficiency[level] ?? '';
}

describeCognitiveStyle(style: CognitiveStyle): string {
  const config = this.loadDescriptionsConfig();
  return config.cognitiveStyle[style] ?? '';
}

describeSyndromeProfile(profile: Record<string, SyndromeAggregation>): string {
  // 将症候画像总结为一句话
  // 例："目前最需要关注的问题是：角色动机缺失（致命伤）"
}
```

### 5.3 IPC 通道

```typescript
// 新增 IPC 通道
IPC_CHANNELS.STUDENT_PROFILE_GET = 'student:profile:get'
// 返回: { proficiencyDesc, cognitiveStyleDesc, syndromeSummary, stats }
```

---

## 六、回退方案

如果文字化描述影响 PromptBuilder 的现有行为：
1. 保持 `toPromptText()` 的现有格式不变
2. 文字化方法仅用于前端展示和新 IPC 通道
3. 后续通过 A/B 测试验证文字化描述的效果

---

## 七、变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-05 | 初始任务文档创建 |
