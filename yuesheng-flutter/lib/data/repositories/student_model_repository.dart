// ─────────────────────────────────────────────────────────────
// StudentModelRepository — 学员画像 DAO
// 复刻 yuesheng-android/src/db/dao/student-model-dao.ts
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/database.dart';
import '../database/utils.dart';
import '../../services/style_fingerprint.dart';
import '../../types/teaching_types.dart';

class StudentModelRepository {
  final AppDatabase _db;
  StudentModelRepository(this._db);

  /// 确保学员画像行存在（不存在则创建），返回 id
  /// 复刻 ensureStudentModel(sessionId) — private 在原项目里
  Future<String> _ensureStudentModel(String sessionId) async {
    final existing = await (_db.select(
      _db.studentModels,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    if (existing != null) return existing.id;

    final id = generateUuid();
    final now = nowSec();
    await _db
        .into(_db.studentModels)
        .insert(
          StudentModelsCompanion.insert(
            id: id,
            sessionId: sessionId,
            teachingHistory: const Value('[]'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  /// 追加教学历史记录
  /// 复刻 appendTeachingHistory(sessionId, record)
  /// record 是任意 JSON 对象（type: diagnosis/confirmation/training）
  Future<void> appendTeachingHistory(
    String sessionId,
    Map<String, dynamic> record,
  ) async {
    final now = nowSec();
    await _db.transaction(() async {
      final modelId = await _ensureStudentModel(sessionId);
      final model = await (_db.select(
        _db.studentModels,
      )..where((t) => t.id.equals(modelId))).getSingle();

      // 解析现有历史
      List<dynamic> history = [];
      try {
        final decoded = jsonDecode(model.teachingHistory);
        if (decoded is List) history = decoded;
      } catch (_) {}

      // 追加新记录
      history.add(record);

      await (_db.update(
        _db.studentModels,
      )..where((t) => t.id.equals(modelId))).write(
        StudentModelsCompanion(
          teachingHistory: Value(jsonEncode(history)),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// 获取教学历史
  /// 复刻 getTeachingHistory(sessionId)
  Future<List<Map<String, dynamic>>> getTeachingHistory(
    String sessionId,
  ) async {
    final model = await (_db.select(
      _db.studentModels,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    if (model == null) return [];

    try {
      final decoded = jsonDecode(model.teachingHistory);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return [];
  }

  /// 更新新手引导数据
  /// 复刻 updateOnboardingData(sessionId, data)
  Future<void> updateOnboardingData(
    String sessionId,
    Map<String, dynamic> data,
  ) async {
    final now = nowSec();
    await _db.transaction(() async {
      final modelId = await _ensureStudentModel(sessionId);
      await (_db.update(
        _db.studentModels,
      )..where((t) => t.id.equals(modelId))).write(
        StudentModelsCompanion(
          onboardingData: Value(jsonEncode(data)),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// 获取新手引导数据
  /// 复刻 getOnboardingData(sessionId)
  Future<Map<String, dynamic>?> getOnboardingData(String sessionId) async {
    final model = await (_db.select(
      _db.studentModels,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    if (model?.onboardingData == null) return null;

    try {
      final decoded = jsonDecode(model!.onboardingData!);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  /// 更新写作风格画像（批次53：并入 student_model.style_profile）
  /// 复刻目标：无 RN 真源（RN 无画像层风格字段，本批 Flutter 先行）
  Future<void> updateStyleProfile(
    String sessionId,
    WritingStyleProfile profile,
  ) async {
    final now = nowSec();
    await _db.transaction(() async {
      final modelId = await _ensureStudentModel(sessionId);
      await (_db.update(
        _db.studentModels,
      )..where((t) => t.id.equals(modelId))).write(
        StudentModelsCompanion(
          styleProfile: Value(jsonEncode(profile.toJson())),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// 更新最新一条有 style_profile 的画像（批次57：成长页风格纠正入口）
  ///
  /// 语义与 GrowthService.getLatestStyleProfile 一致（updated_at DESC, rowid DESC）。
  /// 无任何有效记录 → no-op（不创建新画像，纠错仅作用于已有画像）。
  Future<void> updateLatestStyleProfile(WritingStyleProfile profile) async {
    final row = await _db
        .customSelect(
          "SELECT session_id FROM student_model "
          "WHERE style_profile IS NOT NULL AND style_profile != '' "
          'ORDER BY updated_at DESC, rowid DESC LIMIT 1',
        )
        .getSingleOrNull();
    final sessionId = row?.read<String?>('session_id');
    if (sessionId == null || sessionId.isEmpty) return;
    await updateStyleProfile(sessionId, profile);
  }

  /// 获取写作风格画像（无则返回 null；JSON 非法返回 null，不抛出）
  Future<WritingStyleProfile?> getStyleProfile(String sessionId) async {
    final model = await (_db.select(
      _db.studentModels,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    if (model?.styleProfile == null) return null;

    try {
      final decoded = jsonDecode(model!.styleProfile!);
      if (decoded is Map<String, dynamic>) {
        return WritingStyleProfile.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// M2 修复：跨 session 获取最新写作风格画像
  /// 供 buildStudentContext 注入 LLM，让 AI 了解学员五维风格坐标
  Future<WritingStyleProfile?> getLatestStyleProfile() async {
    final rows = await _db.customSelect(
      "SELECT style_profile FROM student_model "
      "WHERE style_profile IS NOT NULL AND style_profile != '' "
      'ORDER BY updated_at DESC, rowid DESC LIMIT 1',
    ).get();
    if (rows.isEmpty) return null;
    final raw = rows.first.read<String?>('style_profile');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return WritingStyleProfile.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// 更新写作风格定量指纹（批次64 B62f：L2→L3 沉淀）
  Future<void> updateStyleFingerprint(
    String sessionId,
    StyleFingerprint fingerprint,
  ) async {
    final now = nowSec();
    await _db.transaction(() async {
      final modelId = await _ensureStudentModel(sessionId);
      await (_db.update(
        _db.studentModels,
      )..where((t) => t.id.equals(modelId))).write(
        StudentModelsCompanion(
          styleFingerprint: Value(jsonEncode(fingerprint.toJson())),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// 获取写作风格定量指纹（无则返回 null；JSON 非法返回 null，不抛出）
  Future<StyleFingerprint?> getStyleFingerprint(String sessionId) async {
    final model = await (_db.select(
      _db.studentModels,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    if (model?.styleFingerprint == null) return null;

    try {
      final decoded = jsonDecode(model!.styleFingerprint!);
      if (decoded is Map<String, dynamic>) {
        return StyleFingerprint.tryFromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// 全表扫描：是否存在任意一条有效的 onboarding_data — 批次1-8 波6
  ///
  /// 用于 bootstrap_service 边界 A 修复：当 currentSession 查不到 onboarding_data
  /// 但用户级 questionnaire_completed 也缺失时，fallback 扫描全表。
  /// 只要任意一个 session 有有效数据（非 null / 非空串 / 非 'null' 字面量），
  /// 即认定老用户已填过问卷，触发用户级标记迁移。
  ///
  /// 注意：session_id 可能为 NULL（ON DELETE SET NULL 后残留下来的孤儿行），
  /// 但 onboarding_data 仍然有效，所以这里不限定 session_id。
  Future<bool> hasAnyOnboardingData() async {
    final row =
        await (_db.select(_db.studentModels)
              ..where(
                (t) =>
                    t.onboardingData.isNotNull() &
                    t.onboardingData.isNotIn(const ['', 'null']),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }
}
