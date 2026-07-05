/**
 * commitlint 配置 — 遵循 R-016 Git提交规范
 *
 * 格式: <type>(<scope>): <subject>
 *
 * type: feat | fix | docs | style | refactor | perf | test | chore
 * scope: 可选，如 api | ui | db | auth 等
 * subject: 祈使句，首字母小写，≤50字符，无句号
 */
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // 允许的 type 列表 (R-016)
    'type-enum': [2, 'always', [
      'feat',     // 新功能
      'fix',      // Bug修复
      'docs',     // 文档更新
      'style',    // 代码格式调整
      'refactor', // 代码重构
      'perf',     // 性能优化
      'test',     // 测试相关
      'chore',    // 构建/辅助工具变动
    ]],
    // subject 长度 ≤50
    'header-max-length': [2, 'always', 50],
    // scope 小写
    'scope-case': [2, 'always', 'lower-case'],
    // subject 不以句号结尾
    'subject-full-stop': [2, 'never', '.'],
    // body 每行 ≤72 字符
    'body-max-line-length': [2, 'always', 72],
  },
};
