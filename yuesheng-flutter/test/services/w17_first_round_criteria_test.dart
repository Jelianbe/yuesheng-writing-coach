// W-17 首轮判据装配护栏（2026-10-16）
//
// 覆盖（设计批 2026-10-16-W17-首轮判据装配设计批.md §四.3）：
//   ① 注入集 A（三巨头 P001/P002/P003）判据原文 verbatim 在场（含豁免/比例原则）；
//   ② 已批 header 一句逐字在场（R-027 现场批复，逐字 = 设计批 §三）；
//   ③ 非 diagnosis 模式不注入；④ 有活跃症候（非首轮）不重复注入；
//   ⑤ disabled P001 ⇒ 该段不在场（用户主权 R-009）；
//   ⑥ 注入集 ID 有效性：每个 ID 均能从 L3 手册提取非空段（防改名静默失踪）；
//   ⑦ verbatim 护栏：块内判据与 getSyndromeContent 剥 header 后逐字一致；
//   ⑧ 独立 system 消息形态（主 system prompt 字节不变 ⇒ 锚点零漂移依据）。
//
// ⑨ forceSceneFirst（P1-4 裸奔诊断）+ 空 active 同样在场。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/chat_message_types.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/l2_route_hysteresis.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/prompt_assembly_service.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 已批 header（逐字 = 设计批 §三批复文案；改动此串必须重走 R-027）。
const String _kApprovedHeader =
    '以下三条为高频症候的完整判据（判断原则与豁免条款在内）。'
    '首轮判定时逐条核对：命中各判据所列豁免/比例原则的形态不判；'
    '无判据支撑不得标 ID。';

/// 三巨头判据段的独特锚串（取自 manual_1/2 各段正文，verbatim 校验用）。
const Map<String, String> _kSectionAnchors = {
  'P001': '### P001 情绪标签化',
  'P002': '### P002',
  'P003': '### P003',
};

PromptAssemblyService _buildService({Set<String> disabled = const {}}) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final sessionRepo = SessionRepository(db);
  final injector = MessageInjector(
    sessionRepo: sessionRepo,
    diagnosisRepo: DiagnosisRepository(db),
    studentModelRepo: StudentModelRepository(db),
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
    manuscriptRepo: ManuscriptRepository(db),
    diagnosisCommitter: DiagnosisCommitter(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
    ),
    material: const MaterialCapabilityImpl(),
  );
  return PromptAssemblyService(
    teaching: const TeachingCapabilityImpl(),
    routeHysteresis: L2RouteHysteresis(),
    messageInjector: injector,
    appStateRepo: null,
    readDisabledSyndromeIds: () => disabled,
    logBudgetOutcome: (_, _) {},
    wholeChapterBlock: '',
  );
}

SendMessageOptions _options() => const SendMessageOptions(
  phase: TeachingPhase.p2PracticeLoop,
  attitude: AttitudeLevel.yuesheng,
);

void main() {
  group('W-17 · buildFirstRoundCriteriaBlock（单元）', () {
    test('已批 header 逐字在场（R-027 批文锚定）', () {
      final block = buildFirstRoundCriteriaBlock();
      expect(block.startsWith(_kApprovedHeader), isTrue);
    });

    test('三巨头判据段全部在场（注入集 A）', () {
      final block = buildFirstRoundCriteriaBlock();
      for (final entry in _kSectionAnchors.entries) {
        expect(
          block.contains(entry.value),
          isTrue,
          reason: '${entry.key} 判据段应在首轮判据块内',
        );
      }
    });

    test('⑥ 注入集 ID 有效性：每个 ID 均能提取非空段', () {
      for (final id in kFirstRoundCriteriaIds) {
        final section = getSyndromeCriteriaSections([id]);
        expect(
          section.isNotEmpty,
          isTrue,
          reason: '$id 提取为空 ⇒ 注册表/手册可能已改名，注入集静默失踪',
        );
      }
    });

    test('⑦ verbatim：块体判据与 getSyndromeContent 剥 header 后逐字一致', () {
      final block = buildFirstRoundCriteriaBlock();
      final full = getSyndromeContent(kFirstRoundCriteriaIds);
      // getSyndromeContent = header + '\n\n' + sections.join('\n\n---\n\n')
      // 剥出 sections 部分与 criteria 版比对（同提取函数同拼接序 ⇒ 必等）。
      final marker = '---\n\n';
      final idx = full.indexOf(marker);
      final sectionsFromFull = full.substring(idx + marker.length);
      expect(block.endsWith(sectionsFromFull), isTrue);
    });

    test('比例原则/不判条款随段在场（W-31 归因的关键缺口 = 豁免面 0% 在场）', () {
      // P001 段实际措辞锚串（实测：'豁免'0 次、'比例'1 次、'不判'2 次 ——
      // 判据正文一字不动，断言以正文真实用词为准）。
      final p001 = getSyndromeCriteriaSections(['P001']);
      expect(p001.contains('比例'), isTrue, reason: 'P001 段应含比例原则');
      expect(p001.contains('不判'), isTrue, reason: 'P001 段应含不判条款');
    });
  });

  group('W-17 · buildSystemPrompt 首轮注入（装配）', () {
    test('① 首轮（diagnosis 模式 + 无活跃症候）⇒ 独立 system 消息在场', () {
      final svc = _buildService();
      final messages = svc.buildSystemPrompt(
        TeachingPhase.p2PracticeLoop,
        AttitudeLevel.yuesheng,
        TeachingSubphase.diagnosis,
        false,
        sessionId: 'w17-test',
        options: _options(),
        content: '请帮我看看这段',
        activeProblemsEmpty: true,
      );
      expect(messages.length, 2, reason: '主 system + 首轮判据（独立消息）');
      expect(messages[0].role, 'system');
      expect(messages[1].role, 'system');
      expect(messages[1].content.startsWith(_kApprovedHeader), isTrue);
      expect(messages[1].content.contains('### P001'), isTrue);
    });

    test('③ 非 diagnosis 模式（training）不注入', () {
      final svc = _buildService();
      final messages = svc.buildSystemPrompt(
        TeachingPhase.p2PracticeLoop,
        AttitudeLevel.yuesheng,
        TeachingSubphase.practice,
        false,
        sessionId: 'w17-test',
        options: _options(),
        content: '继续练习',
        activeProblemsEmpty: true,
      );
      expect(messages.length, 1);
    });

    test('④ 有活跃症候（非首轮）不重复注入', () {
      final svc = _buildService();
      final messages = svc.buildSystemPrompt(
        TeachingPhase.p2PracticeLoop,
        AttitudeLevel.yuesheng,
        TeachingSubphase.diagnosis,
        false,
        sessionId: 'w17-test',
        options: _options(),
        content: '请帮我看看这段',
        activeProblemsEmpty: false,
      );
      expect(messages.length, 1);
    });

    test('⑧ 主 system prompt 字节不变（锚点零漂移依据）', () {
      final withBlock = _buildService().buildSystemPrompt(
        TeachingPhase.p2PracticeLoop,
        AttitudeLevel.yuesheng,
        TeachingSubphase.diagnosis,
        false,
        sessionId: 'w17-test',
        options: _options(),
        content: '请帮我看看这段',
        activeProblemsEmpty: true,
      );
      final without = _buildService().buildSystemPrompt(
        TeachingPhase.p2PracticeLoop,
        AttitudeLevel.yuesheng,
        TeachingSubphase.diagnosis,
        false,
        sessionId: 'w17-test',
        options: _options(),
        content: '请帮我看看这段',
        activeProblemsEmpty: false,
      );
      expect(withBlock[0].content, equals(without[0].content));
    });

    test('⑤ disabled P001 ⇒ 判据块内无 P001 段（其余仍在）', () {
      final svc = _buildService(disabled: {'P001'});
      final messages = svc.buildSystemPrompt(
        TeachingPhase.p2PracticeLoop,
        AttitudeLevel.yuesheng,
        TeachingSubphase.diagnosis,
        false,
        sessionId: 'w17-test',
        options: _options(),
        content: '请帮我看看这段',
        activeProblemsEmpty: true,
      );
      expect(messages.length, 2);
      expect(messages[1].content.contains('### P001 '), isFalse);
      expect(messages[1].content.contains('### P002'), isTrue);
    });

    test('⑨ P3 非 diagnosis 模式 + forceSceneFirst + 空 active ⇒ 在场', () {
      final svc = _buildService();
      final messages = svc.buildSystemPrompt(
        TeachingPhase.p3Training,
        AttitudeLevel.yuesheng,
        null,
        false,
        sessionId: 'w17-test',
        options: _options(),
        content: '请诊断我这段文字',
        activeProblemsEmpty: true,
      );
      // P3 措辞触发诊断协议（P1-4 force 路径）⇒ 裸奔诊断同样需要判据在场。
      expect(messages.length, 2);
      expect(messages[1].content.contains('### P001'), isTrue);
    });

    test('outline 语境 + 非诊断措辞不注入（规则 0 优先，非诊断轮）', () {
      final svc = _buildService();
      final messages = svc.buildSystemPrompt(
        TeachingPhase.p2PracticeLoop,
        AttitudeLevel.yuesheng,
        TeachingSubphase.diagnosis,
        false,
        sessionId: 'w17-test',
        isOutlineContext: true,
        options: _options(),
        content: '继续',
        activeProblemsEmpty: true,
      );
      expect(messages.length, 1);
    });
  });
}
