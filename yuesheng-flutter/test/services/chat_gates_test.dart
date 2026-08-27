// ─────────────────────────────────────────────────────────────
// chat_gates_test — Teacher 触发判断 + 持久化测试
//
// 覆盖路径：
//   shouldTriggerTeacherForEditor:
//     1. pronounced >= 1 → true
//     2. against >= 2 → true
//     3. 都不满足 → false
//
//   shouldTriggerTeacherForDiagnosis:
//     4. 命中 L2 → true
//     5. 命中 L3 → true
//     6. syndromes.length >= 3 → true
//     7. 都不满足 → false
//
//   persistTeacherSuggestion:
//     8.  encourage + task → null（不入库）
//     9.  defer + task → null
//     10. guide 但 task=null → null
//     11. guide + task → 写入成功，返回 id
//     12. train + task → 写入成功，返回 id
//     13. DB 异常 → null（catch 降级）
//
// 限制：TeacherGate.enabled 是 const true，无法在测试中关闭，
//      所以"enabled=false → false"分支无法覆盖（在注释中标注）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/services/chat_gates.dart';
import 'package:writingcoach/services/editor_validator.dart';
import 'package:writingcoach/services/teacher_validator.dart';
import 'package:writingcoach/types/teaching_types.dart';

// ─── 测试 fixtures ────────────────────────────────────────────

EditorObservation _obs({
  required String visibility,
  required String alignment,
}) {
  return EditorObservation(
    dimension: 'character_agency',
    dimensionName: '人物能动性',
    phenomenon: '现象描述',
    evidence: const ['证据'],
    readerImpact: '影响',
    observationVisibility: visibility,
    intentAlignment: alignment,
  );
}

EditorResult _editorResult(List<EditorObservation> observations) {
  return EditorResult(
    possibleIntent: '表达情绪',
    intentConfidence: 'moderate',
    observations: observations,
    overallImpression: '整体印象',
    strengths: const ['优点'],
  );
}

Syndrome _syndrome(Severity severity) {
  return Syndrome(
    syndromeId: 'P001',
    name: '测试症候',
    severity: severity,
    evidence: const ['证据'],
    explanation: '解释',
  );
}

TrainingTask _task() {
  return const TrainingTask(
    targetSyndromeId: 'P001',
    targetDimension: 'character_agency',
    taskType: 'rewrite',
    taskDescription: '重写这段',
    difficulty: 'medium',
    evaluationCriteria: ['标准1'],
  );
}

TeacherResult _teacherResult({required String decision, TrainingTask? task}) {
  return TeacherResult(
    teachingDecision: decision,
    teachingReason: '理由',
    naturalLanguage: '自然语言反馈',
    trainingTask: task,
  );
}

void main() {
  group('shouldTriggerTeacherForEditor', () {
    test('#1 pronounced >= 1 → true', () {
      final result = _editorResult([
        _obs(visibility: 'pronounced', alignment: 'aligned'),
        _obs(visibility: 'subtle', alignment: 'aligned'),
      ]);
      expect(shouldTriggerTeacherForEditor(result), true);
    });

    test('#2 against >= 2 → true', () {
      final result = _editorResult([
        _obs(visibility: 'subtle', alignment: 'against'),
        _obs(visibility: 'subtle', alignment: 'against'),
      ]);
      expect(shouldTriggerTeacherForEditor(result), true);
    });

    test('#3 都不满足 → false', () {
      final result = _editorResult([
        _obs(visibility: 'subtle', alignment: 'aligned'),
        _obs(visibility: 'moderate', alignment: 'unclear'),
      ]);
      expect(shouldTriggerTeacherForEditor(result), false);
    });

    // 注：TeacherGate.enabled 是 const true，无法在测试中关闭
    // 所以 "enabled=false → false" 分支无法覆盖
  });

  group('shouldTriggerTeacherForDiagnosis', () {
    test('#4 命中 L2 → true', () {
      final syndromes = [_syndrome(Severity.l2), _syndrome(Severity.l1)];
      expect(shouldTriggerTeacherForDiagnosis(syndromes), true);
    });

    test('#5 命中 L3 → true', () {
      final syndromes = [_syndrome(Severity.l3)];
      expect(shouldTriggerTeacherForDiagnosis(syndromes), true);
    });

    test('#6 syndromes.length >= 3 → true', () {
      final syndromes = [
        _syndrome(Severity.l1),
        _syndrome(Severity.l1),
        _syndrome(Severity.l1),
      ];
      expect(shouldTriggerTeacherForDiagnosis(syndromes), true);
    });

    test('#7 都不满足 → false', () {
      final syndromes = [_syndrome(Severity.l1), _syndrome(Severity.l1)];
      expect(shouldTriggerTeacherForDiagnosis(syndromes), false);
    });
  });

  group('persistTeacherSuggestion', () {
    late AppDatabase db;
    late TeacherSuggestionRepository repo;
    late SessionRepository sesRepo;
    late String sessionId;
    late String messageId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = TeacherSuggestionRepository(db);
      sesRepo = SessionRepository(db);
      // 预置 session + message 满足外键约束
      sessionId = await sesRepo.createBlankSession();
      messageId = await sesRepo.addMessage(sessionId, 'assistant', '测试消息');
    });

    tearDown(() => db.close());

    test('#8 encourage + task → null（不入库）', () async {
      final teacher = _teacherResult(decision: 'encourage', task: _task());
      final id = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'editor',
      );
      expect(id, isNull);

      // 确认未写入
      final active = await repo.getActiveSuggestions(sessionId);
      expect(active, isEmpty);
    });

    test('#9 defer + task → null', () async {
      final teacher = _teacherResult(decision: 'defer', task: _task());
      final id = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'editor',
      );
      expect(id, isNull);
    });

    test('#10 guide 但 task=null → null', () async {
      final teacher = _teacherResult(decision: 'guide', task: null);
      final id = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'editor',
      );
      expect(id, isNull);
    });

    test('#11 guide + task → 写入成功，返回 id', () async {
      final teacher = _teacherResult(decision: 'guide', task: _task());
      final id = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'editor',
      );
      expect(id, isNotNull);

      final active = await repo.getActiveSuggestions(sessionId);
      expect(active.length, 1);
      expect(active.first.id, id);
      expect(active.first.teachingDecision, 'guide');
      expect(active.first.source, 'editor');
    });

    test('#12 train + task → 写入成功', () async {
      final teacher = _teacherResult(decision: 'train', task: _task());
      final id = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(id, isNotNull);

      final active = await repo.getActiveSuggestions(sessionId);
      expect(active.length, 1);
      expect(active.first.source, 'diagnosis');
    });

    test('#13 DB 异常 → null（catch 降级）', () async {
      // 关闭 DB 让 insert 抛异常
      await db.close();

      final teacher = _teacherResult(decision: 'guide', task: _task());
      final id = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'editor',
      );
      expect(id, isNull);
    });

    test('#14 批次59 isRapidFire=true → 不写入（心流延迟反馈）', () async {
      final teacher = _teacherResult(decision: 'guide', task: _task());
      final id = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'editor',
        isRapidFire: true,
      );
      expect(id, isNull);

      final active = await repo.getActiveSuggestions(sessionId);
      expect(active, isEmpty);
    });

    test('#15 批次59 同 session 同症候窗口内重复触发 → 第二次不写入', () async {
      final teacher = _teacherResult(decision: 'guide', task: _task());
      final first = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(first, isNotNull);

      final second = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(second, isNull);

      final active = await repo.getActiveSuggestions(sessionId);
      expect(active.length, 1);
    });

    test('#16 批次59 不同症候 → 各自可写入（去重按 syndromeId）', () async {
      final teacherA = _teacherResult(decision: 'guide', task: _task());
      final teacherB = _teacherResult(
        decision: 'guide',
        task: const TrainingTask(
          targetSyndromeId: 'P002',
          targetDimension: 'character_agency',
          taskType: 'analyze',
          taskDescription: '分析这段',
          difficulty: 'easy',
          evaluationCriteria: ['标准1'],
        ),
      );
      final idA = await persistTeacherSuggestion(
        repo,
        teacherA,
        sessionId,
        messageId,
        'diagnosis',
      );
      final idB = await persistTeacherSuggestion(
        repo,
        teacherB,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(idA, isNotNull);
      expect(idB, isNotNull);

      final active = await repo.getActiveSuggestions(sessionId);
      expect(active.length, 2);
    });

    test('#17 批次59 超出去重窗口（窗口=0）→ 可再次触发', () async {
      final teacher = _teacherResult(decision: 'guide', task: _task());
      final first = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(first, isNotNull);

      final second = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
        dedupeRecencyWindowSec: 0,
      );
      expect(second, isNotNull);
    });

    test('#18 批次59 syndromeId 为空 → 不去重（维度型建议不拦截）', () async {
      final teacher = _teacherResult(
        decision: 'guide',
        task: const TrainingTask(
          targetSyndromeId: null,
          targetDimension: 'character_agency',
          taskType: 'analyze',
          taskDescription: '分析这段',
          difficulty: 'easy',
          evaluationCriteria: ['标准1'],
        ),
      );
      final first = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      final second = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(first, isNotNull);
      expect(second, isNotNull);
    });

    test('#19 批次62 已采纳且过冷却 → 可再次触发（新反馈点）', () async {
      final teacher = _teacherResult(decision: 'guide', task: _task());
      final first = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(first, isNotNull);

      await repo.markAdopted(first!);

      // adoptedWindowSec=0 → 距采纳 >= 0 → 不再视为重复
      final second = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
        adoptedWindowSec: 0,
      );
      expect(second, isNotNull);
    });

    test('#20 批次62 已采纳但冷却期内 → 不触发', () async {
      final teacher = _teacherResult(decision: 'guide', task: _task());
      final first = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(first, isNotNull);

      await repo.markAdopted(first!);

      final second = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(second, isNull);
    });

    test('#21 批次62 已跳过 → 不触发（未采纳语义）', () async {
      final teacher = _teacherResult(decision: 'guide', task: _task());
      final first = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(first, isNotNull);

      await repo.markDismissed(first!);

      final second = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(second, isNull);
    });

    test('#22 批次4（4.9 O4）：默认去重窗口缩短至 900s（同症候不重复骚扰窗口收窄）', () async {
      expect(kDedupeRecencyWindowSec, 900);

      // 默认窗口内同症候重复 → 第二次不写入（行为回归，窗口缩短后仍生效）
      final teacher = _teacherResult(decision: 'guide', task: _task());
      final first = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(first, isNotNull);

      final second = await persistTeacherSuggestion(
        repo,
        teacher,
        sessionId,
        messageId,
        'diagnosis',
      );
      expect(second, isNull);
    });
  });

  group('批次62: hasDuplicateSuggestion 采纳语义', () {
    late AppDatabase db;
    late TeacherSuggestionRepository repo;
    late SessionRepository sesRepo;
    late String sessionId;
    late String messageId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = TeacherSuggestionRepository(db);
      sesRepo = SessionRepository(db);
      sessionId = await sesRepo.createBlankSession();
      messageId = await sesRepo.addMessage(sessionId, 'assistant', '测试消息');
    });

    tearDown(() => db.close());

    Future<String> insertSuggestion({String? syndromeId = 'P001'}) async {
      return repo.insertTeacherSuggestion(
        InsertTeacherSuggestionParams(
          sessionId: sessionId,
          messageId: messageId,
          source: 'diagnosis',
          teachingDecision: 'guide',
          targetSyndromeId: syndromeId,
          taskType: 'rewrite',
          taskDescription: '任务描述',
          difficulty: 'medium',
          evaluationCriteria: const [],
        ),
      );
    }

    test('#D1 窗口内未采纳同症候 → true（不再触发）', () async {
      await insertSuggestion();
      expect(await repo.hasDuplicateSuggestion(sessionId, 'P001'), true);
    });

    test('#D2 窗口内已采纳未冷却 → true（冷却中）', () async {
      final id = await insertSuggestion();
      await repo.markAdopted(id);
      expect(await repo.hasDuplicateSuggestion(sessionId, 'P001'), true);
    });

    test('#D3 窗口内已采纳过冷却 → false（可触发新反馈点）', () async {
      final id = await insertSuggestion();
      await repo.markAdopted(id);
      expect(
        await repo.hasDuplicateSuggestion(
          sessionId,
          'P001',
          adoptedWindowSec: 0,
        ),
        false,
      );
    });

    test('#D4 窗口内已跳过 → true（未采纳不再触发）', () async {
      final id = await insertSuggestion();
      await repo.markDismissed(id);
      expect(await repo.hasDuplicateSuggestion(sessionId, 'P001'), true);
    });

    test('#D5 无记录 → false', () async {
      expect(await repo.hasDuplicateSuggestion(sessionId, 'P001'), false);
    });

    test('#D6 syndromeId 为空 → false（维度型不去重）', () async {
      await insertSuggestion(syndromeId: null);
      expect(await repo.hasDuplicateSuggestion(sessionId, null), false);
    });
  });

  group('批次59: isRapidFireSend 心流判定', () {
    test('#J1 无上一条记录 → false', () {
      expect(isRapidFireSend(lastSendAtSec: null, nowAtSec: 1000), false);
    });

    test('#J2 距上一条 30s（< 60s）→ true（心流中）', () {
      expect(isRapidFireSend(lastSendAtSec: 970, nowAtSec: 1000), true);
    });

    test('#J3 距上一条 60s（= 窗口）→ false', () {
      expect(isRapidFireSend(lastSendAtSec: 940, nowAtSec: 1000), false);
    });

    test('#J4 距上一条 300s → false', () {
      expect(isRapidFireSend(lastSendAtSec: 700, nowAtSec: 1000), false);
    });
  });

  group('批次64: isEditorActive / isInFlow 编辑器心流', () {
    test('#K1 无编辑记录 → false', () {
      expect(isEditorActive(lastEditorEditAtSec: null, nowAtSec: 1000), false);
    });

    test('#K2 最近 60s 内有编辑（< 120s）→ true', () {
      expect(isEditorActive(lastEditorEditAtSec: 940, nowAtSec: 1000), true);
    });

    test('#K3 距编辑 120s（= 窗口）→ false', () {
      expect(isEditorActive(lastEditorEditAtSec: 880, nowAtSec: 1000), false);
    });

    test('#K4 isInFlow：消息心流命中（未编辑）→ true', () {
      expect(
        isInFlow(lastSendAtSec: 990, lastEditorEditAtSec: null, nowAtSec: 1000),
        true,
      );
    });

    test('#K5 isInFlow：仅编辑器活跃（未发言）→ true', () {
      expect(
        isInFlow(
          lastSendAtSec: 400, // 距上一条 600s，非消息心流
          lastEditorEditAtSec: 950, // 但 50s 前有编辑
          nowAtSec: 1000,
        ),
        true,
      );
    });

    test('#K6 isInFlow：两者都不活跃 → false', () {
      expect(
        isInFlow(lastSendAtSec: 400, lastEditorEditAtSec: 800, nowAtSec: 1000),
        false,
      );
    });

    test('#K7 批次1 isInFlow：升级阀 bypassFlowWindow=true → 绕过心流窗口', () {
      expect(
        isInFlow(
          lastSendAtSec: 990, // 消息心流命中
          lastEditorEditAtSec: 950, // 编辑器活跃命中
          nowAtSec: 1000,
          bypassFlowWindow: true,
        ),
        false,
        reason: '升级阀触发时应绕过心流窗口（重度/慢性症候需及时反馈）',
      );
    });

    test('#K8 批次1 isInFlow：bypassFlowWindow=false（默认）→ 维持原判定', () {
      expect(
        isInFlow(lastSendAtSec: 990, lastEditorEditAtSec: null, nowAtSec: 1000),
        true,
        reason: '未触发升级阀时心流窗口行为不变',
      );
    });

    test('#K9 批次6（6.8 M4）isInFlow：求助关键词「不会」→ 绕过心流抑制', () {
      expect(
        isInFlow(
          lastSendAtSec: 990, // 消息心流命中
          lastEditorEditAtSec: 950, // 编辑器活跃命中
          nowAtSec: 1000,
          helpSignal: '我不会写这段的结尾',
        ),
        false,
        reason: '主动求助时应绕过心流窗口，及时反馈',
      );
    });

    test('#K10 批次6（6.8 M4）isInFlow：求助关键词「怎么」→ 绕过心流抑制', () {
      expect(
        isInFlow(
          lastSendAtSec: 990,
          lastEditorEditAtSec: 950,
          nowAtSec: 1000,
          helpSignal: '这段对话怎么写才能更自然？',
        ),
        false,
      );
    });

    test('#K11 批次6（6.8 M4）isInFlow：求助关键词「卡住了/没思路」→ 绕过心流抑制', () {
      for (final signal in ['我卡住了', '现在完全没思路']) {
        expect(
          isInFlow(
            lastSendAtSec: 990,
            lastEditorEditAtSec: 950,
            nowAtSec: 1000,
            helpSignal: signal,
          ),
          false,
          reason: '「$signal」应命中求助信号绕过心流',
        );
      }
    });

    test('#K12 批次6（6.8 M4）isInFlow：非求助消息 → 心流判定不受影响', () {
      expect(
        isInFlow(
          lastSendAtSec: 990,
          lastEditorEditAtSec: null,
          nowAtSec: 1000,
          helpSignal: '我觉得这个情节挺好的',
        ),
        true,
        reason: '普通消息不命中求助关键词，心流窗口行为不变',
      );
    });

    test('#K13 批次6（6.8 M4）isHelpSeekingText：关键词匹配', () {
      expect(isHelpSeekingText('我不会写'), true);
      expect(isHelpSeekingText('应该怎么写'), true);
      expect(isHelpSeekingText('这里卡住了'), true);
      expect(isHelpSeekingText('没思路了'), true);
      expect(isHelpSeekingText('这段写好了'), false);
      expect(isHelpSeekingText(null), false);
      expect(isHelpSeekingText(''), false);
    });

    // ─── FT-22 越界输出抑制（架构真源 §4.4 FT-22） ───────────────
    group('FT-22 isDiagnosisOnlyRequest 边界声明检测', () {
      test('#F1 命中「只诊断」', () {
        expect(isDiagnosisOnlyRequest('只诊断就好'), true);
        expect(isDiagnosisOnlyRequest('这章只诊断'), true);
      });

      test('#F2 命中「不要建议/不要改/先别改」', () {
        expect(isDiagnosisOnlyRequest('不要给建议'), true);
        expect(isDiagnosisOnlyRequest('不要建议'), true);
        expect(isDiagnosisOnlyRequest('不要改我的文字'), true);
        expect(isDiagnosisOnlyRequest('先别改'), true);
        expect(isDiagnosisOnlyRequest('先不改'), true);
      });

      test('#F3 命中「不用改/不用建议」', () {
        expect(isDiagnosisOnlyRequest('不用改了'), true);
        expect(isDiagnosisOnlyRequest('不用建议'), true);
      });

      test('#F4 命中「只找问题/只要诊断」', () {
        expect(isDiagnosisOnlyRequest('只找问题就行'), true);
        expect(isDiagnosisOnlyRequest('只要诊断结论'), true);
      });

      test('#F5 普通诊断请求不误判（边界声明不出现）', () {
        expect(isDiagnosisOnlyRequest('帮我看看这章哪里有问题'), false);
        expect(isDiagnosisOnlyRequest('诊断一下吧'), false);
        expect(isDiagnosisOnlyRequest('找找症候'), false);
        expect(isDiagnosisOnlyRequest('请诊断这章'), false);
      });

      test('#F6 null / 空文本 → false', () {
        expect(isDiagnosisOnlyRequest(null), false);
        expect(isDiagnosisOnlyRequest(''), false);
      });

      test('#F7 关键词集合可扩展且不为空', () {
        expect(kDiagnosisOnlyKeywords, isNotEmpty);
        expect(kDiagnosisOnlyKeywords.length, greaterThanOrEqualTo(8));
      });
    });
  });
}
