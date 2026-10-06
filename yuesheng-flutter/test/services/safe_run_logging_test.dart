// ─────────────────────────────────────────────────────────────
// safe_run_logging_test — CR-53 [SafeRun] 降级统一留痕契约
//
// 背景：message_injector / chat_service 的「不阻断主流程」降级路径
// 此前只有 debugPrint（release 不输出→生产静默、无法归因），
// 与诊断编排（captureError 正确形态）形成实现分歧。
// 修复：抽 _logSafeRun helper + 替换全部降级点（CR-53）。
//
// 覆盖：
//   1. 源码契约：两文件各定义 _logSafeRun helper
//   2. 源码契约：降级点全部经 _logSafeRun（无裸 debugPrint('[SafeRun]）
//   3. 源码契约：catch 形态带 st（捕获栈传给 helper）
//   4. 行为契约：captureError 真实落 error_logs（level/category 归一）
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/services/error_handler.dart';

void main() {
  group('CR-53 [SafeRun] 统一留痕契约', () {
    test('1. chat_service 与 message_injector 各定义 _logSafeRun helper', () {
      for (final f in [
        'lib/services/chat_service.dart',
        'lib/services/message_injector.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(
          src,
          contains('void _logSafeRun(String stage, Object e, StackTrace s)'),
          reason: '$f 必须定义统一留痕 helper（CR-53）',
        );
      }
    });

    test('2. 降级点全部经 _logSafeRun，无裸 debugPrint([SafeRun])', () {
      for (final f in [
        'lib/services/chat_service.dart',
        'lib/services/message_injector.dart',
        // ★ B5 甲-1（2026-10-06）：新纳入 —— 该文件承载原
        //   `ChatServiceDiagnosisFocus` 的降级 catch，其降级点走**注入的
        //   `onSafeRun` 回调**（宿主传 `_logSafeRun` 的引用）。
        //   ⚠️ 纳入而非豁免：本用例的意图是「降级点全部经统一留痕通道」，
        //   只扫老文件等于让新文件的降级点**不受契约覆盖**（漏检）。
        'lib/services/chat_service_diagnosis_focus.dart',
      ]) {
        final src = File(f).readAsStringSync();
        // helper 定义内 1 处 debugPrint('[SafeRun] $stage: $e') 合法
        final bare = RegExp(r"debugPrint\('\[SafeRun\]").allMatches(src).length;
        expect(
          bare,
          lessThanOrEqualTo(1),
          reason: '$f 中降级点必须走 _logSafeRun，不允许裸 debugPrint（允许 helper 内 1 处）',
        );
        // ★ 降级调用有两种合法形态（口径随 B5 的依赖注入而扩展）：
        //   ① `_logSafeRun(` —— 直接调宿主私有 helper（原有两个文件）
        //   ② `onSafeRun(`   —— 独立类的注入回调（B5 新增的那个文件）
        //   两条通道最终都落到同一个 `ErrorHandler.captureError`，
        //   故按「两者出现数之和」计总数点。
        // ⚠️ 不写成 `(_logSafeRun|onSafeRun)\(` 单正则：那会把字段声明
        //   `final void Function(...) onSafeRun;` 与构造参数 `required this.onSafeRun`
        //   一并计入，与「调用数」语义不符（既有代码对 `_logSafeRun` 用 -1
        //   扣定义也是同一类手工校正，见下方注释）。
        final calls =
            RegExp(r"_logSafeRun\(").allMatches(src).length +
            RegExp(
              r"(?<!this\.)(?<!final )onSafeRun\(",
            ).allMatches(src).length -
            // 宿主文件里减去 helper 自身定义 1 处
            (f.endsWith('chat_service.dart') ? 1 : 0);
        expect(calls, greaterThan(0), reason: '$f 至少一个降级点调用留痕通道');
      }
      // 全量：message_injector 36 + chat_service 2 + diagnosis_focus 1 = 39 处降级点
      // （批次 E1-b 新增 1 处：设定层观察注入的降级 catch；
      //  2026-09-16 设定资料库第一批新增 1 处：拒绝记忆聚合降级 catch；
      //  2026-09-17 设定资料库第二批新增 1 处：负断言聚合降级 catch；
      //  2026-09-17 设定资料库第二批新增 1 处：设定命中展开降级 catch；
      //  2026-09-17 设定资料库第二批新增 1 处：钉选名片注入降级 catch；
      //  2026-09-17 设定资料库第二批新增 1 处：热度名片注入降级 catch）。
      // 注：审查文档估算 30（含诊断编排 helper 或重复计数），
      // 实际全仓 grep 无裸 debugPrint('[SafeRun] 残留。
      // ⚠️ 本用例是**纯文本计数**型护栏：注释里若写出 helper 的完整调用串
      //    也会被计入（C92-6b 同款教训），故本文件注释一律不写完整调用形式。
      // ADR-C116 A2（v2）2026-10-01 新增 2 处：学员焦点解析失败留痕（序数/
      // 别名多命中/P 码不在集）+ 读取最近 assistant 清单失败 catch。
      // ADR-C134 批 2（2026-10-02）新增 2 处 fading 降级点（chat_service）：
      // _buildFadingBlock 装配失败 + _resolveFadingEligibility 资格裁决失败。
      // ★ B5 甲-1（2026-10-06）：总数 **39 不变** —— 不是放宽，而是**换了归属**：
      //   原属chat_service 的 1 处（升级阀诊断次数统计失败）随
      //   `ChatServiceDiagnosisFocus` 迁至 `chat_service_diagnosis_focus.dart`，
      //   通道由 `_logSafeRun` 直调改为 `onSafeRun` 回调注入。
      //   ⇒ 覆盖面**扩大**（多扫一个文件），总数逐处可追溯。
      final mi = File('lib/services/message_injector.dart').readAsStringSync();
      final cs = File('lib/services/chat_service.dart').readAsStringSync();
      final df = File(
        'lib/services/chat_service_diagnosis_focus.dart',
      ).readAsStringSync();
      final miCalls = '_logSafeRun('.allMatches(mi).length - 1;
      final csCalls = '_logSafeRun('.allMatches(cs).length - 1;
      final dfCalls = RegExp(r"(?<!this\.)onSafeRun\(").allMatches(df).length;
      expect(
        miCalls + csCalls + dfCalls,
        39,
        reason:
            'CR-53 应覆盖全部降级点'
            '（实际 mi=$miCalls cs=$csCalls df=$dfCalls）',
      );
    });

    test('3. catch 形态带栈：降级 catch 均捕获 st 并传入 helper', () {
      final cs = File('lib/services/chat_service.dart').readAsStringSync();
      final mi = File('lib/services/message_injector.dart').readAsStringSync();
      final df = File(
        'lib/services/chat_service_diagnosis_focus.dart',
      ).readAsStringSync();
      // 降级点应形如 catch (e, st) { <留痕调用>('...', e, st); }
      // ★ B5：留痕调用有两种合法形态（直调 / 注入回调），用交替匹配。
      //   用分隔符 `(?:\(\?|)` 会误配（`(` 是量词组开头）—— 改用非捕获组。
      final pattern = RegExp(
        r"catch \(e, st\) \{\s*(?:_logSafeRun|onSafeRun)\('[^']*', e, st\);",
      );
      // ADR-C134 批 2：chat_service 新增 2 处 fading 降级 catch
      // （_buildFadingBlock / _resolveFadingEligibility），带栈形态合规 2→4。
      // ★ B5 甲-1：chat_service 的升级阀降级 catch 迁至 diagnosis_focus
      //   （4 → 3），新增文件补 1 处（3 → 1），**两文件合计仍 4 处**。
      expect(
        pattern.allMatches(cs).length + pattern.allMatches(df).length,
        4,
        reason:
            'chat_service + diagnosis_focus 合计 4 处降级点必须带栈（CR-53）'
            '（实际 cs=${pattern.allMatches(cs).length} '
            'df=${pattern.allMatches(df).length}）',
      );
      expect(
        pattern.allMatches(mi).length,
        greaterThanOrEqualTo(24),
        reason:
            'message_injector 降级点必须带栈（实测 ${pattern.allMatches(mi).length} 处）',
      );
    });
  });

  group('CR-53 行为：captureError 落库', () {
    test('captureError 经真实 ErrorLogRepository 落 error_logs', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      ErrorHandler.instance.resetForTesting();
      ErrorHandler.instance.attachRepository(ErrorLogRepository(db));

      ErrorHandler.instance.captureError(
        level: 'error',
        category: 'database',
        message: '[SafeRun] 测试降级留痕: boom',
        stack: 'test stack trace',
      );

      // flush 为异步（unawaited _persist）——轮询等待落库
      var rows = <ErrorLog>[];
      for (var i = 0; i < 50; i++) {
        rows = await db.select(db.errorLogs).get();
        if (rows.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(rows, hasLength(1), reason: 'captureError 应落库');
      expect(rows.single.message, contains('测试降级留痕'));
      expect(rows.single.level, 'error');
      expect(rows.single.category, 'database');
    });
  });
}
