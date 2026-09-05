# -*- coding: utf-8 -*-
"""门禁 5（密钥扫描）的 Python 等价实现（scripts/check_secrets.sh 同逻辑）。"""
import pathlib
import re
import sys

LIB = pathlib.Path("lib")
pat = re.compile(
    r'(apiKey|api_key|secret|token|password|accessKey|sk-)[ \t]*[:=][ \t]*'
    r"['\"][A-Za-z0-9+/_.-]{12,}"
)
skip = re.compile(
    r'(test|_test|example|sample|mock|dummy|placeholder|your_|xxx|TODO|'
    r'llm_config_storage\.dart)'
)

issues = []
for p in LIB.rglob("*.dart"):
    if skip.search(str(p)):
        continue
    for i, line in enumerate(
        p.read_text(encoding="utf-8", errors="replace").splitlines(), 1
    ):
        if pat.search(line):
            issues.append("{}:{}: {}".format(p, i, line.strip()[:120]))

if issues:
    print("FAIL: suspected hardcoded secrets:")
    for x in issues:
        print("   ", x)
    sys.exit(1)
print("OK: no suspected hardcoded secrets in lib")
sys.exit(0)
