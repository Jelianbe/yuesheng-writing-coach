# ADR-C71 · 跨会话教学状态延续：beginnerLevel 继承 + onboarding 用户级回退读取

- **状态**：Accepted（2026-09-04，舰长授权「按你推荐的来」）
- **类型**：教学状态机 / 会话生命周期（核心模块，先 ADR 后动手）
- **来源**：`docs/audits/从零构建线现状审计-2026-09-04.md` F1/F2；
  关联回归报告 N-1（`docs/audits/真机行为回归-报告-2026-09-04-夜间子代理采样.md` §三）。

## 1. 问题

`teaching_state` 与 session 一对一（`tables.dart:186`），新建会话一律
`P0_ENGAGE + beginnerLevel=null`（`session_repository.dart:36-45`），无继承；
onboarding_data 按 session 存取（`student_profile.dart:201-207`），而
`questionnaire_completed` 是用户级标记（永不再弹）。组合结果：

1. 零基础学员（N0–N2，按设计需多会话完成、且不产生诊断记录）在第二个会话里
   `isBeginner=false` → beginner L2 组与 N0–N4 课程整段消失，画像/认知风格为空；
2. phase-mapper 规则 4 把「N 系未知」默认按 N3 处理 → 回归学员被当可诊断学员；
3. 唯一恢复通道是 LLM 诊断块的 `suggested_beginner_level`，而该通道与 §3.9
   「从零构建不附加」存在规则冲突（N-1），实测行为分裂（1/2 发块）。

## 2. 裁决

**beginnerLevel 是用户级学习属性，跨会话延续；phase/subphase 是会话级关系属性，维持现状。**

| 项 | 裁决 | 理由 |
|:--|:--|:--|
| `beginnerLevel` | **新建会话时继承全库最新非空值** | 它是 N 系课程的进度坐标（用户属性），不是对话属性；N 系优先规则（phase-mapper 规则 1）下 N0–N2 学员的行为由它驱动 |
| `currentPhase` / `currentSubphase` / `attitudeLevel` | **不继承，维持 P0 起步** | 阶段是「这段教练关系」的属性；新对话回到 P0（建立投入）本就是现有语义且被锚点/测试固化。继承 phase 反而会把稿件 A 的 P3 带进与稿件 B 无关的新对话 |
| onboarding_data | **写入仍 session 级（不动 schema）；读取加用户级回退**（本会话无 → 取全库最新有效值） | R-010 最小改动：复用现有 `student_model` 存储，不迁移数据；「跳过」的问卷不作为有效来源（沿用 `effectiveOnboarding` 的 skipped 过滤） |
| 消费指令（F2） | **保留问卷，在画像【学员初始画像】节内补一段教学加权指令** | Q1 的硬接线已证明问卷数据可用；砍掉 Q2/Q3 是更大的行为变更。指令保持通用（不新增 A→B 静态映射表），并显式声明 R-009 优先级：学员当轮请求 > 问卷画像 |
| 认知风格重复段 | **onboarding 存在时不再重复输出第二步「认知风格」段** | 该段与初始画像的「学习偏好」同源同值；且其「依据：基于用户历史关键词推断」在来源为问卷时是失实陈述 |
| N-1（prompt 侧 §3.9 撞车裁决） | **本 ADR 不改 prompt 字节**；补丁建议移交内容线按其流程执行 | 改 L1 常驻层属高风险内容变更，需锚点重生成 + 盲测，属内容线队列 |

## 3. 实施

| # | 文件 | 改动 |
|:--|:--|:--|
| 1 | `student_model_repository.dart` | 新增 `getLatestOnboardingData()`：跨会话取最新有效 onboarding JSON（非 null / 非空 / 非 'null' 字面量，按 `updatedAt` 降序；解码失败走 `logDecodeFailure` 返回 null） |
| 2 | `student_profile.dart` | `buildStudentContext`：本会话 `getOnboardingData` 为空时回退 `getLatestOnboardingData()`；skipped 过滤不变 |
| 3 | `session_repository.dart` | `createBlankSession`：创建 teaching_state 前查全库最新非空 `beginnerLevel`（按 `updatedAt` 降序），存在则写入新行 |
| 4 | `student_profile_format.dart` | ① 【学员初始画像】节内追加消费指令；② onboarding 存在时跳过第二步「认知风格」子段（消重复 + 消失实依据） |

## 4. 已知取舍与不做的事

- **继承 beginnerLevel 不继承 phase** 的代价：P 系学员（N3/N4 或未填问卷）跨会话仍回到
  P0——与现状一致，本 ADR 不扩大战场；P 线跨会话延续（诊断画像已跨会话，缺口主要在
  阶段记忆）留待真实使用数据证明必要性后再议。
- **孤儿行**（session 删除后 `ON DELETE SET NULL` 的 student_model）：`getLatestOnboardingData`
  不排除它们（与 `hasAnyOnboardingData` 同口径）——数据本身仍代表用户的历史自报。
- **「重新做问卷」入口**（UI）：不做，登记为后续项——当前问卷三题可用性与真实用户反馈
  未见证据前，先不加重入手。
- 体裁是否进问卷：不在本 ADR 范围（N35 修复已让「对话中确认体裁」可用）。

## 5. 验收

1. 新增测试：会话继承（有历史 → 继承；无历史 → null；最新值胜出）+ onboarding 回退
   （本会话无 → 取最新会话的；skipped 不作为有效来源）+ 画像文本（消费指令存在且仅随
   初始画像出现；onboarding 存在时无重复认知风格段）。
2. 六道门禁全绿（`bash scripts/gate.sh`）。
3. 变异验证（V4.15 两次）：① 能失败——临时移除继承逻辑，新会话测试必须红；② 能抓真问题——
   按「用户填过问卷 → 删掉该会话行场景」造真实回归，确认回退路径抓得到。
4. 锚点快照零变化（本 ADR 不触碰 `buildSystemPromptV2` 注入路径；画像文本不是锚点对象，
   但行为变化已在测试中显式断言）。

## 6. 后续（不在本 ADR）

- N-1 补丁（内容线）：§3.9 撞车裁决表补第三行「零基础首触且无文本 → 附最小块
  （syndromes 空 + suggested_beginner_level）」或改其他激活通道，二选一后同步护栏 + 锚点。
- 「重新做问卷」UI 入口；体裁进问卷。
- P 线阶段跨会话延续（视真实使用数据）。
