"""把仓库根的 0 字节污染文件逐项送入回收站（可恢复）。

★ 教训（本次踩坑）：清单文件里存的是文件名字面量，用 utf-8 读回来后
  `**` 里的 `*` 被读成私有区字符 \\uf02a ⇒ 名字与真实文件不匹配 ⇒ 全部被判
  「不在」而静默跳过（首跑 RECYCLED=0 FAILED=0 就是这个原因）。
  ⇒ 改为**直接 os.scandir 枚举真实名字**，不依赖任何清单字面内容。

纪律（见 skill windows-sandbox-file-deletion）：
1. 一次一个，绝不批量 —— SHFileOperationW 是全有或全无，坏项会拖垮整批。
2. 不信 rc，只读文件系统验证（scandir 判断名字是否还在）。
3. 失败项隔离，继续下一个，不中断整批。
4. 保留设备名（nul 等）已知无法删除，遇到即跳过并如实报告。
"""
import ctypes
import os
import sys
from ctypes import wintypes


class SHFILEOPSTRUCTW(ctypes.Structure):
    _fields_ = [
        ("hwnd", wintypes.HWND),
        ("wFunc", wintypes.UINT),
        ("pFrom", wintypes.LPCWSTR),
        ("pTo", wintypes.LPCWSTR),
        ("fFlags", ctypes.c_uint16),
        ("fAnyOperationsAborted", wintypes.BOOL),
        ("hNameMappings", ctypes.c_void_p),
        ("lpszProgressTitle", wintypes.LPCWSTR),
    ]


FO_DELETE = 3
FOF_ALLOWUNDO = 0x0040
FOF_NOCONFIRMATION = 0x0010
FOF_SILENT = 0x0004
FOF_NOERRORUI = 0x0400

shell32 = ctypes.windll.shell32
shell32.SHFileOperationW.argtypes = [ctypes.POINTER(SHFILEOPSTRUCTW)]
shell32.SHFileOperationW.restype = ctypes.c_int

RESERVED = {"nul", "con", "aux", "prn", *(f"com{i}" for i in range(1, 10)),
            *(f"lpt{i}" for i in range(1, 10))}


def recycle(path):
    """送单个路径进回收站。返回 (rc, 是否真删除)。"""
    real = os.path.abspath(path)
    op = SHFILEOPSTRUCTW()
    op.hwnd = 0
    op.wFunc = FO_DELETE
    op.pFrom = real + "\0\0"
    op.pTo = None
    op.fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI
    op.fAnyOperationsAborted = False
    op.hNameMappings = None
    op.lpszProgressTitle = None
    rc = shell32.SHFileOperationW(ctypes.byref(op))

    parent = os.path.dirname(real)
    name = os.path.basename(real)
    still_there = any(e.name == name for e in os.scandir(parent))
    return rc, (not still_there)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else r"d:\ai-teacher"
    # 直接枚举真实名字（不信任何清单字面量）
    targets = [
        e.name for e in os.scandir(root)
        if e.is_file() and e.stat().st_size == 0
    ]
    ok_list, fail_list, skipped = [], [], []
    for name in targets:
        stem = name.split(".")[0].lower()
        if stem in RESERVED:
            skipped.append((name, "保留设备名，已知无法删除"))
            continue
        try:
            rc, ok = recycle(os.path.join(root, name))
        except Exception as exc:
            fail_list.append((name, f"EXC {exc}"))
            continue
        (ok_list if ok else fail_list).append(
            (name, rc) if ok else (name, f"rc={rc} still-there")
        )

    print(f"TARGETS={len(targets)} RECYCLED={len(ok_list)} "
          f"FAILED={len(fail_list)} SKIPPED={len(skipped)}")
    for name, rc in ok_list:
        print(f"  OK    rc={rc} {name!r}")
    for name, why in fail_list:
        print(f"  FAIL  {why} {name!r}")
    for name, why in skipped:
        print(f"  SKIP  {why} {name!r}")


if __name__ == "__main__":
    main()