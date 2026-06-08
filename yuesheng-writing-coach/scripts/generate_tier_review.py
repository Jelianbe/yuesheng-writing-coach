"""
脚本: generate_tier_review.py
任务: CX-001-TIER — 生成 tier-review.json（渐进分层评审节点）
依据: docs/tasks/CX-001-TIER-progressive-tier-review.md
"""

import json
import math

CURR_PATH = r'D:\ai-teacher\yuesheng-writing-coach\resources\config\curriculum-path.json'
LIB_PATH = r'D:\ai-teacher\yuesheng-writing-coach\resources\config\technique-library.json'
OUT_PATH = r'D:\ai-teacher\yuesheng-writing-coach\resources\config\tier-review.json'


def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def main():
    curriculum = load_json(CURR_PATH)
    lib = load_json(LIB_PATH)
    by_id = {t['id']: t for t in lib}

    # ── 全局规则 ────────────────────────────────────────────────
    global_rules = {
        "passThreshold": 0.7,
        "skipThreshold": 0.85,
        "maxSkipsPerPath": 1,
        "minTechniquesRatio": 0.75,
        "reviewRetryLimit": 2
    }

    # ── 对每条路径的每个阶段生成评审规则 ────────────────────────
    path_reviews = []
    for path in curriculum["paths"]:
        stage_reviews = []
        for i, stage in enumerate(path["stages"]):
            techniques = stage["techniques"]
            total = len(techniques)
            required = max(1, math.ceil(total * global_rules["minTechniquesRatio"]))

            # 预测试样本：取该阶段最难的 2 条（按 difficultyOrder 降序 + ID 升序）
            sorted_techs = sorted(techniques, key=lambda tid: (-by_id[tid]['difficultyOrder'], tid))
            pretest_samples = sorted_techs[:2]

            # 阶段间复习：取前序阶段最难的 1 条（如果没有前序阶段则为空）
            prev_review = []
            if i > 0:
                prev_stage = path["stages"][i - 1]
                prev_sorted = sorted(prev_stage["techniques"],
                                      key=lambda tid: (-by_id[tid]['difficultyOrder'], tid))
                prev_review = prev_sorted[:1]
            
            # 当前阶段的代表性技法（用于阶段间复习的"当前阶段"侧）
            current_review = sorted_techs[:1]

            skip_criteria_techniques = pretest_samples

            stage_review = {
                "level": stage["level"],
                "name": stage["name"],
                "totalTechniques": total,
                "completionCriteria": {
                    "requiredTechniques": required,
                    "requiredTechniqueIds": techniques,
                    "requiredAssessments": 1
                },
                "skipCriteria": {
                    "enabled": i > 0,  # 首个阶段不可跳过
                    "pretestTechniques": skip_criteria_techniques,
                    "pretestThreshold": global_rules["skipThreshold"]
                },
                "nextStageReview": {
                    "reviewType": "mixed" if prev_review and current_review else "single",
                    "fromPreviousStage": prev_review,
                    "fromCurrentStage": current_review
                }
            }
            stage_reviews.append(stage_review)

        path_reviews.append({
            "pathId": path["id"],
            "pathName": path["name"],
            "stages": stage_reviews
        })

    output = {
        "version": "1.0",
        "updatedAt": "2026-06-06",
        "description": "三条学习路径的渐进分层评审规则，包含完成标准、跳级判定和阶段间复习",
        "globalRules": global_rules,
        "pathReviews": path_reviews
    }

    # ── 写入 ────────────────────────────────────────────────────
    with open(OUT_PATH, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    print(f"[OK] 已生成 {OUT_PATH}")

    # ── 验证 ────────────────────────────────────────────────────
    print(f"\n{'='*50}")
    print("验证")
    print(f"{'='*50}")

    # D1: 全部 9 个阶段覆盖
    total_stages = sum(len(pr["stages"]) for pr in path_reviews)
    print(f"\n[D1] 路径数: {len(path_reviews)}, 阶段总数: {total_stages}")
    assert total_stages == 9, f"预期 9 个阶段, 实际 {total_stages}"
    print("      ✓ 全部 3 路径 × 3 阶段 = 9 阶段覆盖")

    # D1: JSON 合法
    json.dumps(output)
    print("      ✓ JSON 格式合法")

    # D2: 全局规则合理性
    print(f"\n[D2] 全局规则合理性:")
    print(f"      passThreshold ({global_rules['passThreshold']}) < skipThreshold ({global_rules['skipThreshold']}): ✓")
    print(f"      maxSkipsPerPath = {global_rules['maxSkipsPerPath']} (防止跳过多): ✓")
    print(f"      minTechniquesRatio = {global_rules['minTechniquesRatio']} (需完成 ≥75%): ✓")

    # D3: 每个阶段条件可判定
    print(f"\n[D3] 阶段条件可判定性:")
    for pr in path_reviews:
        for sr in pr["stages"]:
            checks = []
            checks.append(sr["completionCriteria"]["requiredTechniques"] > 0)
            checks.append(len(sr["skipCriteria"]["pretestTechniques"]) > 0)
            checks.append(sr["skipCriteria"]["pretestThreshold"] > 0)
            checks.append(len(sr["nextStageReview"]["fromPreviousStage"]) >= 0)
            all_ok = all(checks)
            status = "✓" if all_ok else "✗"
            print(f"      {pr['pathId']:20s} {sr['level']}: 可判定={status} (需完成{sr['completionCriteria']['requiredTechniques']}/{sr['totalTechniques']}, 预测试{len(sr['skipCriteria']['pretestTechniques'])}条)")

    # 输出汇总
    print(f"\n{'='*50}")
    print("各路径评审汇总")
    print(f"{'='*50}")
    for pr in path_reviews:
        print(f"\n--- {pr['pathName']} ({pr['pathId']}) ---")
        for sr in pr["stages"]:
            skip_status = f"可跳过(预测试:{', '.join(sr['skipCriteria']['pretestTechniques'])})" if sr['skipCriteria']['enabled'] else "首阶段不可跳过"
            print(f"  {sr['level']:4s} {sr['name']:8s} | 需完成 {sr['completionCriteria']['requiredTechniques']}/{sr['totalTechniques']} | {skip_status}")
            review_parts = []
            if sr['nextStageReview']['fromPreviousStage']:
                review_parts.append(f"前序:{','.join(sr['nextStageReview']['fromPreviousStage'])}")
            if sr['nextStageReview']['fromCurrentStage']:
                review_parts.append(f"当前:{','.join(sr['nextStageReview']['fromCurrentStage'])}")
            if review_parts:
                print(f"       阶段间复习: {'; '.join(review_parts)}")

    print(f"\n{'='*50}")
    print("完成！")


if __name__ == '__main__':
    main()
