// ─────────────────────────────────────────────────────────────
// ChunkPrompt — 分块链单块系统提示词（T-20261025-06 件2 职责级分解）
//
// 从 `progressive_diagnosis.dart` **整段搬迁**而来（不是 part / extension 伪拆分）：
// 分块 prompt 的常量、判据行过滤与系统提示词构造在此；`progressive_diagnosis.dart`
// 保留分块算法、合并与主入口，并以 `export` 保持既有消费者零改动。
//
// 搬迁动因：`progressive_diagnosis.dart` 已顶到 R-019 文件级基线（容差 0），
// 件2 的 band 过滤必须同时腾出行数 ⇒ 按职责把「单块 prompt 构造」独立成文件。
// 消息装配（`buildChunkMessages`）在同批拆出的 `chunk_messages.dart`。
//
// **文案逐字不变**：搬迁后默认路径的 `kChunkSystemPrompt` 仍是
// `(6345, '6cc995ee715d6ed')`（T-20261025-10 后为 `(6591, '12f336da4c230198')`）；
// 任何字符误改都会让 prompt_const 锚点变红。
// B4（T-20261109-02）：例外指引改由 chunk_exception_guide_data.dart 派生，
// 本文件不再持有手写逐字副本；kChunkSystemPrompt 仍逐字不变。
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';
import 'chunk_exception_guide_data.dart';
import 'position_semantics.dart';
import 'syndrome_redirect.dart';
import 'syndrome_registry.dart';

// ── 单块系统提示词（对齐 RN CHUNK_SYSTEM_PROMPT）──
//
// ADR-C69：症候清单原为硬编码 P001-P017（19 条），而注册表已有 39 条
// （P001-P029），导致分块路径漏掉后段 20 个症候——且 anchor 测试覆盖不到本
// 文件（不在 skill_registry 内），缺陷潜伏至今。现改由注册表派生，扩容自动
// 跟随；一致性由 progressive_chunk_syndrome_coverage_test.dart 兜底。

/// ★ T-20261021-03 读数批（ADR-C155）：分块下系统性退化为 uncertain 的判据集。
///
/// 读数依据（`.ai/reports/2026-10-23-分块链读数.md` §三）：干净名家语料
/// 18 块 × 39 判据 = 701 条判定中，这 6 条 uncertain 率 33%–100%
/// （P022 18/18 全退化 · P020 16/18 · P019 10/18 · P012 8/18 ·
/// P011 7/18 · P033 6/18），其余 33 条 18/18 判定稳定（全 miss）。
/// 形态一致：全部是**跨章/跨片依赖判据**（全文节奏比例 / 跨章长线 /
/// 章末收束 / 章首开篇 / 冲突场次前史）——窗口边界纪律下无法在片内自证。
///
/// 处置（ADR-C155 裁定 = 乙形态 + 丙为先）：
/// - 从分块 prompt 的「判定要点清单」**排除**这 6 条（不注入判定要点）；
/// - 但在「跨章依赖判据」节**显式留痕**（点名 + uncertain 指引）——
///   排除而非静默不选（B4），且是 ADR-C153 窗口边界规则的具体化
///   （规则早已存在，本清单把实测退化者点名，零结构改动）。
///
/// ⚠️ 注册表新增症候时：若其成立依赖片段外信息（跨章比例 / 前史 /
/// 后文解释 / 角色长期状态），须同步加入本常量——否则会自动进入要点
/// 清单（默认假设「片内可判定」），重蹈「注入只会制造噪声」。
const Set<String> kChunkDegradedCriteriaIds = {
  'P011',
  'P012',
  'P019',
  'P020',
  'P022',
  'P033',
};

/// 例外情况指引：**由单一真源表派生**（B4 · `T-20261109-02`）。
///
/// 逐字文本已搬到 `chunk_exception_guide_data.dart` 的
/// `kChunkExceptionGuideLines`；装配模板仍以本名插值，注入文本 Δ = 0。
final String _kChunkExceptionGuide = buildChunkExceptionGuide();

/// 单块输出格式（纯静态，与症候清单分离）。
const String _kChunkOutputFormat = '''请输出JSON格式的笔记，不要包含markdown代码块标记，只输出纯JSON对象：
{
  "notes": [
    {
      "syndromeId": "P001",
      "description": "简要描述观察到的问题，在原文中的位置",
      "evidence": ["具体例句1", "具体例句2"],
      "severity": "L1",
      "uncertain": false,
      "excluded": [{"syndrome_id": "P0XX", "reason": "本片查过但判定不成立的一句话理由",
                        "redirect": {"syndrome_id": "P0XX", "action_id": "AXXX", "text": "撤销后改道句（逐字取自该症候改道行）"}}],
      "exception_quotes": ["例外依据句1", "例外依据句2"]
    }
  ]
}

uncertain 字段说明：按上面「片段窗口边界」一节，该条判据的成立与否依赖片段外信息时置 true，并在 description 里简述缺哪类信息（缺前文铺垫 / 缺后文解释 / 缺片段外人物关系 / 缺全文节奏比例 / 缺角色长期状态）。缺省 false。

excluded 字段说明：本片诊断时考虑过、但在本片证据下判定不成立的相近症候（同类型、共用判定要点的近邻），逐条列你**查过却不报**的，每条一句话理由（≤40字）；没有则输出空数组 []。它记录的是「判了否」，与 uncertain「判不了」是两回事——缺片段外信息而判不了的仍标 uncertain，不得写进 excluded。

exception_quotes 字段说明：仅当该条命中判据原文的「例外情况」条款、且该条例外要求指出原文依据时填写——逐字摘引本片段中支撑该例外成立的句子，一句一条；例外要求两句就摘两句（如「切换前一条、切换后一条」），并逐句对应各自的归属。必须是本片段原文的逐字子串，不得改写或拼接；不得取自引号内的人物台词（该条例外另有说明的除外）。未援引例外时省略此字段或输出空数组 []，二者同义。

redirect 字段说明：仅当被排除症候的改道行给出了可转向出口时填写——syndrome_id 与 action_id **择一**
（转另一症候的训练填 syndrome_id；转同域动作填 action_id），text 逐字取自该症候改道行的对应分支句，
不得改写、不得自拟、不得超出该行登记的指向集合。改道行未给出出口、或撤销理由不含任何已登记分支时，
省略 redirect（缺省 = 无改道，与现行为同义）。redirect 是给学习者的指路句，不是任务派发——是否照做由学员决定。''';

/// ★ 窗口边界声明（2026-10-21，ADR-C153）：分片阶段的**前提**，不是例外清单。
///
/// 为什么不写成例外清单（逐条点名 P0xx「以下不判……」）：那 6 条高风险豁免
/// （P019/P020/P022/P035/P036/P037）的成立条件**都不需要指认任何位置**——
/// 类型自证、意图自证、跨片依赖。任何文本都能套用，列进清单等于给每个分片
/// 发一张免责模板，最坏情况是剧情组真阳性掉一大截，掉的还是「章末无钩子、
/// 长线无牵引」那批最该报的。
///
/// 为什么这么写能覆盖同 6 条 + P012/P037 跨章清单：
/// 「跨片依赖类不可判」是**一条规则**，6 条例外是它的 6 个具体表现。按规则写 =
/// 一次消解；按例外写 = 6 次重复且各有遗漏。规则还顺带覆盖将来新增的同类判据。
///
/// 与 merge 阶段的分工：分片阶段只做**块内可自证**的判定；跨片归并、交叉引用、
/// 因果一律留给 merge（那里能看到全部分片 + 原文覆盖区间）。merge 侧对应机制
/// 是既有的 `pending_context`（W-15-B，已有完整消费链），本块不重复发明，
/// 只补 merge 侧没有的**前半段**：分片阶段不能因为看不到前文就把
/// 「这里像是有问题」写成肯定结论。
const String _kChunkWindowBoundary = '''## 片段窗口边界（判读前提，先读这一节）
你读到的是全章的一个片段，**看不到片段之外的内容**。因此：
- 只依据本片段内可指认的证据判定。看不到前文铺垫、后文解释、片段外人物关系时，
  **既不得据此否定，也不得据此肯定**。
- 若某条判据的成立与否依赖片段外信息（前文伏笔、后文解释、跨片段的人物关系、
  全文节奏比例、角色的长期状态），本片段阶段**无法判定**：不要勉强给结论，
  在该条 note 上标 `"uncertain": true` 并简述缺哪类信息，交由合并阶段裁决。
- 「本片段看不出问题」不等于「本章没问题」，也不等于「本章有问题」。
- 只有一条分片时（片段 1/1），本章即全文，跨片段前提不成立，按常规判定。
''';

/// 「块内可自证」的对照说明 —— 不新增判据，只举例说明上面的规则怎么用。
const String _kChunkSelfContainedProbe =
    '''- 可在片段内指认位置的（局部措辞、局部节奏、局部视角跳变、局部设定堆积）：照常判。
- 可由片段自身自证的（类型通用件的辨识性、类型固有节奏、体裁约定）：照常判。''';

/// 「跨章依赖判据」节：点名 [kChunkDegradedCriteriaIds] + uncertain 指引。
///
/// ADR-C155（T-20261021-03 读数批）：这 6 条在分块形态下 uncertain 率
/// 33%–100%（P022 18/18 全退化），成立与否依赖片段外信息 ⇒ 片内原理上
/// 判不了。**不是豁免**（ADR-C153 已否决例外清单路线），是把窗口边界
/// 规则应用到实测退化者：遇到疑似形态直接标 uncertain 交合并阶段，
/// 勿在片内推测。用户禁用某条时同步剔除（R-009 用户主权）。
String _chunkDegradedCriteriaBlock([
  Set<String> disabled = const {},
  String? band,
]) {
  final allowed = allowedPositionsForBand(band);
  final rows =
      kSyndromeRegistry
          .where((s) => kChunkDegradedCriteriaIds.contains(s.id))
          .where((s) => !disabled.contains(s.id))
          .where((s) => allowed.contains(s.position))
          .map((s) => '- ${s.id} ${s.name}')
          .toList()
        ..sort();
  if (rows.isEmpty) return '';
  return '''跨章依赖判据（片段内不可判定，直接标 uncertain）：
以下症候的成立与否依赖片段之外的信息（全文节奏比例、跨章长线、章末收束、章首开篇、冲突场次前史），在本片段阶段无法自证：
${rows.join('\n')}
遇到以上形态的可疑迹象时，不要勉强给结论：在该条 note 上标 "uncertain": true 并简述缺哪类信息，交由合并阶段裁决。''';
}

/// 分块 prompt 的「判定要点」行：`- <ID> <病名>（<关键词>）：<一句话判定要点>`。
///
/// ADR-C155 裁定 = **乙形态**（原则 + 判据条目，不注入负例 few-shot）：
/// 读数批的判读依据是 39 条判据**原文**（61514 字符）；原文 verbatim
/// （丙形态）按 33 条折算 ≈52000 字符/片，token 成本随片数爆炸 ⇒ 否。
/// 乙形态从注册表现成字段（keyword + oneLine）派生，零新内容维护面。
/// 排除 [kChunkDegradedCriteriaIds]（那些走「跨章依赖判据」节）；
/// [kNonDiagnosableSyndromeIds] **不进**那一节（语义不同：退化者 = 窗口外可 uncertain，前提层 = **不报**）。
List<String> _activeSyndromeCriteriaLines([
  Set<String> disabled = const {},
  String? band,
]) {
  final allowed = allowedPositionsForBand(band);
  final rows =
      kSyndromeRegistry
          .where((s) => !disabled.contains(s.id))
          .where((s) => !kChunkDegradedCriteriaIds.contains(s.id))
          .where((s) => !kNonDiagnosableSyndromeIds.contains(s.id))
          .where((s) => allowed.contains(s.position))
          .map((s) => '- ${s.id} ${s.name}（${s.keyword}）：${s.oneLine}')
          .toList()
        ..sort();
  return rows;
}

/// 撤销改道例外行（**模型面**）：仅 S/A 行进模型面；T 行只作客户端兜底渲染。
///
/// 整段注入，模型按撤销理由**择一**发出对应 id 与逐字句（温知新终稿表 §四注记 1：
/// 「单值字段 vs 条件多支」⇒ 例外行整段注入 + 遍历断言；「学习者每次只见一支」）。
/// 过滤口径与判定要点清单同源：用户禁用（disabled）+ 位次（band）。
/// 返回 ''（无行可注入）或整段（含首尾换行；空串时拼装结果与改动前逐字相同）。
String _redirectExceptionBlock(Set<String> disabled, String? band) {
  final allowed = allowedPositionsForBand(band);
  final positions = {for (final s in kSyndromeRegistry) s.id: s.position};
  final lines = <String>[];
  for (final e in kSyndromeRedirects.entries) {
    if (disabled.contains(e.key)) continue;
    final row = e.value;
    if (!row.inModelFace) continue;
    final pos = positions[e.key];
    if (pos != null && !allowed.contains(pos)) continue;
    final branches = redirectBranchesOf(row);
    if (branches.isEmpty) continue;
    final name = syndromeNameOf(e.key) ?? e.key;
    lines.add(
      '- 撤销 ${e.key}（$name）时：'
      '${branches.map((b) => '${b.id} "${b.clause}"').join('｜')}',
    );
  }
  if (lines.isEmpty) return '';
  return '''

## 撤销改道例外行（只在 excluded 里用）
- 上面某条症候若被撤销（写进 excluded），且下面这一行给出了可转向出口：按撤销理由**择一**发出——一次只发一支，不得合并多支、不得改写文字、不得超出该行登记的指向集合。
${lines.join('\n')}
''';
}

/// 构造单块系统提示词：症候清单由注册表派生（ADR-C69）。
///
/// 每行 4 个，沿用 RN 逐字移植时的紧凑排布，避免 39 条摊成 39 行。
/// [disabled] 为用户永久关闭的症候 ID 集合（空 = 全启用）。
/// 分块链路教学方式指令（与 teaching-mode skill 组语义一致，但分块旁路不走
/// skill_dispatcher，故在此内联注入）。socratic=引导发现；direct=直给结论。
String kTeachingModeChunkInstruction(TeachingMode mode) => switch (mode) {
  TeachingMode.socratic =>
    '\n\n## 教学风格（疑问式）\n- 指出问题时优先用提问引导学员自己发现，不要一次性倾倒全部结论；'
        '长文更应聚焦最核心的 1-2 个问题让学员先动手。',
  TeachingMode.direct => '\n\n## 教学风格（直接说）\n- 直接给出诊断结论与可操作改法，不绕弯、不铺垫。',
  _ => '',
};

String buildChunkSystemPrompt([
  Set<String> disabled = const {},
  TeachingMode teachingMode = TeachingMode.socratic,
  String? positionBand,
]) {
  final criteriaLines = _activeSyndromeCriteriaLines(disabled, positionBand);
  final degradedBlock = _chunkDegradedCriteriaBlock(disabled, positionBand);
  final redirectBlock = _redirectExceptionBlock(disabled, positionBand);
  return '''你是一个专业的写作诊断助手。请阅读以下文本片段，识别其中存在的写作问题。

症候判定要点（逐条核对，不要强行匹配）：
${criteriaLines.join('\n')}

${degradedBlock == '' ? '' : '$degradedBlock\n\n'}$_kChunkWindowBoundary
$_kChunkSelfContainedProbe

$_kChunkExceptionGuide

$_kChunkOutputFormat${kTeachingModeChunkInstruction(teachingMode)}$redirectBlock''';
}

/// 单块系统提示词（全启用默认值）：症候清单由注册表派生，调用处无需感知（ADR-C69）。
/// 运行时按用户启用集构造请用 [buildChunkSystemPrompt]。
final String kChunkSystemPrompt = buildChunkSystemPrompt();
