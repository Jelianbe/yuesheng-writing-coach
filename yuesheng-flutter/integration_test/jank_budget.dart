// ─────────────────────────────────────────────────────────────
// jank_budget.dart — 帧时预算**判据核心**（纯函数 + 常量，无 test/main）
//
// 拆出本文件的原因（结构，不是风格）：判据要被两类测试共用且路径不同：
//   ① `integration_test/jank_budget_assert_test.dart` —— 真设备取帧时后判定（E1）
//   ② `test/performance/jank_budget_judge_test.dart` —— 离线用构造数据验「判据真的会红」
//   若把判据写在①里，②只能相对 import 一个**带 main 的测试文件**，会连带拉进 testWidgets。
//   **禁止**在②里复制一份实现 —— 两份必然漂移，且「哪份是真的」无人可判。
//
// ★ 为什么判据必须是纯函数：否则「判据有没有生效」只能靠真机手跑，等于判据本身不可测。
//
// ★★ 阈值不是拍脑袋定的 —— 但**原先那张三档表已作废**（2026-11-27 二次实测推翻）
//
// 已作废的读数（载体 = `Text(十万字)`，debug 模式，`flutter test -d`）：
//   100 字 / 5000 字 / 10 万字 → jankPct 0.0 / 3.2 / 54.8，看起来「完美剂量反应」。
//   **那是三重口径误判的产物，不是产品行为**：
//     ① 模式错：debug 是 JIT，帧时含 Dart 编译开销，不是给性能测量用的；
//     ② 指标错：用的是 `totalSpan`，其中 `vsyncOverhead` 占大头（build+raster 仅 ~6ms，
//        jank 帧里 build 从不当大头，五轮全 0%）⇒ 测的是模拟器呈现管线，不是应用；
//     ③ 载体错：`Text` 承载 10 万字会让 App 进程消失（读数 54.8% 是崩溃前残值）。
//
// 换成真实被测对象（`WritingEditorView` · 分块 `ListView.builder`）+ `--profile`
// + `work = build+raster` 后，两轮独立实测**无剂量反应**：
//   2 千字 → work jank 39.54 / 16.34%（两轮）
//   2 万字 → 22.47 / 16.67%
//   10 万字 → 28.01 / 24.46%（**不比 2 千字差**）
//   ⇒ 长章节问题已被分块渲染解决；`totalSpan`/jankPct 在本环境**不可作判据**。
//   详见 `.ai/team/runs/2026-11-27-T26-03-帧判据/03-三重口径误判与产品前提订正.md`。
//
// ⇒ 本文件的 `frameStats` / `judgeFrameBudget` 仍是有效的**纯函数**（离线可测、会红），
//   但**不要**再拿它们的读数去判「产品卡不卡」，除非先解决指标与可重复性两个问题。
//   两个常量保留供离线单测使用，**语义已降级为「示例阈值」**。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/scheduler.dart';

/// 超预算帧占比上限（%）。`-03` §三 建议 jank<5%。
/// ⚠ **语义已降级为「示例阈值」**：原取值 10% 的依据（「5000 字 3.2% 应过、
/// 10 万字 54.8% 应红」）已被 2026-11-27 二次实测推翻（见文件头注），
/// 那个「剂量反应」是 debug 模式 + `totalSpan` + `Text` 载体三重误判的产物。
/// 保留本常量只为让 `test/performance/jank_budget_judge_test.dart` 能验「判据函数会红」。
/// **未经新的可重复性论证，不得用它判产品。**
const double kMaxJankPct = 10.0;

/// 单帧 jank 判定阈值（ms）= 60Hz 帧预算。
const double kJankFrameMs = 16.67;

/// L1 采样门槛：少于此帧数直接判红（防「采不到 = 通过」）。
/// 实测真实写作页滚动约 400 帧、离线构造数据可任意多 ⇒ 取 100 只拦
/// 「回调没挂上 / 跑错环境」，不拦正常采集。
const int kMinFrames = 100;

/// 基准文本量（示例）= 本仓最坏情况的正文长度上限。
const int kLongTextChars = 100000;

/// 对照文本量（示例）。
const int kShortTextChars = 5000;

/// 帧统计：`[min, median, max, jankPct]`（jank = totalSpan > [kJankFrameMs]）。
///
/// ⚠ **口径警告**：这里用 `totalSpan`，其中 `vsyncOverhead` 占大头（见文件头注②）。
/// 若要用它判产品，必须先用同一批数据核对 `build+raster` —— 实测该值仅 ~6ms 时，
/// `totalSpan` 的超预算帧是**模拟器在等 vsync**，不是应用在忙。
List<double> frameStats(List<FrameTiming> frames) {
  if (frames.isEmpty) return const [0, 0, 0, 0];
  final xs = frames.map((t) => t.totalSpan.inMicroseconds / 1000.0).toList()
    ..sort();
  final jank = frames
      .where((t) => t.totalSpan.inMicroseconds / 1000.0 > kJankFrameMs)
      .length;
  return [xs.first, xs[xs.length ~/ 2], xs.last, jank / frames.length * 100];
}

/// 两层判定核心。返回 `null` = 通过；非 `null` = 失败原因（含读数，可直接进 message）。
///
/// 判定顺序**不可换**：L1 必须先判 —— 否则 L2 在空集上恒真，
/// 设备一抖或回调没挂上就「帧数 0 ⇒ 通过」= 假绿。
///
/// **为什么不用 max**：实测 max 跨轮漂移极大（同输入 25.9–151.1ms，独立验收 E1）。
String? judgeFrameBudget(
  List<double> stats, {
  required int frameCount,
  double maxJankPct = kMaxJankPct,
  int minFrames = kMinFrames,
}) {
  if (frameCount < minFrames) {
    return 'L1 采样不足：frames=$frameCount < $minFrames ⇒ 本判据拒判'
        '（采不到不等于通过；检查 addTimingsCallback 是否挂在真设备上、'
        '以及本文件是否被误放进 test/ 跑 —— test/ 下收 0 帧）';
  }
  final jankPct = stats[3];
  if (jankPct > maxJankPct) {
    return 'L2 jank 占比超预算：${jankPct.toStringAsFixed(1)}% > $maxJankPct%'
        '（median=${stats[1].toStringAsFixed(1)}ms，n=$frameCount）';
  }
  return null;
}

/// 与 `block_editor_perf_test.dart` 同一套片段池，确定性造长文本。
String buildLongText({int targetChars = 100000}) {
  const fragments = [
    '写作是一场与自己的对话',
    '窗外的雨声落在旧屋檐上',
    '他把台灯调亮了一格',
    '草稿纸上写满了又划掉',
    '故事的开头总要有点悬念',
    '夜色顺着江面慢慢铺开',
    '她想起去年的那场雪',
    '键盘的敲击声断断续续',
    '文字像水流一样自然涌出',
    '人总要学着和孤独相处',
  ];
  final buf = StringBuffer();
  var i = 0;
  while (buf.length < targetChars) {
    buf.write(fragments[i % fragments.length]);
    buf.write('\n');
    i++;
  }
  return buf.toString();
}
