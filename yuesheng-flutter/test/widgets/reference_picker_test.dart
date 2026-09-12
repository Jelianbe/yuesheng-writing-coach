// ─────────────────────────────────────────────────────────────
// ReferencePicker widget 测试 — 引用选择器
//
// 覆盖路径：
//   1. 无稿件 → 空态
//   2. 「引用整本书」→ onSelect('manuscript', msId, title) + 关闭
//   3. 展开章节 → 点章节 → onSelect('chapter', chId, title)
//   4. 素材 Tab → 点素材 → onSelect('file', fileId, title)
//   5. 取消 → 关闭且不触发 onSelect
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/reference_picker.dart';

// ── 契约扫描 helper（抗文件搬迁：锚定「语义」而非「硬编码文件路径」） ──────────

/// 包根定位：从 cwd 向上回溯，直到同时存在 lib/ 与 test/。
Directory _findPackageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (Directory('${dir.path}/lib').existsSync() &&
        Directory('${dir.path}/test').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError('找不到包根目录（cwd=${Directory.current.path}）');
}

final Directory _root = _findPackageRoot();

String _readSrc(String relPath) {
  final f = File('${_root.path}/$relPath');
  if (!f.existsSync()) {
    throw StateError('源文件不存在：$relPath（root=${_root.path}）');
  }
  return f.readAsStringSync();
}

/// lib/ 下全部 .dart 的相对路径（正斜杠、排序稳定），排除生成文件。
List<String> _listLibDartFiles() {
  final libDir = Directory('${_root.path}/lib');
  return libDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart'))
      .where((p) => !p.endsWith('.g.dart') && !p.endsWith('.freezed.dart'))
      .map((p) => p.substring(_root.path.length + 1).replaceAll('\\', '/'))
      .toList()
    ..sort();
}

/// 去掉整行注释（避免把注释里的示例代码当成真实回调）。
String _stripLineComments(String src) => src
    .split('\n')
    .where((line) {
      final t = line.trimLeft();
      return !(t.startsWith('//') || t.startsWith('*') || t.startsWith('/*'));
    })
    .join('\n');

bool _isWs(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

/// 跳过字符串字面量，返回闭合引号下标（处理 `\` 转义；找不到则到末尾）。
int _skipString(String src, int start) {
  final quote = src[start];
  var i = start + 1;
  while (i < src.length) {
    if (src[i] == '\\') {
      i += 2;
      continue;
    }
    if (src[i] == quote) return i;
    i++;
  }
  return src.length - 1;
}

/// 从 [start]（内容是 [open]）起做定界符配对，返回匹配 [close] 的下标；
/// 未找到返回 -1。会跳过字符串字面量与行注释，避免其中的括号 / 花括号
/// 以及 `${...}` 插值干扰配对。
int _matchDelimiter(String src, int start, String open, String close) {
  var depth = 0;
  for (var i = start; i < src.length; i++) {
    final c = src[i];
    if (c == "'" || c == '"') {
      i = _skipString(src, i);
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      final nl = src.indexOf('\n', i);
      if (nl < 0) return -1;
      i = nl;
      continue;
    }
    if (c == open) depth++;
    if (c == close) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// 提取源码中**内联** `onSelect:` 回调体（函数字面量）。
///
/// 「内联回调体」= `onSelect:` 后紧跟 `(` 参数列表，再接 `{ ... }` 块体
/// 或 `=> ...` 箭头体。自动**跳过**（它们不是回调体）：
///   - 字段 / 构造形参声明（`final ... onSelect;` / `required this.onSelect,`）
///   - 引用传递（`onSelect: _handler,` —— 无 `(` 参数列表）
List<String> _inlineOnSelectBodies(String src) {
  final code = _stripLineComments(src);
  final bodies = <String>[];
  final head = RegExp(r'\bonSelect\s*:\s*\(');
  for (final m in head.allMatches(code)) {
    final openParen = m.end - 1; // 指向 '('
    final closeParen = _matchDelimiter(code, openParen, '(', ')');
    if (closeParen < 0) continue;
    var i = closeParen + 1;
    while (i < code.length && _isWs(code.codeUnitAt(i))) {
      i++;
    }
    // 可选的 async / async* 修饰符
    if (code.startsWith('async', i)) {
      i += 5;
      if (i < code.length && code[i] == '*') i++;
      while (i < code.length && _isWs(code.codeUnitAt(i))) {
        i++;
      }
    }
    if (i >= code.length) continue;
    if (code[i] == '{') {
      final end = _matchDelimiter(code, i, '{', '}');
      if (end > 0) bodies.add(code.substring(i, end + 1));
    } else if (code.startsWith('=>', i)) {
      // 箭头体：取到所在语句结束（分号或行尾）——足以捕获同段的 pop
      var j = i + 2;
      while (j < code.length && code[j] != ';' && code[j] != '\n') {
        j++;
      }
      bodies.add(code.substring(i, j));
    }
  }
  return bodies;
}

/// 返回「回调体内含 `Navigator.pop`」的 onSelect 回调体（空 = 合规）。
List<String> _onSelectBodiesContainingPop(String src) => _inlineOnSelectBodies(
  src,
).where((b) => b.contains('Navigator.pop')).toList();

void main() {
  late AppDatabase db;
  late ManuscriptRepository msRepo;
  late ChapterRepository chRepo;
  late ReferenceRepository refRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    msRepo = ManuscriptRepository(db);
    chRepo = ChapterRepository(db);
    refRepo = ReferenceRepository(db);
  });

  tearDown(() async => db.close());

  Widget buildHost(
    void Function(String refType, String refId, String title)? onSelect,
  ) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ReferencePicker(onSelect: onSelect),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openPicker(
    WidgetTester tester,
    void Function(String refType, String refId, String title)? onSelect,
  ) async {
    await tester.pumpWidget(buildHost(onSelect));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('#1 无稿件 → 作品 Tab 空态', (tester) async {
    await openPicker(tester, null);

    expect(find.text('选择引用'), findsOneWidget);
    expect(find.text('还没有作品'), findsOneWidget);
  });

  testWidgets('#2 「引用整本书」→ onSelect(manuscript) + 弹层关闭', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说', genre: '小说');
    String? gotType;
    String? gotId;
    String? gotTitle;

    await openPicker(tester, (t, id, title) {
      gotType = t;
      gotId = id;
      gotTitle = title;
    });

    expect(find.text('测试小说'), findsOneWidget);
    await tester.tap(find.text('引用整本书'));
    await tester.pumpAndSettle();

    expect(gotType, 'manuscript');
    expect(gotId, msId);
    expect(gotTitle, '测试小说');
    expect(find.text('选择引用'), findsNothing);
  });

  testWidgets('#3 展开章节 → 点章节 → onSelect(chapter)', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    final chId = await chRepo.createChapter(
      msId,
      title: '第一章 启程',
      content: '正文',
      sortOrder: 1,
    );
    String? gotType;
    String? gotId;

    await openPicker(tester, (t, id, title) {
      gotType = t;
      gotId = id;
    });

    // 展开稿件行
    await tester.tap(find.text('测试小说'));
    await tester.pumpAndSettle();

    expect(find.text('第一章 启程'), findsOneWidget);
    await tester.tap(find.text('第一章 启程'));
    await tester.pumpAndSettle();

    expect(gotType, 'chapter');
    expect(gotId, chId);
    expect(find.text('选择引用'), findsNothing);
  });

  testWidgets('#4 素材 Tab → 点素材 → onSelect(file)', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    final file = await refRepo.createAttachedFile(
      bookId: msId,
      fileName: '大纲.txt',
      fileRole: 'outline',
      content: '第一卷内容',
    );
    String? gotType;
    String? gotId;

    await openPicker(tester, (t, id, title) {
      gotType = t;
      gotId = id;
    });

    // 切到素材 Tab，展开稿件组后显示文件
    await tester.tap(find.text('素材'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试小说'));
    await tester.pumpAndSettle();

    expect(find.text('大纲.txt'), findsOneWidget);
    await tester.tap(find.text('大纲.txt'));
    await tester.pumpAndSettle();

    expect(gotType, 'file');
    expect(gotId, file.id);
    expect(find.text('选择引用'), findsNothing);
  });

  testWidgets('#4b 批次77 素材 Tab 无素材 → 空态文案指向真实路径', (tester) async {
    // 无任何素材文件：作品 Tab 至少需要一篇作品才能切 Tab，但素材为空
    await msRepo.createManuscript(title: '测试小说');

    await openPicker(tester, null);

    await tester.tap(find.text('素材'));
    await tester.pumpAndSettle();

    expect(find.text('还没有素材文件'), findsOneWidget);
    // 批次77：不再指向不存在的「素材页」，改真实路径
    expect(find.text('在作品详情的「文件」中添加素材文件'), findsOneWidget);
    expect(find.textContaining('素材页'), findsNothing);
  });

  testWidgets('#5 取消 → 关闭且不触发 onSelect', (tester) async {
    await msRepo.createManuscript(title: '测试小说');
    var called = false;

    await openPicker(tester, (t, id, title) => called = true);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('选择引用'), findsNothing);
  });

  testWidgets('#6 mention 模式：显示路径徽章 + 选择回调 @路径', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    final chId = await chRepo.createChapter(
      msId,
      title: '第一章',
      content: '正文',
      sortOrder: 0,
    );
    String? gotPath;
    String? gotTitle;

    // mention 模式宿主
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ReferencePicker(
                      mode: 'mention',
                      onSelectMention: (path, title) {
                        gotPath = path;
                        gotTitle = title;
                      },
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 作品行显示 @测试小说 徽章（批次71：编号 @W001 → 文字标题）
    expect(find.text('@测试小说'), findsOneWidget);

    // 展开 → 章节徽章 @测试小说/第一章
    await tester.tap(find.text('测试小说'));
    await tester.pumpAndSettle();
    expect(find.text('@测试小说/第一章'), findsOneWidget);

    // 选章节 → 回调 @路径
    await tester.tap(find.text('第一章'));
    await tester.pumpAndSettle();

    expect(gotPath, '@测试小说/第一章');
    expect(gotTitle, '测试小说 · 第一章');
    expect(find.text('选择引用'), findsNothing);
  });

  testWidgets('批次97 分卷作品：卷行=选中卷，箭头=展开卷内章节', (tester) async {
    final msId2 = await msRepo.createManuscript(title: '长篇');
    final volRepo = VolumeRepository(db);
    final volId = await volRepo.createVolume(msId2, title: '第一卷');
    final chId2 = await chRepo.createChapter(msId2, title: '开篇');
    await volRepo.setChapterVolume(chId2, volId);
    final ungroupedId = await chRepo.createChapter(msId2, title: '番外');
    // 未分卷章节
    await volRepo.setChapterVolume(ungroupedId, null);

    String? gotPath;
    String? gotTitle;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ReferencePicker(
                      mode: 'mention',
                      onSelectMention: (path, title) {
                        gotPath = path;
                        gotTitle = title;
                      },
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 展开作品 → 卷行 + 卷徽章 @长篇/第一卷
    await tester.tap(find.text('长篇'));
    await tester.pumpAndSettle();
    expect(find.text('第一卷'), findsOneWidget);
    expect(find.text('@长篇/第一卷'), findsOneWidget);
    // 未分卷组标题
    expect(find.textContaining('未分卷'), findsOneWidget);

    // 点箭头展开 → 卷内章节（不触发选中回调）
    await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
    await tester.pumpAndSettle();
    expect(find.text('开篇'), findsOneWidget);
    expect(gotPath, isNull);

    // 选卷内章节 → 回调三段路径（选中后弹层关闭）
    await tester.tap(find.text('开篇'));
    await tester.pumpAndSettle();
    expect(gotPath, '@长篇/第一卷/开篇');
    expect(gotTitle, '长篇 · 第一卷 · 开篇');

    // 重开弹层：点卷行（非箭头）→ 选中整卷（方案2b：volume 可引用）
    gotPath = null;
    gotTitle = null;
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('长篇'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一卷'));
    await tester.pumpAndSettle();
    expect(gotPath, '@长篇/第一卷');
    expect(gotTitle, '长篇 · 第一卷');
  });

  test('契约：default 模式 onSelect 回调不得重复 pop（picker 已负责关闭）', () {
    // 2026-09-07 实证：某消费点的 onSelect 回调曾执行 Navigator.pop(sheetCtx)，
    // 与 reference_picker._handleSelect 内的 pop 构成 double-pop，损坏
    // Overlay/Navigator 状态 → 真实设备黑屏（widget test 无 GPU 渲染，测不出；
    // 故用源码契约护栏）。
    //
    // ⚠️ 锚定方式（2026 伪拆分清偿后）：已从「硬编码具体文件路径」
    // 改为「**全 lib 自适应发现内联 onSelect 回调体**」，抗文件搬迁 / 改名 / 拆分。
    // 契约语义：调用 ReferencePicker 时，其 onSelect 回调**自身**不得再 pop
    // （picker 的 _handleSelect 已负责关闭）。注意不能在**全库**零容忍
    // `Navigator.pop(sheetCtx)`——picker 外部（自管理菜单，如 chat_header）
    // 的 pop 是合法用法，全库零容忍会误伤。
    final offenders = <String, List<String>>{};
    for (final rel in _listLibDartFiles()) {
      final hits = _onSelectBodiesContainingPop(_readSrc(rel));
      if (hits.isNotEmpty) offenders[rel] = hits;
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'onSelect 回调不得再 pop 选择器（reference_picker._handleSelect 已 pop）\n'
          '违规文件：${offenders.keys.join(', ')}',
    );
  });

  test('契约扫描自检：确实发现了内联 onSelect 回调体（防扫描失效假绿）', () {
    var inlineCount = 0;
    for (final rel in _listLibDartFiles()) {
      inlineCount += _inlineOnSelectBodies(_readSrc(rel)).length;
    }
    expect(
      inlineCount,
      greaterThanOrEqualTo(1),
      reason: '未发现任何内联 onSelect 回调体——扫描逻辑可能已失效，契约护栏形同虚设',
    );
  });

  test('契约扫描自检：能捕获回调体内 pop、且不误伤回调外的合法 pop', () {
    // 变异样本：回调体内 pop → 必须被捕获
    const mutated = '''
      ReferencePicker(
        onSelect: (refType, refId, title) async {
          Navigator.pop(sheetCtx);
        },
      );
    ''';
    expect(_onSelectBodiesContainingPop(mutated), isNotEmpty);

    // 合法样本：pop 在回调体之外（自管理菜单，如 chat_header）→ 不得误伤
    const legalOutside = '''
      showModalBottomSheet<void>(
        builder: (sheetCtx) => Menu(
          onSelect: (v) { onPicked(v); },
        ),
      );
      Navigator.pop(sheetCtx);
    ''';
    expect(_onSelectBodiesContainingPop(legalOutside), isEmpty);

    // 字段声明 / 构造形参 / 引用传递不得被当成回调体
    const decls = '''
      final void Function(String a) onSelect;
      required this.onSelect,
    ''';
    expect(_onSelectBodiesContainingPop(decls), isEmpty);
  });

  test('契约扫描自检：花括号配对能穿过字符串与插值（防体截断漏检）', () {
    const sample = '''
      ReferencePicker(
        onSelect: (a, b) {
          log('前缀 \$a 与 \${b.id} 含 } 花括号');
          if (a != null) {
            Navigator.pop(sheetCtx);
          }
        },
      );
    ''';
    expect(_onSelectBodiesContainingPop(sample), isNotEmpty);
  });
}
