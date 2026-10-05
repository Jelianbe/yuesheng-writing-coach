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

    // ───────────────────────────────────────────────────────────
    // #7 ★★ 全局性质：**每一个 markdown 标题都必须独立成行**
    //
    // 为什么加成「全局扫描」而不是再逐个枚举标题：
    //   上一批的同类缺陷是「`## 严重度三维标定` 粘在数据行尾部」，
    //   而本批（舰长指出）发现的**同型第二处**是
    //   「`## 主次排序` 粘在 footer 末行尾部」——
    //   两者都发生在 `footer ↔ ADR 块` 这条**下游接缝**上。
    //   ⚠️ **逐个枚举的断言抓不到第二处**：`#3`/`#4` 用的是
    //   「ADR 五块是否出现/消失」的**子串判定**，
    //   而 `## 主次排序` 在拼接输出里**仍然存在**（只是粘在别人的行尾）⇒
    //   子串照样命中 ⇒ 绿。**这正是「枚举式断言」的盲区。**
    //
    //   ⇒ 正确判据是**不依赖具体标题内容**的结构性质：
    //     凡是行首出现 `#`（即真正的 markdown 标题行），
    //     该标题必须**从行首开始**、且**独占一行**。
    //     任何「粘在上一行尾部」的头部都会被抓到 ——
    //     包括现在这三块之外的、以后新加的任何标题。
    //
    //   扫描口径：以 `^#+ ` 开头的行= 合法标题行（允许 `#` 2~4 级）；
    //   另反向检查「不该出现粘行」：任何行内包含 `## ` 但**不以 `#` 开头**
    //   ⇒ 说明某个标题被粘在了前一行尾部。
    // ───────────────────────────────────────────────────────────
    test('#7 ★★ 所有 markdown 标题都独立成行（防「粘行」同型缺陷）', () {
      for (final opt in [
        {'label': 'includeAdrBlocks=true', 'text': buildSyndromeIndexContent()},
        {
          'label': 'includeAdrBlocks=false',
          'text': buildSyndromeIndexContent({}, false),
        },
      ]) {
        final label = opt['label']!;
        final lines = (opt['text'] as String).split('\n');

        // 正对照：必须真的扫到标题（否则本断言可能恒绿）
        final headingLines = lines
            .where((l) => l.trimLeft().startsWith('#'))
            .toList();
        expect(
          headingLines.length,
          greaterThanOrEqualTo(6),
          reason:
              '$label 扫到的标题行只有 ${headingLines.length} 个，'
              '⇒ 扫描口径失效（不是被测对象有问题）',
        );

        // 反向判据：行内含`## ` 却不以 # 开头 ⇒ 标题被粘在上一行尾部
        final glued = <String>[];
        for (final l in lines) {
          if (l.trimLeft().startsWith('#')) {
            continue; // 合法标题行
          }
          if (l.contains('## ')) {
            glued.add(l.length > 70 ? '${l.substring(0, 70)}…' : l);
          }
        }
        expect(
          glued,
          isEmpty,
          reason:
              '$label 有标题被粘在上一行尾部（AI 侧不可识别为独立标题）：\n'
              '${glued.join('\n')}',
        );
      }
    });

    // ── #8 标题独立成行的**正向**逐个点名（防止 #7 扫描口径被悄悄改弱）──
    test('#8 ★ 关键标题逐个确认独占一行（与 #7 互为正对照）', () {
      final lines = buildSyndromeIndexContent()
          .split('\n')
          .map((e) => e.trim())
          .toSet();
      // 这些是**语义锚点**：被粘住就会让 AI 读错层级
      const anchors = [
        '## 严重度三维标定', // footer 首标题（接缝 1）
        '## 诊断输出规范',
        '## 输出格式',
        '## 排除的"伪问题"', // footer 末标题（接缝 2 的上游）
        '## 主次排序（本轮讲哪一条）', // ADR 首标题（★ 接缝 2，舰长指出）
        '## 诊断权重卡（按写作目标分层）',
        '## 作者命门与投入产出',
        '## 发表前自查（诊断后另附·不进 JSON）',
      ];
      for (final a in anchors) {
        expect(lines.contains(a), isTrue, reason: '「$a」未独占一行 ⇒ 它被粘在了上一行尾部');
      }
    }); // ───────────────────────────────────────────────────────────
  });
}
