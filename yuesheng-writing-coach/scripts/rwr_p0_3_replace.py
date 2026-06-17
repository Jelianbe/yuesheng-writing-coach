#!/usr/bin/env python
"""RWR-P0-3 替换脚本: rightPanelService -> useRightPanelStore (绝对路径)"""

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

for filepath, replacements in files_replacements:
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    original = content
    changes = []
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            changes.append(f'  - {old[:60]}... -> {new[:60]}...')
    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f'[OK] {filepath}')
        for c in changes:
            print(c)
    else:
        print(f'[NO CHANGE] {filepath}')

# 最后处理: 删除 right-panel.service.ts
service_path = os.path.join(target_dir, 'src/renderer/services/right-panel.service.ts')
if os.path.exists(service_path):
    os.remove(service_path)
    print(f'[REMOVED] {service_path}')
else:
    print(f'[NOT FOUND] {service_path}')
