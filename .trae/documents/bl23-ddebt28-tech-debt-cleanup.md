# BL-23 + D-DEBT-28 技术债务处理

## Context

### 任务背景
用户离开项目约一周后回归，决定先处理两个技术债务：
- **BL-23** — preload 白名单与 shared 白名单漂移，每次新增 IPC 频道需手动同步两处（`shared/constants.ts` + `preload/index.ts` + 旧注释里的 `constants.js`）
- **D-DEBT-28** — Tailwind 死代码清理（package.json 还装着 `tailwindcss` + `autoprefixer` + `postcss`，但移动端代码完全不用 Tailwind，桌面端已归档）

### 探索阶段关键发现
1. **`scripts/sync-preload-whitelist.ts` 已经写好**（107 行），功能完整。但**未接入 package.json scripts**，没有钩子触发。
2. **当前 preload 与 shared 已严重漂移**：
   - preload 多了 `teachingHistory:add` / `teachingNote:record|getTree|delete|update`（4 个）
   - preload 用了 `prescription:*` / `training:generateFlow` 注释补的 4 个（shared 已有）
   - preload 缺 `retro:generate` / `retro:save`（shared 已有）
3. **`ALLOWED_EVENT_CHANNELS` 第 286 行有个 BUG**：`DIAGNOSIS_UPDATE` 应为 `DIAGNOSIS_UPDATED`
   - 主进程 `diagnosis.handler.ts:193` / `diagnosis-orchestrator.service.ts:73` 都 emit `'diagnosis:updated'`
   - 跑 sync 会把 preload 改成 `'diagnosis:update'` → **会断诊断事件订阅**
   - 必须先修这个 bug 再跑 sync
4. **Tailwind 实际使用情况**：
   - `globals.css` 第 7-9 行有 `@tailwind base/components/utilities`
   - 移动端代码（`App.tsx`, `TabBar.tsx`, `MoreMenu.tsx`, 5 页面）**完全不用 Tailwind**
   - `components_archived/` 里 6 个废弃文件还含 Tailwind 类（已归档，不在编译路径）
5. **本任务的 scope 控制**：`components_archived/` 不动（已归档），`README.md` 不主动改（如需要由用户确认）。

---

## 实施步骤

### 阶段 1：BL-23 preload 白名单自动同步

**Step 1.1 — 修复 `ALLOWED_EVENT_CHANNELS` 命名 bug**
- 文件：[src/shared/constants.ts:286](file:///d:/ai-teacher/yuesheng-writing-coach/src/shared/constants.ts#L286)
- 改动：`IPC_CHANNELS.DIAGNOSIS_UPDATE,` → `IPC_CHANNELS.DIAGNOSIS_UPDATED,`
- 依据：主进程 `diagnosis.handler.ts:193` 和 `diagnosis-orchestrator.service.ts:73` 实际 emit `DIAGNOSIS_UPDATED`
- 不修这步，跑 sync 会断诊断事件订阅

**Step 1.2 — 补全 `ALLOWED_INVOKE_CHANNELS` 漏的 5 个通道**
- 文件：[src/shared/constants.ts:217-282](file:///d:/ai-teacher/yuesheng-writing-coach/src/shared/constants.ts#L217-L282)
- 改动：在 `ALLOWED_INVOKE_CHANNELS` 数组内新增：
  ```
  IPC_CHANNELS.TEACHING_HISTORY_ADD,
  IPC_CHANNELS.TEACHING_NOTE_RECORD,
  IPC_CHANNELS.TEACHING_NOTE_GET_TREE,
  IPC_CHANNELS.TEACHING_NOTE_DELETE,
  IPC_CHANNELS.TEACHING_NOTE_UPDATE,
  ```
- 依据：preload 白名单里有，主进程有 emit/handle，shared 漏登记
- 位置：建议插在 `TEACHING_STATE_*` 之后、`EVIDENCE_*` 之前（按 IPC_CHANNELS 顺序）

**Step 1.3 — 接入 package.json scripts**
- 文件：[package.json](file:///d:/ai-teacher/yuesheng-writing-coach/package.json)
- 改动：
  - 新增 `"sync:ipc": "npx tsx scripts/sync-preload-whitelist.ts"`
  - 改 `prebuild`：在 `rebuild:electron` 之后追加 `&& npm run sync:ipc`
  - 改 `precommit`：在最前加 `npm run sync:ipc &&`
  - 改 `ci`：在 `typecheck` 之前加 `npm run sync:ipc &&`

**Step 1.4 — 跑 sync + dry-run 验证**
1. `cp src/preload/index.ts src/preload/index.ts.bak`（备份）
2. `npx tsx scripts/sync-preload-whitelist.ts`
3. `git diff src/preload/index.ts` — 预期：只新增 `retro:generate` / `retro:save`，移除 handcrafted 注释，preload 数组结构按 ALLOWED 重排
4. 断言：`preload allowedInvokeChannels.length === shared ALLOWED_INVOKE_CHANNELS.length`
5. `npm run typecheck` 必须 0 错误
6. 防漂移验证：临时在 preload 加 `'fake:channel'`，跑 sync，预期被覆盖 → 撤销

**Step 1.5 — 验证后清理**
- 删 `src/preload/index.ts.bak`
- 修 [src/preload/index.ts:1-11](file:///d:/ai-teacher/yuesheng-writing-coach/src/preload/index.ts#L1-L11) 头注释：移除过时的"`src/shared/constants.js`"提及（文件不存在），更新为"`scripts/sync-preload-whitelist.ts` 自动同步"说明

### 阶段 2：D-DEBT-28 Tailwind 移除

**Step 2.1 — 删 `globals.css` 的 `@tailwind` 三行**
- 文件：[src/renderer/styles/globals.css:7-9](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/styles/globals.css#L7-L9)
- 删除：`@tailwind base;` / `@tailwind components;` / `@tailwind utilities;` 三行
- 依据：vite 缺 postcss 插件时 `@tailwind` 是无效 at-rule 静默丢弃
- 同步删第 3 行注释里的"`先于 @tailwind`"措辞

**Step 2.2 — 删 `postcss.config.mjs`**
- 文件：[postcss.config.mjs](file:///d:/ai-teacher/yuesheng-writing-coach/postcss.config.mjs)
- 整个文件删除
- 依据：vite 找不到 postcss config 即不跑 postcss，不影响 vite 本身

**Step 2.3 — 删 `tailwind.config.js`**
- 文件：[tailwind.config.js](file:///d:/ai-teacher/yuesheng-writing-coach/tailwind.config.js)
- 整个文件删除（84 行）
- 依据：与 `components_archived/` 不在编译路径上，无副作用

**Step 2.4 — 移除 package.json 三个 dep**
- 文件：[package.json:55, 63, 67](file:///d:/ai-teacher/yuesheng-writing-coach/package.json)
- 删除 devDependencies 里的 `autoprefixer`、`postcss`、`tailwindcss` 三行
- 跑 `npm install` 重新生成 lockfile

---

## Critical Files

- [src/shared/constants.ts](file:///d:/ai-teacher/yuesheng-writing-coach/src/shared/constants.ts) — Step 1.1 (L286) + Step 1.2 (L217-282)
- [package.json](file:///d:/ai-teacher/yuesheng-writing-coach/package.json) — Step 1.3 + Step 2.4
- [src/preload/index.ts](file:///d:/ai-teacher/yuesheng-writing-coach/src/preload/index.ts) — Step 1.4 跑 sync + Step 1.5 头注释
- [src/renderer/styles/globals.css](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/styles/globals.css) — Step 2.1
- [postcss.config.mjs](file:///d:/ai-teacher/yuesheng-writing-coach/postcss.config.mjs) — Step 2.2 (整文件删)
- [tailwind.config.js](file:///d:/ai-teacher/yuesheng-writing-coach/tailwind.config.js) — Step 2.3 (整文件删)
- [scripts/sync-preload-whitelist.ts](file:///d:/ai-teacher/yuesheng-writing-coach/scripts/sync-preload-whitelist.ts) — **不改主体**，仅验证

**不改动的文件**：
- `components_archived/**` — 已归档，废弃，不在编译路径
- `README.md` / `dev-docs/**` — 不主动改；如需要由用户决定

---

## 复用现有工具

- **`scripts/sync-preload-whitelist.ts`** — 已写好的 107 行生成器，本任务不修改其主体逻辑
- **`scripts/check-a11y-colors.ts` / `check-file-size.ts`** — 参考它们使用 `npx tsx` 跑的模式
- **`npx tsx`** — 项目已用，scripts/*.ts 都用 tsx 跑

---

## Verification

### 阶段 1（BL-23）验证

```bash
# 备份
cp src/preload/index.ts src/preload/index.ts.bak

# 跑 sync
npx tsx scripts/sync-preload-whitelist.ts
# 预期输出：✅ preload 白名单已同步 或 已是最新

# 看 diff（关键：DIAGNOSIS_UPDATED 是否已生效）
git diff src/preload/index.ts
# 预期：allowedEventChannels 包含 'diagnosis:updated'（带 D）

# 长度断言（手动）
grep -c "IPC_CHANNELS\." src/shared/constants.ts
grep -c "^  '" src/preload/index.ts

# 门禁
npm run typecheck        # 必须 0 错误
npm run test             # 必须全绿
```

### 阶段 2（D-DEBT-28）验证

```bash
# 删完后确认
ls -la tailwind.config.js postcss.config.mjs 2>&1  # 应该 not found
grep -n "@tailwind" src/renderer/styles/globals.css  # 应该无匹配

# package.json 验证
grep -E "(tailwind|postcss|autoprefixer)" package.json  # 应该无匹配

# 门禁
npm install                                       # 重生 lockfile
npm run typecheck                                 # 0 错误
npm run test                                      # 全绿
npm run lint                                      # 0 error
npm run build                                     # vite 缺 postcss 应仍能跑

# 手测（如有 dev server）：UI 与移除前像素级一致
```

### 端到端冒烟

```bash
npm run dev:electron   # 启动 Electron 应用
# 验证：
# 1. 教学对话页能发送消息（chat:* 通道正常）
# 2. 诊断结果能渲染（diagnosis:updated 事件能收到 ← Step 1.1 关键验证点）
# 3. 书架/项目列表能加载（project:list / manuscript:list 通道正常）
# 4. UI 视觉无变化（globals.css 删 @tailwind 无副作用）
```

---

## 风险评估与缓解

| 风险 | 概率 | 缓解 |
|------|------|------|
| sync 跑出意外修改 | 低 | dry-run + 备份 + 看 diff |
| `DIAGNOSIS_UPDATE` 命名 bug 断诊断事件 | 中→已消除 | Step 1.1 必修先 |
| 删 Tailwind 后 components_archived/ 编译失败 | 0 | 已不在 vite 扫描路径 |
| 删 postcss.config.mjs 致 vite 报错 | 0 | vite 不依赖 postcss |
| 删 lockfile 后 npm install 异常 | 低 | Stage 2 Step 2.4 后跑 install 验证 |
| sync 脚本 regex 解析失败 | 低 | 现有 main 函数已 throw + exit 1，会立即暴露 |

### 回退方案

每阶段独立 commit，互不耦合。

**BL-23 误改未提交**：
```bash
cp src/preload/index.ts.bak src/preload/index.ts
git checkout -- src/shared/constants.ts package.json
```

**BL-23 commit 后回退**：`git revert HEAD`

**D-DEBT-28 误改未提交**：
```bash
git checkout -- src/renderer/styles/globals.css
# 重建被删的 postcss.config.mjs / tailwind.config.js
git checkout HEAD -- postcss.config.mjs tailwind.config.js
npm install
```

**D-DEBT-28 commit 后回退**：`git revert HEAD && npm install`

---

## 执行顺序

1. **先 BL-23（5 步）** — 改 `src/shared/constants.ts` + `src/preload/index.ts`（运行时 IPC 契约） + `package.json` scripts
2. **后 D-DEBT-28（4 步）** — 删 `globals.css` 三行 + 删两个 config + 删三个 dep
3. **两个 commit 分开**（便于回退）：
   - Commit 1：`feat(ipc): BL-23 自动同步 preload 白名单`
   - Commit 2：`chore(deps): D-DEBT-28 移除 Tailwind/PostCSS`
4. **不并行**：package.json 改动会触发 lockfile 抖动，与 sync 混在一个 commit 会增加回退复杂度

---

## 范围外（明确不做）

- 不修 `components_archived/` 内的 Tailwind 类引用（已归档，废弃）
- 不动 `scripts/sync-preload-whitelist.ts` 主体（已写好）
- 不主动改 README/docs（如需由用户决定）
- 不加 `scripts/__tests__/sync-preload-whitelist.test.ts`（引入 fixture 维护债务）
- 不改 `src/main/domains/**` 主进程代码（与本任务无关）
- 不做 audit 重跑（D-DEBT-29 另开任务）
- 不做 LLM 网关 / SQLite 事务（Sprint 18 P0 另开任务）
- 不做 Phase A Store 补全（mobile-v1-ipc-plan.md 另开任务）
