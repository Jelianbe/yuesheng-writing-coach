// ─────────────────────────────────────────────────────────────
// BlockEditorPerfTest — ADR-0002 阶段1 长章节帧率实测
//
// 在真实 Android 模拟器（emulator-5554）上 pump 真实 WritingEditorView，
// 注入 ~10 万字章节，SchedulerBinding.addTimingsCallback 收集首帧 +
// 滚动 20 屏的帧数据。
//
// 运行（flag 关=现网通路）：
//   flutter test integration_test/block_editor_perf_test.dart -d emulator-5554
// 运行（flag 开=分块可编辑渲染，**当前默认**）：
//   ⚠️ 2026-10-07 订正：`kBlockEditorEnabled` 自 commit `7d245a75` 起即为 **true**
//   （原文写「改为 true 后重跑」已失效）。当前直接跑即为 flag-on 通路。
//   要跑 flag-off 对照：手动把 lib/features/writing/blocked_text/block_readonly_view.dart
//   的常量改回 false，**跑完务必改回 true** —— 上一次翻值事故见
//   reports/2026-10-07-分块编辑器缺陷专项审查.md
//
// 口径说明：
//   - 直接 pump WritingEditorView（非整页 WritingPage）——两条路径的性能差
//     全部集中在 _buildContentField 输出；视图其余部分两路径逐字节相同。
//   - totalSpan = build + raster + vsync 开销；jank 阈值 16.67ms（60Hz）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:writingcoach/features/writing/blocked_text/block_readonly_view.dart';
import 'package:writingcoach/features/writing/writing_editor_view.dart';
import 'package:writingcoach/providers/writing_providers.dart';

/// 与 test/features/writing/blocked_text 同一套片段池，确定性造 ~10 万字。
String _buildLongText({int targetChars = 100000}) {
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
  int i = 0;
  while (buf.length < targetChars) {
    buf.write(fragments[i % fragments.length]);
    buf.write('\n');
    i++;
  }
  return buf.toString();
}

double _ms(FrameTiming t) => t.totalSpan.inMicroseconds / 1000.0;

/// [frames] 帧统计：[min, median, max, jankPct]（jank = totalSpan > 16.67ms）
List<double> _stats(List<FrameTiming> frames) {
  if (frames.isEmpty) return [0, 0, 0, 0];
  final xs = frames.map(_ms).toList()..sort();
  final jank = frames.where((t) => _ms(t) > 16.67).length;
  return [xs.first, xs[xs.length ~/ 2], xs.last, jank / frames.length * 100];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('长章节首帧 + 滚动 20 屏帧数据', (tester) async {
    final text = _buildLongText();
    final timings = <FrameTiming>[];
    void listener(List<FrameTiming> ts) => timings.addAll(ts);
    SchedulerBinding.instance.addTimingsCallback(listener);

    final editorKey = GlobalKey();
    final contentController = TextEditingController(text: text);
    timings.clear();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WritingEditorView(
            state: const WritingState(),
            titleController: TextEditingController(),
            contentController: contentController,
            focusNode: FocusNode(),
            editorStackKey: editorKey,
            punctBarIds: null,
            punctCustomItems: const [],
            showSelectionMenu: false,
            selectionMenuPos: null,
            onTitleChanged: (_) {},
            onContentChanged: (_) {},
            onDiagnoseSelection: () {},
            onSaveToLibrary: () {},
            onUndo: () {},
            onRedo: () {},
            onPunctuationTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final firstFrames = List<FrameTiming>.from(timings);
    timings.clear();

    final scrollable = find.descendant(
      of: find.byKey(editorKey),
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 20; i++) {
      await tester.fling(scrollable, const Offset(0, -500), 1200);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pumpAndSettle();
    SchedulerBinding.instance.removeTimingsCallback(listener);

    final f = _stats(firstFrames);
    final s = _stats(timings);
    // ignore: avoid_print
    print('PERF_RESULT flagOn=$kBlockEditorEnabled chars=${text.length}');
    // ignore: avoid_print
    print(
      'PERF_FIRST frames=${firstFrames.length} min=${f[0].toStringAsFixed(1)}ms '
      'median=${f[1].toStringAsFixed(1)}ms max=${f[2].toStringAsFixed(1)}ms',
    );
    // ignore: avoid_print
    print(
      'PERF_SCROLL frames=${timings.length} min=${s[0].toStringAsFixed(1)}ms '
      'median=${s[1].toStringAsFixed(1)}ms max=${s[2].toStringAsFixed(1)}ms '
      'jankPct=${s[3].toStringAsFixed(1)}%',
    );
  });
}
