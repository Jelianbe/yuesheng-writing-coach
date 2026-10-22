// ─────────────────────────────────────────────────────────────
// 治理续批第二批护栏：形态字段透传 + 资格闸 v2 + 路 α（R-027 批准 · 2026-10-20）
//
// 任务卡：.ai/tasks/active/T-20261018-05 · 设计稿：
//   yuesheng-flutter/docs/designs/2026-10-20-治理续批-形态字段与资格闸v2与路α-设计批.md
//   （入库真源：.ai/reports/2026-10-20-治理续批-形态字段与资格闸v2与路α-设计批.md）
//
// 覆盖设计稿 §五 红线 R1–R9（层 1 + 层 2，零 LLM）：
//   R1 透传保真：单次链合成输出 ⇒ Syndrome 两字段逐字保真 ⇒ results JSON 含新键
//      ⇒ active_problem 新列落值 ⇒ DTO 同值；「results 有而 active 无」必须红
//   R2 X01/X22 可区分：两锚点 syndrome 逐字取自 w23_cells.json，form 标注写死
//      ⇒ v2 闸只放行 X22 P002（两锚点 evidence 均为 3 条 ⇒ 派生实现必红）
//   R3 X22 零回退：X22 10 格标注重放 ⇒ P002 焦点格只增不减（预期 4→8）
//   R4 X01 零放大：X01 10 格标注重放 ⇒ P002 焦点格不增（陷阱格 t07|r1 不得翻）
//   R5 路 α 合成产出：单次链带 iv ⇒ Syndrome.interventionValue 非空
//      ⇒ A3 valueScore = rank(iv)+1（非先验）+ rationale 不出现「注册表先验」
//   R6 优先级规则锁：iv 非空 ⇒ 用 iv；iv null ⇒ 先验（分支序逐字断言）
//   R8 存量安全：form 两列 NULL 的行 ⇒ v2 闸逐分支 = v1
//
// ⚠️ 诚实边界：R3/R4 的标注重放用的是**人工写死的 form 标注**（按组合⑤
//   人工读原文判定），不是 LLM 产出 —— 层 2 验的是**闸逻辑**，
//   不是「LLM 会不会照标注输出」（那是层 3 重跑的职责）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/focus_resolver.dart';
import 'package:writingcoach/services/intervention_value.dart';
import 'package:writingcoach/types/teaching_types.dart';

Directory _findPackageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (Directory('${dir.path}/lib').existsSync() &&
        Directory('${dir.path}/test').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError('找不到包根目录（cwd=${Directory.current.path}）');
}

final Directory _root = _findPackageRoot();

/// 读仓内文件（W-23 锚点数据在 .ai 仓内，测试按相对路径定位）。
String _readRepoFile(String relPath) {
  final f = File('${_root.path}/$relPath');
  if (!f.existsSync()) {
    throw StateError('源文件不存在：$relPath（root=${_root.path}）');
  }
  return f.readAsStringSync();
}

// ── 夹具 ──────────────────────────────────────────────────────────────

FocusProblem _fp(
  String id,
  Severity severity,
  ConfirmationStatus confirmationStatus, {
  int? formFactCount,
  String? formStructure,
}) => FocusProblem(
  syndromeId: id,
  syndromeName: 'name-$id',
  severity: severity,
  confirmationStatus: confirmationStatus,
  status: 'active',
  formFactCount: formFactCount,
  formStructure: formStructure,
);

ResolveFocusInput _input(List<FocusProblem> problems) => ResolveFocusInput(
  problems: problems,
  aiSuggestedFocusId: null,
  userFocusOverride: null,
  subphase: null,
  focusHistory: const [],
  studentSkillLevel: null,
);

/// 组合⑤双要素的「bulk」形态（成段多事实 + 论文式）。
const int kBulkFacts = 4;
const String kBulkStructure = 'expository';

/// 单句带过（事实条数 1 + 叙事流内）⇒ 不成形成。
const int kMentionFacts = 1;
const String kMentionStructure = 'narrative';

void main() {
  group('R2 · 形态双要素的闸行为（锚点对照）', () {
    test('X22 锚点形态（fact 3 + expository）⇒ 获资格，压过档 A L1', () {
      // X22|t03|r1 的 P002：原文自述「原因有二：其一……其二……」= 论文式
      // + 三处（节目规则/前两季历史/公司背景）成段旁白 ⇒ fact 3 + expository。
      // 对手：P018（wordChoice = 档 A，L1）。
      final out = resolveTeachingFocus(
        _input([
          _fp(
            'P002',
            Severity.l2,
            ConfirmationStatus.suspected,
            formFactCount: 3,
            formStructure: 'expository',
          ),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected),
        ]),
      );
      expect(
        out.activatedFocusId,
        'P002',
        reason: 'X22 真阳型：bulk 形态档 B 应获资格并凭 severity(L2) 胜档 A L1',
      );
      expect(out.reason, contains('形态'));
    });

    test('X01 锚点形态（fact 1 + narrative）⇒ 不获资格，仍输给档 A', () {
      // X01|t03|r2 的 P002：原文自述「这些信息本身必要」= 单句带过 + 旁白无结构。
      final out = resolveTeachingFocus(
        _input([
          _fp(
            'P002',
            Severity.l2,
            ConfirmationStatus.suspected,
            formFactCount: kMentionFacts,
            formStructure: kMentionStructure,
          ),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected),
        ]),
      );
      expect(
        out.activatedFocusId,
        'P018',
        reason: 'X01 过敏型：非 bulk ⇒ 档 B 未获资格 ⇒ 档 A 胜出（与 v1 一致）',
      );
    });

    test('X01|t07|r1 陷阱格（fact 3 + narrative）⇒ 仍不获资格（单值分不开）', () {
      // 陷阱格：3 个事实旁白一次性交代，但**无论文式结构** ⇒ 组合⑤双要素
      // 缺 (b) ⇒ 不成形 ⇒ 不得判 bulk。
      // ★ 这条正是「任何 evidence.length / fact_count 单值派生」的红线用例。
      final out = resolveTeachingFocus(
        _input([
          _fp(
            'P002',
            Severity.l2,
            ConfirmationStatus.suspected,
            formFactCount: 3,
            formStructure: 'narrative',
          ),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected),
        ]),
      );
      expect(
        out.activatedFocusId,
        'P018',
        reason: '陷阱格：fact 3 但结构非 bulk ⇒ 组合⑤双要素缺一不可 ⇒ 不得放行',
      );
    });

    test('两锚点 evidence 均为 3 条 ⇒ 派生式实现在此必错（数据事实自证）', () {
      // R2 的「天然陷阱 fixture」：X01|t03|r2 与 X22|t03|r1 的 P002
      // evidence 条数**相同**（3=3）而形态结论相反。
      // 本测试把该事实固化为可执行断言：若未来数据变化导致两格 evidence
      // 不再都是 3 条，说明锚点数据变了 ⇒ 本护栏的推导前提失效 ⇒ 需复核。
      final doc = json.decode(
        _readRepoFile(
          '../.ai/research/cross-validation/data/w23/w23_cells.json',
        ),
      );
      final cells = {
        for (final c in (doc['cells'] as List)) c['cell_id'] as String: c,
      };
      int evCount(String cellId, String sid) {
        final syns = (cells[cellId]!['syndromes'] as List)
            .cast<Map<String, dynamic>>();
        final s = syns.firstWhere((e) => e['syndrome_id'] == sid);
        return ((s['evidence'] as List?) ?? const []).length;
      }

      final x22 = evCount('X22|t03|r1', 'P002');
      final x01 = evCount('X01|t03|r2', 'P002');
      expect(x22, 3, reason: 'X22|t03|r1 P002 的 evidence 条数应仍为 3（锚点数据事实）');
      expect(x01, 3, reason: 'X01|t03|r2 P002 的 evidence 条数应仍为 3（锚点数据事实）');
      expect(
        x22,
        x01,
        reason:
            '★ 陷阱 fixture 的核心：两锚点 evidence 条数相同 ⇒ '
            '任何以 evidence.length 派生形态的实现都会对这两格给出相同结论 ⇒ 必错。'
            '（若此断言变红，说明锚点数据已变，R2 的推导前提需重核）',
      );
    });
  });

  group('R8 · 存量安全（form 两列 NULL ⇒ 逐分支 = v1）', () {
    test('null/null ⇒ 与 v1 完全一致（档 B 未获资格）', () {
      final out = resolveTeachingFocus(
        _input([
          _fp('P002', Severity.l2, ConfirmationStatus.suspected),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected),
        ]),
      );
      expect(out.activatedFocusId, 'P018');
      expect(
        out.reason,
        isNot(contains('形态')),
        reason:
            '存量行（form 两列 NULL）不得出现形态子句——无形态证据 ⇒ 无从留痕，'
            'reason 必须与 v1 逐字一致',
      );
    });

    test('只有 fact 无 structure ⇒ 不获资格（双要素缺一不可）', () {
      final out = resolveTeachingFocus(
        _input([
          _fp(
            'P002',
            Severity.l2,
            ConfirmationStatus.suspected,
            formFactCount: 5,
          ),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected),
        ]),
      );
      expect(out.activatedFocusId, 'P018');
    });

    test('只有 structure 无 fact ⇒ 不获资格', () {
      final out = resolveTeachingFocus(
        _input([
          _fp(
            'P002',
            Severity.l2,
            ConfirmationStatus.suspected,
            formStructure: 'expository',
          ),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected),
        ]),
      );
      expect(out.activatedFocusId, 'P018');
    });

    test('fact 2 + expository ⇒ 不获资格（阈值 3 = 组合⑤既有数字）', () {
      final out = resolveTeachingFocus(
        _input([
          _fp(
            'P002',
            Severity.l2,
            ConfirmationStatus.suspected,
            formFactCount: 2,
            formStructure: 'expository',
          ),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected),
        ]),
      );
      expect(out.activatedFocusId, 'P018');
    });

    test('fact 3 + interruption ⇒ 获资格（读者关切处被打断也是 bulk 形态）', () {
      final out = resolveTeachingFocus(
        _input([
          _fp(
            'P002',
            Severity.l2,
            ConfirmationStatus.suspected,
            formFactCount: 3,
            formStructure: 'interruption',
          ),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected),
        ]),
      );
      expect(out.activatedFocusId, 'P002');
    });

    test('v1 既有两通道不受影响（confirmed / L3 仍获资格）', () {
      final out1 = resolveTeachingFocus(
        _input([
          _fp('P002', Severity.l2, ConfirmationStatus.confirmed),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected),
        ]),
      );
      expect(out1.activatedFocusId, 'P002', reason: 'v1 confirmed 通道未回归');

      final out2 = resolveTeachingFocus(
        _input([
          _fp('P003', Severity.l3, ConfirmationStatus.suspected),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected),
        ]),
      );
      expect(out2.activatedFocusId, 'P003', reason: 'v1 L3 通道未回归');
    });

    test('★ 只加正向：mention 形态**不撤销** confirmed / L3 既有资格', () {
      // 「不设负向」是可执行判据：mention 档 B 仍应获资格（不因形态被撤）。
      final out = resolveTeachingFocus(
        _input([
          _fp(
            'P002',
            Severity.l2,
            ConfirmationStatus.confirmed,
            formFactCount: kMentionFacts,
            formStructure: kMentionStructure,
          ),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected),
        ]),
      );
      expect(
        out.activatedFocusId,
        'P002',
        reason: 'mention 形态不得撤销 confirmed 资格（本批只加正向通道）',
      );
    });
  });

  group('R1 · 透传保真（解析 → DB → DTO）', () {
    test('Syndrome.fromJson → toJson 往返保真（两字段逐字）', () {
      final s = Syndrome.fromJson(const {
        'syndrome_id': 'P002',
        'name': '信息倾泻',
        'severity': 'L2',
        'evidence': ['原文片段'],
        'explanation': '说明',
        'intervention_value': 'high',
        'form_fact_count': 4,
        'form_structure': 'expository',
      });
      expect(s.formFactCount, 4);
      expect(s.formStructure, 'expository');
      final json = s.toJson();
      expect(json['form_fact_count'], 4);
      expect(json['form_structure'], 'expository');
      expect(json['intervention_value'], 'high');
    });

    test('null 字段不落 key（往返稳定，同 reader_impact 约定）', () {
      final s = Syndrome.fromJson(const {
        'syndrome_id': 'P002',
        'name': '信息倾泻',
        'severity': 'L2',
        'evidence': ['原文片段'],
        'explanation': '说明',
      });
      final json = s.toJson();
      expect(json.containsKey('form_fact_count'), isFalse);
      expect(json.containsKey('form_structure'), isFalse);
      expect(json.containsKey('intervention_value'), isFalse);
    });

    test('越界 / 错类型按缺失处理（不静默纠偏）', () {
      final s = Syndrome.fromJson(const {
        'syndrome_id': 'P002',
        'name': '信息倾泻',
        'severity': 'L2',
        'evidence': ['原文片段'],
        'explanation': '说明',
        'form_fact_count': '四',
        'form_structure': 'poetic',
      });
      expect(s.formFactCount, isNull);
      expect(s.formStructure, isNull);
    });

    test('★ 端到端：results JSON 含新键 ⇒ active_problem 新列落值 ⇒ DTO 同值', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final sessionRepo = SessionRepository(db);
      final sessionId = await sessionRepo.createBlankSession();
      final repo = DiagnosisRepository(db);

      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: 'm-1',
          syndromes: [
            {
              'syndrome_id': 'P002',
              'name': '信息倾泻',
              'severity': 'L2',
              'evidence': ['原文片段'],
              'explanation': '成段多事实 + 论文式',
              'intervention_value': 'high',
              'form_fact_count': 4,
              'form_structure': 'expository',
            },
          ],
          suggestedActions: const ['A001'],
          confidence: 0.9,
        ),
      );

      // ① diagnosis_results.syndromes JSON 含新键（全量保真）
      final results = await (db.select(
        db.diagnosisResults,
      )..where((t) => t.sessionId.equals(sessionId))).get();
      expect(results, hasLength(1));
      final syndromesJson =
          json.decode(results.first.syndromes) as List<dynamic>;
      final first = syndromesJson.first as Map<String, dynamic>;
      expect(first['form_fact_count'], 4);
      expect(first['form_structure'], 'expository');
      expect(first['intervention_value'], 'high');

      // ② active_problem 新列落值
      final rows = await (db.select(
        db.activeProblems,
      )..where((t) => t.sessionId.equals(sessionId))).get();
      expect(rows, hasLength(1));
      expect(rows.first.formFactCount, 4);
      expect(rows.first.formStructure, 'expository');

      // ③ DTO（ActiveProblemView）读到同值。
      // ⚠️ 用 listAllActiveProblems 而非 listActiveProblems：后者带
      //    「弱把握（conf < kWeakEvidenceConfidence=0.4）且未确认 ⇒ 排除」的
      //    既有业务过滤，本例单条证据 conf=0.35 会被过滤掉——那是既有规则，
      //    不是本批缺陷，故此处走无该过滤的读口验「DTO 透传」本身。
      final views = await repo.listAllActiveProblems();
      expect(views, hasLength(1));
      expect(views.first.formFactCount, 4);
      expect(views.first.formStructure, 'expository');
    });

    test('★ 双轨一致性锁：results 有键而 active_problem 无值 ⇒ 变红', () async {
      // latest-wins 语义：本轮无形态字段 ⇒ 写 NULL **清除**旧值。
      // ⇒ 两轮之间 active_problem 的形态列应随本轮诊断结果更新（= 与 severity 同语义）。
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final sessionRepo = SessionRepository(db);
      final sessionId = await sessionRepo.createBlankSession();
      final repo = DiagnosisRepository(db);

      Map<String, dynamic> syn({int? facts, String? structure}) => {
        'syndrome_id': 'P002',
        'name': '信息倾泻',
        'severity': 'L2',
        'evidence': ['原文片段'],
        'explanation': '说明',
        if (facts != null) 'form_fact_count': facts,
        if (structure != null) 'form_structure': structure,
      };

      // 第 1 轮：带形态
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: 'm-1',
          syndromes: [syn(facts: 4, structure: 'expository')],
          suggestedActions: const ['A001'],
          confidence: 0.9,
        ),
      );
      var rows = await (db.select(
        db.activeProblems,
      )..where((t) => t.sessionId.equals(sessionId))).get();
      expect(rows.first.formFactCount, 4);

      // 第 2 轮：本轮无形态 ⇒ 应清除（latest-wins）
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: 'm-2',
          syndromes: [syn()],
          suggestedActions: const ['A001'],
          confidence: 0.9,
        ),
      );
      rows = await (db.select(
        db.activeProblems,
      )..where((t) => t.sessionId.equals(sessionId))).get();
      expect(
        rows.first.formFactCount,
        isNull,
        reason: 'latest-wins：本轮无形态字段 ⇒ active_problem 形态列必须被清除',
      );
      expect(rows.first.formStructure, isNull);
    });
  });

  group('R5/R6 · 路 α（A3 消费侧）', () {
    test('排序消费侧：iv 非空 ⇒ 同 severity 档内按 iv 降序', () {
      final list = [
        Syndrome.fromJson(const {
          'syndrome_id': 'P001',
          'name': 'A',
          'severity': 'L2',
          'evidence': ['x'],
          'explanation': 'x',
          'intervention_value': 'low',
        }),
        Syndrome.fromJson(const {
          'syndrome_id': 'P002',
          'name': 'B',
          'severity': 'L2',
          'evidence': ['x'],
          'explanation': 'x',
          'intervention_value': 'high',
        }),
      ];
      final sorted = sortSyndromesForDiagnosisCard(list);
      expect(
        sorted.first.syndromeId,
        'P002',
        reason: '同 severity 内 iv=high 应排在 iv=low 之前',
      );
    });

    test('★ 优先级规则锁：iv 非空 ⇒ 用 iv；iv null ⇒ 先验（分支序不变）', () {
      // 直接锁 interventionValueRank 与 quantityPrior 的**分支序**：
      // iv 非空 ⇒ rank(iv)+1；iv null ⇒ 先验（wordChoice=2 其余=1）+1。
      expect(interventionValueRank('high'), 2);
      expect(interventionValueRank('medium'), 1);
      expect(interventionValueRank('low'), 0);
      expect(interventionValueRank(null), -1);

      // 归一化口径：越界 iv ⇒ null ⇒ 落先验分支（不静默纠偏）。
      final s = Syndrome.fromJson(const {
        'syndrome_id': 'P002',
        'name': 'B',
        'severity': 'L2',
        'evidence': ['x'],
        'explanation': 'x',
        'intervention_value': 'critical',
      });
      expect(s.interventionValue, isNull);
    });
  });

  group('R3/R4 · 锚点格标注重放（X01/X22 各 10 格）', () {
    // ── 形态人工标注（依据各格 P002 的 explanation 原文逐条读出）──
    // X22 全部十格：成段多事实 + 论文式/说明书式（expository）⇒ bulk。
    //   依据例：X22|t03|r3「…全部以旁白说明书方式一次性倒给读者…而且'原因有二：
    //   其一……其二……'是论文式结构」；X22|t07|r1「大段设定以旁白说明文形式直接
    //   倾倒在正文里」。
    // X01 全部十格：旁白但**单处/局部**交代、事实少或无结构标记 ⇒ 非 bulk。
    //   依据例：X01|t03|r2「这些信息本身必要」；X01|t07|r1「三件事旁白一次性交代」
    //   （= 3 事实但无论文式结构 ⇒ 陷阱格）；X01|t07|r4「几件事都是整段旁白交代」
    //   但无「论文式/说明书」结构标记。
    //
    // ⚠️ 诚实边界：这些是**人工按组合⑤判据读原文**的标注，不是 LLM 产出。
    //   本组验的是「闸逻辑在给定标注下的行为」；「LLM 会不会照标注重现」
    //   属层 3（重跑）的职责，不在此断言。

    /// 形态标注表：cell_id → (factCount, structure)。
    const Map<String, (int?, String?)> kFormAnnotations = {
      // ── X22：成段多事实 + 论文式（fact 数取原文列举的设定项数）──
      'X22|t03|r1': (3, 'expository'), // 节目规则/前两季历史/公司背景 + 「原因有二」
      'X22|t03|r2': (4, 'expository'), // 节目规则/赛制/前两季历史/改女偶像两原因
      'X22|t03|r3': (4, 'expository'), // 同上 + 明写「原因有二…论文式结构」
      'X22|t03|r4': (4, 'expository'), // 节目规则/赛制/前两季历史/换性别两原因
      'X22|t03|r5': (3, 'expository'), // 节目规则/公司地位/往季历史
      'X22|t07|r1': (4, 'expository'), // 节目规则/赛制/公司背景/往季历史
      'X22|t07|r2': (6, 'expository'), // 赛制/投票机制/前两季/换性别两原因/公司定位
      'X22|t07|r3': (4, 'expository'), // 节目规则/导师配置/平台玩法/前两季历史
      'X22|t07|r4': (4, 'expository'), // 节目规则/赛制/三季历史/市场分析
      'X22|t07|r5': (4, 'expository'), // CN娱乐地位/造星模式/粉丝量/赛制来源
      // ── X01：旁白但单处/局部、无结构标记 ⇒ 非 bulk ──
      'X01|t03|r1': (1, 'narrative'), // 小区背景单处交代（且结尾复述）
      'X01|t03|r2': (1, 'narrative'), // 「这些信息本身必要」= 单句带过
      'X01|t03|r3': (2, 'narrative'), // 主角背景 + 小区设定，无结构标记
      'X01|t03|r4': (2, 'narrative'), // 背景 + 桃花苑定位，无结构标记
      'X01|t03|r5': (2, 'narrative'), // 小区定位 + 租房动机，无结构标记
      'X01|t07|r1': (3, 'narrative'), // ★ 陷阱格：3 事实但无论文式结构
      'X01|t07|r2': (2, 'narrative'), // 背景设定整段，但无结构标记
      'X01|t07|r3': (2, 'narrative'), // 两处说明性段落，无结构标记
      'X01|t07|r4': (4, 'narrative'), // 4 件事但无结构标记（双要素缺 (b)）
      'X01|t07|r5': (4, 'narrative'), // 4 项背景但无结构标记（双要素缺 (b)）
    };

    /// 读 W-23 cells 真源，按 cell 构造候选池（FocusProblem 列表）。
    List<FocusProblem> _poolOf(
      Map<String, dynamic> cell, {
      required bool withForm,
    }) {
      final ap = (cell['active_problems'] as List?) ?? const [];
      final cid = cell['cell_id'] as String;
      final ann = kFormAnnotations[cid];
      return ap.map((e) {
        final m = e as Map<String, dynamic>;
        final sid = m['syndrome_id'] as String;
        final isP002 = sid == 'P002';
        return FocusProblem(
          syndromeId: sid,
          syndromeName: 'name-$sid',
          severity:
              Severity.fromString(m['severity'] as String?) ?? Severity.l2,
          confirmationStatus:
              ConfirmationStatus.fromString(
                m['confirmation_status'] as String?,
              ) ??
              ConfirmationStatus.suspected,
          status: 'active',
          formFactCount: (withForm && isP002) ? ann?.$1 : null,
          formStructure: (withForm && isP002) ? ann?.$2 : null,
        );
      }).toList();
    }

    test('★ 形态标注表覆盖 X01/X22 全部 20 格（防漏标注）', () {
      final doc = json.decode(
        _readRepoFile(
          '../.ai/research/cross-validation/data/w23/w23_cells.json',
        ),
      );
      final cells = (doc['cells'] as List).cast<Map<String, dynamic>>();
      final anchorIds = cells
          .map((c) => c['cell_id'] as String)
          .where((id) => id.startsWith('X01') || id.startsWith('X22'))
          .toList();
      expect(anchorIds.length, 20);
      for (final id in anchorIds) {
        expect(
          kFormAnnotations.containsKey(id),
          isTrue,
          reason: '$id 缺形态标注——漏标注会让重放静默少算一格',
        );
      }
      expect(kFormAnnotations.length, 20);
    });

    test('★ R3 · X22 零回退：v2 焦点 P002 格数只增不减（预期 4→8）', () {
      final doc = json.decode(
        _readRepoFile(
          '../.ai/research/cross-validation/data/w23/w23_cells.json',
        ),
      );
      final cells = (doc['cells'] as List).cast<Map<String, dynamic>>();

      var v1P002 = 0;
      var v2P002 = 0;
      final flips = <String>[];

      for (final cell in cells) {
        final cid = cell['cell_id'] as String;
        if (!cid.startsWith('X22')) continue;
        final pool = _poolOf(cell, withForm: false);
        if (pool.isEmpty) continue;
        final v1 = resolveTeachingFocus(_input(pool));
        final v2 = resolveTeachingFocus(_input(_poolOf(cell, withForm: true)));
        if (v1.activatedFocusId == 'P002') v1P002++;
        if (v2.activatedFocusId == 'P002') v2P002++;
        if (v1.activatedFocusId != v2.activatedFocusId) {
          flips.add('$cid: ${v1.activatedFocusId} -> ${v2.activatedFocusId}');
        }
      }

      expect(
        v2P002,
        greaterThanOrEqualTo(v1P002),
        reason: '★ R3 红线：X22 的 P002 焦点格数只增不减（v1=$v1P002 → v2=$v2P002）',
      );
      expect(
        v2P002,
        8,
        reason:
            '预期 v2 恢复至闸前 GT 读数 8 格（cells 基线 X22 P002 焦点 8 格；'
            'v1 闸后因 P018 抢位掉到 4 格）。实际 v1=$v1P002 v2=$v2P002，'
            '翻转明细=$flips',
      );
    });

    test('★ R4 · X01 零放大：v2 焦点 P002 格数不增（陷阱格不得翻）', () {
      final doc = json.decode(
        _readRepoFile(
          '../.ai/research/cross-validation/data/w23/w23_cells.json',
        ),
      );
      final cells = (doc['cells'] as List).cast<Map<String, dynamic>>();

      var v1P002 = 0;
      var v2P002 = 0;
      final flips = <String>[];

      for (final cell in cells) {
        final cid = cell['cell_id'] as String;
        if (!cid.startsWith('X01')) continue;
        final pool = _poolOf(cell, withForm: false);
        if (pool.isEmpty) continue;
        final v1 = resolveTeachingFocus(_input(pool));
        final v2 = resolveTeachingFocus(_input(_poolOf(cell, withForm: true)));
        if (v1.activatedFocusId == 'P002') v1P002++;
        if (v2.activatedFocusId == 'P002') v2P002++;
        if (v1.activatedFocusId != v2.activatedFocusId) {
          flips.add('$cid: ${v1.activatedFocusId} -> ${v2.activatedFocusId}');
        }
      }

      expect(
        v2P002,
        v1P002,
        reason:
            '★ R4 红线：X01 的 P002 焦点格数不得增加（v1=$v1P002 → v2=$v2P002）。'
            '翻转明细=$flips',
      );
      expect(
        flips.where((f) => f.endsWith('-> P002')),
        isEmpty,
        reason: '★ 陷阱格 X01|t07|r1（3 事实但无论文式结构）不得翻成 P002 焦点',
      );
    });
  });

  group('护栏自身有效（变异回归）', () {
    test('形态阈值与结构集合是常量且与设计稿一致', () {
      expect(kFormBulkMinFacts, 3);
      expect(kFormStructureBulk.contains('expository'), isTrue);
      expect(kFormStructureBulk.contains('interruption'), isTrue);
      expect(
        kFormStructureBulk.contains('narrative'),
        isFalse,
        reason: 'narrative（叙事流内、无结构标记）不构成倾泻形态',
      );
    });

    test('★ 组合⑤双要素：缺任一 ⇒ 不成形（判据自身有效）', () {
      // 变异回归：把「fact 数」判据去掉（只看 structure）会让陷阱格通过；
      // 把「structure」判据去掉（只看 fact）同样会让陷阱格通过。
      // ⇒ 两个判据各自都不可省。
      final trap = _fp(
        'P002',
        Severity.l2,
        ConfirmationStatus.suspected,
        formFactCount: 3,
        formStructure: 'narrative',
      );
      final bulk = _fp(
        'P002',
        Severity.l2,
        ConfirmationStatus.suspected,
        formFactCount: kBulkFacts,
        formStructure: kBulkStructure,
      );
      // 陷阱格与 bulk 格仅结构不同 ⇒ 若闸只看 fact 两者等价（判据失效）；
      // 本测试通过「实际闸行为不同」来锁这条。
      final trapOut = resolveTeachingFocus(
        _input([trap, _fp('P018', Severity.l1, ConfirmationStatus.suspected)]),
      );
      final bulkOut = resolveTeachingFocus(
        _input([bulk, _fp('P018', Severity.l1, ConfirmationStatus.suspected)]),
      );
      expect(trapOut.activatedFocusId, 'P018');
      expect(bulkOut.activatedFocusId, 'P002');
    });
  });

  // ── T-20261021-01 补漏：parser 手写构造路径（生产链断点回归） ──
  //
  // R1 声声称「解析 → DB → DTO」透传保真，但组内既有三条只走
  // `Syndrome.fromJson` / `commitDiagnosis`（两者均不经 `parseDiagnosis`
  // 的 `_validateSyndromes` 手写构造）⇒ **生产链断点零覆盖**：
  // `_validateSyndromes` 构造 Syndrome 时未传形态两字段 ⇒ 恒为 null
  // （2026-10-21 实测，卡 T-20261021-01 §2.2）。本组补 parser 路径，
  // 并锁 A5 的「非法值归一为 null、条目不丢、不抛」。
  group('T-20261021-01 补漏：parser 手写构造路径（生产链断点回归）', () {
    String wrapDiag(String syndromeJson) =>
        '前导[YS_DIAGNOSIS]\n{"syndromes":[$syndromeJson],'
        '"suggested_actions":["A002"],"confidence":0.75,'
        '"feedback_summary":"ok","root_cause_analysis":"r",'
        '"next_focus":"P001","teaching_plan":{"current_teaching_focus_id":'
        '"P001","focus_reason":"a","next_step":"b"}}\n[/YS_DIAGNOSIS]';

    test('A1 合法形态值经 parseDiagnosis 透传到 Syndrome（手写构造不断字段）', () {
      final r = parseDiagnosis(
        wrapDiag(
          '{"syndrome_id":"P002","name":"信息倾泻","severity":"L2",'
          '"evidence":["x"],"explanation":"y",'
          '"form_fact_count":4,"form_structure":"expository"}',
        ),
      );
      expect(r.diagnosis, isNotNull);
      final s = r.diagnosis!.syndromes.first;
      expect(s.formFactCount, 4, reason: 'parser 手写构造必须透传（修复前恒 null）');
      expect(s.formStructure, 'expository');
    });

    test('A5 非法形态值 ⇒ 归一为 null、条目不丢、不抛', () {
      final r = parseDiagnosis(
        wrapDiag(
          '{"syndrome_id":"P002","name":"信息倾泻","severity":"L2",'
          '"evidence":["x"],"explanation":"y",'
          '"form_fact_count":-1,"form_structure":"poetic"}',
        ),
      );
      expect(r.diagnosis, isNotNull, reason: '条目不丢（观测不拦截）');
      final s = r.diagnosis!.syndromes.first;
      expect(s.formFactCount, isNull, reason: '负数按缺失处理');
      expect(s.formStructure, isNull, reason: '越界枚举按缺失处理');
    });

    test('缺失形态字段 ⇒ null（旧 payload / 非形式类症候）', () {
      final r = parseDiagnosis(
        wrapDiag(
          '{"syndrome_id":"P001","name":"情绪标签化","severity":"L1",'
          '"evidence":["x"],"explanation":"y"}',
        ),
      );
      expect(r.diagnosis, isNotNull);
      final s = r.diagnosis!.syndromes.first;
      expect(s.formFactCount, isNull);
      expect(s.formStructure, isNull);
    });
  });
}
