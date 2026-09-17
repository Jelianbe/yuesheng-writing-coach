// ─────────────────────────────────────────────────────────────
// focus_resolver_discrimination_test — fallback 优先级表「判别性」补测
//
// 【来源】2026-09-17 mutation 全量审计（309 点 / 79 未检出）。focus_resolver
//   33/117 未检出中，**10 条落在真实业务逻辑**上，根因不是「没测到」而是
//   「原有用例的数据规模让不同代码路径**收敛到同一答案**」：
//   `_selectFallback` 的优先级 1/2/3 都归结为「选最高 severity + 层级软引导」，
//   而原用例的症候池单一（全 confirmed 或全 suspected、只 2 个元素），
//   于是 `==confirmed` 改成 `!=confirmed`、`b-a` 改成 `b+a` 都不改变结果。
//
// 【本文件做什么】用「判别性数据」让每条路径产出**不同**答案，锁死语义：
//   · confirmed 优先于更高 severity 的 suspected（5.4.2 优先级表）
//   · 同 severity 按 confirmedAt DESC
//   · 层级软引导的**边界**（恰好 level == 学员当前+1 时仍算合适）
//   · 越级者被跳过 ⇒ 选层级合适但 severity 较低者
//   · 用户覆盖绕过频繁切换降级（4.8 O5）
//   · 「原 focus 无效」的两种形态（rejected）
//
// 对应变异点：L102 / L106×2 / L141 / L145 / L146 / L147 / L235 / L282 / L388
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/services/focus_resolver.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 构造一个活跃症候视图
FocusProblem _fp(
  String id,
  Severity severity,
  ConfirmationStatus confirmationStatus,
  String status, {
  int? confirmedAt,
}) => FocusProblem(
  syndromeId: id,
  syndromeName: 'name-$id',
  severity: severity,
  confirmationStatus: confirmationStatus,
  status: status,
  confirmedAt: confirmedAt,
);

ResolveFocusInput _input({
  required List<FocusProblem> problems,
  String? aiSuggestedFocusId,
  String? userFocusOverride,
  TeachingSubphase? subphase,
  List<FocusHistoryEntry> focusHistory = const [],
  SkillLevel? studentSkillLevel,
}) => ResolveFocusInput(
  problems: problems,
  aiSuggestedFocusId: aiSuggestedFocusId,
  userFocusOverride: userFocusOverride,
  subphase: subphase,
  focusHistory: focusHistory,
  studentSkillLevel: studentSkillLevel,
);

void main() {
  // ── 5.4.2 优先级表：必须能区分「优先级 1 / 2」与「排序方向」 ──
  group('fallback 优先级表判别性（5.4.2）', () {
    test('1. confirmed 优先于 severity 更高的 suspected', () {
      // 若优先级 1 的筛选被反转（==confirmed → !=confirmed），会选走 suspected 的 P005
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l1, ConfirmationStatus.confirmed, 'active'),
            _fp('P005', Severity.l3, ConfirmationStatus.suspected, 'active'),
          ],
        ),
      );
      expect(out.source, FocusSource.fallback);
      expect(
        out.activatedFocusId,
        'P003',
        reason: '优先级 1（confirmed）必须先于优先级 2，即使 suspected 的 severity 更高',
      );
    });

    test('2. 同 severity 时按 confirmedAt DESC（较新者优先）', () {
      // 若 confirmedAt 比较被改成相加（`-` → `+`，恒正）或短路条件反转，会选走 P003
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp(
              'P003',
              Severity.l3,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 100,
            ),
            _fp(
              'P009',
              Severity.l3,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 200,
            ),
          ],
        ),
      );
      expect(
        out.activatedFocusId,
        'P009',
        reason: '同 severity ⇒ confirmedAt 更新的（200）胜出',
      );
    });

    test('3. 3 元素 severity 降序（高 severity 优先，其次 confirmedAt）', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp(
              'P003',
              Severity.l1,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 100,
            ),
            _fp(
              'P005',
              Severity.l3,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 50,
            ),
            _fp(
              'P009',
              Severity.l3,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 200,
            ),
          ],
        ),
      );
      expect(
        out.activatedFocusId,
        'P009',
        reason: 'l3 组内 confirmedAt 最大者胜出（排序方向反转会选到 P003/P005）',
      );
    });

    test('4. 无 confirmed 时走优先级 2（suspected）取最高 severity', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P004', Severity.l2, ConfirmationStatus.suspected, 'active'),
            _fp('P005', Severity.l3, ConfirmationStatus.suspected, 'active'),
          ],
        ),
      );
      expect(out.source, FocusSource.fallback);
      expect(out.activatedFocusId, 'P005', reason: 'suspected 中 severity 最高');
    });

    test('5. 同 severity 3 元素按 confirmedAt DESC（排序方向反转即失败）', () {
      // 全 l3 ⇒ severity 比较恒为 0 ⇒ 结果**完全**由 confirmedAt 比较决定。
      // 原：降序 ⇒ ca=300 在前；若被改成相加（恒正）⇒ 比较器恒「前者更大」⇒
      // 整体反转 ⇒ ca=100 跑到最前。
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp(
              'P003',
              Severity.l3,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 300,
            ),
            _fp(
              'P009',
              Severity.l3,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 200,
            ),
            _fp(
              'P004',
              Severity.l3,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 100,
            ),
          ],
        ),
      );
      expect(
        out.activatedFocusId,
        'P003',
        reason: 'ca=300 最新 ⇒ 应排第一（排序方向反转会选到 ca=100 的 P004）',
      );
    });
  });

  // ── 批次60 层级软引导：边界与越级跳过 ──
  group('层级软引导判别性（批次60）', () {
    test('6. 恰好 level == 学员当前+1 时仍算合适（<= 边界）', () {
      // 学员 L1（index 0）⇒ maxLevel = 2；P004 是 L2（index 1）⇒ 1+1 = 2，恰在边界内。
      // 若 `<=` 被收紧成 `<`，P004 会被误判越级 ⇒ 选走 P003。
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l1, ConfirmationStatus.confirmed, 'active'),
            _fp('P004', Severity.l3, ConfirmationStatus.confirmed, 'active'),
          ],
          studentSkillLevel: SkillLevel.l1,
        ),
      );
      expect(
        out.activatedFocusId,
        'P004',
        reason: 'L2 症候在学员 L1 下属于「当前+1」，应算合适而非越级',
      );
    });

    test('7. 越级者被跳过 ⇒ 选层级合适但 severity 较低者', () {
      // P005=L4 越级（severity l3 最高），P003=L1 合适（severity l2 较低）。
      // maxLevel 被算错（+2 → -2）或层级偏移被改（+1 → -1）都会选走 P005。
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l2, ConfirmationStatus.confirmed, 'active'),
            _fp('P005', Severity.l3, ConfirmationStatus.confirmed, 'active'),
          ],
          studentSkillLevel: SkillLevel.l1,
        ),
      );
      expect(
        out.activatedFocusId,
        'P003',
        reason: '层级软引导优先于 severity：越级的 L4 应被跳过',
      );
    });
  });

  // ── 分支条件：用户覆盖优先、原 focus 失效判定 ──
  group('分支条件判别性', () {
    test('8. 用户覆盖绕过频繁切换降级（4.8 O5）', () {
      final history = <FocusHistoryEntry>[
        FocusHistoryEntry(focusId: 'P009', timestamp: 300),
        FocusHistoryEntry(focusId: 'P004', timestamp: 200),
        FocusHistoryEntry(focusId: 'P007', timestamp: 100),
      ];
      expect(history.length, FocusSwitch.threshold, reason: '本用例依赖「历史长度正好达阈值」');
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l1, ConfirmationStatus.confirmed, 'active'),
            _fp('P009', Severity.l3, ConfirmationStatus.confirmed, 'active'),
          ],
          userFocusOverride: 'P003',
          focusHistory: history,
        ),
      );
      expect(
        out.activatedFocusId,
        'P003',
        reason: '用户明确指定症候时，频繁切换降级不得拦截（否则会回落到 P009）',
      );
      expect(out.source, FocusSource.userOverride);
    });

    test('9. 候选 resolved + 训练中 + AI 自主 ⇒ 不维持原 focus', () {
      // `training && hasUserOverride` 被放宽成 `||` 时，无用户覆盖也会进入
      // 「维持原 focus」分支 ⇒ 输出变成 P003 而非 fallback 的 P009。
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l1, ConfirmationStatus.confirmed, 'active'),
            _fp('P009', Severity.l3, ConfirmationStatus.confirmed, 'active'),
            _fp('P005', Severity.l2, ConfirmationStatus.confirmed, 'resolved'),
          ],
          aiSuggestedFocusId: 'P005',
          subphase: TeachingSubphase.practice,
          focusHistory: [
            const FocusHistoryEntry(focusId: 'P003', timestamp: 100),
          ],
        ),
      );
      expect(
        out.activatedFocusId,
        'P009',
        reason: 'AI 自主建议了一个已 resolved 的焦点 ⇒ 走 fallback（P009 最高 severity）',
      );
    });

    test('10. 训练中「原 focus 被 rejected」⇒ 不维持（无效判定不被放宽）', () {
      // `_maintainPreviousFocus` 的 `||` 若被改成 `&&`，rejected 的原 focus 会被
      // 误判为「有效」而继续维持 ⇒ 输出变成 P003 而非 fallback 的 P009。
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l1, ConfirmationStatus.rejected, 'active'),
            _fp('P009', Severity.l3, ConfirmationStatus.confirmed, 'active'),
            _fp('P004', Severity.l2, ConfirmationStatus.confirmed, 'active'),
          ],
          aiSuggestedFocusId: 'P004',
          subphase: TeachingSubphase.practice,
          focusHistory: [
            const FocusHistoryEntry(focusId: 'P003', timestamp: 100),
          ],
        ),
      );
      expect(
        out.activatedFocusId,
        'P009',
        reason: '原 focus 已被 rejected ⇒ 不得维持；应回落到 fallback 的 P009',
      );
    });
  });
}
