# -*- coding: utf-8 -*-
"""交互/导航回归扫描（INTERACTION-REGRESSION-CHECKLIST 脚本化 · 校准版）。

对应 docs/standards/INTERACTION-REGRESSION-CHECKLIST-V1.0.md。

层级设计（避免误报海啸，V4.14/4.15 教训）：
- P0（阻塞，需处理或人工复核排除）：
    P0-2 pushNamed 家族误用（清单要求清零）
    P0-3 async 方法内 await 后 context 导航无 mounted 保护（页面销毁后导航 = 运行时崩溃）
- P1（报告性质，需人工复核）：
    P1-1 Navigator.pop 候选（弹层 pop 多数合法；无 canPop/mounted 上下文的标记复核）
    P1-4 context 导航裸字符串路径（应引用 AppRoutes.x）
    P1-5 业务动作方法体无防抖守卫关键词候选（调用方已有守卫则豁免）

退出码：P0 命中 → 1；仅 P1 → 0。
用法：
  python scripts/check_interaction_regression.py [--lib <路径>] [--quiet] [--json <out>]
"""
import argparse
import io
import json
import os
import re
import sys

DEFAULT_LIB = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"
)

# P0-2：路由误用 API（清单要求清零）
PUSHNAMED_PATTERN = re.compile(
    r"\.pushNamed\s*\(|\.pushReplacementNamed\s*\(|\.pushNamedAndRemoveUntil\s*\("
)
# P0-3：await 后 context 导航
CONTEXT_NAV_PATTERN = re.compile(r"context\.(?:pop|push|go)\s*\(")
# P1-1：Navigator 直接 pop
NAV_POP_PATTERN = re.compile(r"Navigator\.(?:of\([^)]*\)\.)?pop\s*\(")
# P1-4：context 导航裸字符串
HARDCODE_PATH_PATTERN = re.compile(r"context\.(?:go|push|popUntil)\s*\(\s*['\"]")
# P1-5：业务动作方法（发送/创建/保存/提交/采纳）
BIZ_ACTION_PATTERN = re.compile(
    r"Future<[^>]*>\s+(send|create|save|submit|adopt|_handleSend|_submit)\w*\s*\("
)

DEBOUNCE_GUARDS = (
    "_isProcessing", "_isSubmitting", "_isSaving", "_isUploading",
    "_isCreating", "_isSending", "_submitting", "_processing",
    "isSubmitting", "isSending", "isProcessing", "isUploading",
    "hasSubmitted", "_isBusy", "inFlight",
)


def _strip_comments(src):
    """去整行注释（不剥行内 //，避免切掉字符串/代码尾注——V4.13/4.25）。"""
    return re.sub(r"(?m)^\s*//[^\n]*", "", src)


def _method_bodies(src):
    """按 async 方法切分：返回 (方法头, 方法体) 列表（括号计数）。"""
    out = []
    for m in re.finditer(r"Future<[^>]*>\s+\w+\s*\([^)]*\)\s+async\s*\{", src):
        start = m.end() - 1  # 指向 {
        depth = 1
        i = start + 1
        while i < len(src) and depth > 0:
            if src[i] == "{":
                depth += 1
            elif src[i] == "}":
                depth -= 1
            i += 1
        out.append((m.group(0), src[start:i]))
    return out


def _scan_file(path, rel, findings):
    src = io.open(path, encoding="utf-8", errors="replace", newline="").read()
    code = _strip_comments(src)

    # P0-2：pushNamed 家族
    for m in PUSHNAMED_PATTERN.finditer(code):
        ln = code[: m.start()].count("\n") + 1
        findings.append(("P0-2", rel, ln, m.group(0).strip(), "pushNamed 家族应为 0（IR-P0-2）"))

    # P1-4：硬编码路径
    for m in HARDCODE_PATH_PATTERN.finditer(code):
        ln = code[: m.start()].count("\n") + 1
        seg = code[m.end(): m.end() + 80]
        val = re.match(r"[^'\"\n)]*", seg)
        path = val.group(0).strip() if val and val.group(0).strip() else "?"
        findings.append(("P1-4", rel, ln, f"裸路径 '{path}'", "应引用 AppRoutes.x（IR-P1-4）"))

    # P0-3 + P1-1 + P1-5：方法级扫描
    for head, body in _method_bodies(src):
        code_body = _strip_comments(body)
        # P0-3：await 后 context 导航无 mounted
        if "await " in code_body and CONTEXT_NAV_PATTERN.search(code_body):
            has_mounted = "mounted" in code_body or "context.mounted" in code_body
            if not has_mounted:
                nav_m = CONTEXT_NAV_PATTERN.search(code_body)
                rel_off = src.find(body) + nav_m.start()
                ln = src[: rel_off].count("\n") + 1
                findings.append(("P0-3", rel, ln, nav_m.group(0).strip(), "await 后 context 导航无 mounted 候选（IR-P0-3）"))

        # P1-1：Navigator.pop 无保护候选（弹层多数合法，标记复核）
        for pop_m in NAV_POP_PATTERN.finditer(code_body):
            ctx = code_body[max(0, pop_m.start() - 200): pop_m.end() + 30]
            if "canPop" in ctx or "mounted" in ctx:
                continue
            rel_off = src.find(body) + pop_m.start()
            ln = src[: rel_off].count("\n") + 1
            findings.append(("P1-1", rel, ln, pop_m.group(0).strip(), "Navigator.pop 无 canPop/mounted 上下文候选（弹层合法则忽略）"))

        # P1-5：业务动作无防抖守卫
        if BIZ_ACTION_PATTERN.search(head):
            has_guard = any(g in code_body for g in DEBOUNCE_GUARDS)
            if not has_guard:
                ln = src[: src.find(head) + 1].count("\n") + 1
                findings.append(("P1-5", rel, ln, head.strip()[:60], "业务动作方法体无防抖守卫候选（调用方已有守卫则豁免，IR-P0-4 延伸）"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", default=DEFAULT_LIB)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--json", default=None, help="JSON 结果输出路径")
    args = ap.parse_args()

    findings = []
    for dirpath, _, files in os.walk(args.lib):
        for fn in sorted(files):
            if not fn.endswith(".dart") or fn.endswith((".g.dart", ".freezed.dart")):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, args.lib).replace("\\", "/")
            try:
                _scan_file(p, rel, findings)
            except Exception as e:  # noqa: BLE001
                print(f"[WARN] {rel}: {e}")

    p0 = [f for f in findings if f[0].startswith("P0")]
    p1 = [f for f in findings if f[0].startswith("P1")]

    if not args.quiet:
        for level, rel, ln, hit, note in findings:
            print(f"[{level}] {rel}:{ln}  {hit}")
            print(f"        {note}")

    if args.json:
        with io.open(args.json, "w", encoding="utf-8") as fh:
            json.dump([{"level": l, "file": r, "line": n, "hit": h, "note": t} for l, r, n, h, t in findings], fh, ensure_ascii=False, indent=1)

    print(f"\n交互回归扫描: P0={len(p0)}  P1={len(p1)}  合计={len(findings)}")
    if p0:
        print("⚠ P0 候选需处理或人工复核（出口条件 IR-P0=0）")
        return 1
    print("P0 = 0 ✓（P1 为报告性质）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
