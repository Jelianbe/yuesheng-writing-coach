"""
网文小说章节提取器
- 批量读取 GBK/UTF-8 编码的 TXT 小说文件
- 按章节自动切分
- 输出到 novel-chapters/ 目录，每章一个文件
"""

import os
import re
import json
from pathlib import Path

# 配置
DOWNLOADS_DIR = Path(r"C:\Users\月笙如歌\Downloads")
OUTPUT_DIR = Path(r"D:\ai-teacher\yuesheng-writing-coach\novel-chapters")
MAX_CHAPTER_LENGTH = 5000  # 每章最大字数

# 书籍配置：(文件名, 书名, slug)
BOOKS = [
    ("《诡秘之主》作者：爱潜水的乌贼.txt", "诡秘之主", "guimi-zhi-zhu"),
    ("《大奉打更人》作者：卖报小郎君.txt", "大奉打更人", "dafeng-dagengren"),
    ("《夜的命名术》（校对版全本）作者：会说话的肘子.txt", "夜的命名术", "yede-mingmingshu"),
]

# 十日终焉：多卷文件，按顺序合并
SHIRI_FILES = [
    "十日终焉(1-500章).txt",
    "十日终焉(501-1000章).txt",
    "十日终焉(1001-1379章).txt",
]

# 我在精神病院学斩神：多卷文件，按顺序合并
ZHANSHEN_FILES = [
    "我在精神病院学斩神(1-500章).txt",
    "我在精神病院学斩神(501-1000章).txt",
    "我在精神病院学斩神(1501-2000章).txt",
    "我在精神病院学斩神(2001-2033章).txt",
]

def process_multi_volume(files, book_name, slug):
    """处理多卷文件（合并）"""
    print(f"📖 处理: {book_name}（多卷合并）")
    
    book_dir = OUTPUT_DIR / slug
    book_dir.mkdir(parents=True, exist_ok=True)
    
    full_text = ""
    for filename in files:
        filepath = DOWNLOADS_DIR / filename
        if not filepath.exists():
            print(f"  ⚠️  文件不存在: {filename}")
            continue
        text = read_file(filepath)
        full_text += text
        print(f"  📄 {filename}: {len(text):,} 字符")
    
    print(f"  📄 合并后: {len(full_text):,} 字符")
    
    chapters = extract_chapters(full_text, book_name)
    
    if not chapters:
        print(f"  ⚠️  没有提取到章节，跳过")
        return []
    
    print(f"  📑 提取到 {len(chapters)} 章")
    
    for ch in chapters:
        ch_file = book_dir / f"ch{ch['number']:04d}.txt"
        with open(ch_file, 'w', encoding='utf-8') as f:
            f.write(ch['content'])
    
    return chapters

# 章节匹配正则（按优先级排列）
CHAPTER_PATTERNS = [
    r'^[ \t]*第[零一二三四五六七八九十百千\d]+[章节回卷][ \t\u3000：:、]+(.+)$',   # 第X章 标题 / 第X章:标题 / 第X章、标题
    r'^[ \t]*第[零一二三四五六七八九十百千\d]+[章节回卷][ \t\u3000：:、]*\s*$',    # 第X章（无标题）
    r'^[ \t]*第\d+[章节回卷][ \t\u3000：:、]+(.+)$',                                # 第1章 标题（纯数字）
    r'^[ \t]*第\d+[章节回卷][ \t\u3000：:、]*\s*$',                                 # 第1章（纯数字无标题）
]

CHAPTER_RE = re.compile('|'.join(CHAPTER_PATTERNS), re.MULTILINE)


def read_file(filepath: Path) -> str:
    """读取文件，尝试 GBK，失败则 UTF-8"""
    for encoding in ['gbk', 'utf-8', 'gb2312', 'gb18030']:
        try:
            with open(filepath, 'r', encoding=encoding) as f:
                return f.read()
        except (UnicodeDecodeError, UnicodeError):
            continue
    raise ValueError(f"无法读取文件 {filepath}，所有编码尝试失败")


def extract_chapters(text: str, book_name: str) -> list[dict]:
    """从文本中提取章节"""
    chapters = []
    
    # 找到所有章节起始位置
    matches = list(CHAPTER_RE.finditer(text))
    
    if not matches:
        print(f"  ⚠️  {book_name}: 未找到章节标记")
        return chapters
    
    for i, match in enumerate(matches):
        start = match.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        
        chapter_title = match.group(0).strip()
        # 清理标题中的特殊字符
        chapter_title_clean = chapter_title.replace('\n', '').replace('\r', '')
        
        content = text[start:end].strip()
        # 截断超长章节
        if len(content) > MAX_CHAPTER_LENGTH:
            content = content[:MAX_CHAPTER_LENGTH] + "\n\n[内容截断，超过5000字]"
        
        chapter_num = i + 1
        chapters.append({
            'number': chapter_num,
            'title': chapter_title_clean,
            'content': content,
            'length': len(content),
        })
    
    return chapters


def process_book(filepath: Path, book_name: str, slug: str):
    """处理单本书"""
    print(f"📖 处理: {book_name}")
    
    book_dir = OUTPUT_DIR / slug
    book_dir.mkdir(parents=True, exist_ok=True)
    
    text = read_file(filepath)
    print(f"  📄 文件大小: {len(text):,} 字符")
    
    chapters = extract_chapters(text, book_name)
    
    if not chapters:
        print(f"  ⚠️  没有提取到章节，跳过")
        return []
    
    print(f"  📑 提取到 {len(chapters)} 章")
    
    # 保存每章
    for ch in chapters:
        ch_file = book_dir / f"ch{ch['number']:04d}.txt"
        with open(ch_file, 'w', encoding='utf-8') as f:
            f.write(ch['content'])
    
    return chapters





def main():
    print("=" * 60)
    print("网文小说章节提取器")
    print("=" * 60)
    
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    index = {}
    total_chapters = 0
    
    # 处理单文件书籍
    for filename, book_name, slug in BOOKS:
        filepath = DOWNLOADS_DIR / filename
        if not filepath.exists():
            print(f"⚠️  文件不存在: {filename}")
            continue
        
        chapters = process_book(filepath, book_name, slug)
        
        index[slug] = {
            'name': book_name,
            'chapter_count': len(chapters),
            'chapters': [{'number': ch['number'], 'title': ch['title'], 'length': ch['length']} for ch in chapters],
        }
        total_chapters += len(chapters)
    
    # 处理凡人修仙传
    fanren_chapters = process_multi_volume([
        "凡人修仙传(1-500章).txt",
        "凡人修仙传(501-1000章).txt",
        "凡人修仙传(1001-1500章).txt",
        "凡人修仙传(1501-2000章).txt",
        "凡人修仙传(2501-2512章).txt",
    ], "凡人修仙传", "fanren-xiuxian-zhuan")
    if fanren_chapters:
        index['fanren-xiuxian-zhuan'] = {
            'name': '凡人修仙传',
            'chapter_count': len(fanren_chapters),
            'chapters': [{'number': ch['number'], 'title': ch['title'], 'length': ch['length']} for ch in fanren_chapters],
        }
        total_chapters += len(fanren_chapters)
    
    # 处理十日终焉
    shiri_chapters = process_multi_volume(SHIRI_FILES, "十日终焉", "shiri-zhongyan")
    if shiri_chapters:
        index['shiri-zhongyan'] = {
            'name': '十日终焉',
            'chapter_count': len(shiri_chapters),
            'chapters': [{'number': ch['number'], 'title': ch['title'], 'length': ch['length']} for ch in shiri_chapters],
        }
        total_chapters += len(shiri_chapters)
    
    # 处理我在精神病院学斩神
    zhanshen_chapters = process_multi_volume(ZHANSHEN_FILES, "我在精神病院学斩神", "wo-zai-jingshenbingyuan-xue-zhanshen")
    if zhanshen_chapters:
        index['wo-zai-jingshenbingyuan-xue-zhanshen'] = {
            'name': '我在精神病院学斩神',
            'chapter_count': len(zhanshen_chapters),
            'chapters': [{'number': ch['number'], 'title': ch['title'], 'length': ch['length']} for ch in zhanshen_chapters],
        }
        total_chapters += len(zhanshen_chapters)
    
    # 保存索引
    index_file = OUTPUT_DIR / "index.json"
    with open(index_file, 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, indent=2)
    
    print("\n" + "=" * 60)
    print(f"✅ 完成！共提取 {len(index)} 本书，{total_chapters} 章")
    print(f"📁 输出目录: {OUTPUT_DIR}")
    print(f"📋 索引文件: {index_file}")
    print("=" * 60)
    
    # 打印每本书统计
    for slug, info in index.items():
        print(f"  {info['name']}: {info['chapter_count']} 章")


if __name__ == '__main__':
    main()
