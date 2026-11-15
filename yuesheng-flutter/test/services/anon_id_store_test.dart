// anon_id_store_test.dart — `DECISIONS §4-516` 匿名载体的可单测判据。
//
// 覆盖报批稿（2026-11-15 §六）中 App 侧可单测的部分：
//   G 形状：36 字符 UUID v4（与 web 侧 `crypto.getRandomValues` 构造同构）。
//   H 判据②：同设备两次调用同值（含「进程重启」= 清内存缓存后仍同值）。
//   I 存储已有合法值 ⇒ 复用，不重生成。
//   J 判据③ App 等价形态：存储值不合法 ⇒ 换新值并覆盖（= 清数据后换 ID）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:writingcoach/services/anon_id_store.dart';

/// v4 形状：第三段首字符 4，第四段首字符 ∈ {8,9,a,b}（variant 10xx）。
final RegExp _kV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AnonIdStore.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('G：首次调用生成 36 字符 UUID v4 形状并写回', () async {
    final id = await AnonIdStore.loadOrCreate();
    expect(id, isNotNull);
    expect(id!.length, 36);
    expect(_kV4.hasMatch(id), isTrue, reason: '判据①同构：须为 v4 形状');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAnonIdPrefsKey), id);
  });

  test('H：同设备两次调用同值（判据② · 清内存缓存后仍同值）', () async {
    final first = await AnonIdStore.loadOrCreate();
    AnonIdStore.debugReset(); // 模拟进程重启
    final second = await AnonIdStore.loadOrCreate();
    expect(first, isNotNull);
    expect(second, first);
  });

  test('I：存储已有合法值 ⇒ 直接复用，不重生成', () async {
    const fixed = '11111111-2222-4333-8444-555555555555';
    SharedPreferences.setMockInitialValues(<String, Object>{
      kAnonIdPrefsKey: fixed,
    });
    AnonIdStore.debugReset();
    expect(await AnonIdStore.loadOrCreate(), fixed);
  });

  test('J：存储值形状不合法 ⇒ 重生成并覆盖（判据③ App 等价形态）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kAnonIdPrefsKey: 'short',
    });
    AnonIdStore.debugReset();
    final id = await AnonIdStore.loadOrCreate();
    expect(id, isNotNull);
    expect(id!.length, 36);
    expect(id, isNot('short'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAnonIdPrefsKey), id);
  });
}
