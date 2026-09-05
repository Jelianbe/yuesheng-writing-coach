# ADR-C73 · 消融 A 族 + 内容重叠方案 A（合并批次）：重复规定收编正典

- **状态**：Accepted（2026-09-05，舰长「按你说的来，执行下去」授权）
- **类型**：Skill 注入内容变更（3 个 skill：teaching-strategy / coaching-rhythm / feedback-cognition）
- **来源**：`docs/plans/prompt减法批次-消融实验方案-2026-09-05.md`（A 族）+
  `docs/audits/内容重叠分析-feedback-cognition×coaching-rhythm-2026-09-04.md`（方案 A）。
  两者重叠度高（A3=A 的 O-3、A4=O-1），按提案 §七.2 合并为同一批 ADR。

## 1. 裁决总表

| # | 项 | 裁决 |
|:--|:--|:--|
| A1 | teaching-strategy §3.3「用户类型表」× §五「学员分层表」 | **合并**：§3.3 扩「诊断重点」列吸收 §五，§五整节删除，识别信号随迁 |
| A3 | 「核心要求」四条在 phase-mapper / coaching-rhythm §5.4 / feedback-cognition §7.4 三处重复 | **正典留在 phase-mapper P2 子阶段（L1 常驻）**；§7.4 整段改指针；§5.4 只保留 beginner 特有两条 + 指针 |
| A4/O-1 | 「训练完成后两件事」三副本（phase-mapper 反馈要点 / §5.3 / §7.3） | **正典定为 phase-mapper「反馈要点」（L1 常驻）**；§5.3 只留语气参考引文；§7.3 保留「归谁管」+训练后特有兜底，两件事改指针 |
| O-2 | coaching-rhythm §六分工表与 §5.3 自相矛盾 | 分工表行改为「训练完成后正典在 phase-mapper；feedback-cognition 补 diagnosis 组兜底」 |
| O-4 | §5.5「同 feedback-cognition §7.5……此处不重复」假句 + beginner 模式悬空引用 | **改为自含红线句**（不虚构群体数据/不比较绝对成绩），删除悬空引用；5.5↔7.5 按 C68 方案 A 登记 **V-05 受控副本 #10** |
| A2 | §3.4「信心水平自适应」缩为指向 teaching-modes | **主动跳过**：teaching-modes 仅 P1+ 加载，指针在 P0 语境悬空——正是 C57/C72 教训的形态。留待 teaching-modes 加载范围调整后再议 |
| 附带 | phase-mapper「反馈要点」的语气参考指针 | 修正悬空：注明两个 L2 skill 的加载组，未加载语境「按本节要点自行组织语言」 |

## 2. 不做的事

- 不动 V-01~V-10 / 铁三角 / E.3 / 协议块字段说明 / 安全词 / N 系完成标志（消融红线）；
- 不动 §7.5 本体（受控副本对保持逐字对称，仅登记）；
- 不做 B 族（B1 悬空引导、B2 话术密度）——视本批结果另批。

## 3. 预期漂移形态（验收判据）

- teaching-strategy：全 13 case 等量漂移（L1 常驻）；
- coaching-rhythm：仅 beginner×6 + diagnosis×2 case 漂移；
- feedback-cognition：仅 diagnosis×2 case 漂移；
- 每个 case 的 Δ = 三个 skill Δ 的对应求和，**多一字少一字都算越界**；
- l3Inject 零变化。

## 4. 验收

1. 既有护栏全绿（C57 coaching_rhythm_phase_slice / N29 diagnosis_contract / C72 guard /
   prompt_style 79 例 / enum_consistency）+ 新增本批护栏（指针存在 + 重复句式消失计数断言）；
2. 锚点按 §3 形态精确归因；
3. 消融等价采样：R0-C21 / CHAIN-T2 / S-9 / R0-C6 / R0-C1 五输入 ×2，与既有基线样品
   判分同向（块出现性/枚举/泄漏/模板），人工抽检无语气退化；
4. 六道门禁全绿；元数据头 4 个（本批起 skill 级改动按内容增减规范 V1.0 填头，
   `check_content_metadata.py` 首次实战）。
