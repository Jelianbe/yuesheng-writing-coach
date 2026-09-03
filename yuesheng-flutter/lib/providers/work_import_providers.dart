// ─────────────────────────────────────────────────────────────
// work_import_providers — 作品导入链路 providers
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/chapter_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../services/work_import_service.dart';
import 'app_providers.dart';
import 'capability_providers.dart';

// ADR-C70：mentionParserProvider 已迁至 capability_providers.dart（它依赖
// 那边的 referenceCapabilityProvider，那边又依赖它，原为循环）。本文件现只
// 单向依赖 capability_providers。`mention_parser.dart` 随之不再需要。

/// 作品导入服务（依赖全局 DB 单例，测试可 override appDatabaseProvider）
final workImportServiceProvider = Provider<WorkImportService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return WorkImportService(
    db,
    ManuscriptRepository(db),
    ChapterRepository(db),
    ref.read(referenceCapabilityProvider),
  );
});
