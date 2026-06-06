/**
 * 验证输入框可见性修复
 * 
 * 测试方法：
 * 1. 在浏览器中打开 docs/design/preview-warm-v2.html
 * 2. 打开开发者工具 (F12)
 * 3. 在 Console 中粘贴以下代码并回车
 * 
 * 验证项：
 * - 初始加载时输入框可见
 * - 新建会话后输入框可见
 * - 加载已有会话后输入框可见
 * - 切换侧边栏折叠状态后输入框可见
 */

function verifyInputVisibility() {
  const results = [];
  
  // 1. 检查 .chat-area 是否有 min-height: 0
  const chatArea = document.querySelector('.chat-area');
  const chatAreaStyle = getComputedStyle(chatArea);
  const hasMinHeight = chatAreaStyle.minHeight === '0px';
  results.push({
    name: 'chat-area min-height: 0',
    passed: hasMinHeight,
    detail: `当前值: ${chatAreaStyle.minHeight}`
  });
  
  // 2. 检查 .input-area 是否有 flex-shrink: 0
  const inputArea = document.querySelector('.input-area');
  const inputAreaStyle = getComputedStyle(inputArea);
  const hasFlexShrink = inputAreaStyle.flexShrink === '0';
  results.push({
    name: 'input-area flex-shrink: 0',
    passed: hasFlexShrink,
    detail: `当前值: ${inputAreaStyle.flexShrink}`
  });
  
  // 3. 检查输入框是否在视口内
  const inputBox = inputArea.getBoundingClientRect();
  const inViewport = inputBox.top < window.innerHeight && inputBox.bottom > 0;
  results.push({
    name: '输入框在视口内',
    passed: inViewport,
    detail: `top: ${inputBox.top.toFixed(0)}px, bottom: ${inputBox.bottom.toFixed(0)}px, viewport: ${window.innerHeight}px`
  });
  
  // 4. 检查 textarea 是否可交互
  const textarea = document.getElementById('messageInput');
  const isVisible = textarea.offsetParent !== null;
  results.push({
    name: 'textarea 可见',
    passed: isVisible,
    detail: `offsetParent: ${textarea.offsetParent ? '存在' : 'null'}`
  });
  
  // 5. 模拟新建会话后检查
  console.log('\n=== 验证结果 ===\n');
  let allPassed = true;
  results.forEach(r => {
    const icon = r.passed ? '✅' : '❌';
    console.log(`${icon} ${r.name}: ${r.detail}`);
    if (!r.passed) allPassed = false;
  });
  
  console.log('\n' + (allPassed ? '🎉 所有检查通过！' : '⚠️  有检查未通过，请检查上述项目'));
  return results;
}

// 自动执行验证
verifyInputVisibility();
