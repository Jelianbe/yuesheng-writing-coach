// ─────────────────────────────────────────────────────────────
// setting_library_service — 设定资料库用户裁决服务（第一批承重墙）
//
// 2026-09-16 批次立项：docs/designs/2026-09-16-setting-library-first-batch.md
// 职责：AI 抽取断言（pending）→ 用户裁决（confirmed / rejected /
//       superseded）+ 同属性异值三选一合并。纯服务层，供第二批
//       确认卡 UI 调用；本身不依赖 UI。
//
// 关键纪律：
//  - 写回一律走 Repository.replaceAssertions（**原样落库，不 merge**）
//    ——merge 语义会把用户裁决当 incoming 重新合并（R-009）。
//  - 只改被裁决的那条断言的 status / rejectReason，其余断言原样。
//  - 断言级 status 四态：pending | confirmed | rejected | superseded。
// ─────────────────────────────────────────────────────────────

import '../data/repositories/character_fact_repository.dart';
import '../data/repositories/world_fact_repository.dart';
import '../types/character_types.dart';

/// 合并裁决：保留 A / 保留 B / 两者皆是（被取代者标 superseded）。
enum MergeVerdict { keepA, keepB, keepBoth }

/// 疑似重复断言对（AI 辅助比较入口）：同人物 + 同属性 + 同章（或均未标章）
/// + 异值。跨章异值属时序演进，不构成冲突。
class AssertionConflictPair {
  final String name;
  final CharacterAssertion a;
  final CharacterAssertion b;

  const AssertionConflictPair({
    required this.name,
    required this.a,
    required this.b,
  });
}

/// 侦测规则（立项备忘 §2.2，防误杀人物弧光）：同章（或均未标章）+
/// 同实体 + 同属性 + 异值 → 疑似重复提示。跨章异值 = 时序演进，不算。
///
/// 输入 = 已按人物解析的断言列表（[items]）；输出按 (人物, 属性, 章节) 稳定
/// 排序。每组冲突只取**首对**（避免同属性三值以上的 N² 爆炸）；rejected /
/// superseded 断言不参与（已裁决或已被取代）。
List<AssertionConflictPair> detectCharacterConflicts(
  List<(String name, CharacterAssertion a)> items,
) {
  final byKey = <(String, String, int?), List<CharacterAssertion>>{};
  for (final (name, a) in items) {
    if (a.status == 'rejected' || a.status == 'superseded') continue;
    byKey.putIfAbsent((name, a.attribute, a.chapter), () => []).add(a);
  }
  final out = <AssertionConflictPair>[];
  for (final entry in byKey.entries) {
    final list = entry.value;
    if (list.length < 2) continue;
    final first = list.first;
    for (final other in list.skip(1)) {
      if (other.value != first.value) {
        out.add(AssertionConflictPair(name: entry.key.$1, a: first, b: other));
        break; // 首对即可，避免 N²
      }
    }
  }
  out.sort((x, y) {
    final byName = x.name.compareTo(y.name);
    if (byName != 0) return byName;
    final byAttr = x.a.attribute.compareTo(y.a.attribute);
    if (byAttr != 0) return byAttr;
    return (x.a.chapter ?? -1).compareTo(y.a.chapter ?? -1);
  });
  return out;
}

/// AI 辅助比较 prompt（纯分析不代决）：输入冲突对，输出对比要点与
/// 倾向建议；最终决定权在用户（R-009）。空冲突对 → 空串（零调用）。
String buildConflictComparisonPrompt({
  required String name,
  required CharacterAssertion a,
  required CharacterAssertion b,
}) {
  final chapterA = a.chapter == null ? '未标注' : '第${a.chapter}章';
  final chapterB = b.chapter == null ? '未标注' : '第${b.chapter}章';
  return '请纯分析以下两条同属性设定（不替你决定，只给参考）：\n'
      '人物：$name\n'
      'A（$chapterA）：${a.attribute} = ${a.value}\n'
      'B（$chapterB）：${b.attribute} = ${b.value}\n\n'
      '请给出：1) 两条设定的差异要点；2) 结合写作常识，两者是否可能'
      '并存（如性格侧面 / 阶段变化）；3) 若只能保留一条，你的倾向与理由。'
      '最后注明「最终由你决定」。';
}

/// 设定资料库用户裁决服务（character + world 双表同构）。
class SettingLibraryService {
  final CharacterFactRepository _characterRepo;
  final WorldFactRepository _worldRepo;

  SettingLibraryService({
    required CharacterFactRepository characterRepo,
    required WorldFactRepository worldRepo,
  }) : _characterRepo = characterRepo,
       _worldRepo = worldRepo;

  /// 工厂：现有 Provider 装配点使用位置参数风格时用（保持调用方零改动）。
  factory SettingLibraryService.withRepos({
    required CharacterFactRepository characterFactRepo,
    required WorldFactRepository worldFactRepo,
  }) => SettingLibraryService(
    characterRepo: characterFactRepo,
    worldRepo: worldFactRepo,
  );

  // ─── 人物侧 ───

  /// 确认一条 pending 断言为 confirmed（用户认可 AI 抽取）。
  Future<void> confirmCharacter({
    required String manuscriptId,
    required String name,
    required String attribute,
    required String value,
  }) async {
    await _applyCharacterVerdict(
      manuscriptId: manuscriptId,
      name: name,
      attribute: attribute,
      value: value,
      status: 'confirmed',
    );
  }

  /// 拒绝一条断言（拒绝记忆本体：AI 不得再次提议同值）。
  Future<void> rejectCharacter({
    required String manuscriptId,
    required String name,
    required String attribute,
    required String value,
    String? reason,
  }) async {
    await _applyCharacterVerdict(
      manuscriptId: manuscriptId,
      name: name,
      attribute: attribute,
      value: value,
      status: 'rejected',
      reason: reason,
    );
  }

  /// 标记 superseded（合并裁决中被取代；留库不进列表）。
  Future<void> supersedeCharacter({
    required String manuscriptId,
    required String name,
    required String attribute,
    required String value,
  }) async {
    await _applyCharacterVerdict(
      manuscriptId: manuscriptId,
      name: name,
      attribute: attribute,
      value: value,
      status: 'superseded',
    );
  }

  /// 同属性异值三选一（人物）：[a]、[b] 为同 (name, attribute) 的两条断言。
  ///
  /// 被取代者标 superseded；跨章异值属时序演进，**不调用本方法**（调用方
  /// 先按「同章或均未标章」筛选——立项备忘 §2.2 防误杀人物弧光）。
  Future<void> resolveCharacterConflict({
    required String manuscriptId,
    required String name,
    required String attribute,
    required CharacterAssertion a,
    required CharacterAssertion b,
    required MergeVerdict verdict,
  }) async {
    final row = await _characterRepo.getCharacter(manuscriptId, name);
    if (row == null) return;
    final existing = CharacterFactRepository.parseAssertions(row.assertions);
    bool aMatches(CharacterAssertion x) =>
        x.attribute == a.attribute && x.value == a.value;
    bool bMatches(CharacterAssertion x) =>
        x.attribute == b.attribute && x.value == b.value;
    final updated = existing.map((x) {
      final isA = aMatches(x);
      final isB = bMatches(x);
      switch (verdict) {
        case MergeVerdict.keepA:
          if (isA) return x.withStatus('confirmed');
          if (isB) return x.withStatus('superseded');
          return x;
        case MergeVerdict.keepB:
          if (isA) return x.withStatus('superseded');
          if (isB) return x.withStatus('confirmed');
          return x;
        case MergeVerdict.keepBoth:
          if (isA || isB) return x.withStatus('confirmed');
          return x;
      }
    }).toList();
    await _characterRepo.replaceAssertions(
      manuscriptId: manuscriptId,
      name: name,
      assertions: updated,
    );
  }

  Future<void> _applyCharacterVerdict({
    required String manuscriptId,
    required String name,
    required String attribute,
    required String value,
    required String status,
    String? reason,
  }) async {
    final row = await _characterRepo.getCharacter(manuscriptId, name);
    if (row == null) return;
    final existing = CharacterFactRepository.parseAssertions(row.assertions);
    final updated = existing.map((a) {
      if (a.attribute == attribute && a.value == value) {
        return a.withStatus(status, rejectReason: reason);
      }
      return a;
    }).toList();
    await _characterRepo.replaceAssertions(
      manuscriptId: manuscriptId,
      name: name,
      assertions: updated,
    );
  }

  // ─── 世界观侧（同构；world 目前仅用户录入，裁决通道先行就位）───

  /// 确认一条世界观断言。
  Future<void> confirmWorld({
    required String manuscriptId,
    required String name,
    required String attribute,
    required String value,
  }) async {
    await _applyWorldVerdict(
      manuscriptId: manuscriptId,
      name: name,
      attribute: attribute,
      value: value,
      status: 'confirmed',
    );
  }

  /// 拒绝一条世界观断言。
  Future<void> rejectWorld({
    required String manuscriptId,
    required String name,
    required String attribute,
    required String value,
    String? reason,
  }) async {
    await _applyWorldVerdict(
      manuscriptId: manuscriptId,
      name: name,
      attribute: attribute,
      value: value,
      status: 'rejected',
      reason: reason,
    );
  }

  Future<void> _applyWorldVerdict({
    required String manuscriptId,
    required String name,
    required String attribute,
    required String value,
    required String status,
    String? reason,
  }) async {
    final row = await _worldRepo.getWorld(manuscriptId, name);
    if (row == null) return;
    final existing = WorldFactRepository.parseAssertions(row.assertions);
    final updated = existing.map((a) {
      if (a.attribute == attribute && a.value == value) {
        return a.withStatus(status, rejectReason: reason);
      }
      return a;
    }).toList();
    await _worldRepo.replaceAssertions(
      manuscriptId: manuscriptId,
      name: name,
      assertions: updated,
    );
  }
}
