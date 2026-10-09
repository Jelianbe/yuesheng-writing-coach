// ─────────────────────────────────────────────────────────────
// history_evidence_isolation_test — 喂 LLM 的 history 副本剔除诊断卡
// （P1 · 外部反馈 2026-10-08）
//
// 根因（逐字实测，见 message_assembly_service 的白名单常量注释）：
//   `insertDiagnosisResultCard` 把 payload JSON 落成 role='system' /
//   messageType='diagnosis_result' 消息，其中 `syndromes[].evidence` 是
//   **学员原文的逐字引用**；`_appendHistory` 不看 messageType、原样全量追加
//   （窗口 20–29 条）⇒ 旧证据句能存活 10 轮以上。学员改完文本回来二次诊断时，
//   模型逐字复制旧证据句比在「## 待诊断全文」里重新定位便宜得多 ⇒
//   「明明改了还照样指出来、引的还是原来那句」。
//
// 本测试的判据核心 = **负向验证必须能红**：
//   断言过滤前标记串确实在 history 里（否则「过滤后不在」是恒真的空断言）。
//
// 数据来源走仓内既有范式（dao_repository_test.dart:205-215）：
//   AppDatabase.forTesting(NativeDatabase.memory()) + SessionRepository真实
//   addMessage 链路 ⇒ 无需手搓 drift Message 构造器、无需装配 8 个 required 依赖。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/features/onboarding/novice_mode_guide.dart'
    show kNoviceMessageType;
import 'package:writingcoach/services/message_assembly_service.dart';

/// 唯一标记串：模拟「上一轮诊断卡里逐字引用的学员原文证据句」。
/// 真实载体是 payload JSON 的 `syndromes[].evidence`，此处只需验证该串在
/// history 副本中被切断。
const String kOldEvidenceMarker = '他很悲伤地离开了。';

/// 构造一条含标记串的诊断卡 payload JSON（形态照 message_card_service.dart:
/// `insertDiagnosisResultCard` → `jsonEncode(payload.toJson())`）。
String _diagnosisCardJson() {
  return '{"syndromeCount":1,"syndromes":[{"syndromeId":"P011",'
      '"name":"信息倾泻症","severity":"L2",'
      '"evidence":["$kOldEvidenceMarker"],"evidenceCount":1}],'
      '"suggestedActions":[],"confidence":0.8,"diagnosisId":"d1"}';
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();

    // 本轮 user 消息（messageType 走 tables.dart 默认值 'chat'）——
    // 这是「剔除后必须仍含本轮 user 消息」不变量所依赖的那一条。
    await sessionRepo.addMessage(sessionId, 'user', '我改完了，再帮我看看这一章');
    // P1 的元凶：role='system' + messageType='diagnosis_result' + JSON 内逐字证据。
    await sessionRepo.addMessage(
      sessionId,
      'system',
      _diagnosisCardJson(),
      messageType: 'diagnosis_result',
    );
    // C123 的既有剔除面：纯新手模式问答。
    await sessionRepo.addMessage(
      sessionId,
      'user',
      '我完全不会写，从零开始教我吧',
      messageType: kNoviceMessageType,
    );
    // 普通 assistant 气泡（messageType='chat'）—— 不得被误剔。
    await sessionRepo.addMessage(sessionId, 'assistant', '你这一段的开头钩子很弱。');
  });

  tearDown(() async => db.close());

  group('excludeFromLlmHistory · 喂 LLM 的 history 副本剔除', () {
    test('#0 负向验证：过滤前标记串确实在 history 里（判据有牙齿的前提）', () async {
      final raw = await sessionRepo.listMessages(sessionId);
      expect(raw.length, 4, reason: '夹具应造出4 条消息');
      final joined = raw.map((m) => m.content).join('\n');
      expect(
        joined.contains(kOldEvidenceMarker),
        isTrue,
        reason:
            '标记串必须真实存在于诊断卡消息的 content 里 —— '
            '否则后续「过滤后不在」是恒真的空断言',
      );
      // 元凶那一条确实是 system + diagnosis_result（根因前提）。
      final card = raw.firstWhere((m) => m.messageType == 'diagnosis_result');
      expect(
        card.role,
        'system',
        reason: '诊断卡落库角色为 system（权重高于 user/assistant）',
      );
    });

    test('#1 过滤后逐字证据句不再出现在喂 LLM 的副本里（P1 主判据）', () async {
      final raw = await sessionRepo.listMessages(sessionId);
      final kept = excludeFromLlmHistory(raw);
      final joined = kept.map((m) => m.content).join('\n');
      expect(
        joined.contains(kOldEvidenceMarker),
        isFalse,
        reason: 'P1：旧证据句是逐字复制的污染源，必须从喂 LLM 的副本里切断',
      );
    });

    test('#2 不变量：过滤后仍含本轮 user 消息（否则学员真实输入被剔掉）', () async {
      final raw = await sessionRepo.listMessages(sessionId);
      final kept = excludeFromLlmHistory(raw);
      final userTexts = kept
          .where((m) => m.role == 'user')
          .map((m) => m.content);
      expect(
        userTexts.contains('我改完了，再帮我看看这一章'),
        isTrue,
        reason: "'chat'绝不可入白名单 —— 现有 user 消息 messageType 即为 'chat'",
      );
    });

    test('#3 两条剔除路径都生效：diagnosis_result 与 novice_chat 都被剔', () async {
      final raw = await sessionRepo.listMessages(sessionId);
      final kept = excludeFromLlmHistory(raw);
      expect(
        kept.length,
        2,
        reason: '4 条 - diagnosis_result - novice_chat = 2',
      );
      expect(
        kept.any((m) => m.messageType == 'diagnosis_result'),
        isFalse,
        reason: 'P1：诊断卡消息须剔除（逐字证据污染源）',
      );
      expect(
        kept.any((m) => m.messageType == kNoviceMessageType),
        isFalse,
        reason: 'C123：纯新手模式问答须剔除（既有行为不得回归）',
      );
    });

    test('#4 不误剔：普通 chat 类型的 user 与 assistant 都保留', () async {
      final raw = await sessionRepo.listMessages(sessionId);
      final kept = excludeFromLlmHistory(raw);
      final contents = kept.map((m) => m.content).toList();
      expect(
        contents.contains('我改完了，再帮我看看这一章'),
        isTrue,
        reason: '普通 user 消息必须保留',
      );
      expect(
        contents.contains('你这一段的开头钩子很弱。'),
        isTrue,
        reason: '普通 assistant 消息必须保留（教学连续性依赖对话正文）',
      );
    });

    test('#5 作用域：DB 与 UI 侧完全不受影响（只动喂 LLM 的副本）', () async {
      final before = await sessionRepo.listMessages(sessionId);
      //走一遍过滤（模拟一次真实发送）
      excludeFromLlmHistory(before);
      final after = await sessionRepo.listMessages(sessionId);
      expect(after.length, 4, reason: '过滤只作用在内存副本上，DB 必须仍是 4 条（UI 全量展示依赖它）');
      expect(
        after.any((m) => m.messageType == 'diagnosis_result'),
        isTrue,
        reason: '诊断卡消息必须仍留在 DB 里（UI 靠 message_type 分派渲染 DiagnosisCard）',
      );
    });

    test('#6 白名单是单一真源：增删只改 kHistoryExcludedMessageTypes 一处', () async {
      // 本例把「白名单是Set 常量」这一设计约定变成可执行判据：
      // 若有人把剔除逻辑散落回各方法、白名单反而空了，本例会红。
      expect(
        kHistoryExcludedMessageTypes.contains('diagnosis_result'),
        isTrue,
        reason: 'P1 的核心剔除项必须在白名单里',
      );
      expect(
        kHistoryExcludedMessageTypes.contains(kNoviceMessageType),
        isTrue,
        reason: 'C123 的既有剔除项必须在白名单里',
      );
      expect(
        kHistoryExcludedMessageTypes.contains('chat'),
        isFalse,
        reason: "'chat' 是现有 user 消息的 messageType，入白名单会剔掉学员真实输入",
      );
    });
  });
}
