# Skill 正交重构 — Phase 0 拆分清单（待舰长签字）

> 关联方案：`docs/designs/2026-08-28-skill-orthogonal-refactor-plan.md`
> 关联 ADR：`docs/ADR-skill-orthogonal-model.md`
> 日期：2026-08-28 · 执行者：WorkBuddy · 状态：**待舰长确认后，方可进入 Phase 1**

---

## 0. 执行摘要（一句话结论）

- **基线门禁**：`dart format`=0 / `flutter analyze lib`=0 / circular=0 **全绿**；`flutter test --no-pub --exclude-tags live,external` 已于后台启动（Phase 1 首个代码改动前必须全绿）。
- **注册表复核**：40 条注册 ≈ **37 个本体**（V1/V2 双轨 + 跨组共享），结构与方案 §1 一致；**但方案 §1 的 `estimatedTokens` 估值与代码实测偏差较大**，需以代码为准（见 §1 备注列）。
- **拆分框架已建立**：按 ADR §2.3「删掉这句话，AI 还知道教什么」逐句判定；**5 个 P0 本体已完成原文逐句粗分**，其余本体完成 ontology-level 分类（细节留待 Phase 4 深拆）。
- **动作维度已现雏形**：`coaching-actions-v2` 本身就是「A001–A016 教学方法目录」，几乎就是正交模型里的「动作卡」种子，Phase 4/5 可顺势收口。

---

## 1. 复核后的注册表全景（grounded，以代码 `estimatedTokens` 为准）

挂载说明：`L1*=L1常驻（l1SkillIds 全场景必载）`；`态度*`=态度档位（`attitude-*` 全场景必载）；其余按 `l2SkillMap` 所属 `L2Mode`。

### 1.1 L1 常驻（always）

| id | group | 代码 tokens | 方案 §1.1 | 备注 |
|----|-------|-----------:|----------:|------|
| core-iron-triangle | core | 600 | 400 | 偏差 |
| core-product-identity | core | 1200 | 630 | 偏差 |
| writing-anchors | core | 450 | 410 | 略偏 |
| teaching-strategy | core | 3300 | 4400 | **偏差（详见 §3）** |
| phase-mapper | core | 2200 | 100 | **严重偏差** |
| scenario-rules | core | 1100 | 560 | **偏差** |
| validation-rules | core | 1700 | 780 | **偏差** |
| teaching-modes | coaching | 1800 | 1600 | 略偏（group=coaching，非 core） |
| reply-voice | core | 300 | 300 | 一致 |

> ⚠️ **group 列 = `SkillMeta.group`（内容语义标签），不等于挂载组（L2Mode）**。二者是正交维度：例如 `teaching-modes` 的 group 标为 `coaching`，但它在 L1 常驻层（全场景加载），不属任何 L2Mode。下同。

### 1.2 态度档位（always）

| id | group | 代码 tokens |
|----|-------|-----------:|
| attitude-doubao | attitude | 450 |
| attitude-yuesheng | attitude | 500 |
| attitude-sensei | attitude | 600 |

> 纯姿势，零教学内容（ADR §1.2 已确认），本重构不动。

### 1.3 L2 beginner 组

| id | group | 代码 tokens | 挂载 | 备注 |
|----|-------|-----------:|------|------|
| beginner-path | teaching | 3200 | beginner | |
| gap-detector | diagnosis | 1700 | beginner | group=diagnosis |
| coaching-rhythm | coaching | 3500 | beginner + diagnosis | **P0 跨组重复** |
| narrative-design | teaching | 3800 | beginner + diagnosis + outline | **P0 跨组+大块** |
| plot-design | teaching | 3400 | beginner + diagnosis + outline | **P0 跨组+大块** |
| writer-psychology | coaching | 3200 | beginner + training | 跨组 |

### 1.4 L2 diagnosis 组

| id | group | 代码 tokens | 挂载 | 备注 |
|----|-------|-----------:|------|------|
| reader-awareness | teaching | 2200 | diagnosis + training + advanced + outline | **P0 跨组重复** |
| genre-guide | teaching | 3500 | diagnosis + advanced | 跨组 / 大块 |
| writing-style | teaching | 2800 | diagnosis + advanced | 跨组 |
| diagnosis-confirmation | teaching | 700 | diagnosis | group=teaching |
| feedback-cognition | diagnosis | 900 | diagnosis | |
| syndrome-diagnosis-index | diagnosis | 1800 | diagnosis | 虚拟索引（L3） |

> 说明：方案 §1.1 将 diagnosis「L2 diagnosis 5」理解为 5 个 diagnosis-native 本体；实际 `l2SkillMap.diagnosis` 在这 6 个 native 之外还挂载 `coaching-actions / coaching-rhythm / narrative-design / plot-design`（4 个跨组本体），合计 6 + 4 = **10 条**。结构结论不受影响，仅清单口径需要调整。

### 1.5 L2 training 组

| id | group | 代码 tokens | 挂载 | 备注 |
|----|-------|-----------:|------|------|
| technique-library-index | training | 900 | training | 虚拟索引（L3） |
| training-loop **(V1)** | training | 3500 | training + advanced | **V1 残留，pilot 下不加载** |
| training-loop-v2 | training | 900 | training + advanced | V2 |
| training-templates-index | training | 1500 | training | 虚拟索引（L3） |
| training-evaluation **(V1)** | training | 1800 | training | **V1 残留** |
| training-evaluation-v2 | training | 700 | training | V2 |
| text-surgery **(V1)** | training | 1600 | training | **V1 残留** |
| text-surgery-v2 | training | 400 | training | V2 |
| coaching-actions-v2 | coaching | 1400 | diagnosis + training + advanced + outline | **P0 跨组重复 / 动作卡种子** |
| demonstration | coaching | 2400 | training | |
| comparison | coaching | 2600 | training | |
| timed-rewrite | coaching | 1600 | training | group=coaching |
| model-rewrite | coaching | 1800 | training | group=coaching |
| revision-methodology | teaching | 2600 | training + advanced | 跨组 |
| reader-awareness | — | (见上) | training | 跨组 |
| writer-psychology | — | (见上) | training | 跨组 |

### 1.6 L2 advanced 组

| id | group | 代码 tokens | 挂载 | 备注 |
|----|-------|-----------:|------|------|
| advanced-phases | advanced | 4200 | advanced | **P1 单组大块** |
| outline-diagnosis | diagnosis | 4200 | outline | **P1 单组大块** |
| training-loop(-v2) | — | — | advanced | 跨组 |
| coaching-actions-v2 | — | — | advanced | 跨组 |
| revision-methodology | — | — | advanced | 跨组 |
| reader-awareness | — | — | advanced | 跨组 |
| writing-style | — | — | advanced | 跨组 |
| genre-guide | — | — | advanced | 跨组 |

### 1.7 注册表总数判定

- 注册条目：**40**（与方案 §1 一致）
- 去重本体：**37**（V1/V2 双轨 3 对合并 + 跨组共享不重复计本体）
- 方案称「~28 个本体」偏保守——按本次 grounded 口径约 **37 本体**；若进一步把跨组共享内容合并计为「一次存储多次挂载」，则「内容实体」约 27 个，与方案「~28」吻合。结论：**两种口径都成立，取决于「本体」是否区分存储与挂载**。

---

## 2. 跨组重复挂载（10 本体 / 26 次）— 与方案 §1.3 一致 ✅

| 本体 | 挂载组 | 次数 |
|------|--------|-----:|
| reader-awareness | diagnosis / training / advanced / outline | 4 |
| coaching-actions(-v2) | diagnosis / training / advanced / outline | 4 |
| narrative-design | beginner / diagnosis / outline | 3 |
| plot-design | beginner / diagnosis / outline | 3 |
| coaching-rhythm | beginner / diagnosis | 2 |
| writer-psychology | beginner / training | 2 |
| genre-guide | diagnosis / advanced | 2 |
| writing-style | diagnosis / advanced | 2 |
| training-loop(-v2) | training / advanced | 2 |
| revision-methodology | training / advanced | 2 |

> Phase 2（跨组去重）的目标：同一份 content 只存一次，各组改为「语境指针 + 适配指令」（方案 Phase 2 方案 A）。

---

## 3. 大块清单（按代码 `estimatedTokens`，阈值 3300）

| Skill | 代码 tokens | 挂载 | 方案 §1.4 记 | 分类 |
|-------|-----------:|------|-------------|------|
| advanced-phases | 4200 | advanced(单) | 4200 | **P1 单组大块** |
| outline-diagnosis | 4200 | outline(单) | 4200 | **P1 单组大块** |
| narrative-design | 3800 | 跨 3 组 | 4200 | **P0 跨组+大块** |
| coaching-rhythm | 3500 | 跨 2 组 | 3500 | **P0 跨组+大块** |
| genre-guide | 3500 | 跨 2 组 | 3500 | 跨组+大块 |
| plot-design | 3400 | 跨 3 组 | 3400 | **P0 跨组+大块** |
| teaching-strategy | 3300 | L1常驻(单) | 4400 | **P1 L1 大块（倾向保留整块）** |

> 方案 §1.4 以「3500+」为界，含 teaching-strategy(4400)/narrative-design/advanced-phases/outline-diagnosis/coaching-rhythm/genre-guide/plot-design 共 7 块。
> 按**代码实测**，teaching-strategy 实际 3300（未达 3500 阈值），但因其 L1 常驻且体量最大，仍列入「大块治理」讨论。
> **Phase 3 索引化对象**（6 个 L2 大块）：narrative-design / plot-design / reader-awareness(2200，非大块但跨组) / coaching-rhythm / advanced-phases / outline-diagnosis / genre-guide。teaching-strategy 因 L1 不随场景切换，**单列决策**（倾向保留整块，不动索引化）。

---

## 4. 逐本体「知识 / 动作 / 话术」分类（Phase 0 核心产出）

### 4.1 判定方法（ADR §2.3）

> 「删掉这句话，AI 还知道教什么吗？」
> - **知道** → 动作/话术，可抽走或参数化（留 skill / 进态度参数）
> - **不知道** → 知识，进数据（L3 知识库）

### 4.2 P0 本体深拆（已读原文，逐句粗分）

#### ① narrative-design（3800，挂 beginner/diagnosis/outline）— 知识为主、动作/话术为辅
- **知识（进数据）**：
  - 世界观五层递进框架（核心差异→运作逻辑→社会结构→环境影响→收敛）
  - 角色四层框架（欲望与恐惧→缺陷与弧光→日常质感→收束）
  - 配角功能分类（盟友/对手/镜像/催化剂）
  - 交织检测三问（角色承载/塑造/改变世界）
- **动作（留 skill）**：
  - 「每层只进一层，不连续跳」「用户回答越短→收住」「根据用户回应深度逐层推进」
  - 红线：「不接受'他太善良'作缺陷」「不替用户设计弧光」
- **话术示例（可参数化）**：
  > 「如果用一个词描述你这个世界和现实世界最大的不同，会是什么？」
  > 「这个故事结束时，他有什么事情做不到了 / 不做了 / 开始做了？」
- **拆分建议**：知识主体下沉到 `narrative_kb_content.dart`（仿 syndrome 模式）；skill 仅留「递进节奏约束 + 红线」；话术按角色/世界观两类模板参数化。

#### ② plot-design（3400，挂 beginner/diagnosis/outline）— 知识（因果链理论）最纯，动作次之
- **知识（进数据）**：
  - 「故事结构 = 因果链」「B 必然因 A」的本体论
  - 引擎公式：欲望→障碍→行动→结果→新欲望
  - 张力弧理论（波峰波谷交替）、场景功能自检标准
- **动作（留 skill）**：
  - 引擎启动三问（事件/驱动力/方向）、因果链追问法（「因为 A 发生，B 必然发生吗？」）
  - 红线：「不要问结局」「问方向」「收在第一个里程碑」
- **话术示例（可参数化）**：
  > 「你能不管这件事吗？不是你想不想，是能不能。如果他走开，什么会追上来？」
  > 「下一句话，读者最想知道的是什么？」
- **拆分建议**：因果链理论 → 数据；「三问 + 因果链追问」作为动作卡；话术参数化「方向/驱动力」两类。

#### ③ reader-awareness（2200，挂 diagnosis/training/advanced/outline）— 知识/动作均衡
- **知识（进数据）**：
  - 三种信息关系（读者=角色 / <角色 / >角色）
  - 读者情感旅程、读者疲劳四类（信息/情绪/认知/期待）
  - 体裁「隐性合同」（悬疑在猜 / 言情在等 / 玄幻在体验 / 都市在对照）
- **动作（留 skill）**：
  - 「第一读」实验流程（当陌生人文本读一遍）
  - 信息释放节奏判断（读者的好奇心在哪，信息就在哪）
- **话术示例（可参数化）**：
  > 「这一段里——读者知道了什么角色还不知道的东西？」
  > 「作为读者，你读到了什么？你脑子里一闪而过的念头是什么？」
- **拆分建议**：三种信息关系 + 体裁合同 → 数据；「第一读」作为动作卡；话术参数化「体裁维度」。

#### ④ coaching-actions-v2（1400，挂 4 组）— 已经是「动作卡」原型，几乎无需拆
- **知识（进数据）**：A001–A016 方法「适用症候清单」（方法→症候映射表）
- **动作（留 skill）**：方法目录本身（A001 缩小范围 … A016 高频词清扫）——**这正是正交模型「动作维度」的种子**
- **话术示例（可参数化）**：方法自带「核心提问方向」（如 A004 现实锚点：「手会怎么放？眼神会怎么样？」）——可下沉为动作卡的参数化提示
- **拆分建议**：**动作维度可直接复用**，无需下沉；仅把「动作-症候映射」数据化（已是 `${kSyndromeRegistry...}` 模板，天然适合 L3）。优先级提为「先收口动作维度」。

#### ⑤ coaching-rhythm（3500，挂 beginner/diagnosis）— 动作/话术最重，知识最轻
- **知识（进数据）**：
  - 三层认知模型（P0 我的故事 → P1 暴露差距 → Layer2 理解目的 → P2 自主尝试）
  - P0/P1/P2 阶段定义
- **动作（留 skill｜大量）**：
  - P0 五步节奏（确认→选择→倾听→梳理→循环）及每步完成标志
  - P1 三类提问模式（聚焦/开放/镜像）+ 问题升级路径（现象→原理→动作）
  - Layer2 桥接输出格式（训练前「原因」/ 训练后「对比」）
- **话术示例（可参数化｜大量）**：
  > 「我理一下，你的意思是……对吗？」
  > 「我们做一次练习：在每句对话后面加上一个角色的小动作。」
- **拆分建议**：本 skill 几乎是「纯动作 + 话术」，知识极少。建议**整体保留为「对话节奏动作卡」骨架**，话术模板参数化（按小组/档位）。它本身就是正交「动作维度」的另一半。

### 4.3 P1 / P2 本体分类（ontology-level，Phase 4 深拆待补）

| 本体 | tokens | 归类判定 | 备注 |
|------|-------:|---------|------|
| advanced-phases | 4200 | 知识主导（P3/P4/P5 进阶指引） | P1 单组大块；Phase 3 索引化候选 |
| outline-diagnosis | 4200 | 知识主导（大纲结构诊断） | P1 单组大块；Phase 3 索引化候选 |
| teaching-strategy | 3300 | L1 常驻核心 | **倾向保留整块**（不随场景切换）；待决策 |
| revision-methodology | 2600 | 知识+动作均衡（L1–L5 修订层级模型） | 跨组；Phase 4 深拆 |
| writer-psychology | 3200 | 知识+动作均衡（6 大心理障碍 + 应对） | 跨组；Phase 4 深拆 |
| genre-guide | 3500 | 知识主导（体裁感知） | 跨组+大块；Phase 3 索引化候选 |
| demonstration | 2400 | 动作主导（示范三步流程 + 类型库） | Phase 4 深拆 |
| comparison | 2600 | 动作主导（A/B 对比教学） | Phase 4 深拆 |
| timed-rewrite | 1600 | 动作主导（限时重写形态） | Phase 4 深拆 |
| model-rewrite | 1800 | 动作主导（范文对照改写） | Phase 4 深拆 |
| gap-detector | 1700 | 知识+动作（能力缺口识别） | Phase 4 深拆 |
| beginner-path | 3200 | 知识+动作（N0–N2 生成式练习路径） | Phase 4 深拆 |
| writing-style | 2800 | 知识主导（风格识别） | 跨组；Phase 4 深拆 |
| diagnosis-confirmation | 700 | 动作主导（确认交互 FSM） | 已「FSM code-fied」，几乎无知识 |
| feedback-cognition | 900 | 动作主导（认知反馈） | 与 coaching-rhythm §五 重叠，注意去重 |
| training-loop(-v2) | 3500/900 | 动作主导（训练四阶段） | V1 退役后仅剩 v2 |
| training-evaluation(-v2) |  *  | 动作主导（评估） | V1 退役后仅剩 v2 |
| text-surgery(-v2) | 1600/400 | 动作主导（文本手术） | V1 退役后仅剩 v2 |
| training-templates-index | 1500 | 虚拟索引（L3） | 已索引化 |
| syndrome-diagnosis-index | 1800 | 虚拟索引（L3） | 已索引化 ✅ |
| technique-library-index | 900 | 虚拟索引（L3） | 已索引化 ✅ |

> `*`：training-evaluation V1=1800 / v2=700；text-surgery V1=1600 / v2=400；training-loop V1=3500 / v2=900。
> 注：feedback-cognition（§五 训练后反馈）与 coaching-rhythm §五（训练前桥接）存在**内容重叠**——Phase 4 需明确分工，避免重复注入。

---

## 5. 拆分优先级汇总 → 方案 Phase 映射

| 优先级 | 本体 | 映射到 |
|--------|------|--------|
| **P0（先行）** | narrative-design · plot-design · reader-awareness · coaching-actions-v2 · coaching-rhythm | Phase 2（去重）+ Phase 4（拆分）+ Phase 5（动作维度收口） |
| **P1（单组大块）** | advanced-phases · outline-diagnosis · teaching-strategy(L1) | Phase 3（索引化）；teaching-strategy 单独决策 |
| **P2（小块，逐个）** | 其余 ~18 个 L2 本体（含 3 个虚拟索引、3 个 V2 训练族、genre-guide 等 diagnosis/beginner 剩余） | Phase 4（逐本体拆分，单提交单验收） |

> **P0 判定标准**（自查校正）：跨 **3+ 组**挂载（narrative-design/plot-design/reader-awareness）**或** 动作维度种子（coaching-actions-v2 / coaching-rhythm）。
> genre-guide 虽达 3500 tokens 且跨 2 组，但仅 2 挂载 + 知识主导，归 P2（Phase 3 索引化候选），不进 P0。
> **P2 计数**（自查校正）：37 本体 − 5(P0) − 3(P1) − 3(态度,不动) − 8(L1 非拆分对象) = **18 个 L2 本体**。

**里程碑提醒**（方案 §10）：M1（Phase 1 V1 退役）零风险，建议确认后立即执行，先锁定确定性收益。

---

## 6. 待舰长确认事项（Decision Points）

1. **拆分框架与优先级**是否确认？尤其 P0/P1/P2 归类是否符合预期。
2. **teaching-strategy（L1 常驻，3300）**是否参与索引化，还是**保留整块**？（ADR 倾向保留；方案 Phase 3 也将其单列）
3. **索引化检索触发条件**（Phase 3 验收重点）：是否直接复用 syndrome/technique 既有 L3 检索链路（`L3RetrievalResult` + `syndrome_kb_content` 模式）？
4. **态度参数化（Phase 5）**：加第四档态度 = 加一个参数文件；是否需在契约层（`contracts/teaching_capability.dart`）预留 `AttitudeParams` 类型？
5. **是否现在进入 Phase 1（V1 退役，零风险）**？改动：`skill_registry.dart` 删_trainingLoop/_trainingEvaluation/_textSurgery 注册 + 对应常量；`l2SkillMap` 的 V1 id 字符串**不动**；验收 `getL2SkillIds` 逐字节一致 + 门禁全绿。

---

## 7. Phase 1 预览（待确认后执行，不在此轮改动）

- **删除 3 个 V1 注册残留**：`skillRegistry` 中 `'training-loop'` / `'training-evaluation'` / `'text-surgery'` 三行。
- **删除 3 个常量定义**：`skills_training_p2.dart:_trainingLoop` / `skills_training_p5.dart:_trainingEvaluation` / `skills_advanced_outline_p6.dart:_textSurgery`。
- **不动**：`l2SkillMap` 中的 V1 id（`getL2SkillIds` 靠 `v2SkillReplacements` 映射）；`training-loop-v2` 等 V2 本体保留。
- **前置 grep 校验**：确认无其它代码直接引用这三个 id / 常量（预期仅 registry 与 l2SkillMap）。
- **验收**：`flutter analyze lib` 零 issues → 完整门禁全绿 → `getL2SkillIds(L2Mode.training)` 结果与删除前逐字节一致（可临时断言或人工核对）。
- **风险**：零（pilot 已硬编码 true）。**回滚**：git revert。
- **前置 grep 已验证**（自查）：`'training-loop'|'training-evaluation'|'text-surgery'|_trainingLoop|_trainingEvaluation|_textSurgery` 在 `lib/` 内仅命中 `skill_registry.dart`（3 行注册）+ `skill_layers.dart`（l2SkillMap 字符串 + v2SkillReplacements 映射）+ 3 个常量定义文件自身。**无其它代码直连 V1 id / 常量**，Phase 1 删除安全。

---

## 8. 自查日志（Self-Check Log）

> 2026-08-28 自查：重读 `skill_registry.dart` + `skill_layers.dart` + 全量 `estimatedTokens` grep，逐项核对清单。

### 已修正错误

| # | 位置 | 错误 | 修正 |
|---|------|------|------|
| 1 | §1.1 | teaching-modes group 标 'core' | 代码 `group: 'coaching'` → 已改；加注 group≠挂载组说明 |
| 2 | §1.3 | gap-detector group 标 'teaching' | 代码 `group: 'diagnosis'` → 已改 |
| 3 | §1.4 | diagnosis-confirmation group 标 'diagnosis' | 代码 `group: 'teaching'` → 已改 |
| 4 | §1.5 | timed-rewrite group 标 'training' | 代码 `group: 'coaching'` → 已改 |
| 5 | §1.5 | model-rewrite group 标 'training' | 代码 `group: 'coaching'` → 已改 |
| 6 | §1.4 注 | syndrome-diagnosis-index 被误列为「跨组新增」 | 实为 diagnosis-native；新增仅 4 个，6+4=10 |
| 7 | §5 | P2 计数 "~25 本体" | 实为 **18 个 L2 本体**（37−5−3−3−8=18）；已改 |
| 8 | §5 | P0 标准 "跨组+大块" 过宽（genre-guide 也满足） | 收紧为「跨 3+ 组 或 动作种子」；genre-guide 归 P2 |

### 已验证正确 ✅

- 40 条注册 / 37 去重本体 / 10 跨组本体 / 26 跨组挂载次数 — 逐项复核 l2SkillMap，计数无误
- 全部 `estimatedTokens` 值（33 条）与代码 `SkillMeta.estimatedTokens` 逐一比对，零偏差
- §2 跨组表 10 行 × 挂载次数 = 26，与 l2SkillMap 实际挂载完全一致
- Phase 1 文件定位（p2/p5/p6）与 grep 命中一致
- Phase 1「零风险」前置 grep 已执行：V1 id/常量无外部直连

### 仍待确认

- ~~`flutter test` 后台运行，完成后补报~~ → **已闭环**：全量 2019 用例 All tests passed（exit 0，2m52s）。

---

## 9. Phase 1 / Phase 2 执行结论（2026-08-28）

### 9.1 Phase 1（V1 退役）已完成

- 删除 `skillRegistry` 中 3 条 V1 注册 + 3 个常量（`_trainingLoop`/`_trainingEvaluation`/`_textSurgery`）。
- `l2SkillMap` 的 V1 id 字符串与 `v2SkillReplacements` **保留**（`getL2SkillIds` 依赖其映射到 V2）。
- ⚠️ **方案「零风险」口径需修正**：Phase 0 的前置 grep 只扫了 `lib/`，漏掉 `test/`。`test/skill_registry_l2_test.dart` 的 `expected` 集合显式断言 V1 id 已注册，删除后测试会红。已同步更新该测试（`expected` 移除 3 个 V1 id，长度断言 `12+25=37` 自动跟随）。
- 门禁：`flutter analyze lib` No issues（exit 0）、`dart format` 0 changed、circular OK、定向测试 11/11 通过。

### 9.2 Phase 2（跨组去重，方案 A）已完成 — 但「token 降 30%」不成立

**改动**：新增契约类型 `SkillRef(skillId, contextHint)`（`lib/contracts/teaching_capability.dart`）；`l2SkillMap` 值由 `List<String>` → `List<SkillRef>`；`getL2SkillIds` 返回 `List<SkillRef>`（V2 替换时保留 contextHint）；`skill_dispatcher` 注入共享 content 后追加各组语境头。5 个 P0 跨组本体（reader-awareness 4 组 / coaching-actions 4 组 / narrative-design 3 组 / plot-design 3 组 / coaching-rhythm 2 组）已填各组语境适配指令。

**实测 token（字符数，L2 各模式）**：

| 模式 | skill 数 | 语境头数 | before | after | 增量 |
|------|--------:|--------:|-------:|------:|-----:|
| beginner | 6 | 3 | 30901 | 30979 | +0.25% |
| diagnosis | 10 | 5 | 42178 | 42302 | +0.29% |
| training | 13 | 2 | 38742 | 38777 | +0.09% |
| advanced | 7 | 2 | 28550 | 28591 | +0.14% |
| outline | 5 | 4 | 25305 | 25408 | +0.41% |

**结论**：Phase 2 **未带来 token 下降**（各模式 +0.09%~+0.41%）。根因：`resolveL2Mode` 每次只决议**一个** mode，同一份共享 content 在单个 prompt 内本来就只注入一次，「10 本体挂 26 次」是**跨模式的挂载关系**，不是单次注入的重复。**方案 §4 的「L2 注入 token 降 30%+」实际只能由 Phase 3（大块索引化）达成**，Phase 2 的真实产出是结构地基（共享本体显式化 + 各组语境适配钩子），而非 token 收益。

**门禁（四道全绿）**：`dart format lib` exit 0 / `flutter analyze lib` No issues（exit 0）/ `flutter test --exclude-tags live,external` 2019 全通过（exit 0）/ circular OK。
**行为等价**：新增锚点测试「Phase 2：共享本体按组注入 contextHint，且不串组」，验证同本体在不同组挂不同语境指令、且互不串组。
⚠️ 同类漏网修复：`test/services/diagnosis_contract_test.dart` 直接消费 `getL2SkillIds`，返回类型变更后需改用 `ref.skillId`（已修，9/9 通过）。

---

### 9.3 完整性自查（2026-08-28，针对本轮多次中断/重试）

本轮执行中出现过：Python 写文件被沙箱拦截（多次重试）、Write 混入乱码、Edit 路径/标识符笔误、后台任务被取消。故以 git 为权威基准做了逐项复核。

| 检查项 | 方法 | 结果 |
|--------|------|------|
| 改动集合 | `git status` / `git diff --stat` | 9 文件修改 + 3 文档新增，与预期一致；无遗漏、无多余 |
| 临时文件 | 时间戳 + `git check-ignore` | 本轮日志已清空；7 个残留 log 为 08-27 既有产物且已被 gitignore，未触碰 |
| 乱码/笔误 | 关键字 + U+FFFD 扫描 | 无已知乱码标记、无替换字符 |
| 迁移完整性 | HEAD vs 工作区程序化比对 | **41 条挂载条目逐条一致**（none 0 / beginner 6 / diagnosis 10 / training 13 / advanced 7 / outline 5），无丢弃/改名/重排 |
| 常量内容 | 逐文件读取 | p2 仅留 `_timedRewrite`、p5 仅留 `_modelRewrite`、p6 仅留文件头；三者内容语义完整、正确收尾 |
| 行尾 | 字节级 CR 计数 | HEAD 与工作区均为纯 LF（CR 总数 0），git 的 LF→CRLF 警告为 `core.autocrlf` 良性提示 |
| R-019 行数 | HEAD vs 当前 | 全部 ≤300（最大 `skill_dispatcher.dart` 255） |
| R-019 `as` 断言 | diff 新增行扫描 | 无 |
| R-010/R-021 范围 | diff 文件清单 | 未触碰任何范围外文件（含 11 个既有未格式化测试文件） |
| R-020 循环依赖 | `check_circular.py` | OK（286 modules） |
| V1 可恢复性 | `git show HEAD` | 3 个 V1 常量仍完整存在于 HEAD，**删除非破坏性** |

**自查发现并修复 1 个问题**：插入 `SkillRef` 时连带改动了下一行注释的标点空格（`契约层，原定义` → `契约层， 原定义`），违反 R-010 最小化范围，已还原。

**门禁终态**：`dart format lib` exit 0 / `flutter analyze lib` No issues（exit 0）/ 定向测试 22 用例全通过 / `flutter test --exclude-tags live,external` 2019 全通过 / circular OK。

**⚠️ 未提交**：9 个文件改动 + 3 个文档均未提交，HEAD 仍为 `1fb0a7ba`。方案 §11 要求「每 Phase 独立提交」，当前无法按 Phase 粒度回滚，需舰长决定是否补两笔提交（Phase 1 / Phase 2）。

---

*核验基准：`estimatedTokens` 取自 `lib/services/skills_*.dart`（`SkillMeta.estimatedTokens`），覆盖时间为 2026-08-28。Phase 0 自查完成于 2026-08-28；Phase 1/2 执行完成于 2026-08-28；完整性自查完成于 2026-08-28。*
