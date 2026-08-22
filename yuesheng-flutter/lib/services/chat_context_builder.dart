/// Chat 上下文构建工具
///
/// 从 chat-service.ts 拆出，负责构建注入 system prompt 的各类上下文：
/// - 引用内容（作品/章节/文件）预算分配与截断
/// - 附属文件上下文格式化
/// - 活跃症候上下文格式化（分级注入）
/// - 智能截断工具
///
/// 真源：yuesheng-android/src/services/chat-context-builder.ts
library;

import 'dart:convert';

import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/services/conflict_detector.dart';
import 'package:writingcoach/services/dialogue_tag_detector.dart';
import 'package:writingcoach/services/event_causality_detector.dart';
import 'package:writingcoach/services/grammar_lexical_detector.dart';
import 'package:writingcoach/services/subplot_closure_detector.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/contracts/material_capability.dart';

export 'package:writingcoach/contracts/material_capability.dart';

part 'chat_context_builder_syndrome.dart';
part 'chat_context_builder_truncate.dart';
part 'chat_context_builder_observation.dart';
part 'chat_context_builder_reference.dart';

// ─── 附属文件上下文 ───────────────────────────────────────────

/// 附属文件上下文格式化（V3.1 — A-1 token 止血）。
///
/// 不再全量注入书籍下所有文件的完整内容（token 爆炸源）：改为「标题 + 200 字开头摘要」
/// 的清单式注入。完整内容仍由用户 @ 引用路径按需获取（见引用注入循环 file 分支）。
String? formatAttachedFilesContext(List<AttachedFileInfo> files) {
  if (files.isEmpty) return null;

  const summaryLen = 200;
  const header =
      '\n## 当前书籍文件（摘要）\n\n'
      '以下是你所关联书籍下的参考文件清单及开头摘要。'
      '需要某文件完整内容时，请引导用户通过 @ 引用该文件，而非在此全量展开。\n\n';

  final body = StringBuffer();
  for (final f in files) {
    final roleLabel = f.fileRole == 'outline'
        ? '大纲'
        : f.fileRole == 'material'
        ? '素材'
        : '常规';
    final summary = f.content.length > summaryLen
        ? '${f.content.substring(0, summaryLen)}…（更多内容可通过 @ 引用获取）'
        : f.content;
    body.writeln('### ${f.fileName}（$roleLabel）');
    body.writeln(summary);
    body.writeln();
  }

  final bodyStr = body.toString();
  return bodyStr.isNotEmpty ? '$header$bodyStr' : null;
}
