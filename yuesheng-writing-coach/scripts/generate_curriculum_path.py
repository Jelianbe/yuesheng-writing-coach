"""
脚本: generate_curriculum_path.py
任务: CX-001-PATH — 生成 curriculum-path.json（三条领域独立路径）
依据: docs/tasks/CX-001-PATH-three-path-prototype.md
"""

import json
from collections import defaultdict

LIB_PATH = r'D:\ai-teacher\yuesheng-writing-coach\resources\config\technique-library.json'
OUT_PATH = r'D:\ai-teacher\yuesheng-writing-coach\resources\config\curriculum-path.json'


def load_techniques():
    with open(LIB_PATH, 'r', encoding='utf-8') as f:
        return json.load(f)


def build_index(data):
    """按 coreId 分组并按 difficultyOrder/id 排序"""
    by_core = defaultdict(list)
    for t in data:
        by_core[t['coreId']].append(t)
    for cid in by_core:
        by_core[cid].sort(key=lambda x: (x['difficultyOrder'], x['id']))
    return by_core, {t['id']: t for t in data}


def pick_techniques(by_core, core_id, max_count=4, max_order=1):
    """从 coreId 中选 max_count 条技法，difficultyOrder <= max_order"""
    candidates = [t for t in by_core.get(core_id, [])
                  if t['difficultyOrder'] <= max_order]
    return [t['id'] for t in candidates[:max_count]]


def verify_techniques_exist(technique_ids, all_data):
    """验证所有 ID 存在且 coreId 匹配"""
    by_id = {t['id']: t for t in all_data}
    missing = [tid for tid in technique_ids if tid not in by_id]
    return missing


def verify_dag_prerequisites(technique_ids, all_data, allowed_core_ids):
    """验证指定技法列表的 prerequisites 在 allowed_core_ids 范围内"""
    by_id = {t['id']: t for t in all_data}
    violations = []
    for tid in technique_ids:
        t = by_id.get(tid)
        if t and t.get('prerequisites'):
            for prereq_id in t['prerequisites']:
                prereq = by_id.get(prereq_id)
                if prereq and prereq['coreId'] not in allowed_core_ids:
                    violations.append(f"{tid}({t['coreId']}) 依赖 {prereq_id}({prereq['coreId']}) 不在允许范围 {allowed_core_ids}")
    return violations


def main():
    data = load_techniques()
    by_core, by_id = build_index(data)

    # ── 路径定义 ────────────────────────────────────────────────
    # 每个路径：id, name, stages 列表
    # stage: level, name, focus, coreIds, maxOrder for picking

    paths_config = [
        {
            "id": "character-craft",
            "name": "角色塑造",
            "nameEn": "Character Craft",
            "description": "从「展示而非告知」的基础表达开始，逐步掌握对话设计、视角控制，最终实现角色立体化",
            "stages": [
                {
                    "level": "L0",
                    "name": "基础表达",
                    "focus": "学习用动作、环境、细节来展示角色的状态和情绪，而非直接告诉读者",
                    "coreIds": ["show-dont-tell"],
                    "maxOrder": 1,
                    "maxCount": 4
                },
                {
                    "level": "L1",
                    "name": "对话与视角",
                    "focus": "掌握对话层次设计和视角管理技巧，让角色之间的互动更加真实有力",
                    "coreIds": ["dialogue-depth", "pov-control"],
                    "maxOrder": 1,
                    "maxCount": 4
                },
                {
                    "level": "L2",
                    "name": "角色立体化",
                    "focus": "综合运用表达、对话和视角技巧，塑造有深度、有弧光的立体角色",
                    "coreIds": ["character-depth"],
                    "maxOrder": 1,
                    "maxCount": 4
                }
            ]
        },
        {
            "id": "world-building",
            "name": "世界观构建",
            "nameEn": "World Building",
            "description": "从通过细节展示世界开始，逐步掌握设定融入和悬念制造，构建令人沉浸的世界观",
            "stages": [
                {
                    "level": "L0",
                    "name": "展示式传递",
                    "focus": "学习通过细节和场景展示世界观设定，而非直接铺陈说明",
                    "coreIds": ["show-dont-tell"],
                    "maxOrder": 1,
                    "maxCount": 3
                },
                {
                    "level": "L2",
                    "name": "设定融入",
                    "focus": "将世界观设定自然地融入日常行为、对话和物品描述中",
                    "coreIds": ["worldbuilding-embed"],
                    "maxOrder": 1,
                    "maxCount": 4
                },
                {
                    "level": "L3",
                    "name": "悬念驱动",
                    "focus": "利用世界观设定制造悬念和期待感，让读者沉浸其中",
                    "coreIds": ["suspense-engine"],
                    "maxOrder": 1,
                    "maxCount": 4
                }
            ]
        },
        {
            "id": "outline-planning",
            "name": "大纲规划",
            "nameEn": "Outline Planning",
            "description": "从写出抓人的开篇开始，逐步掌握节奏控制，最终学会设计创新的故事结构",
            "stages": [
                {
                    "level": "L0",
                    "name": "开篇技巧",
                    "focus": "学习写出吸引读者的开篇，用最短的时间抓住读者的注意力",
                    "coreIds": ["opening-hook"],
                    "maxOrder": 1,
                    "maxCount": 4
                },
                {
                    "level": "L1",
                    "name": "节奏呼吸",
                    "focus": "掌握叙事节奏的控制技巧，让故事张弛有度、高潮迭起",
                    "coreIds": ["rhythm-control"],
                    "maxOrder": 1,
                    "maxCount": 4
                },
                {
                    "level": "L2",
                    "name": "结构创新",
                    "focus": "学习双线叙事、规则嵌套等结构技巧，突破传统叙事框架",
                    "coreIds": ["structure-innovation"],
                    "maxOrder": 1,
                    "maxCount": 4
                }
            ]
        }
    ]

    # ── 生成路径数据 ────────────────────────────────────────────
    paths = []
    for pconf in paths_config:
        stages = []
        for sconf in pconf["stages"]:
            techniques = []
            for cid in sconf["coreIds"]:
                picked = pick_techniques(by_core, cid, 
                                         max_count=sconf["maxCount"] // len(sconf["coreIds"]) + 1,
                                         max_order=sconf["maxOrder"])
                techniques.extend(picked)
            # 按 difficultyOrder 排序
            techniques.sort(key=lambda tid: (by_id[tid]['difficultyOrder'], tid))
            # 限制总数
            techniques = techniques[:sconf["maxCount"]]
            
            stages.append({
                "level": sconf["level"],
                "name": sconf["name"],
                "focus": sconf["focus"],
                "coreIds": sconf["coreIds"],
                "techniques": techniques,
                "prerequisites": []
            })
        
        paths.append({
            "id": pconf["id"],
            "name": pconf["name"],
            "nameEn": pconf["nameEn"],
            "description": pconf["description"],
            "stages": stages
        })

    # ── 补充 prerequisites（前序 stage coreIds + DAG 交叉依赖） ──
    # DAG 中存在交叉依赖：世界观技法依赖节奏控制，结构创新依赖角色立体化
    # 这些跨路径依赖需要显式标注在 stage 的 prerequisites 中
    for path in paths:
        cumulative_cores = set()
        for stage in path["stages"]:
            # 基础：所有前序 stage 的 coreIds
            stage_prereqs = set(cumulative_cores)
            
            # 扩展：当前 stage 技法需要的所有 cross-coreId 前置 coreId
            stage_core_set = set(stage["coreIds"])
            all_allowed = cumulative_cores | stage_core_set
            for tid in stage["techniques"]:
                t = by_id.get(tid)
                if t and t.get('prerequisites'):
                    for prereq_id in t['prerequisites']:
                        prereq = by_id.get(prereq_id)
                        if prereq and prereq['coreId'] not in all_allowed:
                            # 这个前置 coreId 不在路径中，需要添加
                            stage_prereqs.add(prereq['coreId'])
            
            stage["prerequisites"] = sorted(stage_prereqs)
            cumulative_cores.update(stage["coreIds"])

    output = {
        "version": "1.0",
        "updatedAt": "2026-06-06",
        "description": "三条创作领域独立学习路径，按 DAG 依赖关系组织 L0→L1/L2→L2/L3 阶段",
        "paths": paths
    }

    # ── 写入文件 ────────────────────────────────────────────────
    with open(OUT_PATH, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    print(f"[OK] 已生成 {OUT_PATH}")

    # ── 验证 ────────────────────────────────────────────────────
    print(f"\n{'='*50}")
    print("验证")
    print(f"{'='*50}")

    # D1: JSON 格式合法
    with open(OUT_PATH, 'r', encoding='utf-8') as f:
        json.load(f)
    print(f"\n[D1] JSON 格式合法：✓")

    # D2: 3 条路径，每路径 3 阶段，所有 ID 存在
    path_count = len(output["paths"])
    print(f"[D2] 路径数量：{path_count}（需≥3）")
    for p in output["paths"]:
        stage_count = len(p["stages"])
        all_tids = [tid for s in p["stages"] for tid in s["techniques"]]
        missing = verify_techniques_exist(all_tids, data)
        status = "✓" if not missing else "✗"
        print(f"  {p['id']:20s}: {stage_count} 阶段, {len(all_tids)} 技法, ID 存在性={status}")

    # D3: DAG 可达性验证（考虑 stage 的 prerequisites 字段）
    print(f"\n[D3] DAG 依赖可达性验证：")
    for p in output["paths"]:
        cumulative_cores = set()
        violations = []
        for stage in p["stages"]:
            # 允许的 coreId = 累积 + 当前 stage + stage 的 prerequisites
            allowed_cores = cumulative_cores | set(stage["coreIds"]) | set(stage["prerequisites"])
            vs = verify_dag_prerequisites(stage["techniques"], data, allowed_cores)
            violations.extend(vs)
            cumulative_cores.update(stage["coreIds"])
        
        status = "✓" if not violations else "✗"
        print(f"  {p['id']:20s}: {status}" + (f" ({len(violations)} 条违规)" if violations else ""))
        for v in violations:
            print(f"          {v}")

    # 输出统计
    print(f"\n{'='*50}")
    print("各路径技法汇总")
    print(f"{'='*50}")
    for p in output["paths"]:
        print(f"\n--- {p['name']} ({p['id']}) ---")
        for s in p["stages"]:
            names = [f"{tid}({by_id[tid]['name']})" for tid in s["techniques"]]
            print(f"  {s['level']} [{', '.join(s['coreIds'])}]: {', '.join(names)}")
    
    print(f"\n{'='*50}")
    print("完成！")


if __name__ == '__main__':
    main()
