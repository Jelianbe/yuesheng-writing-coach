// ─────────────────────────────────────────────────────────────
// 源面落盘（B0c 前半件 · 纯 instrumentation · R-027 零报批）。
//
// 语义（施工单 `.ai/reports/2026-11-09-B0c前半件施工单.md` §2）：
//   诊断时把 D1/D2/D3 源面文本落盘留痕，供 L0-① 锚定闸与 R1 假红率
//   人评「对源面复验」。载体 = 应用文档目录 JSON 快照（零 DB 迁移、
//   不触 schemaVersion 50 / build_runner 生成链）。
//
// ★ 硬边界（违反即红）：
//   1. 本文件不进任何 prompt / schema / 判据真源（F-5 泄漏教训）；
//   2. 不触诊断结论与弱证据闸的可达化（行为变更归 L0-①，挂 AER）；
//   3. 不截断源面文本（截断 = 逐字复验失效）⇒ 超限直接拒绝保存；
//   4. 诊断链接线 = `source_plane_capture.dart`（B0c 后半件），本文件只管存取。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// 声明域（立项书裁定二十五）：D1 本章 / D2 正文+会话 / D3 正文+设定。
enum SourcePlaneDomain { d1, d2, d3 }

/// 会话消息桩（避免依赖 chat 层数据类；role 逐字取 wire 值）。
class SourcePlaneMessage {
  final String role;
  final String content;

  const SourcePlaneMessage({required this.role, required this.content});
}

/// D2 会话上下文拼接（E5 已验证口径）：**只收 user/system，排除 assistant 回显**。
/// 「回忆不等于证据」——AI 自己的历史回复不是证据来源。
String assembleConversationText(Iterable<SourcePlaneMessage> messages) =>
    messages
        .where((m) => m.role == 'user' || m.role == 'system')
        .map((m) => m.content)
        .join('\n');

/// 源面快照（逐字留痕）。`contentSha` = 三域文本拼接后的 sha256 前 16 位，
/// 供 R1 人评复验「未漂移」；三域长度单独记录便于体积账。
class SourcePlaneSnapshot {
  final String snapshotId;
  final int createdAt;
  final SourcePlaneDomain domain;
  final String chapterText;
  final String conversationText;
  final String settingText;
  final String contentSha;

  const SourcePlaneSnapshot({
    required this.snapshotId,
    required this.createdAt,
    required this.domain,
    required this.chapterText,
    required this.conversationText,
    required this.settingText,
    required this.contentSha,
  });

  int get chapterChars => chapterText.length;
  int get conversationChars => conversationText.length;
  int get settingChars => settingText.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'snapshotId': snapshotId,
    'createdAt': createdAt,
    'domain': domain.name,
    'chapterText': chapterText,
    'conversationText': conversationText,
    'settingText': settingText,
    'chapterChars': chapterChars,
    'conversationChars': conversationChars,
    'settingChars': settingChars,
    'contentSha': contentSha,
  };

  factory SourcePlaneSnapshot.fromJson(Map<String, dynamic> json) =>
      SourcePlaneSnapshot(
        snapshotId: json['snapshotId'] as String,
        createdAt: json['createdAt'] as int,
        domain: SourcePlaneDomain.values.firstWhere(
          (d) => d.name == json['domain'],
        ),
        chapterText: json['chapterText'] as String,
        conversationText: json['conversationText'] as String,
        settingText: json['settingText'] as String,
        contentSha: json['contentSha'] as String,
      );
}

/// 算逐字锚（纯函数，可单测负向变异）。
String sourcePlaneSha({
  required String chapterText,
  required String conversationText,
  required String settingText,
}) => sha256
    .convert(utf8.encode('$chapterText\n$conversationText\n$settingText'))
    .toString()
    .substring(0, 16);

/// 快照存储：应用文档目录 `source_plane/sp-<秒>-<sha>.json`。
///
/// 保留期 = 最近 [kMaxSnapshots] 份（超出按 id 字典序删最旧，id 含秒前缀）；
/// 体积上限 = 单域 [kMaxCharsPerDomain] 字符（与发现调用长度门同源读数）。
class SourcePlaneStore {
  static const int kMaxSnapshots = 50;
  static const int kMaxCharsPerDomain = 122900;
  static const String kSubDir = 'source_plane';

  final Future<Directory> Function() directory;
  final int Function() nowSeconds;

  SourcePlaneStore({
    Future<Directory> Function()? directory,
    int Function()? now,
  }) : directory = directory ?? getApplicationDocumentsDirectory,
       nowSeconds =
           now ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  Future<Directory> _dir() async {
    final root = await directory();
    final dir = Directory('${root.path}/$kSubDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 构造并保存一份快照。超限 fail-closed：抛 StateError，不截断不落盘。
  Future<SourcePlaneSnapshot> save({
    required SourcePlaneDomain domain,
    required String chapterText,
    Iterable<SourcePlaneMessage> messages = const <SourcePlaneMessage>[],
    String settingText = '',
  }) async {
    final conversation = assembleConversationText(messages);
    for (final pair in <MapEntry<String, int>>[
      MapEntry('chapterText', chapterText.length),
      MapEntry('conversationText', conversation.length),
      MapEntry('settingText', settingText.length),
    ]) {
      if (pair.value > kMaxCharsPerDomain) {
        throw StateError(
          '源面 ${pair.key} ${pair.value} 字符 > $kMaxCharsPerDomain：'
          '拒绝落盘（截断会使逐字复验失效）',
        );
      }
    }
    final sha = sourcePlaneSha(
      chapterText: chapterText,
      conversationText: conversation,
      settingText: settingText,
    );
    final seconds = nowSeconds();
    final snapshot = SourcePlaneSnapshot(
      snapshotId: 'sp-$seconds-$sha',
      createdAt: seconds,
      domain: domain,
      chapterText: chapterText,
      conversationText: conversation,
      settingText: settingText,
      contentSha: sha,
    );
    final dir = await _dir();
    await File(
      '${dir.path}/${snapshot.snapshotId}.json',
    ).writeAsString(jsonEncode(snapshot.toJson()));
    await _prune(dir);
    return snapshot;
  }

  /// 回读（R1 人评复验入口）。文件不存在 ⇒ null，不猜。
  Future<SourcePlaneSnapshot?> load(String snapshotId) async {
    final dir = await _dir();
    final file = File('${dir.path}/$snapshotId.json');
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return null;
    return SourcePlaneSnapshot.fromJson(Map<String, dynamic>.from(decoded));
  }

  /// 现存快照 id（字典序 = 时间序）。
  Future<List<String>> listIds() async {
    final dir = await _dir();
    final ids = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final name = entity.path.split(Platform.pathSeparator).last;
        ids.add(name.substring(0, name.length - 5));
      }
    }
    ids.sort();
    return ids;
  }

  Future<void> _prune(Directory dir) async {
    final ids = await listIds();
    if (ids.length <= kMaxSnapshots) return;
    for (final id in ids.take(ids.length - kMaxSnapshots)) {
      final file = File('${dir.path}/$id.json');
      if (await file.exists()) await file.delete();
    }
  }
}
