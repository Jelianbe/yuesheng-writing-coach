// ─────────────────────────────────────────────────────────────
// diagnosis_tier_bridge_test — 「写作阶段」偏好接入分级诊断库的判据
//
// ★ 本批的核心断言不是「UI 后缀词变了」，而是
//   **tier 真能改变 skillLevelForBeginner 的输出**（即诊断侧真的分层了）。
//   护栏 A组锁映射表；B 组锁优先级；C 组锁「tier 不生成禁用集」
//   （守住 2026-09-26 「方案 A」决策不被本桥接推翻）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/services/diagnosis_tier_bridge.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  // ── A 组：映射表锁定 ──────────────────────────────────────
  group('A组 映射表', () {
    test('A1 三档各自映射到一个已登记的 BeginnerLevel', () {
      for (final tier in ['beginner', 'story', 'full']) {
        final lv = resolveBeginnerLevelFromTier(
          tier: tier,
          beginnerLevel: null,
        );
        expect(lv, isNotNull, reason: 'tier=$tier 必须有映射（否则该档是死选项）');
        expect(BeginnerLevel.values, contains(lv));
      }
    });

    test('A2 三档互不相同（否则两档行为一样= 有一档是装饰）', () {
      final lv = ['beginner', 'story', 'full']
          .map(
            (t) => resolveBeginnerLevelFromTier(tier: t, beginnerLevel: null),
          )
          .toList();
      expect(lv.toSet().length, 3, reason: '三档映射到同一个值 ⇒ 有一档无实际差异');
    });

    test('A3 三档对应的技能层级单调递增（先写顺 ≤ 完整故事 ≤ 想被挑刺）', () {
      int lv(String tier) => skillLevelFromTier(tier)!.index;
      expect(lv('beginner'), lessThanOrEqualTo(lv('story')));
      expect(lv('story'), lessThanOrEqualTo(lv('full')));
    });

    test('A4 ★核心：tier 真能改变层级（不是只换后缀词）', () {
      // 这是本批存在的理由：若tier 不影响层级，本批等于没做。
      final beginner = skillLevelFromTier('beginner')!;
      final full = skillLevelFromTier('full')!;
      expect(beginner, isNot(full), reason: '「先写顺」与「想被挑刺」必须落在不同层级，否则 tier 是装饰');
    });

    test('A5 isKnownTier 拒绝未登记值（存量脏数据不崩）', () {
      expect(isKnownTier('beginner'), isTrue);
      expect(isKnownTier('full'), isTrue);
      expect(isKnownTier('nonsense'), isFalse);
      expect(isKnownTier(null), isFalse);
      expect(isKnownTier(''), isFalse);
    });
  });

  // ── B 组：优先级 ──────────────────────────────────────────
  group('B组 优先级：tier 优先、beginner_level 兜底', () {
    test('B1 tier 已设 ⇒ 覆盖 beginner_level', () {
      expect(
        resolveBeginnerLevelFromTier(
          tier: 'full',
          beginnerLevel: BeginnerLevel.n1Elements,
        ),
        BeginnerLevel.n4Independent,
        reason: '用户显式选「想被挑刺」应压过冷启动自评N1',
      );
    });

    test('B2 tier 为 null ⇒ 回退 beginner_level（保持原行为）', () {
      expect(
        resolveBeginnerLevelFromTier(
          tier: null,
          beginnerLevel: BeginnerLevel.n2Scene,
        ),
        BeginnerLevel.n2Scene,
      );
    });

    test('B3 tier 未登记（存量脏值）⇒ 回退而非崩', () {
      expect(
        resolveBeginnerLevelFromTier(
          tier: 'legacy_unknown',
          beginnerLevel: BeginnerLevel.n2Scene,
        ),
        BeginnerLevel.n2Scene,
        reason: '未登记 tier 必须回退，不能让整个诊断链崩',
      );
    });

    test('B4 两者皆无 ⇒ null（调用方按「不限制」处理）', () {
      expect(
        resolveBeginnerLevelFromTier(tier: null, beginnerLevel: null),
        isNull,
      );
    });

    test('B5 tier 与 beginner_level 同档 ⇒ 结果一致（幂等）', () {
      final fromTier = resolveBeginnerLevelFromTier(
        tier: 'story',
        beginnerLevel: null,
      );
      expect(
        resolveBeginnerLevelFromTier(tier: null, beginnerLevel: fromTier),
        fromTier,
      );
    });
  });

  // ── C 组：不推翻 2026-09-26「方案 A」决策 ────────────────
  group('C组 tier 不生成禁用集（守住方案 A）', () {
    test('C1 ★effectiveDisabledIds 不含 tier 派生项', () {
      // 方案 A 撤销了「tier 硬映射成禁用维度」，本桥接不得复活它。
      final prefs = DiagnosisPrefs(
        disabledIds: {'P001'},
        tier: 'beginner',
        customized: true,
      );
      expect(prefs.effectiveDisabledIds, {
        'P001',
      }, reason: 'tier 绝不能进入禁用集——那会让「先写顺」变成硬屏蔽高层级问题');
    });

    test('C2 不同 tier 的effectiveDisabledIds 完全相同', () {
      String eff(String tier) => DiagnosisPrefs(
        disabledIds: {},
        tier: tier,
      ).effectiveDisabledIds.join(',');
      expect(
        eff('beginner'),
        eff('full'),
        reason: '若 tier 会改禁用集，就等于复活了被撤销的硬过滤',
      );
    });

    test('C3 本桥接只影响层级，不改 Symptom 的分级', () {
      // 分级真源是注册表派生的 kSyndromeSkillLevelsDerived，桥接不得改它。
      expect(kSyndromeSkillLevels, isNotEmpty);
      // 同一 tier 两次解析必得同一层级（纯函数，无隐藏状态）
      expect(
        resolveBeginnerLevelFromTier(tier: 'story', beginnerLevel: null),
        resolveBeginnerLevelFromTier(tier: 'story', beginnerLevel: null),
      );
    });

    //★ 性质级断言（2026-10-06 补）。C1/C2 只锁了 `effectiveDisabledIds`
    //  这**一个具体 getter 的返回值** —— 属枚举式断言，对结构类缺陷有盲区：
    //  实测负向验证M3（给 DiagnosisPrefs 加一个「tier 进禁用集」的 getter）
    //  **C1/C2 全绿放行** ⇒ 若有人新增另一个消费点、或改`isDisabled`，
    //  原护栏抓不到。按 §4-168「集合级/单点断言在重编号与派生场景天然不可判」
    //  ⇒ 这里改用**性质**：无论 tier 取什么值，禁用集恒等于disabledIds。
    test('C4 ★性质级：任意 tier 取值下禁用集恒等于 disabledIds', () {
      const tiers = [null, '', 'beginner', 'story', 'full', 'legacy_unknown'];
      for (final t in tiers) {
        final withTier = DiagnosisPrefs(disabledIds: {}, tier: t);
        expect(
          withTier.effectiveDisabledIds,
          isEmpty,
          reason: 'tier="$t" 不得凭空产生禁用项',
        );
        final withBoth = DiagnosisPrefs(disabledIds: {'P002'}, tier: t);
        expect(withBoth.effectiveDisabledIds, {
          'P002',
        }, reason: 'tier="$t" 不得改变用户手动关闭的集合');
        // ★ isDisabled 是禁用集的唯一查询入口。**必须扫全注册表**才能抓住
        //   「tier 偷偷让某个症候变成已关闭」—— 断言一个写死的
        //   `isDisabled('P001')==false` 会被「变异只针对 P003」躲过
        //   （实测负向验证 M3：单点断言全绿放行，改成全表扫描才变红）。
        //   ⚠️ 期望值须按「用户手动关闭集」算，**不能一律 false** ——
        //   本例 disabledIds={'P002'}，P002 本身就是 true；我第一版在
        //   全表扫描里对 P002 也断言 false ⇒ **断言自相矛盾**，
        //   负向验证脚本因此直接红在基线上（教训同§4-177：判据比被测
        //   对象更严 ⇒ 反向假 FAIL，先怀疑判据自己）。
        for (final rec in kSyndromeRegistry) {
          expect(
            withBoth.isDisabled(rec.id),
            withBoth.disabledIds.contains(rec.id),
            reason:
                'tier="$t" 下 ${rec.id} 的禁用态应恒等于'
                '「用户是否手动关闭它」（手动关闭集=${withBoth.disabledIds}）',
          );
        }
      }
    });
  });

  // ── D 组：与既有真链路的衔接 ──────────────────────────────
  group('D组 与 skillLevelForBeginner 同源', () {
    test('D1 换算出的层级 = 既有函数对同一 BeginnerLevel 的输出', () {
      for (final tier in ['beginner', 'story', 'full']) {
        final lv = resolveBeginnerLevelFromTier(
          tier: tier,
          beginnerLevel: null,
        )!;
        expect(
          skillLevelFromTier(tier),
          skillLevelForBeginner(lv),
          reason:
              'tier=$tier 的层级必须等于既有真链路的换算结果，'
              '否则会出现第二套层级口径',
        );
      }
    });

    test('D2 未设 tier 时 skillLevelFromTier 为 null（不擅自给层级）', () {
      expect(skillLevelFromTier(null), isNull);
      expect(skillLevelFromTier(''), isNull);
      expect(skillLevelFromTier('nonsense'), isNull);
    });
  });

  // ── E 组：属性级（不依赖 DB，证明映射本身可用）─────────────
  group('E组 映射结果与「新手/老手不同诊断库」的设计意图一致', () {
    test('E1 三档对应的层级确实分了三档（对应你的原始设计）', () {
      // 你的原话：「面对新手和老手是不一样的诊断库」——
      // 该设计已存在（kSyndromeSkillLevels L1–L5 + skillLevelForBeginner），
      // 只是没接到 UI 的 tier 上。本组断言「接上之后确实分档」。
      final lv = {
        'beginner': skillLevelFromTier('beginner'),
        'story': skillLevelFromTier('story'),
        'full': skillLevelFromTier('full'),
      };
      expect(lv['beginner'], SkillLevel.l1, reason: '「先写顺」= 只扫字句层 = L1 基础表达');
      expect(
        lv['story'],
        SkillLevel.l3,
        reason: '「完整故事」= 文字/角色/结构都管 = L3 角色塑造',
      );
      expect(lv['full'], SkillLevel.l4, reason: '「想被挑刺」= 含结构层与更高 = L4 情节结构');
    });

    test('E2 focus 排序上限随tier 变化（= 真能改变诊断侧重）', () {
      // `focus_resolver._preferLevelAppropriate` 用「当前层级+1」作上限；
      // 断言三档算出的上限**单调递增**——这是「老手看得更远」的可测形态。
      int maxLevelFor(String tier) => skillLevelFromTier(tier)!.index + 2;
      expect(maxLevelFor('beginner'), lessThan(maxLevelFor('full')));
    });

    test('E3 「想被挑刺」不被新手门控（isBeginner 应为 false）', () {
      // `_prepareTeachingState` 用 `level != n3 && level != n4` 判isBeginner；
      // tier='full' → n4 ⇒ 必须落在「非新手」侧，否则与层级自相矛盾。
      final lv = resolveBeginnerLevelFromTier(
        tier: 'full',
        beginnerLevel: null,
      )!;
      final isBeginner =
          lv != BeginnerLevel.n4Independent && lv != BeginnerLevel.n3Diagnose;
      expect(isBeginner, isFalse, reason: '选了「想被挑刺」却被当新手 ⇒ 门控与层级不一致');
    });

    test('E4 「先写顺」确实落在新手侧（反方向也验一次）', () {
      final lv = resolveBeginnerLevelFromTier(
        tier: 'beginner',
        beginnerLevel: null,
      )!;
      final isBeginner =
          lv != BeginnerLevel.n4Independent && lv != BeginnerLevel.n3Diagnose;
      expect(isBeginner, isTrue);
    });
  });
}
