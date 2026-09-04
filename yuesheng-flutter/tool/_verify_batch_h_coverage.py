# -*- coding: utf-8 -*-
"""批次 H 复检：补测判据的分支级变异验证。

背景（2026-09-04 交接 + 侦察修正）：批次 H 给四个判据真空点补测试——
  H-1  _updateDiagnosisSummary（top_syndromes 截断，无 active>2 场景）
  H-2  detectDeterioration（此前 test/ 零直接调用）
  H-3  checkTeacherConsistency（通过判定整个无判据，仅正路径断言）
  H-4  splitContent（`<=` 边界的 `=` 侧无锚）

本脚本对每个新判据打一个**判据级变异**，验证新用例真能拦（V4.21）。

按 V4.10：改源码做验证必须 try/finally 恢复 + 锚点缺失/不唯一显式报错。
按 V4.14：锚点必须唯一（多行块）。
按 V4.18：跑 flutter test 清空会话代理 + 先做基线健康校验（不绿即 abort）。
按 V4.17：多行锚点按文件实际行尾自适应。

**本批特殊点（H4-V1）**：splitContent 的 `<=`→`<` 变异会让测试以**同步
死循环**形式挂死（阻塞 event loop，flutter test 的用例级 Timeout 失效，
批次 H 侦察已实证）。故 run_tests 带 240s 进程级超时；超时（连子进程树
一并 taskkill /T）计为**拦截成功**——正常路径（非挂死变异）远快于该值。

用法：python tool/_verify_batch_h_coverage.py
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

REPO_SRC = 'lib/data/repositories/diagnosis_repository.dart'
TRAIN_SRC = 'lib/services/training_evaluator.dart'
TEACH_SRC = 'lib/services/teacher_validator.dart'
PROG_SRC = 'lib/services/progressive_diagnosis.dart'

REPO_TESTS = ['test/data/repositories/diagnosis_repository_test.dart']
TRAIN_TESTS = ['test/services/training_evaluator_test.dart']
TEACH_TESTS = ['test/services/teacher_consistency_test.dart']
PROG_TESTS = ['test/services/progressive_diagnosis_test.dart']

# (ID, 源文件, 原文本, 变异文本, 判据说明, [测试文件])
MUTATIONS = [
    # ── H-1: _updateDiagnosisSummary ──
    ('H1-V1 截断3', REPO_SRC,
     "final topSyndromes = active.take(3).map((p) {",
     "final topSyndromes = active.take(2).map((p) {",
     'active>2 时 top_syndromes 截前 3（拦 #T1）', REPO_TESTS),
    ('H1-V2 排序', REPO_SRC,
     "      const order = {'L3': 0, 'L2': 1, 'L1': 2};",
     "      const order = {'L1': 0, 'L2': 1, 'L3': 2};",
     'L3>L2>L1 降序（拦 #T1；6 空格缩进锚定行 601，区别于行 380 的 4 空格）',
     REPO_TESTS),
    ('H1-V3 status过滤', REPO_SRC,
     "final active = problems.where((p) => p.status == 'active').toList();",
     "final active = problems.where((p) => p.status == 'resolved').toList();",
     '仅 active 进 top（拦 #T1/#T2）', REPO_TESTS),

    # ── H-2: detectDeterioration ──
    ('H2-V1 门槛2', TRAIN_SRC,
     "if (_kSeverityOrder[currentSeverity]! > _kSeverityOrder[previousSeverity]! &&\n"
     "      consecutiveFailures >= 2) {",
     "if (_kSeverityOrder[currentSeverity]! > _kSeverityOrder[previousSeverity]! &&\n"
     "      consecutiveFailures >= 1) {",
     '连续失败门槛 >=2（摸底点名，拦 #D4）', TRAIN_TESTS),
    ('H2-V2 relapse条件', TRAIN_SRC,
     "if (wasResolvedToL1 && _kSeverityOrder[currentSeverity]! >= 2) {",
     "if (false && _kSeverityOrder[currentSeverity]! >= 2) {",
     'L1 缓解后再现 L2+ → relapse（拦 #D2/#D8）', TRAIN_TESTS),
    ('H2-V3 新并发3', TRAIN_SRC,
     "if (newConcurrentSyndromes >= 3) {",
     "if (newConcurrentSyndromes >= 4) {",
     '新症候门槛 3（拦 #D5）', TRAIN_TESTS),
    ('H2-V4 反弹', TRAIN_SRC,
     "if (reboundPattern) {",
     "if (false) {",
     '反弹模式 → rebound（拦 #D6）', TRAIN_TESTS),
    ('H2-V5 巩固7天', TRAIN_SRC,
     "if (gapDays > 7 && _kSeverityOrder[currentSeverity]! >= 2) {",
     "if (gapDays > 70 && _kSeverityOrder[currentSeverity]! >= 2) {",
     '间隔 >7 天门槛（拦 #D7）', TRAIN_TESTS),
    ('H2-V6 兜底null', TRAIN_SRC,
     "return const DeteriorationResult(signal: null, intervention: '');",
     "return const DeteriorationResult(signal: DeteriorationSignal.rebound, intervention: '');",
     '五路安全 → 无信号（拦 #D1/#D4）', TRAIN_TESTS),

    # ── H-3: checkTeacherConsistency ──
    ('H3-V1 通过判定', TEACH_SRC,
     "final hasError = violations.any((v) => v.severity == 'error');",
     "final hasError = violations.any((v) => v.severity == 'warning');",
     'error 级才不通过（摸底点名，拦 #C1-#C6）', TEACH_TESTS),
    ('H3-V2 task必填', TEACH_SRC,
     "if (result.trainingTask == null) {",
     "if (false) {",
     'guide/train 缺 task → error（拦 #C2）', TEACH_TESTS),
    ('H3-V3 判决词', TEACH_SRC,
     "if (verdictHits.isNotEmpty) {",
     "if (false) {",
     'natural_language 判决词 → error（拦 #C3/#C6）', TEACH_TESTS),
    ('H3-V4 症候泄漏', TEACH_SRC,
     "if (syndromeHits.isNotEmpty) {",
     "if (false) {",
     '症候 ID 泄漏 → error（拦 #C4）', TEACH_TESTS),
    ('H3-V5 warn规则', TEACH_SRC,
     "if (result.trainingTask != null) {",
     "if (false) {",
     'encourage/defer 带 task → warning（拦 #C1/#C6）', TEACH_TESTS),

    # ── H-4: splitContent ──
    # 注意：该变异使测试以**同步死循环**挂死（侦察实证），拦截形式为
    # 进程级超时（run_tests 240s 上限），非 [E] 断言失败。
    ('H4-V1 恰等边界', PROG_SRC,
     "if (content.length <= kDiagnosisChunkSize) {",
     "if (content.length < kDiagnosisChunkSize) {",
     '恰等于阈值 → 单块（拦 #5，挂死形式）', PROG_TESTS),

    # ── H-5: splitContent 单段原子性（死循环修复，ADR-C73 §2）──
    # 同样以**同步死循环**挂死形式拦截——把强制推进 startIndex 那行
    # 注释掉，还原批次 H 侦察时的死循环形态。run_tests 240s 兜底。
    ('H5-V1 单段原子', PROG_SRC,
     "if (endIndex == startIndex) {\n"
     "      chunks.add(paragraphs[startIndex]);\n"
     "      startIndex = startIndex + 1;\n"
     "      continue;\n"
     "    }",
     "if (endIndex == startIndex) {\n"
     "      chunks.add(paragraphs[startIndex]);\n"
     "      // startIndex = startIndex + 1;  // 变异：禁用推进\n"
     "      continue;\n"
     "    }",
     '首段即超阈值 → 整段成块 + 推进 startIndex（拦 #6/#7，挂死形式）',
     PROG_TESTS),
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
        # 同步死循环阻塞 event loop，用例级 Timeout 失效——杀进程树计超时
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
    print('批次 H 补测判据变异验证（V4.21）')
    print('拦住 = 新用例判据锚定成立；漏网 = 虚覆盖或变异等价，须排查')
    print('（H4-V1 预期以进程级超时形式拦截——同步死循环）')
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
        print('  %-18s %-8s  %s' % (mid, v, why))
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
