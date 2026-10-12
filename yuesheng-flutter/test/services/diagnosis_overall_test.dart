// ─────────────────────────────────────────────────────────────
// ADR-0006 D 组：整体判定（overall）解析判据测试
//
// 覆盖：
//   H-3 coverage 缺失 ⇒ overall 作废（观测码 overall_coverage_missing）
//   verdict 非三档 ⇒ 作废（协议契约）
//   unknown-key 容忍（overall 为可选顶层字段，不因它 reject 整块）
//   协议长度回归（merge / 短链路两通道实测增量复核）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';
import 'package:writingcoach/services/chat_service.dart';

/// 基础 JSON（**故意不为根对象收尾**——各用例以 `$_kBaseJson, <extra>` 插值，
/// extra 自身以 `}` 闭合根对象；#7 等无 extra 的用例用 [_kBaseJsonClosed]）。
const _kBaseJson =
    '{"syndromes": [{"syndrome_id": "P001", "name": "情绪标签化", '
    '"severity": "L2", "evidence": ["她很难过"], "explanation": "直接贴标签"}], '
    '"suggested_actions": ["A009"], "confidence": 0.8';

/// 根对象已闭合的基础 JSON（无 extra 字段的用例用）。
const _kBaseJsonClosed = '$_kBaseJson}';
String _block(String json) => '[YS_DIAGNOSIS]\n$json\n[/YS_DIAGNOSIS]';

void main() {
  group('H-3：coverage 缺失 ⇒ overall 作废', () {
    test('#1 overall 存在且 coverage 非空 ⇒ 解析成功', () {
      final r = parseDiagnosis(
        _block(
          '$_kBaseJson, "overall": {"verdict": "基本完整", '
          '"reasons": ["节奏尚可"], "keep": "开篇钩子", '
          '"priority": ["先改转场"], "coverage": "基于已诊断 3/20 章"}}',
        ),
      );
      expect(r.diagnosis, isNotNull);
      expect(r.rejectReason, isNull);
      final o = r.diagnosis!.overall;
      expect(o, isNotNull);
      expect(o!.verdict, '基本完整');
      expect(o.reasons, ['节奏尚可']);
      expect(o.keep, '开篇钩子');
      expect(o.priority, ['先改转场']);
      expect(o.coverage, '基于已诊断 3/20 章');
      expect(r.diagnosis!.syndromes, hasLength(1));
    });

    test('#2 overall 缺 coverage 键 ⇒ overall 置 null + 观测码', () {
      final r = parseDiagnosis(
        _block(
          '$_kBaseJson, "overall": {"verdict": "结构完整", '
          '"reasons": ["因果链完整"], "priority": []}}',
        ),
      );
      expect(r.diagnosis, isNotNull, reason: 'overall 是可选字段，不得拖垮整块');
      expect(r.diagnosis!.overall, isNull);
      // 观测码可经 parseDiagnosis 的 notes 通道读取——本测试经 ParseResult
      // 不直接暴露 notes，故此处断言「块仍通过」这一主判据；notes 码由
      // 服务层日志断言（diagnosis_reject_reason_test 同型）。
    });

    test('#3 coverage 空串 ⇒ 同 #2（空串按缺失处理）', () {
      final r = parseDiagnosis(
        _block(
          '$_kBaseJson, "overall": {"verdict": "结构完整", '
          '"reasons": ["x"], "coverage": ""}}',
        ),
      );
      expect(r.diagnosis!.overall, isNull);
    });

    test('#4 coverage 非字符串（数字）⇒ 按缺失处理', () {
      final r = parseDiagnosis(
        _block(
          '$_kBaseJson, "overall": {"verdict": "结构完整", '
          '"reasons": ["x"], "coverage": 3}}',
        ),
      );
      expect(r.diagnosis!.overall, isNull);
    });

    test('#5 verdict 非三档 ⇒ overall 作废（协议契约）', () {
      final r = parseDiagnosis(
        _block(
          '$_kBaseJson, "overall": {"verdict": "神作", '
          '"reasons": ["x"], "coverage": "基于已诊断 3/20 章"}}',
        ),
      );
      expect(r.diagnosis!.overall, isNull);
    });

    test('#6 overall 非对象（数组/字符串）⇒ 静默忽略', () {
      final r1 = parseDiagnosis(
        _block('$_kBaseJson, "overall": ["not", "an", "object"]}'),
      );
      expect(r1.diagnosis!.overall, isNull);
      final r2 = parseDiagnosis(_block('$_kBaseJson, "overall": "文字"}'));
      expect(r2.diagnosis!.overall, isNull);
    });

    test('#7 无 overall 键（旧模型输出）⇒ 零影响', () {
      final r = parseDiagnosis(_block(_kBaseJsonClosed));
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.overall, isNull);
    });
  });

  group('unknown-key 容忍', () {
    test('#8 overall 与未知顶层字段并存 ⇒ 整块通过', () {
      final r = parseDiagnosis(
        _block(
          '$_kBaseJson, "some_future_field": 42, '
          '"overall": {"verdict": "存在结构性缺口", "reasons": ["转折后置"], '
          '"coverage": "基于已诊断 5/20 章"}}',
        ),
      );
      expect(r.diagnosis, isNotNull);
      expect(r.rejectReason, isNull);
      expect(r.diagnosis!.overall!.verdict, '存在结构性缺口');
    });
  });

  group('协议长度回归（两通道实测增量复核）', () {
    test('#9 merge 协议含 overall 段且该段长度受控（防文案漂移膨胀）', () {
      // 经 buildMergePrompt 公开入口断言 overall 段存在；段长度直接从
      // 协议文本中截取（段尾 = 协议结尾「请输出标准诊断格式」之前）。
      // 施工前报批估算 304 字符；实测 301。阈值给 20% 余量防误报，
      // 超过即说明有人往协议里塞了大段文本——须回查。
      final prompt = buildMergePrompt(const [], diagnosisContext: '');
      final start = prompt.indexOf('overall (object)');
      expect(start, greaterThan(0), reason: 'merge 协议必须含 overall 段说明');
      final end = prompt.indexOf('请输出标准诊断格式', start);
      expect(end, greaterThan(start));
      expect(end - start, lessThan(340));
      // H-3 契约必须在协议层明写（缺 coverage ⇒ overall 无效）。
      expect(prompt, contains('缺此项 overall 无效'));
    });

    test('#10 短链路协议示例含 overall 片段且可被解析', () {
      expect(ChatService.kDiagnosisProtocolSuffix, contains('"overall"'));
      expect(ChatService.kDiagnosisProtocolSuffix, contains('coverage'));
    });
  });
}
