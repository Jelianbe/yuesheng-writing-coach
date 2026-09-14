// ─────────────────────────────────────────────────────────────
// Q2 批次护栏：teaching-strategy 正文压密（ADR-C77 压密收敛删除的延续）
//
// 两头失守的防线：
//   ① 引号话术预算 —— 上限 = 2026-09-14「Q2 批」压密后实测值（重塞台词即红）
//   ② 被压掉的示例台词不得回填
//   ③ 政策句与结构（信号表 / 三层模型 / 四步框架 / WHO-WHAT-WHY 表）逐字在位
//
// 口径：content.length = 12,034（压密前 12,209，Δ=−175）。
// 字节级回潮由 test/snapshots/skill_prompt_anchor.json 兜底，本文件只钉语义与预算，
// 不复述易漂移的总量数字（本仓「数字口径纪律」）。
// ─────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_registry.dart';

final String _ts = skillRegistry['teaching-strategy']!.content;

/// 取 [startMark, endMark) 区段（endMark 缺失则到文末）。
String _slice(String c, String startMark, String endMark) {
  final i = c.indexOf(startMark);
  final j = c.indexOf(endMark, i + startMark.length);
  return c.substring(i, j < 0 ? c.length : j);
}

/// 取成对 ASCII 双引号串（含引号本身），按出现顺序。
List<String> _quoted(String s) {
  final out = <String>[];
  var i = 0;
  while (true) {
    final a = s.indexOf('"', i);
    if (a < 0) return out;
    final b = s.indexOf('"', a + 1);
    if (b < 0) return out;
    out.add(s.substring(a, b + 1));
    i = b + 1;
  }
}

int _count(String hay, String needle) {
  var n = 0, i = 0;
  while (true) {
    final j = hay.indexOf(needle, i);
    if (j < 0) return n;
    n++;
    i = j + needle.length;
  }
}

// ── ① §9.1 引号话术预算（证据 = scripts 侧探针，Q2 压密后实测）────────
void _checkS91Budget() {
  final s = _slice(_ts, '### 9.1', '### 9.2');
  final q = _quoted(s);
  final chars = q.fold<int>(0, (a, b) => a + b.length);
  expect(q.length, lessThanOrEqualTo(33), reason: '§9.1 引号跨度上限 33（压密后实测）');
  expect(chars, lessThanOrEqualTo(248), reason: '§9.1 引号字符上限 248（压密后实测）');
}

void _checkS91LinesGone() {
  final s = _slice(_ts, '### 9.1', '### 9.2');
  for (final gone in const [
    '好，我直接说',
    '你觉得哪里不适应？',
    '你选的方向很好',
    '我这边还没有两份能放在一起比的稿子',
    '好的，那我们继续在这个方向上努力',
    '明白，你觉得不是这个问题',
    '你的描写其实有进步',
  ]) {
    expect(s.contains(gone), isFalse, reason: '已压密的示例台词回潮：$gone');
  }
}

// ── ② §9.1 政策句逐字在位（压密不改语义）──────────────────────────
void _checkS91Policy() {
  for (final keep in const [
    '如实说没有，不要编。',
    '如实说现在还没有足够的积累可谈',
    '不在自然语言中暴露症候编号',
    '**不**逐条朗读画像内容，最多提炼 2-3 条',
    '无条件将态度档位降一档（sensei→yuesheng→doubao）',
    '只用正例示范',
    '优先切换到镜像反馈',
    '尊重学员的选择',
    '不直接回答"是/否"',
    '尊重学员的判断',
  ]) {
    expect(_ts, contains(keep), reason: '政策句缺失：$keep');
  }
}

void _checkS91SignalRows() {
  for (final sig in const [
    '"我写得怎么样"',
    '"我有什么问题"',
    '"你温柔点"',
    '"你直接说问题就行"',
    '"我不太懂"',
    '"换个方式教我"',
    '"我想练这个"',
    '"我是不是没有进步"',
    '"对""是的""确实是""没错"',
    '"不同意""不是这样""不对""我不觉得"',
  ]) {
    expect(_ts, contains(sig), reason: '学员信号行缺失：$sig');
  }
}

// ── ③ §3.2.1 列已改名 + 三层模型与触发条件在位 ──────────────────────
void _checkS321() {
  expect(_ts.contains('入口话术示例'), isFalse, reason: '旧列名未清');
  expect(_ts, contains('| 层级 | 学员状态 | 教练动作 | 入口动作 |'));
  expect(_ts, contains('接住感受后，再落到具体是哪一处不对'));
  expect(_ts, contains('讲清原因，再点出一个可以立刻试的具体动作'));
  expect(_ts, contains('把任务缩到一次只改一处，当场能做完'));
  expect(_ts, contains('≥ 2 轮无进展'));
  expect(_ts, contains('直接跳到动作层'));
  expect(_ts, contains('从现象层开始引导'));
}

// ── ④ §7.2 四步框架 / WHO-WHAT-WHY 表 / 追问轮次约束在位 ────────────
void _checkS72() {
  final s = _slice(_ts, '### 7.2', '### 7.3');
  for (final step in const [
    '**第一步：方向确认**',
    '**第二步：重心选择**',
    '**第三步：WHO/WHAT/WHY 框架引导**',
    '**第四步：第一阶段优先**',
    '| WHO（谁的故事）',
  ]) {
    expect(s, contains(step), reason: '§7.2 结构缺失：$step');
  }
  expect(s, contains('每个问题只追问1-2轮，不需要全部回答才开始写。'));
  expect(s.contains('"主角是谁'), isFalse, reason: '§7.2 示例问答台词回潮');
  expect(s, contains('问主角是谁、最想要什么、最怕什么'));
  expect(s, contains('问世界的核心规则、与真实世界最大的不同'));
}

// ── ⑤ 跨批冻结区不回退（C72 / C75 护栏）───────────────────────────
void _checkCrossBatchFreezeZone() {
  expect(_count(_ts, '唯一例外'), 3, reason: 'ADR-C72 三处交叉引用计数');
  expect(_ts, contains('从零构建优先，不附加'));
  expect(_ts, contains('| 用户类型 | 教学重点 | 语气 | 诊断重点 |'));
  expect(_count(_ts, '识别信号（判断是否进阶及以上）'), 1);
}

void main() {
  group('Q2 压密护栏 · teaching-strategy 正文密度', () {
    test('§9.1 引号话术预算不超压密后上限', _checkS91Budget);
    test('§9.1 被压掉的示例台词不得回填', _checkS91LinesGone);
    test('§9.1 政策句逐字在位', _checkS91Policy);
    test('§9.1 十行学员信号表未塌陷', _checkS91SignalRows);
    test('§3.2.1 入口动作列与三层模型在位', _checkS321);
    test('§7.2 四步框架与追问约束在位', _checkS72);
    test('跨批冻结区（C72/C75）不回退', _checkCrossBatchFreezeZone);
  });
}
