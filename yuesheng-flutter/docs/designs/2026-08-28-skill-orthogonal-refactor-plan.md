# Skill 正交重构 — 任务执行方案

- 日期：2026-08-28
- 状态：**待执行**（Phase 0 起）
- 关联 ADR：`docs/ADR-skill-orthogonal-model.md`
- 执行者：任意具备 Dart/Flutter 能力的模型（本方案自足，无需依赖原会话上下文）
- 工作目录：`D:\ai-teacher\yuesheng-flutter`

---

## 0. 执行者必读（前 3 件事）

1. **先读 ADR**：`docs/ADR-skill-orthogonal-model.md`，理解「知识 × 动作 × 态度」三正交维度的目标模型与决策理由。
2. **先跑基线**：改动任何代码前，先跑一遍完整门禁（命令见 §8），确认基线全绿。
3. **环境坑**：本机所有 flutter 命令必须加 `--no-pub`（否则依赖解析阶段静默卡死）；不要并发跑 flutter test 和 flutter build（争抢 Flutter 工具锁）。详见 §9。

**总目标**：把 40 份 skill 从「知识 + 姿势」焊死的混合块，重构为三个正交维度——知识归数据、动作归行为、态度归参数。注册表收敛到 ~25 个本体，舰长改话术不再依赖代码操作。

---

## 1. 现状盘点（2026-08-28 实测，改动前请复核）

### 1.1 注册表总量：40 份（`lib/services/skill_registry.dart`）

| 层 | 数量 | 明细 |
|:--|:--|:--|
| L1 常驻 | 9 | core-iron-triangle(400) / core-product-identity(630) / writing-anchors(410) / teaching-strategy(**4400**) / phase-mapper(100) / scenario-rules(560) / validation-rules(780) / teaching-modes(1600) / reply-voice(300) |
| 态度 | 3 | attitude-doubao / attitude-yuesheng / attitude-sensei（**纯姿势，已分离** ✅） |
| L2 beginner | 6 | beginner-path / gap-detector / coaching-rhythm(**3500**) / narrative-design(**4200**) / plot-design(**3400**) / writer-psychology(3200) |
| L2 diagnosis | 5 | reader-awareness(2200) / genre-guide(**3500**) / writing-style(2800) / diagnosis-confirmation(700) / feedback-cognition(900) |
| L2 training | 13 | training-loop(V1 残留) / training-loop-v2 / training-templates-index / training-evaluation(V1 残留) / training-evaluation-v2 / text-surgery(V1 残留) / text-surgery-v2 / coaching-actions-v2 / demonstration(470) / comparison(540) / timed-rewrite(1600) / model-rewrite(1800) / revision-methodology(1970) |
| L2 advanced | 1 | advanced-phases(**4200**) |
| L2 outline | 1 | outline-diagnosis(**4200**) |
| 虚拟索引 | 2 | syndrome-diagnosis-index(1800) / technique-library-index(900) |

括号内为 `estimatedTokens`。40 份实际 ~28 个本体（V1/V2 双轨 + 跨组共享）。

### 1.2 V1/V2 双轨（`lib/services/skill_layers.dart` L108-128）

```dart
const bool useTrainingV2Pilot = true;  // L108

const Map<String, String> v2SkillReplacements = {  // L111-117
  'training-loop': 'training-loop-v2',
  'training-templates': 'training-templates-index',
  'training-evaluation': 'training-evaluation-v2',
  'text-surgery': 'text-surgery-v2',
  'coaching-actions': 'coaching-actions-v2',
};
```

- **V1 注册残留 3 个**（pilot=true 下永不加载，纯遗产）：
  - `training-loop` → `skills_training_p2.dart:7` `_trainingLoop`
  - `training-evaluation` → `skills_training_p5.dart:7` `_trainingEvaluation`
  - `text-surgery` → `skills_advanced_outline_p6.dart:7` `_textSurgery`
- `coaching-actions` V1 与 `training-templates` V1 **已不在注册表**（l2SkillMap 仍引用 V1 id，靠 pilot 映射到 V2；切勿反向补回）。

### 1.3 跨组重复挂载（10 个本体挂 26 次）

`l2SkillMap`（skill_layers.dart L41-94）中同一 id 出现在多组：

| 本体 | 挂载组 | 次数 |
|:--|:--|:--|
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

### 1.4 大块内容（3500+ tokens，未索引化）

| Skill | tokens | 挂载 | 备注 |
|:--|:--|:--|:--|
| teaching-strategy | 4400 | L1 常驻 | 是否索引化需单独决策（L1 常驻不随场景切换） |
| narrative-design | 4200 | 3 组 | |
| advanced-phases | 4200 | 1 组 | |
| outline-diagnosis | 4200 | 1 组 | |
| coaching-rhythm | 3500 | 2 组 | |
| genre-guide | 3500 | 2 组 | |
| plot-design | 3400 | 3 组 | |

### 1.5 已验证的索引化模式（复用样板）

- `syndrome-diagnosis-index`：L2 索引 `kSyndromeIndexContent`（~1800） + L3 手册 `kSyndromeManualContent`，定义于 `lib/services/syndrome_kb_content.dart`
- `technique-library-index`：L2 索引 `kTechniqueIndexContent`（~900） + L3 完整技法库 `kTechniqueLibraryContent`，定义于 `lib/services/technique_kb_content.dart`
- L3 检索类型：`L3RetrievalResult`（skill_layers.dart L195-203），由 dispatcher 按 `syndromeIds` 驱动

---

## 2. Phase 0 — 数据摸底与拆分清单（无代码改动）

**产出物**：一份 `docs/designs/skill-split-inventory.md`（拆分清单），经舰长确认后才可进入 Phase 1。

**执行步骤**：

1. 全量导出 40 份 skill 的 `id / group / estimatedTokens / 挂载组`（本方案 §1 已有，复核即可）。
2. 对每份 L2 内容 skill 做「知识 / 动作」逐句粗分类，用判断标准：
   > 「删掉这句话，AI 还知道教什么吗？」知道 → 动作/话术；不知道 → 知识。
3. 每本体产出三列：`知识条目（进数据）` / `动作指令（留 skill）` / `话术示例（可参数化）`。
4. 标注每本体的**拆分优先级**：P0 = 跨组重复 + 大块（narrative-design / plot-design / reader-awareness / coaching-actions / coaching-rhythm 优先）；P1 = 单组大块；P2 = 小块。

**验收**：拆分清单完整、舰长签字。**风险**：无。**回滚**：不涉及。

---

## 3. Phase 1 — V1 退役（零风险，先拿确定性收益）

**目标**：删除 3 个 V1 注册残留，40 → 37（实际生效量不变，pilot 下本来就不加载）。

**改动文件**：

1. `lib/services/skill_registry.dart` — 删除 3 行注册：
   - L114 `'training-loop': _trainingLoop,`
   - L117 `'training-evaluation': _trainingEvaluation,`
   - L119 `'text-surgery': _textSurgery,`
2. `lib/services/skills_training_p2.dart` — 删除 `_trainingLoop` 常量（L7 起，含 Skill 对象字面量）
3. `lib/services/skills_training_p5.dart` — 删除 `_trainingEvaluation` 常量
4. `lib/services/skills_advanced_outline_p6.dart` — 删除 `_textSurgery` 常量

**⚠️ 注意**：
- `l2SkillMap`（skill_layers.dart）中的 V1 id 字符串**不要动**——`getL2SkillIds` 靠它们经 `v2SkillReplacements` 映射到 V2。
- 删除前 grep 确认无其他代码直接引用这三个 id / 常量（预期只有 registry 与 l2SkillMap）。

**验收**：
- `flutter analyze lib` 零 issues（常量删除后无未用警告）
- 完整测试全绿（§8 Gate 2）
- `getL2SkillIds(L2Mode.training)` 结果与删除前逐字节一致（可临时写断言或人工核对映射）

**风险**：零（pilot 已硬编码 true）。**回滚**：git revert 即可，改动孤立。

---

## 4. Phase 2 — 跨组去重（中风险）

**目标**：10 个共享本体 content 只存一份，各组挂载改为「语境指针 + 适配指令」，L2 注入 token 降 30%+。

**实现方式候选**：

- **方案 A（推荐）**：共享 Skill 实体保持单实例，`l2SkillMap` 的值从 `String`（skill id）改为带 `contextHint` 的引用类型：
  ```dart
  // 伪代码：L2 组内条目
  SkillRef('reader-awareness', contextHint: '训练语境：聚焦反馈恐惧的读者视角')
  ```
  dispatcher 组装时：共享 content 注入一次 + 各组拼装 50-150 tokens 的语境头。
- **方案 B**：为每组生成独立的瘦身 skill（每组 200-400 tokens 的「语境化精简版」），共享本体退役。
  - 缺点：产生新本体，维护面反而变大。不推荐。

**改动文件**：`lib/services/skill_layers.dart`（l2SkillMap 结构 + getL2SkillIds 返回类型）、`lib/services/skill_dispatcher.dart`（组装逻辑）、契约层 `lib/contracts/teaching_capability.dart`（如 SkillRef 类型需暴露）。

**前置**：Phase 0 拆分清单中标注了各组语境差异的条目。

**验收**：
- **语义等价测试**：对 5 个 L2 模式，加载结果的关键行为约束与现状等价（需要先为现状写一组「行为锚点」测试，再从锚点断言新结构）。
- 注入 token 量化对比（before/after 各模式合计），下降 ≥30%。
- 四道门禁全绿。

**风险**：中。语境头措辞可能改变行为 → 测试兜底。**回滚**：保留旧 l2SkillMap 结构在 git 历史，revert 即可。

---

## 5. Phase 3 — 大块索引化（高风险，ADR 生效前提）

**目标**：4000+ tokens 大块拆「L2 索引 + L3 知识库条目」，复用 syndrome/technique 已验证模式。

**对象**（按 Phase 0 优先级）：narrative-design / coaching-rhythm / plot-design / advanced-phases / outline-diagnosis / genre-guide。teaching-strategy 是 L1 常驻、不随场景切换，单独决策（倾向保留整块）。

**改动文件**：
- 新建知识库分片：`lib/services/` 下对应 `*_kb_content.dart`（如 `narrative_kb_content.dart`，仿 `syndrome_kb_content.dart` 结构）
- `lib/services/skill_registry.dart`：大块注册改为索引版（仿 L133-148 的 index 注册方式）
- `lib/services/skill_layers.dart`：L3 检索扩展（L3RetrievalResult 增加字段或按主题复用）
- `lib/services/skill_dispatcher.dart`：检索触发逻辑

**验收**：
- 大块 L2 注入降至索引级（<800 tokens）
- L3 检索命中率测试（新增：针对该主题的检索用例全绿）
- 语义等价：行为锚点测试不回归
- 四道门禁全绿

**风险**：高。知识被拆到 L3 后，若检索不触发则 AI 失去知识 → 检索触发条件的完整度是验收重点。

**回滚**：revert 后恢复整块注入，知识无丢失（git 历史完整）。

---

## 6. Phase 4 — 知识 / 动作逐本体拆分（核心重构）

**目标**：按 Phase 0 拆分清单，把每个内容本体拆成「知识数据（下沉）+ 行为指令卡（skill 本体瘦身）」。此阶段完成后，**改话术不再需要动代码**——舰长改知识库数据文件即可。

**执行节奏**：
- 每本体一个提交，独立走门禁。禁止批量混改（R-010 最小化范围）。
- 顺序按 Phase 0 优先级：P0 → P1 → P2。
- 每本体拆分前后：语义等价断言（行为锚点测试）必须通过。

**改动文件**：对应 `*_kb_content.dart` 知识条目扩充 + 对应 `skills_*_pN.dart` 瘦身 + `skill_registry.dart` 注册内容更新。

**验收**：全部 P0 本体拆分完成、行为锚点全绿、四道门禁全绿、舰长抽查话术修改流程（改数据文件 → 生效）跑通。

**风险**：高。逐本体语义漂移累积。**缓解**：单本体独立提交 + 独立验收，漂移可定位到具体提交。

---

## 7. Phase 5 — 三正交组装层落地

**目标**：组装逻辑显式化——知识 + 动作 + 态度 三路输入 → 最终 system prompt。

**改动**：
1. **教学动作独立维度**：从内容 skill 抽取的动作指令聚合为动作卡体系（新文件如 `teaching_actions.dart`，或并入现有 coaching-actions 体系）。
2. **态度参数化**：`attitude-*` 演化为参数集（提问上限、示范与否、直接程度、反馈密度），dispatcher 组装时作用于动作卡。
3. **组装层**：收敛到 `skill_dispatcher.dart` 单点，先写契约测试（输入 L2Mode + attitude + 检索上下文 → 输出 prompt 结构断言）。

**验收**：
- 加第四档态度 = 新增一个参数文件，零 skill 注册变更
- 改知识点 = 改数据文件，零代码变更
- 行为锚点全绿 + 四道门禁全绿
- 真机验证一轮完整教学对话（新建 → 诊断 → 训练），确认组装后 prompt 质量不劣化

**风险**：中（组装层是单点故障，用契约测试兜底）。

---

## 8. 门禁命令（每个 Phase 完成后必须全跑）

工作目录：`D:\ai-teacher\yuesheng-flutter`。**所有 flutter 命令加 `--no-pub`**。

```bash
# Gate 0：格式化
dart format --set-exit-if-changed -o none lib

# Gate 1：静态分析（全工程，非单文件）
flutter analyze lib

# Gate 2：完整测试（注意：全量是 2018 个用例，跑完约 2 分钟）
flutter test --no-pub --exclude-tags live,external

# Gate 3：循环依赖
python scripts/check_circular.py

# 完整门禁组合
dart format --set-exit-if-changed -o none lib && flutter analyze lib && flutter test --no-pub --exclude-tags live,external && python scripts/check_circular.py
```

**Git 提交**：按 R-016 规范（`docs/../.trae/rules/R-016-Git提交规范.md`，真源在 `D:\ai-teacher\.trae\rules\R-016-Git提交规范.md`），中文、带 scope、正文说明动机。示例：

```
refactor(skills): 退役 V1 训练 skill 注册（pilot 已切换 V2）

useTrainingV2Pilot=true 下 V1 不再加载，注册表 3 条纯遗产：
- training-loop / training-evaluation / text-surgery
删除注册 + 常量，行为零变更（40→37 注册，生效量不变）。
```

---

## 9. 环境注意事项（本机已验证的坑）

| 坑 | 现象 | 解法 |
|:--|:--|:--|
| flutter 命令挂起 | 默认依赖解析阶段静默卡死，60 秒零输出 | **所有 flutter 命令加 `--no-pub`** |
| 并发争锁 | flutter test 与 flutter build 同时跑 → 互相阻塞 | 顺序执行，绝不并发 |
| VS 版本切换残留 | CMake 报「generator 不匹配 VS18/VS17」 | 缓存实际在 `build/windows/x64/`（不是 `build/windows/`），`rm -rf build/windows/x64` 后重建 |
| exe 分离启动即退 | `cmd start` / `Start-Process` 启动后几十秒正常退出 | 用 bash 前台/管道方式运行，或接受「分离启动会退」的现象（不影响功能验证） |
| 本地 Git 对象损坏史 | 曾有 gc/filter-repo 中断，commit/push 正常但 fsck 未跑 | 不要盲目 reset/reclone；必要时先 `git fsck` 摸底 |

---

## 10. 依赖关系与里程碑

```
Phase 0（清单，需舰长确认）
  └─ Phase 1（V1 退役，零风险）── 里程碑 M1：注册表 37，行为零变更
       └─ Phase 2（跨组去重）── 里程碑 M2：L2 注入 -30%
            └─ Phase 3（大块索引化）── 里程碑 M3：4000+ 大块全部索引化
                 └─ Phase 4（知识/动作拆分）── 里程碑 M4：改话术零代码
                      └─ Phase 5（三正交组装）── 里程碑 M5：四档态度=加参数文件
```

每个里程碑独立可交付、可回滚。M1 建议立即执行（半小时内完成），先锁定第一笔确定性收益。

---

## 11. 交接给执行模型的一句话

> 本方案自足。执行者从 Phase 0 开始：先读 `docs/ADR-skill-orthogonal-model.md`，再跑 §8 基线门禁（注意 `--no-pub`），然后按 §2 产出拆分清单交给舰长确认。每个 Phase 独立提交、独立验收，门禁全绿才算完成。
