---
name: gate2-case-set-fingerprint-discipline
description: 门禁 2「例集指纹」翻红后的判因与处置纪律。test('…') 的描述字符串是哈希输入，改一个字就红，而净数完全不变；因此文字级订正一律写进 reason: 或文档注释（都不进指纹），测试名保持原串，必要时用 git revert 撤回改名而不是重钉基线。当用户说「门禁 2 红了」「P2 例集指纹不一致」「净数没变为什么说例集变了」「用例改名」「重钉 test_count_baseline」「UPDATE_TEST_BASELINE」时使用；给出红行读数的含义、三档处置（撤回改名 / 核对增删后重钉 / 删 A 补 B 必须逐条说明）与「+N=基线；例集指纹一致」的验收读数。锚点重冻见 prompt-const-anchor-refreeze，红驱动落点见 negative-verify-red-driver-placement，收尾台账见 yuesheng-ledger-closeout，本 skill 只管例集指纹。
---

# 门禁 2 例集指纹纪律

## 适用边界

- 工作目录 `D:/ai-teacher`；活跃真源只有 `yuesheng-flutter/`。
- 本 skill 只管一件事：**门禁 2 的例集指纹（P2 F1）为什么变、变了之后该怎么处置**。
- 分工：注入 prompt 常量的字节锚 ⇒ skill `prompt-const-anchor-refreeze`；
  「改坏必红」的红驱动是否落在被测条件上 ⇒ skill `negative-verify-red-driver-placement`；
  台账四件与双仓提交 ⇒ skill `yuesheng-ledger-closeout`；
  日志完整性 / 树一致性 / 读数是否对应当前树 ⇒ skill `gate-run-evidence-integrity`。
- **不复述会漂的数字**（基线值、指纹值、例数）。现读并带读取时刻。
  本文 §本仓实测锚 里的数字是**带日期的历史读数**，不是当前值，别抄进新台账。
- 结论分级：从脚本或日志**跑出来的**是指 E1；从实现代码**推出**的行为标 E2，不得当 E1 回传。

## 核心规则

**`test()` 的描述字符串是指纹的输入，不是注释。**

想订正一条用例的措辞时，把它写进 `reason:` 或函数上方的文档注释，**不要动 `test('…')` 里的名字**。

真源（现读，勿背）：

```bash
cd /d/ai-teacher/yuesheng-flutter
sed -n '155,166p' scripts/lib_gate_evidence.sh    # _ev_suite_fingerprint
sed -n '125,142p' scripts/lib_gate_evidence.sh    # _ev_write_baseline（唯一写盘入口）
cat tool/test_count_baseline.json                 # 基线当前值
```

指纹输入 = `--file-reporter json` 报告里每个 `testStart` 事件的 `name`（= 组描述 + 空格 + 用例描述），
剔掉 `loading ` 前缀，`LC_ALL=C sort -u` 排序去重，取 `sha256` **前 16 位**。
`reason:` 和文档注释都不进 `name` ⇒ **不进指纹**（E1：提取式只取 `name`）。

三条由实现直接决定的性质（E2，代码推导）：

- **改名 = 改例集**：描述里加一个字，指纹必变。
- **顺序无关**：同一文件内调整用例先后不改指纹（先排序再哈希）。
- **重名会折叠**：两条同名用例在 `sort -u` 下算一条 ⇒ `suite_size` 不增而日志 `+N` 增。
  这两个数差着是正常的（口径不同），但**「+N 涨了、suite_size 没涨」要能说清是哪条**。

## 两套口径，别互相推

| 口径 | 来源 | 含义 |
|:--|:--|:--|
| `count`（日志里的 `+N`） | `flutter test` 文本日志汇总行 | 跑完的**事件数** |
| `suite_size` + `suite_fingerprint` | json 报告 `testStart` 去重名 | **哪些**用例、各一条 |

基线 `tool/test_count_baseline.json` 同时存这两套，**它们可以不相等**
（口径不同：完成事件数 vs 去重用例名数）。⇒ 不要拿它们互校，更不要因为「对不上」就去动基线。
**净数不能单独作为「例集未变」的证据** —— 这正是 F1 这道判据存在的理由（删 A 补 B 时净数可以完全不变）。

## 第 1 步 · 把红行读成一句话，不要看半句

三条判据（P1/P2/P3）每轮都**逐行落盘**到 `outputs/gate/evidence_p123.txt`（append-only，
每轮 3 行，带 run 号与 rc）—— 这是判因的首选，比翻 14 MB 的测试日志快且无歧义：

```bash
tail -9 outputs/gate/evidence_p123.txt
```

红行原样长这样（真源 `ev_p2_count`；stdout 会加两空格缩进，`[run=…][rc=…]` 只进证据文件）：

```
[FAIL] P2 例集：指纹 <new> ≠ 基线 <old> ⇒ 例集变了（删 A 补 B / 改名 / 删例）；净数 +N=<n> 不作数
```

绿行长这样（`；例集指纹 <size> 例一致` 是 F1 通过的标志）：

```
[PASS] P2 例数下限：+N=<n> = 基线 <n>；例集指纹 <size> 例一致
```

**净数超过基线不是红**，只是提示：

```
[WARN] P2 例数下限：+N=<n> > 基线 <base>（Δ=+<d>）⇒ 用例增长，提示刷新基线；例集指纹 <size> 例一致
```

**判定顺序是固定的**（`ev_p2_count` 从上到下）：`UPDATE` 分支 → 例集指纹 → 净数下降 → 净数增长 → 相等。
⇒ 指纹不一致会**先**判红，根本走不到净数比较；反过来「净数涨了」永远不会红，只会 WARN。
所以别拿 WARN 那行当「例集没变」的证据，也别指望用净数变化去解释指纹红。

**两种「未判」不是绿**，必须当红处理去查原因：

```
；例集指纹未判（无 json 报告 ⇒ 归因 json 臂）
；例集指纹未判（基线无 suite_fingerprint ⇒ 下次 UPDATE 时写入，本轮 F1 未生效）
```

基线陈旧另有独立一行 `[WARN] P2 基线陈旧…`（每日只提醒一次，跨自然日 **且** head 变了才报），
它是建议、不是失败 —— **别拿它当重钉的理由**，也别把它和 F1 混成一条。

## 第 2 步 · 用名单级证据判因（不用重跑测试）

门禁每轮都在 `outputs/gate/` 落一份同名 `.json` 报告，指纹差异可以直接从两份报告算出来：

```bash
cd /d/ai-teacher/yuesheng-flutter
python "<本 skill 目录>/scripts/case_set_drift.py" \
  --old outputs/gate/test-<上一轮>.json \
  --new outputs/gate/test-<本轮>.json
```

脚本复刻同一套提取与哈希（已实测与 bash 逐位一致），输出：

- `OLD/NEW size=… fp=…`、`SET removed=N added=N size_delta=…`
- `VERDICT=LIKELY-RENAME` ⇒ 增删条数相等且逐条高度相似 ⇒ **第 3 步走 A**
- `VERDICT=REAL-CHANGE` ⇒ **第 3 步走 B**
- `DETAIL=<临时文件>` ⇒ 中文用例名写在这个 UTF-8 文件里（stdout 保持纯 ASCII，
  防 cp936 控制台花屏，见 skill `windows-bash-io-traps`）

再对基线核一次当前状态：

```bash
python "<本 skill 目录>/scripts/case_set_drift.py" \
  --report outputs/gate/test-<最新>.json --baseline tool/test_count_baseline.json
```

## 第 3 步 · 三档处置

**A. 文字级订正（改名）** ⇒ **撤回改名，不重钉基线。**
为一个描述精度付一次基线重钉不划算：重钉等于把这道纪律门自己松开。
做法是把名字改回原串（或 `git revert <sha>` 单文件撤回），订正留在 `reason:` / 文档注释。

**B. 本批真的新增/删除用例** ⇒ 先核对再重钉。
核对项：`净增例数 == 本批新增用例数`、被删的每条都有理由（不许静默删例）。
重钉只有唯一入口，且**必须在全绿轮次**：

```bash
UPDATE_TEST_BASELINE=1 bash scripts/gate.sh   # 日志会出 [WARN] P2 …基线已刷新 <old> → <new>（含例集指纹 …）
```

随后**不带该变量复跑一轮**确认 `[PASS] …例集指纹 … 一致`。台账里登记 `old → new` 指纹变化。

**C. 删 A 补 B（净数不变）** ⇒ 必须逐条指名「删了哪条、补了哪条、为什么等价」，
写进报批稿/台账；**禁止**用「+N 和基线一样」来论证例集没变。

## 第 4 步 · 验收读数（A 档的收尾）

改回名字后跑**全量**门禁（不是 pre-commit 快道），要读到：

- 门禁 2：`[PASS] P2 例数下限：+N=<n> = 基线 <n>；例集指纹 <size> 例一致`；
- 日志里**没有**「基线已刷新」的 WARN（有 ⇒ 你其实重钉了，第 3 步 A 没成立）；
- `GATE_RC=0` 且 `outputs/gate/gate-report.md` 全通过。

**连带副作用（E2 · 别处记录，当轮产物已被后续跑覆盖，不可本地复核）**：
本仓台账（skill `resumed-work-forensic-review` 的 `references/handoff-verdict-table.md`）记着
同一类 P2 判红轮里覆盖率道降为 SKIP、报告标 DEGRADED、汇总「通过/失败/未执行」不再是全绿。
⇒ **别背那个数**：撤回改名后按当轮 `outputs/gate/gate-report.md` 与 `evidence_p123.txt` 现读，
只要报告不是全通过，就还没收尾。

## 禁止事项

1. **手编 `tool/test_count_baseline.json`** —— 缺 `reason` / `head` 的基线由来源校验直接 FAIL；
   且「删了基线再首建」会永久自洽，这条链已被授权闸（`EV_ALLOW_WRITE_BASELINE`）堵死，别绕。
2. 为文字修饰重钉基线（等于自己把门松开）。
3. 只跑单道就宣布恢复 —— F1 要全绿轮次才作数。
4. 拿 `count` 与 `suite_size` 互相校验（两套口径，见上表）。

## 本仓实测锚（2026-10-29，E1）

`outputs/gate/evidence_p123.txt` 里相邻三轮（原文照录）：

```
[run=20261029-163021-2009][rc=0] [PASS] P2 例数下限：+N=5365 = 基线 5365；例集指纹 5354 例一致
[run=20261029-164603-874][rc=1] [FAIL] P2 例集：指纹 7ee12847a3e78d2b ≠ 基线 c2a7de74fdd45dcd ⇒ 例集变了（删 A 补 B / 改名 / 删例）；净数 +N=5365 不作数
[run=20261029-165200-1317][rc=0] [PASS] P2 例数下限：+N=5365 = 基线 5365；例集指纹 5354 例一致
```

同一天两轮的 json 报告，**用例名集合大小都是 5354、只差一行**：

| 轮次（`outputs/gate/`） | size | fp | 那一条用例名 |
|:--|:--|:--|:--|
| `test-20261029-164603-874.json` | 5354 | `7ee12847a3e78d2b` | `… 边界：库中无 messages 表 → v49 块跳过，升级不抛错` |
| `test-20261029-165200-1317.json` | 5354 | `c2a7de74fdd45dcd` | `… 边界：极老库无 messages 表 → v49 块跳过，升级不抛错` |

⇒ 净数完全不变、只改一个描述串，照样判「例集变了」。
撤回提交 `21b9b0b8`（`revert(test)`）把名字改回原串，语义订正移到 `createNoMessagesDbFile` 的文档注释；
基线 `c2a7de74fdd45dcd` **没有被动过**。逐条复算命令即上面第 2 步那条。

## Resources

- `scripts/case_set_drift.py` —— 只读、无副作用；`--old/--new`（两份 json 报告）
  或 `--report/--baseline`（一份报告对基线）。stdout 纯 ASCII，中文名单写 `DETAIL=` 指到的 UTF-8 文件。
  退出码：0 = 一致 / 无漂移；1 = 漂移、基线无指纹或使用错误（`ERROR:` + `VERDICT=UNAVAILABLE`）。
