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

【残余风险 R2 —— 已从「不修」改为「加哨兵兜底」（2026-10-25 改判）】
  原始担心：本脚本发现不了「自身被改坏」，尤其是 `probe()` 被改成恒真（= 变异 m10）
  ⇒ 所有探针都报 PASS，退出码仍是 0。
  ⚠️ 我曾据此写下「任何自测都无法自证『自己没被强制绿』」，**那句话过强**。
     独立复核用十来行推翻了它：见下面的 `_probe_can_report_failure()` ——
     不看 `bad`（那是从 results 算出来的，probe() 恒真时恒空），
     而是**塞一条已知必失败的探针、直接看它落进去是不是 False**。
  现在这套组合能抓的与抓不到的，写清楚：
    · 能抓：`probe()` 被改成恒真 ⇒ 哨兵返回 False ⇒ 汇总前 rc=1（**已实测**）。
    · 能抓：探针被删/改名 ⇒ R3 的条数 + 名称清单自断言 ⇒ rc=1（**已实测**）。
    · 抓不到：**`probe()` 与 `_probe_can_report_failure()` 被同时改坏**。
      这是有意的：兜底与本体不同源就只能做到这一步，再往上加就是自指涉递归。
      ⇒ 残余风险由此降级为「**必须同时改两处才会静默**」。
    · 抓不到：有人把 EXPECTED_PROBE_COUNT/NAMES 一并改成迁就「探针被删剩几条」。
      外部 sha256 基线只能防「文件被改」，防不了「文件本来就这么写」；
      真正的出口仍是**异体复核**（独立成员跑变异测试，本卡一直由 VRS 做就是这个原因）。
  ⇒ **后来者不许把这一段当待办去做**：它是一个作过的决定（先判不修、后被推翻、改成低
    成本兜底）。要推翻请先指出哨兵与本体在哪条路上共因。

【改探针的规矩】增删/改名任何一条探针，**必须同笔改 EXPECTED_PROBE_COUNT 与
  EXPECTED_PROBE_NAMES**，否则自测会红。这是有意的：让它红，好过让它静默地少测几条。
"""

import contextlib
import io
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(HERE, "lib_gate_evidence.sh")
ROOT = os.path.dirname(HERE)

VERBOSE = "-v" in sys.argv or "--verbose" in sys.argv

# ---------------- 期望的探针清单（R3 自断言的锚）----------------
# 【为什么要有它】删掉一条探针、或把某个 `probe(...)` 注释掉，只要剩下的都通过，
#   输出与「全过」在外观上**一字不差** —— 「覆盖变少」与「覆盖完好」同形。
#   实测过的反例：把 S7 元探针整条注释掉，上一版仍报「探针 34 条：通过 34 / 失败 0」且 rc=0。
# 【为什么不止断言条数】删一条 + 加一条 ⇒ **条数不变、覆盖已经变了**。条数断言抓不到。
#   ⇒ 必须同时比对**名称集合**。
# 【常量怎么来的】不是估的，是**跑出来的**（第 6 笔删掉 S6 之后实测）：
#   `python scripts/_selftest_gate_evidence.py | grep '探针 '`
#     ⇒ 「探针 35 条：通过 35 / 失败 0」
#   ⚠️ **不要**用 `grep -cE '^[[:space:]]+probe\('` 当判据：哨兵
#   `_probe_can_report_failure()` 里也有一行 `probe("__SANITY__", …)`（且它故意
#   不计入条数）⇒ 那个 grep 现在回 **36**，与实跑的 35 差 1。用错的判据去核这个
#   常量，会得出「常量写错了」的假结论 —— 这正是本仓反复踩的那类坑。
EXPECTED_PROBE_COUNT = 35
EXPECTED_PROBE_NAMES = (
    "S0-green",
    "S1-no-summary",
    "S1b-tilde",
    "S1b2-no-tilde",
    "S1c-failed",
    "S1d-trailing-noise",
    "S2b-higher",
    "S2-lower",
    "S2c-equal",
    "S2d-no-baseline",
    "S2e-bad-provenance",
    "S2f-unparseable",
    "S2g-update-env",
    "S3-write-error",
    "S3a-clean",
    "S3b-false-positive",
    "S4a-stale",
    "S4b-same-second",
    "S4b2-newer",
    "S4c-missing",
    "S5-unknown",
    "S5b-empty",
    "S5c-value",
    "S11-missing-state",
    "S11b-empty-state",
    "S11c-crlf",
    "S9-tag-p1-fail",
    "S9b-tag-p2-fail",
    "S9c-tag-p3-fail",
    "S9d-tag-p2-na",
    "S10-all-green",
    "S10b-only-p1",
    "S10c-missing-log",
    "S7-meta-not-always-green",
    "S8-meta-not-always-red",
)

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


def run_shell(cmd):
    """跑一段自由 bash（source 判据库后可以连着看多个变量）。

    为什么需要它：`ev_p4b_cov_flag` 只打印值，**看不到** `_ev_p4b_read` 给出的
    `EV_P4B_MISSING` 标志位 —— 而 gate.sh 的分支正是按那个标志位走的
    （「文件在但为空」判 FAIL，「文件缺失」判 WARN）。只测打印值会漏掉这条分叉。
    """
    p = subprocess.run(["bash", "-c", cmd], cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "").strip()


def probe(name, ok, detail):
    results.append((name, bool(ok), detail))
    mark = "PASS" if ok else "FAIL"
    print("/ %-6s %-28s %s" % (mark, name, detail if ok or VERBOSE else detail))
    if VERBOSE and ok:
        pass


def _probe_can_report_failure():
    """哨兵（R2 的兜底）：直接验 `probe()` 还能不能**报告失败**。

    【为什么不复用 results 汇总】`bad` 是**从 results 算出来的**。若 `probe()` 被改成
      `ok = True`，results 里就全是 True，`bad` 恒空 —— 让嫌疑人自己作证，永远判无罪。
      这里改成：往 results 里塞一条**已知必失败**的探针，直接看它落进去之后是不是 `False`。
    【为什么不经任何别的环节】只依赖 `results` 的**追加**与**末元素取值**这两个动作，
      不依赖标记、不依赖 bad、不依赖退出码计算 ⇒ 不会被同一条篡改带走。
    【不污染汇总】末尾 `del results[n0:]` 把它自己抹掉；`EXPECTED_PROBE_COUNT` 不受影响。
    【输出不污染】把探针自身的打印重定向掉，否则每次正常跑都会多一行 `FAIL __SANITY__`，
      下一个人会去查一个不存在的问题。
    【能变红（已实测）】把 `probe()` 里的 `bool(ok)` 改成 `True`（= 变异审计的 m10）
      ⇒ `results[-1][1] is False` 为 False ⇒ 本函数返回 False ⇒ 汇总前直接 rc=1。
    """
    n0 = len(results)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        probe("__SANITY__", False, "哨兵：本行必须被判 FAIL（不参与汇总）")
    ok = (len(results) == n0 + 1) and (results[-1][1] is False)
    del results[n0:]
    return ok


def self_check_probe_manifest(names):
    """R3：把「实跑的探针名字」与 EXPECTED_PROBE_* 对齐。返回问题列表（空 = 通过）。

    ★ 它自己**不**计入探针条数：计入的话，「删一条探针」会同时减少一条实跑并增加
      一条自断言 ⇒ 条数恰好不变，自指涉地把断言弄废。所以它单独打一行。
    【为什么能变红（已实测，不是推理）】
      · 注释掉任意一条 probe(...) ⇒ 「条数不符 34 ≠ 35」+「少了一条：<名字>」
      · 注释掉 S7 ⇒ 「少了一条：S7-meta-not-always-green」
    """
    problems = []
    if len(names) != EXPECTED_PROBE_COUNT:
        problems.append("条数不符：实跑 %d 条 / 期望 %d 条"
                        % (len(names), EXPECTED_PROBE_COUNT))
    dup = [n for n in sorted(set(names)) if names.count(n) > 1]
    if dup:
        problems.append("探针名重复：%s" % ", ".join(dup))
    missing = [n for n in EXPECTED_PROBE_NAMES if n not in names]
    if missing:
        problems.append("少了一条：%s" % ", ".join(missing))
    extra = [n for n in names if n not in EXPECTED_PROBE_NAMES]
    if extra:
        problems.append("多了一条（不在期望清单里）：%s" % ", ".join(extra))
    return problems


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

    # ---- P4b 的三态标志位（gate.sh 按 EV_P4B_MISSING 分叉，必须单独钉）----
    # 「文件缺失」与「文件在但为空」在**打印值**上已经可分（UNKNOWN vs 空），
    # 但 gate.sh 走的是**标志位**。「空文件被判成 missing」会把
    # 「明确没开覆盖率」（该 FAIL）降级成「不知道」（只 WARN）—— 一条静默降级通路。
    rc, out = run_shell(
        ". %s; _ev_p4b_read %s; printf 'missing=%%s value=[%%s]' "
        "\"$EV_P4B_MISSING\" \"$EV_P4B_VALUE\"" % (shell_quote(LIB), shell_quote(noflag)))
    probe("S11-missing-state", out == "missing=1 value=[UNKNOWN]",
          "文件缺失 ⇒ missing=1 且 value=UNKNOWN（实读=%r）" % out)

    empty_flag2 = write(os.path.join(d, "cov_flag_empty2.txt"), "")
    rc, out = run_shell(
        ". %s; _ev_p4b_read %s; printf 'missing=%%s value=[%%s]' "
        "\"$EV_P4B_MISSING\" \"$EV_P4B_VALUE\"" % (shell_quote(LIB), shell_quote(empty_flag2)))
    probe("S11b-empty-state", out == "missing=0 value=[]",
          "空文件 ⇒ missing=0 且值为空（不得被判成缺失，实读=%r）" % out)

    crlf_flag = write(os.path.join(d, "cov_flag_crlf.txt"), "--coverage\r\n")
    rc, out = run_shell(
        ". %s; _ev_p4b_read %s; printf '[%%s]' \"$EV_P4B_VALUE\""
        % (shell_quote(LIB), shell_quote(crlf_flag)))
    probe("S11c-crlf", out == "[--coverage]",
          "CRLF 写入 ⇒ 值不带 \\r（否则与 --coverage 比较永不成立，实读=%r）" % out)

    # ---------------- P5 工作树脏度：**这里刻意没有探针** ----------------
    # 曾经有一条 `S6-dirty-count`，调 `lib_gate_evidence.sh` 的 `ev_p5_dirty_count`。
    # 2026-10-25 它连同那个库函数一起被删了（T-20261025-04 第6笔）。三条原因都别忘：
    #   ① 那个库函数与 `gate-run.sh` 的内联块**不是同一份代码** ⇒ 探针测的不是上线那份。
    #   ② 库函数在 `git` 失败时返回 `0`（`wc -l` 对空输入照样给 0）⇒ 把「读不到」
    #      记成「干净」，而生产版同环境返回 `-1`。两种语义互斥。
    #   ③ 探针断言写的是 `out.isdigit()`，而 `"-1".isdigit()` 在 Python 里是 **False**
    #      ⇒ **只要有人把库函数改对，这条探针立刻变红** —— 一条「正确修法会被自测拦住」的路径。
    #   ⇒ 删它是**消除一条反向判据**，不是降低覆盖。`dirty_count` 不判红，它的端到端判据
    #     在 `gate-run.sh` 那侧（提取内联块来测），不在这个文件里。
    #   ⇒ **不要在这里补一条新探针把条数凑回 36。** 条数不是指标，判据有效才是。

    # ---------------- 标签契约（「单点归因」直接依赖它）----------------
    # gate.sh 的验收判据是 `grep -c '\[FAIL\] P1' <该轮 stdout>` = 1 且另两条 = 0。
    # 所以「判红时首标记是 [FAIL] P<n>」本身是一条必须被测的契约 ——
    # 格式一改，归因断言就静默失效（红了却说不出哪条红 = 与没红等价）。
    rc, out, _ = run_ev("ev_p1_summary", nosum)
    probe("S9-tag-p1-fail", out.startswith("[FAIL] P1"),
          "P1 判红首标记必须是 [FAIL] P1（实读=%r）" % out[:26])
    rc, out, _ = run_ev("ev_p2_count", low, base100)
    probe("S9b-tag-p2-fail", out.startswith("[FAIL] P2"),
          "P2 判红首标记必须是 [FAIL] P2（实读=%r）" % out[:26])
    rc, out, _ = run_ev("ev_p3_log_integrity", noisy)
    probe("S9c-tag-p3-fail", out.startswith("[FAIL] P3"),
          "P3 判红首标记必须是 [FAIL] P3（实读=%r）" % out[:26])
    rc, out, _ = run_ev("ev_p2_count", nosum, base100)
    probe("S9d-tag-p2-na", out.startswith("[N/A] P2") and "[FAIL]" not in out,
          "P2 无输入时不得出现 [FAIL]（否则破坏 P1 会连带 P2 变红，归因失效）")

    # ---------------- 单一入口 ev_check_p123（gate.sh 实际调的形态）----------------
    # 为什么单测这一条：gate.sh 里写三行 `msg="$(ev_p<n> …)"` 与写一行
    # `ev_check_p123` 在**结论上完全等价**，但在「日志被读几遍」上差 3 倍。
    # 结论等价的两种写法，只有一种是指令要的 —— 所以必须有一条探针钉住入口形态。
    rc, out, _ = run_ev("ev_check_p123", green, base100)
    lines = [l for l in out.splitlines() if l.strip()]
    probe("S10-all-green", rc == 0 and len(lines) == 3
          and lines[0].startswith("[PASS] P1")
          and lines[1].startswith("[WARN] P2") and lines[2].startswith("[PASS] P3"),
          "三行齐全、按 P1/P2/P3 顺序、全绿不 FAIL（rc=%d, 行数=%d）" % (rc, len(lines)))

    rc, out, _ = run_ev("ev_check_p123", nosum, base100)
    lines = [l for l in out.splitlines() if l.strip()]
    probe("S10b-only-p1", rc == 1 and len(lines) == 3
          and sum(1 for l in lines if l.startswith("[FAIL] P1")) == 1
          and sum(1 for l in lines if "[FAIL] P2" in l) == 0
          and sum(1 for l in lines if "[FAIL] P3" in l) == 0,
          "只破坏 P1 ⇒ rc=1 且只有 P1 红（单点归因，行数=%d）" % len(lines))

    missing = os.path.join(d, "no_such_log.txt")
    rc, out, _ = run_ev("ev_check_p123", missing, base100)
    lines = [l for l in out.splitlines() if l.strip()]
    probe("S10c-missing-log", rc == 1 and len(lines) == 3,
          "日志缺失 ⇒ 仍打满三行（少打一行会把「没判」伪装成「通过」，行数=%d）" % len(lines))

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

    # ---------------- 哨兵（R2 的兜底）：probe() 还能不能报告失败 ----------------
    # ⚠️ 必须放在**汇总之前**、且**不经 probe()** —— 否则它自己也会被同一条篡改带走
    #    （用 `bad` 判自检 = 让嫌疑人自己作证：probe() 恒真时 bad 恒空）。
    if not _probe_can_report_failure():
        print("-" * 60)
        print("FAIL 自检哨兵：probe() 已不能报告失败 ⇒ 本次「全绿」无意义，不计入通过")
        print("     ⇒ 处置：先修 probe()，或改用与 probe() 无共因的检查；")
        print("        **不要**把本行当噪声跳过 —— 它意味着上面每一行 PASS 都不可信。")
        return 1

    # ---------------- 汇总 ----------------
    bad = [n for n, ok, _ in results if not ok]
    names = [n for n, _, _ in results]
    manifest = self_check_probe_manifest(names)
    print("-" * 60)
    print("探针 %d 条：通过 %d / 失败 %d" % (len(results), len(results) - len(bad), len(bad)))
    print("清单自断言（R3）：%s"
          % ("不通过" if manifest
             else "通过（条数 %d / 名称 %d 项均与常量一致）"
                  % (EXPECTED_PROBE_COUNT, len(EXPECTED_PROBE_NAMES))))
    if manifest:
        for p in manifest:
            print("[FAIL] 探针清单自断言：%s" % p)
        print("⇒ 实跑清单与 EXPECTED_PROBE_* 不一致。**先别改常量** ——")
        print("   先确认去掉/加上的那条是真不需要了，再同笔改常量；")
        print("   顺手改常量等于把「覆盖被缩小」这件事改成了「符合预期」。")
    if bad:
        print("失败探针：%s" % ", ".join(bad))
        print("⇒ 判据可能已退化（恒绿/恒红/归因错误）。这不是「测试挂了」，是**判据坏了**。")
    if bad or manifest:
        return 1
    print("OK 全部探针符合预期（S7/S8 元探针**只**覆盖 P1：能抓 P1 单点恒绿 / 单点恒红；"
          "不覆盖 P2–P5。自测层自身由 _probe_can_report_failure() 哨兵兜底，"
          "残余风险见文件头 R2：须同时改坏 probe() 与哨兵才会静默）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
