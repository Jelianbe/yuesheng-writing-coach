// ─────────────────────────────────────────────────────────────
// capability_providers — 六大能力契约的 Riverpod 接入点
//
// 选项 B 依赖倒置的收口：能力实现（impl）在此集中实例化，以「契约接口」
// 类型对外暴露。UI / 编排层经契约消费，不直接依赖 impl；实现可在此一处
// 替换而不波及消费者（依赖倒置收益点）。
//
// 现状（2026-08-29 更正）：四个纯能力 provider 均已接入生产链路——
// session_providers.dart:121-124 在 chatServiceProvider 内 watch 全部四个，
// 由 ChatService 经契约注入使用；widget 层则经 chatServiceProvider 消费。
//
// 更正说明：此处原本写的是「已落地但尚无调用方」（2026-08-20），与现状不
// 符——该描述曾导致对「dispatcher 是否在生产链路」的误判，故同步更正。
//
// 说明：capability_registry.dart 此前按 R-010 最小范围刻意递延了「抽
// provider / 改 widget 调用链」，此处为首落 provider 接入；MentionParser
// 以契约类型别名复用 mentionParserProvider，避免重复实例化。
//
// ADR-C70：mentionParserProvider 原先定义在 work_import_providers.dart，
// 而它又需要本文件的 referenceCapabilityProvider，两边互引成环。现已将其
// 迁入本文件（见下方定义），依赖方向变为 work_import → capability（单向）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

// 注：diagnosis / genui / material / teaching 四个契约已由各自 impl 文件
// re-export（见 diagnosis_parser / genui_parser / chat_context_builder /
// skill_dispatcher），此处不再单独 import，避免 unnecessary_import。
// reference / mention 两个契约未被 impl 文件 re-export，需显式 import。
import '../contracts/mention_capability.dart';
import '../contracts/reference_capability.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../data/repositories/reference_repository.dart';
import '../providers/app_providers.dart';
import '../services/chat_context_builder.dart';
import '../services/diagnosis_parser.dart';
import '../services/genui_parser.dart';
import '../services/mention_parser.dart';
import '../services/skill_dispatcher.dart';

// 注：原第 35 行的 `import 'work_import_providers.dart';` 已删除——
// mentionParserProvider 现定义于本文件（ADR-C70），不再需要反向引用。

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

/// 引用仓库（具体类型，单例来源）——供仍需完整仓库 API（附属文件 CRUD 等）
/// 的调用方使用。referenceCapabilityProvider 委托到此，确保同一实例。
final referenceRepositoryProvider = Provider<ReferenceRepository>(
  (ref) => ReferenceRepository(ref.watch(appDatabaseProvider)),
);

/// 引用能力（契约类型）——委托到 referenceRepositoryProvider 的同一实例，
/// 隐式向上转型，无需强制转换。UI 经契约消费；需要仓库专属方法时退回
/// referenceRepositoryProvider。
final referenceCapabilityProvider = Provider<ReferenceCapability>(
  (ref) => ref.watch(referenceRepositoryProvider),
);

/// @ 引用解析服务（具体类型）——ADR-C70 由 work_import_providers.dart 迁入。
///
/// 迁入理由：它依赖本文件的 referenceCapabilityProvider，说明在依赖层次上
/// 位于 capability 装配之下；原放在 work_import_providers 导致该文件反向
/// import 本文件，形成循环。顺依赖箭头搬过来即可解开，且调用方
/// （chat_page.dart 及其 part）本就同时 import 了两个文件，零调用点改动。
///
/// 构造参数与迁入前**完全一致**，行为不变。
final mentionParserProvider = Provider<MentionParser>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return MentionParser(
    ManuscriptRepository(db),
    ChapterRepository(db),
    ref.read(referenceCapabilityProvider),
  );
});

/// @提及解析能力（契约类型别名，复用 mentionParserProvider）
final mentionCapabilityProvider = Provider<MentionCapability>(
  (ref) => ref.watch(mentionParserProvider),
);
