#!/usr/bin/env python3
"""
月笙 Flutter 端 — 依赖健康检查（宪法 §二.6）。

消费 `dart pub outdated --json` 的 stdin/stdout（推荐管线调用）：
    dart pub outdated --json | python3 scripts/check_outdated.py --mode push
    dart pub outdated --json | python3 scripts/check_outdated.py --mode release

两种模式：
  --mode push    (默认) CI push/main 用：只打印报告 + CI warning 注解，恒 exit 0（不阻塞合入）
  --mode release Release build 前：CRITICAL 直接 exit 1；HIGH 仍告警但不阻断（可凭 D# 豁免）

分级依据（基于 dart pub outdated JSON 字段）：
  CRITICAL  isCurrentAffectedByAdvisory = True   — 当前版本命中官方安全公告/CVE，必须处理
  HIGH      isDiscontinued 或 isCurrentRetracted  — 包停更或当前版本已撤回
  MEDIUM    kind=direct 且 latest.major > resolvable.major — 直接依赖主版本落后
  LOW       其他 outdated（transitive/小版本/patch）—— 提示但不作为升级信号

豁免：在脚本旁放 `dependency_exemptions.json`（数组，每项 {"package":str,"until_date":"YYYY-MM-DD","reason":str,"d":"D#编号"}）
     对应包的 CRITICAL/HIGH 降为 WARN_EXEMPT，不触发 release mode exit。
"""
import argparse
import json
import os
import sys
from datetime import date
from pathlib import Path


EXEMPTIONS_FILE = Path(__file__).resolve().parent / "dependency_exemptions.json"


def load_exemptions() -> dict[str, dict]:
    if not EXEMPTIONS_FILE.exists():
        return {}
    try:
        raw = json.loads(EXEMPTIONS_FILE.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError as e:
        print(f"WARN: dependency_exemptions.json 解析失败，忽略豁免（{e}）", file=sys.stderr)
        return {}
    today = date.today().isoformat()
    out: dict[str, dict] = {}
    for item in raw:
        pkg = item.get("package")
        if not pkg:
            continue
        until = item.get("until_date")
        if until and until < today:
            print(f"WARN: 豁免 {pkg} 已过期（until={until}），已失效", file=sys.stderr)
            continue
        out[pkg] = item
    return out


def v(obj):
    return None if obj is None else obj.get("version")


def major_of(ver: str | None) -> int:
    if not ver:
        return 0
    try:
        seg = ver.split(".", 1)[0]
        # 去掉可能的 pre-release 后缀 + build
        seg = seg.split("-", 1)[0].split("+", 1)[0]
        return int(seg) if seg.isdigit() else 0
    except (ValueError, AttributeError):
        return 0


def classify(p: dict, exempt: dict) -> tuple[str, str | None]:
    """返回 (级别, 豁免标记或 None)。级别 ∈ {CRITICAL, HIGH, MEDIUM, LOW, OK, WARN_EXEMPT}."""
    pkg = p["package"]
    cur = v(p.get("resolvable")) or v(p.get("upgradable")) or v(p.get("current"))
    lat = v(p.get("latest"))
    outd = bool(cur and lat and cur != lat)

    reasons = []
    level = "OK"
    if p.get("isCurrentAffectedByAdvisory"):
        reasons.append("ADVISORY")
        level = "CRITICAL"
    if p.get("isDiscontinued"):
        reasons.append("DISCONTINUED")
        if level in ("OK", "MEDIUM", "LOW"):
            level = "HIGH"
    if p.get("isCurrentRetracted"):
        reasons.append("RETRACTED")
        if level in ("OK", "MEDIUM", "LOW"):
            level = "HIGH"

    if outd and level == "OK":
        direct = p.get("kind") in ("direct", "dev")
        if direct and major_of(lat) > major_of(cur):
            level = "MEDIUM"
            reasons.append(f"direct-major-behind ({cur}→{lat})")
        elif outd:
            level = "LOW"
            reasons.append(f"outdated ({cur}→{lat})")

    # 豁免处理（只影响 CRITICAL / HIGH；MEDIUM/LOW 本来就不阻断）
    if level in ("CRITICAL", "HIGH") and pkg in exempt:
        return ("WARN_EXEMPT", level)  # 第二个元素是原级别（保留用于表格展示）
    return (level, None)


def fmt_row(level, pkg, kind, cur, lat, note):
    ansi = {"CRITICAL": "\x1b[31m", "HIGH": "\x1b[33m", "MEDIUM": "\x1b[36m",
            "LOW": "\x1b[90m", "OK": "\x1b[32m", "WARN_EXEMPT": "\x1b[35m"}.get(level, "")
    reset = "\x1b[0m"
    return f"{ansi}{level:<12}{reset} {pkg:<30} {kind:<11} {str(cur or '-'):<12}→{str(lat or '-'):<12} {note}"


def emit_ci_warning(text: str):
    """GitHub Actions 工作流注解：在 UI 上高亮为 warning。"""
    cleaned = text.replace("\n", " ").replace("\r", " ")
    print(f"::warning file=pubspec.yaml::{cleaned}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Dependency health reporter for yuesheng-flutter")
    ap.add_argument("--mode", choices=["push", "release"], default="push",
                    help="push=仅告警不阻断（CI 默认）；release=CRITICAL 阻断（发布前）")
    ap.add_argument("--input", help="读 JSON 的文件路径（默认 stdin，便于管线）")
    args = ap.parse_args(argv)

    if args.input:
        raw = Path(args.input).read_text(encoding="utf-8-sig")
    else:
        raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"FAIL: dart pub outdated JSON 解析失败: {e}", file=sys.stderr)
        # 解析失败不阻断 push，但在 release 模式下提醒
        if args.mode == "release":
            emit_ci_warning("[outdated] JSON parse failed, cannot verify dependency health")
            return 2
        return 0

    exempt = load_exemptions()
    packages = data.get("packages") or []

    counts = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0, "OK": 0, "WARN_EXEMPT": 0}
    exempted_seen: list[tuple[str, str, dict]] = []
    critical_seen: list[str] = []

    print("============================================================")
    print(f" yuesheng-flutter dependency health report  @ {date.today()}")
    print(f" mode = {args.mode}  (exit non-zero only on CRITICAL in release mode)")
    print("============================================================")
    print(fmt_row("LEVEL", "PACKAGE", "KIND", "CURRENT", "LATEST", "NOTE"))

    direct_total = 0
    for p in packages:
        pkg = p["package"]
        kind = p.get("kind", "-")
        if kind in ("direct", "dev"):
            direct_total += 1
        cur = v(p.get("resolvable")) or v(p.get("upgradable")) or v(p.get("current"))
        lat = v(p.get("latest"))
        level, original = classify(p, exempt)
        counts[level] += 1

        if level == "WARN_EXEMPT":
            ex = exempt.get(pkg, {})
            note_parts = [f"[EXEMPT {ex.get('d', 'D#?')} until {ex.get('until_date', '∞')}] {ex.get('reason', '')}"]
            exempted_seen.append((pkg, original or "HIGH/CRITICAL", ex))
            # 还原原级别用于展示（用户仍能看到哪类被豁免了）
            disp_level = f"{original}(EXEMPT)" if original else "EXEMPT"
        else:
            note_parts = []
            if p.get("isCurrentAffectedByAdvisory"):
                note_parts.append("⚠ ADVISORY-HIT")
            if p.get("isDiscontinued"):
                note_parts.append("DISCONTINUED")
            if p.get("isCurrentRetracted"):
                note_parts.append("RETRACTED")
            if level == "MEDIUM":
                note_parts.append("direct major behind")
            if level == "LOW":
                note_parts.append(f"minor outdated {cur}→{lat}")
            disp_level = level

        if level == "CRITICAL":
            critical_seen.append(pkg)
            note_parts.insert(0, "SAFETY ADVISORY — review immediately")
        note = "; ".join(note_parts)

        if level != "OK":  # 只打印非 OK，OK 太多 noise
            print(fmt_row(disp_level, pkg, kind, cur, lat, note))

    outdated_total = sum(v for k, v in counts.items() if k not in ("OK",))
    print("------------------------------------------------------------")
    print(f" packages={len(packages)}  (direct/dev={direct_total})"
          f"  outdated_total={outdated_total}")
    print(f" CRITICAL={counts['CRITICAL']}  HIGH={counts['HIGH']}  "
          f"MEDIUM={counts['MEDIUM']}  LOW={counts['LOW']}  "
          f"WARN_EXEMPT={counts['WARN_EXEMPT']}  OK={counts['OK']}")
    print("------------------------------------------------------------")

    # CI annotation（只对 CRITICAL/HIGH/豁免过期做注解，避免刷屏）
    for pkg in critical_seen:
        emit_ci_warning(f"[outdated CRITICAL] {pkg} 命中官方安全公告 (isCurrentAffectedByAdvisory=true)，release mode 将阻断")
    # HIGH 也加注解（不阻断但提醒）
    if counts["HIGH"]:
        emit_ci_warning(f"[outdated HIGH] {counts['HIGH']} 个包为 DISCONTINUED 或 RETRACTED，请排期处理")
    if counts["WARN_EXEMPT"]:
        emit_ci_warning(f"[outdated EXEMPT] {counts['WARN_EXEMPT']} 个高危包被 D# 豁免登记，请定期复查 until_date")

    # 给 release mode 阻断
    if args.mode == "release" and counts["CRITICAL"] > 0:
        print("")
        print("FAIL (release mode): 存在 CRITICAL（安全公告命中）包，阻断发布。"
              "请处理后再 build，或凭 D# 决策登记 dependency_exemptions.json 豁免。")
        return 1

    print("")
    print(f"DONE  mode={args.mode}  exit={0 if args.mode == 'push' else (1 if counts['CRITICAL'] else 0)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
