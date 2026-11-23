#!/usr/bin/env python3
"""strip_editor_ids.py — git clean filter：入库前剥除编辑器注入的页面节点 ID。

【它解决什么问题】
舰长侧编辑器（HTML 可视化编辑器）在打开并保存 `yuesheng-landing/site/*.html` 时，
会给几乎每个标签注入 `data-page-node-id="<22 位 base62>"`（实测 203 处）。
这些 ID 是**编辑器内部句柄**，对产品零意义；但它们会让工作区常年显脏，
并使某次 `git add -A` 把 203 处噪声**永久写进历史**（不可逆）。

【为什么用 clean filter 而不是 gitignore】
`yuesheng-landing/site/` 是舰长 2026-11-13 明确批准入库的（commit 07741c59），
理由是「让 site/ 成为可独立部署的自包含目录」，并明确接受 1.55MB 重复这一代价。
把它 gitignore 等于反转那次批准。clean filter 让「入库可独立部署」与
「工作区不被污染」两件事同时成立。

【设计约束（逐条对应项目既有纪律）】
1. **只剥这一个属性，其余字节零改动**。不用正则重排标签、不动空白、不动换行。
2. **stdin → stdout 流式**，符合 git clean filter 协议（git 传内容进来，收回内容）。
3. **失败即退出非零**。配 `.gitattributes` 的 `required=true`，使脚本异常时
   `git add` **报错停下**而不是静默放行原内容——后者正是项目明令禁止的形态
   （「校验器 rc=0 ≠ 我写的东西被看见了」的反面：静默放行比红更危险）。
4. **不自带换行归一化**。`* text=auto eol=lf` 由 git 自己处理，本脚本若再动
   一遍换行，就会与 `.gitattributes` 的既有口径打架（§W-05 舰长裁定）。
   实测：clean filter 在 `eol` 转换**之前**运行，故此处看到的是工作区原字节。

【判据（能变红）】
- 注入态输入 → 输出必须**逐字节**等于该文件的 HEAD 版（见批三负向验证）。
- 无注入态输入 → 输出必须与输入**逐字节**相同（幂等且零副作用）。

用法（git 自动调用，人不需要手动跑）：
    git config filter.stripEditorIds.clean "python3 tool/strip_editor_ids.py"
    git config filter.stripEditorIds.smudge cat
    git config filter.stripEditorIds.required true
    # 手动核对单个文件：
    python3 tool/strip_editor_ids.py < in.html > out.html
"""

import re
import sys

# 编辑器注入的节点 ID：属性名固定，值恒为 22 位 base62（实测 203/203 均为 22 位）。
# 允许值里出现 - 和 _ 是为了容忍编辑器将来换 ID 方案时不至于漏剥；
# 但**要求至少 8 位**，避免把「data-page-node-id=""」这类空值或短值误当噪声以外的东西处理。
_NODE_ID_ATTR = re.compile(rb'\s+data-page-node-id="[A-Za-z0-9_-]{8,64}"')

# 同族属性的兜底：若编辑器版本变化引入 data-node-id / data-page-id，
# 一并剥除（当前实测为 0 命中，留着是为了「已知族 + 未知族」都被覆盖）。
# ⚠️ 只剥 data-* 且名字里同时含 page/node 与 id 的，不碰 data-* 其它业务属性。
_RELATED = re.compile(rb'\s+data-(?:page|node)-node-id="[A-Za-z0-9_-]{8,64}"')


def strip(data: bytes) -> tuple[bytes, int]:
    """返回 (剥除后字节, 剥除处数)。不改变其余任何字节。"""
    out, n1 = _NODE_ID_ATTR.subn(b"", data)
    out, n2 = _RELATED.subn(b"", out)
    return out, n1 + n2


def main() -> int:
    raw = sys.stdin.buffer.read()
    cleaned, count = strip(raw)

    # 只往 stderr 说话，不污染 stdout（stdout 是 git 要收的内容）。
    if count:
        print(
            f"strip_editor_ids: 剥除 {count} 处编辑器节点 ID",
            file=sys.stderr,
        )
    sys.stdout.buffer.write(cleaned)
    sys.stdout.buffer.flush()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # 失败关闭：让 git add 直接红
        print(f"strip_editor_ids: 致命错误 {exc!r}", file=sys.stderr)
        sys.exit(1)