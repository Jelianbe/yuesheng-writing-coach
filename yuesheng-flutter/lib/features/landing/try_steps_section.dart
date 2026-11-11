// ─────────────────────────────────────────────────────────────
// try_steps_section.dart — 介绍页正文：「怎么试」三步
//
// ★ 纪律：每一步都对应**已存在**的界面元素，文案逐字取自源码，不凭印象写。
//   ① 书架空态按钮「新建作品」            (`bookshelf_empty_state.dart:50`)
//      作品详情「⊕ 新建章节」              (`manuscript_detail_chapter_list_header.dart:123`)
//   ② 章节正文输入区（写作页）
//   ③ 划词浮动菜单「诊断这段文字」        (`writing_page_chrome.dart:91`)
//      退路：右上角「更多」→「打开教练面板」(`writing_menu_sheet.dart:193`)
//   ⇒ 若哪天 UI 改了而这里没跟着改，介绍页就会**把用户导向一个不存在的按钮**。
//     这比不写介绍更坏（同族：`§4-498` 修的正是「把用户指向没有出口的房间」）。
//     因此本文件与上述四处是**同源依赖**：改动任一处须同步核这里。
//
// 【为什么不写「能看到诊断示例」】
//   实测 `llm_client.dart:254` 的 `_kFreeTestReply`：未配 Key 时固定回一句
//   「本次未进行诊断——没有调用真实模型」，解析类调用方走各自失败兜底
//   ⇒ **试用者看不到任何诊断结果**。写「看示例」就是承诺不存在的东西。
//   介绍页只承诺「流程能走通」，不承诺「有结果可看」（`§4-499` 舰长裁定）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';

/// 介绍页正文区：三步 + 每步一句实话。
class TryStepsSection extends StatelessWidget {
  const TryStepsSection({super.key});

  /// (标题, 说明)。顺序即用户动作顺序，不可重排。
  static const List<(String, String)> _steps = [
    ('新建一部作品，加一章', '书架点「新建作品」写个标题；进作品后点「⊕ 新建章节」'),
    ('把稿子粘进正文', '几百字就够。没有现成的，随手写几句也行'),
    ('选中一段文字，点「诊断这段文字」', '浮动菜单跟着选区出现；也可点右上角「更多」→「打开教练面板」'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          _buildStep(context, i + 1, _steps[i].$1, _steps[i].$2),
        ],
      ],
    );
  }

  Widget _buildStep(BuildContext context, int no, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBadge(context, no),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _buildStepText(context, title, desc)),
      ],
    );
  }

  /// 序号徽记：固定 22dp 圆，与标题首行基线大致对齐。
  Widget _buildBadge(BuildContext context, int no) {
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(top: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.palette.primarySoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$no',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.palette.primary,
        ),
      ),
    );
  }

  Widget _buildStepText(BuildContext context, String title, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          desc,
          style: TextStyle(
            fontSize: 12,
            height: 1.55,
            color: context.palette.textTertiary,
          ),
        ),
      ],
    );
  }
}
