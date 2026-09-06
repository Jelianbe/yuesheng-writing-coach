// ─────────────────────────────────────────────────────────────
// 会话记录导出：单元测试（v0.1 发布准备批任务 3）
//
// 覆盖路径：
//   buildSessionExportJson（纯函数，行来自内存库真实 insert）：
//     #1 完整数据 → meta/session/messages/diagnoses/trainingResults/characterFacts
//     #2 坏 JSON 字符串 → 防御性降级为空值，不抛出
//     #3 sessionExportFileName → 非法字符过滤 + 空标题回退
//   collectLatestSessionExport（IO 编排，内存库）：
//     #4 完整链路 → 最新会话四类数据 + 计数 + 文件名
//     #5 会话未关联作品 → characterFacts 空
//     #6 空库 → null
//     #7 多会话 → 取 updatedAt 最新
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/services/session_export_service.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  /// 造一套完整数据：作品 + 会话 + 2 消息 + 1 诊断 + 1 训练 + 2 角色事实
  Future<void> seedFullSession() async {
    await db
        .into(db.manuscripts)
        .insert(
          ManuscriptsCompanion.insert(id: 'm1', title: const Value('测试作品')),
        );
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 's1',
            title: const Value('新书打磨'),
            manuscriptId: const Value('m1'),
            updatedAt: const Value(1700000100),
          ),
        );
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'msg1',
            sessionId: 's1',
            role: 'user',
            content: '雨落在青瓦上，她想起父亲。',
            timestamp: const Value(1700000000),
            referencesJson: Value(
              jsonEncode([
                {'refType': 'manuscript', 'refId': 'm1', 'title': '测试作品'},
              ]),
            ),
          ),
        );
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'msg2',
            sessionId: 's1',
            role: 'assistant',
            content: '这句场景与情绪贴得很近。',
          ),
        );
    await db
        .into(db.diagnosisResults)
        .insert(
          DiagnosisResultsCompanion.insert(
            id: 'd1',
            sessionId: 's1',
            messageId: 'msg1',
            syndromes: Value(
              jsonEncode([
                {'syndrome_id': 'P003', 'severity': 'L2'},
              ]),
            ),
            suggestedActions: const Value('["rewrite"]'),
            feedbackSummary: const Value('情绪表达依赖直陈'),
            confidence: const Value(0.82),
            timestamp: const Value(1700000005),
          ),
        );
    await db
        .into(db.trainingResults)
        .insert(
          TrainingResultsCompanion.insert(
            id: 't1',
            sessionId: 's1',
            syndromeId: 'P003',
            taskType: 'rewrite',
            userContent: '雨砸在瓦上，父亲的脸在雨里碎了。',
            result: 'passed',
            score: const Value(0.9),
          ),
        );
    await db
        .into(db.characterFacts)
        .insert(
          CharacterFactsCompanion.insert(
            id: 'c1',
            manuscriptId: 'm1',
            name: '林晚',
            assertions: Value(
              jsonEncode([
                {'attribute': '身份', 'value': '修表匠', 'source': 'user'},
              ]),
            ),
            aliases: const Value('["晚晚"]'),
          ),
        );
    await db
        .into(db.characterFacts)
        .insert(
          CharacterFactsCompanion.insert(
            id: 'c2',
            manuscriptId: 'm1',
            name: '陈叙',
          ),
        );
  }

  group('buildSessionExportJson（纯函数）', () {
    test('#1 完整数据 → 各区段正确填充', () async {
      await seedFullSession();
      final session = (await db.select(db.sessions).get()).firstWhere(
        (r) => r.id == 's1',
      );
      final messages = await db.select(db.messages).get();
      final diagnoses = await db.select(db.diagnosisResults).get();
      final training = await db.select(db.trainingResults).get();
      final facts = await db.select(db.characterFacts).get();

      final json = buildSessionExportJson(
        session: session,
        messages: messages,
        diagnoses: diagnoses,
        trainingResults: training,
        characterFacts: facts,
        exportedAt: 1700000200,
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      final meta = decoded['meta'] as Map;
      expect(meta['kind'], 'session-export');
      expect(meta['version'], '1.0');
      expect(meta['exportedAt'], 1700000200);
      expect(meta['app'], 'yuesheng-writing-coach');

      final sessionOut = decoded['session'] as Map;
      expect(sessionOut['id'], 's1');
      expect(sessionOut['title'], '新书打磨');
      expect(sessionOut['manuscriptId'], 'm1');

      final msgList = decoded['messages'] as List;
      expect(msgList.length, 2);
      expect((msgList[0] as Map)['content'], '雨落在青瓦上，她想起父亲。');
      expect(((msgList[0] as Map)['references'] as List).length, 1);
      expect((msgList[1] as Map)['messageType'], 'chat');

      final dxList = decoded['diagnoses'] as List;
      expect(dxList.length, 1);
      final dx = dxList[0] as Map;
      expect(((dx['syndromes'] as List)[0] as Map)['syndrome_id'], 'P003');
      expect((dx['suggestedActions'] as List)[0], 'rewrite');
      expect(dx['feedbackSummary'], '情绪表达依赖直陈');
      expect(dx['confidence'], 0.82);

      final trainList = decoded['trainingResults'] as List;
      expect(trainList.length, 1);
      final tr = trainList[0] as Map;
      expect(tr['taskType'], 'rewrite');
      expect(tr['result'], 'passed');
      expect(tr['userContent'], '雨砸在瓦上，父亲的脸在雨里碎了。');
      expect(tr['score'], 0.9);

      final factList = decoded['characterFacts'] as List;
      expect(factList.length, 2);
      final fact = factList[0] as Map;
      expect(fact['name'], '林晚');
      expect(((fact['assertions'] as List)[0] as Map)['value'], '修表匠');
      expect((fact['aliases'] as List)[0], '晚晚');
      expect(fact['status'], 'active');
    });

    test('#2 坏 JSON 字符串 → 降级为空值，不抛出', () async {
      await db
          .into(db.manuscripts)
          .insert(ManuscriptsCompanion.insert(id: 'm1'));
      await db.into(db.sessions).insert(SessionsCompanion.insert(id: 's1'));
      await db
          .into(db.diagnosisResults)
          .insert(
            DiagnosisResultsCompanion.insert(
              id: 'd1',
              sessionId: 's1',
              messageId: 'msg1',
              syndromes: const Value('not-json'),
              suggestedActions: const Value('{broken'),
            ),
          );
      await db
          .into(db.characterFacts)
          .insert(
            CharacterFactsCompanion.insert(
              id: 'c1',
              manuscriptId: 'm1',
              name: '林晚',
              assertions: const Value(']]]'),
            ),
          );

      final session = (await db.select(db.sessions).get()).firstWhere(
        (r) => r.id == 's1',
      );
      final diagnoses = await db.select(db.diagnosisResults).get();
      final facts = await db.select(db.characterFacts).get();

      final json = buildSessionExportJson(
        session: session,
        messages: [],
        diagnoses: diagnoses,
        trainingResults: [],
        characterFacts: facts,
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      final dx = (decoded['diagnoses'] as List)[0] as Map;
      expect(dx['syndromes'], isEmpty);
      expect(dx['suggestedActions'], isEmpty);
      final fact = (decoded['characterFacts'] as List)[0] as Map;
      expect(fact['assertions'], isEmpty);
    });

    test('#3 sessionExportFileName → 非法字符过滤 + 空标题回退', () {
      final a = sessionExportFileName(sessionLabel: '新书/打磨:第一章?');
      expect(a.contains('/'), isFalse);
      expect(a.contains(':'), isFalse);
      expect(a.contains('?'), isFalse);
      expect(a.startsWith('会话记录-新书打磨第一章-'), isTrue);

      final b = sessionExportFileName();
      expect(b.startsWith('会话记录-'), isTrue);

      final c = sessionExportFileName(sessionLabel: '   ');
      expect(c.startsWith('会话记录-'), isTrue);
    });
  });

  group('collectLatestSessionExport（IO 编排）', () {
    test('#4 完整链路 → 最新会话四类数据 + 计数 + 文件名', () async {
      await seedFullSession();

      final result = await collectLatestSessionExport(
        db,
        exportedAt: 1700000300,
      );

      expect(result, isNotNull);
      expect(result!.sessionTitle, '新书打磨');
      expect(result.messageCount, 2);
      expect(result.diagnosisCount, 1);
      expect(result.fileName.startsWith('会话记录-新书打磨-'), isTrue);

      final decoded = jsonDecode(result.json) as Map<String, dynamic>;
      expect(((decoded['meta'] as Map)['exportedAt']), 1700000300);
      expect((decoded['messages'] as List).length, 2);
      expect((decoded['diagnoses'] as List).length, 1);
      expect((decoded['trainingResults'] as List).length, 1);
      expect((decoded['characterFacts'] as List).length, 2);
    });

    test('#5 会话未关联作品 → characterFacts 空', () async {
      await db.into(db.sessions).insert(SessionsCompanion.insert(id: 's1'));

      final result = await collectLatestSessionExport(db);
      expect(result, isNotNull);
      final decoded = jsonDecode(result!.json) as Map<String, dynamic>;
      expect(decoded['characterFacts'], isEmpty);
    });

    test('#6 空库 → null', () async {
      final result = await collectLatestSessionExport(db);
      expect(result, isNull);
    });

    test('#7 多会话 → 取 updatedAt 最新', () async {
      await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 'old',
              title: const Value('旧会话'),
              updatedAt: const Value(100),
            ),
          );
      await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 'new',
              title: const Value('新会话'),
              updatedAt: const Value(200),
            ),
          );

      final result = await collectLatestSessionExport(db);
      expect(result!.sessionTitle, '新会话');
    });
  });
}
