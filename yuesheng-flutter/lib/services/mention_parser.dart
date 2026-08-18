// ─────────────────────────────────────────────────────────────
// mention_parser — @ 引用语法解析器
//
// 批次71：展示格式从编号（@W001/C003）改为文字标题（@作品标题/章节标题）
//   - 插入输入框的文本：@我的小说 或 @我的小说/第三章
//   - 解析时用标题库反查 refId（标题长度降序前缀匹配，避免短标题误匹配）
//   - trade-off：作品/章节改名后旧消息里的引用会失效
//     （降级为普通文本，不崩溃）
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../data/repositories/reference_repository.dart';

/// 解析出的单条引用
class ParsedMention {
  final String raw;
  final String refType; // 'manuscript' | 'chapter' | 'file'
  final String refId;
  final String title;

  /// 所属作品 ID（manuscript/chapter/file 均填；批次71 @ 引用可视化跳转用）
  final String? manuscriptId;

  const ParsedMention({
    required this.raw,
    required this.refType,
    required this.refId,
    required this.title,
    this.manuscriptId,
  });
}

/// 解析结果
class ParseResult {
  final List<ParsedMention> mentions;

  /// 清理后的文本（移除已解析成功的 @ 引用）
  final String cleanedText;

  const ParseResult({required this.mentions, required this.cleanedText});
}

/// 判断标题后是否为边界（空白、标点、行尾）
/// 非边界时不应匹配（如 "@书一开始" 不应匹配到 "书一"）
bool _isTitleBoundary(String after) {
  if (after.isEmpty) return true;
  return RegExp(r"""^[\s。，！？；：、.,!?:;）)」』】》"']""").hasMatch(after);
}

/// A-2 稳定 ID 标记：@[manuscript:ID] / @[chapter:ID] / @[file:ID]
/// 分隔符 @[ : ] 在中文写作中几乎不出现，refId 为生成型 ID（无 ]/ :），无歧义。
final RegExp _kMarkerRegExp = RegExp(r'^\[([a-z]+):([^\]]+)\]');

/// @ 引用解析服务
class MentionParser {
  final ManuscriptRepository _msRepo;
  final ChapterRepository _chRepo;
  final ReferenceRepository _refRepo;

  MentionParser(this._msRepo, this._chRepo, this._refRepo);

  /// 解析文本中的所有 @ 引用
  ///
  /// 格式：@作品标题 或 @作品标题/章节标题
  /// 用标题库做前缀匹配（长度降序），标题后必须是边界或 /
  Future<ParseResult> parseMentions(String text) async {
    final mentions = <ParsedMention>[];
    final manuscripts = await _msRepo.listManuscripts();

    // 按标题长度降序，避免 "书一" 误匹配 "书一二"
    final sortedMs = List.of(manuscripts)
      ..sort((a, b) => b.title.length.compareTo(a.title.length));

    final chaptersCache = <String, List<Chapter>>{};
    final filesCache = <String, List<AttachedFileRow>>{};

    int idx = 0;
    while (idx < text.length) {
      final atIdx = text.indexOf('@', idx);
      if (atIdx == -1) break;
      if (atIdx + 1 >= text.length) break;

      final afterAt = text.substring(atIdx + 1);

      // A-2：稳定 ID 标记 @[type:id]（改名免疫，ID 优先）
      // 优先于 legacy @标题 匹配；标记合法但目标不存在（被删）→ 降级为字面文本，
      // 跳过整段避免死循环。
      final marker = _kMarkerRegExp.firstMatch(afterAt);
      if (marker != null) {
        final parsed = await _resolveMarker(marker.group(1)!, marker.group(2)!);
        idx = atIdx + marker.end;
        if (parsed != null) mentions.add(parsed);
        continue;
      }

      // 尝试匹配作品标题（长度降序）
      Manuscript? ms;
      for (final m in sortedMs) {
        if (afterAt.startsWith(m.title)) {
          ms = m;
          break;
        }
      }

      if (ms == null) {
        idx = atIdx + 1;
        continue;
      }

      final afterMsTitle = afterAt.substring(ms.title.length);

      // 标题后必须是边界（空白/标点/行尾）或子路径分隔符 /
      if (!_isTitleBoundary(afterMsTitle) && !afterMsTitle.startsWith('/')) {
        idx = atIdx + 1;
        continue;
      }

      if (afterMsTitle.startsWith('/')) {
        final subPart = afterMsTitle.substring(1);

        // 加载章节
        if (!chaptersCache.containsKey(ms.id)) {
          chaptersCache[ms.id] = await _chRepo.listChapters(ms.id);
        }
        final chapters = chaptersCache[ms.id]!;

        // 匹配章节标题（长度降序）
        final sortedCh = List.of(chapters)
          ..sort((a, b) => b.title.length.compareTo(a.title.length));

        Chapter? ch;
        for (final c in sortedCh) {
          if (subPart.startsWith(c.title) &&
              _isTitleBoundary(subPart.substring(c.title.length))) {
            ch = c;
            break;
          }
        }

        if (ch != null) {
          final raw = '@${ms.title}/${ch.title}';
          mentions.add(ParsedMention(
            raw: raw,
            refType: 'chapter',
            refId: ch.id,
            title: '${ms.title} · ${ch.title}',
            manuscriptId: ms.id,
          ));
          idx = atIdx + raw.length;
          continue;
        }

        // 尝试素材文件
        if (!filesCache.containsKey(ms.id)) {
          filesCache[ms.id] = await _refRepo.listAttachedFiles(ms.id);
        }
        final files = filesCache[ms.id]!;

        final sortedFiles = List.of(files)
          ..sort((a, b) => b.fileName.length.compareTo(a.fileName.length));

        bool matched = false;
        for (final f in sortedFiles) {
          if (subPart.startsWith(f.fileName) &&
              _isTitleBoundary(subPart.substring(f.fileName.length))) {
            final raw = '@${ms.title}/${f.fileName}';
            mentions.add(ParsedMention(
              raw: raw,
              refType: 'file',
              refId: f.id,
              title: '【素材】${f.fileName}',
              manuscriptId: ms.id,
            ));
            idx = atIdx + raw.length;
            matched = true;
            break;
          }
        }

        if (!matched) idx = atIdx + 1;
      } else {
        // 只有作品引用
        final raw = '@${ms.title}';
        mentions.add(ParsedMention(
          raw: raw,
          refType: 'manuscript',
          refId: ms.id,
          title: ms.title,
          manuscriptId: ms.id,
        ));
        idx = atIdx + raw.length;
      }
    }

    // 清理文本中的 @ 引用（只移除解析成功的）
    var cleanedText = text;
    for (final m in mentions) {
      cleanedText = cleanedText.replaceFirst(m.raw, '');
    }
    cleanedText = cleanedText.trim();

    return ParseResult(mentions: mentions, cleanedText: cleanedText);
  }

  /// A-2：按稳定 ID 标记解析单条引用（改名免疫）
  /// [refType] ∈ {manuscript,chapter,file}，[refId] 为目标 ID；
  /// 由 ID 反查当前标题；目标不存在（被删）返回 null，由调用方降级为字面文本。
  Future<ParsedMention?> _resolveMarker(String refType, String refId) async {
    switch (refType) {
      case 'manuscript':
        final m = await _msRepo.getManuscript(refId);
        if (m == null) return null;
        return ParsedMention(
          raw: '@[$refType:$refId]',
          refType: 'manuscript',
          refId: m.id,
          title: m.title,
          manuscriptId: m.id,
        );
      case 'chapter':
        final c = await _chRepo.getChapter(refId);
        if (c == null) return null;
        final ms = await _msRepo.getManuscript(c.manuscriptId);
        final msTitle = ms?.title ?? '';
        return ParsedMention(
          raw: '@[$refType:$refId]',
          refType: 'chapter',
          refId: c.id,
          title: msTitle.isEmpty ? c.title : '$msTitle · ${c.title}',
          manuscriptId: c.manuscriptId,
        );
      case 'file':
        final f = await _refRepo.getAttachedFile(refId);
        if (f == null) return null;
        return ParsedMention(
          raw: '@[$refType:$refId]',
          refType: 'file',
          refId: f.id,
          title: '【素材】${f.fileName}',
          manuscriptId: f.bookId,
        );
      default:
        return null;
    }
  }

  /// 解析单个 @ 引用（如 "@我的小说/第三章"）
  Future<ParsedMention?> resolveMention(String mentionText) async {
    final path =
        mentionText.startsWith('@') ? mentionText.substring(1) : mentionText;
    final parts = path.split('/');

    final workTitle = parts[0];
    final manuscripts = await _msRepo.listManuscripts();

    Manuscript? ms;
    for (final m in manuscripts) {
      if (m.title == workTitle) {
        ms = m;
        break;
      }
    }
    if (ms == null) return null;

    // 只有作品引用
    if (parts.length == 1) {
      return ParsedMention(
        raw: mentionText,
        refType: 'manuscript',
        refId: ms.id,
        title: ms.title,
        manuscriptId: ms.id,
      );
    }

    // 子路径
    final subTitle = parts[1];

    // 尝试章节
    final chapters = await _chRepo.listChapters(ms.id);
    for (final ch in chapters) {
      if (ch.title == subTitle) {
        return ParsedMention(
          raw: mentionText,
          refType: 'chapter',
          refId: ch.id,
          title: '${ms.title} · ${ch.title}',
          manuscriptId: ms.id,
        );
      }
    }

    // 尝试素材
    final files = await _refRepo.listAttachedFiles(ms.id);
    for (final f in files) {
      if (f.fileName == subTitle) {
        return ParsedMention(
          raw: mentionText,
          refType: 'file',
          refId: f.id,
          title: '【素材】${f.fileName}',
          manuscriptId: ms.id,
        );
      }
    }

    return null;
  }
}

/// 构建完整路径（@作品标题 或 @作品标题/章节标题）
/// 批次71：从编号格式（@W001/C003）改为文字标题格式
String buildMentionPath(String workTitle, {String? subTitle}) {
  if (subTitle == null) return '@$workTitle';
  return '@$workTitle/$subTitle';
}
