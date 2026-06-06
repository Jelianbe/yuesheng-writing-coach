---
name: 月笙测试规划
description: 为月笙写作教练项目规划测试用例，覆盖诊断解析器、教学状态机、IPC 处理器、Zustand Store 和 UI 组件。适用于功能开发完成后、PR 合并前、重构后需要验证功能时。
alwaysApply: false
priority: high
trigger:
  - "新功能开发完成后需要测试覆盖时"
  - "PR 合并前检查测试覆盖率"
  - "重构后需要验证功能正确性"
  - "Bug 修复后需要回归测试"
---

# 月笙测试规划

## 触发场景
- 新功能开发完成后需要测试覆盖时
- PR 合并前检查测试覆盖率
- 重构后需要验证功能正确性
- Bug 修复后需要回归测试

## 当前已覆盖的测试模块

### 诊断解析器 (diagnosis-parser)
| 测试场景 | 说明 |
|---------|------|
| 正常解析诊断表 JSON | AI 回复中包含 `---DIAGNOSIS_START/END---` 标记 |
| 无诊断表标记 | 纯文本回复，不包含诊断标记 |
| JSON 格式错误 | 诊断标记内 JSON 语法错误时的降级处理 |
| 非法病症 ID 过滤 | `P999` 等不存在的病症 ID 被安全过滤 |
| 严重度值域验证 | `L5` 等非法严重度等级被过滤 |
| confidence 裁剪 | 值为 `99` 时被裁剪到 `[0,1]` 范围内 |

### 教学状态机 (teaching-state-machine)
| 测试场景 | 说明 |
|---------|------|
| 阶段中文名称 | 确认 4 个教学阶段的中文名称正确 |
| 子阶段中文名称 | 确认各子阶段的中文名称正确 |
| 阶段流转 | INIT→WORLD→PRACTICE_LOOP→REVIEW 路径 |
| 子阶段推进 | 推进到下一个子阶段，末尾返回 null |
| 进度计算 | 子阶段位置对应的百分比进度准确 |

## 待覆盖的测试模块（按优先级排序）

### P1 - 高优先级（MVP 阶段）

| 模块 | 测试重点 | 预计用例数 |
|------|---------|:---------:|
| ApiProxy (api-proxy.ts) | 流式 API 调用、SSE 解析、错误处理 | ~8 |
| ChatStore (chat.store.ts) | 消息增删、流式追加、历史截断 | ~6 |
| ConfigService (config.service.ts) | 配置读写、校验、连接测试 | ~8 |
| diagnosis.handler.ts | IPC 通道注册、诊断表推送 | ~6 |

### P2 - 中优先级（MVP 后）

| 模块 | 测试重点 |
|------|---------|
| config.handler.ts | IPC 通信完整性 |
| teaching-state.handler.ts | 状态同步 |
| UI 组件 (ChatPage, ApiConfig, DiagnosisPanel) | 渲染、交互、状态联动 |

## 测试覆盖率目标（按阶段）

| 阶段 | 诊断引擎 | IPC 处理器 | Store | UI 组件 |
|------|:--------:|:----------:|:-----:|:-------:|
| MVP | 60% | 60% | 50% | 40% |
| MVP+1 | 70% | 75% | 60% | 50% |
| 正式发布 | 80% | 90% | 70% | 60% |

## 测试用例模板

```typescript
describe('模块名称', () => {
  describe('方法名称', () => {
    it('应该正确处理场景X', () => {
      const input = '...';
      const result = methodUnderTest(input);
      expect(result).toEqual(expectedOutput);
    });
  });
});
```

## 注意事项
- 测试数据不依赖线上环境（如 API Key）
- Mock 外部依赖（如 AI API 的 HTTP 请求）
- P0 紧急修复可事后补测试（但需在 24 小时内补充）
- 测试用例需要有明确的通过/失败条件
- 运行测试：`npx vitest run`
