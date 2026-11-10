// ─────────────────────────────────────────────────────────────
// 源面落盘 · **平台无关的纯逻辑部分**（T-20261031-03 裁 2）
//
// 为什么单独一个文件：源面快照组件分两半 ——
//   · 「域枚举 / 消息桩 / 文本拼接 / 快照 DTO / sha 锚」= **纯逻辑**（不碰文件系统）；
//   · 「落盘 / 回读 / 列举 / 淘汰」= **io 侧**（要 File / Directory）。
//   web 侧只需要前者（后者恒返回 null：浏览器无文件系统）⇒ 把纯逻辑放在本文件，
//   io / web 两侧各自 import 它 ⇒ **不复制逻辑、不新增 A→B 静态映射表**。
//
// ★ 硬边界（沿用 B0c 原件，逐字保留）：
//   1. 本文件不进任何 prompt / schema / 判据真源（F-5 泄漏教训）；
//   2. 不触诊断结论与弱证据闸的可达化；
//   3. 不截断源面文本（截断 = 逐字复验失效）⇒ 超限直接拒绝保存。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:crypto/crypto.dart';

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
