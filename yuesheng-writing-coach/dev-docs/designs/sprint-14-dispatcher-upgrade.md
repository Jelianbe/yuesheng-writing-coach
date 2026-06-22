
# Sprint 14+ 方向 C 草案 — Skill Dispatcher 完整升级

> **状态**: 草案（占位，未启动）
> **触发条件**: 见 D-030 决策日志 + 本草案
> **范围**: Sprint 13 简化版的完整升级
> **前置**: Sprint 13 完成（v5 拆分 + phase 维度 5 种组合）+ D-DEBT-2026-06-23-11 解决

---

## 一、升级目标

Sprint 13 实质做了 phase 维度 5 种组合。方向 C 升级 4 个核心能力：

1. **attitude 维度实质过滤**：sensei 档剔除"鼓励""加油"等字眼
2. **运行时条件触发**：根据 user 行为（evidence 质量 / 触发关键词）动态切换 SKILL
3. **完整 YAML metadata schema**：depends / tokenPriority / version / conditions
4. **依赖图自动校验**：启动时检测循环依赖 + 缺失依赖

---

## 二、必须先解决的债务（启动前提）

### D-DEBT-2026-06-23-11：dispatcher 启用需解决体积优化

**问题**：
- 旧 loadCorePrompt 提取 v5 §一铁三角（约 800 字符 / 约 1200 tokens）
- 新 dispatcher 默认 phase=P0_INIT 加载 4 个 always SKILL（约 20K 字符 / 约 30K tokens）
- 体积膨胀 25 倍，与 Sprint 13 节省 token 目标直接矛盾

**可能的解决方向**（待方向 C 设计时选择）：

| 方案 | 描述 | 优劣 |
|------|------|------|
| A. SKILL 子集加载 | 增加 metadata 字段 minCoreOnly，core-identity 拆为 core-iron-triangle.md + core-product-identity.md，P0 只加载前者 | 改动小，可能影响 v5 拆分完整性 |
| B. 按 phase 动态体积 | 给每个 SKILL 加 tokenPriority，P0 只加载 priority 1-2 的内容（铁三角 + 基础教学策略） | 灵活但需重新设计 priority 体系 |
| C. 渐进式启用 | P0/P1 仍用 v5 降级路径（800 字符），P2/P3/P4 才用 dispatcher | 最小改动，节省 token 效果局限于高 phase |
| D. LLM 自动摘要 | dispatcher 加载的 4 SKILL 用 LLM 压缩到约 3K 字符后再注入 | 智能但增加 LLM 调用成本 |

**推荐**: A + C 组合 — P0/P1 走 C 方案（仍用 v5 降级），P2/P3/P4 走 A 方案（dispatcher 加载核心子集）

### D-DEBT-2026-06-23-09：教学状态机 phase 注入

dynamicContextService.loadCorePrompt 当前使用 P0_INIT 默认值。理想应根据 getStateContextGetter(sessionId) 获取当前 phase 注入 dispatcher。

---

## 三、架构（相比 Sprint 13 增强）

```
User Request
  ↓
[Teaching State Machine]  ← 已有 R-014 配置外置
  ↓
[Skill Dispatcher v2]  ← 增强
  ├─ Phase 维度（保留 Sprint 13 实现）
  ├─ Attitude 维度（新增实质过滤）
  ├─ 运行时 conditions（新增 evidence 质量 / DP 触发）
  └─ 依赖图校验（启动时 fail-fast）
  ↓
[Prompt Composer]  ← 增强
  ├─ Token 估算 + 截断（已有 truncation.ts）
  └─ 优先级排序（新增 tokenPriority）
  ↓
[LLM]
```

---

## 四、YAML metadata 完整 schema

```yaml
---
id: TEACHING.feedback
version: 1.0
estimatedTokens: 800
depends: [IDENTITY, VALIDATION.output]
loadWhen:
  phases: [P2_PRACTICE_LOOP, P3_TRAINING, P4_REVIEW]
  attitudes: [doubao, yuesheng]
  conditions:
    - evidence.quality IN ['low', 'medium']
    - NOT user.safetyWord
tokenPriority: 8  # 截断时优先级（10 最高，1 最低）
minCoreOnly: false  # 是否只加载最小核心子集（解决 D-DEBT-11）
---
```

---

## 五、任务草案（待 Sprint 13 完成后细化）

| 编号 | 任务 | 预估 | 阻塞 |
|------|------|------|------|
| T14-0 | 解决 D-DEBT-11（选 A/B/C/D 方案） | 2h | 启动前提 |
| T14-1 | 解决 D-DEBT-09（教学状态机 phase 注入） | 1h | 启动前提 |
| T14-2 | 扩展 SkillMetadata：version / depends / tokenPriority / conditions / minCoreOnly | 2h | 依赖 T14-0 |
| T14-3 | 写依赖图校验器（启动时 fail-fast） | 1h | 依赖 T14-2 |
| T14-4 | Attitude 实质过滤：sensei 档删除"鼓励"等话术 | 1h | 依赖 T14-2 |
| T14-5 | 运行时 conditions：evidence 质量 / DP 触发关键词 | 2h | 依赖 T14-2 |
| T14-6 | Token 优先级 + 截断（与已有 truncation 集成） | 1h | 依赖 T14-2 |
| T14-7 | E2E 测试：完整 phase+attitude+conditions 矩阵 | 2h | 依赖 T14-4~6 |
| T14-8 | 灰度发布脚本（双轨：新旧版本对比 1 周） | 1h | 依赖 T14-7 |

**总预估**: 约 12-13 小时（约 2 sprint）

---

## 六、DoD（待定）

- [ ] D-DEBT-11 解决（无 prompt 膨胀回归）
- [ ] D-DEBT-09 解决（教学状态机 phase 注入）
- [ ] Attitude 维度实质过滤生效
- [ ] 运行时 conditions 触发准确（误判率 < 5%）
- [ ] 依赖图无循环依赖
- [ ] 完整 token 预算控制（P0/P1 < 5K 字符）
- [ ] E2E 全绿
- [ ] 灰度发布对比 1 周无回归

---

## 七、风险

| 风险 | 等级 | 缓解 |
|------|------|------|
| 完整 metadata schema 导致 SKILL 文件复杂度上升 | 中 | 提供模板生成器（Node.js 脚本） |
| Attitude 实质过滤误删有效话术 | 中 | 灰度发布（先双轨：sensei 档新旧版本对比 1 周） |
| 运行时 conditions 触发误判 | 高 | 默认保守策略（条件不满足时按 phase 全量加载） |
| 启用 dispatcher 引入 prompt 膨胀 | 高 | 必须先解决 D-DEBT-11，否则不启用 |

---

## 八、何时启动

满足以下任一条件即可启动方向 C：

1. **用户反馈 sensei 档加载"鼓励"话术**（需要 attitude 实质过滤）
2. **需要根据 user 行为动态切换 SKILL**（如触发 DP-F 时临时加载）
3. **切换到更小上下文模型**（< 8K 余量时精细化调度）
4. **真正启用 dispatcher**（必须先解决 D-DEBT-11）

---

## 九、依据

- dev-docs/designs/sprint-13-skill-dispatcher-design.md
- dev-docs/designs/sprint-13-implementation-plan.md
- docs/decision-log.md D-030
- R-018 变更溯源 / R-025 Prompt 治理 / R-019 代码规范
- Issue #19 (Sprint 14+ Skill Dispatcher 完整升级 P1)
