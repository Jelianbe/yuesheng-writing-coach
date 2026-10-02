// ─────────────────────────────────────────────────────────────
// live_m2recall_baseline_test — ADR-C136 项3：M2 复述根因确认行为基线
//
// ★ 开工勘察结论（决定本面形态，务必先读）★
//  逐项核对 C133 M2 链路后确认：**M2 的 confirmed/corrected 并非 LLM prompt
//  驱动**，而是本地 UI 的「人工显式选择」：
//    - lib/widgets/m2_recall_bar.dart（整文件，尤其 13–20 行设计取舍注释）：
//      本批**不把复述自动派发进对话流、也不加 prompt 标记解析**；学员在
//      TextField 提交复述后进入 picking 阶段，由教练点「复述到位」(confirmed)
//      /「需修正」(corrected) 两个按钮 → _commitVerdict → recordM2Recall。
//      全程无任何 LLM 调用、无 prompt 据复述文本判定对错。
//    - lib/data/repositories/edit_diff_event_repository.dart recordM2Recall：
//      只按传入 verdict 落库（append-only 留痕）；R-009 不计算「复述是否到位」。
//    - lib/services 全量 grep「复述/recall/M2」：无任何一段 prompt 消费学员
//      复述文本并输出 confirmed/corrected（命中的「复述」均为教练侧话术指引，
//      与本判定无关）。
//  ⇒ ADR-C136 项3 的前提「教练确认行为是否按现有 prompt 表现」与实现不符：
//     不存在「现有 prompt」在驱动 confirmed/corrected 倾向。按任务纪律
//     「非 LLM 驱动 → 如实记录偏差，不强行制造 LLM 调用」，本面**不构造 LLM
//     回放**：live 组直接 skip 并留证据（有 key 时预算实际消耗 = 0 次）；
//     常驻自检组改为确定性断言**真实已实现的基线**（verdict 为人工显式值、
//     原样落库、R-009 无自动对错判定）。
//
// tag 说明（与任务字面「库级 @Tags」的偏差及理由）：
//  先例 live_interface_comparison_test.dart 的双组结构**不使用库级 tag**，只给
//  live 测试打 tags:['live','external']。原因：库级 @Tags 会传染到本文件的常驻
//  自检组，使门禁 `--exclude-tags live,external` 把常驻组一并排除，违背「常驻组
//  必须在门禁全量中执行」。故照先例：常驻组不打 tag（门禁跑），live 测试打
//  tags:['live','external']（门禁排除）。
//
// R-029：本文件不含任何 key 字面量；不写临时文件；无网络调用。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';

void main() {
  late AppDatabase db;
  late EditDiffEventRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = EditDiffEventRepository(db);
  });

  tearDown(() async => db.close());

  // ── 常驻自检组（不打 live/external tag → 门禁全量执行；确定性、无 key、无网络）──
  // 断言「真实已实现基线」：verdict 是人工显式选择的值，系统原样落库，不据复述
  // 文本自动判定对错（R-009）。两样本对应贴切/偏误两种教学结局。
  group('M2 复述确认·常驻基线自检（无 key 可跑）', () {
    test('贴切复述样本 → 教练选 confirmed：复述/根因/verdict 原样落库', () async {
      // 已诊断根因（= 症候 explanation「为什么」行，C133 既有测试先例）。
      const rootCause = '开篇用程式化套语（天气/时光流逝），未把读者直接带入冲突。';
      // 学员用自己的话贴切复述（语义正确，非照抄）。
      const goodRecall = '他一上来先写天气怎么变、时光怎么过，读者还没碰到主角要面对的事就已经疲了。';

      await repo.recordM2Recall(
        sessionId: 's-m2',
        chapterId: 'c-good',
        syndromeId: 'SYN_open',
        syndromeName: '开头俗套',
        recallText: goodRecall,
        rootCauseText: rootCause,
        verdict: M2RecallVerdict.confirmed, // 教练核对后点「复述到位」
      );

      final e = (await repo.listByChapter('c-good')).single;
      expect(e.eventType, EditDiffEventTypes.anchorAck);
      // 复述文本原样留痕（系统不改写）。
      expect(e.afterText, goodRecall);
      expect(e.beforeText, rootCause);
      final p = M2RecallPayload.tryDecode(e.payload);
      expect(p, isNotNull);
      expect(p!.verdict, M2RecallVerdict.confirmed);
      expect(p.syndromeId, 'SYN_open');
    });

    test('偏误复述样本 → 教练选 corrected：事件仍落库留证据卡，verdict=corrected', () async {
      const rootCause = '开篇用程式化套语，未把读者带入冲突。';
      // 学员歪曲/答非所问（把根因错记成「句子太长」）。
      const badRecall = '我开头的句子写得太长了，应该再短一点。';

      await repo.recordM2Recall(
        sessionId: 's-m2',
        chapterId: 'c-bad',
        syndromeId: 'SYN_open',
        syndromeName: '开头俗套',
        recallText: badRecall,
        rootCauseText: rootCause,
        verdict: M2RecallVerdict.corrected, // 教练核对后点「需修正」
      );

      final e = (await repo.listByChapter('c-bad')).single;
      final p = M2RecallPayload.tryDecode(e.payload);
      expect(p, isNotNull);
      expect(p!.verdict, M2RecallVerdict.corrected);
      // 偏误复述仍原样留痕（证据卡可见，不计候选）。
      expect(e.afterText, badRecall);
    });

    test('R-009：系统不据复述文本自动判定——贴切复述也可落 corrected（无自动对错）', () async {
      // 关键：verdict 由人工传入，系统不读 recallText 内容做匹配/打分。
      // 即便复述贴切，教练若选 corrected 也如实落库（无自动纠正/拦截）。
      await repo.recordM2Recall(
        sessionId: 's',
        chapterId: 'c-r009',
        syndromeId: 'SYN_open',
        recallText: '他写天气套话开头，没把读者带进冲突。', // 语义贴切
        verdict: M2RecallVerdict.corrected, // 人工选 corrected，系统不拦截/不改判
      );
      final e = (await repo.listByChapter('c-r009')).single;
      final p = M2RecallPayload.tryDecode(e.payload);
      expect(p, isNotNull);
      expect(p!.verdict, M2RecallVerdict.corrected);
      // payload 无任何自动成败字段。
      expect(e.payload.contains('score'), isFalse);
      expect(e.payload.contains('passed'), isFalse);
      expect(e.payload.contains('"level"'), isFalse);
      expect(e.payload.contains('达标'), isFalse);
    });

    test('边界：非法 verdict 拒绝落库', () async {
      expect(
        () => repo.recordM2Recall(
          sessionId: 's',
          chapterId: 'c-badv',
          syndromeId: 'SYN_x',
          recallText: '复述……',
          verdict: 'passed',
        ),
        throwsArgumentError,
      );
      expect(await repo.listByChapter('c-badv'), isEmpty);
    });
  });

  // ── live 组（tagged live+external；门禁 --exclude-tags live,external 排除）──
  // 勘察已证：确认行为非 LLM 驱动，无真实回放对象。按纪律不制造 LLM 调用，
  // 无论有无 key 都 skip 并留证据（有 key 时本面预算实际消耗 = 0 次 / 上限 6）。
  group('M2 复述确认·真实 LLM 回放（@live @external）', () {
    test(
      '项3 真实回放：confirmed/corrected 是否按现有 prompt 表现',
      () async {
        final hasKey = Platform.environment.containsKey('DEEPSEEK_API_KEY');
        // ignore: avoid_print
        print(
          '[M2-recall-baseline] DEEPSEEK_API_KEY present=$hasKey '
          '→ 勘察结论：确认由 m2_recall_bar.dart 人工按钮显式选择，'
          '非 LLM prompt 驱动，无回放对象，不制造 LLM 调用（预算消耗 0/6）。',
        );
        markTestSkipped(
          'C136 项3 偏差如实记录：M2 confirmed/corrected 为本地 UI 人工显式选择'
          '（lib/widgets/m2_recall_bar.dart 13-20 行 + _commitVerdict），学员复述'
          '未派发进对话流、无 prompt 判定对错；不存在「现有 prompt」驱动确认倾向，'
          '故不构造真实 LLM 回放（费用护栏 0 次）。',
        );
      },
      tags: const ['live', 'external'],
    );
  });
}
