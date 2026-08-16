// 临时验证脚本：检查设备数据库中的演示数据（用完即删）
// 用法：dart run tool/inspect_device_db.dart <db路径>
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  final dbPath = args.isNotEmpty ? args[0] : 'device.db';
  final db = sqlite3.open(dbPath);
  try {
    db.execute('PRAGMA wal_checkpoint;');
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    print('tables: ${tables.map((r) => r['name']).toList()}');
    for (final t in ['manuscripts', 'chapters', 'volumes']) {
      final rows = db.select('SELECT COUNT(*) c FROM $t');
      print('$t count = ${rows.first['c']}');
    }
    for (final r in db.select('SELECT id, title FROM manuscripts')) {
      print('ms: ${r['id']} ${r['title']}');
    }
    for (final r in db.select(
      'SELECT id, title, sort_order FROM volumes ORDER BY sort_order',
    )) {
      print('vol: ${r['id']} ${r['title']} order=${r['sort_order']}');
    }
    for (final r in db.select(
      'SELECT title, volume_id FROM chapters ORDER BY sort_order',
    )) {
      print('ch: ${r['title']} volume=${r['volume_id']}');
    }
  } finally {
    db.dispose();
  }
}
