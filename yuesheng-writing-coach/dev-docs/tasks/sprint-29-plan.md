# Sprint 29 — Capacitor/Android 测试补强

> **范围**: 为 Capacitor/Android 双轨架构补充测试覆盖，确保后续开发有安全网
> **依据**: D-076（AVD 延期）+ D-079（Sprint 28 完工）+ 用户要求"完善相关内容测试"
> **前提**: 不依赖 AVD/真机，全部在 jsdom CI 中可运行

---

## 0. 目标与边界

### 0.1 目标

- ServiceBridge（main + renderer）测试覆盖从 **0 → ≥90%**
- 6 个 renderer service 的 Capacitor 降级分支测试覆盖从 **0 → ≥90%**
- 总新增测试用例 ~45 个
- 门禁：typecheck 0 error / test 全绿 / lint 0 warning

### 0.2 不在范围

- ❌ CapacitorSqliteAdapter 测试（需要 Capacitor 运行时，推 S30+ 搭配 AVD）
- ❌ Android Java 测试（占位符模板，推 S30+）
- ❌ AVD 修复（D-076 已记，推 S30+）
- ❌ 业务逻辑变更

---

## 1. 现状快照

| 模块 | 当前覆盖 | 目标覆盖 |
|:-----|:--------:|:--------:|
| `_dual-track.ts` | ✅ 完整 | — |
| **ServiceBridge (main)** | ❌ 0 | ≥90% |
| **ServiceBridge (renderer)** | ❌ 0 | ≥90% |
| **Capacitor 降级分支（6 个 service）** | ❌ 0 | ≥90% |
| **双轨 service 集成** | ❌ 0 | ≥80% |
| StorageAdapter PoC | ✅ 2/3 | — |

---

## 2. 阶段拆解

### 阶段 1: ServiceBridge (main) 测试 ✅ 完成

**文件**: `src/main/core/__tests__/service-bridge.test.ts`

**测试用例**（~15 个）：

| 类别 | 用例 | 说明 |
|:-----|:-----|:------|
| **注册** | `registerMethod` 注册单个方法 | 验证方法可调用 |
| | `registerMethods` 批量注册 | 验证多方法注册 |
| | `registerMethod` 覆盖已注册方法 | 验证幂等覆盖 |
| | `isMethodRegistered` 已注册返回 true | 验证存在性检查 |
| | `isMethodRegistered` 未注册返回 false | 验证不存在性检查 |
| **调用** | `handleBridgeInvoke` 成功调用 | 验证返回值透传 |
| | `handleBridgeInvoke` 多参数 | 验证参数透传 |
| | `handleBridgeInvoke` 异步 handler | 验证 async 支持 |
| **安全** | `handleBridgeInvoke` 未注册 method 抛 `MethodNotRegisteredError` | 验证白名单拒绝 |
| | `handleBridgeInvoke` handler 抛错时异常透传 | 验证错误隔离 |
| **管理** | `unregisterMethod` 取消注册 | 验证取消后不可调用 |
| | `clearRegistry` 清空所有 | 验证清空后全不可用 |
| | `getRegisteredMethods` 返回列表 | 验证方法列表正确 |

### 阶段 2: ServiceBridge (renderer) 测试 ✅ 完成

**文件**: `src/renderer/services/__tests__/service-bridge.test.ts`

**测试用例**（~8 个）：

| 类别 | 用例 | 说明 |
|:-----|:-----|:------|
| **Electron 路径** | `invokeBridge` 走 electronAPI 成功 | 完整 IPC 路径 |
| | `invokeBridge` electronAPI 失败抛错 | 错误透传 |
| | `invokeBridgeElectronOnly` 强制走 Electron | 绕过 Capacitor 检测 |
| **Capacitor 路径** | `invokeBridge` 走 directFallback 成功 | Android 直调路径 |
| | `invokeBridge` directFallback 失败抛错 | 不降级原则 |
| **边界** | `invokeBridge` 无 electronAPI 且 non-Capacitor 抛错 | 兜底检查 |
| | `invokeBridge` 调用未注册 method 抛错 | 白名单传递 |
| | 参数透传验证 | 参数完整传递 |

### 阶段 3: Capacitor 降级分支测试 ✅ 完成

**文件**: 各 service 的 `__tests__/` 下（6 个 service）

- `chat.service.ts`（4 个方法 → capacitorNoopChat）
- `diagnosis.service.ts`（4 个方法 → capacitorNoopDiagnosis）
- `training.service.ts`（8 个方法 → capacitorNoopTraining）
- `student-context.service.ts`（3 个方法 → capacitorNoopStudentContext）
- `app-controller.ts`（initialize → 早返回）
- `teaching-state.service.ts`（IPC-only 方法 → noop + warn）

**总用例**: ~12 个

### 阶段 4: 门禁 + 收尾 ✅ 完成

- `npm run typecheck && npm run test && npm run lint`
- ✅ 写入决策日志 D-080

---

## 3. 时间盒

| 阶段 | 工时 | 累计 |
|:-----|:----:|:----:|
| 阶段 1: ServiceBridge (main) | 0.5 天 | 0.5 |
| 阶段 2: ServiceBridge (renderer) | 0.5 天 | 1.0 |
| 阶段 3: Capacitor 降级分支 | 0.5 天 | 1.5 |
| 阶段 4: 门禁收尾 | 0.25 天 | 1.75 |
| **总计** | **1.75 工作日** | |
