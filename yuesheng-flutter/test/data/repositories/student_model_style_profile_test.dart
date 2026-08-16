// ─────────────────────────────────────────────────────────────
// StudentModelRepository — 写作风格画像（style_profile）批次53
// 覆盖：updateStyleProfile / getStyleProfile / WritingStyleProfile JSON 序列化
// 注意：student_model.session_id 外键引用 sessions，测试需先建会话
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late StudentModelRepository repo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = StudentModelRepository(db);
    sessionId = await SessionRepository(db).createBlankSession(title: '风格测试');
  });

  tearDown(() async {
    await db.close();
  });

  const sampleProfile = WritingStyleProfile(
    sensory: SensoryPreference.visual,
    rhythm: RhythmPreference.short,
    narrativeDistance: NarrativeDistance.intimate,
    toneTexture: ToneTexture.poetic,
    structure: StructureInstinct.linear,
    summary: '你的文字有一种画家的眼睛——颜色和光线的使用特别丰富。',
    confidence: 0.8,
  );

  group('批次53: WritingStyleProfile 序列化', () {
    test('#B53-D1 toJson 输出五维英文键（对齐诊断协议字段名）', () {
      final json = sampleProfile.toJson();
      expect(json['sensory'], 'visual');
      expect(json['rhythm'], 'short');
      expect(json['narrative_distance'], 'intimate');
      expect(json['tone_texture'], 'poetic');
      expect(json['structure'], 'linear');
      expect(json['summary'], contains('画家的眼睛'));
      expect(json['confidence'], 0.8);
    });

    test('#B53-D2 fromJson round-trip 保持五维一致', () {
      final parsed = WritingStyleProfile.fromJson(sampleProfile.toJson());
      expect(parsed.sensory, SensoryPreference.visual);
      expect(parsed.rhythm, RhythmPreference.short);
      expect(parsed.narrativeDistance, NarrativeDistance.intimate);
      expect(parsed.toneTexture, ToneTexture.poetic);
      expect(parsed.structure, StructureInstinct.linear);
      expect(parsed.summary, sampleProfile.summary);
      expect(parsed.confidence, 0.8);
    });

    test('#B53-D3 fromJson 未知维度值降级为默认', () {
      final parsed = WritingStyleProfile.fromJson({
        'sensory': 'quantum', // 非法值
        'rhythm': 'short',
        'narrative_distance': 'intimate',
        'tone_texture': 'poetic',
        'structure': 'linear',
        'summary': '降级测试',
      });
      expect(parsed.sensory, SensoryPreference.balanced);
      expect(parsed.rhythm, RhythmPreference.short);
    });

    test('#B53-D4 fromJson 缺 summary 抛 FormatException', () {
      expect(
        () => WritingStyleProfile.fromJson(const {'sensory': 'visual'}),
        throwsFormatException,
      );
    });
  });

  group('批次53: style_profile 落库读写', () {
    test('#B53-D5 updateStyleProfile 落库 + getStyleProfile 读回', () async {
      await repo.updateStyleProfile(sessionId, sampleProfile);

      final loaded = await repo.getStyleProfile(sessionId);
      expect(loaded, isNotNull);
      expect(loaded!.sensory, SensoryPreference.visual);
      expect(loaded.rhythm, RhythmPreference.short);
      expect(loaded.summary, sampleProfile.summary);
      expect(loaded.confidence, 0.8);
    });

    test('#B53-D6 未写入时 getStyleProfile 返回 null', () async {
      final loaded = await repo.getStyleProfile(sessionId);
      expect(loaded, isNull);
    });

    test('#B53-D7 重复更新覆盖旧值并刷新 updated_at', () async {
      await repo.updateStyleProfile(sessionId, sampleProfile);
      final newer = WritingStyleProfile(
        sensory: SensoryPreference.auditory,
        rhythm: sampleProfile.rhythm,
        narrativeDistance: sampleProfile.narrativeDistance,
        toneTexture: sampleProfile.toneTexture,
        structure: sampleProfile.structure,
        summary: '更偏听觉的修正版。',
      );
      await repo.updateStyleProfile(sessionId, newer);

      final loaded = await repo.getStyleProfile(sessionId);
      expect(loaded!.sensory, SensoryPreference.auditory);
      expect(loaded.summary, '更偏听觉的修正版。');
    });

    test('#B53-D8 数据库 style_profile 列为 JSON 文本（v13 迁移生效）', () async {
      await repo.updateStyleProfile(sessionId, sampleProfile);
      final row = await (db.select(
        db.studentModels,
      )..where((t) => t.sessionId.equals(sessionId))).getSingle();
      final decoded = jsonDecode(row.styleProfile!);
      expect((decoded as Map<String, dynamic>)['sensory'], 'visual');
    });
  });

  group('批次57: updateLatestStyleProfile（成长页风格纠正入口）', () {
    const corrected = WritingStyleProfile(
      sensory: SensoryPreference.visual,
      rhythm: RhythmPreference.short,
      narrativeDistance: NarrativeDistance.intimate,
      toneTexture: ToneTexture.poetic,
      structure: StructureInstinct.divergent,
      summary: '你的文字有一种画家的眼睛——颜色和光线的使用特别丰富。',
      confidence: 0.8,
    );

    test('#B57-D1 更新最新一条（后写入 session 被纠正，先前的不动）', () async {
      final sessionA = sessionId;
      final sessionB = await SessionRepository(
        db,
      ).createBlankSession(title: '风格测试B');
      await repo.updateStyleProfile(
        sessionA,
        sampleProfile, // 先写 A（旧）
      );
      await repo.updateStyleProfile(
        sessionB,
        sampleProfile, // 后写 B（较新，rowid 更大）
      );

      await repo.updateLatestStyleProfile(corrected);

      // B 被纠正为发散型，A 保持线性不变
      final loadedB = await repo.getStyleProfile(sessionB);
      expect(loadedB!.structure, StructureInstinct.divergent);
      final loadedA = await repo.getStyleProfile(sessionA);
      expect(loadedA!.structure, StructureInstinct.linear);
      expect(loadedA.summary, sampleProfile.summary);
    });

    test('#B57-D2 无任何有效记录 → no-op 不抛出', () async {
      // sessionId 存在但 style_profile 为空
      await expectLater(repo.updateLatestStyleProfile(corrected), completes);
    });
  });
}
