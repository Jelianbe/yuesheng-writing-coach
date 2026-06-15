#!/usr/bin/env python3
"""每日项目体检扫描脚本 V2.6 — 扫描 src/ 目录下 TypeScript/JavaScript 文件，生成健康报告 JSON。
覆盖 R-019/R-020/R-028/R-029 等 L1 核心规则的可自动化检查项。

更新记录:
  2026-06-15 V2.7: 新增 IPC 频道-处理器配对检查（constants.ts 定义 vs handler.ts 注册）、
                    catch {} 空块检查、Store action 注册完整性检查（*.actions.ts 导出 vs *.store.ts 注册）。
  2026-06-11 V2.6: 新增 createHandler 模式识别，修复 ipc_no_channel 假阳。
                    跳过 JSDoc 注释中的 import 匹配。
  2026-06-11 V2.5: 新增安全扫描(硬编码密钥)、export default 检测、非空断言检测、
                    内联样式统计、IPC handler try/catch 验证、循环依赖检测(madge)
                    规则版本引用更新为 V2.1
"""

import json
import re
import os
import subprocess
from pathlib import Path
from datetime import date
from collections import defaultdict

SRC_DIR = Path(r"D:\ai-teacher\yuesheng-writing-coach\src")
PROJECT_ROOT = Path(r"D:\ai-teacher\yuesheng-writing-coach")
REPORT_DIR = Path(r"D:\ai-teacher\yuesheng-writing-coach\docs\reports\daily-health")
TODAY = date.today().isoformat()

EXCLUDE_DIRS = {"node_modules", "dist", ".git", "__pycache__", ".vite", "test", "__tests__",
                "fixtures", "mocks", "wire-mock", "results", "assertions"}
EXTENSIONS = {".ts", ".tsx", ".js", ".jsx"}

# ── patterns ──
RE_ANY_TYPE = re.compile(r'\bany\b')
RE_TS_IGNORE = re.compile(r'@ts-ignore')
RE_AS_ASSERT = re.compile(r'\bas\s+\w+')
RE_CONSOLE = re.compile(r'\bconsole\.(log|warn|error|info|debug)\b')
RE_TODO = re.compile(r'\bTODO\b')
RE_FIXME = re.compile(r'\bFIXME\b')
RE_IMPORT = re.compile(r"""from\s+['"]([^'"]+)['"]""")
RE_REQUIRE = re.compile(r"""require\s*\(\s*['"]([^'"]+)['"]""")
RE_EXPORT_DEFAULT = re.compile(r'export\s+default\s+')
RE_EXPORT_NAMED = re.compile(r'export\s+(const|function|class|interface|type|enum)\s+(\w+)')
RE_IPC_REGISTER = re.compile(r'(?:ipcMain\.(?:handle|on)|createHandler)\s*\(')
RE_IPC_INVOKE = re.compile(r'ipcRenderer\.(invoke|send)\s*\(')
RE_DB_TRANSACTION = re.compile(r'(transaction|exec|prepare|run)\s*\(')
RE_FUNCTION = re.compile(r'(?:function|const)\s+(\w+)\s*[=(]')

# ── V2.5 新增 patterns ──
# R-029 安全扫描
RE_HARDCODED_KEY = re.compile(
    r'(api[_-]?key|api[_-]?secret|secret[_-]?key|access[_-]?token|'
    r'auth[_-]?token|bearer|password|passwd)\s*[:=]\s*[\'"][^\'"]{8,}[\'"]',
    re.IGNORECASE
)
RE_DOTENV_FILE = re.compile(r'\.env\b')
RE_CONSOLE_SENSITIVE = re.compile(
    r'console\.(log|warn|error)\s*\(\s*.*(api[_-]?key|token|secret|password)',
    re.IGNORECASE
)

# R-019 禁止项
RE_NONNULL_ASSERT = re.compile(r'\w+!')  # 非空断言 x!
RE_INLINE_STYLE = re.compile(r'style=\{\{')  # 内联样式 style={{

# R-019 IPC 通道命名
RE_IPC_CHANNEL = re.compile(r"""['"]([a-zA-Z_]+:[a-zA-Z_]+)['"]\s*[,\)]""")

# R-028 IPC handler try/catch 检测
RE_IPC_HANDLER_BODY = re.compile(
    r'ipcMain\.(handle|on)\s*\(\s*[\'"][^\'"]+[\'"]\s*,',
)

# ── V2.7 新增 patterns ──
# catch {} 空块检测
RE_EMPTY_CATCH = re.compile(
    r'catch\s*(?:\([^)]*\))?\s*\{\s*(?://[^\n]*)?\s*\}',
    re.MULTILINE
)

# Store action 注册: *.actions.ts 导出的 create*Action
RE_ACTION_CREATOR = re.compile(
    r'export\s+(?:const|function)\s+(create\w+Action)',
    re.MULTILINE
)

# IPC handler 注册模式: IPC_CHANNELS.XXX
RE_HANDLER_CHANNEL_REF = re.compile(r'IPC_CHANNELS\.(\w+)')

# ── path aliases ──
PATH_ALIASES = {
    "@": SRC_DIR,
    "@main": SRC_DIR / "main",
    "@renderer": SRC_DIR / "renderer",
    "@shared": SRC_DIR / "shared",
    "@preload": SRC_DIR / "preload",
}

# ── V2.7: 导入边界规则 ──
# 定义每个目录允许的导入目标（仅检查跨 src/X→src/Y 方向）
IMPORT_BOUNDARY_RULES = {
    "main":     ("main", "shared"),       # main 可以导入 main 和 shared
    "renderer": ("renderer", "shared"),   # renderer 可以导入 renderer 和 shared
    "shared":   ("shared",),              # shared 只能导入 shared
    "preload":  ("preload", "shared"),    # preload 可以导入 preload 和 shared
}


def _try_resolve_extensions(resolved: Path) -> bool:
    resolved_str = str(resolved)
    if resolved.exists():
        return True
    for ext in EXTENSIONS:
        if Path(resolved_str + ext).exists():
            return True
    if resolved.is_dir():
        if (resolved / "index.ts").exists():
            return True
    return False


def resolve_import(import_path: str, current_file: Path) -> bool:
    if import_path.startswith("."):
        resolved = (current_file.parent / import_path).resolve()
        return _try_resolve_extensions(resolved)
    elif import_path.startswith("@"):
        for alias, base in PATH_ALIASES.items():
            if import_path == alias or import_path.startswith(alias + "/"):
                suffix = import_path[len(alias):].lstrip("/")
                resolved = base / suffix
                return _try_resolve_extensions(resolved)
        return True
    else:
        return True


def should_exclude(parts: tuple) -> bool:
    return bool(set(parts) & EXCLUDE_DIRS)


def check_ipc_handler_trycatch(content: str, file_path: Path) -> list[dict]:
    """R-028: 检查 IPC handler 是否有 try/catch 保护"""
    issues = []
    # 找到所有 ipcMain.handle/on 调用
    for match in re.finditer(r'ipcMain\.(handle|on)\s*\(\s*[\'"]([^\'"]+)[\'"]', content):
        channel = match.group(2)
        # 从匹配位置向后搜索 800 个字符，检查是否有 try/catch
        tail = content[match.start():match.start() + 1000]
        if 'try' not in tail or 'catch' not in tail:
            # 计算行号
            line_num = content[:match.start()].count('\n') + 1
            issues.append({
                "severity": "P0",
                "file": str(file_path.relative_to(SRC_DIR.parent)),
                "path": str(file_path),
                "line": line_num,
                "type": "ipc_no_trycatch",
                "message": f"IPC handler '{channel}' 缺少 try/catch 保护 (R-028/R-019)",
            })
    return issues


def check_security(content: str, file_path: Path) -> list[dict]:
    """R-029: 安全扫描"""
    issues = []
    rel = str(file_path.relative_to(SRC_DIR.parent))

    for match in RE_HARDCODED_KEY.finditer(content):
        line_num = content[:match.start()].count('\n') + 1
        issues.append({
            "severity": "P0",
            "file": rel,
            "path": str(file_path),
            "line": line_num,
            "type": "hardcoded_credential",
            "message": f"疑似硬编码凭据: {match.group(0)[:60]}... (R-029 零容忍)",
        })

    for match in RE_CONSOLE_SENSITIVE.finditer(content):
        line_num = content[:match.start()].count('\n') + 1
        issues.append({
            "severity": "P0",
            "file": rel,
            "path": str(file_path),
            "line": line_num,
            "type": "console_leak",
            "message": "console 输出疑似包含敏感信息 (R-029)",
        })

    return issues


def check_empty_catch(content: str, file_path: Path) -> list[dict]:
    """R-028: 检查空的 catch 块（吞异常无日志）"""
    issues = []
    rel = str(file_path.relative_to(SRC_DIR.parent))
    for match in RE_EMPTY_CATCH.finditer(content):
        line_num = content[:match.start()].count('\n') + 1
        issues.append({
            "severity": "P1",
            "file": rel,
            "path": str(file_path),
            "line": line_num,
            "type": "empty_catch",
            "message": "catch 块为空，异常被静默吞没 (R-028)",
        })
    return issues


def check_import_boundary(content: str, file_path: Path) -> list[dict]:
    """检查导入是否跨越架构边界（renderer→main / shared→main 等）"""
    issues = []
    rel = str(file_path.relative_to(SRC_DIR.parent))

    # 确定当前文件所在层
    src_rel = str(file_path.relative_to(SRC_DIR))
    parts = src_rel.replace("\\", "/").split("/")
    if not parts:
        return issues
    current_layer = parts[0]
    if current_layer not in IMPORT_BOUNDARY_RULES:
        return issues  # test/ 等目录不做检查
    allowed = IMPORT_BOUNDARY_RULES[current_layer]

    for m in RE_IMPORT.finditer(content):
        imp = m.group(1)
        # 仅检查相对路径（跳过包名、路径别名）
        if not imp.startswith("."):
            continue
        resolved = (file_path.parent / imp).resolve()
        try:
            rel_resolved = str(resolved.relative_to(SRC_DIR)).replace("\\", "/")
        except ValueError:
            continue  # 解析到 src/ 外的路径跳过
        imp_parts = rel_resolved.split("/")
        if not imp_parts:
            continue
        target_layer = imp_parts[0]
        if target_layer not in IMPORT_BOUNDARY_RULES:
            continue

        if target_layer not in allowed:
            line_num = content[:m.start()].count('\n') + 1
            issues.append({
                "severity": "P1",
                "file": rel,
                "path": str(file_path),
                "line": line_num,
                "type": "import_boundary_violation",
                "message": f"架构边界违规: {current_layer} 导入了 {target_layer}（{imp}），允许导入: {allowed}",
            })
    return issues


def check_import_boundaries_all() -> list[dict]:
    """全量扫描所有源文件的导入边界"""
    all_issues = []
    for root, dirs, files in os.walk(SRC_DIR):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for fname in files:
            if Path(fname).suffix not in EXTENSIONS:
                continue
            fp = Path(root) / fname
            try:
                content = fp.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                continue
            all_issues.extend(check_import_boundary(content, fp))
    return all_issues


# ── V2.7: 跨文件检查（在 main() 中调用）──

# ── V2.7: 单向推送频道豁免列表 ──
# 这些频道由主进程主动推送给渲染进程（webContents.send），不需要 handler
ONE_WAY_PUSH_CHANNELS = {
    'chat:stream:data',
    'chat:stream:end',
    'chat:tool:executing',
    'diagnosis:update',
}

def check_ipc_channel_pairing() -> list[dict]:
    """检查 constants.ts 中定义的 IPC 频道是否都在 handler.ts 中有对应 createHandler 注册"""
    issues = []
    constants_path = SRC_DIR / "shared" / "constants.ts"
    if not constants_path.exists():
        return issues

    const_text = constants_path.read_text(encoding="utf-8", errors="ignore")

    # 通过括号计数提取 IPC_CHANNELS 对象体（处理嵌套对象）
    idx = const_text.find("export const IPC_CHANNELS")
    if idx == -1:
        return issues
    start_brace = const_text.index("{", idx)
    depth = 0
    end_brace = start_brace
    for i in range(start_brace, len(const_text)):
        if const_text[i] == "{":
            depth += 1
        elif const_text[i] == "}":
            depth -= 1
            if depth == 0:
                end_brace = i + 1
                break
    ipc_body = const_text[start_brace:end_brace]

    channel_map: dict[str, str] = {}
    for m in re.finditer(r"(\w+):\s*'([\w:]+)'", ipc_body):
        channel_value = m.group(2)
        if ':' in channel_value:
            channel_map[m.group(1)] = channel_value

    # 收集所有 handler.ts 中引用的 IPC_CHANNELS.XXX
    covered_constants: set[str] = set()
    for root, dirs, files in os.walk(SRC_DIR / "main"):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for fname in files:
            if fname.endswith(".handler.ts"):
                text = Path(root, fname).read_text(encoding="utf-8", errors="ignore")
                for m in RE_HANDLER_CHANNEL_REF.finditer(text):
                    covered_constants.add(m.group(1))

    # 检查未覆盖的频道（排除单向推送频道）
    rel = str(constants_path.relative_to(SRC_DIR.parent))
    for const_name, channel_value in channel_map.items():
        if const_name not in covered_constants and channel_value not in ONE_WAY_PUSH_CHANNELS:
            issues.append({
                "severity": "P0",
                "file": rel,
                "path": str(constants_path),
                "line": 0,
                "type": "ipc_channel_no_handler",
                "message": f"IPC 频道 '{channel_value}' (const {const_name}) 未在任何 handler.ts 中注册 createHandler",
            })

    return issues


def check_store_action_registration() -> list[dict]:
    """检查 *.actions.ts 导出的 create*Action 是否在对应 *.store.ts 中有注册"""
    issues = []
    for root, dirs, files in os.walk(SRC_DIR):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for fname in files:
            if not fname.endswith(".actions.ts"):
                continue
            afp = Path(root) / fname
            atext = afp.read_text(encoding="utf-8", errors="ignore")
            creators = RE_ACTION_CREATOR.findall(atext)
            if not creators:
                continue

            # 找对应的 store 文件
            store_fp = Path(root) / fname.replace(".actions.ts", ".store.ts")
            if not store_fp.exists():
                # 尝试在相同目录下寻找引用了该 actions 文件的 store
                for sf in files:
                    if sf.endswith(".store.ts"):
                        s_text = Path(root, sf).read_text(encoding="utf-8", errors="ignore")
                        base_short = afp.stem.replace(".actions", "")
                        if base_short in s_text:
                            store_fp = Path(root) / sf
                            break

            if not store_fp.exists():
                issues.append({
                    "severity": "P1",
                    "file": str(afp.relative_to(SRC_DIR.parent)),
                    "path": str(afp),
                    "line": 0,
                    "type": "store_missing",
                    "message": f"*.actions.ts 导出了 {len(creators)} 个 create*Action，但未找到对应 *.store.ts",
                })
                continue

            stext = store_fp.read_text(encoding="utf-8", errors="ignore")
            unregistered = [c for c in creators if c not in stext]
            for creator in unregistered:
                issues.append({
                    "severity": "P1",
                    "file": str(afp.relative_to(SRC_DIR.parent)),
                    "path": str(afp),
                    "line": 0,
                    "type": "action_unregistered",
                    "message": f"Action creator '{creator}' 在 {afp.name} 中导出，但未在 {store_fp.name} 的 create() 中注册",
                })

    return issues


def check_di_injection_completeness() -> list[dict]:
    """检查 service-config.ts 中所有 c.get() 调用的服务名都有对应的 container.register() 注册"""
    issues = []
    config_path = SRC_DIR / "main" / "core" / "service-config.ts"
    if not config_path.exists():
        return issues

    text = config_path.read_text(encoding="utf-8", errors="ignore")
    rel = str(config_path.relative_to(SRC_DIR.parent))

    # 收集所有 register 的服务名
    registered_names: set[str] = set()
    for m in re.finditer(r"""container\.register\s*\(\s*['"](\w+)['"]""", text):
        registered_names.add(m.group(1))

    # 收集所有 c.get() 引用的服务名
    requested_names: set[str] = set()
    for m in re.finditer(r"""c\.get\s*\(\s*['"](\w+)['"]""", text):
        requested_names.add(m.group(1))

    # 找出未注册的服务
    unregistered = requested_names - registered_names
    for name in sorted(unregistered):
        for m in re.finditer(rf"""c\.get\s*\(\s*['\"]{name}['\"]""", text):
            line_num = text[:m.start()].count('\n') + 1
            issues.append({
                "severity": "P0",
                "file": rel,
                "path": str(config_path),
                "line": line_num,
                "type": "di_unregistered_dependency",
                "message": f"DI 容器中 c.get('{name}') 未找到对应的 container.register('{name}', ...) 注册",
            })
            break

    # 反向检查：已注册但未被引用的（可能是死代码）
    unused = registered_names - requested_names
    for name in sorted(unused):
        for m in re.finditer(rf"""container\.register\s*\(\s*['\"]{name}['\"]""", text):
            line_num = text[:m.start()].count('\n') + 1
            issues.append({
                "severity": "P1",
                "file": rel,
                "path": str(config_path),
                "line": line_num,
                "type": "di_unused_registration",
                "message": f"DI 容器中 container.register('{name}', ...) 注册后未被任何 c.get('{name}') 引用（可能为死代码）",
            })
            break

    return issues


def scan_file(file_path: Path) -> dict | None:
    parts = tuple(file_path.parts)
    if should_exclude(parts):
        return None

    try:
        content = file_path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return None

    lines = content.split("\n")
    line_count = len(lines)
    rel = str(file_path.relative_to(SRC_DIR.parent))

    # ── 基础统计 ──
    any_count = len(RE_ANY_TYPE.findall(content))
    ts_ignore_count = len(RE_TS_IGNORE.findall(content))
    as_assert_count = len(RE_AS_ASSERT.findall(content))
    console_count = len(RE_CONSOLE.findall(content))
    todo_count = len(RE_TODO.findall(content))
    fixme_count = len(RE_FIXME.findall(content))
    export_default_count = len(RE_EXPORT_DEFAULT.findall(content))
    nonnull_assert_count = len(RE_NONNULL_ASSERT.findall(content))
    inline_style_count = len(RE_INLINE_STYLE.findall(content))

    # import 检查
    imports = RE_IMPORT.findall(content) + RE_REQUIRE.findall(content)
    broken_imports = []
    for imp in imports:
        if not resolve_import(imp, file_path):
            broken_imports.append(imp)

    exported_functions = RE_EXPORT_NAMED.findall(content)

    # IPC / DB 专项
    has_ipc = bool(RE_IPC_REGISTER.search(content)) or bool(RE_IPC_INVOKE.search(content))
    has_db = bool(RE_DB_TRANSACTION.search(content)) and "sqlite" in content.lower()
    ipc_channel_names = [m.group(1) for m in RE_IPC_CHANNEL.finditer(content)
                         if ':' in m.group(1)]

    # ── V2.5: IPC handler try/catch 检查 ──
    ipc_trycatch_issues = []
    if "ipcMain" in content:
        ipc_trycatch_issues = check_ipc_handler_trycatch(content, file_path)

    # ── V2.5: 安全扫描 ──
    security_issues = check_security(content, file_path)

    # ── V2.7: 空 catch 检查 ──
    empty_catch_issues = check_empty_catch(content, file_path)

    return {
        "file": str(file_path),
        "relative": rel,
        "lines": line_count,
        "any_count": any_count,
        "ts_ignore_count": ts_ignore_count,
        "as_assert_count": as_assert_count,
        "console_count": console_count,
        "todo_count": todo_count,
        "fixme_count": fixme_count,
        "export_default_count": export_default_count,
        "nonnull_assert_count": nonnull_assert_count,
        "inline_style_count": inline_style_count,
        "broken_imports": broken_imports,
        "exported_functions": len(exported_functions),
        "has_ipc": has_ipc,
        "has_db": has_db,
        "is_ipc_dir": "ipc" in parts,
        "is_db_dir": "db" in parts,
        "ipc_channels": ipc_channel_names,
        "ipc_trycatch_issues": ipc_trycatch_issues,
        "security_issues": security_issues,
        "empty_catch_issues": empty_catch_issues,
    }


def build_stats(results: list[dict]) -> dict:
    return {
        "date": TODAY,
        "total_files": len(results),
        "total_lines": sum(r["lines"] for r in results),
        "total_any": sum(r["any_count"] for r in results),
        "total_ts_ignore": sum(r["ts_ignore_count"] for r in results),
        "total_as_assert": sum(r["as_assert_count"] for r in results),
        "total_console": sum(r["console_count"] for r in results),
        "total_todo": sum(r["todo_count"] for r in results),
        "total_fixme": sum(r["fixme_count"] for r in results),
        "total_export_default": sum(r["export_default_count"] for r in results),
        "total_nonnull_assert": sum(r["nonnull_assert_count"] for r in results),
        "total_inline_style": sum(r["inline_style_count"] for r in results),
        "total_broken_imports": sum(len(r["broken_imports"]) for r in results),
        "total_security_issues": sum(len(r["security_issues"]) for r in results),
        "total_ipc_trycatch_issues": sum(len(r["ipc_trycatch_issues"]) for r in results),
        "total_empty_catch": sum(len(r["empty_catch_issues"]) for r in results),
        "large_files_count": len([r for r in results if r["lines"] > 300]),
        "ts_ignore_files_count": len([r for r in results if r["ts_ignore_count"] > 0]),
        "ipc_files_count": len([r for r in results if r["has_ipc"] or r["is_ipc_dir"]]),
        "db_files_count": len([r for r in results if r["has_db"] or r["is_db_dir"]]),
    }


def run_circular_check() -> dict:
    """R-020: 循环依赖检测（调用 madge）"""
    result = {"success": False, "circular_deps": [], "error": None}
    try:
        proc = subprocess.run(
            ["npx", "madge", "--circular", "--extensions", "ts,tsx", "src/"],
            cwd=str(PROJECT_ROOT),
            capture_output=True, text=True, timeout=30
        )
        output = proc.stdout.strip()
        if proc.returncode == 0 and output:
            # madge 找到循环依赖时返回非 0，正常时 stdout 为空字符串
            # 但某些版本行为不同，解析输出
            if "No circular dependencies found" in output or output == "":
                result["success"] = True
            elif "✖" in output or "circular" in output.lower():
                result["circular_deps"] = [line.strip() for line in output.split("\n") if line.strip() and "→" in line]
                result["success"] = False
            else:
                result["success"] = True
        elif proc.returncode != 0 and output:
            # madge 发现循环依赖时返回非 0
            result["circular_deps"] = [line.strip() for line in output.split("\n") if line.strip()]
            result["success"] = False
        else:
            result["success"] = True
    except FileNotFoundError:
        result["error"] = "madge 未安装，跳过循环依赖检测 (npm install -D madge)"
    except subprocess.TimeoutExpired:
        result["error"] = "madge 检测超时 (>30s)"
    except Exception as e:
        result["error"] = str(e)
    return result


def main():
    print(f"[scan V2.7] 开始扫描 {SRC_DIR} ...")

    results = []
    for root, dirs, files in os.walk(SRC_DIR):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for fname in files:
            if Path(fname).suffix in EXTENSIONS:
                file_path = Path(root) / fname
                r = scan_file(file_path)
                if r:
                    results.append(r)

    stats = build_stats(results)

    # 大文件 Top 10
    large_files = sorted(
        [r for r in results if r["lines"] > 300],
        key=lambda r: r["lines"], reverse=True
    )[:10]

    # any 重度 Top 10
    any_heavy = sorted(
        [r for r in results if r["any_count"] > 5],
        key=lambda r: r["any_count"], reverse=True
    )[:10]

    # export default 文件列表
    export_default_files = sorted(
        [r for r in results if r["export_default_count"] > 0],
        key=lambda r: r["export_default_count"], reverse=True
    )

    # 非空断言 Top 10
    nonnull_heavy = sorted(
        [r for r in results if r["nonnull_assert_count"] > 0],
        key=lambda r: r["nonnull_assert_count"], reverse=True
    )[:10]

    # 内联样式 Top 10
    inline_style_heavy = sorted(
        [r for r in results if r["inline_style_count"] > 0],
        key=lambda r: r["inline_style_count"], reverse=True
    )[:10]

    # 循环依赖检测
    circular_result = run_circular_check()

    # ── 收集所有 P0/P1 问题 ──
    issues = []

    # broken imports
    for r in results:
        for bi in r["broken_imports"]:
            issues.append({
                "severity": "P0",
                "file": r["relative"], "path": r["file"], "line": 1,
                "type": "broken_import",
                "message": f"未解析的 import: {bi}",
            })

    # IPC/DB 目录文件缺少对应注册
    for r in results:
        rel_path = Path(r["file"])
        if r["is_ipc_dir"] and not r["has_ipc"] and "utils" not in rel_path.parts:
            issues.append({
                "severity": "P0",
                "file": r["relative"], "path": r["file"], "line": 1,
                "type": "ipc_no_channel",
                "message": "IPC 目录文件未检测到 ipcMain.handle/on 注册",
            })
        if r["is_db_dir"] and not r["has_db"]:
            issues.append({
                "severity": "P1",
                "file": r["relative"], "path": r["file"], "line": 1,
                "type": "db_no_transaction",
                "message": "DB 目录文件未检测到事务操作",
            })

    # IPC handler 缺少 try/catch (V2.5)
    for r in results:
        for issue in r["ipc_trycatch_issues"]:
            issues.append(issue)

    # 安全扫描 (V2.5)
    for r in results:
        for issue in r["security_issues"]:
            issues.append(issue)

    # 空 catch 检查 (V2.7)
    for r in results:
        for issue in r["empty_catch_issues"]:
            issues.append(issue)

    # ── V2.7: 跨文件检查 ──
    # IPC 频道-处理器配对
    ipc_pairing_issues = check_ipc_channel_pairing()
    issues.extend(ipc_pairing_issues)

    # Store action 注册完整性
    store_action_issues = check_store_action_registration()
    issues.extend(store_action_issues)

    # 导入边界检查 (V2.7)
    boundary_issues = check_import_boundaries_all()
    issues.extend(boundary_issues)

    # DI 注入完整性 (V2.7)
    di_issues = check_di_injection_completeness()
    issues.extend(di_issues)

    # 硬编码密钥 → 汇总单独计数
    hardcoded_cred_count = sum(
        1 for i in issues if i["type"] == "hardcoded_credential"
    )

    # 循环依赖
    if circular_result["circular_deps"]:
        for dep in circular_result["circular_deps"]:
            issues.append({
                "severity": "P0",
                "file": "N/A",
                "path": "N/A",
                "line": 0,
                "type": "circular_dependency",
                "message": f"循环依赖: {dep}",
            })

    # ── 构建输出 ──
    output = {
        "scan_date": TODAY,
        "scan_version": "V2.7",
        "project_root": str(SRC_DIR.parent),
        "stats": stats,
        "large_files_top10": [
            {"file": r["relative"], "path": r["file"], "lines": r["lines"]}
            for r in large_files
        ],
        "any_heavy_top10": [
            {"file": r["relative"], "path": r["file"], "any_count": r["any_count"]}
            for r in any_heavy
        ],
        "ts_ignore_files": [
            {"file": r["relative"], "path": r["file"], "count": r["ts_ignore_count"]}
            for r in results if r["ts_ignore_count"] > 0
        ],
        "export_default_files": [
            {"file": r["relative"], "path": r["file"], "count": r["export_default_count"]}
            for r in export_default_files
        ],
        "nonnull_assert_top10": [
            {"file": r["relative"], "path": r["file"], "count": r["nonnull_assert_count"]}
            for r in nonnull_heavy
        ],
        "inline_style_top10": [
            {"file": r["relative"], "path": r["file"], "count": r["inline_style_count"]}
            for r in inline_style_heavy
        ],
        "ipc_files": [
            {"file": r["relative"], "path": r["file"], "channels": r["ipc_channels"]}
            for r in results if r["is_ipc_dir"]
        ],
        "db_files": [
            {"file": r["relative"], "path": r["file"]}
            for r in results if r["is_db_dir"]
        ],
        "circular_deps": {
            "checked": circular_result["success"] or bool(circular_result["circular_deps"]),
            "error": circular_result["error"],
            "dependencies": circular_result["circular_deps"],
        },
        "security": {
            "hardcoded_credentials": hardcoded_cred_count,
            "total_issues": sum(
                1 for i in issues if i["type"] in ("hardcoded_credential", "console_leak")
            ),
        },
        "ipc_channel_pairing": {
            "uncovered_channels": len(ipc_pairing_issues),
            "details": ipc_pairing_issues,
        },
        "store_action_registration": {
            "unregistered_actions": len(store_action_issues),
            "details": store_action_issues,
        },
        "empty_catch_blocks": {
            "total": stats["total_empty_catch"],
            "files": [{"file": r["relative"], "path": r["file"], "count": len(r["empty_catch_issues"])}
                      for r in results if r["empty_catch_issues"]],
        },
        "import_boundary": {
            "violations": len(boundary_issues),
            "details": boundary_issues,
        },
        "di_injection": {
            "unregistered": sum(1 for i in di_issues if i["type"] == "di_unregistered_dependency"),
            "unused": sum(1 for i in di_issues if i["type"] == "di_unused_registration"),
            "details": di_issues,
        },
        "issues": issues,
    }

    # 写入 JSON
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    json_path = REPORT_DIR / f"scan_{TODAY}.json"
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    # ── 控制台摘要 ──
    print(f"[scan V2.7] 扫描完成: {stats['total_files']} 文件, {stats['total_lines']} 行")
    print(f"[scan V2.7] any={stats['total_any']}  ts-ignore={stats['total_ts_ignore']}  "
          f"as={stats['total_as_assert']}  console={stats['total_console']}")
    print(f"[scan V2.7] export-default={stats['total_export_default']}  "
          f"nonnull-assert={stats['total_nonnull_assert']}  "
          f"inline-style={stats['total_inline_style']}")
    print(f"[scan V2.7] 安全: 硬编码凭据={hardcoded_cred_count}  "
          f"IPC-trycatch缺失={stats['total_ipc_trycatch_issues']}")
    print(f"[scan V2.7] 循环依赖: {'发现 ' + str(len(circular_result['circular_deps'])) + ' 处' if circular_result['circular_deps'] else '未发现' if circular_result['success'] else '跳过 (' + (circular_result['error'] or '') + ')'}")
    print(f"[scan V2.7] V2.7 新增: 空catch={stats['total_empty_catch']}  "
          f"IPC频道未覆盖={len(ipc_pairing_issues)}  "
          f"action未注册={len(store_action_issues)}")
    print(f"[scan V2.7] V2.7 新增: 导入边界违规={len(boundary_issues)}  "
          f"DI注入(P0)={sum(1 for i in di_issues if i['severity']=='P0')}  "
          f"DI死代码(P1)={sum(1 for i in di_issues if i['severity']=='P1')}")
    print(f"[scan V2.7] 总问题: {len(issues)} (P0={sum(1 for i in issues if i['severity']=='P0')} "
          f"P1={sum(1 for i in issues if i['severity']=='P1')})")
    print(f"[scan V2.7] 报告: {json_path}")


if __name__ == "__main__":
    main()
