import 'dart:io';

import 'package:writingcoach/services/syndrome_knowledge_base.dart';

/// 导出**施工后的真实单次链 prompt**（子代理模拟的判读依据）。
///
/// 为什么要导文件而不是让子代理自己读源码：
///   子代理扮演 LLM 时，判据必须是**模型实际看到的 prompt**（含
///   kSyndromeIndexContent 的全部内容 + S3 段 + 形态字段段），
///   否则模拟的是「我以为的 prompt」而非真实 prompt ⇒ 读数无效。
///
/// 用法：dart run tool/dump_single_chain_prompt.dart <输出路径>
void main(List<String> args) {
  final outPath = args.isNotEmpty
      ? args.first
      : 'outputs/gate/single_chain_prompt.txt';
  final content = kSyndromeIndexContent;
  final f = File(outPath);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(content);
  stdout.writeln('[dump] 字符数=${content.length} → $outPath');
  stdout.writeln(
    '[dump] 含 S3 段=${content.contains('干预价值（S3）三判据')} '
    '含形态段=${content.contains('形态字段（仅量形式症候评定）')} '
    '含 iv 字段行=${content.contains('"intervention_value"')}',
  );
}
