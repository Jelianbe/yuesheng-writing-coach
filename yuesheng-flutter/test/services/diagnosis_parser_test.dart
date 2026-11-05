// ─────────────────────────────────────────────────────────────
// diagnosis_parser 测试（含批次74修复：后缀回拼 + 协议块剥离）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';

void main() {
  group('parseDiagnosis', () {
    test('#1 无标记：原文透传', () {
      final r = parseDiagnosis('你好，直接说点什么');
      expect(r.diagnosis, isNull);
      expect(r.displayContent, '你好，直接说点什么');
    });

    test('#2 无诊断块但含大纲块：displayContent 已剥离协议 JSON', () {
      const raw =
          '开头说明\n'
          '[YS_ENTITY]\n{"entities":[{"type":"character","key":"王建国"}]}\n[/YS_ENTITY]\n'
          '结尾说明';
      final r = parseDiagnosis(raw);
      expect(r.diagnosis, isNull);
      expect(r.displayContent, isNot(contains('[YS_ENTITY]')));
      expect(r.displayContent, isNot(contains('"entities"')));
      expect(r.displayContent, startsWith('开头说明'));
      expect(r.displayContent, endsWith('结尾说明'));
    });

    test('#2b 无诊断块但含 FACT 块：displayContent 剥离 FACT 协议 JSON', () {
      final r = parseDiagnosis('前导[YS_FACT]{"fact":1}[/YS_FACT]收尾');
      expect(r.diagnosis, isNull);
      expect(r.displayContent, isNot(contains('[YS_FACT]')));
      expect(r.displayContent, isNot(contains('"fact"')));
      expect(r.displayContent, startsWith('前导'));
      expect(r.displayContent, endsWith('收尾'));
    });

    test('#4b 有起始标记无结束标记 → rejectReason=marker_end_missing', () {
      final r = parseDiagnosis('开头[YS_DIAGNOSIS]{"syndromes":[]}');
      expect(r.diagnosis, isNull);
      expect(r.rejectReason, 'marker_end_missing');
    });

    test('#3 有诊断块但无大纲块：prefix 保留', () {
      const raw =
          '一段前导话\n'
          '[YS_DIAGNOSIS]\n'
          '{"syndromes":[{"syndrome_id":"P001","name":"情绪标签化","severity":"L1","evidence":["x"],"explanation":"y","reader_impact":"z"}],"suggested_actions":["A002"],"confidence":0.75,"feedback_summary":"ok","root_cause_analysis":"r","next_focus":"P001","teaching_plan":{"current_teaching_focus_id":"P001","focus_reason":"a","next_step":"b"}}\n'
          '[/YS_DIAGNOSIS]';
      final r = parseDiagnosis(raw);
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.syndromes.first.syndromeId, 'P001');
      expect(r.displayContent, contains('一段前导话'));
    });

    test('#4 诊断块前 + 大纲块 + 后缀自然语言 → displayContent=prefix+suffix自然语言（大纲块剥掉）', () {
      const raw =
          '自然语言前缀\n'
          '[YS_DIAGNOSIS]\n'
          '{"syndromes":[{"syndrome_id":"P003","name":"视角漂移","severity":"L1","evidence":["e1","e2"],"explanation":"x","reader_impact":"y"}],"suggested_actions":["A002"],"confidence":0.75,"feedback_summary":"ok","root_cause_analysis":"r","next_focus":"P003","teaching_plan":{"current_teaching_focus_id":"P003","focus_reason":"a","next_step":"b"}}\n'
          '[/YS_DIAGNOSIS]\n\n'
          '[YS_ENTITY]\n{"entities":[{"type":"character","key":"王建国","aliases":["建国"],"matched_entity_id":"","impressions":[{"text":"i"}]}]}\n[/YS_ENTITY]\n\n---\n\n'
          '后缀自然语言诊断说明：最后一处视角切换。';
      final r = parseDiagnosis(raw);
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.syndromes.first.syndromeId, 'P003');
      expect(r.displayContent, startsWith('自然语言前缀'));
      expect(r.displayContent, endsWith('后缀自然语言诊断说明：最后一处视角切换。'));
      expect(r.displayContent, isNot(contains('[YS_ENTITY]')));
      expect(r.displayContent, isNot(contains('"entities"')));
      expect(r.displayContent, isNot(contains('"key":"王建国"')));
    });

    test(
      '#5 诊断块占首位 + 后缀含大纲块+自然语言 → displayContent 返回自然语言（无协议JSON，不返回「诊断完成。」兜底）',
      () {
        // 批次74 live 真实结构：YS_DIAGNOSIS 先，YS_ENTITY 中，自然语言最后
        const raw =
            '[YS_DIAGNOSIS]\n'
            '{"syndromes":[{"syndrome_id":"P003","name":"视角漂移","severity":"L1","evidence":["e"],"explanation":"x","reader_impact":"y"}],"suggested_actions":["A002"],"confidence":0.75,"feedback_summary":"ok","root_cause_analysis":"r","next_focus":"P003","teaching_plan":{"current_teaching_focus_id":"P003","focus_reason":"a","next_step":"b"}}\n'
            '[/YS_DIAGNOSIS]\n\n'
            '[YS_ENTITY]\n{"entities":[{"type":"character","key":"林小芸"}]}\n[/YS_ENTITY]\n\n'
            '【位置判断：开头】\n\n你这段开头其实做了很多对的事。';
        final r = parseDiagnosis(raw);
        expect(r.diagnosis, isNotNull);
        expect(r.displayContent.trim(), isNotEmpty);
        expect(r.displayContent, startsWith('【位置判断：开头】'));
        expect(r.displayContent, endsWith('你这段开头其实做了很多对的事。'));
        expect(r.displayContent, isNot(contains('[YS_DIAGNOSIS]')));
        expect(r.displayContent, isNot(contains('[YS_ENTITY]')));
        expect(r.displayContent, isNot(contains('syndromes')));
        expect(r.displayContent, isNot(contains('林小芸')));
      },
    );

    test('#6 V8 嵌套（FACT 在 DIAGNOSIS 内）→ 诊断块整体保守丢弃，无协议 JSON 泄漏', () {
      // AI 误把 FACT 块放进诊断 JSON → jsonDecode 失败 → diagnosis=null；
      // 整块（含 FACT）随诊断块丢弃，displayContent 只留前后自然语言
      const raw =
          '自然语言前缀\n'
          '[YS_DIAGNOSIS]\n'
          '{"syndromes":[{"syndrome_id":"P001","name":"情绪标签化","severity":"L1","evidence":[],"explanation":"x","reader_impact":"y"}]\n'
          '[YS_FACT]\n{"events":[{"name":"决定去金陵","event_type":"决定"}]}\n[/YS_FACT]\n'
          '[/YS_DIAGNOSIS]\n'
          '自然语言后缀';
      final r = parseDiagnosis(raw);
      expect(r.diagnosis, isNull, reason: '嵌套 FACT 破坏诊断 JSON → 保守丢弃不解析');
      expect(r.displayContent, isNot(contains('[YS_DIAGNOSIS]')));
      expect(r.displayContent, isNot(contains('[YS_FACT]')));
      expect(r.displayContent, isNot(contains('syndromes')));
      expect(r.displayContent, isNot(contains('"events"')));
      expect(r.displayContent, contains('自然语言前缀'));
      expect(r.displayContent, contains('自然语言后缀'));
    });

    test('#7 V8 顺序错乱（FACT 在 DIAGNOSIS 之前）→ prefix 剥 FACT，诊断正常解析', () {
      const raw =
          '自然语言前缀\n'
          '[YS_FACT]\n{"events":[{"name":"决定去金陵","event_type":"决定"}]}\n[/YS_FACT]\n'
          '[YS_DIAGNOSIS]\n'
          '{"syndromes":[{"syndrome_id":"P001","name":"情绪标签化","severity":"L1","evidence":["x"],"explanation":"y","reader_impact":"z"}],"suggested_actions":["A002"],"confidence":0.75,"feedback_summary":"ok","root_cause_analysis":"r","next_focus":"P001","teaching_plan":{"current_teaching_focus_id":"P001","focus_reason":"a","next_step":"b"}}\n'
          '[/YS_DIAGNOSIS]';
      final r = parseDiagnosis(raw);
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.syndromes.first.syndromeId, 'P001');
      expect(r.displayContent, isNot(contains('[YS_FACT]')));
      expect(r.displayContent, isNot(contains('"events"')));
      expect(r.displayContent, contains('自然语言前缀'));
    });

    test('#8 V8 顺序错乱（FACT 在 DIAGNOSIS 之后）→ suffix 剥 FACT，诊断正常解析', () {
      const raw =
          '[YS_DIAGNOSIS]\n'
          '{"syndromes":[{"syndrome_id":"P001","name":"情绪标签化","severity":"L1","evidence":["x"],"explanation":"y","reader_impact":"z"}],"suggested_actions":["A002"],"confidence":0.75,"feedback_summary":"ok","root_cause_analysis":"r","next_focus":"P001","teaching_plan":{"current_teaching_focus_id":"P001","focus_reason":"a","next_step":"b"}}\n'
          '[/YS_DIAGNOSIS]\n'
          '[YS_FACT]\n{"events":[{"name":"决定去金陵","event_type":"决定"}]}\n[/YS_FACT]\n'
          '自然语言后缀';
      final r = parseDiagnosis(raw);
      expect(r.diagnosis, isNotNull);
      expect(r.diagnosis!.syndromes.first.syndromeId, 'P001');
      expect(r.displayContent, isNot(contains('[YS_FACT]')));
      expect(r.displayContent, isNot(contains('"events"')));
      expect(r.displayContent, contains('自然语言后缀'));
    });
  });

  // ── T-20261024-16（`DECISIONS §4-260④` 2026-10-25）：next_focus 与
  //    teaching_plan.next_step 的兼容性口径统一为 **next_focus 优先**
  //    （parser 对齐 validator 链 diagnosis_validator.dart:458-460）。
  //
  //    负向验证（本批已实测）：把 diagnosis_parser.dart:446 的 `??` 两侧
  //    换回旧序（teachingPlanNextStep ?? texts.nextFocus）后，**R1 转红**
  //    （parser 产物变 'B'，与 validator 的 'A' 分叉）；R2/R3/R4 守的是
  //    回退与缺失路径，旧序下同样成立，故不因换序转红——它们防的是
  //    「回退链被改断」，不是「优先级方向」。
  group('next_focus / next_step 兼容性口径（T-20261024-16）', () {
    Map<String, dynamic> diagJson({String? nextFocus, String? nextStep}) {
      return {
        'syndromes': [
          {
            'syndrome_id': 'P001',
            'name': '情绪标签化',
            'severity': 'L1',
            'evidence': ['x'],
            'explanation': 'y',
            'reader_impact': 'z',
          },
        ],
        'suggested_actions': ['A002'],
        'confidence': 0.75,
        if (nextFocus != null) 'next_focus': nextFocus,
        if (nextStep != null)
          'teaching_plan': {
            'current_teaching_focus_id': 'P001',
            'focus_reason': 'a',
            'next_step': nextStep,
          },
      };
    }

    String? parseNextFocus({String? nextFocus, String? nextStep}) {
      final raw =
          '[YS_DIAGNOSIS]\n'
          '${jsonEncode(diagJson(nextFocus: nextFocus, nextStep: nextStep))}\n'
          '[/YS_DIAGNOSIS]';
      return parseDiagnosis(raw).diagnosis!.nextFocus;
    }

    test('R1 两字段都填且不一致 ⇒ parser 产物 = next_focus，且与 validator 产物一致', () {
      final bothJson = diagJson(nextFocus: 'A', nextStep: 'B');
      // parser 链（本批改动点）
      expect(parseNextFocus(nextFocus: 'A', nextStep: 'B'), 'A');
      // validator 链口径 = next_focus 优先（未改动，作为对照真源）
      expect(
        validateDiagnosisOutput('自然语言', bothJson).diagnosis!.nextFocus,
        'A',
      );
    });

    test('R2 仅填 next_step ⇒ parser 产物 = next_step（回退仍生效）', () {
      expect(parseNextFocus(nextStep: 'B'), 'B');
    });

    test('R3 仅填 next_focus ⇒ parser 产物 = next_focus', () {
      expect(parseNextFocus(nextFocus: 'A'), 'A');
    });

    test('R4 两者都不填 ⇒ parser 产物 = null（走 fallback，本批不改 fallback）', () {
      expect(parseNextFocus(), isNull);
      expect(
        validateDiagnosisOutput('自然语言', diagJson()).diagnosis!.nextFocus,
        isNull,
      );
    });
  });

  // ── T-20261105-03（nextFocus 三级贯通）产出侧取值链 ──────────────
  //
  // 真源（现场重取）：`diagnosis_parser.dart:445`
  //   `final finalNextFocus = texts.nextFocus ?? plan.teachingPlanNextStep;`
  //   注释声明「与 validator 链（diagnosis_validator.dart:458-460）口径一致」；
  //   validator 侧实读 `diagnosis_validator.dart:513-515`
  //   `nextFocus: raw.nextFocusRaw is String ? raw.nextFocusRaw : teaching.nextStep`。
  //
  // 与上方 T-20261024-16 组（R1–R4）的分工 —— **不是重复**：
  //   R1–R4 钉「优先级方向 + 缺键回退 + 全缺失」三条主路径（夹具值只有 'A'/'B' 单字符）；
  //   本组钉 R1–R4 **覆盖不到的两个入口**：类型漂移（非 String）与空串，
  //   外加一条**整句逐字**（单字符夹具对「trim / 截断 / 改写」零鉴别力）。
  //
  // 负向实测（变异一次只改一行，读数见报告；**原预判保留、实测差异已标注**）：
  //   ① 删掉回退（`= texts.nextFocus`；原预判「NP1 / NP3 红、NP2 / NP4 绿」）
  //      ⇒ **实测** NP1 + NP2 红（+ 既有 R2 红），NP3 / NP4 绿。
  //      差异机制：NP2 的输入是**值级 null**，删掉 `??` 后产物变 null 而非 next_step ⇒
  //      NP2 也落在回退链上；NP3（空串，非 null）与 NP4（next_focus 有值）不经过 `??` 的
  //      回退支路 ⇒ 不红。原预判 NP3 属**过宽**（已导出机制，非用例缺口）。
  //   ② 让空串也回退（`trim().isEmpty` 时取 next_step）⇒ **实测**恰好 NP3 红。
  //   ③ 呈现侧 `widget.nextFocus` → 读兄弟字段 / 读常量串 ⇒ 见 diagnosis_card_test.dart 同批注释。
  group('T-20261105-03 产出侧：nextFocus 取值链（空串 / 类型漂移）', () {
    /// [omitNextFocus] 区分「键缺失」与「键存在但值为 null」——
    /// 两者在 `??` 语义下同号，但只有显式 null 能证明「值级 null 也回退」。
    Map<String, dynamic> diagJson({
      Object? nextFocus,
      bool omitNextFocus = false,
      String? nextStep,
    }) {
      return {
        'syndromes': [
          {
            'syndrome_id': 'P001',
            'name': '情绪标签化',
            'severity': 'L1',
            'evidence': ['x'],
            'explanation': 'y',
            'reader_impact': 'z',
          },
        ],
        'suggested_actions': ['A002'],
        'confidence': 0.75,
        if (!omitNextFocus) 'next_focus': nextFocus,
        if (nextStep != null)
          'teaching_plan': {
            'current_teaching_focus_id': 'P001',
            'focus_reason': 'a',
            'next_step': nextStep,
          },
      };
    }

    String? parseNextFocus(Map<String, dynamic> json) => parseDiagnosis(
      '[YS_DIAGNOSIS]\n${jsonEncode(json)}\n[/YS_DIAGNOSIS]',
    ).diagnosis!.nextFocus;

    test('NP1 next_focus 类型漂移（数字）⇒ 按缺失处理回退 next_step', () {
      final json = diagJson(nextFocus: 123, nextStep: 'B-next-step');
      expect(
        parseNextFocus(json),
        'B-next-step',
        reason:
            '回退链被删/被改成「非 String 也原样带出」时红：'
            '非 String ⇒ _parseOptionalTextFields 给 null ⇒ 必须走 teaching_plan.next_step',
      );
      // validator 链同号（口径一致的对照真源，不随本组改动）
      expect(
        validateDiagnosisOutput('自然语言', json).diagnosis!.nextFocus,
        'B-next-step',
        reason: '两链分叉即红（parser 回退 / validator 不回退）',
      );
    });

    test('NP2 next_focus 显式 null ⇒ 回退 next_step（值级 null 与缺键同号）', () {
      final json = diagJson(nextFocus: null, nextStep: 'B-next-step');
      expect(
        parseNextFocus(json),
        'B-next-step',
        reason: '「键在但值为 null」若被当成已给值 ⇒ 红（会得到 null）',
      );
      expect(
        validateDiagnosisOutput('自然语言', json).diagnosis!.nextFocus,
        'B-next-step',
      );
    });

    test('NP3 next_focus 空串 ⇒ 现状口径：**不**回退，产物为空串（两链一致）', () {
      final json = diagJson(nextFocus: '', nextStep: 'B-next-step');
      expect(
        parseNextFocus(json),
        '',
        reason:
            '本条钉现状口径（与 validator 链一致：String 类型即视为「已给值」⇒ 不触发回退）。'
            '两个方向都会红：① 回退链被删 ⇒ 得到 null；'
            '② 有人把判据改成「trim 后为空也回退」⇒ 得到 B-next-step。'
            '若内容层**有意**改口径为「空串回退」，须同步改本条并在 DECISIONS 登记。',
      );
      expect(
        validateDiagnosisOutput('自然语言', json).diagnosis!.nextFocus,
        '',
        reason: '两链口径必须同号；validator 改成回退而 parser 不改 ⇒ 红',
      );
    });

    test('NP4 整句逐字透传（不 trim / 不截断 / 不改写）', () {
      const sentence = '下一轮把第三段里那两句对话拆开，删掉中间那句解释性独白，让读者自己听出情绪';
      expect(
        parseNextFocus(diagJson(nextFocus: sentence)),
        sentence,
        reason: '逐字相等：任何 trim / 截断 / 改写 / 转义差异都会红',
      );
    });
  });
}
