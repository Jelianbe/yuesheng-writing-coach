// ─────────────────────────────────────────────────────────────
// DiagnosisCommitter — 诊断提交编排器（独立类）
//
// ADR-C74 拆分重构的产物（批次 K）。从 ChatService 抽出诊断提交链路的所有
// 副作用（解析/落库/卡片/阶段迁移），自身无状态（除 B1 连续失败计数），
// 依赖通过构造函数注入——沿用 ADR-capability-contracts §3.2 「独立类 +
// 显式接口 + DI」三步法样板。
//
// 实施节奏（K-1 ~ K-5）：
//   K-1：本文件——仅类骨架（字段+构造），方法体待 K-2 ~ K-5 逐步迁入
//   K-2：迁 _applyPhaseMigration
//   K-3：迁 _parseAndPersist + _commitDiagnosisAndSuggestions
//   K-4：迁 _injectDiagnosisLock + _buildFactProtocolContext + _buildDriftHintContext
//   K-5：迁 commitDiagnosisFromContent 公开委派 + 落库辅助方法
//
// 关键不变量（K-1 阶段）：
//   - chatServiceProvider 注入本类实例，但 ChatService 不消费——
//     行为零变化，仅证明「独立类 + DI」路径可行（X-025-ARCH 教训复盘）
//   - sendMessage / _sendMessageCore 必须留 ChatService 薄壳，
//     避免 _FakeChatService @override 契约断裂
// ─────────────────────────────────────────────────────────────

// 私有字段（_xxx）+ 公开命名参数（xxx）模式无法用 initializing formal
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:writingcoach/contracts/diagnosis_capability.dart';
import 'package:writingcoach/contracts/genui_capability.dart';
import 'package:writingcoach/contracts/material_capability.dart';
import 'package:writingcoach/contracts/teaching_capability.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/subplot_fact_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/diagnosis_service.dart';
import 'package:writingcoach/services/evaluation_service.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/services/phase_mapper_resolver.dart';
import 'package:writingcoach/services/phase_transition.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 诊断提交编排器
///
/// 负责 AI 回复中 [YS_DIAGNOSIS] 块的解析、校验、落库、卡片生成、阶段迁移
/// 等所有副作用。sendMessage 与 commitDiagnosisFromContent 两条诊断路径的
/// 共用行为——通过本类保证一致（ADR-C74 §3.1，X-025-ARCH 复盘实证）。
///
/// 字段/依赖建模原则：
///   - 必备依赖（required）：6 个仓储 + 1 个 service + 4 个 capability
///   - 可选依赖（X-041c 模式）：4 个 nullable 仓储，不装配则跳过对应落库
///   - 内部状态：B1 连续失败计数（按 session 隔离，Map<String, int>）
///
/// K-1 阶段无任何方法体——仅类骨架，用于验证构造签名可编译、Provider 装配
/// 可实例化，且 ChatService 加 `final DiagnosisCommitter? _diagnosisCommitter`
/// 字段后六道门禁全绿（行为零变化护栏）。
class DiagnosisCommitter {
  // ─── 必备依赖（K-2 阶段升级为 nullable，K-3 ~ K-5 阶段随方法迁入
  //    按需收紧为 required）───
  //
  // 升级策略：
  //   K-2：仅 _applyPhaseMigration 迁入，用 4 仓储即可
  //   K-3：迁 _parseAndPersist / _commitDiagnosisAndSuggestions → 升 diagnosis 为 required
  //   K-4：迁 _injectDiagnosisLock + 协议块字符串构造 → 升 diagnosis 为 required
  //   K-5：迁 commitDiagnosisFromContent 委派 + 落库辅助 → 升 genUi/material/teaching 为 required
  //
  // 设计原则：nullable 是「演进中间态」，每一次收紧都靠 commit 落地——避免 K-1
  // 那种「字段预留但长期不用」的 unused_field 摊大饼。DiagnosisService 同理。
  final SessionRepository _sessionRepo;
  final TeachingStateRepository _stateRepo;
  final DiagnosisRepository _diagnosisRepo;
  final StudentModelRepository _studentModelRepo;

  // ─── K-3 ~ K-5 阶段按需升级为 required ───
  final DiagnosisService? _diagnosisService;
  final GenUiCapability? _genUi;
  final MaterialCapability? _material;
  final TeachingCapability? _teaching;
  final DiagnosisCapability? _diagnosis;

  // ─── 可选依赖（X-041c 模式：nullable，不装配则跳过对应落库）───
  final OutlineRepository? _outlineRepo;
  final CharacterFactRepository? _characterFactRepo;
  final EventFactRepository? _eventFactRepo;
  final SubplotFactRepository? _subplotFactRepo;

  // ─── 内部状态：B1 连续失败计数（按 session 隔离）───
  ///
  /// 来自 ChatService L187 `_consecutiveDiagnosisFails`——K-2 ~ K-5 阶段
  /// 随方法迁入时同步迁出。K-1 阶段不消费，仅占位声明。
  final Map<String, int> _consecutiveDiagnosisFails = {};

  DiagnosisCommitter({
    required SessionRepository sessionRepo,
    required TeachingStateRepository stateRepo,
    required DiagnosisRepository diagnosisRepo,
    required StudentModelRepository studentModelRepo,
    // K-3 ~ K-5 阶段按需收紧为 required——K-2 阶段 nullable 以降低测试装配成本
    DiagnosisService? diagnosisService,
    GenUiCapability? genUi,
    MaterialCapability? material,
    TeachingCapability? teaching,
    DiagnosisCapability? diagnosis,
    OutlineRepository? outlineRepo,
    CharacterFactRepository? characterFactRepo,
    EventFactRepository? eventFactRepo,
    SubplotFactRepository? subplotFactRepo,
  }) : _sessionRepo = sessionRepo,
       _stateRepo = stateRepo,
       _diagnosisRepo = diagnosisRepo,
       _studentModelRepo = studentModelRepo,
       _diagnosisService = diagnosisService,
       _genUi = genUi,
       _material = material,
       _teaching = teaching,
       _diagnosis = diagnosis,
       _outlineRepo = outlineRepo,
       _characterFactRepo = characterFactRepo,
       _eventFactRepo = eventFactRepo,
       _subplotFactRepo = subplotFactRepo;

  // ─────────────────────────────────────────────────────────────
  // K-2：applyPhaseMigration 阶段迁移统一处理
  //
  // 由 ChatService._sendMessageCore (L2480) 与 commitDiagnosisFromContent
  // (L731) 两条路径调用——保证两条诊断路径的阶段迁移行为一致。
  //
  // 内部三步：
  //   1. AI 驱动路径（路径 1）：diagnosis 输出 suggestedPhase/Level → resolver
  //   2. M4-B validatePhaseTransition 校验 + 相邻降级（clampEarlyPhaseSkip）
  //   3. M4-A 自动迁移（路径 2）：所有活跃症候 resolved + 达标率 ≥ phasePassRate
  //
  // 公开 + @visibleForTesting：迁出后允许专项测试直接覆盖本方法，弥补
  // sendMessage 私有路径无法单元测试的局限（X-025-ARCH 教训复盘）。
  // ─────────────────────────────────────────────────────────────

  /// 阶段迁移统一处理（批次6 D1）——AI 驱动 resolver + M4-A 自动迁移 + M4-C 达标率校验
  ///
  /// 供 [commitDiagnosisFromContent] 与 sendMessage 复用，保证两条诊断路径行为一致：
  ///   - sendMessage：单次诊断（≤4000 字）
  ///   - commitDiagnosisFromContent：超长分块诊断（>4000 字，progressive 路径）
  ///
  /// 内部职责（均 try/catch 包裹，失败不阻断主流程）：
  ///   1. diagnosis 输出 suggestedPhase/suggestedBeginnerLevel 时 → phase-mapper resolver
  ///   2. effectivePhase → M4-B validatePhaseTransition 校验 → updatePhase + 子阶段重置 + 升级卡片
  ///   3. effectiveBeginnerLevel → updateBeginnerLevel
  ///   4. 所有活跃症候已 resolved → M4-A 自动迁移（M4-C 达标率 ≥ phasePassRate 才放行）
  @visibleForTesting
  Future<void> applyPhaseMigration({
    required String sessionId,
    required ParsedDiagnosis? diagnosis,
  }) async {
    // 批次1（C5/H3）：路径1（AI 驱动）成功迁移后，路径2（M4-A 自动）不得
    // 再无条件继续，防止同轮链式双跳（如 P1→P2→P3）
    var path1Migrated = false;
    // ── 1. AI 驱动路径：phase-mapper resolver ──
    if (diagnosis != null &&
        (diagnosis.suggestedPhase != null ||
            diagnosis.suggestedBeginnerLevel != null)) {
      try {
        final currentState = await _stateRepo.getTeachingState(sessionId);
        final currentBeginnerLevelStr = currentState?.beginnerLevel;
        final currentBeginnerLevel = BeginnerLevel.fromString(
          currentBeginnerLevelStr,
        );

        // 计算连续失败训练次数（仅 N3 触发降级检查时需要）
        int consecutiveFailedTrainings = 0;
        if (currentBeginnerLevel == BeginnerLevel.n3Diagnose) {
          try {
            final allHistory = await _studentModelRepo.getTeachingHistory(
              sessionId,
            );
            final activeProblems = await _diagnosisRepo.listActiveProblems(
              sessionId,
            );
            final focusSyndromeId =
                diagnosis.currentTeachingFocusId ??
                activeProblems.firstOrNull?.syndromeId;
            if (focusSyndromeId != null) {
              final trainingRecords =
                  allHistory
                      .where(
                        (r) =>
                            r['type'] == 'training' &&
                            r['syndromeId'] == focusSyndromeId,
                      )
                      .toList()
                    ..sort((a, b) {
                      final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
                      final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
                      return ta.compareTo(tb);
                    });
              for (int i = trainingRecords.length - 1; i >= 0; i--) {
                if (trainingRecords[i]['result'] == 'failed') {
                  consecutiveFailedTrainings++;
                } else {
                  break;
                }
              }
            }
          } catch (e) {
            debugPrint('[SafeRun] resolver 训练记录读取失败: $e');
          }
        }

        final resolverResult = resolvePhaseMapper(
          PhaseMapperInput(
            currentPhase: TeachingPhase.fromString(currentState?.currentPhase),
            currentBeginnerLevel: currentBeginnerLevel,
            suggestedPhase: diagnosis.suggestedPhase,
            suggestedBeginnerLevel: diagnosis.suggestedBeginnerLevel,
            consecutiveFailedTrainings: consecutiveFailedTrainings,
          ),
        );

        final effectivePhase = resolverResult.effectivePhase;
        if (effectivePhase != null) {
          // M4-B: 阶段迁移合法性校验——拦截非法跳级/回退
          // （如 P2→P0、P3→P1 等），仅放行相邻递进或 P4→P2 回退
          final prevPhaseValue = currentState?.currentPhase;
          final currentPhaseForValidation =
              TeachingPhase.fromString(prevPhaseValue) ??
              TeachingPhase.p0Engage;
          if (validatePhaseTransition(
            currentPhaseForValidation,
            effectivePhase,
          )) {
            await _stateRepo.updatePhase(sessionId, effectivePhase.value);
            // 批次9：阶段真实变化时插入 phase_upgrade 卡片（对齐 RN insertPhaseUpgradeCard）
            if (prevPhaseValue != effectivePhase.value) {
              path1Migrated = true;
              // M4-D: 阶段迁移时重置子阶段，避免上一阶段子阶段残留
              await _stateRepo.updateSubphase(sessionId, null);
              try {
                await insertPhaseUpgradeCard(
                  _sessionRepo,
                  sessionId,
                  PhaseUpgradeCardPayload(
                    from: prevPhaseValue ?? TeachingPhase.p0Engage.value,
                    to: effectivePhase.value,
                  ),
                );
              } catch (e) {
                debugPrint('[SafeRun] 卡片插入失败不影响阶段迁移: $e');
              }
            }
          } else {
            // C54 方案 C（C-2，ADR-C54 §4-C-2）：早期跨一格的非法建议
            // 确定性降级为相邻递进，而非整轮丢弃——首诊双信号场景
            // （P0→P1 与 P1→P2 同时成立）不再依赖 AI 采样选择
            final fallback = clampEarlyPhaseSkip(
              currentPhaseForValidation,
              effectivePhase,
            );
            if (fallback != null) {
              await _stateRepo.updatePhase(sessionId, fallback.value);
              path1Migrated = true;
              // M4-D: 阶段迁移时重置子阶段，避免上一阶段子阶段残留
              await _stateRepo.updateSubphase(sessionId, null);
              try {
                await insertPhaseUpgradeCard(
                  _sessionRepo,
                  sessionId,
                  PhaseUpgradeCardPayload(
                    from: prevPhaseValue ?? TeachingPhase.p0Engage.value,
                    to: fallback.value,
                  ),
                );
              } catch (e) {
                debugPrint('[SafeRun] 卡片插入失败不影响阶段迁移: $e');
              }
            } else {
              debugPrint(
                '[SafeRun] M4-B: 阶段迁移非法已拦截 '
                '$currentPhaseForValidation → $effectivePhase',
              );
            }
          }
        }
        if (resolverResult.effectiveBeginnerLevel != null) {
          await _stateRepo.updateBeginnerLevel(
            sessionId,
            resolverResult.effectiveBeginnerLevel!.value,
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] resolver 失败不阻断主流程: $e');
      }
    } else if (diagnosis != null && diagnosis.syndromes.isNotEmpty) {
      // N38 可观测性：诊断块识别到症候、却没有 suggested_phase → 上面的入口
      // 守卫不成立，路径 1 整条被跳过，本轮不发生迁移且全程无痕。这是实测过的
      // 失败模式（gp-13 三次全漏填，把「可选字段」当成了可填可不填）。
      // 此处只记录、不改行为——代码侧不代填迁移，避免越权改动教学状态机。
      // 仅在 P0/P1 告警：这两个阶段「诊断出症候」本身就是迁移信号，属于确凿
      // 漏填；P2 及以后每轮有症候是常态，不告警以免日志噪声。
      try {
        final n38State = await _stateRepo.getTeachingState(sessionId);
        final n38Phase = TeachingPhase.fromString(n38State?.currentPhase);
        if (n38Phase == TeachingPhase.p0Engage ||
            n38Phase == TeachingPhase.p1World) {
          debugPrint(
            '[N38] ${n38Phase!.value} 阶段诊断块含 ${diagnosis.syndromes.length} 个症候'
            '（迁移信号已成立）但无 suggested_phase → 本轮不发生阶段迁移',
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] N38 可观测读取教学状态失败: $e');
      }
    }

    // 批次1（C5/H3）：路径1 已成功迁移 → 直接返回，路径2 仅当路径1 无有效迁移时评估
    if (path1Migrated) return;

    // ── 2. 自动迁移路径：M4-A + M4-C 达标率校验 ──
    // 所有活跃症候已 resolved 时，代码侧主动推进阶段（不依赖 AI suggestedPhase）
    // 守卫：仅在 P2 及以后触发（P0/P1 阶段迁移由 AI suggested_phase 驱动）
    // M4-C: passRate >= phasePassRate(0.7) 才允许迁移，避免手动标记完成跳过训练升阶
    try {
      final remaining = await _diagnosisRepo.listActiveProblems(sessionId);
      if (remaining.isEmpty) {
        final ts = await _stateRepo.getTeachingState(sessionId);
        final currentPhase =
            TeachingPhase.fromString(ts?.currentPhase) ??
            TeachingPhase.p0Engage;
        if (currentPhase != TeachingPhase.p0Engage &&
            currentPhase != TeachingPhase.p1World) {
          final evalService = EvaluationService(
            _diagnosisRepo,
            _studentModelRepo,
          );
          final passRate = await evalService.computePassRateForPhaseMigration(
            sessionId,
          );
          if (passRate >= EvaluationThresholds.phasePassRate) {
            final next = nextPhase(currentPhase);
            // M4-B: nextPhase 已保证相邻递进，validatePhaseTransition 双重校验
            if (next != null && validatePhaseTransition(currentPhase, next)) {
              await _stateRepo.updatePhase(sessionId, next.value);
              await _stateRepo.updateSubphase(sessionId, null);
              try {
                await insertPhaseUpgradeCard(
                  _sessionRepo,
                  sessionId,
                  PhaseUpgradeCardPayload(
                    from: currentPhase.value,
                    to: next.value,
                  ),
                );
              } catch (e) {
                debugPrint('[SafeRun] 自动迁移卡片插入失败: $e');
              }
            }
          } else {
            debugPrint(
              '[SafeRun] M4-C: 达标率 $passRate < '
              '${EvaluationThresholds.phasePassRate}，阶段暂不迁移',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[SafeRun] 自动迁移失败不阻断主流程: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // K-3：协议块字符串构造器（纯字符串，无 IO 依赖）
  //
  // 原 ChatService.extension.ChatServiceDiagnosis._buildFactProtocolContext
  // + _buildDriftHintContext 迁出。零私有依赖，可独立测试。
  //
  // sendMessage 主链两处调用（L1574 / L1650）改为
  //   `_diagnosisCommitter?.buildXxx(...) ?? ''`
  // —— production 必装，nullable 仅为测试兼容 K-1 设计。
  // ─────────────────────────────────────────────────────────────

  /// 批次64（B62f）：声线漂移提示上下文——引导 AI 以提问方式温和指出其中一条
  @visibleForTesting
  String buildDriftHintContext(List<String> hints) {
    return '## 声线漂移检测（L3→L1 实时反馈）\n\n'
        '检测到写作特征与既有风格基线出现明显偏差。\n'
        '若合适，请用**提问的方式**温和地向学员指出**其中一条**'
        '（结合具体数字，如"你的句子长度通常 15-20 字，但这部分平均只有 8 字——'
        '是刻意加速，还是无意识的变化？"），一次只问一个点，不展开成诊断。\n'
        '偏差项：\n- ${hints.join('\n- ')}';
  }

  /// A6：时序知识图谱事实提取协议（诊断章节正文时注入）
  ///
  /// 指导 AI 在诊断回复中附加 [YS_FACT] 块，提取人物/事件/支线三类结构化事实，
  /// 供系统 upsert 到 TKG 三表，驱动时序矛盾/因果链/情节闭环检测。
  /// 与 [YS_DIAGNOSIS]、[YS_ENTITY] 并列独立，输出顺序排在最后。
  @visibleForTesting
  String buildFactProtocolContext() {
    return '## 时序知识图谱事实沉淀（输出顺序约束）\n\n'
        '【输出顺序】若同时输出诊断块、实体块与事实块，**必须严格按此顺序**：\n'
        '  1. [YS_DIAGNOSIS] 症候块（若诊断要求）；\n'
        '  2. [YS_ENTITY] 实体记忆块；\n'
        '  3. [YS_FACT] 事实块（本条）；\n'
        '  4. 之后再写面向学员的自然语言诊断与教学建议。\n\n'
        '若章节正文出现值得长期记住的**结构化事实**（人物属性断言、关键事件、'
        '支线收束），请在回复中附加 [YS_FACT] JSON 块，供系统沉淀为时序知识图谱。'
        '增量更新：仅记录当前章节新增或变化的事实，不重复已沉淀内容。'
        '完全无新事实（无人物属性变化、无关键事件、无支线进展）可不输出该块。\n\n'
        '格式：\n'
        '[YS_FACT]\n'
        '{\n'
        '  "characters": [\n'
        '    {"name":"人物名","assertions":[\n'
        '      {"attribute":"属性名(如独生子女状态/性格/职业/身份)","value":"属性值",'
        '"chapter":3}\n'
        '    ]}\n'
        '  ],\n'
        '  "events": [\n'
        '    {"name":"事件名","event_type":"决定|转折|突发|冲突|日常",'
        '"chapter":5,"participants":["人物名"],"description":"一句话概述",'
        '"cause_event_name":"触发本事件的前因事件名（无前因则省略）"}\n'
        '  ],\n'
        '  "subplots": [\n'
        '    {"name":"支线名","introduced_chapter":3,"resolved_chapter":null,'
        '"description":"支线梗概"}\n'
        '  ]\n'
        '}\n'
        '[/YS_FACT]\n\n'
        '规则：\n'
        '- characters：记录本章新增或变化的人物属性断言。attribute 用规范属性名'
        '（如「独生子女状态」「性格」「职业」「身份」「关系」），value 为原文可验证的具体值，'
        'chapter 为该断言出现的章节序号。同一人物可多条断言。\n'
        '- events：记录关键事件（决定/转折/突发类必记，冲突/日常视重要性）。'
        'event_type 从「决定|转折|突发|冲突|日常」中选一。participants 为参与人物名列表。'
        'description 一句话概述事件（≤30字）。'
        'cause_event_name 填触发本事件的前因事件名（须与既有事件 name 一致），'
        '用于构建因果链；无前因触发（如开篇事件）则省略此字段。\n'
        '- subplots：记录支线引入或回收。introduced_chapter 填首次引入章节，'
        'resolved_chapter 填本章回收章节（未回收填 null）。'
        '若本章回收了既有支线，必须输出该条并填入 resolved_chapter。\n'
        '- **完整性硬约束**：[YS_FACT] 包裹的 JSON 必须语法合法、完整闭合。'
        '如担心篇幅，请压缩自然语言诊断说明以保证事实块完整。';
  }
}
