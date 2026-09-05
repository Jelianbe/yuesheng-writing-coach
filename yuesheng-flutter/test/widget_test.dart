import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/main.dart';

void main() {
  // 批次 0 占位测试：仅验证 YueshengApp 类型存在（批次63 改为 ConsumerStatefulWidget 启动门）。
  // 不 pumpWidget，避免触发数据库初始化（path_provider 在纯 widget test 不可用）。
  // 数据库初始化的真源验证由 main.dart 的 DatabaseVerifyPage 在真机/集成测试中完成。
  test('YueshengApp 类型存在且为 ConsumerStatefulWidget', () {
    const app = YueshengApp();
    expect(app, isA<ConsumerStatefulWidget>());
  });

  // 批次 0 四闸验证：DB 能开 + onCreate 建表 + PRAGMA 正确
  // 用内存数据库验证新建路径（onCreate 建 v12 最终形态）。
  // onUpgrade 路径（老库升级）在有真实用户数据时才需要，当前是全新 Flutter 项目无老库。
  test('数据库 onCreate 建表 + PRAGMA 正确', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      // 1. 验证 14 张业务表存在（排除 sqlite 内部表）
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .get();
      final tableNames = tables.map((r) => r.read<String>('name')).toSet();

      const expectedTables = {
        'manuscripts',
        'chapters',
        'sessions',
        'messages',
        'diagnosis_results',
        'teaching_state',
        'active_problem',
        'student_model',
        'session_reference',
        'app_state',
        'error_logs',
        'attached_files',
        'teacher_suggestion',
        'editor_observation',
        'character_fact',
        'event_fact',
        'subplot_fact',
        'outline_entity',
        'outline_impression',
        'volumes',
      };
      expect(tableNames.length, 21, reason: '应有 21 张业务表');
      for (final t in expectedTables) {
        expect(tableNames.contains(t), true, reason: '缺少表: $t');
      }

      // 2. 验证 user_version = 27（drift schemaVersion；批次89 → 23，批次94-2 → 24
      // chapters.status CHECK 扩 'archived'；批次94-5 → 25 manuscripts.tags 列；
      // 批次96+ → 26 新增 volumes 之外的 schema bump；
      // C78 批次1 → 27 角色标签页列：character_fact.aliases/status，
      // event_fact.stale/chapter_hash）
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(
        version.read<int>('user_version'),
        27,
        reason: 'schemaVersion 应为 27',
      );

      // 2.5 批次71：验证 messages.references_json 列存在
      final cols = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('messages') WHERE name='references_json'",
          )
          .get();
      expect(cols.length, 1, reason: 'messages 表缺少 references_json 列');

      // 3. 验证 foreign_keys = ON（beforeOpen 回调设置）
      final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(
        fk.read<int>('foreign_keys'),
        1,
        reason: 'foreign_keys 必须开启（PRD 级联删除依赖）',
      );

      // 4. 验证关键索引存在（抽查 3 个）
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%' ORDER BY name",
          )
          .get();
      final indexNames = indexes.map((r) => r.read<String>('name')).toSet();
      expect(
        indexNames.contains('idx_chapters_manuscript_id'),
        true,
        reason: '缺少章节索引',
      );
      expect(
        indexNames.contains('idx_messages_session'),
        true,
        reason: '缺少消息索引',
      );
      expect(
        indexNames.contains('idx_active_problem_session'),
        true,
        reason: '缺少问题索引',
      );
    } finally {
      await db.close();
    }
  });
}
