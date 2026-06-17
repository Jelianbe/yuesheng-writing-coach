#!/usr/bin/env python
"""RWR-P0-3 替换脚本: rightPanelService -> useRightPanelStore (绝对路径)

防御性策略 (R-028):
- 文件读取/写入/删除均包裹 try-except
- 单文件失败时打印错误并 continue,不中断整体处理
- 错误信息包含 filepath + exception type + msg 便于溯源 (R-023)
"""

import os

# 强制 cwd 到 yuesheng-writing-coach
target_dir = r'd:\ai-teacher\yuesheng-writing-coach'
os.chdir(target_dir)
print(f'cwd: {os.getcwd()}')
print(f'exists WindowControls: {os.path.exists("src/renderer/components/layout/WindowControls.tsx")}')

files_replacements = [
    (os.path.join(target_dir, 'src/renderer/components/layout/RightDrawer.tsx'), [
        ("import { rightPanelService } from '../../services/right-panel.service';",
         "import { useRightPanelStore } from '../../stores';"),
        ('rightPanelService.openTool(',
         'useRightPanelStore.getState().openTool('),
        ('rightPanelService.switchSession(',
         'useRightPanelStore.getState().switchSession('),
        ('rightPanelService.removeSession(',
         'useRightPanelStore.getState().removeSession('),
    ]),
    (os.path.join(target_dir, 'src/renderer/components/layout/WindowControls.tsx'), [
        ("import { rightPanelService } from '../../services/right-panel.service';",
         "import { useRightPanelStore } from '../../stores';"),
        ("rightPanelService.switchTo('__settings__');",
         "useRightPanelStore.getState().switchTo('__settings__');"),
    ]),
    (os.path.join(target_dir, 'src/renderer/components/layout/WorkTreePanel.tsx'), [
        ("import { rightPanelService } from '../../services/right-panel.service';",
         "import { useRightPanelStore } from '../../stores';"),
        ('rightPanelService.openTool(',
         'useRightPanelStore.getState().openTool('),
        ('rightPanelService.openEditor(',
         'useRightPanelStore.getState().openEditor('),
    ]),
]


def process_file(filepath: str, replacements: list) -> None:
    """处理单个文件: 读取 -> 替换 -> 写回;任一环节异常时记录并跳过该文件."""
    # === 1. 读取阶段 ===
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f'[ERROR] 读取失败: {filepath} | {type(e).__name__}: {e}')
        return

    # === 2. 替换阶段(纯字符串操作,不涉及 IO,无 IO 异常) ===
    original = content
    changes = []
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            changes.append(f'  - {old[:60]}... -> {new[:60]}...')

    if content == original:
        print(f'[NO CHANGE] {filepath}')
        return

    # === 3. 写回阶段 ===
    try:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
    except Exception as e:
        print(f'[ERROR] 写入失败: {filepath} | {type(e).__name__}: {e}')
        return

    print(f'[OK] {filepath}')
    for c in changes:
        print(c)


for filepath, replacements in files_replacements:
    process_file(filepath, replacements)

# === 最后处理: 删除 right-panel.service.ts ===
service_path = os.path.join(target_dir, 'src/renderer/services/right-panel.service.ts')
if os.path.exists(service_path):
    try:
        os.remove(service_path)
        print(f'[REMOVED] {service_path}')
    except Exception as e:
        print(f'[ERROR] 删除失败: {service_path} | {type(e).__name__}: {e}')
else:
    print(f'[NOT FOUND] {service_path}')
