// ─────────────────────────────────────────────────────────────
// Intent Classifier — 交互意图分类器（B62b，A2 立项落地）
//
// 真源参考：V2.0 §3.2 Layer1「意图识别分类器（创作/修改/询问/闲聊）」
//
// 四分类：
//   compose    创作——正在写新内容（默认）
//   revise     修改——修改/改写已有文稿
//   ask        询问——提问/求解释/求分析
//   smalltalk  闲聊——寒暄/确认/社交短句
//
// 分类结果决定 prompt 构造与触发策略：
//   smalltalk/ask → 不发起诊断与教学建议
//   revise        → 降诊断强度、只提示关键问题、不替写正文
//   compose       → 正常诊断链路
//
// 纯函数、无副作用、无外部依赖，便于单测。
// ─────────────────────────────────────────────────────────────

/// 交互意图四分类
enum UserIntent {
  compose('compose', '创作'),
  revise('revise', '修改'),
  ask('ask', '询问'),
  smalltalk('smalltalk', '闲聊');

  final String value;
  final String label;

  const UserIntent(this.value, this.label);

  static UserIntent fromValue(String? v) {
    for (final i in UserIntent.values) {
      if (i.value == v) return i;
    }
    return UserIntent.compose;
  }
}

/// 闲聊信号：仅当整句较短（<= [kSmalltalkMaxLength]）时命中
const List<String> _smalltalkSignals = [
  '你好',
  '您好',
  '谢谢',
  '辛苦',
  '好的',
  '好哒',
  '嗯嗯',
  '哈哈',
  '收到',
  '明白了',
  '知道了',
  '再见',
  '拜拜',
  '在吗',
  '没事',
  '加油',
];

/// 闲聊判定：短句上限（避免把"谢谢你的建议，我改一下这段"误判为闲聊）
const int kSmalltalkMaxLength = 20;

/// 询问信号：疑问词 / 请求解释 / 请求分析
const List<String> _askSignals = [
  '吗',
  '怎么',
  '如何',
  '为什么',
  '什么',
  '哪个',
  '哪些',
  '请问',
  '是不是',
  '有没有',
  '对不对',
  '能不能',
  '教我',
  '解释一下',
  '什么意思',
  '有什么区别',
  '怎么办',
  '怎么看',
  '你觉得',
  '分析一下',
  '帮我分析',
  '怎么改',
];

/// 修改信号：明确的修改动作动词
const List<String> _reviseSignals = [
  '修改',
  '改一下',
  '改改',
  '改成',
  '改写',
  '重写',
  '换成',
  '换掉',
  '删掉',
  '删除',
  '删了',
  '调整',
  '润色',
  '再写一遍',
  '重新写',
  '帮我改',
];

/// 回复颗粒度（用户控制的回复长度）
enum ReplyDetail {
  standard('standard', '标准'),
  concise('concise', '压缩'),
  detailed('detailed', '展开');

  final String value;
  final String label;

  const ReplyDetail(this.value, this.label);

  static ReplyDetail fromValue(String? v) {
    for (final i in ReplyDetail.values) {
      if (i.value == v) return i;
    }
    return ReplyDetail.standard;
  }
}

/// 压缩信号：要求简短/长话短说
const List<String> _conciseSignals = [
  '长话短说',
  '简单说',
  '简短',
  '说重点',
  '一句话',
  '别啰嗦',
  '别太细',
  '压缩',
  '少说',
  '挑重点',
  '简单点',
  '简单说说',
];

/// 展开信号：要求详细/展开说明
const List<String> _detailedSignals = [
  '详细点',
  '详细些',
  '说详细',
  '展开',
  '讲清楚',
  '说清楚',
  '具体点',
  '具体些',
  '多说一点',
  '再详细',
  '多讲讲',
  '深入一点',
  '细说',
  '详细讲',
];

/// 检测回复颗粒度信号（无信号 → standard）。
///
/// 压缩信号优先（"长话短说"语义更明确）；纯函数无副作用。
ReplyDetail detectReplyDetail(String text) {
  final t = text.trim();
  if (t.isEmpty) return ReplyDetail.standard;
  for (final s in _conciseSignals) {
    if (t.contains(s)) return ReplyDetail.concise;
  }
  for (final s in _detailedSignals) {
    if (t.contains(s)) return ReplyDetail.detailed;
  }
  return ReplyDetail.standard;
}

/// 颗粒度注入文本（standard 返回 null 不注入）。
String? buildReplyDetailInstruction(ReplyDetail detail) {
  switch (detail) {
    case ReplyDetail.standard:
      return null;
    case ReplyDetail.concise:
      return '## 回复颗粒度：压缩\n\n'
          '学员要求长话短说。压缩到最小可感知的形式：'
          '最多一句话结论 + 最多一个极短示范（≤1 句），'
          '删除一切铺垫、解释与次要点。';
    case ReplyDetail.detailed:
      return '## 回复颗粒度：展开\n\n'
          '学员要求详细说明。可适当展开：'
          '给出完整示范与逐步解释，示范可含变体；'
          '仍保持一次一个焦点，不堆砌要点。';
  }
}

/// 对用户消息做意图分类。
///
/// 判定顺序：smalltalk（短句社交）→ ask（疑问）→ revise（修改动作）→ compose（默认）。
/// 注意：ask 先于 revise——"这段怎么改更好"是提问（要引导而非诊断展开）。
UserIntent classifyUserIntent(String text) {
  final t = text.trim();
  if (t.isEmpty) return UserIntent.compose;

  // 1. 闲聊：短句 + 社交信号
  // 批次4（4.7 O3）：教学相关性二次校验——短句同时含实质意图信号（疑问/修改）时，
  // 按实质意图分类，避免"谢谢，你觉得我今天写得怎么样"这类提问被当闲聊吞掉。
  // 单字疑问词（如"吗"）不参与二次校验，避免"你好吗"被误判为 ask。
  if (t.length <= kSmalltalkMaxLength) {
    for (final s in _smalltalkSignals) {
      if (t.contains(s)) {
        final hasAskSignal =
            t.contains('？') ||
            t.endsWith('?') ||
            _askSignals.any((a) => a.length >= 2 && t.contains(a));
        if (hasAskSignal) return UserIntent.ask;
        if (_reviseSignals.any((r) => t.contains(r))) {
          return UserIntent.revise;
        }
        return UserIntent.smalltalk;
      }
    }
  }

  // 2. 询问：问号或疑问词
  if (t.contains('？') || t.endsWith('?')) return UserIntent.ask;
  for (final s in _askSignals) {
    if (t.contains(s)) return UserIntent.ask;
  }

  // 3. 修改：修改动作动词
  for (final s in _reviseSignals) {
    if (t.contains(s)) return UserIntent.revise;
  }

  // 4. 创作：默认
  return UserIntent.compose;
}

/// 意图注入文本（追加为 system 消息；compose 返回 null 不注入）。
///
/// [recentIntents] 为该会话最近 3 次意图序列（L1 意图向量），供 AI 感知上下文。
String? buildIntentInstruction(UserIntent intent, List<String> recentIntents) {
  final recentText = recentIntents.isEmpty
      ? ''
      : '\n\n近期意图序列：${recentIntents.join(' → ')}';
  switch (intent) {
    case UserIntent.smalltalk:
      return '## 交互意图：闲聊\n\n'
          '学员本条为寒暄/闲聊，非写作内容。简短友好回应即可，'
          '不要发起诊断、不要布置教学建议、不要展开教学内容。'
          '$recentText';
    case UserIntent.ask:
      return '## 交互意图：询问\n\n'
          '学员本条为提问。优先直接回答提问本身，'
          '不要展开新的诊断或布置训练任务（除非提问直接与当前训练相关）。'
          '$recentText';
    case UserIntent.revise:
      return '## 交互意图：修改\n\n'
          '学员正在修改已有文稿。诊断语气放宽：只提示最关键的问题，不逐条展开；'
          '优先回应修改诉求；示范可以给，但不替学员改写正文。'
          '$recentText';
    case UserIntent.compose:
      return null;
  }
}
