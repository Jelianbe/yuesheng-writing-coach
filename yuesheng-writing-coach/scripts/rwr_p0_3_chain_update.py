#!/usr/bin/env python
"""RWR-P0-3 闭环: 更新 TASK-CHAIN 指针 V17.2 -> V17.3"""
import os

target = r'd:\ai-teacher\yuesheng-writing-coach\docs\tasks\TASK-CHAIN.md'
os.chdir(r'd:\ai-teacher\yuesheng-writing-coach')
print(f'cwd: {os.getcwd()}')
with open(target, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. 头部 V17.2 -> V17.3
content = content.replace(
    '> **最后更新**: 2026-06-17  V17.2\n> **系统版本**: V3.6\n> **规范依据**: [TASK-SYSTEM-DESIGN.md](TASK-SYSTEM-DESIGN.md)\n> **任务链版本**: V17.2',
    '> **最后更新**: 2026-06-17  V17.3\n> **系统版本**: V3.6\n> **规范依据**: [TASK-SYSTEM-DESIGN.md](TASK-SYSTEM-DESIGN.md)\n> **任务链版本**: V17.3',
    1
)

# 2. 追加 RWR-P0-3 完成行（在 RWR-P0-2 完成行之后）
content = content.replace(
    '| ✅ 已完成 | **FB20260617-002 RWR-P0-2 progress.store 新增**：SessionProgress 类型 + useProgressStore(7 actions + 3 selectors + persist localStorage) + 21 单测。tsc 0 新增,vitest 167/167,eslint 0/0。阻塞解除 P1-5 / P1-6 |',
    '| ✅ 已完成 | **FB20260617-002 RWR-P0-2 progress.store 新增**：SessionProgress 类型 + useProgressStore(7 actions + 3 selectors + persist localStorage) + 21 单测。tsc 0 新增,vitest 167/167,eslint 0/0。阻塞解除 P1-5 / P1-6 |\n| ✅ 已完成 | **FB20260617-003 RWR-P0-3 Store 导出统一 + 删除 rightPanelService**：useRightPanelStore(zustand action store, 8 actions) + stores/index.ts barrel + 删除 right-panel.service.ts(106 行)。5 个消费者全替换 + 修复 2 处 RWR-P0-2 路径回归。tsc 0,vitest 167/167,circular 0。V4-UI-1 X-01 协作协议合并解决 |',
    1
)

# 3. 当前指针 RWR-P0-3 -> RWR-P0-4
content = content.replace(
    '| ▶️ **当前指针** | **RWR-P0-3** — Store 导出统一 + 删除 rightPanelService（V4-UI-1 合并解决）|',
    '| ▶️ **当前指针** | **RWR-P0-4** — 项目 IPC + 项目表 migration(021_projects.sql + project.handler.ts + project.contracts.ts + IPC_CHANNELS)|',
    1
)

with open(target, 'w', encoding='utf-8') as f:
    f.write(content)
print('[OK] TASK-CHAIN.md V17.2 -> V17.3')
print('第 3 行:', content.split(chr(10))[2])
