#!/usr/bin/env python3
"""
反例测试脚本执行器
基于反例库 v2.3 的 15 条测试脚本，调用当前 Prompt 建立基线
"""

import os
import sys
import json
import time
import requests
from pathlib import Path
from datetime import datetime
from dotenv import load_dotenv

# 加载环境变量
load_dotenv()

# 测试脚本定义
TEST_SCRIPTS = [
    {
        "id": "1.1",
        "反例": "买了课但动笔痛苦",
        "输入": "我学了'冲突三要素'，但一动笔就不知道怎么写。我知道要有冲突，但就是写不出来。",
        "期望": "不重复原则，给动作层入口，引导学员自己写"
    },
    {
        "id": "1.2",
        "反例": "买了课但动笔痛苦",
        "输入": "我一动手就痛苦，感觉写出来的东西都很烂。",
        "期望": "不安慰，诊断具体卡点，给最小动作"
    },
    {
        "id": "2.1",
        "反例": "被AI同化，逻辑绑架故事",
        "输入": "我用AI改了几遍，现在越改越迷茫，感觉故事魂丢了。",
        "期望": "不继续帮改，揭穿问题，引导学员找回直觉"
    },
    {
        "id": "2.2",
        "反例": "被AI同化，逻辑绑架故事",
        "输入": "我是不是太追求逻辑，反而丢了故事的魂？",
        "期望": "不给抽象答案，给具体判断标准，引导学员自己判断"
    },
    {
        "id": "3.1",
        "反例": "AI写作效果不稳定",
        "输入": "我提示词改了又改，AI写出来的东西最多就是不犯错，根本谈不上写得好。",
        "期望": "不给提示词建议，揭穿AI天花板，引导学员自己写"
    },
    {
        "id": "3.2",
        "反例": "AI写作效果不稳定",
        "输入": "我觉得信息密度越高越好，一千字能写成两千字信息密度。",
        "期望": "不认同，纠正误区，给正确标准"
    },
    {
        "id": "4.1",
        "反例": "付费群的价值不是知识，是同侪",
        "输入": "我感觉自己一个人在练，不知道别人是不是也这样。",
        "期望": "不给知识，给陪伴感，给进步可视化"
    },
    {
        "id": "5.1",
        "反例": "学员认知断层",
        "输入": "我知道我写得不好，但我不知道问题在哪。",
        "期望": "不直接给答案，引导学员自己发现，给下一层入口"
    },
    {
        "id": "5.2",
        "反例": "学员认知断层",
        "输入": "我该怎么提问才能写好？",
        "期望": "不给提问模板，教'会问'，引导学员拆解"
    },
    {
        "id": "6.1",
        "反例": "平台对AI文的制度性拒绝",
        "输入": "我用AI写完了，可以直接去平台发吗？",
        "期望": "不直接回答，告知风险，给'练vs发'分段"
    },
    {
        "id": "7.1",
        "反例": "学员对'润色'的认知错误",
        "输入": "我润色了一下，500字变成1000字了。",
        "期望": "不认同，纠正认知，给减法练习"
    },
    {
        "id": "7.2",
        "反例": "学员对'润色'的认知错误",
        "输入": "我让AI润色一个词，它给我写了2000字。",
        "期望": "不继续用AI，揭穿问题，引导学员自己写"
    },
    {
        "id": "8.1",
        "反例": "AI工具箱四件套=代笔",
        "输入": "我写了一段，让AI续写了一段，这样不行吗？",
        "期望": "不认同，揭穿问题，引导学员自己写"
    },
    {
        "id": "9.1",
        "反例": "学员的'和AI合作'是依赖的伪装",
        "输入": "剧情是我自己想的，描写让AI写，这样不算依赖吧？",
        "期望": "不认同，揭穿伪装，给判断标准"
    },
    {
        "id": "9.2",
        "反例": "学员的'和AI合作'是依赖的伪装",
        "输入": "我就是让AI辅助润色，剧情走向人物人设都是自己取的。",
        "期望": "不认同，给依赖度检测，揭穿依赖"
    }
]

def load_prompt():
    """加载当前 Prompt"""
    prompt_path = Path(__file__).parent.parent / "resources" / "prompts" / "yuesheng-prompt-v3.md"
    if not prompt_path.exists():
        raise FileNotFoundError(f"Prompt 文件不存在: {prompt_path}")
    return prompt_path.read_text(encoding="utf-8")

def call_api(prompt: str, user_input: str) -> dict:
    """调用 DeepSeek API"""
    api_key = os.getenv("DEEPSEEK_API_KEY")
    endpoint = os.getenv("DEEPSEEK_ENDPOINT", "https://api.deepseek.com/v1")
    
    if not api_key:
        raise ValueError("未设置 DEEPSEEK_API_KEY 环境变量")
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "model": "deepseek-chat",
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": user_input}
        ],
        "temperature": 0.7,
        "max_tokens": 2000
    }
    
    response = requests.post(
        f"{endpoint}/chat/completions",
        headers=headers,
        json=payload,
        timeout=60
    )
    
    response.raise_for_status()
    return response.json()

def run_test(prompt: str, test_case: dict) -> dict:
    """执行单个测试"""
    print(f"\n{'='*60}")
    print(f"测试 {test_case['id']}: {test_case['反例']}")
    print(f"输入: {test_case['输入']}")
    print(f"期望: {test_case['期望']}")
    print(f"{'='*60}")
    
    start_time = time.time()
    
    try:
        response = call_api(prompt, test_case['输入'])
        duration = time.time() - start_time
        
        ai_response = response['choices'][0]['message']['content']
        
        print(f"\nAI 响应 ({duration:.2f}s):")
        print(ai_response)
        
        return {
            "id": test_case['id'],
            "反例": test_case['反例'],
            "输入": test_case['输入'],
            "期望": test_case['期望'],
            "AI响应": ai_response,
            "耗时": duration,
            "状态": "成功"
        }
    
    except Exception as e:
        duration = time.time() - start_time
        print(f"\n错误: {e}")
        return {
            "id": test_case['id'],
            "反例": test_case['反例'],
            "输入": test_case['输入'],
            "期望": test_case['期望'],
            "AI响应": None,
            "错误": str(e),
            "耗时": duration,
            "状态": "失败"
        }

def main():
    """主函数"""
    print("="*60)
    print("反例测试脚本执行器")
    print(f"测试时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"测试数量: {len(TEST_SCRIPTS)}")
    print("="*60)
    
    # 加载 Prompt
    print("\n加载 Prompt...")
    prompt = load_prompt()
    print(f"Prompt 长度: {len(prompt)} 字符")
    
    # 执行测试
    results = []
    for i, test_case in enumerate(TEST_SCRIPTS, 1):
        print(f"\n[{i}/{len(TEST_SCRIPTS)}] 执行测试...")
        result = run_test(prompt, test_case)
        results.append(result)
        
        # 避免 API 限流
        if i < len(TEST_SCRIPTS):
            print("\n等待 2 秒...")
            time.sleep(2)
    
    # 保存结果
    output_dir = Path(__file__).parent.parent / "docs" / "reports" / "baseline"
    output_dir.mkdir(parents=True, exist_ok=True)
    
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    output_file = output_dir / f"counter-example-baseline-{timestamp}.json"
    
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump({
            "测试时间": datetime.now().isoformat(),
            "Prompt版本": "yuesheng-prompt-v3.md",
            "测试数量": len(TEST_SCRIPTS),
            "结果": results
        }, f, ensure_ascii=False, indent=2)
    
    print(f"\n{'='*60}")
    print(f"测试完成!")
    print(f"结果已保存: {output_file}")
    print(f"{'='*60}")
    
    # 统计
    success_count = sum(1 for r in results if r['状态'] == '成功')
    failed_count = len(results) - success_count
    print(f"\n成功: {success_count}/{len(results)}")
    print(f"失败: {failed_count}/{len(results)}")

if __name__ == "__main__":
    main()
