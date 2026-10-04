// ─────────────────────────────────────────────────────────────
// ApiConfigPage widget 测试 — API 配置子页（/settings/api-config）
//
// 为什么这些用例从 settings_page_test.dart 迁到这里：
//   「填表单 + 测试 + 保存」整块已下沉为独立子页（360x640竖屏 = 平台唯一
//   形态，主 CTA 在设置页实测 bottom=721 超首屏 81dp）。表单相关的用例
//   随表单一起走；设置页只留账号列表 / 外观 / 用量 / 维护 / 进度。
//
// 迁移的用例：#2 #F7 #3 #4 #5 #B5-1~#B5-4 #6 #7 #7b #A #B #M2 #M6 #E2
//
// ★ 夹具（_FakeConfigStorage / _FakeLlmClient / seedAccounts / setUp 的
//   secure_storage mock）从 settings_page_test.dart **照抄**：ADR-C91 多账号
//   的 key map 走 flutter_secure_storage 平台通道，不mock 会抛
//   MissingPluginException，故这里的 mock 是**功能依赖**不是样板。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/ai_account_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_resolver.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/features/app_settings/api_config_page.dart';
import '../helpers/mock_last_session_storage.dart';

/// Fake 配置存储：内存 map，避免触碰 flutter_secure_storage
class _FakeConfigStorage extends LlmConfigStorage {
  LlmConfigValues? stored;

  @override
  Future<LlmConfigValues?> getLlmConfig() async => stored;

  @override
  Future<void> saveLlmConfig(LlmConfigValues config) async {
    stored = config;
  }

  @override
  Future<void> clearLlmConfig() async {
    stored = null;
  }
}

/// Fake LLM 客户端：固定返回成功，避免真实网络
class _FakeLlmClient extends LlmClient {
  TestConnectionResult? result;
  LlmConfigValues? lastConfig;

  /// ★ 开关：让 [testLlmConnection] **直接抛异常**。
  ///
  /// 为什么需要它：`result.success == false`（正常返回失败）与「抛异常」是
  /// 两条**不同**的代码路径 —— 后者才进`_setConnFailed()`（api_config_page.dart:342，
  /// 两个 handler 共用）。只测前者会让共用失败态**整段无覆盖**，
  /// 且异常真的抛出时若catch 被误删，界面会静默停在「测试中」永不收敛。
  bool throwOnTest = false;

  @override
  Future<TestConnectionResult> testLlmConnection({
    LlmConfigValues? config,
  }) async {
    lastConfig = config;
    if (throwOnTest) throw StateError('模拟网络异常（连接被拒）');
    return result ??
        const TestConnectionResult(success: true, message: '连接成功（42ms）');
  }
}

/// 未配置 API 时的警告条文案 —— 断言**字面量**，不调用生产函数。
///
/// ★ 2026-10-04，两次踩坑记录（都是「假绿」形态）：
///  ① 原断言写的是旧措辞「填写以下信息」⇒ 与生产不符恒红；同文件另存一份
///     字面量副本 ⇒ 改生产文案时它跟着不红，等于第三份副本。
///  ② 改法一度写成 `buildUnconfiguredWarning(onSettingsPage: false)`——
///     **错**：期望值与被测物出自同一函数，改函数时两边同步变 ⇒ 断言永真。
///     变异验证时改生产文案，27 条用例**全绿**（已实测）。
/// ⇒ 正确姿势：期望侧固定**字面量**，让「生产文案漂移」被抓出来。
/// 本行与 `settings_cards.dart` 的 `buildUnconfiguredWarning` 是**有意的重复**：
/// 它是「跨页口径锚点」，靠这份不动的手写副本证明两页前缀一字不差。
const String _kUnconfiguredWarning = '尚未配置 API，当前为免费测试模式（离线示例）。填写下方表单以启用完整功能';

/// 同一警告条的**前半句**（两页必须逐字相同）。
///单独拆出来断言，是为了在前半句被改动时给出更精确的失败信息。
const String _kUnconfiguredWarningPrefix = '尚未配置 API，当前为免费测试模式（离线示例）。';

void main() {
  late AppDatabase db;
  late _FakeConfigStorage storage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _FakeConfigStorage();
    // ADR-C91：多账号 key map 走 flutter_secure_storage，测试环境必须 mock
    // platform channel（否则 createAccount 写 key map 抛 MissingPluginException）。
    final secure = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final key = (call.arguments as Map?)?['key'] as String?;
            switch (call.method) {
              case 'read':
                return secure[key];
              case 'write':
                secure[key!] = (call.arguments as Map)['value'] as String;
                return null;
              case 'delete':
                secure.remove(key);
                return null;
            }
            return null;
          },
        );
  });

  tearDown(() async => db.close());

  Widget buildPage({_FakeLlmClient? llm}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        lastSessionStorageProvider.overrideWithValue(
          MemoryLastSessionStorage(),
        ),
      ],
      child: MaterialApp(
        home: ApiConfigPage(
          configStorage: storage,
          llmClient: llm ?? _FakeLlmClient(),
        ),
      ),
    );
  }

  /// 填满表单（三字段）
  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'sk-abc');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://api.deepseek.com/',
    );
    await tester.enterText(find.byType(TextField).at(2), 'deepseek-v4-flash');
  }

  /// 滚动到目标控件后点击（ListView 惰性构建 + 表单较长）
  Future<void> scrollAndTap(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> seedAccounts(AppDatabase target) async {
    final repo = AIAccountRepository(target);
    await repo.createAccount(
      name: 'DeepSeek 主账号',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-v4-flash',
      apiKey: 'sk-main',
    );
    await repo.createAccount(
      name: 'Kimi 备选',
      baseUrl: 'https://api.moonshot.cn/v1',
      model: 'kimi-k3',
      apiKey: 'sk-kimi',
    );
  }

  /// ★ 让**账号表的读/写路径**抛异常（DROP TABLE），用于验失败文案分支。
  ///
  /// 为什么用「drop 表」而不是「注入 repository 替身」：本页的
  /// `_accountRepo` 是 `initState` 里 `AIAccountRepository(ref.read(
  /// appDatabaseProvider))` 自建的（api_config_page.dart:141），
  /// **没有注入点** —— 造一个抛异常的 repository 替身得先改生产代码签名，
  /// 那是越界。drop 表则是**真实的 DB 故障**，`listAccounts/setDefault/
  /// createAccount` 都会真的抛，走的是生产代码原样逻辑。
  Future<void> breakAccountTable() =>
      db.customStatement('DROP TABLE IF EXISTS ai_accounts');

  testWidgets('#C1 子页渲染：标题 + 未配置警告 + 三输入框', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('API 配置'), findsOneWidget); // AppBar 标题
    // ★ 文案取生产实际值（api_config_page.dart:590「填写**下方表单**」）。
    //   原断言写的是「填写以下信息」—— 那是设置页的旧措辞，本页表单就在
    //   正下方，生产早已改口径。留着旧串会让本条**恒红**，且:173 的
    //   findsNothing 因「永不匹配」而**空过假绿**（负向断言失去鉴别力）。
    expect(find.text(_kUnconfiguredWarning), findsOneWidget);
    // 前半句单独断言：两页口径必须一字不差，若有人只改了引导语，
    // 上面整句断言会红；这条则保证「前缀」这个跨页契约本身被钉住。
    expect(
      find.textContaining(_kUnconfiguredWarningPrefix),
      findsOneWidget,
      reason: '警告条前半句是跨页口径锚点，两页必须逐字相同',
    );
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('#2 表单加载已有配置', (tester) async {
    storage.stored = const LlmConfigValues(
      apiKey: 'sk-existing',
      baseUrl: 'https://api.example.com',
      model: 'model-x',
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    // 表单已填充 → 未配置警告消失
    expect(find.text(_kUnconfiguredWarning), findsNothing);
    final keyField = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(keyField.controller!.text, 'sk-existing');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'https://api.example.com',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'model-x',
    );
  });

  // FIX-7：API Key 输入框显隐切换（默认密码态，可临时显示支持粘贴）
  testWidgets('#F7 API Key 显隐切换', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    final keyField = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(keyField.obscureText, isTrue, reason: '默认应为密码态');
    expect(find.byIcon(Icons.visibility), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();

    final shownField = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(shownField.obscureText, isFalse, reason: '点击眼睛后应明文显示');
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();

    final hiddenAgain = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(hiddenAgain.obscureText, isTrue, reason: '再点应回到密码态');
  });

  testWidgets('#3 保存配置 → 建账号（ADR-C91 多账号）', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await fillForm(tester);
    await scrollAndTap(tester, '保存配置');

    expect(find.text('API 配置已保存'), findsOneWidget);
    // 多账号：保存落 DB 账号（而非旧三键 storage）
    final accounts = await AIAccountRepository(db).listAccounts();
    expect(accounts, hasLength(1));
    expect(accounts.first.isDefault, isTrue); // 首建自动默认
    expect(accounts.first.baseUrl, 'https://api.deepseek.com'); // 去尾部斜杠
    expect(accounts.first.model, 'deepseek-v4-flash');
  });

  testWidgets('#4 空表单保存 → 完整提示', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    // 空表单：Key 空（预填了 DeepSeek 的 url/model，但 key 没有）
    await scrollAndTap(tester, '保存配置');

    expect(find.text('请填写完整的 API 配置'), findsOneWidget);
    expect(storage.stored, isNull);
    expect(await AIAccountRepository(db).listAccounts(), isEmpty);
  });

  testWidgets('#5 测试连接 → 成功结果框（直接用当前表单，不依赖保存）', (tester) async {
    final llm = _FakeLlmClient();
    await tester.pumpWidget(buildPage(llm: llm));
    await tester.pumpAndSettle();

    await fillForm(tester);
    await scrollAndTap(tester, '测试连接');

    expect(find.textContaining('✓ 连接成功'), findsOneWidget);
    // 测试连接直接使用当前表单（所见即所得），尾斜杠已清洗，不落库
    expect(llm.lastConfig?.apiKey, 'sk-abc');
    expect(llm.lastConfig?.baseUrl, 'https://api.deepseek.com');
    expect(llm.lastConfig?.model, 'deepseek-v4-flash');
    expect(await AIAccountRepository(db).listAccounts(), isEmpty);
  });

  // ══════════════════════════════════════════════════════════════
  // B5 第二批：「测试并保存」主 CTA
  //
  // 判据来源：360dp 竖屏实测（探针已回收）—— 主按钮满宽文字单行 20dp，
  // 次行各 141dp，总高 104dp；三并排不可行（每按钮仅 90~92.7dp 会换行）。
  // ══════════════════════════════════════════════════════════════

  testWidgets('#B5-1 测试并保存 → 成功即落库（联动保存）', (tester) async {
    final llm = _FakeLlmClient();
    await tester.pumpWidget(buildPage(llm: llm));
    await tester.pumpAndSettle();

    await fillForm(tester);
    await scrollAndTap(tester, '测试并保存');

    // 连接确实用的是当前表单（所见即所得）
    expect(llm.lastConfig?.apiKey, 'sk-abc');
    expect(llm.lastConfig?.baseUrl, 'https://api.deepseek.com');
    // ★ 核心判据：成功 ⇒ 写库
    final accounts = await AIAccountRepository(db).listAccounts();
    expect(accounts, hasLength(1), reason: '测试通过后应自动保存');
    expect(accounts.first.model, 'deepseek-v4-flash');
    expect(accounts.first.baseUrl, 'https://api.deepseek.com');
    // 首建自动为默认（用户不必再手动「设默认」才可用）
    expect(accounts.first.isDefault, isTrue);
    // 账号列表即时可见（不是只写库不刷新）。列表在表单**上方**，保存后
    // 视口停在按钮区 ⇒ 需滚回顶部才能命中（ListView 惰性构建）。
    await scrollUntilVisibleText(tester, '已保存的账号（1）');
    expect(find.text('已保存的账号（1）'), findsOneWidget);
  });

  testWidgets('#B5-2 测试失败 → 不落库（不通的密钥不产僵尸账号）', (tester) async {
    final llm = _FakeLlmClient()
      ..result = const TestConnectionResult(
        success: false,
        message: '密钥无效（401）',
      );
    await tester.pumpWidget(buildPage(llm: llm));
    await tester.pumpAndSettle();

    await fillForm(tester);
    await scrollAndTap(tester, '测试并保存');

    // 错误原因可见
    expect(find.textContaining('✗ 密钥无效'), findsOneWidget);
    // ★ 核心判据：失败 ⇒ 不写库。否则用户之后要手动去列表删僵尸账号，
    //   且它会占掉「默认」标记（getDefaultAccount 回退取首个）。
    expect(
      await AIAccountRepository(db).listAccounts(),
      isEmpty,
      reason: '测试失败不应写入账号',
    );
    expect(find.text('已保存的账号（1）'), findsNothing);
  });

  testWidgets('#B5-3 编辑已有账号时「测试并保存」→ 更新而非新建', (tester) async {
    final llm = _FakeLlmClient();
    await seedAccounts(db); // 2 个账号，'DeepSeek 主账号' 为默认
    // ★ 先按 **name** 抓到目标账号的 **id**：本实现把账号名取自 model 字段
    //   （_saveCurrentForm: name = _modelCtrl.text.trim()），保存后账号名会被
    //   改成新 model 值 ⇒ 迁移前那条用例用 `firstWhere((a) => a.name == ...)`
    //   在保存后**永远匹配不到**（抛 StateError），是条自身有 bug 的用例。
    //   改用 id 定位后，它才真正测「更新而非新建」这件事。
    final target = (await AIAccountRepository(
      db,
    ).listAccounts()).firstWhere((a) => a.name == 'DeepSeek 主账号');

    await tester.pumpWidget(buildPage(llm: llm));
    await tester.pumpAndSettle();

    // 点默认账号进入编辑态 → 改 model → 测试并保存
    await tester.tap(find.text('DeepSeek 主账号'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(2), 'edited-model');
    await scrollAndTap(tester, '测试并保存');

    final accounts = await AIAccountRepository(db).listAccounts();
    expect(accounts, hasLength(2), reason: '编辑态不得新建第 3 个账号');
    final edited = accounts.firstWhere((a) => a.id == target.id);
    expect(edited.model, 'edited-model', reason: '应更新原账号而非新建');
    expect(edited.isDefault, isTrue, reason: '默认标记应仍在这个账号上');
    // 负例：另一账号未被误改
    final other = accounts.firstWhere((a) => a.id != target.id);
    expect(other.model, 'kimi-k3');
  });

  testWidgets('#B5-4 空表单点「测试并保存」→ 提示补全，不落库', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await scrollAndTap(tester, '测试并保存');

    expect(find.textContaining('请先填写完整的 API 配置'), findsOneWidget);
    expect(await AIAccountRepository(db).listAccounts(), isEmpty);
  });

  testWidgets('#6 填充示例 → 字段填充', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await scrollAndTap(tester, '填充示例配置');

    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'https://api.deepseek.com',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'deepseek-v4-flash',
    );
  });

  testWidgets('#7 清空配置 → 确认后字段 + storage 清空', (tester) async {
    storage.stored = const LlmConfigValues(
      apiKey: 'sk-x',
      baseUrl: 'https://api.example.com',
      model: 'model-x',
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await scrollAndTap(tester, '清空配置');
    expect(find.text('确定清空所有 API 配置吗？'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(storage.stored, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '',
    );
  });

  testWidgets('#7b 清空配置 → resolveLlmConfig 返回 null（D01 验收：账号表 + 旧键全清）', (
    tester,
  ) async {
    // 清空前种入默认账号 + 旧三键，证明「清空前确有可用配置」
    final repo = AIAccountRepository(db);
    await repo.createAccount(
      name: '默认账号',
      baseUrl: 'https://api.example.com',
      model: 'model-x',
      apiKey: 'sk-seed',
      isDefault: true,
    );
    storage.stored = const LlmConfigValues(
      apiKey: 'sk-seed',
      baseUrl: 'https://api.example.com',
      model: 'model-x',
    );
    expect(await resolveLlmConfig(db, legacyStorage: storage), isNotNull);

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    await scrollAndTap(tester, '清空配置');
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    // 清空后：账号表删空 + 旧键清空 → 解析器返回 null（无可用配置）
    expect(await repo.listAccounts(), isEmpty);
    expect(await resolveLlmConfig(db, legacyStorage: storage), isNull);
  });

  testWidgets('#A 预设点选 → Kimi 自动填 kimi-k3 + api.moonshot.cn（批次A 时效性锚定）', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Kimi（月之暗面）'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'https://api.moonshot.cn/v1',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'kimi-k3',
    );
  });

  testWidgets('#B 预设点选 → 智谱/豆包新模型名生效（时效性锚定 2026-10-04）', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, '智谱 GLM'));
    await tester.pumpAndSettle();
    // 智谱取免费档 glm-4.7-flash（官方 free 分类，输入/输出/缓存全免），
    // 而非付费的 glm-4.7。锚定此值以防被无意改回收费档。
    // 鉴别力实测：预设改回 glm-4.6 或误写收费档 glm-4.7-flashx，本用例红。
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'glm-4.7-flash',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      isNot(contains('flashx')),
      reason:
          'glm-4.7-flashx 是收费档（与免费档仅差一个字母 x，上下文同为 '
          '200K），不得出现在智谱预设里',
    );

    await tester.tap(find.widgetWithText(ActionChip, '豆包（火山方舟）'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'doubao-seed-2.1-turbo',
    );
  });

  testWidgets('#M2 添加新账号 → 表单清空 + 保存后列表 +1', (tester) async {
    await seedAccounts(db);
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    // 当前编辑默认账号 → 点「添加新账号」清空表单
    await tester.tap(find.text('添加新账号'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '',
    );

    // 填新账号并保存（账号列表推高内容 → 滚到保存按钮）
    await tester.enterText(find.byType(TextField).at(0), 'sk-new');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://new.example.com',
    );
    await tester.enterText(find.byType(TextField).at(2), 'new-model');
    await scrollAndTap(tester, '保存配置');

    expect(find.text('API 配置已保存'), findsOneWidget);
    // 列表在表单**上方**，保存后视口停在底部按钮区 ⇒ 需滚回顶部。
    await scrollUntilVisibleText(tester, '已保存的账号（3）');
    expect(find.text('已保存的账号（3）'), findsOneWidget);
    expect(find.text('new-model · https://new.example.com'), findsOneWidget);
  });

  testWidgets('#M6 点击账号行 → 编辑模式（表单载入该账号）', (tester) async {
    await seedAccounts(db);
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kimi 备选'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      'sk-kimi',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'https://api.moonshot.cn/v1',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'kimi-k3',
    );
  });

  testWidgets('#M3 子页删除非默认账号 → 确认后列表 -1', (tester) async {
    await seedAccounts(db);
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    // Kimi 备选行的删除按钮（at(0)=DeepSeek 行，at(1)=Kimi 行）
    await tester.tap(find.byIcon(Icons.delete_outline).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('账号已删除'), findsOneWidget);
    expect(find.text('已保存的账号（1）'), findsOneWidget);
    expect(find.text('Kimi 备选'), findsNothing);
  });

  testWidgets('#M5 子页设默认 → 默认徽标切换', (tester) async {
    await seedAccounts(db);
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.text('设默认'));
    await tester.pumpAndSettle();

    expect(find.text('已设为默认账号'), findsOneWidget);
    // 默认徽标仍只有一个（从 DeepSeek 移到 Kimi）
    expect(find.text('默认'), findsOneWidget);
    // 落库判据：默认标记落在 Kimi 行上（账号**名**不改，只改 is_default）
    final accounts = await AIAccountRepository(db).listAccounts();
    expect(accounts.where((a) => a.isDefault).single.name, 'Kimi 备选');
  });

  testWidgets('#E2 Key 指引：平台路径 + 费用一句话', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await scrollAndTap(tester, '如何获取 API Key →');
    expect(find.text('如何获取 API Key'), findsOneWidget);
    expect(find.textContaining('platform.deepseek.com'), findsOneWidget);
    expect(find.textContaining('账户余额'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('如何获取 API Key'), findsNothing);
  });

  testWidgets('#E2b 免费获取入口在本页可见（通往 free-tier-guide 子页）', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await scrollUntilVisibleText(tester, '免费获取 API Key →');
    expect(find.text('免费获取 API Key →'), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════
  // X 批：连接测试**抛异常**路径（_setConnFailed，api_config_page.dart:342）
  //
  // ★ 为什么这两条最要紧：`_setConnFailed` 是两个 handler **共用**的失败态，
  //   而此前只测了 `result.success == false`（正常返回失败）。异常路径一旦
  //   漏测，catch 被误删时界面会静默停在「测试中」（spinner 永不收敛），
  //   且用户看不到任何原因 —— 这类退化不会被现有 21 条里的任何一条抓到。
  // ══════════════════════════════════════════════════════════════

  testWidgets('#X1 「测试连接」遇异常 → 失败态（共用 _setConnFailed）', (tester) async {
    final llm = _FakeLlmClient()..throwOnTest = true;
    await tester.pumpWidget(buildPage(llm: llm));
    await tester.pumpAndSettle();

    await fillForm(tester);
    await scrollAndTap(tester, '测试连接');

    // 异常被归一为失败态，而不是把异常抛到框架（红屏）或静默卡在 spinner。
    expect(find.textContaining('✗ 测试失败'), findsOneWidget);
    // ★ 负例：不得出现成功态（否则说明 catch 里把失败当成功写了）。
    expect(find.textContaining('✓'), findsNothing);
  });

  testWidgets('#X2 「测试并保存」遇异常 → 失败态且**不落库**（共用 _setConnFailed）', (
    tester,
  ) async {
    final llm = _FakeLlmClient()..throwOnTest = true;
    await tester.pumpWidget(buildPage(llm: llm));
    await tester.pumpAndSettle();

    await fillForm(tester);
    await scrollAndTap(tester, '测试并保存');

    expect(find.textContaining('✗ 测试失败'), findsOneWidget);
    // ★ 关键判据：异常 ≠ 通过，绝不能写库（否则又造一个僵尸账号，
    //   与 #B5-2「返回失败不落库」是同一条产品承诺的另一条触发路径）。
    expect(
      await AIAccountRepository(db).listAccounts(),
      isEmpty,
      reason: '连接测试抛异常时不得视为通过而落库',
    );
  });

  // ══════════════════════════════════════════════════════════════
  // X 批：三个 catch 分支的失败文案（此前一条未覆盖）
  //
  // 这三条 catch 都是「用户已点下按钮但什么都没发生」的唯一可感知补偿，
  // 漏测 ⇒ 线上写库失败时界面**完全无反馈**（用户只会以为按钮坏了）。
  // ══════════════════════════════════════════════════════════════

  testWidgets('#X3 保存配置写库失败 → 「保存失败，请稍后再试」（:227）', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await fillForm(tester);
    await breakAccountTable(); // DB 写路径真抛
    await scrollAndTap(tester, '保存配置');

    expect(find.text('保存失败，请稍后再试'), findsOneWidget);
    // 负例：不得同时报成功（否则用户以为已存）。
    expect(find.text('API 配置已保存'), findsNothing);
  });

  testWidgets('#X4 设默认失败 → 「操作失败，请稍后再试」（:464）', (tester) async {
    await seedAccounts(db);
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await breakAccountTable(); // setDefault 的事务更新会真抛
    await tester.tap(find.text('设默认'));
    await tester.pumpAndSettle();

    expect(find.text('操作失败，请稍后再试'), findsOneWidget);
    expect(find.text('已设为默认账号'), findsNothing, reason: '失败不得报成功');
  });

  testWidgets('#X5 删除最后账号被拒 → 「删除失败：至少保留一个账号」（:502）', (tester) async {
    // ★ 只种**一个**账号：走 `AIAccountRepository.deleteAccount` 里
    //   `if (accounts.length <= 1) throw LastAccountException()` 这条
    //   **真实**拒绝路径（不是造异常），与设置页 #M4 同源但在本页验文案。
    await AIAccountRepository(db).createAccount(
      name: '唯一账号',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-v4-flash',
      apiKey: 'sk-only',
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除失败：至少保留一个账号'), findsOneWidget);
    // 负例：账号必须还在（这条文案正是「拒绝了删除」的证据）。
    expect(await AIAccountRepository(db).listAccounts(), hasLength(1));
  });

  // ── X6：「免费获取 API Key →」真跳转（此前只断言了文案可见）──

  testWidgets('#X6 点「免费获取 API Key →」→ 真跳free-tier-guide 子页', (tester) async {
    // ★ 必须用**真 router**：`context.push` 挂在 GoRouter 上，裸 MaterialApp
    //   里点它只会抛 "No GoRouter found"（⇒ 假红）；而若改用「断言 push
    //   被调用」的替身 router，则路由目标写错（如指向 settings）也照样绿。
    //   故照抄 settings_page_test.dart:779 #R9-3 的 pumpRouter 形状。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: appRouter),
      ),
    );
    await tester.pumpAndSettle();
    appRouter.go(AppRoutes.apiConfig);
    await tester.pumpAndSettle();

    await ensureOnScreen(tester, '免费获取 API Key →');
    await tester.tap(find.text('免费获取 API Key →'));
    await tester.pumpAndSettle();

    // 判据 = 目标页的**独有内容**（引导页正文），不是本页文案。
    expect(find.text('获取步骤'), findsOneWidget, reason: '应已跳到引导页');
    expect(find.text('智谱 GLM'), findsWidgets, reason: '引导页列出官方 free 档清单');
    // ★ 负例：来源页必须已离开（否则「跳转」可能只是叠加、没真导航）。
    expect(find.text('测试并保存'), findsNothing);
  });
}

/// 把指定文本滚进视口（**双向**）。
///
/// `tester.scrollUntilVisible` 只会朝一个方向滚；本页账号列表在表单**上方**，
/// 保存后视口停在底部按钮区 ⇒ 必须能向上滚才能命中列表。
Future<void> scrollUntilVisibleText(WidgetTester tester, String label) async {
  final finder = find.text(label);
  if (finder.evaluate().isNotEmpty) return;
  final listView = find.byType(Scrollable).first;
  // 先向上滚（账号列表在表单**上方**，保存后视口停在底部按钮区）。
  // dragUntilVisible 的 offset 是「拖动方向」：负值 = 内容下移 = 视口上移。
  try {
    await tester.dragUntilVisible(finder, listView, const Offset(0, -200));
    await tester.pumpAndSettle();
  } catch (_) {
    // 已到顶部仍找不到 → 交给 expect 判定失败
  }
  if (finder.evaluate().isNotEmpty) return;
  // 再向下找（控件在按钮区时走这条）
  try {
    await tester.dragUntilVisible(finder, listView, const Offset(0, 200));
    await tester.pumpAndSettle();
  } catch (_) {
    // 已到边界且仍找不到 → 交给 expect 判定失败
  }
}

/// 把指定文本滚到**可点**位置（`scrollUntilVisibleText` 的加强版）。
///
/// ★ 为什么需要加强版：`scrollUntilVisibleText` 只保证控件**被构建**
///   （`finder.evaluate().isNotEmpty`），而 ListView 惰性构建会让视口外
///   上下各多构建一屏 ⇒ 控件 find得到、却**点在视口外**。
///   实测踩坑：#X6 首跑报
///   `derived an Offset(400.0, 698.0) ... outside the bounds of ... Size(800.0, 600.0)`
///   —— 控件在 y=698、视口高 600，`tap` 静默不生效，后续断言全红。
///   故这里在构建后再 `ensureVisible` + 校验中心点真在视口内。
Future<void> ensureOnScreen(WidgetTester tester, String label) async {
  await scrollUntilVisibleText(tester, label);
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final viewport =
      tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final center = tester.getCenter(finder);
  expect(
    center.dy,
    inInclusiveRange(0, viewport),
    reason: '「$label」滚动后仍不在视口内（center=$center, viewport=$viewport）',
  );
}
