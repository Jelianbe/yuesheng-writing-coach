// ─────────────────────────────────────────────────────────────
// tab_touch_target_test — 三 Tab + 设置页的触控尺寸契约
//
// 真源：`T-20261111-01` U1 设计稿 §TC-3 / §TC-4 / §TC-5（舰长 2026-11-11 批）
//
// 口径（设计稿 §11 第 2 条）：**量行不量文字**。文字 rect 会被内边距缩小，
// 本项目常见 (48-21)/2 = 13.5dp 级误差 ⇒ 一律取「行/可点容器」的 rect。
//
// 48dp = Material 最小触控边长；44dp 是 TC-5 的裁定值（舰长 2026-11-11
// 「都批」认可主理人第 ⑤ 条：该卡一屏最多 5 条，48 会把「思考题回顾」推下 fold）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/ai_account_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/features/app_settings/settings_page.dart';
import 'package:writingcoach/features/growth/growth_page.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/llm_config_storage.dart';

import '../helpers/mock_last_session_storage.dart';

/// 探针用最小 config 存储（不落盘、不读 secure storage）
class _FakeConfigStorage extends LlmConfigStorage {
  @override
  Future<LlmConfigValues?> getLlmConfig() async => null;

  @override
  Future<void> saveLlmConfig(LlmConfigValues config) async {}

  @override
  Future<void> clearLlmConfig() async {}
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// 最近一层可点容器的高度（行 / InkWell / 按钮本体）
  double hitHeight(WidgetTester t, Finder target) {
    final ink = find.ancestor(of: target, matching: find.byType(InkWell));
    if (ink.evaluate().isNotEmpty) return t.getRect(ink.first).height;
    return t.getRect(target.first).height;
  }

  Future<void> seedDiagnosis() async {
    final s = await SessionRepository(db).createBlankSession();
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.diagnosisResults)
        .insert(
          DiagnosisResultsCompanion.insert(
            id: 'dr-touch-1',
            sessionId: s,
            messageId: 'msg-touch-1',
            syndromes: Value(
              jsonEncode([
                {
                  'syndrome_id': 'P002',
                  'name': '信息倾泻',
                  'severity': 'L2',
                  'evidence': ['例1'],
                },
              ]),
            ),
            suggestedActions: const Value('[]'),
            confidence: const Value(0.85),
            timestamp: Value(ts),
            createdAt: Value(ts),
          ),
        );
  }

  // ══════════════════════════════════════════════════════════
  // TC-3：整行入口 44 → ≥48（三处）
  // ══════════════════════════════════════════════════════════
  group('TC-3 整行入口 ≥48dp', () {
    testWidgets('成长·快捷入口行（写作诊断 / 学习进度 / 教学资料）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await seedDiagnosis();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GrowthPage()),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in ['写作诊断', '学习进度', '教学资料']) {
        expect(
          hitHeight(tester, find.text(label)),
          greaterThanOrEqualTo(48),
          reason: '「$label」行原为 44dp（padding 12 + 单行 20）',
        );
      }
    });

    testWidgets('成长·教学设置折叠行', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await seedDiagnosis();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GrowthPage()),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.textContaining('教学设置');
      expect(row, findsOneWidget);
      expect(hitHeight(tester, row), greaterThanOrEqualTo(48));
    });

    testWidgets('设置·ActionRow（添加 / 编辑 API 配置）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            lastSessionStorageProvider.overrideWithValue(
              MemoryLastSessionStorage(),
            ),
          ],
          child: MaterialApp(
            home: SettingsPage(configStorage: _FakeConfigStorage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.text('添加 / 编辑 API 配置');
      expect(row, findsOneWidget);
      expect(hitHeight(tester, row), greaterThanOrEqualTo(48));
    });
  });

  // ══════════════════════════════════════════════════════════
  // TC-4：账号行的「设默认 / 删除」≥48，且两键间距 ≥8（防误触删除）
  // ══════════════════════════════════════════════════════════
  group('TC-4 账号行按键', () {
    setUp(() {
      // createAccount 会写 secure storage 的 key map，测试环境必须 mock
      final secure = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              final key = (call.arguments as Map?)?['key'] as String?;
              switch (call.method) {
                case 'read':
                  return secure[key];
                case 'write':
                  secure[key!] = (call.arguments as Map)['value'] as String;
                  return null;
                case 'delete':
                  secure.remove(key);
                  return null;
              }
              return null;
            },
          );
    });

    testWidgets('删除键 ≥48dp 且与「设默认」间距 ≥8dp', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 两个账号：非默认的那一行才同时有「设默认」与「删除」
      final repo = AIAccountRepository(db);
      await repo.createAccount(
        name: '主账号',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        apiKey: 'sk-main',
      );
      await repo.createAccount(
        name: '备选',
        baseUrl: 'https://api.moonshot.cn/v1',
        model: 'kimi-k3',
        apiKey: 'sk-kimi',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            lastSessionStorageProvider.overrideWithValue(
              MemoryLastSessionStorage(),
            ),
          ],
          child: MaterialApp(
            home: SettingsPage(configStorage: _FakeConfigStorage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final deleteBtn = find
          .ancestor(
            of: find.byIcon(Icons.delete_outline).first,
            matching: find.byType(IconButton),
          )
          .first;
      expect(tester.getRect(deleteBtn).height, greaterThanOrEqualTo(48));

      final setDefault = find.ancestor(
        of: find.text('设默认').first,
        matching: find.byType(TextButton),
      );
      expect(
        tester.getRect(setDefault.first).height,
        greaterThanOrEqualTo(48),
        reason: '「设默认」原也带 compact，一并抬到 48',
      );

      final gap =
          tester.getRect(deleteBtn).left -
          tester.getRect(setDefault.first).right;
      expect(gap, greaterThanOrEqualTo(8), reason: '删除是不可逆动作，不能与「设默认」贴太近');
    });
  });

  // ══════════════════════════════════════════════════════════
  // TC-5：成长·「已想过」≥44dp（舰长裁定值，不是 48）
  // ══════════════════════════════════════════════════════════
  group('TC-5 「已想过」热区', () {
    testWidgets('≥44dp（裁定值，取 48 会把「思考题回顾」推下 fold）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await seedDiagnosis();
      await db
          .into(db.reflectionQuestions)
          .insert(
            ReflectionQuestionsCompanion.insert(
              id: 'rq-touch-1',
              sessionId: 'sess_1',
              messageId: const Value('m-touch-1'),
              question: '为什么这里要留白？',
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GrowthPage()),
        ),
      );
      await tester.pumpAndSettle();

      final btns = find.ancestor(
        of: find.text('已想过').first,
        matching: find.byType(TextButton),
      );
      expect(btns, findsWidgets, reason: '思考题卡应渲染出来');
      expect(
        tester.getRect(btns.first).height,
        greaterThanOrEqualTo(44),
        reason: '原为 ≈15dp（padding 0 + shrinkWrap + minimumSize 0）',
      );
    });
  });
}
