"""验证 technique-library.json 的 prerequisites 标注结果"""
import json

with open(r'D:\ai-teacher\yuesheng-writing-coach\resources\config\technique-library.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# 代表性样本验证
samples = ['TQ-001', 'TQ-005', 'TE-013', 'TQ-002', 'TQ-025', 'TQ-029', 'TQ-034', 'TE-018', 'TN-001']
print("=== 样本验证 ===")
for t in data:
    if t['id'] in samples:
        print(f"  {t['id']:8s} {t['name']:12s} coreId={t['coreId']:22s} diff={t['difficultyOrder']}  prereqs={t['prerequisites']}")

# 验证 L0 技法（show-dont-tell, opening-hook）只有同 coreId 内部依赖，无跨 coreId 依赖
cross_core_chains = {
    'show-dont-tell': [], 'opening-hook': [],
    'dialogue-depth': ['show-dont-tell'],
    'pov-control': ['show-dont-tell'],
    'rhythm-control': ['opening-hook'],
    'character-depth': ['show-dont-tell', 'dialogue-depth'],
    'worldbuilding-embed': ['show-dont-tell', 'rhythm-control'],
    'suspense-engine': ['rhythm-control', 'worldbuilding-embed'],
    'structure-innovation': ['opening-hook', 'rhythm-control', 'character-depth'],
    'negative-example': ['show-dont-tell'],
}
all_core_ids = {t['coreId'] for t in data}
for t in data:
    for p in t.get('prerequisites', []):
        p_tech = next((x for x in data if x['id'] == p), None)
        if p_tech:
            p_core = p_tech['coreId']
            allowed_cores = cross_core_chains.get(t['coreId'], [])
            if p_core != t['coreId'] and p_core not in allowed_cores:
                print(f"⚠ {t['id']}({t['coreId']}) 引用了不允许的跨 coreId 前置 {p}({p_core})")

print("✓ 跨 coreId 依赖合法性验证完成")

# 验证所有技法 ID 在 prerequisites 中存在
all_ids = {t['id'] for t in data}
missing_ids = set()
for t in data:
    for p in t.get('prerequisites', []):
        if p not in all_ids:
            missing_ids.add(p)
if missing_ids:
    print(f"⚠ prerequisites 引用了不存在的 ID: {missing_ids}")
else:
    print("✓ 所有 prerequisites 引用的 ID 均存在")

# 验证难度递增
for t in data:
    for p in t.get('prerequisites', []):
        p_tech = next((x for x in data if x['id'] == p), None)
        if p_tech:
            if p_tech['difficultyOrder'] > t['difficultyOrder']:
                print(f"⚠ {t['id']} 的前置 {p} 难度({p_tech['difficultyOrder']}) > 自身({t['difficultyOrder']})")

print("\n✓ 验证完成")
