# 内容重叠分析 · feedback-cognition × coaching-rhythm §五（含 phase-mapper 第三副本）

> 2026-09-04（并行会话，只读分析；不动任何 skill 内容——改 Skill = 高风险，需内容线走 ADR/人工确认）
> 台账来源：docs/README「已知债务与缺口」——「feedback-cognition 与 coaching-rhythm §五 内容重叠，未决，会导致重复注入」。
> 本分析把这一行展开成可裁决的事实清单与修法建议。

---

## 一、注入事实（重叠是"活"的，且集中在此前没人指出的模式）

| skill | L2 组 | loadWhen |
|:--|:--|:--|
| coaching-rhythm | **beginner 组 + diagnosis 组都加载**（`skill_layers.dart:44` 与 `:54`） | P0-P4，P2+ 认知桥接 |
| feedback-cognition | 仅 diagnosis 组（`skill_layers.dart:63`） | P2/P3/P4 |

推论：**diagnosis 模式（P2 诊断子阶段，最常用的教学模式）下，两个 skill 同轮注入**——
台账记的「重复注入」在此发生；beginner 模式下只有 coaching-rhythm，无重叠。

## 二、重叠点清单（三处重复 + 一处内部自相矛盾）

### O-1 ·「训练完成后讲两件事」——共三份副本，diagnosis 模式下三份同 prompt

同一规则（「和之前那一稿比，这次具体哪里不一样了——要指得出来；接下来还可以看什么」）：

| # | 位置 | 层级 | 措辞 |
|:--|:--|:--|:--|
| 1 | `skills_l1_core_p1.dart:134-143`（phase-mapper「反馈要点」） | L1 常驻，P1+ | 「训练完成后：讲清"和之前比，这次哪里不一样了"，以及下一步可以看什么」+ 指明语气参考在 coaching-rhythm §5.3 与 feedback-cognition §7.3 |
| 2 | `skills_beginner_p4.dart:111-121`（coaching-rhythm §5.3「训练完成后的桥接」） | L2 beginner+diagnosis | 同意两件事 + 语气参考引文 |
| 3 | `skills_diagnosis_p2.dart:203-210`（feedback-cognition §7.3） | L2 仅 diagnosis | 同意两件事（声称"训练完成后的反馈归本 Skill"） |

### O-2 · coaching-rhythm 自相矛盾：§六分工表 vs §5.3 内容

§六分工边界表（`skills_beginner_p4.dart` 末尾）写「诊断后→训练前的桥接 = 本站 §五；
训练完成后反馈 = feedback-cognition」——即训练完成后**不归本站**；
但 §5.3 里仍保留着完整的「训练完成后的桥接」小节。
模型同轮收到两处矛盾归属（D 类缺陷家族：不裁决 → 随采样选边）。

### O-3 · §5.4 ↔ §7.4（核心要求四条）近乎逐字重复

「不暴露编号 / 不评分不贴标签 / 原因具体基于文本 / 鼓励自评」两条基本同文。

### O-4 · §5.5 ↔ §7.5（正常化与陪伴感）近重复，且 §5.5 的交叉引用是悬空的

- §5.5 开头写「红线：同 feedback-cognition §7.5……此处不重复」——**这句本身两处失实**：
  ① 它实际上重复了 §7.5 的大部分内容（数字只来自系统注入 / 指得出变化 / 不虚构群体数据）；
  ② 在 beginner 模式下 feedback-cognition **不在注入集里**，这个交叉引用指向一个
  学员当轮看不到的章节——正是 C57 悬空引用同类。
- 另有一处单侧差异：§7.5 有「不做数值打分」，§5.5 没有（副本漂移实证）。

## 三、修法建议（供内容线裁决；推荐方案 A，并给出否决项理由）

**约束条件先行**（决定修法形态的三条硬事实）：
1. beginner 模式下 feedback-cognition 不加载 → coaching-rhythm 侧不能把规则删干净；
2. diagnosis 模式下两者同轮 → 重复规定在这里是真实成本（估算约 500-700 token 双份）；
3. phase-mapper 是 core 组（L1 常驻，P1+ 加载），指向它不会悬空；指向任何 L2 组 skill 都可能悬空。

**方案 A（推荐）：L1 收编正典 + L2 降为语境件 + 受控副本登记**

1. 「训练完成后两件事」正典落在 phase-mapper「反馈要点」（已在注入路径上，V4.9 已验证过其注入位置）；
2. coaching-rhythm §5.3「训练完成后的桥接」：删两句规定，保留语气参考引文，
   加一句「规则见 phase-mapper 反馈要点（常驻）」；
3. feedback-cognition §7.3：保留「归谁管」分工表的价值，两件事改为指向 phase-mapper 反馈要点；
4. §六分工表同步改（「训练完成后反馈 = feedback-cognition」→「= phase-mapper 正典 + 各组语气参考」）；
5. §5.4/§7.4、§5.5/§7.5 两组跨组必需的平行副本 → **按 C68 方案 A 登记 V-05 受控副本**
   （不同 L2 组、各自语境必需，删并会悬空），配逐对语义一致性护栏（枚举类断言，V4.8 口径）；
6. 顺带修正 §5.5「此处不重复」的失实句与悬空引用。

预期收益：diagnosis 模式消除 ~500-700 token 重复；D 类矛盾归零；O-4 假句清掉。

**否决项**：
- 「合并 feedback-cognition 进 coaching-rhythm」——跨 L2 组边界，diagnosis 组还得反向引用，改动面更大；
- 「删 coaching-rhythm §5.3 训练完成后小节」——beginner 模式下规则消失（约束 1）；
- 「§5.5 改指向 §7.5」——beginner 模式悬空（C57 同类）。

**风险提示**：全部改动都会动注入字节 → 需按惯例走锚点重生成 + 行为盲测
（回归输入可复用 `after_b8_2026-09-04/samples/input_R0-C6.txt`——桥接句式正是本域）。
