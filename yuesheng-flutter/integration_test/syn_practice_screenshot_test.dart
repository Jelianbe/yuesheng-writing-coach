// ─────────────────────────────────────────────────────────────
// syn_practice_screenshot_test — T-20261119-01 真机走查截图取证
//
// 为什么单独一个文件
// ------------------
// 该卡 `closes` 第 1 要件要求「**真机走查截图**」，这是全文唯一的缺口
// （其余三项已达成：组件级验证 / 四道闸负向用例 / 落库取证）。
// 组件测试（`test/widgets/diagnosis_card_test.dart`）能证明入口**存在**，
// 但证明不了「在真设备上真的画出来了、可点」——那需要跑在 AVD 上并留图。
//
// 本文件做的事（三步，全部走生产组件、零 mock 卡片）：
//   1. 用真 drift 内存库建最小底座（稿件 → 章节 → 会话）；
//   2. 用**生产入口** `DiagnosisCard.fromMessageContent` 渲染诊断卡
//      （payload 与 `diagnosis_flow_handler` 写入云端/本地的形态同构）；
//   3. 展开卡片，断言「就这条开始练」**在真设备上可见**，然后调
//      `IntegrationTestWidgetsFlutterBinding.takeScreenshot` 存图。
//
// ★ 与 §4-551 的关系（不得混为一谈）
// ----------------------------------
// 「就这条开始练」= `SynPracticeBar`（`diagnosis_card_parts.dart:81`），
// 它的渲染条件**只有** `widget.sessionId != null`（`diagnosis_card.dart:1426`），
// **不依赖** `_chapterId`。而 §4-551 修的是「确认指认」/`M2RecallBar`，
// 那两个依赖 `_chapterId`。⇒ 两条链路依赖不同，本截图不受该修复影响。
//
// 运行
// ----
//   flutter test integration_test/syn_practice_screenshot_test.dart -d emulator-5554
//   截图落盘位置由 `takeScreenshot` 的 driver 决定；本文件同时把关键信息
//   打到 stdout（`SHOT-*` 前缀），便于无 driver 时也能作为文字证据。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/theme/app_theme.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';
import 'package:writingcoach/widgets/diagnosis_card_parts.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('真机走查：诊断卡渲染「就这条开始练」入口并可点', (tester) async {
    final msId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '真机走查稿件');
    final chId = await ChapterRepository(
      db,
    ).createChapter(msId, title: '第一章', content: '这是一段用于真机走查的正文。');
    final sid = await SessionRepository(
      db,
    ).getOrCreateSessionForManuscript(msId, chapterId: chId);

    // ★ 用 snake_case 的症候字段（线上 payload 的真实形态，
    //   见 `message_card_service.dart` 的 fromJson 双写兼容）。
    const diagJson =
        '{"syndromeCount":2,"diagnosisId":"shot-diag-1","syndromes":['
        '{"syndrome_id":"P001","name":"情绪标签化","severity":"L2",'
        '"evidence":["她把委屈直接说了出来，没有让读者自己感到。"],'
        '"evidence_count":1,'
        '"explanation":"情绪被直接说出，而非通过动作与场景呈现。"},'
        '{"syndrome_id":"P003","name":"视角漂移","severity":"L3",'
        '"evidence":["上一段还在她的视角，这里忽然跳到了旁观者。"],'
        '"evidence_count":1,'
        '"explanation":"叙述视角未在一个场景内保持一致。"}'
        '],"suggestedActions":["先把最刺眼的一处情绪标签改成动作。"],'
        '"confidence":0.86}';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DiagnosisCard.fromMessageContent(
                diagJson,
                sessionId: sid,
                messageId: 'shot-msg-1',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 解析成功前置断言：否则 fromMessageContent 的 catch 会静默返回空卡，
    // 「入口不存在」与「JSON 解析失败」同形（该坑在同批 event_flow_sim 里踩过）。
    expect(
      find.text('情绪标签化'),
      findsWidgets,
      reason: '症候名须渲染（缺失 ⇒ fromJson 抛错走了空卡兜底）',
    );

    // 展开卡片（症候块在折叠区内，defaultExpanded=false）
    await tester.tap(find.text('本次诊断'));
    await tester.pumpAndSettle();

    // ★ 本卡的判据：每条症候行内都有「就这条开始练」
    final entries = find.text(SynPracticeText.label);
    final count = entries.evaluate().length;
    // ignore: avoid_print
    print('SHOT-syn_practice_label=${SynPracticeText.label} count=$count');
    expect(count, 2, reason: '两条症候 ⇒ 两个「就这条开始练」入口（逐条训练，不是整卡一个）');

    // 可点性：入口必须是可命中（hitTestable）的真按钮，不是纯文本装饰
    expect(
      find.text(SynPracticeText.label).hitTestable(),
      findsWidgets,
      reason: '入口须可命中（否则真机上点不动，等于不存在）',
    );

    // ★ 落图：真设备截图
    //   `takeScreenshot` 需要 integration_test driver 才能把 PNG 取回主机；
    //   在无 driver 的 `flutter test -d` 直跑下它会抛 MissingPluginException。
    //   ⇒ 用 try/catch 兜住：图能落就落，落不了也**不伪造**，如实打印原因。
    try {
      // ★ Android 必须先 convertFlutterSurfaceToImage，否则 takeScreenshot 抛
      //   `Bad state: Call convertFlutterSurfaceToImage() before taking a screenshot`
      //   —— 这是实测报错，不是猜的（本文件第一次跑就撞上）。
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('syn_practice_entry');
      // ignore: avoid_print
      print('SHOT-taken=syn_practice_entry');
    } catch (e) {
      // ignore: avoid_print
      print('SHOT-take_failed（需 driver 模式）: $e');
    }

    // 另外用 `tester.binding` 的本地渲染截图兜底（无需 driver）：
    //   `IntegrationTestWidgetsFlutterBinding` 在设备上跑，这里改为
    //   把当前帧的尺寸与关键 rect 打出来，作为「确实渲染了」的文字证据。
    final rect = tester.getRect(entries.first);
    // ignore: avoid_print
    print('SHOT-entry_rect=$rect');
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));

    // 顺带核对另一条入口（SynPracticeBar 的 key 形如 syn-practice-<id>）
    expect(find.byKey(const Key('syn-practice-P001')), findsOneWidget);
    expect(find.byKey(const Key('syn-practice-P003')), findsOneWidget);
    // ignore: avoid_print
    print('SHOT-keys=ok(P001,P003)');
  });
}
