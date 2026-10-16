// ───────────────────────────────────────────────
// W-22 G1/G3 · 诊断卡「候选焦点」区护栏
//
// 设计批：候选 = W-21 A3 产物经 payload 接用户侧；改选 = 对目标症候
// confirmDiagnosis（severity 传该行现值 ⇒ 零升级）；不在池 ⇒ 明确反馈
// （施工期修正三：点击时校验，非预查禁用）。
// harness 对齐 w15_b_pending_badge_test.dart + diagnosis_card_test.dart
// （ProviderScope + 内存 drift DB）。
// ───────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/diagnosis_service.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(
          // 展开详情区内容超出测试视口 ⇒ SingleChildScrollView（同
          // diagnosis_card_test 既有模式；overflow 会记 rendering 失败）。
          body: SingleChildScrollView(child: child),
        ),
      ),
    );

const _kCandidateTitle = '候选焦点';
const _kSwitchLabel = '选为焦点';
const _kSwitchedLabel = '已选为焦点';

DiagnosisCard _card({
  List<FocusCandidateCard>? candidates,
  String? sessionId,
}) => DiagnosisCard(
  syndromeCount: 1,
  syndromes: const [
    DiagnosisSyndromeCard(
      syndromeId: 'P001',
      name: '情绪标签化',
      severity: 'L2',
      evidenceCount: 1,
    ),
  ],
  suggestedActions: const [],
  confidence: 0.9,
  defaultExpanded: true,
  sessionId: sessionId,
  focusCandidates: candidates,
);

const _kCandidates = [
  FocusCandidateCard(
    syndromeId: 'P001',
    name: '情绪标签化',
    total: 7,
    rationale: 'P001：严重度 L2(2) · 干预价值 high(3) · 跨 2 章独立出现(2) ⇒ 7',
  ),
  FocusCandidateCard(
    syndromeId: 'P003',
    name: '视角漂移',
    total: 5,
    rationale: 'P003：严重度 L1(1) · 干预价值 未评定(1) · 跨 3 章独立出现(3) ⇒ 5',
  ),
];

void main() {
  // ── 渲染面 ──

  testWidgets('候选在场 ⇒ 渲染候选区（标题/名称/分解说明/按钮）', (tester) async {
    await tester.pumpWidget(_wrap(_card(candidates: _kCandidates)));
    expect(find.text(_kCandidateTitle), findsOneWidget);
    // 「情绪标签化」3 处：症候块标题 + 症候详情 + 候选行（阳性对照：候选区在场）
    expect(find.text('情绪标签化'), findsNWidgets(3));
    expect(find.text('视角漂移'), findsOneWidget);
    expect(find.textContaining('严重度 L2(2)'), findsOneWidget);
    expect(find.text(_kSwitchLabel), findsNWidgets(2));
  });

  testWidgets('候选为 null（未接线/旧消息）⇒ 候选区不渲染', (tester) async {
    await tester.pumpWidget(_wrap(_card()));
    expect(find.text(_kCandidateTitle), findsNothing);
    expect(find.text(_kSwitchLabel), findsNothing);
  });

  testWidgets('候选为空列表 ⇒ 候选区不渲染（不造空区）', (tester) async {
    await tester.pumpWidget(_wrap(_card(candidates: const [])));
    expect(find.text(_kCandidateTitle), findsNothing);
  });

  testWidgets('rationale 超 120 字 ⇒ 截断加省略号（不改写原文）', (tester) async {
    final long = 'P001：${'x' * 200}';
    await tester.pumpWidget(
      _wrap(
        _card(
          candidates: [
            FocusCandidateCard(
              syndromeId: 'P001',
              name: '情绪标签化',
              total: 7,
              rationale: long,
            ),
          ],
        ),
      ),
    );
    final shown = find.textContaining('xxx');
    expect(shown, findsOneWidget);
    expect(tester.widget<Text>(shown).data!.length, 121); // 120 + '…'
    expect(tester.widget<Text>(shown).data!.endsWith('…'), isTrue);
  });

  // ── 改选流程面（内存 DB 真链路）──

  group('W-22 改选（G3 M1）', () {
    late AppDatabase db;
    late ProviderContainer container;
    late String sessionId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      sessionId = await SessionRepository(db).createBlankSession();
    });

    tearDown(() async {
      await db.close();
      container.dispose();
    });

    /// 落一条 active_problem（severity 显式传入，模拟「现值」）。
    Future<void> seedProblem(String syndromeId, String severity) async {
      await DiagnosisRepository(db).commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': syndromeId, 'name': '视角漂移', 'severity': severity},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
    }

    testWidgets('在池 ⇒ confirmDiagnosis 现值落库 + 按钮切「已选为焦点」', (tester) async {
      await seedProblem('P003', 'L1');
      await tester.pumpWidget(
        _wrap(
          _card(candidates: _kCandidates, sessionId: sessionId),
          overrides: [appDatabaseProvider.overrideWithValue(db)],
        ),
      );
      // P003 候选行的按钮（第二个）
      final buttons = find.widgetWithText(TextButton, _kSwitchLabel);
      expect(buttons, findsNWidgets(2));
      await tester.tap(buttons.last);
      await tester.pumpAndSettle();

      final row = await DiagnosisRepository(
        db,
      ).getActiveProblem(sessionId, 'P003');
      expect(row, isNotNull);
      expect(row!.confirmationStatus, 'confirmed');
      // 设计批 §6.2：severity 传现值 ⇒ 零升级（L1 不得被顶成 L2/L3）
      expect(row.severity, 'L1');
      expect(find.text(_kSwitchedLabel), findsOneWidget);
      expect(find.textContaining('已把焦点切换为 视角漂移'), findsOneWidget);
    });

    testWidgets('不在池（resolved/历史）⇒  snack 明示 + 按钮回弹（无死按钮）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _card(candidates: _kCandidates, sessionId: sessionId),
          overrides: [appDatabaseProvider.overrideWithValue(db)],
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, _kSwitchLabel).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('当前不在活跃问题列表'), findsOneWidget);
      // 回弹：按钮恢复可点（不锁死）
      expect(find.widgetWithText(TextButton, _kSwitchLabel), findsNWidgets(2));
      expect(find.text(_kSwitchedLabel), findsNothing);
    });

    testWidgets('落库失败 ⇒ 失败 snack + 回弹（点了要被告知为什么没成）', (tester) async {
      await seedProblem('P003', 'L1');
      final throwing = _ThrowingConfirmService(
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
      );
      await tester.pumpWidget(
        _wrap(
          _card(candidates: _kCandidates, sessionId: sessionId),
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            diagnosisServiceProvider.overrideWithValue(throwing),
          ],
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, _kSwitchLabel).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('切换焦点'), findsOneWidget);
      expect(find.text(_kSwitchedLabel), findsNothing);
      // 状态未切换：DB 仍 suspected
      final row = await DiagnosisRepository(
        db,
      ).getActiveProblem(sessionId, 'P003');
      expect(row!.confirmationStatus, 'suspected');
    });
  });
}

/// 落库必然失败的 confirm（对齐 diagnosis_card_test 的 _ThrowingDiagnosisService
/// 模式；只覆 confirmDiagnosis——改选路径唯一写入口）。
class _ThrowingConfirmService extends DiagnosisService {
  _ThrowingConfirmService({
    required super.diagnosisRepo,
    required super.studentModelRepo,
  });

  @override
  Future<void> confirmDiagnosis(
    String sessionId,
    String syndromeId,
    String syndromeName,
    Severity severity, {
    String level = 'confirmed',
  }) async {
    throw StateError('test-confirm-fail');
  }
}
