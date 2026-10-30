#!/usr/bin/env bash
# ============================================================
# 月笙写作教练 Flutter 端 — 十九道门禁 (R-027 + 宪法 §二)
#
# ★ 统一入口：`bash scripts/gate-run.sh`（默认即本脚本）。
#   本文件仍是**判据真源**；gate-run.sh 只做选路 / 透传 / 记运行流水，**不含任何判据**。
#
# 【2026-10-05 新增·三档分组标注】——★ **只标注、不改调度逻辑**
#   分档依据 = 2026-10-05 成本审计实测的逐道耗时
#   （报告：.ai/reports/2026-10-05-门禁合并去重调研.md）
#
#   ┌ 档位 │ 道次│ 实测耗时 │ 说明
#   ├──────┼────────────┼──────────────────────────────────────
#   │ 主力 │ 2       │ 303.1s │ **占全轮 96.7%**，单道决定总时长
#   │ 次要 │ 1       │   5.9s │ 静态分析
#   │ 次要 │ 0       │   ≈4s  │ 格式校验
#   │ 轻量 │ 3       │   1.7s │ 循环依赖
#   │ 轻量 │ 5/ 7 / 9 │ 各 ≤1.2s │ R-019 / Prompt / 交互回归
#   │ 轻量 │ 4/ 6/ 8 / 10 / 11 / 12 / 13 │ 各 ≤0.3s │ 七道合计 ≈1.0s
#   └──────┴────────────┴──────────────────────────────────────
#   ⚠️ 【口径注 2026-10-14，T-20261014-05】上表 = **道 0–13 时期（14 道口径）的实测**；
#      道 14–18 于后续批次新增（flag 契约 / ADR 悬空 / hook 副本 / 台账新鲜度 /
#      prompt 体积），**无独立逐道耗时实测**，均为轻量脚本（估 ≤1s/道）。
#      本表现行总道数 = **19 道（0–18）**，与下方 echo「门禁 X/19」一致。
#   ⇒ 14 道时期：13 道（除主力）合计 ≈12.6s（4.1%），故：
#     · 「合并去重」若按「减少道数」做，**收益上限 4%** —— 不做
#     · 「加并行提速」不是可选项（实测可用内存仅 5.8 GiB/ 32 核，内存优先）
#     · 快道分层（gate-fast.sh）已存在且有效，本批实测命中 3 文件 / 11 通过
#
#   ⚠️ **分档 ≠ 可以少跑**。三档只用于「定位失败在哪一档」与「估算收尾时间」，
#      **绝不可据此跳过任何一道**（既有纪律：绝不用「减少检查项」换速度）。
#
#   ⚠️ **与 CI 的口径分叉（事实登记，非待办；2026-10-14 按 19 道口径订正）**：
#      本文件 **19 道全跑**；
#      仓库根 `.github/workflows/flutter_ci.yaml` **只跑其中 6 道**
#      （0/1/2/3/4 + 6）+ CI 独有的依赖健康，
#      **门禁 5/7/8/9/10/11/12/13/14/15/16/17/18 从不在 CI 出现**
#      ⇒ **「本地全绿」才是收尾；「CI 全绿」≠ 十九道全绿**。
#      分叉理由与成本实测见该文件同处注释（该文件头部口径已于 2026-10-14 同批对齐 19 道）。
#
# 门禁 0: 代码格式 (dart format --set-exit-if-changed lib test integration_test tool)
#         ⚠️ 2026-09-17 扩范围：原为 `lib`，**test/ 从未被格式检查**——实测 325 个
#            test 文件里 35 个格式不符，其中 27 个与本批改动无关（纯存量无人管）。
# 门禁 1: 静态分析 (dart analyze lib integration_test tool test) — 类型检查 + Lint
#         ⚠️ 2026-09-17 扩范围（两段）：原为 `dart analyze lib`，只覆盖 lib/ ⇒
#            integration_test/ · tool/ · test/ 从未被静态分析。实证代价：
#            ① integration_test/ 内一个**编译级 error**（FakeLlmClient 未跟进
#               LlmClient.extraBody）躺了整整一个月无人察觉；
#            ② test/ 内另有一个**编译级 error**（archive_export_service_test.dart
#               在 strict-casts 下 dynamic→Object 报 argument_type_not_assignable）
#               ＋ 47 warning ＋ 40 info，同样无人察觉。
#            test/ 已于本批清零（88 → 0）并纳入。
#         ⚠️ fatal 语义：`dart analyze` 默认 --fatal-warnings=on / --fatal-infos=off，
#            故 info 级风格问题不阻断（那是门禁 0 的职责）。
#            **复现门禁请用 `dart analyze`，勿用 `flutter analyze`**——
#            后者 infos 也 fatal，会得到 rc=1 的假红（2026-09-17 实测踩过）。
# 门禁 2: 单元测试 (scripts/_run_flutter_test.sh → flutter test --coverage
#            --exclude-tags live,external) — 同时产出 coverage/lcov.info
#         ⚠️ 固定参数以 scripts/_run_flutter_test.sh 为**单一真源**，此处不复述。
#            其中 --exclude-tags live,external 于 2026-09-17 补齐：此前**只有 CI**
#            有标签排除、本地门禁 2 没有 ⇒ 同一仓库两套口径。CI 注释写明该参数是
#            「双保险：即使某条 live 测试的 markTestSkipped 位置没提前到
#            LlmClient() 构造之前，也不会触发出站网络调用」。本地同样需要。
#         ⚠️ 快道（gate-fast.sh）置 RUN_FLUTTER_TEST_COVERAGE=0 关掉 --coverage：
#            窄范围测试若写了 lcov，会盖掉 coverage/lcov.info，使收尾门禁 6 假红。
# 门禁 3: 循环依赖扫描 (scripts/check_circular.py) — 宪法 §二.4 / R-020
#         **全量卡口**：2026-09-03 ADR-C70 解开全部 3 个存量环后已撤除豁免基线
#         ⚠️ 本门禁曾长期假绿（路径不可解析 + lib 缺失时 return 0 放行 +
#            裸相对导入不进图），2026-09-03 修复，详见下方门禁 3 注释
# 门禁 4: 安全/密钥扫描 (scripts/check_secrets.sh) — R-029
# 门禁 5: R-019 函数行数 (tool/check_r019.py --baseline) — 宪法 §二.3 硬上限
#         止血模式：以 tool/r019_baseline.json 为基线，存量豁免、只卡新增
# 门禁 6: 覆盖率 (scripts/check_coverage.py) — R-013 口径补全
#         T1 = 整体行覆盖率 ≥ 65%（±2% 容差，< 63% 才 FAIL）
#         T2 = 五个核心文件各自 85% 硬门槛
#         ⚠️ **必须**读取门禁 2 刚产出的 coverage/lcov.info（门禁 2 已带
#            --coverage）。覆盖率不能独立跑测试：陈旧 lcov 会假绿
#            （查的是旧代码），单文件测试产出的 lcov 会假红（T1 仅 0.83%）。
# 门禁 7: Prompt 反模式 (scripts/check_prompt_antipattern.py --diff-baseline) — R-025
# 门禁 8: 内容元数据 (scripts/check_content_metadata.py --strict) — R-025
# 门禁 9: 交互回归 (scripts/check_interaction_regression.py) — 仅 P0 阻断
# 门禁 10: 伪拆分形态 (scripts/check_split_shape.py --baseline) — R-019 §2
#          A 类纯常量知识库按文件名豁免（见 R-019:57-60）
# 门禁 11: A 类豁免准入 (scripts/check_a_class_exemption.py --baseline) — R-019:57-60
#          把 A 类豁免的**前提**变成可执行判据（内容级），堵住门禁 10 的 fail-open
#          基线 tool/a_class_exemption_baseline.json，止血模式：只卡新增
# 门禁 12: Skill 公共库链接 (scripts/check_skills_links.py) — ADR-C115
#          「单一真源 .agents/skills + 工作台 Junction」结构守卫：① Junction 目标
#          必须存在（防悬空死链）② 公共库 SKILL.md frontmatter 合法（name/description）
#          ③ 旧代 skill 必须带作废标注（防误迁入公共库被助手误加载）
# 门禁 13: extension 单块行数 (scripts/check_extension_shape.py) — ADR-0004 §2 R-2
#          给「减行数不得用 extension」补机器执行点（此前零执行点）；
#          阈值 300 与 R-019 文件级同值。
# ★ 批 4（2026-10-07）：由「基线豁免、只卡新增」**升为全量卡口**——
#   ChatServiceSend 已拆至 292 行（1193 → 292，三批递减 901 行），
#   tool/extension_shape_baseline.json 的最后一条豁免随之删除。
#   ⇒ 现在**任何** extension 块超 300 行都会阻断提交（收紧）。
set -u

# ★ Python 子进程输出编码：Windows 中文 locale 下 python 的 stdout 是 GBK，打「✓」即崩 ⇒ 该道假红。
#   同 gate-fast.sh（2026-09-21 实证：pre-commit 快道 5 道 FAIL，而收尾门禁经带 UTF-8 的桥跑 12/12）。
#   已有显式设定则不覆盖。
export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

OUT_DIR="$ROOT/outputs/gate"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/gate-report.md"

# 日志落盘
FORMAT_LOG="$OUT_DIR/format.txt"
TYPECHECK_LOG="$OUT_DIR/typecheck.txt"
# ⚠️ TEST_LOG **不在这里定义**：它的文件名含 `$GATE_RUN_ID`（见下方「测试日志命名与保留策略」）。
#   顺序不可反 —— 本文件 `set -u` 在生效，提前展开未定义变量会当场 abort。
CIRCULAR_LOG="$OUT_DIR/circular.txt"
SECURITY_LOG="$OUT_DIR/security.txt"
R019_LOG="$OUT_DIR/r019.txt"
COVERAGE_LOG="$OUT_DIR/coverage.txt"
PROMPT_LINT_LOG="$OUT_DIR/prompt_lint.txt"
META_LOG="$OUT_DIR/content_metadata.txt"
INTERACTION_LOG="$OUT_DIR/interaction.txt"
SPLIT_LOG="$OUT_DIR/split_shape.txt"
A_CLASS_LOG="$OUT_DIR/a_class_exemption.txt"
SKILLS_LINKS_LOG="$OUT_DIR/skills_links.txt"
EXT_SHAPE_LOG="$OUT_DIR/extension_shape.txt"
FLAG_CONTRACT_LOG="$OUT_DIR/flag_contract.txt"
ADR_DANGLING_LOG="$OUT_DIR/adr_dangling.txt"
HOOK_SYNC_LOG="$OUT_DIR/hook_sync.txt"
LEDGER_FRESH_LOG="$OUT_DIR/ledger_freshness.txt"
PROMPT_VOLUME_LOG="$OUT_DIR/prompt_volume.txt"
WIRING_LOG="$OUT_DIR/wiring.txt"
SURFACE_LOG="$OUT_DIR/surface_visibility.txt"
SURFACE_SELFTEST_LOG="$OUT_DIR/surface_visibility_selftest.txt"
SOURCE_EXIT_LOG="$OUT_DIR/source_exit.txt"
# 证据链判据自测的日志（WARN 级守卫，不计入十九道）。输出的落点必须固定，
# 否则「自测跑过」与「自测没跑」在事后看只差一个没人读的 stdout。
SELFTEST_EVID_LOG="$OUT_DIR/selftest_gate_evidence.txt"

# P4b 证据文件：由 scripts/_run_flutter_test.sh 在决定 COV_FLAG 之后写入（T-20261025-04）。
# 放在 OUT_DIR（已被 .gitignore 忽略）⇒ 不污染 git status。
# ⚠️ 起跑时**立刻删掉**上一轮留下的那一份，本轮的证据只能由本轮的 wrapper 产生。
#    不删的后果：wrapper 因为版本旧/中途 abort 而没写时，门禁会读到**上一轮的值**
#    ⇒ 把「不知道」显示成「--coverage」= 拿旧事实给新结论作证 —— 这正是本卡要治的病。
#    ⇒ 删了之后，「缺失」才是本轮的缺失，UNKNOWN 才有意义。
#    副作用（有意接受）：门禁 0/1 这两行记录的 cov_flag 会是 UNKNOWN，
#    因为那时 wrapper 确实还没跑。「本轮此刻开了覆盖率吗」的诚实答案是「还不知道」，
#    比填一个上一轮的 `--coverage` 更接近事实。
COV_FLAG_FILE="$OUT_DIR/cov_flag.txt"
rm -f "$COV_FLAG_FILE"

# 判据库（门禁 2 的 P1/P2/P3、门禁 6 的 P4a/P4b 共用同一份定义）。
# **只 source 一次**：两处各 source 一遍，早晚会出现「一处 source 了、另一处没 source」
# 而某一侧判据静默变成 command not found 的分叉。库内无副作用（不打印、不写盘）。
EV_LIB_OK=0
if . "$ROOT/scripts/lib_gate_evidence.sh" 2>/dev/null; then
  EV_LIB_OK=1
fi

pass=0
fail=0
degraded=0   # 因环境缺失而**未真正执行**的门禁数（fail-closed：计入退出码）

# ---------- 命中率流水（2026-10-20 新增 · 汇总见 scripts/gate_hits_report.py）----------
#
# 【要解决的问题】19 道门禁里，**没有任何一处记录「它上次真的失败是什么时候」**。
#   于是「这道门重要」全靠记忆与感觉，而「这道门从没拦住过任何东西」这个事实
#   **完全不可见** —— 零命中与一直很稳，在现有输出里长得一模一样。
#   ⇒ 每道结果追加一行 JSONL，让「命中率」变成可查事实，而不是印象。
#
# 【落点与边界 · 必须如实知道】outputs/gate/hits.jsonl
#   · `yuesheng-flutter/.gitignore` 有 `outputs/` 规则 ⇒ 本文件**不在版本控制内**：
#     **本机累积、换机清零**。故任何报告都必须打印数据区间，不得当成全量历史。
#   · gate-fast.sh **写入同一份文件**（用 profile 字段区分），否则快道与收尾道的
#     命中率会分裂成两套互不可见的账。
#
# 【记录什么 / 不记录什么】
#   · 记：ts / run / profile / seq / name / result / dur_s / head / cov_flag
#     `dur_s` = 与**上一次 log_result** 的间隔 ⇒ 免去在 19 处门禁体内各插一次计时，
#     且天然就是「本道耗时」（首道除外，它含 python 探测等前置开销，报告中会标注）。
#     `cov_flag` = 本轮 wrapper **实际生效**的 COV_FLAG（见下方 P4b）。
#   · 本文件**不记** dirty：hits.jsonl 是**每道一行**，19 道各跑一次 `git status`
#     （本机实测 111 ms）合计约 2 s，而同一轮内这 19 个值**完全相同** ⇒ 重复 19 份，
#     零信息增量。这是「不值得在每道门禁上各测一次」，**不是**「脏度不值得记」。
#     ⚠️ 2026-10-25 修正（T-20261025-04 P5）：原注释只论证了**布尔**脏度「几乎恒为 1、
#     信息量近零」，并据此不记。但 P5 要的是**计数**（本轮有几个文件在飞）：
#     0 / 3 / 27 能区分「干净树上的失败」与「改到一半的树上的失败」，后者不可复现。
#     ⇒ 计数落在 `gate-run.sh` 的 **runs.jsonl（每轮一行）**，字段名 `dirty_count`。
#     **不许缩写成 `dirty`** —— 改名等于把「计数」偷偷降回「布尔」，这条修正就白做了。
#     `head` 仍用 `git rev-parse`（74 ms）保留，它能回答「这条 FAIL 对应哪个提交」。
#   · `seq` 从 1 起、按调用序递增；**不是**门禁编号（编号在 echo 里，不在这里重复）。
#
# 【失败策略】记录装置**永不影响门禁结论**：写失败一律 `|| true`。
#   记录坏了不该让门禁变红（那是假红），更不该让它变绿。
HITS_LOG="$OUT_DIR/hits.jsonl"
GATE_RUN_ID="$(date '+%Y%m%d-%H%M%S')-$$"
# profile 默认 full；经 gate-run.sh 调用时由 GATE_PROFILE_OVERRIDE 透传（quick / fast），
# 使 hits.jsonl 与 runs.jsonl **同一套标签**，否则两份流水的 profile 对不上、无法互相校验。
GATE_PROFILE="full"
[ -n "${GATE_PROFILE_OVERRIDE:-}" ] && GATE_PROFILE="$GATE_PROFILE_OVERRIDE"
GATE_SEQ=0
GATE_T_LAST=$(date +%s)
# P4a 的比对基准：**本轮起跑时刻**（秒级 epoch）。
# 直接复用 GATE_T_LAST 的初值，不再多起一次 `date`（本机 fork 约 75-90 ms）。
# 与 RUN_ID（`YYYYmmdd-HHMMSS`）同源同一秒或早一秒；P4a 用 `>=` 比较，
# 同秒相等不会假红（§4-295④）。GATE_T_LAST 后续会被 record_hit 改写，
# 所以这里必须**拷一份**，不能直接引用它。
GATE_RUN_START_TS="$GATE_T_LAST"
GATE_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

# ---------- 测试日志命名与保留策略（甲方案 · T-20261027-04 §7）----------
# 【为什么名字里必须带 run id】固定名 `test.txt` 全仓唯一 ⇒ 两轮必争同一文件：后一轮的
#   截断会把前一轮日志抹掉，出现「截断型混写」（前轮汇总行已写、后轮未写汇总行即被截断）
#   ⇒ 新老一致假绿。乙方案（bf8b7176）只把截断搬进锁内，名字仍唯一 ⇒ 下一轮仍会合法覆盖。
#   带 run id 才是根因消灭：两轮永不写同一文件。
# 【为什么定义放在这里】本文件 `set -u` 在生效，`$GATE_RUN_ID` 在上一段才算出来；
#   提前展开 = 引用未定义变量 = 当场 abort。
TEST_LOG="$OUT_DIR/test-$GATE_RUN_ID.txt"

# 【保留策略】按轮累积会无限增长（单份实测 ≈14 MB）⇒ 磁盘终态只留 PRUNE_KEEP 份（**含本轮**）。
#   ★ 为什么清掉的是 KEEP-1 份历史：本段**早于本轮文件创建**（文件由门禁 2 的 wrapper
#     在拿到锁之后才建），所以 `ls` 此刻只看得到历史文件。若按 KEEP 清历史，
#     磁盘终态会是 KEEP+1（7 份历史清到 5 份 + 本轮新建 1 份 = 6 份）
#     ⇒ 甲-3 判据「只剩 5 份（含本轮）」必红。
#     ⇒ 语义定死：`PRUNE_KEEP` = **磁盘终态份数（含本轮）**，启动时只保留 `PRUNE_KEEP-1` 份历史。
#   · 通配**只匹配 `test-2*-*.txt`**：同目录下有历史样本 `test_run_full.txt`（14.4 MB，
#     手工留档、不可再生）与 `test_v46.json` 等，写成 `test*` 会把它们一起删掉。
#   · 排除本轮自身：此刻文件还没创建，理论上不会命中；显式比对是防 GATE_RUN_ID 撞名。
#   · 本轮 abort（rc=75，另一轮持锁）时不会创建文件 ⇒ 磁盘终态是 `PRUNE_KEEP-1` 份，属预期。
#   · 失败不得让门禁失败（这是顺手维护，不是判据）⇒ 打一行 [WARN]，不空吞。
PRUNE_KEEP=5                                  # 磁盘终态份数（含本轮）
PRUNE_KEEP_HIST=$((PRUNE_KEEP - 1))           # 启动时保留的历史份数
PRUNE_OLD_LOGS="$(ls -1t "$OUT_DIR"/test-2*-*.txt 2>/dev/null | tail -n +$((PRUNE_KEEP_HIST + 1)) || true)"
while IFS= read -r _old_log; do
  [ -n "$_old_log" ] || continue
  [ "$_old_log" = "$TEST_LOG" ] && continue
  rm -f -- "$_old_log" || echo "  [WARN] 旧测试日志清理失败（不影响门禁结论）: $_old_log"
done <<< "$PRUNE_OLD_LOGS"

record_hit() {
  local name="$1"; local ok="$2"
  local now; now=$(date +%s)
  local dur=$((now - GATE_T_LAST)); GATE_T_LAST=$now
  local result
  case "$ok" in
    0)    result="PASS" ;;
    SKIP) result="SKIP" ;;
    *)    result="FAIL" ;;
  esac
  GATE_SEQ=$((GATE_SEQ + 1))
  # 门禁名实测只含中文/空格/括号/加号/斜杠，均无需转义；仅防御双引号与反斜杠。
  local esc=${name//\\/\\\\}; esc=${esc//\"/\\\"}
  # P4b：记录**本轮 wrapper 实际生效的 COV_FLAG**，不是 gate.sh 导出的环境变量。
  #   取值来源 = wrapper 写的 cov_flag.txt（`_ev_p4b_read` 用内建 read，零 fork；
  #   本函数每轮要跑 19 次，用 `$(…)` 会白送 19 个进程）。
  #   文件缺失 ⇒ `UNKNOWN`（**不是**空串、**不许**省略字段）：
  #     空串 = wrapper 跑了且明确没开覆盖率；UNKNOWN = 不知道跑没跑 / 哪版 wrapper。
  #     把这两态压成同一态，就又造了一个不可证伪的 PASS（P4b 要求 3）。
  #   ⚠️ 判据库读不到时不能直接调 `_ev_p4b_read`：`set -u` 下 `EV_P4B_VALUE` 未定义
  #     会**让 record_hit 当场退出**，进而把 log_result 的计数也带停（门禁自己先崩）。
  #      库不可用本来就会在门禁 2/6 报 FAIL，这里只需要别把记录装置变成新的故障点。
  local cov="UNKNOWN"
  if [ "$EV_LIB_OK" = "1" ]; then
    _ev_p4b_read "$COV_FLAG_FILE"
    cov="$EV_P4B_VALUE"
  fi
  cov="${cov//\\/\\\\}"; cov=${cov//\"/\\\"}
  printf '{"ts":"%s","run":"%s","profile":"%s","seq":%d,"name":"%s","result":"%s","dur_s":%d,"head":"%s","cov_flag":"%s"}\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$GATE_RUN_ID" "$GATE_PROFILE" "$GATE_SEQ" \
    "$esc" "$result" "$dur" "$GATE_HEAD" "$cov" >> "$HITS_LOG" 2>/dev/null || true
}

emit() { printf '%s\n' "$1"; }
# 记录一道门禁的结果。
#   ok=0    → PASS
#   ok=SKIP → SKIP（未真正执行）；不是 PASS，计入 degraded，使退出码非 0
#   其他    → FAIL
log_result() {
  local name="$1"; local ok="$2"
  if [ "$ok" = "0" ]; then
    emit "[PASS] $name"
    pass=$((pass + 1))
  elif [ "$ok" = "SKIP" ]; then
    emit "[SKIP] $name（未真正执行 → 计入 DEGRADED，退出码非 0）"
    degraded=$((degraded + 1))
  else
    emit "[FAIL] $name"
    fail=$((fail + 1))
  fi
  record_hit "$name" "$ok"
}

echo "=================================================="
echo "月笙 Flutter 十九道门禁 @ $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

# ---------- 公共：定位 python（门禁 3 / 5 / 6 共用）----------
# Windows 兼容：优先 python3，fallback python；两者都不可用时门禁 3 / 5 / 6 跳过。
PY_BIN=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  PY_BIN=python3
elif command -v python >/dev/null 2>&1 && python -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  PY_BIN=python
else
  echo "  [WARN] 未找到可用的 python3 / python —— 门禁 3（循环依赖）、门禁 5（R-019）与门禁 6（覆盖率）将跳过"
fi

# ---------- 门禁 0: 格式（宪法 §二.2）----------
echo "--> 门禁 0/19: 格式校验 (dart format lib test integration_test tool)"
if dart format --set-exit-if-changed -o none lib test integration_test tool > "$FORMAT_LOG" 2>&1; then
  RC_FORMAT=0
else
  RC_FORMAT=1
  tail -n 40 "$FORMAT_LOG"
fi
log_result "格式校验 (dart format)" "$RC_FORMAT"

# ---------- 门禁 1: 静态分析 ----------
# 2026-09-17 扩范围 lib → lib + integration_test + tool（实测 rc=0，零新增阻断）。
echo "--> 门禁 1/19: 静态分析 (dart analyze lib integration_test tool test)"
if dart analyze lib integration_test tool test > "$TYPECHECK_LOG" 2>&1; then
  RC_ANALYZE=0
else
  RC_ANALYZE=1
  tail -n 30 "$TYPECHECK_LOG"
fi
log_result "静态分析 (analyze lib+integration_test+tool+test)" "$RC_ANALYZE"

# ---------- 门禁 2: 测试 ----------
echo "--> 门禁 2/19: 单元测试 (flutter test)"
# V4.18：会话注入的 HTTP_PROXY 会劫持 Dart VM ↔ flutter_tester 的
# localhost WebSocket，导致全量测试加载失败（错误行同样带 [E]，
# 看起来每个测试都失败）。门禁脚本必须主动清空代理环境变量，
# 否则整道门禁在某些会话环境下会假红。
#
# V4.22（2026-09-04 批次 I 实证）：AI 沙箱会话缺 PROGRAMFILES(X86)，
# flutter.bat → update_engine_version.ps1 报错退出，表现
# 「%PROGRAMFILES(X86)% environment variable not found.」且被 `| tail`
# 吞掉退出码后**假绿**。注入兜底统一放在 _run_flutter_test.sh：
#   原值优先，仅缺时注入 Windows 标准值；其他环境完全不变。
if TEST_LOG_PATH="$TEST_LOG" bash scripts/_run_flutter_test.sh; then
  RC_TEST=0
else
  rc_ev=$?          # ★ 必须先取：`RC_TEST=1` 是赋值，会把 $? 冲成 0
  RC_TEST=1
  if [ "$rc_ev" = "75" ]; then
    # 75 = lock_abort（另一轮持锁）⇒ 本轮**没跑**测试，本轮的 test-<run>.txt **不存在**
    # （甲方案起日志名带 run id ⇒ 不会再把上一轮内容显示成本轮）。
    # 不截断任何日志：截断会摧毁正在持锁那一轮的日志 —— 那正是 T-20261027-04 要治的混写。
    echo "  [NOTE] 门禁 2 未执行：另一轮 flutter test 持锁（rc=75）⇒ 本轮无测试日志（不展示上一轮内容）"
  else
    tail -n 40 "$TEST_LOG"
  fi
fi

# ---------- 门禁 2 证据链（P1/P2/P3 · T-20261025-04）----------
# 【要解决的问题】本道的 PASS 在结构上不依赖任何例数证据 ⇒「跑 1 例通过」与
#   「跑 5295 例通过」在全部产物上完全同形 ⇒ **不可证伪**。这三条判据就是补证据。
#
# 【为什么只在 rc=0 时校验】证据是 PASS 的**必要条件**，不是 FAIL 的补充说明。
#   rc≠0 本身已经 FAIL，此时再叠 P1/P3 只会让归因更糊（红了两处，说不清是哪一处）。
#   ⇒ 「只破坏 P1 不动测试本身」时，唯一的红点就是 P1 —— 这正是单点归因的前提。
#
# 【为什么不新开道】三条判据讲的都是「本道的 PASS 有没有证据」，语义上就属于本道。
#   新开道要同步改 ~25 处「十九道」文案 + `.ai/STATE.md` 的道数 ⇒ 属另一批范围。
#
# 【判据实现在哪】scripts/lib_gate_evidence.sh。自测 scripts/_selftest_gate_evidence.py
#   直接调用**同一份**函数（44 条探针）—— 不是另写一份实现，所以测的就是上线的逻辑。
#
# 【归因判据】`grep -c '\[FAIL\] P1' <本轮 stdout>` = 1（另两条 = 0）。
#   所以每条判据的失败行**必须以 `[FAIL] P<n>` 开头**，格式变更会静默废掉归因。
#
# 【为什么只调一个入口】缓存是 shell 变量，逐条 `msg="$(ev_p<n> …)"` 会各起一个子 shell
#   ⇒ 缓存全废、14 MB 日志被扫 3 遍（实测 1632 ms vs 单遍）。`ev_check_p123` 先建缓存
#   再串起三条判据，全流程只读日志一次。
if [ "$RC_TEST" = "0" ]; then
  TEST_EVID_FAIL=0
  if [ "$EV_LIB_OK" = "1" ]; then
    EVID_OUT="$(ev_check_p123 "$TEST_LOG" "$ROOT/tool/test_count_baseline.json")"
    EVID_RC=$?
    # 【为什么把 P1/P2/P3 结论落盘】结论原先只进 stdout ⇒ outputs/gate/ 零承载、
    #   gate-report.md 零证据原文 ⇒ 读报告的人无法知道这条 PASS 是哪个 run 的；
    #   一旦代码被改坏，唯一正解是全量重跑（5~6 min），人不会重跑 ⇒ 默认采信。
    # 【为什么 stdout 形态一个字节都不许动】本道归因判据是 grep -c '[FAIL] P1' = 1
    #   （另两条 = 0），每行必须以 '[FAIL] P<n>' 开头；[run=…] 只许进文件，不许进 stdout。
    # 【为什么用 while + 内建 printf】逐行 sed/tee 会让 3 行输出各起子进程；双写零 fork，
    #   且 stdout 与 sed 's/^/  /' 逐字节等价（两个空格 + 原行 + 换行）。
    # 【这个文件会无限增长】append-only（每轮 3 行，量级可忽略），但别当可清空的临时文件。
    # 【空输出必须先判】set -u 在生效、无 set -e；here-string 对空串会喂一行空，
    #   不判空就会多打一行空行 + 多写一条空记录。
    if [ -n "$EVID_OUT" ]; then
      while IFS= read -r ev_line; do
        printf '  %s\n' "$ev_line"
        printf '[run=%s][rc=%s] %s\n' "$GATE_RUN_ID" "$EVID_RC" "$ev_line" >> "$OUT_DIR/evidence_p123.txt"
      done <<< "$EVID_OUT"
    fi
    [ "$EVID_RC" = "0" ] || TEST_EVID_FAIL=1
    # F2-C（T-20261027-03）：基线陈旧提醒（跨自然日 **且** head 与当前不同 ⇒ WARN，当日一次）。
    # ★ 为什么单独一段、不进 ev_check_p123：后者的输出行数被自测断言为**恰好 3 行**
    #   （S10/S12 探针），把提醒塞进去会让行数变 4 ⇒ 探针全红而判据没坏。
    # ★ 为什么这行不破坏本道的归因判据：归因只 grep `[FAIL] P1`（另两条计数为 0），
    #   而本行是 `[WARN] P2` 前缀、不含 `[FAIL]`。
    STALE_HINT="$(ev_p2_stale_hint "$ROOT/tool/test_count_baseline.json" 2>/dev/null || true)"
    if [ -n "$STALE_HINT" ]; then
      echo "  $STALE_HINT"
      printf '[run=%s] %s\n' "$GATE_RUN_ID" "$STALE_HINT" >> "$OUT_DIR/evidence_p123.txt"
    fi
  else
    echo "  [FAIL] 证据链判据库 scripts/lib_gate_evidence.sh 不可读 ⇒ 无法验证 PASS 的证据"
    TEST_EVID_FAIL=1
  fi
  if [ "$TEST_EVID_FAIL" != "0" ]; then
    RC_TEST=1
    echo "  [FAIL] 门禁 2 翻红：上方出现 [FAIL] P<n> ⇒ PASS 缺证据，按 FAIL 计"
    echo "         （归因看 [FAIL] P 前缀，不要靠 tail -n 40 猜）"
  fi
fi
log_result "单元测试 (flutter test)" "$RC_TEST"

# ---------- 门禁 3: 循环依赖（调用独立脚本 scripts/check_circular.py）----------
#
# ⚠️ 传参必须能被 Windows 原生 python 解析（2026-09-03 实证）：
#    旧写法传 "$ROOT"（Git Bash 的 `/d/ai-teacher/...`），python 侧拼出
#    `lib not found`，而 check_circular.py 当时 **return 0 静默放行**，
#    结果门禁 3 长期假绿、一次都没真正扫过。现两处都已修：
#    传 "."（gate.sh 已 cd 至 ROOT）+ 脚本侧 lib 缺失时失败关闭（退出码 2）。
#
# ⚠️ 修好后的第二层问题：建图时**裸相对导入**（`import 'x.dart';`）不进图，
#    而本项目有 177 条这样的边（占内部边 21.7%）——等于在缺了五分之一边的
#    图上做环检测。修复后暴露出 3 个真实存量环（Dart 允许循环 import，
#    故此前从未出过问题）。
#
# ✅ 2026-09-03 ADR-C70：3 个存量环已全部解开，**转为全量卡口**
#    （去掉 --baseline，任何环一律拦截）。这正是 V4.14 设定的终点——
#    豁免基线只是让门禁先落地的过渡手段，债务清零后就必须撤掉，
#    否则门禁会一直停留在「只卡新增」的弱化状态。
#    tool/circular_baseline.json 已重生成空数组并保留在库中，
#    供将来确需临时豁免时按同一格式使用（届时必须同时登记清偿计划）。
echo "--> 门禁 3/19: 循环依赖扫描 (lib import 图，全量卡口)"
if [ -n "$PY_BIN" ]; then
  if "$PY_BIN" scripts/check_circular.py . > "$CIRCULAR_LOG" 2>&1; then
    RC_CIRCULAR=0
  else
    RC_CIRCULAR=1
    cat "$CIRCULAR_LOG"
  fi
else
  echo "  [WARN] 未找到 python3 / python，跳过循环依赖扫描（建议本地装 Python 3.10+）"
  echo "SKIP: (NOT EXECUTED) python not available" > "$CIRCULAR_LOG"
  RC_CIRCULAR=SKIP
fi
# 统一在分支外记录：真正执行过记其退出码，跳过则记 SKIP（fail-closed，非 PASS）
log_result "循环依赖扫描" "$RC_CIRCULAR"

# ---------- 门禁 4: 安全 / 密钥（调用独立脚本 scripts/check_secrets.sh）----------
echo "--> 门禁 4/19: 安全/密钥扫描"
if bash scripts/check_secrets.sh "$ROOT" > "$SECURITY_LOG" 2>&1; then
  RC_SECRETS=0
else
  RC_SECRETS=1
  cat "$SECURITY_LOG"
fi
log_result "安全/密钥扫描" "$RC_SECRETS"

# ---------- 门禁 5: R-019 函数行数（止血模式：存量豁免，只卡新增）----------
#
# 背景：R-019 规定「函数 ≤ 50 行（硬上限）」，但此前四道门禁**没有一道检查它**，
# 债务已累积到 264 个（手写 237 个）却无人察觉。本门禁不追溯存量——
# 以 tool/r019_baseline.json 为基线，只阻止**新增**超限，避免一次性阻塞所有提交。
# 待债务按期清偿后，可去掉 --baseline 改为全量卡口。
echo "--> 门禁 5/19: R-019 函数行数（基线豁免，只卡新增）"
if [ -n "$PY_BIN" ] && [ -f "$ROOT/tool/r019_baseline.json" ]; then
  if "$PY_BIN" tool/check_r019.py --baseline tool/r019_baseline.json > "$R019_LOG" 2>&1; then
    RC_R019=0
  else
    RC_R019=1
    tail -n 30 "$R019_LOG"
  fi
else
  echo "  [WARN] python 不可用或基线缺失（tool/r019_baseline.json），跳过 R-019 扫描"
  echo "SKIP: (NOT EXECUTED)" > "$R019_LOG"
  RC_R019=SKIP
fi
# 统一在分支外记录：跳过记 SKIP（fail-closed，非 PASS）
log_result "R-019 函数行数" "$RC_R019"

# ---------- 门禁 6: 覆盖率（调用独立脚本 scripts/check_coverage.py）----------
#
# 背景（R-013 口径缺口）：门禁 0-5 中**没有**任何覆盖率检查——只有 CI
# （.github/workflows/flutter_ci.yaml:96-104）有。于是本地提交前发现不了
# 覆盖率跌破，只能等 CI 失败，反馈链路过长。本门禁把 CI 的口径原样搬回本地。
#
# ⚠️ 为什么覆盖率**不能**独立成门禁自己跑测试（2026-09 实证）：
#    - 复用仓库里陈旧的 coverage/lcov.info → **假绿**（查的是旧代码；
#      实测仓库内文件停在 2026-08-28，66.37% 已失真）；
#    - 若本门禁自行只跑个别测试文件 → 产出的 lcov 只含那几个文件，
#      整体行覆盖率仅 0.83%，T1 必然 FAIL → **假红**。
#    ⇒ 因此门禁 2 的测试包装器（_run_flutter_test.sh）已固定加 `--coverage`，
#      本门禁只**读取门禁 2 刚产出的新鲜 lcov**，二者构成一条流水线。
#      **顺序依赖**：门禁 6 必须在门禁 2 之后。
#
# ⚠️ lcov 缺失时记 FAIL 而非 SKIP（QA 审计 2026-09-12 裁定）：
#    前置守卫写 `[ -f lcov ]` 曾把脚本自身的 exit 2 保护**架空**——lcov 不在
#    就直接记 SKIP，而 SKIP 只是「不计入通过」，不会像 FAIL 那样把原因钉在
#    报告上。实测中 lcov 会被**并发运行的 flutter test --coverage** 抽走
#    （dart 每次跑完都要重写该文件），于是门禁 6 会在「其实该查」的情况下
#    常态 SKIP（qa 实测：2026-09-12 上午 lcov 两次消失又重生成）。
#    现在改为：门禁 2 通过而 lcov 仍缺失 ⇒ FAIL，并提示查并发。
#    仅当 python 不可用或门禁 2 本身没跑成功时才保留 SKIP。
#
# ⚠️ 传参必须与 CI 完全一致（对齐 flutter_ci.yaml:96-104），
#    否则本地与 CI 口径分叉，又会出现「本地绿、CI 红」的落差。
#    --expect-t2-count 5 是本地额外的**静默降级护栏**：CI 那条命令写死了
#    5 条 --t2，若将来有人删掉一条，剩下 4 条仍可能全 PASS → CI 假绿、
#    实际少守一个文件。加了这条护栏，数量不符一律 FAIL。
#    刻意**不传** --warn-event-file：那是 CI 的跨 run WARN 计数机制，本地无需。
#
# 退出码语义（check_coverage.py）：0 = T1 PASS/WARN 且 T2 全过；
#    1 = T1 FAIL 或任一 T2 FAIL/缺失 或 T2 数量不符护栏；
#    2 = 环境错误（lcov 缺失 / 解析 0 记录 / --t2 语法错）。
echo "--> 门禁 6/19: 覆盖率检查 (T1 整体 ≥65%，T2 五个核心文件各 ≥85%)"

# ---------- P4b：本轮实际生效的 COV_FLAG（T-20261025-04）----------
# 【判据】读 wrapper 写的 cov_flag.txt，**不读 gate.sh 自己导出的 env** ——
#   环境变量只说明「要求了什么」，文件才说明「wrapper 实际用了什么」。
# 【三态，不许压成两态】
#   `--coverage`  ⇒ PASS（与门禁 6 的前提一致）
#   `''`（空串）  ⇒ **FAIL**：wrapper 跑了、且明确没开覆盖率 ⇒ 本道无可信 lcov 可消费。
#                    这不是「没有输入」，是「有输入且输入说没有」。
#   `UNKNOWN`     ⇒ **WARN，不判 PASS 也不判 FAIL**：只说明读不到（旧版 wrapper / 被删），
#                    不说明覆盖率没开。按卡 §P4b 要求 3「首轮 WARN 过渡并明写」。
#                    ⚠️ WARN 不得计入「通过」——下面会明确打出它没有算作 PASS。
COV_FLAG_ACTUAL="UNKNOWN"
COV_FLAG_KNOWN=0
if [ "$EV_LIB_OK" = "1" ]; then
  _ev_p4b_read "$COV_FLAG_FILE"
  COV_FLAG_ACTUAL="$EV_P4B_VALUE"
  [ "$EV_P4B_MISSING" = "0" ] && COV_FLAG_KNOWN=1
fi
if [ "$COV_FLAG_KNOWN" = "0" ]; then
  echo "  [WARN] P4b 实际 COV_FLAG：UNKNOWN（$COV_FLAG_FILE 不存在）⇒ 不知道本轮 wrapper 跑没跑 / 哪一版"
  echo "         ⇒ 本条**未计入通过**：它只说明读不到，不说明覆盖率开了。首轮按 WARN 过渡。"
elif [ "$COV_FLAG_ACTUAL" = "--coverage" ]; then
  echo "  [PASS] P4b 实际 COV_FLAG：--coverage（覆盖率开启，与门禁 6 前提一致）"
else
  echo "  [FAIL] P4b 实际 COV_FLAG：'$COV_FLAG_ACTUAL'（空串 = 本轮明确未开覆盖率）⇒ 本道无可信 lcov 可消费"
fi

if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过覆盖率检查"
  echo "SKIP: (NOT EXECUTED) python not available" > "$COVERAGE_LOG"
  RC_COVERAGE=SKIP
elif [ "${RC_TEST:-1}" != "0" ]; then
  # 门禁 2 没通过 ⇒ lcov 可能只写了一半甚至没写，覆盖率无从判定。
  # 此时不该报 FAIL（会把「测试挂了」误报成「覆盖率挂了」），记 SKIP。
  echo "  [WARN] 门禁 2 未通过，未产出可信 lcov，跳过覆盖率检查"
  echo "SKIP: (NOT EXECUTED) gate 2 did not pass" > "$COVERAGE_LOG"
  RC_COVERAGE=SKIP
elif [ "$COV_FLAG_KNOWN" = "1" ] && [ "$COV_FLAG_ACTUAL" != "--coverage" ]; then
  # 覆盖率**明确没开** ⇒ 后面即便有 lcov 也是上一轮/别人的，不能拿它判覆盖率。
  # 必须先于 `-f lcov` 判：否则报出来的是「lcov 不存在」，把真实原因
  # （wrapper 被 RUN_FLUTTER_TEST_COVERAGE=0 关掉了）藏在一句误导性的话后面。
  echo "  [FAIL] 门禁 6 前提不成立：本轮 COV_FLAG='$COV_FLAG_ACTUAL'，wrapper 没开覆盖率"
  echo "         查是不是有人导出了 RUN_FLUTTER_TEST_COVERAGE=0（快道会，收尾道不许）"
  echo "FAIL: coverage disabled for this run (COV_FLAG='$COV_FLAG_ACTUAL')" > "$COVERAGE_LOG"
  RC_COVERAGE=1
elif [ ! -f "$ROOT/coverage/lcov.info" ]; then
  # V4.28（QA 实测 2026-09-12）：门禁 2 跑成功却没留下 lcov —— 最常见的
  # 原因是**另一个会话正在并发跑 flutter test --coverage**，dart 收尾时
  # 会重写/删除 coverage/ 目录。这不是「无法检查」，是「本该检查却没东西
  # 可查」，按 fail-closed 记 FAIL，逼出真实原因而不是静默放行。
  echo "  [FAIL] 门禁 2 已通过但 coverage/lcov.info 不存在 —— 疑似并发 flutter test --coverage 将其抽走"
  echo "FAIL: lcov missing although gate 2 passed (concurrent flutter test --coverage?)" > "$COVERAGE_LOG"
  RC_COVERAGE=1
elif [ "$EV_LIB_OK" != "1" ]; then
  echo "  [FAIL] P4a 无法校验：判据库 scripts/lib_gate_evidence.sh 不可读（fail-closed）"
  echo "FAIL: evidence lib unreadable, cannot verify lcov freshness" > "$COVERAGE_LOG"
  RC_COVERAGE=1
elif ! P4A_MSG="$(ev_p4a_fresh "$ROOT/coverage/lcov.info" "$GATE_RUN_START_TS")"; then
  # P4a：lcov 的 mtime 必须 >= 本轮起跑时刻。
  #   **必须排在上面的 `-f` 分支之后**：文件不存在时 `stat` 会往 stderr 喷错，
  #   那行错会被读成「环境故障」，而真实原因是上一行已经说清的「lcov 不存在」。
  echo "  $P4A_MSG"
  echo "FAIL: lcov stale (mtime < run_start $GATE_RUN_START_TS)" > "$COVERAGE_LOG"
  RC_COVERAGE=1
else
  echo "  $P4A_MSG"
  if "$PY_BIN" scripts/check_coverage.py \
    --lcov coverage/lcov.info \
    --t1-target 65.0 --t1-margin 2.0 \
    --t2 "lib/services/training_evaluator.dart:85" \
    --t2 "lib/services/evaluation_service.dart:85" \
    --t2 "lib/data/repositories/diagnosis_repository.dart:85" \
    --t2 "lib/services/chat_service.dart:85" \
    --t2 "lib/services/focus_resolver.dart:85" \
    --expect-t2-count 5 > "$COVERAGE_LOG" 2>&1; then
    RC_COVERAGE=0
  else
    RC_COVERAGE=1
    cat "$COVERAGE_LOG"
  fi
fi
log_result "覆盖率检查" "$RC_COVERAGE"

# ---------- 门禁 7: Prompt 反模式（调用 scripts/check_prompt_antipattern.py）----------
#
# 背景（ADR-C92）：该脚本早已写好、能跑，却**从未接入任何门禁**——它真正能拦到
# 的 prompt 话术反模式（强制触发 / 固定格式 / 断言式下结论）被静默放过。
#
# ⚠️ 接入前必须先修假阳性（2026-09-12 实测）：修复前 12 条命中里 11 条是假阳性
#    （92%）——`report-tone` 把月笙**核心协议字段「诊断置信度」**错当报告腔，
#    `assert-conclude` 把 `❌` 标注的反例说明当断言，`cross-dup` 把**有意的
#    跨文件教学规则一致性**当重复缺陷。带着这些假阳性接门禁，结果是「正常改
#    prompt 就假红」→ 门禁被当噪音绕过。现已修复，并**不能反过来改 prompt 去
#    迎合检查器**（违反 R-009/R-010）。
#
# ⚠️ 用 --diff-baseline 而非全量：存量 1 条真阳性（force-trigger）走基线祖父，
#    只卡**新增**，与门禁 5/6 的先例一致（门禁 5 止血基线 / 门禁 6 T2 守卫）。
#    cross-dup 已降级为信息型，不参与 FAIL 判定。
#
# ⚠️ --expect-rule-count 4 是**静默降级护栏**（类比门禁 6 的 --expect-t2-count）：
#    若将来有人删掉一条 KEYWORD_RULES，剩余规则仍可能全 PASS → 假绿、
#    实际少守一类反模式。加了这条护栏，规则数不符一律 FAIL。
#
# 退出码语义（check_prompt_antipattern.py）：0 = 无新增（diff 模式）；
#    1 = 有新增命中 / 规则数不符护栏。
echo "--> 门禁 7/19: Prompt 反模式（diff-baseline，只卡新增）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 prompt 反模式扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$PROMPT_LINT_LOG"
  RC_PROMPT=SKIP
elif [ ! -d "$ROOT/lib/services" ]; then
  # 扫描目录不存在 ⇒ 脚本会 return 1（被误当「有反模式」），故在 wrapper 先判，
  # 记 SKIP（环境缺失）而非 FAIL，避免把「找不到目录」误报成「有反模式」。
  echo "  [WARN] lib/services 不存在，跳过 prompt 反模式扫描"
  echo "SKIP: (NOT EXECUTED) lib/services missing" > "$PROMPT_LINT_LOG"
  RC_PROMPT=SKIP
else
  if "$PY_BIN" scripts/check_prompt_antipattern.py \
    --diff-baseline --expect-rule-count 4 > "$PROMPT_LINT_LOG" 2>&1; then
    RC_PROMPT=0
  else
    RC_PROMPT=1
    cat "$PROMPT_LINT_LOG"
  fi
fi
log_result "Prompt 反模式" "$RC_PROMPT"

# ---------- 门禁 8: 内容元数据（调用 scripts/check_content_metadata.py）----------
#
# 背景（ADR-C92）：同为「已写未接入」脚本。检查内容增减规范要求的元数据头
# （体积/定位/来源/loadWhen）是否齐备。内置存量豁免，只卡新增头缺失。
#
# ⚠️ 必须用 --strict：非 strict 模式下有 finding 也是 rc=0（advisory），
#    接为门禁会恒绿、零价值。--strict 才有「有 finding → 1」的阻断语义。
echo "--> 门禁 8/19: 内容元数据（--strict，只卡新增缺失）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过内容元数据检查"
  echo "SKIP: (NOT EXECUTED) python not available" > "$META_LOG"
  RC_META=SKIP
else
  if "$PY_BIN" scripts/check_content_metadata.py --strict > "$META_LOG" 2>&1; then
    RC_META=0
  else
    RC_META=1
    cat "$META_LOG"
  fi
fi
log_result "内容元数据" "$RC_META"

# ---------- 门禁 9: 交互回归（调用 scripts/check_interaction_regression.py）----------
#
# 背景（ADR-C92）：拦截会导致**运行时崩溃**的交互/导航缺陷（P0 级）。
# 仅 P0 命中才 FAIL；P1 候选只报告不阻断（避免误报海啸淹没门禁）。
#
# ⚠️ 空 lib 扫描会假绿（2026-09-12 规格验证）：若 lib 下无 .dart 文件，
#    脚本会 rc=0「什么都没扫到」——这不是「通过」，是「没检查」。故 wrapper
#    先判 lib 下有 .dart，否则记 SKIP（fail-closed，绝不记 PASS）。
echo "--> 门禁 9/19: 交互回归（仅 P0 阻断，P1 报告）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过交互回归扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$INTERACTION_LOG"
  RC_INTERACTION=SKIP
elif ! ls "$ROOT"/lib/**/*.dart >/dev/null 2>&1 && ! find "$ROOT/lib" -name '*.dart' -print -quit 2>/dev/null | grep -q .; then
  echo "  [WARN] lib 下未找到 .dart 文件，跳过交互回归扫描（空扫会假绿）"
  echo "SKIP: (NOT EXECUTED) no .dart under lib" > "$INTERACTION_LOG"
  RC_INTERACTION=SKIP
else
  if "$PY_BIN" scripts/check_interaction_regression.py > "$INTERACTION_LOG" 2>&1; then
    RC_INTERACTION=0
  else
    RC_INTERACTION=1
    cat "$INTERACTION_LOG"
  fi
fi
log_result "交互回归" "$RC_INTERACTION"

# ---------- 门禁 10: 伪拆分形态（调用 scripts/check_split_shape.py）----------
#
# 背景（舰长质询 2026-09-12 / docs/audits/pseudo-split-legacy-inventory-2026-09-12.md）：
# **R-019 的「文件 ≤300 行」与「禁止 part/extension 伪拆分」两条从来没有机器
# 执行点**——tool/check_r019.py 只统计**函数**行数（limit=50），基线里没有
# 任何文件行数字段。⇒ 伪拆分是**唯一一种七道门禁全绿也无法察觉**的劣化形态。
# 本门禁补上这个执行点。
#
# 判据（三条，实测 S1=3 / S2=5 / S3=4）：
#   S1 宿主>300 且家族内有 part>300 ⇒ 伪拆分（宿主没变小，还多造一个超限文件）
#   S2 宿主>300（含「拆了没拆动」形态）
#   S3 家族内任一 part>300
#   A 类豁免（R-019:57-60）：skills_*.dart / skill_registry.dart /
#     *_knowledge_base.dart / {syndrome,technique,training}_kb_content*.dart
#     —— 纯常量知识库，part 与内容领域边界一致，不触发伪拆分审查。
#
# ⚠️ 基线止血模式（同门禁 5）：存量 12 条违规走基线祖父，只卡**新增**。
#    否则本门禁一上线就红灯、阻塞所有提交，会被当噪音绕过。
#    基线一旦生成不会自动变严 ⇒ **每清偿一条必须重生成基线**：
#      python scripts/check_split_shape.py --json tool/split_shape_baseline.json
#    **重生成时绝不能带 --baseline**（脚本已内置防护：同传 → exit 2）。
#
# 退出码语义（check_split_shape.py）：0 = 通过/无新增；1 = 有违规/新增；
#    2 = 环境错误（lib 缺失 / 0 个 dart / --json 与 --baseline 同传）。
echo "--> 门禁 10/19: 伪拆分形态（基线豁免，只卡新增）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过伪拆分扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$SPLIT_LOG"
  RC_SPLIT=SKIP
elif [ ! -f "$ROOT/tool/split_shape_baseline.json" ]; then
  echo "  [WARN] 伪拆分基线缺失（tool/split_shape_baseline.json），跳过"
  echo "SKIP: (NOT EXECUTED) baseline missing" > "$SPLIT_LOG"
  RC_SPLIT=SKIP
else
  if "$PY_BIN" scripts/check_split_shape.py \
    --baseline tool/split_shape_baseline.json \
    --expect-rule-count 3 > "$SPLIT_LOG" 2>&1; then
    RC_SPLIT=0
  else
    RC_SPLIT=1
    cat "$SPLIT_LOG"
  fi
fi
log_result "伪拆分形态" "$RC_SPLIT"

# ---------- 门禁 11: A 类豁免准入守卫（调用 scripts/check_a_class_exemption.py）----------
#
# 背景（2026-09-12 侦察，docs/recon-reports/RECON-P3-knowledge-relief-2026-09-12.md）：
# 门禁 10 的 A 类豁免是**纯按文件名**（`_A_CLASS_PATTERNS`）的——它豁免「A 类纯常量
# 知识库」，却**从不校验文件内容是否真的满足豁免前提**。⇒ 豁免是 fail-open 的，
# 存在一条完全绕过门禁 10 的路径（代码直读）：
#     建 `foo.dart` 声明 `part 'skills_data.dart';`，`skills_data.dart` 装 800 行逻辑
#     ⇒ 宿主行数没超（S1/S2 不报），分片 basename 命中豁免（S3 不报）。
# 本门禁把 R-019:57-60 的豁免**前提**变成可执行判据。
#
# 判据（四条，每条锚定 R-019 一处前提）：
#   A1  **分片**不得声明 class/extension/mixin（前提②「纯常量」）
#   A2  **任何 A 类文件**不得含 @override（前提③「无 override 契约」）
#   A3  **分片**顶层函数须逐名登记在基线内（前提②「无逻辑耦合」）
#   A4  **任何 A 类文件**必须是 part 家族成员（守住豁免适用范围，防命名滥用）
#   ⚠️ 宿主不做 A1/A3 断言：宿主按设计保留「检索/渲染逻辑」（批次 96-26/96-27），
#      对其施加「无函数」会与既定分离设计冲突（越权改规则）。宿主仍受 A2/A4 约束。
#
# ⚠️ 基线止血模式（同门禁 5/10）：存量漂移 2 个分片 / 5 个函数（Phase 3 阶段裁剪
#    入口）走基线 `allowedFunctions` **透明登记**，只卡**新增**。
#    基线一旦生成不会自动变严 ⇒ **每清偿一条必须重生成基线**：
#       python scripts/check_a_class_exemption.py --json tool/a_class_exemption_baseline.json
#    **重生成时绝不能带 --baseline**（脚本已内置防护：同传 → exit 2）。
#    另：分片数由 `minPartCount` 守（G1）——把分片改名移出豁免集会触发 FAIL。
#
# 退出码语义（check_a_class_exemption.py）：0 = 通过/无新增；1 = 有违规/新增/守卫失败；
#    2 = 环境错误（lib 缺失 / 0 个 dart / 0 个豁免文件 / 真源缺失或载入失败 /
#    基线结构非法 / --json 与 --baseline 同传）。
echo "--> 门禁 11/19: A 类豁免准入守卫（基线豁免，只卡新增）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 A 类豁免准入扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$A_CLASS_LOG"
  RC_ACLASS=SKIP
elif [ ! -f "$ROOT/tool/a_class_exemption_baseline.json" ]; then
  echo "  [WARN] A 类豁免基线缺失（tool/a_class_exemption_baseline.json），跳过"
  echo "SKIP: (NOT EXECUTED) baseline missing" > "$A_CLASS_LOG"
  RC_ACLASS=SKIP
elif [ ! -f "$ROOT/scripts/check_split_shape.py" ]; then
  # 豁免模式真源缺失 ⇒ 脚本 exit 2（fail-closed）。在 wrapper 先判并记 SKIP，
  # 避免把「环境缺失」与「真有违规」混为一谈（但仍计入 degraded → 退出码非 0）。
  echo "  [WARN] 豁免模式真源缺失（scripts/check_split_shape.py），跳过"
  echo "SKIP: (NOT EXECUTED) exemption source missing" > "$A_CLASS_LOG"
  RC_ACLASS=SKIP
else
  if "$PY_BIN" scripts/check_a_class_exemption.py \
    --baseline tool/a_class_exemption_baseline.json \
    --expect-rule-count 4 > "$A_CLASS_LOG" 2>&1; then
    RC_ACLASS=0
  else
    RC_ACLASS=1
    cat "$A_CLASS_LOG"
  fi
fi
log_result "A 类豁免准入" "$RC_ACLASS"

# ---------- 门禁 12: Skill 公共库链接（ADR-C115）----------
echo "--> 门禁 12/19: Skill 公共库链接校验 (scripts/check_skills_links.py)"
if [ -n "$PY_BIN" ]; then
  if "$PY_BIN" scripts/check_skills_links.py . > "$SKILLS_LINKS_LOG" 2>&1; then
    RC_SKILLS_LINKS=0
  else
    RC_SKILLS_LINKS=1
    cat "$SKILLS_LINKS_LOG"
  fi
else
  echo "  [WARN] 未找到 python3 / python，跳过 Skill 公共库链接校验"
  echo "SKIP: (NOT EXECUTED) python not available" > "$SKILLS_LINKS_LOG"
  RC_SKILLS_LINKS=SKIP
fi
log_result "Skill 公共库链接" "$RC_SKILLS_LINKS"

# ---------- 门禁 13: extension 单块行数（ADR-0004 §2 R-2）----------
# 背景（2026-10-07 对抗性审查 P1-3 + ADR-0004）：本仓红线「减行数不得用
# part / extension」此前**零机器执行点** —— 门禁 10 只对已声明 part 的家族
# 求值、门禁 11 只对文件名匹配 A 类 pattern 的文件求值，而
# lib/services/chat_service.dart 两者都不属于 => 两条门禁都看不见它，
# 而它恰是全仓最大问题块（extension ChatServiceSend 实测 1193 行）。
# 判据：E1 = 任一顶格 extension 块行数 > 300 => 违规（阈值与 R-019 文件级
#   上限同值：extension 是同文件的第二层分块，可读单元心智成本相同）。
# 基线止血（同门禁 5/10/11）：存量 1 条超限走 tool/extension_shape_baseline.json
#   透明登记，只卡**新增**。★ 按**块名 + 宿主路径**登记，**不按行号** ——
#   行数会漂：同一块实测曾出现 1173 / 1172 / 1193 三个值。
#   ★ 生命周期终点：由「拆 ChatServiceSend 为独立类 + DI」的那一批关闭，
#   该批须同批删豁免、把 E1 升为全量卡口并做负向验证。
# 退出码：0 通过 / 1 有新增或失效豁免 / 2 环境或基线非法。
#   ⚠️ rc=2 一律判 FAIL 不当 SKIP —— 空扫等于没检查（守卫内建 G1）。
echo "--> 门禁 13/19: extension 单块行数（基线豁免，只卡新增；ADR-0004 R-2）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 extension 分块扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$EXT_SHAPE_LOG"
  RC_EXTENSION_SHAPE=SKIP
elif [ ! -f "$ROOT/tool/extension_shape_baseline.json" ]; then
  echo "SKIP: (NOT EXECUTED) baseline missing" > "$EXT_SHAPE_LOG"
  RC_EXTENSION_SHAPE=SKIP
else
  # ★ ADR-0004 §4 步 5 批 4：E1 由「基线豁免、只卡新增」**升为全量卡口**
  #   —— 不再传 --baseline（脚本无该参数时 exemptions={}，over 全算违规）。
  #   前置：ChatServiceSend 已拆至 292 行 < 300 阈值，豁免登记随之作废。
  if "$PY_BIN" scripts/check_extension_shape.py > "$EXT_SHAPE_LOG" 2>&1; then
    RC_EXTENSION_SHAPE=0
  else
    RC_EXTENSION_SHAPE=1
    cat "$EXT_SHAPE_LOG"
  fi
fi
log_result "extension 单块行数" "$RC_EXTENSION_SHAPE"

# ---------- 门禁 14: flag 契约同步（scripts/check_flag_contract.py）----------
# 背景（2026-10-07 P0 事故 7d245a75）：该提交把 kBlockEditorEnabled 由 false 翻为
# true，提交信息自述「+ 同步测试契约」，实际只同步了 block_readonly_view_test.dart、
# **漏了 writing_page_test.dart** ⇒ 收尾门禁 54 例红，且事故当时零台账登记。
# 根因不是「忘了」，而是「自述已同步 ≠ 已同步」**没有机器执行点**。
# 判据（守卫内建）：G1 空扫 fail-closed / G2 登记完整性 / G3 值变更时受影响测试
#   必须**同批**改动。基线 tool/flag_contract_baseline.json。
# 退出码：0 通过 / 1 有未同步或登记缺失 / 2 环境不可判定（rc=2 判 FAIL 不当 SKIP）。
echo "--> 门禁 14/19: flag 变更须同步测试契约（ADR-0002 事故 7d245a75 遗留）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3/ python，跳过 flag 契约扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$FLAG_CONTRACT_LOG"
  RC_FLAG_CONTRACT=SKIP
elif [ ! -f "$ROOT/tool/flag_contract_baseline.json" ]; then
  echo "  [WARN] flag 基线缺失（tool/flag_contract_baseline.json），跳过"
  echo "SKIP: (NOT EXECUTED) baseline missing" > "$FLAG_CONTRACT_LOG"
  RC_FLAG_CONTRACT=SKIP
else
  if "$PY_BIN" scripts/check_flag_contract.py > "$FLAG_CONTRACT_LOG" 2>&1; then
    RC_FLAG_CONTRACT=0
  else
    RC_FLAG_CONTRACT=1
    cat "$FLAG_CONTRACT_LOG"
  fi
fi
log_result "flag 契约同步" "$RC_FLAG_CONTRACT"

# ---------- 门禁 15: ADR 悬空引用 ----------
# 背景：.ai/adr/ 的编号↔实体对应关系此前**只靠人记**，无机器执行点。实测
# ADR-0001 被 .ai 文档引 9 处（代码侧零引用）而 .ai/adr/ 下无 0001 实体文件。
# 判据：G1 空扫 fail-closed / G2 悬空引用须补实体或**显式登记豁免**（EXEMPT 表
#   只认裸 4 位数字键）/ G3 索引陈旧提醒（排除已豁免）。
# ⚠️ 跨仓判据：它读仓库根的 .ai/ 与 yuesheng-flutter/（本仓是 monorepo 子目录，
#   git 仓库根是 D:/ai-teacher 而非 yuesheng-flutter/）—— 路径错配会静默零扫描，
#   故守卫内建 G1 空扫 fail-closed。
echo "--> 门禁 15/19: ADR 悬空引用（编号↔实体必须有实文件）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 ADR 悬空扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$ADR_DANGLING_LOG"
  RC_ADR_DANGLING=SKIP
elif [ ! -d "$ROOT/../.ai/adr" ]; then
  echo "  [WARN] 未找到 ADR 目录（$ROOT/../.ai/adr），跳过"
  echo "SKIP: (NOT EXECUTED) adr dir missing" > "$ADR_DANGLING_LOG"
  RC_ADR_DANGLING=SKIP
else
  if "$PY_BIN" scripts/check_adr_dangling.py > "$ADR_DANGLING_LOG" 2>&1; then
    RC_ADR_DANGLING=0
  else
    RC_ADR_DANGLING=1
    cat "$ADR_DANGLING_LOG"
  fi
fi
log_result "ADR 悬空引用" "$RC_ADR_DANGLING"

# ---------- 门禁 16: git hook 副本同步 ----------
# 背景（2026-10-07 实踩）：scripts/git-hooks/pre-commit 是**源文件**（受版本控制），
# 而 git 实际执行的是 <git-dir>/hooks/pre-commit（**安装副本**，不受版本控制）。
# 二者只靠手工跑 install-git-hooks.ps1 同步 —— 改了源文件提交后**不生效**，而
# 一切检查都绿（源文件本身没问题）⇒ 静默失效。
# 判据：git rev-parse --absolute-git-dir 取生效目录 → 比 md5；不一致报红并给出
#   修复命令。副本未安装判 SKIP/0（首次 clone 常见，非漂移）。
echo "--> 门禁 16/19: hook 副本↔源文件同步（防改了不生效）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 hook 同步扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$HOOK_SYNC_LOG"
  RC_HOOK_SYNC=SKIP
else
  if "$PY_BIN" scripts/check_hook_sync.py > "$HOOK_SYNC_LOG" 2>&1; then
    RC_HOOK_SYNC=0
  else
    RC_HOOK_SYNC=1
    cat "$HOOK_SYNC_LOG"
  fi
fi
log_result "hook 副本同步" "$RC_HOOK_SYNC"

# ---------- 门禁 17: 台账新鲜度（防「复述即漂移」） ----------
# 背景（2026-10-07 实测）：`.ai/STATE.md` 一天内查出 **9 处失真**，形态一致 ——
#   「用过期快照或窄口径当现状」。四类根因：① 台账表头写「当前值」却锁死在
#   2026-09-19 的读数；② 「收尾道十二道」实为十八道；③ 「三条守卫未接入门禁」
#   而它们已接入为 14/15/16；④ 「未给生产防御」而防御已补。
#   ⇒ 门禁道数 / 测试例数 / 行数这类**会漂的数值**，登记处是**手写**的 ⇒必然漂。
# 判据：F1 gate.sh 运行时标签的**分母必须唯一**（混用即口径漂移）；编号连续 0..N-1；
#      F2 台账声明的「N 道」须与 gate.sh 实测一致；
#      F3 近 24h 新增的 lib 文件须在 `.ai/` 有登记（防「代码做了台账没记」）。
#   ★ 门禁 17 自身也遵守：不硬编码 17，真实道数从标签集合实测取。
echo "--> 门禁 17/19: 台账新鲜度（防复述即漂移）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过台账新鲜度扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$LEDGER_FRESH_LOG"
  RC_LEDGER_FRESH=SKIP
else
  if "$PY_BIN" scripts/check_ledger_freshness.py > "$LEDGER_FRESH_LOG" 2>&1; then
    RC_LEDGER_FRESH=0
  else
    RC_LEDGER_FRESH=1
    cat "$LEDGER_FRESH_LOG"
  fi
fi
log_result "台账新鲜度" "$RC_LEDGER_FRESH"

# ---------- 门禁 18: prompt 体积红线（tool/check_prompt_volume.py）----------
# 背景（2026-10-12 D1 实测批）：ADR-0003 §5 判据 9「diagnosis 组体积不得回涨」
# 的执行体，但长期**不在门禁里** ⇒ 18/18 全绿的门禁从未跑过它；甲-1 之后
# 7 个改 prompt 的批次重冻锚点、无一回跑，存量越线 +572 无人发现
# （根因：纪律「重冻后立刻回跑」只写在脚本头注，无机器执行点）。
# 判据：受控组 diagnosis 两组不超 REDLINE（贴实测、不留余量）+ 对照组零增长。
# 退出码：0 通过 / 1 超红线或有增长 / 2 环境不可判定（按守卫惯例 rc≠0 即 FAIL）。
# ⚠️ 覆盖缺口（已在 D1 报告登记）：本脚本量的是**锚定 system prompt**；
#    运行时 system 消息注入通道（message_injector.dart F07 因果上下文 / 后续
#    D2 结构画像）不经 skill dispatcher ⇒ 不在计量面内，其增量须在触该通道的
#    批次单独实测报批，不得以「红线没超」代替。
echo "--> 门禁 18/19: prompt 体积红线（ADR-0003 判据 9；D1 实证此前无执行点）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 prompt 体积检查"
  echo "SKIP: (NOT EXECUTED) python not available" > "$PROMPT_VOLUME_LOG"
  RC_PROMPT_VOLUME=SKIP
elif [ ! -f "$ROOT/test/snapshots/skill_prompt_anchor.json" ]; then
  echo "  [WARN] 锚点快照缺失（先跑 UPDATE_SNAPSHOTS=true flutter test test/services/skill_prompt_anchor_test.dart），跳过"
  echo "SKIP: (NOT EXECUTED) anchor snapshot missing" > "$PROMPT_VOLUME_LOG"
  RC_PROMPT_VOLUME=SKIP
else
  if "$PY_BIN" tool/check_prompt_volume.py > "$PROMPT_VOLUME_LOG" 2>&1; then
    RC_PROMPT_VOLUME=0
  else
    RC_PROMPT_VOLUME=1
    cat "$PROMPT_VOLUME_LOG"
  fi
fi
log_result "prompt 体积红线" "$RC_PROMPT_VOLUME"

# ---------- 约定层守卫（WARN 级 · 不计道数 · 不阻断）: DB 列活性 ----------
# 背景（2026-10-18 T-20261018-01 全链路活性审查）：确证 6 死列——既有护栏
#   全部验证「代码跑起来做什么」，没有护栏验证「生产有没有真的走到它」。
#   coverage ≠ liveness。本守卫只报**新增**死列（基线豁免 tool/wiring_baseline.json，
#   逐条带精核 reason）；负向验证已做（注入假列必报红 + 字节级恢复）。
# 定性：**约定层守卫，非门禁**（与 check_extension_shape.py 首接形态同款）。
#   报红 ⇒ 当场处置（补读侧或登记豁免），不阻断收尾；升阻断须用户裁定。
echo "--> 约定层守卫: DB 列活性（只报新增死列；WARN 级，2026-10-18 审查批起接）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3/ python，跳过 DB 列活性守卫"
  echo "SKIP: (NOT EXECUTED) python not available" > "$WIRING_LOG"
elif [ ! -f "$ROOT/tool/wiring_baseline.json" ]; then
  echo "  [WARN] 基线缺失（tool/wiring_baseline.json），跳过"
  echo "SKIP: (NOT EXECUTED) baseline missing" > "$WIRING_LOG"
else
  if "$PY_BIN" scripts/check_wiring.py --baseline tool/wiring_baseline.json > "$WIRING_LOG" 2>&1; then
    echo "  [PASS] DB 列活性（无新增死列）"
  else
    # WARN 级：打印但不置 RC_ 变量、不进 pass/fail 计数
    echo "  [WARN] 新增死列/基线异常——当场处置（补读侧或登记豁免），详见 $WIRING_LOG"
    cat "$WIRING_LOG"
  fi
fi

# ---------- 约定层守卫：诊断链字段三级贯通（S1 · 2026-10-21 起接）----------
# 定性：**约定层守卫，非门禁**（与 check_wiring.py 同款）。
#   报红 ⇒ 当场处置（补读侧或登记带到期日的豁免），不阻断收尾；升阻断须用户裁定。
# ★ 判据对象（2026-10-21 修正至 v4，此前经四次实测推翻）：
#   L1 产出（真源 prompt schema，**自动派生**不硬编码）
#     → L2 诊断卡 payload（卡片 DTO 类）
#     → L3 呈现面**有效读点**（X.field 形态，宿主非 payload/this ⇒ 排除「搬运即露出」）
#   字段族**从真源派生** ⇒ 真源加字段守卫自动多判一行 ⇒ 清单不会腐化。
# ★ 为什么是「链」：用户看不见一个字段，断在 L2（没上卡）与断在 L3（上了卡没渲染）
#   **责任卡不同、补救方式不同** ⇒ 必须报出断在哪一级。
# ★ 与 check_wiring / S4 的分工：wiring 判「有人消费吗」· S4 判「真源有没有出口」
#   · S1 判「造出来的东西用户在诊断卡上看得见吗」⇒ 三道互补，都不可互相替代。
#   同一字段可同时「活」（被评分端消费）与「死」（UI 零引用）⇒ 三道必须都跑。
echo "--> 约定层守卫: 诊断链字段三级贯通（S1，WARN 级，2026-10-21 起接）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3/ python，跳过可见性守卫"
  echo "SKIP: (NOT EXECUTED) python not available" > "$SURFACE_LOG"
elif [ ! -f "$ROOT/tool/surface_baseline.json" ]; then
  echo "  [WARN] 基线缺失（tool/surface_baseline.json），跳过"
  echo "SKIP: (NOT EXECUTED) baseline missing" > "$SURFACE_LOG"
else
  if "$PY_BIN" scripts/check_surface_visibility.py --baseline tool/surface_baseline.json > "$SURFACE_LOG" 2>&1; then
    echo "  [PASS] 诊断链字段三级贯通（在阈值内或豁免期内）"
  else
    # WARN 级：打印但不置 RC_ 变量、不进 pass/fail 计数
    echo "  [WARN] 诊断链字段断链（没上卡 / 上了卡没渲染）或豁免到期——当场处置，详见 $SURFACE_LOG"
    cat "$SURFACE_LOG"
  fi
  # ★ 自测探针同批跑：证明本守卫**非恒绿**（恒绿 = 静音 = 守卫头号死法）。
  #   6 探针覆盖「真源加字段 / DTO 加字段 / 呈现面接上 / 渲染被禁字段 / 豁免到期 / 复原」。
  if [ -f "$ROOT/scripts/_selftest_surface_visibility.py" ]; then
    if "$PY_BIN" scripts/_selftest_surface_visibility.py > "$SURFACE_SELFTEST_LOG" 2>&1; then
      # ★★ 前缀是 [INFO] 而不是 [PASS]（2026-10-30 T-20261025-16，与 :1111 证据链自测同处理）：
      #   本层是 WARN 级守卫、不计入门禁道数；[PASS] 的既定含义是「判定通过并计入 tally」。
      #   断言只保留可观测的一件事：rc=0。旧版那行声称「非恒绿非恒红」——实测自测层被
      #   强制绿（m1）或删掉探针（m2）时它一字不变 ⇒ 把结论写进输出 = 在没有证据处盖章。
      echo "  [INFO] S1 守卫自测 rc=0（守卫对 6 类输入有反应；自测层是否可静默不在本行证明范围）"
    else
      echo "  [WARN] S1 守卫负向验证失败——守卫可能已恒绿或恒红，详见 $SURFACE_SELFTEST_LOG"
      cat "$SURFACE_SELFTEST_LOG"
    fi
  fi
fi

# ---------- 约定层守卫：真源 → 出口对账（S4 · 2026-10-21 起接）----------
# 定性：**约定层守卫，非门禁**（与 S1 同级）。
# ★ 为什么要单独一道（2026-10-21 实测逼出来的）：
#   S1 的 MAKER_SOURCES 是**硬编码 9 个文件** ⇒ 第 10 个真源出现时它天然看不见。
#   实测：training_kb_content_1..4 + training_few_shot_library 共 **1279 代码行**
#   从未进入 S1 视野 ⇒ **守卫的判据集合本身静默腐化，且腐化时零输出**。
#   S4 判据对象是**关系**（真源是否至少有一条出口通向 prompt 或产品面），
#   且真源**自动发现** ⇒ 新增真源未登记即报红（防清单腐化）。
#   分工：S1 量「判据语言词频」· S4 验「真源→出口关系」。两道都要跑。
echo "--> 约定层守卫: 真源→出口对账（S4，WARN 级，2026-10-21 起接）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3/ python，跳过真源出口守卫"
  echo "SKIP: (NOT EXECUTED) python not available" > "$SOURCE_EXIT_LOG"
elif [ ! -f "$ROOT/tool/source_exit_baseline.json" ]; then
  echo "  [WARN] 基线缺失（tool/source_exit_baseline.json），跳过"
  echo "SKIP: (NOT EXECUTED) baseline missing" > "$SOURCE_EXIT_LOG"
else
  if "$PY_BIN" scripts/check_source_exit.py --baseline tool/source_exit_baseline.json > "$SOURCE_EXIT_LOG" 2>&1; then
    echo "  [PASS] 真源→出口关系自洽（全部登记在册）"
  else
    echo "  [WARN] 真源出口断裂 / 新真源未登记 / 基线腐烂——当场处置，详见 $SOURCE_EXIT_LOG"
    cat "$SOURCE_EXIT_LOG"
  fi
fi

# ---------- 约定层守卫：证据链判据自测（S5 · 2026-10-25 起接，WARN 级）----------
#
# 【为什么必须挂进来】`_selftest_gate_evidence.py` 在第 1–4 笔期间只能**手工跑**。
#   「有自测」与「自测会在交付前自动跑」是两件事 —— 不挂载的探针等于零覆盖，
#   而它测的是「35 条负向探针 + 清单自断言是否仍全部符合预期」。判据坏掉时门禁照样全绿，
#   所以这层自测一旦静默，整套证据链就退回「不可证伪」。
#   ⚠️ 边界（别把这句读大）：元探针 S7/S8 **只覆盖 P1**，P2–P5 与自测层自身都没有元探针。
#
# 【为什么是 WARN 不是 FAIL】它是**元判据**：测的是判据本身，不是产品。
#   让它阻断收尾，会让「自测脚本自己的 bug」挡住产品交付 —— 与 S1/S4 同级处理。
#   但**必须喊出来且必须进报告**（见报告「详细日志」段）：静默的 WARN 等于没跑。
#
# 【为什么不挂快道（gate-fast.sh）】**不是漏了，是决定**：快道是 pre-commit 用的，
#   预算约 17 s；这套探针要起 30+ 次 bash 子进程（本机单次 fork 约 75-90 ms），
#   会显著拖长 every-commit 的等待。快道本来也不跑门禁 6（P4a/P4b 的另一半），
#   挂一半的自测比不挂更容易被误读成「已经覆盖了」。**别顺手补全。**
#
# 【归因】WARN 行以 `[WARN]` 开头且带脚本路径，与门禁的 `[FAIL] P<n>` 不同前缀
#   ⇒ 不会污染门禁 2 的单点归因判据（`grep -c '\[FAIL\] P1'`）。
echo "--> 约定层守卫: 证据链判据自测（S5，WARN 级，2026-10-25 起接）"
SELFTEST_EVID_VERDICT="SKIP"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过证据链判据自测"
  echo "SKIP: (NOT EXECUTED) python not available" > "$SELFTEST_EVID_LOG"
elif [ ! -f "$ROOT/scripts/_selftest_gate_evidence.py" ]; then
  echo "  [WARN] 自测脚本缺失（scripts/_selftest_gate_evidence.py），跳过"
  echo "SKIP: (NOT EXECUTED) selftest script missing" > "$SELFTEST_EVID_LOG"
else
  if "$PY_BIN" scripts/_selftest_gate_evidence.py > "$SELFTEST_EVID_LOG" 2>&1; then
    SELFTEST_EVID_VERDICT="PASS"          # ← 变量不动：`:1121` 汇总行读它，表达的是 rc 判定
    # ★★ 前缀是 `[INFO]` 而不是 `[PASS]`（2026-10-25 改判，主理人裁定 + 独立复核机器侧核查）：
    #   ① `[PASS]` 在全套判据里的既定含义是「**该道判据判定通过并计入 tally**」
    #      （见本文件 `:252` 的 `emit "[PASS] $name"`）。而本层**不计入十九道、也不阻断**。
    #      两个语义共用一个前缀 —— 这**就是**「措辞过度断言」的生成机制：
    #      不是这次写错，是那个前缀一直在邀请人这么写。
    #   ② 机器侧核查：全仓没有任何脚本用 `grep` 统计 `[PASS]` 行；
    #      `SELFTEST_EVID_VERDICT` 只有 `:1037` 赋值、`:1121` 读取 ⇒ 改前缀零连带风险。
    # ★ 断言只保留**可观测**的一件事：rc=0。不陈述「判据已通过元探针验证」那种结论。
    #   依据：变异审计 m10/m17 实测——自测层被强制绿、或某条探针被删掉时，
    #   上一版那行输出**一字不变**。把结论写进输出，就是在没有证据的地方盖了章。
    echo "  [INFO] 证据链判据自测 rc=0（元探针 S7/S8 仅覆盖 P1，不构成「非恒绿」证明）"
    # ★ 覆盖面边界必须自己说出来（别指望读者去翻脚本）：
    echo "         覆盖面边界：S7/S8 元探针**只覆盖 P1**（ev_p1_summary），能抓的是「P1 单点恒绿 /"
    echo "         单点恒红」；P2/P3/P4a/P4b/P5 **没有**对应元探针。"
    echo "         自测层自身的兜底是脚本内 _probe_can_report_failure() 哨兵（probe() 恒真 ⇒ rc=1）；"
    echo "         残余风险由此降级为「**必须同时改坏 probe() 与哨兵**才会静默」，见脚本头部 R2。"
  else
    SELFTEST_EVID_VERDICT="WARN"
    # 各类失败分开喊，因为它们的处置完全不同（不得共用同一个输出位置）：
    echo "  [WARN] 证据链判据自测失败——详见 $SELFTEST_EVID_LOG"
    echo "         可能是：① 某条判据退化（恒绿/恒红/归因错）② 清单自断言不通过（有人"
    echo "         增删探针但没同笔改 EXPECTED_PROBE_*）③ 脚本自身报错"
    echo "         ④ 哨兵报警（probe() 已不能报告失败 ⇒ 本次「全绿」无意义）。"
    echo "         四种都不许当「测试挂了」略过：除 ③ 外都意味着判据层已不可信。"
    tail -n 20 "$SELFTEST_EVID_LOG"
  fi
fi

# ---------- 汇总报告 ----------
#
# 判定一律以**退出码**为准（2026-09-03 实证）：旧版对循环依赖用
# `grep -q 'OK:'` 判定，而脚本在 lib 找不到时打印的是 `SKIP:`，
# 于是同一份日志里「汇总 6 通过 / 0 失败」却显示「循环依赖 FAIL」——
# 报告自相矛盾，且掩盖了门禁其实没跑的事实。
# 口诀：**报告里的一切判定都要回到退出码，别二次解读日志文本。**
verdict() {
  case "$1" in
    0) printf 'PASS' ;;
    SKIP) printf 'SKIP' ;;
    *) printf 'FAIL' ;;
  esac
}

# 顶部 DEGRADED 横幅：任一 SKIP 门禁都必须在报告最显眼处点名，
# 防止「跳过」被埋在表格里、而汇总行仍写着「全绿」。
DEGRADED_BANNER=""
if [ "$degraded" -gt 0 ]; then
  DEGRADED_BANNER="> ⚠️ **DEGRADED: ${degraded} 门未真正执行**（见下表 SKIP 项）——\
报告**不可**视为全绿；请补齐环境后重跑。

"
fi

cat > "$REPORT" <<EOF
# 十九道门禁报告

${DEGRADED_BANNER}- 时间: $(date '+%Y-%m-%d %H:%M:%S')
- 项目: yuesheng-flutter

| 门禁 | 结果 |
|------|------|
| 格式校验 (dart format) | $(verdict "${RC_FORMAT:-SKIP}") |
| 静态分析 (analyze lib+integration_test+tool+test) | $(verdict "${RC_ANALYZE:-SKIP}") |
| 单元测试 (flutter test) | $(verdict "${RC_TEST:-SKIP}") |
| 循环依赖扫描 | $(verdict "${RC_CIRCULAR:-SKIP}") |
| 安全/密钥扫描 | $(verdict "${RC_SECRETS:-SKIP}") |
| R-019 函数行数（只卡新增） | $(verdict "${RC_R019:-SKIP}") |
| 覆盖率检查 | $(verdict "${RC_COVERAGE:-SKIP}") |
| Prompt 反模式（只卡新增） | $(verdict "${RC_PROMPT:-SKIP}") |
| 内容元数据（--strict） | $(verdict "${RC_META:-SKIP}") |
| 交互回归（仅 P0） | $(verdict "${RC_INTERACTION:-SKIP}") |
| 伪拆分形态（只卡新增） | $(verdict "${RC_SPLIT:-SKIP}") |
| A 类豁免准入（只卡新增） | $(verdict "${RC_ACLASS:-SKIP}") |
| Skill 公共库链接 | $(verdict "${RC_SKILLS_LINKS:-SKIP}") |
| extension 单块行数（只卡新增） | $(verdict "${RC_EXTENSION_SHAPE:-SKIP}") |
| flag 契约同步 | $(verdict "${RC_FLAG_CONTRACT:-SKIP}") |
| ADR 悬空引用 | $(verdict "${RC_ADR_DANGLING:-SKIP}") |
| hook 副本同步 | $(verdict "${RC_HOOK_SYNC:-SKIP}") |
| 台账新鲜度 | $(verdict "${RC_LEDGER_FRESH:-SKIP}") |
| Prompt 体积红线（ADR-0003 判据 9） | $(verdict "${RC_PROMPT_VOLUME:-SKIP}") |

汇总: ${pass} 通过 / ${fail} 失败 / ${degraded} 未执行（SKIP）

## 详细日志
- 格式: outputs/gate/format.txt
- 静态分析: outputs/gate/typecheck.txt
- 测试: outputs/gate/test-$GATE_RUN_ID.txt
- 循环依赖: outputs/gate/circular.txt
- 安全扫描: outputs/gate/security.txt
- R-019 函数行数: outputs/gate/r019.txt
- 覆盖率: outputs/gate/coverage.txt
- Prompt 反模式: outputs/gate/prompt_lint.txt
- 内容元数据: outputs/gate/content_metadata.txt
- 交互回归: outputs/gate/interaction.txt
- 伪拆分形态: outputs/gate/split_shape.txt
- A 类豁免准入: outputs/gate/a_class_exemption.txt
- Skill 公共库链接: outputs/gate/skills_links.txt
- extension 单块行数: outputs/gate/extension_shape.txt
- flag 契约同步: outputs/gate/flag_contract.txt
- ADR 悬空引用: outputs/gate/adr_dangling.txt
- hook 副本同步: outputs/gate/hook_sync.txt
- 台账新鲜度: outputs/gate/ledger_freshness.txt
- Prompt 体积红线: outputs/gate/prompt_volume.txt
- 约定层守卫·DB 列活性（WARN 级，不计道数）: outputs/gate/wiring.txt
- 约定层守卫·证据链判据自测（WARN 级，不计道数）: outputs/gate/selftest_gate_evidence.txt — 结果: ${SELFTEST_EVID_VERDICT}
EOF

echo "=================================================="
if [ "$degraded" -gt 0 ]; then
  echo "⚠️  DEGRADED: ${degraded} 门未真正执行（SKIP）——不计入通过"
fi
echo "汇总: $pass 通过 / $fail 失败 / $degraded 未执行"
echo "报告: $REPORT"
echo "=================================================="

# fail-closed：任一 FAIL 或任一 SKIP（未真正执行）都使退出码非 0。
# 「全绿」= fail==0 且 degraded==0，此时才确信十九道都真的跑过。
[ "$fail" -eq 0 ] && [ "$degraded" -eq 0 ]
