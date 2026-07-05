// 停止现有模拟器并重试
const { execSync, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const userProfile = process.env.USERPROFILE;
const ANDROID_HOME = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk');
const emulator = path.join(ANDROID_HOME, 'emulator', 'emulator.exe');
const adb = path.join(ANDROID_HOME, 'platform-tools', 'adb.exe');

// 1. 杀掉残留
console.log('=== 1. 杀掉残留进程 ===');
try {
  execSync('taskkill /F /IM emulator.exe /T 2>&1', { stdio: 'inherit' });
} catch (e) {}
try {
  execSync('taskkill /F /IM qemu-system-x86_64.exe /T 2>&1', { stdio: 'inherit' });
} catch (e) {}
try {
  execSync('taskkill /F /IM qemu-system-x86_64-headless.exe /T 2>&1', { stdio: 'inherit' });
} catch (e) {}

// 2. 修复 avd 目录权限
console.log('\n=== 2. 检查/修复 AVD 目录 ===');
const avdBase = path.join(userProfile, '.android', 'avd');
if (fs.existsSync(avdBase)) {
  console.log('AVD 基础目录:', avdBase);
  // 列出 avd
  const entries = fs.readdirSync(avdBase, { withFileTypes: true });
  for (const e of entries) {
    const full = path.join(avdBase, e.name);
    if (e.isDirectory()) {
      console.log('  Dir:', e.name, '|', full);
    } else {
      console.log('  File:', e.name);
    }
  }
}

// 创建 qemu-version.txt (避免 emulator 内部错误)
const pixelAvd = path.join(avdBase, 'Pixel6.avd');
if (fs.existsSync(pixelAvd)) {
  try {
    fs.writeFileSync(path.join(pixelAvd, 'qemu-version.txt'), '2\n', 'utf8');
    console.log('已创建 qemu-version.txt');
  } catch (e) {
    console.log('创建失败:', e.message);
  }
}

// 3. adb kill-server / start-server
console.log('\n=== 3. 重启 adb server ===');
try { execSync(`"${adb}" kill-server`, { stdio: 'inherit' }); } catch (e) {}
try { execSync(`"${adb}" start-server`, { stdio: 'inherit' }); } catch (e) {}
try { execSync(`"${adb}" devices`, { stdio: 'inherit' }); } catch (e) {}

console.log('\n[OK] 清理完成,准备重启');
