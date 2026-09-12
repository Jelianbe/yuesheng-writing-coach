// ─────────────────────────────────────────────────────────────
// world_setting — 批次 E1-b：世界观设定层的判据入口（ADR-C93 D3）
//
// 对位 character_identity.dart：把「仓储行 → 判据输入」的适配收在一处，对外
// **只暴露入口，不允许调用方自行组合**——漏掉「解析断言 JSON」或「evidence
// 门槛」任一环都不会报错，只会**静默降级**（观察项永不产出，且无从察觉）。
//
// 与 character 侧的刻意差异：
//   · 无身份合并需求——world_fact 的唯一键是 UNIQUE(manuscript_id, name) 且
//     无 aliases 列（E1-a 已定，见 tables.dart 本表注释），同一设定主题不会
//     因别名落成多行，故本文件比 character_identity.dart 薄。
//   · 不做 findKeywordExcerpt 反查正文——观察项的 excerpt 直接取自断言自带的
//     evidence（D4① 门槛保证非空），门槛机制同时充当了摘录来源。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';
import '../data/repositories/world_fact_repository.dart';
import 'conflict_detector.dart';

/// 判据入口：世界观仓储行 → 设定不一致观察项。
///
/// 调用方契约：入参应是 `WorldFactRepository.listWorlds(manuscriptId)` 的结果
/// ——默认已排除 `status='archived'` 的归档行（归档设定不该参与检测）。
///
/// 断言解析必须走 [WorldFactRepository.parseAssertions]（DB 回读入口，保留
/// status / source / evidence / chapterHash / stale 全字段）。若误用
/// `CharacterAssertion.tryFromJson`（AI 协议入口），除 evidence 外全字段丢失，
/// `stale` 排除（章节已删改）与「用户否决」一并失效，会开始报幽灵不一致——
/// 这正是把适配收在本文件、不许调用方自行组合的原因。
List<WorldConflictObservation> detectConflictsForWorlds(
  List<WorldFact> worlds,
) => detectWorldConflicts([
  for (final w in worlds)
    (
      name: w.name,
      assertions: WorldFactRepository.parseAssertions(w.assertions),
    ),
]);
