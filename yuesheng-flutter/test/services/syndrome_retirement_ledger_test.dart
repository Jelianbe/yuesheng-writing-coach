// ─────────────────────────────────────────────────────────────
// 退役档案 ⇄ 产物 ⇄ 注册表 三方交叉锁定（转换机层 1 · R 批）
//
// ── 本文件锁什么 ──
// 转换机把「每次改 N 处」变成「改 1 处」（`syndrome_retirement.dart` 真源
// → 生成器 → 三份产物）。收益很大，但**风险也集中在一处**：
// 如果真源与产物漂移、或档案与注册表脱节，**没有任何东西会报错**
// —— merge map 少一条键 = 旧行读不出来（静默漏读）；
// 档案里目标 ID 写错 = 数据被归一到错误的实体（静默数据损坏）。
// ⇒ 本文件的每条断言都必须**能变红**，否则就是伪断言。
//
// ── 判据设计 ──
// 判「能否变红」的方法：**问「注入哪个变异会让本用例红」**，答不上就是伪断言。
// 每条用例的 reason 里都写明了它对应的变异。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/migration_v46.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/syndrome_retirement.dart';

/// 剥掉名字里的括号补充说明。
///
/// 旧注册表部分条目的 `name` 带括号（如「信息倾泻症（含原 P001 世界观膨胀子类型）」），
/// 而现行注册表是干净的短名 ⇒ 直接比较会误判「同名 vs 异名」。
/// 实测踩中 2 条（P004 / P009），是本文件初版红的原因。
String _stripParenthetical(String s) =>
    s.replaceAll(RegExp(r'（[^）]*）'), '').trim();

void main() {
  final active = kSyndromeIds.toSet();

  group('R-1 档案自身完整性', () {
    test('#1 旧 ID 唯一（不得有重复档案）', () {
      final seen = <String, SyndromeRetirement>{};
      final dup = <String>[];
      for (final r in kSyndromeRetirement) {
        if (seen.containsKey(r.oldId)) {
          dup.add('${r.oldId}: ${seen[r.oldId]} vs $r');
        }
        seen[r.oldId] = r;
      }
      expect(
        dup,
        isEmpty,
        reason:
            '同一旧 ID 登记了两条档案 ⇒ 归一目标可能冲突。'
            '变异：复制任意一行档案 ⇒ 本用例红',
      );
    });

    test('#2 ★★★ 并入目标必须都是现行注册表 ID', () {
      final bad = kSyndromeRetirement
          .where((r) => !active.contains(r.mergedInto))
          .map((r) => '${r.oldId} → ${r.mergedInto}（不在现行注册表）')
          .toList();
      expect(
        bad,
        isEmpty,
        reason:
            '并入目标必须是现行 ID，否则数据会被归一到不存在的实体。'
            '变异：任改一条 mergedInto 为 P050 ⇒ 本用例红',
      );
    });

    test('#3 ★ 档案规模锁（4 ghost + 31 renumber + 12 merge + 3 recycled = 50）', () {
      // 实测 2026-10-05：50 条。
      // ⚠️ 增删退役记录时**必须**同步改这条计数（它是「有没有漏登记」的探针）。
      expect(
        kSyndromeRetirement.length,
        50,
        reason:
            '实测 50 条。若变了，说明真源被增删 ⇒ '
            '① 跑 tool/gen_syndrome_retirement.py 重生成产物；'
            '② 同步本计数；③ 检查分类计数断言',
      );
      final byKind = <RetirementKind, int>{};
      for (final r in kSyndromeRetirement) {
        byKind[r.kind] = (byKind[r.kind] ?? 0) + 1;
      }
      expect(byKind[RetirementKind.ghost], 4, reason: 'P001/P002/H001/H002');
      expect(byKind[RetirementKind.renumber], 31, reason: '旧名 == 目标名');
      expect(byKind[RetirementKind.merge], 12, reason: '0.3.6 标 retired:true');
      expect(byKind[RetirementKind.recycled], 3, reason: 'P035/P036/P037');
    });

    test('#4 ★★ ghost 号必须旧名为 null（不可编造名字）', () {
      // 依据：`git show e64096db^:…/syndrome_registry.dart` 的最早记录是 P003，
      // P001/P002/H001/H002 在历史里查不到 ⇒ 旧名不可考。
      // ⚠️ 编造一个名字会让「同名/异名」分类判据失去依据（层2 退役时要靠它）。
      final fabricated = kSyndromeRetirement
          .where((r) => r.kind == RetirementKind.ghost && r.oldName != null)
          .map((r) => '${r.oldId}: 凭空写了旧名「${r.oldName}」')
          .toList();
      expect(
        fabricated,
        isEmpty,
        reason:
            'ghost 号的旧名不可考，写了名字就是编造。'
            '变异：给任一 ghost 号填上 oldName ⇒ 本用例红',
      );
    });

    test('#5 ★★★ 分类判据自洽：renumber 必须同名、merge 必须异名', () {
      // 这是档案的**核心语义**，也是 v1 判据误判 2 条的地方
      //（P004/P009 旧名带括号补充说明，实体其实未变）。
      //
      // ⚠️ 比较必须**剥掉括号补充说明**再比（P004 旧名
      // 「信息倾泻症（含原 P001 世界观膨胀子类型）」vs 现行「信息倾泻症」
      // 是同一实体）。这正是 v1 判据翻车的原因 —— 别退回全等比较。
      final wrong = <String>[];
      for (final r in kSyndromeRetirement) {
        if (r.oldName == null) continue; // ghost 走 #4
        final rawTarget = syndromeNameOf(r.mergedInto);
        if (rawTarget == null) continue; // #2 已保证目标在册，这里兜底
        final targetName = _stripParenthetical(rawTarget);
        final oldName = _stripParenthetical(r.oldName!);
        if (r.kind == RetirementKind.renumber && oldName != targetName) {
          wrong.add(
            '${r.oldId}: 标 renumber 但旧名「${r.oldName}」'
            '≠ 目标名「$targetName」',
          );
        }
        if (r.kind == RetirementKind.merge && oldName == targetName) {
          wrong.add('${r.oldId}: 标 merge 但旧名与目标名相同（$targetName）');
        }
      }
      expect(
        wrong,
        isEmpty,
        reason:
            'renumber = 纯改号（同名）；merge = 实体合并（异名）。'
            '分类错 ⇒ 层2 启用新号段时会把「实体还在」当成「实体已退役」。'
            '变异：把某 merge 改成 renumber（或反之）⇒ 本用例红',
      );
    });
  });

  group('R-2 档案 ⇄ 产物（生成器漂移的第一道锁）', () {
    test('#6 ★★★ merge map 键集 == 档案中非 recycled 的旧 ID', () {
      expect(
        kSyndromeMergeMap.keys.toSet(),
        kMergeMappedSyndromeIds,
        reason:
            'merge map 是生成物，键集必须 == 档案（排除 recycled）。'
            '变异：手删 merge map 里任意一行 ⇒ 本用例红；'
            '或把某 recycled 档案混进 merge map ⇒ 本用例红',
      );
    });

    test('#7 ★★★ merge map 的值 == 档案的并入目标（值侧也要对）', () {
      final bad = <String>[];
      for (final r in kSyndromeRetirement) {
        if (r.kind == RetirementKind.recycled) continue;
        final mine = kSyndromeMergeMap[r.oldId];
        if (mine != r.mergedInto) {
          bad.add('${r.oldId}: merge map=$mine vs 档案=${r.mergedInto}');
        }
      }
      expect(
        bad,
        isEmpty,
        reason:
            '键对了值错了同样是静默串号。'
            '变异：任改 merge map 里一个 value ⇒ 本用例红',
      );
    });

    test('#8 ★★★ v46 平铺表 == 档案全量（含 recycled 3 条）', () {
      expect(
        legacyIdMigrationMap,
        {for (final r in kSyndromeRetirement) r.oldId: r.mergedInto},
        reason:
            'v46 平铺表必须 == 档案**全量**。'
            '⚠️ 它比 merge map 多 recycled 3 条是**有意**的：'
            '槽位待复用为新症候（不能留在读路径映射），'
            '但存量库里确有这些旧号的历史行 ⇒ 必须归一。'
            '变异：① 从平铺表删掉 P035 ⇒ 本用例红；'
            '② 把某 recycled 档案从平铺表删掉 ⇒ 本用例红',
      );
    });

    test('#9 ★★★ recycled 槽位绝不在 merge map（否则新槽位被旧映射改写）', () {
      // 这是 A2 批清三键的**原意**，转换机必须把它固化成断言。
      // 危害：ADR-0003 阶段一把 P035 分给新症候后，读路径仍会按旧映射
      // 把它改写成 P009 ⇒ 新症候读到的是旧实体数据，且**表面上完全正常**。
      final leaked = kSyndromeRetirement
          .where(
            (r) =>
                r.kind == RetirementKind.recycled &&
                kSyndromeMergeMap.containsKey(r.oldId),
          )
          .map((r) => r.oldId)
          .toList();
      expect(
        leaked,
        isEmpty,
        reason:
            'recycled 槽位进了 merge map ⇒ 新槽位会被旧映射改写成旧实体。'
            '变异：把 P035 加回 kSyndromeMergeMap ⇒ 本用例红'
            '（同时 #6 也会红）',
      );
    });
  });

  group('R-3 档案 ⇄ 注册表（退役的必须已不在册）', () {
    test('#10 ★★★ 「旧号又出现」时，必须是不同的实体（同名才是事故）', () {
      // ⚠️ **不可写成「merge/ghost 的旧 ID 不得出现在现行注册表」** ——
      // 那是伪断言，实测当前就有 9 条违反（P001/P002 + P017/P019/P023/P024/
      // P025/P029/P033）。原因是 §4-136 的**编码碰撞**：
      // 同一个字符串既是旧号也是现行号，但指**完全不同的实体**
      // （实测：字符串 `P017` 现在是「跳跃叙事/过度概括症」，
      //  而档案里 `P017` 退役时是「伏笔失效症」）。
      //
      // ⇒ 真正可判的判据是：**旧名 ≠ 现行名**。
      // 若哪天某个旧号被复用给**同一个**实体（同名），那才是真事故 ——
      // 因为归一会把新实体的数据改写到旧实体上，且表面完全正常。
      final sameEntity = <String>[];
      for (final r in kSyndromeRetirement) {
        if (!active.contains(r.oldId)) continue; // 未撞现行号，无从谈起
        if (r.oldName == null) continue; // ghost 无旧名可比
        final cur = syndromeNameOf(r.oldId);
        if (cur == null) continue;
        if (_stripParenthetical(cur) == _stripParenthetical(r.oldName!)) {
          sameEntity.add('${r.oldId}: 旧名「${r.oldName}」== 现行名「$cur」');
        }
      }
      expect(
        sameEntity,
        isEmpty,
        reason:
            '旧号撞现行号时必须指向**不同**实体。'
            '若同名 ⇒ 该号被复用给同一实体，归一会把它的数据改写到旧实体'
            '（静默串号）。'
            '变异：把某条档案的 oldId 改成一条同名的现行 ID ⇒ 本用例红',
      );
    });

    test('#11 ★★ renumber 条目的旧 ID 可以撞现行号（编码碰撞的已知形态）', () {
      // 这是 §4-136 记录的**不可救**形态：「旧 P005」与「现行 P005」是同一字符串。
      // 本用例不是断言「不该撞」，而是**把现状钉住**：
      // 撞现行号的数量一旦变化，说明档案或注册表结构变了，需重新评估 M1 语义。
      //
      // ⚠️ **2026-10-05 ADR-0003 阶段一落地，本数 33 → 36**：P035/P036/P037 原为
      //   `RetirementKind.recycled`（槽位待复用，**不在** merge map 里），注册为
      //   新症候后它们从「真旧号」变成「碰撞键」⇒ 档案 ∩ 现行 由 33 升到 36。
      //   ⚠️ **注意两个集合不同义，别混**（本批已踩过一次）：
      //     ·本用例统计的是**档案 50 条**（含 recycled 3条）∩ 现行 = **36**
      //     · 而 `kSyndromeMergeMap` 只有 **47 条**（recycled 已清）∩ 现行 = **33**
      //   ⇒ 「33 变成 36」与「merge map 仍是 33」**同时为真**，不矛盾。
      //   M1 语义**未变**：读路径 merge map 未动，现行 ID 恒等短路仍成立。
      final collided = kSyndromeRetirement
          .where((r) => active.contains(r.oldId))
          .map((r) => r.oldId)
          .toSet();
      expect(
        collided.length,
        36,
        reason:
            '实测 36 个键 ∩ 现行注册表（33 个原碰撞 + P035/P036/P037）。'
            '⚠️ 这是 §4-136 的编码碰撞，**纯逻辑层无解** —— '
            'M1 靠「现行 ID 恒等」短路来保护读路径。'
            '若此数变了，M1 的前提可能已变 ⇒ 必须重读 syndrome_registry 的 M1 文档',
      );
    });
  });

  group('R-4 护栏豁免集合 ⇄ 档案（护栏不得再手抄）', () {
    test('#12 ★★★ 护栏豁免集合 == 档案全量 ID', () {
      // four_libraries_consistency_test.dart #9 与
      // syndrome_reference_integrity_test.dart #R2 的判据真源。
      // ⚠️ 改判据而非改数据：豁免集合必须是「所有仍可被归一的编号」。
      expect(
        kRetiredSyndromeIds,
        legacyIdMigrationMap.keys.toSet(),
        reason:
            '豁免集合的真源（kRetiredSyndromeIds，50 条）'
            '必须 == v46 平铺表键集。'
            '变异：把 P035 从任一处移出 ⇒ 本用例红',
      );
    });

    test('#13 ★★ 豁免集合 ⊇ merge map 键集（超集方向不可反）', () {
      // A1 批的子集校验：平铺 ⊇ 真源。方向反了会让「平铺比真源干净」
      // 这种合法状态无法表达 ⇒ 曾让「清理历史遗留」触发 StateError 阻断升级。
      expect(
        kMergeMappedSyndromeIds.difference(kRetiredSyndromeIds),
        isEmpty,
        reason:
            'merge map（47）⊆ 档案全量（50）。'
            '变异：从档案里删掉任一非 recycled 条目 ⇒ 本用例红',
      );
    });
  });

  group('R-5 生成器产物无残留（生成物必须自标注）', () {
    test('#14 ★ 两份产物都带「请勿手改」标记', () {
      // 防呆：任何人手改了产物，至少能在文件里看到该重跑生成器。
      // ⚠️ 这是**弱**判据（只查字符串存在），它的价值在于让违规可被 grep 到。
      final reg = File(
        'lib/services/syndrome_registry.dart',
      ).readAsStringSync();
      final v46 = File(
        'lib/data/database/migration_v46.dart',
      ).readAsStringSync();
      for (final pair in {
        'kSyndromeMergeMap': reg,
        '_legacyToCanonical': v46,
      }.entries) {
        final seg = pair.value;
        expect(
          seg.contains('本段由 tool/gen_syndrome_retirement.py 生成'),
          isTrue,
          reason:
              '${pair.key} 段必须带「生成物·请勿手改」标记。'
              '变异：删掉该行注释 ⇒ 本用例红',
        );
      }
    });

    test('#15 ★★★ 真源必须被 dart format off 包住（否则生成器静默丢条目）', () {
      // ★★★ 本条是实测踩出来的坑，也是本批最隐蔽的一个缺陷。
      //
      // 形态：带括号长名的两条（`P004` / `P009`）行长远超 80 列。
      // 若不加 `// dart format off`，`dart format` 会把它们拆成
      // 「每参数一行 + **尾随逗号**」的多行形态：
      //     SyndromeRetirement(
      //       'P004',
      //       '信息倾泻症（含原 P001 世界观膨胀子类型）',
      //       'P002',
      //       RetirementKind.renumber,
      //     ),
      // 生成器的逐条正则要求 `\s*\)` 紧跟 `RetirementKind.x` ⇒ 遇到那个
      // **尾随逗号**就匹配不到 ⇒ **静默丢 2 条**（实测解析数 50 → 48）。
      // 而产物里它们还在 ⇒ `--check` 只报「漂移」，看不出真因。
      //
      // 判据不能只查「有没有 format off 标记」—— 那太弱，位置错了也查不出。
      // 必须查**位置**：off 在档案列表之前、on 在其后。
      final src = File(
        'lib/services/syndrome_retirement.dart',
      ).readAsStringSync();
      final listAt = src.indexOf('kSyndromeRetirement = [');
      final offAt = src.indexOf('// dart format off');
      final onAt = src.indexOf('// dart format on');
      expect(
        offAt > 0 && onAt > 0 && offAt < listAt && onAt > listAt,
        isTrue,
        reason:
            '退役档案列表必须被 `dart format off` … `on` 包住。'
            '⚠️ 实测：去掉后 dart format 会把长行拆成多行 + 尾随逗号，'
            '生成器静默丢条目（50 → 48）而 --check 只报「漂移」。'
            '变异：删掉任一标记 ⇒ 本用例红',
      );
    });
  });
}
