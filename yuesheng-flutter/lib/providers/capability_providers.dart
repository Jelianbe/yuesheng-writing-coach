// ─────────────────────────────────────────────────────────────
// capability_providers — 六大能力契约的 Riverpod 接入点
//
// 选项 B 依赖倒置的收口：能力实现（impl）在此集中实例化，以「契约接口」
// 类型对外暴露。UI / 编排层经契约消费，不直接依赖 impl；实现可在此一处
// 替换而不波及消费者（依赖倒置收益点）。
//
// 现状（2026-08-20）：GenUi / Material / Teaching / Diagnosis 四个纯能力
// 实现类已落地但尚无调用方——当前行为仍走底层纯函数（buildSystemPromptV2 /
// parseDiagnosis / formatAttachedFilesContext …）。本文件先建立 DI 接缝，
// 调用方（UI 消费层）迁移列为下一阶段，详见 ADR。
//
// 说明：capability_registry.dart 此前按 R-010 最小范围刻意递延了「抽
// provider / 改 widget 调用链」，此处为首落 provider 接入；MentionParser
// 已有 work_import_providers.dart 的 mentionParserProvider，本文件以契约
// 类型别名复用，避免重复实例化。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

// 注：diagnosis / genui / material / teaching 四个契约已由各自 impl 文件
// re-export（见 diagnosis_parser / genui_parser / chat_context_builder /
// skill_dispatcher），此处不再单独 import，避免 unnecessary_import。
// reference / mention 两个契约未被 impl 文件 re-export，需显式 import。
import '../contracts/mention_capability.dart';
import '../contracts/reference_capability.dart';
import '../data/repositories/reference_repository.dart';
import '../providers/app_providers.dart';
import '../services/chat_context_builder.dart';
import '../services/diagnosis_parser.dart';
import '../services/genui_parser.dart';
import '../services/skill_dispatcher.dart';
import 'work_import_providers.dart';

/// GenUI 组件能力（纯函数委托，无状态）
final genUiCapabilityProvider = Provider<GenUiCapability>(
  (_) => const GenUiParser(),
);

/// 素材能力（纯函数委托，无状态）
///
/// MaterialCapabilityImpl 定义于 chat_context_builder.dart（与其委托的
/// 纯函数同文件），从此处导入以保持单一实现源。
final materialCapabilityProvider = Provider<MaterialCapability>(
  (_) => const MaterialCapabilityImpl(),
);

/// 教学能力（纯函数委托，无状态）
final teachingCapabilityProvider = Provider<TeachingCapability>(
  (_) => const TeachingCapabilityImpl(),
);

/// 诊断能力（纯函数委托，无状态）
final diagnosisCapabilityProvider = Provider<DiagnosisCapability>(
  (_) => const DiagnosisCapabilityImpl(),
);

/// 引用能力（依赖全局 DB 单例）
final referenceCapabilityProvider = Provider<ReferenceCapability>(
  (ref) => ReferenceRepository(ref.watch(appDatabaseProvider)),
);

/// @提及解析能力（契约类型别名，复用既有 mentionParserProvider）
final mentionCapabilityProvider = Provider<MentionCapability>(
  (ref) => ref.watch(mentionParserProvider),
);
