// ─────────────────────────────────────────────────────────────
// L3 训练教学知识库 — 复刻 yuesheng-android/src/assets/skills/training-templates-v2.ts
// 内容 100% 逐字保留（2026-08-08 批次 22 步骤② 补充）
//   kTrainingFullKnowledge → L3 检索源（按症候 ID 提取完整教学知识）
//   getTrainingContent     → L3 检索函数（按症候 ID）
// 生产路径（2026-08-11 校验）：chat_service.sendMessage 已按当前教学焦点
//   调用 getTrainingContent 注入（L3 检索，见 chat_service.dart ~L917）。
//   本文件为训练知识唯一真源，随知识库内容同步维护。
// ─────────────────────────────────────────────────────────────

import 'syndrome_registry.dart'; // kSyndromeIds（b9 真源）

// ─── P3 数据分片（数据/逻辑分离；知识文本在 part 文件）───
part 'training_kb_content.dart';
part 'training_kb_content_1.dart';
part 'training_kb_content_2.dart';
part 'training_kb_content_3.dart';
part 'training_kb_content_4.dart';


/// 症候 ID 列表（b9 真源化：由 syndrome_registry 派生，不再手写；
/// 与 skill_layers syndromeIds 一致；批次15 加 P023-P027，批次23-26 加 P028-P031）
final List<String> kTrainingSyndromeIds = kSyndromeIds;

/// 从完整知识库中按症候 ID 提取单个症候的教学知识（复刻 RN extractTrainingSection）
String _extractTrainingSection(String raw, String id) {
  final pattern = RegExp('^## $id ', multiLine: true);
  final match = pattern.firstMatch(raw);
  if (match == null) return '';
  final startIdx = match.start;
  final nextSection = raw.indexOf('\n## ', startIdx + 1);
  final endIdx = nextSection != -1 ? nextSection : raw.length;
  return raw.substring(startIdx, endIdx).trim();
}

/// L3 检索：获取指定症候的完整训练教学知识（复刻 RN getTrainingContent）
///
/// 用于训练模式下，将当前教学焦点的完整知识注入 system prompt。
/// 入参为症候 ID 列表（通常为 1-2 个）。
String getTrainingContent(List<String> syndromeIds) {
  final sections = syndromeIds
      .map((id) => _extractTrainingSection(kTrainingFullKnowledge, id))
      .where((s) => s.isNotEmpty)
      .toList();

  if (sections.isEmpty) return '';

  const header =
      '## 当前教学焦点的完整训练知识（系统注入，学员不可见）\n\n以下是你当前聚焦症候的完整教学知识（核心本质、教学要点、常见误区、严重度判断参考、教学素材库）。\n请据此组织训练：锚定学员原文、一次只练一个点、给出完成标准、根据学员实时反应调整。\n\n---\n\n';

  return header + sections.join('\n\n---\n\n');
}
