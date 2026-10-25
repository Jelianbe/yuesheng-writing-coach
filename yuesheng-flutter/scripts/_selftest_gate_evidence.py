#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/_selftest_gate_evidence.py — 门禁证据链判据的负向自测（T-20261025-04）

【它测什么】
  直接调用 `scripts/lib_gate_evidence.sh` 里**上线用的那一份**判据函数，
  不另写一份实现 —— 另写一份 = 测的是另一件事（假绿）。

【为什么必须有它】
  「收紧成功」与「基线根本没生效」外观完全相同。五条判据（P1–P5）每条都配
  正测（真绿必须判绿）+ 负测（造假必须判红），另加两条**元探针**：
    S7 防恒绿：空文件必须判红
    S8 防恒红：真绿必须判绿
  缺元探针时，「判据恒绿」与「判据正常工作」不可区分。

【怎么跑】
  python3 scripts/_selftest_gate_evidence.py          # 全量
  python3 scripts/_selftest_gate_evidence.py -v       # 附每条探针的原始输出

【退出码】0 = 全部探针符合预期；1 = 至少一条不符（并打印失败探针名）。
  挂在 gate.sh 的约定层守卫上，**WARN 级**：自测挂了不该让门禁变红，但必须喊出来。
"""

import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(HERE, "lib_gate_evidence.sh")
ROOT = os.path.dirname(HERE)

VERBOSE = "-v" in sys.argv or "--verbose" in sys.argv

# flutter test 汇总行样本（真实形态，取自 2026-10-25 全绿轮）：
#   05:04 +5295 ~3: All tests passed!
GREEN_TAIL = "04:31 +5295 ~3: All tests passed!\n"
PROGRESS = (
    "04:29 +5291 ~3: test/widgets/writing_page_test.dart: 批次96-7 打开菜单读记忆高度\n"
    "04:30 +5292 ~3: test/widgets/writing_page_test.dart: 批次96-8 一键排版\n"
)

results = []  # [(name, ok, detail)]


def run_ev(func, *args, env=None):
    """在 bash 里 source 判据库后调用一个判据函数。返回 (rc, stdout, stderr)。"""
    cmd = ". %s; %s %s" % (shell_quote(LIB), func,
                           " ".join(shell_quote(str(a)) for a in args))
    p = subprocess.run(
        ["bash", "-c", cmd],
        cwd=ROOT, capture_output=True, text=True,
        encoding="utf-8", errors="replace",
        env={**os.environ, **(env or {})},
    )
    return p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip()


def shell_quote(s):
    return "'" + str(s).replace("'", "'\\''") + "'"


def probe(name, ok, detail):
    results.append((name, bool(ok), detail))
    mark = "PASS" if ok else "FAIL"
    print("/ %-6s %-28s %s" % (mark, name, detail if ok or VERBOSE else detail))
    if VERBOSE and ok:
        pass


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    return path


def make_green(d, name="green.txt"):
    return write(os.path.join(d, name), PROGRESS + GREEN_TAIL)


def make_baseline(d, count, name="baseline.json", omit=None):
    parts = {
        "count": str(count),
        "head": '"6970aee7"',
        "generated_at": '"2026-10-25T11:30:35+0800"',
        "reason": '"selftest fixture"',
    }
    if omit:
        parts.pop(omit, None)
    body = ", ".join('"%s": %s' % (k, v) for k, v in parts.items())
    return write(os.path.join(d, name), "{" + body + "}\n")


def main():
    if not os.path.isfile(LIB):
        print("FATAL 找不到判据库：%s" % LIB)
        return 1

    d = tempfile.mkdtemp(prefix="gate_evidence_selftest_")

    # ---------------- P1 汇总行 ----------------
    green = make_green(d)

    rc, out, _ = run_ev("ev_p1_summary", green)
    probe("S0-green", rc == 0, "真绿样本 ⇒ P1 判绿（rc=%d）" % rc)

    nosum = write(os.path.join(d, "no_summary.txt"), PROGRESS)
    rc, out, _ = run_ev("ev_p1_summary", nosum)
    probe("S1-no-summary", rc == 1, "删掉汇总行 ⇒ P1 判红（rc=%d）" % rc)

    tilde = write(os.path.join(d, "tilde.txt"), PROGRESS + GREEN_TAIL)
    rc, out, _ = run_ev("ev_p1_summary", tilde)
    probe("S1b-tilde", rc == 0, "含 ~N 跳过段必须仍判绿（rc=%d）" % rc)

    notilde = write(os.path.join(d, "notilde.txt"), "04:31 +5295: All tests passed!\n")
    rc, out, _ = run_ev("ev_p1_summary", notilde)
    probe("S1b2-no-tilde", rc == 0, "无 ~N 段的汇总行也必须判绿（rc=%d）" % rc)

    failed = write(os.path.join(d, "failed.txt"), PROGRESS + "04:31 +5295 -1: Some tests failed.\n")
    rc, out, _ = run_ev("ev_p1_summary", failed)
    probe("S1c-failed", rc == 1, "Some tests failed 必须判红（rc=%d）" % rc)

    noisy = write(
        os.path.join(d, "noisy.txt"),
        PROGRESS + GREEN_TAIL
        + "scripts/_run_flutter_test.sh: line 241: echo: write error: Permission denied\n",
    )
    rc, out, _ = run_ev("ev_p1_summary", noisy)
    probe("S1d-trailing-noise", rc == 0,
          "汇总行后跟写失败诊断时 P1 必须仍判绿（任意行口径；末行口径会假红，rc=%d）" % rc)

    # ---------------- P2 例数下限 ----------------
    base100 = make_baseline(d, 100)
    rc, out, _ = run_ev("ev_p2_count", green, base100)
    probe("S2b-higher", rc == 0 and "WARN" in out,
          "高于基线 ⇒ WARN 不 FAIL（rc=%d）" % rc)

    low = write(os.path.join(d, "low.txt"), PROGRESS + "04:31 +1 ~3: All tests passed!\n")
    rc, out, _ = run_ev("ev_p2_count", low, base100)
    probe("S2-lower", rc == 1, "低于基线 ⇒ FAIL（rc=%d）" % rc)

    eq = write(os.path.join(d, "eq.txt"), PROGRESS + "04:31 +100 ~3: All tests passed!\n")
    rc, out, _ = run_ev("ev_p2_count", eq, base100)
    probe("S2c-equal", rc == 0, "等于基线 ⇒ PASS（rc=%d）" % rc)

    nb_path = os.path.join(d, "fresh_baseline.json")
    rc, out, _ = run_ev("ev_p2_count", green, nb_path)
    created = os.path.isfile(nb_path)
    keys_ok = created and all(
        ('"%s"' % k) in open(nb_path, encoding="utf-8").read()
        for k in ("count", "head", "generated_at", "reason")
    )
    probe("S2d-no-baseline", rc == 0 and created and keys_ok,
          "基线缺失 ⇒ WARN + 首建且 provenance 四键齐（rc=%d, created=%s, keys=%s）"
          % (rc, created, keys_ok))

    badprov = make_baseline(d, 100, name="badprov.json", omit="head")
    rc, out, _ = run_ev("ev_p2_count", green, badprov)
    probe("S2e-bad-provenance", rc == 0 and "无效基线" in out,
          "缺 head 的基线 ⇒ 判无效、不采用（rc=%d）" % rc)

    rc, out, _ = run_ev("ev_p2_count", nosum, base100)
    probe("S2f-unparseable", rc == 0 and "归因 P1" in out,
          "无汇总行 ⇒ P2 不判、归因 P1（单点归因前提，rc=%d）" % rc)

    upd = make_baseline(d, 100, name="upd.json")
    rc, out, _ = run_ev("ev_p2_count", green, upd, env={"UPDATE_TEST_BASELINE": "1"})
    newcount = ""
    if os.path.isfile(upd):
        import re
        m = re.search(r'"count"\s*:\s*(\d+)', open(upd, encoding="utf-8").read())
        newcount = m.group(1) if m else ""
    probe("S2g-update-env", rc == 0 and newcount == "5295",
          "UPDATE_TEST_BASELINE=1 ⇒ 基线被显式刷新到 5295（实读=%s）" % (newcount or "取不到"))

    # ---------------- P3 日志可信性 ----------------
    rc, out, _ = run_ev("ev_p3_log_integrity", noisy)
    probe("S3-write-error", rc == 1, "锚定写失败诊断 ⇒ P3 判红（rc=%d）" % rc)

    rc, out, _ = run_ev("ev_p3_log_integrity", green)
    probe("S3a-clean", rc == 0, "干净样本 ⇒ P3 判绿（rc=%d）" % rc)

    falsepos = write(
        os.path.join(d, "falsepos.txt"),
        PROGRESS + GREEN_TAIL
        + "[FileSaver] save failed: Permission denied（业务文案，非 bash 诊断）\n",
    )
    rc, out, _ = run_ev("ev_p3_log_integrity", falsepos)
    probe("S3b-false-positive", rc == 0,
          "裸词面业务文案不得误判（锚定必要性，rc=%d）" % rc)

    # ---------------- P4a 覆盖率新鲜度 ----------------
    lcov = write(os.path.join(d, "lcov.info"), "SF:lib/x.dart\nLF:1\nLH:0\nend_of_record\n")
    run_start = 1792900000
    os.utime(lcov, (run_start - 3600, run_start - 3600))
    rc, out, _ = run_ev("ev_p4a_fresh", lcov, run_start)
    probe("S4a-stale", rc == 1, "lcov 比 run_start 老 ⇒ FAIL（rc=%d）" % rc)

    os.utime(lcov, (run_start, run_start))
    rc, out, _ = run_ev("ev_p4a_fresh", lcov, run_start)
    probe("S4b-same-second", rc == 0,
          "mtime == run_start（同秒）必须判绿 ⇒ 证明用的是 >= 不是 >（rc=%d）" % rc)

    os.utime(lcov, (run_start + 5, run_start + 5))
    rc, out, _ = run_ev("ev_p4a_fresh", lcov, run_start)
    probe("S4b2-newer", rc == 0, "lcov 比 run_start 新 ⇒ 判绿（rc=%d）" % rc)

    missing_lcov = os.path.join(d, "no_such_lcov.info")
    rc, out, err = run_ev("ev_p4a_fresh", missing_lcov, run_start)
    probe("S4c-missing", rc == 1 and "stat:" not in err,
          "lcov 缺失 ⇒ FAIL 且 stderr 无 stat: 报错（rc=%d, stderr=%s）"
          % (rc, err[:40] or "空"))

    # ---------------- P4b 实际 COV_FLAG ----------------
    noflag = os.path.join(d, "no_such_cov_flag.txt")
    try:
        rc, out, _ = run_ev("ev_p4b_cov_flag", noflag)
    except Exception as exc:  # noqa: BLE001
        rc, out = -1, ""
    probe("S5-unknown", out == "UNKNOWN",
          "cov_flag.txt 缺失 ⇒ UNKNOWN（不是空串、不是缺键；rc=%d）" % rc)

    empty_flag = write(os.path.join(d, "cov_flag_empty.txt"), "")
    rc, out, _ = run_ev("ev_p4b_cov_flag", empty_flag)
    probe("S5b-empty", rc == 0 and out == "",
          "空文件 ⇒ 空串，且可与 UNKNOWN 区分（rc=%d）" % rc)

    real_flag = write(os.path.join(d, "cov_flag_real.txt"), "--coverage\n")
    rc, out, _ = run_ev("ev_p4b_cov_flag", real_flag)
    probe("S5c-value", rc == 0 and out == "--coverage",
          "实值 ⇒ --coverage（rc=%d）" % rc)

    # ---------------- P5 工作树脏度 ----------------
    rc, out, _ = run_ev("ev_p5_dirty_count")
    probe("S6-dirty-count", rc == 0 and out.isdigit(),
          "返回整数（当前 worktree dirty_count=%s）" % out)

    # ---------------- 元探针 ----------------
    empty_txt = write(os.path.join(d, "empty.txt"), "")
    rc, out, _ = run_ev("ev_p1_summary", empty_txt)
    probe("S7-meta-not-always-green", rc == 1,
          "空文件必须判红 ⇒ 判据不是恒绿（rc=%d）" % rc)

    rc, out, _ = run_ev("ev_p1_summary", green)
    probe("S8-meta-not-always-red", rc == 0,
          "真绿必须判绿 ⇒ 判据不是恒红（rc=%d）" % rc)

    # ---------------- 真样本（信息性，不影响退出码）----------------
    real = os.path.join(ROOT, "outputs", "gate", "test.txt")
    if os.path.isfile(real):
        rc, out, _ = run_ev("ev_p1_summary", real)
        rc3, _, _ = run_ev("ev_p3_log_integrity", real)
        print("/ INFO   真样本 outputs/gate/test.txt  P1 rc=%d · P3 rc=%d（信息性，不参与判定）"
              % (rc, rc3))
        if out:
            print("         %s" % out)
    else:
        print("/ INFO   真样本 outputs/gate/test.txt 不存在 ⇒ 跳过（信息性）")

    # ---------------- 汇总 ----------------
    bad = [n for n, ok, _ in results if not ok]
    print("-" * 60)
    print("探针 %d 条：通过 %d / 失败 %d" % (len(results), len(results) - len(bad), len(bad)))
    if bad:
        print("失败探针：%s" % ", ".join(bad))
        print("⇒ 判据可能已退化（恒绿/恒红/归因错误）。这不是「测试挂了」，是**判据坏了**。")
        return 1
    print("OK 全部探针符合预期（含 S7/S8 元探针：判据既非恒绿也非恒红）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
