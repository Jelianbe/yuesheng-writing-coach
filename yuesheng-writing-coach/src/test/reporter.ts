/**
 * 测试报告自动生成系统
 *
 * 运行所有测试并生成格式化的 JSON/HTML 报告
 * 支持：完整测试执行、覆盖率汇总、模块级分析、失败的详细追踪
 *
 * 用法：
 *   npx vitest run --reporter=verbose
 *   npx tsx src/test/reporter.ts  (生成独立报告文件)
 */

import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

interface TestResult {
  name: string;
  module: string;
  status: 'passed' | 'failed' | 'skipped';
  duration: number;
  error?: string;
}

interface ModuleReport {
  moduleId: string;
  moduleName: string;
  total: number;
  passed: number;
  failed: number;
  skipped: number;
  passRate: number;
  tests: TestResult[];
}

interface TestSummary {
  timestamp: string;
  total: number;
  passed: number;
  failed: number;
  skipped: number;
  passRate: number;
  duration: string;
  modules: Record<string, Omit<ModuleReport, 'tests'>>;
  failedTests: { name: string; error: string; module: string }[];
}

/** 模块划分映射：文件路径 → 模块 ID */
const MODULE_MAP: [RegExp, string, string][] = [
  [/diagnosis\.handler/, 'M-DIAG', '诊断引擎'],
  [/teaching-state/, 'M-TEACH', '教学状态机'],
  [/session/, 'M-SESS', '会话管理'],
  [/chat/, 'M-CHAT', '聊天引擎'],
  [/config/, 'M-CONF', '配置管理'],
  [/evidence/, 'M-EVID', '证据管理'],
  [/author-profile/, 'M-PROF', '作者画像'],
  [/diagnosis-parser/, 'M-DIAG', '诊断引擎'],
  [/merge-diagnosis/, 'M-UNIT', '症候合并'],
  [/AppSidebar/, 'M-UI', '前端组件'],
  [/App/, 'M-UI', '前端组件'],
];

/** 根据文件名判断所属模块 */
function detectModule(filePath: string): [string, string] {
  for (const [pattern, id, name] of MODULE_MAP) {
    if (pattern.test(filePath)) return [id, name];
  }
  return ['M-OTHER', '其他'];
}

/** 解析 vitest 的 verbose 输出生成结构化报告 */
function parseVitestOutput(output: string): TestResult[] {
  const results: TestResult[] = [];
  const lines = output.split('\n');
  let currentFile = '';

  for (const line of lines) {
    // 匹配文件路径行:  ✓ src/main/services/__tests__/evidence.service.test.ts (12ms)
    const fileMatch = line.match(/^(✓|×|✗)\s+(.+?\.test\.ts)\s+\((\d+)ms\)/);
    if (fileMatch) {
      currentFile = fileMatch[2].replace(/\\/g, '/');
      continue;
    }

    // 匹配测试用例行:     ✓ 测试名称 (12ms)
    const testMatch = line.match(/^\s+(✓|×)\s+(.+?)\s+\((\d+)ms\)/);
    if (testMatch && currentFile) {
      const status = testMatch[1] === '✓' ? 'passed' : 'failed';
      const [moduleId, _moduleName] = detectModule(currentFile);
      results.push({
        name: testMatch[2],
        module: moduleId,
        status,
        duration: parseInt(testMatch[3]),
      });
    }
  }

  return results;
}

/** 生成模块级汇总报告 */
function generateModuleReport(results: TestResult[]): ModuleReport[] {
  const moduleGroups = new Map<string, TestResult[]>();

  for (const result of results) {
    if (!moduleGroups.has(result.module)) {
      moduleGroups.set(result.module, []);
    }
    moduleGroups.get(result.module)!.push(result);
  }

  const reports: ModuleReport[] = [];
  for (const [moduleId, tests] of moduleGroups) {
    const moduleName = MODULE_MAP.find(([, id]) => id === moduleId)?.[2] || moduleId;
    const passed = tests.filter((t) => t.status === 'passed').length;
    const failed = tests.filter((t) => t.status === 'failed').length;
    const skipped = tests.filter((t) => t.status === 'skipped').length;

    reports.push({
      moduleId,
      moduleName,
      total: tests.length,
      passed,
      failed,
      skipped,
      passRate: tests.length > 0 ? Math.round((passed / tests.length) * 100) : 0,
      tests,
    });
  }

  return reports.sort((a, b) => b.total - a.total);
}

/** 生成 JSON 报告文件 */
function generateJsonReport(reports: ModuleReport[], startTime: number): TestSummary {
  const allTests = reports.flatMap((r) => r.tests);
  const total = allTests.length;
  const passed = allTests.filter((t) => t.status === 'passed').length;
  const failed = allTests.filter((t) => t.status === 'failed').length;
  const skipped = allTests.filter((t) => t.status === 'skipped').length;
  const duration = ((Date.now() - startTime) / 1000).toFixed(1);

  const failedTests = allTests
    .filter((t) => t.status === 'failed')
    .map((t) => ({
      name: t.name,
      error: t.error || 'Unknown error',
      module: t.module,
    }));

  const modules: Record<string, any> = {};
  for (const report of reports) {
    modules[report.moduleId] = {
      moduleName: report.moduleName,
      total: report.total,
      passed: report.passed,
      failed: report.failed,
      skipped: report.skipped,
      passRate: report.passRate,
    };
  }

  return {
    timestamp: new Date().toISOString(),
    total,
    passed,
    failed,
    skipped,
    passRate: total > 0 ? Math.round((passed / total) * 100) : 0,
    duration: `${duration}s`,
    modules,
    failedTests,
  };
}

/** 生成 HTML 报告 */
function generateHtmlReport(summary: TestSummary): string {
  const { total, passed, failed, passRate, duration, modules } = summary;
  const statusColor = failed > 0 ? '#C0766E' : passRate >= 90 ? '#7A9E7E' : '#D4A56A';
  const statusIcon = failed > 0 ? '✗' : '✓';

  const moduleRows = Object.entries(modules)
    .map(
      ([id, m]) => `
      <tr>
        <td><strong>${id}</strong></td>
        <td>${m.moduleName}</td>
        <td>${m.total}</td>
        <td style="color:#7A9E7E">${m.passed}</td>
        <td style="color:${m.failed > 0 ? '#C0766E' : '#A89888'}">${m.failed}</td>
        <td>${m.skipped}</td>
        <td>
          <div class="progress-bar">
            <div class="progress-fill" style="width:${m.passRate}%; background:${m.passRate >= 90 ? '#7A9E7E' : '#D4A56A'}"></div>
          </div>
          <span style="font-size:0.8rem;color:#7A6B5D">${m.passRate}%</span>
        </td>
      </tr>
    `
    )
    .join('\n');

  const failedRows = summary.failedTests
    .map(
      (f) => `
      <tr>
        <td>${f.module}</td>
        <td>${f.name}</td>
        <td style="color:#C0766E;font-size:0.85rem">${f.error}</td>
      </tr>
    `
    )
    .join('\n');

  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>月笙写作教练 — 测试报告</title>
<style>
  body { font-family: 'Noto Sans SC', -apple-system, sans-serif; background: #F5F0E8; color: #3D3229; max-width: 960px; margin: 0 auto; padding: 24px; }
  h1 { font-size: 1.4rem; font-weight: 600; color: #C0766E; margin-bottom: 4px; }
  .meta { color: #A89888; font-size: 0.85rem; margin-bottom: 24px; }
  .summary { background: #fff; border-radius: 12px; padding: 20px; margin-bottom: 20px; box-shadow: 0 1px 3px rgba(61,50,41,0.06); }
  .summary-grid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 16px; text-align: center; }
  .summary-item .num { font-size: 2rem; font-weight: 700; color: ${statusColor}; }
  .summary-item .label { font-size: 0.75rem; color: #A89888; margin-top: 4px; }
  table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 3px rgba(61,50,41,0.06); }
  th { background: #F0EAE0; font-size: 0.75rem; font-weight: 600; color: #7A6B5D; padding: 10px 14px; text-align: left; }
  td { padding: 10px 14px; border-bottom: 1px solid #F0EAE0; font-size: 0.85rem; }
  .progress-bar { width: 100px; height: 6px; background: #F0EAE0; border-radius: 3px; display: inline-block; vertical-align: middle; margin-right: 8px; }
  .progress-fill { height: 100%; border-radius: 3px; transition: width 0.5s; }
  .section-title { font-size: 1rem; font-weight: 600; margin: 24px 0 12px; color: #3D3229; }
  .pass { color: #7A9E7E; font-weight: 600; }
  .fail { color: #C0766E; font-weight: 600; }
</style>
</head>
<body>
  <h1>${statusIcon} 月笙写作教练 — 测试报告</h1>
  <p class="meta">生成时间：${summary.timestamp} | 耗时：${duration} | 通过率：${passRate}%</p>

  <div class="summary">
    <div class="summary-grid">
      <div class="summary-item"><div class="num">${total}</div><div class="label">总用例</div></div>
      <div class="summary-item"><div class="num" style="color:#7A9E7E">${passed}</div><div class="label">通过</div></div>
      <div class="summary-item"><div class="num" style="color:#C0766E">${failed}</div><div class="label">失败</div></div>
      <div class="summary-item"><div class="num">${summary.modules ? Object.keys(summary.modules).length : 0}</div><div class="label">模块</div></div>
      <div class="summary-item"><div class="num">${passRate}%</div><div class="label">通过率</div></div>
    </div>
  </div>

  <div class="section-title">模块覆盖</div>
  <table>
    <tr><th>模块</th><th>名称</th><th>总数</th><th>通过</th><th>失败</th><th>跳过</th><th>覆盖率</th></tr>
    ${moduleRows}
  </table>

  ${summary.failedTests.length > 0 ? `
    <div class="section-title" style="color:#C0766E">失败测试详情 (${summary.failedTests.length})</div>
    <table>
      <tr><th>模块</th><th>名称</th><th>错误</th></tr>
      ${failedRows}
    </table>
  ` : ''}

  <p class="meta" style="text-align:center;margin-top:32px">月笙写作教练 · AI 教学测试报告 · ${summary.timestamp}</p>
</body>
</html>`;
}

/** 主入口：执行测试并生成报告 */
export async function runAndReport(): Promise<void> {
  const startTime = Date.now();
  const outputDir = path.resolve(__dirname, '../../docs/tests/reports');

  // 确保输出目录存在
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  console.log('🧪 运行测试...\n');

  try {
    // 运行 vitest 并捕获输出
    const output = execSync('npx vitest run --reporter=verbose 2>&1', {
      encoding: 'utf-8',
      cwd: path.resolve(__dirname, '../..'),
    });

    console.log(output);

    // 解析输出
    const results = parseVitestOutput(output);
    const moduleReports = generateModuleReport(results);
    const summary = generateJsonReport(moduleReports, startTime);

    // 写 JSON 报告
    const jsonPath = path.join(outputDir, `test-report-${Date.now()}.json`);
    fs.writeFileSync(jsonPath, JSON.stringify(summary, null, 2));
    console.log(`\n📄 JSON 报告: ${jsonPath}`);

    // 生成 HTML 报告
    const html = generateHtmlReport(summary);
    const htmlPath = path.join(outputDir, `test-report-${Date.now()}.html`);
    fs.writeFileSync(htmlPath, html);
    console.log(`📄 HTML 报告: ${htmlPath}`);

    // 打印汇总
    console.log(`\n📊 汇总: ${summary.total} 测试用例 | ${summary.passed} 通过 | ${summary.failed} 失败 | ${summary.passRate}% 通过率`);
    console.log(`⏱  耗时: ${summary.duration}`);

    // 输出模块级总结
    console.log('\n📦 模块覆盖:');
    for (const [id, m] of Object.entries(summary.modules)) {
      const icon = m.failed > 0 ? '❌' : m.passRate >= 90 ? '✅' : '⚠️';
      console.log(`  ${icon} ${id} (${m.moduleName}): ${m.passed}/${m.total} (${m.passRate}%)`);
    }

    if (summary.failed > 0) {
      console.log('\n❌ 失败的测试:');
      for (const f of summary.failedTests) {
        console.log(`  [${f.module}] ${f.name}: ${f.error}`);
      }
    }
  } catch (error: any) {
    // vitest 返回非零退出码时，输出仍在 stdout 中
    if (error.stdout) {
      console.log(error.stdout.toString());
    }
    console.error('\n❌ 测试执行失败:', error.message);
    process.exit(1);
  }
}

// 直接运行时执行
if (require.main === module) {
  runAndReport().catch(console.error);
}
