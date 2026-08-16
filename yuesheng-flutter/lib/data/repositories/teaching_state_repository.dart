// ─────────────────────────────────────────────────────────────
// TeachingStateRepository — 教学状态 DAO
// 管理 teaching_state 表（current_phase / updated_at）
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';
import '../database/database.dart';
import '../database/utils.dart';

class TeachingStateRepository {
  final AppDatabase _db;
  TeachingStateRepository(this._db);

  /// 持久化态度（attitude_level）
  ///
  /// 复刻 yuesheng-android persistAttitudeTx：事务性双写
  /// teaching_state.attitude_level + student_model.attitude_preference，
  /// 保证两表一致（任一失败则整体回滚）。
  ///
  /// **A2 修复**：teaching_state 先 update，无匹配行再 insert，
  /// 兼容 teaching_state 行缺失的边界场景（race/迁移/未走 createBlankSession）。
  /// 原实现仅 update，行不存在时静默 0 行写入 → attitudeLevel 为空但
  /// student_model 已写入 → 两表不一致。
  Future<void> persistAttitude(String sessionId, String attitude) async {
    final now = nowSec();
    await _db.transaction(() async {
      // 1. teaching_state（Upsert：先 update，受影响 0 行再 insert）
      final affected = await (_db.update(
        _db.teachingState,
      )..where((t) => t.sessionId.equals(sessionId))).write(
            TeachingStateCompanion(
              attitudeLevel: Value(attitude),
              updatedAt: Value(now),
            ),
          );
      if (affected == 0) {
        await _db.into(_db.teachingState).insert(
              TeachingStateCompanion.insert(
                id: generateUuid(),
                sessionId: sessionId,
                currentPhase: const Value('P0_ENGAGE'),
                attitudeLevel: Value(attitude),
                updatedAt: Value(now),
              ),
            );
      }

      // 2. student_model：不存在则创建，否则更新 attitude_preference
      final existing = await (_db.select(
        _db.studentModels,
      )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
      if (existing == null) {
        await _db
            .into(_db.studentModels)
            .insert(
              StudentModelsCompanion.insert(
                id: generateUuid(),
                sessionId: sessionId,
                attitudePreference: Value(attitude),
                teachingHistory: const Value('[]'),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (_db.update(
          _db.studentModels,
        )..where((t) => t.sessionId.equals(sessionId))).write(
          StudentModelsCompanion(
            attitudePreference: Value(attitude),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// 更新会话的当前教学阶段
  ///
  /// **A2 修复**：同步 upsert（update 0 行时 insert），无行时自动建行。
  /// 原实现仅 update，session 未走 createBlankSession 时静默失败。
  Future<void> updatePhase(String sessionId, String phase) async {
    final now = nowSec();
    final affected = await (_db.update(
      _db.teachingState,
    )..where((t) => t.sessionId.equals(sessionId))).write(
          TeachingStateCompanion(
            currentPhase: Value(phase),
            updatedAt: Value(now),
          ),
        );
    if (affected == 0) {
      await _db.into(_db.teachingState).insert(
            TeachingStateCompanion.insert(
              id: generateUuid(),
              sessionId: sessionId,
              currentPhase: Value(phase),
              updatedAt: Value(now),
            ),
          );
    }
  }

  /// 读取会话的教学状态（不存在返回 null）
  Future<TeachingStateRow?> getTeachingState(String sessionId) async {
    return (_db.select(
      _db.teachingState,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
  }

  /// 更新学员等级（beginner_level）
  ///
  /// **A2 修复**：同步 upsert，无行时自动建行。
  Future<void> updateBeginnerLevel(
    String sessionId,
    String beginnerLevel,
  ) async {
    final now = nowSec();
    final affected = await (_db.update(
      _db.teachingState,
    )..where((t) => t.sessionId.equals(sessionId))).write(
          TeachingStateCompanion(
            beginnerLevel: Value(beginnerLevel),
            updatedAt: Value(now),
          ),
        );
    if (affected == 0) {
      await _db.into(_db.teachingState).insert(
            TeachingStateCompanion.insert(
              id: generateUuid(),
              sessionId: sessionId,
              currentPhase: const Value('P0_ENGAGE'),
              beginnerLevel: Value(beginnerLevel),
              updatedAt: Value(now),
            ),
          );
    }
  }

  /// 更新当前子阶段（current_subphase，可空）
  ///
  /// **A2 修复**：同步 upsert，无行时自动建行。
  Future<void> updateSubphase(String sessionId, String? subphase) async {
    final now = nowSec();
    final affected = await (_db.update(
      _db.teachingState,
    )..where((t) => t.sessionId.equals(sessionId))).write(
          TeachingStateCompanion(
            currentSubphase: Value(subphase),
            updatedAt: Value(now),
          ),
        );
    if (affected == 0) {
      await _db.into(_db.teachingState).insert(
            TeachingStateCompanion.insert(
              id: generateUuid(),
              sessionId: sessionId,
              currentPhase: const Value('P0_ENGAGE'),
              currentSubphase: Value(subphase),
              updatedAt: Value(now),
            ),
          );
    }
  }
}
