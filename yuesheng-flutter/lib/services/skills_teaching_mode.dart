// ─────────────────────────────────────────────────────────────
// skill_registry 数据分片：教学方式 skill（socratic / direct）
//
// 与人格档位（attitude-*/skills_attitude.dart）正交：人格只定「语气/态度」，
// 本组只定「提问引导 vs 直给结论」的教学方式，由 coach_teaching_mode 开关经
// skill_dispatcher 按 ctx.teachingMode 注入（L1 pinned block）。
// 抽离自 skills_attitude 三档的「诊断方式/发现引导级别/提问上限」句式
// （R-027 改动：原句式从人格 skill 移除，避免 doubao(疑问式)+开关(直给)冲突）。
// ─────────────────────────────────────────────────────────────
part of 'skill_registry.dart';

// ### teaching-mode-socratic · 疑问式（苏格拉底引导）
// | 字段 | 值 |
// |:--|:--|
// | 归属组件 | 教学方式 |
// | 加载范围 | L1 常驻，按 SkillLoadContext.teachingMode 注入（socratic） |
// | 依赖数据 | 教练设定页 teaching_mode 开关（coach_teaching_mode KV）；SkillLoadContext.teachingMode |
// | 数据缺失兜底 | 开关未设置时默认 socratic（疑问式）；本组两 skill 正文各自自含完整行为，不互相依赖 |
// | 引用目标 | skills_attitude（与人格档位正交，本组只定提问/直给方式）；skill_dispatcher（按 ctx.teachingMode 注入） |
// | 冲突与优先级 | 与人格档位正交——人格定语气、本组定方式；progressive_diagnosis 分块链路直给式（绕过 skill_dispatcher 时由 _kTeachingModeChunkInstruction 保证一致） |
// | 副本登记 | 无副本（本组为教学方式唯一真源；attitude 三档正文已移除诊断方式句式，引用式指向本组） |
// | 示例标注 | 无示例（行为约束为主） |
// | 校验方式 | skill_prompt_anchor_test（本组 case 指纹） |
const Skill _teachingModeSocratic = Skill(
  meta: SkillMeta(
    id: 'teaching-mode-socratic',
    group: 'teaching-mode',
    promptStyle: PromptStyle.free,
  ),
  content: '''# 教学方式：疑问式（苏格拉底引导）

- **不直接给答案**：优先用提问引导学员自己观察到问题，而非直接告知结论。
- **诊断节奏**：先确认学员已理解现状，再温和追问，最后才在学员卡住时给方向。
- **提问上限**：每轮最多 3 个问题，避免连环发问让学员窒息。
- **发现引导**：高。尽可能让学员自己注意到问题；只在学员明确卡住、或主动要求直说时，才直接给出结论与改法。
- **鼓励**：肯定要落在具体处，不用空泛夸奖。''',
);

// ### teaching-mode-direct · 直接说（直给式）
// | 字段 | 值 |
// |:--|:--|
// | 归属组件 | 教学方式 |
// | 加载范围 | L1 常驻，按 SkillLoadContext.teachingMode 注入（direct） |
// | 依赖数据 | 教练设定页 teaching_mode 开关（coach_teaching_mode KV）；SkillLoadContext.teachingMode |
// | 数据缺失兜底 | 开关未设置时默认 socratic（疑问式），本档作为显式直给选择；本组两 skill 正文各自自含完整行为 |
// | 引用目标 | skills_attitude（与人格档位正交，本组只定提问/直给方式）；skill_dispatcher（按 ctx.teachingMode 注入） |
// | 冲突与优先级 | 与人格档位正交——人格定语气、本组定方式；长文/赶进度场景优先本档以减少上下文负担与前后不一致 |
// | 副本登记 | 无副本（本组为教学方式唯一真源；attitude 三档正文已移除诊断方式句式，引用式指向本组） |
// | 示例标注 | 无示例（行为约束为主） |
// | 校验方式 | skill_prompt_anchor_test（本组 case 指纹） |
const Skill _teachingModeDirect = Skill(
  meta: SkillMeta(
    id: 'teaching-mode-direct',
    group: 'teaching-mode',
    promptStyle: PromptStyle.free,
  ),
  content: '''# 教学方式：直接说（直给式）

- **直接给结论**：首轮即可指出问题并给出改法，不绕弯、不铺垫、不靠提问拖延。
- **结构**：每条反馈覆盖「现象（引用原文）→ 诊断（技术原因）→ 建议（可操作改法）」。
- **密度**：一次聚焦最要紧的 1-2 个问题讲透，其余留给下一轮。
- **鼓励**：用诊断的精准度代替空泛赞美；认可进步时嵌入技术解释。
- **适用场景**：长文 / 赶进度 / 学员已明确要直给时，优先用本模式以减少上下文负担与前后不一致。''',
);
