# ADR-C90 章节列表单一真源收敛（CR-24）

- 状态：**已接受**
- 日期：2026-09-08
- 决策者：主 Agent（经 CR-24 立项确认）
- 关联：CR-21 / CR-22 / CR-23（同土壤批次）

## 背景

`chapterStoreProvider`（StateNotifier，乐观更新，详情页真源）与
`chapterListProvider`（FutureProvider，直读 DB，树抽屉等消费方）双通道并存。
写操作后需手工同步，`ref.invalidate` 散落 **6 文件 14 处**：

- manuscript_detail_chapter ×4（写 store 后同步 FutureProvider）
- manuscript_detail_volume ×1（loadChapters 后同步）
- chapter_recycle_bin_page ×2（loadChapters + invalidate 双刷新）
- chapter_tree_drawer ×4（直写 repo 后同步）
- writing_page ×2 / writing_page_chapter_nav ×1（直写 repo 后同步）

**风险**：任何一处漏 invalidate → 双通道数据不一致（乐观更新 vs DB 直读），
且未来新增写路径时易遗漏同步点（CR-21 就是「建卷入口」与列表刷新脱节）。

## 决策

**单一真源 = `chapterStoreProvider`**，`chapterListProvider` 降级为派生视图。

### 1. chapterStoreProvider 自动加载

provider 创建时 `Future.microtask(loadChapters)`——任何消费方首次 watch
即拿到真实数据，不再依赖详情页显式 `loadChapters()`。

### 2. chapterListProvider 改为派生

```dart
final chapterListProvider = Provider.family<List<Chapter>, String>(
  (ref, msId) => ref.watch(chapterStoreProvider(msId)).chapters,
);
```

- 不再直读 DB；写操作经 store 后列表自动同步，无需 invalidate
- 类型从 `FutureProvider<List<Chapter>>`（AsyncValue）变 `Provider<List<Chapter>>`
  （同步 List）——**唯一 watch 方（树抽屉）已适配**；测试零直接引用

### 3. invalidate 清理（14 处 → 分类处置）

| 类别 | 位置 | 处置 |
|---|---|---|
| 写 store 后同步 FutureProvider（冗余） | manuscript_detail_chapter ×4、manuscript_detail_volume ×1、recycle_bin ×2 | **删除** invalidate（store 已更新，派生视图自动同步） |
| 直写 repo 后同步 | chapter_tree_drawer ×4、writing_page ×2、chapter_nav ×1 | **改为** `loadChapters()` 刷新 store（幂等） |

## 被否方案

- **写操作统一经 store**：改动面过大（树抽屉/回收站/写作页全部写路径改造 +
  状态方法扩展），本批不做；收敛后写路径只剩「store 方法」与「直写+loadChapters」
  两类，未来可再收。
- **直接移除 chapterListProvider**：名字保留作派生视图，避免 import 冲击与
  外部引用断裂（R-010 最小范围）。

## 验证

- 全量测试通过（2600+ 基线）
- 树抽屉/详情页/回收站/写作页章节列表在写操作后一致（真机复核清单）

## 后续（未做）

- 写操作全部收敛到 store 方法（消灭「直写+loadChapters」路径）
- 卷列表（volumeListProvider）同款收敛评估
