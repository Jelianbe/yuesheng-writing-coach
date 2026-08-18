// ─────────────────────────────────────────────────────────────
// L3 技法知识库 — 复刻 yuesheng-android/src/assets/skills/technique-library.ts
// 内容 100% 逐字保留（2026-08-08 批次 22 步骤② 搬运）
//   kTechniqueIndexContent → L2 层 technique-library-index 索引
//   kTechniqueLibraryContent → L3 检索源（按技法 ID 提取完整内容）
// b9 批次29：症候→技法映射表行、kTechniquesBySyndrome 改从注册表派生；
//           技法索引表「适用症候」列为人工精选（≠注册表反查），保留手写。
// ─────────────────────────────────────────────────────────────

import 'syndrome_registry.dart';

// ─── P3 数据分片（数据/逻辑分离；知识文本在 part 文件）───
part 'technique_kb_content.dart';


/// 症候 → 推荐技法 ID 列表（复刻 RN TECHNIQUE_BY_SYNDROME；b9 批次29 由注册表派生）
Map<String, List<String>> get kTechniquesBySyndrome => kTechniquesBySyndromeDerived;

/// 从完整技法库中按技法 ID 提取单个技法的完整内容（复刻 RN extractTechniqueSection）
String _extractTechniqueSection(String raw, String id) {
  final pattern = RegExp('### $id ');
  final match = pattern.firstMatch(raw);
  if (match == null) return '';
  final startIdx = match.start;
  final nextSection = raw.indexOf('\n### ', startIdx + 1);
  final endIdx = nextSection != -1
      ? nextSection
      : raw.indexOf('\n## ', startIdx + 1);
  return raw.substring(startIdx, endIdx > 0 ? endIdx : raw.length).trim();
}

/// L3 检索：获取指定技法的完整内容（复刻 RN getTechniqueContent）
String getTechniqueContent(List<String> techniqueIds) {
  final sections = techniqueIds
      .map((id) => _extractTechniqueSection(kTechniqueLibraryContent, id))
      .where((s) => s.isNotEmpty)
      .toList();
  if (sections.isEmpty) return '';
  const header =
      '## 聚焦技法详细内容（系统注入，学员不可见）\n\n以下是你当前训练聚焦的技法的完整定义。请严格参照其中的技法描述、示范对比和练习模板进行教学。\n\n---\n\n';
  return header + sections.join('\n\n---\n\n');
}

/// L3 检索：根据锁定症候 ID 获取对应推荐技法（复刻 RN getTechniquesBySyndrome，
/// 每个症候取首选 + 第一个备选）
String getTechniquesBySyndrome(List<String> syndromeIds) {
  final techniqueSet = <String>{};
  for (final sid in syndromeIds) {
    final techniques = kTechniquesBySyndrome[sid];
    if (techniques != null && techniques.isNotEmpty) {
      techniqueSet.add(techniques[0]);
      if (techniques.length > 1) techniqueSet.add(techniques[1]);
    }
  }
  return getTechniqueContent(techniqueSet.toList());
}

/// 技法精简名真源（31 条，技法名稳定；渲染各映射表时取用。
/// 注意：不依赖 kTechniqueIndexContent 解析，避免顶层 lazy 变量初始化自引用）。
const Map<String, String> kTechniqueShortNames = {
  'T001': '动态描写公式',
  'T002': '感官交织法',
  'T003': '核心信息提取',
  'T004': '角色独白检测',
  'T005': '人味三问法',
  'T006': '特征性对话法',
  'T007': '意外测试法',
  'T008': '因果动作链',
  'T009': '欲望三层法',
  'T010': '信息投喂检测',
  'T011': '角色中介法',
  'T012': '视角锚定法',
  'T013': '潜台词法',
  'T014': '声线分立法',
  'T015': '对话节奏法',
  'T016': '对白动作插入法',
  'T017': '悬念伏笔法',
  'T018': '欲扬先抑法',
  'T019': '线性变奏法',
  'T020': '借景抒情法',
  'T021': '动静烘托法',
  'T022': '场景概述交替法',
  'T023': '句速控制法',
  'T024': '钩子开篇法',
  'T025': '余韵收束法',
  'T026': '伏笔回收法',
  'T027': '高潮阶梯法',
  'T028': '反转设计法',
  'T029': '过渡桥接法',
  'T030': '人设锚定法',
  'T031': '氛围构建法',
};

/// 技法精简名查询（真源：kTechniqueShortNames）。未知 ID 返回 null。
String? techniqueNameOf(String? id) =>
    id == null ? null : kTechniqueShortNames[id];

// ─── 2026-08-18 批次（文笔画像→技法旁路路由）───────────────────
// 设计：docs/2026-08-18-style-technique-bypass-routing-design.md
// 技法分层标签 + 五维偏差→文笔层技法映射，供 style_technique_router 消费。
// 按 R-021 映射表禁令：教学知识放在技法知识库真源文件内，与技法索引同源维护。

/// 技法作用层：prose=文笔层（作用于句子/段落文本），
/// content=内容层（作用于故事结构/情节推进），character=角色层（作用于角色塑造）
enum TechniqueLayer { prose, content, character }

/// 技法 ID → 作用层（31 条全覆盖）
///
/// 注：设计文档原文漏列 T012/T031（prose 计数 12 实为 11）。
/// 按「作用于句子/段落文本本身」的定义补入：T012 视角锚定、T031 氛围构建 → prose。
/// 实际分层：prose 13 / content 13 / character 5。
const Map<String, TechniqueLayer> kTechniqueLayers = {
  // prose（文笔层，13）
  'T001': TechniqueLayer.prose,
  'T002': TechniqueLayer.prose,
  'T003': TechniqueLayer.prose,
  'T012': TechniqueLayer.prose,
  'T013': TechniqueLayer.prose,
  'T014': TechniqueLayer.prose,
  'T015': TechniqueLayer.prose,
  'T016': TechniqueLayer.prose,
  'T020': TechniqueLayer.prose,
  'T021': TechniqueLayer.prose,
  'T023': TechniqueLayer.prose,
  'T025': TechniqueLayer.prose,
  'T031': TechniqueLayer.prose,
  // content（内容层，13）
  'T008': TechniqueLayer.content,
  'T009': TechniqueLayer.content,
  'T010': TechniqueLayer.content,
  'T011': TechniqueLayer.content,
  'T017': TechniqueLayer.content,
  'T018': TechniqueLayer.content,
  'T019': TechniqueLayer.content,
  'T022': TechniqueLayer.content,
  'T024': TechniqueLayer.content,
  'T026': TechniqueLayer.content,
  'T027': TechniqueLayer.content,
  'T028': TechniqueLayer.content,
  'T029': TechniqueLayer.content,
  // character（角色层，5）
  'T004': TechniqueLayer.character,
  'T005': TechniqueLayer.character,
  'T006': TechniqueLayer.character,
  'T007': TechniqueLayer.character,
  'T030': TechniqueLayer.character,
};

/// 五维风格坐标偏差 → 文笔层技法候选映射（首版经验值，待学员数据校准）
///
/// 关键设计：五维坐标是「风格偏好」不是「错误」（spare 冷峻型不是病），
/// 因此只映射「可提升方向」，健康/中性值（rhythm=alternating、sensory=balanced、
/// narrativeDistance=fluid/observational、toneTexture=spare/elegant/colloquial、
/// structure=linear/circular/divergent）不进映射。
class StyleTechniqueMapping {
  /// 维度键，格式 `维度:值`（如 `rhythm:long`）
  final String dimensionKey;

  /// 维度中文标签（如「节奏偏好=长句型」）
  final String dimensionLabel;

  /// 候选技法 ID 列表
  final List<String> techniqueIds;

  /// 一句提升理由
  final String reason;

  /// 跨层调用标注（文笔维度→非 prose 层技法时为 true）
  final bool crossLayer;

  const StyleTechniqueMapping({
    required this.dimensionKey,
    required this.dimensionLabel,
    required this.techniqueIds,
    required this.reason,
    this.crossLayer = false,
  });
}

/// 五维非健康值 → 文笔层技法映射表（8 条）
const List<StyleTechniqueMapping> kStyleDimensionTechniques = [
  StyleTechniqueMapping(
    dimensionKey: 'rhythm:long',
    dimensionLabel: '节奏偏好=长句型',
    techniqueIds: ['T023'],
    reason: '长句从句嵌套，节奏单一，可练句速切换',
  ),
  StyleTechniqueMapping(
    dimensionKey: 'rhythm:short',
    dimensionLabel: '节奏偏好=短句型',
    techniqueIds: ['T021'],
    reason: '短句碎片化，缺乏呼吸感，可用动静交替补节奏',
  ),
  StyleTechniqueMapping(
    dimensionKey: 'rhythm:repetitive',
    dimensionLabel: '节奏偏好=重复型',
    techniqueIds: ['T023'],
    reason: '排比过度、结构重复，可练句速变化破单调',
  ),
  StyleTechniqueMapping(
    dimensionKey: 'sensory:visual',
    dimensionLabel: '感官偏好=视觉型',
    techniqueIds: ['T002'],
    reason: '感官通道以视觉为主，可交织其他感官',
  ),
  StyleTechniqueMapping(
    dimensionKey: 'sensory:auditory',
    dimensionLabel: '感官偏好=听觉型',
    techniqueIds: ['T002'],
    reason: '感官通道以听觉为主，可交织其他感官',
  ),
  StyleTechniqueMapping(
    dimensionKey: 'sensory:kinesthetic',
    dimensionLabel: '感官偏好=体感型',
    techniqueIds: ['T002'],
    reason: '感官通道以体感为主，可交织其他感官',
  ),
  StyleTechniqueMapping(
    dimensionKey: 'toneTexture:poetic',
    dimensionLabel: '语调质感=诗意型',
    techniqueIds: ['T003'],
    reason: '修辞密集有堆砌风险（关联 P008），可练删繁就简',
  ),
  StyleTechniqueMapping(
    dimensionKey: 'narrativeDistance:intimate',
    dimensionLabel: '叙事距离=贴身型',
    techniqueIds: ['T001'],
    reason: '内心独白偏多（关联 P003），可练情绪外化',
  ),
  StyleTechniqueMapping(
    dimensionKey: 'narrativeDistance:editorial',
    dimensionLabel: '叙事距离=评述型',
    techniqueIds: ['T020'],
    reason: '叙述者抢戏、告知倾向，可练借景抒情',
  ),
  StyleTechniqueMapping(
    dimensionKey: 'structure:fragmented',
    dimensionLabel: '结构直觉=碎片型',
    techniqueIds: ['T029'],
    reason: '跳跃无过渡（关联 P020），可练场景桥接',
    crossLayer: true, // T029 属 content 层，跨层调用显式声明
  ),
];

// ── b9 批次29：技法库 L2 症候→技法映射表行渲染（输出与手写逐字一致）─

/// 首选技法列：`T001 动态描写公式`
String _l2Primary(SyndromeRecord s) {
  final t = s.techniques.first;
  return '$t ${techniqueNameOf(t) ?? ''}';
}

/// 备选技法列：逐症候复现现有格式特例
///   - 无备选 → '—'
///   - 斜杠组（P006/P007/P008/P009/P011）：`T017/T018/T022`（无技法名）
///   - 带技法名组（P003/P004/P023-P031）：`T002 感官交织法、T020 借景抒情法`
///   - 其余单值无技法名：`T007`
String _l2AltColumn(SyndromeRecord s) {
  final alts = s.techniques.sublist(1);
  if (alts.isEmpty) return '—';
  const slashGroup = {'P006', 'P007', 'P008', 'P009', 'P011'};
  if (slashGroup.contains(s.id)) return alts.join('/');
  const namedGroup = {
    'P003',
    'P004',
    'P023',
    'P024',
    'P026',
    'P027',
    'P028',
    'P029',
    'P030',
    'P031',
    'P032',
    'P033',
    'P034',
    'P035',
    'P036',
    'P037',
    'P038',
    'P039',
    'P040',
    'P041',
  };
  if (namedGroup.contains(s.id)) {
    return alts.map((t) => '$t ${techniqueNameOf(t) ?? ''}').join('、');
  }
  return alts.join('、');
}

/// L2 症候→技法映射表行：`| P003 | T001 动态描写公式 | T002 感官交织法、T020 借景抒情法 |`
String _l2TechniqueMapRow(SyndromeRecord s) =>
    '| ${s.id} | ${_l2Primary(s)} | ${_l2AltColumn(s)} |';
