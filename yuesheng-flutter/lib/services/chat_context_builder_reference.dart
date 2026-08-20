// ─────────────────────────────────────────────────────────────
// chat_context_builder 主题分组拆分：chat_context_builder_reference.dart（R-019 ≤300 行）
// 引用内容上下文：ReferenceItem/锚点工具/MaterialCapabilityImpl/ManuscriptDetail/ChapterBrief/buildReferencesContext/ReferenceResolvers。逐字迁移自 chat_context_builder.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_context_builder.dart';
// ─── 引用内容上下文 ───────────────────────────────────────────

/// 引用项（buildReferencesContext 的输入）
class ReferenceItem {
  final String refType; // 'manuscript' | 'chapter' | 'file'
  final String refId;
  final String title;
  final int isPrimary; // 0 | 1
  final String? manuscriptId;

  /// A-3：选段锚点 JSON（如 {"chapterId":"ch-1","startPara":0,"endPara":1}），chapter  引用专用
  final String? excerptRange;

  const ReferenceItem({
    required this.refType,
    required this.refId,
    required this.title,
    required this.isPrimary,
    this.manuscriptId,
    this.excerptRange,
  });
}

/// A-3：解析段落锚点 JSON（{"chapterId":..,"startPara":..,"endPara":..}），非法返回 null。
/// 旧版 {"start","end"} 字符偏移格式已废弃，返回 null（安全降级）。
ParagraphAnchor? parseParagraphAnchor(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) return null;
    final chapterId = decoded['chapterId'];
    final start = decoded['startPara'];
    final end = decoded['endPara'];
    if (chapterId is! String || start is! num || end is! num) return null;
    if (start < 0 || end < start) return null;
    return ParagraphAnchor(chapterId, start.toInt(), end.toInt());
  } catch (_) {
    return null;
  }
}

/// A-3：按段落锚点截取窗口（段落以 `\n` 分段）。越界自动 clamp；
/// startPara 超出段落数 → 回退整段内容（安全降级）。
String extractParagraphWindow(String content, int startPara, int endPara) {
  if (content.isEmpty) return content;
  final paras = content.split('\n');
  if (paras.isEmpty) return content;
  if (startPara >= paras.length) return content;
  final s = startPara.clamp(0, paras.length - 1);
  final e = endPara.clamp(s, paras.length - 1);
  return paras.sublist(s, e + 1).join('\n');
}

/// 素材能力实现（选项 B 依赖倒置）
///
/// 委托到既有纯函数 formatAttachedFilesContext / parseParagraphAnchor /
/// extractParagraphWindow，自身无状态；UI 经 MaterialCapability 消费。

/// 顶层实现别名：供 MaterialCapabilityImpl 委托，避免同名实例方法自递归
///（Dart 方法体内同名标识符优先解析为实例成员）。见 2026-08-19 修复。
ParagraphAnchor? _parseParagraphAnchorImpl(String? json) =>
    parseParagraphAnchor(json);

String _extractParagraphWindowImpl(String content, int startPara, int endPara) =>
    extractParagraphWindow(content, startPara, endPara);

class MaterialCapabilityImpl implements MaterialCapability {
  const MaterialCapabilityImpl();

  @override
  String? formatAttachedFiles(List<AttachedFileInfo> files) =>
      formatAttachedFilesContext(files);

  @override
  ParagraphAnchor? parseParagraphAnchor(String? excerptRangeJson) =>
      _parseParagraphAnchorImpl(excerptRangeJson);

  @override
  String extractParagraphWindow(String content, int startPara, int endPara) =>
      _extractParagraphWindowImpl(content, startPara, endPara);
}

/// 引用内容解析后的详情（manuscript 类型需要聚合章节信息）
class ManuscriptDetail {
  final String genre;
  final String? description;
  final List<ChapterBrief> chapters;

  const ManuscriptDetail({
    required this.genre,
    required this.description,
    required this.chapters,
  });
}

class ChapterBrief {
  final String id;
  final String title;
  final int wordCount;
  final int sortOrder;
  final String content;

  const ChapterBrief({
    required this.id,
    required this.title,
    required this.wordCount,
    required this.sortOrder,
    required this.content,
  });
}

/// 构建引用内容上下文（注入 system prompt）
///
/// 真源：yuesheng-android/src/services/chat-context-builder.ts L221-338
///
/// 输入：
///   refs: 该会话的所有引用项（listReferencesOfSession 返回值）
///   resolvers: 引用内容解析器（注入式依赖，避免在纯函数里直接调用 DAO）
///
/// 简化项（与 RN 原版偏差）：
///   - resolvers.fileResolver 直接返回 AttachedFileRow（合并 getAttachedFile 到一条路径）
///   - resolvers.manuscriptResolver 返回聚合后的 _ManuscriptDetail（包含章节列表）
///   - 没用 `__DEV__` 日志（Flutter 无对应宏）
String buildReferencesContext(
  List<ReferenceItem> refs, {
  required ReferenceResolvers resolvers,
}) {
  if (refs.isEmpty) return '';

  final totalBudget = ContextBudget.totalBudget;
  final primaryRatio = ContextBudget.primaryRatio;
  final secondaryRatio = ContextBudget.secondaryRatio;

  final primaryRefs = refs.where((r) => r.isPrimary == 1).toList();
  final secondaryRefs = refs.where((r) => r.isPrimary != 1).toList();

  int primaryBudget;
  int secondaryBudget;
  if (primaryRefs.isEmpty) {
    primaryBudget = 0;
    secondaryBudget =
        (totalBudget / (secondaryRefs.isNotEmpty ? secondaryRefs.length : 1))
            .floor();
  } else {
    primaryBudget = (totalBudget * primaryRatio / primaryRefs.length).floor();
    secondaryBudget =
        (totalBudget *
                secondaryRatio /
                (secondaryRefs.isNotEmpty ? secondaryRefs.length : 1))
            .floor();
  }

  final parts = <String>[];
  parts.add('## 内容位置判断');
  parts.add(
    '请先判断以下引用内容在原文中的位置（开头/中段/结尾/全局），然后仅对 position_sensitivity 匹配的症候进行诊断。',
  );
  parts.add('');
  parts.add('## 引用内容');
  parts.add('以下是用户当前引用的作品和章节内容。');
  parts.add('');
  parts.add('**优先级规则**：标注【主引用】的是用户主要希望分析的目标，请以主引用为核心分析对象；');
  parts.add('标注【次要引用】的仅作为辅助参考，用于理解上下文和写作风格，不应作为诊断的主要依据。');
  parts.add('如果预算不足以完整呈现内容，主引用的完整性优先于次要引用。');
  parts.add('');

  for (final ref in refs) {
    final budget = ref.isPrimary == 1 ? primaryBudget : secondaryBudget;
    final tag = ref.isPrimary == 1 ? '【主引用】' : '【次要引用】';

    if (ref.refType == 'file') {
      final file = resolvers.fileResolver(ref.refId);
      if (file != null) {
        // A-1 止血：素材不再走 50KB 独立预算，与章节引用共享同一档位 budget，
        // 消除「双预算体系 token 爆炸」。
        final content = file.content.length > budget
            ? '${file.content.substring(0, budget)}\n...(内容已截断，超过$budget字符)'
            : file.content;
        parts.add('### 【素材文件】${file.fileName}（${file.fileRole}）');
        parts.add('```');
        parts.add(content);
        parts.add('```');
        parts.add('');
      }
    } else if (ref.refType == 'chapter') {
      final chapter = resolvers.chapterResolver(ref.refId);
      if (chapter != null) {
        parts.add('### $tag 章节：${ref.title}（${chapter.wordCount}字）');
        // A-3：主引用带段落锚点 → 优先展开锚点窗口（替代整章）；无锚点则全章截断
        final anchor = parseParagraphAnchor(ref.excerptRange);
        if (ref.isPrimary == 1 && anchor != null && anchor.chapterId == ref.refId) {
          parts.add('【选段诊断】以下为主引用章节中的选中片段（段落锚点截取）');
          parts.add('```');
          parts.add(extractParagraphWindow(chapter.content, anchor.startPara, anchor.endPara));
          parts.add('```');
          parts.add('');
        } else {
          parts.add('【位置提示】请根据内容判断这是原文章节的开头/中段/结尾');
          parts.add('```');
          parts.add(smartTruncate(chapter.content, budget));
          parts.add('```');
          parts.add('');
        }
      }
    } else if (ref.refType == 'manuscript') {
      final detail = resolvers.manuscriptResolver(ref.refId);
      if (detail == null) continue;

      final totalWords = detail.chapters.fold<int>(
        0,
        (sum, ch) => sum + ch.wordCount,
      );

      final metaLines = <String>[];
      metaLines.add('### $tag 作品：${ref.title}');
      metaLines.add('- 类型：${detail.genre.isEmpty ? "未指定" : detail.genre}');
      metaLines.add('- 章节数：${detail.chapters.length}');
      metaLines.add('- 总字数：$totalWords');
      if (detail.description != null && detail.description!.isNotEmpty) {
        metaLines.add('- 简介：${detail.description}');
      }
      metaLines.add('');
      metaLines.add('**目录概览：**');
      for (final ch in detail.chapters) {
        metaLines.add('  ${ch.sortOrder}. ${ch.title}（${ch.wordCount}字）');
      }
      metaLines.add('');
      metaLines.add('【位置提示】以下预览章节可能位于作品的不同位置，请根据内容判断每段的位置');

      final metaLength = metaLines.join('\n').length;
      final previewBudget = budget - metaLength;
      final previewCount =
          detail.chapters.length < ContextBudget.manuscriptPreviewChapterCount
          ? detail.chapters.length
          : ContextBudget.manuscriptPreviewChapterCount;
      if (previewCount > 0 && previewBudget > ContextBudget.minPreviewBudget) {
        final chBudget = (previewBudget / previewCount).floor();
        for (int i = 0; i < previewCount; i++) {
          final ch = detail.chapters[i];
          metaLines.add('#### ${ch.title}');
          metaLines.add('```');
          metaLines.add(smartTruncate(ch.content, chBudget));
          metaLines.add('```');
          metaLines.add('');
        }
      }

      parts.addAll(metaLines);
    }
  }

  return parts.join('\n');
}

/// 引用内容解析器（依赖注入，避免纯函数直接调 DAO）
class ReferenceResolvers {
  final AttachedFileRow? Function(String fileId) fileResolver;
  final ChapterBrief? Function(String chapterId) chapterResolver;
  final ManuscriptDetail? Function(String manuscriptId) manuscriptResolver;

  const ReferenceResolvers({
    required this.fileResolver,
    required this.chapterResolver,
    required this.manuscriptResolver,
  });
}
