# -*- coding: utf-8 -*-
"""批次 K 服务层变异验证（V4.21）。

覆盖范围（ADR-C74 K-1 ~ K-5 实际迁出的方法）：
  K-2  applyPhaseMigration（217 行）             — 阶段迁移
  K-3  buildDriftHintContext（14 行）            — 声线漂移提示
  K-3  buildFactProtocolContext（48 行）          — 时序知识图谱协议块
  K-4  applyOutlineEntitiesFromContent（78 行）   — 大纲实体提取
  K-4  applyFactExtractionFromContent（122 行）   — 事实提取落库

按 V4.10：改源码做验证必须 try/finally 恢复 + 锚点缺失/不唯一显式报错。
按 V4.14：锚点必须唯一（多行块）。
按 V4.17：多行锚点按文件实际行尾自适应。
按 V4.18：跑 flutter test 清空会话代理 + 先做基线健康校验（不绿即 abort）。
按 V4.21：每个补测判据都要打分支级变异（全拦才叫真覆盖）。

用法：python tool/_verify_batch_k_coverage.py
"""
import io
import os
import shutil
import subprocess
import sys

FLUTTER = (
    shutil.which('flutter_env.bat')
    or r'C:\Users\NewName\flutter_env.bat'
    or shutil.which('flutter.bat')
    or shutil.which('flutter')
    or r'D:\flutter\bin\flutter.bat'
)

DC_SRC = 'lib/services/diagnosis_committer.dart'

# 5 个迁入方法对应受影响的测试文件
K2_TESTS = ['test/services/chat_service_phase_migration_test.dart']  # applyPhaseMigration
K3A_TESTS = ['test/services/chat_service_drift_injection_test.dart']  # buildDriftHintContext
K3B_TESTS = ['test/services/chat_service_fact_coverage_t2_4_test.dart']  # buildFactProtocolContext
K4A_TESTS = ['test/services/chat_service_outline_test.dart']  # applyOutlineEntitiesFromContent
K4B_TESTS = ['test/services/chat_service_fact_coverage_t2_4_test.dart']  # applyFactExtractionFromContent

# (ID, 源文件, 原文本, 变异文本, 判据说明, [测试文件])
MUTATIONS = [
    # ── K-2: applyPhaseMigration ──
    ('K2-V1 链式双跳防御', DC_SRC,
     "    // 批次1（C5/H3）：路径1（AI 驱动）成功迁移后，路径2（M4-A 自动）不得\n"
     "    // 再无条件继续，防止同轮链式双跳（如 P1→P2→P3）\n"
     "    var path1Migrated = false;",
     "    // 批次1（C5/H3）：路径1（AI 驱动）成功迁移后，路径2（M4-A 自动）不得\n"
     "    // 再无条件继续，防止同轮链式双跳（如 P1→P2→P3）\n"
     "    var path1Migrated = true;  // 变异：永远当作已迁移，跳过路径 1",
     '路径 1 已迁移标记恒为 true → 阻断真实 AI 驱动迁移（拦 #PM1 链式双跳防御）', K2_TESTS),
    ('K2-V2 路径2 早返回', DC_SRC,
     "    // 批次1（C5/H3）：路径1 已成功迁移 → 直接返回，路径2 仅当路径1 无有效迁移时评估\n"
     "    if (path1Migrated) return;",
     "    // 批次1（C5/H3）：路径1 已成功迁移 → 直接返回，路径2 仅当路径1 无有效迁移时评估\n"
     "    if (false) return;  // 变异：早返回永远不触发",
     '路径 2 自动迁移早返回失效 → 与路径 1 重复触发迁移（拦 #PM2 路径互斥）', K2_TESTS),
    ('K2-V3 M4-B 相邻校验', DC_SRC,
     "          if (validatePhaseTransition(\n"
     "            currentPhaseForValidation,\n"
     "            effectivePhase,\n"
     "          )) {",
     "          if (true) {  // 变异：跳过 M4-B 相邻阶段校验",
     'M4-B 相邻校验放行所有跳转 → 触发 P2→P0 等非法跳级（拦 #PM3 跳级校验）', K2_TESTS),

    # ── K-3: buildDriftHintContext ──
    ('K3-V1 偏差项拼接', DC_SRC,
     "        '偏差项：\\n- ${hints.join('\\n- ')}';",
     "        '偏差项：\\n- (已脱敏)';",
     'hints 拼接保留具体偏差项（拦 #DH1 偏差项具体内容透传）', K3A_TESTS),

    # ── K-3: buildFactProtocolContext ──
    ('K3-V2 输出顺序约束', DC_SRC,
     "        '  1. [YS_DIAGNOSIS] 症候块（若诊断要求）；\\n'\n"
     "        '  2. [YS_ENTITY] 实体记忆块；\\n'\n"
     "        '  3. [YS_FACT] 事实块（本条）；\\n'",
     "        '  1. [YS_FACT] 事实块（本条）；\\n'\n"  # 变异：顺序倒置且丢失前两条
     "        '  2. [YS_ENTITY] 实体记忆块；\\n'\n"
     "        '  3. [YS_DIAGNOSIS] 症候块（若诊断要求）；\\n'",
     '协议块输出顺序必须 [YS_DIAGNOSIS] → [YS_ENTITY] → [YS_FACT]（拦 #FP1 顺序硬约束）', K3B_TESTS),

    # ── K-4: applyOutlineEntitiesFromContent ──
    ('K4-V1 大纲服务空检查', DC_SRC,
     "    if (_ensureOutlineService() == null) return;",
     "    if (false) return;  // 变异：未装配也继续",
     '_ensureOutlineService 装配检查跳过 → 无 outlineRepo 也跑提取（拦 #OE1 装配静默跳过）', K4A_TESTS),
    ('K4-V2 章节类型过滤', DC_SRC,
     "    if (pRef?.refType != 'chapter') return;\n"
     "    try {\n"
     "      final outlineExtraction = parseOutlineExtraction(fullContent);",
     "    // 变异：章节类型过滤被注释\n"
     "    // if (pRef?.refType != 'chapter') return;\n"
     "    try {\n"
     "      final outlineExtraction = parseOutlineExtraction(fullContent);",
     '非章节主引用也跑大纲提取（拦 #OE2 refType 过滤）', K4A_TESTS),
    ('K4-V3 空提取静默跳过', DC_SRC,
     "      if (outlineExtraction == null || outlineExtraction.entities.isEmpty) {\n"
     "        return;\n"
     "      }",
     "      if (false) {\n"
     "        return;\n"
     "      }",
     '空提取也尝试落库 → 调用 applyOutlineExtraction 引爆 null 错误（拦 #OE3 空输入早返）', K4A_TESTS),

    # ── K-4: applyFactExtractionFromContent ──
    ('K4-V4 characterFactRepo 仓储检查', DC_SRC,
     "    // 三表仓储至少一个未装配 → 跳过\n"
     "    if (_characterFactRepo == null &&\n"
     "        _eventFactRepo == null &&\n"
     "        _subplotFactRepo == null) {\n"
     "      return;\n"
     "    }",
     "    // 变异：三表仓储检查替换为强制 return\n"
     "    if (true) {\n"
     "      return;\n"
     "    }",
     '即使三表仓储都装配，方法也直接 return（拦 #FE1 仓储放行）', K4B_TESTS),
    ('K4-V5 章节类型过滤', DC_SRC,
     "    if (pRef?.refType != 'chapter') return;\n"
     "\n"
     "    try {\n"
     "      final extraction = parseFactExtraction(fullContent);",
     "    // 变异：章节类型过滤被注释\n"
     "    // if (pRef?.refType != 'chapter') return;\n"
     "\n"
     "    try {\n"
     "      final extraction = parseFactExtraction(fullContent);",
     '非章节主引用也跑事实提取（拦 #FE2 refType 过滤）', K4B_TESTS),
    ('K4-V6 空提取静默跳过', DC_SRC,
     "      if (extraction == null || extraction.isEmpty) return;",
     "      if (false) return;  // 变异：空提取也继续尝试 upsert",
     '空提取也跑 upsert → 三表无数据循环（拦 #FE3 空输入早返）', K4B_TESTS),
]

PROCESS_TIMEOUT_MARK = '__PROCESS_TIMEOUT__'
TEST_TIMEOUT_SEC = 240


def adapt_eol(text, eol):
    """把锚点里的 \\n 换成文件实际行尾（V4.17）。"""
    return text.replace('\n', eol) if eol != '\n' else text


def detect_eol(content):
    return '\r\n' if content.count('\r\n') >= content.count('\n') / 2 else '\n'


def run_tests(test_files):
    env = dict(os.environ)
    for k in ('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy'):
        env.pop(k, None)
    env['NO_PROXY'] = 'localhost,127.0.0.1'
    proc = subprocess.Popen(
        [FLUTTER, 'test'] + test_files, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        out, err = proc.communicate(timeout=TEST_TIMEOUT_SEC)
        return (out or '') + (err or '')
    except subprocess.TimeoutExpired:
        if os.name == 'nt':
            subprocess.run(
                ['taskkill', '/F', '/T', '/PID', str(proc.pid)],
                capture_output=True,
            )
        else:
            proc.kill()
        out, err = proc.communicate()
        return ((out or '') + (err or '') + PROCESS_TIMEOUT_MARK)


def main():
    cache = {}
    for _, src, _, _, _, _ in MUTATIONS:
        if src not in cache:
            with io.open(src, encoding='utf-8', newline='') as f:
                cache[src] = f.read()

    print('=' * 70)
    print('批次 K 服务层变异验证（V4.21）— DiagnosisCommitter 拆出后真覆盖')
    print('拦住 = 补测判据真覆盖；漏网 = 虚覆盖或变异等价')
    print('=' * 70)

    base_cache = {}
    results = []
    try:
        for mid, src, old, new, why, tests in MUTATIONS:
            original = cache[src]
            eol = detect_eol(original)
            o_a, n_a = adapt_eol(old, eol), adapt_eol(new, eol)

            key = (src, tuple(tests))
            if key not in base_cache:
                out = run_tests(list(tests))
                base_cache[key] = (
                    'All tests passed' in out
                    and PROCESS_TIMEOUT_MARK not in out
                )
                if not base_cache[key]:
                    print('\n[基线异常] %s — ABORT' % src)
                    print(out[-500:])
            if not base_cache[key]:
                results.append((mid, why, '基线异常'))
                continue

            if o_a not in original:
                print('\n[%s] INJECT-FAILED：锚点缺失（%r）' % (mid, o_a[:70]))
                results.append((mid, why, '锚点异常'))
                continue
            if original.count(o_a) != 1:
                print('\n[%s] INJECT-FAILED：锚点不唯一（%d 次）'
                      % (mid, original.count(o_a)))
                results.append((mid, why, '锚点异常'))
                continue

            mutated = original.replace(o_a, n_a, 1)
            with io.open(src, 'w', encoding='utf-8', newline='') as f:
                f.write(mutated)
            try:
                out = run_tests(list(tests))
                caught = (
                    PROCESS_TIMEOUT_MARK in out
                    or any('[E]' in line for line in out.splitlines())
                )
                results.append((mid, why, '真覆盖' if caught else '虚覆盖'))
                print('  [%s] %s → %s' % (
                    mid, '变红/挂死（拦住）' if caught else '仍全绿（漏网）',
                    why))
            finally:
                with io.open(src, 'w', encoding='utf-8', newline='') as f:
                    f.write(original)
    finally:
        for src, content in cache.items():
            with io.open(src, 'w', encoding='utf-8', newline='') as f:
                f.write(content)

    same = all(io.open(s, encoding='utf-8', newline='').read() == c
               for s, c in cache.items())

    print('\n' + '=' * 70)
    print('源码恢复字节一致：%s' % same)
    print('-' * 70)
    n_real = sum(1 for _, _, v in results if v == '真覆盖')
    n_virt = sum(1 for _, _, v in results if v == '虚覆盖')
    n_bad = len(results) - n_real - n_virt
    for mid, why, v in results:
        print('  %-22s %-8s  %s' % (mid, v, why))
    print('-' * 70)
    print('合计 %d：拦住 %d / 漏网 %d / 异常 %d'
          % (len(results), n_real, n_virt, n_bad))
    if n_virt:
        print('\n漏网判据（新用例未锚定，先排查是否变异等价）：')
        for mid, why, v in results:
            if v == '虚覆盖':
                print('  - [%s] %s' % (mid, why))
    return 0 if (same and n_virt == 0 and n_bad == 0) else 1


if __name__ == '__main__':
    sys.exit(main())