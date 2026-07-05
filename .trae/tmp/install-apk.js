// 安装并启动 APK
const { execSync, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const userProfile = process.env.USERPROFILE;
const adb = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe');
const apk = 'd:\\ai-teacher\\yuesheng-writing-coach\\android\\app\\build\\outputs\\apk\\debug\\app-debug.apk';

if (!fs.existsSync(apk)) {
  console.error('APK 不存在:', apk);
  process.exit(1);
}

console.log('APK:', apk);
console.log('大小:', (fs.statSync(apk).size / 1024 / 1024).toFixed(2), 'MB');

function run(cmd, opts = {}) {
  console.log(`\n$ ${cmd}`);
  try {
    const out = execSync(cmd, { encoding: 'utf8', stdio: 'inherit', ...opts });
    return out;
  } catch (e) {
    console.error('失败:', e.message);
    return null;
  }
}

console.log('\n=== 1. 验证设备 ===');
run(`"${adb}" devices`);

console.log('\n=== 2. 安装 APK ===');
// -r 替换, -t 允许测试包, -g 自动授权
run(`"${adb}" -s emulator-5554 install -r -t -g "${apk}"`);

console.log('\n=== 3. 启动 App ===');
// App ID: com.yuesheng.writingcoach
// MainActivity 由 Capacitor 模板自动生成
run(`"${adb}" -s emulator-5554 shell am start -n com.yuesheng.writingcoach/com.yuesheng.writingcoach.MainActivity`);

console.log('\n=== 4. 验证 App 运行 ===');
run(`"${adb}" -s emulator-5554 shell "pidof com.yuesheng.writingcoach"`);

console.log('\n=== 5. 截图 logs ===');
run(`"${adb}" -s emulator-5554 logcat -d -t 100 | grep -i "yuesheng\\|capacitor\\|chromium\\|webview"`);
