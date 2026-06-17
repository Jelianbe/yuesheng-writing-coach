#!/usr/bin/env python3
"""
前端-后端 IPC 链接完整性检测脚本 V1.0
检测三层 IPC 通信链路的完整性：
  1. constants.ts 中 IPC_CHANNELS 定义 ↔ handler.ts 注册（主进程端）
  2. handler.ts 注册 ↔ preload/index.ts 暴露（桥接层）
  3. constants.ts ALLOWED_INVOKE_CHANNELS ↔ preload allowedInvokeChannels（白名单对齐）
  4. preload 暴露缺口检测：handler 已注册但 preload 未暴露

使用方式:
  python scripts/link_checker.py
  python scripts/link_checker.py --json  # 输出 JSON 到 stdout
"""

import json
import re
import sys
from pathlib import Path
from collections import defaultdict

PROJECT_ROOT = Path(r"D:\ai-teacher\yuesheng-writing-coach")
SRC_DIR = PROJECT_ROOT / "src"
CONSTANTS_PATH = SRC_DIR / "shared" / "constants.ts"
PRELOAD_PATH = SRC_DIR / "preload" / "index.ts"


# ── 工具函数 ──

def extract_brace_block(text: str, start_marker: str) -> str:
    """提取从 start_marker 后的第一个 { ... } 对象体"""
    idx = text.find(start_marker)
    if idx == -1:
        return ""
    start_brace = text.index("{", idx)
    depth = 0
    for i in range(start_brace, len(text)):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start_brace:i + 1]
    return ""


def extract_array_body(text: str, start_marker: str) -> str:
    """提取从 start_marker 后的第一个 = [ ... ] 数组体"""
    idx = text.find(start_marker)
    if idx == -1:
        return ""
    # 跳过类型标注中的 []（如 readonly string[]），找到 = [ 作为起始
    eq_bracket = text.find("= [", idx)
    if eq_bracket == -1:
        return ""
    start_bracket = eq_bracket + 2  # 跳过 "= "
    depth = 0
    for i in range(start_bracket, len(text)):
        ch = text[i]
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return text[start_bracket:i + 1]
    return ""


def extract_strings_from_array(array_body: str) -> set[str]:
    """从 TypeScript 数组字面量中提取字符串值"""
    return set(re.findall(r"""['"]([\w:]+)['"]\s*[,\)\]]""", array_body))


def extract_strings_from_object(obj_body: str) -> dict[str, str]:
    """从 TypeScript 对象字面量中提取 key: 'value' 映射"""
    result: dict[str, str] = {}
    for m in re.finditer(r"""(\w+)\s*:\s*['"]([\w:]+)['"]""", obj_body):
        result[m.group(1)] = m.group(2)
    return result


# ── 数据提取 ──

def extract_constants() -> dict:
    """从 constants.ts 提取所有 IPC 相关定义"""
    text = CONSTANTS_PATH.read_text(encoding="utf-8", errors="ignore")

    # 1. IPC_CHANNELS 对象 → { CONST_NAME: channel_value }
    ipc_body = extract_brace_block(text, "export const IPC_CHANNELS")
    ipc_channels = extract_strings_from_object(ipc_body)

    # 2. ALLOWED_INVOKE_CHANNELS 数组（含 IPC_CHANNELS.XXX 引用）→ resolve to channel values
    invoke_body = extract_array_body(text, "export const ALLOWED_INVOKE_CHANNELS")
    allowed_invoke_raw = set(re.findall(r"IPC_CHANNELS\.(\w+)", invoke_body))
    allowed_invoke = {ipc_channels[name] for name in allowed_invoke_raw if name in ipc_channels}

    # 3. ALLOWED_EVENT_CHANNELS 数组 → resolve to channel values
    event_body = extract_array_body(text, "export const ALLOWED_EVENT_CHANNELS")
    allowed_events_raw = set(re.findall(r"IPC_CHANNELS\.(\w+)", event_body))
    allowed_events = {ipc_channels[name] for name in allowed_events_raw if name in ipc_channels}

    return {
        "ipc_channels": ipc_channels,
        "allowed_invoke": allowed_invoke,
        "allowed_events": allowed_events,
    }


def extract_handler_registrations(constants: dict) -> dict[str, list[dict]]:
    """扫描所有 *.handler.ts，提取 IPC handler 注册"""
    registrations: dict[str, list[dict]] = defaultdict(list)
    channel_map = constants["ipc_channels"]  # {CONST_NAME: channel_value}
    # 反向映射: IPC_CHANNELS.X → channel value（用于解析常量引用）
    const_name_to_value = {f"IPC_CHANNELS.{k}": v for k, v in channel_map.items()}

    for hf in (SRC_DIR / "main" / "ipc").glob("*.handler.ts"):
        text = hf.read_text(encoding="utf-8", errors="ignore")

        # 匹配 createHandler('channel:name', ...) 字符串字面量
        for m in re.finditer(r"""createHandler\s*\(\s*['"]([\w:]+)['"]""", text):
            ch = m.group(1)
            line_num = text[:m.start()].count('\n') + 1
            tail = text[m.start():m.start() + 800]
            has_trycatch = 'try' in tail and 'catch' in tail
            registrations[ch].append({
                "file": str(hf.relative_to(PROJECT_ROOT)),
                "line": line_num,
                "has_trycatch": has_trycatch,
                "method": "createHandler(string)",
            })

        # 匹配 createHandler(IPC_CHANNELS.XXX, ...) 常量引用
        for m in re.finditer(r"""createHandler\s*\(\s*(IPC_CHANNELS\.\w+)""", text):
            ref = m.group(1)
            if ref in const_name_to_value:
                ch = const_name_to_value[ref]
                line_num = text[:m.start()].count('\n') + 1
                tail = text[m.start():m.start() + 800]
                has_trycatch = 'try' in tail and 'catch' in tail
                registrations[ch].append({
                    "file": str(hf.relative_to(PROJECT_ROOT)),
                    "line": line_num,
                    "has_trycatch": has_trycatch,
                    "method": "createHandler(const)",
                })

        # 匹配 ipcMain.handle('channel:name', ...) 字符串字面量
        for m in re.finditer(r"""ipcMain\.handle\s*\(\s*['"]([\w:]+)['"]""", text):
            ch = m.group(1)
            line_num = text[:m.start()].count('\n') + 1
            tail = text[m.start():m.start() + 800]
            has_trycatch = 'try' in tail and 'catch' in tail
            registrations[ch].append({
                "file": str(hf.relative_to(PROJECT_ROOT)),
                "line": line_num,
                "has_trycatch": has_trycatch,
                "method": "ipcMain.handle(string)",
            })

        # 匹配 ipcMain.handle(IPC_CHANNELS.XXX, ...) 常量引用
        for m in re.finditer(r"""ipcMain\.handle\s*\(\s*(IPC_CHANNELS\.\w+)""", text):
            ref = m.group(1)
            if ref in const_name_to_value:
                ch = const_name_to_value[ref]
                line_num = text[:m.start()].count('\n') + 1
                tail = text[m.start():m.start() + 800]
                has_trycatch = 'try' in tail and 'catch' in tail
                registrations[ch].append({
                    "file": str(hf.relative_to(PROJECT_ROOT)),
                    "line": line_num,
                    "has_trycatch": has_trycatch,
                    "method": "ipcMain.handle(const)",
                })

    return dict(registrations)


def extract_preload_expose() -> dict:
    """从 preload/index.ts 提取暴露的白名单"""
    text = PRELOAD_PATH.read_text(encoding="utf-8", errors="ignore")

    # 1. allowedInvokeChannels
    invoke_body = extract_array_body(text, "const allowedInvokeChannels")
    allowed_invoke = extract_strings_from_array(invoke_body)

    # 2. allowedSendChannels
    send_body = extract_array_body(text, "const allowedSendChannels")
    allowed_send = extract_strings_from_array(send_body)

    # 3. allowedEventChannels
    event_body = extract_array_body(text, "const allowedEventChannels")
    allowed_events = extract_strings_from_array(event_body)

    return {
        "allowed_invoke": allowed_invoke,
        "allowed_send": allowed_send,
        "allowed_events": allowed_events,
    }


# ── 检测逻辑 ──

def check_channel_handler_pairing(constants: dict, handlers: dict) -> list[dict]:
    """constants IPC_CHANNELS 定义 vs handler.ts 注册"""
    issues = []
    all_channels = set(constants["ipc_channels"].values())
    registered = set(handlers.keys())

    # 单向推送频道（主→渲染，不需 handler）
    one_way = {
        'chat:stream:data', 'chat:stream:end', 'chat:tool:executing',
        'diagnosis:update', 'teachingState:updated',
    }

    # 已定义但未注册 handler
    missing_handler = all_channels - registered - one_way
    for ch in sorted(missing_handler):
        const_name = [k for k, v in constants["ipc_channels"].items() if v == ch][0]
        issues.append({
            "severity": "P0",
            "type": "channel_no_handler",
            "channel": ch,
            "const_name": const_name,
            "message": f"const {const_name} = '{ch}' 在 constants.ts 中定义，但未在任何 handler.ts 中注册",
        })

    # 已注册但不在 constants 定义中
    unlisted = registered - all_channels
    for ch in sorted(unlisted):
        for reg in handlers[ch]:
            issues.append({
                "severity": "P1",
                "type": "handler_no_channel_def",
                "channel": ch,
                "file": reg["file"],
                "line": reg["line"],
                "message": f"handler 注册了 '{ch}' 但该频道不在 IPC_CHANNELS 对象中定义",
            })

    # 已注册但缺少 try/catch
    for ch, regs in handlers.items():
        for reg in regs:
            if not reg["has_trycatch"]:
                issues.append({
                    "severity": "P0",
                    "type": "handler_no_trycatch",
                    "channel": ch,
                    "file": reg["file"],
                    "line": reg["line"],
                    "message": f"handler '{ch}' 缺少 try/catch 保护",
                })

    return issues


def check_handler_preload_pairing(handlers: dict, preload: dict) -> list[dict]:
    """handler 注册 ↔ preload 暴露"""
    issues = []
    registered = set(handlers.keys())

    # 单向推送（preload 用 on 订阅，不需要 invoke/send）
    one_way = {
        'chat:stream:data', 'chat:stream:end', 'chat:tool:executing',
        'diagnosis:update', 'teachingState:updated',
    }

    all_exposed = preload["allowed_invoke"] | preload["allowed_send"] | preload["allowed_events"]

    # handler 已注册但 preload 未暴露
    not_exposed = registered - all_exposed - one_way
    for ch in sorted(not_exposed):
        reg = handlers[ch][0]
        issues.append({
            "severity": "P0",
            "type": "handler_not_exposed",
            "channel": ch,
            "file": reg["file"],
            "line": reg["line"],
            "message": f"handler '{ch}' 已注册，但 preload/index.ts 未暴露该频道",
        })

    # preload 暴露了但无 handler（可能是死代码或单向推送）
    handler_channels = registered | one_way
    dead_preload = all_exposed - handler_channels
    for ch in sorted(dead_preload):
        in_invoke = ch in preload["allowed_invoke"]
        in_send = ch in preload["allowed_send"]
        in_events = ch in preload["allowed_events"]
        locations = []
        if in_invoke:
            locations.append("allowedInvokeChannels")
        if in_send:
            locations.append("allowedSendChannels")
        if in_events:
            locations.append("allowedEventChannels")
        issues.append({
            "severity": "P1",
            "type": "preload_dead_expose",
            "channel": ch,
            "locations": locations,
            "message": f"preload 暴露了 '{ch}'（位于 {', '.join(locations)}），但无对应 handler 注册",
        })

    return issues


def check_whitelist_alignment(constants: dict, preload: dict) -> list[dict]:
    """constants ALLOWED_INVOKE_CHANNELS ↔ preload allowedInvokeChannels 白名单对齐"""
    issues = []

    const_invoke = set(constants["allowed_invoke"])
    preload_invoke = set(preload["allowed_invoke"])
    const_events = set(constants["allowed_events"])
    preload_events = set(preload["allowed_events"])

    # invoke 白名单不对齐
    invoke_only_const = const_invoke - preload_invoke
    invoke_only_preload = preload_invoke - const_invoke

    for ch in sorted(invoke_only_const):
        issues.append({
            "severity": "P0",
            "type": "whitelist_mismatch",
            "channel": ch,
            "detail": "在 ALLOWED_INVOKE_CHANNELS 中但 preload 未暴露",
            "message": f"频道 '{ch}' 在 constants.ts ALLOWED_INVOKE_CHANNELS 中，但 preload 的 allowedInvokeChannels 未包含",
        })

    for ch in sorted(invoke_only_preload):
        issues.append({
            "severity": "P1",
            "type": "whitelist_mismatch",
            "channel": ch,
            "detail": "在 preload 暴露但不在 ALLOWED_INVOKE_CHANNELS 中",
            "message": f"频道 '{ch}' 在 preload 的 allowedInvokeChannels 中，但不在 constants.ts ALLOWED_INVOKE_CHANNELS 中",
        })

    # event 白名单不对齐
    event_only_const = const_events - preload_events
    event_only_preload = preload_events - const_events

    for ch in sorted(event_only_const):
        issues.append({
            "severity": "P0",
            "type": "whitelist_mismatch",
            "channel": ch,
            "detail": "在 ALLOWED_EVENT_CHANNELS 中但 preload 未暴露",
            "message": f"事件频道 '{ch}' 在 constants.ts ALLOWED_EVENT_CHANNELS 中，但 preload 的 allowedEventChannels 未包含",
        })

    for ch in sorted(event_only_preload):
        issues.append({
            "severity": "P1",
            "type": "whitelist_mismatch",
            "channel": ch,
            "detail": "在 preload 暴露但不在 ALLOWED_EVENT_CHANNELS 中",
            "message": f"事件频道 '{ch}' 在 preload 的 allowedEventChannels 中，但不在 constants.ts ALLOWED_EVENT_CHANNELS 中",
        })

    return issues


def check_window_channels(preload: dict, handlers: dict) -> list[dict]:
    """检查 window:* 频道是否有 handler"""
    issues = []
    window_channels = [ch for ch in preload["allowed_send"] if ch.startswith("window:")]
    for ch in window_channels:
        if ch not in handlers:
            issues.append({
                "severity": "P1",
                "type": "window_channel_no_handler",
                "channel": ch,
                "message": f"window 控制频道 '{ch}' 在 preload 暴露，但无对应 handler（需确认是否为原生处理）",
            })
    return issues


# ── 主流程 ──

def main():
    print("[link_checker V1.0] 开始 IPC 链接完整性检测...")

    # 1. 数据提取
    constants = extract_constants()
    handlers = extract_handler_registrations(constants)
    preload = extract_preload_expose()

    total_channels = len(constants["ipc_channels"])
    total_handlers = len(handlers)
    print(f"[link_checker V1.0] IPC 频道: {total_channels} 定义, {total_handlers} 已注册 "
          f"({sum(1 for regs in handlers.values() for r in regs)} 个 handler 实例)")

    # 2. 运行四类检测
    all_issues = []
    all_issues.extend(check_channel_handler_pairing(constants, handlers))
    all_issues.extend(check_handler_preload_pairing(handlers, preload))
    all_issues.extend(check_whitelist_alignment(constants, preload))
    all_issues.extend(check_window_channels(preload, handlers))

    # 3. 分类统计
    p0 = [i for i in all_issues if i["severity"] == "P0"]
    p1 = [i for i in all_issues if i["severity"] == "P1"]

    # 4. 输出
    json_output = {
        "checker": "link_checker V1.0",
        "summary": {
            "total_channels_defined": total_channels,
            "total_handlers_registered": total_handlers,
            "handler_instances": sum(1 for regs in handlers.values() for r in regs),
            "preload_invoke_count": len(preload["allowed_invoke"]),
            "preload_send_count": len(preload["allowed_send"]),
            "preload_event_count": len(preload["allowed_events"]),
            "total_issues": len(all_issues),
            "p0": len(p0),
            "p1": len(p1),
        },
        "issues": all_issues,
        "handler_registry": {ch: [{"file": r["file"], "line": r["line"]} for r in regs]
                             for ch, regs in sorted(handlers.items())},
        "preload_exposed": {
            "invoke": sorted(preload["allowed_invoke"]),
            "send": sorted(preload["allowed_send"]),
            "events": sorted(preload["allowed_events"]),
        },
    }

    if "--json" in sys.argv:
        print(json.dumps(json_output, ensure_ascii=False, indent=2))
        return

    # 终端可读输出
    print(f"\n{'='*60}")
    print(f"  IPC 链接检测报告")
    print(f"  P0: {len(p0)}   P1: {len(p1)}   总计: {len(all_issues)}")
    print(f"{'='*60}")

    if p0:
        print(f"\n  ▸ P0 (阻断):")
        for i in p0:
            print(f"    [{i['type']}] {i['message']}")

    if p1:
        print(f"\n  ▸ P1 (建议):")
        for i in p1:
            print(f"    [{i['type']}] {i['message']}")

    if not all_issues:
        print("\n  全部 IPC 链路正常，无问题。")

    print(f"\n{'='*60}")

    # 保存 JSON 报告到 output 目录
    report_dir = PROJECT_ROOT / "docs" / "reports" / "link-check"
    report_dir.mkdir(parents=True, exist_ok=True)
    from datetime import date
    report_path = report_dir / f"link_check_{date.today().isoformat()}.json"
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(json_output, f, ensure_ascii=False, indent=2)
    print(f"  报告已保存: {report_path}")


if __name__ == "__main__":
    main()
