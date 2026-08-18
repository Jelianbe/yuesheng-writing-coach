# P3 批次一：skill_registry.dart 数据/逻辑分离
# 逐字迁移各 Skill 常量块到 part 文件，宿主留 类 + registry + 帮助函数。零行为变更。
import io

SRC = r"D:\ai-teacher\yuesheng-flutter\lib\services\skill_registry.dart"
OUT_DIR = r"D:\ai-teacher\yuesheng-flutter\lib\services"

with io.open(SRC, "r", encoding="utf-8") as f:
    lines = f.readlines()  # 0-based; line N = lines[N-1]

def L(n):
    return lines[n - 1]

# ---- 边界断言（防行号漂移）----
assert L(42).startswith("// ─── L1 常驻层：8 个核心"), L(42)
assert L(927).startswith("// ─── 态度档位"), L(927)
assert L(1069).startswith("// ─── L2 按需层"), L(1069)
assert L(2506).startswith("const Skill _diagnosisConfirmation"), L(2506)
assert L(3153).startswith("const Skill _demonstration"), L(3153)
assert L(4360).startswith("const Skill _textSurgery"), L(4360)
assert L(5299).startswith("// ─── L1 常驻层：回复语气"), L(5299)
assert L(5337).startswith("// ─── Skill 注册表"), L(5337)
assert L(5343).startswith("final Map<String, Skill> skillRegistry"), L(5343)
assert L(14).startswith("import 'syndrome_knowledge_base.dart';"), L(14)
assert L(15).startswith("import 'syndrome_registry.dart';"), L(15)
assert L(16).startswith("import 'technique_knowledge_base.dart';"), L(16)

PART_HEADER = (
    "// ─────────────────────────────────────────────────────────────\n"
    "// skill_registry 数据分片：{desc}（P3 知识减负 · 数据/逻辑分离）\n"
    "// 逐字迁移自 skill_registry.dart，零行为变更。\n"
    "// ─────────────────────────────────────────────────────────────\n"
    "part of 'skill_registry.dart';\n"
    "\n"
)

PARTS = [
    # (文件名, 起始行, 结束行(含), 说明)
    ("skills_l1_core.dart", 42, 926, "L1 常驻层 8 个核心 skill"),
    ("skills_attitude.dart", 927, 1068, "态度档位 skill（doubao/yuesheng/sensei）"),
    ("skills_beginner.dart", 1069, 2504, "L2 beginner 组 6 个 skill"),
    ("skills_diagnosis.dart", 2505, 3151, "L2 diagnosis 组 5 个 skill"),
    ("skills_training.dart", 3152, 4358, "L2 training 组 11 个 skill"),
    ("skills_advanced_outline.dart", 4359, 5298, "L2 advanced/outline 组 4 个 skill"),
    ("skills_reply_voice.dart", 5299, 5336, "L1 回复语气（去 AI 味）"),
]

for name, s, e, desc in PARTS:
    body = "".join(lines[s - 1 : e])
    with io.open(OUT_DIR + "\\" + name, "w", encoding="utf-8", newline="") as f:
        f.write(PART_HEADER.format(desc=desc) + body)
    print(f"{name}: L{s}-{e} ({e - s + 1} 行)")

# ---- 重建宿主：头(1-41) + part 指令(15 行后) + 尾(5337-5469) ----
part_directives = (
    "\n"
    "// ─── P3 数据分片（数据/逻辑分离；Skill 常量在各 skills_*.dart part 文件）──\n"
    + "".join(f"part '{name}';\n" for name, _, _, _ in PARTS)
)

head = lines[0:16] + [part_directives] + lines[16:41]
tail = lines[5336:]

with io.open(SRC, "w", encoding="utf-8", newline="") as f:
    f.write("".join(head) + "".join(tail))

print(f"宿主 skill_registry.dart 重建完成：{41 + 1 + len(part_directives.splitlines()) + (len(lines) - 5336)} 行（原 {len(lines)} 行）")
