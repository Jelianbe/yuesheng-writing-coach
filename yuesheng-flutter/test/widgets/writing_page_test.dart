// ─────────────────────────────────────────────────────────────
// WritingPage widget 测试 — 写作页 4 层结构
//
// 覆盖路径：
//   #1 加载章节 → AppBar 显示章节标题 + 字数
//   #2 编辑器显示章节内容
//   #3 编辑器背景色为 #F5F1E8（米纸底）
//   #4 ⋮ 按钮 → 点击 → 菜单 sheet 出现
//   #5 FAB 存在（图标 chat_bubble_outline）
//   #6 输入文本 → 字数更新
//   #7 返回按钮 → 触发 onBack
//   #8 章节不存在 → 显示错误
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';
import 'package:writingcoach/config/app_theme.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/providers/writing_providers.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/realtime_observation_service.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/chapter_tree_drawer.dart';
import 'package:writingcoach/widgets/punctuation_bar.dart';
import 'package:writingcoach/widgets/recycle_bin_sheet.dart';
import 'package:writingcoach/widgets/search_replace_sheet.dart';
import 'package:writingcoach/widgets/selection_ai_sheet.dart';
import 'package:writingcoach/widgets/version_time_machine_sheet.dart';
import 'package:writingcoach/widgets/writing_coach_panel.dart';
import 'package:writingcoach/widgets/writing_curve_chart.dart';
import 'package:writingcoach/widgets/writing_page.dart';
import 'package:writingcoach/widgets/editing/focus_aware_editing_controller.dart';

import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;

/// 测试用 Fake LLM：预设 streamChat / chatCompletion 响应
/// （复用 writing_coach_panel_test 模式；批次83 择选弹层走非流式 chatCompletion）
class FakeLlmClient extends LlmClient {
  final String fullResponse;
  final Exception? error;

  /// 非流式响应队列（择选生成按调用次数依次取，取尽后复用最后一条）
  final List<String> chatResponses;
  int _chatCallCount = 0;

  FakeLlmClient(this.fullResponse, {this.error, List<String>? chatResponses})
    : chatResponses = chatResponses ?? const [];

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
  }) async {
    if (error != null) throw error!;
    if (chatResponses.isEmpty) return fullResponse;
    final index = _chatCallCount < chatResponses.length
        ? _chatCallCount
        : chatResponses.length - 1;
    _chatCallCount++;
    return chatResponses[index];
  }

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    if (error != null) throw error!;

    const chunkSize = 10;
    for (int i = 0; i < fullResponse.length; i += chunkSize) {
      final end = i + chunkSize < fullResponse.length
          ? i + chunkSize
          : fullResponse.length;
      callback(
        LlmStreamResponse(
          content: fullResponse.substring(i, end),
          isDone: false,
        ),
      );
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// 批次60：保存失败模拟 store（saveNow 恒失败，用于验证失败提示 UI）
class _FailingSaveStore extends WritingStore {
  _FailingSaveStore(AppDatabase db, String chapterId) : super(db, chapterId);

  @override
  Future<void> saveNow() async {
    // 与真实 saveNow 失败语义一致：标记 saveError，不切换整页错误视图
    state = state.copyWith(isSaving: false, saveError: '模拟保存失败');
  }
}

/// 批次83：择选弹层两批响应（第一批生成 + 第二批换一换）
const String _v1s =
    '【版本一】雪地旅人裹紧了大衣，脚步更快了。\n【版本二】大雪里，旅人缩了缩脖子，继续前行。\n【版本三】旅人顶着风雪，一步一步往前走。';
const String _v2s =
    '【版本一】北风里，旅人的围巾被吹得猎猎作响。\n【版本二】旅人停下脚步，望了望灰蒙蒙的天。\n【版本三】雪越下越大，旅人却越走越坚定。';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String chapterId;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    // 预置：创建稿件 + 章节
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    manuscriptId = await msRepo.createManuscript(title: '测试作品');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第一章：启程',
      content: '这是一个大雪纷飞的夜晚。',
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildWritingPage({
    String? id,
    VoidCallback? onBack,
    String? msId,
    void Function(String chapterId, String title)? onJumpToChapter,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: WritingPage(
          chapterId: id ?? chapterId,
          manuscriptId: msId,
          onBack: onBack,
          onJumpToChapter: onJumpToChapter,
        ),
      ),
    );
  }

  /// 批次82-④：以指定容器泵写作页（批次83 各组合用）
  Future<void> pumpWithContainer(
    WidgetTester tester,
    ProviderContainer c, {
    required String id,
    String? msId,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: WritingPage(chapterId: id, manuscriptId: msId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 批次83：构造带择选响应（非流式 chatCompletion）的容器
  ProviderContainer buildSelectionContainer(List<String> chatResponses) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llmClientProvider.overrideWithValue(
          FakeLlmClient('已收到，我来看一下。', chatResponses: chatResponses),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// 批次88-2：菜单已 16 项，底部项在滚动区外 → 打开菜单（若已开则复用）+ 滚动到可见后点击
  Future<void> tapMenuScrolled(WidgetTester tester, String label) async {
    if (find.byType(BottomSheet).evaluate().isEmpty) {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }
    final target = find.text(label);
    await tester.scrollUntilVisible(
      target,
      80,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// 批次87-4：菜单底部项「版本时光机」在滚动区外 → 滚动后点击
  Future<void> openTimeMachineMenu(WidgetTester tester) async {
    await tapMenuScrolled(tester, '版本时光机');
  }

  group('WritingPage', () {
    testWidgets('#1 加载章节 → AppBar 显示章节标题 + 字数', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 批次95-4：AppBar 面包屑（未分卷仅章名）+ 标题大区块 → 共 2 处
      expect(find.text('第一章：启程'), findsNWidgets(2));
      // 内容 "这是一个大雪纷飞的夜晚。" = 12 字符（含句号）
      expect(find.text('12字'), findsOneWidget);
    });

    testWidgets('#2 编辑器显示章节内容', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 批次90：页面有标题+正文两个 TextField → 正文用 key
      final textField = tester.widget<TextField>(
        find.byKey(const Key('chapterContentField')),
      );
      expect(textField.controller?.text, '这是一个大雪纷飞的夜晚。');
    });

    testWidgets('#3 编辑器背景色为 #F5F1E8（米纸底）', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      final colored = find.byWidgetPredicate(
        (w) => w is Container && w.color == const Color(0xFFF5F1E8),
      );
      expect(colored, findsOneWidget);
    });

    testWidgets('#4 ⋮ 按钮 → 点击 → 菜单 sheet 出现', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // E3：占位项已移除，菜单只保留「打开教练面板」（批次79 B 由「诊断本章」改名）
      expect(find.text('打开教练面板'), findsOneWidget);
    });

    testWidgets('#5 FAB 存在（图标 chat_bubble_outline）', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });

    testWidgets('#6 输入文本 → 字数更新', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 初始字数 12字
      expect(find.text('12字'), findsOneWidget);

      // 输入 "测试" 替换内容
      await tester.enterText(
        find.byKey(const Key('chapterContentField')),
        '测试',
      );
      await tester.pump();

      // 字数应为 2字
      expect(find.text('2字'), findsOneWidget);
    });

    testWidgets('#7 返回按钮 → 触发 onBack', (tester) async {
      bool backCalled = false;
      await tester.pumpWidget(
        buildWritingPage(onBack: () => backCalled = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(backCalled, isTrue);
    });

    testWidgets('#8 章节不存在 → 显示错误', (tester) async {
      await tester.pumpWidget(buildWritingPage(id: 'nonexistent'));
      await tester.pumpAndSettle();

      expect(find.textContaining('章节不存在'), findsOneWidget);
    });

    // ── B3: 划词诊断（选中 → 浮动菜单 → 校验 → 注入面板） ──

    testWidgets('#9 B3 选中文本 → 浮动菜单「诊断这段文字」出现', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 选中章节内容（12 字）→ 浮动菜单出现
      // 批次90：页面有标题+正文两个 TextField → 正文用 key 定位
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const Key('chapterContentField')),
          matching: find.byType(EditableText),
        ),
      );
      editable.updateEditingValue(
        TextEditingValue(
          text: editable.textEditingValue.text,
          selection: const TextSelection(baseOffset: 0, extentOffset: 12),
        ),
      );
      await tester.pump();

      expect(find.text('诊断这段文字'), findsOneWidget);
    });

    testWidgets('#10 B3 取消选中（光标）→ 浮动菜单消失', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 先选中 → 菜单出现
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const Key('chapterContentField')),
          matching: find.byType(EditableText),
        ),
      );
      editable.updateEditingValue(
        TextEditingValue(
          text: editable.textEditingValue.text,
          selection: const TextSelection(baseOffset: 0, extentOffset: 12),
        ),
      );
      await tester.pump();
      expect(find.text('诊断这段文字'), findsOneWidget);

      // 取消选中（collapsed）→ 菜单消失
      editable.updateEditingValue(
        TextEditingValue(
          text: editable.textEditingValue.text,
          selection: const TextSelection.collapsed(offset: 0),
        ),
      );
      await tester.pump();

      expect(find.text('诊断这段文字'), findsNothing);
    });

    testWidgets('#11 B3 选中 <20 字 → 点击菜单 → SnackBar 拦截', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 选中章节内容（12 字 <20）
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const Key('chapterContentField')),
          matching: find.byType(EditableText),
        ),
      );
      editable.updateEditingValue(
        TextEditingValue(
          text: editable.textEditingValue.text,
          selection: const TextSelection(baseOffset: 0, extentOffset: 12),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('诊断这段文字'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('请至少选择 20 字以上的文本进行诊断'), findsOneWidget);
    });

    // ── 批次 24 B7: 撤销/重做（批次96-10 起：标点栏常驻唯一入口，AppBar 已去除） ──

    testWidgets('#12 B7 AppBar 无撤销/重做；标点栏撤销/重做常驻可点', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 批次96-10：AppBar 不再有撤销/重做（入口收敛，标点栏兜底）
      expect(
        find.widgetWithIcon(IconButton, Icons.undo),
        findsNothing,
        reason: 'AppBar 撤销入口已移除',
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.redo),
        findsNothing,
        reason: 'AppBar 重做入口已移除',
      );
      // 标点栏最前两位常驻撤销/重做（不随 visibleIds 配置隐藏）
      final bar = find.byType(PunctuationBar);
      expect(
        find.descendant(of: bar, matching: find.byIcon(Icons.undo)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.byIcon(Icons.redo)),
        findsOneWidget,
      );
    });

    testWidgets('#13 B7 编辑后撤销可用 → 点击标点栏撤销回退内容', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 输入新内容（触发 updateContent + 历史 debounce）
      await tester.enterText(
        find.byKey(const Key('chapterContentField')),
        '新编辑的内容',
      );
      await tester.pump();

      // 等待历史 debounce（1.5s，批次91-2 撤销栈独立）→ canUndo=true
      await tester.pump(const Duration(milliseconds: 1600));

      // 点击撤销（批次96-10：标点栏常驻撤销为唯一入口，限定在 PunctuationBar 内）
      final undoIcon = find.descendant(
        of: find.byType(PunctuationBar),
        matching: find.byIcon(Icons.undo),
      );
      expect(undoIcon, findsOneWidget);
      await tester.tap(undoIcon);
      await tester.pump();

      final textField = tester.widget<TextField>(
        find.byKey(const Key('chapterContentField')),
      );
      expect(textField.controller?.text, '这是一个大雪纷飞的夜晚。');
    });

    // ── 批次 36: 章节标题栏（AppBar 内可编辑，输入即保存） ──

    testWidgets('#14 批次36 正文上方存在可编辑标题输入框（初始为章节标题）', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 批次88-1：标题移出 AppBar，改为正文上方独立标题行（Key('chapterTitleField')）
      // 批次90：升级为独立大区块（28sp w800）
      final titleField = tester.widget<TextField>(
        find.byKey(const Key('chapterTitleField')),
      );
      expect(titleField.controller?.text, '第一章：启程');
      // 标题独立大块（字号 28、加粗）
      expect(titleField.style?.fontSize, 28);
      expect(titleField.style?.fontWeight, FontWeight.w800);
      // 输入框可编辑（非只读）
      expect(titleField.readOnly, isFalse);
    });

    testWidgets('#15 批次36 修改标题 → 即时保存落库（对齐 RN handleTitleChange）', (
      tester,
    ) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      final titleFinder = find.byKey(const Key('chapterTitleField'));
      await tester.enterText(titleFinder, '第一章：新的征程');
      // 等待异步 DB 保存完成
      await tester.pumpAndSettle();

      // 1) state 同步：标题输入框显示新值
      expect(
        tester.widget<TextField>(titleFinder).controller?.text,
        '第一章：新的征程',
      );
      // 2) DB 落库
      final repo = ChapterRepository(db);
      final chapter = await repo.getChapter(chapterId);
      expect(chapter?.title, '第一章：新的征程');
    });

    // ── 批次 60: 保存状态可见 + 失败反馈 ──

    testWidgets('#16 批次60 编辑保存成功 → 底部出现「已保存」指示', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 从未保存 → 无状态条
      expect(find.textContaining('已保存'), findsNothing);

      // 输入内容 → 300ms 合并保存（批次91-1）→ 显示「已保存 HH:MM」
      await tester.enterText(
        find.byKey(const Key('chapterContentField')),
        '新的内容',
      );
      // 推进保存 debounce（pumpAndSettle 不推进 Timer，需显式 pump 到期）
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.textContaining('已保存'), findsOneWidget);
    });

    testWidgets('#17 批次60 保存失败 → 状态条「保存失败」+ SnackBar 提示', (tester) async {
      final failingContainer = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          writingStoreProvider(
            chapterId,
          ).overrideWith((ref) => _FailingSaveStore(db, chapterId)),
        ],
      );
      addTearDown(failingContainer.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: failingContainer,
          child: MaterialApp(home: WritingPage(chapterId: chapterId)),
        ),
      );
      await tester.pumpAndSettle();

      // 输入触发保存（300ms 合并 debounce，批次91-1）→ store 失败 → 状态条 + SnackBar 提示
      await tester.enterText(
        find.byKey(const Key('chapterContentField')),
        '触发保存失败',
      );
      // 推进保存 debounce（pumpAndSettle 不推进 Timer，需显式 pump 到期）
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('保存失败，请稍后重试'), findsOneWidget);
      expect(find.text('刚才的内容没能保存成功，请稍后重试'), findsOneWidget);

      // 推进 B7 历史提交 debounce（1.5s，批次91-2）与 SnackBar 自动关闭，避免结束 pending timer
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
    });

    testWidgets('#18 批次79 A 划词诊断 → 关面板重开 → 不重复诊断旧选段', (tester) async {
      // 预置 ≥20 字章节（setUp 默认章节仅 12 字，划词诊断校验下限 20 字）
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '长文测试');
      final longChapterId = await chRepo.createChapter(
        msId,
        title: '长章',
        content:
            '这是一个大雪纷飞的夜晚，北风呼啸着穿过空旷的原野，远处的山峦在暮色中显得格外孤寂。一位旅人独自走在雪地里，身后留下一串深深浅浅的脚印。',
      );

      // 注入 fake LLM，避免真实网络调用
      final container2 = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          chatServiceProvider.overrideWith((ref) {
            return ChatService(
              sessionRepo: SessionRepository(db),
              stateRepo: TeachingStateRepository(db),
              diagnosisRepo: DiagnosisRepository(db),
              studentModelRepo: StudentModelRepository(db),
              referenceRepo: ReferenceRepository(db),
              chapterRepo: ChapterRepository(db),
              manuscriptRepo: ManuscriptRepository(db),
              llmClient: FakeLlmClient('诊断完成。本章结构清晰。'),
              teacherSuggestionRepo: TeacherSuggestionRepository(db),
              editorObservationRepo: EditorObservationRepository(db),
              // ADR-C74 K-5：诊断提交编排器收紧为 required
              diagnosisCommitter: DiagnosisCommitter(
                sessionRepo: SessionRepository(db),
                stateRepo: TeachingStateRepository(db),
                diagnosisRepo: DiagnosisRepository(db),
                studentModelRepo: StudentModelRepository(db),
                referenceRepo: ReferenceRepository(db),
                chapterRepo: ChapterRepository(db),
              ),

              messageInjector: MessageInjector(
                sessionRepo: SessionRepository(db),

                diagnosisRepo: DiagnosisRepository(db),

                studentModelRepo: StudentModelRepository(db),

                referenceRepo: ReferenceRepository(db),

                chapterRepo: ChapterRepository(db),

                manuscriptRepo: ManuscriptRepository(db),

                diagnosisCommitter: DiagnosisCommitter(
                  sessionRepo: SessionRepository(db),

                  stateRepo: TeachingStateRepository(db),

                  diagnosisRepo: DiagnosisRepository(db),

                  studentModelRepo: StudentModelRepository(db),

                  referenceRepo: ReferenceRepository(db),

                  chapterRepo: ChapterRepository(db),
                ),

                material: const MaterialCapabilityImpl(),
              ),
              diagnosisFlowHandler: DiagnosisFlowHandler(
                sessionRepo: SessionRepository(db),
                stateRepo: TeachingStateRepository(db),
                diagnosisRepo: DiagnosisRepository(db),
                studentModelRepo: StudentModelRepository(db),
                referenceRepo: ReferenceRepository(db),
                chapterRepo: ChapterRepository(db),
                teacherSuggestionRepo: TeacherSuggestionRepository(db),
                llmClient: FakeLlmClient('诊断完成。本章结构清晰。'),

                messageInjector: MessageInjector(
                  sessionRepo: SessionRepository(db),

                  diagnosisRepo: DiagnosisRepository(db),

                  studentModelRepo: StudentModelRepository(db),

                  referenceRepo: ReferenceRepository(db),

                  chapterRepo: ChapterRepository(db),

                  manuscriptRepo: ManuscriptRepository(db),

                  diagnosisCommitter: DiagnosisCommitter(
                    sessionRepo: SessionRepository(db),

                    stateRepo: TeachingStateRepository(db),

                    diagnosisRepo: DiagnosisRepository(db),

                    studentModelRepo: StudentModelRepository(db),

                    referenceRepo: ReferenceRepository(db),

                    chapterRepo: ChapterRepository(db),
                  ),

                  material: const MaterialCapabilityImpl(),
                ),
                diagnosisCommitter: DiagnosisCommitter(
                  sessionRepo: SessionRepository(db),
                  stateRepo: TeachingStateRepository(db),
                  diagnosisRepo: DiagnosisRepository(db),
                  studentModelRepo: StudentModelRepository(db),
                  referenceRepo: ReferenceRepository(db),
                  chapterRepo: ChapterRepository(db),
                ),
                diagnosis: const DiagnosisCapabilityImpl(),
                genUi: const GenUiParser(),
              ),
            );
          }),
          realtimeObservationServiceProvider.overrideWith((ref) {
            return RealtimeObservationService(
              llmClient: FakeLlmClient('快速观察反馈。'),
              sessionRepo: SessionRepository(db),
              editorObservationRepo: EditorObservationRepository(db),
            );
          }),
        ],
      );
      addTearDown(container2.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container2,
          child: MaterialApp(
            home: WritingPage(chapterId: longChapterId, manuscriptId: msId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 选中 ≥20 字 → 点「诊断这段文字」→ 面板打开 + 选段诊断触发
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const Key('chapterContentField')),
          matching: find.byType(EditableText),
        ),
      );
      editable.updateEditingValue(
        TextEditingValue(
          text: editable.textEditingValue.text,
          selection: const TextSelection(baseOffset: 0, extentOffset: 20),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('诊断这段文字'));
      await tester.pumpAndSettle();

      expect(find.byType(WritingCoachPanel), findsOneWidget);
      final sessionRepo = SessionRepository(db);
      final sessionId = await sessionRepo.getOrCreateSessionForChapter(
        msId,
        longChapterId,
      );
      Future<int> diagnoseCount() => sessionRepo
          .listMessages(sessionId)
          .then(
            (msgs) => msgs
                .where((m) => m.content.contains('请对以下选中文本进行写作诊断分析'))
                .length,
          );

      expect(await diagnoseCount(), 1, reason: '首次划词诊断应触发 1 条选段诊断');

      // 关闭面板（面板关闭按钮 → onClose）→ 重开（FAB）
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(WritingCoachPanel), findsNothing);
      // 等待诊断完成 SnackBar 消失（自定义 FAB 在 body Stack 内，不会像 Scaffold FAB 一样自动上浮避让）
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('aiChatFab')));
      await tester.pumpAndSettle();
      expect(find.byType(WritingCoachPanel), findsOneWidget);

      // 一次性消费：重开面板不再对旧选段重复诊断
      expect(await diagnoseCount(), 1, reason: '关闭重开面板不应重复诊断旧选段');
    });
  });

  group('批次82：排版设置（P0 四件套之①）', () {
    /// 编辑器正文 TextField（AppBar 标题也是 TextField，需限定在编辑器容器内）
    Finder editorTextField() => find.byKey(const Key('chapterContentField'));

    testWidgets('#82-1 更多菜单 →「排版设置」→ 弹层出现（标题 + 背景预设）', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 打开更多菜单
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('排版设置'), findsOneWidget);
      expect(find.text('打开教练面板'), findsOneWidget);

      // 进入排版设置（菜单已 16 项，滚动到可见后点击）
      await tapMenuScrolled(tester, '排版设置');

      expect(find.text('排版设置'), findsOneWidget);
      expect(find.text('字号'), findsOneWidget);
      expect(find.text('行距'), findsOneWidget);
      expect(find.text('背景'), findsOneWidget);
      // 3 个背景预设（批次 X-037-P0-1 H1：暖白伪选项已移除）
      expect(find.text('米纸'), findsOneWidget);
      expect(find.text('护眼'), findsOneWidget);
      expect(find.text('暗夜'), findsOneWidget);
    });

    testWidgets('#82-2 点「暗夜」→ 编辑器背景/文字色切换 + 落库', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      await tapMenuScrolled(tester, '排版设置');

      await tester.tap(find.text('暗夜'));
      await tester.pumpAndSettle();

      // 编辑器容器背景切换为暗夜
      final editor = tester.widget<Container>(
        find.byKey(const Key('editorContainer')),
      );
      expect(editor.color, const Color(0xFF26282B));
      // 文字色切换为浅色
      final field = tester.widget<TextField>(editorTextField());
      expect(field.style?.color, const Color(0xFFE8EAED));
      // 落库（用户级，跨章节生效）
      final repo = AppStateRepository(db);
      expect(await repo.getValue('editor_background'), 'dark');
    });

    testWidgets('#82-3 拖字号滑条 → 字号变化 + 落库', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      await tapMenuScrolled(tester, '排版设置');

      // 第一个 Slider = 字号（默认 16）
      final before = container.read(writingStoreProvider(chapterId)).fontSize;
      await tester.drag(find.byType(Slider).first, const Offset(80, 0));
      await tester.pumpAndSettle();

      final after = container.read(writingStoreProvider(chapterId)).fontSize;
      expect(after, isNot(before), reason: '拖动字号滑条应改变字号');
      final repo = AppStateRepository(db);
      expect(await repo.getValue('editor_font_size'), after.toString());
    });

    testWidgets('#82-4 设置持久化 → 重建页面恢复（用户级跨章节生效）', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 设置为护眼背景 + 行距 2.0（直接经 store，模拟设置后关闭；批次 X-037-P0-1 H1：暖白已移除，改测护眼）
      container
          .read(writingStoreProvider(chapterId).notifier)
          .setEditorBackground('green');
      container
          .read(writingStoreProvider(chapterId).notifier)
          .setLineSpacing(2.0);
      await container
          .read(writingStoreProvider(chapterId).notifier)
          .persistEditorSettings();

      // 重建页面（同一 chapterId）→ loadChapter 重新加载排版设置
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      final editor = tester.widget<Container>(
        find.byKey(const Key('editorContainer')),
      );
      expect(editor.color, const Color(0xFFE6F0E9), reason: '护眼背景应恢复');
      final field = tester.widget<TextField>(editorTextField());
      expect(field.style?.height, 2.0, reason: '行距应恢复');
    });
  });

  group('批次82：写作目标进度条（P0 四件套之②）', () {
    /// 编辑器正文 TextField（AppBar 标题也是 TextField，需限定在编辑器容器内）
    Finder editorTextField() => find.byKey(const Key('chapterContentField'));

    testWidgets('#82-5 点击字数 → 设置目标 → 显示「当前/目标」+ 进度条 + 章节级落库', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 未设目标：显示「12字」，无进度条
      expect(find.text('12字'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // 点击字数区 → 目标设置对话框
      await tester.tap(find.text('12字'));
      await tester.pumpAndSettle();
      expect(find.text('本章写作目标'), findsOneWidget);

      // 输入目标 100 → 保存
      final goalInput = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(goalInput, '100');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 显示「12/100」+ 进度条出现且进度正确（12/100 = 0.12）
      expect(find.text('12/100'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.12, 0.01));
      // 章节级落库（key = chapter_goal:$chapterId）
      final repo = AppStateRepository(db);
      expect(await repo.getValue('chapter_goal:$chapterId'), '100');
    });

    testWidgets('#82-6 跨过目标线 → SnackBar「目标达成」提示一次，降回线下可再提示', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 预设目标 13（初始 12 字在目标线下，+1 字即跨越）
      await container
          .read(writingStoreProvider(chapterId).notifier)
          .setGoalWords(13);
      await tester.pumpAndSettle();
      expect(find.text('12/13'), findsOneWidget);

      // 输入跨过目标线（≥13 字）→ SnackBar 提示
      await tester.enterText(editorTextField(), '这是一个大雪纷飞的夜晚。雪');
      await tester.pump();
      expect(find.text('本章写作目标达成 🎉'), findsOneWidget);

      // 等第一条 SnackBar 完全关闭（entrance 完成 → 2s 自动关闭 → exit 完成移除）
      await tester.pumpAndSettle(); // 进入动画完成（此后自动关闭定时器才开始计时）
      await tester.pump(const Duration(seconds: 3)); // 触发自动关闭 → 退场动画开始
      await tester.pumpAndSettle(); // 退场动画完成 → SnackBar 移除
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: '第一条 SnackBar 应已自动关闭',
      );

      // 仍在目标线上继续输入 → 不重复提示（_goalCelebrated 已置位）
      await tester.enterText(editorTextField(), '这是一个大雪纷飞的夜晚。雪雪');
      await tester.pump();
      expect(find.text('本章写作目标达成 🎉'), findsNothing);

      // 降回目标线下 → 再跨越 → 可再次提示
      await tester.enterText(editorTextField(), '测试');
      await tester.pump();
      await tester.enterText(editorTextField(), '这是一个大雪纷飞的夜晚。雪');
      await tester.pump();
      expect(find.text('本章写作目标达成 🎉'), findsOneWidget);

      // 收尾：等 SnackBar 关闭，避免 pending timer
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('#82-7 目标持久化 → 重建页面恢复 + 清除目标恢复「X字」', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 直接经 store 设置目标 100（模拟设置后离开）
      await container
          .read(writingStoreProvider(chapterId).notifier)
          .setGoalWords(100);

      // 重建页面 → loadChapter 重新加载目标（章节级持久化）
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      expect(find.text('12/100'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // 点击字数区 → 对话框出现「清除目标」→ 清除 → 恢复「12字」+ 进度条消失
      await tester.tap(find.text('12/100'));
      await tester.pumpAndSettle();
      expect(find.text('清除目标'), findsOneWidget);
      await tester.tap(find.text('清除目标'));
      await tester.pumpAndSettle();
      expect(find.text('12字'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final repo = AppStateRepository(db);
      expect(await repo.getValue('chapter_goal:$chapterId'), '0');
    });
  });

  group('批次82：版本时光机（P0 四件套之③）', () {
    /// 编辑器正文 TextField（AppBar 标题也是 TextField，需限定在编辑器容器内）
    Finder editorTextField() => find.byKey(const Key('chapterContentField'));

    testWidgets('#82-8 ⋮ 菜单 → 版本时光机 → 空态显示', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('版本时光机'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('版本时光机'),
        80,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('版本时光机'));
      await tester.pumpAndSettle();

      expect(find.text('版本时光机'), findsOneWidget);
      expect(find.textContaining('还没有版本记录'), findsOneWidget);
    });

    testWidgets('#82-9 预置版本 → 时光机显示 → 恢复 → 编辑器内容更新 + 落库', (tester) async {
      // 预置两个版本（最新在前：版本二，其次版本一）
      final repo = AppStateRepository(db);
      await repo.addChapterVersion(chapterId, '版本一：他站在雪地里。');
      await repo.addChapterVersion(chapterId, '版本二：她推开窗户，雨声渐近。');

      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 打开时光机 → 两行版本（预览 = 首行摘要）
      await openTimeMachineMenu(tester);
      expect(find.text('版本二：她推开窗户，雨声渐近。'), findsOneWidget);
      expect(find.text('版本一：他站在雪地里。'), findsOneWidget);

      // 点版本行 → 进入详情视图
      await tester.tap(find.text('版本二：她推开窗户，雨声渐近。'));
      await tester.pumpAndSettle();
      expect(find.text('版本详情'), findsOneWidget);

      await tester.tap(find.text('恢复此版本'));
      await tester.pumpAndSettle();

      // 时光机关闭 + 编辑器内容 = 版本二 + SnackBar 提示
      expect(find.text('版本时光机'), findsNothing);
      final field = tester.widget<TextField>(editorTextField());
      expect(field.controller?.text, '版本二：她推开窗户，雨声渐近。');
      expect(find.text('已恢复到所选版本'), findsOneWidget);

      // 落库验证
      final chRepo = ChapterRepository(db);
      final chapter = await chRepo.getChapter(chapterId);
      expect(chapter?.content, '版本二：她推开窗户，雨声渐近。');

      // 收尾：SnackBar 关闭
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('#82-10 输入越过 200 字 → saveNow → 时光机出现版本快照', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 输入 210 字（初始 12 字 → 快照阈值 200）
      await tester.enterText(editorTextField(), '雪' * 210);
      await tester.pumpAndSettle(); // saveNow 异步落库 + 快照

      // 打开时光机 → 出现 210 字版本行
      await openTimeMachineMenu(tester);

      final sheetWordCount = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('210字'),
      );
      expect(sheetWordCount, findsOneWidget);
    });
  });

  group('批次82：AI 入口重构（P0 四件套之④）', () {
    /// 编辑器正文 TextField（AppBar 标题也是 TextField，需限定在编辑器容器内）
    Finder editorTextField() => find.byKey(const Key('chapterContentField'));

    testWidgets('#82-11 FAB 打开面板 → 编辑器与面板并排，正文不被覆盖', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();

      // 打开面板（FAB）
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();

      // 面板 + 编辑器同时存在（Row 并排，正文未被 bottomSheet 覆盖）
      expect(find.byType(WritingCoachPanel), findsOneWidget);
      expect(editorTextField(), findsOneWidget);
      // 面板位于编辑器右侧
      final editorRect = tester.getRect(
        find.byKey(const Key('editorContainer')),
      );
      final panelRect = tester.getRect(find.byType(WritingCoachPanel));
      expect(panelRect.left, greaterThanOrEqualTo(editorRect.right - 1));
    });

    testWidgets('#82-12 面板打开时标点栏仍可见（正文可继续编辑）', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();

      expect(find.byType(PunctuationBar), findsOneWidget);
    });

    testWidgets('#82-13 选中文本 → 浮动菜单扩展为 诊断/改写/续写 三动作', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 选中章节内容（12 字）
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const Key('chapterContentField')),
          matching: find.byType(EditableText),
        ),
      );
      editable.updateEditingValue(
        TextEditingValue(
          text: editable.textEditingValue.text,
          selection: const TextSelection(baseOffset: 0, extentOffset: 12),
        ),
      );
      await tester.pump();

      expect(find.text('诊断这段文字'), findsOneWidget);
      expect(find.text('改写这段'), findsOneWidget);
      expect(find.text('续写这段'), findsOneWidget);
      // 批次83：划词菜单完整版新增「扩写这段」
      expect(find.text('扩写这段'), findsOneWidget);
    });

    testWidgets('#82-14 点击「改写这段」→ 择选弹层打开（3 个版本 + 换一换）', (tester) async {
      // 预置长章（≥20 字选中）
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '改写测试');
      final longChapterId = await chRepo.createChapter(
        msId,
        title: '长章',
        content: '这是一个大雪纷飞的夜晚，北风呼啸着穿过空旷的原野，远处的山峦在暮色中显得格外孤寂。',
      );

      final c = buildSelectionContainer([_v1s]);
      await pumpWithContainer(tester, c, id: longChapterId, msId: msId);

      // 选中 ≥10 字
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const Key('chapterContentField')),
          matching: find.byType(EditableText),
        ),
      );
      editable.updateEditingValue(
        TextEditingValue(
          text: editable.textEditingValue.text,
          selection: const TextSelection(baseOffset: 0, extentOffset: 20),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('改写这段'));
      await tester.pumpAndSettle();

      // 择选弹层：3 个版本 + 换一换（不再走面板消息）
      expect(find.text('版本 1'), findsOneWidget);
      expect(find.text('版本 2'), findsOneWidget);
      expect(find.text('版本 3'), findsOneWidget);
      expect(find.text('换一换'), findsOneWidget);
      expect(find.byType(WritingCoachPanel), findsNothing);
    });

    testWidgets('#82-15 点击「续写这段」→ 择选弹层打开（续写版本 + 换一换）', (tester) async {
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '续写测试');
      final longChapterId = await chRepo.createChapter(
        msId,
        title: '长章',
        content: '这是一个大雪纷飞的夜晚，北风呼啸着穿过空旷的原野，远处的山峦在暮色中显得格外孤寂。',
      );

      final c = buildSelectionContainer([_v1s]);
      await pumpWithContainer(tester, c, id: longChapterId, msId: msId);

      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const Key('chapterContentField')),
          matching: find.byType(EditableText),
        ),
      );
      editable.updateEditingValue(
        TextEditingValue(
          text: editable.textEditingValue.text,
          selection: const TextSelection(baseOffset: 0, extentOffset: 20),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('续写这段'));
      await tester.pumpAndSettle();

      expect(find.text('版本 1'), findsOneWidget);
      expect(find.text('换一换'), findsOneWidget);
      expect(find.byType(WritingCoachPanel), findsNothing);
    });

    testWidgets('#82-16 选中 <10 字点「改写这段」→ SnackBar 拦截', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 仅选中前 5 字（<10）
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const Key('chapterContentField')),
          matching: find.byType(EditableText),
        ),
      );
      editable.updateEditingValue(
        TextEditingValue(
          text: editable.textEditingValue.text,
          selection: const TextSelection(baseOffset: 0, extentOffset: 5),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('改写这段'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('请至少选择 10 字以上的文本'), findsOneWidget);

      // 收尾：SnackBar 关闭
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });

  group('批次83：章节树侧栏（P1）', () {
    /// 打开章节树抽屉（⋮ 菜单 →「章节列表」）
    Future<void> openChapterTree(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('章节列表'));
      await tester.pumpAndSettle();
    }

    testWidgets('#83-1 ⋮ 菜单 →「章节列表」→ 抽屉打开并显示当前章节', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();

      await openChapterTree(tester);

      // 抽屉标题 + 章节条目（限定在抽屉内，排除 AppBar 标题 TextField）
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('章节列表')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第一章：启程')),
        findsOneWidget,
      );
      // 当前章高亮标记
      expect(find.byKey(ValueKey('tree-current-$chapterId')), findsOneWidget);
    });

    testWidgets('#83-2 多章 → 抽屉显示全部章节（按序）+ 仅当前章高亮', (tester) async {
      final chRepo = ChapterRepository(db);
      final id2 = await chRepo.createChapter(
        manuscriptId,
        title: '第二章：夜行',
        content: '第二段内容。',
      );
      await chRepo.createChapter(manuscriptId, title: '第三章：重逢');

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第一章：启程')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第二章：夜行')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第三章：重逢')),
        findsOneWidget,
      );
      // 仅当前章带高亮标记
      expect(find.byKey(ValueKey('tree-current-$chapterId')), findsOneWidget);
      expect(find.byKey(ValueKey('tree-current-$id2')), findsNothing);
    });

    testWidgets('#83-3 点击另一章 → onJumpToChapter 触发（id + 标题）', (tester) async {
      final chRepo = ChapterRepository(db);
      final id2 = await chRepo.createChapter(
        manuscriptId,
        title: '第二章：夜行',
        content: '第二段内容。',
      );
      String? jumpedId;
      String? jumpedTitle;
      await tester.pumpWidget(
        buildWritingPage(
          msId: manuscriptId,
          onJumpToChapter: (id, title) {
            jumpedId = id;
            jumpedTitle = title;
          },
        ),
      );
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      await tester.tap(
        find.descendant(of: find.byType(Drawer), matching: find.text('第二章：夜行')),
      );
      await tester.pumpAndSettle();

      expect(jumpedId, id2);
      expect(jumpedTitle, '第二章：夜行');
    });

    testWidgets('#83-4 点击「新建章节」→ 落库新章 + 跳转到新章节', (tester) async {
      String? jumpedId;
      await tester.pumpWidget(
        buildWritingPage(
          msId: manuscriptId,
          onJumpToChapter: (id, _) => jumpedId = id,
        ),
      );
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      await tester.tap(find.text('新建章节'));
      await tester.pumpAndSettle();

      // 落库：1 章 → 2 章，新章排在尾部；批次88-1 自动命名「第二章」
      final chapters = await ChapterRepository(db).listChapters(manuscriptId);
      expect(chapters.length, 2);
      expect(jumpedId, chapters[1].id);
      expect(chapters[1].title, '第二章');
    });

    testWidgets('#83-5 无章节作品 → 抽屉显示空态引导', (tester) async {
      final emptyMs = await ManuscriptRepository(
        db,
      ).createManuscript(title: '空作品');
      // 直接渲染抽屉组件（无章节作品的空态路径）
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              drawer: ChapterTreeDrawer(
                currentChapterId: chapterId,
                manuscriptId: emptyMs,
                onJumpToChapter: (_, _) {},
                onCreateChapter: () {},
              ),
              body: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 打开抽屉（闭合态内容 offstage，finder 默认跳过）
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('还没有章节'), findsOneWidget);
      expect(find.text('新建章节'), findsOneWidget);
    });
  });

  group('批次89-2：章节树按卷分组（P1 卷分组）', () {
    /// 打开章节树抽屉（⋮ 菜单 →「章节列表」）
    Future<void> openChapterTree(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('章节列表'));
      await tester.pumpAndSettle();
    }

    testWidgets('#89-2-1 有卷 → 抽屉按全局序渲染：卷头 + 散落章节平铺（批次96-4）', (tester) async {
      final volRepo = VolumeRepository(db);
      final chRepo = ChapterRepository(db);
      final v1 = await volRepo.createVolume(manuscriptId, title: '第一卷');
      final v2 = await volRepo.createVolume(manuscriptId, title: '第二卷');
      // 当前章移入 v1；另建 v2 章节 + 未分卷章节
      await volRepo.setChapterVolume(chapterId, v1);
      await chRepo.createChapter(manuscriptId, title: '第二卷之章', volumeId: v2);
      await chRepo.createChapter(manuscriptId, title: '散章');

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      // 卷头顺序：第一卷 → 第二卷（散落章节平铺，不再有「未分卷」组头）
      final headerTitles = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(Drawer),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .toList();
      final v1Idx = headerTitles.indexOf('第一卷');
      final v2Idx = headerTitles.indexOf('第二卷');
      expect(v1Idx, greaterThan(-1));
      expect(v2Idx, greaterThan(v1Idx));
      expect(headerTitles.contains('未分卷'), isFalse, reason: '散落章节平铺无组头');

      // 各组章节可见（默认展开）
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第一章：启程')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第二卷之章')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('散章')),
        findsOneWidget,
      );
    });

    testWidgets('#89-2-2 点击卷头 → 折叠该组章节', (tester) async {
      final volRepo = VolumeRepository(db);
      final v1 = await volRepo.createVolume(manuscriptId, title: '第一卷');
      await volRepo.setChapterVolume(chapterId, v1);

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第一章：启程')),
        findsOneWidget,
      );

      // 点击卷头 → 组内章节隐藏
      await tester.tap(
        find.descendant(of: find.byType(Drawer), matching: find.text('第一卷')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第一章：启程')),
        findsNothing,
      );
      // 卷头仍在
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第一卷')),
        findsOneWidget,
      );
    });

    testWidgets('#89-2-3 新建章节自动落入当前章所在卷', (tester) async {
      final volRepo = VolumeRepository(db);
      final v1 = await volRepo.createVolume(manuscriptId, title: '第一卷');
      // 当前章（第一章：启程）在 v1 卷内
      await volRepo.setChapterVolume(chapterId, v1);

      String? jumpedId;
      await tester.pumpWidget(
        buildWritingPage(
          msId: manuscriptId,
          onJumpToChapter: (id, _) => jumpedId = id,
        ),
      );
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      await tester.tap(find.text('新建章节'));
      await tester.pumpAndSettle();

      final chapters = await ChapterRepository(db).listChapters(manuscriptId);
      expect(chapters.length, 2);
      final newChapter = chapters.firstWhere((c) => c.id == jumpedId);
      expect(newChapter.volumeId, v1, reason: '新建章节落入当前章所在卷');
    });

    testWidgets('#89-2-4 当前章未分卷 → 新建章节也不分卷', (tester) async {
      // 不建卷（当前章 volumeId 为 null）
      String? jumpedId;
      await tester.pumpWidget(
        buildWritingPage(
          msId: manuscriptId,
          onJumpToChapter: (id, _) => jumpedId = id,
        ),
      );
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      await tester.tap(find.text('新建章节'));
      await tester.pumpAndSettle();

      final chapters = await ChapterRepository(db).listChapters(manuscriptId);
      final newChapter = chapters.firstWhere((c) => c.id == jumpedId);
      expect(newChapter.volumeId, isNull);
    });
  });

  group('批次89-3：卷管理交互（新建/删卷/章节移卷）', () {
    /// 打开章节树抽屉（⋮ 菜单 →「章节列表」）
    Future<void> openChapterTree(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('章节列表'));
      await tester.pumpAndSettle();
    }

    /// 等 SnackBar 消失（2 秒 + 动画余量）
    Future<void> dismissSnack(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }

    testWidgets('#89-3-1 新建卷（输入名称）→ 卷头出现 + 落库', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      await tester.tap(find.byKey(const ValueKey('create-volume-btn')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-volume-field')),
        '风起篇',
      );
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      // 落库 + 卷头显示 + 轻提示
      final volumes = await VolumeRepository(db).listVolumes(manuscriptId);
      expect(volumes.length, 1);
      expect(volumes.first.title, '风起篇');
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('风起篇')),
        findsOneWidget,
      );
      expect(find.textContaining('已创建《风起篇》'), findsOneWidget);
      await dismissSnack(tester);
    });

    testWidgets('#89-3-2 新建卷（留空）→ 自动命名「第一卷」', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      await tester.tap(find.byKey(const ValueKey('create-volume-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      final volumes = await VolumeRepository(db).listVolumes(manuscriptId);
      expect(volumes.length, 1);
      expect(volumes.first.title, '第一卷');
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第一卷')),
        findsOneWidget,
      );
      await dismissSnack(tester);
    });

    testWidgets('#89-3-3 长按卷头 → 删除卷 → 卷内章节一并删除（批次96-4）', (tester) async {
      final volRepo = VolumeRepository(db);
      final v1 = await volRepo.createVolume(manuscriptId, title: '第一卷');
      await volRepo.setChapterVolume(chapterId, v1);

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      // 长按卷头 → 卷操作弹层 → 删除卷
      await tester.longPress(
        find.descendant(of: find.byType(Drawer), matching: find.text('第一卷')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除卷'));
      await tester.pumpAndSettle();
      // 二次确认
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // 卷删除 + 卷内章节一并软删进回收站（不再散落）
      final volumes = await volRepo.listVolumes(manuscriptId);
      expect(volumes, isEmpty);
      final chapter = await ChapterRepository(db).getChapter(chapterId);
      expect(chapter!.status, 'archived', reason: '删卷后卷内章节软删进回收站');

      // 抽屉刷新：卷头消失；卷内章节一并从列表消失
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第一卷')),
        findsNothing,
      );
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('第一章：启程')),
        findsNothing,
      );
      await dismissSnack(tester);
    });

    testWidgets('#89-3-4 长按章节 → 移动到卷', (tester) async {
      final volRepo = VolumeRepository(db);
      final v1 = await volRepo.createVolume(manuscriptId, title: '第一卷');
      final chRepo = ChapterRepository(db);
      final looseId = await chRepo.createChapter(manuscriptId, title: '散章');

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      // 批次90 修复3：长按「散章」→ 首先弹操作菜单（重命名 / 移动到卷）
      await tester.longPress(
        find.descendant(of: find.byType(Drawer), matching: find.text('散章')),
      );
      await tester.pumpAndSettle();
      // 从操作菜单里选「移动到卷」
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('移动到卷'),
        ),
      );
      await tester.pumpAndSettle();
      // 再在第二个 BottomSheet 里选目标卷「第一卷」
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('第一卷'),
        ),
      );
      await tester.pumpAndSettle();

      // 落库断言：散章移入 v1
      final moved = await chRepo.getChapter(looseId);
      expect(moved!.volumeId, v1);

      // 抽屉刷新：散章不再在「未分卷」组（当前卷 chapterId 仍在 v1 内展示）
      final chapters = await chRepo.listChapters(manuscriptId);
      expect(chapters.firstWhere((c) => c.id == looseId).volumeId, v1);
    });
  });

  group('批次89-4：新建章节入口移至列表末尾（底部无按钮）', () {
    /// 打开章节树抽屉（⋮ 菜单 →「章节列表」）
    Future<void> openChapterTree(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('章节列表'));
      await tester.pumpAndSettle();
    }

    testWidgets('#89-4-1 底部无「新建章节」按钮；列表末尾有新建章节行（扁平）', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      // 底部按钮移除：FilledButton 内不再有「新建章节」
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.text('新建章节'),
        ),
        findsNothing,
        reason: '底部「新建章节」按钮应移除',
      );
      // 列表内「新建章节」行唯一存在
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('新建章节')),
        findsOneWidget,
      );
      // 位于列表末尾（Drawer 内最后一个文本）
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(Drawer),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .toList();
      expect(texts.last, '新建章节');
    });

    testWidgets('#89-4-2 分组模式下「新建章节」行也在列表末尾', (tester) async {
      final volRepo = VolumeRepository(db);
      final v1 = await volRepo.createVolume(manuscriptId, title: '第一卷');
      await volRepo.setChapterVolume(chapterId, v1);

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openChapterTree(tester);

      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('新建章节')),
        findsOneWidget,
      );
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(Drawer),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .toList();
      expect(texts.last, '新建章节');
    });

    testWidgets('#89-4-3 空态：引导 + 新建章节入口可点击（触发新建）', (tester) async {
      final emptyMs = await ManuscriptRepository(
        db,
      ).createManuscript(title: '空作品');
      var createTapped = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              drawer: ChapterTreeDrawer(
                currentChapterId: chapterId,
                manuscriptId: emptyMs,
                onJumpToChapter: (_, _) {},
                onCreateChapter: () => createTapped++,
              ),
              body: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('还没有章节'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text('新建章节')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: find.byType(Drawer), matching: find.text('新建章节')),
      );
      await tester.pumpAndSettle();
      expect(createTapped, 1, reason: '空态下列表项应可触发新建');
    });
  });

  group('批次83：大纲边写边看（P1）', () {
    /// 打开大纲抽屉（⋮ 菜单 →「大纲」）
    Future<void> openOutline(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('大纲'));
      await tester.pumpAndSettle();
    }

    testWidgets('#83-6 ⋮ 菜单 →「大纲」→ 抽屉打开 + 空态引导', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();

      await openOutline(tester);

      expect(find.text('还没有大纲'), findsOneWidget);
      expect(find.textContaining('去教练面板做次诊断'), findsOneWidget);
    });

    testWidgets('#83-7 有实体 → 抽屉按类型分组展示 + 印象 + 第N章标签', (tester) async {
      final repo = OutlineRepository(db);
      await repo.insertEntity(
        manuscriptId: manuscriptId,
        entityType: 'character',
        entityKey: '林晚',
        aliases: ['小晚'],
      );
      await repo.insertEntity(
        manuscriptId: manuscriptId,
        entityType: 'plot',
        entityKey: '夜行赴金陵',
      );
      final entities = await repo.listEntities(manuscriptId);
      final linwan = entities.firstWhere((e) => e.entityKey == '林晚');
      final impId = await repo.insertImpression(
        entityId: linwan.id,
        impression: '怕黑，小时候在巷口走丢过',
        sourceChapterNo: 1,
      );
      // 确认后：印象 active + 实体 active
      await repo.approveImpression(impId);
      // 情节实体同样确认，避免遗留 pending「待确认」标签
      final plotEntity = entities.firstWhere((e) => e.entityKey == '夜行赴金陵');
      final plotImpId = await repo.insertImpression(
        entityId: plotEntity.id,
        impression: '连夜赶路去金陵求医',
      );
      await repo.approveImpression(plotImpId);

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openOutline(tester);

      // 类型分组标题（人物/情节 出现；设定无实体不出现）
      expect(find.text('人物'), findsOneWidget);
      expect(find.text('情节'), findsOneWidget);
      expect(find.text('设定'), findsNothing);
      // 实体名 + 印象 + 章节标签
      expect(find.text('林晚'), findsOneWidget);
      expect(find.text('别名：小晚'), findsOneWidget);
      expect(find.text('夜行赴金陵'), findsOneWidget);
      expect(find.text('怕黑，小时候在巷口走丢过'), findsOneWidget);
      expect(find.text('第1章'), findsOneWidget);
      // 已确认印象不带「待确认」
      expect(find.text('待确认'), findsNothing);
    });

    testWidgets('#83-8 待确认实体/印象标记 + 被拒印象隐藏', (tester) async {
      final repo = OutlineRepository(db);
      await repo.insertEntity(
        manuscriptId: manuscriptId,
        entityType: 'setting',
        entityKey: '神秘钥匙',
      );
      final entities = await repo.listEntities(manuscriptId);
      final keyEntity = entities.firstWhere((e) => e.entityKey == '神秘钥匙');
      await repo.insertImpression(
        entityId: keyEntity.id,
        impression: '藏在老宅地板的暗格里',
      );
      final rejectedId = await repo.insertImpression(
        entityId: keyEntity.id,
        impression: '旧设定：埋在院子的树下',
      );
      await repo.rejectImpression(rejectedId);

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openOutline(tester);

      // 分组 + 实体（pending → 待确认）
      expect(find.text('设定'), findsOneWidget);
      expect(find.text('神秘钥匙'), findsOneWidget);
      expect(find.text('待确认'), findsNWidgets(2)); // 实体卡 1 + 印象 1
      // 待确认印象可见、被拒印象隐藏
      expect(find.text('藏在老宅地板的暗格里'), findsOneWidget);
      expect(find.text('旧设定：埋在院子的树下'), findsNothing);
    });

    testWidgets('#83-9 右上角关闭 → 大纲抽屉收起', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openOutline(tester);

      expect(find.text('还没有大纲'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 抽屉闭合后内容 offstage → finder 跳过
      expect(find.text('还没有大纲'), findsNothing);
    });
  });

  group('批次83：划词选区 AI 菜单完整版（P0-P1）', () {
    /// 批次90：页面有标题+正文两个 TextField → 正文用专用 key 下的 EditableText
    Finder editorEditable() => find.descendant(
      of: find.byKey(const Key('chapterContentField')),
      matching: find.byType(EditableText),
    );

    /// 预置长章（≥20 字，供选区）
    Future<({String msId, String chapterId})> presetLongChapter() async {
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '择选测试');
      final chapterId = await chRepo.createChapter(
        msId,
        title: '长章',
        content: '这是一个大雪纷飞的夜晚，北风呼啸着穿过空旷的原野，远处的山峦在暮色中显得格外孤寂。',
      );
      return (msId: msId, chapterId: chapterId);
    }

    /// 选中 [start, end) 区间
    Future<void> selectText(WidgetTester tester, {required int end}) async {
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const Key('chapterContentField')),
          matching: find.byType(EditableText),
        ),
      );
      editable.updateEditingValue(
        TextEditingValue(
          text: editable.textEditingValue.text,
          selection: TextSelection(baseOffset: 0, extentOffset: end),
        ),
      );
      await tester.pump();
    }

    /// 收尾：SnackBar 自动关闭
    Future<void> settleSnackBar(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }

    testWidgets('#83-10 改写 → 用这个 → 替换选区 + 落库', (tester) async {
      final preset = await presetLongChapter();
      final c = buildSelectionContainer([_v1s]);
      await pumpWithContainer(
        tester,
        c,
        id: preset.chapterId,
        msId: preset.msId,
      );
      await selectText(tester, end: 20);

      await tester.tap(find.text('改写这段'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('用这个').first);
      await tester.pumpAndSettle();

      // 编辑器内容 = 版本一替换前 20 字
      final editable = tester.state<EditableTextState>(editorEditable());
      final content = editable.textEditingValue.text;
      expect(content, startsWith('雪地旅人裹紧了大衣，脚步更快了。'));
      expect(content, isNot(contains('这是一个大雪纷飞的夜晚，北风')));
      // 落库
      final chapter = await ChapterRepository(db).getChapter(preset.chapterId);
      expect(chapter!.content, startsWith('雪地旅人裹紧了大衣'));
      // 轻提示
      expect(find.text('已更新这段文字'), findsOneWidget);
      await settleSnackBar(tester);
    });

    testWidgets('#83-11 续写 → 用这个 → 插入到选中文本之后', (tester) async {
      final preset = await presetLongChapter();
      final c = buildSelectionContainer([_v1s]);
      await pumpWithContainer(
        tester,
        c,
        id: preset.chapterId,
        msId: preset.msId,
      );
      await selectText(tester, end: 20);

      await tester.tap(find.text('续写这段'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('用这个').first);
      await tester.pumpAndSettle();

      final editable = tester.state<EditableTextState>(editorEditable());
      final content = editable.textEditingValue.text;
      // 原 20 字保留，版本一插入其后（选区 [0,20) 止于「空」字）
      expect(content, startsWith('这是一个大雪纷飞的夜晚，北风呼啸着穿过空'));
      expect(content, contains('雪地旅人裹紧了大衣'));
      expect(find.text('已续写这段'), findsOneWidget);
      await settleSnackBar(tester);
    });

    testWidgets('#83-12 扩写 → 用这个 → 替换选区 + 落库', (tester) async {
      final preset = await presetLongChapter();
      final c = buildSelectionContainer([_v2s]);
      await pumpWithContainer(
        tester,
        c,
        id: preset.chapterId,
        msId: preset.msId,
      );
      await selectText(tester, end: 20);

      await tester.tap(find.text('扩写这段'));
      await tester.pumpAndSettle();

      // 扩写弹层打开（标题 + 版本）
      expect(find.text('版本 1'), findsOneWidget);
      await tester.tap(find.text('用这个').first);
      await tester.pumpAndSettle();

      final editable = tester.state<EditableTextState>(editorEditable());
      expect(editable.textEditingValue.text, startsWith('北风里，旅人的围巾被吹得猎猎作响。'));
      final chapter = await ChapterRepository(db).getChapter(preset.chapterId);
      expect(chapter!.content, startsWith('北风里，旅人的围巾'));
      await settleSnackBar(tester);
    });

    testWidgets('#83-13 换一换 → 重新生成一批版本', (tester) async {
      final preset = await presetLongChapter();
      final c = buildSelectionContainer([_v1s, _v2s]);
      await pumpWithContainer(
        tester,
        c,
        id: preset.chapterId,
        msId: preset.msId,
      );
      await selectText(tester, end: 20);

      await tester.tap(find.text('改写这段'));
      await tester.pumpAndSettle();

      // 第一批：雪地旅人版本可见
      expect(find.textContaining('雪地旅人裹紧了大衣'), findsOneWidget);
      await tester.tap(find.text('换一换'));
      await tester.pumpAndSettle();

      // 第二批：围巾版本可见，雪地旅人版本消失
      expect(find.textContaining('北风里，旅人的围巾被吹得猎猎作响'), findsOneWidget);
      expect(find.textContaining('雪地旅人裹紧了大衣'), findsNothing);
    });

    testWidgets('#83-14 生成失败 → 弹层内错误提示 + 重试可再生成', (tester) async {
      final preset = await presetLongChapter();
      final failing = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llmClientProvider.overrideWithValue(
            FakeLlmClient('x', error: Exception('模拟失败')),
          ),
        ],
      );
      addTearDown(failing.dispose);
      await pumpWithContainer(
        tester,
        failing,
        id: preset.chapterId,
        msId: preset.msId,
      );
      await selectText(tester, end: 20);

      await tester.tap(find.text('改写这段'));
      await tester.pumpAndSettle();

      expect(find.text('生成失败，稍后再试一次吧'), findsOneWidget);
    });
  });

  group('批次83：parseSelectionVersions 解析', () {
    test('按【版本N】标记切分', () {
      expect(parseSelectionVersions('【版本一】A\n【版本二】B\n【版本三】C'), ['A', 'B', 'C']);
    });

    test('兜底：编号行切分', () {
      expect(parseSelectionVersions('1. A\n2. B\n3. C'), ['A', 'B', 'C']);
    });

    test('兜底：整段当一个版本', () {
      expect(parseSelectionVersions('只是一段话'), ['只是一段话']);
    });

    test('空串 → 空列表', () {
      expect(parseSelectionVersions(''), isEmpty);
      expect(parseSelectionVersions('   '), isEmpty);
    });
  });

  group('批次84-②：全文查找替换（P1）', () {
    /// 查找替换弹层内的输入框（编辑器 TextField 也在场，需限定 BottomSheet 内）
    Finder sheetFields() => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );

    /// 编辑器正文 TextField（AppBar 标题也是 TextField，需限定编辑器容器内）
    Finder editorTextField() => find.byKey(const Key('chapterContentField'));

    /// 当前编辑器选区（定位断言用）
    TextSelection editorSelection(WidgetTester tester) =>
        tester.widget<TextField>(editorTextField()).controller!.selection;

    Future<void> openFindReplace(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查找替换'));
      await tester.pumpAndSettle();
    }

    test('computeMatches 基础单测', () {
      expect(computeMatches('大雪纷飞', '大雪'), [0]);
      expect(computeMatches('大雪纷飞，雪落无声。大雪封山。', '大雪'), [0, 10]);
      expect(computeMatches('abc', 'd'), isEmpty);
      expect(computeMatches('', 'a'), isEmpty);
      expect(computeMatches('abc', ''), isEmpty);
      // 相邻匹配不共享字符（非重叠）
      expect(computeMatches('aaaa', 'aa'), [0, 2]);
    });

    testWidgets('#84-6 ⋮ 菜单 → 查找替换 → 弹层打开（标题 + 查找/替换输入 + 提示）', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();

      await openFindReplace(tester);

      expect(find.text('查找替换'), findsOneWidget);
      expect(sheetFields(), findsNWidgets(2));
      expect(find.text('搜索全书'), findsOneWidget);
      expect(find.text('查找会在正文里标出位置，替换后即时保存'), findsOneWidget);
    });

    testWidgets('#84-7 输入查找词 → 计数 + 编辑器定位首个匹配', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openFindReplace(tester);

      await tester.enterText(sheetFields().first, '大雪');
      await tester.pumpAndSettle();

      // 本章 1 处 → 计数 1/1
      expect(find.text('1/1 处'), findsOneWidget);
      // 「这是一个大雪纷飞的夜晚。」→ 大雪位于 [4,6)
      expect(
        editorSelection(tester),
        const TextSelection(baseOffset: 4, extentOffset: 6),
      );
    });

    testWidgets('#84-8 下一个/上一个 循环定位', (tester) async {
      final chRepo = ChapterRepository(db);
      final ch2Id = await chRepo.createChapter(
        manuscriptId,
        title: '第二章：风雪',
        content: '大雪纷飞，雪落无声。大雪封山。',
      );
      await tester.pumpWidget(buildWritingPage(id: ch2Id, msId: manuscriptId));
      await tester.pumpAndSettle();
      await openFindReplace(tester);

      await tester.enterText(sheetFields().first, '大雪');
      await tester.pumpAndSettle();

      // 本章 2 处，初始定位第 1 个 → 计数 1/2
      expect(find.text('1/2 处'), findsOneWidget);
      // 默认定位第一个 [0,2)
      expect(
        editorSelection(tester),
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );

      // 下一个 → 第二个 [10,12)，计数 2/2
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump();
      expect(
        editorSelection(tester),
        const TextSelection(baseOffset: 10, extentOffset: 12),
      );
      expect(find.text('2/2 处'), findsOneWidget);

      // 下一个越界 → 绕回第一个
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump();
      expect(
        editorSelection(tester),
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );

      // 上一个 → 绕回最后一个
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pump();
      expect(
        editorSelection(tester),
        const TextSelection(baseOffset: 10, extentOffset: 12),
      );
    });

    testWidgets('#84-9 替换当前匹配 → 编辑器内容更新 + 计数归零', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openFindReplace(tester);

      await tester.enterText(sheetFields().first, '大雪');
      await tester.pumpAndSettle();
      await tester.enterText(sheetFields().at(1), '小雪');
      await tester.pump();

      await tester.tap(find.text('替换'));
      await tester.pumpAndSettle();

      // 编辑器内容已替换 + store 同步
      final editor = tester.widget<TextField>(editorTextField());
      expect(editor.controller!.text, '这是一个小雪纷飞的夜晚。');
      expect(
        container.read(writingStoreProvider(chapterId).notifier).currentContent,
        '这是一个小雪纷飞的夜晚。',
      );
      // 已无匹配 → 计数 0/0
      expect(find.text('0/0 处'), findsOneWidget);
    });

    testWidgets('#84-10 全部替换 → 整章替换 + 计数归零', (tester) async {
      final chRepo = ChapterRepository(db);
      final ch2Id = await chRepo.createChapter(
        manuscriptId,
        title: '第二章：风雪',
        content: '大雪纷飞，雪落无声。大雪封山。',
      );
      await tester.pumpWidget(buildWritingPage(id: ch2Id, msId: manuscriptId));
      await tester.pumpAndSettle();
      await openFindReplace(tester);

      await tester.enterText(sheetFields().first, '大雪');
      await tester.pumpAndSettle();
      await tester.enterText(sheetFields().at(1), '细雨');
      await tester.pump();

      await tester.tap(find.text('全部替换'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(editorTextField()).controller!.text,
        '细雨纷飞，雪落无声。细雨封山。',
      );
      expect(find.text('0/0 处'), findsOneWidget);
    });

    testWidgets('#84-11 搜索全书 → 各章命中列表 → 点击跳转', (tester) async {
      final chRepo = ChapterRepository(db);
      final ch2Id = await chRepo.createChapter(
        manuscriptId,
        title: '第二章：风雪',
        content: '雪地里的灯笼亮着，大雪封山。',
      );
      String? jumpedId;
      String? jumpedTitle;
      await tester.pumpWidget(
        buildWritingPage(
          msId: manuscriptId,
          onJumpToChapter: (id, title) {
            jumpedId = id;
            jumpedTitle = title;
          },
        ),
      );
      await tester.pumpAndSettle();
      await openFindReplace(tester);

      await tester.enterText(sheetFields().first, '大雪');
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索全书'));
      await tester.pumpAndSettle();

      // 两章各命中 1 处（AppBar 标题 TextField 也含「第一章：启程」文本，
      // find.text 会命中 EditableText → 只断言第二章标题唯一 + 计数 2 处）
      expect(find.text('第二章：风雪'), findsOneWidget);
      expect(find.text('1 处'), findsNWidgets(2));

      await tester.tap(find.text('第二章：风雪'));
      await tester.pumpAndSettle();

      expect(jumpedId, ch2Id);
      expect(jumpedTitle, '第二章：风雪');
    });
  });

  group('批次96-11：全文搜索（整本作品章节搜索）', () {
    /// 弹层内输入框（编辑器 TextField 也在场，需限定 BottomSheet 内）
    Finder sheetFields() => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );

    /// 编辑器正文 TextField
    Finder editorTextField() => find.byKey(const Key('chapterContentField'));

    /// 当前编辑器选区
    TextSelection editorSelection(WidgetTester tester) =>
        tester.widget<TextField>(editorTextField()).controller!.selection;

    Future<void> openFullTextSearch(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全文搜索'));
      await tester.pumpAndSettle();
    }

    /// 输入关键词并等待防抖（300ms）+ 搜索完成
    Future<void> typeQuery(WidgetTester tester, String q) async {
      await tester.enterText(sheetFields().first, q);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    test('buildSnippet 命中片段截取 + 省略号', () {
      // 短文本：首处命中前后各 20 字，不超界 → 不补省略号
      expect(buildSnippet('这是一个大雪纷飞的夜晚。', 4, 2), '这是一个大雪纷飞的夜晚。');
      // 长文本：命中在中间 → 前后截断 + 省略号 + 命中词完整保留
      final long = '${'甲' * 30}命中词${'乙' * 30}';
      final s = buildSnippet(long, 30, 3);
      expect(s.startsWith('…'), isTrue);
      expect(s.endsWith('…'), isTrue);
      expect(s, contains('命中词'));
      // 命中在开头 → 无前省略号
      final head = buildSnippet('命中词${'乙' * 40}', 0, 3);
      expect(head.startsWith('…'), isFalse);
      expect(head, contains('命中词'));
    });

    testWidgets('#96-11 ⋮ 菜单「全文搜索」→ 打开即全书视图（标题 + 查询框）', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();

      await openFullTextSearch(tester);

      // 独立入口 → 标题「全文搜索」+ 全书视图查询框（hint「搜索全书」）
      expect(find.text('全文搜索'), findsOneWidget);
      expect(find.text('搜索全书'), findsOneWidget);
      // 全书视图只有查询框 1 个（无替换框）→ 空态提示
      expect(sheetFields(), findsOneWidget);
      expect(find.text('输入关键词搜索全书章节'), findsOneWidget);
    });

    testWidgets('#96-11 输入关键词 → 结果含命中片段（关键词高亮）', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openFullTextSearch(tester);

      await typeQuery(tester, '大雪');

      // 搜索结果 tile 限定在弹层内（编辑器标题/面包屑也有「第一章：启程」）
      final inSheet = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('第一章：启程'),
      );
      expect(inSheet, findsOneWidget);
      expect(find.text('1 处'), findsOneWidget);
      // 命中片段（Text.rich 以 plainText 匹配）→ 含原文「大雪纷飞」
      expect(find.textContaining('这是一个大雪纷飞的夜晚。'), findsWidgets);
    });

    testWidgets('#96-11 点击当前章结果 → 编辑器定位命中处', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openFullTextSearch(tester);

      await typeQuery(tester, '大雪');

      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('第一章：启程'),
        ),
      );
      await tester.pumpAndSettle();

      // sheet 关闭 + 编辑器选中命中词 [4,6)（「这是一个大雪纷飞的夜晚。」）
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        editorSelection(tester),
        const TextSelection(baseOffset: 4, extentOffset: 6),
      );
    });

    testWidgets('#96-11 标题命中 → 结果含标题命中的章节（片段=标题）', (tester) async {
      final chRepo = ChapterRepository(db);
      // 标题含「风雪」但正文不含 → 仅标题命中
      await chRepo.createChapter(
        manuscriptId,
        title: '第三章：风雪夜归人',
        content: '夜归人推开门，屋里炉火正旺。',
      );
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openFullTextSearch(tester);

      await typeQuery(tester, '风雪');

      // 标题命中 → 结果项含该章：标题行 Text + 片段行 Text.rich（同为该文本，共 2 处）
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('第三章：风雪夜归人'),
        ),
        findsNWidgets(2),
      );
      expect(find.text('1 处'), findsOneWidget);
      expect(find.textContaining('第三章：风雪夜归人'), findsWidgets);
    });

    testWidgets('#96-11 点击跨章结果 → onJumpToChapter 触发', (tester) async {
      final chRepo = ChapterRepository(db);
      final ch2Id = await chRepo.createChapter(
        manuscriptId,
        title: '第二章：风雪',
        content: '雪地里的灯笼亮着，大雪封山。',
      );
      String? jumpedId;
      String? jumpedTitle;
      await tester.pumpWidget(
        buildWritingPage(
          msId: manuscriptId,
          onJumpToChapter: (id, title) {
            jumpedId = id;
            jumpedTitle = title;
          },
        ),
      );
      await tester.pumpAndSettle();
      await openFullTextSearch(tester);

      await typeQuery(tester, '大雪');

      // 两章各命中 1 处（当前章 + 第二章）
      expect(find.text('1 处'), findsNWidgets(2));
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('第二章：风雪'),
        ),
      );
      await tester.pumpAndSettle();

      expect(jumpedId, ch2Id);
      expect(jumpedTitle, '第二章：风雪');
    });
  });

  group('批次84-③：版本时光机差异对比（轻量版本回溯）', () {
    Future<void> openTimeMachine(WidgetTester tester) async {
      await openTimeMachineMenu(tester);
    }

    test('diffText：两版相同 → 整段 same', () {
      final segs = diffText('ABC', 'ABC');
      expect(segs.map((s) => (s.text, s.kind)).toList(), [
        ('ABC', DiffKind.same),
      ]);
    });

    test('diffText：版本尾部新增 → same + added', () {
      final segs = diffText('AB', 'ABC');
      expect(segs.map((s) => (s.text, s.kind)).toList(), [
        ('AB', DiffKind.same),
        ('C', DiffKind.added),
      ]);
    });

    test('diffText：版本删词 → same + removed + same', () {
      final segs = diffText('你好世界', '你世界');
      expect(segs.map((s) => (s.text, s.kind)).toList(), [
        ('你', DiffKind.same),
        ('好', DiffKind.removed),
        ('世界', DiffKind.same),
      ]);
    });

    test('diffText：当前为空 → 整段 added；版本为空 → 整段 removed', () {
      expect(diffText('', '新内容').map((s) => (s.text, s.kind)).toList(), [
        ('新内容', DiffKind.added),
      ]);
      expect(diffText('旧内容', '').map((s) => (s.text, s.kind)).toList(), [
        ('旧内容', DiffKind.removed),
      ]);
    });

    test('diffText：换行保留 + 无损重建（跳过 removed 得版本，跳过 added 得当前）', () {
      const current = '第一行\n第二行旧内容\n第三行';
      const version = '第一行\n第二行新内容\n第三行改';
      final segs = diffText(current, version);
      String rebuild({required bool skipAdded, required bool skipRemoved}) =>
          segs
              .where(
                (s) =>
                    !(skipAdded && s.kind == DiffKind.added) &&
                    !(skipRemoved && s.kind == DiffKind.removed),
              )
              .map((s) => s.text)
              .join();
      expect(rebuild(skipAdded: true, skipRemoved: false), current);
      expect(rebuild(skipAdded: false, skipRemoved: true), version);
    });

    testWidgets('#84-12 版本详情 → 差异对比：新增标绿 + 图例文案', (tester) async {
      // 当前内容 = 编辑器正文（setUp 预置）；版本 = 当前 + 尾部新增
      final repo = AppStateRepository(db);
      await repo.addChapterVersion(chapterId, '这是一个大雪纷飞的夜晚，他裹紧了衣领。');

      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openTimeMachine(tester);

      // 列表 → 版本行 → 详情
      await tester.tap(find.text('这是一个大雪纷飞的夜晚，他裹紧了衣领。'));
      await tester.pumpAndSettle();

      expect(find.text('版本详情'), findsOneWidget);
      // 图例文案（有差异）
      expect(find.text('相对当前内容：新增标绿 · 删除划线'), findsOneWidget);
      // 全文预览（RichText）还原版本全文
      expect(
        find.text('这是一个大雪纷飞的夜晚，他裹紧了衣领。', findRichText: true),
        findsOneWidget,
      );
      // 差异正文 = 含「他裹紧了衣领」片段的 RichText（Text 内部也是 RichText，需按内容定位）
      final diffRich = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((r) {
            final buf = StringBuffer();
            r.text.visitChildren((span) {
              if (span is TextSpan && span.text != null) buf.write(span.text);
              return true;
            });
            return buf.toString().contains('他裹紧了衣领');
          }, orElse: () => fail('未找到差异富文本'));
      // 新增段带绿底（successBg），且新增内容完整保留
      var addedText = '';
      diffRich.text.visitChildren((span) {
        if (span is TextSpan &&
            span.text != null &&
            span.style?.backgroundColor == AppColors.successBg) {
          addedText += span.text!;
        }
        return true;
      });
      expect(addedText, '，他裹紧了衣领');
    });

    testWidgets('#84-13 版本与当前一致 → 「与当前内容一致」', (tester) async {
      final repo = AppStateRepository(db);
      await repo.addChapterVersion(chapterId, '这是一个大雪纷飞的夜晚。');

      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openTimeMachine(tester);

      // 版本行（编辑器正文与版本同串，find.text 会命中编辑器 EditableText → 限定弹层内）
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('这是一个大雪纷飞的夜晚。'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('与当前内容一致'), findsOneWidget);
      expect(find.text('相对当前内容：新增标绿 · 删除划线'), findsNothing);
    });
  });

  group('批次85：完成度徽标（P2 效率组①）', () {
    /// 编辑器正文 TextField（AppBar 标题也是 TextField，需限定编辑器容器内）
    Finder editorTextField() => find.byKey(const Key('chapterContentField'));

    /// 完成度徽标内的文本（AppBar 标题 EditableText 可能与徽标同文 → 限定徽标内）
    Finder badgeText(String label) => find.descendant(
      of: find.byKey(const Key('completionBadge')),
      matching: find.text(label),
    );

    testWidgets('#85-1 未设目标 → 章节体量徽标「短章」+ 纯字数', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 默认 12 字 → 短章徽标 + 「12字」
      expect(badgeText('短章'), findsOneWidget);
      expect(find.text('12字'), findsOneWidget);
    });

    testWidgets('#85-2 设目标 + 未达标 → 徽标显示进度百分比', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      await container
          .read(writingStoreProvider(chapterId).notifier)
          .setGoalWords(1000);
      await tester.pumpAndSettle();

      // 输入 650 字 → 徽标 65% + 字数区「650/1,000」
      await tester.enterText(editorTextField(), '雪' * 650);
      await tester.pumpAndSettle();

      expect(badgeText('65%'), findsOneWidget);
      expect(find.text('650/1,000'), findsOneWidget);

      // 收尾：快照/保存残留定时器清理
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('#85-3 达标 → 徽标「已达成」', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 目标 10 字 < 当前 12 字 → 已达成
      await container
          .read(writingStoreProvider(chapterId).notifier)
          .setGoalWords(10);
      await tester.pumpAndSettle();

      expect(badgeText('已达成'), findsOneWidget);
    });

    testWidgets('#85-4 章节体量徽标：中章（3000+ 字）', (tester) async {
      final chRepo = ChapterRepository(db);
      final ch2Id = await chRepo.createChapter(
        manuscriptId,
        title: '中章',
        content: '雪' * 3000,
      );

      await tester.pumpWidget(buildWritingPage(id: ch2Id, msId: manuscriptId));
      // 3000 字大章加载后存在持续排帧（pumpAndSettle 超时）→ 用有限 pump 推进
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(badgeText('中章'), findsOneWidget);
    });

    testWidgets('#85-5 章节体量徽标：长章（10000+ 字）', (tester) async {
      final chRepo = ChapterRepository(db);
      final ch3Id = await chRepo.createChapter(
        manuscriptId,
        title: '长章',
        content: '雪' * 10000,
      );

      await tester.pumpWidget(buildWritingPage(id: ch3Id, msId: manuscriptId));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(badgeText('长章'), findsOneWidget);
    });
  });

  group('批次85-②：行段聚焦（P2 效率组②）', () {
    /// 编辑器正文 TextField（AppBar 标题也是 TextField，需限定编辑器容器内）
    Finder editorTextField() => find.byKey(const Key('chapterContentField'));

    test('currentSegmentRange：光标所在段区间', () {
      const text = '第一段。\n第二段。\n第三段。';
      // 光标在第一段（[0,4)，\n 在位置 4）
      expect(currentSegmentRange(text, 2), (start: 0, end: 4));
      // 光标在第二段（段首 5 / 段中 6 / 段尾 8）
      expect(currentSegmentRange(text, 5), (start: 5, end: 9));
      expect(currentSegmentRange(text, 6), (start: 5, end: 9));
      expect(currentSegmentRange(text, 8), (start: 5, end: 9));
      // 光标在第三段
      expect(currentSegmentRange(text, 10), (start: 10, end: 14));
      // 空文本 / 越界
      expect(currentSegmentRange('', 0), (start: 0, end: 0));
      expect(currentSegmentRange(text, -1), (start: 0, end: 4));
      expect(currentSegmentRange(text, 99), (start: 10, end: 14));
    });

    testWidgets('#85-6 排版设置 →「行段聚焦」开关 → 开启 + 控制器同步', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 打开菜单 → 排版设置（批次96-9：行段聚焦开关移入排版设置）
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tapMenuScrolled(tester, '排版设置');
      await tester.pumpAndSettle();

      // 排版设置内：行段聚焦开关默认关
      final sw = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '行段聚焦'),
      );
      expect(sw.value, isFalse);

      // 点击开关 → 开启
      await tester.tap(find.text('行段聚焦'));
      await tester.pumpAndSettle();

      // 开关状态更新 + 控制器已同步（淡化渲染即时生效）+ 编辑器内容不变
      final sw2 = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '行段聚焦'),
      );
      expect(sw2.value, isTrue);
      final ctrl =
          tester.widget<TextField>(editorTextField()).controller!
              as FocusAwareEditingController;
      expect(ctrl.focusMode, isTrue);
      expect(ctrl.text, '这是一个大雪纷飞的夜晚。');
    });

    testWidgets('#85-7 预置开启 → 排版设置内「行段聚焦」默认开', (tester) async {
      await AppStateRepository(db).setValue('editor_focus_mode', '1');

      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tapMenuScrolled(tester, '排版设置');
      await tester.pumpAndSettle();

      final sw = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '行段聚焦'),
      );
      expect(sw.value, isTrue);
    });

    testWidgets('#85-8 开启聚焦 → buildTextSpan 淡化光标段以外内容', (tester) async {
      final chRepo = ChapterRepository(db);
      final multiId = await chRepo.createChapter(
        manuscriptId,
        title: '多段',
        content: '第一段。\n第二段。\n第三段。',
      );
      await tester.pumpWidget(
        buildWritingPage(id: multiId, msId: manuscriptId),
      );
      await tester.pumpAndSettle();

      final ctrl =
          tester.widget<TextField>(editorTextField()).controller!
              as FocusAwareEditingController;
      ctrl.focusMode = true;
      // 光标在第二段内
      ctrl.selection = const TextSelection.collapsed(offset: 6);
      final span = ctrl.buildTextSpan(
        context: tester.element(editorTextField()),
        style: const TextStyle(color: Colors.black, fontSize: 16),
        withComposing: false,
      );

      final children = span.children!.map((s) => s as TextSpan).toList();
      expect(children.length, 3);
      // 前缀/后缀淡化（alpha 0.32），当前段正常
      expect(children[0].text, '第一段。\n');
      expect(children[0].style?.color, Colors.black.withValues(alpha: 0.32));
      expect(children[1].text, '第二段。');
      expect(children[1].style?.color, isNull);
      expect(children[2].text, '\n第三段。');
      expect(children[2].style?.color, Colors.black.withValues(alpha: 0.32));
    });
  });

  group('批次85-③：快捷短语（P2 效率组③）', () {
    /// 快捷短语弹层内的输入框（编辑器 TextField 也在场，需限定 BottomSheet 内）
    Finder sheetField() => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );

    /// 编辑器正文 TextField（AppBar 标题也是 TextField，需限定编辑器容器内）
    Finder editorTextField() => find.byKey(const Key('chapterContentField'));

    Future<void> openQuickPhrases(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      // 批次96-6：菜单非全屏，「快捷短语」在滚动区外 → 滚动后点击
      await tapMenuScrolled(tester, '快捷短语');
      await tester.pumpAndSettle();
    }

    testWidgets('#85-9 ⋮ 菜单 → 快捷短语 → 弹层打开（标题 + 输入框 + 空态）', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openQuickPhrases(tester);

      expect(find.text('快捷短语'), findsOneWidget);
      expect(sheetField(), findsOneWidget);
      expect(find.textContaining('还没有快捷短语'), findsOneWidget);
    });

    testWidgets('#85-10 输入 + 添加 → 列表显示 + 落库', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openQuickPhrases(tester);

      await tester.enterText(sheetField(), '夜里的风很轻。');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(find.text('夜里的风很轻。'), findsOneWidget);
      final list = await AppStateRepository(db).listQuickPhrases();
      expect(list, ['夜里的风很轻。']);
    });

    testWidgets('#85-11 点击短语 → 插入编辑器光标处 + 保存 + 轻提示', (tester) async {
      await AppStateRepository(db).addQuickPhrase('他紧了紧衣领。');

      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openQuickPhrases(tester);

      await tester.tap(find.text('他紧了紧衣领。'));
      await tester.pumpAndSettle();

      // 光标默认在文末 → 追加；即时保存到 store
      final field = tester.widget<TextField>(editorTextField());
      expect(field.controller!.text, '这是一个大雪纷飞的夜晚。他紧了紧衣领。');
      expect(
        container.read(writingStoreProvider(chapterId).notifier).currentContent,
        '这是一个大雪纷飞的夜晚。他紧了紧衣领。',
      );
      expect(find.text('已插入'), findsOneWidget);
      // 收尾：SnackBar 关闭
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('#85-12 删除短语 → 列表移除 + 落库', (tester) async {
      final repo = AppStateRepository(db);
      await repo.addQuickPhrase('短语一');
      await repo.addQuickPhrase('短语二');

      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openQuickPhrases(tester);

      expect(find.text('短语一'), findsOneWidget);
      expect(find.text('短语二'), findsOneWidget);

      // 删除第一条（列表首行）
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('短语一'), findsNothing);
      expect(find.text('短语二'), findsOneWidget);
      expect(await repo.listQuickPhrases(), ['短语二']);
    });
  });

  group('批次85-④：当前文风（P2 教学组④）', () {
    Future<void> openStyleProfile(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      // 批次96-6：菜单非全屏，「当前文风」在滚动区外 → 滚动后点击
      await tapMenuScrolled(tester, '当前文风');
      await tester.pumpAndSettle();
    }

    testWidgets('#85-13 无画像 → 当前文风空态', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openStyleProfile(tester);

      expect(find.text('当前文风'), findsOneWidget);
      expect(find.textContaining('还没有文风画像'), findsOneWidget);
    });

    testWidgets('#85-14 预置画像 → summary + 五维标签 + 置信度', (tester) async {
      // student_model.session_id 外键需先有 session
      final sid = await SessionRepository(db).createBlankSession(title: '文风测试');
      await StudentModelRepository(db).updateStyleProfile(
        sid,
        WritingStyleProfile(
          sensory: SensoryPreference.visual,
          rhythm: RhythmPreference.long,
          narrativeDistance: NarrativeDistance.intimate,
          toneTexture: ToneTexture.poetic,
          structure: StructureInstinct.linear,
          summary: '你擅长用画面推动故事，句子偏长但节奏稳。',
          confidence: 0.85,
          updatedAt: 1754995200,
        ),
      );

      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openStyleProfile(tester);

      expect(find.text('你擅长用画面推动故事，句子偏长但节奏稳。'), findsOneWidget);
      // 五维标签
      expect(find.text('视觉型'), findsOneWidget);
      expect(find.text('长句型'), findsOneWidget);
      expect(find.text('贴身型'), findsOneWidget);
      expect(find.text('诗意型'), findsOneWidget);
      expect(find.text('线性型'), findsOneWidget);
      // 置信度 + 更新时间
      expect(find.textContaining('识别置信度 85%'), findsOneWidget);
      expect(find.textContaining('更新于'), findsOneWidget);
    });
  });

  group('批次85-⑤：写作统计（P2 教学组⑤）', () {
    Future<void> openWritingStats(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      // 批次96-6：菜单非全屏，「写作统计」在滚动区外 → 滚动后点击
      await tapMenuScrolled(tester, '写作统计');
      await tester.pumpAndSettle();
    }

    testWidgets('#85-15 无写作记录 → 写作统计空态', (tester) async {
      // 独立 db：不预置任何有字数的章节，确保曲线为空
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      final container2 = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db2)],
      );
      addTearDown(() {
        container2.dispose();
        db2.close();
      });
      final msRepo2 = ManuscriptRepository(db2);
      final chRepo2 = ChapterRepository(db2);
      final ms2 = await msRepo2.createManuscript(title: '空作品');
      final ch2 = await chRepo2.createChapter(ms2, title: '空章', content: '');

      await pumpWithContainer(tester, container2, id: ch2);
      await openWritingStats(tester);

      expect(find.text('写作统计'), findsOneWidget);
      expect(find.text('还没有写作记录'), findsOneWidget);
      expect(find.textContaining('多写几天'), findsOneWidget);
    });

    testWidgets('#85-16 有写作记录 → 成长曲线 + 摘要行 + 今天高亮', (tester) async {
      // setUp 已预置章节「这是一个大雪纷飞的夜晚。」（12 字）
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openWritingStats(tester);

      expect(find.text('写作统计'), findsOneWidget);
      // 曲线卡片
      expect(find.text('写作成长曲线'), findsOneWidget);
      // 摘要行：总字数 / 诊断次数 / 活跃天数（限定在曲线卡片内，避免命中 AppBar 字数）
      expect(
        find.descendant(
          of: find.byType(WritingCurveChart),
          matching: find.text('12字'),
        ),
        findsOneWidget,
      );
      // 摘要行 + 图例各有「字数」「诊断」，故各 2 处
      expect(
        find.descendant(
          of: find.byType(WritingCurveChart),
          matching: find.text('字数'),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byType(WritingCurveChart),
          matching: find.text('诊断'),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byType(WritingCurveChart),
          matching: find.text('活跃天数'),
        ),
        findsOneWidget,
      );
      // 今天标签
      expect(find.text('今天'), findsOneWidget);
      // 鼓励文案
      expect(find.text('每天进步一点点，成长看得见。'), findsOneWidget);
    });

    testWidgets('#87-3 统计窗口：默认近14天 + 切换近7/30天重新加载', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openWritingStats(tester);

      ChoiceChip chip(int d) =>
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '近$d天'));

      // 默认近 14 天选中
      expect(chip(14).selected, isTrue);
      expect(find.text('今天'), findsOneWidget);

      // 切近 7 天
      await tester.tap(find.text('近7天'));
      await tester.pumpAndSettle();
      expect(chip(7).selected, isTrue);
      expect(chip(14).selected, isFalse);
      expect(find.text('今天'), findsOneWidget);

      // 切近 30 天
      await tester.tap(find.text('近30天'));
      await tester.pumpAndSettle();
      expect(chip(30).selected, isTrue);
      expect(find.text('今天'), findsOneWidget);
    });

    testWidgets('#87-3 空态下窗口切换可用', (tester) async {
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      final container2 = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db2)],
      );
      addTearDown(() {
        container2.dispose();
        db2.close();
      });
      final msRepo2 = ManuscriptRepository(db2);
      final chRepo2 = ChapterRepository(db2);
      final ms2 = await msRepo2.createManuscript(title: '空作品');
      final ch2 = await chRepo2.createChapter(ms2, title: '空章', content: '');

      await pumpWithContainer(tester, container2, id: ch2);
      await openWritingStats(tester);
      expect(find.text('还没有写作记录'), findsOneWidget);

      await tester.tap(find.text('近7天'));
      await tester.pumpAndSettle();
      expect(find.text('还没有写作记录'), findsOneWidget);
    });
  });

  group('批次85-⑥：智能标点（P2 效率组⑥）', () {
    testWidgets('#85-17 输入「 → 自动补全「」且光标居中', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      final editorFinder = find.byKey(const Key('chapterContentField'));
      // 编辑器有预置内容，而 enterText 是整段替换 → 先清空，
      // 再输入单个左配对符（等价真实逐字符输入）→ 触发智能补全
      await tester.enterText(editorFinder, '');
      await tester.enterText(editorFinder, '「');
      await tester.pumpAndSettle();

      final controller = tester.widget<TextField>(editorFinder).controller!;
      expect(controller.text, '「」');
      // 光标停在一对引号中间，可继续书写
      expect(controller.selection.baseOffset, 1);
    });

    testWidgets('#85-18 普通输入不受智能标点影响', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      final editorFinder = find.byKey(const Key('chapterContentField'));
      await tester.tap(editorFinder);
      await tester.enterText(editorFinder, '你好');
      await tester.pumpAndSettle();

      final controller = tester.widget<TextField>(editorFinder).controller!;
      expect(controller.text, '你好');
    });
  });

  group('批次86-①：回收板（P2 工具组①）', () {
    Finder editorFinder() {
      return find.byKey(const Key('chapterContentField'));
    }

    Future<void> openRecycleBin(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      // 批次96-6：菜单非全屏，「回收板」在滚动区外 → 滚动后点击
      await tapMenuScrolled(tester, '回收板');
      await tester.pumpAndSettle();
    }

    // ── extractRemovedText 纯函数单测 ──
    test('extractRemovedText：纯删除（中间段）→ 返回被删片段', () {
      expect(extractRemovedText('abcXYZdef', 'abcdef'), 'XYZ');
    });

    test('extractRemovedText：尾部删除 → 返回被删片段', () {
      expect(extractRemovedText('abcdefXYZ', 'abcdef'), 'XYZ');
    });

    test('extractRemovedText：插入 → null', () {
      expect(extractRemovedText('abcdef', 'abcXYZdef'), isNull);
    });

    test('extractRemovedText：替换（增删混合）→ null', () {
      expect(extractRemovedText('abcXYZdef', 'abc123def'), isNull);
    });

    test('extractRemovedText：等长 / 变长 → null', () {
      expect(extractRemovedText('abc', 'abc'), isNull);
      expect(extractRemovedText('abc', 'abcd'), isNull);
    });

    testWidgets('#86-1 ⋮ 菜单 → 回收板 → 弹层打开 + 空态', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openRecycleBin(tester);

      expect(find.text('回收板'), findsOneWidget);
      expect(find.textContaining('回收板是空的'), findsOneWidget);
    });

    testWidgets('#86-2 删除 ≥8 字片段 → 自动入回收板 + 列表可见', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      final editor = editorFinder();
      // 编辑器原文「这是一个大雪纷飞的夜晚。」→ 整段替换为前 2 字（等价删除 10 字）
      await tester.enterText(editor, '这是');
      await tester.pumpAndSettle();

      await openRecycleBin(tester);
      expect(find.text('一个大雪纷飞的夜晚。'), findsOneWidget);
    });

    testWidgets('#86-3 短删除（<8 字）不入回收板', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      final editor = editorFinder();
      // 只删句号（1 字）→ 不足阈值
      await tester.enterText(editor, '这是一个大雪纷飞的夜晚');
      await tester.pumpAndSettle();

      await openRecycleBin(tester);
      expect(find.textContaining('回收板是空的'), findsOneWidget);
    });

    testWidgets('#86-4 点击条目 → 恢复插入光标处 + 落库', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      final editor = editorFinder();
      await tester.enterText(editor, '这是');
      await tester.pumpAndSettle();
      await openRecycleBin(tester);

      await tester.tap(find.text('一个大雪纷飞的夜晚。'));
      await tester.pumpAndSettle();

      final controller = tester.widget<TextField>(editor).controller!;
      expect(controller.text, '这是一个大雪纷飞的夜晚。');
    });

    testWidgets('#86-5 行尾删除 → 条目移除 + 回到空态', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      final editor = editorFinder();
      await tester.enterText(editor, '这是');
      await tester.pumpAndSettle();
      await openRecycleBin(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('回收板是空的'), findsOneWidget);
    });

    testWidgets('#86-6 清空回收板 → 空态', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      final editor = editorFinder();
      await tester.enterText(editor, '这是');
      await tester.pumpAndSettle();
      await openRecycleBin(tester);

      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('回收板是空的'), findsOneWidget);
    });
  });

  group('批次86-②：自定义工具栏（P2 工具组②）', () {
    testWidgets('#86-2 预置标点配置 → 标点栏只渲染配置项', (tester) async {
      await AppStateRepository(db).setPunctuationBarConfig(['comma', 'period']);
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      final bar = find.byType(PunctuationBar);
      expect(
        find.descendant(of: bar, matching: find.text('，')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('。')),
        findsOneWidget,
      );
      expect(find.descendant(of: bar, matching: find.text('？')), findsNothing);
    });

    testWidgets('#86-2 未配置 → 标点栏渲染默认 15 项', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      final bar = find.byType(PunctuationBar);
      final texts = tester.widgetList<Text>(
        find.descendant(of: bar, matching: find.byType(Text)),
      );
      expect(texts, hasLength(15));
      expect(
        find.descendant(of: bar, matching: find.text('缩进')),
        findsOneWidget,
      );
    });
  });

  group('批次87-②：回收板增强（收尾②）', () {
    Finder editorFinder() {
      return find.byKey(const Key('chapterContentField'));
    }

    Future<void> openRecycleBin(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      // 批次96-6：菜单非全屏，「回收板」在滚动区外 → 滚动后点击
      await tapMenuScrolled(tester, '回收板');
      await tester.pumpAndSettle();
    }

    testWidgets('#87-2 恢复即移除开关：默认关 + 切换持久化', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openRecycleBin(tester);

      // 默认关
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      // 打开开关 → 落库
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        await AppStateRepository(db).getRecycleBinRemoveOnRestore(),
        isTrue,
      );

      // 重开弹层 → 开关仍开（用户级持久化）
      Navigator.of(tester.element(find.byType(RecycleBinSheet))).pop();
      await tester.pumpAndSettle();
      await openRecycleBin(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('#87-2 默认关：恢复后条目保留', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      final editor = editorFinder();
      await tester.enterText(editor, '这是');
      await tester.pumpAndSettle();
      await openRecycleBin(tester);

      await tester.tap(find.text('一个大雪纷飞的夜晚。'));
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(editor).controller!;
      expect(controller.text, '这是一个大雪纷飞的夜晚。');

      // 重开 → 条目仍在（默认保留，可手动删）
      await openRecycleBin(tester);
      expect(find.text('一个大雪纷飞的夜晚。'), findsOneWidget);
    });

    testWidgets('#87-2 开启开关：恢复后条目自动移除', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      final editor = editorFinder();
      await tester.enterText(editor, '这是');
      await tester.pumpAndSettle();
      await openRecycleBin(tester);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('一个大雪纷飞的夜晚。'));
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(editor).controller!;
      expect(controller.text, '这是一个大雪纷飞的夜晚。');

      // 重开 → 空态（条目已随恢复移除）
      await openRecycleBin(tester);
      expect(find.textContaining('回收板是空的'), findsOneWidget);
    });

    testWidgets('#87-2 超龄条目自动清理（30 天）', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await AppStateRepository(db).setValue(
        'recycle_bin',
        jsonEncode([
          {'content': '三十天前的旧草稿', 'deletedAt': now - 31 * 24 * 3600},
          {'content': '刚删的新片段', 'deletedAt': now},
        ]),
      );
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await openRecycleBin(tester);

      expect(find.text('刚删的新片段'), findsOneWidget);
      expect(find.text('三十天前的旧草稿'), findsNothing);
    });
  });

  group('批次87-④：低成本小项打包（收尾④）', () {
    Finder editorFinder() {
      return find.byKey(const Key('chapterContentField'));
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }

    /// 打开 ⋮ 菜单并点击指定菜单项（先滚动到可见，菜单已 15 项）
    Future<void> tapMenuText(WidgetTester tester, String text) async {
      await openMenu(tester);
      final target = find.text(text);
      await tester.scrollUntilVisible(
        target,
        80,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> openOutline(WidgetTester tester) async {
      await tapMenuText(tester, '大纲');
    }

    // ── A 智能标点开关 ──
    testWidgets('#87-4 智能标点开关：默认开 + 关闭落库', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      // 批次96-9：智能标点开关移入排版设置
      await tapMenuScrolled(tester, '排版设置');
      await tester.pumpAndSettle();

      // 智能标点开关默认开
      final sw = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '智能标点'),
      );
      expect(sw.value, isTrue);

      // 点击关闭 → 落库 + 开关状态更新
      await tester.tap(find.text('智能标点'));
      await tester.pumpAndSettle();
      expect(
        await AppStateRepository(db).getSmartPunctuationEnabled(),
        isFalse,
      );
      final sw2 = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '智能标点'),
      );
      expect(sw2.value, isFalse);
    });

    testWidgets('#87-4 关闭智能标点后：输入「不再自动补全', (tester) async {
      await AppStateRepository(db).setSmartPunctuationEnabled(false);
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      final editor = editorFinder();
      await tester.enterText(editor, '');
      await tester.enterText(editor, '「');
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(editor).controller!;
      expect(controller.text, '「', reason: '关闭后输入左符不自动补右符');
    });

    // ── C 版本差异角标 ──
    test('diffCounts：新增 → (n,0)；删除 → (0,n)；相同 → (0,0)', () {
      expect(diffCounts('你好', '你好世界'), (2, 0));
      expect(diffCounts('你好世界', '你好'), (0, 2));
      expect(diffCounts('你好', '你好'), (0, 0));
    });

    testWidgets('#87-4 版本列表行显示差异角标', (tester) async {
      final repo = AppStateRepository(db);
      // 版本一相对当前（当前=初始正文「这是一个大雪纷飞的夜晚。」）新增「，雪很大」
      // （字符级 LCS 把句号匹配为 same）→ +4
      await repo.addChapterVersion(chapterId, '这是一个大雪纷飞的夜晚，雪很大。');
      // 版本二与当前一致 → 无角标
      await repo.addChapterVersion(chapterId, '这是一个大雪纷飞的夜晚。');

      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();
      await tapMenuText(tester, '版本时光机');

      expect(find.text('+4'), findsOneWidget);
    });

    // ── D 大纲抽屉快速确认/拒绝 ──
    testWidgets('#87-4 大纲抽屉快速确认实体 + 拒绝印象', (tester) async {
      final repo = OutlineRepository(db);
      await repo.insertEntity(
        manuscriptId: manuscriptId,
        entityType: 'character',
        entityKey: '林晚',
      );
      final entities = await repo.listEntities(manuscriptId);
      final linwan = entities.firstWhere((e) => e.entityKey == '林晚');
      await repo.insertImpression(
        entityId: linwan.id,
        impression: '怕黑',
        sourceChapterNo: 1,
      );

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();
      await openOutline(tester);

      // pending 实体「确认」 + pending 印象「确认/拒绝」→ 2 个待确认 + 1 个拒绝
      expect(find.text('待确认'), findsNWidgets(2));
      expect(find.text('拒绝'), findsOneWidget);

      // 拒绝印象 → 印象消失（实体确认按钮仍在）
      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();
      expect(find.text('怕黑'), findsNothing);
      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('已拒绝这条梗概'), findsOneWidget);

      // 确认实体 → 实体待确认消失（active 实体仍在）
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(find.text('待确认'), findsNothing);
      expect(find.text('林晚'), findsOneWidget);
    });
  });

  group('批次88-2：对话按钮（FAB 可拖动/隐藏）', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }

    /// 打开 ⋮ 菜单并点击指定菜单项（先滚动到可见，菜单已 16 项）
    Future<void> tapMenuText(WidgetTester tester, String text) async {
      await openMenu(tester);
      final target = find.text(text);
      await tester.scrollUntilVisible(
        target,
        80,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    testWidgets('#88-2 排版设置「显示对话按钮」→ 关闭隐藏 + 落库', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 默认显示 FAB
      expect(find.byKey(const Key('aiChatFab')), findsOneWidget);

      // 批次96-9：对话按钮开关移入排版设置
      await tapMenuScrolled(tester, '排版设置');
      await tester.pumpAndSettle();

      // 显示对话按钮开关默认开
      final sw = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '显示对话按钮'),
      );
      expect(sw.value, isTrue);

      // 开关在弹层滚动区外 → 先滚动到可见再点击
      await tester.ensureVisible(find.text('显示对话按钮'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示对话按钮'));
      await tester.pumpAndSettle();
      expect(await AppStateRepository(db).getFabVisible(), isFalse);
      expect(find.byKey(const Key('aiChatFab')), findsNothing);
      final sw2 = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '显示对话按钮'),
      );
      expect(sw2.value, isFalse);
    });

    testWidgets('#88-2 预置隐藏 → 页面无 FAB；排版设置「显示对话按钮」→ 恢复', (tester) async {
      await AppStateRepository(db).setFabVisible(false);
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('aiChatFab')), findsNothing);

      // 批次96-9：对话按钮开关移入排版设置
      await tapMenuScrolled(tester, '排版设置');
      await tester.pumpAndSettle();

      // 显示对话按钮开关默认关
      final sw = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '显示对话按钮'),
      );
      expect(sw.value, isFalse);

      // 开关在弹层滚动区外 → 先滚动到可见再点击
      await tester.ensureVisible(find.text('显示对话按钮'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示对话按钮'));
      await tester.pumpAndSettle();
      expect(await AppStateRepository(db).getFabVisible(), isTrue);
      expect(find.byKey(const Key('aiChatFab')), findsOneWidget);
    });

    testWidgets('#88-2 长按拖动 FAB → 位置变化 + 落库 fab_position', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const Key('aiChatFab'));
      final before = tester.getTopLeft(fabFinder);

      // 长按 500ms 后拖动
      final gesture = await tester.startGesture(tester.getCenter(fabFinder));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
      await gesture.moveBy(const Offset(-80, -120));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final after = tester.getTopLeft(fabFinder);
      expect(after.dx, lessThan(before.dx), reason: 'FAB 应向左移动');
      expect(after.dy, lessThan(before.dy), reason: 'FAB 应向上移动');
      // 松手已持久化位置（saved 为 body 内局部坐标，与渲染 Positioned 参数一致）
      final saved = await AppStateRepository(db).getFabPosition();
      expect(saved, isNotNull);
      final positioned = tester.widget<Positioned>(
        find.ancestor(of: fabFinder, matching: find.byType(Positioned)).first,
      );
      expect(positioned.left, closeTo(saved!.dx, 1));
      expect(positioned.top, closeTo(saved.dy, 1));
    });

    testWidgets('#88-2 排版设置「恢复右下角位置」→ 清持久化 + FAB 回默认角', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const Key('aiChatFab'));
      final defaultPos = tester.getTopLeft(fabFinder);

      // 先拖动换位
      final gesture = await tester.startGesture(tester.getCenter(fabFinder));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
      await gesture.moveBy(const Offset(-100, -100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(fabFinder), isNot(defaultPos));

      // 排版设置 → 恢复右下角位置（弹层较长，先滚动到可见）
      await tapMenuText(tester, '排版设置');
      final resetBtn = find.text('恢复右下角位置');
      await tester.scrollUntilVisible(
        resetBtn,
        80,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(fabFinder), defaultPos);
      expect(await AppStateRepository(db).getFabPosition(), isNull);
    });
  });

  group('批次88-4：段落格式（自动首行缩进 / 段间空行）', () {
    // 批次90：editorContainer 内有标题+正文两个 TextField → 正文用专用 key 定位
    Finder editorFinder() => find.byKey(const Key('chapterContentField'));

    /// 打开排版设置弹层（菜单滚动 + 弹层内滚动到指定文本可见）
    Future<void> openSettings(WidgetTester tester, String label) async {
      await tapMenuScrolled(tester, '排版设置');
      final target = find.text(label);
      await tester.scrollUntilVisible(
        target,
        80,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }

    testWidgets('#88-4 默认缩进开：回车自动补两格缩进', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      await tester.enterText(editorFinder(), '第一段。\n');
      await tester.pumpAndSettle();

      final controller = tester.widget<TextField>(editorFinder()).controller!;
      expect(controller.text, '第一段。\n\u3000\u3000');
    });

    testWidgets('#88-4 关闭缩进开关 → 回车不补 + 落库', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      await openSettings(tester, '自动首行缩进');
      await tester.tap(find.text('自动首行缩进'));
      await tester.pumpAndSettle();
      expect(
        await AppStateRepository(db).getValue('editor_indent_paragraph'),
        '0',
      );
      // 关闭弹层后回车不再补缩进
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();

      await tester.enterText(editorFinder(), '第一段。\n');
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(editorFinder()).controller!;
      expect(controller.text, '第一段。\n');
    });

    testWidgets('#88-4 开启段间空行 → 回车补空行 + 缩进 + 落库', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      await openSettings(tester, '段间空行');
      await tester.tap(find.text('段间空行'));
      await tester.pumpAndSettle();
      expect(await AppStateRepository(db).getValue('editor_blank_line'), '1');
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();

      await tester.enterText(editorFinder(), '第一段。\n');
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(editorFinder()).controller!;
      expect(controller.text, '第一段。\n\n\u3000\u3000');
    });

    testWidgets('#88-4 排版设置「应用到全文」：移除全文缩进 + 落库', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 预置两段（默认缩进开，回车自动补缩进）
      await tester.enterText(editorFinder(), '一段。\n');
      await tester.pumpAndSettle();
      await tester.enterText(editorFinder(), '一段。\n\u3000\u3000二段。');
      await tester.pumpAndSettle();

      // 关闭缩进开关 → 应用到全文 → 全文移除缩进
      await openSettings(tester, '自动首行缩进');
      await tester.tap(find.text('自动首行缩进'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('应用到全文'),
        80,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('应用到全文'));
      await tester.pumpAndSettle();

      final controller = tester.widget<TextField>(editorFinder()).controller!;
      expect(controller.text, '一段。\n二段。');
      expect(find.text('已应用到全文'), findsOneWidget);
      // 落库
      final chapter = await ChapterRepository(db).getChapter(chapterId);
      expect(chapter?.content, '一段。\n二段。');
    });
  });

  group('批次91：编辑器P0双bug（保存debounce / 撤销历史解绑 / 标点栏undo-redo）', () {
    Finder editorFinder() => find.byKey(const Key('chapterContentField'));

    testWidgets('#91-1 输入后 300ms 合并保存：窗口内不落库、到期落库一次', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 输入内容（300ms 合并窗口内）
      await tester.enterText(editorFinder(), '合并保存内容');
      await tester.pump(const Duration(milliseconds: 100));

      // 窗口未到 → DB 未更新
      var chapter = await ChapterRepository(db).getChapter(chapterId);
      expect(chapter?.content, '这是一个大雪纷飞的夜晚。');

      // 等待 300ms debounce 到期 → 落库
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      chapter = await ChapterRepository(db).getChapter(chapterId);
      expect(chapter?.content, '合并保存内容');

      // 收尾：清历史 debounce timer（1.5s）
      await tester.pump(const Duration(milliseconds: 1600));
    });

    testWidgets('#91-3 标点栏撤销图标 → 回退内容（撤销栈与保存独立）', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 输入新内容 → 停 1.5s 落历史点
      await tester.enterText(editorFinder(), '新内容');
      await tester.pump(const Duration(milliseconds: 1600));

      // 标点栏撤销图标（AppBar 也有同图标 → 限定在 PunctuationBar 内）
      final undoInBar = find.descendant(
        of: find.byType(PunctuationBar),
        matching: find.byIcon(Icons.undo),
      );
      expect(undoInBar, findsOneWidget);
      await tester.tap(undoInBar);
      await tester.pump();

      final controller = tester.widget<TextField>(editorFinder()).controller!;
      expect(controller.text, '这是一个大雪纷飞的夜晚。');
    });

    testWidgets('#91-3 标点栏重做图标 → 恢复被撤销的内容', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      await tester.enterText(editorFinder(), '可重做的内容');
      await tester.pump(const Duration(milliseconds: 1600));

      final bar = find.byType(PunctuationBar);
      // 先撤销再重做
      await tester.tap(
        find.descendant(of: bar, matching: find.byIcon(Icons.undo)),
      );
      await tester.pump();
      var controller = tester.widget<TextField>(editorFinder()).controller!;
      expect(controller.text, '这是一个大雪纷飞的夜晚。');

      await tester.tap(
        find.descendant(of: bar, matching: find.byIcon(Icons.redo)),
      );
      await tester.pump();
      controller = tester.widget<TextField>(editorFinder()).controller!;
      expect(controller.text, '可重做的内容');
    });

    testWidgets('#91-4 无效选区点击标点 → 不 RangeError，插入末尾', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 构造无效选区（ed-p2-3 防御场景：offset 为负 → selection.isValid false）
      final controller = tester.widget<TextField>(editorFinder()).controller!;
      controller.value = const TextEditingValue(
        text: '正文内容',
        selection: TextSelection.collapsed(offset: -1),
      );
      await tester.pump();

      // 点击标点 → 不抛 RangeError，插入到文本末尾
      await tester.tap(find.text('，'));
      await tester.pump();

      expect(controller.text, '正文内容，');

      // 收尾：清保存/历史 timer
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
    });
  });

  group('批次94-4：暗夜编辑器背景联动取反', () {
    testWidgets('#94-4 暗夜背景 → AppBar 底色/标点栏取反', (tester) async {
      // 预置暗夜背景（用户级持久化，跨章节生效）
      await AppStateRepository(db).setValue('editor_background', 'dark');
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 编辑器容器背景（既有 #82-2 断言，保持）
      final editor = tester.widget<Container>(
        find.byKey(const Key('editorContainer')),
      );
      expect(editor.color, const Color(0xFF26282B));

      // AppBar 底色取反（暗夜 = #1E2126）
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, const Color(0xFF1E2126));

      // 标点栏容器底色取反（暗夜 = #26282B）
      final punctContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(PunctuationBar),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(punctContainer.color, const Color(0xFF26282B));

      // 标点文字色取反（浅色）
      final commaText = tester.widget<Text>(find.text('，'));
      expect(commaText.style?.color, const Color(0xFFE8EAED));
    });

    testWidgets('#94-4 亮色背景（默认米纸）→ 周边保持亮色令牌不变', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, AppColors.background);

      final punctContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(PunctuationBar),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(punctContainer.color, AppColors.background);
    });
  });

  group('批次95-3：标题→正文焦点切换', () {
    testWidgets('#95-3 键盘「下一项」→ 聚焦正文', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 聚焦标题
      await tester.tap(find.byKey(const Key('chapterTitleField')));
      await tester.pumpAndSettle();

      // 键盘「下一项」动作 → onSubmitted 聚焦正文
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();

      final contentField = tester.widget<TextField>(
        find.byKey(const Key('chapterContentField')),
      );
      expect(contentField.focusNode?.hasFocus, isTrue);
    });
  });

  group('批次95-4：写作页面包屑', () {
    testWidgets('#95-4 卷内章节 → AppBar 显示「卷名 · 章名」', (tester) async {
      final volRepo = VolumeRepository(db);
      final v1 = await volRepo.createVolume(manuscriptId, title: '第一卷');
      await volRepo.setChapterVolume(chapterId, v1);

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();

      expect(find.text('第一卷 · 第一章：启程'), findsOneWidget);
    });

    testWidgets('#95-4 未分卷 → 面包屑仅章名', (tester) async {
      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();

      // AppBar 面包屑 + 标题大区块 = 2 处
      expect(find.text('第一章：启程'), findsNWidgets(2));
    });
  });

  group('批次95-2：窄屏 AI 面板响应式', () {
    testWidgets('#95-2 窄屏(<600dp) → 底部抽屉覆盖 + 正文仍可见', (tester) async {
      // 逻辑视口 400x800（devicePixelRatio 3 → 物理 1200x2400）
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // 预创建会话（面板 _initSession 复用，避免空 manuscript_id 外键失败）
      await SessionRepository(
        db,
      ).getOrCreateSessionForChapter(manuscriptId, chapterId);

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('aiChatFab')));
      await tester.pumpAndSettle();

      expect(find.byType(WritingCoachPanel), findsOneWidget);
      // 正文编辑器仍在（覆盖而非替换）
      expect(find.byKey(const Key('chapterContentField')), findsOneWidget);
      // 面板铺满屏宽（底部抽屉而非 280px 侧栏）
      final panelSize = tester.getSize(find.byType(WritingCoachPanel));
      expect(panelSize.width, 400);
    });

    testWidgets('#95-2 宽屏(≥600dp) → 保持 Row 并排侧栏', (tester) async {
      // 默认逻辑视口 800x600 → 宽屏路径
      await SessionRepository(
        db,
      ).getOrCreateSessionForChapter(manuscriptId, chapterId);

      await tester.pumpWidget(buildWritingPage(msId: manuscriptId));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('aiChatFab')));
      await tester.pumpAndSettle();

      expect(find.byType(WritingCoachPanel), findsOneWidget);
      // 侧栏宽 = (800*0.55).clamp(280,480) = 440（浮点容差）
      final panelSize = tester.getSize(find.byType(WritingCoachPanel));
      expect(panelSize.width, closeTo(440, 0.5));
      // 正文右边缘 ≤ 面板左边缘（Row 并排，正文不被覆盖）
      final contentRect = tester.getRect(
        find.byKey(const Key('chapterContentField')),
      );
      final panelRect = tester.getRect(find.byType(WritingCoachPanel));
      expect(contentRect.right, lessThanOrEqualTo(panelRect.left + 1));
    });
  });

  group('批次95-1：划词菜单跟随选区', () {
    Finder contentEditable() => find.descendant(
      of: find.byKey(const Key('chapterContentField')),
      matching: find.byType(EditableText),
    );

    void selectRange(
      WidgetTester tester, {
      required int start,
      required int end,
    }) {
      final editable = tester.state<EditableTextState>(contentEditable());
      editable.updateEditingValue(
        TextEditingValue(
          text: editable.textEditingValue.text,
          selection: TextSelection(baseOffset: start, extentOffset: end),
        ),
      );
    }

    testWidgets('#95-1 菜单跟随选区：不再固定在右上角 + 位置随选区移动', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 选中开头 12 字
      selectRange(tester, start: 0, end: 12);
      await tester.pump();
      expect(find.text('诊断这段文字'), findsOneWidget);
      final pos1 = tester.getTopLeft(find.text('诊断这段文字'));
      // 菜单在选区下方（不再固定 top:4 右上角）
      expect(pos1.dy, greaterThan(4));

      // 选区后移到文本中部
      selectRange(tester, start: 5, end: 12);
      await tester.pump();
      expect(find.text('诊断这段文字'), findsOneWidget);
      final pos2 = tester.getTopLeft(find.text('诊断这段文字'));
      // 选区右移 → 菜单左边界右移（跟随）
      expect(pos2.dx, greaterThan(pos1.dx));
    });

    testWidgets('#95-1 文本底部选区 → 菜单翻转到选区上方（屏幕外翻转）', (tester) async {
      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      // 用长文本（≈40 行）让选区落在编辑器底部，触发下方放不下 → 翻转
      final editable = tester.state<EditableTextState>(contentEditable());
      final longText = List.filled(40, '霜叶红于二月花，秋风起时满林金。').join();
      editable.updateEditingValue(
        TextEditingValue(
          text: longText,
          selection: TextSelection(
            baseOffset: longText.length - 6,
            extentOffset: longText.length,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('诊断这段文字'), findsOneWidget);

      // 选区 caret 的全局 y（文本末尾、多行底部）
      final caretRect = editable.renderEditable.getLocalRectForCaret(
        TextPosition(offset: longText.length),
      );
      final caretTop = editable.renderEditable
          .localToGlobal(caretRect.topLeft)
          .dy;
      final menuTop = tester.getTopLeft(find.text('诊断这段文字')).dy;
      // 菜单翻到选区上方（纯纯/笔落跟随）
      expect(menuTop, lessThan(caretTop));
    });
  });

  group('批次96-7：菜单拖拽调整篇幅', () {
    testWidgets('#96-7 打开菜单读记忆高度 + 拖拽后落库', (tester) async {
      final repo = AppStateRepository(db);
      await repo.setEditorMenuHeight(0.70);

      await tester.pumpWidget(buildWritingPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // 初始高度 = 记忆值 0.70（用户级持久化生效）
      final dss = tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet),
      );
      expect(dss.initialChildSize, closeTo(0.70, 0.001));

      // 连续上推拖拽 → 高度变化 + 落库
      final scrollable = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      for (var i = 0; i < 8; i++) {
        await tester.drag(scrollable, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      final saved = await repo.getEditorMenuHeight();
      expect(saved, inInclusiveRange(0.30, 0.85));
      // 拖拽后高度吸附到档位，不再是初始 0.70
      expect(saved, isNot(closeTo(0.70, 0.01)));
    });

    testWidgets('#96-7 未设置时默认 0.55', (tester) async {
      expect(
        await AppStateRepository(db).getEditorMenuHeight(),
        closeTo(0.55, 0.001),
      );
    });
  });

  group('批次96-8：一键排版（原记灵感位置，参考百灵布局）', () {
    testWidgets('#96-8 AppBar 一键排版 → 按开关批量排版全文 + 落库', (tester) async {
      final chRepo = ChapterRepository(db);
      final id = await chRepo.createChapter(
        manuscriptId,
        title: '排版章',
        content: '第一段。\n第二段。',
      );
      await tester.pumpWidget(buildWritingPage(id: id, msId: manuscriptId));
      await tester.pumpAndSettle();

      // AppBar 一键排版按钮（原「记灵感」位置）
      expect(find.byIcon(Icons.format_align_left), findsOneWidget);
      expect(find.byIcon(Icons.lightbulb_outline), findsNothing);
      await tester.tap(find.byIcon(Icons.format_align_left));
      await tester.pumpAndSettle();

      // 默认开关（首行缩进开/段间空行关）：每段补两个全角空格
      final field = tester.widget<TextField>(
        find.byKey(const Key('chapterContentField')),
      );
      expect(field.controller!.text, '\u3000\u3000第一段。\n\u3000\u3000第二段。');
      expect(find.text('已应用到全文'), findsOneWidget);
      // 已落库
      final saved = await chRepo.getChapter(id);
      expect(saved!.content, '\u3000\u3000第一段。\n\u3000\u3000第二段。');

      // 再点 → 已是当前段落格式（无重复排版）
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.format_align_left));
      await tester.pumpAndSettle();
      expect(find.text('全文已是当前段落格式'), findsOneWidget);
    });
  });
}
