// ─────────────────────────────────────────────────────────────
// event_flow_sim_test — 模拟数据流端到端：把「埋点到底会不会上报」做成可判读数
//
// 为什么需要这个文件
// ------------------
// `T-20261115-02` 的 `closes` ① 要求「至少 3 种新事件非探针计数 > 0」。
// 云端那三种事件长期 0 行，但 **0 行不可定性**（`MEASUREMENT.md §2.3`）：
// 既可能是「没人走到」，也可能是「埋点根本没发」。2026-11-23 AVD 走查已定死
// 第一层根因是 `PlatformQuotaConfig.isConfigured == false`（构建未带 dart-define）
// ⇒ `record()` 首行就 return，事件连构造都不发生。
//
// 本文件解决的是「**验证**」问题，不是「补流量」问题：
//   · 用既有注入口 `InteractionEventService.debugEndpointOverride` 把上报
//     指向**本机 mock 接收器**（`adb reverse tcp:8765` 转发）；
//   · 用 `debugConfiguredOverride = true` 打开开关；
//   · 然后调**真实调用点**（仓储），让 `record()` 真的发 HTTP。
//
// ★★ 覆盖边界（2026-11-23 独立审查后订正，原写「等价于带 define 构建」是**高估**）
// ---------------------------------------------------------------------------
// `debugConfiguredOverride = true` 把 `isConfigured` **替换成常量**，而本次生产根因
// 恰恰是「define 没带 ⇒ `isConfigured` 为 false」。所以：
//   能证：通道打开后，这四个调用点会真的发出合规的行
//   不能证：**打包后的 APK 通道是开的**（那是 `String.fromEnvironment` 的事，
//           `grep -rn debugConfiguredOverride integration_test/` 只命中本文件
//           ⇒ 当前**没有任何用例**验证「带 define 构建后 isConfigured == true」）
// ⇒ 本文件全绿**不可**被引为 `T-20261115-02` L1（构建参数）已闭合的证据。
//
// 证据分级（2026-11-23 审查订正：原把第二档标成 E2，实为 E3）
// ---------------------------------------------------------------
//   · 「事件发出并到达 mock，且行内容符合契约」= **E1（实测）**
//   · 「真实云端会接受这些行」= **E3（推断）**，不是 E2。理由：mock 明确不模拟
//     准入三闸里的两项半 —— ① access-key 校验（只在空时 WARN）
//     ② `event_type` CHECK（只 WARN 不拒）③ `source` CHECK（完全不看）。
//     （RLS 不构成风险：`MEASUREMENT.md` 实测只有一条 `with_check=true` 的
//      INSERT 策略 ⇒ 不拒行。）
//
// 探针隔离现状（如实登记，不粉饰）
// ------------------------------
// `MEASUREMENT.md §5 P3` 要求探针行**同时**带 `payload.probe=true` **和**
// `session_tag` 的 `probe-`/`spike-` 前缀。本文件两条都做不到：
//   · `training_completed` / `reflection_reviewed` 的 payload 由仓储单点构造，
//     **不接受** probe 参数（`training_result_repository.dart:131-135`、
//     `reflection_question_repository.dart:68`）；
//   · `session_tag` 取会话 UUID，无法注入前缀。
// ⇒ 本文件靠 **endpoint 强制 loopback** 做物理隔离（见 setUp 的守卫断言），
//   而不是靠 probe 标记。这条隔离**没有机器以外的人工保障**，故加了守卫。
//
// 运行
// ----
//   1. 主机起接收器：python .ai/tools/mock_event_sink.py --port 8765 --out ...
//   2. adb reverse tcp:8765 tcp:8765
//   3. flutter test integration_test/event_flow_sim_test.dart -d emulator-5554
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reflection_question_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/training_result_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/services/interaction_event_service.dart';
import 'package:writingcoach/theme/app_theme.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';

/// 本机 mock 接收器地址（设备内 127.0.0.1:8765 经 `adb reverse` 到主机）。
const String kSimEndpoint = 'http://127.0.0.1:8765';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late String sessionId;
  late String chapterId;
  HttpOverrides? savedHttpOverrides;

  setUp(() async {
    // ★★ 关键：`flutter_test` 默认给 `HttpClient` 装了 mock（一律返回 400），
    //    目的是让单测不发真网络。本文件**就是要发真网络**（打到本机 mock 接收器），
    //    故必须显式清掉它。实测未清时症状：
    //      `[interaction_event] training_completed 云端返回 HTTP 400（不阻断）`
    //    —— 看着像「服务端拒收」，实际是请求**从未离开设备**。
    //    （这正是本项目 `flutter-test-real-network` 那条坑的同一形态。）
    //    保存原值，tearDown 还原：本文件与其它 integration_test 并存时，
    //    把全局 HttpOverrides 永久置 null 会让「本该被拦的用例」悄悄放行。
    savedHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;

    db = AppDatabase.forTesting(NativeDatabase.memory());

    // ★ 打开上报通道：等价于「构建时带了 --dart-define」。
    //   两个 override 是本文件与被测代码之间**唯一**的接缝；被测逻辑一行未改。
    InteractionEventService.debugConfiguredOverride = true;
    InteractionEventService.debugEndpointOverride = kSimEndpoint;
    InteractionEventService.debugKeyOverride = 'sim-local-key';
    InteractionEventService.anonId = null; // 不冒充真实设备身份

    // ★★ D4：endpoint 机器守卫（审查 P2 落地）
    //   为什么必须有：本文件的 payload 里**注入不了** `probe` 键
    //   （见文件头「探针隔离现状」），探针标记这条防线是缺的。
    //   若有人把上面那行 endpoint 覆盖注释掉、又直接把 kSimEndpoint 改成
    //   生产地址，四种事件就会以「非探针、source=app」的身份进生产库，
    //   而**所有断言照样绿**（生产库计数也会涨）。
    //   ⇒ 用 loopback 断言把「物理隔离」变成机器可判的失败。
    final ep = Uri.parse(InteractionEventService.debugEndpointOverride!);
    final host = InternetAddress.tryParse(ep.host);
    final isLoopback =
        (host != null && host.isLoopback) ||
        ep.host == 'localhost' ||
        ep.host == '::1';
    expect(
      isLoopback,
      isTrue,
      reason:
          'endpoint 必须是 loopback（当前=${ep.host}）——本文件发的是无 probe 标记的'
          '「非探针」行，指向非本机地址会把模拟数据写进真实库',
    );

    // 建最小数据底座：稿件 → 章节 → 会话
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final sid = SessionRepository(db);
    final manuscriptId = await msRepo.createManuscript(title: '模拟流稿件');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: '这是一个用于模拟数据流的章节。',
    );
    sessionId = await sid.getOrCreateSessionForManuscript(
      manuscriptId,
      chapterId: chapterId,
    );
  });

  tearDown(() async {
    InteractionEventService.debugConfiguredOverride = null;
    InteractionEventService.debugEndpointOverride = null;
    InteractionEventService.debugKeyOverride = null;
    InteractionEventService.anonId = null;
    HttpOverrides.global = savedHttpOverrides; // 还原，不污染同进程其它用例
    await db.close();
  });

  testWidgets('模拟数据流：四种 App 侧事件能真的发出并到达接收器', (tester) async {
    // 确认 override 在**测试体内**生效（binding 可能在 setUp 之后重设）
    HttpOverrides.global = null;

    // ── 0. 基线：必须先取，判据一律用**增量**而非绝对计数 ──
    //
    // ★ 这条是被负向变异逼出来的：初版用「绝对计数 > 0」，
    //   结果把 `debugConfiguredOverride` 注释掉后**照样绿** ——
    //   因为读的是上一次运行残留在接收器里的累计值。
    //   ⇒ 绝对计数不能当判据（`MEASUREMENT §2.1` 同款陷阱：
    //     「不得用 id 差当事件增量」，其反面即「不得用累计值当本次增量」）。
    final before = await _fetchStats();
    // ignore: avoid_print
    print('SIM-BEFORE by_type=$before');

    /// 某类型「本次运行造成的增量」。通道关着时它必须是 0。
    int delta(String t, Map<String, int> now) =>
        (now[t] ?? 0) - (before[t] ?? 0);

    /// 轮询直到该类型的**增量**恰为 want，否则超时失败。
    ///
    /// ★ 2026-11-23 审查订正（D2）：原判据是 `>= want`，只有下界。
    ///   后果：**重复上报对它不可见** —— 若某调用点被改成一次写两行
    ///   （例如仓储重试、或 `record` 被调用两次），`delta` 会变成 2，
    ///   而 `>= 1` 照样绿。埋点系统的典型缺陷恰恰是「多发」不是「少发」
    ///   （多发给云端带来脏数据与成本，少发只是缺口）。
    ///   ⇒ 改为 `== want`，把上界也钉住。
    Future<Map<String, int>> waitForDelta(
      String eventType, {
      int want = 1,
      Duration timeout = const Duration(seconds: 15),
    }) async {
      final deadline = DateTime.now().add(timeout);
      Map<String, int> last = before;
      while (DateTime.now().isBefore(deadline)) {
        last = await _fetchStats();
        if (delta(eventType, last) == want) return last;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      fail(
        'mock 接收器未收到新增的 $eventType（期望 +$want，'
        '基线=${before[eventType] ?? 0}，实际=${last[eventType] ?? 0}'
        '，增量=${delta(eventType, last)}）\n$_diagHint',
      );
    }

    // ── 1. training_completed（真源：TrainingResultRepository.insertTrainingResult:130）──
    final trRepo = TrainingResultRepository(db);
    final trainingId = await trRepo.insertTrainingResult(
      InsertTrainingResultParams(
        sessionId: sessionId,
        syndromeId: 'P001',
        taskType: 'rewrite',
        userContent: '模拟作答内容',
        result: 'passed',
      ),
    );
    expect(trainingId, isNotEmpty);
    await waitForDelta('training_completed');

    // ★ D1：行内容断言（真源 training_result_repository.dart:129-135）
    final trainRow = await _lastRowOf('training_completed', sessionId);
    expect(trainRow['source'], 'app');
    expect(trainRow['session_tag'], sessionId);
    final trainPayload = (trainRow['payload'] as Map).cast<String, Object?>();
    expect(
      trainPayload.keys.toSet(),
      {'syndrome_id', 'task_type', 'armed_by_suggestion'},
      reason: 'training_completed 的 payload 键集须与仓储单点构造逐字一致',
    );
    expect(trainPayload['syndrome_id'], 'P001');
    expect(trainPayload['task_type'], 'rewrite');
    expect(
      trainPayload['armed_by_suggestion'],
      isFalse,
      reason: '本次未经推荐武装，须为 false（若恒 true 则推荐链路统计全失真）',
    );

    // ── 2. reflection_reviewed（真源：ReflectionQuestionRepository.markReviewed:67）──
    final rqRepo = ReflectionQuestionRepository(db);
    await rqRepo.insertQuestions([
      ReflectionQuestionsCompanion.insert(
        id: 'sim-q-1',
        sessionId: sessionId,
        question: '这段情绪为什么用直白写法？',
        syndromeId: const Value('P001'),
      ),
    ]);
    await rqRepo.markReviewed('sim-q-1');
    await waitForDelta('reflection_reviewed');

    // ★ D1：行内容断言（真源 reflection_question_repository.dart:66-70）
    final reflRow = await _lastRowOf('reflection_reviewed', sessionId);
    expect(reflRow['source'], 'app');
    expect(reflRow['session_tag'], sessionId);
    final reflPayload = (reflRow['payload'] as Map).cast<String, Object?>();
    expect(reflPayload.keys.toSet(), {'review_count'});
    expect(reflPayload['review_count'], 1);

    // ── 3. anchor_ack（真源：**UI 层** diagnosis_card.dart:351）──
    //   ★ 2026-11-23 审查订正：初版在这里**手写**了一份 `record(eventType:'anchor_ack')`，
    //     并在 payload 里塞 `probe:true`。那是**自证**（用我写的一行去证明另一行能跑），
    //     而且造出了**生产路径永不产生的行形态**（生产没有 probe 键）。
    //   现改为走真实 widget：渲染 DiagnosisCard → 点「确认指认」→ 由
    //     `_acknowledgeEvidence`（:336）先落端侧、再 record（:351）真实发出。
    //   顺带覆盖了 `:338` 的守卫（sessionId/chapterId 皆非空才继续）。
    // ★ JSON 键名是**实测对着 fromJson 写的**，不是凭直觉写的。
    //   2026-11-23 连错三次的根因就在这：
    //   ① 顶层 `syndromeCount` 是**驼峰**（message_card_service.dart:101
    //      只读 `json['syndromeCount']`，不吃 snake）——我原写 `syndrome_count`
    //      ⇒ 恒 0（不影响渲染，但有误导性）；
    //   ② 症候内 `evidence` 有值但 `evidence_count` 缺 ⇒
    //      `count = 0` ⇒ `_SyndromeBlock` 走 `count == 0` 的「无证据」分支
    //      （:1793-1794）⇒ **证据 toggle 根本不渲染** ⇒ 连「展开证据」都找不到。
    //      ⇒ 这就是「断言写在注释上、没写在键名上」的代价。
    const diagJson =
        '{"syndromeCount":1,"syndromes":[{"syndrome_id":"P001",'
        '"name":"叙事含糊","severity":"L2","evidence":["模拟指认片段"],'
        '"evidence_count":1,'
        '"explanation":"情绪直接说出而非展现"}],"suggestedActions":[],'
        '"confidence":0.8}';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: DiagnosisCard.fromMessageContent(
              diagJson,
              sessionId: sessionId,
              messageId: 'sim-msg-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ★ 先钉「JSON 解析成功」（否则 fromMessageContent 的 catch 会**静默**
    //   返回空卡，症状是「卡片渲染了但什么都没」，极难定位 —— 本轮连错三次
    //   都耗在这一点上）。判据：解析成功才会出现症候名与问题数。
    expect(
      find.text('叙事含糊'),
      findsWidgets,
      reason: '症候名须渲染（缺失 ⇒ fromJson 抛错走了空卡兜底，或 syndrome_id 键名错）',
    );

    // ★★ 三级前置条件（2026-11-23 实跑后**逐层**订正 —— 原以为「渲染就有
    //    确认指认」，连错两次：第一次找不到「确认指认」，第二次连
    //    「展开证据」都找不到）：
    //   ① 整张卡 `defaultExpanded = false`（:193）⇒ 症候块**根本没渲染**。
    //      须点表头「本次诊断」触发 `_toggleExpanded`（:855 的 InkWell）。
    //   ② `_evidenceExpanded` 初值 false（:1522）⇒ 证据原文折叠，
    //      「确认指认」在展开区里 ⇒ 须点「▸ 展开证据」。
    //   ③ `onAcknowledgeEvidence` 仅在 `sessionId != null && _chapterId.isNotEmpty`
    //      时下传（:1387-1390），而 `_chapterId` 由 `_resolveChapterId()`
    //      **异步反查**（initState :284，且**不 setState**）⇒ 首帧为 null，
    //      要靠后续任一次 setState 才「带出来」。
    //
    //    ★ 这三级顺带暴露一个真实产品行为（记一笔，不属本卡范围）：
    //      卡片默认折叠 + 章节反查不 setState ⇒ 真实使用中用户要「先展开卡片、
    //      再展开证据」两步才见确认入口；且若反查慢于首次 setState，
    //      用户第一次展开时会看到**没有**确认指认，需再触发一次重建才出现。
    //      本测试用「收起再展开」把它挡住；产品侧是否该在
    //      `_resolveChapterId` 成功后补 `setState` 是独立问题。
    expect(find.text('本次诊断'), findsWidgets, reason: '诊断卡表头须渲染（折叠态唯一可见的展开入口）');
    await tester.tap(find.text('本次诊断').first);
    await tester.pumpAndSettle();

    expect(find.text('▸ 展开证据（1 处）'), findsWidgets, reason: '展开卡片后须渲染证据展开入口');
    await tester.tap(find.text('▸ 展开证据（1 处）').first);
    await tester.pumpAndSettle();

    // 展开后仍无确认指认 ⇒ 多半 `_chapterId` 反查慢于本次重建，再推一轮。
    if (find.text('确认指认').evaluate().isEmpty) {
      await tester.tap(find.text('▾ 收起证据（1 处）').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('▸ 展开证据（1 处）').first);
      await tester.pumpAndSettle();
    }
    expect(
      find.text('确认指认'),
      findsWidgets,
      reason:
          '证据块须渲染出确认指认入口（否则 anchor_ack 无从触发）；'
          '若此处失败，先查 `_chapterId` 是否已从 sessionId 反查成功',
    );
    await tester.tap(find.text('确认指认').first);
    await tester.pumpAndSettle();
    await waitForDelta('anchor_ack');

    // ★ D1：行内容断言（不只数类型计数）
    //   审查判定：只断言「某类型 +1」是**计数痕迹**，而项目纪律
    //   （`PRACTICES.md:91`）要求断言**结果痕迹**。计数痕迹查不出
    //   「发了但 payload 是错的 / session_tag 串了会话 / source 被改」。
    final ackRow = await _lastRowOf('anchor_ack', sessionId);
    expect(ackRow['source'], 'app', reason: 'source 必须固定 app');
    expect(
      ackRow['session_tag'],
      sessionId,
      reason: 'session_tag 必须是本会话（串了会话则复盘按会话聚合全错）',
    );
    final ackPayload = (ackRow['payload'] as Map).cast<String, Object?>();
    // ★ 生产路径的 payload **只有两个键**（diagnosis_card.dart:351-355）：
    //   chapter_id / message_id。这里钉死键集，正是为了防我初版那种
    //   「手写 payload 多塞 probe 键」的伪造行再次出现。
    expect(
      ackPayload.keys.toSet(),
      {'chapter_id', 'message_id'},
      reason: 'anchor_ack 的 payload 键集须与生产路径逐字一致（不接受 probe 等额外键）',
    );
    expect(
      ackPayload['chapter_id'],
      chapterId,
      reason: 'chapter_id 须由 _resolveChapterId 从 sessionId 反查得到（非空、且指向本章）',
    );
    expect(
      ackPayload['message_id'],
      'sim-msg-1',
      reason: 'message_id 须透传触发它的诊断消息 id',
    );
    // 隐私口径：anchor_ack **不传稿件文本**（对齐 web）。evidence 文本只进端侧表。
    expect(
      jsonEncode(ackPayload).contains('模拟指认片段'),
      isFalse,
      reason: 'anchor_ack payload 不得含证据原文（隐私口径：只传结构化标识）',
    );

    // ── 4. diagnosed（真源：DiagnosisFlowHandler → recordDiagnosed:749）──
    //   ⚠️ 如实登记：这里只调**封装方法**，未走完整诊断编排。
    //   真实链路里 `recordDiagnosed` 与 5 个落库 await 同处
    //   `diagnosis_flow_handler.dart:720-756` 的**一个 try** 内 ⇒ 任一落库失败，
    //   埋点会**静默消失**（只进 `_logSafeRun`）。这条耦合本文件**未覆盖**，
    //   已在台账登记为独立待查项（不在此假装覆盖）。
    InteractionEventService.recordDiagnosed(
      sessionId,
      const ['P001', 'P002'],
      materialText: 'A' * 240, // ≥200 ⇒ 会带 text_fp
    );
    final after = await waitForDelta('diagnosed');

    // ★ D1（审查 C3 点名要求）：`diagnosed` 是唯一带稿件指纹的事件，
    //   我在上面特意造了 240 字符的 materialText，若不断言就等于白造。
    //   这三个字段是 web/App 跨端对账的锚：`text_len` 用于判断「同一份材料
    //   重诊」，`text_fp` 用于判重（16 位 sha 前缀，见 `_fp16`）。
    final diagRow = await _lastRowOf('diagnosed', sessionId);
    expect(diagRow['source'], 'app');
    expect(diagRow['session_tag'], sessionId);
    final diagPayload = (diagRow['payload'] as Map).cast<String, Object?>();
    expect(diagPayload.keys.toSet(), {
      'syndromes',
      'syndrome_count',
      'text_len',
      'text_fp',
    });
    expect((diagPayload['syndromes'] as List).toList(), ['P001', 'P002']);
    expect(diagPayload['syndrome_count'], 2);
    expect(
      diagPayload['text_len'],
      240,
      reason: 'text_len 须等于实际材料长度（造了 240 字符就必须读到 240）',
    );
    expect(
      diagPayload['text_fp'],
      hasLength(16),
      reason: 'text_fp 是 sha256 前 16 位（_fp16），长度须恰为 16',
    );
    // 隐私口径：**指纹可传、原文不可传**。这条是防「哪天有人把 materialText
    // 直接塞进 payload」的回归线。
    expect(
      jsonEncode(diagPayload).contains('A' * 40),
      isFalse,
      reason: 'diagnosed payload 不得含材料原文（只传 len + fp）',
    );

    // ── 5. 汇总：closes ① 字面要求「≥3 种事件计数 > 0」──
    //     本模拟覆盖 4 种，但它们是**模拟行** ⇒ 只能写「链路可达」，
    //     不能写「closes ① 已达成」（后者要求的是非探针真人数据）。
    // ignore: avoid_print
    print('SIM-AFTER by_type=$after');

    final covered = [
      'training_completed',
      'reflection_reviewed',
      'anchor_ack',
      'diagnosed',
    ].where((e) => delta(e, after) == 1).toList();

    // ★ 2026-11-23 审查订正（D2）：原写 `greaterThanOrEqualTo(3)` 是**装饰性断言** ——
    //   上面四个 `waitForDelta` 已各自成功（`== want` 才会走到这里）
    //   ⇒ `covered.length` 必然 = 4 ⇒ 这条断言恒真、零鉴别力。
    //   改成 `== 4`：它现在的唯一作用是把「四个都在」这件事写成可读的总结句，
    //   并且一旦上面有人改成 `>=` 或放宽 `want`，这里会立刻变成真正的红线。
    expect(
      covered.length,
      4,
      reason:
          '本次模拟须覆盖 4 种事件（实测增量：'
          '${covered.map((e) => '$e+${delta(e, after)}').join(', ')}）',
    );

    // ★ 反证「零探针污染」：这四行必须能被「非探针」口径统计到
    //   （`MEASUREMENT §5 P3` 的口径是「有 probe 或有 probe- 前缀即排除」）。
    //   本文件无法注入 probe（见文件头），故它们天然是**非探针形态**；
    //   但这正是危险所在 —— 若 endpoint 泄漏到生产，它们会被当成真人数据。
    //   ⇒ 这里只断言「形态」，隔离靠 setUp 的 loopback 守卫。
    for (final r in [trainRow, reflRow, ackRow, diagRow]) {
      final p = (r['payload'] as Map).cast<String, Object?>();
      expect(p.containsKey('probe'), isFalse, reason: '模拟行不得带 probe 标记');
      expect(
        '${r['session_tag']}'.startsWith('probe-') ||
            '${r['session_tag']}'.startsWith('spike-'),
        isFalse,
        reason: 'session_tag 不带 probe-/spike- 前缀（故须靠 loopback 物理隔离）',
      );
    }
  });
}

/// 读 mock 接收器 `/__stats`。
Future<Map<String, int>> _fetchStats() async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('$kSimEndpoint/__stats'));
    req.headers.set('connection', 'close');
    final res = await req.close().timeout(const Duration(seconds: 3));
    final body = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 3));
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final byType = (decoded['by_type'] as Map?) ?? const {};
    return {
      for (final e in byType.entries)
        if (e.value is int) '${e.key}': e.value as int,
    };
  } finally {
    client.close(force: true);
  }
}

/// 读 mock 接收器全部行。
Future<List<Map<String, Object?>>> _fetchRows() async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('$kSimEndpoint/__rows'));
    req.headers.set('connection', 'close');
    final res = await req.close().timeout(const Duration(seconds: 3));
    final body = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 3));
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final rows = (decoded['rows'] as List?) ?? const [];
    return [
      for (final r in rows)
        if (r is Map) r.cast<String, Object?>(),
    ];
  } finally {
    client.close(force: true);
  }
}

/// 取「属于本会话、该类型」的**最后一行**。
///
/// 为什么按 `session_tag` 过滤而不是取全局最后一行：接收器是**跨运行累积**的
/// （本文件跑一次写 4 行，跑 N 次就有 4N 行，且历史版本还留下过 `sim-probe`
/// 之类的行）。若取全局最后一行，断言可能读到**上一次运行**的残留，
/// 于是「本轮 payload 写错」也会绿 —— 那正是 `MEASUREMENT §2.1`
/// 「不得用累计值当本次增量」的同一形态。
///
/// 按 `sessionId`（每个 setUp 新建）过滤即天然隔离本轮。
Future<Map<String, Object?>> _lastRowOf(
  String eventType,
  String sessionId,
) async {
  final rows = await _fetchRows();
  final hit = rows
      .where((r) => r['event_type'] == eventType)
      .where((r) => r['session_tag'] == sessionId)
      .toList();
  expect(
    hit,
    isNotEmpty,
    reason:
        '接收器里找不到 event_type=$eventType 且 session_tag=$sessionId 的行\n'
        '$_diagHint',
  );
  if (hit.length > 1) {
    fail(
      'event_type=$eventType 在会话 $sessionId 下出现了 ${hit.length} 行（期望恰 1 行）——'
      '重复上报（`waitForDelta` 的 `== want` 已判到计数，这里判到行）',
    );
  }
  return hit.single;
}

/// 失败时的归因提示。审查 D3 指出：`400 / 埋点静默失败 / 连接被拒 / mock 没起`
/// 四种病因在旧报文里**同形**（都只是「没收到」），排查时无法区分。
const String _diagHint =
    '排查顺序：\n'
    '  ① 接收器起了吗 —— 主机执行 `curl http://127.0.0.1:8765/__stats`\n'
    '  ② 端口转发活着吗 —— `adb reverse --list`（须见 tcp:8765）\n'
    '  ③ 上报被拒了吗 —— 测试输出里搜 `[interaction_event]`（400 = 请 求未离开设备，'
    '即 HttpOverrides 未清）\n'
    '  ④ 通道开着的吗 —— setUp 里 `debugConfiguredOverride` 是否为 true';
