// ─────────────────────────────────────────────────────────────
// coach_persona_templates — 系统档派生起点模板（ADR-C132 批3 · B）
//
// 定位：新建自定义教练时「从系统档开始」的**语气起点模板**。
//
// 边界（ADR §5 B 裁定）：这是**静态 seed 副本**（用户编辑起点文本，
// 进 UI / 数据层），不是运行时注入 prompt 原文——注入真源仍在
// skills_attitude.dart（skill_registry part，快照锁守护）。模板文本
// 按各档「五段精髓」面向用户重写，不逐字复制注入资产。
//
// 键 = 系统档 id（doubao / yuesheng / sensei），与 builtInCoachPersonas 对齐。
//
// 本文件同时承载「角色预设」模板（kCharacterPresetTemplates）：试听效果测试
// 用的语气便捷起点。与 kSystemToneTemplates 同纪律——静态 seed、进 UI 数据层、
// 不注入运行时 prompt；点 chips 仅把语气文本填入语气设定框，由用户继续编辑
// （只填框、不写回、不自动保存）。
// ─────────────────────────────────────────────────────────────

import '../types/coach_persona_seed.dart';

/// 系统档 → 语气起点模板（B 派生入口的数据源）。
const Map<String, String> kSystemToneTemplates = {
  'doubao':
      '你是用户的写作陪练伙伴，氛围轻松友好，语气温和包容。'
      '反馈先肯定具体之处，再给一个可操作的练习方向；'
      '回复要短，一次只抛一个点，多用「呀 / 呢 / 哦」拉近距离，'
      'emoji 最多用 1 个。',
  'yuesheng':
      '你是用户的写作陪练教练，温柔但有锋芒。'
      '直接指出问题并讲清原理，给选择而不是指令；'
      '回复长度中等，一次聚焦 1-2 个症候，示范 1 句；'
      '不用 emoji，节制修饰词。',
  'sensei':
      '你是用户的严格技术教练，专注写作工艺本身的提升。'
      '反馈覆盖「现象 - 诊断 - 建议」三件事，不做情感鼓励，'
      '不给示范只给方向；回复完整深入，一次聚焦 1 个核心问题，'
      '零客套零铺垫。',
};

/// 按系统档 id 取模板（id 未知 = null）。
String? systemToneTemplateById(String? id) {
  if (id == null) return null;
  return kSystemToneTemplates[id];
}

/// 系统档 id → 展示名（供派生入口 toast 使用；未知 = 原样返回）。
String systemToneName(String id) {
  for (final p in builtInCoachPersonas) {
    if (p.id == id) return p.name;
  }
  return id;
}

/// 角色预设模板：试听效果测试用的语气便捷起点（静态 seed，不注入运行时 prompt）。
class CharacterPresetTemplate {
  const CharacterPresetTemplate({
    required this.id,
    required this.displayName,
    required this.toneText,
  });

  /// 预设 id（内部标识，不展示）。
  final String id;

  /// chip 上展示的名字。
  final String displayName;

  /// 语气设定文本（点 chip 填入语气框，用户可继续编辑）。
  final String toneText;
}

/// 角色预设静态模板（第一例：猫娘，仅用于视听效果测试）。
/// 与 kSystemToneTemplates 同纪律：静态 seed、进 UI 数据层、不注入运行时 prompt。
const List<CharacterPresetTemplate> kCharacterPresetTemplates = [
  CharacterPresetTemplate(
    id: 'neko',
    displayName: '猫娘',
    toneText: '你是猫娘，说话带撒娇感，每句话结尾加"喵～"',
  ),
];
