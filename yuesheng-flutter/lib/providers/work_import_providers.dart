// ─────────────────────────────────────────────────────────────
// work_import_providers — 作品导入链路 providers
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/chapter_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../services/mention_parser.dart';
import '../services/work_import_service.dart';
import 'app_providers.dart';
import 'capability_providers.dart';

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

/// @ 引用解析服务
final mentionParserProvider = Provider<MentionParser>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return MentionParser(
    ManuscriptRepository(db),
    ChapterRepository(db),
    ref.read(referenceCapabilityProvider),
  );
});
