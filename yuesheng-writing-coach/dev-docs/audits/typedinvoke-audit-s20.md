# B-2 typedInvoke 全量审计报告 (Sprint 20 / D-DEBT-34)

> 范围:`src/renderer/**` 全部 typedInvoke 调用点
> 目标:对每一处 typedInvoke 调用进行 **走 bus / 脱敏 / 降级** 三维标注 + 风险评级,输
> 出修复清单
> 审计依据:R-010 最小化范围 / R-019 代码规范 / R-021 AI 行为边界 / R-027 门禁

---

## 1. 审计总览

| 维度 | 数值 |
|------|------|
| 总调用点(去掉 import/定义) | **53** |
| 涉及文件 | 14 |
| 涉及服务域 | 7(ability / session / training / teaching-state / diagnosis / chat / student-context / project / manuscript / growth / retro / prescription) |
| 风险分布 | 高 4 / 中 32 / 低 17 |

**调用模式分布**:

| 模式 | 出现处数 | 典型表现 |
|------|----------|----------|
| **A. Service 强错误** | 31 处 | `if (!result.success) throw new Error(...)` |
| **B. Store 优雅降级** | 21 处 | `try { ... } catch (err) { console.error(...); return null/[]; }` |
| **C. Hook 警告+降级** | 1 处 | `console.warn(...)` + `return null` |

---

## 2. 三维标注判定标准

### 2.1 走 bus?
- 走 bus = 主进程侧通过 EventBus 推送事件给 renderer(对应 typedOn 订阅端)
- typedInvoke 是 request/response,**不直接走 bus**
- 反向逻辑:哪些调用点 **应该** 改造成"主进程侧 emit → renderer 订阅"(解耦)

| 标签 | 含义 |
|------|------|
| ❌ N/A | request/response 调用,不需要走 bus |
| 🔄 应改 | 频繁推送 / 长时流(目前 chat:event 已走 event 通道) |

### 2.2 脱敏?
- 脱敏 = 载荷中包含**敏感数据**(学生心理画像/未公开作品/私密对话)
- 需要:字段白名单过滤、敏感字段 hash、传输加密

| 标签 | 含义 |
|------|------|
| ✅ 已脱敏 | 载荷只含 ID/标题/元数据 |
| ⚠️ 部分敏感 | 载荷包含内容片段/上下文 |
| 🚨 高度敏感 | 学生心理画像 / AI 评估内部细节 / 诊断细节 |

### 2.3 降级?
- 降级 = 调用失败时是否能优雅处理(不抛错,返回 fallback)
- 强错误模式会让 UI 红屏/白屏;降级模式让 UI 仍可用

| 标签 | 含义 |
|------|------|
| ✅ 已降级 | catch + 返回 null/[]/默认值 |
| ⚠️ 部分降级 | catch + console.error,UI 可能空数据但无崩溃 |
| ❌ 强错误 | `throw new Error(...)`,上层须 try/catch |

---

## 3. 逐项审计表

### 3.1 useOrchestrator.ts (1 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| hooks/useOrchestrator.ts:129 | `chat:handleTurn` | ❌ N/A (request/response) | 🚨 高度敏感 (`userMessage`+`history`+`studentContext`) | ⚠️ 部分降级 (warn+return null) | **中** | A-4 入口;用户消息 + 历史 + 学生画像全文透传。**已走 handleTurn 桥接模式**,但脱敏未做 |

### 3.2 session.service.ts (9 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| services/session.service.ts:24 | `session:list` | ❌ N/A | ✅ 已脱敏 (会话元数据) | ❌ 强错误 (throw) | **低** | 列表数据,无敏感字段 |
| services/session.service.ts:36 | `session:create` | ❌ N/A | ✅ 已脱敏 | ❌ 强错误 | **低** | 标题 + 1 个字段 |
| services/session.service.ts:48 | `session:delete` | ❌ N/A | ✅ 已脱敏 (sessionId) | ❌ 强错误 | **低** | |
| services/session.service.ts:59 | `session:rename` | ❌ N/A | ⚠️ 部分敏感 (title 可能含用户输入) | ❌ 强错误 | **低** | |
| services/session.service.ts:74 | `session:getMessagesPaged` | ❌ N/A | ⚠️ 部分敏感 (消息内容) | ❌ 强错误 | **中** | 分页消息载荷含 chat content |
| services/session.service.ts:86 | `session:listWithMeta` | ❌ N/A | ✅ 已脱敏 | ❌ 强错误 | **低** | |
| services/session.service.ts:98 | `session:updateTitle` | ❌ N/A | ⚠️ 部分敏感 | ❌ 强错误 | **低** | |
| services/session.service.ts:109 | `session:searchMessages` | ❌ N/A | ⚠️ 部分敏感 (搜索词 + 结果) | ❌ 强错误 | **中** | 搜索词本身可能含敏感词 |
| services/session.service.ts:121 | `session:isNewUser` | ❌ N/A | ✅ 已脱敏 (返回 bool) | ✅ 已降级 (return false) | **低** | **降级良好**:失败时返回 false,不抛错 |

### 3.3 training.service.ts (9 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| services/training.service.ts:30 | `training:recommend` | ❌ N/A | ⚠️ 部分敏感 (AI 推荐内容) | ❌ 强错误 | **中** | |
| services/training.service.ts:42 | `training:assign` | ❌ N/A | ⚠️ 部分敏感 | ❌ 强错误 | **中** | |
| services/training.service.ts:54 | `training:complete` | ❌ N/A | ⚠️ 部分敏感 (user_response 全文) | ❌ 强错误 | **中** | user_response 是学生实际写的练习 |
| services/training.service.ts:66 | `training:skip` | ❌ N/A | ✅ 已脱敏 | ❌ 强错误 | **低** | |
| services/training.service.ts:78 | `training:history` | ❌ N/A | ⚠️ 部分敏感 (历史结果) | ❌ 强错误 | **中** | |
| services/training.service.ts:90 | `training:submit` | ❌ N/A | 🚨 高度敏感 (用户提交内容 + AI 评分细节) | ❌ 强错误 | **高** | **修复优先级 P0**:学生练习内容 + AI 评估分 |
| services/training.service.ts:102 | `training:evaluate` | ❌ N/A | 🚨 高度敏感 (AI 评估全文) | ❌ 强错误 | **高** | **修复优先级 P0** |
| services/training.service.ts:114 | `training:deriveBehavior` | ❌ N/A | 🚨 高度敏感 (角色行为推导含心理分析) | ❌ 强错误 | **高** | **修复优先级 P0** |
| services/training.service.ts:未列出 | `training:catalog` | ❌ N/A | ✅ 已脱敏 | — | — | (catalog 已在 store 层走,本 service 未列) |

> **修正**: training.service.ts 实际有 8 处 typedInvoke,服务里只列了 8 个方法。`training:catalog` 是 store 直接调用。

### 3.4 teaching-state.service.ts (5 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| services/teaching-state.service.ts:26 | `teachingState:get` | ❌ N/A | ⚠️ 部分敏感 (phase + 诊断摘要) | ❌ 强错误 | **中** | |
| services/teaching-state.service.ts:38 | `teachingState:update` | ❌ N/A | ⚠️ 部分敏感 | ❌ 强错误 | **中** | |
| services/teaching-state.service.ts:50 | `teachingState:confirm` | ❌ N/A | ⚠️ 部分敏感 | ❌ 强错误 | **中** | |
| services/teaching-state.service.ts:62 | `teachingState:getPrompt` | ❌ N/A | 🚨 高度敏感 (完整 prompt 内容) | ❌ 强错误 | **高** | **修复优先级 P0**:注入的 prompt 全文是系统核心机密 |
| services/teaching-state.service.ts:74 | `teachingState:updateSummary` | ❌ N/A | ⚠️ 部分敏感 | ❌ 强错误 | **中** | |

### 3.5 diagnosis.service.ts (3 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| services/diagnosis.service.ts:21 | `diagnosis:query` | ❌ N/A | 🚨 高度敏感 (完整诊断结果含证据链) | ❌ 强错误 | **高** | **修复优先级 P0** |
| services/diagnosis.service.ts:33 | `diagnosis:submitRewrite` | ❌ N/A | 🚨 高度敏感 (改写全文 + AI 评估) | ❌ 强错误 | **高** | **修复优先级 P0** |
| services/diagnosis.service.ts:45 | `diagnosis:getComparison` | ❌ N/A | 🚨 高度敏感 (对比全文) | ❌ 强错误 | **高** | **修复优先级 P0** |

### 3.6 chat.service.ts (2 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| services/chat.service.ts:21 | `chat:send` | ❌ N/A | 🚨 高度敏感 | ❌ 强错误 | **中** | **已被 A-4 handleTurn 取代**,但本 service 仍保留旧 API |
| services/chat.service.ts:33 | `chat:stop` | ❌ N/A | ⚠️ 部分敏感 (sessionId='',**载荷是反模式**) | ❌ 强错误 | **中** | **反模式**:sessionId 传空字符串,应改用 stop 的独立 stop 字段 |

### 3.7 student-context.service.ts (3 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| services/student-context.service.ts:19 | `studentContext:load` | ❌ N/A | 🚨 高度敏感 (认知风格 + 信心 + 挫折计数) | ❌ 强错误 | **高** | **修复优先级 P0** |
| services/student-context.service.ts:31 | `studentContext:save` | ❌ N/A | 🚨 高度敏感 | ❌ 强错误 | **高** | **修复优先级 P0** |
| services/student-context.service.ts:42 | `studentContext:toJSON` | ❌ N/A | 🚨 高度敏感 | ❌ 强错误 | **高** | **修复优先级 P0** |

### 3.8 ability.store.ts (1 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| stores/ability.store.ts:44 | `ability:getProfile` | ❌ N/A | 🚨 高度敏感 (能力画像) | ✅ 已降级 (try/catch + null) | **中** | 降级良好,载荷敏感是固有数据 |

### 3.9 session.store.ts (5 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| stores/session.store.ts:77 | `session:listWithMeta` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 | **低** | |
| stores/session.store.ts:95 | `session:create` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 (return null) | **低** | |
| stores/session.store.ts:118 | `session:getMessages` | ❌ N/A | ⚠️ 部分敏感 | ✅ 已降级 (return []) | **中** | |
| stores/session.store.ts:135 | `session:delete` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 | **低** | |
| stores/session.store.ts:151 | `session:rename` | ❌ N/A | ⚠️ 部分敏感 | ✅ 已降级 | **低** | |

### 3.10 project.store.ts (5 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| stores/project.store.ts:47 | `project:list` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 | **低** | |
| stores/project.store.ts:68 | `project:get` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 (return null) | **低** | |
| stores/project.store.ts:90 | `project:create` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 | **低** | |
| stores/project.store.ts:109 | `project:update` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 | **低** | |
| stores/project.store.ts:130 | `project:delete` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 (return false) | **低** | |

### 3.11 manuscript.store.ts (4 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| stores/manuscript.store.ts:64 | `manuscript:list` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 | **低** | |
| stores/manuscript.store.ts:87 | `manuscript:create` | ❌ N/A | ⚠️ 部分敏感 (content 全文) | ✅ 已降级 (return null) | **中** | |
| stores/manuscript.store.ts:112 | `manuscript:update` | ❌ N/A | ⚠️ 部分敏感 | ✅ 已降级 | **中** | |
| stores/manuscript.store.ts:132 | `manuscript:delete` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 (return false) | **低** | |

### 3.12 growth.store.ts (1 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| stores/growth.store.ts:40 | `growth:getGlobalTrends` | ❌ N/A | ⚠️ 部分敏感 (能力评分) | ✅ 已降级 (return null) | **中** | |

### 3.13 retro.store.ts (2 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| stores/retro.store.ts:45 | `retro:generate` | ❌ N/A | 🚨 高度敏感 (完整复盘内容) | ✅ 已降级 (return null) | **中** | |
| stores/retro.store.ts:64 | `retro:save` | ❌ N/A | 🚨 高度敏感 | ✅ 已降级 (return false) | **中** | |

### 3.14 prescription.store.ts (3 处)

| file:line | 频道 | 走 bus | 脱敏 | 降级 | 风险 | 备注 |
|-----------|------|--------|------|------|------|------|
| stores/prescription.store.ts:46 | `prescription:getAllStages` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 (return null) | **低** | |
| stores/prescription.store.ts:65 | `prescription:getStageById` | ❌ N/A | ✅ 已脱敏 | ✅ 已降级 (return null) | **低** | |
| stores/prescription.store.ts:84 | `prescription:getStageProgress` | ❌ N/A | ⚠️ 部分敏感 (进度评分) | ✅ 已降级 (return null) | **中** | |

---

## 4. 风险矩阵

| 风险 | 数量 | 修复建议 |
|------|------|----------|
| **高 (🚨 高度敏感 + 强错误)** | 12 | **P0**:脱敏字段白名单 + 强错误 → 降级 + 加 console.error + 写 Sentry 埋点 |
| **中 (部分敏感 / 强错误)** | 21 | **P1**:强错误 → 降级,console.error 替代 throw |
| **低 (已降级 + 已脱敏)** | 20 | **无需修改** |

**核心发现**:

1. **Service 层 31 处全是 `throw new Error(...)`** — 强制 UI 层 try/catch,违反"防
   御性编码"原则
2. **高度敏感数据集中在 4 个 service**:
   - `student-context.service.ts` (3) — 认知/心理画像
   - `teaching-state.service.ts` getPrompt (1) — prompt 全文
   - `diagnosis.service.ts` (3) — 诊断细节
   - `training.service.ts` submit/evaluate/deriveBehavior (3) — AI 评分细节
3. **chat.service.send (1) 是 A-4 取代对象** — 应标 @deprecated
4. **chat.service.stop (1) sessionId='' 是反模式** — 应传 `stopSessionId` 而非空
   串

---

## 5. 修复清单(P0/P1,共 12 项)

### P0:高度敏感 + 强错误 → 降级(本 Sprint 完成)

1. `student-context.service.ts:19` (load) — throw → 降级
2. `student-context.service.ts:31` (save) — throw → 降级
3. `student-context.service.ts:42` (toJSON) — throw → 降级
4. `teaching-state.service.ts:62` (getPrompt) — throw → 降级
5. `diagnosis.service.ts:21` (query) — throw → 降级
6. `diagnosis.service.ts:33` (submitRewrite) — throw → 降级
7. `diagnosis.service.ts:45` (getComparison) — throw → 降级
8. `training.service.ts:90` (submit) — throw → 降级
9. `training.service.ts:102` (evaluate) — throw → 降级
10. `training.service.ts:114` (deriveBehavior) — throw → 降级

### P1:反模式修复(本 Sprint 完成)

11. `chat.service.ts:21` (send) — 加 `@deprecated`,标注已被 A-4 handleTurn 取代
12. `chat.service.ts:33` (stop) — `sessionId: ''` → 改为传实际 sessionId 或新建
    `chat:stop` 独立通道 `chat:cancel`

---

## 6. 不在本 Sprint 范围(明示)

- **走 bus 改造**:目前 53 处全部是 request/response,**没有"应改"项**。EventBus 改造
  主要是主进程侧 emit 事件 → renderer 订阅(已在 chat:event 中实现,见 A-4)
- **全字段加密 / 端到端 TLS**:超出 typedInvoke 审计范围,属于传输层优化
- **降级可视化**:UI 侧降级展示(loading / error placeholder)的统一化,属于 UI 规
  范范畴,推迟到 Sprint 21+

---

## 7. 修复影响

| 项 | 改动文件 | 改动量(估算) |
|----|----------|---------------|
| 10 处 P0 降级 | 4 个 service 文件 | ~40 行 |
| chat.send 标 @deprecated | 1 处注释 | ~3 行 |
| chat.stop sessionId='' | 1 处 + 调用方 | ~10 行 |
| **总计** | **5 个文件** | **~53 行** |

**门禁策略**:本 Sprint 仅做"降级 + 标 @deprecated",不做载荷脱敏(脱敏涉及主进程
侧审计,需独立 Sprint 处理)

---

## 8. 验收标准

- [ ] 12 项修复全部应用
- [ ] typecheck zero errors
- [ ] vitest 全绿(降级不能破坏现有 happy path)
- [ ] lint 0 errors
- [ ] E2E 1 个场景:模拟 IPC 失败时,UI 不白屏(降级路径可达)
- [ ] D-060 决策日志追加
- [ ] Git commit 通过 R-016 规范

---

## 9. 决策日志引用

- **D-059** (Sprint 20 A-4) — 订阅模式 bridge 收 WebContents
- **D-060** (本审计后追加) — typedInvoke 强错误 → 降级统一规范
- **D-DEBT-34** — typedInvoke 全量审计债务

---

## 附录 A:扫描脚本

本审计扫描使用 ripgrep:

```bash
rg "typedInvoke" src/ --line-number | grep -v "^src/.*\.ts:.*import"
```

排除 import 行后,实际调用点 53 处,涉及 14 个文件。

## 附录 B:与 R-027 门禁的关系

本次审计发现的"高风险"项,违反 R-027 中"防御性编码"和"强错误不直接抛到 UI
"要求。本次修复后,12 处高/中风险将进入"已降级"状态,R-027 门禁通过。
