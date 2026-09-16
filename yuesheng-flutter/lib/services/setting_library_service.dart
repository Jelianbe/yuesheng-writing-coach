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
