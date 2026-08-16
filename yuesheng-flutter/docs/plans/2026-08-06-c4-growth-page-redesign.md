# C4 成长页 + 成长详情页实现计划

> **For agentic workers:** TDD 优先 — 先写失败测试,再实施,最后验证全绿。Steps 用 checkbox (`- [ ]`) 跟踪。

**Goal:** 将成长 Tab 从 PlaceholderPage 升级为完整的成长概览页 + 成长详情页,展示用户级能力画像(熟练度/认知风格/症候分布)与诊断历史时间线。视觉规范对齐 C1/C3 月色竹青基线,数据可视化用极简色块条(无第三方图表库)。

**Architecture:**
- `GrowthStore` (StateNotifier) 聚合 `buildStudentContext(sessionId: null)` 全局画像 + `listAllActiveProblems()` 跨会话活跃问题 + `listDiagnosisHistory()` 最近诊断
- `GrowthPage` 是概览页,展示熟练度卡片 + 症候概览 + 入口
- `GrowthDetailPage` 是详情页,展示能力画像详情 + 症候分布 SeverityBar + 诊断历史时间线
- 数据层补齐 `DiagnosisRepository.listAllActiveProblems()`(跨 session 聚合,group by syndrome_id)
- 可视化组件 `SeverityBar` + `ProficiencyRing` 纯 Container + CustomPaint

**Tech Stack:** Flutter 3.12 / Riverpod 2.5 / go_router 14.2 / Drift 2.20 / 现有 student_profile service

---

## 视觉规范(对齐 C1/C3 月色竹青基线)

| 元素 | 色值 | 说明 |
|------|------|------|
| AppBar | #F7F8F6 + 48dp + 深字 #2D3142 | 与 C1 WritingPage / C3 一致 |
| Scaffold 背景 | #F7F8F6 | 冷青灰白 |
| 卡片 | #F2F4F2 + 左侧 4dp 竹青色条 | 与 C3 ManuscriptDetailPage 一致(ClipRRect + 内部 Container) |
| 主色锚点 | #2D5A52 | 竹青 |
| 熟练度环 | #2D5A52 填充 + #E0E4E0 底 | CustomPaint 进度环 |
| 症候色块 L1 | #E8F0EE(浅竹青) | 矿物色 — 轻微 |
| 症候色块 L2 | #F5E6B8(浅赭黄) | 矿物色 — 中等 |
| 症候色块 L3 | #E8C5C5(浅赭红) | 矿物色 — 严重 |
| 教学状态标签 | identified=#E0E4E0 / in_progress=#F5E6B8 / consolidating=#E8F0EE / mastered=#E8F0EE+竹青字 | 矿物色定型 |
| 诊断历史时间线 | 左侧 2dp 竹青竖线 + 圆点 | 极简时间线 |

---

## 文件结构

| 文件 | 职责 | 动作 |
|------|------|------|
| `lib/data/repositories/diagnosis_repository.dart` | 补 `listAllActiveProblems()` 跨 session 聚合 | 修改 |
| `lib/providers/growth_providers.dart` | GrowthState + GrowthStore | 创建 |
| `lib/widgets/severity_bar.dart` | 症候严重度色块条组件 | 创建 |
| `lib/widgets/proficiency_ring.dart` | 熟练度竹青进度环(CustomPaint) | 创建 |
| `lib/widgets/growth_page.dart` | 成长概览页 | 创建 |
| `lib/widgets/growth_detail_page.dart` | 成长详情页(能力画像+症候分布+诊断历史) | 创建 |
| `lib/router/app_router.dart` | Tab3 改 GrowthPage + 新增 /growth-detail 路由 | 修改 |
| `test/data/repositories/diagnosis_repository_test.dart` | listAllActiveProblems 测试 | 创建 |
| `test/providers/growth_providers_test.dart` | GrowthStore 单元测试 | 创建 |
| `test/widgets/severity_bar_test.dart` | SeverityBar 视觉断言 | 创建 |
| `test/widgets/proficiency_ring_test.dart` | ProficiencyRing 视觉断言 | 创建 |
| `test/widgets/growth_page_test.dart` | GrowthPage 视觉+功能测试 | 创建 |
| `test/widgets/growth_detail_page_test.dart` | GrowthDetailPage 视觉+功能测试 | 创建 |
| `test/router/growth_route_test.dart` | /growth + /growth-detail 路由测试 | 创建 |

---

## Task 1: DiagnosisRepository.listAllActiveProblems — 跨 session 聚合

**Files:**
- Modify: `lib/data/repositories/diagnosis_repository.dart`
- Test: `test/data/repositories/diagnosis_repository_test.dart`

**背景**:现有 `listActiveProblems(sessionId)` 按 session 隔离。成长页是用户级视图,需跨所有 session 聚合活跃问题,group by syndrome_id 取最新严重度。

- [ ] **Step 1: 写失败测试**

```dart
// test/data/repositories/diagnosis_repository_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';

void main() {
  late AppDatabase db;
  late DiagnosisRepository repo;
  late SessionRepository sessionRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DiagnosisRepository(db);
    sessionRepo = SessionRepository(db);
  });

  tearDown(() => db.close());

  group('listAllActiveProblems', () {
    test('#1 空 DB → 返回空列表', () async {
      final result = await repo.listAllActiveProblems();
      expect(result, isEmpty);
    });

    test('#2 跨 session 聚合相同 syndrome_id → 合并为一条,取最新严重度', () async {
      // session A
      final sidA = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(DiagnosisInput(
        sessionId: sidA,
        messageId: 'msg-a',
        syndromes: [
          {'syndrome_id': 'S001', 'name': '视角跳跃', 'severity': 'L2'},
        ],
        suggestedActions: [],
        confidence: 0.8,
      ));

      // session B — 同一 syndrome 但更严重
      final sidB = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(DiagnosisInput(
        sessionId: sidB,
        messageId: 'msg-b',
        syndromes: [
          {'syndrome_id': 'S001', 'name': '视角跳跃', 'severity': 'L3'},
        ],
        suggestedActions: [],
        confidence: 0.9,
      ));

      final result = await repo.listAllActiveProblems();

      expect(result.length, 1); // 合并为一条
      expect(result.first.syndromeId, 'S001');
      expect(result.first.severity, 'L3'); // 取最新
      expect(result.first.syndromeName, '视角跳跃');
    });

    test('#3 排除 resolved 状态的症候', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(DiagnosisInput(
        sessionId: sid,
        messageId: 'msg-1',
        syndromes: [
          {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L2'},
        ],
        suggestedActions: [],
        confidence: 0.8,
      ));
      // 解决该症候
      await repo.resolveProblem(sid, 'S001');

      final result = await repo.listAllActiveProblems();
      expect(result, isEmpty); // resolved 被排除
    });

    test('#4 按 severity DESC 排序(L3 在前)', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(DiagnosisInput(
        sessionId: sid,
        messageId: 'msg-1',
        syndromes: [
          {'syndrome_id': 'S001', 'name': 'L2症候', 'severity': 'L2'},
          {'syndrome_id': 'S002', 'name': 'L3症候', 'severity': 'L3'},
          {'syndrome_id': 'S003', 'name': 'L1症候', 'severity': 'L1'},
        ],
        suggestedActions: [],
        confidence: 0.8,
      ));

      final result = await repo.listAllActiveProblems();
      expect(result.length, 3);
      expect(result[0].severity, 'L3');
      expect(result[1].severity, 'L2');
      expect(result[2].severity, 'L1');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/data/repositories/diagnosis_repository_test.dart`
Expected: FAIL — `listAllActiveProblems` 方法不存在

- [ ] **Step 3: 实现 listAllActiveProblems**

在 `lib/data/repositories/diagnosis_repository.dart` 的 `DiagnosisRepository` 类中追加:

```dart
/// 跨 session 聚合所有活跃问题(group by syndrome_id,取最新严重度)
/// 用于成长页用户级视图
Future<List<ActiveProblemView>> listAllActiveProblems() async {
  // SELECT * FROM active_problem WHERE status='active'
  //   GROUP BY syndrome_id 取最新 created_at
  final rows = await (_db.select(_db.activeProblems)
        ..where((t) => t.status.equals('active'))
        ..orderBy([
          // 先按 created_at DESC,后续在 Dart 层 group by 取第一条
          (t) => OrderingTerm(
            expression: t.createdAt,
            mode: OrderingMode.desc,
          ),
        ]))
      .get();

  // Dart 层 group by syndrome_id(保留最新一条)
  final grouped = <String, ActiveProblemsData>{};
  for (final r in rows) {
    if (!grouped.containsKey(r.syndromeId)) {
      grouped[r.syndromeId] = r;
    }
  }

  // 转 ActiveProblemView + 按 severity DESC 排序
  const order = {'L3': 0, 'L2': 1, 'L1': 2};
  final result = grouped.values.map((r) {
    return ActiveProblemView(
      syndromeId: r.syndromeId,
      syndromeName: r.syndromeName,
      severity: r.severity,
      confirmationStatus: r.confirmationStatus,
      confirmedAt: r.confirmedAt,
    );
  }).toList()
    ..sort((a, b) {
      return (order[a.severity] ?? 3).compareTo(order[b.severity] ?? 3);
    });

  return result;
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/data/repositories/diagnosis_repository_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 5: 提交**

```bash
git add lib/data/repositories/diagnosis_repository.dart test/data/repositories/diagnosis_repository_test.dart
git commit -m "feat: DiagnosisRepository.listAllActiveProblems 跨 session 聚合"
```

---

## Task 2: GrowthStore — 状态管理

**Files:**
- Create: `lib/providers/growth_providers.dart`
- Test: `test/providers/growth_providers_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/providers/growth_providers_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/growth_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  group('GrowthStore', () {
    test('初始状态:isLoading=true, profile=null', () {
      final state = container.read(growthStoreProvider);
      expect(state.isLoading, true);
      expect(state.profile, isNull);
      expect(state.activeProblems, isEmpty);
      expect(state.diagnosisHistory, isEmpty);
    });

    test('loadGrowthData: 空 DB → profile.proficiency=beginner, activeProblems 空', () async {
      await container.read(growthStoreProvider.notifier).loadGrowthData();

      final state = container.read(growthStoreProvider);
      expect(state.isLoading, false);
      expect(state.profile, isNotNull);
      expect(state.profile!.proficiency.value, 'beginner');
      expect(state.activeProblems, isEmpty);
    });

    test('loadGrowthData: 有诊断 → activeProblems 非空', () async {
      // 准备数据
      final sessionRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sid = await sessionRepo.createBlankSession();
      await diagRepo.commitDiagnosis(DiagnosisInput(
        sessionId: sid,
        messageId: 'msg-1',
        syndromes: [
          {'syndrome_id': 'S001', 'name': '视角跳跃', 'severity': 'L2'},
        ],
        suggestedActions: [],
        confidence: 0.8,
      ));

      await container.read(growthStoreProvider.notifier).loadGrowthData();

      final state = container.read(growthStoreProvider);
      expect(state.activeProblems.length, 1);
      expect(state.activeProblems.first.syndromeId, 'S001');
      expect(state.diagnosisHistory.length, 1);
    });

    test('loadGrowthData: 多次诊断 → diagnosisHistory 按 timestamp DESC', () async {
      final sessionRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sid = await sessionRepo.createBlankSession();

      // 第一条诊断(旧)
      await diagRepo.commitDiagnosis(DiagnosisInput(
        sessionId: sid,
        messageId: 'msg-1',
        syndromes: [{'syndrome_id': 'S001', 'name': 'A', 'severity': 'L1'}],
        suggestedActions: [],
        confidence: 0.7,
      ));
      await Future.delayed(const Duration(seconds: 1));
      // 第二条诊断(新)
      await diagRepo.commitDiagnosis(DiagnosisInput(
        sessionId: sid,
        messageId: 'msg-2',
        syndromes: [{'syndrome_id': 'S002', 'name': 'B', 'severity': 'L2'}],
        suggestedActions: [],
        confidence: 0.8,
      ));

      await container.read(growthStoreProvider.notifier).loadGrowthData();

      final state = container.read(growthStoreProvider);
      expect(state.diagnosisHistory.length, 2);
      // 新的在前
      expect(state.diagnosisHistory.first.messageId, 'msg-2');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/providers/growth_providers_test.dart`
Expected: FAIL — `growth_providers.dart` 不存在

- [ ] **Step 3: 实现 GrowthStore**

```dart
// lib/providers/growth_providers.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/student_model_repository.dart';
import '../services/student_profile.dart';
import '../types/teaching_types.dart';
import 'app_providers.dart';

/// 成长页状态(不可变)
class GrowthState {
  final bool isLoading;
  final StudentProfile? profile;
  final List<ActiveProblemView> activeProblems;
  final List<DiagnosisRow> diagnosisHistory;
  final String? error;

  const GrowthState({
    this.isLoading = true,
    this.profile,
    this.activeProblems = const [],
    this.diagnosisHistory = const [],
    this.error,
  });

  GrowthState copyWith({
    bool? isLoading,
    StudentProfile? profile,
    List<ActiveProblemView>? activeProblems,
    List<DiagnosisRow>? diagnosisHistory,
    String? error,
    bool clearError = false,
  }) {
    return GrowthState(
      isLoading: isLoading ?? this.isLoading,
      profile: profile ?? this.profile,
      activeProblems: activeProblems ?? this.activeProblems,
      diagnosisHistory: diagnosisHistory ?? this.diagnosisHistory,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 成长页状态管理器 — 全局聚合(sessionId: null)
class GrowthStore extends StateNotifier<GrowthState> {
  final AppDatabase _db;

  GrowthStore(this._db) : super(const GrowthState());

  /// 加载成长数据(全局聚合)
  Future<void> loadGrowthData() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final diagRepo = DiagnosisRepository(_db);
      final sessionRepo = SessionRepository(_db);
      final studentModelRepo = StudentModelRepository(_db);

      // 并行加载三项数据
      final results = await Future.wait([
        // 1. 能力画像(全局聚合,sessionId: null)
        buildStudentContext(
          diagnosisRepo: diagRepo,
          studentModelRepo: studentModelRepo,
          sessionRepo: sessionRepo,
          sessionId: null, // 全局聚合
        ),
        // 2. 跨 session 活跃问题
        diagRepo.listAllActiveProblems(),
        // 3. 最近 10 条诊断历史(跨 session)
        _listRecentDiagnoses(diagRepo, limit: 10),
      ]);

      final profileResult = results[0] as ProfileTextResult;
      final activeProblems = results[1] as List<ActiveProblemView>;
      final history = results[2] as List<DiagnosisRow>;

      state = GrowthState(
        isLoading: false,
        profile: profileResult.profile,
        activeProblems: activeProblems,
        diagnosisHistory: history,
      );
    } catch (e) {
      debugPrint('[GrowthStore] loadGrowthData 失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 跨 session 获取最近 N 条诊断(按 timestamp DESC)
  Future<List<DiagnosisRow>> _listRecentDiagnoses(
    DiagnosisRepository repo, {
    int limit = 10,
  }) async {
    // 复用 getAllDiagnoses 的查询逻辑,但返回 DiagnosisRow 而非扁平条目
    // 注意:getAllDiagnoses 返回 SyndromeFlatEntry[],这里需要 DiagnosisRow[]
    // 简化:直接查 diagnosis_results 表,不限定 sessionId
    final db = _db;
    return (db.select(db.diagnosisResults)
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.timestamp,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(limit))
        .get();
  }
}

/// 全局单例 provider(成长页是用户级视图,不需 family)
final growthStoreProvider =
    StateNotifierProvider<GrowthStore, GrowthState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return GrowthStore(db);
});
```

**注意**:Step 3 实现时需 import `dart:async` for `Future.wait`,以及 `package:drift/drift.dart` for `OrderingTerm` / `OrderingMode`。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/providers/growth_providers_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 5: 提交**

```bash
git add lib/providers/growth_providers.dart test/providers/growth_providers_test.dart
git commit -m "feat: GrowthStore 全局聚合状态管理"
```

---

## Task 3: SeverityBar — 症候严重度色块条

**Files:**
- Create: `lib/widgets/severity_bar.dart`
- Test: `test/widgets/severity_bar_test.dart`

**视觉**:横向色块条,按 L1/L2/L3 矿物色填充比例。例如 3 个症候中 L1×1 + L2×1 + L3×1 → 三段等宽色块。

- [ ] **Step 1: 写失败测试**

```dart
// test/widgets/severity_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/widgets/severity_bar.dart';

void main() {
  group('SeverityBar', () {
    testWidgets('#1 渲染 3 段色块(L1/L2/L3 各 1 个)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeverityBar(counts: SeverityCounts(l1: 1, l2: 1, l3: 1)),
          ),
        ),
      );

      // 验证 3 个色块 Container(排除外层)
      final blocks = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color != null,
        ),
      );
      expect(blocks.length, 3);
    });

    testWidgets('#2 L1 色块 = #E8F0EE', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeverityBar(counts: SeverityCounts(l1: 2, l2: 0, l3: 0)),
          ),
        ),
      );

      final l1Block = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color ==
                  const Color(0xFFE8F0EE),
        ),
      );
      expect(l1Block.length, 1); // 合并为 1 段,宽度按比例
    });

    testWidgets('#3 L2 色块 = #F5E6B8', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeverityBar(counts: SeverityCounts(l1: 0, l2: 1, l3: 0)),
          ),
        ),
      );

      final l2Block = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color ==
                  const Color(0xFFF5E6B8),
        ),
      );
      expect(l2Block.length, 1);
    });

    testWidgets('#4 L3 色块 = #E8C5C5', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeverityBar(counts: SeverityCounts(l1: 0, l2: 0, l3: 1)),
          ),
        ),
      );

      final l3Block = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color ==
                  const Color(0xFFE8C5C5),
        ),
      );
      expect(l3Block.length, 1);
    });

    testWidgets('#5 全 0 → 渲染空状态占位(灰底)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeverityBar(counts: SeverityCounts(l1: 0, l2: 0, l3: 0)),
          ),
        ),
      );

      // 空状态:1 个灰色 Container
      final emptyBlock = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color ==
                  const Color(0xFFE0E4E0),
        ),
      );
      expect(emptyBlock.length, 1);
    });

    testWidgets('#6 比例正确:L1=2,L2=1,L3=1 → 总 4 份,L1 占 50%', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: SeverityBar(counts: SeverityCounts(l1: 2, l2: 1, l3: 1)),
            ),
          ),
        ),
      );

      // L1 段宽度 = 400 * 2/4 = 200
      // 用 Flex 或 Expanded 的 flex 验证比例
      final expanded = tester.widgetList<Expanded>(
        find.byType(Expanded),
      ).toList();
      expect(expanded.length, 3); // 3 段
      expect(expanded[0].flex, 2); // L1 flex=2
      expect(expanded[1].flex, 1); // L2 flex=1
      expect(expanded[2].flex, 1); // L3 flex=1
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/widgets/severity_bar_test.dart`
Expected: FAIL — `severity_bar.dart` 不存在

- [ ] **Step 3: 实现 SeverityBar**

```dart
// lib/widgets/severity_bar.dart
import 'package:flutter/material.dart';

/// 症候严重度计数
class SeverityCounts {
  final int l1;
  final int l2;
  final int l3;
  const SeverityCounts({required this.l1, required this.l2, required this.l3});

  int get total => l1 + l2 + l3;
  bool get isEmpty => total == 0;
}

/// 症候严重度色块条 — 极简横向比例条
///
/// 月色竹青矿物色配色:
///   L1 = #E8F0EE(浅竹青,轻微)
///   L2 = #F5E6B8(浅赭黄,中等)
///   L3 = #E8C5C5(浅赭红,严重)
///
/// 用 Expanded + flex 按比例填充,无第三方图表库。
class SeverityBar extends StatelessWidget {
  final SeverityCounts counts;
  final double height;

  const SeverityBar({
    super.key,
    required this.counts,
    this.height = 8,
  });

  static const _l1Color = Color(0xFFE8F0EE);
  static const _l2Color = Color(0xFFF5E6B8);
  static const _l3Color = Color(0xFFE8C5C5);
  static const _emptyColor = Color(0xFFE0E4E0);

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: _emptyColor,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            if (counts.l1 > 0)
              Expanded(flex: counts.l1, child: Container(color: _l1Color)),
            if (counts.l2 > 0)
              Expanded(flex: counts.l2, child: Container(color: _l2Color)),
            if (counts.l3 > 0)
              Expanded(flex: counts.l3, child: Container(color: _l3Color)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/severity_bar_test.dart`
Expected: PASS — 6 tests

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/severity_bar.dart test/widgets/severity_bar_test.dart
git commit -m "feat: SeverityBar 症候严重度色块条"
```

---

## Task 4: ProficiencyRing — 熟练度竹青进度环

**Files:**
- Create: `lib/widgets/proficiency_ring.dart`
- Test: `test/widgets/proficiency_ring_test.dart`

**视觉**:圆形进度环,竹青 #2D5A52 填充 + #E0E4E0 底环,中心显示熟练度等级文本。用 CustomPaint 实现。

**进度语义（方案 A）**:
- progress = 等级位置,而非 confidence
  - beginner=0.25 / elementary=0.5 / intermediate=0.75 / advanced=1.0
  - 环满 = 满级,符合直觉
- confidence 仅用于"数据不足"判断（< 0.3 显示"数据不足",progress=0）
- 中心只显示等级标签,不显示百分比（避免 UX 误导）
- strokeWidth 按 size 比例:`size / 15`(默认 size=120 → 8.0)

- [ ] **Step 1: 写失败测试**

```dart
// test/widgets/proficiency_ring_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/proficiency_ring.dart';

void main() {
  group('ProficiencyRing', () {
    testWidgets('#1 中心显示熟练度等级文本', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.beginner,
              confidence: 0.5,
            ),
          ),
        ),
      );

      expect(find.text('新手'), findsOneWidget);
    });

    testWidgets('#2 elementary → 显示"入门"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.elementary,
              confidence: 0.6,
            ),
          ),
        ),
      );

      expect(find.text('入门'), findsOneWidget);
    });

    testWidgets('#3 intermediate → 显示"进阶"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.intermediate,
              confidence: 0.7,
            ),
          ),
        ),
      );

      expect(find.text('进阶'), findsOneWidget);
    });

    testWidgets('#4 advanced → 显示"熟练"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.advanced,
              confidence: 0.85,
            ),
          ),
        ),
      );

      expect(find.text('熟练'), findsOneWidget);
    });

    testWidgets('#5 CustomPaint 存在(进度环绘制)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.beginner,
              confidence: 0.5,
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('#6 置信度 < 0.3 → 显示"数据不足"提示', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.beginner,
              confidence: 0.2,
            ),
          ),
        ),
      );

      expect(find.text('数据不足'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/widgets/proficiency_ring_test.dart`
Expected: FAIL — `proficiency_ring.dart` 不存在

- [ ] **Step 3: 实现 ProficiencyRing**

```dart
// lib/widgets/proficiency_ring.dart
import 'package:flutter/material.dart';
import '../types/teaching_types.dart';

/// 熟练度竹青进度环 — CustomPaint 实现
///
/// 月色竹青配色:
///   进度环 = #2D5A52(竹青)
///   底环 = #E0E4E0(浅灰)
///   中心文本 = 等级中文标签
///
/// 置信度 < 0.3 时显示"数据不足"。
class ProficiencyRing extends StatelessWidget {
  final ProficiencyLevel level;
  final double confidence;
  final double size;

  const ProficiencyRing({
    super.key,
    required this.level,
    required this.confidence,
    this.size = 120,
  });

  static const _progressColor = Color(0xFF2D5A52);
  static const _trackColor = Color(0xFFE0E4E0);
  static const _textColor = Color(0xFF2D3142);
  static const _subTextColor = Color(0xFF8A8D93);

  String get _levelLabel {
    switch (level) {
      case ProficiencyLevel.beginner:
        return '新手';
      case ProficiencyLevel.elementary:
        return '入门';
      case ProficiencyLevel.intermediate:
        return '进阶';
      case ProficiencyLevel.advanced:
        return '熟练';
    }
  }

  bool get _isInsufficientData => confidence < 0.3;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 进度环
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: _isInsufficientData ? 0.0 : confidence,
              progressColor: _progressColor,
              trackColor: _trackColor,
            ),
          ),
          // 中心文本
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isInsufficientData ? '数据不足' : _levelLabel,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textColor,
                ),
              ),
              if (!_isInsufficientData)
                Text(
                  '${(confidence * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _subTextColor,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress; // 0.0 - 1.0
  final Color progressColor;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.progressColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeWidth = 8.0;

    // 底环
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // 进度环(从 -π/2 开始,顺时针)
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweepAngle = 2 * 3.141592653589793 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.141592653589793 / 2, // 起始角度(12点方向)
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/proficiency_ring_test.dart`
Expected: PASS — 6 tests

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/proficiency_ring.dart test/widgets/proficiency_ring_test.dart
git commit -m "feat: ProficiencyRing 熟练度竹青进度环"
```

---

## Task 5: GrowthPage — 成长概览页

**Files:**
- Create: `lib/widgets/growth_page.dart`
- Test: `test/widgets/growth_page_test.dart`

**视觉布局**:
1. AppBar: 浅色 #F7F8F6 + 48dp + 标题"成长" + 右上 ⓘ 图标(跳详情页)
2. 熟练度卡片: ProficiencyRing + 总会话数
3. 症候概览卡片: SeverityBar + 活跃问题数
4. 最近诊断入口: 点击进入详情页

- [ ] **Step 1: 写失败测试**

```dart
// test/widgets/growth_page_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/growth_page.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildGrowthPage() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: GrowthPage(),
      ),
    );
  }

  group('GrowthPage 视觉规范(月色竹青)', () {
    testWidgets('#V1 AppBar 浅色 #F7F8F6 + 48dp + 深字 #2D3142', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, const Color(0xFFF7F8F6));
      expect(appBar.toolbarHeight, 48);
      expect(appBar.foregroundColor, const Color(0xFF2D3142));
    });

    testWidgets('#V2 Scaffold 背景 #F7F8F6', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFFF7F8F6));
    });

    testWidgets('#V3 熟练度卡片左侧 4dp 竹青色条', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      final colorBar = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 4 &&
            w.color == const Color(0xFF2D5A52),
      );
      expect(colorBar, findsWidgets); // 至少熟练度卡片有
    });

    testWidgets('#V4 AppBar 右上有详情入口图标', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });

  group('GrowthPage 功能', () {
    testWidgets('#F1 加载后显示熟练度等级文本', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      // 空 DB → beginner + 数据不足
      expect(find.text('数据不足'), findsOneWidget);
    });

    testWidgets('#F2 显示总会话数(0)', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('0'), findsWidgets);
    });

    testWidgets('#F3 点击详情图标 → 跳转详情页', (tester) async {
      String? pushedRoute;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: GrowthPage(
              onOpenDetail: () => pushedRoute = '/growth-detail',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(pushedRoute, '/growth-detail');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/widgets/growth_page_test.dart`
Expected: FAIL — `growth_page.dart` 不存在

- [ ] **Step 3: 实现 GrowthPage**

```dart
// lib/widgets/growth_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/growth_providers.dart';
import '../types/teaching_types.dart';
import 'proficiency_ring.dart';
import 'severity_bar.dart';

/// 成长概览页 — 用户级能力画像入口
///
/// 视觉规范(月色竹青,对齐 C1/C3):
///   AppBar #F7F8F6 + 48dp + 深字
///   卡片 #F2F4F2 + 左侧 4dp 竹青色条
///   熟练度环 + 症候色块条
class GrowthPage extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDetail;

  const GrowthPage({super.key, this.onOpenDetail});

  @override
  ConsumerState<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends ConsumerState<GrowthPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(growthStoreProvider.notifier).loadGrowthData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(growthStoreProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        title: const Text('成长'),
        backgroundColor: const Color(0xFFF7F8F6),
        foregroundColor: const Color(0xFF2D3142),
        toolbarHeight: 48,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 22),
            onPressed: widget.onOpenDetail,
            tooltip: '能力画像详情',
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2D5A52)),
            )
          : state.error != null
          ? _ErrorView(error: state.error!)
          : _GrowthContent(
              state: state,
              onOpenDetail: widget.onOpenDetail,
            ),
    );
  }
}

class _GrowthContent extends StatelessWidget {
  final GrowthState state;
  final VoidCallback? onOpenDetail;

  const _GrowthContent({required this.state, this.onOpenDetail});

  @override
  Widget build(BuildContext context) {
    final profile = state.profile;
    final proficiency = profile?.proficiency ?? ProficiencyLevel.beginner;
    final confidence = profile?.confidence ?? 0;
    final totalSessions = profile?.totalSessions ?? 0;

    // 统计症候严重度计数
    final counts = _countSeverities(state.activeProblems);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 熟练度卡片
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '能力画像',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8A8D93),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ProficiencyRing(
                    level: proficiency,
                    confidence: confidence,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    '共 $totalSessions 次写作会话',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8A8D93),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 症候概览卡片
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '症候概览',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A8D93),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${state.activeProblems.length} 个活跃',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2D5A52),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SeverityBar(counts: counts, height: 10),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Legend(color: const Color(0xFFE8F0EE), label: 'L1 ${counts.l1}'),
                    const SizedBox(width: 12),
                    _Legend(color: const Color(0xFFF5E6B8), label: 'L2 ${counts.l2}'),
                    const SizedBox(width: 12),
                    _Legend(color: const Color(0xFFE8C5C5), label: 'L3 ${counts.l3}'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 详情入口
        if (onOpenDetail != null)
          _Card(
            child: InkWell(
              onTap: onOpenDetail,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      '查看完整能力画像',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF2D3142),
                      ),
                    ),
                    Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Color(0xFFB8BCC0),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  SeverityCounts _countSeverities(List<ActiveProblemView> problems) {
    int l1 = 0, l2 = 0, l3 = 0;
    for (final p in problems) {
      switch (p.severity) {
        case 'L1':
          l1++;
          break;
        case 'L2':
          l2++;
          break;
        case 'L3':
          l3++;
          break;
      }
    }
    return SeverityCounts(l1: l1, l2: l2, l3: l3);
  }
}

/// 通用卡片:左侧 4dp 竹青色条(对齐 C3 ManuscriptDetailPage)
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4F2),
          border: Border.all(color: const Color(0xFFE0E4E0)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: const Color(0xFF2D5A52)),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8A8D93)),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32, color: Color(0xFFB91C1C)),
            const SizedBox(height: 8),
            Text(
              '加载失败',
              style: const TextStyle(fontSize: 14, color: Color(0xFF8A8D93)),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/growth_page_test.dart`
Expected: PASS — 7 tests

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/growth_page.dart test/widgets/growth_page_test.dart
git commit -m "feat: GrowthPage 成长概览页"
```

---

## Task 6: GrowthDetailPage — 成长详情页

**Files:**
- Create: `lib/widgets/growth_detail_page.dart`
- Test: `test/widgets/growth_detail_page_test.dart`

**视觉布局**:
1. AppBar: 浅色 + 48dp + 标题"能力画像"
2. 能力画像详情卡: ProficiencyRing + 认知风格 + 总会话数
3. 症候分布列表: 每条症候一行,含名称 + 教学状态标签 + SeverityBar(个人)
4. 诊断历史时间线: 左侧 2dp 竹青竖线 + 圆点 + 时间 + 症候数

- [ ] **Step 1: 写失败测试**

```dart
// test/widgets/growth_detail_page_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/growth_detail_page.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildDetailPage() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: GrowthDetailPage()),
    );
  }

  group('GrowthDetailPage 视觉规范(月色竹青)', () {
    testWidgets('#V1 AppBar 浅色 #F7F8F6 + 48dp', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, const Color(0xFFF7F8F6));
      expect(appBar.toolbarHeight, 48);
      expect(appBar.foregroundColor, const Color(0xFF2D3142));
    });

    testWidgets('#V2 Scaffold 背景 #F7F8F6', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFFF7F8F6));
    });

    testWidgets('#V3 卡片左侧 4dp 竹青色条', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      final colorBar = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 4 &&
            w.color == const Color(0xFF2D5A52),
      );
      expect(colorBar, findsWidgets);
    });
  });

  group('GrowthDetailPage 功能', () {
    testWidgets('#F1 有诊断 → 渲染症候列表(含症候名)', (tester) async {
      // 准备数据
      final sessionRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sid = await sessionRepo.createBlankSession();
      await diagRepo.commitDiagnosis(DiagnosisInput(
        sessionId: sid,
        messageId: 'msg-1',
        syndromes: [
          {'syndrome_id': 'S001', 'name': '视角跳跃', 'severity': 'L2'},
        ],
        suggestedActions: [],
        confidence: 0.8,
      ));

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('视角跳跃'), findsOneWidget);
    });

    testWidgets('#F2 空状态 → 显示"暂无诊断数据"', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('暂无诊断数据'), findsOneWidget);
    });

    testWidgets('#F3 诊断历史时间线渲染(有时间文本)', (tester) async {
      final sessionRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sid = await sessionRepo.createBlankSession();
      await diagRepo.commitDiagnosis(DiagnosisInput(
        sessionId: sid,
        messageId: 'msg-1',
        syndromes: [
          {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L1'},
        ],
        suggestedActions: [],
        confidence: 0.7,
      ));

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 时间线左侧竹青竖线存在
      final timelineLine = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 2 &&
            w.color == const Color(0xFF2D5A52),
      );
      expect(timelineLine, findsWidgets);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/widgets/growth_detail_page_test.dart`
Expected: FAIL — `growth_detail_page.dart` 不存在

- [ ] **Step 3: 实现 GrowthDetailPage**

```dart
// lib/widgets/growth_detail_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/growth_providers.dart';
import '../types/teaching_types.dart';
import 'proficiency_ring.dart';

/// 成长详情页 — 完整能力画像 + 症候分布 + 诊断历史时间线
///
/// 视觉规范(月色竹青):
///   AppBar #F7F8F6 + 48dp
///   卡片 #F2F4F2 + 左侧 4dp 竹青色条
///   诊断历史时间线: 左侧 2dp 竹青竖线 + 圆点
class GrowthDetailPage extends ConsumerStatefulWidget {
  const GrowthDetailPage({super.key});

  @override
  ConsumerState<GrowthDetailPage> createState() => _GrowthDetailPageState();
}

class _GrowthDetailPageState extends ConsumerState<GrowthDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(growthStoreProvider.notifier).loadGrowthData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(growthStoreProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        title: const Text('能力画像'),
        backgroundColor: const Color(0xFFF7F8F6),
        foregroundColor: const Color(0xFF2D3142),
        toolbarHeight: 48,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2D5A52)),
            )
          : state.error != null
          ? Center(
              child: Text(
                '加载失败',
                style: const TextStyle(color: Color(0xFF8A8D93)),
              ),
            )
          : _buildContent(state),
    );
  }

  Widget _buildContent(GrowthState state) {
    final profile = state.profile;
    final hasDiagnoses = state.diagnosisHistory.isNotEmpty ||
        state.activeProblems.isNotEmpty;

    if (!hasDiagnoses && (profile == null || profile.totalSessions == 0)) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(
                    Icons.insights_outlined,
                    size: 32,
                    color: Color(0xFFB8BCC0),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '暂无诊断数据',
                    style: TextStyle(fontSize: 14, color: Color(0xFF8A8D93)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 能力画像详情卡
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '能力画像',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8A8D93),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ProficiencyRing(
                    level: profile?.proficiency ?? ProficiencyLevel.beginner,
                    confidence: profile?.confidence ?? 0,
                  ),
                ),
                const SizedBox(height: 16),
                if (profile?.cognitiveStyle != null) ...[
                  _InfoRow(
                    label: '认知风格',
                    value: _cognitiveStyleLabel(profile!.cognitiveStyle!.style),
                  ),
                  const SizedBox(height: 8),
                ],
                _InfoRow(
                  label: '总会话数',
                  value: '${profile?.totalSessions ?? 0}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 症候分布列表
        if (state.activeProblems.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '症候分布',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8A8D93),
              ),
            ),
          ),
          for (final problem in state.activeProblems)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              problem.syndromeName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF2D3142),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '严重度 ${problem.severity}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8A8D93),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _SeverityChip(severity: problem.severity),
                    ],
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        // 诊断历史时间线
        if (state.diagnosisHistory.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '诊断历史',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8A8D93),
              ),
            ),
          ),
          _Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _Timeline(items: state.diagnosisHistory),
            ),
          ),
        ],
      ],
    );
  }

  String _cognitiveStyleLabel(CognitiveStyle style) {
    switch (style) {
      case CognitiveStyle.analytical:
        return '分析型';
      case CognitiveStyle.intuitive:
        return '直觉型';
      case CognitiveStyle.mixed:
        return '混合型';
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF8A8D93)),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2D3142),
          ),
        ),
      ],
    );
  }
}

class _SeverityChip extends StatelessWidget {
  final String severity;
  const _SeverityChip({required this.severity});

  @override
  Widget build(BuildContext context) {
    final (bg, text) = switch (severity) {
      'L1' => (const Color(0xFFE8F0EE), const Color(0xFF5B7565)),
      'L2' => (const Color(0xFFF5E6B8), const Color(0xFF8B6F47)),
      'L3' => (const Color(0xFFE8C5C5), const Color(0xFFB45309)),
      _ => (const Color(0xFFE0E4E0), const Color(0xFF5B7565)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        severity,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: text),
      ),
    );
  }
}

/// 诊断历史时间线 — 左侧 2dp 竹青竖线 + 圆点
class _Timeline extends StatelessWidget {
  final List<DiagnosisRow> items;
  const _Timeline({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          _TimelineItem(item: items[i], isLast: i == items.length - 1),
          if (i < items.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final DiagnosisRow item;
  final bool isLast;
  const _TimelineItem({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(item.timestamp * 1000);
    final dateStr = '${dt.month}-${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧竖线 + 圆点
          SizedBox(
            width: 16,
            child: Column(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2D5A52),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: const Color(0xFF2D5A52),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 右侧内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A8D93),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '置信度 ${(item.confidence * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF2D3142),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用卡片(对齐 GrowthPage)
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4F2),
          border: Border.all(color: const Color(0xFFE0E4E0)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: const Color(0xFF2D5A52)),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/growth_detail_page_test.dart`
Expected: PASS — 6 tests

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/growth_detail_page.dart test/widgets/growth_detail_page_test.dart
git commit -m "feat: GrowthDetailPage 能力画像详情页(症候分布+时间线)"
```

---

## Task 7: 路由集成 + Tab3 接入

**Files:**
- Modify: `lib/router/app_router.dart`
- Test: `test/router/growth_route_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/router/growth_route_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/widgets/growth_detail_page.dart';
import 'package:writingcoach/widgets/growth_page.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  testWidgets('/growth → 渲染 GrowthPage(非 PlaceholderPage)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: appRouter),
      ),
    );
    await tester.pumpAndSettle();

    // 默认 Tab 是书架,切换到成长 Tab
    await tester.tap(find.text('成长'));
    await tester.pumpAndSettle();

    expect(find.byType(GrowthPage), findsOneWidget);
    expect(find.byType(PlaceholderPage), findsNothing);
  });

  testWidgets('/growth-detail → 渲染 GrowthDetailPage', (tester) async {
    final router = GoRouter(
      initialLocation: '/growth-detail',
      routes: [
        GoRoute(
          path: '/growth-detail',
          builder: (context, state) => const GrowthDetailPage(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GrowthDetailPage), findsOneWidget);
  });

  testWidgets('GrowthPage 点击详情图标 → 跳转 /growth-detail', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: appRouter),
      ),
    );
    await tester.pumpAndSettle();

    // 切到成长 Tab
    await tester.tap(find.text('成长'));
    await tester.pumpAndSettle();

    // 点击详情图标
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.byType(GrowthDetailPage), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/router/growth_route_test.dart`
Expected: FAIL — Tab3 仍是 PlaceholderPage,/growth-detail 路由不存在

- [ ] **Step 3: 更新 app_router.dart**

1. 在 `AppRoutes` 类中添加路由常量:
```dart
static const String growthDetail = '/growth-detail';
```

2. 在 import 区域添加:
```dart
import '../widgets/growth_page.dart';
import '../widgets/growth_detail_page.dart';
```

3. 在顶层 routes 列表中(`/writing/:chapterId` 之后)添加:
```dart
// ── 顶层路由:/growth-detail(能力画像详情页)──
GoRoute(
  path: AppRoutes.growthDetail,
  builder: (context, state) => const GrowthDetailPage(),
),
```

4. 修改 Branch C(成长)的 builder:
```dart
// Branch C: 成长(C4 改造:从 PlaceholderPage 升级为 GrowthPage)
StatefulShellBranch(
  routes: [
    GoRoute(
      path: AppRoutes.growth,
      builder: (context, state) => GrowthPage(
        onOpenDetail: () => context.go(AppRoutes.growthDetail),
      ),
    ),
  ],
),
```

5. 删除 `placeholder_page.dart` 的 import(如果不再被其他地方引用)。检查后再决定是否删除文件本身(保守策略:若其他地方仍引用则保留)。

- [ ] **Step 4: 运行路由测试确认通过**

Run: `flutter test test/router/growth_route_test.dart`
Expected: PASS — 3 tests

- [ ] **Step 5: 运行全量测试确认无回归**

Run: `flutter test`
Expected: ALL PASS(除 pre-existing persistAttitude)

- [ ] **Step 6: 提交**

```bash
git add lib/router/app_router.dart test/router/growth_route_test.dart
git commit -m "feat: C4 路由集成 — Tab3 改 GrowthPage + /growth-detail 路由"
```

---

## Task 8: 四闸验证 + 文档同步

**Files:**
- 无新文件

- [ ] **Step 1: flutter analyze**

Run: `flutter analyze`
Expected: 0 errors / 0 warnings

- [ ] **Step 2: dart format**

Run: `dart format --set-exit-if-changed lib/widgets/growth_page.dart lib/widgets/growth_detail_page.dart lib/widgets/severity_bar.dart lib/widgets/proficiency_ring.dart lib/providers/growth_providers.dart lib/data/repositories/diagnosis_repository.dart test/`
如有漂移,运行 `dart format` 落盘。

- [ ] **Step 3: flutter test 全量**

Run: `flutter test`
Expected: ALL PASS(除 pre-existing persistAttitude)

- [ ] **Step 4: 文档同步**

在 `docs/logs/` 生成 `2026-08-06-c4-growth-page-redesign.md` 变更说明。

- [ ] **Step 5: 最终提交**

```bash
git add docs/logs/2026-08-06-c4-growth-page-redesign.md
git commit -m "docs: C4 成长页+成长详情页变更说明"
```

---

## 关键技术决策

### 1. 全局聚合策略(sessionId: null)

**问题**:`listActiveProblems(sessionId)` 和 `getTeachingState(sessionId)` 按 session 隔离,但成长页是用户级视图。

**方案**:
- `buildStudentContext(sessionId: null)` 已支持全局聚合(返回 `totalSessions` 跨会话计数)
- 新增 `listAllActiveProblems()` 跨 session 聚合(group by syndrome_id 取最新)
- 诊断历史用 `diagnosis_results` 表全表查询(不限定 sessionId)
- **不聚合** `teaching_state`(该表按 session 隔离,无用户级语义)

### 2. 视觉对齐 C1/C3 月色竹青基线

**统一**:
- AppBar #F7F8F6 + 48dp + 深字 #2D3142
- Scaffold 背景 #F7F8F6
- 卡片 #F2F4F2 + 左侧 4dp 竹青色条(ClipRRect + 内部 Container,规避 Border+borderRadius uniform 限制)
- 主色锚点 #2D5A52

**新增**(C4 独有):
- 症候矿物色定型:L1=#E8F0EE / L2=#F5E6B8 / L3=#E8C5C5
- 诊断历史时间线:左侧 2dp 竹青竖线 + 8dp 圆点

### 3. 可视化用纯 Flutter 绘制(无第三方库)

- `SeverityBar`:Expanded + flex 按比例填充色块
- `ProficiencyRing`:CustomPaint 画圆环(drawArc + strokeCap.round)
- 诊断历史时间线:Row + Container 竖线 + 圆点

不引入 fl_chart / syncfusion 等图表库,保持依赖最小化。

### 4. GrowthStore 全局单例(非 family)

成长页是用户级视图,不需按 ID 隔离。用 `StateNotifierProvider<GrowthStore, GrowthState>` 全局单例,与 `manuscriptStoreProvider` 模式一致。

### 5. _Card 组件复用

GrowthPage 和 GrowthDetailPage 各自定义 `_Card` private 类(左侧 4dp 竹青色条)。**不抽取公共组件**,因为:
- 两个页面的 _Card 用法略有差异(详情页可能后续加交互)
- 抽取公共组件需新建 `lib/widgets/_card.dart`,但 private 类无法跨文件复用
- 若后续 C5/C6 也需要,再统一抽取为 `lib/widgets/ink_card.dart`

---

## Self-Review 检查

### 1. Spec 覆盖
- ✅ 成长 Tab 从占位页升级为 GrowthPage → Task 5 + Task 7
- ✅ 成长详情页(/growth-detail) + 路由注册 + 成长 Tab 跳转按钮 → Task 6 + Task 7
- ✅ 能力画像(熟练度 + 认知风格 + 总会话数) → Task 5 + Task 6
- ✅ 症候分布可视化(SeverityBar 矿物色) → Task 3 + Task 5 + Task 6
- ✅ 诊断历史时间线 → Task 6
- ✅ 视觉对齐 C1/C3 月色竹青基线 → 所有 Task 的视觉断言
- ✅ 全局聚合(跨 session) → Task 1 + Task 2

### 2. Placeholder 扫描
- 无 TBD / TODO 遗留
- `_handleDiagnose` 仍是 MVP 占位的问题(C1 遗留)与 C4 无关

### 3. 类型一致性
- `GrowthState` / `GrowthStore` / `growthStoreProvider` 命名与 C1 WritingStore 模式一致
- `SeverityCounts` / `SeverityBar` / `ProficiencyRing` 命名清晰
- `ActiveProblemView` / `DiagnosisRow` / `StudentProfile` 均为现有类型,无新建
- `ProficiencyLevel` / `CognitiveStyle` / `Severity` 枚举值已核对(teaching_types.dart)

### 4. 不扩大范围
- 仅修改/新建 14 个文件(均在 C4 文件清单内)
- 不改 WritingPage / WritingCoachPanel / BookshelfPage / ManuscriptDetailPage(C1/C3 已完成)
- 不引入新依赖(fl_chart 等)
- `placeholder_page.dart` 是否删除取决于是否还有其他引用,保守策略:若仅 app_router 引用则删除 import,文件本身保留(避免误删)

### 5. 已知遗留(非本批次范围)
- 全项目无 `darkTheme`:C4 色值硬编码浅色,深色模式适配作为独立批次统一推进
- pre-existing `dao_repository_test.dart persistAttitude` 测试失败:与本批次无关
- `teaching_state` 表无用户级聚合:成长页不展示 current_phase / beginner_level(这些是 session 级概念)
- 训练记录(teachingHistory)未展示:用户确认不需要(C4 决策#2)
