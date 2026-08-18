// ─────────────────────────────────────────────────────────────
// AppDatabase — drift 主数据库类
// 严格复刻 yuesheng-android 的 DB 初始化逻辑：
//   - WAL 模式（并发读写性能）
//   - foreign_keys = ON（PRD 级联删除依赖）
//   - 13 版本迁移历史（onUpgrade 逐版本执行原始 SQL）
//   - 新库走 onCreate 直接建最终形态（v13）
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Manuscripts,
    Chapters,
    Sessions,
    Messages,
    DiagnosisResults,
    TeachingState,
    ActiveProblems,
    StudentModels,
    SessionReferences,
    AppStates,
    ErrorLogs,
    AttachedFiles,
    TeacherSuggestions,
    EditorObservations,
    CharacterFacts,
    EventFacts,
    SubplotFacts,
    OutlineEntities,
    OutlineImpressions,
    Volumes,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 用于测试的构造函数（内存数据库）
  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 25;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      // drift 自动建所有表的最终形态（v13）
      await m.createAll();

      // 创建普通索引（drift 不会自动生成，需手动）
      // 严格复刻 schema.ts 中的所有 CREATE INDEX
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_chapters_manuscript_id ON chapters(manuscript_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_chapters_sort_order ON chapters(manuscript_id, sort_order)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sessions_manuscript ON sessions(manuscript_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sessions_updated_at ON sessions(updated_at DESC)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, timestamp)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_messages_type ON messages(message_type)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_diagnosis_session ON diagnosis_results(session_id, timestamp)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_diagnosis_message ON diagnosis_results(message_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_diagnosis_target ON diagnosis_results(target_ref_type, target_ref_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_teaching_state_session ON teaching_state(session_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_active_problem_session ON active_problem(session_id, status)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_student_model_session ON student_model(session_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_session_reference_session ON session_reference(session_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_session_reference_target ON session_reference(ref_type, ref_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_error_logs_level ON error_logs(level, created_at DESC)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_error_logs_category ON error_logs(category, created_at DESC)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_error_logs_created ON error_logs(created_at DESC)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_attached_files_book ON attached_files(book_id, sort_order)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_attached_files_role ON attached_files(book_id, file_role)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_teacher_suggestion_session ON teacher_suggestion(session_id, status)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_editor_observation_session ON editor_observation(session_id, timestamp)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_editor_observation_target ON editor_observation(target_ref_type, target_ref_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_character_fact_manuscript ON character_fact(manuscript_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_event_fact_manuscript ON event_fact(manuscript_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_subplot_fact_manuscript ON subplot_fact(manuscript_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_outline_entity_manuscript ON outline_entity(manuscript_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_outline_impression_entity ON outline_impression(entity_id)',
      );
      // 批次89：卷分组索引
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_volumes_manuscript ON volumes(manuscript_id, sort_order)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_chapters_volume ON chapters(volume_id)',
      );
    },

    onUpgrade: (m, from, to) async {
      // 逐版本迁移，严格复刻 yuesheng-android/src/db/migrations.ts
      // 新库走 onCreate 不会触发此回调
      // 使用 customStatement 执行原始 SQL，与原项目保持一致
      // 批次62：守卫随 schemaVersion 上移到 14，使 v13/v14 块对 from>=12 的存量库可达
      // （v13 块幂等，无数据风险；原 `from >= 12` 守卫会令 v13 块对 from=12 库失效）
      // 批次66：守卫上移到 16（v15 块对 from=14 存量库可达，全部幂等）
      // 批次67：守卫上移到 17（v16 块对 from=15 存量库可达，全部幂等）
      // 批次72：守卫上移到 18（v17 块对 from=16 存量库可达，全部幂等）
      // 批次5（5.3）：守卫上移到 20（v19/v20 块对 from=18 存量库可达，全部幂等）
      // 批次7（D2）：守卫上移到 21（v21 块对 from=20 存量库可达）
      // 批次71：守卫上移到 22（v22 块对 from=21 存量库可达，幂等）
      // 批次89：守卫上移到 23（v23 块对 from=22 存量库可达，幂等）
      // 批次94-2：守卫上移到 24（v24 块对 from=23 存量库可达，幂等）
      // 批次94-5：守卫上移到 25（v25 块对 from=24 存量库可达，幂等）
      if (from >= 25) return;

      // v2: add_last_diagnosed_at_to_chapters
      if (from < 2) {
        await customStatement(
          'ALTER TABLE chapters ADD COLUMN last_diagnosed_at INTEGER DEFAULT NULL',
        );
      }

      // v3: add_message_type_to_messages
      if (from < 3) {
        await customStatement(
          "ALTER TABLE messages ADD COLUMN message_type TEXT DEFAULT 'chat'",
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_messages_type ON messages(message_type)',
        );
      }

      // v4: add_onboarding_data_to_student_model
      if (from < 4) {
        await customStatement(
          'ALTER TABLE student_model ADD COLUMN onboarding_data TEXT DEFAULT NULL',
        );
      }

      // v5: add_attached_files_table
      if (from < 5) {
        await customStatement('''
              CREATE TABLE IF NOT EXISTS attached_files (
                id            TEXT PRIMARY KEY,
                book_id       TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
                file_name     TEXT NOT NULL DEFAULT '',
                file_role     TEXT NOT NULL DEFAULT 'general'
                              CHECK(file_role IN ('outline','material','general')),
                mime_type     TEXT NOT NULL DEFAULT 'text/plain',
                content       TEXT NOT NULL DEFAULT '',
                byte_size     INTEGER NOT NULL DEFAULT 0,
                sort_order    INTEGER NOT NULL DEFAULT 0,
                created_at    INTEGER NOT NULL DEFAULT (unixepoch()),
                updated_at    INTEGER NOT NULL DEFAULT (unixepoch())
              )
            ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_attached_files_book ON attached_files(book_id, sort_order)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_attached_files_role ON attached_files(book_id, file_role)',
        );
      }

      // v6: add_language_to_manuscripts（幂等）
      if (from < 6) {
        final cols = await customSelect('PRAGMA table_info(manuscripts)').get();
        final hasLanguage = cols.any(
          (r) => r.read<String>('name') == 'language',
        );
        if (!hasLanguage) {
          await customStatement(
            "ALTER TABLE manuscripts ADD COLUMN language TEXT DEFAULT '中文'",
          );
        }
      }

      // v7: add_previous_content_to_chapters（幂等）
      if (from < 7) {
        final cols = await customSelect('PRAGMA table_info(chapters)').get();
        final hasPreviousContent = cols.any(
          (r) => r.read<String>('name') == 'previous_content',
        );
        if (!hasPreviousContent) {
          await customStatement(
            'ALTER TABLE chapters ADD COLUMN previous_content TEXT DEFAULT NULL',
          );
        }
      }

      // v8: add_teacher_suggestion_table
      if (from < 8) {
        await customStatement('''
              CREATE TABLE IF NOT EXISTS teacher_suggestion (
                id                   TEXT PRIMARY KEY,
                session_id           TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                message_id           TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                source               TEXT NOT NULL CHECK(source IN ('editor','diagnosis')),
                teaching_decision    TEXT NOT NULL CHECK(teaching_decision IN ('guide','train')),
                target_syndrome_id   TEXT DEFAULT NULL,
                target_dimension     TEXT DEFAULT NULL,
                task_type            TEXT NOT NULL CHECK(task_type IN ('rewrite','analyze','compare','generate')),
                task_description     TEXT NOT NULL,
                difficulty           TEXT NOT NULL CHECK(difficulty IN ('easy','medium','hard')),
                evaluation_criteria  TEXT NOT NULL DEFAULT '[]',
                status               TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','resolved')),
                created_at           INTEGER NOT NULL DEFAULT (unixepoch()),
                resolved_at          INTEGER DEFAULT NULL
              )
            ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_teacher_suggestion_session ON teacher_suggestion(session_id, status)',
        );
      }

      // v9: add_editor_observation_table
      if (from < 9) {
        await customStatement('''
              CREATE TABLE IF NOT EXISTS editor_observation (
                id                 TEXT PRIMARY KEY,
                session_id         TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                message_id         TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                possible_intent    TEXT NOT NULL,
                intent_confidence  TEXT NOT NULL CHECK(intent_confidence IN ('low','moderate','high')),
                observations       TEXT NOT NULL,
                overall_impression TEXT NOT NULL,
                strengths          TEXT NOT NULL DEFAULT '[]',
                teacher_triggered  INTEGER NOT NULL DEFAULT 0 CHECK(teacher_triggered IN (0,1)),
                pronounced_count   INTEGER NOT NULL DEFAULT 0,
                against_count      INTEGER NOT NULL DEFAULT 0,
                target_ref_type    TEXT DEFAULT NULL CHECK(target_ref_type IS NULL OR target_ref_type IN ('manuscript','chapter')),
                target_ref_id      TEXT DEFAULT NULL,
                timestamp          INTEGER NOT NULL DEFAULT (unixepoch()),
                created_at         INTEGER NOT NULL DEFAULT (unixepoch()),
                UNIQUE(session_id, message_id)
              )
            ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_editor_observation_session ON editor_observation(session_id, timestamp)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_editor_observation_target ON editor_observation(target_ref_type, target_ref_id)',
        );
      }

      // v10: add_confirmation_status_to_active_problem（幂等）
      if (from < 10) {
        final cols = await customSelect(
          'PRAGMA table_info(active_problem)',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('confirmation_status')) {
          await customStatement(
            "ALTER TABLE active_problem ADD COLUMN confirmation_status TEXT DEFAULT 'suspected' CHECK(confirmation_status IN ('suspected','confirmed','rejected','ignored'))",
          );
        }
        if (!colNames.contains('confirmed_at')) {
          await customStatement(
            'ALTER TABLE active_problem ADD COLUMN confirmed_at INTEGER DEFAULT NULL',
          );
        }
      }

      // v11: add_teaching_focus_and_fix_schema_v1
      if (from < 11) {
        // 1. 新增 diagnosis_results 列
        final diagCols = await customSelect(
          'PRAGMA table_info(diagnosis_results)',
        ).get();
        final diagColNames = diagCols
            .map((r) => r.read<String>('name'))
            .toSet();
        if (!diagColNames.contains('current_teaching_focus_id')) {
          await customStatement(
            'ALTER TABLE diagnosis_results ADD COLUMN current_teaching_focus_id TEXT',
          );
        }
        if (!diagColNames.contains('focus_reason')) {
          await customStatement(
            'ALTER TABLE diagnosis_results ADD COLUMN focus_reason TEXT',
          );
        }

        // 2. 修复 active_problem（幂等保底）
        final apCols = await customSelect(
          'PRAGMA table_info(active_problem)',
        ).get();
        final apColNames = apCols.map((r) => r.read<String>('name')).toSet();
        if (!apColNames.contains('confirmation_status')) {
          await customStatement(
            "ALTER TABLE active_problem ADD COLUMN confirmation_status TEXT DEFAULT 'suspected' CHECK(confirmation_status IN ('suspected','confirmed','rejected','ignored'))",
          );
        }
        if (!apColNames.contains('confirmed_at')) {
          await customStatement(
            'ALTER TABLE active_problem ADD COLUMN confirmed_at INTEGER DEFAULT NULL',
          );
        }

        // 3. 重建 teaching_state 表扩展 CHECK 约束
        final tsSql = await customSelect(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='teaching_state'",
        ).getSingle();
        final sqlText = tsSql.read<String>('sql');
        if (!sqlText.contains('P3_TRAINING')) {
          await customStatement('''
                CREATE TABLE teaching_state_new (
                  id               TEXT PRIMARY KEY,
                  session_id       TEXT NOT NULL UNIQUE REFERENCES sessions(id) ON DELETE CASCADE,
                  current_phase    TEXT NOT NULL DEFAULT 'P0_ENGAGE'
                                   CHECK(current_phase IN ('P0_ENGAGE','P1_WORLD','P2_PRACTICE_LOOP','P3_TRAINING','P4_REVIEW')),
                  current_subphase TEXT DEFAULT NULL,
                  attitude_level   TEXT DEFAULT NULL,
                  updated_at       INTEGER NOT NULL DEFAULT (unixepoch())
                )
              ''');
          await customStatement('''
                INSERT INTO teaching_state_new (id, session_id, current_phase, current_subphase, attitude_level, updated_at)
                SELECT id, session_id, current_phase, current_subphase, attitude_level, updated_at FROM teaching_state
              ''');
          await customStatement('DROP TABLE teaching_state');
          await customStatement(
            'ALTER TABLE teaching_state_new RENAME TO teaching_state',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_teaching_state_session ON teaching_state(session_id)',
          );
        }
      }

      // v12: add_beginner_level_to_teaching_state（幂等）
      if (from < 12) {
        final cols = await customSelect(
          'PRAGMA table_info(teaching_state)',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('beginner_level')) {
          await customStatement(
            "ALTER TABLE teaching_state ADD COLUMN beginner_level TEXT DEFAULT NULL CHECK(beginner_level IN ('N0_ENGAGE','N1_ELEMENTS','N2_SCENE','N3_DIAGNOSE','N4_INDEPENDENT'))",
          );
        }
      }

      // v13: add_style_profile_to_student_model（幂等）— 批次53 写作风格画像
      if (from < 13) {
        final cols = await customSelect(
          'PRAGMA table_info(student_model)',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('style_profile')) {
          await customStatement(
            'ALTER TABLE student_model ADD COLUMN style_profile TEXT DEFAULT NULL',
          );
        }
      }

      // v14: add_adopted_dismissed_to_teacher_suggestion（幂等）— 批次62 采纳回写
      if (from < 14) {
        final cols = await customSelect(
          'PRAGMA table_info(teacher_suggestion)',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('adopted_at')) {
          await customStatement(
            'ALTER TABLE teacher_suggestion ADD COLUMN adopted_at INTEGER DEFAULT NULL',
          );
        }
        if (!colNames.contains('dismissed_at')) {
          await customStatement(
            'ALTER TABLE teacher_suggestion ADD COLUMN dismissed_at INTEGER DEFAULT NULL',
          );
        }
      }

      // v15: add_style_fingerprint_to_student_model（幂等）— 批次64 定量指纹
      if (from < 15) {
        final cols = await customSelect(
          'PRAGMA table_info(student_model)',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('style_fingerprint')) {
          await customStatement(
            'ALTER TABLE student_model ADD COLUMN style_fingerprint TEXT DEFAULT NULL',
          );
        }
      }

      // v16: add_character_fact_table — 批次66 B62i A6 人物知识结构
      if (from < 16) {
        await customStatement('''
              CREATE TABLE IF NOT EXISTS character_fact (
                id                 TEXT PRIMARY KEY,
                manuscript_id      TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
                name               TEXT NOT NULL,
                first_seen_chapter INTEGER DEFAULT NULL,
                first_seen_at      INTEGER DEFAULT NULL,
                assertions         TEXT NOT NULL DEFAULT '[]',
                created_at         INTEGER NOT NULL DEFAULT (unixepoch()),
                updated_at         INTEGER NOT NULL DEFAULT (unixepoch()),
                UNIQUE(manuscript_id, name)
              )
            ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_character_fact_manuscript ON character_fact(manuscript_id)',
        );
      }

      // v17: add_event_fact_and_subplot_fact_tables — 批次67 B62j A6 第二迭代（F07/F11）
      if (from < 17) {
        await customStatement('''
              CREATE TABLE IF NOT EXISTS event_fact (
                id            TEXT PRIMARY KEY,
                manuscript_id TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
                name          TEXT NOT NULL,
                chapter       INTEGER DEFAULT NULL,
                event_type    TEXT NOT NULL,
                cause_event_id  TEXT DEFAULT NULL,
                effect_event_id TEXT DEFAULT NULL,
                participants  TEXT NOT NULL DEFAULT '[]',
                description   TEXT NOT NULL DEFAULT '',
                created_at    INTEGER NOT NULL DEFAULT (unixepoch()),
                updated_at    INTEGER NOT NULL DEFAULT (unixepoch()),
                UNIQUE(manuscript_id, name)
              )
            ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_event_fact_manuscript ON event_fact(manuscript_id)',
        );
        await customStatement('''
              CREATE TABLE IF NOT EXISTS subplot_fact (
                id                  TEXT PRIMARY KEY,
                manuscript_id       TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
                name                TEXT NOT NULL,
                introduced_chapter  INTEGER DEFAULT NULL,
                resolved_chapter    INTEGER DEFAULT NULL,
                resolved_at         INTEGER DEFAULT NULL,
                description         TEXT NOT NULL DEFAULT '',
                created_at          INTEGER NOT NULL DEFAULT (unixepoch()),
                updated_at          INTEGER NOT NULL DEFAULT (unixepoch()),
                UNIQUE(manuscript_id, name)
              )
            ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_subplot_fact_manuscript ON subplot_fact(manuscript_id)',
        );
      }

      // v18: add_outline_entity_and_impression_tables — 批次72 大纲层（AI 自主记忆沉淀）
      if (from < 18) {
        await customStatement('''
              CREATE TABLE IF NOT EXISTS outline_entity (
                id            TEXT PRIMARY KEY,
                manuscript_id TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
                entity_type   TEXT NOT NULL
                              CHECK(entity_type IN ('character','setting','plot')),
                entity_key    TEXT NOT NULL,
                aliases       TEXT NOT NULL DEFAULT '[]',
                status        TEXT NOT NULL DEFAULT 'pending'
                              CHECK(status IN ('pending','active','rejected')),
                created_at    INTEGER NOT NULL DEFAULT (unixepoch()),
                updated_at    INTEGER NOT NULL DEFAULT (unixepoch()),
                UNIQUE(manuscript_id, entity_key)
              )
            ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_outline_entity_manuscript ON outline_entity(manuscript_id)',
        );
        await customStatement('''
              CREATE TABLE IF NOT EXISTS outline_impression (
                id                  TEXT PRIMARY KEY,
                entity_id           TEXT NOT NULL REFERENCES outline_entity(id) ON DELETE CASCADE,
                impression          TEXT NOT NULL,
                source_chapter_id   TEXT DEFAULT NULL,
                source_chapter_no   INTEGER DEFAULT NULL,
                version             INTEGER NOT NULL DEFAULT 1,
                conflict_with       TEXT DEFAULT NULL,
                status              TEXT NOT NULL DEFAULT 'pending'
                                    CHECK(status IN ('pending','active','rejected','superseded')),
                created_at          INTEGER NOT NULL DEFAULT (unixepoch()),
                UNIQUE(entity_id, impression)
              )
            ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_outline_impression_entity ON outline_impression(entity_id)',
        );
      }

      // v19: add_teaching_state_to_active_problem（幂等）— 教学状态机持久化
      if (from < 19) {
        final cols = await customSelect(
          'PRAGMA table_info(active_problem)',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('teaching_state')) {
          await customStatement(
            "ALTER TABLE active_problem ADD COLUMN teaching_state TEXT DEFAULT NULL CHECK(teaching_state IN ('identified','in_progress','consolidating','mastered'))",
          );
        }
      }

      // v20: add_updated_at_to_active_problem（幂等）— 批次5（5.3）
      if (from < 20) {
        final cols = await customSelect(
          'PRAGMA table_info(active_problem)',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('updated_at')) {
          await customStatement(
            'ALTER TABLE active_problem ADD COLUMN updated_at INTEGER DEFAULT NULL',
          );
        }
      }

      // v21: expand_session_reference_check（D2，批次7）
      // 重建 session_reference 表扩展 ref_type CHECK 允许 'file' 作次引用。
      // SQLite 不支持 ALTER CHECK，走「建新表 → 复制 → 删旧 → 改名」，
      // 保留 UNIQUE(session_id, ref_type, ref_id)（addReference 的 ON CONFLICT 依赖）
      // 与索引；DROP 连带删除索引 → 用 IF NOT EXISTS 幂等重建。
      if (from < 21) {
        await customStatement('''
              CREATE TABLE session_reference_new (
                id            TEXT PRIMARY KEY,
                session_id    TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                ref_type      TEXT NOT NULL
                              CHECK(ref_type IN ('manuscript','chapter','file')),
                ref_id        TEXT NOT NULL,
                is_primary    INTEGER NOT NULL DEFAULT 0
                              CHECK(is_primary IN (0,1)),
                excerpt_range TEXT DEFAULT NULL,
                created_at    INTEGER NOT NULL DEFAULT (unixepoch()),
                UNIQUE(session_id, ref_type, ref_id)
              )
            ''');
        await customStatement('''
              INSERT INTO session_reference_new (id, session_id, ref_type, ref_id, is_primary, excerpt_range, created_at)
              SELECT id, session_id, ref_type, ref_id, is_primary, excerpt_range, created_at FROM session_reference
            ''');
        await customStatement('DROP TABLE session_reference');
        await customStatement(
          'ALTER TABLE session_reference_new RENAME TO session_reference',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_session_reference_session ON session_reference(session_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_session_reference_target ON session_reference(ref_type, ref_id)',
        );
      }

      // v22: add_references_json_to_messages（批次71 @ 引用可视化）
      // 消息级引用快照：气泡底部展示 @ 引用徽章（JSON 数组，nullable）。
      // SQLite 版本普遍支持 ADD COLUMN，直接 ALTER 即可（幂等）。
      if (from < 22) {
        await customStatement(
          'ALTER TABLE messages ADD COLUMN references_json TEXT DEFAULT NULL',
        );
      }

      // v23: add_volumes_table（批次89 卷分组）
      // 新建 volumes 表 + chapters.volume_id（可空，兼容存量章节）。
      // 删卷时卷内章节 SET NULL 回「未分卷」（外键 ON DELETE SET NULL）。
      if (from < 23) {
        await customStatement('''
              CREATE TABLE IF NOT EXISTS volumes (
                id            TEXT PRIMARY KEY,
                manuscript_id TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
                title         TEXT NOT NULL DEFAULT '',
                sort_order    INTEGER NOT NULL DEFAULT 0,
                created_at    INTEGER NOT NULL DEFAULT (unixepoch()),
                updated_at    INTEGER NOT NULL DEFAULT (unixepoch())
              )
            ''');
        final colNames = (await customSelect('PRAGMA table_info(chapters)').get())
            .map((r) => r.read<String>('name'))
            .toSet();
        if (!colNames.contains('volume_id')) {
          await customStatement(
            'ALTER TABLE chapters ADD COLUMN volume_id TEXT DEFAULT NULL REFERENCES volumes(id) ON DELETE SET NULL',
          );
        }
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_volumes_manuscript ON volumes(manuscript_id, sort_order)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_chapters_volume ON chapters(volume_id)',
        );
      }

      // v24: expand_chapters_status_check（批次94-2 章节回收站）
      // chapters.status CHECK 扩 'archived'（软删态）。SQLite 不支持 ALTER CHECK，
      // 走「建新表 → 复制 → 删旧 → 改名」标准流程，幂等保护见下。
      if (from < 24) {
        await customStatement('''
              CREATE TABLE chapters_new (
                id                TEXT PRIMARY KEY,
                manuscript_id     TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
                volume_id         TEXT DEFAULT NULL REFERENCES volumes(id) ON DELETE SET NULL,
                title             TEXT NOT NULL DEFAULT '',
                content           TEXT NOT NULL DEFAULT '',
                previous_content  TEXT DEFAULT NULL,
                word_count        INTEGER NOT NULL DEFAULT 0,
                sort_order        INTEGER NOT NULL DEFAULT 0,
                status            TEXT NOT NULL DEFAULT 'draft'
                                  CHECK(status IN ('draft','revising','complete','archived')),
                last_diagnosed_at INTEGER DEFAULT NULL,
                created_at        INTEGER NOT NULL DEFAULT (unixepoch()),
                updated_at        INTEGER NOT NULL DEFAULT (unixepoch())
              )
            ''');
        await customStatement('''
              INSERT INTO chapters_new (id, manuscript_id, volume_id, title, content, previous_content, word_count, sort_order, status, last_diagnosed_at, created_at, updated_at)
              SELECT id, manuscript_id, volume_id, title, content, previous_content, word_count, sort_order, status, last_diagnosed_at, created_at, updated_at FROM chapters
            ''');
        await customStatement('DROP TABLE chapters');
        await customStatement('ALTER TABLE chapters_new RENAME TO chapters');
        // DROP 连带删除索引 → 幂等重建（含 v23 卷索引）
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_chapters_manuscript_id ON chapters(manuscript_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_chapters_sort_order ON chapters(manuscript_id, sort_order)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_chapters_volume ON chapters(volume_id)',
        );
      }

      // v25: add_tags_to_manuscripts（批次94-5 标签落库，幂等）
      if (from < 25) {
        final cols = await customSelect('PRAGMA table_info(manuscripts)').get();
        final hasTags = cols.any((r) => r.read<String>('name') == 'tags');
        if (!hasTags) {
          await customStatement(
            "ALTER TABLE manuscripts ADD COLUMN tags TEXT DEFAULT '[]'",
          );
        }
      }

      // A-2：稳定 ID 标记语法已在解析层（mention_parser）落地，
      //      不再需要 ref_title 快照列（死 schema，评审移除）。
    },

    beforeOpen: (details) async {
      // 严格复刻原项目 db/index.ts 的 openAndConfigureDb
      // WAL 模式（并发读写、移动端性能）
      await customStatement('PRAGMA journal_mode = WAL');
      // foreign_keys = ON（PRD 的级联删除依赖它，SQLite 默认 OFF！）
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

// ── 数据库连接 ──

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'yuesheng.db'));
    return NativeDatabase.createInBackground(file);
  });
}
