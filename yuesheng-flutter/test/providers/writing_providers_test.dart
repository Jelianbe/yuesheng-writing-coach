// ─────────────────────────────────────────────────────────────
// writing_providers_test — WritingStore 状态管理单元测试
//
// 覆盖路径：
//   1. 初始状态：isLoading=true / localContent 空
//   2. loadChapter：加载章节 + localContent = chapter.content + isLoading=false
//   3. updateContent + saveNow：localContent 更新 + wordCount 同步 + DB 内容匹配
//   4. saveNow：DB 内容正确写入（重新读取 DB 验证）
//   5. setFontSize / setLineSpacing：状态更新
//   6. toggleAiPanel：open → close → open
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/writing_providers.dart';

void main() {
  late AppDatabase db;
  late String chapterId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());

    // 预置：创建稿件 + 章节，内容为 "初始内容"
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final msId = await msRepo.createManuscript(title: '测试作品');
    chapterId = await chRepo.createChapter(msId, title: '第一章', content: '初始内容');
  });

  tearDown(() async {
    await db.close();
  });

  /// 构造 ProviderContainer，override appDatabaseProvider 用内存 DB
  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 预置一份「严格晚于章节 updatedAt」的草稿。
  /// 章节创建与存草稿可能落在同一 unix 秒（savedAt == updatedAt），
  /// 而 RN 判定用严格 `>`，故手动把 savedAt 调大为章节更新 +100 秒。
  Future<void> saveNewerDraft(
    String chapterId,
    String title,
    String content,
  ) async {
    final appStateRepo = AppStateRepository(db);
    await appStateRepo.saveChapterDraft(chapterId, title, content);

    final ch = await ChapterRepository(db).getChapter(chapterId);
    final row =
        await (db.select(db.appStates)
              ..where((t) => t.key.equals('chapter_draft:$chapterId')))
            .getSingleOrNull();
    if (ch == null || row == null) return;
    final value = jsonDecode(row.value) as Map<String, dynamic>;
    value['savedAt'] = ch.updatedAt + 100;
    await appStateRepo.setValue('chapter_draft:$chapterId', jsonEncode(value));
  }

  group('WritingStore', () {
    test('#1 初始状态：isLoading=true / localContent 空', () {
      final container = buildContainer();
      final state = container.read(writingStoreProvider(chapterId));

      expect(state.isLoading, true);
      expect(state.localContent, isEmpty);
      expect(state.wordCount, 0);
      expect(state.chapter, isNull);
      expect(state.error, isNull);
      expect(state.isAiPanelOpen, false);
      expect(state.lastSavedAt, isNull);
      expect(state.isSaving, false);
      expect(state.fontSize, 16.0);
      expect(state.lineSpacing, 1.6);
    });

    test(
      '#2 loadChapter：加载章节 + localContent=chapter.content + isLoading=false',
      () async {
        final container = buildContainer();
        final notifier = container.read(
          writingStoreProvider(chapterId).notifier,
        );

        await notifier.loadChapter();

        final state = container.read(writingStoreProvider(chapterId));
        expect(state.isLoading, false);
        expect(state.chapter, isNotNull);
        expect(state.chapter!.id, chapterId);
        expect(state.localContent, '初始内容');
        expect(state.wordCount, '初始内容'.length);
        expect(state.error, isNull);
      },
    );

    test(
      '#3 updateContent + saveNow：localContent 更新 + wordCount 同步 + DB 内容匹配',
      () async {
        final container = buildContainer();
        final notifier = container.read(
          writingStoreProvider(chapterId).notifier,
        );

        // 先加载章节
        await notifier.loadChapter();

        // 更新内容
        notifier.updateContent('编辑后的新内容');

        // 验证 localContent + wordCount 已同步
        var state = container.read(writingStoreProvider(chapterId));
        expect(state.localContent, '编辑后的新内容');
        expect(state.wordCount, '编辑后的新内容'.length);

        // 保存到 DB
        await notifier.saveNow();

        state = container.read(writingStoreProvider(chapterId));
        expect(state.isSaving, false);
        expect(state.lastSavedAt, isNotNull);

        // 重新从 DB 读取验证
        final chRepo = ChapterRepository(db);
        final ch = await chRepo.getChapter(chapterId);
        expect(ch!.content, '编辑后的新内容');
        expect(ch.wordCount, '编辑后的新内容'.length);
      },
    );

    test('#4 saveNow：DB 内容正确写入（重新读取 DB 验证）', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);

      await notifier.loadChapter();
      notifier.updateContent('保存测试内容');
      await notifier.saveNow();

      // 用独立的 ChapterRepository 重新读取 DB
      final chRepo = ChapterRepository(db);
      final ch = await chRepo.getChapter(chapterId);
      expect(ch, isNotNull);
      expect(ch!.content, '保存测试内容');
      expect(ch.wordCount, '保存测试内容'.length);
    });

    test('#5 setFontSize / setLineSpacing：状态更新', () {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);

      notifier.setFontSize(20.0);
      expect(container.read(writingStoreProvider(chapterId)).fontSize, 20.0);

      notifier.setLineSpacing(1.8);
      expect(container.read(writingStoreProvider(chapterId)).lineSpacing, 1.8);
    });

    test('#6 toggleAiPanel：open → close → open', () {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);

      // 初始关闭
      expect(
        container.read(writingStoreProvider(chapterId)).isAiPanelOpen,
        false,
      );

      // open
      notifier.toggleAiPanel();
      expect(
        container.read(writingStoreProvider(chapterId)).isAiPanelOpen,
        true,
      );

      // close
      notifier.toggleAiPanel();
      expect(
        container.read(writingStoreProvider(chapterId)).isAiPanelOpen,
        false,
      );

      // open again
      notifier.toggleAiPanel();
      expect(
        container.read(writingStoreProvider(chapterId)).isAiPanelOpen,
        true,
      );
    });

    // ── Task 9: 自动保存 debounce + dispose 契约 ──
    // WritingStore 本身不做 debounce（调度在 WritingPage），
    // 这里验证 store 契约：连续 updateContent 后 saveNow 只保留最后值。
    test(
      '#7 连续 updateContent（模拟 1s debounce 窗口内多次输入）→ saveNow → DB 仅保留最后值',
      () async {
        final container = buildContainer();
        final notifier = container.read(
          writingStoreProvider(chapterId).notifier,
        );

        await notifier.loadChapter();

        // 模拟 1s debounce 窗口内的连续输入
        notifier.updateContent('第一段');
        notifier.updateContent('第一段第二段');

        // debounce 到期后触发 saveNow
        await notifier.saveNow();

        // DB 内容应为最后一次 updateContent 的值
        final chRepo = ChapterRepository(db);
        final ch = await chRepo.getChapter(chapterId);
        expect(ch!.content, '第一段第二段');
        expect(ch.wordCount, '第一段第二段'.length);
      },
    );

    test(
      '#8 _dirty 状态下强制 saveNow（模拟 dispose 时强制保存）→ lastSavedAt 非 null + DB 落盘',
      () async {
        final container = buildContainer();
        final notifier = container.read(
          writingStoreProvider(chapterId).notifier,
        );

        await notifier.loadChapter();

        // 多次编辑（模拟用户输入后未等 debounce 即离开页面）
        notifier.updateContent('A');
        notifier.updateContent('AB');
        notifier.updateContent('ABC');

        // 保存前状态
        var state = container.read(writingStoreProvider(chapterId));
        expect(state.localContent, 'ABC');
        expect(state.wordCount, 3);

        // 模拟 dispose 时强制 saveNow
        await notifier.saveNow();

        // 保存后状态
        state = container.read(writingStoreProvider(chapterId));
        expect(state.lastSavedAt, isNotNull);
        expect(state.isSaving, false);

        // DB 已落盘
        final chRepo = ChapterRepository(db);
        final ch = await chRepo.getChapter(chapterId);
        expect(ch!.content, 'ABC');
      },
    );

    // ── 批次 23 B5：离线模式 + 本地草稿 ──

    test('#9 离线保存：setOffline(true) → saveNow 存本地草稿，DB 内容不变', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);

      await notifier.loadChapter();
      notifier.setOffline(true);

      notifier.updateContent('离线编辑的内容');
      await notifier.saveNow();

      var state = container.read(writingStoreProvider(chapterId));
      expect(state.isOffline, true);
      expect(state.hasDraft, true);
      expect(state.lastSavedAt, isNull, reason: '离线保存不更新 lastSavedAt');

      // DB 内容不变（仍是「初始内容」）
      final chRepo = ChapterRepository(db);
      final ch = await chRepo.getChapter(chapterId);
      expect(ch!.content, '初始内容');

      // 草稿已写入 app_state
      final appStateRepo = AppStateRepository(db);
      final draft = await appStateRepo.getChapterDraft(chapterId);
      expect(draft, isNotNull);
      expect(draft!.content, '离线编辑的内容');
    });

    test('#10 恢复网络自动同步：离线编辑 → 上线 → 草稿写入章节', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);

      await notifier.loadChapter();
      notifier.setOffline(true);
      notifier.updateContent('离线编辑待同步');
      await notifier.saveNow();
      expect(container.read(writingStoreProvider(chapterId)).hasDraft, true);

      // 恢复网络 → 自动同步草稿到章节
      await notifier.setOffline(false);

      final state = container.read(writingStoreProvider(chapterId));
      expect(state.isOffline, false);
      expect(state.hasDraft, false, reason: '同步后草稿清除');
      expect(state.lastSavedAt, isNotNull);

      // DB 内容 = 草稿内容
      final chRepo = ChapterRepository(db);
      final ch = await chRepo.getChapter(chapterId);
      expect(ch!.content, '离线编辑待同步');

      // 草稿已清除
      final appStateRepo = AppStateRepository(db);
      final draft = await appStateRepo.getChapterDraft(chapterId);
      expect(draft, isNull);
    });

    test(
      '#11 草稿恢复检测：草稿较新（savedAt > 章节 updatedAt）→ loadChapter 标记 hasDraft',
      () async {
        // 预置较新草稿（保存时间晚于章节更新）
        await saveNewerDraft(chapterId, '第一章', '未保存的草稿内容');

        final container = buildContainer();
        final notifier = container.read(
          writingStoreProvider(chapterId).notifier,
        );
        await notifier.loadChapter();

        final state = container.read(writingStoreProvider(chapterId));
        expect(state.hasDraft, true);
        // 编辑器内容仍是章节原文（待用户选择恢复）
        expect(state.localContent, '初始内容');
      },
    );

    test('#12 restoreDraft：恢复草稿内容到编辑器', () async {
      await saveNewerDraft(chapterId, '第一章', '草稿恢复内容');

      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();
      expect(container.read(writingStoreProvider(chapterId)).hasDraft, true);

      notifier.restoreDraft();

      final state = container.read(writingStoreProvider(chapterId));
      expect(state.localContent, '草稿恢复内容');
      expect(state.wordCount, '草稿恢复内容'.length);
      // 恢复后草稿保留（待后续保存/同步落库）
      expect(state.hasDraft, true);
    });

    test('#13 discardDraft：放弃草稿 → 清除草稿 + hasDraft=false', () async {
      await saveNewerDraft(chapterId, '第一章', '将被放弃的草稿');

      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();
      expect(container.read(writingStoreProvider(chapterId)).hasDraft, true);

      await notifier.discardDraft();

      final state = container.read(writingStoreProvider(chapterId));
      expect(state.hasDraft, false);
      // 编辑器内容仍是章节原文
      expect(state.localContent, '初始内容');
      // 草稿已从存储清除
      final draft = await AppStateRepository(db).getChapterDraft(chapterId);
      expect(draft, isNull);
    });

    test('#14 陈旧草稿：savedAt <= 章节 updatedAt → loadChapter 自动清除', () async {
      // 先存草稿，再更新章节（章节 updatedAt 变新 → 草稿变旧）
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.saveChapterDraft(chapterId, '第一章', '陈旧草稿');
      final chRepo = ChapterRepository(db);
      await chRepo.saveChapterContent(chapterId, '章节已更新的内容');

      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();

      final state = container.read(writingStoreProvider(chapterId));
      expect(state.hasDraft, false);
      expect(state.localContent, '章节已更新的内容');
      // 陈旧草稿已被清除
      final draft = await appStateRepo.getChapterDraft(chapterId);
      expect(draft, isNull);
    });

    // ── 批次 24 B7：撤销/重做（复刻 RN useUndoRedo）──

    test('#15 B7 undo/redo：commitHistory 提交点 + 回退前进', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();

      // 编辑版本 A → 提交（lastCommitted: 初始内容 → A）
      notifier.updateContent('版本A');
      notifier.commitHistory();
      expect(container.read(writingStoreProvider(chapterId)).canUndo, true);

      // 编辑版本 B → 提交
      notifier.updateContent('版本B');
      notifier.commitHistory();
      var state = container.read(writingStoreProvider(chapterId));
      expect(state.canUndo, true);
      expect(state.canRedo, false);

      // 撤销 → 版本A
      notifier.undo();
      state = container.read(writingStoreProvider(chapterId));
      expect(state.localContent, '版本A');
      expect(state.canUndo, true);
      expect(state.canRedo, true);

      // 再撤销 → 初始内容
      notifier.undo();
      state = container.read(writingStoreProvider(chapterId));
      expect(state.localContent, '初始内容');
      expect(state.canUndo, false);

      // 重做 → 版本A
      notifier.redo();
      state = container.read(writingStoreProvider(chapterId));
      expect(state.localContent, '版本A');
      expect(state.canRedo, true);
    });

    test('#16 B7 debounce 1.5s 后自动提交历史（批次91-2 撤销栈独立）', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();

      // 编辑后 debounce 未到 → 尚无历史
      notifier.updateContent('自动提交A');
      expect(container.read(writingStoreProvider(chapterId)).canUndo, false);

      // 等待 debounce（1.5s）→ 自动提交
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(container.read(writingStoreProvider(chapterId)).canUndo, true);
    });

    test('#17 B7 历史上限 10：超过后只保留最近 10 个', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();

      // 连续编辑 + 提交 15 次（past 上限 10）
      for (int i = 0; i < 15; i++) {
        notifier.updateContent('版本$i');
        notifier.commitHistory();
      }

      // 连续撤销 10 次（应恰好用尽 past 栈）
      for (int i = 0; i < 10; i++) {
        notifier.undo();
      }
      final state = container.read(writingStoreProvider(chapterId));
      expect(state.canUndo, false);
      // 撤销 10 次后应回到第 5 个版本（版本4）
      expect(state.localContent, '版本4');
    });

    test('#18 B7 loadChapter 重置历史栈', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();

      // 产生历史
      notifier.updateContent('编辑内容');
      notifier.commitHistory();
      expect(container.read(writingStoreProvider(chapterId)).canUndo, true);

      // 重新加载章节 → 历史清空
      await notifier.loadChapter();
      final state = container.read(writingStoreProvider(chapterId));
      expect(state.canUndo, false);
      expect(state.canRedo, false);
      expect(state.localContent, '初始内容');
    });
  });

  group('批次82：版本快照（P0 四件套之③）', () {
    /// 生成 200+ 字符内容（用于跨越快照边界）
    String longContent(int n) => '字' * n;

    test('#82-3-1 跨 200 字边界 saveNow → 落版本快照（时光机留痕）', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter(); // 初始 4 字 → 快照阈值 200

      // 初始无快照
      expect(await AppStateRepository(db).listChapterVersions(chapterId), isEmpty);

      // 更新到 205 字 → saveNow → 跨 200 边界 → 快照
      notifier.updateContent(longContent(205));
      await notifier.saveNow();

      final versions = await AppStateRepository(db).listChapterVersions(chapterId);
      expect(versions.length, 1);
      expect(versions.first.wordCount, 205);
      expect(versions.first.content, longContent(205));
    });

    test('#82-3-2 未跨边界不产生快照；同一 200 窗口内多次保存只落一次', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();

      // 50 字（未到 200）→ 无快照
      notifier.updateContent(longContent(50));
      await notifier.saveNow();
      expect(
        await AppStateRepository(db).listChapterVersions(chapterId),
        isEmpty,
      );

      // 199 字 → 仍无快照
      notifier.updateContent(longContent(199));
      await notifier.saveNow();
      expect(
        await AppStateRepository(db).listChapterVersions(chapterId),
        isEmpty,
      );

      // 200 字 → 恰好跨线 → 快照
      notifier.updateContent(longContent(200));
      await notifier.saveNow();
      expect(
        (await AppStateRepository(db).listChapterVersions(chapterId)).length,
        1,
      );

      // 同一窗口内（201 字，下一边界 400）→ 不重复快照
      notifier.updateContent(longContent(201));
      await notifier.saveNow();
      expect(
        (await AppStateRepository(db).listChapterVersions(chapterId)).length,
        1,
      );
    });

    test('#82-3-3 快照上限 50：超出丢弃最旧，最新在前', () async {
      final repo = AppStateRepository(db);
      for (int i = 0; i < 60; i++) {
        await repo.addChapterVersion(chapterId, '版本内容$i');
      }
      final versions = await repo.listChapterVersions(chapterId);
      expect(versions.length, 50);
      // 最新在前：第一个是 版本内容59，最后是 版本内容10
      expect(versions.first.content, '版本内容59');
      expect(versions.last.content, '版本内容10');
    });

    test('#82-3-4 restoreVersion：当前内容先存新版本 + 状态回退（恢复可逆）', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();

      notifier.updateContent('当前正在写的新内容');
      await notifier.restoreVersion('恢复到的旧版本内容');

      // 状态回退
      final state = container.read(writingStoreProvider(chapterId));
      expect(state.localContent, '恢复到的旧版本内容');
      expect(state.wordCount, '恢复到的旧版本内容'.length);

      // 恢复前内容已存为新版本（最新在前）
      final versions = await AppStateRepository(db).listChapterVersions(chapterId);
      expect(versions.first.content, '当前正在写的新内容');
    });
  });

  group('批次91：保存 debounce + 撤销历史解绑', () {
    test('#91-1 scheduleSave 300ms 合并：窗口内多次输入只落库一次', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();

      // 连续输入（模拟 300ms 窗口内的多次按键）→ 只调度一次合并保存
      notifier.updateContent('第一段');
      notifier.scheduleSave();
      notifier.updateContent('第一段第二段');
      notifier.scheduleSave();

      // 窗口未到 → 尚未保存
      expect(container.read(writingStoreProvider(chapterId)).lastSavedAt, isNull);
      final chRepo = ChapterRepository(db);
      expect((await chRepo.getChapter(chapterId))!.content, '初始内容');

      // 等待 300ms debounce → 落库一次（内容为最后值）
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(container.read(writingStoreProvider(chapterId)).lastSavedAt, isNotNull);
      expect((await chRepo.getChapter(chapterId))!.content, '第一段第二段');
    });

    test('#91-1 scheduleSave 后立即 saveNow → 定时器取消不重复保存', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();

      notifier.updateContent('手动保存内容');
      notifier.scheduleSave();
      // 手动立即保存（如 dispose 强制保存）→ 取消未决定时器
      await notifier.saveNow();
      expect(notifier.hasPendingSave, isFalse);

      // 再等 400ms → 不触发第二次写库（无 pending timer）
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final chRepo = ChapterRepository(db);
      expect((await chRepo.getChapter(chapterId))!.content, '手动保存内容');
    });

    test('#91-2 保存不提交历史点：saveNow 后 canUndo 仍 false（撤销栈独立）', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();

      // 编辑 + 立即保存（批次31 时代：每次按键即历史点；91-2 后：保存与历史解绑）
      notifier.updateContent('保存但未停输入');
      await notifier.saveNow();

      // 保存完成但历史尚未提交（用户仍在输入 → 无历史点）
      expect(container.read(writingStoreProvider(chapterId)).lastSavedAt, isNotNull);
      expect(container.read(writingStoreProvider(chapterId)).canUndo, isFalse);

      // 停输入 1.5s → 历史提交
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(container.read(writingStoreProvider(chapterId)).canUndo, isTrue);
    });

    test('#91-2 快速连续编辑不耗尽历史上限：仅停输入才落历史点', () async {
      final container = buildContainer();
      final notifier = container.read(writingStoreProvider(chapterId).notifier);
      await notifier.loadChapter();

      // 模拟连续输入（每次按键触发 updateContent，均不落历史点）
      for (int i = 0; i < 25; i++) {
        notifier.updateContent('连续输入$i');
        await notifier.saveNow(); // 保存频繁，但不产生历史点
      }
      expect(container.read(writingStoreProvider(chapterId)).canUndo, isFalse);

      // 停输入 1.5s → 只产生 1 个历史点（最后一次输入）
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      final state = container.read(writingStoreProvider(chapterId));
      expect(state.canUndo, isTrue);
      // 撤销一次即可回到「初始内容」（仅一次提交点，未耗尽 10 条上限）
      notifier.undo();
      expect(container.read(writingStoreProvider(chapterId)).localContent, '初始内容');
      expect(container.read(writingStoreProvider(chapterId)).canUndo, isFalse);
    });
  });
}
