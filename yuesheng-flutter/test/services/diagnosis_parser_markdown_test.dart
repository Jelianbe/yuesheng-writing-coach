// diagnosis_parser_markdown_test — ADR-C82：模型先验 markdown 代码块包裹兼容
//
// 实测证据（2026-09-07 模拟器）：deepseek 系模型在长历史对话下对诊断 JSON
// 输出 ```` ```diagnosis ```` 包裹而非 [YS_DIAGNOSIS] 标记，导致 parseDiagnosis
// 走 _parseNoMarker（diagnosis=null），诊断卡静默不触发。本组验证兼容路径
// 与回归护栏。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';

/// 合法诊断 JSON（syndromes 为对象数组，符合 _validateSyndromes 契约）。
const String _validDiagnosisJson =
    '{'
    '"syndromes": [{'
    '"syndrome_id": "P019", '
    '"name": "直白抒情", '
    '"severity": "L2", '
    '"evidence": ["She did not dare to move"], '
    '"explanation": "内心解释替代画面"'
    '}], '
    '"suggested_actions": ["引导学员对比内心解释与可见动作"], '
    '"confidence": 0.6'
    '}';

void main() {
  group('parseDiagnosis markdown 兼容（ADR-C82）', () {
    test('```diagnosis 包裹的合法 JSON → 解析出 diagnosis', () {
      const raw =
          '收到。这段写法有改进空间。\n'
          '```diagnosis\n'
          '$_validDiagnosisJson\n'
          '```';
      final result = parseDiagnosis(raw);
      expect(result.diagnosis, isNotNull, reason: 'markdown 包裹的诊断块应被解析');
      expect(result.diagnosis!.confidence, 0.6);
      expect(result.diagnosis!.syndromes, hasLength(1));
      expect(
        result.displayContent,
        contains('收到。这段写法有改进空间。'),
        reason: '诊断块应被剥离，正文保留',
      );
      expect(
        result.displayContent,
        isNot(contains('```diagnosis')),
        reason: '代码块不应泄漏到展示内容',
      );
    });

    test('markdown 块 JSON 解码失败 → 保持无诊断（不崩溃）', () {
      const raw = '正文\n```diagnosis\n{not valid json\n```';
      final result = parseDiagnosis(raw);
      expect(result.diagnosis, isNull);
      expect(result.displayContent, isNot(contains('```diagnosis')));
    });

    test('无任何块 → diagnosis null 且原样展示', () {
      const raw = '普通聊天回复，无诊断块。';
      final result = parseDiagnosis(raw);
      expect(result.diagnosis, isNull);
      expect(result.displayContent, raw);
    });

    test('[YS_DIAGNOSIS] 标记路径不回归（协议真源优先）', () {
      const raw =
          '正文\n[YS_DIAGNOSIS]\n'
          '$_validDiagnosisJson\n'
          '[/YS_DIAGNOSIS]';
      final result = parseDiagnosis(raw);
      expect(result.diagnosis, isNotNull);
      expect(result.diagnosis!.confidence, 0.6);
      expect(result.displayContent, '正文');
    });

    test('markdown 块出现在文本中部 → 前后正文都保留', () {
      const raw =
          '前文点评。\n```diagnosis\n'
          '$_validDiagnosisJson\n'
          '```\n后文补充。';
      final result = parseDiagnosis(raw);
      expect(result.diagnosis, isNotNull);
      expect(result.displayContent, contains('前文点评。'));
      expect(result.displayContent, contains('后文补充。'));
      expect(result.displayContent, isNot(contains('```')));
    });
  });
}
