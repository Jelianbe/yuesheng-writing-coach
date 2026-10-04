// ─────────────────────────────────────────────────────────────
// syndrome_merge_map_test — C126 幽灵键清理+ B1 M1 归一语义锁定
//
// 第一部分（C126）：kSyndromeMergeMap 曾残留 `'P034': 'P025'` 幽灵键：
//   P034 本是现行症候（代词指代不清/零回指过载症），却被错吸进旧 P025。
//   1. mergeMap 不再含 'P034' 键
//   2. mergeMap 不再含 'P025' 值（幽灵值彻底消失）
//   3. effectiveSyndromeId('P034') == 'P034'
//   4. syndromeNameOf('P034') == '代词指代不清/零回指过载症'
//
// 第二部分（B1 · M1 语义）：`effectiveSyndromeId` 归一语义的**四条性质**锁定。
//
//   背景（2026-10-04 实测）：旧实现是 `kSyndromeMergeMap[id] ?? id`，
//   而 merge map 有 **33 个键同时是现行活跃 ID**（P001–P033）且**有环**
//   （P003→P001→P002→P007→P005→P003）
//   ⇒ `effectiveSyndromeId` **不是等价关系**：
//      · 传递性违例 106 · 幂等违反 34/34
//      · 单边用它比较 ⇒ 34 个现行 ID 只有 1 个自匹配（漏读 + 串号）
//      · 双边用它比较 ⇒ 18 对现行 ID 互撞（**把不同症候并成一个**，更隐蔽）
//
//   M1 语义（现行 ID 恒等 + 旧号单跳）：
//      · ID ∈ 现行注册表 ⇒ **原样返回**（不查 merge map）
//      · 否则 ⇒ 单跳 `merge[id] ?? id`（与 v46 迁移语义完全一致）
//   实测读数：现行 ID 被改写 **0/34** · 串号 **0 对** · 幂等稳定 **0 处不稳定**
//              · `P999`→`P999` ✓ · `P050`→`P050` ✓
//
// ★ 本部分的作用是**锁住这个语义不被静默改回**。
//   任何把「现行 ID 恒等」这条去掉的改动，都必须先来这里改断言并说明理由。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/syndrome_registry.dart';

void main() {
  group('C126 幽灵键清理（P034→P025 残留）', () {
    test('#1 kSyndromeMergeMap 不再含 P034 键', () {
      expect(
        kSyndromeMergeMap.containsKey('P034'),
        isFalse,
        reason: 'P034 是现行症候，不应作为 legacy 归一键',
      );
    });

    test('#2 kSyndromeMergeMap 不再含 P025 值', () {
      expect(
        kSyndromeMergeMap.containsValue('P025'),
        isFalse,
        reason: '幽灵值 P025 彻底消失（P025 自身仍是现行症候记录，只是不被任何 legacy 指向）',
      );
    });

    test('#3 effectiveSyndromeId(P034) == P034（P034 自聚）', () {
      expect(effectiveSyndromeId('P034'), 'P034');
    });

    test('#4 syndromeNameOf(P034) == 代词指代不清/零回指过载症', () {
      expect(
        syndromeNameOf('P034'),
        '代词指代不清/零回指过载症',
        reason: '精确匹配注册表优先，语义不随幽灵键删除而变',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // B1 · M1 归一语义锁定
  //
  // 这部分锁的**不是某条数据**，而是**归一函数的语义契约**。
  // 删掉任何一条断言前先问：这条性质若丢了，会有哪个缺陷重新静默地活过来？
  // ═════════════════════════════════════════════════════════════

  group('B1-M1 性质一：现行 ID 恒等（自反）', () {
    test('#M1-1 ★★★ 全 34 个现行 ID 归一后原样返回', () {
      final broken = <String>[];
      for (final id in kSyndromeIds) {
        final after = effectiveSyndromeId(id);
        if (after != id) {
          broken.add('$id(${syndromeRecordOf(id)?.name}) → $after');
        }
      }
      expect(
        broken,
        isEmpty,
        reason:
            '现行 ID 必须恒等（自反）。没有这条，「拿现行 ID 查自己」就不成立'
            '⇒ 漏读 33/34（实测旧实现只有 1 个现行 ID 能自匹配）。',
      );
    });

    test('#M1-2 正对照：merge map 里确实有键 ∈ 现行集合', () {
      // 这条是 #M1-1 的**鉴别力前提**：若 merge map 里再没有键 ∈ 现行集合，
      // #M1-1 就变成恒真断言（怎么实现都过）⇒ 必须显式守住「碰撞仍然存在」
      // 这个事实，让后来人知道 M1 不是多余的分支。
      final active = kSyndromeIds.toSet();
      final collided = kSyndromeMergeMap.keys.where(active.contains).toList();
      expect(
        collided.length,
        33,
        reason:
            '实测 33/34（仅 P034 逃过，因它是 C118 后加、不在旧号段）。'
            '若此数变了：变大有新键撞现行 ID（要核对其值指向）；'
            '变小说明已清理过，则 #M1-1 的鉴别力下降，应重新评估。',
      );
    });
  });

  group('B1-M1 性质二：幂等（归一再归一不变）', () {
    test('#M1-3 ★★★ eff(eff(x)) == eff(x)，对全部 merge 键 + 全部现行 ID', () {
      final unstable = <String>[];
      final all = <String>{...kSyndromeMergeMap.keys, ...kSyndromeIds};
      for (final id in all) {
        final once = effectiveSyndromeId(id);
        final twice = effectiveSyndromeId(once);
        if (once != twice) unstable.add('$id → $once → $twice');
      }
      expect(
        unstable,
        isEmpty,
        reason:
            '幂等是「可反复归一」的前提。旧实现实测幂等违反 34/34'
            '（如 P005 → P003 → P001，连跳两次就变）。',
      );
    });
  });

  group('B1-M1 性质三：等值判定（现行 ID 之间不得互撞）', () {
    test('#M1-4 ★★★ 34×34 全对：现行 ID 两两不互撞', () {
      final collisions = <String>[];
      for (final a in kSyndromeIds) {
        for (final b in kSyndromeIds) {
          if (a == b) continue;
          if (effectiveSyndromeId(a) == effectiveSyndromeId(b)) {
            collisions.add(
              '${syndromeRecordOf(a)?.name}($a) ~ '
              '${syndromeRecordOf(b)?.name}($b)',
            );
          }
        }
      }
      expect(
        collisions,
        isEmpty,
        reason:
            '两侧都是现行 ID 时，归一不得把它们并成同一个。'
            '旧实现下实测 **18 对**（如 P001 情绪标签化 ~ P004 节奏停滞，都归一到 P002）。'
            '⚠️ 这一条正是「双边归一不等于安全」的判据。',
      );
    });

    test('#M1-5 现行 ID 自匹配恒真（漏读判据）', () {
      // 修 training_input_builder:407 时用的就是这个判据：
      // 「拿现行 ID 查自己」必须恒成立。
      for (final id in kSyndromeIds) {
        expect(
          effectiveSyndromeId(id),
          id,
          reason: '$id 自匹配必须成立（否则该症候读不到自己的历史）',
        );
      }
    });
  });

  group('B1-M1 性质四：真旧号仍能兜底', () {
    test('#M1-6 ★★★ 键∉现行集合的条目归一到正确实体', () {
      final active = kSyndromeIds.toSet();
      final legacyKeys = kSyndromeMergeMap.entries
          .where((e) => !active.contains(e.key))
          .toList();
      // 真旧号 = P035–P049（15 个）+ H001/H002（2 个）= 17 个。
      // 它们**必须**仍走 merge 归一——否则 DB 里的旧行会读不出来。
      expect(
        legacyKeys.length,
        17,
        reason:
            '实测 17 个（P035–P049 + H001/H002）。'
            '若此数变了，说明 merge map 结构变了（M1 只保护键侧，值侧变会让本用例红）。',
      );
      for (final e in legacyKeys) {
        expect(
          effectiveSyndromeId(e.key),
          e.value,
          reason:
              '真旧号 ${e.key} 必须归一到 ${e.value}'
              '（它是 DB 存量行的唯一归一路径）',
        );
      }
    });

    test('#M1-7 未登记 ID 原样返回（不猜、不吞）', () {
      for (final id in ['P050', 'P099', 'P999', 'X001', 'ZZZ']) {
        expect(
          effectiveSyndromeId(id),
          id,
          reason: '$id 不在 merge map 与注册表里，必须原样返回（未知不能变成已知）',
        );
      }
    });
  });

  group('B1-M1 与 v46 迁移的语义一致性', () {
    test('#M1-8 ★★ 对真旧号，M1 结果必须 == merge 单跳结果', () {
      // v46 迁移按 merge map 把存量**旧号**行单跳改写成现行 ID；
      // M1 对**真旧号**也是单跳。两条路径必须给同一答案，
      // 否则「迁移前的行」与「迁移后的行」会在读路径上分叉成两个实体。
      final active = kSyndromeIds.toSet();
      final divergence = <String>[];
      for (final e in kSyndromeMergeMap.entries) {
        if (active.contains(e.key)) continue; // 只看真旧号
        final v46 = kSyndromeMergeMap[e.key] ?? e.key; // 迁移用的单跳
        final m1 = effectiveSyndromeId(e.key); // 读路径用的单跳
        if (v46 != m1) divergence.add('${e.key}: v46→$v46 vs M1→$m1');
      }
      expect(
        divergence,
        isEmpty,
        reason: 'M1 与 v46 迁移必须对同一真旧号给同一答案，否则存量行与已迁移行分叉',
      );
    });
  });
}
