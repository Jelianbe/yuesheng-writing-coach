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

import 'package:writingcoach/contracts/diagnosis_capability.dart';
import 'package:writingcoach/contracts/genui_capability.dart';
import 'package:writingcoach/contracts/material_capability.dart';
import 'package:writingcoach/contracts/teaching_capability.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/subplot_fact_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/diagnosis_service.dart';

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
  // ─── 必备依赖 ───
  final SessionRepository _sessionRepo;
  final TeachingStateRepository _stateRepo;
  final DiagnosisRepository _diagnosisRepo;
  final DiagnosisService _diagnosisService;

  // ─── 可选依赖（X-041c 模式：nullable，不装配则跳过对应落库）───
  final OutlineRepository? _outlineRepo;
  final CharacterFactRepository? _characterFactRepo;
  final EventFactRepository? _eventFactRepo;
  final SubplotFactRepository? _subplotFactRepo;

  // ─── 四大能力（capability 注入，沿用 ChatService 现有依赖约定）───
  final GenUiCapability _genUi;
  final MaterialCapability _material;
  final TeachingCapability _teaching;
  final DiagnosisCapability _diagnosis;

  // ─── 内部状态：B1 连续失败计数（按 session 隔离）───
  ///
  /// 来自 ChatService L187 `_consecutiveDiagnosisFails`——K-2 ~ K-5 阶段
  /// 随方法迁入时同步迁出。K-1 阶段不消费，仅占位声明。
  final Map<String, int> _consecutiveDiagnosisFails = {};

  DiagnosisCommitter({
    required SessionRepository sessionRepo,
    required TeachingStateRepository stateRepo,
    required DiagnosisRepository diagnosisRepo,
    required DiagnosisService diagnosisService,
    required GenUiCapability genUi,
    required MaterialCapability material,
    required TeachingCapability teaching,
    required DiagnosisCapability diagnosis,
    OutlineRepository? outlineRepo,
    CharacterFactRepository? characterFactRepo,
    EventFactRepository? eventFactRepo,
    SubplotFactRepository? subplotFactRepo,
  }) : _sessionRepo = sessionRepo,
       _stateRepo = stateRepo,
       _diagnosisRepo = diagnosisRepo,
       _diagnosisService = diagnosisService,
       _genUi = genUi,
       _material = material,
       _teaching = teaching,
       _diagnosis = diagnosis,
       _outlineRepo = outlineRepo,
       _characterFactRepo = characterFactRepo,
       _eventFactRepo = eventFactRepo,
       _subplotFactRepo = subplotFactRepo;
}
