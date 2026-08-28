// ─────────────────────────────────────────────────────────────
// diagnosis_contract_test — B29 诊断解析 + 系统提示契约测试
//
// 锁定三类不应随重构漂移的行为：
//   1. DiagnosisParser 往返：合法 [YS_DIAGNOSIS] 块解析 → 字段齐全；
//      重建成协议文本再解析 → 关键字段一致（解析稳定）。
//   2. 失败降级：非法 JSON / 残缺块 / 无块 → diagnosis=null 但 displayContent 保留。
//   3. buildSystemPromptV2：L1 常驻核心 skill 必在、位置判断引导语必在、
//      L2 按需组按 mode 注入；[YS_ENTITY] 大纲协议块必注入。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/outline_service.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/skill_layers.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

const String _kValidDiagnosisJson = '''
{
  "syndromes": [
    {
      "syndrome_id": "P007",
      "name": "句式单一",
      "severity": "L2",
      "evidence": ["他跑了", "她笑了"],
      "explanation": "句式重复缺乏变化"
    },
    {
      "syndrome_id": "P010",
      "name": "OC平面化",
      "severity": "L3",
      "evidence": ["两人对峙"],
      "explanation": "缺少张力与层次"
    }
  ],
  "suggested_actions": ["A003", "A004"],
  "confidence": 0.85,
  "root_cause_analysis": "结构层面缺乏变化",
  "next_focus": "P007",
  "feedback_summary": "建议先做句式练习",
  "suggested_phase": "P2_PRACTICE_LOOP",
  "suggested_beginner_level": "N2_SCENE",
  "teaching_mode": "socratic"
}
''';

String buildRaw(String innerJson, {String prefix = '', String suffix = ''}) =>
    '$prefix[YS_DIAGNOSIS]\n$innerJson[/YS_DIAGNOSIS]$suffix';

void main() {
  group('DiagnosisParser 往返一致性', () {
    test('合法块：解析字段齐全 + displayContent 剥离协议块', () {
      final raw = buildRaw(
        _kValidDiagnosisJson,
        prefix: '这是诊断说明文字。\n',
        suffix: '\n继续加油。',
      );
      final result = parseDiagnosis(raw);

      expect(result.diagnosis, isNotNull);
      final d = result.diagnosis!;
      expect(d.syndromes.length, 2);
      expect(d.syndromes[0].syndromeId, 'P007');
      expect(d.syndromes[0].severity, Severity.l2);
      expect(d.syndromes[0].evidence, ['他跑了', '她笑了']);
      expect(d.suggestedActions, ['A003', 'A004']);
      expect(d.confidence, closeTo(0.85, 1e-9));
      expect(d.suggestedPhase, TeachingPhase.p2PracticeLoop);
      expect(d.suggestedBeginnerLevel, BeginnerLevel.n2Scene);
      expect(d.teachingMode, TeachingMode.socratic);

      // displayContent 必须剥离 [YS_DIAGNOSIS] 块，仅保留前后自然语言
      expect(result.displayContent, contains('这是诊断说明文字。'));
      expect(result.displayContent, contains('继续加油。'));
      expect(result.displayContent, isNot(contains('[YS_DIAGNOSIS]')));
      expect(result.displayContent, isNot(contains('syndrome_id')));
    });

    test('重建往返：从解析结果重建协议块再解析 → 关键字段一致', () {
      final first = parseDiagnosis(buildRaw(_kValidDiagnosisJson)).diagnosis!;
      // 从 ParsedDiagnosis 重建一份协议 JSON（仅取契约关心的字段）
      final rebuilt = {
        'syndromes': first.syndromes
            .map(
              (s) => {
                'syndrome_id': s.syndromeId,
                'name': s.name,
                'severity': s.severity.value,
                'evidence': s.evidence,
                'explanation': s.explanation,
              },
            )
            .toList(),
        'suggested_actions': first.suggestedActions,
        'confidence': first.confidence,
      };
      final second = parseDiagnosis(buildRaw(jsonEncode(rebuilt))).diagnosis!;

      expect(second.syndromes.length, first.syndromes.length);
      expect(
        second.syndromes.map((s) => s.syndromeId).toList(),
        first.syndromes.map((s) => s.syndromeId).toList(),
      );
      expect(second.suggestedActions, first.suggestedActions);
      expect(second.confidence, first.confidence);
    });
  });

  group('DiagnosisParser 失败降级', () {
    test('非法 JSON 块 → diagnosis=null 但 displayContent 保留', () {
      final raw = '正常文本\n[YS_DIAGNOSIS]\n{ 这不是合法 json \n[/YS_DIAGNOSIS]\n尾部说明';
      final result = parseDiagnosis(raw);
      expect(result.diagnosis, isNull);
      expect(result.displayContent, contains('正常文本'));
      expect(result.displayContent, contains('尾部说明'));
      // 协议块被剥离，不泄漏原始 JSON
      expect(result.displayContent, isNot(contains('[YS_DIAGNOSIS]')));
    });

    test('无诊断块 → diagnosis=null，原文原样返回', () {
      final raw = '今天想聊聊开头怎么写';
      final result = parseDiagnosis(raw);
      expect(result.diagnosis, isNull);
      expect(result.displayContent, raw);
    });

    test('confidence 越界 → 校验失败 diagnosis=null', () {
      const bad = '''
      {
        "syndromes": [{"syndrome_id":"P007","name":"x","severity":"L2","evidence":["a"],"explanation":"e"}],
        "suggested_actions": ["A003"],
        "confidence": 1.5
      }''';
      final result = parseDiagnosis(buildRaw(bad));
      expect(result.diagnosis, isNull);
    });
  });

  group('buildSystemPromptV2 契约', () {
    test('diagnosis 模式：L1 核心 + 位置引导 + L2 诊断组 全部注入', () {
      final result = buildSystemPromptV2(
        SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          subphase: TeachingSubphase.diagnosis,
          attitude: AttitudeLevel.doubao,
        ),
      );

      expect(result.systemPrompt, isNotEmpty);
      // 位置判断引导语始终注入末尾
      expect(result.systemPrompt, contains('内容位置判断（必读）'));

      // L1 常驻核心 skill：已注册项必须出现在 system prompt 中
      for (final id in l1SkillIds) {
        final skill = getSkill(id);
        if (skill != null) {
          expect(
            result.systemPrompt.contains(skill.content),
            isTrue,
            reason: 'L1 核心 skill 缺失: $id',
          );
        }
      }

      // L2 diagnosis 组：已注册项必须出现
      for (final ref in getL2SkillIds(L2Mode.diagnosis)) {
        final skill = getSkill(ref.skillId);
        if (skill != null) {
          expect(
            result.systemPrompt.contains(skill.content),
            isTrue,
            reason: 'L2 diagnosis skill 缺失: ${ref.skillId}',
          );
        }
      }
    });

    test('attitude 档位随 context 注入（态度档位 skill 生效）', () {
      final result = buildSystemPromptV2(
        SkillLoadContext(
          phase: TeachingPhase.p1World,
          attitude: AttitudeLevel.sensei,
        ),
      );
      expect(result.loadedSkillIds, contains('attitude-sensei'));
    });
  });

  group('[YS_ENTITY] 大纲协议块契约', () {
    test('实体协议说明包含 [YS_ENTITY] 开闭标记与输出顺序约束', () {
      // OutlineService.buildEntityProtocolContext 为纯函数（不触 repo），
      // 仅需一个占位 repo 构造实例。
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final service = OutlineService(OutlineRepository(db));
      final ctx = service.buildEntityProtocolContext();

      expect(ctx, contains('[YS_ENTITY]'));
      expect(ctx, contains('[/YS_ENTITY]'));
      // 强约束：实体块优先级高于自然语言诊断说明（防 max_tokens 截断丢失）
      expect(ctx, contains('宁可压缩自然语言诊断说明也不得省略'));
    });
  });

  group('临场输出约束契约', () {
    test('kLiveOutputConstraints 锁定关键指令不被误删', () {
      expect(kLiveOutputConstraints, contains('临场输出约束（最高优先级）'));
      expect(kLiveOutputConstraints, contains('一次只抛一个点'));
      expect(kLiveOutputConstraints, contains('表达密度'));
      expect(kLiveOutputConstraints, contains('不堆叠'));
    });
  });
}
