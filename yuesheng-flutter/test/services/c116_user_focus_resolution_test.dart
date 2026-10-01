// ADR-C116 A2（v2）：学员焦点选择序数/别名映射
//
// 被守护的缺陷：directExplain 全貌清单（「序号. [P码] 名称」）后，学员自然回答
// 「先练第二个 / 对话疲劳症那个」，旧 _parseUserFocusFromMessage 三条正则全部
// 要求显式 P\d+ → 解析 null → focus_resolver 静默改用 AI 自挑（userOverride 丢失、
// 无留痕）。v2 定稿：从 AI 上一条 assistant 消息还原「序号→P码」映射（真同源）
// + 症候真名别名唯一命中兜底 + 解析失败留痕。
//
// name→Pcode 对照真实注册表（syndrome_registry.dart）：
//   P001 情绪标签化 / P004 节奏停滞 / P005 句式节奏单一 /
//   P006 语言堆砌 / P009 对话疲劳症（A2 事实订正：P005 真名不是「对话生硬」）。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/error_handler.dart';
import 'package:writingcoach/services/message_injector.dart';

ActiveProblemView _p(String id, String name) => ActiveProblemView(
  syndromeId: id,
  syndromeName: name,
  severity: 'L2',
  confirmationStatus: 'confirmed',
);

/// AI directExplain 全貌清单（真实格式：序号. [P码] 名称——来自 prompt，
/// 本测试不改 prompt）。
const String _kAssistantList3 = '''
本次识别出 3 个症候：
1. [P005] 句式节奏单一——连续多句同结构
2. [P009] 对话疲劳症——对话灌水无潜台词
3. [P001] 情绪标签化——空评价词盖章
你想先动哪一个？''';

const String _kAssistantList5 = '''
本次识别出 5 个症候：
1. [P005] 句式节奏单一——连续多句同结构
2. [P009] 对话疲劳症——对话灌水无潜台词
3. [P001] 情绪标签化——空评价词盖章
4. [P004] 节奏停滞——事件平铺无聚焦
5. [P006] 语言堆砌——修饰密度过高
你想先动哪一个？''';

final List<ActiveProblemView> _active3 = [
  _p('P005', '句式节奏单一'),
  _p('P009', '对话疲劳症'),
  _p('P001', '情绪标签化'),
];

final List<ActiveProblemView> _active5 = [
  _p('P005', '句式节奏单一'),
  _p('P009', '对话疲劳症'),
  _p('P001', '情绪标签化'),
  _p('P004', '节奏停滞'),
  _p('P006', '语言堆砌'),
];

void main() {
  // ════════════ 组 1：纯函数 resolveUserSyndromeFocus ════════════
  group('组1 序数映射（从 AI 上一条清单还原）', () {
    test('中文序数：先练第二个 → map[2]=P009', () {
      final r = resolveUserSyndromeFocus(
        content: '先练第二个',
        activeProblems: _active3,
        recentAssistantText: _kAssistantList3,
      );
      expect(r.focusId, 'P009');
      expect(r.logReason, isNull);
    });

    test('中文序数：选第一条 → map[1]=P005', () {
      final r = resolveUserSyndromeFocus(
        content: '选第一条',
        activeProblems: _active3,
        recentAssistantText: _kAssistantList3,
      );
      expect(r.focusId, 'P005');
    });

    test('中文序数：第三个吧 → map[3]=P001', () {
      final r = resolveUserSyndromeFocus(
        content: '第三个吧',
        activeProblems: _active3,
        recentAssistantText: _kAssistantList3,
      );
      expect(r.focusId, 'P001');
    });

    test('阿拉伯序数：练第3个 → map[3]=P001', () {
      final r = resolveUserSyndromeFocus(
        content: '我想练第3个',
        activeProblems: _active3,
        recentAssistantText: _kAssistantList3,
      );
      expect(r.focusId, 'P001');
    });

    test('序数越界（列表仅 5 条，第八条）→ null + logReason', () {
      final r = resolveUserSyndromeFocus(
        content: '第八条',
        activeProblems: _active5,
        recentAssistantText: _kAssistantList5,
      );
      expect(r.focusId, isNull);
      expect(r.logReason, contains('序数第8'));
    });

    test('P 码回归：先练 P005 仍由旧正则优先命中', () {
      final r = resolveUserSyndromeFocus(
        content: '先练 P005',
        activeProblems: _active3,
        recentAssistantText: _kAssistantList3,
      );
      expect(r.focusId, 'P005');
      expect(r.logReason, isNull);
    });

    test('P 码不在活跃集 → null + logReason（旧静默路径现在留痕）', () {
      final r = resolveUserSyndromeFocus(
        content: '先练 P099',
        activeProblems: _active3,
        recentAssistantText: null,
      );
      expect(r.focusId, isNull);
      expect(r.logReason, contains('P099'));
    });
  });

  group('组2 别名兜底（真名包含匹配，唯一命中）', () {
    test('按真名回答 → 唯一命中返回', () {
      final r = resolveUserSyndromeFocus(
        content: '我想先改对话疲劳症那个问题',
        activeProblems: [_p('P005', '句式节奏单一'), _p('P009', '对话疲劳症')],
        recentAssistantText: null,
      );
      expect(r.focusId, 'P009');
      expect(r.logReason, isNull);
    });

    test('一句含两个症候名 → null + 多命中 logReason', () {
      final r = resolveUserSyndromeFocus(
        content: '情绪标签化和句式节奏单一我都想练',
        activeProblems: [_p('P001', '情绪标签化'), _p('P005', '句式节奏单一')],
        recentAssistantText: null,
      );
      expect(r.focusId, isNull);
      expect(r.logReason, contains('多命中'));
    });

    test('非选择类闲聊 → null 且不留痕', () {
      final r = resolveUserSyndromeFocus(
        content: '今天这章写得怎么样',
        activeProblems: _active3,
        recentAssistantText: _kAssistantList3,
      );
      expect(r.focusId, isNull);
      expect(r.logReason, isNull);
    });

    test('AI 上一条无编号清单（map 为空）→ 序数分支整体跳过', () {
      final r = resolveUserSyndromeFocus(
        content: '先练第二个',
        activeProblems: _active3,
        recentAssistantText: '好的，那我们继续看下一段。',
      );
      expect(r.focusId, isNull);
      expect(r.logReason, isNull);
    });
  });

  group('组3 编号清单解析器 parseSyndromeOrdinalList', () {
    test('逐行解析 序号. [P码]', () {
      final map = parseSyndromeOrdinalList(_kAssistantList3);
      expect(map[1], 'P005');
      expect(map[2], 'P009');
      expect(map[3], 'P001');
    });

    test('顿号分隔（2、[P009]）同样接受；非清单行忽略', () {
      final map = parseSyndromeOrdinalList('开头一句\n2、[P009] 对话疲劳症\n尾句');
      expect(map[2], 'P009');
      expect(map.containsKey(1), isFalse);
    });

    test('null / 空文本 → 空映射', () {
      expect(parseSyndromeOrdinalList(null), isEmpty);
      expect(parseSyndromeOrdinalList(''), isEmpty);
    });
  });

  // ════════════ 组 4：端到端（MessageInjector.injectDiagnosisLock）════════════
  group('组4 注入编排端到端（含留痕落 error_logs）', () {
    late AppDatabase db;
    late SessionRepository sessionRepo;
    late MessageInjector injector;
    late String sessionId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      sessionRepo = SessionRepository(db);
      final diagnosisRepo = DiagnosisRepository(db);
      injector = MessageInjector(
        sessionRepo: sessionRepo,
        diagnosisRepo: diagnosisRepo,
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        manuscriptRepo: ManuscriptRepository(db),
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: diagnosisRepo,
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
        ),
        material: const MaterialCapabilityImpl(),
      );
      sessionId = await sessionRepo.createBlankSession();
      ErrorHandler.instance.resetForTesting();
      ErrorHandler.instance.attachRepository(ErrorLogRepository(db));
    });

    tearDown(() async {
      ErrorHandler.instance.resetForTesting();
      await db.close();
    });

    Future<String?> runInject(String content, List<ActiveProblemView> active) {
      return injector.injectDiagnosisLock(
        sessionId: sessionId,
        content: content,
        activeProblems: active,
        currentSubphase: null,
        beginnerLevel: null,
        messages: [],
        markStage: (_) {},
      );
    }

    Future<List<ErrorLog>> pollErrorLogs() async {
      var rows = <ErrorLog>[];
      for (var i = 0; i < 50; i++) {
        rows = await db.select(db.errorLogs).get();
        if (rows.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return rows;
    }

    test('序数「先练第二个」端到端 → 返回 P009（userOverride 生效）', () async {
      await sessionRepo.addMessage(sessionId, 'assistant', _kAssistantList3);
      final result = await runInject('先练第二个', _active3);
      expect(result, 'P009');
    });

    test('序数越界「第八条」端到端 → 回退 fallback 且留痕落库', () async {
      await sessionRepo.addMessage(sessionId, 'assistant', _kAssistantList5);
      final result = await runInject('第八条', _active5);
      // 越界解析 null → userFocusOverride 丢失 → fallback 从活跃集取一个
      expect(result, isNotNull);
      expect(_active5.map((p) => p.syndromeId), contains(result));

      final rows = await pollErrorLogs();
      expect(rows, isNotEmpty);
      expect(
        rows.any((r) => r.message.contains('学员焦点解析失败')),
        isTrue,
        reason: '序数越界必须留痕（此前静默降级无痕迹）',
      );
    });

    test('别名多命中端到端 → 不替学员决定且留痕落库', () async {
      final active = [_p('P001', '情绪标签化'), _p('P005', '句式节奏单一')];
      // 不写 assistant 清单消息（map 为空，走纯别名分支）
      final result = await runInject('情绪标签化和句式节奏单一我都想练', active);
      expect(result, isNotNull);

      final rows = await pollErrorLogs();
      expect(rows, isNotEmpty);
      expect(rows.any((r) => r.message.contains('学员焦点解析失败')), isTrue);
    });
  });
}
