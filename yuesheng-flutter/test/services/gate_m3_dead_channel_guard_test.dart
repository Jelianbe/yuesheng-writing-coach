// ─────────────────────────────────────────────────────────────
// 发布门槛 M3 — 死通道可达性护栏（2026-10-13 四任务书 §4-M3；S2 落地）
//
// 审计（批 1 E-DEAD）确认的「写而无消费」通道，逐条建立生产可达性护栏：
//
//   ① formatValidationErrors（diagnosis_validator.dart:663）
//      生产零调用（同文件 :56 注释自证「无人调」）。纯死代码 →
//      「存在性 + 行为」护栏：删除或改名时编译/断言双红。
//      处置待定：接线（给上层 UI 报校验摘要）或删除，均须同批更新本护栏。
//
//   ② isWeakUnconfirmed（evidence_confidence.dart:71）
//      生产零调用（Part B 门实际由 repository 的 SQL 条件承担，
//      见 ④）。纯死代码 → 存在性护栏 + 行为锚定。处置待定。
//
//   ③ _kD3DiagnosisGuidance（skill_dispatcher.dart:142）
//      有意保留的待接线死代码（ignore: unused_element + 注释写明启用
//      须经舰长批准的重冻流程）→ 源码级护栏：删内容 / 丢注释 / 绕过
//      重冻流程直接接线，三者任一发生本护栏变红。
//
//   ④ evidenceConfidence（active_problem 列）
//      有生产 wiring：写库（diagnosis_repository.dart 写入侧
//      _evidenceConfidenceFor → computeEvidenceConfidence）+ SQL 注入门
//      （listActiveProblems 的 where 条件引用 kWeakEvidenceConfidence）。
//      → wiring 护栏：删除写入侧 / 改动门条件（剔除把握度判据）即红。
//
//   ⚠️ partial.level（diagnosis_service.confirmDiagnosis 写入）**不在本护栏
//      范围**：2026-09-19 交互批 P0-1 已定性为「留痕设计」（该文件
//      :208-213 注释仍在，2026-10-14 复核确认），零消费者是有意为之，
//      不得再报缺陷——见该注释「后人勿把『字段零消费者』再报成缺陷」。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';
import 'package:writingcoach/services/evidence_confidence.dart';

/// 包根定位：从 cwd 向上回溯，直到同时存在 lib/ 与 test/
/// （同 progressive_chunk_syndrome_coverage_test 的口径）。
Directory _findPackageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (Directory('${dir.path}/lib').existsSync() &&
        Directory('${dir.path}/test').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError('找不到包根目录（cwd=${Directory.current.path}）');
}

final Directory _root = _findPackageRoot();

String _readSrc(String relPath) {
  final f = File('${_root.path}/$relPath');
  if (!f.existsSync()) {
    throw StateError('源文件不存在：$relPath（root=${_root.path}）');
  }
  return f.readAsStringSync();
}

void main() {
  group('M3-① formatValidationErrors：零生产调用死代码的存在性护栏', () {
    // ⚠️ 处置待定：本函数当前生产零调用（diagnosis_validator.dart:56 自证）。
    // 若 S 系列后续把它接进上层（校验摘要 UI）或彻底删除，须同批更新本护栏：
    // 接线后应升级为「调用点可达性」断言；删除后本组整体移除。
    test('函数存在且行为锚定（删除/改名即红）', () {
      const result = FullValidationResult(
        passed: false,
        displayContent: 'x',
        diagnosis: null,
        jsonValidation: DiagnosisValidationResult(valid: true, errors: []),
        nlValidation: NlValidationResult(
          valid: false,
          fixes: [NlFix(type: 'V-03', original: 'T03', replacement: '某技法')],
          cleaned: 'x',
        ),
      );
      final formatted = formatValidationErrors(result);
      expect(
        formatted,
        contains('[V-03 编号泄漏]'),
        reason:
            'formatValidationErrors 被删除或改名时本断言编译失败/变红——'
            '这是刻意的护栏：其处置（接线或删除）必须是显式决定，不得静默消失',
      );
    });
  });

  group('M3-② isWeakUnconfirmed：零生产调用死代码的存在性护栏', () {
    // ⚠️ 处置待定：Part B 的弱把握门当前由 repository SQL 条件直接承担（④），
    // 本纯函数无人调用。删除或接线须同批更新本护栏。
    test('函数存在且判定语义锚定（删除/改名即红）', () {
      // 弱把握 + 未确认 → gated。
      expect(
        isWeakUnconfirmed(evidenceConfidence: 0.3, confirmed: false),
        isTrue,
      );
      // 把握度达标 / 已确认 / 无把握度（legacy 数据）→ 不 gated。
      expect(
        isWeakUnconfirmed(evidenceConfidence: 0.5, confirmed: false),
        isFalse,
      );
      expect(
        isWeakUnconfirmed(evidenceConfidence: 0.3, confirmed: true),
        isFalse,
      );
      expect(
        isWeakUnconfirmed(evidenceConfidence: null, confirmed: false),
        isFalse,
      );
    });
  });

  group('M3-③ _kD3DiagnosisGuidance：有意保留待接线（源码级护栏）', () {
    test('D3 提示块仍在、仍带「静默未接线」标注与重冻流程启用约定', () {
      final src = _readSrc('lib/services/skill_dispatcher.dart');
      expect(
        src.contains('_kD3DiagnosisGuidance'),
        isTrue,
        reason:
            'D3「疑似未收录毛病」提示块被删除——若已裁定弃用，'
            '应同步移除本护栏并留痕；若只是误删，须恢复',
      );
      expect(
        src.contains('ignore: unused_element'),
        isTrue,
        reason:
            'D3 块的「有意保留死代码」标注（ignore: unused_element）丢失——'
            '分析器将把该 const 报为未使用，静默接线也会失去这层提示',
      );
      expect(
        src.contains('重冻流程'),
        isTrue,
        reason:
            'D3 块的启用约定注释（须经舰长批准的重冻流程，会改诊断 '
            'system prompt 触发锚点重冻）丢失——接线前必须恢复该约定',
      );
    });
  });

  group('M3-④ evidenceConfidence：写库 + SQL 注入门的生产 wiring 护栏', () {
    test('写入侧：evidence 把握度仍由 computeEvidenceConfidence 现算并落库', () {
      final src = _readSrc('lib/data/repositories/diagnosis_repository.dart');
      expect(
        src.contains('_evidenceConfidenceFor('),
        isTrue,
        reason:
            '_evidenceConfidenceFor（写库前的把握度现算入口）被移除——'
            '删除消费者/wiring 时此测试变红是设计行为：'
            'evidenceConfidence 的写入链路变更是显式决定',
      );
      expect(
        src.contains('computeEvidenceConfidence('),
        isTrue,
        reason:
            '仓储不再引用 computeEvidenceConfidence——把握度计算与落库'
            '解绑（evidence_confidence.dart 通道被拆）时此护栏变红',
      );
    });

    test('门侧：listActiveProblems 注入门仍以把握度为放行条件', () {
      final src = _readSrc('lib/data/repositories/diagnosis_repository.dart');
      expect(
        src.contains('evidenceConfidence.isNull()'),
        isTrue,
        reason:
            'listActiveProblems 的 SQL 注入门不再看 evidenceConfidence——'
            '弱把握症候将无差别进入活跃注入（Part B 门失效）',
      );
      expect(
        src.contains('kWeakEvidenceConfidence'),
        isTrue,
        reason:
            '门条件不再引用 kWeakEvidenceConfidence 阈值——'
            '阈值真源（evidence_confidence.dart）与门解绑',
      );
    });
  });
}
