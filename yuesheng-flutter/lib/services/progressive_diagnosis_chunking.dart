// ─────────────────────────────────────────────────────────────
// progressive_diagnosis 拆分：progressive_diagnosis_chunking.dart（R-019 ≤300 行）
// 分块：splitContent/kChunkSystemPrompt。迁移自 progressive_diagnosis.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'progressive_diagnosis.dart';
// ── 分块：按段落 + overlap 回溯（对齐 RN splitContent）──

/// 按段落切分文本为若干块，块间保留 overlap 字符的上下文重叠。
///
/// 算法：
///   1. 按 '\n\n' 切段落
///   2. 从 startIndex 累加段落，总长度接近 SIZE 时切块
///   3. overlap 从本块末尾段落向前回溯，累计长度 ≥ OVERLAP 停
///   4. 末块 < MIN_LAST_CHUNK 时合并到前一块
List<String> splitContent(String content) {
  if (content.length <= kDiagnosisChunkSize) {
    return [content];
  }

  final paragraphs = content.split('\n\n');
  final chunks = <String>[];
  var startIndex = 0;

  while (startIndex < paragraphs.length) {
    var endIndex = startIndex;
    var length = 0;
    var reachedThreshold = false;

    for (var i = startIndex; i < paragraphs.length; i++) {
      final pLen = paragraphs[i].length + 2; // +2 是 '\n\n' 分隔
      if (length + pLen >= kDiagnosisChunkSize) {
        reachedThreshold = true;
        break;
      }
      length += pLen;
      endIndex = i + 1;
    }

    if (!reachedThreshold) {
      chunks.add(paragraphs.sublist(startIndex).join('\n\n'));
      break;
    }

    final chunk = paragraphs.sublist(startIndex, endIndex).join('\n\n');
    chunks.add(chunk);

    // overlap 回溯：从 endIndex-1 向前累加，直到长度 >= OVERLAP
    var overlapLength = 0;
    var overlapStart = endIndex - 1;
    while (overlapStart > startIndex) {
      overlapLength += paragraphs[overlapStart].length + 2;
      if (overlapLength >= kDiagnosisChunkOverlap) {
        break;
      }
      overlapStart--;
    }

    startIndex = overlapStart > startIndex ? overlapStart : startIndex;
  }

  // 末块过小时合并
  if (chunks.length >= 2) {
    final last = chunks.last;
    if (last.length < kDiagnosisMinLastChunk) {
      final merged = '${chunks[chunks.length - 2]}\n\n$last';
      chunks[chunks.length - 2] = merged;
      chunks.removeLast();
    }
  }

  return chunks;
}

// ── 单块系统提示词（对齐 RN CHUNK_SYSTEM_PROMPT）──
const String kChunkSystemPrompt = '''你是一个专业的写作诊断助手。请阅读以下文本片段，识别其中存在的写作问题。

症候类型参考（仅用于标注，不要强行匹配）：
- P003 情绪标签化 / P004 信息倾泻症 / P005 视角漂移 / P006 节奏停滞
- P007 句式节奏单一 / P008 语言堆砌 / P009 角色动机缺失 / P010 OC平面化
- P011 对话疲劳症 / P012 张力不足症 / P013 开篇平庸症 / P014 结尾乏力症
- P015 高潮疲软症 / P016 情节巧合过多症 / P017 伏笔失效症 / P018 人设崩塌症
- P019 情感失真症 / P020 过渡生硬症 / P021 跳跃叙事/过度概括症

例外情况指引（以下场景通常不应判定为症候）：
- P003例外：隐喻表达（"冰冷的眼神""心头一热"）、有具体动作支撑的情绪词、紧凑叙事中的快速过渡
- P004例外：角色的内心自省（角色在评价自己，非作者补设定）、角色对地点/势力的随口判断
- P005例外：角色对自己所处环境的评价、角色对自身经历的回忆、有明确标记的视角切换
- P006例外：情绪沉淀段落、氛围描写的节奏变化、关键揭示前的屏息时刻
- P008例外：情感爆发点的浓墨重彩、作者刻意特定风格
- P009例外：悬疑叙事中动机故意模糊、功能性配角
- P011例外：剧本/对白主导文体、法庭剧/审讯场景
- P012例外：日常向/温馨向作品、悬疑铺垫章节
- P014例外：开放式结局的刻意留白、系列连载的"未完待续"设计
- P015例外：情绪高潮替代动作高潮的文学型叙事
- P016例外：喜剧/荒诞向作品中刻意设计的巧合（前提是风格一致）
- P018例外：角色因重大事件（如创伤、顿悟）导致的刻意转变，且有明确铺垫
- P019例外：非人类/非常规思维的角色设定
- P020例外：蒙太奇/意识流/碎片化叙事手法

请输出JSON格式的笔记，不要包含markdown代码块标记，只输出纯JSON对象：
{
  "notes": [
    {
      "syndromeId": "P003",
      "description": "简要描述观察到的问题，在原文中的位置",
      "evidence": ["具体例句1", "具体例句2"],
      "severity": "L1"
    }
  ]
}''';
