// ─────────────────────────────────────────────────────────────
// pre_migrate 备份保留策略（**平台门面** · T-20261031-03 §九 #2）
//
// 为什么是门面：
//   本模块的 io 实现要碰 `Directory` / `File` ⇒ **整份归 io 侧**；
//   但消费方 `lib/data/database/database.dart` 必须保持**无 io 依赖**
//   （否则 web 编译期就红）。⇒ 本文件只做**条件导出**：
//     · native（移动端 / 桌面）→ `backup_retention_io.dart`（真实实现）
//     · web                    → `backup_retention_web.dart`（stub，抛 UnsupportedError）
//
// 平台无关的纯逻辑（按套归组 → 淘汰清单）在 `backup_retention_core.dart`，
// 两侧共用同一份实现（**不复制逻辑、不新增 A→B 静态映射表**）。
//
// ★ 消费方与调用图（拆分前不变）：
//   · `lib/data/database/database.dart` → `_preMigrateBackup`（迁移前备份的**唯一写入方**）
//   · `lib/services/database_backup_service_io.dart` → 保留策略的**既有归属**
//   ⇒ 两处都不得反向 import service，否则构成文件级环 ⇒ 门禁 3 直接红。
//
// 落盘形态（**不是** `.db` 单文件，是三件套）：
//   backup_<stamp>_pre_migrate_v<from>            ← 主库副本
//   backup_<stamp>_pre_migrate_v<from>-wal        ← WAL 副本
//   backup_<stamp>_pre_migrate_v<from>-shm        ← SHM 副本
//   ⇒ 「一套」= 同一次迁移前的这三件。
//
// ★ 为什么不能沿用按 `.db` 计数的旧清理：
//   `DatabaseBackupService.cleanupOldBackups` 过滤 `endsWith('.db')`，
//   而 pre_migrate 的文件名**没有 `.db` 扩展名**（后缀是 `-wal` / `-shm` 或什么都没有）
//   ⇒ 对它是**空操作**（一条都匹配不到）。这正是「备份目录无上限增长」的直接成因。
//   ⇒ 本模块按**前缀成套**归组，整**套**淘汰，**绝不删半套**（半套 = 不可用备份）。
// ─────────────────────────────────────────────────────────────

export 'backup_retention_io.dart'
    if (dart.library.js_interop) 'backup_retention_web.dart';
