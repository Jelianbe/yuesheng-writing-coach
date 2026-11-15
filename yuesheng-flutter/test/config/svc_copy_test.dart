// svc_copy_test — L-SVC 层单一真源（R-027 任务 A）
//
// 锚定：
//   1. kOperationFailed 模板形态与「重试」统一收尾（无「再试」变体）；
//   2. 各迁移文案与原服务层硬编码逐字一致（回归不冻结文案本身，
//      但单一真源必须自证产出形态正确）；
//   3. AppError.toUserMessage 按 code 映射且不外露内部 message。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/svc_copy.dart';
import 'package:writingcoach/services/app_error.dart';

void main() {
  group('kOperationFailed', () {
    test(r'无 next：$action失败，请稍后重试', () {
      expect(kOperationFailed('加载'), '加载失败，请稍后重试');
    });

    test('有 next：追加句原样拼接', () {
      expect(kOperationFailed('保存', next: '（请到设置页检查）'), '保存失败，请稍后重试（请到设置页检查）');
    });

    test('统一「重试」，不产出「再试」', () {
      expect(kOperationFailed('操作'), isNot(contains('再试')));
    });
  });

  group('LLM 错误码文案', () {
    test('timeout / server 带参数逐字形态', () {
      expect(kLlmTimeoutMessage(60), '请求超时（60秒无响应），请稍后重试');
      expect(kLlmServerMessage(503), '服务端异常（HTTP 503），请稍后重试');
    });

    test('rateLimited 统一「重试」（原 llm_error_codes 误写「再试」）', () {
      expect(kLlmRateLimitedMessage, '请求过于频繁，请稍后重试');
      expect(kLlmRateLimitedMessage, isNot(contains('再试')));
    });
  });

  group('熔断开路 / 流式超时', () {
    test('熔断提示带秒数', () {
      expect(kCircuitOpenMessage(30), '服务暂时不可用（连续失败熔断），30 秒后自动恢复');
    });

    test('两段超时文案', () {
      expect(kStreamIdleInterruptMessage(60), '模型响应中断（超过 60 秒未收到新内容）');
      expect(kStreamConnectTimeoutMessage(30), '模型响应超时（超过 30 秒未返回首个字符）');
    });
  });

  group('兜底 / 占位文案', () {
    test('编辑观察兜底逐字不变', () {
      expect(kEditorObservationFailed, '审稿通过，但生成编辑观察失败，请稍后重试');
    });

    test('会话缺失提示逐字不变', () {
      expect(kSessionMissingReopen, '会话不存在或已被删除，请重新打开教练面板');
    });

    test('空输出占位按保存物分型', () {
      expect(
        kEmptyContentSavedNotice(syndromeCount: 1),
        '诊断数据已保存（1 条症候），但这次教练没有附上文字点评——通常是网络或模型临时故障。',
      );
      expect(
        kEmptyContentSavedNotice(entityCount: 2),
        '大纲实体已保存（2 条），但这次教练没有附上文字点评——通常是网络或模型临时故障。',
      );
    });
  });

  // ── 空输出 / 失败路径回归（T-20261115-06 U3 · 2026-11-15）──────────────
  //
  // 判据目标：四类路径渲染结果**不得为空白**，且**不得回退成已释放的固定串**
  // （`kReportFooter` 与旧 `kDiagnosisEmptyFallback='诊断完成'`）。
  //
  // ⚠️ 口径诚实：本组验证的是**文案层**（四类路径产出的字符串），不是
  // widget 渲染层。但链路可推理：`diagnosis_flow_handler._writeAssistantMessage`
  // 的唯一兜底是 `content.trim().isEmpty ? kDiagnosisEmptyFallback : content`
  // ⇒ 只要该常量非空且非空白，该路径的 assistant 消息就必然非空。
  // 真正的 widget 渲染回归不在本组视野，如实登记（见卡 §未验）。
  group('空输出/失败路径 · 不得空白、不得回退已释放固定串', () {
    const releasedOld = '诊断完成';

    test('① 模型返回空文字 → 兜底非空、非空白、非旧四字', () {
      final text = kDiagnosisEmptyFallback;
      expect(text.trim().isNotEmpty, isTrue, reason: '空白回复 = 直接判红');
      expect(
        text.contains(releasedOld),
        isFalse,
        reason: '不得回退成已释放的「$releasedOld」（失败路径上它会谎称已完成）',
      );
      expect(
        text.length,
        greaterThanOrEqualTo(15),
        reason: '短于此不足以说明「没拿到结论」这件事（旧串仅 4 字即反例）',
      );
    });

    test('①b 兜底给出可操作下一步（不是一个死胡同）', () {
      final text = kDiagnosisEmptyFallback;
      final hasAction =
          text.contains('再') || text.contains('重试') || text.contains('换');
      expect(hasAction, isTrue, reason: '只报错不给下一步 = 学员卡死');
    });

    test('② 网络失败 → 非空且可操作', () {
      expect(kLlmNetworkMessage.trim().isNotEmpty, isTrue);
      expect(kLlmNetworkMessage.contains('重试'), isTrue);
    });

    test('③ 熔断 → 非空且带恢复时间（可操作）', () {
      final text = kCircuitOpenMessage(30);
      expect(text.trim().isNotEmpty, isTrue);
      expect(text.contains('30'), isTrue, reason: '恢复秒数必须出现在文案里，否则学员不知道等多久');
    });

    test('④ 流中断 → 非空且说明内容可能不完整', () {
      expect(kStreamTruncatedMessage.trim().isNotEmpty, isTrue);
      expect(
        kStreamTruncatedMessage.contains('不完整'),
        isTrue,
        reason: '断开却不说明，学员会把残段当完整回复',
      );
      expect(kStreamIdleInterruptMessage(15).trim().isNotEmpty, isTrue);
    });

    test('⑤ 已释放固定串在全库不再作为用户文案出现', () {
      // 形态断言：新文案不得与已释放旧串重合，否则等于没释放。
      for (final text in [
        kDiagnosisEmptyFallback,
        kEmptyContentSavedNotice(syndromeCount: 1),
      ]) {
        expect(text.contains('✨'), isFalse, reason: '不得残留报告尾加油的装饰符');
        expect(text.contains(releasedOld), isFalse);
      }
    });
  });

  group('AppError.toUserMessage', () {
    test('可重试族走 svc_copy 真源', () {
      expect(
        const AppError(AppErrorCode.network, '内部详情：socket 104').toUserMessage(),
        kLlmNetworkMessage,
      );
      expect(
        const AppError(AppErrorCode.rateLimited, 'x').toUserMessage(),
        kLlmRateLimitedMessage,
      );
      expect(
        const AppError(AppErrorCode.timeout, 'x').toUserMessage(),
        kOperationFailed('操作'),
      );
    });

    test('不外露内部 message', () {
      const err = AppError(AppErrorCode.internal, 'LeakingStackTrace: #0 main');
      expect(err.toUserMessage(), isNot(contains('LeakingStackTrace')));
    });

    test('取消为预期行为 → 空串', () {
      expect(
        const AppError(AppErrorCode.cancelled, '用户取消').toUserMessage(),
        '',
      );
    });
  });
}
