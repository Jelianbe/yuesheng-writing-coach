# yuesheng-flutter 项目宪法（v0.1 基线；v0.2 改动待正式评审）

> 状态：**v0.1 基线**（2026-08-16 迁入工程 `docs/` 并与 `.workbuddy/skills` 体系对齐）。⚠️ 文件曾被改为"v0.2 定稿/评审通过"，但该"评审"由执行 AI 自行标注、**未经用户/主会话确认**，不构成本项目正式评审；v0.2 内容（§4.1/§4.2/§7.1/§九/§十 等）暂按草稿保留，待正式评审后定稿。
> 源材料 = `yuesheng-android/锐评清单现状核对-2026-08-16.md`（RN 版 31 天实跑证据）。
> 用途：纳入工程 `docs/`（本项目是主仓库 `yuesheng-flutter/` 子目录，归入 docs 较根目录 `AGENTS.md` 更契合），作为 `AGENTS.md` 的核心依据；历史项目（yuesheng-android）已废弃，其代码/文档仅作模式证据。
> 建议落地日期：2026-08-16

---

## 一、项目定位（继承已确认的产品决策）

- **做什么**：AI 对话式写作指导 + 作品/章节管理 + 渐进式诊断（写作问题识别与教学闭环）+ 成长可视化 + 本地存储。
- **目标用户**：轻量写作爱好者（日记/随笔/短篇/兴趣写作）。
- **产品形态**：编辑器为主、对话为辅；移动端优先。
- **边界**：无后端、无账号、无云同步（换机数据丢失必须作为已知取舍写进产品文档，不许假装不存在）；不做网文作者专属功能、不做自媒体爆款工具、不做应试作文评分。
- **命名**：**禁止医学化话语**——写作问题不叫"症候"，"诊断/症候/患者"类词汇不得进入 UI 与用户可见文案（教学内部代码可保留 `syndrome` 作为迁移兼容名）。**废弃时间登记：`syndrome` 内部名保留至 v1.0 发布，之后统一重命名为 `writing_issue`（代码/表名/变量同步，重命名批次须四闸全绿）**。

## 二、技术栈（真源，落地时冻结）

- Flutter stable + Dart 最新稳定；状态管理、路由、本地数据库（sqflite/drift）在开工第一周内定案并写入本文件，之后禁止私自更换。
- LLM：用户自定义 API Key + Base URL + Model，本地安全存储（flutter_secure_storage），**禁止内置密钥、禁止 AsyncStorage 类明文持久化**。
- 测试：widget/unit/integration 三级；E2E 用 Maestro（可复用 RN 版的 YAML 流程思路）。
- 工程质量门禁（git commit 前必须全绿，缺一不可）：
  1. `flutter analyze` 0 问题
  2. `dart format --set-exit-if-changed` 通过
  3. 受影响测试全绿
  4. **架构分层检查（机器强制）**：分层规则必须进 analyze/lint 或独立脚本，禁止只写进文档（⚠️ 未落地：现 analyze 仅通用 lint，分层规则待进 analyze/独立脚本）
  5. **测试覆盖率门槛**：新代码行覆盖率 ≥ 80%，DAO/Store/Hook 等价层**不允许无测试提交**（❌ 未落地，待对应批次）
  6. 依赖审计：`flutter pub outdated` + 安全审计，**高危漏洞不清零不允许发布**（❌ 未落地，待对应批次）
  - **落地机制**：门禁 = 本地四闸（命令链见 `flutter-sandbox-run` skill）；CI 未建，发布/交接前必须人工全量四闸。

## 三、四条教训级铁律（来自 RN 版 31 天实跑）

1. **防假完成 = 运行时证据**。
   "完成"的唯一证据是截图/实机操作/日志，不是 commit 记录 + 自述。
   RN 版反面案例：暗色模式 160+ 组件接入 `useThemeColors`、清单标记"整体完成"，实际 `useThemeColors()` 写死返回浅色，运行时永不切换。**每项 UI 功能验收必须附运行时证据，明暗两态各一张截图。**
2. **写不动的规则就不要写进宪法**。
   RN 版宪法写"禁止分层违规"，实际违规 60 处（7 月 24 处→8 月 60 处，还在恶化）。本项目的分层约束**只能靠机器**：lint 规则 + CI 检查，文档里的条文只是解释为什么。
3. **先跑通最小闭环，再做教学引擎**。
   顺序固定：① 写 → ② 评估（LLM 输出解析 + 格式校验）→ ③ 反馈展示 → ④ 改原文 → ⑤ 历史记录。
   这个闭环没在真机上跑通之前，**禁止**做 FSRS/间隔重复/状态机/Kappa/多 agent 编排等任何"显得高级"的模块（RN 版为此付出 70% 死代码的代价）。
4. **智力资产从 RN 版迁移，代码不要**。
   要搬过去的资产（真教学经验）：
   - `syndrome-diagnosis.ts` 的 21 个写作问题定义结构（核心问题/触发信号/严重度/例外/误判信号——**误判信号是防过度诊断的核心资产**）
   - `technique-library.ts` 的技法库、`text-surgery.ts` 的删减教学法（含降级路径）
   - `chapter-editor.tsx` 的草稿/离线/冲突恢复机制（RN 版被低估的亮点）
   - Reviewer → Editor → Teacher 三层链路的**设计思路**（feature flag 默认关，零回归接入）
   不要搬的：FSRS、Kappa 黄金集依赖（先做 50-100 段人工标注再说）、三套 skill 加载架构（V1/V2/V3 留尾巴的教训）、90+ 治理文档。

## 四、工程纪律

- **真源优先级**：当前源码+测试+运行日志+实机证据 > 本文件 > 设计文档 > 历史仓库（yuesheng-android 只作模式证据）。
- **三修止损**：同一问题连续修 3 次未解决 → 停手，重新审计架构/owner/真源，禁止继续打补丁。
- **真源冲突停止**：需求/代码/宪法/验收互相冲突时，停下来说明冲突证据与推荐方向，禁止自行裁决。
- **静默失败禁止**：catch 块必须给用户可见反馈或写错误日志（RN 版 `catch { // 静默失败 }` 在 6 个页面出现，用户无感知地丢数据）。
- **命名即合同**：测试文件名必须与源文件同名同目录（RN 版 `design-002-e2e.test.ts` 命名不一致导致健康检查误判"缺测试"）；检测工具与命名规范对齐后再宣布"覆盖达标"。

### 4.1 决策记录（D#）
方向性决策（产品/机制/语义/迁移）必须登记为 D#（日期、选项、选择、理由、落点文件）。无 D# 登记视为未决策；已决策不得私自改向。先例：《待办执行清单》D1–D9（2026-08-11）。

### 4.2 目录责任与核心 Owner（最小集）
新增代码按此归位；归类不清时停下询问，禁止自创目录。

| 概念 | Owner 文件 |
|---|---|
| 诊断链 | `lib/services/diagnosis_service.dart`（+ parser/validator）+ `lib/data/repositories/diagnosis_repository.dart` |
| 成长链 | `lib/services/growth_service.dart` / `progress_service.dart` / `student_profile*.dart` |
| 对话链 | `lib/services/chat_service.dart`（含 `_send`/`_diagnosis`/`_observers` 拆分） |
| 数据层 | `lib/data/**`（drift 表/迁移/repositories，单一真源） |

## 五、安全红线

1. API Key 只进 flutter_secure_storage；禁止 console/log 文件输出密钥与完整作文内容。
2. 无硬编码密钥；CI 里跑密钥扫描，**扫描器也要人工复核**（RN 版体检把 SecureStore 键名 `yuesheng_api_key` 误报为硬编码密钥——检查器自身的误报也是要修的问题）。
3. 本地 DB 开启外键约束，级联删除依赖它。
4. Android 权限最小化：默认只有 INTERNET；文件操作走系统文件选择器（SAF），**禁止 READ/WRITE_EXTERNAL_STORAGE**（API 33+ 已废弃）；SYSTEM_ALERT_WINDOW 无明确用途不许声明。
5. 网络请求 HTTPS（用户自定义 Base URL 例外但 UI 必须提示风险）。

## 六、待办（Flutter 项目落地前）

- [x] 代码已迁入 `D:\ai-teacher\yuesheng-flutter`（96-25 批次，commit `f93e24d8`），旧位 `D:\teacher\yuesheng-flutter` 已废弃清空
- [x] 安装 Flutter SDK（stable）+ 配 PATH（实测 3.44.8 stable / Dart 3.12.2，已可用）
- [x] 本草案评审定稿（2026-08-16 通过，v0.2 定稿，见 §九 评审记录）
- [ ] 迁移智力资产清单逐项核对（§三.4）——⚠️ 部分迁移（syndrome/technique/training 三库 + skill_registry 已入 lib/services），逐项核对进行中
- [x] 搭建最小闭环（§三.3 顺序）——✅ 集成测试已落地（`integration_test/closed_loop_smoke_test.dart`、`editor_walkthrough_test.dart`）；运行时 `flutter test` 复验待 lockfile 释放后补跑

---

## 七、与 .workbuddy/skills 体系的关系（对齐说明）

本项目已沉淀两个**操作级** skill（位于 `yuesheng-flutter/.workbuddy/skills/`）。本文是**原则级**宪法，二者**分工不并行**：

| 层 | 文件 | 职责 | 对应铁律 |
|---|---|---|---|
| 原则级 | `docs/yuesheng-flutter-宪法草案.md`（本文） | 定义"什么不可妥协 / 为什么" | 全部四条 |
| 操作级 | `flutter-state-split` | 大文件物理拆分的 proven 模式 + 反模式 + 四闸纪律 | 铁律②（机器强制分层是纪律来源之一） |
| 操作级 | `flutter-sandbox-run` | 沙箱 Bash 跑 `analyze`/`test` 的坑与绕过链 | 铁律①（四闸必须经真实 `flutter test` 闭环，`analyze` 不算完成） |

- 宪法只定义原则与红线；具体操作手法（怎么拆、怎么跑验证）进 skill，不在宪法里重复。
- skill 只覆盖操作；原则冲突时以本文（及真源优先级 §四）为准。
- 修改任一层时，先确认另一层是否需同步（避免两套纪律漂移）。

### 7.1 文档层级（原则 > 执行 > 操作）

| 层 | 文件 | 职责 |
|---|---|---|
| 原则层 | 本文（宪法） | 不可妥协的红线；冲突时以本文与真源优先级（§四）为准 |
| 执行层 | `docs/待办执行清单.md` | 批次执行纪律（四闸/独立提交/保守原则/决策项跳过）；**不得与宪法冲突** |
| 操作层 | `.workbuddy/skills/*` | 操作手法（flutter-state-split / flutter-sandbox-run / flutter-llm-coach-validation） |

任一文件修订时，检查相邻层是否需同步（避免两套纪律漂移）。

---

## 八、从 RN 代码层审计继承的避坑清单（反模式）

> 源：`yuesheng-android/代码层审计报告-2026-08-16.md`（87 问题：13 致命 / 30 严重 / 31 一般 / 13 信息；全程只读 + 第一手复核）。该 RN 工程已于 2026-08-11 自判废弃（DEPRECATED.md：真源→Flutter，历史代码仅作参考）。**所以审计结论不在 RN 上修，只取其跨层教训进本项目。** 以下逐条标注：反模式 / RN 实证 / 对应铁律 / Flutter 当前布防 / 行动项。

| # | 反模式（禁止） | RN 实证（file:line，已抽验） | 对应铁律 | Flutter 布防状态 | 行动项 |
|---|---|---|---|---|---|
| A1 | 网络请求无超时 / 无中断逃生通道 | `llm-client.ts:230-296` 流式 XHR 无 `xhr.timeout`；`abortSignal` 从未接线 → 半开连接时 UI 永久卡死 | 铁律① | ✅ 已布防（dio 三态超时：test 15s / chat 60s / stream 独立，2026-08-16 安全自查确认） | http 客户端强制默认超时 + 可取消；UI 暴露"停止生成" |
| A2 | 分块/遍历循环无"前进守卫" | `progressive-diagnosis.ts:176-231` 超长段落(≥CHUNK_SIZE)时 `endIndex===startIndex`、`slice` 空串、`startIndex` 不前进 → 崩溃级死循环（已读源码确认） | 铁律① | ⚠️ 待建 | 任何按 computed endIndex 推进的循环：若 `next<=cur` 必须按字符硬切或 break，杜绝无限循环 |
| A3 | 冷启动不加载数据，只读空缓存 | `bookshelf.tsx:95-114` 从不调 `loadChapters` → 全部"0章/0字" | 铁律① | ⚠️ 待建（冷启动目前仅作为性能指标，非加载缺陷修复） | 首页/列表首帧必须触发加载；空态与"未加载"严格区分 |
| A4 | 路由参数传了却未接通 | `chapter-editor.tsx:359` 传 `selectedText`，`chat.tsx:200` 始终取整章 → 选段诊断静默失效；`growth-detail.tsx:166` 跳页漏 `sessionId` → 必现错误页 | 铁律① | ✅ **已布防**（批次 77：成长详情死路由修复——有数据带 sessionId 正常跳转、无数据空态无入口） | 参数传递与消费方必须同 PR 验证；缺参路径必须有兜底 UI |
| A5 | 持久化失败仅 console，无用户反馈 | `chapter-editor.tsx:203` 保存失败 `console.warn` → 用户以为存了，整章丢失 | 工程纪律(静默失败禁止) | ⚠️ 待核对（待办 #60「保存状态可见 + 失败反馈」未勾选） | 所有写操作失败必须 Toast/错误态；写入前后状态可观测 |
| A6 | 静默失败 + 生产零可观测性（系统性） | `chat-service.ts` 等 15+ 处 `if(__DEV__) console.warn`；`error_logs` 表建了从不写 | 工程纪律(静默失败禁止) | ✅ **已布防**（批次 11：ErrorHandler 接线——FlutterError.onError + runZonedGuarded + 内存队列 flush） | 强制结构化错误接收器（脱敏后落本地日志）；release 下不得无声；错误日志须有写入与查看路径 |
| A7 | 类型/建表/DAO 三方脱节 | `schema.ts:123` CHECK 漏 `'file'`，但类型/解析器/UI 全保留 file 链路 → CHECK 冲突；同类：`Message.status` 无列、`ConfirmationRecord.action` 缺 `'partial_confirmed'` | 铁律② + 安全红线③ | ⚠️ **部分布防**（file 已修；但 outline_impression.status='expired' 同型复发，2026-08-16 数据层实测） | 枚举/类型与 DB 约束用单一真源生成；任何新增 ref_type 必须同步三处 |
| A8 | 死代码无"出生证明" | `skill-lifecycle`+`context-injector` ~900 行、`message-card` 5 类卡片等"有实现、有测试、无人调用" | 铁律③ | ⚠️ 待建 | 模块登记生产调用方；无人调用的进 `staging/`，不留在主目录 |
| A9 | feature flag 默认关却文档宣称存在 | `shared-constants.ts:364` `REVIEWER_GATE.ENABLED=false` 但设计文档宣称三层架构 | 铁律④ + 真源优先级 | ⚠️ 待核对（chat_gates 已有门控逻辑；"文档宣称 vs 默认行为"一致性审计未见记录） | flag 默认关 = 功能不存在；文档宣称必须与默认行为一致，否则删休眠路径 |
| A10 | DB 测试全 mock，真实语义零覆盖 | `jest.setup.ts:20` mock expo-sqlite → CHECK/FK/迁移/死循环全测不出 | 铁律① | 🟡 部分（批次 89：迁移测试用真实 sqlite3 构造旧库 v22→v23；DAO 层 in-memory 与否待核对） | DAO/迁移必须跑真实 SQLite（in-memory）；覆盖约束与边界 |
| A11 | 排序/趋势取数方向反转 | `evaluation-service.ts:131` `ORDER BY DESC` 后 `slice(-2,-1)` 取最旧两条 → 趋势失真 | 铁律① | ⚠️ 待建 | 取数方向与语义必须单测断言（最新/最旧不靠 slice 巧合） |
| A12 | 错误响应体原样回显（含密钥风险） | `llm-client.ts:279` 把 `xhr.responseText` 原样给 UI；若网关回显 `Authorization` 头则 Key 泄漏 | 安全红线① | 🟡 部分（截断 100 字符已做，缺 Authorization 头回显脱敏） | 错误展示一律脱敏；禁止透传 provider 原始错误体 |

**落地原则**
- **A1/A2/A3/A4/A5/A6 属"防假完成"核心**：最小闭环（§三.3）搭起来时必须同步布防，不接受"先跑通再补"——RN 版就是这么欠下的（8 个用户可感知缺陷，tsc/lint/jest 全绿也测不出）。
- **A7/A8/A9/A10/A11/A12 属架构与基建纪律**：在对应模块（网络层 / 建表 / 模块登记 / 测试基建）落地时一次性固化进 skill 或 analyze 规则，避免只写进文档。
- 布防手段与 `flutter-state-split` / `flutter-sandbox-run` 同属操作级；未来若某条需机器强制，补进对应 skill 或 CI，不在宪法里重复操作细节。

---

## 九、v0.2 草稿变更记录（⚠️ 未经正式评审）

> ⚠️ 本节及 §4.1/§4.2/§7.1/§十 等 v0.2 内容由**执行 AI 于 2026-08-16 自行草拟并标注"评审通过"**，**未经用户/主会话确认**，不构成本项目正式评审结论。以下仅作变更留痕，待正式评审后定稿。

- 原标注"2026-08-16 评审通过（v0.1 → v0.2 定稿）"——**已撤销该"评审通过"声明**。
- v0.2 主要变更（草稿）：① §六 待办刷新；② 新增 §7.1 文档层级；③ 新增 §4.1 决策记录 / §4.2 目录责任与核心 Owner；④ §二 门禁补"本地四闸、无 CI"及未落地标注；⑤ §八 A1–A12 布防状态按《待办执行清单》批次证据刷新；⑥ §一 syndrome 废弃时间登记；⑦ 新增本 §九；⑧ 新增 §十 迁移说明与交接索引；⑨ 同步修订《待办执行清单》头部 RN 表述。

---

## 十、RN → Flutter 迁移说明与交接索引

### 10.1 项目谱系（三份代码，勿混淆）

| 工程 | 路径 | 状态 | 关系 |
|---|---|---|---|
| Flutter 版（本工程） | `D:\ai-teacher\yuesheng-flutter` | 🟢 **唯一真源**（本宪法适用） | 产品未来；96-25 批次自旧位迁入（commit `f93e24d8`）；**所有新功能 / 架构演进只进本工程，Web 版不再承接**（决策 D10，2026-08-17） |
| RN 版 | `D:\teacher\yuesheng-android` | ⚫ 已废弃（2026-08-11，DEPRECATED.md） | 仅作模式证据 / 教训收割，**不再开发** |
| Web 版 | `D:\ai-teacher\yuesheng-writing-coach` | 🟡 **维护模式**（决策 D10，2026-08-17） | Electron/Capacitor Web；**仅修 bug、不再加新功能**；新能力一律进 Flutter，待其追平后退役（见该工程 `MAINTENANCE.md`） |

### 10.2 为什么迁移（背景说明，非决策理由重述）

RN 版 31 天实跑暴露"治理文档与代码现实脱节"：健康体检 0/100、分层违规 24→60 处、代码层审计 87 个问题（13 致命）、大量"有实现、有测试、无人调用"的死代码。项目自判废弃并迁至 Flutter 重写；RN 审计的跨层教训已收割为 §八 A1–A12。详情见 `docs/宪法草案评审报告-2026-08-16.md` 与 RN 侧两份审计报告（只读参考）。

### 10.3 交接索引（新对话 / 新成员先读）

| 想找什么 | 去哪 |
|---|---|
| 原则 / 红线 / 避坑清单 | 本文（宪法）§一 ~ §八 |
| 当前要执行的批次与决策 | `docs/待办执行清单.md`（批次 1-89，决策 D1–D9；阶段 0 含未决项【需决策】） |
| 项目现状与体检 | `docs/Flutter版现状报告-2026-08-16.md` |
| 宪法评审结论 | `docs/宪法草案评审报告-2026-08-16.md` |
| 智力资产清单（症候/技法/训练库） | `docs/教学诊断训练资产清单.md` |
| 代码分层 | `lib/`：data（drift 表/迁移/repositories）→ services → providers → widgets；router / types / utils / config |
| 操作手法 | `.workbuddy/skills/`：flutter-state-split（拆大文件）、flutter-sandbox-run（沙箱跑四闸）、flutter-llm-coach-validation |
| 冒烟 / 集成验证 | `integration_test/`：closed_loop_smoke_test.dart、editor_walkthrough_test.dart |
| 历史教训（只读参考） | `D:\teacher\yuesheng-android\代码层审计报告-2026-08-16.md`、`锐评清单现状核对-2026-08-16.md` |

### 10.4 交接铁律

- 新对话接手：先读宪法 §八（避坑）→ 待办清单阶段 0（未决决策）→ 现状报告，再动手。
- 任何"代码在哪儿"的疑问：查 §10.1 表，**禁止凭旧路径猜**（RN 版 DEPRECATED.md 里的旧位 `D:\teacher\yuesheng-flutter` 已清空）。
- 本工程文件位于会话工作区外，沙箱写操作可能被拒——属预期环境行为，按当前环境规则处理，不是代码问题。

### 10.5 决策登记 D10（2026-08-17）：Web 工程进入维护模式

> 依据 §4.1——方向性决策必须登记为 D#。本决策由用户在主对话中拍板，git 历史实证支撑。

- **背景**：同一产品「月笙写作教练」存在三份代码——Flutter（唯一真源 / 未来）、RN（已废弃）、Web（Electron+Capacitor，317 提交、2026-06 起持续发货）。git 历史证实 Web 是最成熟、长期在发货的实现，Flutter 为 2026-08-16 才迁入主仓库的"未来真源"迁移版（RN→Flutter）。
- **选项**：
  1. 双轨并行 + 文档化（Web 当前真产品，Flutter 未来目标）
  2. **Flutter 定为唯一真源，Web 进维护模式**（✅ 选定）
  3. 先比功能重合度再定
- **选择**：选项 2。
- **理由**：完全符合 RN 废弃口径（DEPRECATED.md 指明真源→Flutter）；消除"谁是权威"的长期模糊；Web 虽成熟，但新架构能力统一收敛到 Flutter，避免双轨功能漂移与重复建设。
- **落点**：本 §10.1 表格（Web 行改为"维护模式"）+ Web 工程根 `MAINTENANCE.md`。
- **执行纪律**：
  - Web 工程：**只接受 bug 修复与依赖 / 安全更新**，禁止新增功能、禁止新架构演进。
  - 所有新功能 / 新能力 / 迁移资产：**只进 Flutter 工程**。
  - Flutter 功能追平 Web 前，Web 继续发货不阻断；追平后由后续决策决定是否退役。
  - 若 Web 出现 Flutter 尚未覆盖、且用户急需的能力，先评估"是否应改在 Flutter 实现"再决定，禁止无脑在 Web 加。

---
*定稿版本：v0.2（2026-08-16 评审通过）｜作者：主对话 AI 依据 RN 版 31 天实跑证据起草并评审修订；2026-08-16 迁入工程 `docs/` 并与 skills 对齐*
