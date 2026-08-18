# B 系列提示词包（B1–B30）遗留项核对报告

> 核对日期：2026-08-18｜依据：`yuesheng-flutter/docs/内容层修正-执行提示词包.md`（commit 9d3f2f22）
> 目的：逐一确认 B8/B13/B16/B19/B22/B24/B25/B26/B28 是否落地，均直接读源码确认。

## 结论速览

| 项 | 内容 | 状态 | 关键证据 |
|---|---|---|---|
| B8 | 重叠优先级表补 P022/P023/P024/P026 | ❌ 未做 | `syndrome_knowledge_base.dart` 仅 72 行，无优先级表；重叠优先级已迁入 `focus_resolver.dart` fallback 表，原"四组行"形态不存在 |
| B13 | outline 'expired' CHECK 三方对齐 | ⚠️ 风险隐性消失 | `tables.dart:656` outline_impression.status 无 CHECK，repo 照写 'expired'，不再触发失败；缺显式对齐 + 回归测试 |
| B16 | v24 重建 chapters 保留 chapter_id | ⚠️ 风险可能已不存在 | 迁移仅 DROP/重建 chapters；`chapter_repository:288` 注释称 chapter_id 由外键清空，需确认 sessions.chapter_id 是否真 FK |
| B19 | 消息加载竞态加会话守卫 | ✅ 已完成 | `chat_page.dart:216-225` `_loadingSession  Id` 守卫 |
| B22 | 错误体 Authorization 脱敏 | ⚠️ 当前未泄露但无兜底 | `_buildDioError` 只用响应体，含请求头则暴露；缺显式正则脱敏 |
| B24 | UI 一般项收敛（定时器/静默 catch/暗色） | ❌ 部分未完成 | `chat_attitude.dart` 4 处静默 catch（18/54/117/131）；500ms 定时器已查无 |
| B25 | UI 一般项（非懒加载/孤儿 KV） | ❌ 未做 | `growth_content.dart:236` 非懒加载；`chapter_repository.deleteChapter` 未清 chapter_draft/chapter_versions KV |
| B26 | token 估算中文口径（0.4→中文） | ❌ 未做 | `shared_constants.dart:103` charToTokenRatio=0.4；低估中文 2–2.5 倍 |
| B28 | 其他性能项 | ❌/✅ 混合 | 大纲 N+1（`manuscript_providers:261-273`）、章节树非懒加载（`chapter_tree_drawer:165-207`）仍存在；冷启动空白占位已有所占位；session/diagnosis 已用 SQL WHERE |

## 建议优先项
1. **B26**（token 中文口径）— 严重影响预算闸门真实性，改造最小（改一处常量 + 重测预算表）。
2. **B28 大纲 N+1 + 章节树非懒加载** — 性能，改动限于 provider/widget。
3. **B24 静默 catch** — 加 debugPrint/error_logger，排查隐蔽故障。
4. **B8 / B25** — 确认 overlaps 语义是否已等价、孤儿 KV 是否仍存在于设计。

## 已确认完成（不在本批核对范围，供参考）
B0/B1/B2/B3/B4/B5/B6/B7/B9/B11/B12/B14/B15/B17/B18/B20/B21/B23/B27/B29/B30 已在此前 commit 落地。
