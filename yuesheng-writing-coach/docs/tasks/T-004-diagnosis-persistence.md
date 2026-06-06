---
id: T-004
status: completed
follows: T-003
precedes:
started: 2026-06-01
completed: 2026-06-01
---

# T-004: 诊断结果持久化

## 目标

将每次 AI 诊断结果持久化到 SQLite，确保诊断数据可追溯、可查询，为后续长期能力表单提供数据基础。

## 设计哲学依据

- **设计哲学**: design-philosophy_V1.0.md 第五章「诊断表 + 长期能力表单」
- **技术规格**: SPEC_diagnosis-persistence_V1.0.md

## 涉及文件

| 文件 | 改动类型 |
|------|---------|
| `src/main/db/005_diagnosis.sqlite` | 新增 |
| `src/main/services/diagnosis.service.ts` | 新增 |
| `src/main/ipc/diagnosis.handler.ts` | 修改 |
| `src/main/index.ts` | 修改 |
| `src/main/services/__tests__/diagnosis.service.test.ts` | 新增 |

## DoD

- [ ] 诊断结果持久化到 SQLite 的 diagnosis_results 表
- [ ] 不改变现有 IPC 通道和前端行为
- [ ] 所有测试通过
- [ ] 类型检查零错误

## 变更溯源

- **设计哲学依据**: design-philosophy_V1.0.md 第五章
- **技术规格**: SPEC_diagnosis-persistence_V1.0.md

### 变更日志

| 日期 | 文件 | 变更内容 |
|------|------|---------|
| 2026-06-01 | — | 任务创建（待执行） |
