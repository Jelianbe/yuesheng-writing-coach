# P3 批次二：三大知识库数据/逻辑分离
# 把巨型 r''' 知识字符串（数据）逐字迁到 part 文件，宿主留检索/渲染逻辑。零行为变更。
import io, re

BASE = r"D:\ai-teacher\yuesheng-flutter\lib\services"

PART_HEADER = (
    "// ─────────────────────────────────────────────────────────────\n"
    "// {lib} 数据分片：{desc}（P3 知识减负 · 数据/逻辑分离）\n"
    "// 逐字迁移自 {host}，零行为变更。\n"
    "// ─────────────────────────────────────────────────────────────\n"
    "part of '{host}';\n"
    "\n"
)

def find_line(lines, pattern, start=0):
    rx = re.compile(pattern)
    for i in range(start, len(lines)):
        if rx.match(lines[i]):
            return i  # 0-based
    raise SystemExit(f"未找到锚点: {pattern}")

def split(host_file, part_file, desc, decl_patterns, doc_back=0):
    path = BASE + "\\" + host_file
    with io.open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # 数据块起点：首个声明行（可向上带 doc 注释行）
    di = find_line(lines, decl_patterns[0])
    start = di
    for k in range(doc_back):
        j = di - 1 - k
        if j >= 0 and lines[j].lstrip().startswith("///"):
            start = j
        else:
            break

    # 数据块终点：最后一个声明行之后第一个以 '''; 结尾的行（字符串终止符，
    # 可能在行首独占，也可能跟在内容尾部如 "…排除项。''';"）
    last_decl = di
    for p in decl_patterns[1:]:
        last_decl = find_line(lines, p, last_decl + 1)
    end = find_line(lines, r"^.*''';\s*$", last_decl)

    # 宿主插入点：import 区之后（最后一个 import 行 +1）
    last_import = 0
    for i, l in enumerate(lines):
        if l.startswith("import "):
            last_import = i
    insert_at = last_import + 1

    header = PART_HEADER.format(lib=host_file[:-5], desc=desc, host=host_file)

    with io.open(BASE + "\\" + part_file, "w", encoding="utf-8", newline="") as f:
        f.write(header + "".join(lines[start : end + 1]))

    part_directive = (
        "\n// ─── P3 数据分片（数据/逻辑分离；知识文本在 part 文件）───\n"
        f"part '{part_file}';\n"
    )
    new_host = (
        lines[:insert_at]
        + [part_directive]
        + lines[insert_at:start]
        + lines[end + 1 :]
    )
    with io.open(path, "w", encoding="utf-8", newline="") as f:
        f.write("".join(new_host))

    print(
        f"{host_file}: 数据块 L{start+1}-L{end+1}({end-start+1}行) -> {part_file}；"
        f"宿主 {len(lines)} -> {len(new_host)} 行"
    )

# 症候库：索引 + 手册两个字符串一起搬（连续块，中间无逻辑）
split(
    "syndrome_knowledge_base.dart",
    "syndrome_kb_content.dart",
    "L2 索引 + L3 症候诊断手册（kSyndromeIndexContent / kSyndromeManualContent）",
    [r"^final String kSyndromeIndexContent", r"^final String kSyndromeManualContent"],
    doc_back=2,
)
# 技法库：索引 + 完整技法库两个字符串（连续块）
split(
    "technique_knowledge_base.dart",
    "technique_kb_content.dart",
    "L2 索引 + L3 完整技法库（kTechniqueIndexContent / kTechniqueLibraryContent）",
    [r"^final String kTechniqueIndexContent", r"^const String kTechniqueLibraryContent"],
    doc_back=2,
)
# 训练库：完整教学知识
split(
    "training_knowledge_base.dart",
    "training_kb_content.dart",
    "L3 完整训练教学知识（kTrainingFullKnowledge）",
    [r"^const String kTrainingFullKnowledge"],
    doc_back=3,
)
print("完成")
