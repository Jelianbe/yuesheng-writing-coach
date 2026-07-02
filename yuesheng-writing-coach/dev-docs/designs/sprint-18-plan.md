# Sprint 18 Plan — 后端加固 + 债务清理

> 目标：在转向 H5 手机端之前，先把后端根基打牢、债务清掉。
> 核心原则：不修 UI、不改前端、只动后端服务和工程规范。

---

## 一、摸底总结（2026-06-24）

### ✅ 已经做好，不需要在 Sprint 18 动的

| 模块 | 状态 | 说明 |
|:-----|:----:|:------|
| **IPC 推送机制** | ✅ 完备 | 5 个事件通道（diagnosis/teachingState/chat stream/tool），主进程主动 `webContents.send` |
| **IPC invoke 封装** | ✅ 完备 | `createHandler` 工厂：try-catch、{success,data,error} 格式、幂等键去重 |
| **状态机持久化** | ✅ 完备 | `TeachingStateStore` SQLite CRUD + 状态变更自动推送渲染进程 |
| **DB 迁移** | ✅ 存在 | SQL 文件 013-025，带迁移测试 |
| **版本号** | ✅ 对齐 | package.json = v1.4.0 = release tag（D-049 修复） |

### ❌ 需要修的

| # | 问题 | 严重度 | 类型 | 影响 |
|:-:|:-----|:------:|:-----|------|
| 1 | **LLM 调用无统一网关** | **P0** | 基础设施 | API 失败无降级、无并发控制、无重试、密钥明文存储 |
| 2 | **SQLite 事务覆盖不全** | **P0** | 数据安全 | 批量写入中途崩溃可能产生脏数据 |
| 3 | **technique-library.json 无缓存** | **P1** | 性能 | 高频训练场景重复 JSON 解析 IO |
| 4 | **SessionService 无分页** | **P1** | 性能 | 大量消息时全表扫描 |
| 5 | **mock-data-injector 仍在运行** | **P1** | 工程 | 开发模式注入假数据，可能污染线上环境 |
| 6 | **ESLint 253 个 warning** | **P1** | 规范 | `--max-warnings 300` 掩盖新问题 |
| 7 | **preload 白名单需人工同步** | **P1** | 维护 | 共享白名单已有过遗漏事故 |
| 8 | **better-sqlite3 双版本** | **P1** | 构建 | dev/electron 需不同 rebuild |

---

## 二、任务排期

### Phase 1：P0 修复（2-3d）— LLM 网关 + 事务

#### T18-1：LLM 统一网关层（P0, 1.5d）

**现状**：`ApiProxy` 直接 HTTP 调用 DeepSeek，无容错/限流/重试/缓存。

**目标**：构建 `LLMGateway` 适配器层，封装所有 LLM 调用。

```
src/main/shared/llm/
├── gateway.ts              # 统一入口：chat / chatStream / evaluate
├── adapters/
│   └── deepseek.ts         # DeepSeek 适配器（现有 ApiProxy 迁移至此）
├── middleware/
│   ├── rate-limiter.ts     # 令牌桶并发控制
│   ├── retry.ts            # 指数退避重试（最多 3 次）
│   └── fallback.ts         # 本地缓存兜底（API 不可用时）
├── cache.ts                # 评估结果缓存（LRU）
├── types.ts                # 统一请求/响应类型
└── __tests__/
    ├── gateway.test.ts
    ├── rate-limiter.test.ts
    └── retry.test.ts
```

**验收标准**：
- ✅ 现有服务（DiagnosisService / EvaluatorAgent / ChatOrchestrator）通过 gateway 调用，不直连 ApiProxy
- ✅ API 失败时走缓存兜底（至少返回"AI 暂时不可用，请稍后重试"）
- ✅ 同时发起多个 LLM 请求时，并发数 ≤ 3
- ✅ API 超时（30s）自动重试 1 次
- ✅ 密钥不明文存储（至少 `config:get` 返回脱敏值）

#### T18-2：SQLite 事务覆盖（P0, 0.5d）

**现状**：`SessionService.saveMessage` 有事务，但 `createSession`/`deleteSession` 等无事务包装。

**目标**：统一 DB 操作的事务封装。

**改动**：
- `src/main/shared/services/session.service.ts` — 所有写操作加 `db.transaction()`
- `src/main/domains/01-diagnosis/diagnosis.service.ts` — 诊断结果写入加事务
- `src/main/domains/04-validation/training/training-record.service.ts` — 训练记录加事务

**验收标准**：
- ✅ 所有写操作在事务中执行
- ✅ 相关测试通过

---

### Phase 2：P1 修复（2-3d）— 性能 + 工程

#### T18-3：技法库内存缓存（P1, 0.5d）

**现状**：`training-flow.service.ts` 每次调用 `import` JSON，bundler 打包后无法热更新。

**目标**：`TechniqueLibraryLoader` 启动时加载 + 内存缓存 + 文件 watch 热重载。

```
src/main/shared/services/
└── technique-loader.ts   # 单例：load() / get() / reload() / watch()
```

**验收标准**：
- ✅ JSON 仅在应用启动时加载一次到内存
- ✅ 文件修改后自动重载（fs.watch，dev 模式）
- ✅ 无版本变更时走缓存，不重复 IO

#### T18-4：Session 分页 + 数据清理策略（P1, 0.5d）

**目标**：
- `session:getMessagesPaged` 已有分页参数？检查并补充分页
- 新增 `session:cleanupOlderThan` — 清理 90 天前的诊断记录（仅保留摘要）

**验收标准**：
- ✅ 消息列表支持分页（limit/offset）
- ✅ 有数据清理接口（不自动执行，暴露给用户/设置页面）

#### T18-5：移除 mock-data-injector（P1, 0.3d）

**目标**：
- `src/main/services/mock-data-injector.ts` — 移除此文件
- 所有引用处清理（`service-config.ts` 中的调用）

**验收标准**：
- ✅ mock-data-injector.ts 删除
- ✅ 无残余 import/调用
- ✅ 测试不受影响

#### T18-6：ESLint warning 收敛至 ≤50（P1, 0.5d）

**目标**：253 → ≤50

**策略**：
- 自动修复：`npx eslint src --fix`（可解决的 rule）
- 手动处理高优先级 warning（no-unused-vars, @typescript-eslint/ban-types 等）
- 将 `--max-warnings` 从 300 收紧到 50

**验收标准**：
- ✅ `npx eslint src --max-warnings 50` 通过

#### T18-7：preload 白名单同步自动化（P1, 0.3d）

**现状**：`preload/index.ts` 中的 `allowedInvokeChannels` 需手工同步 `shared/constants.ts`。

**目标**：从 `shared/constants.ts` 生成白名单，消除手工维护。

**方案**：在 `preload/index.ts` 头部加注释 `// GENERATED — do not edit`，写一个 `scripts/sync-preload-whitelist.js` 脚本自动同步。

**验收标准**：
- ✅ `npm run sync:preload` 自动同步白名单
- ✅ CI 中检查白名单是否过时

#### T18-8：better-sqlite3 双版本（P1, 0.5d）

**目标**：解决 dev/electron 不同 native module 版本问题。

**方案**：在 `package.json` 中加 `scripts/rebuild:electron` 脚本，在 CI 和 dev 启动前自动 rebuild。

**验收标准**：
- ✅ `npm run rebuild:electron` 正确编译 electron 版本的 better-sqlite3
- ✅ dev 模式下不报 native module 版本错误

---

### Phase 3：文档更新（0.5d）

#### T18-9：更新决策日志 + 状态标记

- D-050：Sprint 18 决策（LLM 网关 / 事务覆盖 / 技法库缓存）
- D-051：确认"IPC 推送机制已存在，无需新建设计"
- 关闭过时的 Issue/BL 条目
- 更新 dev-docs/designs/ 中的 diagram 以反映真实 push 机制

---

## 三、时间线汇总

| Phase | 任务 | 估时 | 天数 |
|:-----|:-----|:----:|:----:|
| **P0** | T18-1 LLM 网关层 | 1.5d | 2-3d |
| | T18-2 SQLite 事务 | 0.5d | |
| | *（P0 门禁）* | | |
| **P1** | T18-3 技法库缓存 | 0.5d | 2-3d |
| | T18-4 分页+清理 | 0.5d | |
| | T18-5 移除 mock | 0.3d | |
| | T18-6 ESLint 收敛 | 0.5d | |
| | T18-7 白名单同步 | 0.3d | |
| | T18-8 better-sqlite3 | 0.5d | |
| **Docs** | T18-9 更新日志 | 0.5d | 0.5d |
| | **合计** | **~5d** | **~1 周** |

---

## 四、不做清单（Sprint 18 Scope）

| 不做 | 理由 |
|:-----|:------|
| 任何前端 UI 改动 | 等待 H5 迁移 |
| IPC 推送机制重建 | **摸底确认已存在**，不需要 |
| 状态机持久化改造 | **已存在**（TeachingStateStore） |
| 版本号对齐 | **已修复**（v1.4.0） |
| 插件化架构 | 方向待定，不拔高 |
| 新功能（T15-1/2/3 等） | Phase 0 冻结，不引入新功能 |

---

## 五、完成标准（DoD）

1. ✅ LLM 网关层替换所有直连调用，95% 测试覆盖
2. ✅ SQLite 所有写操作有事务保护
3. ✅ 技法库启动加载 + 内存缓存 + 开发模式热重载
4. ✅ mock-data-injector 删除
5. ✅ ESLint warning ≤ 50
6. ✅ preload 白名单同步脚本就绪
7. ✅ better-sqlite3 双版本方案落地
8. ✅ 决策日志更新
9. ⚪ 门禁：typecheck / test / lint / 安全
