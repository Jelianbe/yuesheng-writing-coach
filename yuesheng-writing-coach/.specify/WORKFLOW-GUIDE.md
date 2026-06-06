# 月笙写作教练项目 - Spec Kit 工作流指南

## 📁 目录结构

```
yuesheng-writing-coach/
└── .specify/
    ├── constitution.md              # 项目原则（已创建）
    ├── templates/
    │   └── overrides/               # 项目特定模板覆盖
    │       ├── spec-template.md     # 功能规范模板
    │       └── plan-template.md     # 技术实现计划模板
    └── WORKFLOW-GUIDE.md            # 本文件
```

## 🔄 Spec-Driven 开发流程

### 阶段 1: 建立原则 (Constitution)
✅ **已完成** - `.specify/constitution.md`

### 阶段 2: 创建规范 (Specify)
```
1. 复制 .specify/templates/overrides/spec-template.md
2. 重命名为 specs/<功能名称>-spec_V1.0.md
3. 填写"什么"和"为什么"，不写"如何做"
4. 提交审核
```

**存储位置**: `yuesheng-writing-coach/docs/specs/`

### 阶段 3: 制定计划 (Plan)
```
1. 复制 .specify/templates/overrides/plan-template.md
2. 重命名为 docs/plans/<功能名称>-plan_V1.0.md
3. 填写"如何做"，包含技术选型、架构设计
4. 提交审核
```

**存储位置**: `yuesheng-writing-coach/docs/plans/`

### 阶段 4: 拆分任务 (Tasks)
```
1. 根据实现计划拆分可独立测试的小任务
2. 每个任务对应一个提交
3. 任务间有明确依赖关系
```

### 阶段 5: 实施 (Implement)
```
1. 按任务列表逐个完成
2. 每个任务完成后运行测试
3. 所有任务完成后运行完整测试套件
4. 提交 PR，人工审查
```

## 📝 工作流示例

### 示例：开发"诊断面板"功能

```
1. 创建规范: docs/specs/diagnosis-panel-spec_V1.0.md
   → 描述"用户需要看到诊断结果"
   → 不描述"如何实现"

2. 创建计划: docs/plans/diagnosis-panel-plan_V1.0.md
   → 描述"使用 Zustand 管理诊断状态"
   → 描述"IPC 通道：diagnosis:get"
   → 描述"组件结构"

3. 拆分任务:
   → Task 1: 创建 diagnosis.store.ts
   → Task 2: 创建 IPC handler
   → Task 3: 创建 UI 组件
   → Task 4: 编写测试

4. 实施:
   → 逐个完成任务
   → 每个任务独立提交
```

## ✅ 检查清单

### 创建规范前
- [ ] 已阅读 constitution.md
- [ ] 明确功能目标和范围
- [ ] 识别相关利益方

### 创建计划前
- [ ] 规范已通过审核
- [ ] 技术选型明确
- [ ] 架构设计清晰

### 实施前
- [ ] 计划已通过审核
- [ ] 任务列表已拆分
- [ ] DoD 已定义（至少 3 条可验证标准）

### 提交 PR 前
- [ ] 所有测试通过
- [ ] 代码审查通过（使用月笙代码审查 Skill）
- [ ] 文档已同步更新

## 🔗 相关文档

- [项目开发规则汇总](../.trae/rules/月笙项目开发规则汇总.md)
- [PRD](../docs/PRD_月笙写作教练_V1.0.md)
- [开发计划](../docs/development-plan.md)
