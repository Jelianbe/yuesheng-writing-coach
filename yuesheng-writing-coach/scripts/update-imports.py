#!/usr/bin/env python3
"""批量更新导入路径：renderer/shared/types → shared/types"""

import re
import os
from pathlib import Path

SRC_DIR = Path(r"D:\ai-teacher\yuesheng-writing-coach\src")

# 匹配从 renderer/shared/types 导入的语句
PATTERN = re.compile(r"""(from\s+['"])([^'"]*?)/renderer/shared/(types[^'"]*?)(['"])""")

def calculate_new_path(file_path: Path, import_path: str, types_part: str) -> str:
    """计算新的导入路径"""
    # 目标：src/shared/types 或 src/shared/types/types-config
    if types_part == 'types':
        target = SRC_DIR / 'shared' / 'types' / 'index'
    else:
        target = SRC_DIR / 'shared' / 'types' / types_part
    
    # 计算相对路径
    try:
        rel_path = os.path.relpath(target, file_path.parent)
        # 移除 .ts 扩展名（如果存在）
        if rel_path.endswith('.ts'):
            rel_path = rel_path[:-3]
        # 转换为相对导入格式
        if not rel_path.startswith('.'):
            rel_path = './' + rel_path
        return rel_path.replace('\\', '/')
    except ValueError:
        return str(target).replace('\\', '/')

def update_file(file_path: Path) -> int:
    """更新单个文件的导入路径"""
    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return 0
    
    original_content = content
    changes = 0
    
    def replace_import(match):
        nonlocal changes
        prefix = match.group(1)  # from '
        import_path = match.group(2)  # ../../../
        types_part = match.group(3)  # types or types-config
        suffix = match.group(4)  # '
        
        new_path = calculate_new_path(file_path, import_path, types_part)
        changes += 1
        return f"{prefix}{new_path}{suffix}"
    
    content = PATTERN.sub(replace_import, content)
    
    if changes > 0:
        try:
            file_path.write_text(content, encoding='utf-8')
            print(f"Updated {file_path}: {changes} import(s)")
        except Exception as e:
            print(f"Error writing {file_path}: {e}")
            return 0
    
    return changes

def main():
    total_changes = 0
    files_updated = 0
    
    # 遍历所有 TypeScript 文件
    for ext in ['*.ts', '*.tsx']:
        for file_path in SRC_DIR.rglob(ext):
            if 'node_modules' in str(file_path):
                continue
            if 'dist' in str(file_path):
                continue
            
            changes = update_file(file_path)
            if changes > 0:
                files_updated += 1
                total_changes += changes
    
    print(f"\nTotal: {files_updated} files updated, {total_changes} imports changed")

if __name__ == '__main__':
    main()
