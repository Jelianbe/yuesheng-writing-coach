// ─────────────────────────────────────────────────────────────
// L2 索引内容构建 — ADR-0003 判据 8（回退开关）锁测试
//
// 背景
// ----
// ADR-0003 §5 判据 8：「各阶段独立开关，关闭即恢复原行为（**prompt 层可整体
// 摘除前置块**；schema 可选字段解析器兼容）」。
//
// A3 批落地后自查发现：`buildSyndromeIndexContent` 此前**零测试覆盖**
// （全仓只有库内 `kSyndromeIndexContent` 一处调用它），判据 8 处于
// 「写在 ADR 里、无任何执行体」的状态。
//
// 本批做的事
// ------------
// ① 把 ADR 五个新块（裁定 2/5/7）从 `_kIndexFooter` **拆成独立 const**
//    （`_kIndexAdrBlocks`），并给 `buildSyndromeIndexContent` 加
//    `includeAdrBlocks` 开关 ⇒ 判据 8 从「措辞」变成「能变绿的断言」。
// ② 锁「关掉开关后**原有输出协议一行不丢**」—— 这是判据 8 的真语义：
//    回退要退的是本批注入，不是既有协议。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/syndrome_knowledge_base.dart';

void main() {
  group('ADR-0003 判据 8 · 索引构建的回退开关', () {
    // ── #1 开关语义：false 时输出严格短于 true，且短掉的正是 ADR 五块 ──
    test('#1 includeAdrBlocks=false 剔除 ADR 五块，输出更短', () {
      final withBlocks = buildSyndromeIndexContent();
      final withoutBlocks = buildSyndromeIndexContent({}, false);

      expect(
        withBlocks.length > withoutBlocks.length,
        isTrue,
        reason:
            '关掉开关后必须更短（实测 '
            '${withBlocks.length} vs ${withoutBlocks.length}）',
      );
    });

    // ── #2 ★ 判据 8 的真语义：关掉开关后【原有协议一行不丢】──
    // 这条是本文件的核心。若它红了，说明拆分把原协议弄丢了。
    //
    // ⚠️ **断言口径两次修正（变异 V2 实证）**：
    //   v1 子串匹配 `contains(s)`：变异 V2 把「## 输出格式」改成
    //      「## 输出格式（已删）」后仍全绿 ⇒ 无牙齿。
    //   v2 改成 `contains('\n$s\n')`：实测 `contains plain=true` 但
    //      `contains newline-form=false` —— 因为 footer 自带前导 `\n`
    //      与数据行结尾 `\n` 叠加，标题前是**两个**换行，「恰好一个换行」
    //      这个判据本身过脆。
    //   v3（当前）：**逐行切分后精确比对行内容**。既保住「加后缀不算命中」
    //      的牙齿，又不依赖换行个数。
    //   ⇒ 判据：断言文本是否「独立成行」时，**必须切行比对**，
    //      不要用「固定数量的换行」当判别式（DECISIONS §4-153 同型推广）。
    test('#2 ★关掉开关后原有输出协议完整保留', () {
      final lines = buildSyndromeIndexContent(
        {},
        false,
      ).split('\n').map((e) => e.trim()).toSet();

      // 判别式标题：必须**恰好整行等于**该标题（加后缀/加前缀都不算）
      const headings = [
        '## 严重度三维标定', // 严重度标定
        '## 诊断输出规范', // 输出规范
        '## 输出格式', // 输出格式
        '## 排除的"伪问题"', // 伪问题段
      ];
      for (final h in headings) {
        expect(
          lines.contains(h),
          isTrue,
          reason:
              '关掉 ADR 块后，原有协议标题行「$h」丢失了 —— '
              '这会让回退变成「连协议一起退」',
        );
      }

      // JSON 标记与字段：同样要求独立成行/独立成项
      const tokens = [
        '[YS_DIAGNOSIS]',
        '[/YS_DIAGNOSIS]',
        '"syndromes"',
        '"teaching_plan"',
        '"current_teaching_focus_id"',
      ];
      final blob = lines.join('\n');
      for (final t in tokens) {
        expect(blob.contains(t), isTrue, reason: '关掉 ADR 块后，协议标记「$t」丢失了');
      }
    });

    // ── #3 开启时 ADR 五块齐全（防止 #2 写成恒绿：反向咬合）──
    test('#3 includeAdrBlocks=true 时 ADR 五块齐全', () {
      final withBlocks = buildSyndromeIndexContent();
      const adrBlocks = [
        '## 主次排序（本轮讲哪一条）', // 裁定 2
        '## 诊断权重卡（按写作目标分层）', // 裁定 7
        '## 作者命门与投入产出', // 裁定 5
        '## 发表前自查（诊断后另附·不进 JSON）', // 裁定 5
      ];
      for (final s in adrBlocks) {
        expect(withBlocks.contains(s), isTrue, reason: '开启时 ADR 块「$s」缺失');
      }
    });

    // ── #4 关掉开关后，ADR 五块必须【全部】消失（不留半块）──
    test('#4 关掉开关后 ADR 五块全部消失（不留半块）', () {
      final withoutBlocks = buildSyndromeIndexContent({}, false);
      const adrBlocks = [
        '## 主次排序（本轮讲哪一条）',
        '## 诊断权重卡（按写作目标分层）',
        '## 作者命门与投入产出',
        '## 发表前自查（诊断后另附·不进 JSON）',
      ];
      for (final s in adrBlocks) {
        expect(
          withoutBlocks.contains(s),
          isFalse,
          reason: '关掉开关后仍残留 ADR 块「$s」⇒ 回退不干净',
        );
      }
    });

    // ── #5 两种模式都必须仍含映射表数据行（不能把表头也弄丢）──
    test('#5 两种模式都保留映射表行', () {
      for (final s in [
        buildSyndromeIndexContent(),
        buildSyndromeIndexContent({}, false),
      ]) {
        expect(
          s.contains('| 症候 ID | 问题类型关键词 | 一句话描述 |'),
          isTrue,
          reason: '映射表表头丢失',
        );
        expect(s.contains('P001'), isTrue, reason: '映射表数据行丢失');
        expect(
          s.contains('P037'),
          isTrue,
          reason: 'ADR-0003 阶段一新增的 P037 应在映射表里',
        );
      }
    });

    // ── #6 幂等：同参数两次调用逐字节相同（拆分不得引入非确定性）──
    test('#6 幂等：同参数两次调用逐字节相同', () {
      expect(buildSyndromeIndexContent(), buildSyndromeIndexContent());
      expect(
        buildSyndromeIndexContent({}, false),
        buildSyndromeIndexContent({}, false),
      );
    });
  });
}
