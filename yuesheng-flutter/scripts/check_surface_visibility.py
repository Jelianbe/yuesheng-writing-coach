#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_surface_visibility.py — S1 ·「造出来的东西，用户看得见吗」守卫（v4）。

★ v4 修正（2026-10-21）：判据对象第四次迭代 —— 链路按**运行时真实数据流**重建
--------------------------------------------------------------------
**v1 判据对象**：「造物主侧行数 ↔ 产品面判据语言命中数」的比值。
⇒ **实测推翻**：17 个造物主侧真源**全部是 `role: 'system'` 给模型看的**
（技法库头注「系统注入，**学员不可见**」`technique_knowledge_base.dart:43`；
few-shot 头注「让 **LLM** …」`training_few_shot_library.dart:8-11`；
训练库头注「为 **AI** 提供…」`training_kb_content_1.dart:8-10`），
且 17/17 **全部有 prompt 出口、全部无 product 出口**（`check_source_exit.py --list` 实测）
⇒ 分子分母**不同质** ⇒ 该比值恒为 0 且**应当**为 0 ⇒ v1 会在豁免到期后**误报**。

**v2a 判据对象**：「用户侧真源 ↔ 产品面」。
⇒ **实测推翻**：17 个真源**全是模型侧**；用户可见文案（`whyLabel` / `evidenceLabel` …）
是 **widget 里的常量**（`diagnosis_card.dart:83-99`），**不在 services 真源层**
⇒ **当前架构里不存在「用户侧真源」这个实体** ⇒ v2a 退化成**空守卫**（0 真源可判）。

**v2 判据对象**：「诊断链字段族 ↔ 产品面是否消费」+ **硬编码 9 字段清单**。
⇒ **实测推翻三点**：
  ① **清单式判据**（硬编码 9 字段）⇒ 新增同类字段天然落在视野外而守卫继续报绿
     ⇒ 违反「凡清单式判据必须有清单外对象检出机制」（已实测踩坑两次）。
  ② **把「DTO 里没有」与「DTO 有但没渲染」混为一谈**：形态两字段
     （`form_fact_count` / `form_structure`）**不在任何 DTO 类**里
     ⇒ 它们断在**落库→DTO** 这一段，不是「DTO 有但用户看不到」。
  ③ **「落库」判据错位**：诊断链多数字段**不占独立表列**，而是经
     `Syndrome.toJson()`（`teaching_types.dart:225-241`）序列化成 snake_case 键，
     整体塞进 `diagnosis_results.syndromes` 一列（`diagnosis_repository.dart:178`
     `jsonEncode(filteredSyndromes)`）⇒ **只看表列会把 8/10 字段误判成「没落库」**
     （v3 初版实测踩中）。

**v3 判据对象**：「四级贯通链 L1 产出 → L2 落库 → L3 DTO → L4 产品面」。
⇒ **实测推翻一点（关键）**：
  **卡片回看读的不是 `diagnosis_results` 表，而是 `messages` 表里那份
  `jsonEncode(payload.toJson())`**（`message_card_service.dart:347-352`
  `messageType: 'diagnosis_result'`）⇒ **诊断卡 payload 本身就是存档件**。
  ⇒ 「落库」这一级对「用户看得见吗」这个问题**不是判据对象**（判它只会引出
  「历史诊断卡在 DB 里能不能回放」这种与本题无关的分支）；
  真正决定用户看不看得见的是：**产出 → 进卡片 payload → 呈现面真读点**。

⇒ **v4 终版：判据对象 = 「诊断链字段的**三级贯通链**」，字段族**从真源自动派生**。**

三级链（每一级都是运行时真实数据流上的一环）
----------------------------------------------
| 级 | 名称 | 权威来源 | 查法 |
|:--|:--|:--|:--|
| **L1** | 产出 | `lib/services/progressive_diagnosis.dart` | prompt 输出格式声明行 `- xxx (type):` |
| **L2** | 卡片 payload | `lib/services/message_card_service.dart` | DTO 类 `final T xxx;`（含 `toJson` 键） |
| **L3** | 呈现面 | 引用了 DTO 的 widget 文件 | **有效读点**（见下） |

★ **L3 为什么要「有效读点」而不是「grep 到字段名就算」**：
`diagnosis_card.dart` 里 `final double confidence;` / `confidence: payload.confidence`
只是**把值搬进 widget 字段**，不等于**渲染出来** ⇒ 裸 grep 会把「搬运」误判成
「用户看得见」⇒ **恒绿 = 静音**（本守卫的头号死法）。
判据改为：字段名必须作为**「某对象的属性读取」**出现（即 `X.field` 形式），
且**排除** `payload.field` / `this.field` 这类纯搬运形态 ⇒ 只有真正取值去用才算。

★ **为什么字段族从真源派生**：硬编码清单 = 清单腐化 = 恒绿 = 静音（已实测踩坑两次）。
本脚本的 L1 字段集**直接由真源 prompt 的格式声明行解析而来** ⇒ 真源加了字段，
守卫**自动**多判一行 ⇒ 无需改脚本 ⇒ 清单不会腐化。

★ **呈现面文件怎么定**：不硬编码文件名，而是**反向查**——凡产品面里引用了
DTO 类名（`DiagnosisSyndromeCard` / `DiagnosisResultCardPayload` / `OverallDiagnosis`）
的文件即呈现面 ⇒ 换了 widget 文件名不会漏判，也不会误扫无关文件。

判据（五条）
---------
- **S1-1 贯通性**：诊断链字段须走完 L1→L2→L3。**断在哪一级就报在哪一级**。
- **S1-2 清单外对象检出**：DTO 里出现但 L1 真源未声明的字段 ⇒ 报红
  （防止「绕过诊断链直接塞进 DTO」的字段悄悄进来；新字段须先进真源 schema）。
- **S1-3 基线登记字段消失**：基线登记过的字段若从真源产出清单消失 ⇒ 报红（基线腐烂）。
- **S1-4 豁免到期**：基线豁免带到期日 ⇒ 到期未修则**恢复报红**（避免永久豁免=永久静音）。
- **S1-5 豁免内容自洽**：豁免点名的字段必须**确实**处于断链状态 ⇒ 否则报红
  （防止豁免名存实亡而守卫继续绿）。

用法
----
    python scripts/check_surface_visibility.py --baseline tool/surface_baseline.json
    python scripts/check_surface_visibility.py --list             # 只列逐级读数
    python scripts/check_surface_visibility.py --json            # 机器可读

退出码
------
    0 = 通过（或全部断点都在基线豁免期内）
    1 = 有断链 / 清单外对象 / 基线腐烂 / 豁免到期 / 豁免失实
    2 = 环境错误（文件缺失 / 基线结构非法）

⚠️ 与既有基线同源纪律：**拿来「检查」是对的，拿来「重生成」就是自杀。**
"""
from __future__ import annotations

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

REPO = Path(__file__).resolve().parent.parent

# ── 三级链的权威来源 ──
# ★ L1 产出真源有**两个**（实测）：`skills_l1_core_p2.dart` 是主诊断 prompt 的
#   输出格式段（顶层 + teaching_plan 子块 + style_profile 子块），
#   `progressive_diagnosis.dart` 是分块链 merge prompt 的输出格式段。
#   只扫一个 ⇒ 另一半字段天然落在视野外而守卫继续报绿（清单腐化的同族坑）。
SRC_PROMPTS = [
    "lib/services/skills_l1_core_p2.dart",      # 主诊断 prompt
    "lib/services/progressive_diagnosis.dart",   # 分块链 merge prompt
]
SRC_DTO = "lib/services/message_card_service.dart"        # L2 卡片 payload
SURFACE_DIRS = ["lib/features", "lib/widgets"]            # L3 呈现面

# ── 卡片 DTO 类（用户看的就是这张卡）──
CARD_DTO_CLASSES = [
    "DiagnosisResultCardPayload",   # 整张诊断卡
    "DiagnosisSyndromeCard",        # 卡内单条症候
    "OverallDiagnosis",             # 整体判定
]

# ── 非「诊断链产出」的 DTO 结构性字段（不参与可见性判断）──
# ★ 这些是「卡的结构」不是「诊断链产出」：判它们露不露出没有意义。
DTO_STRUCTURAL = {
    # DiagnosisResultCardPayload
    "syndromeCount", "syndromes", "diagnosisId", "messageId", "status",
    "focusCandidates",
    # DiagnosisSyndromeCard
    "syndromeId", "name", "severity", "evidenceCount",
    # FocusCandidateCard（候选焦点区）
    "total", "rationale",
}

# ── 诊断卡语义域的**真源归属** ──
# ★ 诊断链真源不只产出「卡上字段」，还产出**走别的出口**的字段：
#   `style_profile.*`（风格画像链 `student_profile.dart` / `style_technique_router.dart`）·
#   `suggested_phase` / `suggested_beginner_level` / `teaching_mode`（教学链）·
#   `teaching_plan.current_teaching_focus_id`（焦点激活链）·
#   `teaching_plan.next_step`（焦点激活链）。
#   这些字段**本就不该进诊断卡** ⇒ 若把它们纳入「必须露出」判据，
#   守卫会逼着把风格/教学状态塞进诊断卡（**判据反向驱动架构劣化**）。
# ⇒ 判据对象 = **诊断卡语义域**：
#     ① 卡片 DTO 已声明的字段（卡上有的，一律须露出）
#     ② 真源声明、且属于诊断卡语义域的字段（卡上该有而没有的 ⇒ 缺口）
#   ②的归属判定 = **父对象 + 已知非诊断卡出口表**。
NON_CARD_DOMAINS = {
    "style_profile": "风格画像链（student_profile.dart / style_technique_router.dart）",
    "teaching_plan": "焦点激活链（teaching_plan.* 三元组驱动 focus）",
}
NON_CARD_TOP_FIELDS = {
    "suggested_phase": "教学链（阶段迁移 FSM）",
    "suggested_beginner_level": "教学链（零基础路径）",
    "teaching_mode": "教学链（教学方式追踪）",
}

# ── 真源 prompt 的字段格式声明行 ──
#   `- syndrome_id (string): 症候编号 ...`
#   `- severity (L1|L2|L3): 严重度`
#   `- evidence (string[]): 原文证据片段`
#   `- root_cause_analysis / next_focus / feedback_summary: 可选`（斜杠并列）
RE_SCHEMA_LINE = re.compile(r"^\s*-\s+([a-z][a-z0-9_]*)\s*(?:\(([^)]*)\))?\s*[:：]", re.M)
RE_SCHEMA_SLASH = re.compile(r"^\s*-\s+([a-z_]+(?:\s*/\s*[a-z_]+)+)\s*[:：]", re.M)

# ── DTO 字段声明行 ──
RE_DTO_FIELD = re.compile(r"^\s*final\s+[\w<>,?\s]+?\s(\w+)\s*;", re.M)

# ── 呈现面「有效读点」：`.field` 形态，且宿主不是纯搬运对象 ──
RE_DOT_PROP = re.compile(r"\.\s*(\w+)\b")
RE_HOST = re.compile(r"([A-Za-z_]\w*)\s*$")
RE_PASSTHROUGH = {"payload", "this", "json", "raw", "parsed", "_raw"}

RE_LINE_COMMENT = re.compile(r"//.*$")
RE_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)


def strip_comments(text: str) -> str:
    """剥离行注释与块注释（注释不剥离则词频虚高一倍以上，实测踩坑）。"""
    text = RE_BLOCK_COMMENT.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), text)
    out = []
    for line in text.split("\n"):
        in_str = False
        quote = ""
        cut = len(line)
        for i, ch in enumerate(line):
            if not in_str and ch in "'\"":
                in_str = True
                quote = ch
            elif in_str and ch == quote:
                in_str = False
            elif not in_str and ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
                cut = i
                break
        out.append(RE_LINE_COMMENT.sub("", line[:cut]))
    return "\n".join(out)


def snake_to_camel(s: str) -> str:
    parts = s.split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def read(rel: str) -> str:
    p = REPO / rel
    if not p.exists():
        print("缺少真源文件：%s" % rel, file=sys.stderr)
        sys.exit(2)
    return p.read_text(encoding="utf-8", errors="ignore")


# ── L1：真源 prompt 声明的产出字段 ──
def l1_produced_fields() -> dict:
    """全部真源 prompt 输出格式段声明的字段 → {type, level, src}。

    ★ **必须扫所有真源**：主诊断 prompt（`skills_l1_core_p2.dart`：顶层 +
      `teaching_plan` 子块 + `style_profile` 子块）与分块链 merge prompt
      （`progressive_diagnosis.dart`：顶层 + syndrome 对象段）**各声明一部分**。
      只扫一个 ⇒ 另一半字段天然落在视野外而守卫继续报绿。

    ★ **父子层级按缩进自动判定**（不硬编码子字段名）：schema 段里
      `- xxx (type):` 的缩进 > 0 ⇒ 它是**上一个 indent=0 的对象字段**的子字段
      （实测：`teaching_plan` 下 3 个、`style_profile` 下 7 个、`overall` 下 5 个）。
      硬编码子字段名 = 又一份会腐化的清单 ⇒ 不做。
    """
    out = {}
    containers = set()
    for rel in SRC_PROMPTS:
        t = read(rel)
        parent = "top"          # 当前父对象
        for line in t.split("\n"):
            m = RE_SCHEMA_LINE.match(line)
            if not m:
                ms = RE_SCHEMA_SLASH.match(line)
                if ms:
                    for name in re.split(r"\s*/\s*", ms.group(1)):
                        out.setdefault(name, {"type": "", "level": "top", "src": rel})
                continue
            indent = len(line) - len(line.lstrip())
            name = m.group(1)
            ty = (m.group(2) or "").lower()
            if indent > 0:
                level = parent
            else:
                level = "top"
                # 该字段本身若是对象（type 写 object / object|null）⇒ 它是后随子字段的父
                if "object" in ty:
                    parent = name
                    containers.add(name)
            if name in out:
                # 同名字段（顶层 confidence 与 style_profile.confidence）：
                # 保留「顶层」身份（顶层字段的可见性要求更严）
                if out[name]["level"] != "top" and level == "top":
                    out[name]["level"] = "top"
                continue
            out[name] = {"type": m.group(2) or "", "level": level, "src": rel}
    for name, meta in out.items():
        meta["is_container"] = name in containers
    return out


# ── L2：卡片 DTO 字段 ──
def l2_dto_fields() -> dict:
    """类名 → 该类声明的字段名列表（`OverallDiagnosis` 在 teaching_types.dart）。"""
    out = {}
    for rel in (SRC_DTO, "lib/types/teaching_types.dart"):
        t = strip_comments(read(rel))
        cur = None
        buf = []
        for line in t.split("\n"):
            m = re.match(r"\s*class\s+(\w+)", line)
            if m:
                if cur:
                    out.setdefault(cur, buf)
                cur = m.group(1)
                buf = []
                continue
            if cur is None:
                continue
            m2 = RE_DTO_FIELD.match(line)
            if m2:
                buf.append(m2.group(1))
        if cur:
            out.setdefault(cur, buf)
    return out


# ── L3：呈现面有效读点 ──
def surface_files() -> list:
    """呈现面文件 = 产品面里**引用了卡片 DTO 类名**的文件（反向查，不硬编码文件名）。"""
    out = []
    for rel in SURFACE_DIRS:
        d = REPO / rel
        if not d.exists():
            continue
        for fp in sorted(d.rglob("*.dart")):
            try:
                t = strip_comments(fp.read_text(encoding="utf-8", errors="ignore"))
            except OSError:
                continue
            if any(re.search(r"\b%s\b" % c, t) for c in CARD_DTO_CLASSES):
                out.append((fp, t))
    return out


def effective_reads(field: str, surfaces: list) -> dict:
    """字段在呈现面的**有效读点**数。

    有效读点 = 形如 `宿主.field` 的**属性读取**，且宿主**不是**纯搬运对象
    （`payload` / `this` / `json` / `raw` / `parsed`）。
    ★ 不区分「搬运」与「渲染」会误判：诊断卡把 `confidence` 从 payload 搬进
      widget 字段（`confidence: payload.confidence`）若算命中，就等于说
      「用户看得见置信度」——而它其实从不渲染 ⇒ **恒绿 = 静音**
      （本守卫的头号死法）。
    ★ 宿主取 `.` 前最近的标识符 ⇒ `widget.syndrome.evidence` 的宿主是
      `syndrome`（有效读点），不是 `widget`。
    """
    hits = []
    for fp, t in surfaces:
        for m in RE_DOT_PROP.finditer(t):
            if m.group(1) != field:
                continue
            head = t[:m.start()]
            hm = RE_HOST.search(head)
            host = hm.group(1) if hm else ""
            if host in RE_PASSTHROUGH:
                continue
            ln = t[:m.start()].count("\n") + 1
            hits.append("%s:%d(%s.)" % (fp.name, ln, host))
    return {"total": len(hits), "hits": hits[:8]}


def build_chain() -> list:
    produced = l1_produced_fields()          # snake_case
    dto = l2_dto_fields()                     # class -> [fields]
    surfaces = surface_files()

    dto_field_index = {}                      # camel field -> [classes]
    for cls, flds in dto.items():
        # ★ 只认**卡片 DTO 类**：其余类（Syndrome / ParsedDiagnosis /
        #   FocusProblem / WritingStyleProfile …）是链路中间层，
        #   出现在那里只说明「解析层有」，**不能**说明「用户看得见」。
        if cls not in CARD_DTO_CLASSES:
            continue
        for f in flds:
            dto_field_index.setdefault(f, []).append(cls)

    rows = []
    dto_all = l2_dto_fields()
    card_fields = set()
    for cls in CARD_DTO_CLASSES:
        card_fields.update(dto_all.get(cls, []))

    for snake, meta in produced.items():
        camel = snake_to_camel(snake)
        # ── 语义域筛选：只判「诊断卡语义域」的字段 ──
        #   ① 卡上已有 ⇒ 必判
        #   ② 卡上未有 ⇒ 只在它**属于诊断卡语义域**时判（缺口）
        in_card = camel in card_fields
        domain = meta.get("level", "top")
        # ★ 容器对象本身不判：它的子字段各自判（`overall` 是容器但**在卡上**
        #   ⇒ 它自己也是「卡上有的字段」，判它是对的；
        #   而 `teaching_plan` / `style_profile` 是**走别出口的容器** ⇒ 跳过）。
        if meta.get("is_container") and not in_card:
            continue
        if domain in NON_CARD_DOMAINS:
            if not in_card:
                continue          # 走别的出口 ⇒ 不属本判据对象
        elif domain == "top" and snake in NON_CARD_TOP_FIELDS:
            if not in_card:
                continue
        rows.append({
            "field": camel,
            "snake": snake,
            "type": meta.get("type", ""),
            "level": domain,
            "in_card_now": in_card,
            "L1_produced": True,
            "L2_dto": dto_field_index.get(camel, []),
            "L3_surface": effective_reads(camel, surfaces),
        })
    return rows


def break_level(r: dict) -> int:
    """断链发生的级号（0 = 全通）。"""
    if not r["L2_dto"]:
        return 2
    if r["L3_surface"]["total"] == 0:
        return 3
    return 0


LEVEL_NAME = {
    0: "全通",
    2: "L2 卡片断（产出了但没进诊断卡 payload）",
    3: "L3 呈现断（进卡了但呈现面没真读）",
}


def load_baseline(path: Path) -> dict:
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print("基线 JSON 非法：%s" % e, file=sys.stderr)
        sys.exit(2)
    if not isinstance(data, dict) or "exemptions" not in data:
        print("基线结构非法：缺 exemptions", file=sys.stderr)
        sys.exit(2)
    for item in data["exemptions"]:
        if not item.get("reason"):
            print("基线豁免缺 reason：%s" % item.get("id", "<无 id>"), file=sys.stderr)
            sys.exit(2)
    return data


def main() -> int:
    ap = argparse.ArgumentParser(description="S1 诊断链字段三级贯通守卫 (v4)")
    ap.add_argument("--baseline", default="tool/surface_baseline.json",
                    help="基线文件路径（豁免表）")
    ap.add_argument("--list", action="store_true", help="只列逐级读数，不判定")
    ap.add_argument("--json", action="store_true", help="机器可读输出")
    args = ap.parse_args()

    rows = build_chain()

    if args.list:
        print("── S1 诊断链字段三级贯通读数（v4）──")
        for r in rows:
            lv = break_level(r)
            print("  %-22s L1✓ L2=%-46s L3读点=%-3d %s" % (
                r["field"], ",".join(r["L2_dto"]) or "—",
                r["L3_surface"]["total"], LEVEL_NAME[lv]))
        return 0

    base = load_baseline(REPO / args.baseline)
    exempt = None
    if base is not None:
        exempts = base["exemptions"]
        exempt = exempts[0] if exempts else None
        if not args.json:
            print("基线豁免 %d 项" % len(exempts))
            for e in exempts:
                print("  - %s" % e.get("id", "<无 id>"))
                print("    责任卡=%s 到期日=%s" % (e.get("owner_card", "<无>"),
                                                  e.get("due", "<无>")))

    errors = []
    broken = []
    for r in rows:
        lv = break_level(r)
        r["break_level"] = lv
        if lv:
            broken.append(r)

    # ── S1-1 贯通性：断链字段须在豁免内 ──
    # ★ 「设计性不露」登记项**不算断链**（它是被裁定的正确状态，不是缺口）
    #   ⇒ 先把它从 broken 里剔出去，否则守卫会逼着把被废除的字段渲染出来
    #   （§1-20 禁止重新引入模型自报 confidence —— 守卫若反向驱动，
    #    就成了「判据反向驱动架构劣化」）。
    design_non_visible = base.get("design_non_visible", []) if base else []
    dnv_fields = {d.get("field") for d in design_non_visible if d.get("field")}
    real_broken = [r for r in broken if r["field"] not in dnv_fields]

    exempt_fields = set()
    exempt_due = None
    exempt_expired = False
    days_left = None
    if exempt and exempt.get("id") == "S1-诊断链字段未贯通":
        exempt_fields = set(exempt.get("fields", []))
        exempt_due = exempt.get("due", "")
        if exempt_due:
            try:
                due = datetime.date.fromisoformat(exempt_due)
                days_left = (due - datetime.date.today()).days
                exempt_expired = days_left < 0
            except ValueError:
                errors.append("S1-4 基线豁免 due 格式非法：%s" % exempt_due)
    elif exempt:
        errors.append("S1-4 基线豁免 id 不认识：%s（v4 期望 S1-诊断链字段未贯通）"
                      % exempt.get("id"))

    uncovered = [r for r in real_broken if r["field"] not in exempt_fields]
    # ★ 到期判据必须独立于 uncovered：
    #   到期字段**仍在豁免名单内** ⇒ uncovered 恒空 ⇒ 若把到期检查挂在
    #   `uncovered` 上，豁免就变成**永久静音**（自测 P5 实测抓到此 bug：
    #   due 改成 2026-01-01（已逾期 293 天）仍 PASS「豁免期内」）。
    #   正确形态：豁免到期 ⇒ 该豁免**整体失效** ⇒ 名单内所有断链字段恢复报红。
    if exempt_expired and real_broken:
        for r in real_broken:
            tag = "逾期豁免" if r["field"] in exempt_fields else "未登记"
            errors.append("S1-1 诊断链字段未贯通且豁免已到期（逾期 %d 天，%s）：%s —— %s" % (
                -days_left, tag, r["field"], LEVEL_NAME[r["break_level"]]))
    elif uncovered:
        for r in uncovered:
            errors.append("S1-1 诊断链字段未贯通：%s —— %s" % (
                r["field"], LEVEL_NAME[r["break_level"]]))

    if real_broken and not uncovered and not exempt_expired:
        if not args.json:
            print("")
            print("WARN（S1，基线豁免中）：断链字段 %s" % ", ".join(
                r["field"] for r in real_broken))
            print("  ⇒ 缺口已登记：责任卡=%s 到期日=%s（剩余 %s 天）"
                  % (exempt.get("owner_card", "<无>"), exempt_due, days_left))
            print("  ⇒ 豁免期内本守卫不报红；到期未修则恢复报红。")
    elif real_broken and exempt_expired and not args.json:
        print("")
        print("WARN（S1）：基线豁免已于 %s 到期（逾期 %d 天）⇒ 本次报红"
              % (exempt_due, -days_left))

    # ── S1-2 清单外对象检出：DTO 里出现但 L1 真源未声明的字段 ──
    produced_camel = {snake_to_camel(s) for s in l1_produced_fields()}
    dto = l2_dto_fields()
    for cls in CARD_DTO_CLASSES:
        flds = dto.get(cls, [])
        extra = [f for f in flds
                 if f not in produced_camel and f not in DTO_STRUCTURAL]
        if extra:
            errors.append(
                "S1-2 DTO %s 出现真源 schema 未声明的字段（清单外对象）：%s "
                "⇒ 须先在 %s 的输出格式里声明，再判它是否该露出"
                % (cls, ", ".join(extra), " + ".join(SRC_PROMPTS)))

    # ── S1-3 基线登记字段消失（基线腐烂）──
    if base is not None:
        live = {r["field"] for r in rows}
        for f in base.get("registered_fields", []):
            if f not in live:
                errors.append("S1-3 基线登记字段 %s 已从真源产出清单消失（基线腐烂）" % f)

    # ── S1-5 豁免内容自洽：豁免点名的字段必须确实断链 ──
    if exempt and exempt_fields:
        live_break = {r["field"] for r in broken}
        stale = [f for f in sorted(exempt_fields) if f not in live_break]
        if stale:
            errors.append(
                "S1-5 豁免点名的字段其实已贯通（豁免名存实亡）：%s "
                "⇒ 应收窄豁免范围，否则掩盖新断点" % ", ".join(stale))

    # ── S1-6 设计性不露字段：登记为「不该露」的字段若真露了 ⇒ 报红 ──
    # ★ 这条是**双向判据**的另一半：只豁免断链而不反向检出，
    #   则「设计性不露」会变成永久免检区（清单腐化的另一种形态）。
    for item in design_non_visible:
        f = item.get("field")
        if not f:
            continue
        r = next((x for x in rows if x["field"] == f), None)
        if r is None:
            errors.append("S1-6 设计性不露登记的字段 %s 已不在真源产出清单（登记项过期）" % f)
            continue
        if r["L3_surface"]["total"] > 0:
            errors.append(
                "S1-6 设计性不露字段 %s 竟在呈现面出现 %d 个有效读点（%s）"
                "⇒ 违反其登记正典，须先裁正典再改代码"
                % (f, r["L3_surface"]["total"], "; ".join(r["L3_surface"]["hits"])))
        if not item.get("authority"):
            errors.append("S1-6 设计性不露登记 %s 缺 authority（须指向台账正典，不得凭印象）" % f)

    if args.json:
        print(json.dumps({
            "rows": rows,
            "exempt": exempt,
            "errors": errors,
        }, ensure_ascii=False, indent=2))
        return 1 if errors else 0

    print("")
    for r in rows:
        lv = r["break_level"]
        mark = "OK  " if lv == 0 else "★断 "
        print("  %s %-22s L2=%-46s L3读点=%d" % (
            mark, r["field"], ",".join(r["L2_dto"]) or "—",
            r["L3_surface"]["total"]))
        if lv:
            print("       └ 断点：%s" % LEVEL_NAME[lv])

    print("")
    if errors:
        print("FAIL（%d 项）" % len(errors))
        for e in errors:
            print("  - %s" % e)
        return 1

    if real_broken:
        print("PASS（豁免期内）：诊断链字段 %d 个，%d 个已贯通；%d 个断链在豁免登记中"
              "（责任卡=%s，到期日=%s，剩余 %s 天）"
              % (len(rows), len(rows) - len(real_broken), len(real_broken),
                 exempt.get("owner_card", "<无>"), exempt_due, days_left))
        print("  断链字段：%s" % ", ".join(
            "%s(%s)" % (r["field"], LEVEL_NAME[r["break_level"]].split("（")[0])
                     for r in real_broken))
        if dnv_fields:
            print("  设计性不露（不计缺口）：%s" % ", ".join(sorted(dnv_fields)))
    else:
        print("PASS：诊断链字段 %d 个全部贯通 L1→L2→L3" % len(rows))
    return 0


if __name__ == "__main__":
    _rc = main()
    sys.exit(_rc)
