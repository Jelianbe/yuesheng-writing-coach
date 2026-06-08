"""
CX-001-SPACE: 间隔重复复习配置生成脚本
========================================
基于遗忘曲线（Ebbinghaus）为 curriculum-path.json 中 3 条路径 32 条技法
生成间隔重复复习配置，输出到 spaced-repetition.json

产出: resources/config/spaced-repetition.json
"""

import json
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
CONFIG_DIR = BASE_DIR / "resources" / "config"

# 加载技法库
with open(CONFIG_DIR / "technique-library.json", "r", encoding="utf-8") as f:
    techniques_list = json.load(f)
techniques_map = {t["id"]: t for t in techniques_list}

# 加载路径配置
with open(CONFIG_DIR / "curriculum-path.json", "r", encoding="utf-8") as f:
    curriculum = json.load(f)

# ======== 配置参数 ========
DEFAULT_INTERVALS = [1, 3, 7, 14, 30, 60, 120]
REVIEW_PASS_THRESHOLD = 0.7
MAX_REVIEWS_PER_DAY = 5
MASTERY_AFTER_REVIEWS = 7
FAILED_REVIEW_PENALTY = "reset"

# ReviewMode 分配规则: 按技法难度
DIFFICULTY_TO_MODE = {
    "beginner": "recall",      # 初学者 → 回忆模式
    "intermediate": "practice", # 中级 → 练习模式
    "advanced": "mixed",       # 高级 → 混合模式
}

# 复习提示模板（按 coreId 定制）
PROMPT_TEMPLATES = {
    "show-dont-tell": "练习用{name}：{description}，尝试用动作和细节来代替直接说明",
    "dialogue-depth": "练习{name}：{description}，写一段带有潜台词的对话",
    "pov-control": "练习{name}：{description}，尝试用不同视角重写同一场景",
    "character-depth": "练习{name}：{description}，让角色通过行动展现内在层次",
    "worldbuilding-embed": "练习{name}：{description}，将世界观设定自然地融入场景叙事",
    "suspense-engine": "练习{name}：{description}，制造悬念并控制信息释放节奏",
    "opening-hook": "练习{name}：{description}，写一个能立刻抓住读者的开篇",
    "rhythm-control": "练习{name}：{description}，调整段落节奏制造张弛效果",
    "structure-innovation": "练习{name}：{description}，尝试用非线性或嵌套结构叙事",
}


def generate_prompt(technique, core_id):
    """为技法生成复习提示"""
    name = technique["name"]
    desc = technique.get("description", "")
    exercise = technique.get("exercise", "")

    # 优先使用模板
    if core_id in PROMPT_TEMPLATES:
        prompt = PROMPT_TEMPLATES[core_id].format(name=name, description=desc)
        if len(prompt) > 120:
            prompt = prompt[:117] + "..."
        return prompt

    # 通用模板
    if exercise:
        prompt = f"复习「{name}」：{exercise[:80]}{'...' if len(exercise) > 80 else ''}"
    else:
        prompt = f"复习「{name}」：{desc[:80]}{'...' if len(desc) > 80 else ''}"
    return prompt


def build_spaced_repetition():
    """构建间隔重复复习配置"""
    path_reviews = []

    for path in curriculum["paths"]:
        path_id = path["id"]
        stage_reviews = []

        for stage in path["stages"]:
            level = stage["level"]
            techniques_reviews = []

            for tech_id in stage["techniques"]:
                technique = techniques_map.get(tech_id)
                if not technique:
                    print(f"  ⚠ 技法 {tech_id} 未在技法库中找到，跳过")
                    continue

                # 按难度分配复习模式
                difficulty = technique.get("difficulty", "intermediate")
                review_mode = DIFFICULTY_TO_MODE.get(difficulty, "practice")

                # 生成复习提示
                core_ids = stage.get("coreIds", [])
                core_id = core_ids[0] if core_ids else ""
                review_prompt = generate_prompt(technique, core_id)

                techniques_reviews.append({
                    "id": tech_id,
                    "reviewMode": review_mode,
                    "reviewPrompt": review_prompt,
                    "intervals": DEFAULT_INTERVALS,
                })

            stage_reviews.append({
                "level": level,
                "techniques": techniques_reviews,
            })

        path_reviews.append({
            "pathId": path_id,
            "stageReviews": stage_reviews,
        })

    return {
        "version": "1.0",
        "updatedAt": "2026-06-06",
        "description": "基于Ebbinghaus遗忘曲线的间隔重复复习配置，覆盖3条学习路径32条技法",
        "spacingRules": {
            "defaultIntervals": DEFAULT_INTERVALS,
            "reviewPassThreshold": REVIEW_PASS_THRESHOLD,
            "maxReviewsPerDay": MAX_REVIEWS_PER_DAY,
            "masteryAfterReviews": MASTERY_AFTER_REVIEWS,
            "failedReviewPenalty": FAILED_REVIEW_PENALTY,
        },
        "pathReviews": path_reviews,
    }


def verify_output(data):
    """验证生成的配置"""
    errors = []
    warnings = []

    # D1: 3条路径覆盖
    path_ids = {p["pathId"] for p in data["pathReviews"]}
    expected_paths = {"character-craft", "world-building", "outline-planning"}
    if path_ids != expected_paths:
        errors.append(f"路径缺失: 期望 {expected_paths}，实际 {path_ids}")
    else:
        print("  ✅ D1: 3条路径全部覆盖")

    # D1: 技法数统计
    total_techniques = 0
    for path in data["pathReviews"]:
        for stage in path["stageReviews"]:
            total_techniques += len(stage["techniques"])
    print(f"  📊 技法总数: {total_techniques}（含跨路径重复计数）")

    if total_techniques < 32:
        warnings.append(f"技法总数 {total_techniques} < 32，可能遗漏")
    else:
        print(f"  ✅ D1: {total_techniques} 条技法配置（含重复计数 >= 32）")

    # D2: 间隔严格递增
    intervals = data["spacingRules"]["defaultIntervals"]
    is_increasing = all(intervals[i] < intervals[i + 1] for i in range(len(intervals) - 1))
    if not is_increasing:
        errors.append(f"D2失败: 间隔 {intervals} 未严格递增")
    else:
        print(f"  ✅ D2: 7级间隔严格递增 {intervals}")

    # D2: 7级
    if len(intervals) != 7:
        errors.append(f"D2失败: 间隔级数 {len(intervals)} != 7")
    else:
        print(f"  ✅ D2: 恰好7级间隔")

    # D3: 每技法有 reviewPrompt
    missing_prompts = []
    for path in data["pathReviews"]:
        for stage in path["stageReviews"]:
            for t in stage["techniques"]:
                if not t.get("reviewPrompt"):
                    missing_prompts.append(t["id"])
    if missing_prompts:
        errors.append(f"D3失败: {len(missing_prompts)} 条技法缺少 reviewPrompt: {missing_prompts}")
    else:
        print(f"  ✅ D3: 全部技法有 reviewPrompt")

    # 额外: reviewMode 合法性
    valid_modes = {"recall", "practice", "mixed"}
    for path in data["pathReviews"]:
        for stage in path["stageReviews"]:
            for t in stage["techniques"]:
                if t.get("reviewMode") not in valid_modes:
                    warnings.append(f"技法 {t['id']} reviewMode={t.get('reviewMode')} 不合法")

    if errors:
        print(f"\n  ❌ 验证失败 ({len(errors)} 个错误):")
        for e in errors:
            print(f"     - {e}")
    else:
        print(f"\n  ✅ 全部 DoD 验证通过")

    if warnings:
        print(f"\n  ⚠ 警告 ({len(warnings)} 个):")
        for w in warnings:
            print(f"     - {w}")

    return len(errors) == 0


def main():
    print("=" * 50)
    print("CX-001-SPACE: 间隔重复复习配置生成")
    print("=" * 50)

    # 加载配置
    print("\n📂 加载 curriculum-path.json...")
    path_count = len(curriculum["paths"])
    stage_count = sum(len(p["stages"]) for p in curriculum["paths"])
    print(f"   读取 {path_count} 条路径, {stage_count} 个阶段")

    # 生成
    print("\n🔄 生成间隔重复配置...")
    output = build_spaced_repetition()

    # 验证
    print("\n🔍 验证 DoD...")
    success = verify_output(output)

    if not success:
        print("\n❌ 验证未通过，中止输出")
        return

    # 输出
    output_path = CONFIG_DIR / "spaced-repetition.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"\n💾 已输出: {output_path}")

    # 统计摘要
    print("\n📋 生成摘要:")
    for path in output["pathReviews"]:
        total = sum(len(s["techniques"]) for s in path["stageReviews"])
        modes = {}
        for s in path["stageReviews"]:
            for t in s["techniques"]:
                m = t["reviewMode"]
                modes[m] = modes.get(m, 0) + 1
        mode_str = ", ".join(f"{k}={v}" for k, v in modes.items())
        print(f"   {path['pathId']}: {total} 条技法 [{mode_str}]")


if __name__ == "__main__":
    main()
